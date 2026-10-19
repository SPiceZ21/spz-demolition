-- server/base.lua — shared arena-minigame core (identical in spz-demolition and spz-bomb)
-- Rooms → private bucket per room → server-created cars on a ring around the
-- arena → 3-2-1 → Game.run(round) plays the game → endRound pays out and sends
-- everyone home. Several rooms can play at once: each round lives in its own
-- routing bucket, so the same arena hosts them all without them seeing each
-- other. The server reads real entity coords for every rule that eliminates
-- anyone; the client only reports what it can't be faked into (its own car
-- being wrecked).
--
-- The game file (server/game.lua) fills in the global `Game` table:
--   Game.run(r)            required. Plays the round; return when it's over.
--                          Loop while r.active — it goes false when the round ends.
--   Game.hud(r, src)       optional. Extra fields merged into the HUD state.
--   Game.onEliminated(r, src, p)  optional.
--   Game.onLeave(r, src, p)       optional (left / dropped mid-round).

Game = Game or {}
Base = {}

local Log = SPZ and SPZ.Logger and SPZ.Logger(GetCurrentResourceName()) or nil
local function log(m) if Log then Log.info(m) else print(("[%s] %s"):format(Config.Key, m)) end end
Base.log = log

local function E(name) return Config.Key .. ":" .. name end
Base.E = E

local Rooms = {}         -- [id] = { id, name, host, private, max, members = { [src] = { pid, name } }, armed, armedAt, round }
local RoomOf = {}        -- [src] = room
local Invites = {}       -- [src] = { [roomId] = true, last = roomId }
local nextRoomId = 1

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function notify(src, msg, t) TriggerClientEvent(E("notify"), src, msg, t or "info") end
Base.notify = notify

local function pidOf(src)
    local ok, p = pcall(function() return exports["spz-identity"]:GetProfile(src) end)
    return ok and p and p.id or nil, ok and p or nil
end

local function nameOf(src)
    local _, prof = pidOf(src)
    return (prof and prof.username) or GetPlayerName(src) or ("Player" .. src)
end

local function srcFromPid(pid)
    for _, s in ipairs(GetPlayers()) do
        if pidOf(tonumber(s)) == pid then return tonumber(s) end
    end
end

local function payPid(pid, amt, reason)
    if not pid or amt <= 0 then return end
    local s = srcFromPid(pid)
    if s and GetResourceState("spz-progression") == "started" then
        exports["spz-progression"]:GrantBonus(s, { credits = amt, reason = reason })
    else
        MySQL.update.await("UPDATE players SET credits = credits + ? WHERE id = ?", { amt, pid })
    end
end

local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

function Base.shuffle(t)
    for i = #t, 2, -1 do local j = math.random(i); t[i], t[j] = t[j], t[i] end
    return t
end

--- The live round a player is in, if any.
function Base.roundOf(src)
    local room = RoomOf[src]
    local r = room and room.round
    return (r and r.players[src]) and r or nil
end

function Base.toAll(r, event, payload)
    if not r then return end
    for src in pairs(r.players) do TriggerClientEvent(E(event), src, payload) end
end

function Base.aliveList(r)
    local out = {}
    if not r then return out end
    for src, p in pairs(r.players) do if p.alive then out[#out + 1] = src end end
    return out
end

-- The entity that counts for a player: their car when they're in one.
function Base.entityOf(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return 0 end
    local veh = GetVehiclePedIsIn(ped, false) or 0
    if veh ~= 0 and DoesEntityExist(veh) then return veh end
    return ped
end

-- spz-core ghosts every player unless BOTH carry `spz:contact`; round players
-- get it so their cars actually hit each other.
local function setContact(src, on)
    if GetPlayerName(src) then Player(src).state:set("spz:contact", on or nil, true) end
end

-- Cars are created HERE: spz-core buckets run strict entity lockdown and delete
-- networked entities a client creates.
local function spawnCarFor(bucketId, x, y, z, heading)
    local pool = Config.Cars or { "blista" }
    local model = pool[math.random(#pool)]
    local veh = CreateVehicleServerSetter(joaat(model), "automobile", x, y, z, heading or 0.0)
    local dl = GetGameTimer() + 3000
    while veh ~= 0 and not DoesEntityExist(veh) and GetGameTimer() < dl do Wait(0) end
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    if bucketId ~= 0 then SetEntityRoutingBucket(veh, bucketId) end
    SetEntityOrphanMode(veh, 2)
    return veh
end

local function deleteCar(p)
    if p and p.veh and DoesEntityExist(p.veh) then DeleteEntity(p.veh) end
    if p then p.veh = nil end
end
Base.deleteCar = deleteCar

-- ── Round end / elimination ─────────────────────────────────────────────────

function Base.endRound(r, reason)
    if not r or not r.active then return end
    r.active = false
    if r.room.round == r then r.room.round = nil end
    for src, p in pairs(r.players) do deleteCar(p); setContact(src, false) end

    local survivors = {}
    for _, p in pairs(r.players) do if p.alive then survivors[#survivors + 1] = p end end

    local winReward = Config.WinReward or 0
    for src, p in pairs(r.players) do
        local prize = 0
        if p.alive then prize = (#survivors > 1) and math.floor(winReward / #survivors) or winReward end
        local total = prize + (p.bonus or 0)
        if total > 0 then payPid(p.pid, total, Config.Title) end
        TriggerClientEvent(E("over"), src, {
            won = p.alive, reason = reason, payout = total, survivors = #survivors,
            winner = (#survivors == 1) and survivors[1].name or nil,
        })
    end

    SetTimeout(1500, function()
        if r.bucketId and r.bucketId ~= 0 and GetResourceState("spz-core") == "started" then
            exports["spz-core"]:DeleteBucket(r.bucketId)
        end
    end)

    pcall(function()
        local who = (#survivors == 1) and survivors[1].name or (#survivors .. " survivors")
        exports["spz-log"]:Log("minigame", Config.Title, ("%s — %s (%s)"):format(who, reason, r.room.name), "success")
    end)
    log(("room %d round over: %s (%d survivor(s))"):format(r.room.id, reason, #survivors))
    SetTimeout(4000, function()
        if Rooms[r.room.id] ~= r.room then return end
        -- Match over: the room closes and everyone is out of the lobby.
        Rooms[r.room.id] = nil
        for s in pairs(r.room.members) do
            RoomOf[s] = nil
            if GetPlayerName(s) then Player(s).state:set("mgRoom", nil, true) end
            notify(s, "Match over — you left the room. Open the hub to play again.")
        end
    end)
end

function Base.eliminate(src, why)
    local r = Base.roundOf(src)
    local p = r and r.players[src]
    if not p or not p.alive then return end
    p.alive = false
    p.outAt = GetGameTimer()
    TriggerClientEvent(E("eliminated"), src, { why = why })
    Base.toAll(r, "feed", { name = p.name, why = why })
    if Game.onEliminated then pcall(Game.onEliminated, r, src, p) end
    -- A moment to see the wreck / blast, then off to the spectator view.
    SetTimeout(math.floor((Config.SpectateDelaySec or 2.0) * 1000), function()
        if not r.active then return end
        deleteCar(p)
        TriggerClientEvent(E("spectate"), src)
    end)
end

-- Everyone still in the match back onto the start ring in a fresh car, then
-- 3-2-1-GO. For games played over several rounds (Game.run calls it).
function Base.respawnAll(r)
    r.live = false
    local present = {}
    for src, p in pairs(r.players) do
        deleteCar(p)
        if GetPlayerName(src) then
            p.alive, p.outSince, p.walkSince, p.outAt = true, nil, nil, nil
            present[#present + 1] = src
        end
    end
    Base.shuffle(present)
    for i, src in ipairs(present) do
        local p = r.players[src]
        local a = (i - 1) / #present * math.pi * 2.0
        local x = Config.Center.x + math.cos(a) * Config.SpawnRadius
        local y = Config.Center.y + math.sin(a) * Config.SpawnRadius
        p.heading = (math.deg(math.atan(Config.Center.y - y, Config.Center.x - x)) - 90.0) % 360.0
        p.spawn = vector3(x, y, Config.Center.z)
        TriggerClientEvent(E("respawn"), src, { spawn = p.spawn, heading = p.heading })
    end
    Wait(4000)
    for n = 3, 1, -1 do
        if not r.active then return end
        Base.toAll(r, "countdown", n)
        Wait(1000)
    end
    if not r.active then return end
    r.live = true
    Base.toAll(r, "go", {})
end

local function eachRound(fn)
    for _, room in pairs(Rooms) do
        if room.round and room.round.active then fn(room.round) end
    end
end

-- ── Arena rules every game shares ───────────────────────────────────────────
-- Out of the arena (with a grace timer and warning), fallen under it, or out of
-- the car for too long = eliminated. Only while r.live is true.
CreateThread(function()
    while true do
        Wait(250)
        local now = GetGameTimer()
        eachRound(function(r)
            if not r.live then return end
            for src, p in pairs(r.players) do
                if p.alive then
                    local ped = GetPlayerPed(src)
                    if ped == 0 then goto continue end
                    local ent = Base.entityOf(src)
                    local c = GetEntityCoords(ent)
                    local dx, dy = c.x - Config.Center.x, c.y - Config.Center.y
                    local out = (dx * dx + dy * dy) > (Config.ArenaRadius * Config.ArenaRadius)

                    if c.z < Config.Center.z - (Config.FallDepth or 15.0) then
                        Base.eliminate(src, "fell out of the arena")
                    elseif out then
                        p.outSince = p.outSince or now
                        if now - p.outSince > (Config.OutGraceSec or 5) * 1000 then
                            Base.eliminate(src, "left the arena")
                        end
                    else
                        p.outSince = nil
                    end

                    if p.alive and p.veh then
                        if GetVehiclePedIsIn(ped, false) ~= p.veh then
                            p.walkSince = p.walkSince or now
                            if now - p.walkSince > (Config.OutOfCarSec or 6) * 1000 then
                                Base.eliminate(src, "abandoned their car")
                            end
                        else
                            p.walkSince = nil
                        end
                    end
                end
                ::continue::
            end
        end)
    end
end)

-- HUD state, 4x a second.
CreateThread(function()
    while true do
        Wait(250)
        local now = GetGameTimer()
        eachRound(function(r)
            local alive = #Base.aliveList(r)
            local total = count(r.players)

            -- Scoreboard, built once per round per tick. Game.boardRow fills the
            -- game-specific columns (value / icon / sort score).
            local rows = {}
            for src, p in pairs(r.players) do
                local row = { src = src, name = p.name, out = not p.alive, score = 0 }
                if Game.boardRow then pcall(Game.boardRow, r, src, p, row) end
                rows[#rows + 1] = row
            end
            table.sort(rows, function(a, b)
                if a.out ~= b.out then return not a.out end
                if a.score ~= b.score then return a.score > b.score end
                return a.name < b.name
            end)
            for _, row in ipairs(rows) do row.score = nil end
            local board = { title = Game.boardTitle or "Players", rows = rows }

            for src, p in pairs(r.players) do
                local s = {
                    phase = r.phase, wave = r.wave, alive = alive, total = total, me = p.alive,
                    remain = r.endsAt and math.max(0, (r.endsAt - now) / 1000) or nil,
                    outRemain = p.outSince and math.max(0, (Config.OutGraceSec or 5) - (now - p.outSince) / 1000) or nil,
                    board = board,
                }
                if Game.hud then
                    local ok, extra = pcall(Game.hud, r, src, p)
                    if ok and type(extra) == "table" then for k, v in pairs(extra) do s[k] = v end end
                end
                TriggerClientEvent(E("state"), src, s)
            end
        end)
    end
end)

-- ── Rooms ───────────────────────────────────────────────────────────────────

local function roomMax(room) return room.max or Config.MaxPlayers end

local function disarm(room) room.armed, room.armedAt = false, nil end

local function startRound(room)
    disarm(room)
    if room.round then return end
    if count(room.members) < Config.MinPlayers then
        for s in pairs(room.members) do notify(s, "Not enough players to start.", "warning") end
        return
    end

    local roster = {}
    for src, e in pairs(room.members) do roster[#roster + 1] = { src = src, pid = e.pid, name = e.name } end
    Base.shuffle(roster)

    local bucketId = 0
    if GetResourceState("spz-core") == "started" then
        bucketId = exports["spz-core"]:CreateBucket(("%s:%d"):format(Config.Key, room.id))
        SetRoutingBucketPopulationEnabled(bucketId, false)
    end

    local r = { room = room, active = true, bucketId = bucketId, players = {}, phase = "intro", wave = 0, live = false }
    room.round = r

    -- Spawn on a ring around the centre, every car facing in.
    for i, m in ipairs(roster) do
        local a = (i - 1) / #roster * math.pi * 2.0
        local x = Config.Center.x + math.cos(a) * Config.SpawnRadius
        local y = Config.Center.y + math.sin(a) * Config.SpawnRadius
        local heading = (math.deg(math.atan(Config.Center.y - y, Config.Center.x - x)) - 90.0) % 360.0
        r.players[m.src] = { pid = m.pid, name = m.name, alive = true, bonus = 0,
                             spawn = vector3(x, y, Config.Center.z), heading = heading }
        pcall(function()
            if GetResourceState("spz-vehicles") == "started" then exports["spz-vehicles"]:DespawnVehicle(m.src) end
        end)
        if bucketId ~= 0 then exports["spz-core"]:AssignPlayerToBucket(m.src, bucketId) end
        setContact(m.src, true)
        TriggerClientEvent(E("start"), m.src, { spawn = r.players[m.src].spawn, heading = heading })
    end
    log(("room %d round start: %d players"):format(room.id, #roster))

    CreateThread(function()
        Wait(4000)                         -- fade in, load the arena, get the cars
        for n = 3, 1, -1 do
            if not r.active then return end
            Base.toAll(r, "countdown", n)
            Wait(1000)
        end
        if not r.active then return end
        r.live = true
        Base.toAll(r, "go", {})
        local ok, err = pcall(Game.run, r)
        if not ok then log("Game.run failed: " .. tostring(err)) end
        if r.active then
            local alive = Base.aliveList(r)
            Base.endRound(r, #alive == 1 and "last one standing" or "round over")
        end
    end)
end

local function arm(room)
    if room.armed or room.round then return end
    room.armed, room.armedAt = true, GetGameTimer()
    local token = room.armedAt
    SetTimeout((Config.LobbyWaitSec or 45) * 1000, function()
        if Rooms[room.id] == room and room.armed and room.armedAt == token and not room.round then
            CreateThread(function() startRound(room) end)
        end
    end)
end

-- Busy elsewhere → hidden from invite lists. Queued racers still show: joining
-- a room takes them out of the race queue (see leaveRaceQueue).
local function invitable(sid)
    local st = Player(sid).state
    if st.mgRoom or st.inMinigame or st.inRace or st.inTimeTrial or st.inPursuit then return false end
    return true
end

-- Joining a minigame room drops your E-join race queue spot instead of refusing.
local function leaveRaceQueue(src)
    local st = Player(src).state
    if not (st.inQueue or st.pendingRace) or st.inRace then return end
    if GetResourceState("spz-races") ~= "started" then return end
    pcall(function() exports["spz-races"]:LeaveQueue(src) end)
end

local function busy(src)
    if RoomOf[src] then return "already in a room" end
    local st = Player(src).state
    -- One minigame room at a time, across every game.
    if st.mgRoom and st.mgRoom ~= GetCurrentResourceName() then return "already in another minigame room — leave it first" end
    if st.inRace then return "in a race" end
    if st.inTimeTrial then return "in a time trial" end
    return nil
end

local function closeRoom(room, why)
    Rooms[room.id] = nil
    for s in pairs(room.members) do
        RoomOf[s] = nil
        if GetPlayerName(s) then Player(s).state:set("mgRoom", nil, true) end
        if why then notify(s, ("Room closed — %s"):format(why), "warning") end
    end
end

local function addMember(room, src)
    local pid, prof = pidOf(src)
    if not pid then return false, "Profile not ready." end
    room.members[src] = { pid = pid, name = (prof and prof.username) or GetPlayerName(src) }
    RoomOf[src] = room
    if Invites[src] then Invites[src][room.id] = nil end
    local n = count(room.members)
    for s in pairs(room.members) do
        if s ~= src then notify(s, ("%s joined %s (%d/%d)"):format(room.members[src].name, room.name, n, roomMax(room)), "success") end
    end
    Player(src).state:set("mgRoom", GetCurrentResourceName(), true)
    leaveRaceQueue(src)
    -- No auto-start: only the room host starts the match.
    return true
end

local function removeMember(src, why)
    local room = RoomOf[src]
    if not room then return end
    local e = room.members[src]
    room.members[src] = nil
    RoomOf[src] = nil
    if GetPlayerName(src) then Player(src).state:set("mgRoom", nil, true) end
    if not next(room.members) then closeRoom(room); return end
    if room.host == src then
        room.host = next(room.members)
        notify(room.host, "You are now the room host.", "info")
    end
    if count(room.members) < Config.MinPlayers then disarm(room) end
    for s in pairs(room.members) do
        notify(s, ("%s left the room%s."):format(e and e.name or "Someone", why and (" (" .. why .. ")") or ""), "warning")
    end
end

local function createRoom(src, opts)
    local b = busy(src)
    if b then return false, "You are " .. b .. "." end
    local maxRooms = Config.MaxRooms or 8
    if count(Rooms) >= maxRooms then return false, ("All %d rooms are in use."):format(maxRooms) end
    opts = type(opts) == "table" and opts or {}

    local name = tostring(opts.name or ""):gsub("[^%w%s%-_'!%.]", ""):sub(1, 24)
    if name:match("^%s*$") then name = nameOf(src) .. "'s room" end
    local max = math.floor(tonumber(opts.max) or Config.MaxPlayers)
    max = math.max(Config.MinPlayers, math.min(Config.MaxPlayers, max))

    local room = { id = nextRoomId, name = name, host = src, private = opts.private == true, max = max, members = {} }
    nextRoomId = nextRoomId + 1
    Rooms[room.id] = room
    local ok, err = addMember(room, src)
    if not ok then Rooms[room.id] = nil; return false, err end
    log(("room %d created by %s (%s, max %d%s)"):format(room.id, nameOf(src), name, max, room.private and ", private" or ""))
    return true, ("Created %s."):format(name)
end

local function joinRoom(src, id)
    local room = Rooms[tonumber(id) or -1]
    if not room then return false, "That room is gone." end
    if RoomOf[src] == room then return true end
    local b = busy(src)
    if b then return false, "You are " .. b .. "." end
    if room.round then return false, "That room is mid-round — wait for it to finish." end
    if room.private and not (Invites[src] and Invites[src][room.id]) then return false, "That room is invite-only." end
    if count(room.members) >= roomMax(room) then return false, "That room is full." end
    local ok, err = addMember(room, src)
    if not ok then return false, err end
    return true, ("Joined %s."):format(room.name)
end

-- Public matchmaking: the fullest open public room, else a new one.
local function quickJoin(src)
    local best
    for _, room in pairs(Rooms) do
        if not room.private and not room.round and count(room.members) < roomMax(room)
            and (not best or count(room.members) > count(best.members)) then
            best = room
        end
    end
    if best then return joinRoom(src, best.id) end
    return createRoom(src, {})
end

local function roomView(room, viewer)
    local roster = {}
    for s, e in pairs(room.members) do
        roster[#roster + 1] = { src = s, name = e.name, isMe = (s == viewer), host = (s == room.host) }
    end
    table.sort(roster, function(a, b)
        if a.host ~= b.host then return a.host end
        return a.name < b.name
    end)
    return {
        id = room.id, name = room.name, private = room.private, host = nameOf(room.host),
        count = #roster, max = roomMax(room), live = room.round ~= nil,
        wave = room.round and room.round.wave or nil,
        armed = room.armed,
        armedRemain = room.armed and math.max(0, (Config.LobbyWaitSec or 45) - math.floor((GetGameTimer() - room.armedAt) / 1000)) or nil,
        roster = roster,
    }
end

-- Shape kept compatible with the old single-lobby menu (inLobby/count/roster…),
-- plus the room list for the hub.
local function lobbyStateFor(src)
    local room = RoomOf[src]
    local rooms = {}
    for _, rm in pairs(Rooms) do
        local invited = Invites[src] and Invites[src][rm.id] or false
        if not rm.private or invited or rm == room then
            local v = roomView(rm, src)
            v.roster, v.invited, v.mine = nil, invited and true or false, rm == room
            rooms[#rooms + 1] = v
        end
    end
    table.sort(rooms, function(a, b)
        if a.mine ~= b.mine then return a.mine end
        if a.invited ~= b.invited then return a.invited end
        if a.live ~= b.live then return not a.live end
        return a.count > b.count
    end)

    local v = room and roomView(room, src)
    return {
        rooms = rooms, maxRooms = Config.MaxRooms or 8,
        room = v, isHost = room ~= nil and room.host == src,
        inRound = Base.roundOf(src) ~= nil,
        roundLive = v and v.live or false,
        inLobby = room ~= nil,
        count = v and v.count or 0, min = Config.MinPlayers, max = v and v.max or Config.MaxPlayers,
        armed = v and v.armed or false, armedRemain = v and v.armedRemain or nil,
        roster = v and v.roster or {}, wave = v and v.wave or nil,
    }
end

local function reply(src, ok, msg)
    if msg then notify(src, msg, ok and "success" or "error") end
    return lobbyStateFor(src)
end

local function toggleJoin(src)
    local room = RoomOf[src]
    if room then
        if Base.roundOf(src) then notify(src, "You are in a round.", "error"); return end
        removeMember(src, "left")
        notify(src, "Left the room.")
        return
    end
    local ok, msg = quickJoin(src)
    if msg then notify(src, msg, ok and "success" or "error") end
end

local function startNow(src)
    local room = RoomOf[src]
    if not room then return false, "Join a room first with /" .. Config.Command end
    if room.host ~= src then return false, "Only the room host can start." end
    if room.round then return false, "A round is already running." end
    if count(room.members) < Config.MinPlayers then return false, ("Need %d players."):format(Config.MinPlayers) end
    CreateThread(function() startRound(room) end)
    return true
end

RegisterCommand(Config.Command, function(src) if src > 0 then toggleJoin(src) end end, false)
RegisterCommand(Config.StartCommand, function(src)
    if src <= 0 then return end
    local ok, msg = startNow(src)
    if not ok then notify(src, msg, "error") end
end, false)

lib.callback.register(E("lobbyState"), function(src) return lobbyStateFor(src) end)
lib.callback.register(E("joinToggle"), function(src) toggleJoin(src); return lobbyStateFor(src) end)
lib.callback.register(E("createRoom"), function(src, opts) return reply(src, createRoom(src, opts)) end)
lib.callback.register(E("joinRoom"), function(src, id) return reply(src, joinRoom(src, id)) end)
lib.callback.register(E("leaveRoom"), function(src)
    if Base.roundOf(src) then return reply(src, false, "You are in a round.") end
    if not RoomOf[src] then return reply(src, false) end
    removeMember(src, "left")
    return reply(src, true, "Left the room.")
end)
lib.callback.register(E("startRoom"), function(src) return reply(src, startNow(src)) end)
lib.callback.register(E("kick"), function(src, target)
    local room = RoomOf[src]
    target = tonumber(target)
    if not room or room.host ~= src then return reply(src, false, "Only the host can do that.") end
    if room.round then return reply(src, false, "Not during a round.") end
    if not target or target == src or RoomOf[target] ~= room then return reply(src, false) end
    removeMember(target, "removed by host")
    notify(target, ("You were removed from %s."):format(room.name), "warning")
    return reply(src, true)
end)
lib.callback.register(E("online"), function(src)
    local list = {}
    for _, id in ipairs(GetPlayers()) do
        local sid = tonumber(id)
        if sid ~= src and not RoomOf[sid] and invitable(sid) then
            list[#list + 1] = { source = sid, name = nameOf(sid) }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end)

RegisterNetEvent(E("invite"), function(target)
    local src = source
    local room = RoomOf[src]
    target = tonumber(target)
    if not room then notify(src, "Join a room before inviting.", "error"); return end
    if not target or not GetPlayerName(target) then notify(src, "That player is not online.", "error"); return end
    if RoomOf[target] then notify(src, "They are already in a room.", "info"); return end
    Invites[target] = Invites[target] or {}
    Invites[target][room.id] = true
    Invites[target].last = room.id
    TriggerClientEvent(E("invited"), target, { fromName = room.members[src].name, room = room.id, roomName = room.name })
    notify(src, ("Invite sent to %s."):format(nameOf(target)), "success")
end)

RegisterNetEvent(E("acceptInvite"), function(roomId)
    local src = source
    if RoomOf[src] then return end
    local id = tonumber(roomId) or (Invites[src] and Invites[src].last)
    if not id then return end
    local ok, msg = joinRoom(src, id)
    if msg then notify(src, msg, ok and "success" or "error") end
end)

-- Client has loaded the arena around its spawn and found the ground: create
-- its car there (it gets ownership straight away and can drive it).
RegisterNetEvent(E("ready"), function(groundZ)
    local src = source
    local r = Base.roundOf(src)
    local p = r and r.players[src]
    if not p or p.veh or not p.spawn then return end
    local z = (type(groundZ) == "number" and math.abs(groundZ - Config.Center.z) < 30.0) and groundZ or p.spawn.z
    local veh = spawnCarFor(r.bucketId or 0, p.spawn.x, p.spawn.y, z + 0.6, p.heading)
    if not r.active then if veh then DeleteEntity(veh) end return end
    p.veh = veh
    TriggerClientEvent(E("car"), src, { netId = veh and NetworkGetNetworkIdFromEntity(veh) or nil })
end)

local function dropOut(src, sendHome)
    local r = Base.roundOf(src)
    local p = r and r.players[src]
    if not p then return end
    if Game.onLeave then pcall(Game.onLeave, r, src, p) end
    deleteCar(p)
    setContact(src, false)
    r.players[src] = nil
    if sendHome then
        TriggerClientEvent(E("over"), src, { won = false, payout = 0, reason = "left" })
        SetTimeout(600, function()
            if GetPlayerName(src) and GetResourceState("spz-core") == "started" then
                exports["spz-core"]:RemovePlayerFromBucket(src)
            end
        end)
    end
    Base.toAll(r, "feed", { name = p.name, why = "left" })
end

RegisterNetEvent(E("leave"), function()
    local src = source
    dropOut(src, true)
    removeMember(src, "left")
end)

AddEventHandler("playerDropped", function()
    local src = source
    dropOut(src, false)
    removeMember(src, "disconnected")
    Invites[src] = nil
end)

AddEventHandler("onResourceStop", function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, room in pairs(Rooms) do
        if room.round then Base.endRound(room.round, "resource stopped") end
    end
end)

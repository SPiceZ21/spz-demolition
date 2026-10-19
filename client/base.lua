-- client/base.lua — shared arena-minigame core (identical in spz-demolition and spz-bomb)
-- Fade in at the spawn ring, load the arena, report the ground, take the car the
-- server makes, draw the HUD, spectate when out, go home when it ends.
--
-- The game file (client/game.lua) can fill in the global `Game` table:
--   Game.onCar(veh)          car is ours — set damage / looks
--   Game.onStart(d) / Game.onGo() / Game.onOver(r) / Game.onEliminated(d)
--   Game.hud(state, hud)     add to the shared HUD table (spz-minigames Hud export), ~10x/s

Game = Game or {}
Base = { active = false, alive = false, veh = 0, state = {} }

-- After a match everyone spawns at the hub's shared return point (DK garage).
local function returnPoint(ped)
    if GetResourceState("spz-minigames") == "started" then
        local ok, p = pcall(function() return exports["spz-minigames"]:ReturnPoint() end)
        if ok and p then return vector3(p.x, p.y, p.z), p.w end
    end
    return GetEntityCoords(ped), GetEntityHeading(ped)
end

local function E(name) return Config.Key .. ":" .. name end
Base.E = E

local myBackH
local myBack, spectating = nil, false
local camSpec = nil

RegisterNetEvent(E("notify"), function(msg, t) lib.notify({ description = msg, type = t or "info" }) end)

-- All on-screen text goes through the shared spz-minigames HUD.
local HUD = exports["spz-minigames"]
Base.HUD = HUD

local function playClip(name)
    if GetResourceState("spz-raceUI") == "started" then
        if pcall(function() exports["spz-raceUI"]:PlaySound(name, 1.0) end) then return end
    end
    PlaySoundFrontend(-1, name == "go" and "GO" or "3_2_1", "HUD_MINI_GAME_SOUNDSET", true)
end
Base.playClip = playClip

local function flash(txt, color, ms)
    HUD:Flash(txt, color, ms)
end
Base.flash = flash

local function despawnFreeroamCar()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then return end
    local dl = GetGameTimer() + 1000
    while not NetworkHasControlOfEntity(veh) and GetGameTimer() < dl do NetworkRequestControlOfEntity(veh); Wait(0) end
    SetEntityAsMissionEntity(veh, true, true)
    DeleteVehicle(veh)
    if DoesEntityExist(veh) then DeleteEntity(veh) end
end

local function groundAt(x, y, zGuess)
    RequestCollisionAtCoord(x, y, zGuess)
    local dl = GetGameTimer() + 4000
    while GetGameTimer() < dl do
        local ok, z = GetGroundZFor_3dCoord(x, y, zGuess + 25.0, false)
        if ok and z > 0.0 then return z end
        RequestCollisionAtCoord(x, y, zGuess)
        Wait(50)
    end
    return nil
end

local function claimCar(netId)
    if not netId then return 0 end
    local dl = GetGameTimer() + 8000
    while not NetworkDoesEntityExistWithNetworkId(netId) and GetGameTimer() < dl do Wait(50) end
    if not NetworkDoesEntityExistWithNetworkId(netId) then
        lib.notify({ title = Config.Title, description = "Your car failed to arrive", type = "error" })
        return 0
    end
    local veh = NetToVeh(netId)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    TaskWarpPedIntoVehicle(ped, veh, -1)
    dl = GetGameTimer() + 3000
    while GetPedInVehicleSeat(veh, -1) ~= ped and GetGameTimer() < dl do Wait(20) end
    dl = GetGameTimer() + 3000
    while not NetworkHasControlOfEntity(veh) and GetGameTimer() < dl do NetworkRequestControlOfEntity(veh); Wait(20) end
    SetVehicleOnGroundProperly(veh)
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleNumberPlateText(veh, (Config.PlatePrefix or "SPZ") .. ("%03d"):format(math.random(0, 999)))
    -- Held until GO.
    FreezeEntityPosition(veh, true)
    SetVehicleEngineOn(veh, true, true, false)
    if Game.onCar then pcall(Game.onCar, veh) end
    return veh
end

local function deleteCar()
    if Base.veh ~= 0 and DoesEntityExist(Base.veh) then
        SetEntityAsMissionEntity(Base.veh, true, true)
        DeleteEntity(Base.veh)
    end
    Base.veh = 0
end

-- Spectator view: a slow orbit high over the arena centre.
local function enterSpectate()
    if spectating then return end
    spectating = true
    deleteCar()
    local ped = PlayerPedId()
    SetEntityInvincible(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityCoords(ped, Config.Center.x, Config.Center.y, Config.Center.z + 40.0, false, false, false, false)

    camSpec = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamFov(camSpec, 60.0)
    RenderScriptCams(true, true, 800, true, false)
    CreateThread(function()
        local t0 = GetGameTimer()
        while spectating and camSpec do
            local a = (GetGameTimer() - t0) / 1000.0 * 0.12
            local R = Config.ArenaRadius * 0.9
            SetCamCoord(camSpec, Config.Center.x + math.cos(a) * R, Config.Center.y + math.sin(a) * R, Config.Center.z + 55.0)
            PointCamAtCoord(camSpec, Config.Center.x, Config.Center.y, Config.Center.z)
            Wait(0)
        end
    end)
end

local function leaveSpectate()
    spectating = false
    if camSpec then
        RenderScriptCams(false, true, 500, true, false)
        DestroyCam(camSpec, false)
        camSpec = nil
    end
end

local function cleanup()
    Base.active, Base.alive = false, false
    HUD:Hud(nil)
    TriggerServerEvent("spz:setPlayerFlag", "inMinigame", false)
    TriggerServerEvent("spz:setPlayerFlag", "vehDamage", nil)
    TriggerEvent("spz:minigameChanged")
    leaveSpectate()
    deleteCar()
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    SetEntityInvincible(ped, false)
    if myBack then
        SetEntityCoords(ped, myBack.x, myBack.y, myBack.z, false, false, false, false)
        if myBackH then SetEntityHeading(ped, myBackH) end
        myBack = nil
    end
end

-- ── Round events ────────────────────────────────────────────────────────────

RegisterNetEvent(E("start"), function(d)
    DoScreenFadeOut(300)
    Wait(300)
    Base.active, Base.alive, spectating = true, true, false
    Base.state = { phase = "intro" }
    TriggerServerEvent("spz:setPlayerFlag", "inMinigame", Config.Title)
    if Config.VehicleDamage then TriggerServerEvent("spz:setPlayerFlag", "vehDamage", true) end
    TriggerEvent("spz:minigameChanged")

    local ped = PlayerPedId()
    myBack, myBackH = returnPoint(ped)
    despawnFreeroamCar()
    ped = PlayerPedId()
    SetEntityCoords(ped, d.spawn.x, d.spawn.y, d.spawn.z + 2.0, false, false, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)          -- the car is what's in play, never the ped
    ClearPedTasksImmediately(ped)
    SetEntityCollision(ped, true, true)
    ResetEntityAlpha(ped)

    local gz = groundAt(d.spawn.x, d.spawn.y, d.spawn.z)
    TriggerServerEvent(E("ready"), gz)
    if Game.onStart then pcall(Game.onStart, d) end
    DoScreenFadeIn(600)
end)

-- Next round: out of spectate, back on the start ring, the server sends a new car.
RegisterNetEvent(E("respawn"), function(d)
    if not Base.active then return end
    DoScreenFadeOut(300)
    Wait(300)
    leaveSpectate()
    deleteCar()
    Base.alive = true
    local ped = PlayerPedId()
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    SetEntityCoords(ped, d.spawn.x, d.spawn.y, d.spawn.z + 2.0, false, false, false, false)
    FreezeEntityPosition(ped, true)
    local gz = groundAt(d.spawn.x, d.spawn.y, d.spawn.z)
    TriggerServerEvent(E("ready"), gz)
    if Game.onStart then pcall(Game.onStart, d) end
    DoScreenFadeIn(600)
end)

RegisterNetEvent(E("car"), function(d)
    if not Base.active then return end
    Base.veh = claimCar(d.netId)
    if Base.veh == 0 then FreezeEntityPosition(PlayerPedId(), false) end
end)

RegisterNetEvent(E("countdown"), function(n)
    if not Base.active then return end
    flash(tostring(n)); playClip("countdown")
end)

RegisterNetEvent(E("go"), function()
    if not Base.active then return end
    if Base.veh ~= 0 and DoesEntityExist(Base.veh) then FreezeEntityPosition(Base.veh, false) end
    flash("GO!", "ok"); playClip("go")
    if Game.onGo then pcall(Game.onGo) end
end)

RegisterNetEvent(E("state"), function(s)
    if not Base.active then return end
    Base.state = s
end)

RegisterNetEvent(E("feed"), function(d)
    if not Base.active then return end
    lib.notify({ description = ("%s — %s"):format(d.name or "?", d.why or "out"), type = "warning", duration = 3500 })
end)

RegisterNetEvent(E("eliminated"), function(d)
    if not Base.active then return end
    Base.alive = false
    lib.notify({ title = "ELIMINATED", description = d.why or "", type = "error", duration = 6000 })
    if Game.onEliminated then pcall(Game.onEliminated, d) end
end)

RegisterNetEvent(E("spectate"), function()
    if not Base.active then return end
    enterSpectate()
end)

RegisterNetEvent(E("over"), function(r)
    if not Base.active then return end
    if Game.onOver then pcall(Game.onOver, r) end
    local sub = (r.winner and (r.winner .. " wins") or (r.reason or ""))
        .. ((r.payout and r.payout > 0) and ("  ·  +%d credits"):format(r.payout) or "")
    HUD:Shard(r.won and "Winner" or "Round over", sub, r.won and "ok" or "bad", 4000)
    SetTimeout(3500, function()
        DoScreenFadeOut(400)
        Wait(450)
        cleanup()
        DoScreenFadeIn(600)
    end)
end)

-- ── HUD ─────────────────────────────────────────────────────────────────────

CreateThread(function()
    while true do
        if Base.active then
            local s = Base.state or {}
            local hud = { chips = { ("%d / %d alive"):format(s.alive or 0, s.total or 0) } }
            if s.wave and s.wave > 0 then hud.chips[#hud.chips + 1] = ("Wave %d"):format(s.wave) end
            if s.outRemain then hud.alert = ("Back into the arena  %.1f"):format(s.outRemain) end
            if spectating then hud.foot = { text = "Spectating", color = "bad" } end
            hud.board = s.board
            if Game.hud then pcall(Game.hud, s, hud) end
            -- key bar (live bindings, resolved by spz-minigames)
            hud.keys = hud.keys or {}
            hud.keys[#hud.keys + 1] = { control = 200, default = "ESC", pad = "START_INDEX", label = "Menu · leave" }
            HUD:Hud(hud)
            Wait(100)
        else
            Wait(500)
        end
    end
end)

-- ── Arena edge ──────────────────────────────────────────────────────────────

CreateThread(function()
    while true do
        if Base.active then
            -- Arena edge as a ring of markers, only when near it.
            if Base.alive and not spectating then
                local p = GetEntityCoords(PlayerPedId())
                local dx, dy = p.x - Config.Center.x, p.y - Config.Center.y
                local d = math.sqrt(dx * dx + dy * dy)
                if d > Config.ArenaRadius - 30.0 then
                    local n = 72
                    for i = 0, n - 1 do
                        local a = i / n * math.pi * 2.0
                        local x = Config.Center.x + math.cos(a) * Config.ArenaRadius
                        local y = Config.Center.y + math.sin(a) * Config.ArenaRadius
                        if (x - p.x) ^ 2 + (y - p.y) ^ 2 < 70.0 * 70.0 then
                            DrawMarker(1, x, y, p.z - 3.0, 0, 0, 0, 0, 0, 0, 2.5, 2.5, 8.0, 255, 60, 60, 110, false, false, 2, false, nil, nil, false)
                        end
                    end
                end
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- ── Queue menu ──────────────────────────────────────────────────────────────

local function openLobbyMenu()
    local st = lib.callback.await(E("lobbyState"), false)
    if not st then return end
    if st.roundLive then lib.notify({ description = "A round is live — wait for the next.", type = "warning" }); return end

    local online = lib.callback.await(E("online"), false) or {}
    local invite = {}
    if #online == 0 then invite[1] = { title = "No one else online", disabled = true } end
    for _, p in ipairs(online) do
        invite[#invite + 1] = { title = p.name, icon = "user-plus",
            onSelect = function() TriggerServerEvent(E("invite"), p.source) end }
    end
    lib.registerContext({ id = Config.Key .. "_invite", title = "Invite Player", menu = Config.Key .. "_lobby",
        search = #online > 6, options = invite })

    local opts = {
        {
            title = st.inLobby and "Leave Room" or "Quick Join",
            description = st.inLobby and "You are queued — tap to leave" or Config.Blurb,
            icon = st.inLobby and "right-from-bracket" or "right-to-bracket",
            iconColor = st.inLobby and "#ff4d5e" or "#22c55e",
            onSelect = function() lib.callback.await(E("joinToggle"), false); openLobbyMenu() end,
        },
        { title = "Invite Player", description = #online .. " online", icon = "user-plus", arrow = true, menu = Config.Key .. "_invite" },
        { title = ("── %s %d/%d%s ──"):format(st.room and st.room.name or "Room", st.count, st.max,
            st.armed and (" · starts in " .. (st.armedRemain or 0) .. "s") or ""), disabled = true },
    }
    if #st.roster == 0 then opts[#opts + 1] = { title = "Queue is empty", disabled = true } end
    for _, r in ipairs(st.roster) do opts[#opts + 1] = { title = (r.isMe and "★ " or "") .. r.name, disabled = true } end

    lib.registerContext({ id = Config.Key .. "_lobby", title = Config.MenuTitle or Config.Title, options = opts })
    lib.showContext(Config.Key .. "_lobby")
end

RegisterCommand(Config.MenuCommand, function() openLobbyMenu() end, false)

RegisterNetEvent(E("invited"), function(d)
    -- Racing / queued / in another minigame: a dialog would grab mouse focus
    -- and lock the car mid-race. Just tell them; the invite is kept, so the
    -- room shows as invited in the hub once they are free.
    do
        local st = LocalPlayer.state
        if st.inRace or st.inQueue or st.inMinigame or st.inTimeTrial then
            lib.notify({ title = Config.Title .. " invite",
                description = ("%s invited you to %s — open the minigames hub when you're free."):format(d.fromName or "Someone", d.roomName or "their room"),
                type = "inform", duration = 7000 })
            return
        end
    end
    local resp = lib.alertDialog({
        header = Config.Title .. " invite",
        content = ("**%s** invited you to **%s** (%s)."):format(d.fromName or "Someone", d.roomName or "their room", Config.Title),
        centered = true, cancel = true, labels = { cancel = "Dismiss", confirm = "Join" },
    })
    if resp == "confirm" then TriggerServerEvent(E("acceptInvite"), d.room) end
end)

AddEventHandler("spz:leaveMinigame", function()
    if Base.active then TriggerServerEvent(E("leave")) end
end)

AddEventHandler("onResourceStop", function(res)
    if res == GetCurrentResourceName() and Base.active then cleanup() end
end)

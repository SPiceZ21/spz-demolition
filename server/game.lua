-- server/game.lua — Demolition rules (see server/base.lua for the shared core)

local function health(veh)
    if not veh or not DoesEntityExist(veh) then return -1 end
    return math.max(0.0, GetVehicleEngineHealth(veh)) + math.max(0.0, GetVehicleBodyHealth(veh))
end

local function wrecked(veh)
    if not veh or not DoesEntityExist(veh) then return true end
    return GetVehicleEngineHealth(veh) <= Config.WreckEngine or GetVehicleBodyHealth(veh) <= Config.WreckBody
end

function Game.run(r)
    r.phase = "fight"
    r.endsAt = GetGameTimer() + Config.RoundSec * 1000

    while r.active do
        Wait(250)
        for src, p in pairs(r.players) do
            if p.alive and p.veh and wrecked(p.veh) then Base.eliminate(src, "wrecked") end
        end

        if #Base.aliveList(r) <= 1 then return end

        if GetGameTimer() >= r.endsAt then
            -- Time: the healthiest car takes it; ties share the win.
            local best = -1
            for _, src in ipairs(Base.aliveList(r)) do best = math.max(best, health(r.players[src].veh)) end
            for _, src in ipairs(Base.aliveList(r)) do
                if health(r.players[src].veh) < best then Base.eliminate(src, "time — more damaged") end
            end
            return
        end
    end
end

-- Every knockout pays the cars still running.
function Game.onEliminated(r, _, _)
    for _, src in ipairs(Base.aliveList(r)) do
        local p = r.players[src]
        p.bonus = (p.bonus or 0) + (Config.KnockoutBonus or 0)
    end
end

Game.boardTitle = "Cars"

function Game.boardRow(r, src, p, row)
    if not p.alive then row.value, row.valueColor, row.icon = "Wrecked", "bad", "skull"; return end
    local hp = math.max(0.0, math.min(1.0, (p.veh and DoesEntityExist(p.veh) and GetVehicleEngineHealth(p.veh) or 0) / 1000.0))
    row.value = ("%d%%"):format(math.floor(hp * 100))
    row.valueColor = hp > 0.6 and "ok" or (hp > 0.3 and "warn" or "bad")
    row.icon, row.color, row.score = "car", "dim", hp
end

function Game.hud(r, src, p)
    return { health = p.veh and DoesEntityExist(p.veh) and GetVehicleEngineHealth(p.veh) or 0 }
end

-- Client backup: its own car is dead / burning (only ever eliminates the sender).
RegisterNetEvent(Base.E("wrecked"), function()
    local src = source
    local r = Base.roundOf(src)
    if r and r.live and r.players[src] and r.players[src].alive then Base.eliminate(src, "wrecked") end
end)

RegisterCommand("dmwhere", function(src)
    if src == 0 or not IsPlayerAceAllowed(src, "spz.admin") then return end
    local c = GetEntityCoords(GetPlayerPed(src))
    Base.notify(src, ("Config.Center = vector3(%.1f, %.1f, %.1f)"):format(c.x, c.y, c.z), "info")
    print(("[%s] /dmwhere %.2f, %.2f, %.2f"):format(Config.Key, c.x, c.y, c.z))
end, false)

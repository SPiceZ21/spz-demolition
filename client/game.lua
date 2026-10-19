-- client/game.lua — Demolition HUD + real damage (see client/base.lua for the shared core)

local reported = false

function Game.onStart() reported = false end

-- Undo anything spz-vehfunc godmode applied before it stood down (vehDamage flag).
function Game.onCar(veh)
    SetEntityCanBeDamaged(veh, true)
    SetEntityInvincible(veh, false)
    SetEntityProofs(veh, false, false, false, false, false, false, false, false)
    SetVehicleCanBeVisiblyDamaged(veh, true)
    SetVehicleStrong(veh, false)
    SetVehicleTyresCanBurst(veh, true)
    SetVehicleWheelsCanBreak(veh, true)
    SetVehicleEngineCanDegrade(veh, true)
    SetVehicleEngineHealth(veh, 1000.0)
    SetVehicleBodyHealth(veh, 1000.0)
    SetVehiclePetrolTankHealth(veh, 1000.0)
end

function Game.onGo()
    lib.notify({ title = "DEMOLITION", description = "Wreck everyone. Last car running wins.", type = "inform", duration = 5000 })
end

function Game.onEliminated()
    local v = Base.veh
    if v ~= 0 and DoesEntityExist(v) then
        SetVehicleEngineOn(v, false, true, true)
        SetVehicleUndriveable(v, true)
        SetVehicleEngineHealth(v, -1000.0)     -- smoking wreck for the moment before spectate
    end
end

-- Backup wreck report: catches a car that blew up between server polls.
CreateThread(function()
    while true do
        if Base.active and Base.alive and not reported and Base.veh ~= 0 and (Base.state or {}).phase == "fight" then
            local v = Base.veh
            if not DoesEntityExist(v) or IsEntityDead(v) or GetVehicleEngineHealth(v) <= Config.WreckEngine then
                reported = true
                TriggerServerEvent(Base.E("wrecked"))
            end
            Wait(200)
        else
            Wait(500)
        end
    end
end)

function Game.hud(s, hud)
    if s.remain and s.phase == "fight" then
        local m = math.floor(s.remain / 60)
        hud.status = { label = "Time left", value = ("%d:%02d"):format(m, math.floor(s.remain % 60)),
                       color = s.remain < 30 and "bad" or nil }
    end
    if Base.alive and Base.veh ~= 0 and DoesEntityExist(Base.veh) then
        local hp = math.max(0.0, math.min(1.0, GetVehicleEngineHealth(Base.veh) / 1000.0))
        hud.bar = { label = "Car", pct = math.floor(hp * 100) / 100 }
    end
end

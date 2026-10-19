-- config.lua — Demolition (destruction derby)
-- Everyone spawns on a ring in the iak_demolition bowl, facing in. Cars take
-- REAL damage. Wreck the others; the last car still running wins. If the clock
-- runs out first, the healthiest car left wins.

Config = {}

Config.Key          = "spz-demolition"     -- event prefix / bucket name (don't change)
Config.Title        = "Demolition"
Config.MenuTitle    = "💥 Demolition Derby"
Config.Blurb        = "Destruction derby — last car running wins"
Config.Command      = "demolition"         -- join / leave the lobby
Config.StartCommand = "dmstart"            -- start the lobby now
Config.MenuCommand  = "demolitionmenu"     -- queue menu (radial → Minigames)
Config.PlatePrefix  = "DRB"

-- ── Lobby ───────────────────────────────────────────────────────────────────
Config.MinPlayers   = 2
Config.MaxPlayers   = 16
Config.LobbyWaitSec = 45
Config.MaxRooms     = 8      -- rooms that can exist (and play) at the same time

-- ── Rewards ─────────────────────────────────────────────────────────────────
Config.WinReward    = 1500     -- last car running (split if the clock decides a tie)
Config.KnockoutBonus = 75      -- paid to every survivor each time someone is wrecked

-- ── Arena (iak_demolition, the bowl near the Grand Senora prison road) ──────
-- Centre of the arena floor, read from the map's own props. Tune in game if the
-- ring or the fence sits wrong: stand where you want the centre and use
-- /dmwhere (admin) to print the coords.
Config.Center      = vector3(2035.0, 2818.0, 49.0)
Config.SpawnRadius = 38.0      -- the start ring
Config.ArenaRadius = 92.0      -- leave this circle for OutGraceSec = eliminated
Config.OutGraceSec = 5
Config.FallDepth   = 15.0      -- metres under the floor = eliminated
Config.OutOfCarSec = 6         -- on foot this long = eliminated
Config.SpectateDelaySec = 2.5

-- ── Round ───────────────────────────────────────────────────────────────────
Config.RoundSec    = 240       -- 4:00, then the healthiest car wins
Config.WreckEngine = 0.0       -- GTA engine health (1000 new): at/below this you're out
Config.WreckBody   = 0.0

-- ── Cars ────────────────────────────────────────────────────────────────────
-- Heavy, cheap, body-on-frame: they take a beating and look the part.
Config.VehicleDamage = true    -- real damage (spz-vehfunc godmode stands down)
Config.Cars = {
    "emperor2", "tornado3", "voodoo2", "glendale", "regina", "stanier",
    "dukes", "sabregt", "rancherxl", "picador", "bodhi2", "ingot",
}

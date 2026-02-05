-- ============================================================================
-- Real Smoke - Configuration
-- ============================================================================
-- Realistic vehicle fire smoke for FiveM. All settings are customizable.
-- ============================================================================

RealSmoke = {
    Enabled = true,

    -- Performance & Distance
    CheckInterval = 1000,       -- ms between vehicle fire scans
    WorldFireInterval = 2000,   -- ms between world fire scans
    MaxDistance = 1000.0,        -- max distance (meters) to render smoke effects
    MAX_ACTIVE_FX = 30,         -- hard cap on simultaneous particle effects

    -- Feature toggles
    ExplosionSmoke = true,      -- secondary explosion + lingering smoke on vehicle destruction
    WorldFireSmoke = true,      -- smoke on non-vehicle fires (molotovs, gas stations, etc.)
    GasStationSmoke = true,     -- enhanced smoke for gas station fires (detects nearby gas pumps)
    MassScaling = true,         -- heavier vehicles produce more smoke

    -- Smoke appearance
    Fire = {
        scale = 1.0,            -- size of fire smoke column
        alpha = 0.4,            -- opacity (0.0 invisible, 1.0 opaque)
        delay = 2000,           -- ms before smoke appears (lets GTA fire build first)
        offsetZ = 2.0,          -- vertical offset above vehicle
    },
    Wreck = {
        scale = 0.8,            -- size of wreck smoke
        alpha = 0.3,            -- opacity
        fadeTime = 60,          -- seconds to gradually fade out
        offsetZ = 0.5,          -- vertical offset
    },
    WorldFire = {
        scale = 0.8,
        alpha = 0.4,
        offsetZ = 1.0,
    },
    GasStation = {
        -- Gas/petrol fires burn hotter and produce thick black smoke
        scale = 2.0,            -- larger primary smoke column
        alpha = 0.7,            -- denser/darker smoke (real fuel fires are very opaque)
        offsetZ = 1.5,          -- slightly higher base
        secondaryScale = 3.0,   -- second column for towering effect
        secondaryAlpha = 0.5,   -- upper column slightly more transparent
    },
    Explosion = {
        scale = 1.2,
        alpha = 0.4,
        duration = 30,          -- seconds the smoke lingers after explosion
    },

    -- Mass-based scaling config
    Mass = {
        threshold = 2000.0,     -- kg — vehicles under this get no bonus
        normalPerTon = 0.03,    -- multiplier increase per ton over threshold (cars, trucks)
        heavyPerTon = 0.05,     -- multiplier increase per ton for aircraft/military
        maxMultiplier = 1.8,    -- cap so massive vehicles don't break effects
        -- Vehicle classes that get the heavier per-ton rate (GTA vehicle class IDs)
        heavyClasses = {
            [15] = true,        -- Helicopters
            [16] = true,        -- Planes
            [19] = true,        -- Military
        },
    },

    -- Debug — set to true to print messages to F8 console
    Debug = false,
}

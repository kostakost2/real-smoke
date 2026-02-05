-- ============================================================================
-- Real Smoke - Realistic Vehicle Fire Smoke for FiveM
-- ============================================================================
-- Adds realistic smoke columns to burning vehicles, destroyed wrecks,
-- world fires and explosion aftermath. Mass-based scaling makes heavier
-- vehicles produce proportionally more smoke.
--
-- Client-side only. Uses only the 'core' PTFX dictionary (guaranteed
-- available in FiveM). Distance-culled and FX-capped for performance.
-- ============================================================================

local activeFx = {}
local coreLoaded = false
local activeCount = 0
local worldFireSmoke = {}
local explosionFx = {}  -- Track explosion aftermath effects for cleanup

-- Gas pump prop model hashes for gas station fire detection
local gasPumpHashes = {
    GetHashKey("prop_gas_pump_1a"),
    GetHashKey("prop_gas_pump_1b"),
    GetHashKey("prop_gas_pump_1c"),
    GetHashKey("prop_gas_pump_1d"),
    GetHashKey("prop_gas_pump_old1"),
    GetHashKey("prop_gas_pump_old2"),
    GetHashKey("prop_gas_pump_old3"),
    GetHashKey("prop_vintage_pump"),
    GetHashKey("prop_gas_pump_1d_lod"),
}

-- ============================================================================
-- Debug Helper
-- ============================================================================

local function DebugPrint(msg)
    if RealSmoke.Debug then
        print("^2[Real Smoke] " .. msg)
    end
end

-- ============================================================================
-- PTFX Dictionary Management
-- ============================================================================

local function EnsureCore()
    if coreLoaded then return true end
    RequestNamedPtfxAsset("core")
    local timeout = 0
    while not HasNamedPtfxAssetLoaded("core") and timeout < 100 do
        Citizen.Wait(10)
        timeout = timeout + 1
    end
    if HasNamedPtfxAssetLoaded("core") then
        coreLoaded = true
        return true
    end
    DebugPrint("^1Failed to load core PTFX dictionary!")
    return false
end

-- ============================================================================
-- Effect Helpers
-- ============================================================================

local function StartLoopedOnEntity(effect, entity, offX, offY, offZ, scale, alpha)
    if activeCount >= RealSmoke.MAX_ACTIVE_FX then return nil end
    if not EnsureCore() then return nil end
    UseParticleFxAssetNextCall("core")
    local handle = StartParticleFxLoopedOnEntity(
        effect, entity,
        offX, offY, offZ,
        0.0, 0.0, 0.0,
        scale, false, false, false
    )
    if handle and handle ~= 0 then
        activeCount = activeCount + 1
        if alpha then SetParticleFxLoopedAlpha(handle, alpha) end
        return handle
    end
    return nil
end

local function StartLoopedAtCoord(effect, x, y, z, scale, alpha)
    if activeCount >= RealSmoke.MAX_ACTIVE_FX then return nil end
    if not EnsureCore() then return nil end
    UseParticleFxAssetNextCall("core")
    local handle = StartParticleFxLoopedAtCoord(
        effect, x, y, z,
        0.0, 0.0, 0.0,
        scale, false, false, false, false
    )
    if handle and handle ~= 0 then
        activeCount = activeCount + 1
        if alpha then SetParticleFxLoopedAlpha(handle, alpha) end
        return handle
    end
    return nil
end

local function StopFx(handle)
    if handle and DoesParticleFxLoopedExist(handle) then
        StopParticleFxLooped(handle, false)  -- Also handles removal internally
        activeCount = activeCount - 1
        if activeCount < 0 then activeCount = 0 end
    end
end

-- Recount active effects to fix potential desync from GTA-killed effects
local function ValidateActiveCount()
    local realCount = 0
    for _, handles in pairs(activeFx) do
        for _, h in ipairs(handles) do
            if DoesParticleFxLoopedExist(h) then
                realCount = realCount + 1
            end
        end
    end
    for _, entry in pairs(worldFireSmoke) do
        for _, h in ipairs(entry.handles) do
            if DoesParticleFxLoopedExist(h) then
                realCount = realCount + 1
            end
        end
    end
    for h, _ in pairs(explosionFx) do
        if DoesParticleFxLoopedExist(h) then
            realCount = realCount + 1
        end
    end
    if activeCount ~= realCount then
        DebugPrint(("activeCount corrected: %d -> %d"):format(activeCount, realCount))
        activeCount = realCount
    end
end

-- ============================================================================
-- Mass-Based Smoke Scaling
-- ============================================================================

local function GetSmokeMultiplier(vehicle)
    if not RealSmoke.MassScaling then return 1.0 end

    local mass = GetVehicleHandlingFloat(vehicle, "CHandlingData", "fMass")
    local cfg = RealSmoke.Mass
    if mass <= cfg.threshold then return 1.0 end

    local excessTons = (mass - cfg.threshold) / 1000.0
    local vehClass = GetVehicleClass(vehicle)
    local perTon = cfg.normalPerTon
    if cfg.heavyClasses[vehClass] then
        perTon = cfg.heavyPerTon
    end

    local mult = 1.0 + excessTons * perTon
    if mult > cfg.maxMultiplier then mult = cfg.maxMultiplier end
    return mult
end

-- ============================================================================
-- Cleanup Helpers
-- ============================================================================

local function CleanupEntity(entity)
    local handles = activeFx[entity]
    if not handles then return end
    for _, h in ipairs(handles) do
        StopFx(h)
    end
    activeFx[entity] = nil
end

-- ============================================================================
-- Vehicle Fire Smoke
-- ============================================================================

local function ApplyFireSmoke(vehicle)
    if activeFx[vehicle] then return end
    activeFx[vehicle] = {}

    local mult = GetSmokeMultiplier(vehicle)
    local cfg = RealSmoke.Fire
    DebugPrint(("Fire smoke on vehicle %d (mult=%.2f)"):format(vehicle, mult))

    -- Smoke layer delayed to let GTA's own fire effects build first
    Citizen.SetTimeout(cfg.delay, function()
        if not activeFx[vehicle] then return end
        if not DoesEntityExist(vehicle) then return end
        local s1 = StartLoopedOnEntity("ent_amb_smoke_foundry", vehicle, 0.0, 0.0, cfg.offsetZ, cfg.scale * mult, cfg.alpha * mult)
        if s1 then table.insert(activeFx[vehicle], s1) end
    end)
end

local function ApplyWreckSmoke(vehicle)
    if activeFx[vehicle] then return end
    activeFx[vehicle] = {}

    local mult = GetSmokeMultiplier(vehicle)
    local cfg = RealSmoke.Wreck
    local baseAlpha = cfg.alpha * mult
    DebugPrint(("Wreck smoke on vehicle %d (mult=%.2f, fading over %ds)"):format(vehicle, mult, cfg.fadeTime))

    local s1 = StartLoopedOnEntity("ent_amb_smoke_foundry", vehicle, 0.0, 0.0, cfg.offsetZ, cfg.scale * mult, baseAlpha)
    if s1 then
        table.insert(activeFx[vehicle], s1)
        -- Gradually reduce alpha then stop
        Citizen.CreateThread(function()
            local steps = 12
            local interval = (cfg.fadeTime * 1000) / steps
            for i = 1, steps do
                Citizen.Wait(interval)
                if not activeFx[vehicle] then return end
                if not DoesParticleFxLoopedExist(s1) then return end
                local newAlpha = baseAlpha * (1.0 - (i / steps))
                SetParticleFxLoopedAlpha(s1, newAlpha)
            end
            CleanupEntity(vehicle)
        end)
    end
end

-- ============================================================================
-- World Fire Detection
-- ============================================================================

local function CoordKey(x, y, z)
    return math.floor(x / 2) .. "_" .. math.floor(y / 2) .. "_" .. math.floor(z / 2)
end

-- Check if coordinates are near a gas pump (gas station fire)
local function IsNearGasPump(x, y, z, radius)
    for _, hash in ipairs(gasPumpHashes) do
        local pump = GetClosestObjectOfType(x, y, z, radius, hash, false, false, false)
        if pump ~= 0 then
            return true
        end
    end
    return false
end

local function ApplyWorldFireSmoke(x, y, z)
    local key = CoordKey(x, y, z)
    if worldFireSmoke[key] then
        worldFireSmoke[key].lastSeen = GetGameTimer()
        return
    end

    -- Check if this is a gas station fire
    local isGasStation = RealSmoke.GasStationSmoke and IsNearGasPump(x, y, z, 15.0)
    local cfg = isGasStation and RealSmoke.GasStation or RealSmoke.WorldFire

    worldFireSmoke[key] = { handles = {}, lastSeen = GetGameTimer(), isGasStation = isGasStation }

    if isGasStation then
        DebugPrint(("Gas station fire detected at %.1f, %.1f, %.1f"):format(x, y, z))
    end

    local s1 = StartLoopedAtCoord("ent_amb_smoke_foundry", x, y, z + cfg.offsetZ, cfg.scale, cfg.alpha)
    if s1 then table.insert(worldFireSmoke[key].handles, s1) end

    -- Gas station fires get a second, larger smoke column for thick black smoke effect
    if isGasStation and cfg.secondaryScale then
        local s2 = StartLoopedAtCoord("ent_amb_smoke_foundry", x, y, z + cfg.offsetZ + 3.0, cfg.secondaryScale, cfg.secondaryAlpha or cfg.alpha)
        if s2 then table.insert(worldFireSmoke[key].handles, s2) end
    end
end

local function CleanupWorldFire(key)
    local entry = worldFireSmoke[key]
    if not entry then return end
    for _, h in ipairs(entry.handles) do
        StopFx(h)
    end
    worldFireSmoke[key] = nil
end

-- ============================================================================
-- Main Loop - Vehicle Fires
-- ============================================================================

Citizen.CreateThread(function()
    while not RealSmoke do Citizen.Wait(500) end
    if not RealSmoke.Enabled then
        DebugPrint("Disabled in config")
        return
    end

    DebugPrint("Vehicle fire smoke thread started")

    while true do
        Citizen.Wait(RealSmoke.CheckInterval)

        local playerPos = GetEntityCoords(PlayerPedId())
        local vehicles = GetGamePool('CVehicle')

        for _, vehicle in ipairs(vehicles) do
            if DoesEntityExist(vehicle) then
                local dist = #(playerPos - GetEntityCoords(vehicle))

                if dist < RealSmoke.MaxDistance then
                    local engineHealth = GetVehicleEngineHealth(vehicle)
                    local onFire = IsEntityOnFire(vehicle)

                    if onFire then
                        ApplyFireSmoke(vehicle)
                    elseif engineHealth < -3000 then
                        ApplyWreckSmoke(vehicle)
                    else
                        if activeFx[vehicle] then
                            CleanupEntity(vehicle)
                        end
                    end
                elseif activeFx[vehicle] then
                    CleanupEntity(vehicle)
                end
            end
        end

        for entity, _ in pairs(activeFx) do
            if type(entity) == "number" and not DoesEntityExist(entity) then
                CleanupEntity(entity)
            end
        end
    end
end)

-- ============================================================================
-- Main Loop - World Fires (non-vehicle)
-- ============================================================================

Citizen.CreateThread(function()
    while not RealSmoke do Citizen.Wait(500) end
    if not RealSmoke.Enabled or not RealSmoke.WorldFireSmoke then return end

    DebugPrint("World fire smoke thread started")

    while true do
        Citizen.Wait(RealSmoke.WorldFireInterval)

        local playerPos = GetEntityCoords(PlayerPedId())
        local searchRadius = math.min(RealSmoke.MaxDistance, 100.0)
        local foundFires = {}

        for angle = 0, 330, 30 do
            for r = 10, searchRadius, 20 do
                local rad = math.rad(angle)
                local checkX = playerPos.x + math.cos(rad) * r
                local checkY = playerPos.y + math.sin(rad) * r
                local checkZ = playerPos.z

                local retval, firePos = GetClosestFirePos(checkX, checkY, checkZ)
                if retval then
                    local fireDist = #(playerPos - firePos)
                    if fireDist < RealSmoke.MaxDistance then
                        local key = CoordKey(firePos.x, firePos.y, firePos.z)
                        if not foundFires[key] then
                            foundFires[key] = true
                            ApplyWorldFireSmoke(firePos.x, firePos.y, firePos.z)
                        end
                    end
                end
            end
        end

        local now = GetGameTimer()
        for key, entry in pairs(worldFireSmoke) do
            if now - entry.lastSeen > 5000 then
                CleanupWorldFire(key)
            end
        end
    end
end)

-- ============================================================================
-- Explosion Aftermath
-- ============================================================================

Citizen.CreateThread(function()
    while not RealSmoke do Citizen.Wait(500) end
    if not RealSmoke.Enabled or not RealSmoke.ExplosionSmoke then return end

    DebugPrint("Explosion aftermath thread started")
    local trackedVehicles = {}

    while true do
        Citizen.Wait(200)

        local playerPos = GetEntityCoords(PlayerPedId())
        local vehicles = GetGamePool('CVehicle')

        for _, vehicle in ipairs(vehicles) do
            if DoesEntityExist(vehicle) then
                local engineHealth = GetVehicleEngineHealth(vehicle)

                if engineHealth <= -4000 and not trackedVehicles[vehicle] then
                    trackedVehicles[vehicle] = true
                    local coords = GetEntityCoords(vehicle)
                    local dist = #(playerPos - coords)

                    if dist < RealSmoke.MaxDistance then
                        local mult = GetSmokeMultiplier(vehicle)
                        local cfg = RealSmoke.Explosion

                        -- Delayed secondary explosion
                        Citizen.SetTimeout(300, function()
                            if EnsureCore() then
                                UseParticleFxAssetNextCall("core")
                                StartParticleFxNonLoopedAtCoord(
                                    "exp_grd_rpg", coords.x, coords.y, coords.z + 0.5,
                                    0.0, 0.0, 0.0, 2.0 * mult,
                                    false, false, false
                                )
                            end
                        end)

                        -- Lingering smoke column
                        Citizen.SetTimeout(800, function()
                            local h1 = StartLoopedAtCoord("ent_amb_smoke_foundry", coords.x, coords.y, coords.z, cfg.scale * mult, cfg.alpha * mult)
                            if h1 then
                                explosionFx[h1] = true  -- Track for cleanup on resource stop
                                Citizen.SetTimeout(cfg.duration * 1000, function()
                                    if explosionFx[h1] then
                                        StopFx(h1)
                                        explosionFx[h1] = nil
                                    end
                                end)
                            end
                        end)
                    end
                elseif engineHealth > -4000 then
                    trackedVehicles[vehicle] = nil
                end
            end
        end

        for vehicle, _ in pairs(trackedVehicles) do
            if not DoesEntityExist(vehicle) then
                trackedVehicles[vehicle] = nil
            end
        end
    end
end)

-- ============================================================================
-- Periodic Active Count Validation
-- ============================================================================

Citizen.CreateThread(function()
    while not RealSmoke do Citizen.Wait(500) end
    if not RealSmoke.Enabled then return end

    while true do
        Citizen.Wait(30000)  -- Validate every 30 seconds
        ValidateActiveCount()
    end
end)

-- ============================================================================
-- Cleanup on Resource Stop
-- ============================================================================

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for entity, _ in pairs(activeFx) do
            CleanupEntity(entity)
        end
        for key, _ in pairs(worldFireSmoke) do
            CleanupWorldFire(key)
        end
        for handle, _ in pairs(explosionFx) do
            StopFx(handle)
        end
        explosionFx = {}
        if coreLoaded then
            RemoveNamedPtfxAsset("core")
        end
        DebugPrint("Resource stopped, all effects cleaned up")
    end
end)

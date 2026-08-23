local GetGamePool                     = GetGamePool
local GetEntityCoords                 = GetEntityCoords
local GetEntityModel                  = GetEntityModel
local DoesEntityExist                 = DoesEntityExist
local NetworkGetEntityIsNetworked     = NetworkGetEntityIsNetworked
local GetPedDrawableVariation         = GetPedDrawableVariation
local GetPedTextureVariation          = GetPedTextureVariation
local GetPedPropIndex                 = GetPedPropIndex
local GetNumberOfPedDrawableVariations = GetNumberOfPedDrawableVariations
local GetNumberOfPedTextureVariations  = GetNumberOfPedTextureVariations
local GetNumberOfPedPropDrawableVariations = GetNumberOfPedPropDrawableVariations
local SetPedComponentVariation        = SetPedComponentVariation
local ClearPedPropImmediately         = ClearPedPropImmediately
local PlayerPedId                     = PlayerPedId

local PASS_INTERVAL_MS = 1000
local PEDS_PER_PASS    = 128
local SCAN_RADIUS_SQ   = 8100.0
local COMPONENT_LAST   = 11
local PROP_LAST        = 9
local CACHE_MIN_COUNT  = 1

local drawablesByModel = {}
local texturesByModel  = {}
local propsByModel     = {}

local function getDrawableCount(model, component, ped)
    local perModel = drawablesByModel[model]
    if not perModel then
        perModel = {}
        drawablesByModel[model] = perModel
    end

    local count = perModel[component]
    if not count then
        count = GetNumberOfPedDrawableVariations(ped, component)

        if count < CACHE_MIN_COUNT then
            return count
        end

        perModel[component] = count
    end

    return count
end

local function getTextureCount(model, component, drawable, ped)
    local perModel = texturesByModel[model]
    if not perModel then
        perModel = {}
        texturesByModel[model] = perModel
    end

    local perComponent = perModel[component]
    if not perComponent then
        perComponent = {}
        perModel[component] = perComponent
    end

    local count = perComponent[drawable]
    if not count then
        count = GetNumberOfPedTextureVariations(ped, component, drawable)

        if count < CACHE_MIN_COUNT then
            return count
        end

        perComponent[drawable] = count
    end

    return count
end

local function getPropCount(model, prop, ped)
    local perModel = propsByModel[model]
    if not perModel then
        perModel = {}
        propsByModel[model] = perModel
    end

    local count = perModel[prop]
    if not count then
        count = GetNumberOfPedPropDrawableVariations(ped, prop)

        if count < CACHE_MIN_COUNT then
            return count
        end

        perModel[prop] = count
    end

    return count
end

local function validateAndRepair(ped, myX, myY)
    local coords = GetEntityCoords(ped)
    local dx = coords.x - myX
    local dy = coords.y - myY

    if dx * dx + dy * dy > SCAN_RADIUS_SQ then
        return
    end

    local model = GetEntityModel(ped)
    if not model or model == 0 then
        return
    end

    for component = 0, COMPONENT_LAST do
        local drawable = GetPedDrawableVariation(ped, component)
        local maxDrawable = getDrawableCount(model, component, ped)

        if maxDrawable > 0 and (drawable < 0 or drawable >= maxDrawable) then
            SetPedComponentVariation(ped, component, 0, 0, 0)
        else
            local texture = GetPedTextureVariation(ped, component)

            if maxDrawable > 0 then
                local maxTexture = getTextureCount(model, component, drawable, ped)

                if maxTexture > 0 and (texture < 0 or texture >= maxTexture) then
                    SetPedComponentVariation(ped, component, drawable, 0, 0)
                end
            end
        end
    end

    for prop = 0, PROP_LAST do
        local propIndex = GetPedPropIndex(ped, prop)

        if propIndex ~= -1 then
            local maxProp = getPropCount(model, prop, ped)

            if maxProp > 0 and propIndex >= maxProp then
                ClearPedPropImmediately(ped, prop)
            end
        end
    end
end

local cursor = 0

CreateThread(function()
    while true do
        Wait(PASS_INTERVAL_MS)

        local peds = GetGamePool('CPed')
        local total = #peds

        if total == 0 then
            cursor = 0
        else
            local myPed = PlayerPedId()
            local myCoords = GetEntityCoords(myPed)
            local scanned = 0
            local index = cursor

            while scanned < PEDS_PER_PASS do
                index = index + 1

                if index > total then
                    index = 1
                end

                cursor = index
                scanned = scanned + 1

                local ped = peds[index]

                if ped ~= myPed
                    and DoesEntityExist(ped)
                    and NetworkGetEntityIsNetworked(ped) then
                    validateAndRepair(ped, myCoords.x, myCoords.y)
                end

                if scanned >= total then
                    break
                end
            end
        end
    end
end)

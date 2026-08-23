local GetPlayers               = GetPlayers
local GetPlayerPed             = GetPlayerPed
local GetPlayerName            = GetPlayerName
local GetPlayerIdentifierByType = GetPlayerIdentifierByType
local GetVehiclePedIsIn        = GetVehiclePedIsIn
local GetVehicleType           = GetVehicleType
local GetPedSpecificTaskType   = GetPedSpecificTaskType
local GetEntityType            = GetEntityType
local GetEntityOwner           = GetEntityOwner
local DoesEntityExist          = DoesEntityExist
local DeleteEntity             = DeleteEntity
local DropPlayer               = DropPlayer
local GetGameTimer             = GetGameTimer
local GetConvar                = GetConvar
local PerformHttpRequest       = PerformHttpRequest

local format = string.format
local time   = os.time
local date   = os.date
local abs    = math.abs

local KICK_REASON      = 'Attempt To Crash Players Detected'

local RAPPEL_TASK_TYPE = 67
local TASK_SLOT_COUNT  = 8
local TASK_SWEEP_MS    = 500

local ENTITY_LIMITS = {
    [1] = { key = 'ped',     limit = 24, window = 5000 },
    [2] = { key = 'vehicle', limit = 20, window = 5000 },
    [3] = { key = 'object',  limit = 60, window = 5000 },
}

local ENTITY_HARD_MULT   = 3
local RING_SIZE          = 128
local RING_MAX_AGE_MS    = 15000

local EXPLOSION_LIMIT     = 30
local EXPLOSION_WINDOW    = 5000
local EXPLOSION_HARD_MULT = 3
local MAX_EXPLOSION_TYPE  = 80
local MAX_WORLD_COORD     = 60000

local WEBHOOK_URL  = GetConvar('ecg_discord_webhook', '')
local WEBHOOK_NAME = GetConvar('ecg_discord_name', 'Elit3 Crash Guard')

local onesyncSetting = GetConvar('onesync', 'off')
local onesyncRuntime = pcall(GetEntityOwner, 0)

if onesyncSetting == 'off' or onesyncSetting == '' or not onesyncRuntime then
    print('OneSync Needs To Be Enabled For Elit3 Crash Guard')
    return
end

local kickCounter  = 0
local rateBuckets  = {}
local entityRings  = {}
local floodFlagged = {}

local logQueue = {}

local function nextKickId()
    kickCounter = kickCounter + 1
    return format('ecg-%04d', kickCounter)
end

local function getLicense(src)
    return GetPlayerIdentifierByType(src, 'license') or 'unknown'
end

local function getDiscordId(src)
    local ident = GetPlayerIdentifierByType(src, 'discord')

    if ident then
        return ident:gsub('^discord:', '')
    end

    return nil
end

local function queueLog(description)
    if WEBHOOK_URL == '' then
        return
    end

    logQueue[#logQueue + 1] = {
        description = description,
        stamp = time()
    }
end

CreateThread(function()
    while true do
        Wait(5000)

        if WEBHOOK_URL ~= '' and #logQueue > 0 then
            local embeds = {}

            for i = 1, math.min(#logQueue, 10) do
                local entry = table.remove(logQueue, 1)

                embeds[i] = {
                    title = 'Crash Attempt Blocked',
                    description = entry.description,
                    color = 15158332,
                    footer = { text = 'Elit3 Crash Guard' },
                    timestamp = date('!%Y-%m-%dT%H:%M:%SZ', entry.stamp)
                }
            end

            PerformHttpRequest(WEBHOOK_URL, function() end, 'POST',
                json.encode({ username = WEBHOOK_NAME, embeds = embeds }),
                { ['Content-Type'] = 'application/json' })
        end
    end
end)

local function crashDrop(src, method, detail)
    local name = GetPlayerName(src)

    if not name then
        return
    end

    local kickId = nextKickId()

    DropPlayer(src, format('%s (%s)', KICK_REASON, kickId))

    local discordId = getDiscordId(src)
    local discordLine = discordId and format('**Discord:** <@%s>\n', discordId) or '**Discord:** not linked\n'

    queueLog(format(
        '**Player:** %s\n**Server ID:** %d\n%s**License:** %s\n**Method:** %s\n**Detail:** %s\n**Reference:** %s',
        name, src, discordLine, getLicense(src), method, detail or 'n/a', kickId))
end

local function bumpRate(src, key, window)
    local now = GetGameTimer()

    local perPlayer = rateBuckets[src]
    if not perPlayer then
        perPlayer = {}
        rateBuckets[src] = perPlayer
    end

    local bucket = perPlayer[key]
    if not bucket or now - bucket.reset >= window then
        bucket = { reset = now, count = 0 }
        perPlayer[key] = bucket
    end

    bucket.count = bucket.count + 1
    return bucket.count
end

local function ringPush(src, entity)
    local ring = entityRings[src]
    if not ring then
        ring = { cursor = 1, handles = {}, stamps = {} }
        entityRings[src] = ring
    end

    local slot = ring.cursor
    ring.handles[slot] = entity
    ring.stamps[slot] = GetGameTimer()
    ring.cursor = (slot % RING_SIZE) + 1
end

local function ringPurge(src)
    local ring = entityRings[src]
    if not ring then
        return
    end

    local now = GetGameTimer()

    for i = 1, RING_SIZE do
        local handle = ring.handles[i]

        if handle and DoesEntityExist(handle) and now - ring.stamps[i] < RING_MAX_AGE_MS then
            DeleteEntity(handle)
        end

        ring.handles[i] = nil
        ring.stamps[i] = nil
    end

    ring.cursor = 1
end

CreateThread(function()
    while true do
        Wait(TASK_SWEEP_MS)

        local players = GetPlayers()

        for i = 1, #players do
            local src = tonumber(players[i])

            if src then
                local ped = GetPlayerPed(src)

                if ped and ped > 0 then
                    local vehicle = GetVehiclePedIsIn(ped, false)

                    if vehicle > 0 and GetVehicleType(vehicle) ~= 'heli' then
                        for slot = 0, TASK_SLOT_COUNT - 1 do
                            if GetPedSpecificTaskType(ped, slot) == RAPPEL_TASK_TYPE then
                                crashDrop(src, 'Spoofed TASK_HELI_PASSENGER_RAPPEL',
                                    format('rappel task active in slot %d while not in a helicopter', slot))
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end)

AddEventHandler('entityCreating', function(entity)
    local owner = GetEntityOwner(entity)

    if not owner or owner <= 0 then
        return
    end

    local cfg = ENTITY_LIMITS[GetEntityType(entity)]
    if not cfg then
        return
    end

    local count = bumpRate(owner, cfg.key, cfg.window)

    if count >= cfg.limit * ENTITY_HARD_MULT then
        CancelEvent()

        if not floodFlagged[owner] then
            floodFlagged[owner] = true
            ringPurge(owner)
            crashDrop(owner, 'Entity spawn flood',
                format('%d client-owned %s creations within %dms', count, cfg.key, cfg.window))
        end
    end
end)

AddEventHandler('entityCreated', function(entity)
    local owner = GetEntityOwner(entity)

    if not owner or owner <= 0 then
        return
    end

    if not ENTITY_LIMITS[GetEntityType(entity)] then
        return
    end

    ringPush(owner, entity)
end)

AddEventHandler('explosionEvent', function(sender, ev)
    if not ev then
        return
    end

    local src = tonumber(sender)
    if not src or src <= 0 then
        return
    end

    local exType = ev.explosionType
    local px, py, pz = ev.posX or 0, ev.posY or 0, ev.posZ or 0

    local forged = type(exType) ~= 'number'
        or exType < 0
        or exType > MAX_EXPLOSION_TYPE
        or px ~= px or py ~= py or pz ~= pz
        or abs(px) > MAX_WORLD_COORD
        or abs(py) > MAX_WORLD_COORD
        or abs(pz) > MAX_WORLD_COORD

    if forged then
        CancelEvent()
        crashDrop(src, 'Forged explosion packet',
            format('type=%s pos=(%s, %s, %s)', tostring(exType), tostring(px), tostring(py), tostring(pz)))
        return
    end

    local count = bumpRate(src, 'explosions', EXPLOSION_WINDOW)

    if count > EXPLOSION_LIMIT then
        CancelEvent()

        if count > EXPLOSION_LIMIT * EXPLOSION_HARD_MULT then
            crashDrop(src, 'Explosion flood',
                format('%d explosions within %dms', count, EXPLOSION_WINDOW))
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source

    rateBuckets[src]  = nil
    entityRings[src]  = nil
    floodFlagged[src] = nil
end)

print('Successfully Loaded | Protection Active | Discord Logging '
    .. (WEBHOOK_URL == '' and 'Off' or 'On'))

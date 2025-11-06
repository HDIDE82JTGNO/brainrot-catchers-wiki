--!strict

local ContentProvider = game:GetService("ContentProvider")

local AnimationPreloader = {}
AnimationPreloader.__index = AnimationPreloader

export type AnimationPreloaderType = typeof(AnimationPreloader)

-- Core trainer animations
local TRAINER_ANIMS: {[string]: string} = {
    SendOut = "78441710358556",
    Clap = "74642253257972",
    Ashamed = "120749917990524",
    Sad = "122010512980716",
}

local function normalizeId(id: string): string
    if string.find(id, "rbxassetid://", 1, true) then
        return id
    end
    return "rbxassetid://" .. id
end

local function toAnimations(ids: {string}): {Instance}
    local list: {Instance} = {}
    for _, id in ipairs(ids) do
        local anim = Instance.new("Animation")
        anim.AnimationId = normalizeId(id)
        table.insert(list, anim)
    end
    return list
end

local function preloadInstances(instances: {Instance})
    if #instances == 0 then return end
    local ok, err = pcall(function()
        if ContentProvider.PreloadAsync then
            ContentProvider:PreloadAsync(instances)
        else
            -- Legacy fallback: Preload each asset id (deprecated in modern API)
            for _, inst in ipairs(instances) do
                pcall(function()
                    (ContentProvider :: any):Preload(inst)
                end)
            end
        end
    end)
    if not ok then
        warn("[AnimationPreloader] Preload failed:", err)
    end
    -- Cleanup temp Animation instances
    for _, inst in ipairs(instances) do
        inst:Destroy()
    end
end

function AnimationPreloader:PreloadCore()
    local ids: {string} = {}
    -- Trainer
    for _, id in pairs(TRAINER_ANIMS) do
        table.insert(ids, id)
    end
    -- NPC emotions
    local ok, NPCAnimations = pcall(function()
        return require(script.Parent.NPCAnimations)
    end)
    if ok and NPCAnimations and NPCAnimations.GetAllAssetIds then
        local list = NPCAnimations:GetAllAssetIds()
        for _, id in ipairs(list) do
            table.insert(ids, id)
        end
    end
    -- Dedupe
    local seen: {[string]: boolean} = {}
    local deduped: {string} = {}
    for _, id in ipairs(ids) do
        local norm = normalizeId(id)
        if not seen[norm] then
            seen[norm] = true
            table.insert(deduped, norm)
        end
    end
    preloadInstances(toAnimations(deduped))
end

return AnimationPreloader



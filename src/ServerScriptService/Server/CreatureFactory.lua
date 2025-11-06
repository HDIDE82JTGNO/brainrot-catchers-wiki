--!strict
-- CreatureFactory.lua
-- Server-side utility to create fully initialized creature instances consistently

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Creatures = require(ReplicatedStorage.Shared.Creatures)
local Moves = require(ReplicatedStorage.Shared.Moves)
local StatCalc = require(ReplicatedStorage.Shared.StatCalc)
local Natures = require(ReplicatedStorage.Shared.Natures)

local CreatureFactory = {}

-- Normalize a list of move refs (strings or move tables) to valid move name strings present in Moves
local function normalizeMoves(moveRefs: {any}): {string}
    local names: {string} = {}
    for _, mv in ipairs(moveRefs or {}) do
        if type(mv) == "string" then
            if Moves[mv] then
                table.insert(names, mv)
            else
                -- Attempt case-insensitive match as fallback
                local lower = string.lower(mv)
                for name, _ in pairs(Moves) do
                    if string.lower(name) == lower then
                        table.insert(names, name)
                        break
                    end
                end
            end
        elseif type(mv) == "table" then
            -- Try to find the move name by table identity
            for name, data in pairs(Moves) do
                if data == mv then
                    table.insert(names, name)
                    break
                end
            end
        end
        if #names >= 4 then break end
    end
    return names
end

-- Build starting moves from Learnset at a given level (4 most recent moves)
local function buildStartingMovesFromLearnset(learnset: {[number]: {string}}?, level: number): ({string}, {[string]: boolean})
    local current: {string} = {}
    local learned: {[string]: boolean} = {}
    if not learnset or not level then return current, learned end

    local all: { { lvl: number, move: string } } = {}
    for lvl, mvList in pairs(learnset) do
        for _, mv in ipairs(mvList) do
            table.insert(all, { lvl = lvl, move = mv })
        end
    end
    table.sort(all, function(a, b)
        if a.lvl == b.lvl then return a.move < b.move end
        return a.lvl < b.lvl
    end)

    local recent: {string} = {}
    for i = #all, 1, -1 do
        local e = all[i]
        if e.lvl <= level and not table.find(recent, e.move) then
            if Moves[e.move] then
                table.insert(recent, e.move)
            end
            if #recent == 4 then break end
        end
    end
    for i = #recent, 1, -1 do
        table.insert(current, recent[i])
        learned[recent[i]] = true
    end
    if #current < 4 then
        for _, e in ipairs(all) do
            if e.lvl <= level and not learned[e.move] and Moves[e.move] then
                table.insert(current, e.move)
                learned[e.move] = true
                if #current == 4 then break end
            end
        end
    end
    return current, learned
end

-- Create a creature instance from a foe battle creature, preserving battle-generated fields
function CreatureFactory.CreateFromFoe(foe: any): any
    local name = foe.Name
    local level = foe.Level or 1
    local ivs = foe.IVs or {
        HP = math.random(0, 31),
        Attack = math.random(0, 31),
        Defense = math.random(0, 31),
        Speed = math.random(0, 31),
    }
local stats, maxStats = StatCalc.ComputeStats(name, level, ivs, foe.Nature)

    local fc = (Creatures[name] and tonumber(Creatures[name].FemaleChance)) or 50
    local computedGender = (math.random(1, 100) <= fc) and 1 or 0
    local instance = {
        Name = name,
        Level = level,
        Gender = (foe.Gender == 0 or foe.Gender == 1) and foe.Gender or computedGender,
        Shiny = foe.Shiny == true,
        WeightKg = foe.WeightKg,
        Nature = foe.Nature or Natures.GetRandomNature(),
        IVs = ivs,
        Stats = stats,
        MaxStats = maxStats,
        CurrentHP = foe.CurrentHP or 100,
        CatchData = { CaughtWhen = os.time(), CaughtBy = tostring(foe.CaughtBy or "server") },
        TradeLocked = false,
        OT = foe.OT,
    }

    -- Moves: prefer foe.CurrentMoves (normalize), else learnset
    local moveNames: {string} = {}
    if type(foe.CurrentMoves) == "table" and #foe.CurrentMoves > 0 then
        moveNames = normalizeMoves(foe.CurrentMoves)
    end
    if #moveNames == 0 then
        local def = Creatures[name]
        if def and def.Learnset then
            moveNames = select(1, buildStartingMovesFromLearnset(def.Learnset, level))
        end
    end
    instance.CurrentMoves = moveNames
    local learned: {[string]: boolean} = {}
    for _, mn in ipairs(moveNames) do learned[mn] = true end
    instance.LearnedMoves = learned

    return instance
end

return CreatureFactory



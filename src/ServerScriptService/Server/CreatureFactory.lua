--!strict
-- CreatureFactory.lua
-- Server-side utility to create fully initialized creature instances consistently

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Creatures = require(ReplicatedStorage.Shared.Creatures)
local Moves = require(ReplicatedStorage.Shared.Moves)
local StatCalc = require(ReplicatedStorage.Shared.StatCalc)
local Natures = require(ReplicatedStorage.Shared.Natures)
local Abilities = require(ReplicatedStorage.Shared.Abilities)
local GameConfig = require(ServerScriptService.Server.GameData.Config)

local CreatureFactory = {}

local function rollWeightKg(baseWeight: number?): number?
	if type(baseWeight) ~= "number" or baseWeight <= 0 then
		return nil
	end
	local lower = math.max(1, math.floor(baseWeight * 0.7))
	local upper = math.max(lower, math.ceil(baseWeight * 1.3))
	return math.random(lower, upper)
end

local function simpleStat(base: number, level: number, iv: number): number
	return math.floor(((2 * base + iv) * level / 100) + level + 10)
end

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

    -- Assign ability if not provided
    if foe and foe.Ability then
        instance.Ability = foe.Ability
    else
        instance.Ability = Abilities.SelectAbility(name, false)
    end

    return instance
end

function CreatureFactory.CreateFromInfo(info: any)
	if type(info) ~= "table" or type(info.Creature) ~= "string" then
		return "Invalid creature info."
	end

	local creatureDef = Creatures[info.Creature]
	if not creatureDef then
		return "Creature: " .. tostring(info.Creature) .. " not found."
	end

	local level = tonumber(info.Level) or 1
	local tempCurrentMoves = {}
	if creatureDef.LearnableMoves then
		if creatureDef.LearnableMoves[1] then tempCurrentMoves[1] = creatureDef.LearnableMoves[1] end
		if level >= 10 and creatureDef.LearnableMoves[2] then tempCurrentMoves[2] = creatureDef.LearnableMoves[2] end
		if level >= 25 and creatureDef.LearnableMoves[3] then tempCurrentMoves[3] = creatureDef.LearnableMoves[3] end
		if level >= 45 and creatureDef.LearnableMoves[4] then tempCurrentMoves[4] = creatureDef.LearnableMoves[4] end
	end

	local tempIVs = {}
	local tempStats = {}
	for statName, base in pairs(creatureDef.BaseStats or {}) do
		local iv = math.random(0, 31)
		tempIVs[statName] = iv
		tempStats[statName] = simpleStat(base, level, iv)
	end

	local gender
	if info.Gender == 0 or info.Gender == 1 then
		gender = info.Gender
	else
		local fc = tonumber(creatureDef.FemaleChance) or 50
		gender = (math.random(1, 100) <= fc) and 1 or 0
	end

	local isShiny = false
	if info.Shiny == true then
		isShiny = true
	elseif math.random(1, GameConfig.SHINY_CHANCE) == 1 then
		isShiny = true
	end

	local natureName = info.Nature or Natures.GetRandomNature()
	local statsWithNature = Natures.ApplyNatureModifiers(tempStats, natureName)

	local caughtBy = info.CaughtBy
	if not caughtBy and typeof(info.OT) == "number" then
		local ok, name = pcall(function()
			return Players:GetNameFromUserIdAsync(info.OT)
		end)
		if ok and name and name ~= "" then
			caughtBy = name
		end
	end
	caughtBy = caughtBy or "Unknown"

	local catchData = {
		CaughtWhen = os.time(),
		CaughtBy = caughtBy,
	}

	local finalCreation = {
		DexNumber = creatureDef.DexNumber,
		Name = creatureDef.Name,
		Description = creatureDef.Description,
		Type = creatureDef.Type,
		-- Assign a species ability (allow override via info.Ability)
		Ability = info.Ability or Abilities.SelectAbility(creatureDef.Name, false),
		Stats = statsWithNature,
		IVs = tempIVs,
		LearnableMoves = creatureDef.LearnableMoves,
		CurrentMoves = tempCurrentMoves,
		Shiny = isShiny,
		Level = level,
		Gender = gender,
		OT = info.OT,
		TradeLocked = (info.TradeLocked == true),
		Nature = natureName,
		CatchData = catchData,
		WeightKg = rollWeightKg(creatureDef.BaseWeightKg),
	}

	return finalCreation
end

CreatureFactory.RollWeightKg = rollWeightKg

return CreatureFactory



--!strict
--[[
	XPManager.lua
	Manages experience points, leveling, and evolution
	Implements Pokémon-style XP system with proper formulas
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DBG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DBG"))
local BattleTypes = require(ReplicatedStorage.Shared.BattleTypes)
local CreaturesModule = require(ReplicatedStorage.Shared.Creatures)
local StatCalc = require(ReplicatedStorage.Shared.StatCalc)
local Config = require(ServerScriptService.Server.GameData.Config)
local Events = ReplicatedStorage:WaitForChild("Events", 5)
local Request = Events and Events:FindFirstChild("Request")

type Creature = BattleTypes.Creature

local XPManager = {}

-- Constants
local MAX_LEVEL = 100
local MAX_EXPERIENCE = 1000000 -- Maximum experience cap

--[[
	Calculates total XP needed for a given level using Medium Fast growth rate
	Formula: level^3
	@param level The target level
	@return number Total XP needed
]]
function XPManager.CalculateXPForLevel(level: number): number
	if level <= 1 then
		return 0
	end
	-- Medium Fast: n^3
	return math.floor(level * level * level)
end

--[[
	Calculates XP progress within current level
	@param creature The creature
	@return currentXP: number, neededXP: number, progress: number (0-1)
]]
function XPManager.CalculateXPProgress(creature: Creature): (number, number, number)
	if not creature or not creature.Level then
		return 0, 100, 0
	end
	
	local currentLevel = creature.Level
	local currentTotalXP = creature.Experience or XPManager.CalculateXPForLevel(currentLevel)
	
	local xpForCurrentLevel = XPManager.CalculateXPForLevel(currentLevel)
	local xpForNextLevel = XPManager.CalculateXPForLevel(currentLevel + 1)
	
	local currentXP = currentTotalXP - xpForCurrentLevel
	local neededXP = xpForNextLevel - xpForCurrentLevel
	
	local progress = neededXP > 0 and (currentXP / neededXP) or 0
	progress = math.clamp(progress, 0, 1)
	
	return currentXP, neededXP, progress
end

--[[
	Initializes XP data for a creature
	@param creature The creature to initialize
]]
function XPManager.InitializeCreatureXP(creature: Creature)
	if not creature.Level then
		creature.Level = 1
	end
	
	-- Initialize total experience (Experience field holds total XP gained)
	if not creature.Experience then
		-- If we have XPProgress stored (legacy format), convert it to Experience
		if creature.XPProgress and creature.XPProgress > 0 then
			local xpForCurrentLevel = XPManager.CalculateXPForLevel(creature.Level)
			local xpForNextLevel = XPManager.CalculateXPForLevel(creature.Level + 1)
			local xpRange = xpForNextLevel - xpForCurrentLevel
			local xpWithinLevel = math.floor(xpRange * (creature.XPProgress / 100))
			creature.Experience = xpForCurrentLevel + xpWithinLevel
			print("[XP] Initialized Experience from XPProgress:", creature.XPProgress, "% → Total XP:", creature.Experience)
		else
			creature.Experience = XPManager.CalculateXPForLevel(creature.Level)
			print("[XP] Initialized Experience to base level XP:", creature.Experience)
		end
	end
	
	-- Legacy support: XPProgress is now calculated on-the-fly from Experience
	-- but we keep it for backward compatibility
	if not creature.XPProgress then
		local _, _, progress = XPManager.CalculateXPProgress(creature)
		creature.XPProgress = math.floor(progress * 100)
	end
end

--[[
	Awards XP to a creature and handles leveling
	@param creature The creature receiving XP
	@param xpAmount The amount of XP to award (raw XP value)
	@return levelsGained: number, didEvolve: boolean, newName: string?
]]
function XPManager.AwardXP(creature: Creature, xpAmount: number): (number, boolean, string?)
	if not creature or xpAmount <= 0 then
		return 0, false, nil
	end
	
	-- Initialize XP if needed
	XPManager.InitializeCreatureXP(creature)
	
	-- Check if at max level
	if creature.Level >= MAX_LEVEL then
		return 0, false, nil
	end
	
	-- Get current HP percentage to preserve after leveling
	local hpPercentage = 1.0
	if creature.MaxStats and creature.MaxStats.HP and creature.MaxStats.HP > 0 then
		hpPercentage = creature.Stats.HP / creature.MaxStats.HP
	end
	
	-- Add XP to total experience
	local currentExperience = creature.Experience or XPManager.CalculateXPForLevel(creature.Level)
	local newExperience = math.min(MAX_EXPERIENCE, currentExperience + xpAmount)
	creature.Experience = newExperience
	
	print("[XP] Awarding", xpAmount, "XP to", creature.Name)
	print("[XP] Current XP:", currentExperience, "→ New XP:", newExperience)
	print("[XP] Current Level:", creature.Level)
	
    -- Reset per-award learned moves accumulator
    creature._MovesLearnedRecently = {}

    -- Check for level ups
	local levelsGained = 0
	local creatureData = CreaturesModule[creature.Name]
	
	while creature.Level < MAX_LEVEL do
		local xpNeededForNextLevel = XPManager.CalculateXPForLevel(creature.Level + 1)
		print("[XP] Checking level-up: Experience", creature.Experience, "vs needed", xpNeededForNextLevel)
		
		if creature.Experience >= xpNeededForNextLevel then
			creature.Level = creature.Level + 1
			levelsGained = levelsGained + 1
			print("[XP] ✓ Leveled up to", creature.Level, "! Total levels gained:", levelsGained)
			
			-- Recalculate stats for new level
			if creatureData and creatureData.BaseStats then
				local newStats, newMaxStats = StatCalc.ComputeStats(
					creature.Name,
					creature.Level,
					creature.IVs,
					creature.Nature
				)
				
				-- Preserve HP percentage
				creature.Stats = newStats
				creature.MaxStats = newMaxStats
				creature.Stats.HP = math.max(1, math.floor(newMaxStats.HP * hpPercentage))
			end
			
			-- Learnset processing: learn moves for this level
			if creatureData and creatureData.Learnset then
				creature.CurrentMoves = creature.CurrentMoves or {}
				creature.LearnedMoves = creature.LearnedMoves or {}
                local movesAtLevel = creatureData.Learnset[creature.Level]
				if movesAtLevel and #movesAtLevel > 0 then
					for _, moveName in ipairs(movesAtLevel) do
						if not creature.LearnedMoves[moveName] then
							-- If fewer than 4 moves, auto learn
							if #creature.CurrentMoves < 4 then
								table.insert(creature.CurrentMoves, moveName)
								creature.LearnedMoves[moveName] = true
                                -- Track learned move for messaging
                                table.insert(creature._MovesLearnedRecently, moveName)
							else
								-- Store pending move to learn (UI will prompt player)
								creature.PendingMoveToLearn = moveName
							end
						end
					end
				end
			end
		else
			print("[XP] No level-up (not enough XP)")
			break
		end
	end
	
	print("[XP] Final result - Levels gained:", levelsGained, "Final level:", creature.Level)
	
	-- Update XPProgress for UI (0-100 scale within current level)
	local _, _, progress = XPManager.CalculateXPProgress(creature)
	creature.XPProgress = math.floor(progress * 100)
	print("[XP] XP Progress:", creature.XPProgress, "%")
	
	-- Check for evolution (only after all levels gained)
	local didEvolve, newName = XPManager.CheckEvolution(creature)
	
	return levelsGained, didEvolve, newName
end

--[[
	Checks if a creature should evolve
	@param creature The creature to check
	@return shouldEvolve: boolean, evolvedName: string?
]]
function XPManager.CheckEvolution(creature: Creature): (boolean, string?)
	DBG:print("[XP] CheckEvolution - Checking:", creature and creature.Name or "nil")
	if not creature or not creature.Name then
		DBG:print("[XP] CheckEvolution - Failed: No creature or name")
		return false, nil
	end
	
	local creatureData = CreaturesModule[creature.Name]
	if not creatureData then
		DBG:print("[XP] CheckEvolution - Failed: No creature data for", creature.Name)
		return false, nil
	end
	
	DBG:print("[XP] CheckEvolution - Creature:", creature.Name, "Level:", creature.Level)
	DBG:print("[XP] CheckEvolution - EvolutionLevel:", creatureData.EvolutionLevel, "EvolvesInto:", creatureData.EvolvesInto)
	
	-- Check if this creature has an evolution
	if not creatureData.EvolutionLevel or not creatureData.EvolvesInto then
		DBG:print("[XP] CheckEvolution - Failed: No EvolutionLevel or EvolvesInto")
		return false, nil
	end
	
	-- Check if the creature has reached the evolution level
	if not creature.Level or creature.Level < creatureData.EvolutionLevel then
		DBG:print("[XP] CheckEvolution - Failed: Level check failed. CreatureLevel:", creature.Level, "EvolutionLevel:", creatureData.EvolutionLevel)
		return false, nil
	end
	
	DBG:print("[XP] CheckEvolution - SUCCESS! Can evolve into:", creatureData.EvolvesInto)
	return true, creatureData.EvolvesInto
end

--[[
	Evolves a creature into its evolved form
	@param creature The creature to evolve
	@return success: boolean, evolvedName: string?
]]
function XPManager.EvolveCreature(creature: Creature): (boolean, string?)
	if not creature or not creature.Name then
		return false, nil
	end
	
	local creatureData = CreaturesModule[creature.Name]
	if not creatureData then
		return false, nil
	end
	
	-- Check if this creature can evolve
	if not creatureData.EvolutionLevel or not creatureData.EvolvesInto then
		return false, nil
	end
	
	-- Check if the creature has reached the evolution level
	-- Safety check: ensure both Level and EvolutionLevel are numbers before comparing
	if not creature.Level or type(creature.Level) ~= "number" or 
	   not creatureData.EvolutionLevel or type(creatureData.EvolutionLevel) ~= "number" or
	   creature.Level < creatureData.EvolutionLevel then
		return false, nil
	end
	
	-- Get the evolved creature data
	local evolvedCreatureData = CreaturesModule[creatureData.EvolvesInto]
	if not evolvedCreatureData then
		return false, nil
	end
	
	-- Store old data
	local oldName = creature.Name
	local oldNickname = creature.Nickname
	
	-- Transform the creature
	creature.Name = creatureData.EvolvesInto
	creature.DexNumber = evolvedCreatureData.DexNumber
	creature.Description = evolvedCreatureData.Description
	creature.Type = evolvedCreatureData.Type
	creature.BaseStats = evolvedCreatureData.BaseStats
	creature.LearnableMoves = evolvedCreatureData.LearnableMoves
	
	-- Recalculate stats with new base stats
    local newStats, newMaxStats = StatCalc.ComputeStats(
		creature.Name,
		creature.Level,
		creature.IVs,
		creature.Nature
	)
	
	-- Preserve current HP percentage
	local hpPercentage = creature.Stats.HP / creature.MaxStats.HP
	creature.Stats = newStats
	creature.MaxStats = newMaxStats
	creature.Stats.HP = math.floor(newMaxStats.HP * hpPercentage)
	
	-- Keep nickname if it was the old name
	if not oldNickname or oldNickname == oldName then
		creature.Nickname = creature.Name
	end
	
	return true, creature.Name
end

--[[
	Calculates base experience yield for a creature dynamically from its stats
	Formula based on Pokémon: sum of base stats, scaled appropriately
	Generally: BaseExpYield ≈ (sum of base stats) / 3 to 4
	
	@param creatureName The creature's name
	@return number Base experience yield
]]
function XPManager.GetBaseExperienceYield(creatureName: string): number
	if not creatureName then
		return 60 -- default fallback
	end
	
	local creatureData = CreaturesModule[creatureName]
	if not creatureData or not creatureData.BaseStats then
		return 60 -- default fallback
	end
	
	-- Sum all base stats
	local statSum = 0
	for statName, statValue in pairs(creatureData.BaseStats) do
		statSum = statSum + statValue
	end
	
	-- Calculate base experience yield
	-- Formula: (statSum / 4) rounded
	-- This gives reasonable values: 
	--   - 200 total stats → 50 base exp
	--   - 300 total stats → 75 base exp
	--   - 400 total stats → 100 base exp
	--   - 500 total stats → 125 base exp
	--   - 600 total stats → 150 base exp (legendaries)
	local baseExpYield = math.floor(statSum / 4)
	
	-- Ensure minimum of 30 and maximum of 250
	return math.clamp(baseExpYield, 30, 250)
end

--[[
	Calculates XP yield from defeating a creature using Pokémon Gen 5+ formula
	Formula: (a * t * b * e * L * p * f * v) / (7 * s)
	Where:
		a = 1.5 if trainer battle, 1 if wild
		t = 1.5 if traded (not original trainer), 1 otherwise
		b = base experience yield of defeated creature
		e = 1.5 if holding Lucky Egg, 1 otherwise
		L = level of defeated creature
		p = 1 (O-Power/Roto Boost, not implemented)
		f = 1 (affection bonus, not implemented)
		v = 1 (can evolve but hasn't, not implemented)
		s = number of non-fainted creatures that participated
	
	@param defeatedCreature The defeated creature
	@param receivingCreature The creature receiving XP
	@param isTrainerBattle Whether this was a trainer battle
	@param participantCount Number of creatures that participated (when EXP Share is on, this should be total non-fainted party members)
	@param isShared DEPRECATED: This parameter is no longer used. Participant count should be passed directly via participantCount.
	@return number XP amount
]]
function XPManager.CalculateXPYield(
	defeatedCreature: Creature,
	receivingCreature: Creature,
	isTrainerBattle: boolean,
	participantCount: number?,
	isShared: boolean?
): number
	if not defeatedCreature or not defeatedCreature.Level then
		return 0
	end
	
	-- a: Trainer bonus (1.5 for trainer battles, 1 for wild)
	local a = isTrainerBattle and 1.5 or 1.0
	
	-- t: Trade bonus (not original trainer) - not implemented yet, always 1
	local t = 1.0
	
	-- b: Base experience yield
	local b = XPManager.GetBaseExperienceYield(defeatedCreature.Name)
	
	-- e: Lucky Egg bonus - check if holding lucky egg (not implemented yet, always 1)
	local e = 1.0
	-- TODO: When items are implemented, check receivingCreature.HeldItem
	
	-- L: Level of defeated creature
	local L = defeatedCreature.Level
	
	-- p: Power boost (O-Power/Roto Boost) - not implemented, always 1
	local p = 1.0
	
	-- f: Affection bonus - not implemented, always 1
	local f = 1.0
	
	-- v: Evolution bonus (can evolve but hasn't) - not implemented, always 1
	local v = 1.0
	
	-- s: Number of participants (participantCount should already account for EXP Share)
	-- Note: isShared parameter is deprecated and ignored
	local s = participantCount or 1
	
	-- Calculate XP using Pokémon formula
	local xp = math.floor((a * t * b * e * L * p * f * v) / (7 * s))

	-- Apply global XP multiplier from Config
	local mult = (Config and Config.XP_MULTIPLIER) or 1.0
	xp = math.floor(xp * mult)
	
	return math.max(1, xp)
end

return XPManager

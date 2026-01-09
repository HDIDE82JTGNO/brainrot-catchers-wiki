--!strict
--[[
	StatStages.lua
	Manages in-battle stat stage modifications (+1 to +6, -1 to -6)
	Based on Pokemon-style stat stage mechanics
]]

local StatStages = {}

-- Constants
StatStages.MIN_STAGE = -6
StatStages.MAX_STAGE = 6

-- Stat stage multipliers for regular stats (Attack, Defense, Speed)
-- Stage -6 to +6 maps to 2/8 to 8/2
local STAT_MULTIPLIERS = {
	[-6] = 2/8,  -- 0.25
	[-5] = 2/7,  -- 0.286
	[-4] = 2/6,  -- 0.333
	[-3] = 2/5,  -- 0.4
	[-2] = 2/4,  -- 0.5
	[-1] = 2/3,  -- 0.667
	[0] = 2/2,   -- 1.0
	[1] = 3/2,   -- 1.5
	[2] = 4/2,   -- 2.0
	[3] = 5/2,   -- 2.5
	[4] = 6/2,   -- 3.0
	[5] = 7/2,   -- 3.5
	[6] = 8/2,   -- 4.0
}

-- Accuracy/Evasion stage multipliers (different formula)
-- Stage -6 to +6 maps to 3/9 to 9/3
local ACCURACY_MULTIPLIERS = {
	[-6] = 3/9,  -- 0.333
	[-5] = 3/8,  -- 0.375
	[-4] = 3/7,  -- 0.429
	[-3] = 3/6,  -- 0.5
	[-2] = 3/5,  -- 0.6
	[-1] = 3/4,  -- 0.75
	[0] = 3/3,   -- 1.0
	[1] = 4/3,   -- 1.333
	[2] = 5/3,   -- 1.667
	[3] = 6/3,   -- 2.0
	[4] = 7/3,   -- 2.333
	[5] = 8/3,   -- 2.667
	[6] = 9/3,   -- 3.0
}

-- Valid stat names for stage modification
StatStages.BATTLE_STATS = {
	"Attack",
	"Defense", 
	"SpecialAttack",
	"SpecialDefense",
	"Speed",
	"Accuracy",
	"Evasion",
	"CritStage",
}

export type StatStagesTable = {
	Attack: number?,
	Defense: number?,
	SpecialAttack: number?,
	SpecialDefense: number?,
	Speed: number?,
	Accuracy: number?,
	Evasion: number?,
	CritStage: number?,
}

--[[
	Creates a new stat stages table with all stages at 0
	@return StatStagesTable Empty stat stages table
]]
function StatStages.Create(): StatStagesTable
	return {
		Attack = 0,
		Defense = 0,
		SpecialAttack = 0,
		SpecialDefense = 0,
		Speed = 0,
		Accuracy = 0,
		Evasion = 0,
		CritStage = 0,
	}
end

--[[
	Ensures a creature has a valid StatStages table
	@param creature The creature to check
	@return StatStagesTable The creature's stat stages (created if missing)
]]
function StatStages.EnsureCreatureHasStages(creature: any): StatStagesTable
	if not creature then
		return StatStages.Create()
	end
	
	if not creature.StatStages then
		creature.StatStages = StatStages.Create()
	end
	
	return creature.StatStages
end

--[[
	Gets the current stage for a stat
	@param creature The creature
	@param statName The stat name (Attack, Defense, Speed, Accuracy, Evasion)
	@return number The current stage (-6 to +6)
]]
function StatStages.GetStage(creature: any, statName: string): number
	if not creature or not creature.StatStages then
		return 0
	end
	
	return creature.StatStages[statName] or 0
end

--[[
	Gets the multiplier for a given stat stage
	@param stage The stage value (-6 to +6)
	@param isAccuracyOrEvasion Whether this is for accuracy/evasion
	@return number The multiplier value
]]
function StatStages.GetMultiplier(stage: number, isAccuracyOrEvasion: boolean?): number
	-- Clamp stage to valid range
	stage = math.clamp(stage, StatStages.MIN_STAGE, StatStages.MAX_STAGE)
	
	if isAccuracyOrEvasion then
		return ACCURACY_MULTIPLIERS[stage] or 1
	else
		return STAT_MULTIPLIERS[stage] or 1
	end
end

--[[
	Applies stat stage multiplier to a base stat value
	@param baseStat The base stat value
	@param stage The current stage (-6 to +6)
	@param isAccuracyOrEvasion Whether this is for accuracy/evasion
	@return number The modified stat value
]]
function StatStages.ApplyStage(baseStat: number, stage: number, isAccuracyOrEvasion: boolean?): number
	local multiplier = StatStages.GetMultiplier(stage, isAccuracyOrEvasion)
	return math.floor(baseStat * multiplier)
end

--[[
	Modifies a stat stage by a given amount
	@param creature The creature
	@param statName The stat name
	@param stages The number of stages to add (can be negative)
	@return number, number The new stage value and actual change applied
]]
function StatStages.ModifyStage(creature: any, statName: string, stages: number): (number, number)
	if not creature then
		return 0, 0
	end
	
	-- Ensure creature has stat stages
	StatStages.EnsureCreatureHasStages(creature)
	
	local currentStage = creature.StatStages[statName] or 0
	local newStage = math.clamp(currentStage + stages, StatStages.MIN_STAGE, StatStages.MAX_STAGE)
	local actualChange = newStage - currentStage
	
	creature.StatStages[statName] = newStage
	
	return newStage, actualChange
end

--[[
	Sets a stat stage to a specific value
	@param creature The creature
	@param statName The stat name
	@param stage The stage value to set
	@return number The new stage value (clamped)
]]
function StatStages.SetStage(creature: any, statName: string, stage: number): number
	if not creature then
		return 0
	end
	
	-- Ensure creature has stat stages
	StatStages.EnsureCreatureHasStages(creature)
	
	local newStage = math.clamp(stage, StatStages.MIN_STAGE, StatStages.MAX_STAGE)
	creature.StatStages[statName] = newStage
	
	return newStage
end

--[[
	Resets all stat stages to 0 for a creature
	@param creature The creature
]]
function StatStages.ResetAll(creature: any)
	if not creature then
		return
	end
	
	creature.StatStages = StatStages.Create()
end

--[[
	Checks if a stat can be raised further
	@param creature The creature
	@param statName The stat name
	@return boolean True if the stat can be raised
]]
function StatStages.CanRaise(creature: any, statName: string): boolean
	local currentStage = StatStages.GetStage(creature, statName)
	return currentStage < StatStages.MAX_STAGE
end

--[[
	Checks if a stat can be lowered further
	@param creature The creature
	@param statName The stat name
	@return boolean True if the stat can be lowered
]]
function StatStages.CanLower(creature: any, statName: string): boolean
	local currentStage = StatStages.GetStage(creature, statName)
	return currentStage > StatStages.MIN_STAGE
end

--[[
	Gets a message describing a stat change
	@param creatureName The creature's name
	@param statName The stat name
	@param stageChange The amount of change
	@param actualChange The actual change that was applied (after clamping)
	@return string The message to display
]]
function StatStages.GetChangeMessage(creatureName: string, statName: string, stageChange: number, actualChange: number): string
	if actualChange == 0 then
		if stageChange > 0 then
			return creatureName .. "'s " .. statName .. " won't go any higher!"
		else
			return creatureName .. "'s " .. statName .. " won't go any lower!"
		end
	end
	
	local absChange = math.abs(actualChange)
	local direction = actualChange > 0 and "rose" or "fell"
	
	-- Sharply/drastically modifiers based on stage change
	local modifier = ""
	if absChange == 2 then
		modifier = actualChange > 0 and "sharply " or "harshly "
	elseif absChange >= 3 then
		modifier = "drastically "
	end
	
	return creatureName .. "'s " .. statName .. " " .. modifier .. direction .. "!"
end

--[[
	Copies stat stages from one creature to another (for transforms, etc.)
	@param source The source creature
	@param target The target creature
]]
function StatStages.CopyStages(source: any, target: any)
	if not source or not target then
		return
	end
	
	StatStages.EnsureCreatureHasStages(source)
	target.StatStages = table.clone(source.StatStages)
end

--[[
	Gets all stat stages for a creature as a table (for client display)
	@param creature The creature
	@return StatStagesTable The stat stages table
]]
function StatStages.GetAllStages(creature: any): StatStagesTable
	if not creature or not creature.StatStages then
		return StatStages.Create()
	end
	
	return table.clone(creature.StatStages)
end

--[[
	Gets the effective stat value considering stat stages
	@param creature The creature
	@param statName The stat name (Attack, Defense, Speed)
	@return number The effective stat value
]]
function StatStages.GetEffectiveStat(creature: any, statName: string): number
	if not creature or not creature.Stats then
		return 1
	end
	
	local baseStat = creature.Stats[statName] or 1
	local stage = StatStages.GetStage(creature, statName)
	
	return StatStages.ApplyStage(baseStat, stage, false)
end

--[[
	Calculates accuracy check with stat stages
	@param attacker The attacking creature
	@param defender The defending creature  
	@param baseAccuracy The move's base accuracy (0-100, or nil for always hit)
	@return number The final accuracy percentage
]]
function StatStages.CalculateAccuracy(attacker: any, defender: any, baseAccuracy: number?): number
	if not baseAccuracy or baseAccuracy == 0 then
		return 100 -- Always hits
	end
	
	local attackerAccuracyStage = StatStages.GetStage(attacker, "Accuracy")
	local defenderEvasionStage = StatStages.GetStage(defender, "Evasion")
	
	-- Net stage = accuracy - evasion (clamped to -6 to +6)
	local netStage = math.clamp(attackerAccuracyStage - defenderEvasionStage, StatStages.MIN_STAGE, StatStages.MAX_STAGE)
	
	local stageMultiplier = StatStages.GetMultiplier(netStage, true)
	local finalAccuracy = math.floor(baseAccuracy * stageMultiplier)
	
	return math.clamp(finalAccuracy, 0, 100)
end

return StatStages


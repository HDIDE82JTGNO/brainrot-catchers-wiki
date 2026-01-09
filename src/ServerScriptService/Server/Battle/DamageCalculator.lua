--!strict
--[[
	DamageCalculator.lua
	Pure functions for battle damage calculation
	Handles type effectiveness, STAB, critical hits, and damage formulas
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BattleTypes = require(ReplicatedStorage.Shared.BattleTypes)
local MovesModule = require(ReplicatedStorage.Shared.Moves)
local StatStages = require(ReplicatedStorage.Shared.StatStages)
local TypeChart = require(ReplicatedStorage.Shared.TypeChart)
local WeatherConfig = require(ReplicatedStorage.Shared.WeatherConfig)

local HeldItemEffects = require(script.Parent.HeldItemEffects)

type Creature = BattleTypes.Creature
type Move = BattleTypes.Move
type DamageResult = BattleTypes.DamageResult

local DamageCalculator = {}

-- Constants
local CRIT_MULTIPLIER = 1.5
-- Gen 8–9 crit rate stages:
-- 0: 1/24
-- 1: 1/8
-- 2: 1/2
-- 3+: 1
local CRIT_CHANCE = 1/24
local STAB_MULTIPLIER = 1.5
local MIN_DAMAGE = 1

-- Critical hit chance multipliers based on crit stage
-- We store absolute chances to match modern mechanics.
local CRIT_CHANCE_BY_STAGE = {
	[0] = 1/24,
	[1] = 1/8,
	[2] = 1/2,
	[3] = 1,
}

--[[
	Calculates critical hit chance based on crit stage
	@param critStage The crit stage (0-4)
	@param highCritMove Whether the move has high crit chance
	@return number The crit chance (0.0 to 1.0)
]]
local function calculateCritChance(critStage: number, highCritMove: boolean?): number
	critStage = critStage or 0
	-- High-crit moves add +1 stage in modern gens.
	if highCritMove then
		critStage += 1
	end
	critStage = math.clamp(critStage, 0, 3)
	return CRIT_CHANCE_BY_STAGE[critStage] or CRIT_CHANCE
end

--[[
	Calculates type effectiveness multiplier
	@param moveType The type of the move
	@param defenderTypes The defender's types (array)
	@return number The effectiveness multiplier
]]
local function calculateTypeEffectiveness(moveType: any, defenderTypes: {string}): number
	return TypeChart.GetMultiplier(moveType, defenderTypes)
end

--[[
	Checks if the move gets STAB (Same Type Attack Bonus)
	@param moveType The type of the move
	@param attackerTypes The attacker's types (array)
	@return number The STAB multiplier (1.5 or 1.0)
]]
local function calculateSTAB(moveType: string, attackerTypes: {string}): number
	if not moveType or not attackerTypes then
		return 1
	end
	
	for _, attackerType in ipairs(attackerTypes) do
		if attackerType == moveType then
			return STAB_MULTIPLIER
		end
	end
	
	return 1
end

local function resolveMoveTypeName(moveTypeValue: any): string?
	return TypeChart.ResolveTypeName(moveTypeValue)
end

--[[
	Determines if the attack is a critical hit
	@param attacker The attacking creature (for crit stage)
	@param highCritMove Whether the move has high crit chance
	@return boolean True if critical hit
]]
local function rollCriticalHit(attacker: Creature?, highCritMove: boolean?): boolean
	local critStage = 0
	if attacker then
		critStage = StatStages.GetStage(attacker, "CritStage") or 0
	end
	local critChance = calculateCritChance(critStage, highCritMove)
	return math.random() < critChance
end

--[[
	Applies stat stage multipliers to a stat value
	@param baseStat The base stat value
	@param stage The stat stage (-6 to +6)
	@return number The modified stat value
]]
local function applyStatStage(baseStat: number, stage: number): number
	return StatStages.ApplyStage(baseStat, stage, false)
end

--[[
	Calculates damage for a move
	@param attacker The attacking creature
	@param defender The defending creature
	@param moveNameOrData The move name or move data
	@param forceCrit Force a critical hit (optional)
	@param attackStage Attack stat stage (optional, default 0)
	@param defenseStage Defense stat stage (optional, default 0)
	@param weather Weather name or weather ID (optional, for weather multipliers)
	@return DamageResult The damage calculation result
]]
function DamageCalculator.CalculateDamage(
	attacker: Creature,
	defender: Creature,
	moveNameOrData: string | Move,
	forceCrit: boolean?,
	attackStage: number?,
	defenseStage: number?,
	weather: string | number?
): DamageResult
	-- Get move data
	local moveData: Move?
	if type(moveNameOrData) == "string" then
		moveData = MovesModule[moveNameOrData]
	else
		moveData = moveNameOrData
	end
	
	if not moveData or not moveData.BasePower then
		return {
			damage = 0,
			isCrit = false,
			effectiveness = 1,
			stab = 1,
		}
	end

	local moveTypeName = resolveMoveTypeName(moveData.Type)

    -- Determine stats and stages based on move category
    local category = moveData.Category or "Physical" -- Default to Physical if not specified
    local atkBase, defBase
    local atkStageVal, defStageVal

    if category == "Special" then
        atkBase = attacker.Stats.SpecialAttack or attacker.Stats.Attack
        defBase = defender.Stats.SpecialDefense or defender.Stats.Defense
        atkStageVal = attackStage or StatStages.GetStage(attacker, "SpecialAttack")
        defStageVal = defenseStage or StatStages.GetStage(defender, "SpecialDefense")
    else
        atkBase = attacker.Stats.Attack
        defBase = defender.Stats.Defense
        atkStageVal = attackStage or StatStages.GetStage(attacker, "Attack")
        defStageVal = defenseStage or StatStages.GetStage(defender, "Defense")
    end
	
	-- Check if this will be a crit (needed for stat stage ignoring)
	local willBeCrit = forceCrit or rollCriticalHit(attacker, moveData.Flags and moveData.Flags.highCrit)
	
	-- Critical hits ignore negative attack stages and positive defense stages
	if willBeCrit then
		atkStageVal = math.max(0, atkStageVal)
		defStageVal = math.min(0, defStageVal)
	end
	
	-- Get stats with stage modifiers
	local attackStat = applyStatStage(atkBase, atkStageVal)
	local defenseStat = applyStatStage(defBase, defStageVal)
	
	-- Apply status multipliers
	local StatusModule = require(ReplicatedStorage.Shared.Status)
	if category ~= "Special" then
		-- Gen 9: burn halves Attack for physical damage only
		local statusAttackMult = StatusModule.GetAttackMultiplier(attacker)
		attackStat = math.floor(attackStat * statusAttackMult)
	end
	
	-- Calculate base damage using Pokémon formula
	local level = attacker.Level or 1
	local levelFactor = math.floor((2 * level) / 5) + 2
	local baseDamage = math.floor((levelFactor * moveData.BasePower * (attackStat / defenseStat)) / 50) + 2
	
	-- Calculate modifiers (isCrit already determined above for stat stage ignoring)
	local isCrit = willBeCrit
	local critMultiplier = isCrit and CRIT_MULTIPLIER or 1
	
	-- Ability-based move type conversions should occur before STAB/effectiveness
	local Abilities = require(ReplicatedStorage.Shared.Abilities)
	moveTypeName = Abilities.ModifyMoveType(attacker, moveTypeName)

	local stab = calculateSTAB(moveTypeName, attacker.Type or {})
	local effectiveness = calculateTypeEffectiveness(moveTypeName, defender.Type or {})
	
    -- Apply ability overrides for immunity (e.g., Magic Eyes)
    effectiveness = Abilities.OverrideImmunity(attacker, defender, moveTypeName, effectiveness)

	-- Random factor (0.85 to 1.0)
	local randomFactor = 0.85 + (math.random() * 0.15)
	
    -- Ability damage multipliers
    local abilityMult = Abilities.DamageMultiplier(attacker, defender, moveTypeName, type(moveNameOrData)=="string" and moveNameOrData or nil)

	-- Held item multipliers
	local heldMult = HeldItemEffects.DamageMultiplier(attacker, defender, moveTypeName)

	-- Weather multipliers
	local weatherMult = 1.0
	if weather then
		local weatherId: number?
		if type(weather) == "number" then
			weatherId = weather
		elseif type(weather) == "string" then
			-- Map battle weather names to weather IDs
			-- Battle weather: "Sunlight", "Rain", "Sandstorm", "Snow"
			-- WeatherConfig names: "Harsh Sun", "Rain", "Thunderstorm", "Sandstorm", "Snow", "Snowstorm"
			if weather == "Sunlight" then
				weatherId = 2 -- Harsh Sun
			elseif weather == "Rain" then
				weatherId = 7 -- Rain (Thunderstorm also uses Rain modifiers)
			elseif weather == "Sandstorm" then
				weatherId = 9 -- Sandstorm
			elseif weather == "Snow" then
				weatherId = 4 -- Snow (Snowstorm also uses Snow modifiers)
			else
				-- Try to find by name
				local weatherData = WeatherConfig.GetWeatherByName(weather)
				if weatherData then
					weatherId = weatherData.Id
				end
			end
		end
		
		if weatherId then
			weatherMult = WeatherConfig.GetAbilityModifier(weatherId, moveTypeName) or 1.0
		end
	end

	-- Calculate final damage
	local finalDamage = baseDamage * critMultiplier * stab * effectiveness * randomFactor * abilityMult * heldMult * weatherMult
	finalDamage = math.floor(finalDamage)
	
	-- Ensure minimum damage if not immune
	if effectiveness > 0 and finalDamage < MIN_DAMAGE then
		finalDamage = MIN_DAMAGE
	end
	
	return {
		damage = finalDamage,
		isCrit = isCrit,
		effectiveness = effectiveness,
		stab = stab,
	}
end

--[[
	Checks if a move will hit based on accuracy
	@param moveNameOrData The move name or move data
	@param accuracyStage Accuracy stat stage (optional, default 0)
	@param evasionStage Evasion stat stage (optional, default 0)
	@return boolean True if the move hits
]]
function DamageCalculator.CheckAccuracy(
	moveNameOrData: string | Move,
	accuracyStage: number?,
	evasionStage: number?,
    attacker: Creature? -- Added attacker param
): boolean
	-- Get move data
    local moveData: Move?
    if type(moveNameOrData) == "string" then
        moveData = MovesModule[moveNameOrData]
    else
        moveData = moveNameOrData
    end

    if not moveData then
        return false
    end

    local Abilities = require(ReplicatedStorage.Shared.Abilities)
    local abilityName = Abilities.GetName(attacker) -- attacker needs to be passed to CheckAccuracy if we want to use it
    if abilityName and (string.lower(abilityName) == "recon flight") then
        return true
    end

    -- Moves with no accuracy always hit
	if not moveData.Accuracy or moveData.Accuracy == 0 then
		return true
	end
	
	-- Calculate accuracy with stages using StatStages module
	-- Net stage = accuracy - evasion for combined calculation
	local accStage = accuracyStage or 0
	local evaStage = evasionStage or 0
	local netStage = math.clamp(accStage - evaStage, StatStages.MIN_STAGE, StatStages.MAX_STAGE)
	
	-- Get the accuracy multiplier for the net stage
	local accuracyMultiplier = StatStages.GetMultiplier(netStage, true)
	local finalAccuracy = math.clamp(math.floor(moveData.Accuracy * accuracyMultiplier), 0, 100)
	
	-- Roll for hit
	return math.random(1, 100) <= finalAccuracy
end

--[[
	Gets the effectiveness string for display
	@param moveType The type of the move
	@param defenderTypes The defender's types
	@return string The effectiveness description
]]
function DamageCalculator.GetEffectivenessString(moveType: string, defenderTypes: {string}): string
	local effectiveness = calculateTypeEffectiveness(moveType, defenderTypes)
	
	if effectiveness == 0 then
		return "Immune"
	elseif effectiveness >= 2 then
		return "SuperEffective"
	elseif effectiveness <= 0.5 then
		return "NotVeryEffective"
	else
		return "Normal"
	end
end

--[[
	Rolls for a critical hit based on crit stage and move properties
	@param attacker The attacking creature (for crit stage)
	@param highCritMove Whether the move has high crit chance
	@return boolean True if critical hit
]]
function DamageCalculator.RollCriticalHit(attacker: Creature?, highCritMove: boolean?): boolean
	return rollCriticalHit(attacker, highCritMove)
end

return DamageCalculator

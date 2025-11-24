--!strict
--[[
	DamageCalculator.lua
	Pure functions for battle damage calculation
	Handles type effectiveness, STAB, critical hits, and damage formulas
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BattleTypes = require(ReplicatedStorage.Shared.BattleTypes)
local TypesModule = require(ReplicatedStorage.Shared.Types)
local MovesModule = require(ReplicatedStorage.Shared.Moves)

type Creature = BattleTypes.Creature
type Move = BattleTypes.Move
type DamageResult = BattleTypes.DamageResult

local DamageCalculator = {}

-- Constants
local CRIT_MULTIPLIER = 1.5
local CRIT_CHANCE = 1/16
local STAB_MULTIPLIER = 1.5
local MIN_DAMAGE = 1

--[[
	Calculates type effectiveness multiplier
	@param moveType The type of the move
	@param defenderTypes The defender's types (array)
	@return number The effectiveness multiplier
]]
local function calculateTypeEffectiveness(moveType: string, defenderTypes: {string}): number
	if not moveType or not defenderTypes then
		return 1
	end
	
	local effectiveness = 1
	local moveTypeData = TypesModule[moveType]
	
	if not moveTypeData then
		return 1
	end
	
	for _, defenderType in ipairs(defenderTypes) do
		-- Check immunity
		if moveTypeData.immuneTo then
			for _, immuneType in ipairs(moveTypeData.immuneTo) do
				if immuneType == defenderType then
					return 0
				end
			end
		end
		
		-- Check super effective
		if moveTypeData.strongTo then
			for _, strongType in ipairs(moveTypeData.strongTo) do
				if strongType == defenderType then
					effectiveness *= 2
				end
			end
		end
		
		-- Check not very effective
		if moveTypeData.weakTo then
			for _, weakType in ipairs(moveTypeData.weakTo) do
				if weakType == defenderType then
					effectiveness *= 0.5
				end
			end
		end
		
		-- Check resist
		if moveTypeData.resist then
			for _, resistType in ipairs(moveTypeData.resist) do
				if resistType == defenderType then
					effectiveness *= 0.5
				end
			end
		end
	end
	
	return effectiveness
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

--[[
	Determines if the attack is a critical hit
	@param highCritMove Whether the move has high crit chance
	@return boolean True if critical hit
]]
local function rollCriticalHit(highCritMove: boolean?): boolean
	local critChance = highCritMove and (CRIT_CHANCE * 2) or CRIT_CHANCE
	return math.random() < critChance
end

--[[
	Applies stat stage multipliers to a stat value
	@param baseStat The base stat value
	@param stage The stat stage (-6 to +6)
	@return number The modified stat value
]]
local function applyStatStage(baseStat: number, stage: number): number
	if stage == 0 then
		return baseStat
	end
	
	local multiplier
	if stage > 0 then
		multiplier = (2 + stage) / 2
	else
		multiplier = 2 / (2 + math.abs(stage))
	end
	
	return math.floor(baseStat * multiplier)
end

--[[
	Calculates damage for a move
	@param attacker The attacking creature
	@param defender The defending creature
	@param moveNameOrData The move name or move data
	@param forceCrit Force a critical hit (optional)
	@param attackStage Attack stat stage (optional, default 0)
	@param defenseStage Defense stat stage (optional, default 0)
	@return DamageResult The damage calculation result
]]
function DamageCalculator.CalculateDamage(
	attacker: Creature,
	defender: Creature,
	moveNameOrData: string | Move,
	forceCrit: boolean?,
	attackStage: number?,
	defenseStage: number?
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
	
	-- Get stats with stage modifiers
	local attackStat = applyStatStage(attacker.Stats.Attack, attackStage or 0)
	local defenseStat = applyStatStage(defender.Stats.Defense, defenseStage or 0)
	
	-- Apply status multipliers
	local StatusModule = require(ReplicatedStorage.Shared.Status)
	local statusAttackMult = StatusModule.GetAttackMultiplier(attacker)
	local statusSpeedMult = StatusModule.GetSpeedMultiplier(attacker)
	attackStat = math.floor(attackStat * statusAttackMult)
	
	-- Calculate base damage using Pokémon formula
	local level = attacker.Level or 1
	local levelFactor = math.floor((2 * level) / 5) + 2
	local baseDamage = math.floor((levelFactor * moveData.BasePower * (attackStat / defenseStat)) / 50) + 2
	
	-- Calculate modifiers
	local isCrit = forceCrit or rollCriticalHit(moveData.Flags and moveData.Flags.highCrit)
	local critMultiplier = isCrit and CRIT_MULTIPLIER or 1
	
	local stab = calculateSTAB(moveData.Type, attacker.Type or {})
	local effectiveness = calculateTypeEffectiveness(moveData.Type, defender.Type or {})
	
    -- Apply ability overrides for immunity (e.g., Magic Eyes)
    local Abilities = require(ReplicatedStorage.Shared.Abilities)
    effectiveness = Abilities.OverrideImmunity(attacker, defender, moveData.Type, effectiveness)

	-- Random factor (0.85 to 1.0)
	local randomFactor = 0.85 + (math.random() * 0.15)
	
    -- Ability damage multipliers
    local abilityMult = Abilities.DamageMultiplier(attacker, defender, moveData.Type, type(moveNameOrData)=="string" and moveNameOrData or nil)

	-- Calculate final damage
	local finalDamage = baseDamage * critMultiplier * stab * effectiveness * randomFactor * abilityMult
	finalDamage = math.floor(finalDamage)
	
	-- Ensure minimum damage if not immune
	if effectiveness > 0 and finalDamage < MIN_DAMAGE then
		finalDamage = MIN_DAMAGE
	end
	
	-- Convert effectiveness to string for client display
	local effectivenessString
	if effectiveness == 0 then
		effectivenessString = "Immune"
	elseif effectiveness >= 2 then
		effectivenessString = "SuperEffective"
	elseif effectiveness <= 0.5 then
		effectivenessString = "NotVeryEffective"
	else
		effectivenessString = "Normal"
	end
	
	return {
		damage = finalDamage,
		isCrit = isCrit,
		effectiveness = effectivenessString,
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
	
	-- Calculate accuracy with stages
	local baseAccuracy = moveData.Accuracy
	local accuracyMultiplier = 1
	local evasionMultiplier = 1
	
	if accuracyStage and accuracyStage ~= 0 then
		if accuracyStage > 0 then
			accuracyMultiplier = (3 + accuracyStage) / 3
		else
			accuracyMultiplier = 3 / (3 + math.abs(accuracyStage))
		end
	end
	
	if evasionStage and evasionStage ~= 0 then
		if evasionStage > 0 then
			evasionMultiplier = 3 / (3 + evasionStage)
		else
			evasionMultiplier = (3 + math.abs(evasionStage)) / 3
		end
	end
	
	local finalAccuracy = baseAccuracy * accuracyMultiplier * evasionMultiplier
	
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

return DamageCalculator

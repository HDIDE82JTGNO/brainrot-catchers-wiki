--!strict
--[[
	Status.lua
	Handles status condition definitions, application, and effects
	Provides utilities for status condition management in battles
]]

local Status = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StatStages = require(ReplicatedStorage.Shared.StatStages)

export type StatusType = "BRN" | "PAR" | "PSN" | "TOX" | "SLP" | "FRZ"
export type VolatileStatusType = "Confusion" | "Infatuation" | "Flinch"

export type StatusData = {
	Type: StatusType,
	TurnsRemaining: number?, -- For Sleep (1-3 turns)
	ToxicCounter: number?, -- For Badly Poisoned (increases each turn)
}

export type VolatileStatusData = {
	Confusion: number?, -- Turns remaining (1-4)
	Infatuation: boolean?,
	Flinch: boolean?, -- Single turn only
}

-- Status condition definitions
local STATUS_DEFINITIONS: {[StatusType]: {
	Color: Color3,
	StrokeColor: Color3,
	Name: string,
	IsVolatile: boolean,
}} = {
	BRN = {
		Color = Color3.fromRGB(255, 42, 42),
		StrokeColor = Color3.fromRGB(121, 0, 0),
		Name = "BRN",
		IsVolatile = false,
	},
	PAR = {
		Color = Color3.fromRGB(255, 217, 0),
		StrokeColor = Color3.fromRGB(121, 103, 0),
		Name = "PAR",
		IsVolatile = false,
	},
	PSN = {
		Color = Color3.fromRGB(153, 51, 255),
		StrokeColor = Color3.fromRGB(73, 0, 121),
		Name = "PSN",
		IsVolatile = false,
	},
	TOX = {
		Color = Color3.fromRGB(204, 0, 255),
		StrokeColor = Color3.fromRGB(97, 0, 121),
		Name = "TOX",
		IsVolatile = false,
	},
	SLP = {
		Color = Color3.fromRGB(102, 153, 255),
		StrokeColor = Color3.fromRGB(0, 73, 121),
		Name = "SLP",
		IsVolatile = false,
	},
	FRZ = {
		Color = Color3.fromRGB(0, 204, 255),
		StrokeColor = Color3.fromRGB(0, 97, 121),
		Name = "FRZ",
		IsVolatile = false,
	},
}

--[[
	Gets status definition data
	@param statusType The status type
	@return table? Status definition or nil
]]
function Status.GetDefinition(statusType: StatusType): {Color: Color3, StrokeColor: Color3, Name: string, IsVolatile: boolean}?
	return STATUS_DEFINITIONS[statusType]
end

--[[
	Checks if a creature can be inflicted with a status condition
	@param creature The creature
	@param statusType The status type to check
	@return boolean True if can be inflicted
]]
function Status.CanBeInflicted(creature: any, statusType: StatusType): boolean
	if not creature then return false end
	
	-- Check ability immunities
	local Abilities = require(script.Parent.Abilities)
	local ability = Abilities.GetName(creature)
	if not ability then return true end
	
	local normAbility = string.lower(ability)
	
	-- Type-based immunities
	if creature.Type then
		for _, typeName in ipairs(creature.Type) do
			-- Gen 9: Fire-types are immune to burn (but can still be frozen)
			if typeName == "Fire" and statusType == "BRN" then
				return false
			end
			if typeName == "Ice" and statusType == "FRZ" then
				return false
			end
			if typeName == "Electric" and statusType == "PAR" then
				return false
			end
			-- Poison-types are immune to both poison and toxic poison
			if typeName == "Poison" and (statusType == "PSN" or statusType == "TOX") then
				return false
			end
			if typeName == "Steel" and (statusType == "PSN" or statusType == "TOX") then
				return false
			end
		end
	end
	
	-- Ability-based immunities
	if statusType == "PAR" and normAbility == "lithe" then
		return false
	end
	if statusType == "SLP" and normAbility == "arcane veil" then
		return false
	end
	
	-- Can't inflict a major status if already has one (no refreshing/reapplying)
	if creature.Status then
		return false
	end
	
	return true
end

--[[
	Applies a status condition to a creature
	@param creature The creature
	@param statusType The status type to apply
	@param turnsRemaining Optional turns for Sleep (1-3)
	@return boolean True if successfully applied
]]
function Status.Apply(creature: any, statusType: StatusType, turnsRemaining: number?): boolean
	if not Status.CanBeInflicted(creature, statusType) then
		return false
	end
	
	creature.Status = {
		Type = statusType,
		TurnsRemaining = turnsRemaining,
		ToxicCounter = (statusType == "TOX") and 1 or nil,
	}
	
	return true
end

--[[
	Removes status condition from a creature
	@param creature The creature
]]
function Status.Remove(creature: any)
	if creature then
		creature.Status = nil
	end
end

--[[
	Processes end-of-turn status effects (HP loss, etc.)
	@param creature The creature
	@return number? HP loss amount, or nil if no loss
]]
function Status.ProcessEndOfTurn(creature: any): number?
	if not creature or not creature.Status then
		return nil
	end
	
	local status = creature.Status
	local statusType = status.Type
	local maxHP = creature.MaxStats and creature.MaxStats.HP or 1
	
	if statusType == "BRN" then
		-- Gen 8–9: Burn is 1/16 max HP
		return math.max(1, math.floor(maxHP / 16))
	elseif statusType == "PSN" then
		-- Gen 8–9: Poison is 1/8 max HP
		return math.max(1, math.floor(maxHP / 8))
	elseif statusType == "TOX" then
		-- Gen 8–9: Badly Poisoned increases each end of turn while active (1/16, 2/16, 3/16, ...)
		-- Counter resets when the creature switches out (handled by battle switch logic).
		local counter = status.ToxicCounter or 1
		local damage = math.max(1, math.floor(maxHP * counter / 16))
		-- Increment counter for next turn
		status.ToxicCounter = counter + 1
		return damage
	end
	
	return nil
end

--[[
	Checks if creature can act this turn (Sleep, Freeze, Paralysis check)
	@param creature The creature
	@return boolean, string? Can act, and message if can't act
]]
function Status.CanAct(creature: any): (boolean, string?)
	if not creature or not creature.Status then
		return true, nil
	end
	
	local status = creature.Status
	local statusType = status.Type
	local creatureName = creature.Nickname or creature.Name or "The creature"
	
	if statusType == "SLP" then
		-- Check if sleep turns expired
		local turns = status.TurnsRemaining or 1
		if turns > 0 then
			status.TurnsRemaining = turns - 1
			return false, creatureName .. " is fast asleep!"
		else
			-- Wake up
			Status.Remove(creature)
			return true, creatureName .. " woke up!"
		end
	elseif statusType == "FRZ" then
		-- 20% chance to thaw each turn
		if math.random(1, 5) == 1 then
			Status.Remove(creature)
			return true, creatureName .. " thawed out!"
		end
		return false, creatureName .. " is frozen solid!"
	elseif statusType == "PAR" then
		-- 25% chance to be unable to move
		if math.random(1, 4) == 1 then
			return false, creatureName .. " is paralyzed! It can't move!"
		end
	end
	
	return true, nil
end

--[[
	Thaws frozen creature (when hit by Fire-type move)
	@param creature The creature
	@return boolean True if was frozen and thawed
]]
function Status.Thaw(creature: any): boolean
	if creature and creature.Status and creature.Status.Type == "FRZ" then
		Status.Remove(creature)
		return true
	end
	return false
end

--[[
	Applies volatile status condition
	@param creature The creature
	@param volatileType The volatile status type
	@param turns Optional turns for Confusion (1-4)
]]
function Status.ApplyVolatile(creature: any, volatileType: VolatileStatusType, turns: number?)
	if not creature then return end
	
	creature.VolatileStatus = creature.VolatileStatus or {}
	
	if volatileType == "Confusion" then
		creature.VolatileStatus.Confusion = turns or math.random(1, 4)
	elseif volatileType == "Infatuation" then
		creature.VolatileStatus.Infatuation = true
	elseif volatileType == "Flinch" then
		creature.VolatileStatus.Flinch = true
	end
end

--[[
	Removes volatile status condition
	@param creature The creature
	@param volatileType The volatile status type to remove
]]
function Status.RemoveVolatile(creature: any, volatileType: VolatileStatusType)
	if not creature or not creature.VolatileStatus then return end
	
	if volatileType == "Confusion" then
		creature.VolatileStatus.Confusion = nil
	elseif volatileType == "Infatuation" then
		creature.VolatileStatus.Infatuation = nil
	elseif volatileType == "Flinch" then
		creature.VolatileStatus.Flinch = nil
	end
end

--[[
	Checks if creature can act due to volatile status (Confusion, Infatuation, Flinch)
	@param creature The creature
	@return boolean, string?, number? Can act, message if can't act, self-damage if confusion hits
]]
function Status.CanActVolatile(creature: any): (boolean, string?, number?)
	-- Initialize VolatileStatus if it doesn't exist
	if not creature then
		return true, nil, nil
	end
	
	if not creature.VolatileStatus then
		creature.VolatileStatus = {}
		return true, nil, nil
	end
	
	local volatile = creature.VolatileStatus
	local creatureName = creature.Nickname or creature.Name or "The creature"
	
	-- Flinch: single turn only, checked at start of turn
	if volatile.Flinch then
		Status.RemoveVolatile(creature, "Flinch")
		-- Format message like Pokemon: "X flinched!"
		return false, creatureName .. " flinched!"
	end
	
	-- Infatuation: 50% chance to skip turn
	if volatile.Infatuation then
		if math.random(1, 2) == 1 then
			return false, creatureName .. " is in love! It can't attack!"
		end
	end
	
	-- Confusion: check turns remaining, then 33% chance to self-hit
	if volatile.Confusion and volatile.Confusion > 0 then
		volatile.Confusion = volatile.Confusion - 1
		
		-- 33% chance to hurt self (0-100, if <= 33)
		if math.random(1, 100) <= 33 then
			-- Gen 8–9: confusion self-hit is a 40 BP typeless PHYSICAL hit using the user's
			-- Attack/Defense (including stat stages and burn Attack reduction).
			local level = creature.Level or 1
			local power = 40
			local atkBase = (creature.Stats and creature.Stats.Attack) or 1
			local defBase = (creature.Stats and creature.Stats.Defense) or 1
			local atkStage = StatStages.GetStage(creature, "Attack")
			local defStage = StatStages.GetStage(creature, "Defense")

			local atk = StatStages.ApplyStage(atkBase, atkStage, false)
			local def = math.max(1, StatStages.ApplyStage(defBase, defStage, false))

			-- Burn halves Attack for physical damage (unless abilities override elsewhere)
			atk = math.floor(atk * Status.GetAttackMultiplier(creature))

			local levelFactor = math.floor((2 * level) / 5) + 2
			local baseDamage = math.floor((levelFactor * power * (atk / def)) / 50) + 2
			local randomFactor = math.random(85, 100) / 100
			local selfDamage = math.max(1, math.floor(baseDamage * randomFactor))

			return false, creatureName .. " is confused!\n" .. creatureName .. " hurt itself in confusion!", selfDamage
		end
		
		-- Confusion ended naturally
		if volatile.Confusion <= 0 then
			Status.RemoveVolatile(creature, "Confusion")
			return true, creatureName .. " snapped out of confusion!"
		end
	end
	
	return true, nil, nil
end

--[[
	Gets speed multiplier from status conditions
	@param creature The creature
	@return number Speed multiplier (1.0 = normal)
]]
function Status.GetSpeedMultiplier(creature: any): number
	if not creature or not creature.Status then
		return 1.0
	end
	
	local statusType = creature.Status.Type
	if statusType == "PAR" then
		-- Gen 8–9: paralysis halves Speed
		return 0.5
	end
	
	return 1.0
end

--[[
	Gets attack multiplier from status conditions
	@param creature The creature
	@return number Attack multiplier (1.0 = normal)
]]
function Status.GetAttackMultiplier(creature: any): number
	if not creature or not creature.Status then
		return 1.0
	end
	
	local statusType = creature.Status.Type
	if statusType == "BRN" then
		return 0.5 -- Attack halved
	end
	
	return 1.0
end

return Status


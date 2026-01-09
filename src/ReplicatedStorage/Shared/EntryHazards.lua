--!strict
--[[
	EntryHazards.lua
	Handles entry hazard mechanics: Stealth Rock, Spikes, Toxic Spikes
	
	Entry hazards are set on the opponent's side and trigger when they switch in:
	- Stealth Rock: Rock-type damage based on type effectiveness (6.25% to 50% max HP)
	- Spikes: Ground-based damage, 1-3 layers (12.5%, 16.67%, 25% max HP)
	- Toxic Spikes: Poisons grounded foes (1 layer = PSN, 2 layers = TOX)
	
	Flying types and Levitate ability users are immune to Spikes and Toxic Spikes.
	Poison types absorb Toxic Spikes on switch-in (removes them).
]]

local Status = require(script.Parent:WaitForChild("Status"))
local TypeChart = require(script.Parent:WaitForChild("TypeChart"))

local EntryHazards = {}

export type HazardType = "StealthRock" | "Spikes" | "ToxicSpikes"
export type EntryHazardsState = {
	StealthRock: boolean?,
	Spikes: number?, -- 0-3
	ToxicSpikes: number?, -- 0-2
}

--[[
	Initialize empty hazards state
	@return EntryHazardsState Empty hazards table
]]
function EntryHazards.CreateEmpty(): EntryHazardsState
	return {
		StealthRock = false,
		Spikes = 0,
		ToxicSpikes = 0,
	}
end

--[[
	Check if a hazard type is already at max
	@param hazards The current hazards state
	@param hazardType The type of hazard to check
	@return boolean True if hazard is at max/already set
]]
function EntryHazards.IsAtMax(hazards: EntryHazardsState?, hazardType: HazardType): boolean
	if not hazards then return false end
	
	if hazardType == "StealthRock" then
		return hazards.StealthRock == true
	elseif hazardType == "Spikes" then
		return (hazards.Spikes or 0) >= 3
	elseif hazardType == "ToxicSpikes" then
		return (hazards.ToxicSpikes or 0) >= 2
	end
	
	return false
end

--[[
	Set/add a hazard layer
	@param hazards The current hazards state (will be created if nil)
	@param hazardType The type of hazard to set
	@return EntryHazardsState The updated hazards state
	@return boolean True if hazard was successfully added
	@return number The new layer count (1 for Stealth Rock, 1-3 for Spikes, 1-2 for Toxic Spikes)
]]
function EntryHazards.SetHazard(hazards: EntryHazardsState?, hazardType: HazardType): (EntryHazardsState, boolean, number)
	local h = hazards or EntryHazards.CreateEmpty()
	
	if hazardType == "StealthRock" then
		if h.StealthRock then
			return h, false, 0 -- Already set
		end
		h.StealthRock = true
		return h, true, 1
		
	elseif hazardType == "Spikes" then
		local current = h.Spikes or 0
		if current >= 3 then
			return h, false, current -- Max layers
		end
		h.Spikes = current + 1
		return h, true, h.Spikes
		
	elseif hazardType == "ToxicSpikes" then
		local current = h.ToxicSpikes or 0
		if current >= 2 then
			return h, false, current -- Max layers
		end
		h.ToxicSpikes = current + 1
		return h, true, h.ToxicSpikes
	end
	
	return h, false, 0
end

--[[
	Clear all hazards from a side
	@param hazards The hazards state to clear
	@return EntryHazardsState Cleared hazards state
	@return boolean True if any hazards were cleared
]]
function EntryHazards.ClearAll(hazards: EntryHazardsState?): (EntryHazardsState, boolean)
	if not hazards then
		return EntryHazards.CreateEmpty(), false
	end
	
	local hadHazards = (hazards.StealthRock == true) 
		or ((hazards.Spikes or 0) > 0) 
		or ((hazards.ToxicSpikes or 0) > 0)
	
	return EntryHazards.CreateEmpty(), hadHazards
end

--[[
	Check if creature is grounded (affected by Spikes/Toxic Spikes)
	Flying types and Levitate ability are immune
	@param creature The creature to check
	@return boolean True if grounded
]]
function EntryHazards.IsGrounded(creature: any): boolean
	if not creature then return true end
	
	-- Check Flying type
	if creature.Type then
		for _, typeName in ipairs(creature.Type) do
			if typeName == "Flying" then
				return false
			end
		end
	end
	
	-- Check Levitate ability (if abilities are implemented)
	local ability = creature.Ability
	if ability and string.lower(ability) == "levitate" then
		return false
	end
	
	return true
end

--[[
	Check if creature is Poison type (absorbs Toxic Spikes)
	@param creature The creature to check
	@return boolean True if Poison type
]]
function EntryHazards.IsPoisonType(creature: any): boolean
	if not creature or not creature.Type then return false end
	
	for _, typeName in ipairs(creature.Type) do
		if typeName == "Poison" then
			return true
		end
	end
	
	return false
end

--[[
	Check if creature is Steel type (immune to poison)
	@param creature The creature to check
	@return boolean True if Steel type
]]
function EntryHazards.IsSteelType(creature: any): boolean
	if not creature or not creature.Type then return false end
	
	for _, typeName in ipairs(creature.Type) do
		if typeName == "Steel" then
			return true
		end
	end
	
	return false
end

--[[
	Calculate Stealth Rock damage based on type effectiveness
	Rock type effectiveness determines damage:
	- 4x weak: 50% max HP
	- 2x weak: 25% max HP
	- Neutral: 12.5% max HP
	- 2x resist: 6.25% max HP
	- 4x resist: 3.125% max HP
	@param creature The creature taking damage
	@return number Damage amount
	@return string Effectiveness description for message
]]
function EntryHazards.CalculateStealthRockDamage(creature: any): (number, string)
	if not creature or not creature.MaxStats then
		return 0, "Normal"
	end
	
	local maxHP = creature.MaxStats.HP or 100
	local multiplier = TypeChart.GetMultiplier("Rock", creature.Type)
	local effectivenessDesc = "Normal"
	
	-- Set effectiveness description
	if multiplier == 0 then
		effectivenessDesc = "Immune"
	elseif multiplier >= 4 then
		effectivenessDesc = "Super"
	elseif multiplier >= 2 then
		effectivenessDesc = "Super"
	elseif multiplier <= 0.25 then
		effectivenessDesc = "NotVery"
	elseif multiplier <= 0.5 then
		effectivenessDesc = "NotVery"
	end
	
	-- Base damage is 12.5% (1/8) max HP, scaled by effectiveness
	local baseDamagePercent = 12.5
	local damage = math.floor(maxHP * (baseDamagePercent / 100) * multiplier)
	
	-- Minimum 1 damage if not immune
	if multiplier > 0 then
		damage = math.max(1, damage)
	end
	
	return damage, effectivenessDesc
end

--[[
	Calculate Spikes damage based on layers
	- 1 layer: 12.5% max HP (1/8)
	- 2 layers: 16.67% max HP (1/6)
	- 3 layers: 25% max HP (1/4)
	@param creature The creature taking damage
	@param layers Number of spike layers (1-3)
	@return number Damage amount
]]
function EntryHazards.CalculateSpikesDamage(creature: any, layers: number): number
	if not creature or not creature.MaxStats or layers <= 0 then
		return 0
	end
	
	local maxHP = creature.MaxStats.HP or 100
	local damagePercent = 0
	
	if layers == 1 then
		damagePercent = 12.5  -- 1/8
	elseif layers == 2 then
		damagePercent = 16.67 -- 1/6
	else -- 3 or more
		damagePercent = 25    -- 1/4
	end
	
	local damage = math.floor(maxHP * (damagePercent / 100))
	return math.max(1, damage)
end

--[[
	Apply entry hazard effects when a creature switches in
	@param creature The creature switching in
	@param hazards The hazards on their side
	@return table Array of step results to process (damage, status, messages)
	@return EntryHazardsState Updated hazards (Toxic Spikes may be absorbed)
]]
function EntryHazards.ApplyOnSwitchIn(creature: any, hazards: EntryHazardsState?, isPlayer: boolean): ({any}, EntryHazardsState?)
	local steps = {}
	local creatureName = creature and (creature.Nickname or creature.Name) or "Creature"
	
	print("[EntryHazards] ApplyOnSwitchIn called for:", creatureName, "isPlayer:", isPlayer)
	print("[EntryHazards] hazards table:", hazards)
	
	if not hazards then
		print("[EntryHazards] No hazards on this side - returning early")
		return steps, hazards
	end
	
	print("[EntryHazards] StealthRock:", hazards.StealthRock, "Spikes:", hazards.Spikes, "ToxicSpikes:", hazards.ToxicSpikes)
	
	local updatedHazards = table.clone(hazards)
	local isGrounded = EntryHazards.IsGrounded(creature)
	local isPoisonType = EntryHazards.IsPoisonType(creature)
	local isSteelType = EntryHazards.IsSteelType(creature)
	
	-- Stealth Rock: Affects all creatures (not just grounded)
	if hazards.StealthRock then
		local damage, effectiveness = EntryHazards.CalculateStealthRockDamage(creature)
		if damage > 0 then
			-- Apply damage to creature
			local newHP = math.max(0, (creature.Stats and creature.Stats.HP or 100) - damage)
			if creature.Stats then
				creature.Stats.HP = newHP
			end
			
			table.insert(steps, {
				Type = "HazardDamage",
				HazardType = "StealthRock",
				Creature = creatureName,
				Damage = damage,
				NewHP = newHP,
				MaxHP = creature.MaxStats and creature.MaxStats.HP,
				Effectiveness = effectiveness,
				IsPlayer = isPlayer,
				Message = string.format("%s is hurt by Stealth Rock!", creatureName),
			})
		end
	end
	
	-- Spikes: Only affects grounded creatures
	if isGrounded and (hazards.Spikes or 0) > 0 then
		local layers = hazards.Spikes
		local damage = EntryHazards.CalculateSpikesDamage(creature, layers)
		if damage > 0 then
			-- Apply damage to creature
			local newHP = math.max(0, (creature.Stats and creature.Stats.HP or 100) - damage)
			if creature.Stats then
				creature.Stats.HP = newHP
			end
			
			table.insert(steps, {
				Type = "HazardDamage",
				HazardType = "Spikes",
				Creature = creatureName,
				Damage = damage,
				NewHP = newHP,
				MaxHP = creature.MaxStats and creature.MaxStats.HP,
				Layers = layers,
				IsPlayer = isPlayer,
				Message = string.format("%s is hurt by the Spikes!", creatureName),
			})
		end
	end
	
	-- Toxic Spikes: Only affects grounded creatures
	if isGrounded and (hazards.ToxicSpikes or 0) > 0 then
		local layers = hazards.ToxicSpikes
		
		-- Poison types absorb Toxic Spikes
		if isPoisonType then
			updatedHazards.ToxicSpikes = 0
			table.insert(steps, {
				Type = "HazardDamage",
				HazardType = "ToxicSpikes",
				Creature = creatureName,
				Absorbed = true,
				IsPlayer = isPlayer,
				Message = string.format("%s absorbed the Toxic Spikes!", creatureName),
			})
		-- Steel types are immune to poison
		elseif isSteelType then
			-- No effect, no message needed
		-- Already has a status condition
		elseif creature.Status then
			-- Can't be poisoned, no message needed
		else
			-- Apply poison status
			local statusType = (layers >= 2) and "TOX" or "PSN"
			local statusName = (layers >= 2) and "badly poisoned" or "poisoned"
			
			if Status.Apply(creature, statusType) then
				table.insert(steps, {
					Type = "HazardDamage",
					HazardType = "ToxicSpikes",
					Creature = creatureName,
					Status = statusType,
					IsPlayer = isPlayer,
					Message = string.format("%s was %s by Toxic Spikes!", creatureName, statusName),
				})
			end
		end
	end
	
	return steps, updatedHazards
end

--[[
	Get message for when hazard is set
	@param hazardType The type of hazard set
	@param isPlayer Whether the user is the player (hazards go on foe's side)
	@param layers Current layer count after setting
	@return string The message to display
]]
function EntryHazards.GetSetMessage(hazardType: HazardType, isPlayer: boolean, layers: number): string
	local sideDesc = isPlayer and "opposing side" or "your side"
	
	if hazardType == "StealthRock" then
		return string.format("Pointed stones float in the air around the %s!", sideDesc)
	elseif hazardType == "Spikes" then
		if layers == 1 then
			return string.format("Spikes were scattered around the %s!", sideDesc)
		else
			return string.format("Spikes were scattered around the %s! (Layer %d)", sideDesc, layers)
		end
	elseif hazardType == "ToxicSpikes" then
		if layers == 1 then
			return string.format("Toxic Spikes were scattered around the %s!", sideDesc)
		else
			return string.format("Toxic Spikes were scattered around the %s! (Layer %d)", sideDesc, layers)
		end
	end
	
	return "Hazards were set!"
end

--[[
	Get message when hazard fails (already at max)
	@param hazardType The type of hazard
	@return string The failure message
]]
function EntryHazards.GetFailMessage(hazardType: HazardType): string
	if hazardType == "StealthRock" then
		return "But the floating rocks are already in place!"
	elseif hazardType == "Spikes" then
		return "But the spikes are already at their limit!"
	elseif hazardType == "ToxicSpikes" then
		return "But the toxic spikes are already at their limit!"
	end
	
	return "But it failed!"
end

--[[
	Get message when hazards are cleared
	@param isPlayer Whether the player's side was cleared
	@param hadStealthRock Whether Stealth Rock was cleared
	@param hadSpikes Whether Spikes were cleared
	@param hadToxicSpikes Whether Toxic Spikes were cleared
	@return string The message to display
]]
function EntryHazards.GetClearMessage(isPlayer: boolean, hadStealthRock: boolean, hadSpikes: boolean, hadToxicSpikes: boolean): string
	local sideDesc = isPlayer and "your side" or "the opposing side"
	local hazardList = {}
	
	if hadStealthRock then
		table.insert(hazardList, "the pointed stones")
	end
	if hadSpikes then
		table.insert(hazardList, "the spikes")
	end
	if hadToxicSpikes then
		table.insert(hazardList, "the toxic spikes")
	end
	
	if #hazardList == 0 then
		return ""
	elseif #hazardList == 1 then
		return string.format("%s disappeared from around %s!", hazardList[1]:gsub("^%l", string.upper), sideDesc)
	else
		local last = table.remove(hazardList)
		return string.format("%s and %s disappeared from around %s!", table.concat(hazardList, ", "), last, sideDesc)
	end
end

return EntryHazards


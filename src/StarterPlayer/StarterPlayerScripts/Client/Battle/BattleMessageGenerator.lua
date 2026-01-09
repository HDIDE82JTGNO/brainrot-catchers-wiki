--!strict
--[[
	BattleMessageGenerator.lua
	
	Generates all battle messages client-side from structured event data.
	The server sends only event codes and data - no descriptive strings.
	
	This ensures:
	- Faster network transmission (less data)
	- Easier localization support
	- Consistent message formatting
	- Reduced server complexity
]]

local BattleMessageGenerator = {}

-- Cache for checking if player and foe have the same creature
local _cachedPlayerCreatureName: string? = nil
local _cachedFoeCreatureName: string? = nil
-- Message logger helper to ensure every generated battle message is traced
local function _emit(msg: string, tag: string): string
	print(string.format("[BattleMessage][%s] %s", tag, msg))
	return msg
end

--[[
	Updates the cached creature names for comparison
	@param playerCreatureName The player's current creature name
	@param foeCreatureName The foe's current creature name
]]
function BattleMessageGenerator.UpdateCreatureNames(playerCreatureName: string?, foeCreatureName: string?)
	_cachedPlayerCreatureName = playerCreatureName
	_cachedFoeCreatureName = foeCreatureName
end

--[[
	Formats a foe creature name with "the opposing" prefix if both have the same species
	@param foeName The name of the foe creature
	@return Formatted name string
]]
local function formatFoeName(foeName: string): string
	-- Check if player and foe have the same creature species
	if _cachedPlayerCreatureName and _cachedFoeCreatureName then
		if _cachedPlayerCreatureName == _cachedFoeCreatureName then
			return "the opposing " .. foeName
		end
	end
	return foeName
end

--[[
	Generates a message for a creature using a move
	@param actorName The name of the creature using the move
	@param moveName The name of the move
	@param isPlayer Whether this is the player's creature
	@return Formatted message string
]]
function BattleMessageGenerator.MoveUsed(actorName: string, moveName: string, isPlayer: boolean?): string
	-- Format foe name if applicable
	local displayName = actorName
	if isPlayer == false then
		displayName = formatFoeName(actorName)
	end
	return _emit(string.format("%s used %s!", displayName, moveName), "MoveUsed")
end

--[[
	Generates a message for a creature fainting
	@param creatureName The name of the creature that fainted
	@param isPlayer Whether this is the player's creature
	@return Formatted message string
]]
function BattleMessageGenerator.Faint(creatureName: string, isPlayer: boolean?): string
	-- Format foe name if applicable
	local displayName = creatureName
	if isPlayer == false then
		displayName = formatFoeName(creatureName)
	end
	return _emit(string.format("%s fainted!", displayName), "Faint")
end

--[[
	Generates a message for a creature being recalled
	@param creatureName The name of the creature being recalled
	@return Formatted message string
]]
function BattleMessageGenerator.Recall(creatureName: string): string
	return _emit(string.format("%s, come back!", creatureName), "Recall")
end

--[[
	Generates a message for sending out a creature
	@param creatureName The name of the creature being sent out
	@param variant Optional variant (1-3) for different messages
	@return Formatted message string
]]
function BattleMessageGenerator.SendOut(creatureName: string, variant: number?, opts: { isPlayer: boolean?, trainerName: string? }?): string
    opts = opts or {}
    local isPlayer = opts.isPlayer == true
    local trainerName = opts.trainerName
    if isPlayer then
        local messages = {
            string.format("Go %s!", creatureName),
            string.format("You got this %s!", creatureName),
            string.format("Go for it %s!", creatureName),
        }
        local index = variant or math.random(1, #messages)
        return _emit(messages[index] or messages[1], "SendOut:Player")
    else
        if trainerName and trainerName ~= "" then
            return _emit(string.format("%s sent out %s!", trainerName, creatureName), "SendOut:Trainer")
        end
        return _emit(string.format("Trainer sent out %s!", creatureName), "SendOut:Trainer")
    end
end

--[[
	Generates a message for gaining XP
	@param creatureName The name of the creature gaining XP
	@param xpAmount The amount of XP gained
	@param isShared Whether this is shared XP
	@return Formatted message string
]]
function BattleMessageGenerator.XPGain(creatureName: string, xpAmount: number, isShared: boolean?): string
	return _emit(string.format("%s gained %d XP!", creatureName, xpAmount), "XPGain")
end

--[[
	Generates a message for EXP Spread
	@return Formatted message string
]]
function BattleMessageGenerator.XPSpread(): string
	return _emit("The rest of your party gained XP thanks to EXP Spread!", "XPSpread")
end

--[[
	Generates a message for leveling up
	@param creatureName The name of the creature leveling up
	@param newLevel The new level
	@return Formatted message string
]]
function BattleMessageGenerator.LevelUp(creatureName: string, newLevel: number): string
	return _emit(string.format("%s reached Lv. %d!", creatureName, newLevel), "LevelUp")
end

--
-- Generates a message for learning a move
-- @param creatureName The name of the creature
-- @param moveName The name of the learned move
-- @return Formatted message string
--
function BattleMessageGenerator.MoveLearned(creatureName: string, moveName: string): string
    return _emit(string.format("%s learned %s!", creatureName, moveName), "MoveLearned")
end

-- Move learn declined
function BattleMessageGenerator.MoveDeclined(creatureName: string, moveName: string): string
    return _emit(string.format("%s did not learn %s.", creatureName, moveName), "MoveDeclined")
end

--[[
	Generates a message for evolution
	@param oldName The creature's name before evolution
	@param newName The creature's name after evolution
	@return Formatted message string
]]
function BattleMessageGenerator.Evolution(oldName: string, newName: string): string
	return _emit(string.format("%s evolved into %s!", oldName, newName), "Evolution")
end

--[[
	Generates a message for a critical hit
	@return Formatted message string
]]
function BattleMessageGenerator.CriticalHit(): string
	return _emit("A critical hit!", "CriticalHit")
end

--[[
	Generates a message for a move missing
	@param actorName The name of the creature whose move missed (optional, message may be pre-formatted)
	@return Formatted message string
]]
function BattleMessageGenerator.Miss(actorName: string?, moveName: string?): string
	-- If message is already formatted (from server), use it directly
	if actorName and not string.find(actorName, "'s attack missed", 1, true) and not string.find(actorName, "avoided", 1, true) then
		if moveName then
			return _emit(string.format("%s used %s, but it missed!", actorName, moveName), "Miss")
		else
			return _emit(string.format("%s's attack missed!", actorName), "Miss")
		end
	end
	-- Default message for when server provides pre-formatted message
	return _emit(actorName or "The attack missed!", "Miss")
end

--[[
	Generates a message for type effectiveness
	@param effectiveness "SuperEffective" | "NotVeryEffective" | "NoEffect"
	@return Formatted message string
]]
function BattleMessageGenerator.Effectiveness(effectiveness: string): string
	if effectiveness == "SuperEffective" then
		return _emit("It's super effective!", "Effectiveness")
	elseif effectiveness == "NotVeryEffective" then
		return _emit("It's not very effective...", "Effectiveness")
	elseif effectiveness == "NoEffect" then
		return _emit("It doesn't affect the target...", "Effectiveness")
	end
	return _emit("", "Effectiveness")
end

--[[
	Generates a message for status condition application
	@param creatureName The name of the creature
	@param status The status condition
	@return Formatted message string
]]
function BattleMessageGenerator.StatusApplied(creatureName: string, status: string): string
	-- Ensure status is a string and uppercase for matching
	local statusStr = tostring(status):upper()
	
	-- Map status codes to display names and messages
	local statusMap = {
		-- Status codes (from server)
		BRN = string.format("%s was burned!", creatureName),
		PAR = string.format("%s is paralyzed! It may be unable to move!", creatureName),
		PSN = string.format("%s was poisoned!", creatureName),
		TOX = string.format("%s was badly poisoned!", creatureName),
		SLP = string.format("%s fell asleep!", creatureName),
		FRZ = string.format("%s was frozen solid!", creatureName),
		-- Volatile statuses
		CONFUSION = string.format("%s became confused!", creatureName),
		INFATUATION = string.format("%s fell in love!", creatureName),
		-- Display names (for backwards compatibility)
		BURN = string.format("%s was burned!", creatureName),
		PARALYSIS = string.format("%s is paralyzed! It may be unable to move!", creatureName),
		POISON = string.format("%s was poisoned!", creatureName),
		SLEEP = string.format("%s fell asleep!", creatureName),
		FREEZE = string.format("%s was frozen solid!", creatureName),
	}
	
	local message = statusMap[statusStr]
	if message then
		return _emit(message, "StatusApplied")
	end
	
	-- Fallback: try to generate a reasonable message
	warn("[BattleMessageGenerator] Unknown status type:", status, "for creature:", creatureName)
	return _emit(string.format("%s was affected!", creatureName), "StatusApplied:Fallback")
end

--[[
	Generates a message for status condition removal
	@param creatureName The name of the creature
	@param status The status condition
	@return Formatted message string
]]
function BattleMessageGenerator.StatusRemoved(creatureName: string, status: string): string
	local statusMessages = {
		Burn = string.format("%s's burn was healed!", creatureName),
		Paralysis = string.format("%s was cured of paralysis!", creatureName),
		Poison = string.format("%s was cured of poison!", creatureName),
		Sleep = string.format("%s woke up!", creatureName),
		Freeze = string.format("%s thawed out!", creatureName),
	}
	
	local msg = statusMessages[status] or string.format("%s recovered from %s!", creatureName, status)
	return _emit(msg, "StatusRemoved")
end

--[[
	Generates a message for stat stage changes
	@param creatureName The name of the creature
	@param stat The stat being changed
	@param stages The number of stages (positive = increase, negative = decrease)
	@return Formatted message string
]]
function BattleMessageGenerator.StatChange(creatureName: string, stat: string, stages: number): string
	local statNames = {
		Attack = "Attack",
		Defense = "Defense",
		Speed = "Speed",
		Accuracy = "accuracy",
		Evasion = "evasiveness",
	}
	
	local statName = statNames[stat] or stat
	local changeText
	
	if stages > 0 then
		if stages == 1 then
			changeText = "rose"
		elseif stages == 2 then
			changeText = "sharply rose"
		else
			changeText = "rose drastically"
		end
	else
		if stages == -1 then
			changeText = "fell"
		elseif stages == -2 then
			changeText = "harshly fell"
		else
			changeText = "severely fell"
		end
	end
	
	return _emit(string.format("%s's %s %s!", creatureName, statName, changeText), "StatChange")
end

--[[
	Generates a message for escape attempts
	@param success Whether the escape was successful
	@return Formatted message string
]]
function BattleMessageGenerator.Escape(success: boolean): string
	if success then
		return _emit("Got away safely!", "Escape")
	else
		return _emit("Can't escape!", "Escape")
	end
end

--[[
	Generates a message for flinching
	@param creatureName The name of the creature that flinched
	@return Formatted message string
]]
function BattleMessageGenerator.Flinch(creatureName: string): string
	return _emit(string.format("%s flinched and couldn't move!", creatureName), "Flinch")
end

--[[
	Generates a message for healing
	@param creatureName The name of the creature being healed
	@param amount The amount healed
	@return Formatted message string
]]
function BattleMessageGenerator.Heal(creatureName: string, amount: number): string
	return _emit(string.format("%s restored %d HP!", creatureName, amount), "Heal")
end

--[[
	Generates a message for recoil damage
	@param creatureName The name of the creature taking recoil
	@return Formatted message string
]]
function BattleMessageGenerator.Recoil(creatureName: string): string
	return _emit(string.format("%s was hurt by the recoil!", creatureName), "Recoil")
end

--[[
	Generates a message for entry hazard setup
	@param hazardType "StealthRock" | "Spikes" | "ToxicSpikes"
	@param isPlayer Whether the player set the hazard (hazards go on opponent's side)
	@param layers The layer count (for Spikes/ToxicSpikes)
	@return Formatted message string
]]
function BattleMessageGenerator.HazardSet(hazardType: string, isPlayer: boolean, layers: number?): string
	local sideDesc = isPlayer and "opposing side" or "your side"
	
	if hazardType == "StealthRock" then
		return _emit(string.format("Pointed stones float in the air around the %s!", sideDesc), "HazardSet:StealthRock")
	elseif hazardType == "Spikes" then
		local layerMsg = ""
		if layers and layers > 1 then
			layerMsg = string.format(" (Layer %d)", layers)
		end
		return _emit(string.format("Spikes were scattered around the %s!%s", sideDesc, layerMsg), "HazardSet:Spikes")
	elseif hazardType == "ToxicSpikes" then
		local layerMsg = ""
		if layers and layers > 1 then
			layerMsg = string.format(" (Layer %d)", layers)
		end
		return _emit(string.format("Toxic Spikes were scattered around the %s!%s", sideDesc, layerMsg), "HazardSet:ToxicSpikes")
	end
	
	return _emit("Hazards were set!", "HazardSet:Unknown")
end

--[[
	Generates a message for entry hazard damage on switch-in
	@param creatureName The name of the creature taking damage
	@param hazardType "StealthRock" | "Spikes" | "ToxicSpikes"
	@param statusApplied Optional status for Toxic Spikes ("PSN" or "TOX")
	@param absorbed Whether Toxic Spikes were absorbed by Poison type
	@return Formatted message string
]]
function BattleMessageGenerator.HazardDamage(creatureName: string, hazardType: string, statusApplied: string?, absorbed: boolean?): string
	if hazardType == "StealthRock" then
		return _emit(string.format("%s is hurt by Stealth Rock!", creatureName), "HazardDamage:StealthRock")
	elseif hazardType == "Spikes" then
		return _emit(string.format("%s is hurt by the Spikes!", creatureName), "HazardDamage:Spikes")
	elseif hazardType == "ToxicSpikes" then
		if absorbed then
			return _emit(string.format("%s absorbed the Toxic Spikes!", creatureName), "HazardDamage:ToxicSpikesAbsorbed")
		elseif statusApplied == "TOX" then
			return _emit(string.format("%s was badly poisoned by Toxic Spikes!", creatureName), "HazardDamage:ToxicSpikesTOX")
		elseif statusApplied == "PSN" then
			return _emit(string.format("%s was poisoned by Toxic Spikes!", creatureName), "HazardDamage:ToxicSpikesPSN")
		end
		return _emit(string.format("%s was affected by Toxic Spikes!", creatureName), "HazardDamage:ToxicSpikes")
	end
	
	return _emit(string.format("%s was hurt by the hazards!", creatureName), "HazardDamage:Unknown")
end

--[[
	Generates a message for hazard removal
	@param isPlayer Whether the player's side was cleared
	@param hadStealthRock Whether Stealth Rock was cleared
	@param hadSpikes Whether Spikes were cleared
	@param hadToxicSpikes Whether Toxic Spikes were cleared
	@return Formatted message string
]]
function BattleMessageGenerator.HazardClear(isPlayer: boolean, hadStealthRock: boolean?, hadSpikes: boolean?, hadToxicSpikes: boolean?): string
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
		local capitalized = hazardList[1]:gsub("^%l", string.upper)
		return _emit(string.format("%s disappeared from around %s!", capitalized, sideDesc), "HazardClear")
	else
		local last = table.remove(hazardList)
		local capitalized = hazardList[1]:gsub("^%l", string.upper)
		hazardList[1] = capitalized
		return _emit(string.format("%s and %s disappeared from around %s!", table.concat(hazardList, ", "), last, sideDesc), "HazardClear")
	end
end

--[[
	Generates a message for ability activation
	@param creatureName The name of the creature
	@param abilityName The name of the ability
	@param effectDescription Optional description of the effect
	@return Formatted message string
]]
function BattleMessageGenerator.AbilityActivation(creatureName: string, abilityName: string, effectDescription: string?): string
	if effectDescription then
		return _emit(string.format("[%s] %s", abilityName, effectDescription), "AbilityActivation")
	end
	return _emit(string.format("%s's %s activated!", creatureName, abilityName), "AbilityActivation")
end

--[[
	Generates a message for ability-based stat changes
	@param creatureName The name of the creature
	@param stat The stat being changed
	@param stages The number of stages (positive = increase, negative = decrease)
	@param abilityName Optional ability name for context
	@return Formatted message string
]]
function BattleMessageGenerator.AbilityStatChange(creatureName: string, stat: string, stages: number, abilityName: string?): string
	local statNames = {
		Attack = "Attack",
		Defense = "Defense",
		Speed = "Speed",
		Accuracy = "accuracy",
		Evasion = "evasiveness",
	}
	
	local statName = statNames[stat] or stat
	local changeText
	
	if stages > 0 then
		if stages == 1 then
			changeText = "rose"
		elseif stages == 2 then
			changeText = "sharply rose"
		else
			changeText = "rose drastically"
		end
	else
		if stages == -1 then
			changeText = "fell"
		elseif stages == -2 then
			changeText = "harshly fell"
		else
			changeText = "severely fell"
		end
	end
	
	return _emit(string.format("%s's %s %s!", creatureName, statName, changeText), "AbilityStatChange")
end

--[[
	Generates ability-specific messages based on ability name and effect type
	@param abilityName The name of the ability
	@param creatureName The creature with the ability
	@param effectType The type of effect (e.g., "speed_boost", "immunity", "intimidate")
	@param extraData Optional additional data for the message
	@return Formatted message string
]]
function BattleMessageGenerator.AbilityEffect(abilityName: string, creatureName: string, effectType: string, extraData: {[string]: any}?): string
	extraData = extraData or {}
	
	-- Ability-specific message templates
	local templates = {
		-- Speed boosts
		speed_boost = string.format("%s's Speed rose!", creatureName),
		
		-- Attack/Defense changes
		attack_boost = string.format("%s's Attack rose!", creatureName),
		defense_boost = string.format("%s's Defense rose!", creatureName),
		attack_drop = string.format("%s's Attack fell!", creatureName),
		defense_drop = string.format("%s's Defense fell!", creatureName),
		
		-- Intimidate-style
		intimidate = string.format("%s's Attack fell!", extraData.TargetName or "The opposing creature"),
		
		-- Weather triggers
		weather_speed = string.format("%s's Speed rose!", creatureName),
		
		-- Type immunities/absorptions
		immunity = string.format("It doesn't affect %s...", creatureName),
		absorption = string.format("%s absorbed the attack!", creatureName),
		
		-- Heal effects
		heal = string.format("%s restored HP!", creatureName),
		
		-- Damage reduction
		reduced = "The attack was weakened!",
		
		-- Entry effects
		entry = string.format("%s's %s!", creatureName, abilityName),
		
		-- Generic
		generic = string.format("%s's %s activated!", creatureName, abilityName),
	}
	
	return _emit(templates[effectType] or templates.generic, "AbilityEffect:" .. effectType)
end

--[[
	Generates a message for weather effects
	@param weather The weather type (battle weather name or WeatherConfig name)
	@param action "Start" | "Continue" | "End"
	@return Formatted message string
]]
function BattleMessageGenerator.Weather(weather: string, action: string): string
	-- Map battle weather names and WeatherConfig names to messages
	local weatherMessages = {
		-- Battle weather names (from abilities)
		Sunlight = {
			Start = "The sunlight turned harsh!",
			Continue = "The sunlight is harsh!",
			End = "The harsh sunlight faded.",
		},
		Rain = {
			Start = "It started to rain!",
			Continue = "Rain continues to fall.",
			End = "The rain stopped.",
		},
		Sandstorm = {
			Start = "A sandstorm kicked up!",
			Continue = "The sandstorm rages.",
			End = "The sandstorm subsided.",
		},
		Snow = {
			Start = "It started to snow!",
			Continue = "The snow continues to fall.",
			End = "The snow stopped.",
		},
		-- WeatherConfig names
		["Harsh Sun"] = {
			Start = "The sunlight turned harsh!",
			Continue = "The sunlight is harsh!",
			End = "The harsh sunlight faded.",
		},
		["Thunderstorm"] = {
			Start = "It started to rain!",
			Continue = "Rain continues to fall.",
			End = "The rain stopped.",
		},
		["Snowstorm"] = {
			Start = "It started to snow!",
			Continue = "The snow continues to fall.",
			End = "The snow stopped.",
		},
		-- Legacy names
		Sun = {
			Start = "The sunlight turned harsh!",
			Continue = "The sunlight is harsh!",
			End = "The harsh sunlight faded.",
		},
		Hail = {
			Start = "It started to snow!",
			Continue = "The snow continues to fall.",
			End = "The snow stopped.",
		},
	}
	
	if weatherMessages[weather] and weatherMessages[weather][action] then
		return _emit(weatherMessages[weather][action], "Weather")
	end
	
	return _emit("", "Weather")
end

--[[
	Generates a message for trainer battles
	@param trainerName The trainer's name
	@param action "Challenge" | "Defeat" | "Loss"
	@return Formatted message string
]]
function BattleMessageGenerator.Trainer(trainerName: string, action: string): string
	if action == "Challenge" then
		return _emit(string.format("%s wants to battle!", trainerName), "Trainer:Challenge")
	elseif action == "Defeat" then
		return _emit(string.format("You defeated %s!", trainerName), "Trainer:Defeat")
	elseif action == "Loss" then
		return _emit(string.format("You lost to %s!", trainerName), "Trainer:Loss")
	end
	return _emit("", "Trainer:Unknown")
end

--[[
	Generates a generic battle message from event data
	@param eventData The structured event data from server
	@return Formatted message string or nil
]]
function BattleMessageGenerator.FromEvent(eventData: any): string?
	if not eventData or not eventData.Type then
		return nil
	end
	
	local eventType = eventData.Type
	
	-- Handle different event types
	if eventType == "Move" and eventData.Actor and eventData.Move then
		return BattleMessageGenerator.MoveUsed(eventData.Actor, eventData.Move, eventData.IsPlayer)
		
	elseif eventType == "Faint" and eventData.Creature then
		return BattleMessageGenerator.Faint(eventData.Creature, eventData.IsPlayer)
		
	elseif eventType == "Switch" then
		if eventData.Action == "Recall" and eventData.Creature then
			return BattleMessageGenerator.Recall(eventData.Creature)
        elseif eventData.Action == "SendOut" and eventData.Creature then
            return BattleMessageGenerator.SendOut(eventData.Creature, eventData.Variant, { isPlayer = eventData.IsPlayer, trainerName = eventData.TrainerName })
		end
		
	elseif eventType == "XP" and eventData.Creature and eventData.Amount then
		return BattleMessageGenerator.XPGain(eventData.Creature, eventData.Amount, eventData.IsShared)
		
	elseif eventType == "XPSpread" then
		return BattleMessageGenerator.XPSpread()
		
    elseif eventType == "LevelUp" and eventData.Creature and eventData.Level then
		return BattleMessageGenerator.LevelUp(eventData.Creature, eventData.Level)
    
    elseif eventType == "MoveLearned" and eventData.Creature and eventData.Move then
        return BattleMessageGenerator.MoveLearned(eventData.Creature, eventData.Move)
    elseif eventType == "MoveDeclined" and eventData.Creature and eventData.Move then
        return BattleMessageGenerator.MoveDeclined(eventData.Creature, eventData.Move)
		
	elseif eventType == "Evolution" and eventData.OldName and eventData.NewName then
		return BattleMessageGenerator.Evolution(eventData.OldName, eventData.NewName)
		
	elseif eventType == "Critical" then
		return BattleMessageGenerator.CriticalHit()
		
	elseif eventType == "Miss" and eventData.Actor then
		return BattleMessageGenerator.Miss(eventData.Actor, eventData.Move)
		
	elseif eventType == "Effectiveness" and eventData.Effectiveness then
		return BattleMessageGenerator.Effectiveness(eventData.Effectiveness)
		
	elseif eventType == "Status" then
		if eventData.Action == "Apply" and eventData.Creature and eventData.Status then
			return BattleMessageGenerator.StatusApplied(eventData.Creature, eventData.Status)
		elseif eventData.Action == "Remove" and eventData.Creature and eventData.Status then
			return BattleMessageGenerator.StatusRemoved(eventData.Creature, eventData.Status)
		end
		
	elseif eventType == "StatChange" and eventData.Creature and eventData.Stat and eventData.Stages then
		return BattleMessageGenerator.StatChange(eventData.Creature, eventData.Stat, eventData.Stages)
		
	elseif eventType == "Escape" and eventData.Success ~= nil then
		return BattleMessageGenerator.Escape(eventData.Success)
		
	elseif eventType == "Flinch" and eventData.Creature then
		return BattleMessageGenerator.Flinch(eventData.Creature)
		
	elseif eventType == "Heal" and eventData.Creature and eventData.Amount then
		return BattleMessageGenerator.Heal(eventData.Creature, eventData.Amount)
		
	elseif eventType == "Recoil" and eventData.Creature then
		return BattleMessageGenerator.Recoil(eventData.Creature)
		
	elseif eventType == "Weather" and eventData.Weather and eventData.Action then
		return BattleMessageGenerator.Weather(eventData.Weather, eventData.Action)
		
	elseif eventType == "Trainer" and eventData.Trainer and eventData.Action then
		return BattleMessageGenerator.Trainer(eventData.Trainer, eventData.Action)
	
	elseif eventType == "AbilityActivation" and eventData.Creature and eventData.Ability then
		if eventData.EffectType then
			return BattleMessageGenerator.AbilityEffect(eventData.Ability, eventData.Creature, eventData.EffectType, eventData.ExtraData)
		end
		return BattleMessageGenerator.AbilityActivation(eventData.Creature, eventData.Ability, eventData.EffectDescription)
	
	elseif eventType == "ItemUse" and eventData.Actor and eventData.Item and eventData.Target then
		-- Ex: "You used an apple on X"
		local actor = eventData.Actor
		local item = eventData.Item
		local target = eventData.Target
		if actor == game.Players.LocalPlayer.Name then
			return _emit(string.format("You used an %s on %s", item:lower(), target), "ItemUse")
		else
			return _emit(string.format("%s used an %s on %s", actor, item:lower(), target), "ItemUse")
		end
		
	elseif eventType == "EntryHazard" and eventData.HazardType then
		return BattleMessageGenerator.HazardSet(eventData.HazardType, eventData.IsPlayer, eventData.Layers)
		
	elseif eventType == "HazardDamage" and eventData.HazardType and eventData.Creature then
		return BattleMessageGenerator.HazardDamage(
			eventData.Creature, 
			eventData.HazardType, 
			eventData.Status, 
			eventData.Absorbed
		)
	end
	
	return nil
end

return BattleMessageGenerator

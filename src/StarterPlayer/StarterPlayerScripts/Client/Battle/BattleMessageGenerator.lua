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
	return string.format("%s used %s!", displayName, moveName)
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
    local msg = string.format("%s fainted!", displayName)
    print("[FAINT][Generator]", msg)
    return msg
end

--[[
	Generates a message for a creature being recalled
	@param creatureName The name of the creature being recalled
	@return Formatted message string
]]
function BattleMessageGenerator.Recall(creatureName: string): string
	return string.format("%s, come back!", creatureName)
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
        return messages[index] or messages[1]
    else
        if trainerName and trainerName ~= "" then
            return string.format("%s sent out %s!", trainerName, creatureName)
        end
        return string.format("Trainer sent out %s!", creatureName)
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
	return string.format("%s gained %d XP!", creatureName, xpAmount)
end

--[[
	Generates a message for EXP Spread
	@return Formatted message string
]]
function BattleMessageGenerator.XPSpread(): string
	return "The rest of your party gained XP thanks to EXP Spread!"
end

--[[
	Generates a message for leveling up
	@param creatureName The name of the creature leveling up
	@param newLevel The new level
	@return Formatted message string
]]
function BattleMessageGenerator.LevelUp(creatureName: string, newLevel: number): string
	return string.format("%s reached Lv. %d!", creatureName, newLevel)
end

--
-- Generates a message for learning a move
-- @param creatureName The name of the creature
-- @param moveName The name of the learned move
-- @return Formatted message string
--
function BattleMessageGenerator.MoveLearned(creatureName: string, moveName: string): string
    return string.format("%s learned %s!", creatureName, moveName)
end

-- Move learn declined
function BattleMessageGenerator.MoveDeclined(creatureName: string, moveName: string): string
    return string.format("%s did not learn %s.", creatureName, moveName)
end

--[[
	Generates a message for evolution
	@param oldName The creature's name before evolution
	@param newName The creature's name after evolution
	@return Formatted message string
]]
function BattleMessageGenerator.Evolution(oldName: string, newName: string): string
	return string.format("%s evolved into %s!", oldName, newName)
end

--[[
	Generates a message for a critical hit
	@return Formatted message string
]]
function BattleMessageGenerator.CriticalHit(): string
	return "A critical hit!"
end

--[[
	Generates a message for a move missing
	@param actorName The name of the creature whose move missed (optional, message may be pre-formatted)
	@return Formatted message string
]]
function BattleMessageGenerator.Miss(actorName: string?): string
	-- If message is already formatted (from server), use it directly
	if actorName and not string.find(actorName, "'s attack missed", 1, true) and not string.find(actorName, "avoided", 1, true) then
		return string.format("%s's attack missed!", actorName)
	end
	-- Default message for when server provides pre-formatted message
	return actorName or "The attack missed!"
end

--[[
	Generates a message for type effectiveness
	@param effectiveness "SuperEffective" | "NotVeryEffective" | "NoEffect"
	@return Formatted message string
]]
function BattleMessageGenerator.Effectiveness(effectiveness: string): string
	if effectiveness == "SuperEffective" then
		return "It's super effective!"
	elseif effectiveness == "NotVeryEffective" then
		return "It's not very effective..."
	elseif effectiveness == "NoEffect" then
		return "It doesn't affect the target..."
	end
	return ""
end

--[[
	Generates a message for status condition application
	@param creatureName The name of the creature
	@param status The status condition
	@return Formatted message string
]]
function BattleMessageGenerator.StatusApplied(creatureName: string, status: string): string
	local statusMessages = {
		Burn = string.format("%s was burned!", creatureName),
		Paralysis = string.format("%s was paralyzed!", creatureName),
		Poison = string.format("%s was poisoned!", creatureName),
		Sleep = string.format("%s fell asleep!", creatureName),
		Freeze = string.format("%s was frozen solid!", creatureName),
	}
	
	return statusMessages[status] or string.format("%s was affected by %s!", creatureName, status)
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
	
	return statusMessages[status] or string.format("%s recovered from %s!", creatureName, status)
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
	
	return string.format("%s's %s %s!", creatureName, statName, changeText)
end

--[[
	Generates a message for escape attempts
	@param success Whether the escape was successful
	@return Formatted message string
]]
function BattleMessageGenerator.Escape(success: boolean): string
	if success then
		return "Got away safely!"
	else
		return "Can't escape!"
	end
end

--[[
	Generates a message for flinching
	@param creatureName The name of the creature that flinched
	@return Formatted message string
]]
function BattleMessageGenerator.Flinch(creatureName: string): string
	return string.format("%s flinched and couldn't move!", creatureName)
end

--[[
	Generates a message for healing
	@param creatureName The name of the creature being healed
	@param amount The amount healed
	@return Formatted message string
]]
function BattleMessageGenerator.Heal(creatureName: string, amount: number): string
	return string.format("%s restored %d HP!", creatureName, amount)
end

--[[
	Generates a message for recoil damage
	@param creatureName The name of the creature taking recoil
	@return Formatted message string
]]
function BattleMessageGenerator.Recoil(creatureName: string): string
	return string.format("%s is damaged by recoil!", creatureName)
end

--[[
	Generates a message for weather effects
	@param weather The weather type
	@param action "Start" | "Continue" | "End"
	@return Formatted message string
]]
function BattleMessageGenerator.Weather(weather: string, action: string): string
	local weatherMessages = {
		Rain = {
			Start = "It started to rain!",
			Continue = "Rain continues to fall.",
			End = "The rain stopped.",
		},
		Sun = {
			Start = "The sunlight turned harsh!",
			Continue = "The sunlight is strong.",
			End = "The harsh sunlight faded.",
		},
		Sandstorm = {
			Start = "A sandstorm kicked up!",
			Continue = "The sandstorm rages.",
			End = "The sandstorm subsided.",
		},
		Hail = {
			Start = "It started to hail!",
			Continue = "Hail continues to fall.",
			End = "The hail stopped.",
		},
	}
	
	if weatherMessages[weather] and weatherMessages[weather][action] then
		return weatherMessages[weather][action]
	end
	
	return ""
end

--[[
	Generates a message for trainer battles
	@param trainerName The trainer's name
	@param action "Challenge" | "Defeat" | "Loss"
	@return Formatted message string
]]
function BattleMessageGenerator.Trainer(trainerName: string, action: string): string
	if action == "Challenge" then
		return string.format("%s wants to battle!", trainerName)
	elseif action == "Defeat" then
		return string.format("You defeated %s!", trainerName)
	elseif action == "Loss" then
		return string.format("You lost to %s!", trainerName)
	end
	return ""
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
		return BattleMessageGenerator.Miss(eventData.Actor)
		
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
	
	elseif eventType == "ItemUse" and eventData.Actor and eventData.Item and eventData.Target then
		-- Ex: "You used an apple on X"
		local actor = eventData.Actor
		local item = eventData.Item
		local target = eventData.Target
		if actor == game.Players.LocalPlayer.Name then
			return string.format("You used an %s on %s", item:lower(), target)
		else
			return string.format("%s used an %s on %s", actor, item:lower(), target)
		end
	end
	
	return nil
end

return BattleMessageGenerator

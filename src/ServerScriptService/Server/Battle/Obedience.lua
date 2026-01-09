--!strict
--[[
	Obedience.lua
	Handles creature obedience checks based on gym badges.
	Traded creatures (OT != player's UserId) will disobey if their level exceeds the obedience cap.
	Own creatures (OT == player's UserId) always obey regardless of level.
]]

local Obedience = {}

-- Obedience level caps based on gym badges
-- Returns the maximum level that will obey (nil = all levels obey)
local function GetObedienceLevelCap(badges: number): number?
	if badges >= 8 then
		return nil -- All levels obey
	elseif badges >= 7 then
		return 80
	elseif badges >= 6 then
		return 70
	elseif badges >= 5 then
		return 60
	elseif badges >= 4 then
		return 50
	elseif badges >= 3 then
		return 40
	elseif badges >= 2 then
		return 30
	elseif badges >= 1 then
		return 20
	else
		return 10 -- 0 badges
	end
end

-- Disobedience behavior types
local DISOBEDIENCE_BEHAVIORS = {
	"ignore",      -- Most common (~50%)
	"randomMove",  -- ~25%
	"sleep",       -- ~15%
	"hurtSelf",    -- ~10%
}

-- Get random disobedience behavior based on probabilities
local function GetDisobedienceBehavior(creature: any): string
	local roll = math.random(1, 100)
	
	if roll <= 50 then
		return "ignore"
	elseif roll <= 75 then
		return "randomMove"
	elseif roll <= 90 then
		return "sleep"
	else
		return "hurtSelf"
	end
end

-- Get disobedience message based on behavior
local function GetDisobedienceMessage(creature: any, behavior: string, randomMoveName: string?): string
	local creatureName = creature.Nickname or creature.Name or "Creature"
	
	if behavior == "ignore" then
		local messages = {
			string.format("%s ignored orders!", creatureName),
			string.format("%s is loafing around!", creatureName),
			string.format("%s pretended not to notice!", creatureName),
		}
		return messages[math.random(1, #messages)]
	elseif behavior == "randomMove" then
		if randomMoveName then
			return string.format("%s decided to use %s!", creatureName, randomMoveName)
		else
			return string.format("%s is acting on its own!", creatureName)
		end
	elseif behavior == "sleep" then
		local messages = {
			string.format("%s began to nap!", creatureName),
			string.format("%s fell asleep!", creatureName),
		}
		return messages[math.random(1, #messages)]
	elseif behavior == "hurtSelf" then
		return string.format("%s won't obey and hurt itself!", creatureName)
	else
		return string.format("%s won't obey!", creatureName)
	end
end

-- Check if a creature will obey based on player's badges and creature's OT
-- Returns (obeys: boolean, disobedienceMessage: string?, disobedienceBehavior: string?)
-- playerBadges: number - Required: the player's badge count
function Obedience.CheckObedience(player: Player, creature: any, playerBadges: number): (boolean, string?, string?)
	if not creature then
		return true, nil, nil
	end
	
	-- Own creatures (OT matches player's UserId) always obey
	if creature.OT == player.UserId then
		return true, nil, nil
	end
	
	-- If no OT field or OT is nil, treat as own creature (backward compatibility)
	if not creature.OT then
		return true, nil, nil
	end
	
	-- Get obedience level cap
	local cap = GetObedienceLevelCap(playerBadges)
	
	-- If cap is nil, all levels obey
	if cap == nil then
		return true, nil, nil
	end
	
	-- Check if creature level exceeds cap
	local creatureLevel = creature.Level or 1
	if creatureLevel > cap then
		-- Creature will disobey
		local behavior = GetDisobedienceBehavior(creature)
		local message = GetDisobedienceMessage(creature, behavior)
		return false, message, behavior
	end
	
	-- Creature obeys
	return true, nil, nil
end

-- Get obedience level cap for a given badge count (public API)
function Obedience.GetObedienceLevelCap(badges: number): number?
	return GetObedienceLevelCap(badges)
end

-- Get disobedience behavior (public API)
function Obedience.GetDisobedienceBehavior(creature: any): string
	return GetDisobedienceBehavior(creature)
end

-- Get disobedience message (public API)
function Obedience.GetDisobedienceMessage(creature: any, behavior: string, randomMoveName: string?): string
	return GetDisobedienceMessage(creature, behavior, randomMoveName)
end

return Obedience


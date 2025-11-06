--[[
	DayNightExample.lua
	Example script showing how to use the Day/Night Cycle system
	
	This demonstrates how to:
	- Get current time information
	- Listen for time period changes
	- Use time-based logic for events
]]

local ServerStorage = game:GetService("ServerStorage")
local DayNightCycle = require(ServerStorage:WaitForChild("Server"):WaitForChild("DayNightCycle"))
local DBG = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("DBG"))

-- Example: Listen for time period changes
local function onTimePeriodChanged(newPeriod, oldPeriod)
	DBG:print("Time period changed from", oldPeriod, "to", newPeriod)
	
	-- Example: Different events based on time period
	if newPeriod == "Day" then
		DBG:print("The sun rises! Day creatures become more active.")
		-- Trigger day-specific events here
		
	elseif newPeriod == "Dusk" then
		DBG:print("The sun sets... Twilight creatures emerge.")
		-- Trigger dusk-specific events here
		
	elseif newPeriod == "Night" then
		DBG:print("Night falls. Nocturnal creatures are now active.")
		-- Trigger night-specific events here
	end
end

-- Connect to the time period change event
DayNightCycle:GetTimePeriodChangedEvent():Connect(onTimePeriodChanged)

-- Example: Check current time and set up time-based logic
local function setupTimeBasedEvents()
	local currentPeriod = DayNightCycle:GetCurrentPeriod()
	local currentTime = DayNightCycle:GetFormattedTime()
	
	DBG:print("Current time:", currentTime, "Period:", currentPeriod)
	
	-- Example: Set up different encounter rates based on time
	if DayNightCycle:IsDay() then
		DBG:print("Day time - Normal encounter rates")
		
	elseif DayNightCycle:IsDusk() then
		DBG:print("Dusk time - Rare creatures may appear")
		
	elseif DayNightCycle:IsNight() then
		DBG:print("Night time - Nocturnal creatures only")
	end
	
	-- Example: Get time until next period change
	local timeUntilNext = DayNightCycle:GetTimeUntilNextPeriod()
	DBG:print("Time until next period change:", timeUntilNext, "seconds")
end

-- Example: Function to check if a specific creature should spawn based on time
local function shouldCreatureSpawn(creatureName, timeOfDay)
	-- Example creature spawn logic
	local spawnRules = {
		["Vampire Bat"] = {"Night"}, -- Only spawns at night
		["Sunflower"] = {"Day"}, -- Only spawns during day
		["Firefly"] = {"Dusk", "Night"}, -- Spawns at dusk and night
		["Common Rat"] = {"Day", "Dusk", "Night"} -- Spawns all day
	}
	
	local allowedTimes = spawnRules[creatureName]
	if not allowedTimes then
		return true -- Default: spawn anytime if no rules
	end
	
	for _, allowedTime in ipairs(allowedTimes) do
		if timeOfDay == allowedTime then
			return true
		end
	end
	
	return false
end

-- Example: Function to get time-based encounter modifiers
local function getEncounterModifier()
	if DayNightCycle:IsDay() then
		return 1.0 -- Normal encounter rate
	elseif DayNightCycle:IsDusk() then
		return 1.2 -- Slightly increased rare encounters
	elseif DayNightCycle:IsNight() then
		return 0.8 -- Reduced overall encounters, but different pool
	end
end

-- Example: Function to get time-based XP modifiers
local function getXPModifier()
	if DayNightCycle:IsNight() then
		return 1.1 -- Slightly increased XP at night (harder to train)
	else
		return 1.0 -- Normal XP during day/dusk
	end
end

-- Initialize the example
setupTimeBasedEvents()

-- Example: Print debug info every 5 minutes
spawn(function()
	while true do
		task.wait(300) -- Wait 5 minutes
		local debugInfo = DayNightCycle:GetDebugInfo()
		DBG:print("=== DAY/NIGHT CYCLE DEBUG ===")
		DBG:print("Current Time:", debugInfo.CurrentTime)
		DBG:print("Current Period:", debugInfo.CurrentPeriod)
		DBG:print("Time Until Next Period:", debugInfo.TimeUntilNextPeriod, "seconds")
		DBG:print("=============================")
	end
end)

-- Export example functions for use in other scripts
return {
	shouldCreatureSpawn = shouldCreatureSpawn,
	getEncounterModifier = getEncounterModifier,
	getXPModifier = getXPModifier,
	onTimePeriodChanged = onTimePeriodChanged
}

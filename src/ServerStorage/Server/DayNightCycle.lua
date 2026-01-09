--[[
	DayNightCycle.lua
	Server-side day and night cycle system for Brainrot Catchers
	
	Provides time tracking and period calculation for time-based events.
	All time logic is handled server-side for security and consistency.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local DBG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DBG"))

local DayNightCycle = {}

-- Midday time configuration
local MIDDAY_SECONDS = 12 * 60 * 60 -- 12:00 (noon) in seconds

-- Check if current context should pause the day/night cycle
local function shouldPauseCycle(): boolean
	local context = Workspace:GetAttribute("Context")
	return context == "Trade" or context == "Battle"
end

-- Force midday lighting
local function forceMidday()
	game.Lighting.ClockTime = 12
	game.Lighting.TimeOfDay = "12:00:00"
end

-- Time periods
local TIME_PERIODS = {
	DAY = "Day",
	DUSK = "Dusk", 
	NIGHT = "Night"
}

-- Time configuration (in seconds)
local CYCLE_CONFIG = {
	TOTAL_CYCLE_SECONDS = 24 * 60 * 60, -- Full day/night cycle duration (24 hours in seconds)
	DAY_START_SECONDS = 6 * 60 * 60,    -- Day starts at 6:00 (6 hours in seconds)
	DAY_END_SECONDS = 18 * 60 * 60,     -- Day ends at 18:00 (18 hours in seconds)
	DUSK_DURATION_SECONDS = 2 * 60      -- Dusk lasts 2 minutes (120 seconds)
}

-- Current cycle state
local CurrentCycleTime = 0 -- Current time in the cycle (0-86400 seconds = 24 hours)
local CurrentPeriod = TIME_PERIODS.DAY
local LastPeriod = TIME_PERIODS.DAY

-- Events for time period changes
local TimePeriodChanged = Instance.new("BindableEvent")

-- Initialize the day/night cycle
function DayNightCycle:Initialize()
	DBG:print("Initializing Day/Night Cycle system")
	
	-- Check if we should pause for Trade/Battle context
	if shouldPauseCycle() then
		DBG:print("Day/Night Cycle paused - Context is Trade or Battle, forcing midday")
		CurrentCycleTime = MIDDAY_SECONDS
		CurrentPeriod = TIME_PERIODS.DAY
		LastPeriod = TIME_PERIODS.DAY
		forceMidday()
	else
		-- Start the cycle at a random time for variety (0 to 24 hours in seconds)
		CurrentCycleTime = math.random(0, CYCLE_CONFIG.TOTAL_CYCLE_SECONDS)
		CurrentPeriod = self:CalculateTimePeriod(CurrentCycleTime)
		LastPeriod = CurrentPeriod
		
		-- Set initial lighting time
		self:UpdateLightingTime()
	end
	
	DBG:print("Day/Night Cycle initialized - Current time:", self:GetFormattedTime(), "Period:", CurrentPeriod)
	DBG:print("Random cycle time:", CurrentCycleTime, "seconds (", math.floor(CurrentCycleTime/3600), "hours", math.floor((CurrentCycleTime%3600)/60), "minutes)")
	
	-- Start the cycle timer
	self:StartCycleTimer()
end

-- Update the lighting time based on current cycle time
function DayNightCycle:UpdateLightingTime()
	local minutes = CurrentCycleTime / 60
	local hours = math.floor(minutes)
	local minutesRemainder = (minutes - hours) * 60
	
	-- Convert to Roblox ClockTime format (0-24 hours as decimal)
	local clockTime = hours + (minutesRemainder / 60)
	
	-- Set the lighting time
	game.Lighting.ClockTime = clockTime
	game.Lighting.TimeOfDay = string.format("%02d:%02d:00", hours, math.floor(minutesRemainder))
end

-- Start the cycle timer that updates every second
function DayNightCycle:StartCycleTimer()
	task.spawn(function()
		while true do
			task.wait(1) -- Update every second
			
			-- Skip cycle updates if in Trade or Battle context - force midday instead
			if shouldPauseCycle() then
				-- Force midday and keep time locked
				CurrentCycleTime = MIDDAY_SECONDS
				CurrentPeriod = TIME_PERIODS.DAY
				forceMidday()
				continue
			end
			
			-- Advance time by 1 second
			CurrentCycleTime = CurrentCycleTime + 1
			
			-- Reset cycle if we've completed a full day
			if CurrentCycleTime >= CYCLE_CONFIG.TOTAL_CYCLE_SECONDS then
				CurrentCycleTime = 0
			end
			
			-- Update lighting time every second
			self:UpdateLightingTime()
			
			-- Check if time period has changed
			local newPeriod = self:CalculateTimePeriod(CurrentCycleTime)
			if newPeriod ~= CurrentPeriod then
				LastPeriod = CurrentPeriod
				CurrentPeriod = newPeriod
				
				DBG:print("Time period changed from", LastPeriod, "to", CurrentPeriod, "at", self:GetFormattedTime())
				
				-- Fire event for time period change
				TimePeriodChanged:Fire(CurrentPeriod, LastPeriod)
				
				-- Notify all clients of time period change
				local Events = game:GetService("ReplicatedStorage"):WaitForChild("Events")
				Events.Communicate:FireAllClients("TimePeriodChanged", CurrentPeriod)
			end
		end
	end)
end

-- Calculate the current time period based on cycle time
function DayNightCycle:CalculateTimePeriod(cycleTime)
	-- Handle day period (6:00 - 18:00)
	if cycleTime >= CYCLE_CONFIG.DAY_START_SECONDS and cycleTime < CYCLE_CONFIG.DAY_END_SECONDS then
		return TIME_PERIODS.DAY
	end
	
	-- Handle dusk period (18:00 - 18:02)
	if cycleTime >= CYCLE_CONFIG.DAY_END_SECONDS and cycleTime < CYCLE_CONFIG.DAY_END_SECONDS + CYCLE_CONFIG.DUSK_DURATION_SECONDS then
		return TIME_PERIODS.DUSK
	end
	
	-- Handle night period (18:02 - 6:00 next day)
	return TIME_PERIODS.NIGHT
end

-- Get the current time period
function DayNightCycle:GetCurrentPeriod()
	return CurrentPeriod
end

-- Get the previous time period
function DayNightCycle:GetLastPeriod()
	return LastPeriod
end

-- Get the current time of day as a string
function DayNightCycle:GetTimeOfDay()
	return self:GetCurrentPeriod()
end

-- Get formatted time string (HH:MM)
function DayNightCycle:GetFormattedTime()
	local totalMinutes = CurrentCycleTime / 60
	local hours = math.floor(totalMinutes)
	local minutes = math.floor((totalMinutes - hours) * 60)
	
	-- Format with leading zeros
	local hoursStr = string.format("%02d", hours)
	local minutesStr = string.format("%02d", minutes)
	
	return hoursStr .. ":" .. minutesStr
end

-- Get the current cycle time in seconds
function DayNightCycle:GetCycleTime()
	return CurrentCycleTime
end

-- Get the current cycle time in minutes
function DayNightCycle:GetCycleTimeMinutes()
	return CurrentCycleTime / 60
end

-- Check if it's currently a specific time period
function DayNightCycle:IsPeriod(period)
	return CurrentPeriod == period
end

-- Check if it's currently day time
function DayNightCycle:IsDay()
	return self:IsPeriod(TIME_PERIODS.DAY)
end

-- Check if it's currently dusk
function DayNightCycle:IsDusk()
	return self:IsPeriod(TIME_PERIODS.DUSK)
end

-- Check if it's currently night time
function DayNightCycle:IsNight()
	return self:IsPeriod(TIME_PERIODS.NIGHT)
end

-- Get the time until the next period change (in seconds)
function DayNightCycle:GetTimeUntilNextPeriod()
	local nextChangeTime = 0
	
	if CurrentPeriod == TIME_PERIODS.DAY then
		nextChangeTime = CYCLE_CONFIG.DAY_END_SECONDS
	elseif CurrentPeriod == TIME_PERIODS.DUSK then
		nextChangeTime = CYCLE_CONFIG.DAY_END_SECONDS + CYCLE_CONFIG.DUSK_DURATION_SECONDS
	elseif CurrentPeriod == TIME_PERIODS.NIGHT then
		nextChangeTime = CYCLE_CONFIG.TOTAL_CYCLE_SECONDS
	end
	
	-- Handle wrap-around for night to day transition
	if nextChangeTime <= CurrentCycleTime then
		nextChangeTime = nextChangeTime + CYCLE_CONFIG.TOTAL_CYCLE_SECONDS
	end
	
	return nextChangeTime - CurrentCycleTime
end

-- Get the event for time period changes
function DayNightCycle:GetTimePeriodChangedEvent()
	return TimePeriodChanged
end

-- Get all available time periods
function DayNightCycle:GetTimePeriods()
	return TIME_PERIODS
end

-- Get cycle configuration
function DayNightCycle:GetCycleConfig()
	return CYCLE_CONFIG
end

-- Debug function to set a specific time (for testing)
function DayNightCycle:SetTime(hours, minutes)
	if hours < 0 or hours >= 24 or minutes < 0 or minutes >= 60 then
		DBG:warn("Invalid time provided to SetTime:", hours, minutes)
		return false
	end
	
	CurrentCycleTime = (hours * 60 + minutes) * 60
	local newPeriod = self:CalculateTimePeriod(CurrentCycleTime)
	
	if newPeriod ~= CurrentPeriod then
		LastPeriod = CurrentPeriod
		CurrentPeriod = newPeriod
		TimePeriodChanged:Fire(CurrentPeriod, LastPeriod)
	end
	
	DBG:print("Time manually set to:", self:GetFormattedTime(), "Period:", CurrentPeriod)
	return true
end

-- Debug function to get cycle status
function DayNightCycle:GetDebugInfo()
	return {
		CurrentTime = self:GetFormattedTime(),
		CurrentPeriod = CurrentPeriod,
		LastPeriod = LastPeriod,
		CycleTimeSeconds = CurrentCycleTime,
		CycleTimeMinutes = self:GetCycleTimeMinutes(),
		TimeUntilNextPeriod = self:GetTimeUntilNextPeriod(),
		Config = CYCLE_CONFIG
	}
end

return DayNightCycle

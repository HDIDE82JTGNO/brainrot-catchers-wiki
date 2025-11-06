--[[
	DayNightLighting.lua
	Client-side lighting system that modifies brightness, exposure, and other properties
	based on the server's day/night cycle.
	
	Assumes all lighting modules are designed for day time (12:00 baseline).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local DBG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DBG"))

local DayNightLighting = {}
local SyncEnabled = true

-- Component-wise Color3 multiply
local function multiplyColor3(a: Color3, b: Color3): Color3
	return Color3.new(a.R * b.R, a.G * b.G, a.B * b.B)
end

-- Lighting modifiers for different time periods
local LIGHTING_MODIFIERS = {
	-- Day time (6:00 - 18:00) - Normal lighting
	Day = {
		Brightness = 1.0,           -- Full brightness
		ExposureCompensation = 0,   -- No exposure adjustment
		Ambient = Color3.new(1, 1, 1), -- No color tint
		OutdoorAmbient = Color3.new(1, 1, 1), -- No outdoor tint
		FogColor = Color3.new(1, 1, 1), -- No fog tint
		ShadowColor = Color3.new(1, 1, 1), -- No shadow tint
	},
	
	-- Dusk time (18:00 - 18:02) - Transitional lighting
	Dusk = {
		Brightness = 0.85,           -- Slightly reduced brightness (brighter than before)
		ExposureCompensation = -0.1, -- Gentle darkening for mood
		Ambient = Color3.new(1, 0.9, 0.75), -- Warm, but closer to neutral
		OutdoorAmbient = Color3.new(1, 0.85, 0.7), -- Warm outdoor tint
		FogColor = Color3.new(1, 0.8, 0.6), -- Softer orange fog
		ShadowColor = Color3.new(0.9, 0.8, 0.65), -- Softer warm shadows
	},
	
	-- Night time (18:02 - 6:00) - Dark lighting
	Night = {
		Brightness = 1.1,            -- Elevated brightness for high visibility at night
		ExposureCompensation = 0.15, -- Slight positive exposure to lift dark areas
		Ambient = Color3.new(1.0, 1.0, 1.0), -- Neutral bright ambient
		OutdoorAmbient = Color3.new(0.95, 0.98, 1.0), -- Very light cool outdoor tint
		FogColor = Color3.new(0.9, 0.95, 1.0), -- Light fog for clarity
		ShadowColor = Color3.new(0.9, 0.95, 1.0), -- Much lighter shadows at night
	}
}

-- Base lighting values (stored when lighting is first applied)
local BaseLightingValues = {}
local IsInitialized = false

-- Initialize the day/night lighting system
function DayNightLighting:Initialize()
	if IsInitialized then return end
	
	DBG:print("Initializing Day/Night Lighting system")
	
	-- Store base lighting values
	self:StoreBaseLightingValues()
	
	-- Start listening for time period changes
	self:StartTimeListener()
	
	IsInitialized = true
	DBG:print("Day/Night Lighting system initialized")
end

-- Store the current lighting values as baseline (assumed to be day lighting)
function DayNightLighting:StoreBaseLightingValues()
	BaseLightingValues = {
		Brightness = game.Lighting.Brightness,
		ExposureCompensation = game.Lighting.ExposureCompensation,
		Ambient = game.Lighting.Ambient,
		OutdoorAmbient = game.Lighting.OutdoorAmbient,
		FogColor = game.Lighting.FogColor,
		ShadowColor = game.Lighting.ShadowColor,
	}
	
	DBG:print("=== STORED BASE LIGHTING VALUES ===")
	DBG:print("Brightness:", BaseLightingValues.Brightness)
	DBG:print("ExposureCompensation:", BaseLightingValues.ExposureCompensation)
	DBG:print("Ambient:", BaseLightingValues.Ambient)
	DBG:print("=== END BASE VALUES ===")
end

-- Start listening for time period changes from server
function DayNightLighting:StartTimeListener()
	-- Listen for time period changes via server events
	local Events = ReplicatedStorage:WaitForChild("Events")
	
	Events.Communicate.OnClientEvent:Connect(function(EventType, Data)
		if not SyncEnabled then return end
		DBG:print("Received event:", EventType, "Data:", Data)
		if EventType == "TimePeriodChanged" then
			DBG:print("Received time period change:", Data)
			self:UpdateLightingForPeriod(Data)
		end
	end)
	
	-- Also check current time period on initialization
	task.spawn(function()
		task.wait(1) -- Wait for server to be ready
		local currentPeriod = self:GetCurrentTimePeriod()
		if currentPeriod then
			self:UpdateLightingForPeriod(currentPeriod)
		end
	end)
end

-- Get current time period from server
function DayNightLighting:GetCurrentTimePeriod()
	local success, result = pcall(function()
		local RemoteFunction = ReplicatedStorage:WaitForChild("Events"):WaitForChild("Request")
		return RemoteFunction:InvokeServer({"GetCurrentTimePeriod"})
	end)
	
	if success and result then
		DBG:print("Current time period from server:", result)
		return result
	else
		DBG:warn("Failed to get current time period from server")
		return nil
	end
end

-- Update lighting based on time period
function DayNightLighting:UpdateLightingForPeriod(period)
	if not SyncEnabled then return end
	if not BaseLightingValues.Brightness then
		DBG:warn("Base lighting values not stored, cannot update lighting")
		return
	end
	
	local modifiers = LIGHTING_MODIFIERS[period]
	if not modifiers then
		DBG:warn("Unknown time period:", period)
		return
	end
	
	DBG:print("=== UPDATING LIGHTING FOR PERIOD:", period, "===")
	DBG:print("Base Brightness:", BaseLightingValues.Brightness)
	DBG:print("Modifier Brightness:", modifiers.Brightness)
	DBG:print("New Brightness:", BaseLightingValues.Brightness * modifiers.Brightness)
	
	-- Apply lighting modifications
	game.Lighting.Brightness = BaseLightingValues.Brightness * modifiers.Brightness
	game.Lighting.ExposureCompensation = BaseLightingValues.ExposureCompensation + modifiers.ExposureCompensation
	
	-- Apply color modifications (component-wise multiply)
	game.Lighting.Ambient = multiplyColor3(BaseLightingValues.Ambient, modifiers.Ambient)
	game.Lighting.OutdoorAmbient = multiplyColor3(BaseLightingValues.OutdoorAmbient, modifiers.OutdoorAmbient)
	game.Lighting.FogColor = multiplyColor3(BaseLightingValues.FogColor, modifiers.FogColor)
	game.Lighting.ShadowColor = multiplyColor3(BaseLightingValues.ShadowColor, modifiers.ShadowColor)
	
	DBG:print("Lighting updated - Brightness:", game.Lighting.Brightness, "Exposure:", game.Lighting.ExposureCompensation)
	DBG:print("=== END LIGHTING UPDATE ===")
end

-- Smooth transition between lighting states
function DayNightLighting:TransitionToPeriod(period, duration)
	if not SyncEnabled then return end
	duration = duration or 2 -- Default 2 second transition
	
	if not BaseLightingValues.Brightness then
		DBG:warn("Base lighting values not stored, cannot transition")
		return
	end
	
	local modifiers = LIGHTING_MODIFIERS[period]
	if not modifiers then
		DBG:warn("Unknown time period:", period)
		return
	end
	
	DBG:print("Transitioning to period:", period, "over", duration, "seconds")
	
	-- Store current values as starting point
	local startValues = {
		Brightness = game.Lighting.Brightness,
		ExposureCompensation = game.Lighting.ExposureCompensation,
		Ambient = game.Lighting.Ambient,
		OutdoorAmbient = game.Lighting.OutdoorAmbient,
		FogColor = game.Lighting.FogColor,
		ShadowColor = game.Lighting.ShadowColor,
	}
	
	-- Calculate target values
	local targetValues = {
		Brightness = BaseLightingValues.Brightness * modifiers.Brightness,
		ExposureCompensation = BaseLightingValues.ExposureCompensation + modifiers.ExposureCompensation,
		Ambient = multiplyColor3(BaseLightingValues.Ambient, modifiers.Ambient),
		OutdoorAmbient = multiplyColor3(BaseLightingValues.OutdoorAmbient, modifiers.OutdoorAmbient),
		FogColor = multiplyColor3(BaseLightingValues.FogColor, modifiers.FogColor),
		ShadowColor = multiplyColor3(BaseLightingValues.ShadowColor, modifiers.ShadowColor),
	}
	
	-- Animate the transition
	local startTime = tick()
	local connection
	
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		local alpha = math.min(elapsed / duration, 1)
		
		-- Smooth interpolation
		local smoothAlpha = alpha * alpha * (3 - 2 * alpha) -- Smoothstep
		
		-- Interpolate values
		game.Lighting.Brightness = startValues.Brightness + (targetValues.Brightness - startValues.Brightness) * smoothAlpha
		game.Lighting.ExposureCompensation = startValues.ExposureCompensation + (targetValues.ExposureCompensation - startValues.ExposureCompensation) * smoothAlpha
		
		-- Interpolate colors
		game.Lighting.Ambient = startValues.Ambient:Lerp(targetValues.Ambient, smoothAlpha)
		game.Lighting.OutdoorAmbient = startValues.OutdoorAmbient:Lerp(targetValues.OutdoorAmbient, smoothAlpha)
		game.Lighting.FogColor = startValues.FogColor:Lerp(targetValues.FogColor, smoothAlpha)
		game.Lighting.ShadowColor = startValues.ShadowColor:Lerp(targetValues.ShadowColor, smoothAlpha)
		
		if alpha >= 1 then
			connection:Disconnect()
			DBG:print("Lighting transition completed")
		end
	end)
end

-- Force refresh base lighting values (call when new lighting is applied)
function DayNightLighting:RefreshBaseValues()
	DBG:print("Refreshing base lighting values")
	self:StoreBaseLightingValues()
	
	-- Reapply current time period
	if SyncEnabled then
		local currentPeriod = self:GetCurrentTimePeriod()
		if currentPeriod then
			self:UpdateLightingForPeriod(currentPeriod)
		end
	end
end

-- Get current lighting modifiers
function DayNightLighting:GetLightingModifiers()
	return LIGHTING_MODIFIERS
end

-- Get base lighting values
function DayNightLighting:GetBaseLightingValues()
	return BaseLightingValues
end

-- Debug function to manually set time period
function DayNightLighting:SetTimePeriod(period)
	DBG:print("Manually setting time period to:", period)
	self:UpdateLightingForPeriod(period)
end

-- Debug function to test all time periods
function DayNightLighting:TestAllPeriods()
	DBG:print("=== TESTING ALL TIME PERIODS ===")
	
	-- Store current values first
	self:StoreBaseLightingValues()
	
	-- Test each period
	for periodName, _ in pairs(LIGHTING_MODIFIERS) do
		DBG:print("Testing period:", periodName)
		self:UpdateLightingForPeriod(periodName)
		task.wait(2) -- Wait 2 seconds between tests
	end
	
	DBG:print("=== END TEST ===")
end

-- Debug function to get current status
function DayNightLighting:GetDebugStatus()
	return {
		IsInitialized = IsInitialized,
		SyncEnabled = SyncEnabled,
		BaseValuesStored = BaseLightingValues.Brightness ~= nil,
		CurrentBrightness = game.Lighting.Brightness,
		BaseBrightness = BaseLightingValues.Brightness,
		CurrentExposure = game.Lighting.ExposureCompensation,
		BaseExposure = BaseLightingValues.ExposureCompensation,
		AvailablePeriods = LIGHTING_MODIFIERS
	}
end

function DayNightLighting:SetSyncEnabled(enabled: boolean)
	SyncEnabled = enabled
	DBG:print("DayNight sync:", enabled and "enabled" or "disabled")
	if enabled then
		self:RefreshBaseValues()
	end
end

return DayNightLighting

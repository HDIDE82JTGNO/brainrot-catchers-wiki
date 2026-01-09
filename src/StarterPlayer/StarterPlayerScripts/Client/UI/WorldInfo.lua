--[[
	WorldInfo.lua
	Client-side UI for displaying current time and weather
	
	Features:
	- Shows current game time in 12:34pm format
	- Shows current weather name and icon
	- Hover to reveal, syncs with TopBar visibility
	- Auto-updates from server weather events
]]

local WorldInfo = {}

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local DBG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DBG"))

-- Weather VFX module
local Utilities = script.Parent.Parent:WaitForChild("Utilities")
local WeatherVFX = require(Utilities:WaitForChild("WeatherVFX"))

--============================================================================
-- POSITION CONSTANTS
--============================================================================

local POSITIONS = {
	OnScreen = UDim2.new(0.5, 0, 0.93, 0),
	OffScreen = UDim2.new(0.5, 0, 1.052, 0),
	FullyOffScreen = UDim2.new(0.5, 0, 1.2, 0),
}

--============================================================================
-- WEATHER ICON OFFSETS (ImageRectOffset)
--============================================================================

local WEATHER_ICON_OFFSETS = {
	[1] = Vector2.new(0, 0),      -- Clear
	[2] = Vector2.new(114, 0),    -- Harsh Sun
	[3] = Vector2.new(234, 0),    -- Snowstorm
	[4] = Vector2.new(354, 0),    -- Snow
	[5] = Vector2.new(474, 0),    -- Fog
	[6] = Vector2.new(591, 0),    -- Overcast
	[7] = Vector2.new(700, 0),    -- Rain
	[8] = Vector2.new(812, 0),    -- Thunderstorm
	[9] = Vector2.new(916, 0),    -- Sandstorm
}

-- Weather names by ID
local WEATHER_NAMES = {
	[1] = "Clear",
	[2] = "Harsh Sun",
	[3] = "Snowstorm",
	[4] = "Snow",
	[5] = "Fog",
	[6] = "Overcast",
	[7] = "Rain",
	[8] = "Thunderstorm",
	[9] = "Sandstorm",
}

--============================================================================
-- STATE
--============================================================================

local WorldInfoFrame = nil
local TimeLabel = nil
local WeatherTypeLabel = nil
local WeatherIcon = nil
local HoverShow = nil

local IsHovering = false
local IsTopBarVisible = false
local IsInitialized = false

-- Weather data per chunk: {[chunkName]: {Id, Name, Icon, ...}}
local ChunkWeatherData = {}
local CurrentChunkName = nil

-- Connections
local Connections = {}

--============================================================================
-- TWEEN HELPERS
--============================================================================

local TweenInfo_Fast = TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

local function TweenToPosition(targetPos)
	if not WorldInfoFrame then return end
	local tween = TweenService:Create(WorldInfoFrame, TweenInfo_Fast, {Position = targetPos})
	tween:Play()
end

--============================================================================
-- TIME FORMATTING
--============================================================================

local function FormatTime12Hour(clockTime: number): string
	-- clockTime is 0-24 decimal (e.g., 13.5 = 1:30 PM)
	local hours = math.floor(clockTime)
	local minutes = math.floor((clockTime - hours) * 60)
	
	local period = "am"
	local displayHour = hours
	
	if hours == 0 then
		displayHour = 12
		period = "am"
	elseif hours == 12 then
		displayHour = 12
		period = "pm"
	elseif hours > 12 then
		displayHour = hours - 12
		period = "pm"
	end
	
	return string.format("%d:%02d%s", displayHour, minutes, period)
end

local function UpdateTimeDisplay()
	if not TimeLabel then return end
	
	local clockTime = Lighting.ClockTime
	TimeLabel.Text = FormatTime12Hour(clockTime)
end

--============================================================================
-- WEATHER DISPLAY
--============================================================================

local function UpdateWeatherDisplay()
	if not WeatherTypeLabel or not WeatherIcon then return end
	
	-- Get current chunk's weather
	local weatherData = nil
	if CurrentChunkName then
		weatherData = ChunkWeatherData[CurrentChunkName]
	end
	
	if weatherData then
		WeatherTypeLabel.Text = weatherData.Name or "Clear"
		local iconOffset = WEATHER_ICON_OFFSETS[weatherData.Id] or Vector2.new(0, 0)
		WeatherIcon.ImageRectOffset = iconOffset
	else
		-- Default to Clear
		WeatherTypeLabel.Text = "Clear"
		WeatherIcon.ImageRectOffset = Vector2.new(0, 0)
	end
end

--============================================================================
-- VISIBILITY LOGIC
--============================================================================

local function UpdatePosition()
	if not WorldInfoFrame then return end
	
	if IsTopBarVisible then
		if IsHovering then
			TweenToPosition(POSITIONS.OnScreen)
		else
			TweenToPosition(POSITIONS.OffScreen)
		end
	else
		TweenToPosition(POSITIONS.FullyOffScreen)
	end
end

--============================================================================
-- PUBLIC API
--============================================================================

function WorldInfo:Init()
	if IsInitialized then return end
	IsInitialized = true
	
	-- Get UI elements
	local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
	local GameUI = PlayerGui:WaitForChild("GameUI")
	
	WorldInfoFrame = GameUI:FindFirstChild("WorldInfo")
	if not WorldInfoFrame then
		DBG:warn("[WorldInfo] WorldInfo frame not found in GameUI")
		return
	end
	
	TimeLabel = WorldInfoFrame:FindFirstChild("Time")
	WeatherTypeLabel = WorldInfoFrame:FindFirstChild("WeatherType")
	WeatherIcon = WorldInfoFrame:FindFirstChild("Weather")
	HoverShow = WorldInfoFrame:FindFirstChild("HoverShow")
	
	if not TimeLabel then DBG:warn("[WorldInfo] Time label not found") end
	if not WeatherTypeLabel then DBG:warn("[WorldInfo] WeatherType label not found") end
	if not WeatherIcon then DBG:warn("[WorldInfo] Weather icon not found") end
	if not HoverShow then DBG:warn("[WorldInfo] HoverShow not found") end
	
	-- Start fully off screen
	WorldInfoFrame.Position = POSITIONS.FullyOffScreen
	WorldInfoFrame.Visible = true
	
	-- Setup hover detection
	if HoverShow then
		Connections.MouseEnter = HoverShow.MouseEnter:Connect(function()
			IsHovering = true
			UpdatePosition()
		end)
		
		Connections.MouseLeave = HoverShow.MouseLeave:Connect(function()
			IsHovering = false
			UpdatePosition()
		end)
	end
	
	-- Setup time update loop
	Connections.TimeUpdate = RunService.Heartbeat:Connect(function()
		UpdateTimeDisplay()
	end)
	
	-- Listen for weather updates from server
	local Events = ReplicatedStorage:FindFirstChild("Events")
	if Events then
		local Communicate = Events:FindFirstChild("Communicate")
		if Communicate then
			Connections.WeatherUpdate = Communicate.OnClientEvent:Connect(function(eventType, data)
				if eventType == "WeatherUpdate" then
					self:HandleWeatherUpdate(data)
				end
			end)
		end
	end
	
	-- Initialize WeatherVFX
	WeatherVFX:Init()
	
	DBG:print("[WorldInfo] Initialized")
end

function WorldInfo:HandleWeatherUpdate(data)
	if not data then return end
	
	local chunkName = data.ChunkName
	if chunkName then
		-- Store weather for this chunk
		ChunkWeatherData[chunkName] = {
			Id = data.Id,
			Name = data.Name,
			Description = data.Description,
			Icon = data.Icon,
			VisualEffects = data.VisualEffects,
			AmbientSound = data.AmbientSound,
		}
		
		DBG:print("[WorldInfo] Received weather for", chunkName, ":", data.Name)
		
		-- Update display if this is the current chunk
		if chunkName == CurrentChunkName then
			UpdateWeatherDisplay()
			-- Update weather VFX
			WeatherVFX:SetWeather(data.Name)
		end
	end
end

function WorldInfo:SetCurrentChunk(chunkName: string)
	CurrentChunkName = chunkName
	
	-- If we don't have weather data for this chunk, request it from the server
	if not ChunkWeatherData[chunkName] then
		DBG:print("[WorldInfo] No weather data for", chunkName, "- requesting from server")
		self:RequestWeatherFromServer(chunkName)
	else
		UpdateWeatherDisplay()
		-- Update weather VFX for current chunk
		local weatherData = ChunkWeatherData[chunkName]
		if weatherData then
			WeatherVFX:SetWeather(weatherData.Name)
		else
			WeatherVFX:SetWeather(nil)
		end
	end
	
	DBG:print("[WorldInfo] Current chunk set to:", chunkName)
end

function WorldInfo:RequestWeatherFromServer(chunkName: string)
	-- Request weather for this chunk from the server
	local Events = ReplicatedStorage:FindFirstChild("Events")
	if not Events then return end
	
	local Request = Events:FindFirstChild("Request")
	if not Request then return end
	
	-- Ask server for weather data
	task.spawn(function()
		local success, result = pcall(function()
			return Request:InvokeServer({"GetChunkWeather", chunkName})
		end)
		
		if success and result then
			-- Store the weather data
			ChunkWeatherData[chunkName] = {
				Id = result.Id,
				Name = result.Name,
				Description = result.Description,
				Icon = result.Icon,
				VisualEffects = result.VisualEffects,
				AmbientSound = result.AmbientSound,
			}
			
			DBG:print("[WorldInfo] Received weather for", chunkName, ":", result.Name)
			
			-- Update display if this is still the current chunk
			if chunkName == CurrentChunkName then
				UpdateWeatherDisplay()
				-- Update weather VFX
				WeatherVFX:SetWeather(result.Name)
			end
		else
			DBG:warn("[WorldInfo] Failed to get weather for", chunkName)
		end
	end)
end

function WorldInfo:SetTopBarVisible(visible: boolean)
	IsTopBarVisible = visible
	UpdatePosition()
end

function WorldInfo:Show()
	IsTopBarVisible = true
	UpdatePosition()
end

function WorldInfo:Hide()
	IsTopBarVisible = false
	IsHovering = false
	UpdatePosition()
end

function WorldInfo:GetWeatherForChunk(chunkName: string)
	return ChunkWeatherData[chunkName]
end

function WorldInfo:GetCurrentWeather()
	if CurrentChunkName then
		return ChunkWeatherData[CurrentChunkName]
	end
	return nil
end

function WorldInfo:Cleanup()
	for name, connection in pairs(Connections) do
		if connection then
			connection:Disconnect()
		end
	end
	Connections = {}
	
	-- Clean up weather VFX
	WeatherVFX:Cleanup()
	
	IsInitialized = false
end

return WorldInfo


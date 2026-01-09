--[[
	WeatherVFX.lua
	Client-side weather visual effects manager
	
	Features:
	- Displays weather VFX parts above player's HRP
	- Automatically swaps effects when weather or chunks change
	- Manages terrain clouds for Rain and Thunderstorm
	- Parts follow player movement continuously
]]

local WeatherVFX = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Terrain = workspace.Terrain

local LocalPlayer = Players.LocalPlayer
local DBG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DBG"))

--============================================================================
-- WEATHER HEIGHT CONFIGURATION
--============================================================================

local WEATHER_HEIGHTS = {
	["Snowstorm"] = 25,
	["Fog"] = 15,
	["Sandstorm"] = 15,
	["Rain"] = 20,
	["Snow"] = 20,
	["Thunderstorm"] = 20,
}

-- Weather types that require terrain clouds
local WEATHER_WITH_CLOUDS = {
	["Rain"] = {
		Color = Color3.fromRGB(232, 232, 232),
		Cover = 0.7,
		Density = 0.5,
	},
	["Thunderstorm"] = {
		Color = Color3.fromRGB(109, 109, 109),
		Cover = 0.8,
		Density = 1,
	},
}

--============================================================================
-- STATE
--============================================================================

local ActiveVFXPart = nil :: BasePart?
local CurrentWeatherName = nil :: string?
local PositionUpdateConnection = nil :: RBXScriptConnection?
local AssetsFolder = nil :: Folder?
local WeatherVFXFolder = nil :: Folder?

-- Battle-specific weather VFX state
local BattleVFXParts = {} :: {BasePart}
local BattleWeatherName = nil :: string?

--============================================================================
-- INTERNAL FUNCTIONS
--============================================================================

-- Clean up the current active VFX part
local function CleanupCurrentVFX()
	if ActiveVFXPart then
		pcall(function()
			ActiveVFXPart:Destroy()
		end)
		ActiveVFXPart = nil
	end
	
	if PositionUpdateConnection then
		PositionUpdateConnection:Disconnect()
		PositionUpdateConnection = nil
	end
end

-- Remove terrain clouds
local function RemoveTerrainClouds()
	pcall(function()
		Terrain:SetClouds({
			Cover = 0,
			Density = 0,
			Color = Color3.new(1, 1, 1),
		})
	end)
end

-- Set terrain clouds for a specific weather
local function SetTerrainClouds(weatherName: string)
	local cloudConfig = WEATHER_WITH_CLOUDS[weatherName]
	if not cloudConfig then
		return
	end
	
	pcall(function()
		Terrain:SetClouds({
			Cover = cloudConfig.Cover,
			Density = cloudConfig.Density,
			Color = cloudConfig.Color,
		})
		DBG:print("[WeatherVFX] Set terrain clouds for", weatherName)
	end)
end

-- Update the VFX part position to follow the player
local function UpdateVFXPosition()
	if not ActiveVFXPart then
		return
	end
	
	local character = LocalPlayer.Character
	if not character then
		return
	end
	
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	
	local weatherName = CurrentWeatherName
	if not weatherName then
		return
	end
	
	local height = WEATHER_HEIGHTS[weatherName]
	if not height then
		return
	end
	
	-- Position the part above the player's HRP
	local newPosition = hrp.Position + Vector3.new(0, height, 0)
	ActiveVFXPart.CFrame = CFrame.new(newPosition)
end

-- Start the position tracking loop
local function StartPositionTracking()
	if PositionUpdateConnection then
		return -- Already tracking
	end
	
	-- Use RenderStepped for maximum update frequency (runs right before rendering)
	PositionUpdateConnection = RunService.RenderStepped:Connect(function()
		UpdateVFXPosition()
	end)
end

--============================================================================
-- PUBLIC API
--============================================================================

-- Initialize the WeatherVFX system
function WeatherVFX:Init()
	-- Wait for Assets folder
	AssetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if not AssetsFolder then
		DBG:warn("[WeatherVFX] Assets folder not found in ReplicatedStorage")
		return false
	end
	
	-- Wait for WeatherVFX folder
	WeatherVFXFolder = AssetsFolder:FindFirstChild("WeatherVFX")
	if not WeatherVFXFolder then
		DBG:warn("[WeatherVFX] WeatherVFX folder not found in Assets")
		return false
	end
	
	DBG:print("[WeatherVFX] Initialized")
	return true
end

-- Set the current weather and update VFX accordingly
function WeatherVFX:SetWeather(weatherName: string?)
	-- Handle nil or empty weather (clear weather)
	if not weatherName or weatherName == "" or weatherName == "Clear" then
		CleanupCurrentVFX()
		RemoveTerrainClouds()
		CurrentWeatherName = nil
		return
	end
	
	-- Check if weather has VFX support
	if not WEATHER_HEIGHTS[weatherName] then
		-- Weather doesn't have VFX yet, but still clean up previous weather
		if CurrentWeatherName ~= weatherName then
			CleanupCurrentVFX()
			RemoveTerrainClouds()
			CurrentWeatherName = weatherName
		end
		return
	end
	
	-- If same weather, don't recreate
	if CurrentWeatherName == weatherName and ActiveVFXPart then
		return
	end
	
	-- Clean up previous weather
	CleanupCurrentVFX()
	RemoveTerrainClouds()
	
	-- Get the VFX part template
	if not WeatherVFXFolder then
		DBG:warn("[WeatherVFX] WeatherVFX folder not available")
		return
	end
	
	local vfxTemplate = WeatherVFXFolder:FindFirstChild(weatherName)
	if not vfxTemplate then
		DBG:warn("[WeatherVFX] VFX part not found for weather:", weatherName)
		CurrentWeatherName = weatherName
		return
	end
	
	-- Clone the VFX part
	local success, clonedPart = pcall(function()
		return vfxTemplate:Clone()
	end)
	
	if not success or not clonedPart then
		DBG:warn("[WeatherVFX] Failed to clone VFX part for:", weatherName)
		CurrentWeatherName = weatherName
		return
	end
	
	-- Setup the cloned part
	clonedPart.Parent = workspace
	ActiveVFXPart = clonedPart
	
	-- Set initial position
	local character = LocalPlayer.Character
	if character then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local height = WEATHER_HEIGHTS[weatherName]
			clonedPart.CFrame = CFrame.new(hrp.Position + Vector3.new(0, height, 0))
		end
	end
	
	-- Start position tracking
	StartPositionTracking()
	
	-- Set terrain clouds if needed
	SetTerrainClouds(weatherName)
	
	CurrentWeatherName = weatherName
	DBG:print("[WeatherVFX] Set weather VFX to:", weatherName)
end

-- Clean up all VFX (called on cleanup or player removal)
function WeatherVFX:Cleanup()
	CleanupCurrentVFX()
	RemoveTerrainClouds()
	CurrentWeatherName = nil
end

--============================================================================
-- BATTLE WEATHER VFX
--============================================================================

-- Map battle weather names to WeatherConfig names
local function MapBattleWeatherToConfig(battleWeather: string, weatherName: string?): string?
	if battleWeather == "Sunlight" then
		return "Harsh Sun"
	elseif battleWeather == "Rain" then
		-- Use Thunderstorm if WeatherName indicates it, otherwise Rain
		if weatherName == "Thunderstorm" then
			return "Thunderstorm"
		end
		return "Rain"
	elseif battleWeather == "Sandstorm" then
		return "Sandstorm"
	elseif battleWeather == "Snow" then
		-- Use Snowstorm if WeatherName indicates it, otherwise Snow
		if weatherName == "Snowstorm" then
			return "Snowstorm"
		end
		return "Snow"
	end
	return nil
end

-- Clean up battle weather VFX
local function CleanupBattleVFX()
	for _, part in ipairs(BattleVFXParts) do
		pcall(function()
			part:Destroy()
		end)
	end
	BattleVFXParts = {}
	BattleWeatherName = nil
end

-- Set weather VFX for battle scenes
-- @param battleWeather Battle weather name ("Sunlight", "Rain", "Sandstorm", "Snow")
-- @param weatherName Optional WeatherConfig name for more specific mapping
-- @param scene The battle scene model
-- @param playerSpawn Player creature spawn point
-- @param foeSpawn Foe creature spawn point
function WeatherVFX:SetBattleWeather(battleWeather: string?, weatherName: string?, scene: Model?, playerSpawn: BasePart?, foeSpawn: BasePart?)
	-- Handle nil or empty weather
	if not battleWeather or battleWeather == "" then
		CleanupBattleVFX()
		return
	end
	
	-- Ensure WeatherVFXFolder is initialized
	if not WeatherVFXFolder then
		if not self:Init() then
			DBG:warn("[WeatherVFX] Failed to initialize WeatherVFX folder for battle")
			return
		end
	end
	
	-- Map battle weather to WeatherConfig name
	local configWeatherName = MapBattleWeatherToConfig(battleWeather, weatherName)
	if not configWeatherName then
		DBG:print("[WeatherVFX] No VFX mapping for battle weather:", battleWeather)
		CleanupBattleVFX()
		return
	end
	
	-- Check if weather has VFX support
	if not WEATHER_HEIGHTS[configWeatherName] then
		DBG:print("[WeatherVFX] Weather", configWeatherName, "does not have VFX support")
		CleanupBattleVFX()
		return
	end
	
	-- Clean up previous battle weather (always cleanup before creating new)
	CleanupBattleVFX()
	
	-- Get the VFX part template
	if not WeatherVFXFolder then
		DBG:warn("[WeatherVFX] WeatherVFX folder not available for battle")
		return
	end
	
	local vfxTemplate = WeatherVFXFolder:FindFirstChild(configWeatherName)
	if not vfxTemplate then
		DBG:warn("[WeatherVFX] VFX part not found for weather:", configWeatherName)
		return
	end
	
	-- Determine position for VFX
	-- If we have both spawn points, center between them; otherwise use available spawn point
	local vfxPosition: Vector3?
	local height = WEATHER_HEIGHTS[configWeatherName] or 20
	
	if playerSpawn and foeSpawn then
		-- Center between spawn points
		local centerPos = (playerSpawn.Position + foeSpawn.Position) / 2
		vfxPosition = centerPos + Vector3.new(0, height, 0)
	elseif playerSpawn then
		vfxPosition = playerSpawn.Position + Vector3.new(0, height, 0)
	elseif foeSpawn then
		vfxPosition = foeSpawn.Position + Vector3.new(0, height, 0)
	else
		DBG:warn("[WeatherVFX] No spawn points available for battle weather VFX")
		return
	end
	
	if not vfxPosition then
		return
	end
	
	-- Clone and position the VFX part
	local success, clonedPart = pcall(function()
		return vfxTemplate:Clone()
	end)
	
	if not success or not clonedPart then
		DBG:warn("[WeatherVFX] Failed to clone VFX part for battle weather:", configWeatherName)
		return
	end
	
	-- Setup the cloned part
	clonedPart.Parent = scene or workspace
	clonedPart.CFrame = CFrame.new(vfxPosition)
	table.insert(BattleVFXParts, clonedPart)
	
	-- Set terrain clouds if needed (battle scenes may not use terrain, but set it anyway)
	SetTerrainClouds(configWeatherName)
	
	BattleWeatherName = configWeatherName
	DBG:print("[WeatherVFX] Set battle weather VFX to:", configWeatherName, "at position:", vfxPosition)
end

-- Clean up battle weather VFX
function WeatherVFX:CleanupBattle()
	CleanupBattleVFX()
	-- Also remove terrain clouds set for battle
	RemoveTerrainClouds()
end

return WeatherVFX


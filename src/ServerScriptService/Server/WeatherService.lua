--[[
	WeatherService.lua
	Server-authoritative weather system for Brainrot Catchers
	
	Inspired by Pokémon Sword & Shield's dynamic weather system.
	
	Features:
	- Each OUTDOOR chunk has its own weather
	- Weather changes once per day at 00:00 UTC
	- Weighted random selection (deterministic based on chunk name + day)
	- Weather is consistent across ALL servers (same chunk + same day = same weather)
	- Server replicates weather to clients per-chunk
	- Exposes GetCurrentWeather(chunkName) for other systems
	- Weather influences creature spawn tables
	- Weather can boost/alter creature abilities
	
	Extensibility:
	- Duration-based weather overrides can be added later
	- All data is driven from WeatherConfig
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local WeatherConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeatherConfig"))
local DBG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DBG"))

local WeatherService = {}

--============================================================================
-- INTERNAL STATE
--============================================================================

-- Cached weather per chunk: {[chunkName]: {weatherId: number, weatherData: table, utcDay: number}}
local ChunkWeatherCache: {[string]: {weatherId: number, weatherData: any, utcDay: number}} = {}

-- Virtual/special contexts that don't have weather
local EXCLUDED_CHUNKS = {
	["Title"] = true,
	["Trade"] = true,
	["Battle"] = true,
}

-- Reference to ChunkList (loaded on initialize)
local ChunkList = nil

-- Events for weather changes (internal use)
local WeatherChangedEvent = Instance.new("BindableEvent")

--============================================================================
-- UTC TIME HELPERS
--============================================================================

-- Get current UTC day number (days since epoch)
local function GetCurrentUtcDay(): number
	local utcTime = os.time(os.date("!*t"))
	return math.floor(utcTime / 86400) -- 86400 seconds per day
end

-- Get seconds until next 00:00 UTC
local function GetSecondsUntilMidnightUtc(): number
	local utcTime = os.time(os.date("!*t"))
	local secondsToday = utcTime % 86400
	return 86400 - secondsToday
end

-- Get formatted UTC time string
local function GetUtcTimeString(): string
	local utcDate = os.date("!*t")
	return string.format("%02d:%02d:%02d UTC", utcDate.hour, utcDate.min, utcDate.sec)
end

--============================================================================
-- DETERMINISTIC HASH FOR CHUNK + DAY
--============================================================================

-- Create a deterministic hash from a string using multiple passes for better distribution
-- This ensures the same chunk name always produces the same base value
local function HashString(str: string): number
	-- Use multiple hash algorithms combined for better distribution
	local hash1 = 5381  -- djb2
	local hash2 = 0     -- simple sum with position weight
	local hash3 = 1     -- multiplicative hash
	
	for i = 1, #str do
		local char = string.byte(str, i)
		
		-- djb2 hash
		hash1 = (hash1 * 33 + char) % 2147483647
		
		-- Position-weighted sum
		hash2 = (hash2 + char * i * 7) % 2147483647
		
		-- Multiplicative hash with mixing
		hash3 = (hash3 * 31 + char * 17 + i * 13) % 2147483647
	end
	
	-- Combine all three hashes with XOR-like mixing using arithmetic
	-- Since Lua 5.1 doesn't have bit operations, we simulate mixing
	local combined = (hash1 * 3 + hash2 * 7 + hash3 * 11) % 2147483647
	
	return combined
end

-- Mix function to further distribute seed values
local function MixSeed(seed: number): number
	-- Apply multiple mixing steps to spread out similar seeds
	seed = (seed * 1103515245 + 12345) % 2147483647
	seed = (seed * 134775813 + 1) % 2147483647
	return seed
end

-- Generate a deterministic seed based on chunk name and UTC day
-- This ensures the same weather for the same chunk on the same day across all servers
local function GetChunkDaySeed(chunkName: string, utcDay: number): number
	local chunkHash = HashString(chunkName)
	
	-- Create unique seed by combining chunk hash and day with mixing
	local baseSeed = chunkHash + utcDay * 86400  -- Use seconds in a day as multiplier
	local mixedSeed = MixSeed(baseSeed)
	
	-- Additional mixing with chunk-specific offset
	local finalSeed = MixSeed(mixedSeed + chunkHash)
	
	return finalSeed
end

--============================================================================
-- WEIGHTED RANDOM WEATHER SELECTION
--============================================================================

-- Select a weather ID using weighted random selection with deterministic seed
local function SelectWeightedWeather(seed: number): number
	-- Create a deterministic random generator based on seed
	local rng = Random.new(seed)
	
	local totalWeight = WeatherConfig.GetTotalWeight()
	local roll = rng:NextNumber() * totalWeight
	
	local cumulative = 0
	local weatherIds = WeatherConfig.GetAllWeatherIds()
	
	for _, id in ipairs(weatherIds) do
		local weather = WeatherConfig.GetWeatherById(id)
		if weather then
			cumulative = cumulative + weather.Weight
			if roll <= cumulative then
				return id
			end
		end
	end
	
	-- Fallback to Clear if something goes wrong
	return 1
end

--============================================================================
-- CHUNK VALIDATION
--============================================================================

-- Check if a chunk is an outdoor chunk that should have weather
local function IsOutdoorChunk(chunkName: string): boolean
	-- Exclude special contexts
	if EXCLUDED_CHUNKS[chunkName] then
		return false
	end
	
	-- Check ChunkList if available
	if ChunkList then
		local chunkData = ChunkList[chunkName]
		if chunkData then
			-- Only outdoor chunks (IsSubRoom = false) have weather
			return chunkData.IsSubRoom == false
		end
	end
	
	-- If chunk not in ChunkList, assume it's not outdoor
	return false
end

--============================================================================
-- WEATHER COMPUTATION
--============================================================================

-- Get or compute weather for a specific chunk
-- Returns weatherId, weatherData (or nil, nil if not outdoor)
local function GetOrComputeChunkWeather(chunkName: string)
	if not IsOutdoorChunk(chunkName) then
		return nil, nil
	end
	
	local utcDay = GetCurrentUtcDay()
	
	-- Check cache
	local cached = ChunkWeatherCache[chunkName]
	if cached and cached.utcDay == utcDay then
		return cached.weatherId, cached.weatherData
	end
	
	-- Compute new weather
	local seed = GetChunkDaySeed(chunkName, utcDay)
	local weatherId = SelectWeightedWeather(seed)
	local weatherData = WeatherConfig.GetWeatherById(weatherId)
	
	-- Cache the result
	ChunkWeatherCache[chunkName] = {
		weatherId = weatherId,
		weatherData = weatherData,
		utcDay = utcDay,
	}
	
	DBG:print("[WeatherService] Computed weather for", chunkName, ":", weatherData and weatherData.Name or "Unknown", "(seed:", seed, ")")
	
	return weatherId, weatherData
end

-- Refresh all cached chunk weather (called on day change)
local function RefreshAllChunkWeather()
	local utcDay = GetCurrentUtcDay()
	DBG:print("[WeatherService] ========================================")
	DBG:print("[WeatherService] Refreshing all chunk weather for UTC day:", utcDay)
	DBG:print("[WeatherService] ========================================")
	
	-- Clear cache to force recomputation
	ChunkWeatherCache = {}
	
	-- Pre-compute weather for all known outdoor chunks
	local weatherSummary = {}
	if ChunkList then
		for chunkName, chunkData in pairs(ChunkList) do
			if not EXCLUDED_CHUNKS[chunkName] and chunkData.IsSubRoom == false then
				local seed = GetChunkDaySeed(chunkName, utcDay)
				local weatherId, weatherData = GetOrComputeChunkWeather(chunkName)
				if weatherData then
					table.insert(weatherSummary, {
						chunk = chunkName,
						weather = weatherData.Name,
						id = weatherId,
						seed = seed
					})
				end
			end
		end
	end
	
	-- Print weather summary
	DBG:print("[WeatherService] Weather Summary:")
	for _, info in ipairs(weatherSummary) do
		DBG:print(string.format("  %s: %s (ID: %d, Seed: %d)", info.chunk, info.weather, info.id, info.seed))
	end
	DBG:print("[WeatherService] ========================================")
	
	-- Fire weather changed event
	WeatherChangedEvent:Fire(utcDay)
	
	-- Notify all players of weather update
	WeatherService:BroadcastWeatherToAll()
end

--============================================================================
-- CLIENT COMMUNICATION
--============================================================================

-- Send weather state for a specific chunk to a player
function WeatherService:SendChunkWeatherToPlayer(player: Player, chunkName: string)
	local weatherId, weatherData = GetOrComputeChunkWeather(chunkName)
	
	if not weatherData then
		-- Not an outdoor chunk, send clear weather indicator
		return
	end
	
	local Events = ReplicatedStorage:FindFirstChild("Events")
	if not Events then
		DBG:warn("[WeatherService] Events folder not found")
		return
	end
	
	local Communicate = Events:FindFirstChild("Communicate")
	if not Communicate then
		DBG:warn("[WeatherService] Communicate remote not found")
		return
	end
	
	-- Send weather update to client
	Communicate:FireClient(player, "WeatherUpdate", {
		ChunkName = chunkName,
		Id = weatherData.Id,
		Name = weatherData.Name,
		Description = weatherData.Description,
		Icon = weatherData.Icon,
		VisualEffects = weatherData.VisualEffects,
		AmbientSound = weatherData.AmbientSound,
	})
	
	DBG:print("[WeatherService] Sent weather for", chunkName, "to", player.Name, ":", weatherData.Name)
end

-- Send all outdoor chunk weather to a player
function WeatherService:SendAllWeatherToPlayer(player: Player)
	if not ChunkList then return end
	
	for chunkName, chunkData in pairs(ChunkList) do
		if not EXCLUDED_CHUNKS[chunkName] and chunkData.IsSubRoom == false then
			self:SendChunkWeatherToPlayer(player, chunkName)
		end
	end
end

-- Broadcast all weather to all players (called on day change)
function WeatherService:BroadcastWeatherToAll()
	for _, player in ipairs(Players:GetPlayers()) do
		self:SendAllWeatherToPlayer(player)
	end
end

--============================================================================
-- PUBLIC API
--============================================================================

--[[
	Get the weather for a specific chunk.
	Returns the full WeatherType table from WeatherConfig, or nil if not an outdoor chunk.
]]
function WeatherService:GetCurrentWeather(chunkName: string?): any?
	if not chunkName then
		-- Fallback: return Clear weather data
		return WeatherConfig.GetWeatherById(1)
	end
	
	local _, weatherData = GetOrComputeChunkWeather(chunkName)
	return weatherData
end

--[[
	Get the weather ID for a specific chunk.
	Returns nil if not an outdoor chunk.
]]
function WeatherService:GetCurrentWeatherId(chunkName: string?): number?
	if not chunkName then
		return 1 -- Default to Clear
	end
	
	local weatherId, _ = GetOrComputeChunkWeather(chunkName)
	return weatherId
end

--[[
	Get the weather name for a specific chunk.
]]
function WeatherService:GetCurrentWeatherName(chunkName: string?): string
	local weather = self:GetCurrentWeather(chunkName)
	if weather then
		return weather.Name
	end
	return "Clear"
end

--[[
	Get spawn modifier for a creature type based on chunk's weather.
	Used by spawn systems to adjust encounter rates.
]]
function WeatherService:GetSpawnModifier(chunkName: string?, creatureType: string): number
	local weatherId = self:GetCurrentWeatherId(chunkName)
	if not weatherId then
		return 1.0
	end
	return WeatherConfig.GetSpawnModifier(weatherId, creatureType)
end

--[[
	Get ability modifier for a move type based on chunk's weather.
	Used by battle system to adjust move power.
]]
function WeatherService:GetAbilityModifier(chunkName: string?, moveType: string): number
	local weatherId = self:GetCurrentWeatherId(chunkName)
	if not weatherId then
		return 1.0
	end
	return WeatherConfig.GetAbilityModifier(weatherId, moveType)
end

--[[
	Check if a special form can spawn in chunk's weather.
]]
function WeatherService:CanSpawnSpecialForm(chunkName: string?, formName: string): boolean
	local weatherId = self:GetCurrentWeatherId(chunkName)
	if not weatherId then
		return false
	end
	return WeatherConfig.CanSpawnSpecialForm(weatherId, formName)
end

--[[
	Check if a chunk is an outdoor chunk (has weather).
]]
function WeatherService:IsOutdoorChunk(chunkName: string): boolean
	return IsOutdoorChunk(chunkName)
end

--[[
	Get all outdoor chunks and their current weather.
	Returns a table: {[chunkName]: weatherName}
]]
function WeatherService:GetAllChunkWeather(): {[string]: string}
	local result = {}
	
	if ChunkList then
		for chunkName, chunkData in pairs(ChunkList) do
			if not EXCLUDED_CHUNKS[chunkName] and chunkData.IsSubRoom == false then
				local _, weatherData = GetOrComputeChunkWeather(chunkName)
				if weatherData then
					result[chunkName] = weatherData.Name
				end
			end
		end
	end
	
	return result
end

--[[
	Get the event for weather changes.
	Returns a BindableEvent that fires (utcDay) when weather refreshes.
]]
function WeatherService:GetWeatherChangedEvent(): BindableEvent
	return WeatherChangedEvent
end

--[[
	Get debug info about weather state.
]]
function WeatherService:GetDebugInfo(): {[string]: any}
	local allWeather = self:GetAllChunkWeather()
	
	return {
		CurrentUtcDay = GetCurrentUtcDay(),
		CurrentUtcTime = GetUtcTimeString(),
		SecondsUntilMidnight = GetSecondsUntilMidnightUtc(),
		TotalWeight = WeatherConfig.GetTotalWeight(),
		ChunkWeather = allWeather,
		CachedChunks = #ChunkWeatherCache,
	}
end

--============================================================================
-- INITIALIZATION
--============================================================================

function WeatherService:Initialize()
	DBG:print("[WeatherService] Initializing per-chunk weather system...")
	
	-- Load ChunkList
	local GameData = script.Parent:FindFirstChild("GameData")
	if GameData then
		local ChunkListModule = GameData:FindFirstChild("ChunkList")
		if ChunkListModule then
			ChunkList = require(ChunkListModule)
			DBG:print("[WeatherService] Loaded ChunkList with", self:_countOutdoorChunks(), "outdoor chunks")
		else
			DBG:warn("[WeatherService] ChunkList module not found!")
		end
	else
		DBG:warn("[WeatherService] GameData folder not found!")
	end
	
	-- Pre-compute weather for all outdoor chunks
	RefreshAllChunkWeather()
	
	DBG:print("[WeatherService] Current UTC time:", GetUtcTimeString())
	DBG:print("[WeatherService] Seconds until next weather change:", GetSecondsUntilMidnightUtc())
	
	-- Handle new player connections
	Players.PlayerAdded:Connect(function(player)
		-- Small delay to ensure client is ready
		task.delay(1, function()
			if player.Parent == Players then
				self:SendAllWeatherToPlayer(player)
			end
		end)
	end)
	
	-- Send weather to existing players
	for _, player in ipairs(Players:GetPlayers()) do
		self:SendAllWeatherToPlayer(player)
	end
	
	-- Track last checked UTC day
	local lastCheckedDay = GetCurrentUtcDay()
	
	-- Start the weather check loop
	task.spawn(function()
		while true do
			-- Check every minute for day changes
			task.wait(60)
			
			local currentDay = GetCurrentUtcDay()
			if currentDay ~= lastCheckedDay then
				DBG:print("[WeatherService] UTC day changed from", lastCheckedDay, "to", currentDay)
				lastCheckedDay = currentDay
				RefreshAllChunkWeather()
			end
		end
	end)
	
	DBG:print("[WeatherService] Per-chunk weather system initialized successfully!")
end

-- Helper to count outdoor chunks
function WeatherService:_countOutdoorChunks(): number
	local count = 0
	if ChunkList then
		for chunkName, chunkData in pairs(ChunkList) do
			if not EXCLUDED_CHUNKS[chunkName] and chunkData.IsSubRoom == false then
				count = count + 1
			end
		end
	end
	return count
end

return WeatherService


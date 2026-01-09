--[[
	WeatherApi.lua
	Exposes WeatherService functions through ServerFunctions
	
	Each outdoor chunk has its own weather, deterministic across all servers.
]]

local WeatherApi = {}

function WeatherApi.apply(ServerFunctions, deps)
	local WeatherService = deps.WeatherService
	
	-- Get the current weather data for a specific chunk
	function ServerFunctions:GetCurrentWeather(chunkName: string?)
		return WeatherService:GetCurrentWeather(chunkName)
	end
	
	-- Get the current weather ID for a specific chunk
	function ServerFunctions:GetCurrentWeatherId(chunkName: string?)
		return WeatherService:GetCurrentWeatherId(chunkName)
	end
	
	-- Get the current weather name for a specific chunk
	function ServerFunctions:GetCurrentWeatherName(chunkName: string?)
		return WeatherService:GetCurrentWeatherName(chunkName)
	end
	
	-- Get spawn modifier for a creature type in a specific chunk
	function ServerFunctions:GetWeatherSpawnModifier(chunkName: string?, creatureType: string)
		return WeatherService:GetSpawnModifier(chunkName, creatureType)
	end
	
	-- Get ability modifier for a move type in a specific chunk
	function ServerFunctions:GetWeatherAbilityModifier(chunkName: string?, moveType: string)
		return WeatherService:GetAbilityModifier(chunkName, moveType)
	end
	
	-- Check if a special form can spawn in current weather for a chunk
	function ServerFunctions:CanSpawnSpecialForm(chunkName: string?, formName: string)
		return WeatherService:CanSpawnSpecialForm(chunkName, formName)
	end
	
	-- Check if a chunk is an outdoor chunk (has weather)
	function ServerFunctions:IsOutdoorChunk(chunkName: string)
		return WeatherService:IsOutdoorChunk(chunkName)
	end
	
	-- Get all outdoor chunks and their current weather
	function ServerFunctions:GetAllChunkWeather()
		return WeatherService:GetAllChunkWeather()
	end
	
	-- Get the WeatherService instance for direct access
	function ServerFunctions:GetWeatherService()
		return WeatherService
	end
	
	-- Get debug info
	function ServerFunctions:GetWeatherDebugInfo()
		return WeatherService:GetDebugInfo()
	end
	
	-- Initialize the weather service
	WeatherService:Initialize()
end

return WeatherApi

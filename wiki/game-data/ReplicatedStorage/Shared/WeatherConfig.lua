--[[
	WeatherConfig.lua
	Data-driven weather configuration for Brainrot Catchers
	
	Weather changes once per day at 00:00 UTC.
	Each weather type has:
	- ID (1-9)
	- Name
	- Icon asset ID
	- Weight (for randomized selection)
	- SpawnModifiers (creature type boosts/restrictions)
	- AbilityModifiers (in-battle effects)
	- VisualEffects (particle/lighting config for client)
	- AmbientSound (sound asset ID for client)
	
	This module is shared between server and client.
]]

export type WeatherType = {
	Id: number,
	Name: string,
	Description: string,
	Icon: string,
	Weight: number,
	-- Spawn table modifiers: type -> multiplier (1.0 = normal, 2.0 = double chance, 0.5 = half chance)
	SpawnModifiers: {[string]: number}?,
	-- Ability power modifiers in battle: type -> multiplier
	AbilityModifiers: {[string]: number}?,
	-- Visual effect configuration for client
	VisualEffects: {
		ParticleEffect: string?,
		ParticleColor: Color3?,
		ParticleRate: number?,
		FogDensity: number?,
		FogColor: Color3?,
		Brightness: number?,
		ColorCorrection: {
			Brightness: number?,
			Contrast: number?,
			Saturation: number?,
			TintColor: Color3?,
		}?,
	}?,
	-- Ambient sound asset ID
	AmbientSound: string?,
	-- Special forms that may appear in this weather
	SpecialForms: {string}?,
}

local WeatherConfig = {}

--============================================================================
-- WEATHER TYPE DEFINITIONS
--============================================================================

-- Weather types indexed by ID (1-9)
WeatherConfig.Types = {
	--[[
		ID 1: Clear
		Default sunny weather. No special modifiers.
	]]
	[1] = {
		Id = 1,
		Name = "Clear",
		Description = "Clear skies with pleasant sunshine.",
		Icon = "rbxassetid://18610834972", -- Sun icon
		Weight = 25, -- Most common
		SpawnModifiers = {
			-- Normal spawns, slight boost to Fire and Flying
			["Fire"] = 1.2,
			["Flying"] = 1.15,
		},
		AbilityModifiers = nil,
		VisualEffects = {
			Brightness = 2,
			FogDensity = 0,
		},
		AmbientSound = nil,
	},

	--[[
		ID 2: Harsh Sun
		Intense sunlight. Boosts Fire, reduces Water.
	]]
	[2] = {
		Id = 2,
		Name = "Harsh Sun",
		Description = "Blazing sunlight scorches the land.",
		Icon = "rbxassetid://18610835159", -- Intense sun icon
		Weight = 8,
		SpawnModifiers = {
			["Fire"] = 2.0,
			["Ground"] = 1.5,
			["Water"] = 0.3,
			["Ice"] = 0.2,
		},
		AbilityModifiers = {
			["Fire"] = 1.5,  -- Fire moves powered up
			["Water"] = 0.5, -- Water moves weakened
		},
		VisualEffects = {
			Brightness = 3,
			FogDensity = 0,
			ColorCorrection = {
				Brightness = 0.1,
				Contrast = 0.1,
				Saturation = 0.2,
				TintColor = Color3.fromRGB(255, 240, 200),
			},
		},
		AmbientSound = "rbxassetid://9043994997", -- Heat haze ambience
	},

	--[[
		ID 3: Snowstorm (Blizzard)
		Heavy snow with reduced visibility. Boosts Ice.
	]]
	[3] = {
		Id = 3,
		Name = "Snowstorm",
		Description = "A fierce blizzard blankets everything in snow.",
		Icon = "rbxassetid://18610835520", -- Blizzard icon
		Weight = 6,
		SpawnModifiers = {
			["Ice"] = 2.5,
			["Water"] = 0.5,
			["Fire"] = 0.3,
			["Flying"] = 0.4,
		},
		-- Pokémon-faithful: Snow does not directly boost move power.
		-- (Defensive boosts like Ice Defense are applied in battle damage logic.)
		AbilityModifiers = nil,
		VisualEffects = {
			ParticleEffect = "Snowstorm",
			ParticleColor = Color3.fromRGB(255, 255, 255),
			ParticleRate = 150,
			FogDensity = 0.15,
			FogColor = Color3.fromRGB(220, 230, 240),
			Brightness = 1.2,
			ColorCorrection = {
				Brightness = -0.05,
				Contrast = -0.1,
				Saturation = -0.3,
				TintColor = Color3.fromRGB(200, 210, 230),
			},
		},
		AmbientSound = "rbxassetid://9043887900", -- Blizzard wind
	},

	--[[
		ID 4: Snow
		Light snow. Gentle boost to Ice types.
	]]
	[4] = {
		Id = 4,
		Name = "Snow",
		Description = "Gentle snowflakes drift down from the sky.",
		Icon = "rbxassetid://18610835349", -- Snowflake icon
		Weight = 10,
		SpawnModifiers = {
			["Ice"] = 1.8,
			["Water"] = 1.2,
			["Fire"] = 0.7,
		},
		-- Pokémon-faithful: Snow does not directly boost move power.
		-- (Defensive boosts like Ice Defense are applied in battle damage logic.)
		AbilityModifiers = nil,
		VisualEffects = {
			ParticleEffect = "Snow",
			ParticleColor = Color3.fromRGB(255, 255, 255),
			ParticleRate = 50,
			FogDensity = 0.03,
			FogColor = Color3.fromRGB(230, 235, 245),
			Brightness = 1.5,
			ColorCorrection = {
				Brightness = 0,
				Contrast = 0,
				Saturation = -0.15,
				TintColor = Color3.fromRGB(220, 225, 240),
			},
		},
		AmbientSound = "rbxassetid://9043887640", -- Light wind
	},

	--[[
		ID 5: Fog
		Dense fog reduces visibility. Boosts Ghost and Psychic.
	]]
	[5] = {
		Id = 5,
		Name = "Fog",
		Description = "A thick fog obscures everything in sight.",
		Icon = "rbxassetid://18610834608", -- Fog icon
		Weight = 10,
		SpawnModifiers = {
			["Ghost"] = 2.0,
			["Psychic"] = 1.5,
			["Dark"] = 1.3,
			["Flying"] = 0.6,
		},
		-- Pokémon-faithful: Fog is not a standard modern battle weather with move-power modifiers.
		AbilityModifiers = nil,
		VisualEffects = {
			FogDensity = 0.25,
			FogColor = Color3.fromRGB(200, 200, 210),
			Brightness = 1.0,
			ColorCorrection = {
				Brightness = -0.1,
				Contrast = -0.15,
				Saturation = -0.4,
				TintColor = Color3.fromRGB(180, 180, 200),
			},
		},
		AmbientSound = "rbxassetid://9043887640", -- Eerie ambience
	},

	--[[
		ID 6: Overcast
		Cloudy skies. Slight boost to certain types.
	]]
	[6] = {
		Id = 6,
		Name = "Overcast",
		Description = "Grey clouds cover the sky.",
		Icon = "rbxassetid://18610834766", -- Cloud icon
		Weight = 18, -- Common
		SpawnModifiers = {
			["Normal"] = 1.2,
			["Dark"] = 1.3,
			["Poison"] = 1.2,
		},
		AbilityModifiers = nil,
		VisualEffects = {
			FogDensity = 0.02,
			FogColor = Color3.fromRGB(180, 180, 190),
			Brightness = 1.3,
			ColorCorrection = {
				Brightness = -0.05,
				Contrast = 0,
				Saturation = -0.2,
			},
		},
		AmbientSound = nil,
	},

	--[[
		ID 7: Rain
		Steady rainfall. Boosts Water, weakens Fire.
	]]
	[7] = {
		Id = 7,
		Name = "Rain",
		Description = "A steady rain falls from the clouds.",
		Icon = "rbxassetid://18610835682", -- Rain icon
		Weight = 12,
		SpawnModifiers = {
			["Water"] = 1.8,
			["Electric"] = 1.3,
			["Fire"] = 0.5,
			["Ground"] = 0.8,
		},
		-- Pokémon-faithful (Gen 3+): Rain boosts Water and weakens Fire.
		AbilityModifiers = {
			["Water"] = 1.5,
			["Fire"] = 0.5,
		},
		VisualEffects = {
			ParticleEffect = "Rain",
			ParticleColor = Color3.fromRGB(180, 200, 220),
			ParticleRate = 80,
			FogDensity = 0.05,
			FogColor = Color3.fromRGB(150, 160, 180),
			Brightness = 1.2,
			ColorCorrection = {
				Brightness = -0.1,
				Contrast = 0.05,
				Saturation = -0.25,
				TintColor = Color3.fromRGB(170, 180, 200),
			},
		},
		AmbientSound = "rbxassetid://9043887390", -- Rain sounds
	},

	--[[
		ID 8: Thunderstorm
		Heavy rain with lightning. Strong boosts to Water and Electric.
	]]
	[8] = {
		Id = 8,
		Name = "Thunderstorm",
		Description = "Thunder rumbles as lightning splits the sky.",
		Icon = "rbxassetid://18610835852", -- Thunderstorm icon
		Weight = 6,
		SpawnModifiers = {
			["Water"] = 2.0,
			["Electric"] = 2.5,
			["Fire"] = 0.3,
			["Flying"] = 0.5,
			["Ground"] = 0.6,
		},
		-- Pokémon-faithful: treat Thunderstorm as a rain variant for battle power modifiers.
		AbilityModifiers = {
			["Water"] = 1.5,
			["Fire"] = 0.5,
		},
		VisualEffects = {
			ParticleEffect = "HeavyRain",
			ParticleColor = Color3.fromRGB(160, 180, 200),
			ParticleRate = 150,
			FogDensity = 0.08,
			FogColor = Color3.fromRGB(120, 130, 150),
			Brightness = 0.8,
			ColorCorrection = {
				Brightness = -0.2,
				Contrast = 0.15,
				Saturation = -0.35,
				TintColor = Color3.fromRGB(140, 150, 180),
			},
		},
		AmbientSound = "rbxassetid://9043887130", -- Thunderstorm sounds
		SpecialForms = {
			-- Future: special storm forms could spawn here
		},
	},

	--[[
		ID 9: Sandstorm
		Desert winds kick up sand. Boosts Ground, Rock, Steel.
	]]
	[9] = {
		Id = 9,
		Name = "Sandstorm",
		Description = "Swirling sand fills the air.",
		Icon = "rbxassetid://18610836022", -- Sandstorm icon
		Weight = 5,
		SpawnModifiers = {
			["Ground"] = 2.0,
			["Steel"] = 1.5,
			["Rock"] = 1.8,
			["Water"] = 0.4,
			["Grass"] = 0.5,
			["Flying"] = 0.6,
		},
		-- Pokémon-faithful: Sandstorm does not boost move power.
		-- (Rock Sp. Def boost + chip damage are applied in battle logic.)
		AbilityModifiers = nil,
		VisualEffects = {
			ParticleEffect = "Sandstorm",
			ParticleColor = Color3.fromRGB(210, 180, 140),
			ParticleRate = 100,
			FogDensity = 0.12,
			FogColor = Color3.fromRGB(200, 170, 130),
			Brightness = 1.4,
			ColorCorrection = {
				Brightness = 0.05,
				Contrast = 0.1,
				Saturation = -0.2,
				TintColor = Color3.fromRGB(220, 190, 150),
			},
		},
		AmbientSound = "rbxassetid://9043886870", -- Desert wind
	},
}

--============================================================================
-- HELPER FUNCTIONS
--============================================================================

-- Get weather by ID
function WeatherConfig.GetWeatherById(id: number): WeatherType?
	return WeatherConfig.Types[id]
end

-- Get weather by name
function WeatherConfig.GetWeatherByName(name: string): WeatherType?
	for _, weather in pairs(WeatherConfig.Types) do
		if weather.Name == name then
			return weather
		end
	end
	return nil
end

-- Get all weather IDs
function WeatherConfig.GetAllWeatherIds(): {number}
	local ids = {}
	for id in pairs(WeatherConfig.Types) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- Get total weight for weighted random selection
function WeatherConfig.GetTotalWeight(): number
	local total = 0
	for _, weather in pairs(WeatherConfig.Types) do
		total = total + weather.Weight
	end
	return total
end

-- Get spawn modifier for a specific type in a given weather
function WeatherConfig.GetSpawnModifier(weatherId: number, creatureType: string): number
	local weather = WeatherConfig.Types[weatherId]
	if not weather then return 1.0 end
	if not weather.SpawnModifiers then return 1.0 end
	return weather.SpawnModifiers[creatureType] or 1.0
end

-- Get ability modifier for a specific type in a given weather
function WeatherConfig.GetAbilityModifier(weatherId: number, moveType: string): number
	local weather = WeatherConfig.Types[weatherId]
	if not weather then return 1.0 end
	if not weather.AbilityModifiers then return 1.0 end
	return weather.AbilityModifiers[moveType] or 1.0
end

-- Check if a special form can spawn in this weather
function WeatherConfig.CanSpawnSpecialForm(weatherId: number, formName: string): boolean
	local weather = WeatherConfig.Types[weatherId]
	if not weather or not weather.SpecialForms then return false end
	for _, form in ipairs(weather.SpecialForms) do
		if form == formName then
			return true
		end
	end
	return false
end

return WeatherConfig


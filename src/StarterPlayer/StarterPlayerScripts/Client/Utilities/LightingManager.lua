local LightingManager = {}
local DayNightLighting = require(script.Parent.DayNightLighting)

function LightingManager:SetLighting(LightingModule)
	local LightingProperties = require(LightingModule)
	local LightingObjects = LightingModule:GetChildren()
	
	-- Properties to exclude to prevent conflicts with DayNightCycle system
	local ExcludedProperties = {
		"ClockTime",
		"TimeOfDay",
		"GeographicLatitude"
	}
	
	for i,v in pairs(game.Lighting:GetDescendants()) do v:Destroy() end
	if workspace.Terrain:FindFirstChildOfClass("Clouds") then
		workspace.Terrain:FindFirstChildOfClass("Clouds"):Destroy()
	end
	
	-- Apply lighting properties, excluding time-related ones by default
	for propertyName, propertyValue in pairs(LightingProperties) do
		-- Skip time-related properties that would conflict with DayNightCycle
		local shouldExclude = false
		for _, excludedProp in ipairs(ExcludedProperties) do
			if propertyName == excludedProp then
				shouldExclude = true
				break
			end
		end
		
		if not shouldExclude and game.Lighting[propertyName] ~= nil then
			game.Lighting[propertyName] = propertyValue
		end
	end
	
	for i,v in pairs(LightingObjects) do
		if v:IsA("Clouds") then
			v:Clone().Parent = workspace.Terrain
		else
			v:Clone().Parent = game.Lighting
		end
	end
	
	-- Initialize Day/Night Lighting system and refresh base values
	DayNightLighting:Initialize()

	-- Detect interior by checking the chunk model root attribute set by server
	local isInterior = false
	local chunkModel = LightingModule and LightingModule.Parent and LightingModule.Parent.Parent
	if chunkModel and chunkModel:GetAttribute("IsInterior") == true then
		isInterior = true
	end

	if isInterior then
		-- Disable server sync and apply interior TimeOfDay/GeographicLatitude if provided
		DayNightLighting:SetSyncEnabled(false)
		if LightingProperties.TimeOfDay then
			game.Lighting.TimeOfDay = LightingProperties.TimeOfDay
		end
		if LightingProperties.GeographicLatitude ~= nil then
			game.Lighting.GeographicLatitude = LightingProperties.GeographicLatitude
		end
	else
		-- Enable server sync for exterior/main chunks
		DayNightLighting:SetSyncEnabled(true)
		DayNightLighting:RefreshBaseValues()
	end
end

return LightingManager
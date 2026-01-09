local LightingManager = {}
local DayNightLighting = require(script.Parent.DayNightLighting)
local GameContext = require(script.Parent.GameContext)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DBG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DBG"))

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
	local chunkName = chunkModel and chunkModel.Name or ""
	local context = GameContext:Get()

	-- Force bright day and disable sync for Trade/Battle contexts
	if context == "Trade" or context == "Battle" or chunkName == "Trade" then
		DayNightLighting:LockSyncDisabled(true)
		-- Hard-set daytime sun position to avoid night skybox/ambient
		game.Lighting.ClockTime = 12
		game.Lighting.TimeOfDay = "12:00:00"
		-- Pause sync, capture current as base, then apply Day once and lock off
		DayNightLighting:SetSyncEnabled(false)
		DayNightLighting:RefreshBaseValues()
		DayNightLighting:SetSyncEnabled(true)
		DayNightLighting:UpdateLightingForPeriod("Day")
		DayNightLighting:SetSyncEnabled(false)
		DBG:print(string.format("[LightingManager] Forcing Day (context=%s, chunk=%s) and disabling sync", tostring(context), tostring(chunkName)))
		return
	end
	-- For normal/story contexts, release lock and proceed with standard rules
	DayNightLighting:LockSyncDisabled(false)

	if chunkModel and chunkModel:GetAttribute("IsInterior") == true then
		isInterior = true
	end

	-- Special case: CatchCare should always use bright noon lighting like outdoors
	if chunkName == "CatchCare" then
		-- Force CatchCare to use Day lighting (bright noon-like)
		DayNightLighting:RefreshBaseValues() -- Store base values first
		-- Temporarily enable sync to apply Day lighting, then disable
		DayNightLighting:SetSyncEnabled(true)
		DayNightLighting:UpdateLightingForPeriod("Day") -- Apply Day lighting modifiers (bright noon)
		DayNightLighting:SetSyncEnabled(false) -- Disable sync to prevent future updates
		DBG:print("[LightingManager] CatchCare detected - forcing bright noon lighting")
	elseif isInterior then
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
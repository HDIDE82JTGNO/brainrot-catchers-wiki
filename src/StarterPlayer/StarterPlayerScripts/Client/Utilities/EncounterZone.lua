--!strict
--[[
	EncounterZone System
	
	Handles wild creature encounters in designated zones.
	Pure event-driven system - no polling loops.
	
	Architecture:
	- Touch-based encounter checks (triggered only on Touched events)
	- Step-based encounter mechanics (distance tracking between touches)
	- Server-authoritative encounter generation
	- Immunity system to prevent encounter spam
	- Step effects based on zone material
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DBG = require(ReplicatedStorage.Shared.DBG)
local CharacterFunctions = require(script.Parent.CharacterFunctions)
local CutsceneRegistry = require(script.Parent:WaitForChild("CutsceneRegistry"))
local Say = require(script.Parent:WaitForChild("Say"))
local ClientData = require(script.Parent.Parent.Plugins.ClientData)

-- Lazy load UI to prevent circular dependencies
local UIModule = nil
local function GetUI()
	if not UIModule then
		local ok, ui = pcall(function()
			return require(script.Parent.Parent.UI)
		end)
		UIModule = ok and ui or false
	end
	return UIModule or nil
end

-- Type Definitions
export type EncounterZonePart = BasePart

export type ZoneConnections = {
	Touched: RBXScriptConnection,
	TouchEnded: RBXScriptConnection?,
}

export type BoundStepFunction = {
	Callback: () -> (),
	Interval: number,
	Counter: number,
}

export type EncounterZoneConfig = {
	StepDistance: number,
	EncounterCooldown: number,
	ImmunityStepsAfterBattle: number,
	EncounterChance: number,
}

-- Configuration
local DEFAULT_CONFIG: EncounterZoneConfig = {
	StepDistance = 2,
	EncounterCooldown = 0.5,
	ImmunityStepsAfterBattle = 2,
	EncounterChance = 80,
}

-- Material to step effect mapping
-- Maps Roblox material names to effect attachment names in ReplicatedStorage.Assets.Effects.EncounterZones
local MATERIAL_TO_EFFECT: {[string]: string} = {
	-- Grass variants
	["Grass"] = "Step_Grass",
	["LeafyGrass"] = "Step_Grass",
	["Ground"] = "Step_Grass",
	
	-- Sand variants
	["Sand"] = "Step_Sand",
	["Sandstone"] = "Step_Sand",
	["Mud"] = "Step_Sand",
	
	-- Snow variants
	["Snow"] = "Step_Snow",
	["Glacier"] = "Step_Snow",
	["Ice"] = "Step_Snow",
}

-- Keywords to effect mapping (case-insensitive matching)
-- Used for part names and texture names
local KEYWORDS_TO_EFFECT: {[string]: string} = {
	-- Grass keywords
	["grass"] = "Step_Grass",
	["foliage"] = "Step_Grass",
	["leaf"] = "Step_Grass",
	["meadow"] = "Step_Grass",
	["lawn"] = "Step_Grass",
	["forest"] = "Step_Grass",
	["jungle"] = "Step_Grass",
	
	-- Sand keywords
	["sand"] = "Step_Sand",
	["beach"] = "Step_Sand",
	["desert"] = "Step_Sand",
	["dune"] = "Step_Sand",
	["dirt"] = "Step_Sand",
	["mud"] = "Step_Sand",
	
	-- Snow keywords
	["snow"] = "Step_Snow",
	["ice"] = "Step_Snow",
	["frost"] = "Step_Snow",
	["winter"] = "Step_Snow",
	["frozen"] = "Step_Snow",
	["glacier"] = "Step_Snow",
	["tundra"] = "Step_Snow",
}

-- Color ranges for fallback detection (HSV-based)
-- H = Hue (0-1), S = Saturation (0-1), V = Value/Brightness (0-1)
local function getEffectFromColor(color: Color3): string?
	local h, s, v = color:ToHSV()
	
	-- Snow/Ice: Very low saturation (grayish/white) and high brightness
	if s < 0.15 and v > 0.7 then
		return "Step_Snow"
	end
	
	-- Grass: Green hues (roughly 80-160 degrees, or 0.22-0.44 in 0-1 range)
	-- With reasonable saturation and not too dark
	if h >= 0.20 and h <= 0.45 and s > 0.25 and v > 0.2 then
		return "Step_Grass"
	end
	
	-- Sand: Yellow/Orange/Tan hues (roughly 30-60 degrees, or 0.08-0.17 in 0-1 range)
	-- Also catches brownish colors
	if h >= 0.05 and h <= 0.18 and s > 0.15 and v > 0.3 then
		return "Step_Sand"
	end
	
	-- Brownish sand (lower saturation yellows/oranges)
	if h >= 0.05 and h <= 0.12 and s > 0.1 and s < 0.5 and v > 0.2 and v < 0.7 then
		return "Step_Sand"
	end
	
	return nil
end

-- Minimum velocity threshold to consider the player as "moving" (studs/second)
local MOVEMENT_VELOCITY_THRESHOLD = 0.5

-- Grace period before removing step effects after leaving a zone (seconds)
-- This prevents flickering when body parts briefly exit during normal walking
local ZONE_EXIT_GRACE_PERIOD = 0.5

-- Effect name to sound name mapping
-- Maps step effect names to sound names in ReplicatedStorage.Audio.SFX.EncounterZones
local EFFECT_TO_SOUND: {[string]: string} = {
	["Step_Grass"] = "Grass",
	["Step_Sand"] = "Sand",
	["Step_Snow"] = "Snow",
}

--[[ EncounterZone Class ]]--
local EncounterZone = {}
EncounterZone.__index = EncounterZone

-- Constructor
function EncounterZone.new(config: EncounterZoneConfig?)
	local self = setmetatable({}, EncounterZone)
	
	-- Configuration
	self._config = config or DEFAULT_CONFIG
	
	-- Services and references
	self._player = Players.LocalPlayer
	self._character = self._player.Character or self._player.CharacterAdded:Wait()
	self._humanoidRootPart = self._character:WaitForChild("HumanoidRootPart") :: BasePart
	self._events = ReplicatedStorage:WaitForChild("Events")
	
	-- State tracking
	self._activeZones = {} :: {[string]: EncounterZonePart}
	self._zoneConnections = {} :: {[string]: ZoneConnections}
	
	-- Movement and step tracking
	self._lastPosition = self._humanoidRootPart.Position
	self._distanceWalked = 0
	self._lastEncounterTime = 0
	
	-- State flags
	self._inEncounter = false
	self._isRequestingEncounter = false
	self._partyEmptyLogged = false
	self._showingRepelPrompt = false -- Prevent encounters while showing repel prompt
	self._immunityIsRepel = false -- Track whether current immunity came from a repel item
	
	-- Immunity system
	self._immunitySteps = 0
	
	-- Bound step functions for extensibility
	self._boundStepFunctions = {} :: {[string]: any}
	
	-- Current chunk tracking
	self._currentChunkName = nil :: string?
	
	-- StepStatus UI references (lazy loaded)
	self._stepStatusUI = nil :: GuiObject?
	self._stepStatusIcon = nil :: ImageLabel?
	self._stepStatusAMT = nil :: TextLabel?
	
	-- Step effects state
	self._currentStepEffect = nil :: Attachment? -- The cloned effect attachment on the character
	self._currentEffectName = nil :: string? -- Name of the current effect (e.g., "Step_Grass")
	self._stepEffectsEnabled = false -- Whether particle emitters are currently enabled
	self._stepEffectConnection = nil :: RBXScriptConnection? -- RunService connection for movement detection
	self._insideZoneParts = {} :: {[BasePart]: number} -- Track zone parts with touch count (multiple body parts can touch)
	self._pendingZoneExit = nil :: thread? -- Pending delayed zone exit check
	self._lastZonePart = nil :: BasePart? -- Last zone part we were in (for grace period)
	
	-- Zone audio state
	self._currentZoneSound = nil :: Sound? -- The cloned looping sound for current zone
	self._currentSoundName = nil :: string? -- Name of the current sound (e.g., "Grass")
	
	-- Setup character respawn handling
	self:_setupCharacterRespawn()
	
	return self
end

--[[ Private Methods ]]--

-- Handle character respawn
function EncounterZone:_setupCharacterRespawn()
	self._player.CharacterAdded:Connect(function(newCharacter)
		-- Cancel any pending zone exit
		if self._pendingZoneExit then
			task.cancel(self._pendingZoneExit)
			self._pendingZoneExit = nil
		end
		
		-- Clean up old step effects and audio before updating character reference
		self:_cleanupStepEffects()
		self:_stopZoneSound()
		
		self._character = newCharacter
		self._humanoidRootPart = newCharacter:WaitForChild("HumanoidRootPart") :: BasePart
		self._lastPosition = self._humanoidRootPart.Position
		self._distanceWalked = 0
		
		-- Clear zone tracking on respawn
		table.clear(self._insideZoneParts)
		self._lastZonePart = nil
	end)
end

--[[ Step Effects System ]]--

-- Check a string for keyword matches
local function getEffectFromKeywords(text: string): string?
	local lowerText = string.lower(text)
	for keyword, effectName in pairs(KEYWORDS_TO_EFFECT) do
		if string.find(lowerText, keyword, 1, true) then
			return effectName
		end
	end
	return nil
end

-- Check the part's name for keyword matches
function EncounterZone:_getEffectFromPartName(zonePart: BasePart): string?
	return getEffectFromKeywords(zonePart.Name)
end

-- Check textures/decals inside a part for keyword matches
function EncounterZone:_getEffectFromTextures(zonePart: BasePart): string?
	-- Check all descendants for texture-related instances
	for _, child in ipairs(zonePart:GetDescendants()) do
		local textureName: string? = nil
		local textureId: string? = nil
		
		-- Get name and texture ID from various texture types
		if child:IsA("Texture") or child:IsA("Decal") then
			textureName = child.Name
			textureId = child.Texture
		elseif child:IsA("SurfaceAppearance") then
			textureName = child.Name
			-- SurfaceAppearance uses ColorMap, NormalMap, etc.
			textureId = child.ColorMap
		end
		
		-- Check the name for keywords
		if textureName then
			local effectFromName = getEffectFromKeywords(textureName)
			if effectFromName then
				return effectFromName
			end
		end
		
		-- Check the texture ID/URL for keywords (asset names sometimes contain hints)
		if textureId and textureId ~= "" then
			local effectFromTexture = getEffectFromKeywords(textureId)
			if effectFromTexture then
				return effectFromTexture
			end
		end
	end
	
	return nil
end

-- Resolve effect name using material, part name, textures, and color fallback
function EncounterZone:_resolveEffectForZonePart(zonePart: BasePart): string?
	-- Priority 1: Direct material match
	local materialName = zonePart.Material.Name
	local effectFromMaterial = MATERIAL_TO_EFFECT[materialName]
	if effectFromMaterial then
		return effectFromMaterial
	end
	
	-- Priority 2: Check the part's name for keywords (e.g., "GrassZone", "SandArea")
	local effectFromName = self:_getEffectFromPartName(zonePart)
	if effectFromName then
		DBG:print("[EncounterZone] Resolved effect from part name:", effectFromName, "Name:", zonePart.Name)
		return effectFromName
	end
	
	-- Priority 3: Check textures/decals inside the part
	local effectFromTextures = self:_getEffectFromTextures(zonePart)
	if effectFromTextures then
		DBG:print("[EncounterZone] Resolved effect from textures:", effectFromTextures)
		return effectFromTextures
	end
	
	-- Priority 4: Color-based fallback (for Plastic or other generic materials)
	local effectFromColor = getEffectFromColor(zonePart.Color)
	if effectFromColor then
		DBG:print("[EncounterZone] Resolved effect from color:", effectFromColor, "Color:", zonePart.Color)
		return effectFromColor
	end
	
	-- No match found
	return nil
end

-- Get the effect name for a given material (legacy compatibility)
function EncounterZone:_getEffectNameForMaterial(material: Enum.Material): string?
	local materialName = material.Name
	return MATERIAL_TO_EFFECT[materialName]
end

-- Set whether the step effect particles and sound are enabled (based on movement)
function EncounterZone:_setStepEffectsActive(enabled: boolean)
	if self._stepEffectsEnabled == enabled then
		return -- No change needed
	end
	
	self._stepEffectsEnabled = enabled
	
	-- Enable/disable particles
	if self._currentStepEffect then
		for _, child in ipairs(self._currentStepEffect:GetDescendants()) do
			if child:IsA("ParticleEmitter") then
				child.Enabled = enabled
			end
		end
	end
	
	-- Play/pause zone sound based on movement
	if self._currentZoneSound then
		if enabled then
			if not self._currentZoneSound.Playing then
				self._currentZoneSound:Play()
			end
		else
			if self._currentZoneSound.Playing then
				self._currentZoneSound:Pause()
			end
		end
	end
end

-- Clone and attach the step effect for a given effect name
function EncounterZone:_attachStepEffect(effectName: string)
	-- Already using this effect, no need to change
	if self._currentEffectName == effectName and self._currentStepEffect then
		return
	end
	
	-- Clean up existing effect first
	if self._currentStepEffect then
		self._currentStepEffect:Destroy()
		self._currentStepEffect = nil
	end
	self._currentEffectName = nil
	self._stepEffectsEnabled = false
	
	-- Find the effect template
	local effectsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if effectsFolder then
		effectsFolder = effectsFolder:FindFirstChild("Effects")
	end
	if effectsFolder then
		effectsFolder = effectsFolder:FindFirstChild("EncounterZones")
	end
	
	if not effectsFolder then
		DBG:warn("[EncounterZone] Effects folder not found: ReplicatedStorage.Assets.Effects.EncounterZones")
		return
	end
	
	local effectTemplate = effectsFolder:FindFirstChild(effectName)
	if not effectTemplate or not effectTemplate:IsA("Attachment") then
		DBG:warn("[EncounterZone] Effect template not found or not an Attachment:", effectName)
		return
	end
	
	-- Clone and attach to character
	local clonedEffect = effectTemplate:Clone()
	clonedEffect.Parent = self._character
	
	-- Initially disable all particles (they'll be enabled when moving)
	for _, child in ipairs(clonedEffect:GetDescendants()) do
		if child:IsA("ParticleEmitter") then
			child.Enabled = false
		end
	end
	
	self._currentStepEffect = clonedEffect
	self._currentEffectName = effectName
	
	DBG:print("[EncounterZone] Attached step effect:", effectName)
end

-- Remove the current step effect
function EncounterZone:_removeStepEffect()
	if self._currentStepEffect then
		self._currentStepEffect:Destroy()
		self._currentStepEffect = nil
	end
	self._currentEffectName = nil
	self._stepEffectsEnabled = false
end

-- Clean up all step effect resources
function EncounterZone:_cleanupStepEffects()
	-- Disconnect the movement detection connection
	if self._stepEffectConnection then
		self._stepEffectConnection:Disconnect()
		self._stepEffectConnection = nil
	end
	
	-- Remove the effect attachment
	self:_removeStepEffect()
end

--[[ Zone Audio System ]]--

-- Get the sound name for a given effect name
function EncounterZone:_getSoundNameForEffect(effectName: string): string?
	return EFFECT_TO_SOUND[effectName]
end

-- Attach zone ambient sound (starts paused, movement detection controls play/pause)
function EncounterZone:_playZoneSound(soundName: string)
	-- Already using this sound
	if self._currentSoundName == soundName and self._currentZoneSound then
		return
	end
	
	-- Stop any existing sound first
	self:_stopZoneSound()
	
	-- Find the sound template
	local audioFolder = ReplicatedStorage:FindFirstChild("Audio")
	if audioFolder then
		audioFolder = audioFolder:FindFirstChild("SFX")
	end
	if audioFolder then
		audioFolder = audioFolder:FindFirstChild("EncounterZones")
	end
	
	if not audioFolder then
		DBG:warn("[EncounterZone] Audio folder not found: ReplicatedStorage.Audio.SFX.EncounterZones")
		return
	end
	
	local soundTemplate = audioFolder:FindFirstChild(soundName)
	if not soundTemplate or not soundTemplate:IsA("Sound") then
		DBG:warn("[EncounterZone] Sound not found or not a Sound:", soundName)
		return
	end
	
	-- Clone the sound on the character's HumanoidRootPart for spatial audio
	-- Start paused - movement detection will control play/pause
	local clonedSound = soundTemplate:Clone()
	clonedSound.Parent = self._humanoidRootPart
	-- Don't play yet - will be controlled by _setStepEffectsActive based on movement
	
	self._currentZoneSound = clonedSound
	self._currentSoundName = soundName
	
	DBG:print("[EncounterZone] Attached zone sound:", soundName, "(will play when moving)")
end

-- Stop zone ambient sound
function EncounterZone:_stopZoneSound()
	if self._currentZoneSound then
		self._currentZoneSound:Stop()
		self._currentZoneSound:Destroy()
		self._currentZoneSound = nil
	end
	self._currentSoundName = nil
end

-- Update zone audio based on current effect
function EncounterZone:_updateZoneAudio(effectName: string?)
	if not effectName then
		self:_stopZoneSound()
		return
	end
	
	local soundName = self:_getSoundNameForEffect(effectName)
	if soundName then
		self:_playZoneSound(soundName)
	else
		-- No sound for this effect type
		self:_stopZoneSound()
	end
end

-- Start monitoring movement for step effects
function EncounterZone:_startStepEffectMonitoring()
	-- Already monitoring
	if self._stepEffectConnection then
		return
	end
	
	self._stepEffectConnection = RunService.Heartbeat:Connect(function()
		-- Safety check
		if not self._character or not self._character.Parent then
			return
		end
		if not self._humanoidRootPart or not self._humanoidRootPart.Parent then
			return
		end
		
		-- Check if we have an active effect or sound
		if not self._currentStepEffect and not self._currentZoneSound then
			return
		end
		
		-- Check if player is grounded
		local humanoid = self._character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.FloorMaterial == Enum.Material.Air then
			self:_setStepEffectsActive(false)
			return
		end
		
		-- Get horizontal velocity from HumanoidRootPart
		local velocity = self._humanoidRootPart.AssemblyLinearVelocity
		local horizontalSpeed = math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z)
		
		-- Enable/disable effects based on movement
		local isMoving = horizontalSpeed > MOVEMENT_VELOCITY_THRESHOLD
		self:_setStepEffectsActive(isMoving)
	end)
end

-- Stop monitoring movement for step effects
function EncounterZone:_stopStepEffectMonitoring()
	if self._stepEffectConnection then
		self._stepEffectConnection:Disconnect()
		self._stepEffectConnection = nil
	end
	
	-- Disable particles when stopping
	self:_setStepEffectsActive(false)
end

-- Get the current active zone part (first valid one found with active touches)
function EncounterZone:_getCurrentZonePart(): BasePart?
	for zonePart, count in pairs(self._insideZoneParts) do
		if zonePart and zonePart.Parent and count > 0 then
			return zonePart
		end
	end
	-- Fallback to last known zone part during grace period
	if self._lastZonePart and self._lastZonePart.Parent then
		return self._lastZonePart
	end
	return nil
end

-- Update step effects and audio based on current zone state
function EncounterZone:_updateStepEffects()
	-- Check if we're inside any zones (or in grace period with last known zone)
	local currentZonePart = self:_getCurrentZonePart()
	
	if not currentZonePart then
		-- Not in any zone and no grace period fallback
		-- Don't immediately remove - let the grace period in _onZoneExited handle it
		return
	end
	
	-- Use the full resolver to determine the effect
	local effectName = self:_resolveEffectForZonePart(currentZonePart)
	if not effectName then
		-- No effect resolved for this zone, but keep monitoring if we have an effect
		-- (player might walk into a zone that does have an effect)
		return
	end
	
	-- Attach the appropriate effect (handles "already using this effect" case)
	self:_attachStepEffect(effectName)
	
	-- Update zone audio to match the effect
	self:_updateZoneAudio(effectName)
	
	-- Start monitoring if not already
	self:_startStepEffectMonitoring()
end

-- Handle entering a zone part (increment touch count)
function EncounterZone:_onZoneEntered(zonePart: BasePart)
	-- Cancel any pending exit check since we're still in a zone
	if self._pendingZoneExit then
		task.cancel(self._pendingZoneExit)
		self._pendingZoneExit = nil
	end
	
	-- Increment touch count for this zone part
	local currentCount = self._insideZoneParts[zonePart] or 0
	self._insideZoneParts[zonePart] = currentCount + 1
	
	-- Remember this zone part
	self._lastZonePart = zonePart
	
	-- Update effects (will attach if needed)
	self:_updateStepEffects()
end

-- Handle leaving a zone part (decrement touch count with grace period)
function EncounterZone:_onZoneExited(zonePart: BasePart)
	-- Decrement touch count for this zone part
	local currentCount = self._insideZoneParts[zonePart] or 0
	if currentCount > 1 then
		-- Still have other body parts touching this zone
		self._insideZoneParts[zonePart] = currentCount - 1
		return
	end
	
	-- Last touch ended for this zone part
	self._insideZoneParts[zonePart] = nil
	
	-- Check if we're still in any zone
	local stillInZone = false
	for zp, count in pairs(self._insideZoneParts) do
		if zp and zp.Parent and count > 0 then
			stillInZone = true
			break
		end
	end
	
	if stillInZone then
		-- Still in another zone, just update effects (might need to change effect type)
		self:_updateStepEffects()
		return
	end
	
	-- No zones left - start grace period before removing effects
	-- This prevents flickering during normal walking motion
	if self._pendingZoneExit then
		task.cancel(self._pendingZoneExit)
	end
	
	self._pendingZoneExit = task.delay(ZONE_EXIT_GRACE_PERIOD, function()
		self._pendingZoneExit = nil
		
		-- Re-check if we're still not in any zone after grace period
		local inZone = false
		for zp, count in pairs(self._insideZoneParts) do
			if zp and zp.Parent and count > 0 then
				inZone = true
				break
			end
		end
		
		if not inZone then
			-- Still not in any zone after grace period, clean up effects and audio
			DBG:print("[EncounterZone] Left all zones after grace period, removing step effects and audio")
			self:_stopStepEffectMonitoring()
			self:_removeStepEffect()
			self:_stopZoneSound()
			self._lastZonePart = nil
		end
	end)
end

-- Check if player has a valid party
function EncounterZone:_hasValidParty(): boolean
	local playerData = ClientData:Get()
	if not playerData or not playerData.Party or #playerData.Party == 0 then
		if not self._partyEmptyLogged then
			DBG:print("[EncounterZone] Party is empty; encounters disabled")
			self._partyEmptyLogged = true
		end
		return false
	end
	
	if self._partyEmptyLogged then
		self._partyEmptyLogged = false
	end
	
	return true
end

-- Check if player is grounded
function EncounterZone:_isPlayerGrounded(): boolean
	local humanoid = self._character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end
	
	return humanoid.FloorMaterial ~= Enum.Material.Air
end

-- Process step-based functions bound by external systems
function EncounterZone:_processStepFunctions()
	for name, fn in pairs(self._boundStepFunctions) do
		if typeof(fn) == "function" then
			fn()
		elseif typeof(fn) == "table" then
			local stepFn = fn :: BoundStepFunction
			stepFn.Counter += 1
			if stepFn.Counter >= stepFn.Interval then
				stepFn.Counter = 0
				stepFn.Callback()
			end
		end
	end
end

-- Request encounter from server
function EncounterZone:_requestEncounterFromServer()
	self._isRequestingEncounter = true
	
	local success, triggered = pcall(function()
		return self._events.Request:InvokeServer({"TryEncounterStep"})
	end)
	
	self._isRequestingEncounter = false
	
	if not success then
		DBG:warn("[EncounterZone] Failed to request encounter from server:", triggered)
		return false
	end
	
	if triggered and not self._inEncounter then
		self:_onEncounterTriggered()
		return true
	end
	
	return false
end

-- Handle encounter trigger
function EncounterZone:_onEncounterTriggered()
	self._inEncounter = true
	CharacterFunctions:SetSuppressed(true)
	CharacterFunctions:CanMove(false)
	
	-- Play encounter start sound effect
	pcall(function()
		local sfxFolder = ReplicatedStorage:FindFirstChild("Audio")
		if sfxFolder then
			sfxFolder = sfxFolder:FindFirstChild("SFX")
		end
		if sfxFolder then
			local startSound = sfxFolder:FindFirstChild("StartEncounter")
			if startSound and startSound:IsA("Sound") then
				startSound:Play()
			end
		end
	end)
	
	-- Disable step effects and audio during encounter
	self:_setStepEffectsActive(false)
	self:_stopZoneSound()
	
	-- Hide UI
	local ui = GetUI()
	if ui and ui.TopBar then
		pcall(function()
			ui.TopBar:SetSuppressed(true)
			if ui.TopBar.HideImmediate then
				ui.TopBar:HideImmediate()
			else
				ui.TopBar:Hide()
			end
		end)
	end
	
	DBG:print("[EncounterZone] Encounter triggered - battle starting")
end

-- Check for encounter on touch (pure event-driven)
function EncounterZone:_checkForEncounterOnTouch()
	-- Gate: Must not be in encounter already
	if self._inEncounter then
		return
	end

	-- Gate: Do not allow wild encounters during cutscenes or active dialogue
	local cutsceneActive = false
	local dialogueActive = false
	pcall(function()
		cutsceneActive = CutsceneRegistry:IsAnyActive()
		dialogueActive = (Say and Say.IsActive and Say:IsActive()) == true
	end)
	if cutsceneActive or dialogueActive or self._showingRepelPrompt then
		return
	end
	
	-- Gate: Movement must be enabled
	if not CharacterFunctions:CheckCanMove() then
		return
	end
	
	-- Gate: Must have valid party
	if not self:_hasValidParty() then
		return
	end
	
	-- Gate: Must be grounded
	if not self:_isPlayerGrounded() then
		return
	end
	
	-- Track horizontal distance walked since last position
	local currentPosition = self._humanoidRootPart.Position
	local dx = currentPosition.X - self._lastPosition.X
	local dz = currentPosition.Z - self._lastPosition.Z
	local horizontalDistance = math.sqrt(dx * dx + dz * dz)
	
	self._lastPosition = currentPosition
	self._distanceWalked += horizontalDistance
	
	-- Gate: Must have walked enough for a step
	local stepDistance = self._config.StepDistance
	if self._distanceWalked < stepDistance then
		return
	end
	
	-- Convert walked distance into discrete steps
	local stepsGained = math.floor(self._distanceWalked / stepDistance)
	self._distanceWalked = self._distanceWalked - (stepsGained * stepDistance)
	
	-- Process bound step functions
	self:_processStepFunctions()
	
	-- Gate: Immunity steps (prevent spam after battle and repel effects)
	if self._immunitySteps > 0 then
		local oldSteps = self._immunitySteps
		local isRepel = self._immunityIsRepel
		-- Decrement steps (cap at reasonable amount per update to prevent rapid depletion)
		local stepsToDecrement = math.min(stepsGained, 10) -- Cap at 10 steps per update
		self._immunitySteps = math.max(0, self._immunitySteps - stepsToDecrement)
		
		-- Repel-specific handling (UI + server sync) only when a repel is actually active
		if isRepel and oldSteps ~= self._immunitySteps then
			DBG:print("[EncounterZone] Repel steps:", oldSteps, "->", self._immunitySteps, "(decremented", stepsToDecrement, "of", stepsGained, "steps gained)")
			self:_updateStepStatusUI()
			
			-- Sync repel steps with server (for save/load compatibility)
			pcall(function()
				local ClientData = require(script.Parent.Parent.Plugins.ClientData)
				local playerData = ClientData:Get()
				if playerData and playerData.RepelState and playerData.RepelState.ActiveSteps then
					-- Update local client data
					playerData.RepelState.ActiveSteps = self._immunitySteps
					
					-- Notify server if steps reached 0 and show Y/N prompt
					if self._immunitySteps == 0 then
						self:_updateStepStatusUI()
						self._events.Request:InvokeServer({"RepelStepsDepleted"})
						self._immunityIsRepel = false
						DBG:print("[EncounterZone] Repel steps depleted - notifying server")
						
						-- Check if player has any repel items before showing prompt
						local hasRepel = false
						local repelItems = {"Focus Spray", "Super Focus Spray", "Max Focus Spray"}
						local availableRepel = nil
						
						if playerData.Items then
							for _, repelName in ipairs(repelItems) do
								if playerData.Items[repelName] and (playerData.Items[repelName] or 0) > 0 then
									hasRepel = true
									if not availableRepel then
										availableRepel = repelName
									end
									break
								end
							end
						end
						
						-- Only show prompt if player has repel items
						if hasRepel then
							local itemName = playerData.RepelState.ItemName or "Focus Spray"
							-- Set flag to prevent encounters while showing prompt
							self._showingRepelPrompt = true
							task.spawn(function()
								local success, err = pcall(function()
									Say:Say("", false, {"The " .. itemName .. " effect has worn off. Use another?"})
									local wantsAnother = Say:YieldChoice()
									
									if wantsAnother == true then
										-- Exit the current Say UI first
										Say:Exit()
										
										-- Automatically use another repel item (try Focus Spray, then Super, then Max)
										local usedRepel = false
										for _, repelName in ipairs(repelItems) do
											if playerData.Items[repelName] and (playerData.Items[repelName] or 0) > 0 then
												local Events = ReplicatedStorage:WaitForChild("Events")
												local result = Events.Request:InvokeServer({"UseItem", { Name = repelName, Context = "Overworld" }})
												if result == true then
													usedRepel = true
													Say:Say("", true, {"Used " .. repelName .. "!"}, nil, nil)
													local UI = GetUI()
													if UI and UI.TopBar then
														UI.TopBar:SetSuppressed(false)
														UI.TopBar:Show()
													end
													break
												elseif type(result) == "string" then
													Say:Say("", true, {result}, nil, nil)
													break
												end
											end
										end
										
										if not usedRepel then
											Say:Say("", true, {"Could not use repel item."}, nil, nil)
										end
									else
										-- Hide Say UI and restore TopBar when user selects No
										Say:Exit()
										local UI = GetUI()
										if UI and UI.TopBar then
											UI.TopBar:SetSuppressed(false)
											UI.TopBar:Show()
										end
									end
								end)
								
								-- Always clear flag after prompt is resolved (even on error)
								self._showingRepelPrompt = false
								if not success then
									DBG:warn("[EncounterZone] Error in repel prompt:", err)
								end
							end)
						end
					else
						-- Periodically sync with server (every 10 steps)
						if self._immunitySteps % 10 == 0 then
							self._events.Request:InvokeServer({"UpdateRepelSteps", self._immunitySteps})
						end
					end
				end
			end)
		end
		
		return
	end
	
	-- Gate: Time-based cooldown
	local now = tick()
	local timeSinceLastEncounter = now - self._lastEncounterTime
	if timeSinceLastEncounter < self._config.EncounterCooldown then
		return
	end
	
	-- Gate: Prevent multiple simultaneous requests
	if self._isRequestingEncounter then
		return
	end

	--Random chance
	if math.random(1, 100) > self._config.EncounterChance then
		print("No encounter this step")
		return
	end
	
	-- All gates passed - request encounter from server
	self._lastEncounterTime = now
	DBG:print("[EncounterZone] Step taken in encounter zone - requesting from server")
	self:_requestEncounterFromServer()
end

-- Handle zone touched event
function EncounterZone:_onZoneTouched(zonePart: EncounterZonePart, hit: BasePart)
	local character = hit.Parent
	if not character then
		return
	end
	
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local player = Players:GetPlayerFromCharacter(character)
	
	-- Only react to local player's character
	if not humanoid or not player or player ~= self._player then
		return
	end
	
	-- Track zone entry for step effects (always increment touch count)
	self:_onZoneEntered(zonePart)
	
	-- Check for encounter on each touch
	self:_checkForEncounterOnTouch()
end

-- Handle zone touch ended event
function EncounterZone:_onZoneTouchEnded(zonePart: EncounterZonePart, hit: BasePart)
	local character = hit.Parent
	if not character then
		return
	end
	
	local player = Players:GetPlayerFromCharacter(character)
	
	-- Only react to local player's character
	if not player or player ~= self._player then
		return
	end
	
	-- Track zone exit for step effects (decrement touch count)
	self:_onZoneExited(zonePart)
end

--[[ Public Methods ]]--

-- Initialize the encounter system
function EncounterZone:Init()
	DBG:print("[EncounterZone] Initializing event-driven encounter system")
	-- No loop to start - purely event-driven
	
	-- Restore repel state from client data if present
	pcall(function()
		local playerData = ClientData:Get()
		if playerData and playerData.RepelState and playerData.RepelState.ActiveSteps and playerData.RepelState.ActiveSteps > 0 then
			self._immunitySteps = playerData.RepelState.ActiveSteps
			self._immunityIsRepel = true
			DBG:print("[EncounterZone] Restored repel state on init:", playerData.RepelState.ItemName, "with", self._immunitySteps, "steps")
			-- Update UI after restoring repel state
			task.wait(0.5) -- Wait a bit for GameUI to be ready
			self:_updateStepStatusUI()
		end
	end)
end

-- Setup an encounter zone part
function EncounterZone:Setup(zonePart: BasePart): boolean
	if not zonePart or not zonePart:IsA("BasePart") then
		DBG:warn("[EncounterZone] Invalid encounter zone part provided")
		return false
	end
	
	DBG:print("[EncounterZone] Setting up zone:", zonePart.Name, "Material:", zonePart.Material.Name)
	
	-- Store zone reference
	self._activeZones[zonePart.Name] = zonePart :: EncounterZonePart
	
	-- Connect touch event for encounter checks
	local touchedConnection = zonePart.Touched:Connect(function(hit)
		self:_onZoneTouched(zonePart :: EncounterZonePart, hit)
	end)
	
	-- Connect touch ended event for step effect cleanup
	local touchEndedConnection = zonePart.TouchEnded:Connect(function(hit)
		self:_onZoneTouchEnded(zonePart :: EncounterZonePart, hit)
	end)
	
	-- Store connections for cleanup
	self._zoneConnections[zonePart.Name] = {
		Touched = touchedConnection,
		TouchEnded = touchEndedConnection,
	}
	
	return true
end

-- Clean up all encounter zones
function EncounterZone:Cleanup()
	DBG:print("[EncounterZone] Cleaning up encounter zones")
	
	-- Cancel any pending zone exit
	if self._pendingZoneExit then
		task.cancel(self._pendingZoneExit)
		self._pendingZoneExit = nil
	end
	
	-- Disconnect all zone events
	for _, connections in pairs(self._zoneConnections) do
		if connections.Touched then
			connections.Touched:Disconnect()
		end
		if connections.TouchEnded then
			connections.TouchEnded:Disconnect()
		end
	end
	
	-- Clear all state
	table.clear(self._activeZones)
	table.clear(self._zoneConnections)
	table.clear(self._insideZoneParts)
	self._lastZonePart = nil
	
	-- Reset flags
	self._inEncounter = false
	self._isRequestingEncounter = false
	self._partyEmptyLogged = false
	
	-- Reset tracking
	self._lastPosition = self._humanoidRootPart.Position
	self._distanceWalked = 0
	self._lastEncounterTime = 0
	self._immunitySteps = 0
	self._immunityIsRepel = false
	
	-- Clean up step effects and audio
	self:_cleanupStepEffects()
	self:_stopZoneSound()
	
	-- Hide UI when cleaning up
	self:_updateStepStatusUI()
end

-- Set current chunk for encounter context
function EncounterZone:SetCurrentChunk(chunkName: string)
	self._currentChunkName = chunkName
	DBG:print("[EncounterZone] Current chunk set to:", chunkName)
end

-- End encounter and restore normal state
function EncounterZone:EndEncounter()
	self._inEncounter = false
	self._isRequestingEncounter = false
	
	-- Reset cooldown to allow immediate encounter after immunity
	self._lastEncounterTime = tick() - self._config.EncounterCooldown
	
	-- Apply immunity steps to prevent immediate re-encounter
	self._immunitySteps = self._config.ImmunityStepsAfterBattle
	self._immunityIsRepel = false
	self:_updateStepStatusUI()
	
	-- Lift suppression and re-enable movement
	CharacterFunctions:SetSuppressed(false)
	CharacterFunctions:CanMove(true)
	
	-- Reset exclamation mark UI
	local playerGui = self._player.PlayerGui
	local gameUI = playerGui:FindFirstChild("GameUI")
	if gameUI then
		local questionMark = gameUI:FindFirstChild("QuestionMark") or gameUI:FindFirstChild("ExclamationMark")
		if questionMark and questionMark:IsA("GuiObject") then
			questionMark.Visible = false
			pcall(function()
				questionMark.Size = UDim2.fromScale(0, 0)
				questionMark.Rotation = 0
				questionMark.Position = UDim2.fromScale(0.5, 0.5)
			end)
		end

		local flashing = gameUI:FindFirstChild("Flashing")
		if flashing and flashing:IsA("GuiObject") then
			flashing.Visible = false
			pcall(function()
				flashing.BackgroundTransparency = 1
			end)
		end

		local blackBars = gameUI:FindFirstChild("BlackBars")
		if blackBars and blackBars:IsA("GuiObject") then
			blackBars.Visible = false
		end
	end
	
	-- Resume zone audio if still in a zone
	local currentZonePart = self:_getCurrentZonePart()
	if currentZonePart then
		local effectName = self:_resolveEffectForZonePart(currentZonePart)
		if effectName then
			self:_updateZoneAudio(effectName)
		end
	end
	
	DBG:print("[EncounterZone] Encounter ended - movement restored")
end

-- Bind a function to be called on steps
function EncounterZone:BindToStep(name: string, callback: () -> (), intervalSteps: number?)
	if intervalSteps and intervalSteps > 1 then
		self._boundStepFunctions[name] = {
			Callback = callback,
			Interval = intervalSteps,
			Counter = 0,
		}
	else
		self._boundStepFunctions[name] = callback
	end
end

-- Unbind a step function
function EncounterZone:UnbindFromStep(name: string)
	self._boundStepFunctions[name] = nil
end

-- Reset accumulated step distance
function EncounterZone:ResetStepDistance()
	self._distanceWalked = 0
end

-- Get current encounter state (for debugging/external systems)
function EncounterZone:IsInEncounter(): boolean
	return self._inEncounter
end

-- Get current zone count (for debugging)
function EncounterZone:GetActiveZoneCount(): number
	local count = 0
	for _ in pairs(self._activeZones) do
		count += 1
	end
	return count
end

-- Add immunity steps (for repel system)
function EncounterZone:AddImmunitySteps(steps: number)
	if steps and steps > 0 then
		local oldValue = self._immunitySteps
		-- Always set to the new value (don't use max, as we want to replace the current repel)
		self._immunitySteps = steps
		self._immunityIsRepel = true
		DBG:print("[EncounterZone] Set immunity steps to", steps, "(was", oldValue, ")")
		-- Update UI
		self:_updateStepStatusUI()
		return true
	end
	return false
end

-- Get current immunity steps (for UI display)
function EncounterZone:GetImmunitySteps(): number
	return self._immunitySteps
end

-- Get StepStatus UI references (lazy load)
function EncounterZone:_getStepStatusUI()
	if not self._stepStatusUI then
		local playerGui = self._player.PlayerGui
		local gameUI = playerGui:FindFirstChild("GameUI")
		if gameUI then
			self._stepStatusUI = gameUI:FindFirstChild("StepStatus")
			if self._stepStatusUI then
				self._stepStatusIcon = self._stepStatusUI:FindFirstChild("Icon") :: ImageLabel?
				self._stepStatusAMT = self._stepStatusUI:FindFirstChild("AMT") :: TextLabel?
			end
		end
	end
	return self._stepStatusUI, self._stepStatusIcon, self._stepStatusAMT
end

-- Update StepStatus UI based on repel state
function EncounterZone:_updateStepStatusUI()
	local stepStatusUI, icon, amt = self:_getStepStatusUI()
	if not stepStatusUI then
		return -- UI element doesn't exist yet
	end
	
	if self._immunitySteps > 0 and self._immunityIsRepel then
		-- Show UI and update with current repel info
		stepStatusUI.Visible = true
		
		-- Get current repel item name from client data
		local playerData = ClientData:Get()
		local itemName = nil
		if playerData and playerData.RepelState and playerData.RepelState.ItemName then
			itemName = playerData.RepelState.ItemName
		end
		
		-- Update icon if we have an item name
		if icon and itemName then
			local Items = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Items"))
			local itemDef = Items[itemName]
			if itemDef and itemDef.Image then
				icon.Image = itemDef.Image
			end
		end
		
		-- Update step count
		if amt then
			amt.Text = tostring(self._immunitySteps)
		end
	else
		-- Hide UI when no repel is active
		stepStatusUI.Visible = false
	end
end

-- Module-level singleton (legacy compatibility)
local EncounterZoneInstance = EncounterZone.new()

return EncounterZoneInstance


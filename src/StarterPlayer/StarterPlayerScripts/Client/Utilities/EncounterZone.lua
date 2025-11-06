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
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

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
	
	-- Immunity system
	self._immunitySteps = 0
	
	-- Bound step functions for extensibility
	self._boundStepFunctions = {} :: {[string]: any}
	
	-- Current chunk tracking
	self._currentChunkName = nil :: string?
	
	-- Setup character respawn handling
	self:_setupCharacterRespawn()
	
	return self
end

--[[ Private Methods ]]--

-- Handle character respawn
function EncounterZone:_setupCharacterRespawn()
	self._player.CharacterAdded:Connect(function(newCharacter)
		self._character = newCharacter
		self._humanoidRootPart = newCharacter:WaitForChild("HumanoidRootPart") :: BasePart
		self._lastPosition = self._humanoidRootPart.Position
		self._distanceWalked = 0
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
	if cutsceneActive or dialogueActive then
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
	
	-- Gate: Immunity steps (prevent spam after battle)
	if self._immunitySteps > 0 then
		self._immunitySteps = math.max(0, self._immunitySteps - stepsGained)
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
	
	-- Check for encounter on each touch
	self:_checkForEncounterOnTouch()
end

--[[ Public Methods ]]--

-- Initialize the encounter system
function EncounterZone:Init()
	DBG:print("[EncounterZone] Initializing event-driven encounter system")
	-- No loop to start - purely event-driven
end

-- Setup an encounter zone part
function EncounterZone:Setup(zonePart: BasePart): boolean
	if not zonePart or not zonePart:IsA("BasePart") then
		DBG:warn("[EncounterZone] Invalid encounter zone part provided")
		return false
	end
	
	DBG:print("[EncounterZone] Setting up zone:", zonePart.Name)
	
	-- Store zone reference
	self._activeZones[zonePart.Name] = zonePart :: EncounterZonePart
	
	-- Connect touch event (this is the only event we need!)
	local touchedConnection = zonePart.Touched:Connect(function(hit)
		self:_onZoneTouched(zonePart :: EncounterZonePart, hit)
	end)
	
	-- Store connection for cleanup
	self._zoneConnections[zonePart.Name] = {
		Touched = touchedConnection,
	}
	
	return true
end

-- Clean up all encounter zones
function EncounterZone:Cleanup()
	DBG:print("[EncounterZone] Cleaning up encounter zones")
	
	-- Disconnect all zone events
	for _, connections in pairs(self._zoneConnections) do
		if connections.Touched then
			connections.Touched:Disconnect()
		end
	end
	
	-- Clear all state
	table.clear(self._activeZones)
	table.clear(self._zoneConnections)
	
	-- Reset flags
	self._inEncounter = false
	self._isRequestingEncounter = false
	self._partyEmptyLogged = false
	
	-- Reset tracking
	self._lastPosition = self._humanoidRootPart.Position
	self._distanceWalked = 0
	self._lastEncounterTime = 0
	self._immunitySteps = 0
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
	
	-- Lift suppression and re-enable movement
	CharacterFunctions:SetSuppressed(false)
	CharacterFunctions:CanMove(true)
	
	-- Reset exclamation mark UI
	local playerGui = self._player.PlayerGui
	local gameUI = playerGui:FindFirstChild("GameUI")
	if gameUI then
		local exclamationMark = gameUI:FindFirstChild("ExclamationMark")
		if exclamationMark and exclamationMark:IsA("GuiObject") then
			exclamationMark.Visible = false
			pcall(function()
				exclamationMark.ImageTransparency = 1
				exclamationMark.Size = UDim2.fromScale(0, 0)
			end)
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

-- Module-level singleton (legacy compatibility)
local EncounterZoneInstance = EncounterZone.new()

return EncounterZoneInstance

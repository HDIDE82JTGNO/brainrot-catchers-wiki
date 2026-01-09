--!strict
--[[
	CreatureSpawner.lua
	Handles client-side spawning and despawning of party creatures in the overworld.
	Uses client-side simulation for chunk loading compatibility.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")

local ClientData = require(script.Parent.Parent.Plugins.ClientData)

-- Remote for sending animation updates to server
local Request = ReplicatedStorage:WaitForChild("Events"):WaitForChild("Request")

-- Lazy load NPC to avoid circular dependency (NPC requires UI, Party is in UI)
local NPC = nil
local function getNPC()
	if not NPC then
		NPC = require(script.Parent.NPC)
	end
	return NPC
end

local CreatureSpawner = {}
CreatureSpawner.__index = CreatureSpawner

-- Collision group setup
local CREATURE_COLLISION_GROUP = "SpawnedCreatures"
local DEFAULT_COLLISION_GROUP = "Default"

do
	-- Register collision groups
	pcall(function()
		PhysicsService:RegisterCollisionGroup(CREATURE_COLLISION_GROUP)
		
		-- Set collision between spawned creatures and players to false
		-- Note: "plrs" group should already be registered on server
		-- We just need to set the collision relationship
		PhysicsService:CollisionGroupSetCollidable(CREATURE_COLLISION_GROUP, "plrs", false)
		PhysicsService:CollisionGroupSetCollidable(CREATURE_COLLISION_GROUP, DEFAULT_COLLISION_GROUP, true)
	end)
end

-- Track spawned creature per player
local spawnedCreature: Model? = nil
local spawnedSlotIndex: number? = nil

-- Track movement state for spawned creature (animations are handled on server)
local isMoving = false
local movementCheckConnection: RBXScriptConnection? = nil
local descendantAddedConnection: RBXScriptConnection? = nil
local visibilityConnection: RBXScriptConnection? = nil

--[[
	Sets collision group for all parts in a model
]]
local function setCollisionGroup(model: Model, groupName: string)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") or descendant:IsA("MeshPart") then
			pcall(function()
				descendant.CollisionGroup = groupName
				descendant.CanTouch = false
				descendant.CanCollide = false
			end)
		end
	end
end

--[[
	Spawns a creature from party slot (finds server-spawned model and sets up client-side follow system)
	@param slotIndex The party slot index (1-6)
	@param creatureData The creature data
	@param modelName Optional model name to find (if not provided, will search by player name pattern)
]]
function CreatureSpawner:SpawnCreature(slotIndex: number, creatureData: any, modelName: string?): boolean
	print("[CreatureSpawner] SpawnCreature called - slotIndex:", slotIndex, "creatureName:", creatureData and creatureData.Name)
	
	-- Despawn existing creature if any
	if spawnedCreature then
		print("[CreatureSpawner] Despawning existing creature first")
		CreatureSpawner:DespawnCreature()
	end
	
	local player = Players.LocalPlayer
	if not player then
		warn("[CreatureSpawner] LocalPlayer not found")
		return false
	end
	
	-- Find the server-spawned model in workspace
	local model: Model? = nil
	if modelName then
		-- Try to find by exact name first
		model = workspace:FindFirstChild(modelName) :: Model?
	end
	
	-- If not found, search by player name pattern
	if not model then
		local searchName = player.Name .. "_Creature_" .. slotIndex
		model = workspace:FindFirstChild(searchName) :: Model?
	end
	
	-- If still not found, wait a bit for server to spawn it
	if not model then
		print("[CreatureSpawner] Model not found immediately, waiting for server spawn...")
		local searchName = player.Name .. "_Creature_" .. slotIndex
		model = workspace:WaitForChild(searchName, 5) :: Model?
	end
	
	if not model then
		warn("[CreatureSpawner] Could not find server-spawned creature model")
		return false
	end
	
	print("[CreatureSpawner] Found server-spawned model:", model.Name)
	
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then
		warn("[CreatureSpawner] Model missing HumanoidRootPart")
		return false
	end
	
	-- Capture original transparency values and manage visibility for hologram effect
	local originalTransparency: {[Instance]: number} = {}
	
	-- Capture original transparency values
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") or descendant:IsA("MeshPart") or descendant:IsA("Decal") or descendant:IsA("Texture") then
			pcall(function()
				originalTransparency[descendant] = descendant.Transparency
			end)
		end
	end
	
	-- Function to set model visibility (hide = true, show = false)
	local function setModelVisibility(hide: boolean)
		for instance, originalValue in pairs(originalTransparency) do
			if instance.Parent then -- Only update if still in the model
				pcall(function()
					if instance:IsA("BasePart") or instance:IsA("MeshPart") or instance:IsA("Decal") or instance:IsA("Texture") then
						instance.Transparency = hide and 1 or originalValue
					end
				end)
			end
		end
	end
	
	-- Also handle newly added descendants
	local function handleNewDescendant(descendant: Instance)
		if (descendant:IsA("BasePart") or descendant:IsA("MeshPart") or descendant:IsA("Decal") or descendant:IsA("Texture")) and descendant.Parent == model then
			pcall(function()
				-- Capture original transparency if not already captured
				if not originalTransparency[descendant] then
					originalTransparency[descendant] = descendant.Transparency
				end
				-- Set to invisible if model is currently hidden
				if descendant.Transparency ~= 1 then
					descendant.Transparency = 1
				end
			end)
		end
	end
	
	-- Start with model invisible
	setModelVisibility(true)
	
	-- Connect to handle new descendants (use module-level variable for cleanup)
	if visibilityConnection then
		visibilityConnection:Disconnect()
	end
	visibilityConnection = model.DescendantAdded:Connect(handleNewDescendant)
	
	-- Get spawn position for hologram effect
	local spawnPosition = hrp.Position
	
	-- Create hologram effect
	local HologramSpawnEffect = require(script.Parent.HologramSpawnEffect)
	
	-- Use CreateForModel to create hologram sized to the creature model
	HologramSpawnEffect:CreateForModel(model, spawnPosition, {
		onPeak = function()
			-- Make creature visible when hologram reaches peak (after flash)
			setModelVisibility(false) -- false = show (restore original transparency)
			print("[CreatureSpawner] Creature made visible after hologram peak")
		end,
		onDone = function()
			-- Ensure creature is visible after effect completes
			setModelVisibility(false) -- false = show (restore original transparency)
			-- Disconnect visibility handler since effect is done
			if visibilityConnection then
				visibilityConnection:Disconnect()
				visibilityConnection = nil
			end
			print("[CreatureSpawner] Hologram effect completed")
		end
	})
	
	-- Ensure collision group is set on all parts (client-side enforcement)
	setCollisionGroup(model, CREATURE_COLLISION_GROUP)
	print("[CreatureSpawner] Set collision group to", CREATURE_COLLISION_GROUP, "on all parts")
	
	-- Explicitly ensure HumanoidRootPart has all properties set
	if hrp:IsA("BasePart") or hrp:IsA("MeshPart") then
		pcall(function()
			hrp.CollisionGroup = CREATURE_COLLISION_GROUP
			hrp.CanTouch = false
			hrp.CanCollide = false
			print("[CreatureSpawner] Verified HumanoidRootPart properties - CollisionGroup:", hrp.CollisionGroup, "CanTouch:", hrp.CanTouch, "CanCollide:", hrp.CanCollide)
		end)
	end
	
	-- Also set up a connection to apply collision group to any new parts added
	local function applyCollisionToNewPart(part: Instance)
		if (part:IsA("BasePart") or part:IsA("MeshPart")) and part.Parent == model then
			pcall(function()
				part.CollisionGroup = CREATURE_COLLISION_GROUP
				part.CanTouch = false
				part.CanCollide = false
			end)
		end
	end
	
	-- Connect to descendant added to catch any new parts
	-- Disconnect previous connection if exists
	if descendantAddedConnection then
		descendantAddedConnection:Disconnect()
	end
	descendantAddedConnection = model.DescendantAdded:Connect(applyCollisionToNewPart)
	
	-- Ensure humanoid exists and configure it
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("[CreatureSpawner] Model missing Humanoid")
		return false
	end
	
	print("[CreatureSpawner] Found humanoid, configuring")
	-- Make sure humanoid can move (server may have set this, but ensure it's correct)
	humanoid.WalkSpeed = 14
	humanoid.JumpPower = 50
	print("[CreatureSpawner] Humanoid configured - WalkSpeed:", humanoid.WalkSpeed)
	
	-- Setup movement detection to send animation updates to server
	-- Animations are now played on the server so they replicate to all clients
	if hrp and humanoid then
		local movementThreshold = 1.0 -- studs/second to consider "moving"
		
		-- Disconnect previous connection if exists
		if movementCheckConnection then
			movementCheckConnection:Disconnect()
			movementCheckConnection = nil
		end
		
		-- Initialize movement state to false (not moving initially)
		isMoving = false
		
		-- Wait a moment before starting movement detection
		task.wait(0.5)
		
		-- Send initial animation state (idle) to ensure server plays idle
		pcall(function()
			Request:InvokeServer({"UpdateCreatureAnimation", false})
			print("[CreatureSpawner] Sent initial idle animation request")
		end)
		
		movementCheckConnection = RunService.Heartbeat:Connect(function()
			if not spawnedCreature or spawnedCreature ~= model or not humanoid.Parent then
				if movementCheckConnection then
					movementCheckConnection:Disconnect()
					movementCheckConnection = nil
				end
				return
			end
			
				-- Use humanoid velocity magnitude (horizontal speed)
			local velocity = hrp.AssemblyLinearVelocity
			local horizontalSpeed = math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z)
			
			local wasMoving = isMoving
			local newMovingState = horizontalSpeed > movementThreshold
			
			-- Only update if state actually changed
			if newMovingState ~= wasMoving then
				isMoving = newMovingState
				-- Send animation update to server
				pcall(function()
					Request:InvokeServer({"UpdateCreatureAnimation", isMoving})
					if isMoving then
						print("[CreatureSpawner] Creature started moving (speed:", horizontalSpeed, ") - requesting Move animation")
					else
						print("[CreatureSpawner] Creature stopped moving (speed:", horizontalSpeed, ") - requesting Idle animation")
					end
				end)
			end
		end)
	end
	
	-- Start following player
	print("[CreatureSpawner] Starting NPC follow system")
	local npcModule = getNPC()
	if not npcModule then
		warn("[CreatureSpawner] Failed to get NPC module!")
		return false
	end
	
	local followSuccess = npcModule:StartFollowingPlayer(model, {
		stopDistance = 4.5,
		maxTeleportDistance = 60,
		arriveRadius = 1.5,
		pathRecomputeDelay = 0.35,
		walkSpeed = 14,
		runSpeed = 20,
	})
	
	if followSuccess then
		print("[CreatureSpawner] NPC follow system started successfully")
	else
		warn("[CreatureSpawner] Failed to start NPC follow system!")
	end
	
	-- Auto-cleanup if model is removed
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			if spawnedCreature == model then
				spawnedCreature = nil
				spawnedSlotIndex = nil
			end
		end
	end)
	
	spawnedCreature = model
	spawnedSlotIndex = slotIndex
	
	print("[CreatureSpawner] ===== SPAWN COMPLETE =====")
	print("[CreatureSpawner] Creature:", creatureData.Name)
	print("[CreatureSpawner] Slot:", slotIndex)
	print("[CreatureSpawner] Model:", model.Name)
	print("[CreatureSpawner] Model parent:", model.Parent and model.Parent.Name or "nil")
	print("[CreatureSpawner] Model position:", hrp and hrp.Position or "no HRP")
	print("[CreatureSpawner] Stored spawnedSlotIndex:", spawnedSlotIndex)
	print("[CreatureSpawner] GetSpawnedSlotIndex() returns:", CreatureSpawner:GetSpawnedSlotIndex())
	print("[CreatureSpawner] ==========================")
	return true
end

--[[
	Despawns the currently spawned creature
]]
function CreatureSpawner:DespawnCreature(): boolean
	if not spawnedCreature then
		return false
	end
	
	local model = spawnedCreature
	local hrp = model:FindFirstChild("HumanoidRootPart")
	
	-- Disconnect movement check
	if movementCheckConnection then
		movementCheckConnection:Disconnect()
		movementCheckConnection = nil
	end
	
	-- Disconnect descendant added connection
	if descendantAddedConnection then
		descendantAddedConnection:Disconnect()
		descendantAddedConnection = nil
	end
	
	-- Disconnect visibility connection
	if visibilityConnection then
		visibilityConnection:Disconnect()
		visibilityConnection = nil
	end
	
	isMoving = false
	
	-- Stop following immediately (before hologram effect)
	getNPC():StopFollowingPlayer(model)
	
	-- Function to hide the model for fade-out effect
	local function hideModel()
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") or descendant:IsA("MeshPart") or descendant:IsA("Decal") or descendant:IsA("Texture") then
				pcall(function()
					descendant.Transparency = 1
				end)
			end
		end
	end
	
	-- Create hologram fade-out effect if we have a valid model and HRP
	if model and model.Parent and hrp then
		local HologramSpawnEffect = require(script.Parent.HologramSpawnEffect)
		local spawnPosition = hrp.Position
		
		-- Hide the model when fade-out starts
		hideModel()
		
		-- Create fade-out hologram effect
		HologramSpawnEffect:CreateFadeOut(model, function()
			-- Effect completed - cleanup
			print("[CreatureSpawner] Hologram fade-out effect completed")
			
			-- Clear references (don't destroy - server handles that)
			spawnedCreature = nil
			spawnedSlotIndex = nil
		end, function()
			-- Peak callback - ensure model is hidden
			hideModel()
			print("[CreatureSpawner] Hologram fade-out at peak - model hidden")
		end)
		
		print("[CreatureSpawner] Started hologram fade-out effect for despawn")
	else
		-- If model is invalid or already destroyed, just cleanup immediately
		spawnedCreature = nil
		spawnedSlotIndex = nil
		print("[CreatureSpawner] Despawned creature (model invalid, skipped hologram)")
	end
	
	return true
end

--[[
	Gets the currently spawned creature model
	@return Model? The spawned creature model
]]
function CreatureSpawner:GetSpawnedCreature(): Model?
	return spawnedCreature
end

--[[
	Gets the currently spawned slot index
	@return number? The slot index (1-6) or nil
]]
function CreatureSpawner:GetSpawnedSlotIndex(): number?
	return spawnedSlotIndex
end

-- Track if initialized to prevent duplicate listeners
local initialized = false

-- Auto-initialize on module load
do
	print("[CreatureSpawner] Module loaded, auto-initializing...")
	local success, err = pcall(function()
		local Events = ReplicatedStorage:WaitForChild("Events")
		local Communicate = Events:WaitForChild("Communicate")
		print("[CreatureSpawner] Events and Communicate found, setting up listener")
		
		-- Listen for spawn events from server
		print("[CreatureSpawner] Connecting to Communicate.OnClientEvent")
		local connection = Communicate.OnClientEvent:Connect(function(eventType, data)
			-- Only handle creature spawn/despawn events; ignore others to avoid spam
			if eventType ~= "CreatureSpawned" and eventType ~= "CreatureDespawned" then
				return
			end

			if type(data) == "table" then
				if data.DebugLog == true then
					print("[CreatureSpawner] Received CreatureSpawned with keys:")
					for k, v in pairs(data) do
						print("  ", k, "=", v)
					end
				end
			end
			
			if eventType == "CreatureSpawned" then
				-- Check if data is a table
				if type(data) ~= "table" then
					warn("[CreatureSpawner] Invalid data type for CreatureSpawned, expected table, got:", type(data))
					return
				end
				
				local slotIndex = data.SlotIndex
				local creatureData = data.CreatureData
				local modelName = data.ModelName -- Server-provided model name
				
				print("[CreatureSpawner] Parsed - slotIndex:", slotIndex, "creatureData:", creatureData, "modelName:", modelName)
				print("[CreatureSpawner] Creature name:", creatureData and creatureData.Name)
				
				if slotIndex and creatureData then
					local success, err = pcall(function()
						CreatureSpawner:SpawnCreature(slotIndex, creatureData, modelName)
					end)
					if not success then
						warn("[CreatureSpawner] Error spawning creature:", err)
						print(debug.traceback())
					else
						print("[CreatureSpawner] Spawn function completed successfully")
					end
				else
					warn("[CreatureSpawner] Invalid spawn data - slotIndex:", slotIndex, "creatureData:", creatureData)
				end
			elseif eventType == "CreatureDespawned" then
				-- data is the slot index (number)
				local slotIndex = type(data) == "number" and data or nil
				print("[CreatureSpawner] Despawning creature from slot:", slotIndex)
				if slotIndex then
					-- Only despawn if this is the currently spawned slot
					if spawnedSlotIndex == slotIndex then
						CreatureSpawner:DespawnCreature()
					else
						print("[CreatureSpawner] Slot mismatch - current:", spawnedSlotIndex, "requested:", slotIndex)
					end
				end
			end
		end)
		
		-- Cleanup on character removal
		local player = Players.LocalPlayer
		player.CharacterRemoving:Connect(function()
			if spawnedCreature then
				CreatureSpawner:DespawnCreature()
			end
		end)
		
		initialized = true
		print("[CreatureSpawner] Auto-initialized successfully, connection active:", connection.Connected)
	end)
	if not success then
		warn("[CreatureSpawner] Failed to auto-initialize:", err)
	end
end

--[[
	Initializes the creature spawner and sets up event listeners
]]
function CreatureSpawner:Init()
	if initialized then
		warn("[CreatureSpawner] Already initialized, skipping")
		return
	end
	initialized = true
	
	print("[CreatureSpawner] Initializing...")
	local Events = ReplicatedStorage:WaitForChild("Events")
	local Communicate = Events:WaitForChild("Communicate")
	print("[CreatureSpawner] Events and Communicate found, setting up listener")
	
	-- Listen for spawn events from server
	print("[CreatureSpawner] Connecting to Communicate.OnClientEvent")
	local connection = Communicate.OnClientEvent:Connect(function(eventType, data)
		print("[CreatureSpawner] ===== EVENT RECEIVED =====")
		print("[CreatureSpawner] Event type:", tostring(eventType))
		print("[CreatureSpawner] Data type:", type(data))
		if type(data) == "table" then
			print("[CreatureSpawner] Data keys:")
			for k, v in pairs(data) do
				print("  ", k, "=", v)
			end
		else
			print("[CreatureSpawner] Data contents:", data)
		end
		
		if eventType == "CreatureSpawned" then
			-- Check if data is a table
			if type(data) ~= "table" then
				warn("[CreatureSpawner] Invalid data type for CreatureSpawned, expected table, got:", type(data))
				return
			end
			
			local slotIndex = data.SlotIndex
			local creatureData = data.CreatureData
			
			print("[CreatureSpawner] Parsed - slotIndex:", slotIndex, "creatureData:", creatureData)
			print("[CreatureSpawner] Creature name:", creatureData and creatureData.Name)
			
			if slotIndex and creatureData then
				local success, err = pcall(function()
					CreatureSpawner:SpawnCreature(slotIndex, creatureData)
				end)
				if not success then
					warn("[CreatureSpawner] Error spawning creature:", err)
					print(debug.traceback())
				else
					print("[CreatureSpawner] Spawn function completed successfully")
				end
			else
				warn("[CreatureSpawner] Invalid spawn data - slotIndex:", slotIndex, "creatureData:", creatureData)
			end
		elseif eventType == "CreatureDespawned" then
			-- data is the slot index (number)
			local slotIndex = type(data) == "number" and data or nil
			print("[CreatureSpawner] Despawning creature from slot:", slotIndex)
			if slotIndex then
				-- Only despawn if this is the currently spawned slot
				if spawnedSlotIndex == slotIndex then
					CreatureSpawner:DespawnCreature()
				else
					print("[CreatureSpawner] Slot mismatch - current:", spawnedSlotIndex, "requested:", slotIndex)
				end
			end
		end
	end)
	
	-- Cleanup on character removal
	local player = Players.LocalPlayer
	player.CharacterRemoving:Connect(function()
		if spawnedCreature then
			CreatureSpawner:DespawnCreature()
		end
	end)
	
	print("[CreatureSpawner] Initialized")
end

return CreatureSpawner


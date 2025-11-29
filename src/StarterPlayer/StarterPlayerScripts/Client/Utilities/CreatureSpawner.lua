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

-- Track animation tracks for spawned creature
local idleTrack: AnimationTrack? = nil
local moveTrack: AnimationTrack? = nil
local isMoving = false
local movementCheckConnection: RBXScriptConnection? = nil

--[[
	Sets collision group for all parts in a model
]]
local function setCollisionGroup(model: Model, groupName: string)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") or descendant:IsA("MeshPart") then
			pcall(function()
				descendant.CollisionGroup = groupName
			end)
		end
	end
end

--[[
	Spawns a creature from party slot
	@param slotIndex The party slot index (1-6)
	@param creatureData The creature data
]]
function CreatureSpawner:SpawnCreature(slotIndex: number, creatureData: any): boolean
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
	
	local character = player.Character
	if not character then
		warn("[CreatureSpawner] Player character not found, waiting...")
		character = player.CharacterAdded:Wait()
	end
	
	local playerHRP = character:FindFirstChild("HumanoidRootPart")
	if not playerHRP then
		warn("[CreatureSpawner] Player HumanoidRootPart not found")
		return false
	end
	
	print("[CreatureSpawner] Player character found, HRP:", playerHRP)
	
	-- Get creature model from ReplicatedStorage
	local Assets = ReplicatedStorage:WaitForChild("Assets")
	local CreatureModels = Assets:WaitForChild("CreatureModels")
	print("[CreatureSpawner] Looking for creature model:", creatureData.Name)
	local creatureModelTemplate = CreatureModels:FindFirstChild(creatureData.Name)
	
	if not creatureModelTemplate then
		warn("[CreatureSpawner] Creature model not found:", creatureData.Name)
		warn("[CreatureSpawner] Available models:")
		for _, child in ipairs(CreatureModels:GetChildren()) do
			print("  -", child.Name)
		end
		return false
	end
	
	print("[CreatureSpawner] Found creature model:", creatureModelTemplate.Name)
	
	-- Clone and spawn the model
	local model = creatureModelTemplate:Clone()
	
	-- Find HRP before parenting
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		warn("[CreatureSpawner] Model missing HumanoidRootPart:", creatureData.Name)
		model:Destroy()
		return false
	end
	
	-- Set PrimaryPart if not already set
	if not model.PrimaryPart then
		model.PrimaryPart = hrp
	end
	
	-- Position behind player
	local playerCFrame = playerHRP.CFrame
	local spawnPosition = playerCFrame.Position - (playerCFrame.LookVector * 4)
	spawnPosition = Vector3.new(spawnPosition.X, playerHRP.Position.Y, spawnPosition.Z)
	
	-- Parent to workspace and position
	print("[CreatureSpawner] Parenting model to workspace")
	model.Parent = workspace
	print("[CreatureSpawner] Model parented, setting position")
	model:SetPrimaryPartCFrame(CFrame.new(spawnPosition))
	
	print("[CreatureSpawner] Model spawned at position:", spawnPosition)
	print("[CreatureSpawner] Model in workspace:", model.Parent == workspace)
	print("[CreatureSpawner] Model visible:", model and model.Parent ~= nil)
	
	-- Remove Status GUI if present
	if hrp then
		local statusGUI = hrp:FindFirstChild("Status")
		if statusGUI then
			statusGUI:Destroy()
			print("[CreatureSpawner] Removed Status GUI")
		end
	end
	
	-- Apply shiny recolor if needed
	if creatureData.Shiny then
		local Creatures = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Creatures"))
		local species = Creatures and Creatures[creatureData.Name]
		local shinyColors = species and species.ShinyColors
		if shinyColors then
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") or d:IsA("MeshPart") then
					local newColor = shinyColors[d.Name]
					if newColor then
						pcall(function()
							d.Color = newColor
						end)
					end
				end
			end
		end
		
		-- Attach persistent shiny emitters if available
		local effects = Assets:FindFirstChild("Effects")
		local persist = effects and effects:FindFirstChild("PersistentShinyEffect")
		if persist and persist:IsA("BasePart") and hrp then
			local one = persist:FindFirstChild("One")
			local two = persist:FindFirstChild("Two")
			if one and one:IsA("ParticleEmitter") then
				local c1 = one:Clone()
				c1.Parent = hrp
			end
			if two and two:IsA("ParticleEmitter") then
				local c2 = two:Clone()
				c2.Parent = hrp
			end
		end
	end
	
	-- Set collision group (using new API)
	setCollisionGroup(model, CREATURE_COLLISION_GROUP)
	print("[CreatureSpawner] Set collision group to", CREATURE_COLLISION_GROUP)
	
	-- Ensure humanoid exists and configure it
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		print("[CreatureSpawner] Found humanoid, configuring")
		-- Make sure humanoid can move
		humanoid.WalkSpeed = 14
		humanoid.JumpPower = 50
		print("[CreatureSpawner] Humanoid configured - WalkSpeed:", humanoid.WalkSpeed)
		
		-- Setup animation system
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		
		-- Find animations folder
		local animationsFolder = model:FindFirstChild("Animations")
		print("[CreatureSpawner] Animations folder found:", animationsFolder ~= nil)
		if animationsFolder then
			print("[CreatureSpawner] Animations folder children:")
			for _, child in ipairs(animationsFolder:GetChildren()) do
				print("  -", child.Name, "Type:", child.ClassName)
			end
		end
		
		local idleAnim = animationsFolder and animationsFolder:FindFirstChild("Idle")
		local moveAnim = animationsFolder and animationsFolder:FindFirstChild("Move")
		
		print("[CreatureSpawner] Idle animation found:", idleAnim ~= nil, "Type:", idleAnim and idleAnim.ClassName)
		print("[CreatureSpawner] Move animation found:", moveAnim ~= nil, "Type:", moveAnim and moveAnim.ClassName)
		
		-- Load animations but don't play them yet - movement detection will handle that
		if idleAnim and idleAnim:IsA("Animation") then
			local success, result = pcall(function()
				return animator:LoadAnimation(idleAnim)
			end)
			if success and result then
				idleTrack = result
				idleTrack.Priority = Enum.AnimationPriority.Idle
				idleTrack.Looped = true
				print("[CreatureSpawner] Loaded Idle animation successfully")
			else
				warn("[CreatureSpawner] Failed to load Idle animation:", result)
			end
		else
			warn("[CreatureSpawner] Idle animation not found in model.Animations")
			-- Try alternative locations
			local altIdle = model:FindFirstChild("Idle", true)
			if altIdle and altIdle:IsA("Animation") then
				local success, result = pcall(function()
					return animator:LoadAnimation(altIdle)
				end)
				if success and result then
					idleTrack = result
					idleTrack.Priority = Enum.AnimationPriority.Idle
					idleTrack.Looped = true
					print("[CreatureSpawner] Found and loaded Idle animation from alternative location")
				else
					warn("[CreatureSpawner] Failed to load Idle from alternative location:", result)
				end
			else
				warn("[CreatureSpawner] No Idle animation found anywhere in model")
			end
		end
		
		if moveAnim and moveAnim:IsA("Animation") then
			moveTrack = animator:LoadAnimation(moveAnim)
			if moveTrack then
				moveTrack.Priority = Enum.AnimationPriority.Movement
				moveTrack.Looped = true
				print("[CreatureSpawner] Loaded Move animation")
			else
				warn("[CreatureSpawner] Failed to load Move animation")
			end
		else
			warn("[CreatureSpawner] Move animation not found in model.Animations")
			-- Try alternative locations
			local altMove = model:FindFirstChild("Move", true)
			if altMove and altMove:IsA("Animation") then
				moveTrack = animator:LoadAnimation(altMove)
				if moveTrack then
					moveTrack.Priority = Enum.AnimationPriority.Movement
					moveTrack.Looped = true
					print("[CreatureSpawner] Found and loaded Move animation from alternative location")
				end
			end
		end
		
		-- Initialize movement state to false (not moving initially)
		isMoving = false
		
		-- Start with idle animation by default
		if idleTrack then
			local success, err = pcall(function()
				idleTrack:Play()
			end)
			if success then
				print("[CreatureSpawner] Started Idle animation (default), IsPlaying:", idleTrack.IsPlaying)
			else
				warn("[CreatureSpawner] Failed to play Idle animation:", err)
			end
		else
			warn("[CreatureSpawner] No idleTrack to play!")
		end
		
		-- Monitor movement to switch between Idle and Move animations
		-- Use humanoid velocity for more reliable movement detection
		if hrp and humanoid then
			local movementThreshold = 1.0 -- studs/second to consider "moving"
			
			-- Disconnect previous connection if exists
			if movementCheckConnection then
				movementCheckConnection:Disconnect()
				movementCheckConnection = nil
			end
			
			-- Wait a moment before starting movement detection to let idle animation start
			task.wait(0.5)
			
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
				isMoving = horizontalSpeed > movementThreshold
				
				-- Switch animations based on movement state (only when state actually changes)
				if isMoving ~= wasMoving then
					if isMoving then
						-- Start moving: stop idle, play move
						print("[CreatureSpawner] Creature started moving (speed:", horizontalSpeed, ") - switching to Move animation")
						if idleTrack and idleTrack.IsPlaying then
							idleTrack:Stop(0.2)
						end
						if moveTrack then
							if not moveTrack.IsPlaying then
								moveTrack:Play(0.2)
								print("[CreatureSpawner] Started Move animation")
							end
						else
							warn("[CreatureSpawner] Move track is nil!")
						end
					else
						-- Stop moving: stop move, play idle
						print("[CreatureSpawner] Creature stopped moving (speed:", horizontalSpeed, ") - switching to Idle animation")
						if moveTrack and moveTrack.IsPlaying then
							moveTrack:Stop(0.2)
						end
						if idleTrack then
							-- Always ensure idle is playing when stopped
							if not idleTrack.IsPlaying then
								local success, err = pcall(function()
									idleTrack:Play(0.2)
								end)
								if success then
									print("[CreatureSpawner] Started Idle animation, IsPlaying:", idleTrack.IsPlaying)
								else
									warn("[CreatureSpawner] Failed to play Idle animation:", err)
								end
							else
								print("[CreatureSpawner] Idle animation already playing")
							end
						else
							warn("[CreatureSpawner] Idle track is nil!")
						end
					end
				end
			end)
		end
	else
		warn("[CreatureSpawner] No humanoid found in model!")
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
	
	-- Disconnect movement check
	if movementCheckConnection then
		movementCheckConnection:Disconnect()
		movementCheckConnection = nil
	end
	
	-- Stop animations
	if idleTrack then
		pcall(function() idleTrack:Stop(0.1) end)
		idleTrack = nil
	end
	if moveTrack then
		pcall(function() moveTrack:Stop(0.1) end)
		moveTrack = nil
	end
	isMoving = false
	
	-- Stop following
	getNPC():StopFollowingPlayer(spawnedCreature)
	
	-- Destroy model
	spawnedCreature:Destroy()
	spawnedCreature = nil
	spawnedSlotIndex = nil
	
	print("[CreatureSpawner] Despawned creature")
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


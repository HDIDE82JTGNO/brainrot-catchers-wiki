local CreatureSpawnService = {}

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local StatCalc = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StatCalc"))
local CreaturesModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Creatures"))
local DBG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DBG"))

local CREATURE_COLLISION_GROUP = "SpawnedCreatures"
local _spawnedCreatureModels: {[Player]: Model?} = {}
local _creatureAnimationTracks: {[Player]: {Idle: AnimationTrack?, Move: AnimationTrack?}} = {}
local _creatureAnimationState: {[Player]: boolean} = {}
local _spawnedCreatures: {[Player]: number?} = {}
local _spawnedCreatureData: {[Player]: any?} = {} -- Track the actual creature data that was spawned

-- Initialize collision groups for spawned creatures
-- Note: "plrs" group is registered in init.server.lua before this module loads
pcall(function()
	PhysicsService:RegisterCollisionGroup(CREATURE_COLLISION_GROUP)
	-- Set collision relationship both ways to ensure it's bidirectional
	PhysicsService:CollisionGroupSetCollidable(CREATURE_COLLISION_GROUP, "plrs", false)
	PhysicsService:CollisionGroupSetCollidable("plrs", CREATURE_COLLISION_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(CREATURE_COLLISION_GROUP, CREATURE_COLLISION_GROUP, true)
end)

local function stopAnimationTracks(player: Player)
	local tracks = _creatureAnimationTracks[player]
	if not tracks then
		return
	end
	if tracks.Idle then
		pcall(function() tracks.Idle:Stop(0.1) end)
	end
	if tracks.Move then
		pcall(function() tracks.Move:Stop(0.1) end)
	end
end

local function fireCommunicate(player: Player, eventName: string, payload: any?)
	local events = ReplicatedStorage:WaitForChild("Events")
	local communicate = events:WaitForChild("Communicate")
	communicate:FireClient(player, eventName, payload)
end

local function setCollisionGroupOnPart(part: Instance)
	if (part:IsA("BasePart") or part:IsA("MeshPart")) then
		pcall(function()
			part.CollisionGroup = CREATURE_COLLISION_GROUP
		end)
	end
end

local function setNetworkOwnership(part: Instance, player: Player)
	if (part:IsA("BasePart") or part:IsA("MeshPart")) then
		pcall(function()
			part:SetNetworkOwner(player)
		end)
	end
end

local function setPartNonInteractable(part: Instance)
	if (part:IsA("BasePart") or part:IsA("MeshPart")) then
		pcall(function()
			part.CanTouch = false
		end)
	end
end

function CreatureSpawnService.GetSpawnedCreatureModels()
	return _spawnedCreatureModels
end

function CreatureSpawnService.DespawnPlayerCreature(Player: Player)
	local model = _spawnedCreatureModels[Player]
	if model and model.Parent then
		stopAnimationTracks(Player)
		model:Destroy()
		DBG:print("[CreatureSpawnService] Despawned creature model for", Player.Name)
	end
	_spawnedCreatureModels[Player] = nil
	_creatureAnimationTracks[Player] = nil
	_creatureAnimationState[Player] = nil
	_spawnedCreatures[Player] = nil
	_spawnedCreatureData[Player] = nil
end

function CreatureSpawnService.UpdateCreatureAnimation(Player: Player, isMoving: boolean)
	local tracks = _creatureAnimationTracks[Player]
	if not tracks then
		return false, "No spawned creature found"
	end

	local currentState = _creatureAnimationState[Player]
	if currentState == isMoving then
		return true
	end

	_creatureAnimationState[Player] = isMoving

	if isMoving then
		if tracks.Idle then
			pcall(function()
				if tracks.Idle.IsPlaying then
					tracks.Idle:Stop(0.15)
				end
			end)
		end
		if tracks.Move then
			pcall(function()
				if not tracks.Move.IsPlaying then
					tracks.Move:Play(0.15)
					DBG:print("[CreatureSpawnService] Started Move animation for", Player.Name)
				end
			end)
		end
	else
		if tracks.Move then
			pcall(function()
				if tracks.Move.IsPlaying then
					tracks.Move:Stop(0.2)
				end
			end)
		end
		if tracks.Idle then
			pcall(function()
				tracks.Idle:Play(0.2)
				DBG:print("[CreatureSpawnService] Started Idle animation for", Player.Name)
			end)
		end
	end

	return true
end

function CreatureSpawnService.SpawnPlayerCreature(Player: Player, slotIndex: number, creatureData: any): Model?
	local character = Player.Character
	if not character then
		DBG:warn("[CreatureSpawnService] Cannot spawn creature: Player character not found")
		return nil
	end

	local playerHRP = character:FindFirstChild("HumanoidRootPart")
	if not playerHRP then
		DBG:warn("[CreatureSpawnService] Cannot spawn creature: Player HumanoidRootPart not found")
		return nil
	end

	local Assets = ReplicatedStorage:WaitForChild("Assets")
	local CreatureModels = Assets:WaitForChild("CreatureModels")
	local creatureModel = CreatureModels:FindFirstChild(creatureData.Name)

	if not creatureModel then
		DBG:warn("[CreatureSpawnService] Creature model not found:", creatureData.Name)
		return nil
	end

	local model = creatureModel:Clone()

	-- Set collision groups and properties BEFORE parenting to workspace
	-- This ensures no collision can occur during the brief moment of parenting
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant.Parent == model then
			setCollisionGroupOnPart(descendant)
			setNetworkOwnership(descendant, Player)
			setPartNonInteractable(descendant)
		end
	end

	local playerCFrame = playerHRP.CFrame
	local lookVector = playerCFrame.LookVector
	local spawnPosition = playerHRP.Position - lookVector * 3
	spawnPosition = Vector3.new(spawnPosition.X, playerHRP.Position.Y, spawnPosition.Z)

	-- Ensure creature is upright and facing the player
	local targetLookAt = Vector3.new(playerHRP.Position.X, spawnPosition.Y, playerHRP.Position.Z)
	local spawnCFrame = CFrame.new(spawnPosition, targetLookAt)
	model:SetPrimaryPartCFrame(spawnCFrame)
	
	model.Name = Player.Name .. "_Creature_" .. slotIndex
	
	-- Explicitly ensure HumanoidRootPart has all properties set (double-check)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and (hrp:IsA("BasePart") or hrp:IsA("MeshPart")) then
		pcall(function()
			hrp.CollisionGroup = CREATURE_COLLISION_GROUP
			hrp.CanTouch = false
			hrp:SetNetworkOwner(Player)
		end)
	end
	
	model.Parent = Workspace

	-- After parenting, explicitly verify and set properties on HumanoidRootPart again
	-- This ensures the properties persist after replication
	local hrpCheck = model:FindFirstChild("HumanoidRootPart")
	if hrpCheck and (hrpCheck:IsA("BasePart") or hrpCheck:IsA("MeshPart")) then
		pcall(function()
			hrpCheck.CollisionGroup = CREATURE_COLLISION_GROUP
			hrpCheck.CanTouch = false
			hrpCheck:SetNetworkOwner(Player)
			DBG:print("[CreatureSpawnService] Verified HumanoidRootPart properties - CollisionGroup:", hrpCheck.CollisionGroup, "CanTouch:", hrpCheck.CanTouch)
		end)
	end

	DBG:print("[CreatureSpawnService] Collision group", CREATURE_COLLISION_GROUP, "set on all parts")
	DBG:print("[CreatureSpawnService] Set network ownership to", Player.Name, "for all parts")
	DBG:print("[CreatureSpawnService] Set CanTouch = false on all parts to prevent other players from interacting")

	model.DescendantAdded:Connect(function(part) 
		if part.Parent == model then
			setCollisionGroupOnPart(part)
			setNetworkOwnership(part, Player)
			setPartNonInteractable(part)
		end
	end)

	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp then
		local statusGUI = hrp:FindFirstChild("Status")
		if statusGUI and statusGUI:FindFirstChild("CreatureInfo") then
			statusGUI.CreatureInfo.Shiny.Visible = creatureData.Shiny
			statusGUI.CreatureInfo.Lv.LvLabel.Text = "Lv. " .. tostring(creatureData.Level)

			local maxFromServer = creatureData.MaxStats and creatureData.MaxStats.HP
			local statsFallback, maxStatsFallback = StatCalc.ComputeStats(creatureData.Name, creatureData.Level or 1, creatureData.IVs or {}, creatureData.Nature)
			local maxHP = (typeof(maxFromServer) == "number" and maxFromServer > 0 and maxFromServer)
				or (maxStatsFallback and maxStatsFallback.HP)
				or (creatureData.Stats and creatureData.Stats.HP)
				or (creatureData.BaseStats and creatureData.BaseStats.HP)
				or 1

			local percent = creatureData.CurrentHP
			local currentHP: number
			if typeof(percent) == "number" then
				percent = math.clamp(percent, 0, 100)
				currentHP = math.floor(maxHP * (percent / 100) + 0.5)
			elseif creatureData.Stats and typeof(creatureData.Stats.HP) == "number" then
				currentHP = math.clamp(creatureData.Stats.HP, 0, maxHP)
			else
				currentHP = maxHP
			end

			local hpPercent = math.clamp(currentHP / math.max(1, maxHP), 0, 1)
			statusGUI.CreatureInfo.HP.Current.Size = UDim2.new(hpPercent, 0, 1, 0)
		end
	end

	if creatureData.Shiny then
		local species = CreaturesModule and CreaturesModule[creatureData.Name]
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

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 14
		humanoid.JumpPower = 50

		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end

		local animationsFolder = model:FindFirstChild("Animations")
		local idleAnim = animationsFolder and animationsFolder:FindFirstChild("Idle")
		local moveAnim = animationsFolder and animationsFolder:FindFirstChild("Move")

		if not idleAnim then
			idleAnim = model:FindFirstChild("Idle", true)
		end
		if not moveAnim then
			moveAnim = model:FindFirstChild("Move", true)
		end

		local idleTrack: AnimationTrack? = nil
		local moveTrack: AnimationTrack? = nil

		if idleAnim and idleAnim:IsA("Animation") then
			local success, result = pcall(function()
				return animator:LoadAnimation(idleAnim)
			end)
			if success and result then
				idleTrack = result
				idleTrack.Priority = Enum.AnimationPriority.Idle
				idleTrack.Looped = true
				DBG:print("[CreatureSpawnService] Loaded Idle animation for", Player.Name)
			else
				DBG:warn("[CreatureSpawnService] Failed to load Idle animation for", Player.Name, ":", result)
			end
		else
			DBG:warn("[CreatureSpawnService] Idle animation not found for", Player.Name)
		end

		if moveAnim and moveAnim:IsA("Animation") then
			local success, result = pcall(function()
				return animator:LoadAnimation(moveAnim)
			end)
			if success and result then
				moveTrack = result
				moveTrack.Priority = Enum.AnimationPriority.Movement
				moveTrack.Looped = true
				DBG:print("[CreatureSpawnService] Loaded Move animation for", Player.Name)
			else
				DBG:warn("[CreatureSpawnService] Failed to load Move animation for", Player.Name, ":", result)
			end
		else
			DBG:warn("[CreatureSpawnService] Move animation not found for", Player.Name)
		end

		_creatureAnimationTracks[Player] = {
			Idle = idleTrack,
			Move = moveTrack,
		}

		if idleTrack then
			pcall(function()
				idleTrack:Play(0)
				DBG:print("[CreatureSpawnService] Started Idle animation for", Player.Name)
			end)
		end

		_creatureAnimationState[Player] = false
	end

	_spawnedCreatureModels[Player] = model
	DBG:print("[CreatureSpawnService] Spawned creature model for", Player.Name, ":", model.Name)
	DBG:print("[CreatureSpawnService] Set collision group", CREATURE_COLLISION_GROUP, "on all parts")
	return model
end

-- Helper function to check if a creature is fainted
local function isCreatureFainted(creature: any): boolean
	if not creature then
		return true
	end
	-- Check both HP formats: Stats.HP (absolute) and CurrentHP (percentage)
	local hpAbs = creature.Stats and creature.Stats.HP
	local hpPct = creature.CurrentHP
	
	if hpAbs ~= nil then
		return hpAbs <= 0
	end
	if hpPct ~= nil then
		return hpPct <= 0
	end
	-- If no HP data, assume not fainted (shouldn't happen, but safer)
	return false
end

function CreatureSpawnService.ToggleCreatureSpawn(Player: Player, slotIndex: number, creature: any)
	local current = _spawnedCreatures[Player]

	if current == slotIndex then
		CreatureSpawnService.DespawnPlayerCreature(Player)
		fireCommunicate(Player, "CreatureDespawned", slotIndex)
		return true
	elseif current then
		CreatureSpawnService.DespawnPlayerCreature(Player)
		fireCommunicate(Player, "CreatureDespawned", current)
	end

	-- Prevent spawning fainted creatures
	if isCreatureFainted(creature) then
		DBG:print("[CreatureSpawnService] Cannot spawn fainted creature in slot", slotIndex, "for", Player.Name)
		return false, "Cannot spawn fainted creature"
	end

	local model = CreatureSpawnService.SpawnPlayerCreature(Player, slotIndex, creature)
	if not model then
		return false, "Failed to spawn creature"
	end

	_spawnedCreatures[Player] = slotIndex
	_spawnedCreatureData[Player] = creature -- Store the creature data for comparison
	fireCommunicate(Player, "CreatureSpawned", {
		SlotIndex = slotIndex,
		CreatureData = creature,
		ModelName = model.Name,
	})
	DBG:print("[CreatureSpawnService] Event fired successfully for", Player.Name)
	return true
end

function CreatureSpawnService.CleanupPlayer(Player: Player)
	CreatureSpawnService.DespawnPlayerCreature(Player)
	_spawnedCreatures[Player] = nil
	_spawnedCreatureData[Player] = nil
end

-- Check if the currently spawned creature is fainted and despawn it if so
-- Also checks all party creatures and despawns any that are fainted
function CreatureSpawnService.CheckAndDespawnFaintedCreatures(Player: Player)
	local ClientData = require(script.Parent.ClientData)
	local PlayerData = ClientData:Get(Player)
	if not PlayerData or not PlayerData.Party then
		return
	end
	
	local spawnedSlot = _spawnedCreatures[Player]
	if spawnedSlot then
		local creature = PlayerData.Party[spawnedSlot]
		if creature and isCreatureFainted(creature) then
			DBG:print("[CreatureSpawnService] Despawning fainted creature in slot", spawnedSlot, "for", Player.Name)
			CreatureSpawnService.DespawnPlayerCreature(Player)
			fireCommunicate(Player, "CreatureDespawned", spawnedSlot)
			_spawnedCreatures[Player] = nil
		end
	end
end

-- Check if a specific slot's creature is spawned and despawn it
function CreatureSpawnService.CheckAndDespawnSlot(Player: Player, slotIndex: number)
	local spawnedSlot = _spawnedCreatures[Player]
	if spawnedSlot == slotIndex then
		DBG:print("[CreatureSpawnService] Despawning creature from slot", slotIndex, "for", Player.Name)
		CreatureSpawnService.DespawnPlayerCreature(Player)
		fireCommunicate(Player, "CreatureDespawned", slotIndex)
		_spawnedCreatures[Player] = nil
		return true
	end
	return false
end

-- Get the currently spawned slot index for a player
function CreatureSpawnService.GetSpawnedSlotIndex(Player: Player): number?
	return _spawnedCreatures[Player]
end

-- Get the currently spawned creature data for a player
function CreatureSpawnService.GetSpawnedCreatureData(Player: Player): any?
	return _spawnedCreatureData[Player]
end

-- Helper function to create a fingerprint for creature comparison
local function creatureFingerprint(c: any): string
	if typeof(c) ~= "table" then return "" end
	local caught = c.CatchData or {}
	local key = table.concat({ 
		tostring(c.Name), 
		tostring(c.Level), 
		tostring(c.Gender), 
		tostring(c.Shiny), 
		tostring(c.Nickname or ""), 
		tostring(c.OT or ""), 
		tostring(caught.CaughtWhen or 0), 
		tostring(caught.CaughtBy or "") 
	}, "|")
	return key
end

-- Check if the spawned creature still exists in the party (at any slot)
-- Returns the slot index if found, or nil if not found
function CreatureSpawnService.FindSpawnedCreatureInParty(Player: Player, party: {any}?): number?
	local spawnedCreatureData = _spawnedCreatureData[Player]
	
	if not spawnedCreatureData or not party then
		DBG:print("[CreatureSpawnService] FindSpawnedCreatureInParty: No spawned creature data or party for", Player.Name)
		return nil
	end
	
	local spawnedFp = creatureFingerprint(spawnedCreatureData)
	if spawnedFp == "" then
		DBG:warn("[CreatureSpawnService] FindSpawnedCreatureInParty: Invalid fingerprint for spawned creature", Player.Name)
		return nil
	end
	
	DBG:print("[CreatureSpawnService] FindSpawnedCreatureInParty: Searching for creature with fingerprint:", spawnedFp, "for", Player.Name)
	
	-- Search all party slots to find the spawned creature
	-- This handles party compaction where slot indices shift
	for i = 1, 6 do
		local creature = party[i]
		if creature then
			local creatureFp = creatureFingerprint(creature)
			DBG:print("[CreatureSpawnService] FindSpawnedCreatureInParty: Slot", i, "has fingerprint:", creatureFp)
			if creatureFp == spawnedFp then
				DBG:print("[CreatureSpawnService] FindSpawnedCreatureInParty: Found spawned creature at slot", i, "for", Player.Name)
				return i -- Found the spawned creature at this slot
			end
		end
	end
	
	DBG:print("[CreatureSpawnService] FindSpawnedCreatureInParty: Spawned creature not found in party for", Player.Name)
	return nil -- Creature not found in party (was moved to box)
end

-- Check if the creature at the spawned slot is still the same creature that was spawned
-- This is a legacy function, but we'll update it to use the new search function
function CreatureSpawnService.IsSpawnedCreatureStillInSlot(Player: Player, party: {any}?): boolean
	local foundSlot = CreatureSpawnService.FindSpawnedCreatureInParty(Player, party)
	local spawnedSlot = _spawnedCreatures[Player]
	
	if not foundSlot then
		return false -- Creature not in party anymore
	end
	
	-- If found at a different slot, update the tracked slot index
	-- This handles party compaction where creatures shift slots
	if foundSlot ~= spawnedSlot then
		DBG:print("[CreatureSpawnService] Spawned creature moved from slot", spawnedSlot, "to slot", foundSlot, "for", Player.Name, "- updating slot index")
		-- Notify client that the creature despawned from old slot
		if spawnedSlot then
			fireCommunicate(Player, "CreatureDespawned", spawnedSlot)
		end
		-- Update tracked slot index
		_spawnedCreatures[Player] = foundSlot
		-- Notify client that the creature spawned at new slot
		local creatureData = _spawnedCreatureData[Player]
		if creatureData then
			local model = _spawnedCreatureModels[Player]
			fireCommunicate(Player, "CreatureSpawned", {
				SlotIndex = foundSlot,
				CreatureData = creatureData,
				ModelName = model and model.Name or "",
			})
			DBG:print("[CreatureSpawnService] Notified client of slot change from", spawnedSlot, "to", foundSlot)
		end
	end
	
	return true -- Creature still in party
end

return CreatureSpawnService


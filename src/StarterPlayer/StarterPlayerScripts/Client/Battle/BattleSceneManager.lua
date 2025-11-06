--!strict
--[[
	BattleSceneManager.lua
	Manages battle scene loading, creature spawning, and cleanup
	Handles hologram effects and model management
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local HologramSpawnEffect = require(script.Parent.Parent.Utilities:WaitForChild("HologramSpawnEffect"))

local BattleSceneManager = {}
BattleSceneManager.__index = BattleSceneManager

export type BattleSceneManagerType = typeof(BattleSceneManager.new())

--[[
	Creates a new battle scene manager instance
	@return BattleSceneManager
]]
function BattleSceneManager.new(): any
	local self = setmetatable({}, BattleSceneManager)
	
	self._currentScene = nil
	self._playerCreatureModel = nil
	self._foeCreatureModel = nil
	self._assets = ReplicatedStorage:WaitForChild("Assets")
	self._creatureModels = self._assets:WaitForChild("CreatureModels")
	self._effects = self._assets:FindFirstChild("Effects")
	
	return self
end

--[[
	Loads a battle scene from PlayerGui and moves it to Workspace
	@param chunkName The chunk name for the scene
	@return boolean Success
]]
function BattleSceneManager:LoadScene(chunkName: string): boolean
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local sceneName = "BattleScene_" .. chunkName
	local scene = playerGui:FindFirstChild(sceneName)
	
	if not scene then
		warn("[BattleSceneManager] Battle scene not found:", sceneName)
		return false
	end
	
	print("[BattleSceneManager] Found battle scene in PlayerGui:", sceneName)
	
	-- Move scene from PlayerGui to Workspace
	scene.Parent = workspace
	print("[BattleSceneManager] Moved battle scene to Workspace")
	
	-- Wait a frame for all children to replicate properly
	task.wait()
	print("[BattleSceneManager] Scene replication complete")
	
	self._currentScene = scene
	return true
end

--[[
	Gets the current battle scene
	@return Model? The battle scene
]]
function BattleSceneManager:GetScene(): Model?
	return self._currentScene
end

--[[
	Gets spawn points from the scene
	@return BasePart? playerSpawn, BasePart? foeSpawn
]]
function BattleSceneManager:GetSpawnPoints(): (BasePart?, BasePart?)
	if not self._currentScene then
		return nil, nil
	end
	
	local essentials = self._currentScene:FindFirstChild("Essentials")
	if not essentials then
		return nil, nil
	end
	
	local playerSpawn = essentials:FindFirstChild("PlayerCreatureSpawn")
	local foeSpawn = essentials:FindFirstChild("FoeCreatureSpawn")
	
	return playerSpawn, foeSpawn
end

--[[
	Spawns a creature model at a spawn point
	@param creatureData The creature data
	@param spawnPoint The spawn point
	@param isPlayer Whether this is the player's creature
	@param useHologram Whether to use hologram effect
	@param onComplete Optional callback when spawn completes
	@return Model? The spawned model
]]
function BattleSceneManager:SpawnCreature(
	creatureData: any,
	spawnPoint: BasePart,
	isPlayer: boolean,
	useHologram: boolean,
	onComplete: (() -> ())?
): Model?
	local creatureModel = self._creatureModels:FindFirstChild(creatureData.Name)
	if not creatureModel then
		warn("Creature model not found:", creatureData.Name)
		return nil
	end
	
	local model = creatureModel:Clone()
	model.Parent = workspace
	
	-- Position model
	model:SetPrimaryPartCFrame(spawnPoint.CFrame + Vector3.new(0, 5, 0))
	
	-- Remove Status GUI
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp then
		local statusGUI = hrp:FindFirstChild("Status")
		if statusGUI then
			statusGUI:Destroy()
		end
	end
	
	-- Apply shiny recolor if needed (no highlight)
	if creatureData.Shiny then
		local creaturesData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Creatures"))
		local species = creaturesData and creaturesData[creatureData.Name]
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

		-- Attach persistent shiny emitters from Assets.Effects.PersistentShinyEffect
		local effects = self._effects
		local persist = effects and effects:FindFirstChild("PersistentShinyEffect")
		if persist and persist:IsA("BasePart") then
			local hrp = model:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") then
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
	end
	
	-- Destroy old model if it exists (for mid-battle switches)
	if isPlayer and self._playerCreatureModel then
		print("[BattleSceneManager] Destroying old player creature model before spawn:", self._playerCreatureModel.Name)
		self._playerCreatureModel:Destroy()
		self._playerCreatureModel = nil
	elseif (not isPlayer) and self._foeCreatureModel then
		print("[BattleSceneManager] Destroying old foe creature model before spawn:", self._foeCreatureModel.Name)
		self._foeCreatureModel:Destroy()
		self._foeCreatureModel = nil
	end
	
	print("[BattleSceneManager] Spawning creature:", creatureData.Name, "IsPlayer:", isPlayer, "UseHologram:", useHologram)
	
	-- Store reference
	if isPlayer then
		self._playerCreatureModel = model
	else
		self._foeCreatureModel = model
	end
	
	-- Spawn with or without hologram
	if useHologram then
		self:_spawnWithHologram(model, spawnPoint, onComplete)
	else
		self:_spawnInstant(model, spawnPoint, onComplete)
	end
	
	return model
end

--[[
	Gets the player's creature model
	@return Model? The player creature model
]]
function BattleSceneManager:GetPlayerCreature(): Model?
	return self._playerCreatureModel
end

--[[
	Gets the foe's creature model
	@return Model? The foe creature model
]]
function BattleSceneManager:GetFoeCreature(): Model?
	return self._foeCreatureModel
end

--[[
	Despawns a creature model
	@param isPlayer Whether this is the player's creature
	@param useHologram Whether to use hologram fade-out
	@param onComplete Optional callback
]]
function BattleSceneManager:DespawnCreature(
	isPlayer: boolean,
	useHologram: boolean,
	onComplete: (() -> ())?
)
	local model = isPlayer and self._playerCreatureModel or self._foeCreatureModel
	if not model then
		if onComplete then
			onComplete()
		end
		return
	end
	
	if useHologram then
		-- TODO: Implement hologram fade-out
		model:Destroy()
		if onComplete then
			onComplete()
		end
	else
		model:Destroy()
		if onComplete then
			onComplete()
		end
	end
	
	if isPlayer then
		self._playerCreatureModel = nil
	else
		self._foeCreatureModel = nil
	end
end

--[[
	Cleans up all creatures and scene
]]
function BattleSceneManager:Cleanup()
	print("[BattleSceneManager] Cleaning up battle scene")
	
	if self._playerCreatureModel then
		self._playerCreatureModel:Destroy()
		self._playerCreatureModel = nil
		print("[BattleSceneManager] Destroyed player creature model")
	end
	
	if self._foeCreatureModel then
		self._foeCreatureModel:Destroy()
		self._foeCreatureModel = nil
		print("[BattleSceneManager] Destroyed foe creature model")
	end
	
	if self._currentScene then
		print("[BattleSceneManager] Destroying battle scene:", self._currentScene.Name)
		self._currentScene:Destroy()
		self._currentScene = nil
	end
end

--[[
	Internal: Spawns creature with hologram effect
]]
function BattleSceneManager:_spawnWithHologram(model: Model, spawnPoint: BasePart, onComplete: (() -> ())?)
	print("[BattleSceneManager] _spawnWithHologram called for:", model.Name)
	local primaryPart = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not primaryPart then
		warn("[BattleSceneManager] No primary part found, falling back to instant spawn")
		self:_spawnInstant(model, spawnPoint, onComplete)
		return
	end
	
    -- Move off-screen temporarily
	local originalCFrame = spawnPoint.CFrame + Vector3.new(0, 3, 0) -- Spawn 3 studs higher
	primaryPart.CFrame = originalCFrame * CFrame.new(0, -1000, 0)
	print("[BattleSceneManager] Model moved off-screen, creating hologram effect")

    -- Start idle animation immediately (avoid T-pose before hologram completes)
    local function playIdleNow()
        local humanoid = model:FindFirstChildOfClass("Humanoid")
        local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
        if humanoid and not animator then
            animator = Instance.new("Animator")
            animator.Parent = humanoid
        end
        if animator then
            -- Find an Animation named "Idle" under the model
            local idleAnim = model:FindFirstChild("Idle", true)
            if idleAnim and idleAnim:IsA("Animation") then
                local ok, track = pcall(function()
                    return animator:LoadAnimation(idleAnim)
                end)
                if ok and track then
                    pcall(function()
                        track.Priority = Enum.AnimationPriority.Core
                        track.Looped = true
                        track:Play(0.05)
                    end)
                    pcall(function()
                        model:SetAttribute("EarlyIdlePlaying", true)
                    end)
                end
            end
        end
    end
    playIdleNow()
	
	-- Create hologram effect
	HologramSpawnEffect:CreateForModel(model, originalCFrame.Position, {
		onPeak = function()
			print("[BattleSceneManager] Hologram peak reached for:", model.Name)
			task.wait(0.2)
			-- Teleport model to spawn when hologram is visible
			if primaryPart then
				primaryPart.CFrame = originalCFrame
				print("[BattleSceneManager] Model teleported to spawn position")
			end
		end,
		onDone = function()
			print("[BattleSceneManager] Hologram effect complete for:", model.Name)
			if onComplete then
				onComplete()
			end
		end
	})
end

--[[
	Internal: Spawns creature instantly
]]
function BattleSceneManager:_spawnInstant(model: Model, spawnPoint: BasePart, onComplete: (() -> ())?)
	local primaryPart = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if primaryPart then
		primaryPart.CFrame = spawnPoint.CFrame + Vector3.new(0, 3, 0) -- Spawn 3 studs higher
	end
	
	if onComplete then
		onComplete()
	end
end

--[[
	Internal: Adds shiny effect to model
]]
-- Shiny highlight removed in favor of direct recolor

return BattleSceneManager

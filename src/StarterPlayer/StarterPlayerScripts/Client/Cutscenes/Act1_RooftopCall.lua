local PlayersService = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

local ClientRoot = script.Parent.Parent
local Utilities = ClientRoot:WaitForChild("Utilities")
local UI = require(ClientRoot:WaitForChild("UI"))
local UIFunctions = require(ClientRoot:WaitForChild("UI"):WaitForChild("UIFunctions"))
local Say = require(Utilities:WaitForChild("Say"))
local DBG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DBG"))
local CharacterFunctions = require(Utilities:WaitForChild("CharacterFunctions"))

local CreatureModels = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("CreatureModels")

local function resolveEssentials(currentChunk: any): Instance?
	if not currentChunk then return nil end
	if currentChunk.Essentials then return currentChunk.Essentials end
	if currentChunk.Model and currentChunk.Model:FindFirstChild("Essentials") then
		return currentChunk.Model:FindFirstChild("Essentials")
	end
	return nil
end

return function(currentChunk: any, handle: any): boolean
	DBG:print("[Act1_RooftopCall] Begin (modular)")
	local camera = workspace.CurrentCamera
	local essentials = resolveEssentials(currentChunk)
	DBG:print("[Act1_RooftopCall] Essentials:", essentials)
	local introFolder = essentials and essentials:FindFirstChild("Intro")
	DBG:print("[Act1_RooftopCall] Intro folder:", introFolder)
	local function getPart(name: string): BasePart?
		local p = introFolder and introFolder:FindFirstChild(name)
		return (p and p:IsA("BasePart")) and p or nil
	end

	local function resolveBasePart(root: Instance?, name: string): BasePart?
		if not root then return nil end
		local inst = root:FindFirstChild(name)
		if inst then
			if inst:IsA("BasePart") then return inst end
			local child = inst:FindFirstChildOfClass("BasePart")
			if child then return child end
		end
		return root:FindFirstChildOfClass("BasePart")
	end

	local Cam1 = getPart("Cam1")
	local Cam2 = getPart("Cam2")
	local Cam3 = getPart("Cam3")
	local Cam4 = getPart("Cam4")
	local Cam5 = getPart("Cam5")
	local Cam6 = getPart("Cam6")
	local Cam7 = getPart("Cam7")
	local Cam8 = getPart("Cam8")
	local spawnPart: BasePart? = resolveBasePart(introFolder, "FrulliFrullaSpawn")

	-- Debug which references are missing
	local missing = {}
	if not Cam1 then table.insert(missing, "Cam1") end
	if not Cam2 then table.insert(missing, "Cam2") end
	if not Cam3 then table.insert(missing, "Cam3") end
	if not Cam4 then table.insert(missing, "Cam4") end
	if not Cam5 then table.insert(missing, "Cam5") end
	if not Cam6 then table.insert(missing, "Cam6") end
	if not Cam7 then table.insert(missing, "Cam7") end
	if not Cam8 then table.insert(missing, "Cam8") end
	if not spawnPart then table.insert(missing, "FrulliFrullaSpawn") end
	if #missing > 0 then
		DBG:print("[Act1_RooftopCall] Missing parts:", table.concat(missing, ", "))
		return false
	end

	-- Spawn the cutscene model
	local cutsceneModelTemplate = CreatureModels:FindFirstChild("FrulliFrulla_Cutscene")
	local model: Model? = nil
	if not cutsceneModelTemplate then
		DBG:print("[Act1_RooftopCall] Model template not found in CreatureModels.")
	else
		model = cutsceneModelTemplate:Clone()
		model.Name = "FrulliFrulla_Cutscene"
		local parentContainer: Instance = (currentChunk and currentChunk.Model) or (essentials and essentials.Parent) or workspace
		model.Parent = parentContainer
		if model.PrimaryPart then
			model:SetPrimaryPartCFrame(spawnPart.CFrame)
		end
		DBG:print("[Act1_RooftopCall] Model cloned and positioned")
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://90227010722534"
	pcall(function() ContentProvider:PreloadAsync({anim}) end)
	local humanoid: Humanoid? = model and model:FindFirstChildOfClass("Humanoid") or nil
	local animController: AnimationController? = model and model:FindFirstChildOfClass("AnimationController") or nil
	local loader = humanoid or animController

	-- Camera sequence
    UIFunctions:Transition(true)
    UI.TopBar:SetSuppressed(true) 
    UI.TopBar:Hide()
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = Cam1.CFrame
	UIFunctions:Transition(false)
	task.wait(0.35)
	TweenService:Create(camera, TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { CFrame = Cam2.CFrame }):Play()
	task.wait(3)
	camera.CFrame = Cam3.CFrame
	TweenService:Create(camera, TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { CFrame = Cam4.CFrame }):Play()
	task.wait(3)
	DBG:print("[Act1_RooftopCall] Cam1->Cam4 complete")

	local track: AnimationTrack? = nil
	if loader and loader.LoadAnimation then
		track = loader:LoadAnimation(anim)
		track:Play(0.1, 1, 1)
	end
	if track then repeat task.wait() until track.TimePosition > 0 or not track.IsPlaying end
	DBG:print("[Act1_RooftopCall] Animation started")
	camera.CFrame = Cam5.CFrame
	task.wait(0.2)
	TweenService:Create(camera, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { CFrame = Cam6.CFrame }):Play()
	task.wait(0.4)
Say:Say("Frulli Frulla", false, { { Text = "FRULLLL-LAAAAA!", Emotion = "Excited" } })
	DBG:print("[Act1_RooftopCall] Dialogue shown")
	task.wait(0.85)

	-- Fade to black and cleanup
    UIFunctions:Transition(true)
	pcall(function() Say:Exit() end)
	task.wait(0.5)
    pcall(function() if model and model.Parent then model:Destroy() end end)

	-- Next phase: load PlayersHouse and play NPC intro anim + dialogue
	local player = PlayersService.LocalPlayer
	local ChunkLoaderModule = require(Utilities:WaitForChild("ChunkLoader"))
	local _cutscene_npc: Model? = nil
	local _spawn_cframe: CFrame? = nil

	local preloadAnim = Instance.new("Animation")
	preloadAnim.AnimationId = "rbxassetid://111906838982660"
	pcall(function() ContentProvider:PreloadAsync({preloadAnim}) end)

	local function finishRestore()
		camera.CameraType = Enum.CameraType.Custom
		pcall(function()
			local character = player.Character or player.CharacterAdded:Wait()
			local hrp2 = character and character:FindFirstChild("HumanoidRootPart")
			if hrp2 and _spawn_cframe then
				local baseHRP2: BasePart = hrp2 :: BasePart
				baseHRP2.CFrame = _spawn_cframe
			end
			if hrp2 then
				local baseHRP2b: BasePart = hrp2 :: BasePart
				baseHRP2b.Anchored = false
			end
			local hum2: Humanoid? = character and character:FindFirstChildOfClass("Humanoid")
			if hum2 then hum2.AutoRotate = true end
			if _cutscene_npc and _cutscene_npc.Parent then _cutscene_npc:Destroy() end
			_cutscene_npc = nil
			_spawn_cframe = nil
		end)
	end

	local loaded, chunkData = ChunkLoaderModule:ClientRequestChunk("PlayersHouse")
	if loaded and chunkData and chunkData.Essentials then
		local intro2 = chunkData.Essentials:FindFirstChild("Intro")
		local camPart = intro2 and intro2:FindFirstChild("CameraPart")
		local spawnPart2 = intro2 and intro2:FindFirstChild("PlayerSpawn")
        if camPart and camPart:IsA("BasePart") then
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = (camPart :: BasePart).CFrame
			camera.FieldOfView = 35
		end
        UIFunctions:Transition(false)
		local character = player.Character or player.CharacterAdded:Wait()
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if hrp then (hrp :: BasePart).Anchored = true end
		CharacterFunctions:CanMove(false)
		if humanoid then humanoid.AutoRotate = false end
		if spawnPart2 and spawnPart2:IsA("BasePart") then
			local desc: HumanoidDescription? = nil
			pcall(function()
				desc = PlayersService:GetHumanoidDescriptionFromUserId(player.UserId)
			end)
			local npc: Model? = nil
			pcall(function()
				if desc then
					npc = PlayersService:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
				else
					npc = PlayersService:CreateHumanoidModelFromUserId(player.UserId)
				end
			end)
			if npc then
				npc.Name = "PlayerNPC_Cutscene"
				npc.Parent = chunkData.Model
				local npcHRP = npc:FindFirstChild("HumanoidRootPart")
				if npcHRP and npcHRP:IsA("BasePart") then
					local baseNpcHRP: BasePart = npcHRP :: BasePart
					baseNpcHRP.CFrame = (spawnPart2 :: BasePart).CFrame
					baseNpcHRP.Anchored = true
				end
				local npcHum: Humanoid? = npc:FindFirstChildOfClass("Humanoid")
				if npcHum then
					npcHum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
					local tr = npcHum:LoadAnimation(preloadAnim)
					tr:Play(0.1, 1, 1)
					task.spawn(function()
						repeat task.wait() until tr.TimePosition > 0 or not tr.IsPlaying
						if tr.IsPlaying == true then
							DBG:print("[Act1_RooftopCall] NPC intro animation started playing")
							task.wait(0.9)
Say:Say("Me", false, { { Text = "WOAAH!", Emotion = "Happy" } })
							task.wait(1.1)
							Say:Exit()
							task.wait(0.85)
Say:Say("Me", false, { { Text = "WAIT!", Emotion = "Angry" } })
							task.wait(0.65)
							Say:Exit()
Say:Say("Me", false, { { Text = "TODAY IS THE DAY!", Emotion = "Happy" } })
							task.wait(0.85)
							Say:Exit()
Say:Say("Me", false, { { Text = "I'M GOING TO BE A TRAINER!", Emotion = "Happy" } })
							task.wait(1.12)
							Say:Exit()
Say:Say("Me", false, { { Text = "Woah woah!", Emotion = "Confused" } })
							task.wait(1)
							Say:Exit()
Say:Say("Mom", false, { { Text = "Cmon! You're gonna be late!", Emotion = "Angry" } })
							task.wait(1)
							Say:Exit()
Say:Say("Me", false, { { Text = "I better get going!", Emotion = "Neutral" } })
							task.wait(2)
                            Say:Exit()
                            finishRestore()
							camera.FieldOfView = 70
                            if handle and handle.End then handle:End() end
						end
					end)
				end
				_cutscene_npc = npc
				_spawn_cframe = (spawnPart2 :: BasePart).CFrame
			end
		end
	end
	-- Do not end here; wait for handle:End() in the async flow
	return false
end



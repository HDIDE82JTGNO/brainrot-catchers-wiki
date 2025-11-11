local PlayersService = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Events = ReplicatedStorage:WaitForChild("Events")
local RSAssets = ReplicatedStorage:WaitForChild("Assets")

local ClientRoot = script.Parent.Parent
local Utilities = ClientRoot:WaitForChild("Utilities")
local UI = require(ClientRoot:WaitForChild("UI"))
local UIFunctions = require(ClientRoot:WaitForChild("UI"):WaitForChild("UIFunctions"))
local ClientData = require(ClientRoot:WaitForChild("Plugins"):WaitForChild("ClientData"))
local Say = require(Utilities:WaitForChild("Say"))
local NPC = require(Utilities:WaitForChild("NPC"))
local CharacterFunctions = require(Utilities:WaitForChild("CharacterFunctions"))
local HologramSpawnEffect = require(Utilities:WaitForChild("HologramSpawnEffect"))
local MoveTo = require(Utilities:WaitForChild("MoveTo"))
local RelocationSignals = require(Utilities:WaitForChild("RelocationSignals"))
local MusicManager = require(Utilities:WaitForChild("MusicManager"))
local CameraManager = require(Utilities:WaitForChild("CameraManager"))

local CreatureModels = RSAssets:WaitForChild("CreatureModels")

local function tweenLookAt(fromPart: BasePart, toPart: BasePart)
	local targetPos = Vector3.new(toPart.Position.X, fromPart.Position.Y, toPart.Position.Z)
	local lookCFrame = CFrame.new(fromPart.Position, targetPos)
	TweenService:Create(fromPart, TweenInfo.new(0.5), { CFrame = lookCFrame }):Play()
end

return function(CurrentChunk: any, handle: any): boolean
	local Professor = CurrentChunk and CurrentChunk.Model and CurrentChunk.Model.NPCs and CurrentChunk.Model.NPCs:FindFirstChild("Professor")
	if not Professor then return false end

	local RivalCutsceneModel = CurrentChunk.Essentials.RivalCutscene
	RivalCutsceneModel.Parent = game.ReplicatedStorage --hide for now
	game:GetService("ContentProvider"):PreloadAsync({
		"87452715028649","73604893265362", --anims
		"108464076359191", "79384975011257", "73346527641539" --sfx
        })

	-- Suppress movement re-enabling from external systems for this cutscene
	pcall(function()
		Events.Request:InvokeServer({"SetCutsceneActive", true})
	end)
	CharacterFunctions:SetSuppressed(true)
	CharacterFunctions:CanMove(false)

	-- Greet and move near professor (stop short)
	Say:Say("Professor", true, {
		{ Text = "Ah, there you are!", Emotion = "Happy" },
		{ Text = "Right on time—come closer.", Emotion = "Neutral" },
	}, Professor)

	local player = PlayersService.LocalPlayer
	local character = player and player.Character or player.CharacterAdded:Wait()
	local hrp: BasePart? = character and character:FindFirstChild("HumanoidRootPart")
	local profHRP: BasePart? = Professor:FindFirstChild("HumanoidRootPart")
	if hrp and profHRP then
		local desiredDistance = -5
		-- Place player in front of the professor using professor's facing direction (XZ), keep player's Y
		local forward = profHRP.CFrame.LookVector
		local targetPos = Vector3.new(profHRP.Position.X, hrp.Position.Y, profHRP.Position.Z) - (forward * desiredDistance)
		-- Use shared MoveTo helper; it temporarily toggles controls, so reassert suppression after
		local _ = MoveTo.MoveToTarget(targetPos, { minWalkSpeed = 12, timeout = 2.5, preserveFacing = true, arriveRadius = 1.75, retryInterval = 0.4, delayAfter = 0.2 })
		-- Controls remain disabled for cutscene
		pcall(function()
			CharacterFunctions:SetSuppressed(true)
			CharacterFunctions:CanMove(false)
		end)
		-- Ensure both face each other
		tweenLookAt(hrp, profHRP)
		tweenLookAt(profHRP, hrp)
	end

	-- Name prompt
	Say:Say("Professor", true, {
		{ Text = "Big day, isn't it?", Emotion = "Happy" },
		{ Text = "Before we begin, what should I call you?", Emotion = "Talking" },
	}, Professor)
	local playerGui = player:WaitForChild("PlayerGui")
	local gameUI = playerGui:WaitForChild("GameUI")
	local inputName = gameUI:WaitForChild("InputName")
	inputName.Visible = true
	local nameConfirmed = false
	local playerName = ""
	local function onDone()
		local field = inputName.Input.InputField
		local nm = field.Text
		if nm and #nm > 0 and #nm <= 20 then
			playerName = nm
			nameConfirmed = true
			inputName.Visible = false
		else
			Say:Say("Professor", true, {
				{ Text = "That name doesn't seem right. Please try again.", Emotion = "Confused" },
			}, Professor)
		end
	end
	local function onNo()
		inputName.Visible = false
		Say:Say("Professor", true, {
			{ Text = "Please enter your name again.", Emotion = "Talking" },
		}, Professor)
		inputName.Visible = true
	end
	local doneConn = inputName.Done.MouseButton1Click:Connect(onDone)
	local noConn = inputName.No.MouseButton1Click:Connect(onNo)
	repeat task.wait(0.1) until nameConfirmed
	doneConn:Disconnect(); noConn:Disconnect()
	local filteredName = Events.Request:InvokeServer({"FilterName", playerName})
	Say:Say("Professor", true, {
		{ Text = "Ah, " .. filteredName .. ". A strong name.", Emotion = "Happy" },
		{ Text = "It suits a future Champion.", Emotion = "Smug" },
	}, Professor)
	Events.Request:InvokeServer({"UpdateNickname", filteredName})

	-- Primer for starters and shiny
	Say:Say("Professor", true, {
		{ Text = "Excellent. Now for the moment every trainer remembers.", Emotion = "Happy" },
	}, Professor)
	Say:Say("Professor", true, {
		{ Text = "I'll bring in three partners with the lab's holo-spawner—try to keep your jaw up.", Emotion = "Talking" },
	}, Professor)
	Say:Say("Professor", true, {
		{ Text = "Study their posture, their presence. Stats matter, but heart matters more.", Emotion = "Thinking" },
	}, Professor)
	Say:Say("Professor", true, {
		{ Text = "If one arrives shimmering… that's a rare Shiny. Consider yourself blessed.", Emotion = "Happy" },
	}, Professor)

	-- Request starters (server now returns Frigo Camelo, Kitung, Twirlina)
	local Starters = Events.Request:InvokeServer({"RequestStarters"})
	if not Starters then
		-- Lift suppression if we failed to get starters to avoid soft-lock
		pcall(function()
			CharacterFunctions:SetSuppressed(false)
			CharacterFunctions:CanMove(true)
		end)
		return false
	end

	local function spawnStarter(starterData, spawnName)
		local spawnFolder = CurrentChunk.Model:FindFirstChild(spawnName)
		if not spawnFolder or not spawnFolder:FindFirstChild("Root") then return nil end
		local lookAtPart = spawnFolder.Root
		if hrp then tweenLookAt(hrp, lookAtPart) end
		if profHRP then tweenLookAt(profHRP, lookAtPart) end
		local model = CreatureModels:WaitForChild(starterData.Name):Clone()
		model.Parent = CurrentChunk.Model
		model.PrimaryPart.Anchored = false
		model:SetPrimaryPartCFrame(spawnFolder:FindFirstChild("Spawn").CFrame)
		for _, d in ipairs(model:GetDescendants()) do
			if (d:IsA("BasePart") or d:IsA("MeshPart")) and d.Name ~= "HumanoidRootPart" then
				d.Transparency = 1
			end
		end
		local pivot = model:GetPivot()
		HologramSpawnEffect:CreateForModel(model, pivot.Position, {
			onPeak = function()
				if starterData.Shiny then
					local Creatures = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Creatures"))
					local species = Creatures and Creatures[starterData.Name]
					local shinyColors = species and species.ShinyColors
					if shinyColors then
						for _, d in ipairs(model:GetDescendants()) do
							if d:IsA("BasePart") or d:IsA("MeshPart") then
								local c = shinyColors[d.Name]
								if c then pcall(function() d.Color = c end) end
							end
						end
					end
					local status = model:WaitForChild("HumanoidRootPart"):WaitForChild("Status")
					if status and status.CreatureInfo and status.CreatureInfo.Shiny then
						status.CreatureInfo.Shiny.Visible = true
					end
				end
				for _, d in ipairs(model:GetDescendants()) do
					if (d:IsA("BasePart") or d:IsA("MeshPart")) and d.Name ~= "HumanoidRootPart" then
						d.Transparency = 0
					end
				end
				local hum = model:WaitForChild("Humanoid")
				local anims = model:WaitForChild("Animations")
				local idle = hum:LoadAnimation(anims:WaitForChild("Idle"))
				idle:Play()
			end
		})
		task.delay(0.5, function()
			pcall(function()
				local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
				if root and root:IsA("BasePart") then
					root.Anchored = true
				end
			end)
		end)
		return model
	end

	-- Present each starter with short descriptions
	local data = ClientData:Get()
	local nickname = (data and data.Nickname) or "Trainer"
	spawnStarter(Starters[1], "Starter1Spawn")
	Say:Say("Professor", true, {
		{ Text = "Frigo Camelo—steady and dependable.", Emotion = "Neutral" },
		{ Text = "Ground type. Tough and reliable.", Emotion = "Talking" },
	}, Professor)
	spawnStarter(Starters[2], "Starter2Spawn")
	Say:Say("Professor", true, {
		{ Text = "Kitung—focused and brave.", Emotion = "Smug" },
		{ Text = "Fighting type. Quick strikes, clean wins.", Emotion = "Talking" },
	}, Professor)
	spawnStarter(Starters[3], "Starter3Spawn")
	Say:Say("Professor", true, {
		{ Text = "Twirlina—playful and clever.", Emotion = "Happy" },
		{ Text = "Fairy type. Tricks and charm.", Emotion = "Talking" },
	}, Professor)
	Say:Say("Professor", true, {
		{ Text = "Alright, " .. nickname .. ", your choice.", Emotion = "Neutral" },
		{ Text = "Walk up to the one you want and confirm.", Emotion = "Neutral" },
		{ Text = "You can't go wrong—pick the partner you like most.", Emotion = "Happy" },
	}, Professor)

	CharacterFunctions:SetSuppressed(false)
	CharacterFunctions:CanMove(true)

	-- Click-to-confirm handlers (reuse NPC:Setup on models under chunk)
	local function wireSelectionFor(name)
		local m = CurrentChunk.Model:FindFirstChild(name)
		if not m then return end
		local done = false
		NPC:Setup(m, function()
			if done then return end
			UI.TopBar:Hide()
			Say:Say(name, true, {
				{ Text = name .. " tilts its head.", Emotion = "Confused" },
			}, m)
			Say:Say("Professor", false, {
				{ Text = "So—" .. name .. ".", Emotion = "Talking" },
				{ Text = "Are you certain this is the bond you want, " .. nickname .. "?", Emotion = "Thinking" },
			}, Professor)
			local choice = Say:YieldChoice()
			Say:Exit()
				if choice == true then
					Say:Say("Professor", false, {
						{ Text = "Splendid—" .. name .. " it is.", Emotion = "Happy" },
						{ Text = "Treat them well and they'll move mountains for you, " .. nickname .. ".", Emotion = "Happy" },
					}, Professor)
				task.wait(1.2)
				Say:Exit()
				local okPick = Events.Request:InvokeServer({"PickStarter", name})
				if okPick then
					done = true
					-- Update client cache
					task.wait(0.1)
					local updated = Events.Request:InvokeServer({"DataGet"})
					if updated then pcall(function() ClientData:ServerForceUpdateData(updated) end) end
					-- Cleanup all starter creatures
					for _, child in ipairs(CurrentChunk.Model:GetChildren()) do
						if child.Name == "Frigo Camelo" or child.Name == "Kitung" or child.Name == "Twirlina" then
							pcall(function()
								HologramSpawnEffect:CreateFadeOut(child, function()
									-- no-op onComplete
								end, function()
									if child and child.Parent then
										child:Destroy()
									end
								end)
							end)
						end
					end
					Say:Say("Professor", true, {
						{ Text = "Very well! Now that you have your partner it's time to start your journey!.", Emotion = "Talking" },
					}, Professor)

					Say:Say("???", true, {
						{ Text = "...", Emotion = "Happy" },
					})

					Say:Say("Professor", true, {
						{ Text = "What was that?.", Emotion = "Talking" },
					}, Professor)

					CharacterFunctions:CanMove(false)
					CharacterFunctions:SetSuppressed(true)


					pcall(function()
						local hum = Professor:FindFirstChildOfClass("Humanoid")
						local ac = Professor:FindFirstChildOfClass("AnimationController")
						local animator = (hum and hum:FindFirstChildOfClass("Animator")) or (ac and ac:FindFirstChildOfClass("Animator"))
						if animator then
							for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
								tr:Stop(0.1)
							end
						end
			
					end)

					Professor:WaitForChild("HumanoidRootPart").CFrame = RivalCutsceneModel.ProfessorCF.CFrame
					RivalCutsceneModel.Parent = CurrentChunk.Essentials

					hrp.CFrame = RivalCutsceneModel.PlayerCF.CFrame

					-- Rival cutscene animations and camera control
					local function safeGetAnimator(container: Instance): Animator?
						if not container then return nil end
						local animator = container:FindFirstChildOfClass("Animator")
						if animator and animator:IsA("Animator") then return animator end
						local humanoid = container:FindFirstChildOfClass("Humanoid")
						if humanoid then
							local a = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
							a.Parent = humanoid
							return a
						end
						local ac = container:FindFirstChildOfClass("AnimationController")
						if ac then
							local a = ac:FindFirstChildOfClass("Animator") or Instance.new("Animator")
							a.Parent = ac
							return a
						end
						return nil
					end

					local function loadTrack(animator: Animator?, assetId: string): AnimationTrack?
						if not animator then return nil end
						local anim = Instance.new("Animation")
						anim.AnimationId = "rbxassetid://" .. assetId
						local ok, track = pcall(function()
							return animator:LoadAnimation(anim)
						end)
						if ok and track then return track end
						return nil
					end

					local rivalModel = RivalCutsceneModel
					local kyroContainer: Instance? = rivalModel:FindFirstChild("Kyro")
					local rig: Instance? = rivalModel:FindFirstChild("CameraRig")
					local camPos: BasePart? = rig and rig:FindFirstChild("CameraPosition")
					print("[RivalCutscene] Setup: kyroContainer=", kyroContainer, " rig=", rig, " camPos=", camPos)

					-- Resolve desired FOV from model values/attributes
					local function readFovFrom(model: Instance?, rigInst: Instance?): number?
						local function coerce(v: any): number?
							if typeof(v) == "number" then return v end
							if typeof(v) == "string" then
								local n = tonumber(v)
								return n
							end
							return nil
						end
						if not model then return nil end
						local fov: number? = nil
						local child = model:FindFirstChild("FOV")
						if child then
							if child:IsA("NumberValue") then fov = child.Value end
							if not fov and child:IsA("StringValue") then fov = tonumber(child.Value) end
							-- Support FOV as Folder of NumberValues
							if not fov and child:IsA("Folder") then
								local preferred = {"Value","Default","Camera","CameraFOV"}
								local pickedName: string? = nil
								for _, name in ipairs(preferred) do
									local nv = child:FindFirstChild(name)
									if nv and nv:IsA("NumberValue") then
										fov = nv.Value
										pickedName = name
										break
									end
								end
								if not fov then
									for _, nv in ipairs(child:GetChildren()) do
										if nv:IsA("NumberValue") then
											fov = nv.Value
											pickedName = nv.Name
											break
										end
									end
								end
								print("[RivalCutscene] FOV folder detected; using key:", pickedName, " value:", fov)
							end
						end
						if not fov then
							fov = coerce(model:GetAttribute("FOV"))
						end
						if not fov and rigInst then
							local rchild = rigInst:FindFirstChild("FOV")
							if rchild then
								if rchild:IsA("NumberValue") then fov = rchild.Value end
								if not fov and rchild:IsA("StringValue") then fov = tonumber(rchild.Value) end
								-- Folder on rig as well
								if not fov and rchild:IsA("Folder") then
									local preferred = {"Value","Default","Camera","CameraFOV"}
									local pickedName: string? = nil
									for _, name in ipairs(preferred) do
										local nv = rchild:FindFirstChild(name)
										if nv and nv:IsA("NumberValue") then
											fov = nv.Value
											pickedName = name
											break
										end
									end
									if not fov then
										for _, nv in ipairs(rchild:GetChildren()) do
											if nv:IsA("NumberValue") then
												fov = nv.Value
												pickedName = nv.Name
												break
											end
										end
									end
									print("[RivalCutscene] Rig FOV folder detected; using key:", pickedName, " value:", fov)
								end
							end
							if not fov then
								fov = coerce(rigInst:GetAttribute("FOV"))
							end
						end
						return fov
					end
					local desiredFov: number? = readFovFrom(rivalModel, rig)
					print("[RivalCutscene] desiredFov=", desiredFov)

					-- Optional per-frame FOV driver (Folder of NumberValues). Prefer Rig.FOV → RivalCutscene.FOV → workspace.FOV
					local fovFolder: Folder? = nil
					local fovFrames: {number}? = nil
					local fovFps: number = 60
					pcall(function()
						local candidate = (rig and rig:FindFirstChild("FOV"))
						if candidate and candidate:IsA("Folder") then fovFolder = candidate return end
						local fromModel = rivalModel and rivalModel:FindFirstChild("FOV")
						if fromModel and fromModel:IsA("Folder") then fovFolder = fromModel return end
						local fromWorkspace = workspace:FindFirstChild("FOV")
						if fromWorkspace and fromWorkspace:IsA("Folder") then fovFolder = fromWorkspace return end
					end)
					if fovFolder then
						print("[RivalCutscene] FOV folder detected at:", fovFolder:GetFullName())
						-- Optional FPS hint: read from child named "FPS" or attribute "FPS"
						pcall(function()
							local fpsChild = fovFolder:FindFirstChild("FPS")
							if fpsChild and fpsChild:IsA("NumberValue") then
								fovFps = math.max(1, math.floor(fpsChild.Value))
							elseif fovFolder:GetAttribute("FPS") then
								local v = tonumber(fovFolder:GetAttribute("FPS"))
								if v and v > 0 then fovFps = math.floor(v) end
							end
						end)
						local numbered: { { idx: number, val: number } } = {}
						for _, child in ipairs(fovFolder:GetChildren()) do
							if child:IsA("NumberValue") then
								local n = tonumber(child.Name)
								if n ~= nil then
									table.insert(numbered, { idx = n, val = child.Value })
								end
							end
						end
						if #numbered > 0 then
							table.sort(numbered, function(a, b) return a.idx < b.idx end)
							fovFrames = {}
							for i = 1, #numbered do
								fovFrames[i] = numbered[i].val
							end
							print("[RivalCutscene] Loaded", #fovFrames, "FOV frames (numeric order)")
						else
							local temp: {number} = {}
							for _, child in ipairs(fovFolder:GetChildren()) do
								if child:IsA("NumberValue") then table.insert(temp, child.Value) end
							end
							if #temp > 0 then
								fovFrames = temp
								print("[RivalCutscene] Loaded", #fovFrames, "FOV frames (unordered)")
							end
						end
					end

					-- Explicit animator resolution per spec:
					-- 1) Camera: use CameraRig.AnimationController
					local rigAC = rig and rig:FindFirstChildOfClass("AnimationController")
					local acAnimator: Animator? = nil
					if rigAC then
						acAnimator = rigAC:FindFirstChildOfClass("Animator") or Instance.new("Animator")
						if acAnimator.Parent == nil then acAnimator.Parent = rigAC end
					end
					-- 2) Kyro: use Kyro.Humanoid
					local kyroHum = kyroContainer and kyroContainer:FindFirstChildOfClass("Humanoid")
					local kyroAnimator: Animator? = nil
					if kyroHum then
						kyroAnimator = kyroHum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
						if kyroAnimator.Parent == nil then kyroAnimator.Parent = kyroHum end
					end
					print("[RivalCutscene] Animators: rigAC=", rigAC, " acAnimator=", acAnimator, " kyroHum=", kyroHum, " kyroAnimator=", kyroAnimator)

					local acTrack = loadTrack(acAnimator, "73604893265362")
					local kyroTrack = loadTrack(kyroAnimator, "87452715028649")
					print("[RivalCutscene] Tracks loaded: ac=", acTrack, " kyro=", kyroTrack)

					local cameraConn: RBXScriptConnection? = nil
					local cameraRunning = false
					local oldFov: number? = nil
					local fovFrameIndex: number = 1
					local fovTimeAccumulator: number = 0
					local lastPrintIndex: number = 0
					local currentFov: number? = nil
					local FOV_SMOOTHNESS = 12 -- higher = faster response, without TweenService
					local function startCameraFollow()
						if not camPos or not camPos:IsA("BasePart") then return end
						local cam = workspace.CurrentCamera
						if not cam then return end
						cam.CameraType = Enum.CameraType.Scriptable
						oldFov = cam.FieldOfView
						if fovFrames and #fovFrames > 0 then
							currentFov = fovFrames[1]
							cam.FieldOfView = currentFov
							print("[RivalCutscene] Applied FOV (frame 1):", currentFov, " (old=", oldFov, ")")
						else
							currentFov = (type(desiredFov) == "number" and desiredFov) or oldFov
							cam.FieldOfView = currentFov
							print("[RivalCutscene] Applied FOV:", currentFov, " (old=", oldFov, ")")
						end
						cameraRunning = true
						cam.CFrame = camPos.CFrame
						cameraConn = RunService.RenderStepped:Connect(function(dt)
							if cameraRunning and camPos and camPos.Parent then
								cam.CFrame = camPos.CFrame
							-- Drive FOV per frame from collected frames (time-based index advance)
							if fovFrames and #fovFrames > 0 then
								fovTimeAccumulator += (dt or 0)
								local frameInterval = 1 / math.max(1, fovFps)
								if fovTimeAccumulator >= frameInterval then
									local steps = math.floor(fovTimeAccumulator / frameInterval)
									fovTimeAccumulator -= steps * frameInterval
									fovFrameIndex = math.min(fovFrameIndex + steps, #fovFrames)
								end
								local target = fovFrames[fovFrameIndex] or currentFov or cam.FieldOfView
								if fovFrameIndex ~= lastPrintIndex and (fovFrameIndex % 30 == 0) then
									print("[RivalCutscene][FOV] frame=", fovFrameIndex, " value=", target)
									lastPrintIndex = fovFrameIndex
								end
								local alpha = math.clamp((dt or 0) * FOV_SMOOTHNESS, 0, 1)
								currentFov = (currentFov or target) + (target - (currentFov or target)) * alpha
								cam.FieldOfView = currentFov
							end
								-- If no wsFovFolder, but desiredFov is set, smoothly approach it too
							if (not fovFrames or #fovFrames == 0) and type(desiredFov) == "number" then
									local alpha = math.clamp((dt or 0) * FOV_SMOOTHNESS, 0, 1)
									currentFov = (currentFov or desiredFov) + (desiredFov - (currentFov or desiredFov)) * alpha
									cam.FieldOfView = currentFov
								end
							end
						end)
					end

					local function stopCameraFollow()
						cameraRunning = false
						if cameraConn then cameraConn:Disconnect() cameraConn = nil end
						local cam = workspace.CurrentCamera
						if cam then
							if oldFov then
								cam.FieldOfView = oldFov
								print("[RivalCutscene] Restored FOV:", oldFov)
								oldFov = nil
							end
							cam.CameraType = Enum.CameraType.Custom
						end
					end

					-- Synchronization primitives to yield until finished
					local finishedEvent = Instance.new("BindableEvent")
					local finished = false
					local function finishOnce()
						if finished then return end
						finished = true
						finishedEvent:Fire()
					end

					-- Helper to fetch time length safely
					local function getLength(track: AnimationTrack?): number
						if not track then return 0 end
						local ok, len = pcall(function()
							return track:GetTimeLength()
						end)
						if ok and type(len) == "number" and len > 0 then return len end
						return track.Length or 0
					end
					print("[RivalCutscene] Lengths: ac=", getLength(acTrack), " kyro=", getLength(kyroTrack))

					-- Hook Kyro animation markers / keyframes
					if kyroTrack then
						local function onMarker(name: string)
							if name == "Jump" or name == "Land" or name == "End" then
								print("[RivalCutscene][Kyro] Marker:", name)
								if name == "Jump" then
									local sfx = Instance.new("Sound")
									sfx.SoundId = "rbxassetid://79384975011257"	sfx.Parent = workspace
									sfx:Play(); game.Debris:AddItem(sfx, 1)
									task.delay(0.25, function()
										local sfx = Instance.new("Sound")
										sfx.SoundId = "rbxassetid://108464076359191"	sfx.Parent = workspace
										sfx:Play(); game.Debris:AddItem(sfx, 1)
									end)
								end	
								if name == "Land" then
									local sfx = Instance.new("Sound")
									sfx.SoundId = "rbxassetid://79384975011257"	sfx.Parent = workspace
									sfx:Play(); game.Debris:AddItem(sfx, 1)
								end
								if name == "End" then
									task.wait(0.25)
									UIFunctions:Transition(true)
									task.wait(1)
									stopCameraFollow()
									-- Ensure both tracks are stopped
									pcall(function() if acTrack and acTrack.IsPlaying then acTrack:Stop(0) end end)
									pcall(function() if kyroTrack and kyroTrack.IsPlaying then kyroTrack:Stop(0) end end)
									finishOnce()
								end
							end
						end
						-- Prefer marker signals if present
						pcall(function()
							kyroTrack:GetMarkerReachedSignal("Jump"):Connect(function() onMarker("Jump") end)
							kyroTrack:GetMarkerReachedSignal("Land"):Connect(function() onMarker("Land") end)
							kyroTrack:GetMarkerReachedSignal("End"):Connect(function() onMarker("End") end)
						end)
						-- Fallback: keyframe names
						kyroTrack.KeyframeReached:Connect(function(name)
							onMarker(name)
						end)
					end

					-- Play both animations simultaneously (with guards)
					if acTrack and kyroTrack then
						print("[RivalCutscene] Playing tracks now")
						acTrack:Play(0)
						kyroTrack:Play(0)
						-- Defer camera CFrame until animation is actually advancing (TimePosition > 0)
						task.spawn(function()
							for _ = 1, 120 do -- ~2 seconds max wait
								local rigStarted = (acTrack and acTrack.IsPlaying and (acTrack.TimePosition or 0) > 0) or false
								local kyroStarted = (kyroTrack and kyroTrack.IsPlaying and (kyroTrack.TimePosition or 0) > 0) or false
								if rigStarted or kyroStarted then

									local pg = game.Players.LocalPlayer and game.Players.LocalPlayer:FindFirstChild("PlayerGui")
									local gameUI = pg and pg:FindFirstChild("GameUI")
									local blackBars = gameUI and gameUI:FindFirstChild("BlackBars")
									if blackBars and blackBars:IsA("ImageLabel") then
										UIFunctions:BlackBars(true, blackBars)
									end

									startCameraFollow()
									break
								end
								task.wait(0.016)
							end
						end)
						-- Watch for explicit stops
						acTrack.Stopped:Connect(function()
							print("[RivalCutscene] acTrack.Stopped")
						end)
						kyroTrack.Stopped:Connect(function()
							print("[RivalCutscene] kyroTrack.Stopped")
							finishOnce()
						end)
						-- Safety: ensure cleanup even if markers don't fire
						task.delay(math.max(getLength(kyroTrack), getLength(acTrack), 8), function()
							print("[RivalCutscene] Timeout fallback reached; stopping camera follow")
							stopCameraFollow()
							finishOnce()
						end)
					else
						-- If one is missing, try to still run camera briefly and then restore
						print("[RivalCutscene] Missing track(s); starting brief camera follow only")
						startCameraFollow()
						task.delay(4, function()
							stopCameraFollow()
							finishOnce()
						end)
					end

					-- Yield here until cutscene has finished
					print("[RivalCutscene] Waiting for cutscene to finish...")
					finishedEvent.Event:Wait()
					print("[RivalCutscene] Cutscene finished")

					rig:Destroy()
					--continuing from here later im taking a break
					kyroContainer:WaitForChild("HumanoidRootPart").CFrame = CurrentChunk.Essentials.RivalCutscene.KyroCF.CFrame
					Professor:WaitForChild("HumanoidRootPart").CFrame = CurrentChunk.Essentials.RivalCutscene.ProfessorCF.CFrame
					hrp.CFrame = CurrentChunk.Essentials.RivalCutscene.PlayerCF.CFrame

					task.wait(1)

					local pg = game.Players.LocalPlayer and game.Players.LocalPlayer:FindFirstChild("PlayerGui")
					local gameUI = pg and pg:FindFirstChild("GameUI")
					local blackBars = gameUI and gameUI:FindFirstChild("BlackBars")
					if blackBars and blackBars:IsA("ImageLabel") then
						UIFunctions:BlackBars(false, blackBars)
					end
					
					UIFunctions:Transition(false)

					-- Rival introduction sequence (sharper tone, Pokémon-like)
					-- Professor first addresses Kyro, then the player separately for proper facing
					Say:Say("Professor", true, {
						{ Text = "Kyro.. this is a lab, not a stage...", Emotions = { Talker = "Confused", Hearer = "Neutral" } },
					}, Professor, kyroContainer)
					
					Say:Say("Kyro", true, {
						{ Text = "Cmon! Have some fun.", Emotions = { Talker = "Smug", Hearer = "Neutral" } },
						{ Text = "I'm just trying to make stuff interesting.", Emotions = { Talker = "Smug", Hearer = "Neutral" } },
					}, kyroContainer, Professor)
					
					Say:Say("Professor", true, {
						{ Text = "Anyways...", Emotions = { Talker = "Happy" } },
						{ Text = tostring(nickname) .. ", this is Kyro.", Emotions = { Talker = "Happy" } },
						{ Text = "I asked him to drop by so you could start at the same time. You guys can push each other to grow.", Emotions = { Talker = "Talking" } },
					}, Professor, character)

					-- Kyro declares rivalry, already ahead
					Say:Say("Kyro", true, {
						{ Text = "Sup!!! I'm Kyro, nice to meet ya!", Emotions = { Talker = "Smug", Hearer = "Neutral" } },
						{ Text = "Me and my partner ready to go!", Emotions = { Talker = "Smug", Hearer = "Neutral" } },
					}, kyroContainer, Professor)

					-- Professor frames rules and purpose (address Kyro)
					Say:Say("Professor", true, {
						{ Text = tostring(nickname) .. " here just got their partner actually.", Emotions = { Talker = "Talking", Hearer = "Neutral" } },
						{ Text = "Why don't you guys battle and see what they can do?.", Emotions = { Talker = "Happy", Hearer = "Neutral" } },
					}, Professor, kyroContainer)

					-- Kyro stakes a concrete challenge
					Say:Say("Kyro", true, {
						{ Text = "YES! Get ready " .. tostring(nickname) .. ", I'm not holding back!", Emotions = { Talker = "Smug", Hearer = "Neutral" } },
					}, kyroContainer, character)

					-- Optional immediate rival battle (NPC-style: dialogue + model in battle)
					local pdBattle = nil
					pcall(function() pdBattle = ClientData:Get() end)
					-- Prepare Kyro model so the trainer intro uses his model
					pcall(function()
						local TrainerIntroController = require(Utilities:WaitForChild("TrainerIntroController"))
						TrainerIntroController:PrepareFromNPC(kyroContainer)
					end)
					-- Build Kyro's dialogue (used for defeat and overworld follow-ups)
					local trainerDialogue = {
						Name = kyroContainer.Name,
						CustomAnimation = false,
						Emotion = "Bored",
						LineOfSight = false,
						TrainerId = "Rival_Kyro_Intro",
						TrainerName = kyroContainer.Name,
						Say = {
							{ Text = "James just beat me in a battle.", Emotion = "Bored" },
							{ Text = "Hey! You beat him? Let's battle!", Emotion = "Thinking" },
						},
						AfterSayInBattle = {
							{ Text = "I really thought I had this one!...", Emotion = "Shy" },
						},
						AfterSayOverworld = {
							{ Text = "I'll get better... I know it!", Emotion = "Shy" },
						},
					}
					local trainerSpec = {
						{ Name = "Abrazard", Level = 5, 
						Gender = "0", 
						IVs = {HP = 15, Attack = 28, Defense = 12, Speed = 19},
						Nature = "Calm" },
					}
					-- Start the trainer battle with dialogue included
					pcall(function()
						-- One-shot override trainer BGM for Kyro battle
						pcall(function()
							MusicManager:SetTrainerBattleTrackOverride("VSKyro_ProfessorLab")
						end)
						Events.Request:InvokeServer({"StartBattle", "Trainer", {
							TrainerName = trainerDialogue.TrainerName,
							TrainerSpec = trainerSpec,
							TrainerId = trainerDialogue.TrainerId,
							TrainerDialogue = trainerDialogue,
						}})
					end)

					-- Post-battle dialogue (deferred until after relocation back to overworld)
					do
						local conn
						conn = Events.Communicate.OnClientEvent:Connect(function(eventType, data)
							if eventType ~= "BattleOver" then return end
							if conn then conn:Disconnect() end
							local rc
							rc = RelocationSignals.OnPostBattleRelocated(function(ctx)
								if rc then rc:Disconnect() end
								local reason = (type(data) == "table" and data.Reason) or nil
								if reason == "Win" then
									Say:Say("Kyro", true, {
										{ Text = "You're a great trainer already!", Emotions = { Talker = "Smug", Hearer = "Neutral" } },
									}, kyroContainer, character)
								else
									Say:Say("Kyro", true, {
										{ Text = "You'll get me next time!", Emotions = { Talker = "Smug", Hearer = "Neutral" } },
									}, kyroContainer, character)
								end
								-- Heal party in lab after battle (as per Professor line)
								pcall(function()
									Events.Request:InvokeServer({"HealParty"})
								end)

														
								local kyroHRP: BasePart? = kyroContainer:FindFirstChild("HumanoidRootPart")
								local kyroHum: Humanoid? = kyroContainer:FindFirstChildOfClass("Humanoid")
								if kyroHRP  then
									kyroHRP.Anchored = false
								end

								Say:Say("Professor", true, {
									{ Text = "That was amazing! You guys did great.", Emotions = { Talker = "Talking", Hearer = "Neutral" } },
									{ Text = "Here. I'll heal you up.", Emotions = { Talker = "Happy", Hearer = "Neutral" } },
								}, Professor, kyroContainer)
								Say:Say("Professor", true, {
									{ Text = "Well then! Here is where your adventure begins!", Emotions = { Talker = "Talking", Hearer = "Neutral" } },
									{ Text = "Your adventure to become a champion starts now!", Emotions = { Talker = "Happy", Hearer = "Neutral" } },
									{ Text = "This is so exciting!", Emotions = { Talker = "Happy", Hearer = "Neutral" } },
								}, Professor, kyroContainer)
								Say:Say("Kyro", true, {
									{ Text = "It's me VS. You now! A race to the top!", Emotions = { Talker = "Smug", Hearer = "Neutral" } },
									{ Text = "OOOH! I CANT WAIT! Catcha later!", Emotions = { Talker = "Smug", Hearer = "Bored" } },
								}, kyroContainer, character)

								local target = CurrentChunk.Model.Doors:WaitForChild("Door").Part
								tweenLookAt(hrp, target)


							if kyroHRP and kyroHum then
								local target = CurrentChunk.Model.Doors:WaitForChild("Door").Part.Position 
								local kyroAnimator: Animator? = kyroHum:FindFirstChildOfClass("Animator")
								if not kyroAnimator then kyroAnimator = Instance.new("Animator"); kyroAnimator.Parent = kyroHum end
								local runTrack: AnimationTrack? = nil
								MoveTo.MoveHumanoidToTarget(kyroHum, kyroHRP, target, {
									minWalkSpeed = 12,
									timeout = 1.5,
									delayAfter = 0.5,
									onStart = function()
										if kyroAnimator and runTrack == nil then
											local anim = Instance.new("Animation"); anim.AnimationId = "rbxassetid://120866625087275"
											local ok, track = pcall(function() return kyroAnimator:LoadAnimation(anim) end)
											if ok and track then
												runTrack = track
												runTrack.Priority = Enum.AnimationPriority.Movement
												runTrack.Looped = true
												pcall(function() runTrack:Play(0.1) end)
											end
										end
									end,
									onComplete = function()
										if runTrack then pcall(function() runTrack:Stop(0.15) end) end
									end,
								})
							end

							local camManager = CameraManager.new()
							local phrpSide: BasePart? = character and character:FindFirstChild("HumanoidRootPart")
							local profHRPSide: BasePart? = Professor and Professor:FindFirstChild("HumanoidRootPart")
							if phrpSide and profHRPSide then
								local centerPos = (phrpSide.Position + profHRPSide.Position) / 2
								-- Calculate perpendicular direction for side view
								local toPlayer = phrpSide.Position - profHRPSide.Position
								local perpDir = Vector3.new(0, 1, 0):Cross(toPlayer).Unit
								if perpDir.Magnitude < 0.1 then
									perpDir = Vector3.new(0, 0, 1) -- Fallback to Z-axis
								end
								
								-- Position camera to the side at a good distance (2 studs further back like Kyro scene)
								local cameraOffset = -perpDir * 10 + Vector3.new(0, 2, 0)
								local cameraPos = centerPos + cameraOffset
								local cameraCFrame = CFrame.lookAt(cameraPos, centerPos)
								
								camManager:TransitionTo(cameraCFrame, 1, 65, nil)
							end

								Say:Say("Professor", true, {
									{ Text = "Kyro!", Emotions = { Talker = "Talking", Hearer = "Neutral" } },
									{ Text = "He's in such a rush! He's gone already?", Emotions = { Talker = "Happy", Hearer = "Neutral" } },
									{ Text = "Not much we can do now I guess...", Emotions = { Talker = "Happy", Hearer = "Neutral" } },
									{ Text = "It's time for you to get started!", Emotions = { Talker = "Happy", Hearer = "Neutral" } },
								})

					

							workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
							do
								local hrp: BasePart? = character:FindFirstChild("HumanoidRootPart")
								local head: BasePart? = character:FindFirstChild("Head")
								if hrp then
									local camPos = hrp.Position - (hrp.CFrame.LookVector * -10) + (hrp.CFrame.UpVector * 2.5)
									local lookAt = (head and head.Position) or hrp.Position
									workspace.CurrentCamera.CFrame = CFrame.new(camPos, lookAt)
								end
							end

								Say:Say("Professor", false, {
									{ Text = nickname.."! YOUR NEXT CHAMPION!", Emotions = { Talker = "Talking", Hearer = "Smug" } },
								})

								task.wait(1.5)
								
								Say:Exit()
								
								local PlayerGui = game.Players.LocalPlayer.PlayerGui
								local GameUI = PlayerGui:FindFirstChild("GameUI")
								local CircleTransition = GameUI and GameUI:FindFirstChild("CircularTransition")
								if CircleTransition then
									UIFunctions:CircularTransition(CircleTransition, true)
								end

								task.wait(0.1)
								CharacterFunctions:SetSuppressed(false)
								task.wait(2)

								UI.TopBar:SetSuppressed(true) 

								local ChunkLoader = require(Utilities:WaitForChild("ChunkLoader"))
								local loaded, chunkData = ChunkLoader:ClientRequestChunk("PlayersHouse")
								if loaded and chunkData and chunkData.Essentials then
									local afterPart = chunkData.Essentials:FindFirstChild("AfterProfessorLab")
									task.wait(0.5)
									local character2 = player.Character or player.CharacterAdded:Wait()
									local hrp2: BasePart? = character2 and character2:FindFirstChild("HumanoidRootPart")
									local head2: BasePart? = character2 and character2:FindFirstChild("Head")
									if hrp2 and afterPart and afterPart:IsA("BasePart") then
										(hrp2 :: BasePart).CFrame = (afterPart :: BasePart).CFrame
										local camPos = hrp2.Position - (hrp2.CFrame.LookVector * -7) + (hrp2.CFrame.UpVector * 1.5)
										local lookAt = (head2 and head2.Position) or hrp2.Position
										workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
										workspace.CurrentCamera.CFrame = CFrame.new(camPos, lookAt)
									end
					

									task.wait(0.5)
									Say:Say("Me", true, {
										{ Text = nickname.."! YOUR NEXT CHAMPION!", Emotions = { Talker = "Talking", Hearer = "Smug" } },
									})
									workspace.CurrentCamera.CFrame = workspace.CurrentCamera.CFrame * CFrame.Angles(0, math.rad(-90), 0)
									workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
									workspace.CurrentCamera.FieldOfView = 70
									Say:Say("Mom", true, {
										{ Text = "The professor said that?", Emotions = { Talker = "Smug", Hearer = "Happy" } },
										{ Text = "He must believe in you! Not as much as I do, but still!", Emotions = { Talker = "Smug", Hearer = "Happy" } },
									},chunkData.Model.NPCs.Mom)

									Say:Say("Me", true, {
										{ Text = "Mom I've been waiting for this!", Emotions = { Talker = "Talking", Hearer = "Smug" } },
										{ Text = "It's finally time to start my journey!", Emotions = { Talker = "Talking", Hearer = "Smug" } },
									})

									Say:Say("Mom", true, {
										{ Text = "Not so fast!", Emotions = { Talker = "Smug", Hearer = "Happy" } },
										{ Text = "I can't expect you to go out there with no gear!", Emotions = { Talker = "Smug", Hearer = "Happy" } },
										{ Text = "Here, take these.", Emotions = { Talker = "Smug", Hearer = "Happy" } },
									},chunkData.Model.NPCs.Mom)

									Say:Say("", true, {
						{ Text = nickname.." obtained 500 Capture Cubes!", Emotions = { Talker = "Smug", Hearer = "Happy" } },
									},chunkData.Model.NPCs.Mom)

					-- Mark tutorial completion to trigger server-side item grant
					pcall(function()
						local Events = game:GetService("ReplicatedStorage"):WaitForChild("Events")
						if Events and Events.Request then
							Events.Request:InvokeServer({"SetEvent", "FINISHED_TUTORIAL", true})
						end
					end)

									Say:Say("Mom", true, {
										{ Text = "Capture Cubes!", Emotions = { Talker = "Smug", Hearer = "Happy" } },
										{ Text = "It's how you capture creatures silly!", Emotions = { Talker = "Smug", Hearer = "Happy" } },
										{ Text = "When you encounter a creature, just use one from your bag.", Emotions = { Talker = "Smug", Hearer = "Happy" } },
										{ Text = "Now then! You best be off. Wouldn't want to keep Kyro waiting now would we?", Emotions = { Talker = "Smug", Hearer = "Happy" } },
									},chunkData.Model.NPCs.Mom)

									Say:Say("Me", true, {
										{ Text = "THIS IS GONNA BE AWESOME!", Emotions = { Talker = "Talking", Hearer = "Smug" } },
										{ Text = "Thanks Mom!", Emotions = { Talker = "Talking", Hearer = "Smug" } },
										{ Text = "Although, I don't really know where he went...", Emotions = { Talker = "Talking", Hearer = "Smug" } },
									})
									
									local firstCreatureName = "your partner"
									pcall(function()
										local pd = ClientData:Get()
										local first = pd and pd.Party and pd.Party[1]
										if first then
											local nm = (first.Nickname and first.Nickname ~= "" and first.Nickname) or first.Name
											if type(nm) == "string" and #nm > 0 then firstCreatureName = nm end
										end
									end)
									Say:Say("Mom", true, {
										{ Text = "Head to Route 1, Just exit the house and follow the signs!", Emotions = { Talker = "Smug", Hearer = "Happy" } },
										{ Text = "I'll see you later, good luck out there!", Emotions = { Talker = "Smug", Hearer = "Happy" } },
										{ Text = "Let's see what you and " .. tostring(firstCreatureName) .. " can do!", Emotions = { Talker = "Smug", Hearer = "Happy" } },
									},chunkData.Model.NPCs.Mom)
								end
			

								UI.TopBar:SetSuppressed(false) 
								UI.TopBar:Show()
								CharacterFunctions:SetSuppressed(false)
								CharacterFunctions:CanMove(true)
								pcall(function()
									Events.Request:InvokeServer({"SetCutsceneActive", false})

									task.delay(0.3, function()
										local c = player.Character or player.CharacterAdded:Wait()
										local hum: BasePart? = c and c:FindFirstChild("Humanoid")
										for _, track in ipairs(hum.Animator:GetPlayingAnimationTracks()) do
											track:Stop()
										end --for some reason anims just break so reset them
									end)
								end)
							end)
						end)
					end
				end
			else
				Say:Say("Professor", true, {
					{ Text = "No rush. Let them speak to you in their own way.", Emotion = "Neutral" },
				}, Professor)
			end
		end)
	end
	wireSelectionFor("Frigo Camelo")
	wireSelectionFor("Kitung")
	wireSelectionFor("Twirlina")

    if handle and handle.End then handle:End() end
    return true
end



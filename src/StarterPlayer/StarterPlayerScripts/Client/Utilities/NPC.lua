local NPC = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RSAssets = ReplicatedStorage:WaitForChild("Assets")

local Say = require(script.Parent.Say)
local UI = require(script.Parent.Parent.UI)
local NPCAnimations = require(script.Parent.NPCAnimations)
local LOS = require(script.Parent.LineOfSightTriggers)
local CharacterFunctions = require(script.Parent.CharacterFunctions)
local RelocationSignals = require(script.Parent.RelocationSignals)
local CutsceneRegistry = require(script.Parent:WaitForChild("CutsceneRegistry"))
local MusicManager = require(script.Parent:WaitForChild("MusicManager"))
local UIFunctions = require(script.Parent.Parent.UI.UIFunctions)
local TweenService = game:GetService("TweenService")
local MoveTo = require(script.Parent.MoveTo)
local TrainerIntroController = require(script.Parent.TrainerIntroController)

-- Runtime engagement guard for trainer LOS (per-session, client-only)
local engagedTrainerIds: {[string]: boolean} = {}

-- Plays a short, random reaction animation on the NPC. Returns the track if played.
local function playRandomIntroAnim(npcModel: Model): AnimationTrack?
    local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
    if not humanoid then return nil end
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end
    local ids = {"rbxassetid://127685879005353", "rbxassetid://103694131430779"}
    local pick = ids[math.random(1, #ids)]
    local anim = Instance.new("Animation")
    anim.AnimationId = pick
    local ok, track = pcall(function()
        return animator:LoadAnimation(anim)
    end)
    if ok and track then
        track.Priority = Enum.AnimationPriority.Action
        track.Looped = false
        pcall(function() track:Play(0.1) end)
        return track
    end
    return nil
end

-- Moves the NPC toward the player, stopping at a fixed distance or timing out
local function moveNpcToPlayer(npcModel: Model, playerHRP: BasePart, stopDistance: number, timeoutSeconds: number): boolean
    local npcHRP = npcModel:FindFirstChild("HumanoidRootPart")
    local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
    if not (npcHRP and humanoid and playerHRP) then return false end
    local toPlayer = (playerHRP.Position - npcHRP.Position)
    local dir = (toPlayer.Magnitude > 0.001) and toPlayer.Unit or Vector3.new(0,0,-1)
    local targetPos = Vector3.new(playerHRP.Position.X, npcHRP.Position.Y, playerHRP.Position.Z) - (dir * stopDistance)
    return MoveTo.MoveHumanoidToTarget(humanoid, npcHRP, targetPos, {
        minWalkSpeed = 14,
        timeout = timeoutSeconds,
        arriveRadius = 1.2,
        retryInterval = 0.35,
    })
end

local NPC_Animations = {
	["Thinking"] = "rbxassetid://96330194627339",
	["Talking"] = "rbxassetid://110437102401052",
	["Smug"] = "rbxassetid://116184509431414",
	["Sleepy"] = "rbxassetid://112602001209074",
	["Shy"] = "rbxassetid://124965534094622",
	["Sad"] = "rbxassetid://72116622449493",
	["Neutral"] = "rbxassetid://123980712848501",
	["Happy"] = "rbxassetid://94328949610609",
	["Excited"] = "rbxassetid://104821505506421",
	["Confused"] = "rbxassetid://75794920166998",
	["Bored"] = "rbxassetid://93939354651160",
	["Angry"] = "rbxassetid://87629702370664",
}

function NPC:Setup(NPC, ClickFunction)
	local dialogueModule = NPC:FindFirstChild("Dialogue")
	if not dialogueModule and not ClickFunction then
		return -- Nothing to setup
	end

	local dialogueData
	if dialogueModule then
		local success, result = pcall(require, dialogueModule)
		if success and type(result) == "table" then
			dialogueData = result
			-- Play custom animation if provided
			local customAnim = dialogueData.CustomAnimation
			local customEmotion = dialogueData.Emotion
			if customAnim ~= nil and customAnim ~= false then
				local animId = customAnim
				if typeof(animId) == "number" then
					animId = tostring(animId)
				end
				if typeof(animId) == "string" and animId ~= "" then
					if not string.find(animId, "rbxassetid://", 1, true) then
						animId = "rbxassetid://" .. animId
					end
					local humanoid = NPC:FindFirstChildOfClass("Humanoid")
					if humanoid then
						local animator = humanoid:FindFirstChildOfClass("Animator")
						if not animator then
							animator = Instance.new("Animator")
							animator.Parent = humanoid
						end
						local animation = Instance.new("Animation")
						animation.AnimationId = animId
						local ok, track = pcall(function()
							return animator:LoadAnimation(animation)
						end)
						if ok and track then
							track.Priority = Enum.AnimationPriority.Idle
							track.Looped = true
							pcall(function()
								track:Play()
							end)
							-- Mark NPC as having a custom dialogue animation to prevent emotion overrides
							pcall(function()
								NPC:SetAttribute("HasCustomDialogueAnim", true)
							end)
						else
							warn("Failed to load custom animation for NPC:", NPC.Name)
						end
					end
				end
			end
			-- Or play a predefined emotion if provided
			if type(customEmotion) == "string" and customEmotion ~= "" and not NPC:GetAttribute("HasCustomDialogueAnim") then
				local humanoid = NPC:FindFirstChildOfClass("Humanoid")
				if humanoid then
					NPCAnimations:PlayEmotionLoop(NPC, customEmotion)
				end
			end
		else
			warn("Failed to load dialogue for NPC:", NPC.Name)
		end
	end

	-- Optional: Trainer LOS trigger from Dialogue if present
	if dialogueData and dialogueData.LineOfSight == true then
		local trainerIdStr = dialogueData.TrainerId and tostring(dialogueData.TrainerId) or nil
		-- Plays a short, random intro animation on the NPC. Returns the track if played.
		local function playRandomIntroAnim(npcModel: Model): AnimationTrack?
			local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
			if not humanoid then return nil end
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if not animator then
				animator = Instance.new("Animator")
				animator.Parent = humanoid
			end
			local ids = {"rbxassetid://127685879005353", "rbxassetid://103694131430779"}
			local pick = ids[math.random(1, #ids)]
			local anim = Instance.new("Animation")
			anim.AnimationId = pick
			local ok, track = pcall(function()
				return animator:LoadAnimation(anim)
			end)
			if ok and track then
				track.Priority = Enum.AnimationPriority.Action
				track.Looped = false
				pcall(function() track:Play(0.1) end)
				return track
			end
			return nil
		end

		-- Moves the NPC toward the player, stopping at a fixed distance or timing out
		local function moveNpcToPlayer(npcModel: Model, playerHRP: BasePart, stopDistance: number, timeoutSeconds: number)
			local npcHRP = npcModel:FindFirstChild("HumanoidRootPart")
			local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
			if not (npcHRP and humanoid and playerHRP) then return false end
			local toPlayer = (playerHRP.Position - npcHRP.Position)
			local dir = (toPlayer.Magnitude > 0.001) and toPlayer.Unit or Vector3.new(0,0,-1)
			local targetPos = Vector3.new(playerHRP.Position.X, npcHRP.Position.Y, playerHRP.Position.Z) - (dir * stopDistance)
			return MoveTo.MoveHumanoidToTarget(humanoid, npcHRP, targetPos, {
				minWalkSpeed = 12,
				timeout = timeoutSeconds,
				arriveRadius = 1.75,
				retryInterval = 0.35,
			})
		end
		local function triggerTrainerLOS(npcModel: Model)
			-- Mark engagement as a cutscene to gate other systems immediately
			pcall(function()
				CutsceneRegistry:Start("TrainerEngagement")
			end)
			-- Stop player movement and face trainer; hide topbar during engagement
			CharacterFunctions:CanMove(false)
			pcall(function() UI.TopBar:Hide() end)
			local player = game.Players.LocalPlayer
			local character = player.Character or player.CharacterAdded:Wait()
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			local npcHRP = npcModel:FindFirstChild("HumanoidRootPart")
			-- Play a short reaction animation, then walk up to the player before starting dialogue
			local introTrack = playRandomIntroAnim(npcModel)
			if hrp then
				-- Prepare walk loop to start exactly when movement begins
				local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
				local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
				if humanoid and not animator then animator = Instance.new("Animator"); animator.Parent = humanoid end
				local walkTrack: AnimationTrack? = nil
				local function handleStart()
					if not animator then return end
					if walkTrack == nil then
						local anim = Instance.new("Animation"); anim.AnimationId = "rbxassetid://120866625087275"
						local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
						if ok and track then
							walkTrack = track
							walkTrack.Priority = Enum.AnimationPriority.Movement
							walkTrack.Looped = true
							-- Only start walk after actual movement begins; guard by checking velocity soon after
							task.delay(0.05, function()
								local hrpNow = npcModel:FindFirstChild("HumanoidRootPart")
								if hrpNow then
									local v = hrpNow.AssemblyLinearVelocity
									local speed2d = math.sqrt(v.X*v.X + v.Z*v.Z)
									if speed2d > 0.9 then
										pcall(function() walkTrack:Play(0.1) end)
									end
								end
							end)
						end
					end
				end
				local function handleComplete()
					if walkTrack then pcall(function() walkTrack:Stop(0.15) end) end
				end
				MoveTo.MoveHumanoidToTarget(humanoid, npcHRP, (function()
					local toPlayer = (hrp.Position - npcHRP.Position)
					local dir = (toPlayer.Magnitude > 0.001) and toPlayer.Unit or Vector3.new(0,0,-1)
					return Vector3.new(hrp.Position.X, npcHRP.Position.Y, hrp.Position.Z) - (dir * 6)
				end)(), {
					minWalkSpeed = 12,
					timeout = 5.0,
					arriveRadius = 1.75,
					retryInterval = 0.35,
					onStart = handleStart,
					onComplete = function()
						handleComplete()
					end
				})
			end
			if introTrack then pcall(function() introTrack:Stop(0.1) end) end
			-- Smoothly face each other after movement or timeout
			if hrp and npcHRP then
				local tweenA = TweenService:Create(npcHRP, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					CFrame = CFrame.new(npcHRP.Position, Vector3.new(hrp.Position.X, npcHRP.Position.Y, hrp.Position.Z))
				})
				local tweenB = TweenService:Create(hrp, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					CFrame = CFrame.new(hrp.Position, Vector3.new(npcHRP.Position.X, hrp.Position.Y, npcHRP.Position.Z))
				})
				tweenA:Play(); tweenB:Play()
			end
			-- Only now start intro dialogue; when done, optionally start trainer battle
			if dialogueData.Say and #dialogueData.Say > 0 then
				Say:Say(dialogueData.Name or npcModel.Name, true, dialogueData.Say, npcModel)
				UI.TopBar:Show()
			end
			-- Play EyesMeet sting and raise cinematic black bars on trainer engagement
			local pg = game.Players.LocalPlayer and game.Players.LocalPlayer:FindFirstChild("PlayerGui")
			local gameUI = pg and pg:FindFirstChild("GameUI")
			local blackBars = gameUI and gameUI:FindFirstChild("BlackBars")
			if blackBars and blackBars:IsA("ImageLabel") then
				UIFunctions:BlackBars(true, blackBars)
			end
			TweenService:Create(workspace.CurrentCamera, TweenInfo.new(0.65,Enum.EasingStyle.Back,Enum.EasingDirection.Out), {FieldOfView = 60}):Play()
			MusicManager:PlayTrainerIntro()


			-- Build trainer spec and request battle
			-- Prepare trainer intro clone so BattleSystemV2 can consume it
			pcall(function()
				TrainerIntroController:PrepareFromNPC(npcModel)
			end)
			if type(dialogueData.Party) == "table" and (dialogueData.TrainerName or dialogueData.Name) then
				local Events = game:GetService("ReplicatedStorage"):WaitForChild("Events")
				local trainerSpec = {}
				for _, p in ipairs(dialogueData.Party) do
					if type(p) == "table" and type(p.Name) == "string" then
						table.insert(trainerSpec, { Name = p.Name, Level = tonumber(p.Level) or 1, Moves = p.Moves, Shiny = p.Shiny, Nature = p.Nature, Gender = p.Gender })
					end
				end
				pcall(function()
					Events.Request:InvokeServer({"StartBattle", "Trainer", {
						TrainerName = dialogueData.TrainerName or dialogueData.Name or (npcModel and npcModel.Name) or "Trainer",
						TrainerSpec = trainerSpec,
						TrainerId = dialogueData.TrainerId,
						TrainerDialogue = dialogueData, -- Pass full dialogue data for post-battle messages
					}})
				end)
				pcall(function()
					CutsceneRegistry:End("TrainerEngagement")
				end)
			end
		end
		-- Arm a re-arming LOS trigger with engagement gating
		local function armTrainerLOS()
			local EncounterZone = require(script.Parent.EncounterZone)
			LOS:SetupRearmingTrigger(NPC, {
				MaxDistance = dialogueData.LOSMaxDistance or 35,
				FOV = dialogueData.LOSFOV or 15,
				UniqueKey = (dialogueData.TrainerId and ("TRAINER_LOS_" .. tostring(dialogueData.TrainerId))) or (NPC:GetFullName() .. "::TRAINER_LOS"),
				CooldownSeconds = 1.5,
				ShouldStop = function()
					local ClientData = require(script.Parent.Parent.Plugins.ClientData)
					local pd = ClientData:Get()
					local defeated = pd and pd.DefeatedTrainers and dialogueData.TrainerId and pd.DefeatedTrainers[dialogueData.TrainerId] == true or false
					local engaged = trainerIdStr and engagedTrainerIds[trainerIdStr] == true or false
					return defeated or engaged
				end,
				OnTrigger = function(npc)
					-- Skip if already in an encounter or trainer already defeated/engaged
					if EncounterZone and EncounterZone:IsInEncounter() then return end
					local ClientData = require(script.Parent.Parent.Plugins.ClientData)
					local pd = ClientData:Get()
					if pd and pd.DefeatedTrainers and dialogueData.TrainerId and pd.DefeatedTrainers[dialogueData.TrainerId] then return end
					if trainerIdStr and engagedTrainerIds[trainerIdStr] then return end
					if trainerIdStr then engagedTrainerIds[trainerIdStr] = true end
					-- Friendly LOS line specific to healers or non-hostile trainers
					if dialogueData and dialogueData.Name == "Healer Tom" then
						local Say = require(script.Parent.Say)
						Say:Say("Healer Tom", true, {"Oh, it's me again! Come to me if you need healing."}, npc)
						UI.TopBar:Show()
					else
						triggerTrainerLOS(npc)
					end
					-- Re-arm after battle ends (win/loss)
					local Events = game:GetService("ReplicatedStorage"):WaitForChild("Events")
					local conn
					conn = Events.Communicate.OnClientEvent:Connect(function(eventType, data)
						if eventType ~= "BattleOver" then return end
						-- Wait for confirmed relocation rather than re-arming immediately
						local rc
						rc = RelocationSignals.OnPostBattleRelocated(function(ctx)
							if trainerIdStr then engagedTrainerIds[trainerIdStr] = nil end
							armTrainerLOS()
							if rc then rc:Disconnect() end
						end)
						if conn then conn:Disconnect() end
					end)
				end,
			})
		end
		armTrainerLOS()
	end

	-- Only create ClickDetector if there's dialogue with Say table or a custom ClickFunction
	local hasDialogue = dialogueData and dialogueData.Say
	if not hasDialogue and not ClickFunction then
		return -- No interaction needed for static NPCs
	end

	local clickDetector = RSAssets.ClickDetector:Clone()
	clickDetector.Parent = NPC

	local function onClick()
		-- Check if any TopBar menu is open - prevent NPC interactions
		if UI.TopBar:IsMenuOpen() then
			return -- Don't allow NPC interaction when menus are open
		end
		-- If this NPC has LOS trainer logic, allow click-to-initiate battle using same gating
		if dialogueData and dialogueData.LineOfSight == true then
			local EncounterZone = require(script.Parent.EncounterZone)
			if not (EncounterZone and EncounterZone:IsInEncounter()) then
				local trainerIdStr = dialogueData.TrainerId and tostring(dialogueData.TrainerId) or nil
				local ClientData = require(script.Parent.Parent.Plugins.ClientData)
				local pd = ClientData:Get()
				local defeated = pd and pd.DefeatedTrainers and dialogueData.TrainerId and pd.DefeatedTrainers[dialogueData.TrainerId] == true or false
				local engaged = trainerIdStr and engagedTrainerIds[trainerIdStr] == true or false
				if not defeated and not engaged then
					if trainerIdStr then engagedTrainerIds[trainerIdStr] = true end
					-- Use the same trainer engagement flow as LOS
					local function startTrainer()
						pcall(function()
							CutsceneRegistry:Start("TrainerEngagement")
						end)
					-- Inline the trigger logic to avoid upvalue scope for linter
						CharacterFunctions:CanMove(false)
						local player = game.Players.LocalPlayer
						local character = player.Character or player.CharacterAdded:Wait()
						local hrp = character and character:FindFirstChild("HumanoidRootPart")
					local npcHRP = NPC:FindFirstChild("HumanoidRootPart")
						-- Prepare trainer intro clone so BattleSystemV2 can consume it
						pcall(function()
							TrainerIntroController:PrepareFromNPC(NPC)
						end)
					-- Play reaction, walk, then dialogue
					local introTrack = playRandomIntroAnim(NPC)
					task.wait(1)
					if hrp then
						moveNpcToPlayer(NPC, hrp, 6, 5.0)
					end
					if introTrack then pcall(function() introTrack:Stop(0.1) end) end
					if hrp and npcHRP then
						npcHRP.CFrame = CFrame.new(npcHRP.Position, Vector3.new(hrp.Position.X, npcHRP.Position.Y, hrp.Position.Z))
						hrp.CFrame = CFrame.new(hrp.Position, Vector3.new(npcHRP.Position.X, hrp.Position.Y, npcHRP.Position.Z))
					end
					if dialogueData.Say and #dialogueData.Say > 0 then
						Say:Say(dialogueData.Name or NPC.Name, true, dialogueData.Say, NPC)
						UI.TopBar:Show()
					end
						if type(dialogueData.Party) == "table" and (dialogueData.TrainerName or dialogueData.Name) then
							local Events = game:GetService("ReplicatedStorage"):WaitForChild("Events")
							local trainerSpec = {}
							for _, p in ipairs(dialogueData.Party) do
								if type(p) == "table" and type(p.Name) == "string" then
									table.insert(trainerSpec, { Name = p.Name, Level = tonumber(p.Level) or 1, Moves = p.Moves, Shiny = p.Shiny, Nature = p.Nature, Gender = p.Gender })
								end
							end
							pcall(function()
								Events.Request:InvokeServer({"StartBattle", "Trainer", {
									TrainerName = dialogueData.TrainerName or dialogueData.Name or (NPC and NPC.Name) or "Trainer",
									TrainerSpec = trainerSpec,
									TrainerId = dialogueData.TrainerId,
									TrainerDialogue = dialogueData,
								}})
							end)
							pcall(function()
								CutsceneRegistry:End("TrainerEngagement")
							end)
						end
					end
					startTrainer()
					return
				end
			end
		end

		if ClickFunction then
			ClickFunction()
		elseif dialogueData and dialogueData.Say then
			-- Check if this is a trainer and if they've been defeated
			local dialogueToUse = dialogueData.Say
			if dialogueData.TrainerId then
				local ClientData = require(script.Parent.Parent.Plugins.ClientData)
				local pd = ClientData:Get()
				if pd and pd.DefeatedTrainers and pd.DefeatedTrainers[dialogueData.TrainerId] then
					-- Trainer defeated - use AfterSayOverworld if available
					if dialogueData.AfterSayOverworld then
						dialogueToUse = dialogueData.AfterSayOverworld
					end
				end
			end
			Say:Say(dialogueData.Name, true, dialogueToUse, NPC)
			UI.TopBar:Show()
		end
	end

	return clickDetector.MouseClick:Connect(onClick)
end

return NPC
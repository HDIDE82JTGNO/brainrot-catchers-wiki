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

-- Follow system state
type FollowConfig = {
	stopDistance: number?,
	maxTeleportDistance: number?,
	arriveRadius: number?,
	pathRecomputeDelay: number?,
	walkSpeed: number?,
	runSpeed: number?,
}
local _followTokens: {[Model]: any} = {}
local _followAnims: {[Model]: AnimationTrack?} = {}

-- Internal: start/stop walk loop animation for an NPC humanoid
local function _ensureWalkAnim(npcModel: Model): AnimationTrack?
	local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	-- Reuse cached if still playing
	local existing = _followAnims[npcModel]
	if existing and existing.IsPlaying then
		return existing
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://120866625087275"
	local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Movement
		track.Looped = true
		_followAnims[npcModel] = track
		return track
	end
	return nil
end

local function _stopWalkAnim(npcModel: Model)
	local t = _followAnims[npcModel]
	if t then
		pcall(function() t:Stop(0.1) end)
		_followAnims[npcModel] = nil
	end
end

-- Start following the local player. Safe to call repeatedly; re-entrant guarded.
function NPC:StartFollowingPlayer(npcModel: Model, cfg: FollowConfig?): boolean
	if not npcModel or not npcModel:IsA("Model") then return false end
	if _followTokens[npcModel] ~= nil then return true end
	local npcHRP = npcModel:FindFirstChild("HumanoidRootPart")
	local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
	if not (npcHRP and humanoid) then return false end

	local player = game:GetService("Players").LocalPlayer
	local character = player and (player.Character or player.CharacterAdded:Wait())
	local playerHRP = character and character:FindFirstChild("HumanoidRootPart")
	if not playerHRP then return false end

	local stopDistance = (cfg and cfg.stopDistance) or 4.5
	local maxTeleportDistance = (cfg and cfg.maxTeleportDistance) or 60
	local arriveRadius = (cfg and cfg.arriveRadius) or 1.5
	local pathDelay = (cfg and cfg.pathRecomputeDelay) or 0.35
	local walkSpeed = (cfg and cfg.walkSpeed) or 14
	local runSpeed = (cfg and cfg.runSpeed) or 20

	local token = {}
	_followTokens[npcModel] = token

	-- Auto-stop if the NPC model is removed
	npcModel.AncestryChanged:Connect(function(_, parent)
		if not parent then
			self:StopFollowingPlayer(npcModel)
		end
	end)

	local PathfindingService = game:GetService("PathfindingService")
	task.spawn(function()
		local walking = false
		local lastPathAt = 0
		local path = nil
		local waypoints: {PathWaypoint}? = nil
		local waypointIndex = 2
		local lastPathTarget: Vector3? = nil
		local lastMoveDir: Vector3 = Vector3.zero
		local function blendDir(current: Vector3, target: Vector3): Vector3
			-- Light smoothing to reduce micro-turn jitter
			local a = 0.7
			local b = 0.3
			local v = current * a + target * b
			if v.Magnitude < 1e-3 then
				return target
			end
			return v.Unit
		end
		while _followTokens[npcModel] == token do
			local mp = npcHRP.Position
			local pp = playerHRP.Position
			local diff = pp - mp
			local dist = diff.Magnitude
			local playerVel = playerHRP.AssemblyLinearVelocity
			local speed2d = math.sqrt(playerVel.X * playerVel.X + playerVel.Z * playerVel.Z)

			-- Teleport catch-up for large separations (e.g., after cutscene)
			if dist > maxTeleportDistance then
				-- Place behind player by 3 studs
				local look = playerHRP.CFrame.LookVector
				local targetCFrame = CFrame.new(pp - look * 3, Vector3.new(mp.X, pp.Y, mp.Z))
				npcHRP.CFrame = targetCFrame
				humanoid:Move(Vector3.zero)
				_stopWalkAnim(npcModel)
				walking = false
				task.wait(0.15)
			else
				-- Compute a sensible goal position with near-ring projection to avoid crossing through the player
				local goalPos: Vector3
				local planarToPlayer = Vector3.new(pp.X - mp.X, 0, pp.Z - mp.Z)
				local planarGap = planarToPlayer.Magnitude
				local nearRing = planarGap <= (stopDistance + 1.5)
				if nearRing then
					-- Project to a ring around the player at stopDistance, preserving current bearing
					if planarGap > 0.05 then
						local ringDir = (-planarToPlayer).Unit -- from player to NPC
						goalPos = Vector3.new(pp.X, mp.Y, pp.Z) + ringDir * stopDistance
					else
						-- Degenerate case: fall back to behind player's facing
						local look = playerHRP.CFrame.LookVector
						goalPos = Vector3.new(pp.X, mp.Y, pp.Z) - look * stopDistance
					end
				else
					-- Farther away: head toward player or behind if they're nearly stationary
					if speed2d < 1.5 then
						local look = playerHRP.CFrame.LookVector
						goalPos = Vector3.new(pp.X, mp.Y, pp.Z) - look * stopDistance
					else
						goalPos = Vector3.new(pp.X, mp.Y, pp.Z)
					end
				end

				-- Arrival check with hysteresis
				local toGoal = goalPos - mp
				local flatGoalDelta = Vector3.new(toGoal.X, 0, toGoal.Z)
				local planarDistToPlayer = planarGap
				if flatGoalDelta.Magnitude <= math.max(arriveRadius, 1.25) or planarDistToPlayer <= (stopDistance - 0.5) then
					-- Close enough: idle
					humanoid:Move(Vector3.zero)
					if walking then
						_stopWalkAnim(npcModel)
						walking = false
					end
					-- Don't override idle animations for Following Creatures (they use server-managed animations)
					-- Following Creatures have names like "PlayerName_Creature_SlotIndex"
					local isFollowingCreature = string.find(npcModel.Name, "_Creature_") ~= nil
					if not isFollowingCreature then
						pcall(function() NPCAnimations:PlayEmotionLoop(npcModel, "Happy") end)
					end
				else
					-- Choose direct steering vs pathfinding
					local needPath = dist > 18
					-- Recompute path if needed and target changed notably
					if needPath then
						if (os.clock() - lastPathAt) >= pathDelay then
							local targetChanged = (lastPathTarget and (lastPathTarget - goalPos).Magnitude > 6) or (lastPathTarget == nil)
							if targetChanged then
								lastPathAt = os.clock()
								lastPathTarget = goalPos
								local p = PathfindingService:CreatePath({
									AgentRadius = 2,
									AgentHeight = 3,
									WaypointSpacing = 4,
									AgentCanJump = true,
								})
								local ok = pcall(function() p:ComputeAsync(mp, goalPos) end)
								if ok and p.Status == Enum.PathStatus.Success then
									path = p
									waypoints = p:GetWaypoints()
									waypointIndex = 2
								else
									path = nil
									waypoints = nil
								end
							end
						end
					else
						path = nil
						waypoints = nil
					end

					local moveTarget: Vector3 = goalPos
					if waypoints and waypoints[waypointIndex] then
						-- Advance waypoint when close enough
						while waypoints[waypointIndex] and (npcHRP.Position - waypoints[waypointIndex].Position).Magnitude <= 2.0 do
							waypointIndex += 1
						end
						if waypoints[waypointIndex] then
							moveTarget = Vector3.new(waypoints[waypointIndex].Position.X, mp.Y, waypoints[waypointIndex].Position.Z)
						else
							moveTarget = goalPos
						end
					end

					-- Speed based on gap with slowdown near target to prevent overshoot/orbiting
					local baseSpeed = (dist > 12) and runSpeed or walkSpeed
					local remaining = flatGoalDelta.Magnitude
					local slowFactor = math.clamp(remaining / 6, 0.4, 1)
					humanoid.WalkSpeed = math.max(8, baseSpeed * slowFactor)
					local flat = Vector3.new(1, 0, 1)
					local dirRaw = (moveTarget - mp) * flat
					if dirRaw.Magnitude > 0.001 then
						local desired = dirRaw.Unit
						local smooth = blendDir(lastMoveDir, desired)
						lastMoveDir = smooth
						humanoid:Move(smooth)
					end
					-- Start walk loop if not already
					if not walking then
						pcall(function() NPCAnimations:StopEmotion(npcModel) end)
						local track = _ensureWalkAnim(npcModel)
						if track and not track.IsPlaying then
							pcall(function() track:Play(0.1) end)
						end
						walking = true
					end
				end
			end
			task.wait(0.1)
		end
		-- Cleanup when loop exits
		humanoid:Move(Vector3.zero)
		_stopWalkAnim(npcModel)
		-- Restore a neutral idle when follow stops (but not for Following Creatures)
		local isFollowingCreature = string.find(npcModel.Name, "_Creature_") ~= nil
		if not isFollowingCreature then
			pcall(function() NPCAnimations:PlayEmotionLoop(npcModel, "Happy") end)
		end
	end)
	return true
end

function NPC:StopFollowingPlayer(npcModel: Model): ()
	if not npcModel or not npcModel:IsA("Model") then return end
	_followTokens[npcModel] = nil	
	_stopWalkAnim(npcModel)
	local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Move(Vector3.zero)
	end
end

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
			pcall(function() UI.TopBar:Hide() UI.TopBar:SetSuppressed(true) end)
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
		-- Check if dialogue is already active - prevent multiple dialogues
		if Say:IsActive() then
			return -- Don't allow NPC interaction while dialogue is active
		end
		-- Check if any TopBar menu is open - prevent NPC interactions
		if UI.TopBar:IsMenuOpen() then
			return -- Don't allow NPC interaction when menus are open
		end
		-- Check if player is in battle - prevent NPC interactions during battle
		local ClientDataMod = require(script.Parent.Parent.Plugins.ClientData)
		local pd = ClientDataMod:Get()
		if pd and pd.InBattle == true then
			return -- Don't allow NPC interaction while in battle
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
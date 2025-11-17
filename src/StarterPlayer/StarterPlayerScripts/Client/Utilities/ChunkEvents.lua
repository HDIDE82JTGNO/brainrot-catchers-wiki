local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local DBG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DBG"))
local Events = ReplicatedStorage:WaitForChild("Events")
local UI = require(script.Parent.Parent:WaitForChild("UI"))
local Say = require(script.Parent:WaitForChild("Say"))
local NPC = require(script.Parent:WaitForChild("NPC"))
local LOS = require(script.Parent:WaitForChild("LineOfSightTriggers"))
local CutsceneManager = require(script.Parent:WaitForChild("CutsceneManager"))
local CameraManager = require(script.Parent:WaitForChild("CameraManager"))
local RunService = game:GetService("RunService")
local ClientData = require(script.Parent.Parent.Plugins.ClientData)
local CharacterFunctions = require(script.Parent.CharacterFunctions)
local MoveTo = require(script.Parent.MoveTo)
local UIFunctions = require(script.Parent.Parent.UI.UIFunctions)

DBG:print("[ChunkEvents] Module required and initialized")

local function setClientEventFlag(eventName: string, value: boolean): ()
	local data = ClientData:Get()
	if data then
		data.Events = data.Events or {}
		data.Events[eventName] = value
	end
	task.spawn(function()
		local success, result = pcall(function()
			return Events.Request:InvokeServer({"SetEvent", eventName, value})
		end)
		if not success or result ~= true then
			DBG:warn(string.format("[ChunkEvents] Failed to set event %s (value=%s): %s", tostring(eventName), tostring(value), tostring(result)))
		end
	end)
end

-- Helper: lazy-load and register a cutscene module by name from Client/Cutscenes
local function LoadAndRegisterCutscene(cutsceneName: string, moduleName: string): boolean
    return CutsceneManager:RegisterModule(cutsceneName, moduleName)
end

-- Helper: explicit event gating + lazy registration + RunOnceEvent
local function RunCutsceneOnceGated(eventName: string, cutsceneName: string, moduleName: string, ctx: any)
	CutsceneManager:RunOnceModule(eventName, cutsceneName, moduleName, ctx)
end

-- Register modular cutscenes here if needed
CutsceneManager:RegisterModule("Act1_RooftopCall", "Act1_RooftopCall")

return {	
	["Load_Chunk1"] = function(CurrentChunk)
        DBG:print("[ChunkEvents] Load_Chunk1 invoked")
		
		--Runs game intro if we have not played before.
		CutsceneManager:RunOnceEvent("GAME_INTRO", "Act1_RooftopCall", CurrentChunk)

		-- Healer Tom NPC (LOS hint + click-to-heal)
		local NPCFolder = CurrentChunk and CurrentChunk.Model and CurrentChunk.Model:FindFirstChild("NPCs")
		local Healer = NPCFolder and NPCFolder:FindFirstChild("Healer Tom")
		if Healer then
			-- One-time line-of-sight hint
            LOS:SetupOnceTrigger(Healer, {
				MaxDistance = 24,
				FOV = 10,
				UniqueKey = "HealerTom_LOS_Chunk1",
                OnTrigger = function(npcModel, npcHRP)
					UI.TopBar:Hide()
                    Say:Say("Healer Tom", true, {
						{ Text = "Hey there! If you need your creatures healed, come and speak to me!", Emotion = "Happy" },
                    }, npcHRP or npcModel)
                    UI.TopBar:Show()
                    -- Re-enable movement after LOS hint finishes
                    local CharacterFunctions = require(script.Parent.CharacterFunctions)
                    pcall(function()
                        CharacterFunctions:SetSuppressed(false)
                        CharacterFunctions:CanMove(true)
                    end)
					
				end,
			})
			-- Click interaction: request heal
            NPC:Setup(Healer, function()
				UI.TopBar:Hide()
				Say:Say("Healer Tom", true, {
					{ Text = "Here, let me heal your creatures for you!", Emotion = "Talking" },
				}, Healer)
				local ok = false
				local success, result = pcall(function()
					return Events.Request:InvokeServer({"HealParty"})
				end)
				ok = success and result == true
				if ok then
					Say:Say("Healer Tom", true, {
						{ Text = "Okay, all done! Happy hunting!", Emotion = "Happy" },
					}, Healer)
					UI.TopBar:Show()
                    -- Re-enable movement after healer interaction
                    local CharacterFunctions = require(script.Parent.CharacterFunctions)
                    pcall(function()
                        CharacterFunctions:SetSuppressed(false)
                        CharacterFunctions:CanMove(true)
                    end)
				else
					Say:Say("Healer Tom", true, {
						{ Text = "Hmm, that didn't work. Come back when you're nearby.", Emotion = "Confused" },
					}, Healer)
					UI.TopBar:Show()
                    -- Ensure movement is re-enabled even on failure path
                    local CharacterFunctions = require(script.Parent.CharacterFunctions)
                    pcall(function()
                        CharacterFunctions:SetSuppressed(false)
                        CharacterFunctions:CanMove(true)
                    end)
				end
			end)
		end

			-- Register where to relocate after blackout in this chunk
		CurrentChunk.BlackoutRelocate = {
			Type = "HealerTom",
			ChunkName = "Chunk1",
			NPCTargetName = "Healer Tom",
		}

		-- Prevent exiting town without a starter near Essentials.NonStarterBlocker
		local Essentials = CurrentChunk and CurrentChunk.Essentials
		local Blocker: BasePart? = Essentials and Essentials:FindFirstChild("NonStarterBlocker")
		if Blocker and Blocker:IsA("BasePart") then
			local Player = game:GetService("Players").LocalPlayer
			local ClientData = require(script.Parent.Parent.Plugins.ClientData)
			local CharacterFunctions = require(script.Parent.CharacterFunctions)

            local lastTriggerTime = 0
            local proximityAhead = 3 -- studs in front of Blocker front face to trigger
            local lateralPadding = 2 -- side padding to allow some leeway
            local pushBackBehind = 10 -- studs behind Blocker to push player
			local hbConn
			hbConn = RunService.Heartbeat:Connect(function()
				-- Validate character and HRP
				local character = Player.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				local humanoid: Humanoid? = character and character:FindFirstChildOfClass("Humanoid")
				if not hrp or not humanoid then return end

				-- If player has a starter, remove guard
				local pd = ClientData:Get()
				local hasStarter = (pd and ((pd.SelectedStarter ~= nil) or (pd.Party and #pd.Party > 0))) and true or false
				if hasStarter then
					if hbConn then hbConn:Disconnect() end
					return
				end

                -- Compute relative position using Blocker orientation
                local toPlayer = hrp.Position - Blocker.Position
                local look = Blocker.CFrame.LookVector
                local right = Blocker.CFrame.RightVector
                local halfDepth = (Blocker.Size.Z or 0) * 0.5
                local halfWidth = (Blocker.Size.X or 0) * 0.5
                local axisDist = toPlayer:Dot(look) -- + in front of blocker, - behind
                local lateralDist = math.abs(toPlayer:Dot(right))
                local frontFace = halfDepth
                local inFrontBand = axisDist >= (frontFace - 0.25) and axisDist <= (frontFace + proximityAhead)
                local withinWidth = lateralDist <= (halfWidth + lateralPadding)
                if inFrontBand and withinWidth then
                    local now = os.clock()
                    if now - lastTriggerTime < 1.2 then return end
                    lastTriggerTime = now
                    
                    -- Prompt the player with a brief hint
                    Say:Say("Me", true, { { Text = "I should head to the lab first.", Emotion = "Thinking" } })

                    local behindPoint = Blocker.CFrame.Position - (look * (halfDepth + 10))
                    local target = Vector3.new(behindPoint.X, hrp.Position.Y, behindPoint.Z)
                    local MoveTo = require(script.Parent.MoveTo)
                    MoveTo.MoveToTarget(target, {
                        minWalkSpeed = 12,
                        timeout = 1.5,
                        delayAfter = 0.5,
                        preserveFacing = true,
                    })
                    pcall(function() Say:Exit() end)
                end
            end)

            -- Clean up when chunk unloads
            if CurrentChunk and CurrentChunk.Model then
                CurrentChunk.Model.AncestryChanged:Connect(function(_, parent)
                    if not parent and hbConn then
                        hbConn:Disconnect()
                        hbConn = nil
                    end
                end)
            end
        end

		local CD = ClientData:Get()
		if CD and CD.Events and CD.Events.MET_KYRO_ROUTE_1 ~= true then
			local Player = game:GetService("Players").LocalPlayer
			local character = Player and (Player.Character or Player.CharacterAdded:Wait())
			local hrp: BasePart? = character and character:FindFirstChild("HumanoidRootPart")
			local essentials = CurrentChunk and CurrentChunk.Essentials
			local kyroFolder = essentials and essentials:FindFirstChild("Kyro_R1")
			local kyro = kyroFolder:FindFirstChild("Kyro")
			local CharacterFunctions = require(script.Parent.CharacterFunctions)
			local Interactables = require(script.Parent.Interactables)
			local RelocationSignals = require(script.Parent.RelocationSignals)
			local TrainerIntroController = require(script.Parent.TrainerIntroController)

			local greeted = false
			local csActive = false
			local hbProxConn: RBXScriptConnection? = nil
			local cutsceneConn: RBXScriptConnection? = nil

			-- 1) Proximity greet near Kyro (within 8 studs)
			if kyro then
				local kyroHRP: BasePart? = kyro:FindFirstChild("HumanoidRootPart")
				hbProxConn = RunService.Heartbeat:Connect(function()
					if greeted or csActive then return end
					local phrp: BasePart? = character and character:FindFirstChild("HumanoidRootPart")
					if not phrp or not kyroHRP then return end
					if (phrp.Position - kyroHRP.Position).Magnitude <= 8 then
						greeted = true
						local look = kyroHRP.CFrame.LookVector
						local target = Vector3.new(kyroHRP.Position.X, phrp.Position.Y, kyroHRP.Position.Z) - (look * -4)
						MoveTo.MoveToTarget(target, { minWalkSpeed = 12, timeout = 2.5, preserveFacing = true, arriveRadius = 2.0, retryInterval = 0.35, delayAfter = 0.2 })
						UI.TopBar:Hide()
						Say:Say("Kyro", true, {
							{ Text = "Caught up did ya?", Emotion = "Smug" },
							{ Text = "That's good, I'm glad to see you're on the same pace.", Emotion = "Happy" },
							{ Text = "Haha! Anyways, This isn't my first time in Route 1, I've been here a few times.", Emotion = "Talking" },
							{ Text = "I want you to experience it for yourself, so I'm gonna let you explore on your own.", Emotion = "Talking" },
							{ Text = "I'll be waiting here, so don't worry about me.", Emotion = "Neutral" },
							{ Text = "Just go up ahead and you'll meet a few trainers, and a find a few creatures to catch.", Emotion = "Happy" },
						}, kyro)
						UI.TopBar:Show()
					setClientEventFlag("MET_KYRO_ROUTE_1", true)
						if hbProxConn then hbProxConn:Disconnect() hbProxConn = nil end
					end
				end)
			end

			local agent = (kyroFolder and kyroFolder:FindFirstChild("Agent Alex")) or (CurrentChunk and CurrentChunk.Model and CurrentChunk.Model.NPCs and CurrentChunk.Model.NPCs:FindFirstChild("Agent Alex"))
				local agentHRP: BasePart? = agent and agent:FindFirstChild("HumanoidRootPart")
				local agentHum: Humanoid? = agent and agent:FindFirstChildOfClass("Humanoid")
				local agentOrigCF: CFrame? = agentHRP and agentHRP.CFrame or nil
				agentHRP.Anchored = false

			-- 2) Cutscene trigger: move to shard, play pickup, Kyro runs in, then Agent confrontation and battle
			local function beginShardSequence()
				if csActive then return end
				csActive = true
				UI.TopBar:Hide()
				pcall(function() Events.Request:InvokeServer({"SetCutsceneActive", true}) end)
				CharacterFunctions:SetSuppressed(true)
				CharacterFunctions:CanMove(false)
				
				-- Initialize camera manager for cutscene
				local camManager = CameraManager.new()
				
				local shardPart: BasePart? = kyroFolder and kyroFolder:FindFirstChild("Shard")
				local phrp: BasePart? = character and character:FindFirstChild("HumanoidRootPart")
				if shardPart and shardPart:IsA("BasePart") and phrp then
					local target = Vector3.new(shardPart.Position.X, phrp.Position.Y, shardPart.Position.Z)
					MoveTo.MoveToTarget(target, { minWalkSpeed = 12, timeout = 3.0, preserveFacing = true, arriveRadius = 1.75, retryInterval = 0.35, delayAfter = 0.1 })
					pcall(function() Interactables:_playPickupAnimation() end)
					task.wait(0.5)
					shardPart:Destroy()
				end

				-- Teleport Kyro behind player at FindShardCF, then run to player and speak
				pcall(function()
					local kyHRP: BasePart? = kyro and kyro:FindFirstChild("HumanoidRootPart")
					local kyHum: Humanoid? = kyro and kyro:FindFirstChildOfClass("Humanoid")
					local findCF: BasePart? = kyroFolder and kyroFolder:FindFirstChild("FindShardCF")
					local phrp2: BasePart? = character and character:FindFirstChild("HumanoidRootPart")
					if kyHRP and kyHum and findCF and findCF:IsA("BasePart") and phrp2 then
						kyHRP.CFrame = findCF.CFrame
						kyHRP.Anchored = false
						local toPlayer = phrp2.Position - kyHRP.Position
						local dir = (toPlayer.Magnitude > 0.001) and toPlayer.Unit or Vector3.new(0,0,-1)
						-- Target a point approximately 4 studs from the player and use a small arrive radius
						local stopPos = Vector3.new(phrp2.Position.X, kyHRP.Position.Y, phrp2.Position.Z) - (dir * 4)
						local kyAnimator: Animator? = kyHum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
						if kyAnimator.Parent == nil then kyAnimator.Parent = kyHum end
						local runTrack: AnimationTrack? = nil
						MoveTo.MoveHumanoidToTarget(kyHum, kyHRP, stopPos, {
							minWalkSpeed = 14,
							timeout = 5.0,
							arriveRadius = 0.75,
							retryInterval = 0.3,
							onStart = function()
								if kyAnimator and runTrack == nil then
									local anim = Instance.new("Animation"); anim.AnimationId = "rbxassetid://120866625087275"
									local ok, track = pcall(function() return kyAnimator:LoadAnimation(anim) end)
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
								
								-- Set up camera shot showing both player and Kyro (side view)
								-- Since they're on X-axis: Kyro at X=0, Player at X=10, camera should be to the side
								task.wait(0.2) -- Wait for Kyro to settle
								if phrp2 and kyHRP then
									local centerPos = (phrp2.Position + kyHRP.Position) / 2
									-- Calculate perpendicular direction (along Z-axis for side view)
									local toPlayer = phrp2.Position - kyHRP.Position
									local perpDir = Vector3.new(0, 1, 0):Cross(toPlayer).Unit
									if perpDir.Magnitude < 0.1 then
										perpDir = Vector3.new(0, 0, 1) -- Fallback to Z-axis
									end
									
									-- Position camera to the side at a good distance (2 studs further back)
									local cameraOffset = perpDir * 10 + Vector3.new(0, 2, 0)
									local cameraPos = centerPos + cameraOffset
									local cameraCFrame = CFrame.lookAt(cameraPos, centerPos)
									
									camManager:TransitionTo(cameraCFrame, 1, 65, nil)
								end
							end,
						})
						Say:Say("Kyro", true, {
							{ Text = "WOAH! What is that?", Emotion = "Smug" },
							{ Text = "Can I take a look?", Emotion = "Talking" },
						}, kyro)
						Say:Say("", true, { { Text = "You hand the shard to Kyro.", Emotion = "Neutral" } })
						Say:Say("Kyro", true, {
							{ Text = "This sure is weird! I've never seen anything like this before.", Emotion = "Thinking" },
							{ Text = "Maybe it's from the ruins?", Emotion = "Thinking" },
							{ Text = "Or maybe it's from the ocean?", Emotion = "Thinking" },
							{ Text = "Who knows!", Emotion = "Neutral" },
						}, kyro)
					end
				end)

				-- Agent Alex approaches and challenges
				if agent and agentHRP and agentHum then
					local ahead = agentHRP.Position + (agentHRP.CFrame.LookVector * 20)
					MoveTo.MoveHumanoidToTarget(agentHum, agentHRP, Vector3.new(ahead.X, agentHRP.Position.Y, ahead.Z), { 
						minWalkSpeed = 12, 
						timeout = 4.0, 
						arriveRadius = 2.0, 
						retryInterval = 0.35,
						onComplete = function()
							-- Make agent face the player before dialogue
							local phrp3: BasePart? = character and character:FindFirstChild("HumanoidRootPart")
							if agentHRP and phrp3 then
								local tween = TweenService:Create(agentHRP, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
									CFrame = CFrame.new(agentHRP.Position, Vector3.new(phrp3.Position.X, agentHRP.Position.Y, phrp3.Position.Z))
								})
								tween:Play()
								tween.Completed:Wait()
							end
							
							-- Focus camera on Agent when he arrives
							task.wait(0.3)
							camManager:MediumShot({
								subject = agent,
								duration = 1,
								fov = 65,
								fromBehind = false
							})
						end
					})
					Say:Say("Agent Alex", true, {
						{ Text = "So… you found it first. Step aside. This shard isn't for you.", Emotion = "Angry" },
						{ Text = "You've no idea how important these pieces are.", Emotion = "Talking" },
						{ Text = "They belong to us — to Team Rift.", Emotion = "Smug" },
						{ Text = "I won't let some rookie get in the way.", Emotion = "Angry" },
						{ Text = "If you want to keep it, you'll have to beat me.", Emotion = "Smug" },
					}, agent)
					-- Start trainer battle vs Agent Alex (Frulli Frulla Lv5)
					pcall(function() TrainerIntroController:PrepareFromNPC(agent) end)
					pcall(function()
						Events.Request:InvokeServer({"StartBattle", "Trainer", {
							TrainerName = "Agent Alex",
							TrainerId = "Agent_Alex_R1",
							TrainerDialogue = { Name = "Agent Alex", Say = {} },
							TrainerSpec = { { Name = "Frulli Frulla", Level = 5 } },
						}})
					end)
					-- Post battle outcome handler
					local conn
					conn = Events.Communicate.OnClientEvent:Connect(function(eventType, data)
						if eventType ~= "BattleOver" then return end
						if conn then conn:Disconnect() end
						local rc
						rc = RelocationSignals.OnPostBattleRelocated(function(ctx)
							if rc then rc:Disconnect() end
							local reason = (type(data) == "table" and data.Reason) or nil
							if reason ~= "Win" then
								-- Loss: allow re-trigger again
								camManager:ResetToGameplay()
								UI.TopBar:Show()
								CharacterFunctions:SetSuppressed(false)
								CharacterFunctions:CanMove(true)
								csActive = false
								return
							end
							-- Win branch: agent retreats, Kyro praises, end cutscene
							Say:Say("Agent Alex", true, {
								{ Text = "…You don't understand what you're interfering with.", Emotion = "Angry" },
								{ Text = "But soon you'll see.", Emotion = "Smug" },
							}, agent)
							if agentHRP and agentHum and agentOrigCF then
								local backPos = agentOrigCF.Position
								MoveTo.MoveHumanoidToTarget(agentHum, agentHRP, Vector3.new(backPos.X, agentHRP.Position.Y, backPos.Z), { 
									minWalkSpeed = 12, 
									timeout = 3.0, 
									arriveRadius = 2.0, 
									retryInterval = 0.35,
									onStart = function()
										-- Switch to showing only player and Kyro (side view) when agent starts walking away
										task.wait(0.5)
										local phrpPost: BasePart? = character and character:FindFirstChild("HumanoidRootPart")
										local kyHRPPost: BasePart? = kyro and kyro:FindFirstChild("HumanoidRootPart")
										if phrpPost and kyHRPPost then
											local centerPos = (phrpPost.Position + kyHRPPost.Position) / 2
											local toPlayer = phrpPost.Position - kyHRPPost.Position
											local perpDir = Vector3.new(0, 1, 0):Cross(toPlayer).Unit
											if perpDir.Magnitude < 0.1 then
												perpDir = Vector3.new(0, 0, 1)
											end
											
											local cameraOffset = perpDir * 10 + Vector3.new(0, 2, 0)
											local cameraPos = centerPos + cameraOffset
											local cameraCFrame = CFrame.lookAt(cameraPos, centerPos)
											
											camManager:TransitionTo(cameraCFrame, 1, 65, nil)
										end
									end
								})
								pcall(function() if agent and agent.Parent then agent:Destroy() end end)
							end
							local pd = ClientData:Get()
							local nickname = (pd and pd.Nickname) or "Trainer"
							Say:Say("Kyro", true, {
								{ Text = "Wow. Amazing work " .. nickname .. "!", Emotion = "Happy" },
								{ Text = "You really showed that Team Rift who's boss!", Emotion = "Smug" },
								{ Text = "That shard looks important...", Emotion = "Thinking" },
								{ Text = "We should bring it to the Professor — he’s the one who’ll know what to do with it.", Emotion = "Talking" },
								{ Text = "Let me take it back to the lab for you — I’ll get it to him safely.", Emotion = "Talking" },
							}, kyro)
							Say:Say("Kyro", true, {
								{ Text = "Trust me, I’ll make sure the Professor sees it right away.", Emotion = "Happy" },
								{ Text = "You head forward, I'll catch up with you later.", Emotion = "Neutral" },
							}, kyro)
							-- Kyro turns 180 and walks back 20 studs
							pcall(function()
								local kyHRP2: BasePart? = kyro and kyro:FindFirstChild("HumanoidRootPart")
								local kyHum2: Humanoid? = kyro and kyro:FindFirstChildOfClass("Humanoid")
								if kyHRP2 and kyHum2 then
									local back = kyHRP2.Position - (kyHRP2.CFrame.LookVector * 20)
									MoveTo.MoveHumanoidToTarget(kyHum2, kyHRP2, Vector3.new(back.X, kyHRP2.Position.Y, back.Z), { 
										minWalkSpeed = 12, 
										timeout = 3.0, 
										arriveRadius = 2.0, 
										retryInterval = 0.35,
										onStart = function()
											-- Switch to close-up on player's face when Kyro starts walking away
											task.wait(0.3)
											camManager:CloseUp({
												subject = character,
												duration = 1,
												fov = 60,
												fromBehind = false
											})
										end
									})
								end
							end)
							-- Finish cutscene 2s after Kyro starts walking back: unlock, mark event, destroy folder
							task.delay(2, function()
								-- Reset camera to gameplay mode
								camManager:ResetToGameplay()
								
								UI.TopBar:Show()
								pcall(function() Events.Request:InvokeServer({"SetCutsceneActive", false}) end)
								CharacterFunctions:SetSuppressed(false)
								CharacterFunctions:CanMove(true)
								pcall(function() Events.Request:InvokeServer({"SetEvent", "MET_KYRO_ROUTE_1", true}) end)
								pcall(function()
									local folder = kyroFolder
									if folder and folder.Parent then folder:Destroy() end
								end)
								csActive = false
							end)
						end)
					end)
				end
			end

			-- Wire CutsceneTrigger touched → beginShardSequence
			local trigger: BasePart? = kyroFolder and kyroFolder:FindFirstChild("CutsceneTrigger")
			if trigger and trigger:IsA("BasePart") then
				cutsceneConn = trigger.Touched:Connect(function(hit)
					if csActive then return end
					local char = Player.Character
					if not char then return end
					if hit and hit:IsDescendantOf(char) then
						beginShardSequence()
					end
				end)
			end

		else
			-- Already completed: clean up cutscene pieces
			local kyroCut = CurrentChunk.Model.Essentials:FindFirstChild("Kyro_R1")
			if kyroCut then kyroCut:Destroy() end
		end
		
    end,
    ["Load_CatchCare"] = function(CurrentChunk)
		local NPCFolder = CurrentChunk and CurrentChunk.Model and CurrentChunk.Model:FindFirstChild("NPCs")
		if not NPCFolder then return end

		local function SetupHealer(npcName: string, greetText: string, doneText: string)
			local npc = NPCFolder:FindFirstChild(npcName)
			if not npc then return end
			NPC:Setup(npc, function()
				UI.TopBar:Hide()
				Say:Say(npcName, true, { { Text = greetText, Emotion = "Happy" } }, npc)
				local ok = false
				local success, result = pcall(function()
					return Events.Request:InvokeServer({"HealParty"})
				end)
				ok = success and result == true
				if ok then
					Say:Say(npcName, true, { { Text = doneText, Emotion = "Happy" } }, npc)
				else
					Say:Say(npcName, true, { { Text = "Hmm, that didn't work. Come back when you're nearby.", Emotion = "Confused" } }, npc)
				end
				UI.TopBar:Show()
			end)
		end

		SetupHealer("Camille", "Hey! Let me heal those creatures for you.", "Andddd... All done!")
		SetupHealer("Miranda", "Oh hi! You need your creatures healed? Allow me!", "Done! Take care of them!")

		local shopController = UI and UI.CatchCareShop

		local function SetupShopKeeper(npcName: string)
			local npc = NPCFolder:FindFirstChild(npcName)
			if not npc then
				return
			end
			NPC:Setup(npc, function()
				UI.TopBar:Hide()
				Say:Say(npcName, false, {
					{ Text = "Oh, sup. What can I do for ya?", Emotion = "Happy" },
				}, npc)

				local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
				local sayFrame = pg and pg:FindFirstChild("GameUI")
				sayFrame = sayFrame and sayFrame:FindFirstChild("Say")
				local choiceFrame = sayFrame and sayFrame:FindFirstChild("Choice")
				local yesBtn = choiceFrame and choiceFrame:FindFirstChild("Yes")
				local noBtn = choiceFrame and choiceFrame:FindFirstChild("No")
				local yesLabel = yesBtn and yesBtn:FindFirstChild("Label")
				local noLabel = noBtn and noBtn:FindFirstChild("Label")
				local originalYes = yesLabel and yesLabel:IsA("TextLabel") and yesLabel.Text or nil
				local originalNo = noLabel and noLabel:IsA("TextLabel") and noLabel.Text or nil
				if yesLabel and yesLabel:IsA("TextLabel") then
					yesLabel.Text = "View shop"
				elseif yesBtn and yesBtn:IsA("TextButton") then
					yesBtn.Text = "View shop"
				end
				if noLabel and noLabel:IsA("TextLabel") then
					noLabel.Text = "Nevermind"
				elseif noBtn and noBtn:IsA("TextButton") then
					noBtn.Text = "Nevermind"
				end

				local wantsShop = Say:YieldChoice()

				if originalYes and yesLabel and yesLabel:IsA("TextLabel") then
					yesLabel.Text = originalYes
				elseif originalYes and yesBtn and yesBtn:IsA("TextButton") then
					yesBtn.Text = originalYes
				end
				if originalNo and noLabel and noLabel:IsA("TextLabel") then
					noLabel.Text = originalNo
				elseif originalNo and noBtn and noBtn:IsA("TextButton") then
					noBtn.Text = originalNo
				end

				Say:Exit()

				local function restoreState()
					UI.TopBar:SetSuppressed(false)
					UI.TopBar:Show()
					CharacterFunctions:SetSuppressed(false)
					CharacterFunctions:CanMove(true)
				end

				if wantsShop ~= true then
					Say:Say(npcName, true, {
						{ Text = "No problem! Come back anytime.", Emotion = "Happy" },
					}, npc)
					restoreState()
					return
				end

				UI.TopBar:SetSuppressed(true)
				CharacterFunctions:SetSuppressed(true)
				CharacterFunctions:CanMove(false)

				local opened = shopController and shopController:Open(function()
					restoreState()
				end)

				if opened ~= true then
					restoreState()
					Say:Say(npcName, true, {
						{ Text = "Hm... register's acting up. Try again in a bit.", Emotion = "Confused" },
					}, npc)
				end
			end)
		end

		SetupShopKeeper("Damian")
	end,
	["Load_Chunk2"] = function(CurrentChunk)
		DBG:print("[ChunkEvents] Load_Chunk2 invoked")
		-- Healer Tom NPC (LOS hint + click-to-heal) same as Chunk1
		local NPCFolder = CurrentChunk and CurrentChunk.Model and CurrentChunk.Model:FindFirstChild("NPCs")
		local Healer = NPCFolder and NPCFolder:FindFirstChild("Healer Tom")
		if Healer then
			-- One-time line-of-sight hint
			LOS:SetupOnceTrigger(Healer, {
				MaxDistance = 24,
				FOV = 10,
				UniqueKey = "HealerTom_LOS_Chunk2",
				OnTrigger = function(npcModel, npcHRP)
					UI.TopBar:Hide()
					Say:Say("Healer Tom", true, {
						{ Text = "Oh, it's me again! Come to me if you need healing.", Emotion = "Happy" },
					}, npcHRP or npcModel)
					UI.TopBar:Show()
					local CharacterFunctions = require(script.Parent.CharacterFunctions)
					pcall(function()
						CharacterFunctions:SetSuppressed(false)
						CharacterFunctions:CanMove(true)
					end)
				end,
			})
			-- Click interaction: request heal
			NPC:Setup(Healer, function()
				UI.TopBar:Hide()
				Say:Say("Healer Tom", true, {
					{ Text = "Here, let me heal your creatures for you!", Emotion = "Talking" },
				}, Healer)
				local ok = false
				local success, result = pcall(function()
					return Events.Request:InvokeServer({"HealParty"})
				end)
				ok = success and result == true
				if ok then
					Say:Say("Healer Tom", true, {
						{ Text = "Okay, all done! Happy hunting!", Emotion = "Happy" },
					}, Healer)
					UI.TopBar:Show()
					local CharacterFunctions = require(script.Parent.CharacterFunctions)
					pcall(function()
						CharacterFunctions:SetSuppressed(false)
						CharacterFunctions:CanMove(true)
					end)
				else
					Say:Say("Healer Tom", true, {
						{ Text = "Hmm, that didn't work. Come back when you're nearby.", Emotion = "Confused" },
					}, Healer)
					UI.TopBar:Show()

					pcall(function()
						CharacterFunctions:SetSuppressed(false)
						CharacterFunctions:CanMove(true)
					end)
				end
			end)
		end

		-- Register where to relocate after blackout in this chunk
		CurrentChunk.BlackoutRelocate = {
			Type = "HealerTom",
			ChunkName = "Chunk2",
			NPCTargetName = "Healer Tom",
		}

		-- Ayla Route 2 cutscene and search sequence
		local Essentials = CurrentChunk and CurrentChunk.Essentials
		local Cutscene = Essentials and Essentials:FindFirstChild("Cutscene")
		if not (Essentials and Cutscene) then
			return
		end

		-- One-time gate: destroy cutscene rig if already completed
		do
			local CD = ClientData:Get()
			if CD and CD.Events and CD.Events.AYLA_ROUTE2_DONE == true then
				pcall(function() Cutscene:Destroy() end)
				return
			end
		end

		local function getPart(name: string): BasePart?
			local p = Cutscene:FindFirstChild(name)
			return (p and p:IsA("BasePart")) and p or nil
		end
		local function getNPC(name: string): Model?
			local m = Cutscene:FindFirstChild(name)
			return (m and m:IsA("Model")) and m or nil
		end
		local function getHRP(m: Model?): BasePart?
			return m and (m:FindFirstChild("HumanoidRootPart") :: BasePart?) or nil
		end
		local function setModelVisible(m: Model?, visible: boolean)
			if not m then return end
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Transparency = visible and 0 or 1
					d.CanCollide = visible
				elseif d:IsA("Decal") or d:IsA("Texture") then
					d.Transparency = visible and 0 or 1
				end
			end
		end
		local function placeModelAt(m: Model?, p: BasePart?)
			local hrp = getHRP(m)
			if hrp and p then
				hrp.CFrame = p.CFrame
			end
		end
		local function playCreatureIdle(model: Model?)
			if not model then return end
			-- Find or create animator (check Humanoid first, then AnimationController)
			local animator: Animator? = nil
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid then
				animator = humanoid:FindFirstChildOfClass("Animator")
				if not animator then
					animator = Instance.new("Animator")
					animator.Parent = humanoid
				end
			else
				local animController = model:FindFirstChildOfClass("AnimationController")
				if not animController then
					animController = Instance.new("AnimationController")
					animController.Parent = model
				end
				animator = animController:FindFirstChildOfClass("Animator")
				if not animator then
					animator = Instance.new("Animator")
					animator.Parent = animController
				end
			end
			-- Find Idle animation (check Animations folder first, then direct child)
			local animFolder = model:FindFirstChild("Animations")
			local idle = animFolder and animFolder:FindFirstChild("Idle") or model:FindFirstChild("Idle")
			if idle and idle:IsA("Animation") and animator then
				local ok, track = pcall(function()
					return animator:LoadAnimation(idle)
				end)
				if ok and track then
					track.Priority = Enum.AnimationPriority.Idle
					track.Looped = true
					pcall(function() track:Play() end)
				end
			end
		end
		local function playerHRP(): BasePart?
			local player = game:GetService("Players").LocalPlayer
			local character = player and (player.Character or player.CharacterAdded:Wait())
			return character and character:FindFirstChild("HumanoidRootPart") or nil
		end
		local function playerName(): string
			local CD = ClientData:Get()
			return (CD and CD.Nickname) or (game:GetService("Players").LocalPlayer and game:GetService("Players").LocalPlayer.Name) or "Player"
		end

		-- Shared dialogue lines to avoid duplication
		local Lines = {
			AylaFoundAva = { { Text = "There you are!! I was so worried, Ava!", Emotion = "Happy" } },
		}
		
		-- Helpers to reduce duplication within this cutscene
		local function frameGroupShot(AylaModel: Model?, BryanModel: Model?, EdwardModel: Model?, camMgrOpt)
			local pHRP = playerHRP()
			local aHRP = getHRP(AylaModel)
			local bHRP = getHRP(BryanModel)
			local eHRP = getHRP(EdwardModel)
			local points = {}
			if pHRP then table.insert(points, pHRP.Position) end
			if aHRP then table.insert(points, aHRP.Position) end
			if bHRP then table.insert(points, bHRP.Position) end
			if eHRP then table.insert(points, eHRP.Position) end
			if #points >= 2 then
				local center = Vector3.new(0, 0, 0)
				for _, v in ipairs(points) do center += v end
				center /= #points
				local maxR = 0
				for _, v in ipairs(points) do
					local d = (Vector3.new(v.X, 0, v.Z) - Vector3.new(center.X, 0, center.Z)).Magnitude
					if d > maxR then maxR = d end
				end
				local facing = (pHRP and pHRP.CFrame.LookVector) or Vector3.new(0, 0, -1)
				local backDist = math.max(12, maxR * 1.8)
				local height = math.max(6, maxR * 0.7)
				local camPos = center - facing * backDist + Vector3.new(0, height, 0)
				local cf = CFrame.lookAt(camPos, center)
				local camShot = camMgrOpt or CameraManager.new()
				camShot:TransitionTo(cf, 0.6, 65, nil)
			end
		end
		local function getFixedSpecFor(npc: Model?): {any}
			local name = npc and npc.Name or ""
			if name == "Grunt Bryan" then
				return {
					{ Name = "Frulli Frulla", Level = 6 },
					{ Name = "Doggolino", Level = 5 },
				}
			elseif name == "Grunt Edward" then
				return {
					{ Name = "Burbaloni Lulliloli", Level = 7 },
					{ Name = "Timmy Cheddar", Level = 6 },
				}
			end
			return { { Name = "Frulli Frulla", Level = 5 } }
		end
		local function startTrainerBattle(npc: Model?): boolean
			local tname = npc and npc.Name or "Trainer"
			local spec = getFixedSpecFor(npc)
			pcall(function()
				local TrainerIntroController = require(script.Parent.TrainerIntroController)
				TrainerIntroController:PrepareFromNPC(npc)
			end)
			local ok = pcall(function()
				Events.Request:InvokeServer({"StartBattle", "Trainer", {
					TrainerName = tname,
					TrainerSpec = spec,
					TrainerId = tname,
				}})
			end)
			if not ok then return false end
			local done = false
			local ec
			ec = Events.Communicate.OnClientEvent:Connect(function(ev)
				if ev ~= "BattleOver" then return end
				if ec then ec:Disconnect() end
				local rc
				rc = require(script.Parent.RelocationSignals).OnPostBattleRelocated(function()
					done = true
					if rc then rc:Disconnect() end
				end)
			end)
			local t0 = os.clock()
			while not done and (os.clock() - t0) < 90 do task.wait(0.25) end
			if ec then ec:Disconnect() end
			return done
		end
		local function moveAwayNPC(npc: Model?)
			local hrp = getHRP(npc) 
			local hum = npc and npc:FindFirstChildOfClass("Humanoid")
			if not (hrp and hum) then return end
			MoveTo.MoveHumanoidToTarget(hum, hrp, Vector3.new(142.698, 12.114, -1024.194), { minWalkSpeed = 18, timeout = 5, arriveRadius = 1.5, retryInterval = 0.3 })
		end
		local function runAylaConfrontationFlow(pnameLocal: string, AylaModel: Model?, BryanModel: Model?, EdwardModel: Model?, connsTab: {RBXScriptConnection}, camMgrOpt)
			CharacterFunctions:SetSuppressed(true)
			CharacterFunctions:CanMove(false)
			UI.TopBar:Hide()
			UIFunctions:Transition(true)
			task.wait(1.5)
			local NPCUtil = require(script.Parent.NPC)
			if AylaModel then NPCUtil:StopFollowingPlayer(AylaModel) end
			local ppb = getPart("PlayerPlacement_Before")
			local apb = getPart("AylaPlacement_Before")
			local phrpNow = playerHRP()
			if phrpNow and ppb then
				phrpNow.CFrame = ppb.CFrame
			end
			placeModelAt(AylaModel, apb)
			UIFunctions:Transition(false)
			-- Mark that confrontation phase has begun (used for rejoin restore)
			setClientEventFlag("AYLA_ROUTE2_CONFRONT", true)
			-- Two-shot on player and Ayla
			do
				local camFront = camMgrOpt or CameraManager.new()
				local pHRP = playerHRP()
				local aHRP = getHRP(AylaModel)
				if pHRP and aHRP then
					local center = (pHRP.Position + aHRP.Position) / 2
					local forward = pHRP.CFrame.LookVector
					local cameraPos = center - (forward * 8) + Vector3.new(0, 3, 0)
					local cf = CFrame.lookAt(cameraPos, center)
					camFront:TransitionTo(cf, 0.6, 60, nil)
				end
			end
			task.wait(0.5)
			Say:Say("Ayla", true, Lines.AylaFoundAva)
			-- Face after-placements
			local ppa = getPart("PlayerPlacement_After")
			local apa = getPart("AylaPlacement_After")
			local phrp3 = playerHRP()
			if phrp3 and ppa then
				phrp3.CFrame = CFrame.new(phrp3.Position, Vector3.new(ppa.Position.X, phrp3.Position.Y, ppa.Position.Z))
			end
			placeModelAt(AylaModel, apa)
			-- Place Team Rift members and frame group
			placeModelAt(BryanModel, getPart("BryanPlacement"))
			placeModelAt(EdwardModel, getPart("EdwardPlacement"))
			frameGroupShot(AylaModel, BryanModel, EdwardModel, camMgrOpt)
			-- Rift intro lines
			Say:Say("Team Rift Member Bryan", true, {
				{ Text = "Step away, kids.", Emotion = "Angry" },
				{ Text = "It seems this Avocadini Guffo has been in contact with the shard.", Emotion = "Talking" },
				{ Text = "You two wouldn't happen to know where it got this energy, would you?", Emotion = "Talking" },
				{ Text = "Silence, huh? No matter—we'll take this creature with us.", Emotion = "Smug" },
			}, getHRP(BryanModel))
			Say:Say("Ayla", true, {
				{ Text = (pnameLocal or "Player") .. ", I don't have any brainrots... what do we do?", Emotion = "Sad" },
				{ Text = "Wait—you're going to help? I believe in you!", Emotion = "Happy" },
			}, getHRP(AylaModel))
			-- Battles
			startTrainerBattle(BryanModel)
			Say:Say("Team Rift Member Edward", true, {
				{ Text = "There's no way you beat Bryan...", Emotion = "Angry" },
				{ Text = "I guess I'll just have to stop you.", Emotion = "Angry" },
			}, getHRP(EdwardModel))
			startTrainerBattle(EdwardModel)
			-- Wrap-up
			Say:Say("Team Rift Member Edward", true, {
				{ Text = "Guess I humbled myself...", Emotion = "Sad" },
			}, getHRP(EdwardModel))
			Say:Say("Team Rift Member Bryan", true, {
				{ Text = "We said you'd keep it; we're leaving.", Emotion = "Neutral" },
				{ Text = "Boss will be mad... but we'll deal with it. Anyone can be strong.", Emotion = "Talking" },
			}, getHRP(BryanModel))
			task.spawn(function()
				moveAwayNPC(BryanModel); moveAwayNPC(EdwardModel)
			end)
			task.wait(1.5)
			Say:Say("Ayla", true, {
				{ Text = "Woah! I can't believe you beat both of them!", Emotion = "Excited" },
				{ Text = "Thank you so much, " .. (pnameLocal or "Player") .. "! Because of you, I got Ava back!", Emotion = "Happy" },
				{ Text = "I'll meet you in Cresamore Town—see how strong Ava is and battle me there!", Emotion = "Happy" },
				{ Text = "See you soon!", Emotion = "Happy" },
			}, getHRP(AylaModel))
			UIFunctions:Transition(true)
			setClientEventFlag("AYLA_ROUTE2_DONE", true)
			-- Done; cleanup after fade
			task.delay(0.75, function()
				pcall(function() Cutscene:Destroy() end)
			end)
			task.delay(2, function()
				UIFunctions:Transition(false)
				UI.TopBar:Show()
			end)
		end
		-- (restoreRoute2State is defined later, after controller class)

		-- References
		local Ayla: Model? = getNPC("Ayla")
		local Avocadini: Model? = Cutscene:FindFirstChild("AvocadiniGuffo")
		local Bryan: Model? = getNPC("Grunt Bryan")
		local Edward: Model? = getNPC("Grunt Edward")

		-- Stage Ayla and hide Avocadini at load
		placeModelAt(Ayla, getPart("AylaFirstPlacement"))
		setModelVisible(Avocadini, false)

		-- Connection cleanup on unload
		local conns: {RBXScriptConnection} = {}
		if CurrentChunk and CurrentChunk.Model then
			local c = CurrentChunk.Model.AncestryChanged:Connect(function(_, parent)
				if not parent then
					for _, cc in ipairs(conns) do if cc.Connected then cc:Disconnect() end end
				end
			end)
			table.insert(conns, c)
		end

		-- Controller to manage Ayla Route 2 search flow (OOP-style)
		type AylaSearchControllerType = {
			Ayla: Model?,
			Avocadini: Model?,
			Bryan: Model?,
			Edward: Model?,
			conns: {RBXScriptConnection},
			pnameLocal: string,
			start: (self: any) -> (),
			_bindChatter: (self: any) -> (),
			_bindISeeHer: (self: any) -> (),
			_bindFound: (self: any) -> (),
		}
		
		local AylaSearchController = {}
		AylaSearchController.__index = AylaSearchController
		
		function AylaSearchController.new(Ayla: Model?, Avocadini: Model?, Bryan: Model?, Edward: Model?, connsTab: {RBXScriptConnection}): AylaSearchControllerType
			local self = setmetatable({}, AylaSearchController)
			self.Ayla = Ayla
			self.Avocadini = Avocadini
			self.Bryan = Bryan
			self.Edward = Edward
			self.conns = connsTab
			self.pnameLocal = playerName()
			return (self :: any) :: AylaSearchControllerType
		end
		
		function AylaSearchController:start()
			local NPCUtil = require(script.Parent.NPC)
			if self.Ayla then
				NPCUtil:StartFollowingPlayer(self.Ayla, { stopDistance = 4, maxTeleportDistance = 35, runSpeed = 20 })
			end
			setClientEventFlag("AYLA_ROUTE2_SEARCH_ACTIVE", true)
			
			CharacterFunctions:SetSuppressed(false)
			CharacterFunctions:CanMove(true)
			UI.TopBar:Show()
			
			setModelVisible(self.Avocadini, true)
			placeModelAt(self.Avocadini, getPart("CreaturePlacement"))
			playCreatureIdle(self.Avocadini)
			
			self:_bindChatter()
			self:_bindISeeHer()
			self:_bindFound()
		end
		
		function AylaSearchController:_bindChatter()
			local searchLines = {
				{ { Text = "Looks like there's nothing here...", Emotion = "Neutral" } },
				{ { Text = "Nothing here at all...", Emotion = "Neutral" } },
				{ { Text = "I think I heard something!", Emotion = "Excited" } },
				{ { Text = "I hope Ava is doing okay...", Emotion = "Sad" } },
				{ { Text = "I really appreciate the help, " .. (self.pnameLocal or "Player"), Emotion = "Happy" } },
				{ { Text = "You're the best—let's keep searching!", Emotion = "Happy" } },
			}
			local function bindOneShot(name: string, idx: number)
				local p = getPart(name)
				if not p then return end
				local fired = false
				local c; c = p.Touched:Connect(function(hit2)
					local phrp2 = playerHRP()
					if fired or not phrp2 or hit2 ~= phrp2 then return end
					fired = true
					Say:Say("Ayla", true, searchLines[idx], getHRP(self.Ayla))
					if c then c:Disconnect() end
				end)
				table.insert(self.conns, c)
			end
			bindOneShot("AylaNothingHere1", 1)
			bindOneShot("AylaNothingHere2", 2)
			bindOneShot("AylaNothingHere3", 3)
			bindOneShot("AylaNothingHere4", 4)
		end
		
		function AylaSearchController:_bindISeeHer()
			local p = getPart("AylaIThinkISeeHer")
			if not p then return end
			local fired = false
			local c; c = p.Touched:Connect(function(hit3)
				local phrp2 = playerHRP()
				if fired or not phrp2 or hit3 ~= phrp2 then return end
				fired = true
				Say:Say("Ayla", true, { { Text = (self.pnameLocal or "Player") .. ", I think I see her!", Emotion = "Excited" } }, getHRP(self.Ayla))
				if c then c:Disconnect() end
			end)
			table.insert(self.conns, c)
		end
		
		function AylaSearchController:_bindFound()
			local p = getPart("AylaFoundHer")
			if not p then return end
			local fired = false
			local c; c = p.Touched:Connect(function(hit4)
				local phrp2 = playerHRP()
				if fired or not phrp2 or hit4 ~= phrp2 then return end
				fired = true
				
				setClientEventFlag("AYLA_ROUTE2_SEARCH_ACTIVE", false)

				runAylaConfrontationFlow(self.pnameLocal, self.Ayla, self.Bryan, self.Edward, self.conns, nil)
				
				if c then c:Disconnect() end
			end)
			table.insert(self.conns, c)
		end
		
		-- Define restoration helper after controller to avoid forward reference issues
		local function restoreRoute2State(AylaModel: Model?, AvocadiniModel: Model?, BryanModel: Model?, EdwardModel: Model?, connsTab: {RBXScriptConnection})
			local cd = ClientData:Get()
			local ev = cd and cd.Events
			if not ev then return end
			if ev.AYLA_ROUTE2_DONE == true then
				pcall(function() Cutscene:Destroy() end)
				return
			end
			if ev.AYLA_ROUTE2_CONFRONT == true then
				runAylaConfrontationFlow(playerName(), AylaModel, BryanModel, EdwardModel, connsTab, nil)
				return
			end
			if ev.AYLA_ROUTE2_SEARCH_ACTIVE == true then
				local controller = AylaSearchController.new(AylaModel, AvocadiniModel, BryanModel, EdwardModel, connsTab)
				controller:start()
				return
			end
		end
		-- Restore any pending Route 2 state on (re)join
		restoreRoute2State(Ayla, Avocadini, Bryan, Edward, conns)
		-- Start cutscene when player touches AylaCutsceneTrigger
		local trigger = getPart("AylaCutsceneTrigger")
		if trigger then
			local started = false
			local tConn
			tConn = trigger.Touched:Connect(function(hit)
				local phrp = playerHRP()
				if started or not phrp or hit ~= phrp then return end
				started = true

				CharacterFunctions:SetSuppressed(true)
				CharacterFunctions:CanMove(false)
				UI.TopBar:Hide()
				local camMgr = CameraManager.new()
				pcall(function() camMgr:Reset() end)

				getHRP(Ayla).Anchored = false

				Say:Say("Ayla", true, {
					{ Text = "Ava!!! Where are you!! someone help!!", Emotion = "Angry" },
				}, getHRP(Ayla))

				-- Walk Ayla to player
				if Ayla and phrp then
					local aylaHum = Ayla:FindFirstChildOfClass("Humanoid")
					local aylaHRP = getHRP(Ayla)
					local walkTrack = nil
					MoveTo.MoveHumanoidToTarget(aylaHum, aylaHRP, phrp.Position, {
						minWalkSpeed = 16,
						timeout = 3.5,
						arriveRadius = 5,
						retryInterval = 0.35,
						onStart = function()
							if not aylaHum then return end
							local animator = aylaHum:FindFirstChildOfClass("Animator")
							if not animator then
								animator = Instance.new("Animator")
								animator.Parent = aylaHum
							end
							local anim = Instance.new("Animation")
							anim.AnimationId = "rbxassetid://120866625087275"
							local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
							if ok and track then
								walkTrack = track
								walkTrack.Priority = Enum.AnimationPriority.Movement
								walkTrack.Looped = true
								pcall(function() walkTrack:Play(0.1) end)
							end
						end,
						onComplete = function()
							if walkTrack then
								pcall(function() walkTrack:Stop(0.15) end)
								walkTrack = nil
							end
						end,
					})
				end

				local pname = playerName()
				Say:Say("Ayla", true, {
					{ Text = "Hey you! I need help finding my creature; I've been calling her for ages and can't find her.", Emotion = "Talking" },
					{ Text = "There's an area near the end of this route I haven't checked.", Emotion = "Talking" },
					{ Text = "My creature is Avocadini Guffo—Ava. She's a green owl, super sweet.", Emotion = "Happy" },
					{ Text = "Route 2 is pretty busy with trainers; I couldn't get past after I lost her...", Emotion = "Sad" },
					{ Text = "If you help me out, I’ll have to pay you back!", Emotion = "Happy" },
					{ Text = "Before we continue—what's your name?", Emotion = "Talking" },
					{ Text = "Oh your name's " .. pname .. "? Awesome name!", Emotion = "Happy" },
					{ Text = "What's your story, " .. pname .. "?", Emotion = "Talking" },
				}, getHRP(Ayla))

				local UIFunctions = require(script.Parent.Parent.UI.UIFunctions)
				UIFunctions:Transition(true)
				task.wait(1)
				Say:Say("", true, {
					{ Text = "Moments later...", Emotion = "Confused" },
				})
	
				task.wait(0.5)
				UIFunctions:Transition(false)
				Say:Say("Ayla", true, {
					{ Text = "Woah... you said someone fought you because of a shard?", Emotion = "Confused" },
					{ Text = "I caught Ava near Route 5; there was a weird shard there—gave me creepy vibes.", Emotion = "Thinking" },
					{ Text = "Maybe that shard is related to what Team Rift was talking about.", Emotion = "Thinking" },
					{ Text = "Ava was acting strange near it... I hope she's okay.", Emotion = "Sad" },
					{ Text = "We should start searching!", Emotion = "Excited" },
				}, getHRP(Ayla))
	

				-- Begin search phase via controller (maintainable)
				do
					local controller = AylaSearchController.new(Ayla, Avocadini, Bryan, Edward, conns)
					controller.pnameLocal = pname
					controller:start()
				end
				
				-- Controller sets up all search bindings for the search phase
				local pnameLocal = pname

				-- Search chatter and triggers bound by AylaSearchController

				-- "I think I see her!" trigger handled by AylaSearchController

				-- Found trigger (handled by AylaSearchController; rejoin handled via restoreRoute2State)
			end)
			table.insert(conns, tConn)
		end
	end,
	["Load_Chunk3"] = function(CurrentChunk)
		local CD = ClientData:Get()

		-- Arm Old Man Franklin trigger 
		do
			local events = (CD and CD.Events) or {}
			if events.MET_MAN_ROUTE_3 ~= true then
				local essentials = CurrentChunk and CurrentChunk.Model and CurrentChunk.Model.Essentials
				local cutscene = essentials and essentials:FindFirstChild("Cutscene")
				local trigger = cutscene and cutscene:FindFirstChild("OldManFranklinTrigger")
				local oldmanfranklin = cutscene and cutscene:FindFirstChild("Old Man Franklin")
				local shark = cutscene and cutscene:FindFirstChild("Shark")
				local sharkanim = shark and shark:FindFirstChild("Animation")
				local sharkhumanoid = shark and shark:FindFirstChildOfClass("Humanoid")

				if trigger and trigger:IsA("BasePart") then
					warn("MET_MAN_ROUTE_3 is false, running")
					if trigger:GetAttribute("FranklinArmed") == true then
						DBG:print("[Route3] Franklin trigger already armed - skipping duplicate")
					else
						trigger:SetAttribute("FranklinArmed", true)
						DBG:print("[Route3] MET_MAN_ROUTE_3 = false; arming OldManFranklinTrigger (early)")
						local fired = false
						local conn
						conn = trigger.Touched:Connect(function(hit)
							local player = game:GetService("Players").LocalPlayer
							local character = player and (player.Character or player.CharacterAdded:Wait())
							local hrp = character and character:FindFirstChild("HumanoidRootPart")
							if fired or not hrp or hit ~= hrp then return end
							fired = true
							DBG:print("[Route3] OldManFranklinTrigger touched - starting cutscene")

							-- Begin Franklin cutscene
							UI.TopBar:SetSuppressed(true); UI.TopBar:Hide()
							CharacterFunctions:SetSuppressed(true); CharacterFunctions:CanMove(false)

							-- Walk player to scenic points
							do
								local one = cutscene and cutscene:FindFirstChild("PlayerWalkToONE")
								local two = cutscene and cutscene:FindFirstChild("PlayerWalkToTWO")
								local phrp2: BasePart? = character and character:FindFirstChild("HumanoidRootPart")
								if phrp2 and one and one:IsA("BasePart") then
									DBG:print("[Route3] Walking player to PlayerWalkToONE")
									local t1 = Vector3.new(one.Position.X, phrp2.Position.Y, one.Position.Z)
									pcall(function()
										MoveTo.MoveToTarget(t1, { minWalkSpeed = 14, timeout = 3.0, preserveFacing = true, arriveRadius = 1.5, retryInterval = 0.35, delayAfter = 0.05 })
									end)
								end
								if phrp2 and two and two:IsA("BasePart") then
									DBG:print("[Route3] Walking player to PlayerWalkToTWO")
									local t2 = Vector3.new(two.Position.X, phrp2.Position.Y, two.Position.Z)
									pcall(function()
										MoveTo.MoveToTarget(t2, { minWalkSpeed = 14, timeout = 3.0, preserveFacing = true, arriveRadius = 1.5, retryInterval = 0.35, delayAfter = 0.05 })
									end)
								end
							end

							-- Franklin intro
							Say:Say("Franklin", true, {
								{ Text = "Hey there, sonny! Name’s Franklin. I was a builder in this town back in the day.", Emotion = "Talking" },
							}, oldmanfranklin)
							Say:Say("Franklin", true, {
								{ Text = "I always come by to greet newcomers. Cresamore was the greatest place for me — no other town ever felt like home quite like this one.", Emotion = "Happy" },
							}, oldmanfranklin)
							Say:Say("Franklin", true, {
								{ Text = "You know, legends say a legendary Brainrot used to roam these waters. They called it Tralalero Tralala.", Emotion = "Thinking" },
							}, oldmanfranklin)
							Say:Say("Franklin", true, {
								{ Text = "But that’s just old folk talk… I’ve never seen it myself.", Emotion = "Sad" },
							}, oldmanfranklin)

							-- Start rain
							pcall(function()
								local rain = cutscene and cutscene:FindFirstChild("Rain")
								local particles = rain and rain:FindFirstChild("Particles")
								if particles and particles:IsA("ParticleEmitter") then particles.Enabled = true end
							end)

							-- Move camera to scenic CameraPart
							pcall(function()
								local cameraPart = cutscene and cutscene:FindFirstChild("CameraPart")
								local cam = workspace.CurrentCamera
								if cameraPart and cameraPart:IsA("BasePart") and cam then
									cam.CameraType = Enum.CameraType.Scriptable
									local tween = TweenService:Create(cam, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
										CFrame = cameraPart.CFrame,
									})
									tween:Play()
								end
							end)

							-- Play shark animation
							local sharkTrack: AnimationTrack? = nil
							pcall(function()
								if sharkhumanoid and sharkanim and sharkanim:IsA("Animation") then
									local animator = sharkhumanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", sharkhumanoid)
									local ok, tr = pcall(function() return animator:LoadAnimation(sharkanim) end)
									if ok and tr then
										sharkTrack = tr
										pcall(function() sharkTrack:Play(0.1) end)
									end
								end
							end)

							repeat
								task.wait(0.01)
							until sharkTrack and sharkTrack.TimePosition >= 0.01
							
							Say:Say("Franklin", false, {
								{ Text = "My goodness! Son, do you see that?! That’s him! The legend was true!", Emotion = "Excited" },
							}, oldmanfranklin)
							task.wait(3.6)
							Say:Exit()
							Say:Say("Franklin", false, {
								{ Text = "By the waters of Cresamore… never in my life did I think I’d see that Brainrot with my own eyes!", Emotion = "Happy" },
							}, oldmanfranklin)
							task.wait(3.7)
							Say:Exit()

							local rain = cutscene and cutscene:FindFirstChild("Rain")
							local particles = rain and rain:FindFirstChild("Particles")
							if particles and particles:IsA("ParticleEmitter") then particles.Enabled = false end
							workspace.CurrentCamera.CameraType = Enum.CameraType.Custom


							-- Back to manual
							Say:Say("Franklin", true, {
								{ Text = "Surely this has something to do with you! You must radiate a light that only Brainrots can sense — you shine bright to them!", Emotion = "Talking" },
							}, oldmanfranklin)
							Say:Say("Franklin", true, {
								{ Text = "You’ll be a fantastic trainer, I can already tell.", Emotion = "Happy" },
							}, oldmanfranklin)
							Say:Say("Franklin", true, {
								{ Text = "For your journeys, I want to give you something. You’re planning to challenge the Grass Gym in Asterden, right?", Emotion = "Talking" },
							}, oldmanfranklin)
							Say:Say("Franklin", true, {
								{ Text = "Take these potions. They aren’t much, but they’ll surely help you.", Emotion = "Happy" },
							}, oldmanfranklin)

							do
								local pname = (ClientData:Get() and ClientData:Get().Nickname) or (game.Players.LocalPlayer and game.Players.LocalPlayer.Name) or "Player"
								Say:Say("", true, { { Text = pname .. " obtained 3 Potions!", Emotion = "Happy" }, })
							end

							-- Franklin farewell
							Say:Say("Franklin", true, {
								{ Text = "It was a pleasure meeting you, son. If you ever need advice, my house is the last one up the hill!", Emotion = "Smug" },
								{ Text = "And if you ever find Tralalero Tralala again, please — come show me. I’d love to see it up close.", Emotion = "Happy" },
							}, oldmanfranklin)

							UIFunctions:Transition(true)

							if shark then shark:Destroy() end
							if oldmanfranklin then oldmanfranklin:Destroy() end
		
							-- Server authoritative event set (grants items server-side)
							pcall(function()
								local Events = game:GetService("ReplicatedStorage"):WaitForChild("Events")
								if Events and Events.Request then
									Events.Request:InvokeServer({"SetEvent", "MET_MAN_ROUTE_3", true})
								end
							end)
							setClientEventFlag("MET_MAN_ROUTE_3", true)

							task.wait(1.0)
							UIFunctions:Transition(false)

							UI.TopBar:SetSuppressed(false); UI.TopBar:Show()
							CharacterFunctions:SetSuppressed(false); CharacterFunctions:CanMove(true)

							if conn then conn:Disconnect() end
						end)
					end
				else
					DBG:print("[Route3] OldManFranklinTrigger missing; cannot arm")
				end
			else
				local CutsceneFolder = CurrentChunk.Model.Essentials.Cutscene
				CutsceneFolder:FindFirstChild("Old Man Franklin"):Destroy()
			end
		end

		if CD and CD.Events and CD.Events.MET_KYRO_ROUTE_3 ~= true then
			print("We've not met kyro in route 3 yet, running cutscene")
			-- Mark Route3 intro as a cutscene so TopBar stays hidden across the battle
			pcall(function()
				local CutsceneRegistry = require(script.Parent.CutsceneRegistry)
				CutsceneRegistry:Start("Route3_KyroIntro")
			end)
			local nickname = (CD and CD.Nickname) or "Trainer"
			UI.TopBar:Hide()
			UI.TopBar:SetSuppressed(true)
			CharacterFunctions:CanMove(false)
			CharacterFunctions:SetSuppressed(true)
			local CutsceneFolder = CurrentChunk.Model.Essentials.Cutscene

			task.wait(0.5)

			local kyroHRP = CutsceneFolder.Kyro:FindFirstChild("HumanoidRootPart")
			local character = game.Players.LocalPlayer.Character
			local phrp: BasePart? = character and character:FindFirstChild("HumanoidRootPart")
			local look = kyroHRP.CFrame.LookVector
			local target = Vector3.new(kyroHRP.Position.X, phrp.Position.Y, kyroHRP.Position.Z) - (look * -4)
			Say:Say("Kyro", true, {
				{ Text = "A legendary huh.", Emotion = "Thinking" },
				{ Text = "Interesting...", Emotion = "Thinking" },
			})

			local aylaHRP: BasePart? = CutsceneFolder.Ayla:FindFirstChild("HumanoidRootPart")
			-- Ayla greets and gives shoes (Say will auto-face player)
			Say:Say("Ayla", true, {
				{ Text = nickname .. "! There you are.", Emotion = "Happy" },
				{ Text = "Before we have our battle, I wanted to help you out and give you these running shoes!", Emotion = "Excited" },
			}, CutsceneFolder.Ayla)

			Say:Say("", true, {
				{ Text = nickname .. " obtained the running shoes!", Emotion = "Happy" },
			})			

			-- Ayla thanks player (Say auto-faces player)
			Say:Say("Ayla", true, {
				{ Text = "I really appreciate what you did back there — thank you so much for helping me get Ava back.", Emotion = "Happy" },
			}, CutsceneFolder.Ayla)

			local kyHumanoid = CutsceneFolder.Kyro:FindFirstChildOfClass("Humanoid")
			if kyHumanoid and kyroHRP and phrp then
				local toPlayer = phrp.Position - kyroHRP.Position
				local dir = (toPlayer.Magnitude > 0.001) and toPlayer.Unit or Vector3.new(0, 0, -1)
				local stopPos = Vector3.new(phrp.Position.X, kyroHRP.Position.Y, phrp.Position.Z) - (dir * 3) + (Vector3.yAxis:Cross(dir).Unit * 2.5)
				local kyAnimator = kyHumanoid:FindFirstChildOfClass("Animator")
				if not kyAnimator then
					kyAnimator = Instance.new("Animator")
					kyAnimator.Parent = kyHumanoid
				end
				local runTrack: AnimationTrack? = nil
				MoveTo.MoveHumanoidToTarget(kyHumanoid, kyroHRP, stopPos, {
					minWalkSpeed = 16,
					timeout = 4,
					arriveRadius = 5.6,
					retryInterval = 0.35,
					onStart = function()
						if kyAnimator then
							local anim = Instance.new("Animation")
							anim.AnimationId = "rbxassetid://120866625087275"
							local ok, track = pcall(function()
								return kyAnimator:LoadAnimation(anim)
							end)
							if ok and track then
								runTrack = track
								runTrack.Priority = Enum.AnimationPriority.Movement
								runTrack.Looped = true
								pcall(function()
									runTrack:Play(0.1)
								end)
							end
						end
					end,
					onComplete = function()
						if runTrack then
							pcall(function()
								runTrack:Stop(0.2)
							end)
							runTrack = nil
						end
					end,
				})
			end

			-- Kyro talks to player first
			Say:Say("Kyro", true, {
				{ Text = nickname .. "! Sup, how’d Route 2 go? I kinda came to Cresamore after I gave the Professor the shard piece.", Emotion = "Happy" },
			}, CutsceneFolder.Kyro)
			-- Then Kyro notices Ayla
			Say:Say("Kyro", true, {
				{ Text = "Oh, who’s this?", Emotion = "Talking" },
			}, CutsceneFolder.Kyro, CutsceneFolder.Ayla)

			-- Ayla introduces herself to Kyro
			Say:Say("Ayla", true, {
				{ Text = "Hi! I’m Ayla. Me and " .. nickname .. " met on Route 2 — he helped me get my Brainrot back from those evil Team Rift members!", Emotion = "Happy" },
				{ Text = "I actually heard a bit about you from " .. nickname .. ". He says you’re kind of a big deal.", Emotion = "Happy" },
			}, CutsceneFolder.Ayla, CutsceneFolder.Kyro)

			-- Kyro responds
			Say:Say("Kyro", true, {
				{ Text = "Oof… Team Rift, huh? Yeah, they’re up to no good lately.", Emotion = "Talking" },
				{ Text = "It’s nice to meet you, I’m Kyro — coolest guy in town! …Or, you know, maybe the world.", Emotion = "Smug" },
			}, CutsceneFolder.Kyro, CutsceneFolder.Ayla)

			-- Ayla playful response and battle setup (to Kyro, then to player)
			Say:Say("Ayla", true, {
				{ Text = "Ooooh, show-off! It’s nice to meet you, Kyro.", Emotion = "Happy" },
			}, CutsceneFolder.Ayla, CutsceneFolder.Kyro)
			Say:Say("Ayla", true, {
				{ Text = "I hope we can all be great friends. But for now — me and " .. nickname .. " were just about to have a battle.", Emotion = "Happy" },
			}, CutsceneFolder.Ayla)

			-- Kyro warns player (Say auto-faces player)
			Say:Say("Kyro", true, {
				{ Text = "Oooh, be careful — " .. nickname .. " is stronger than he looks.", Emotion = "Talking" },
			}, CutsceneFolder.Kyro)

			-- Ayla confident reply (Say auto-faces player)
			Say:Say("Ayla", true, {
				{ Text = "Trust me, I know. He beat those Team Rift members like they were nothing.", Emotion = "Happy" },
				{ Text = "But my Ava’s a lot stronger now! Haha, this’ll be fun!", Emotion = "Excited" },
			}, CutsceneFolder.Ayla)

			-- Kyro final hype (Say auto-faces player)
			Say:Say("Kyro", true, {
				{ Text = "Welp, guess it’s time for a battle! " .. nickname .. ", I’ll be watching — don’t disappoint me!", Emotion = "Excited" },
			}, CutsceneFolder.Kyro)

			local trainerDialogue = {
				Name = "Ayla",
				CustomAnimation = false,
				Emotion = "Bored",
				LineOfSight = false,
				TrainerId = "Rival_Ayla_1",
				TrainerName = "Ayla",
				Say = {
					{ Text = "", Emotion = "Bored" },
				},
				AfterSayInBattle = {
					{ Text = "WOW!", Emotion = "Shy" },
				},
				AfterSayOverworld = {
					{ Text = "I'll get better... I know it!", Emotion = "Shy" },
				},
			}
			local trainerSpec = {
				{ Name = "Avocadini Guffo", Level = 12, 
				Gender = "1", 
				IVs = {HP = 31, Attack = 28, Defense = 12, Speed = 19},
				Nature = "Calm" },
			}

			-- Prepare trainer intro agent for Ayla so BattleSystemV2 can animate her
			pcall(function()
				local TrainerIntroController = require(script.Parent.TrainerIntroController)
				TrainerIntroController:PrepareFromNPC(CutsceneFolder.Ayla)
			end)

			Events.Request:InvokeServer({"StartBattle", "Trainer", {
				TrainerName = trainerDialogue.TrainerName,
				TrainerSpec = trainerSpec,
				TrainerId = trainerDialogue.TrainerId,
				TrainerDialogue = trainerDialogue,
			}})

			-- Wait for battle to end and relocation back to overworld, then run post-battle dialogue
			do
				local BattleAwait = require(script.Parent.BattleAwait)
				local ok, _reason = BattleAwait.waitForBattleOverAndRelocation(90)
				-- Post-battle conversation (Ayla, Kyro, Player)
				if ok then
					local pname = nickname
					-- Ayla to Player
					Say:Say("Ayla", true, {
						{ Text = "Woah… you’re so strong!", Emotion = "Excited" },
						{ Text = "I really gave it my all, but you’re something else, " .. pname .. ".", Emotion = "Happy" },
					}, CutsceneFolder.Ayla)
					-- Kyro to Ayla
					Say:Say("Kyro", true, {
						{ Text = "Told ya! He’s pretty good — always has been.", Emotion = "Smug" },
					}, CutsceneFolder.Kyro, CutsceneFolder.Ayla)
					-- Ayla to Player
					Say:Say("Ayla", true, {
						{ Text = "I hope to one day reach your potential, " .. pname .. "!", Emotion = "Happy" },
						{ Text = "You make me want to train even harder.", Emotion = "Excited" },
					}, CutsceneFolder.Ayla)
					-- Kyro to Ayla (curious)
					Say:Say("Kyro", true, {
						{ Text = "…Still, I’m curious. Why were those Team Rift members after you two anyway?", Emotion = "Thinking" },
					}, CutsceneFolder.Kyro, CutsceneFolder.Ayla)
					-- Ayla to Kyro (shard story)
					Say:Say("Ayla", true, {
						{ Text = "Well… see, I was on Route 5 the other day. My Brainrot was caught near this strange shard — it was glowing, and it gave me these really creepy vibes.", Emotion = "Thinking" },
						{ Text = "I didn’t touch it. I just caught Ava and left.", Emotion = "Talking" },
					}, CutsceneFolder.Ayla, CutsceneFolder.Kyro)
					-- Kyro to Ayla (reasoning)
					Say:Say("Kyro", true, {
						{ Text = "Hmm… so they probably thought Ava could lead them to the shard.", Emotion = "Thinking" },
						{ Text = "Do you remember where exactly you saw it?", Emotion = "Talking" },
					}, CutsceneFolder.Kyro, CutsceneFolder.Ayla)
					-- Ayla to Kyro (uncertain)
					Say:Say("Ayla", true, {
						{ Text = "Not really… it’s all kind of a blur.", Emotion = "Sad" },
					}, CutsceneFolder.Ayla, CutsceneFolder.Kyro)
					-- Kyro planning (to Ayla)
					Say:Say("Kyro", true, {
						{ Text = "Then we’ll need to find it before they do. If Team Rift’s gathering these shards, the Professor needs to know ASAP.", Emotion = "Talking" },
					}, CutsceneFolder.Kyro, CutsceneFolder.Ayla)
					-- Ayla agreeing (to Kyro)
					Say:Say("Ayla", true, {
						{ Text = "Yeah… I don’t want anyone else going through what I went through.", Emotion = "Sad" },
					}, CutsceneFolder.Ayla, CutsceneFolder.Kyro)
					-- Kyro gives guidance (to Player)
					Say:Say("Kyro", true, {
						{ Text = "There’s a CatchCare here in town. " .. pname .. ", you should stop by there — you can heal your Brainrots and stock up on items.", Emotion = "Talking" },
					}, CutsceneFolder.Kyro)
					-- Kyro to Ayla
					Say:Say("Kyro", true, {
						{ Text = "Ayla, we should go too and heal your Ava.", Emotion = "Talking" },
					}, CutsceneFolder.Kyro, CutsceneFolder.Ayla)
					-- Ayla to Player
					Say:Say("Ayla", true, {
						{ Text = "You’re right. " .. pname .. ", I’ll see you soon, okay?", Emotion = "Happy" },
					}, CutsceneFolder.Ayla)
					-- Kyro to Player
					Say:Say("Kyro", true, {
						{ Text = "Later, " .. pname .. ". Don’t slack off now!", Emotion = "Smug" },
					}, CutsceneFolder.Kyro)

					UIFunctions:Transition(true)
					task.wait(1.5)
					UIFunctions:Transition(false)
				end
			end

			CutsceneFolder.Ayla:Destroy()
			CutsceneFolder.Kyro:Destroy()

 			local CutsceneRegistry = require(script.Parent.CutsceneRegistry)
 			CutsceneRegistry:End("Route3_KyroIntro")
			
			UI.TopBar:SetSuppressed(false)
			UI.TopBar:Show()

			CharacterFunctions:SetSuppressed(false)
			CharacterFunctions:CanMove(true)

		else
			local CutsceneFolder = CurrentChunk.Model.Essentials.Cutscene
			CutsceneFolder.Ayla:Destroy()
			CutsceneFolder.Kyro:Destroy()
		end

		local events = (CD and CD.Events) or {}
		local assassinIntro = events.ASSASSIN_ROUTE_3_INTRO == true

		if events.ASSASSIN_ROUTE_3 ~= true then
			local essentials = CurrentChunk and CurrentChunk.Model and CurrentChunk.Model.Essentials
			local cutscene = essentials and essentials:FindFirstChild("Cutscene")
			if cutscene then
				-- Phase 1: Assassin blocks the gate when player touches trigger (only if intro hasn't already happened)
				if not assassinIntro then
					local trigger = cutscene:FindFirstChild("CappuchinoAssasinoTrigger")
					if trigger and trigger:IsA("BasePart") then
						if trigger:GetAttribute("AssassinArmed") == true then
							DBG:print("[Route3] Assassin trigger already armed - skipping duplicate")
						else
							trigger:SetAttribute("AssassinArmed", true)
							DBG:print("[Route3] ASSASSIN_ROUTE_3 = false; arming CappuchinoAssasinoTrigger")

							local fired = false
							local conn
							conn = trigger.Touched:Connect(function(hit)
								local player = Players.LocalPlayer
								local character = player and (player.Character or player.CharacterAdded:Wait())
								local hrp: BasePart? = character and character:FindFirstChild("HumanoidRootPart")
								if fired or not hrp or (hit ~= hrp and (not hit or not hit:IsDescendantOf(character))) then
									return
								end
								fired = true
								DBG:print("[Route3] Assassin trigger touched - starting Assassin gate block sequence")

								-- Hide UI / lock player movement during the short animation
								UI.TopBar:SetSuppressed(true)
								UI.TopBar:Hide()
								CharacterFunctions:SetSuppressed(true)
								CharacterFunctions:CanMove(false)

								workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
								workspace.CurrentCamera.CFrame = cutscene:FindFirstChild("CameraPart2").CFrame
								workspace.CurrentCamera.FieldOfView = 48

								local assassin = cutscene:FindFirstChild("Assassin")
								local assassinHRP: BasePart? = assassin and assassin:FindFirstChild("HumanoidRootPart")
								local assassinHum: Humanoid? = assassin and assassin:FindFirstChildOfClass("Humanoid")
								local assassinAnim = assassin and assassin:FindFirstChild("Animation")
								local jumpTarget: BasePart? = cutscene:FindFirstChild("CappuchinoAssasinoJumpToCutscene")

								-- Play Assassin jump-in animation
								local assassinTrack: AnimationTrack? = nil
								pcall(function()
									if assassinHum and assassinAnim and assassinAnim:IsA("Animation") then
										local animator = assassinHum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
										animator.Parent = assassinHum
										local ok, tr = pcall(function()
											return animator:LoadAnimation(assassinAnim)
										end)
										if ok and tr then
											assassinTrack = tr
											assassinTrack.Priority = Enum.AnimationPriority.Action
											assassinTrack.Looped = false
											pcall(function()
												assassinTrack:Play(0.1)
											end)
										end
									end
								end)

								repeat
									task.wait()
								until assassinTrack and assassinTrack.TimePosition > 0

								task.wait(2.8)

								-- Move Assassin into blocking position
								if assassinHRP and jumpTarget and jumpTarget:IsA("BasePart") then
									assassinHRP.CFrame = jumpTarget.CFrame
								end

								workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
								workspace.CurrentCamera.FieldOfView = 70

								-- Mark intro as done so it persists across reloads
								setClientEventFlag("ASSASSIN_ROUTE_3_INTRO", true)

								-- Player reaction to seeing the Assassin
								Say:Say("Me", true, {
									{ Text = "Huh? What the— I think this is someone’s Cappuccino Assassino.", Emotion = "Thinking" },
									{ Text = "Guess I’ll have to find who it belongs to…", Emotion = "Talking" },
								})

								-- Return control so player can explore town and find Noah
								UI.TopBar:SetSuppressed(false)
								UI.TopBar:Show()
								CharacterFunctions:SetSuppressed(false)
								CharacterFunctions:CanMove(true)

								if conn then
									conn:Disconnect()
								end
							end)
						end
					else
						DBG:print("[Route3] CappuchinoAssasinoTrigger missing; cannot arm Assassin cutscene")
					end
				else
					-- Intro already happened earlier (possibly before a reload); ensure Assassin is in blocking position
					local assassin = cutscene:FindFirstChild("Assassin")
					local assassinHRP: BasePart? = assassin and assassin:FindFirstChild("HumanoidRootPart")
					local jumpTarget: BasePart? = cutscene:FindFirstChild("CappuchinoAssasinoJumpToCutscene")
					if assassinHRP and jumpTarget and jumpTarget:IsA("BasePart") then
						assassinHRP.CFrame = jumpTarget.CFrame
					end
				end

				-- Phase 2: Noah interaction when player clicks on him
				local noahNpc = cutscene:FindFirstChild("Noah")
				if noahNpc then
					NPC:Setup(noahNpc, function()
						-- Re-read events so we see any changes made since chunk load
						local cdNow = ClientData:Get()
						local evNow = (cdNow and cdNow.Events) or {}

						-- If everything is already resolved, just give a small post-event line
						if evNow.ASSASSIN_ROUTE_3 == true then
							UI.TopBar:Hide()
							Say:Say("Noah", true, {
								{ Text = "Hey again! Cappuccino Assassino’s calm now, so the gate should be clear.", Emotion = "Happy" },
							}, noahNpc)
							UI.TopBar:Show()
							CharacterFunctions:SetSuppressed(false)
							CharacterFunctions:CanMove(true)
							return
						end

						-- If we haven’t seen the Assassin block the gate yet, give pre-dialogue instead of starting the battle
						if evNow.ASSASSIN_ROUTE_3_INTRO ~= true then
							UI.TopBar:Hide()
							Say:Say("Noah", true, {
								{ Text = "Oh, hey! I’m Noah.", Emotion = "Happy" },
								{ Text = "I’ve got a Brainrot named Cappuccino Assassino — he can get a little overprotective near the Route 3 gate.", Emotion = "Talking" },
								{ Text = "If you see him blocking the way, come let me know, alright?", Emotion = "Happy" },
							}, noahNpc)
							UI.TopBar:Show()
							CharacterFunctions:SetSuppressed(false)
							CharacterFunctions:CanMove(true)
							return
						end

						-- At this point, the Assassin intro has happened but the event isn’t resolved yet: run full battle flow
						UI.TopBar:SetSuppressed(true)
						UI.TopBar:Hide()
						CharacterFunctions:SetSuppressed(true)
						CharacterFunctions:CanMove(false)

						local player = Players.LocalPlayer
						local character = player and (player.Character or player.CharacterAdded:Wait())
						local hrp: BasePart? = character and character:FindFirstChild("HumanoidRootPart")

						local playerPos: BasePart? = cutscene:FindFirstChild("CapuchinoPlayerPos")
						local noahPosAfter: BasePart? = cutscene:FindFirstChild("NoahPositionAfter")

						local noahHRP: BasePart? = noahNpc:FindFirstChild("HumanoidRootPart")

						-- Noah dialogue sequence explaining the situation
						Say:Say("Noah", true, {
							{ Text = "You said a Brainrot’s blocking the gate?", Emotion = "Thinking" },
							{ Text = "Oh man, that’s mine! Sorry about that. Cappuccino Assassino’s always been protective of trainers — he won’t let people through if he feels they’re not ready yet.", Emotion = "Happy" },
						}, noahNpc)
						Say:Say("Noah", true, {
							{ Text = "It’s kind of his thing, y’know? Helping trainers by testing them.", Emotion = "Talking" },
							{ Text = "If you want to pass, you’ll have to prove yourself and beat him in battle.", Emotion = "Excited" },
						}, noahNpc)
						Say:Say("Me", true, {
							{ Text = "So… I have to battle him to earn my way through, huh?", Emotion = "Thinking" },
						})
						Say:Say("Noah", true, {
							{ Text = "Exactly! Let’s go together — I’ll tell him it’s a friendly match.", Emotion = "Happy" },
							{ Text = "Don’t hold back though, he loves a real challenge.", Emotion = "Excited" },
						}, noahNpc)

						-- Transition and teleport to battle positions
						UIFunctions:Transition(true)
						task.wait(1.5)

						if hrp and playerPos and playerPos:IsA("BasePart") then
							hrp.CFrame = playerPos.CFrame
						end
						if noahHRP and noahPosAfter and noahPosAfter:IsA("BasePart") then
							noahHRP.CFrame = noahPosAfter.CFrame
						end

						UIFunctions:Transition(false)

						Say:Say("Noah", true, {
							{ Text = "Awesome! Now we're here, let's do this!", Emotion = "Excited" },
						}, noahNpc)

						-- Start Trainer battle: Noah with Cappuccino Assassino (level 12)
						local trainerDialogue = {
							Name = "Noah",
							CustomAnimation = false,
							Emotion = "Bored",
							LineOfSight = false,
							TrainerId = "Route3_Noah_Assassin",
							TrainerName = "Noah",
							Say = {
								{ Text = "", Emotion = "Bored" },
							},
							AfterSayInBattle = {
								{ Text = "Cappuccino Assassino really went all out!", Emotion = "Happy" },
							},
							AfterSayOverworld = {
								{ Text = "He definitely respects you now.", Emotion = "Happy" },
							},
						}

						local trainerSpec = {
							{
								Name = "Cappuccino Assassino",
								Level = 12,
								Gender = "1",
								IVs = { HP = 31, Attack = 20, Defense = 18, Speed = 22 },
								Nature = "Brave",
							},
						}

						local TrainerIntroController = require(script.Parent.TrainerIntroController)
						TrainerIntroController:PrepareFromNPC(noahNpc)

						Events.Request:InvokeServer({ "StartBattle", "Trainer", {
							TrainerName = trainerDialogue.TrainerName,
							TrainerSpec = trainerSpec,
							TrainerId = trainerDialogue.TrainerId,
							TrainerDialogue = trainerDialogue,
						} })

						-- Wait for battle to finish and then run post-battle cleanup/dialogue
						do
							local ok, reason = pcall(function()
								local BattleAwait = require(script.Parent.BattleAwait)
								return BattleAwait.waitForBattleOverAndRelocation(90)
							end)

							if ok and reason == true then
								Say:Say("Noah", true, {
									{ Text = "Haha! He respects you now. See that little nod? That’s his way of saying, \"You’re ready.\"", Emotion = "Happy" },
								}, noahNpc)
								Say:Say("Noah", true, {
									{ Text = "Seems like you’re good to go! Good luck with the Asterden Gym Leader — he’s tough, but you’ve got this.", Emotion = "Excited" },
								}, noahNpc)

								UIFunctions:Transition(true)
								task.wait(1.5)

								-- Clean up Assassin and Noah from cutscene after battle
								local assassin = cutscene:FindFirstChild("Assassin")
								if assassin then assassin:Destroy() end
								if noahNpc then noahNpc:Destroy() end

								setClientEventFlag("ASSASSIN_ROUTE_3", true)

								UIFunctions:Transition(false)
							else
								DBG:warn("[Route3] Assassin/Noah battle did not complete successfully: " .. tostring(reason))
							end
						end

						UI.TopBar:SetSuppressed(false)
						UI.TopBar:Show()
						CharacterFunctions:SetSuppressed(false)
						CharacterFunctions:CanMove(true)
					end)

					-- Soft gate in front of the Route 3 gate so player can't proceed to Chunk4
					-- until the Assassin/Noah event is fully resolved.
					do
						local blocker: BasePart? = cutscene:FindFirstChild("CappuchinoAssasinoBlocker")
						if blocker and blocker:IsA("BasePart") then
							local Player = Players.LocalPlayer
							local lastTriggerTime = 0
							local proximityAhead = 3 -- studs in front of blocker front face
							local lateralPadding = 2 -- side padding
							local hbConn: RBXScriptConnection? = nil

							hbConn = RunService.Heartbeat:Connect(function()
								local cdNow = ClientData:Get()
								local evNow = (cdNow and cdNow.Events) or {}

								-- If event finished, stop gating
								if evNow.ASSASSIN_ROUTE_3 == true then
									if hbConn then hbConn:Disconnect() hbConn = nil end
									return
								end

								-- Only gate after the Assassin has actually blocked the gate
								if evNow.ASSASSIN_ROUTE_3_INTRO ~= true then
									return
								end

								local character = Player and Player.Character
								local hrp: BasePart? = character and character:FindFirstChild("HumanoidRootPart")
								local humanoid: Humanoid? = character and character:FindFirstChildOfClass("Humanoid")
								if not hrp or not humanoid then return end

								-- Compute relative position using blocker orientation
								local toPlayer = hrp.Position - blocker.Position
								local look = blocker.CFrame.LookVector
								local right = blocker.CFrame.RightVector
								local halfDepth = (blocker.Size.Z or 0) * 0.5
								local halfWidth = (blocker.Size.X or 0) * 0.5
								local axisDist = toPlayer:Dot(look) -- + in front, - behind
								local lateralDist = math.abs(toPlayer:Dot(right))
								local frontFace = halfDepth
								local inFrontBand = axisDist >= (frontFace - 0.25) and axisDist <= (frontFace + proximityAhead)
								local withinWidth = lateralDist <= (halfWidth + lateralPadding)
								if not (inFrontBand and withinWidth) then
									return
								end

								local now = os.clock()
								if now - lastTriggerTime < 1.2 then
									return
								end
								lastTriggerTime = now

								-- Prompt and push the player back
								Say:Say("Cappuccino Assassino", true, { { Text = "Assassino!", Emotion = "Thinking" } })

								local behindPoint = blocker.CFrame.Position - (look * (halfDepth + 10))
								local target = Vector3.new(behindPoint.X, hrp.Position.Y, behindPoint.Z)

								MoveTo.MoveToTarget(target, {
									minWalkSpeed = 12,
									timeout = 1.5,
									delayAfter = 0.5,
									preserveFacing = true,
								})

								pcall(function() Say:Exit() end)
							end)

							-- Clean up when chunk unloads
							if CurrentChunk and CurrentChunk.Model then
								CurrentChunk.Model.AncestryChanged:Connect(function(_, parent)
									if not parent and hbConn then
										hbConn:Disconnect()
										hbConn = nil
									end
								end)
							end
						end
					end
				else
					DBG:print("[Route3] Noah NPC missing; cannot arm Noah interaction")
				end
			end
		else
			local CutsceneFolder = CurrentChunk.Model.Essentials.Cutscene
			CutsceneFolder.Assassin:Destroy()
			CutsceneFolder.Noah:Destroy()
		end
	end,
["Load_Professor's Lab"] = function(CurrentChunk)
        -- If player hasn't chosen a starter yet, re-run the professor intro cutscene on (re)entry
        local pd = ClientData:Get()
        local hasStarter = (pd and ((pd.SelectedStarter ~= nil) or (pd.Party and #pd.Party > 0))) and true or false
        if not hasStarter then
            RunCutsceneOnceGated("MET_PROFESSOR", "Professor_StarterIntro", "ProfessorStarterIntro", CurrentChunk)
		else
			CurrentChunk.Essentials.RivalCutscene:Destroy()
        end
end,
	
	
}




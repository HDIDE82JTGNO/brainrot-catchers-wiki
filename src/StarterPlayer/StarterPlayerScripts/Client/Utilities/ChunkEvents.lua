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

DBG:print("[ChunkEvents] Module required and initialized")

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

                    -- Use reusable MoveTo helper to push the player behind the blocker
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
			local MoveTo = require(script.Parent.MoveTo)
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
		SetupHealer("Damian", "Oh, sup. Need those creatures healing? I got you!", "All done, no need to thank me.")
		SetupHealer("Miranda", "Oh hi! You need your creatures healed? Allow me!", "Done! Take care of them!")
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
			ChunkName = "Chunk2",
			NPCTargetName = "Healer Tom",
		}
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




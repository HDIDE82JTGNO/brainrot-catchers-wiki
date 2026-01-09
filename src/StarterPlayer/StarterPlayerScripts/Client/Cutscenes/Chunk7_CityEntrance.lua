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
local MoveTo = require(Utilities:WaitForChild("MoveTo"))
local NPCAnimations = require(Utilities:WaitForChild("NPCAnimations"))

local function resolveEssentials(currentChunk: any): Instance?
	if not currentChunk then return nil end
	if currentChunk.Essentials then return currentChunk.Essentials end
	if currentChunk.Model and currentChunk.Model:FindFirstChild("Essentials") then
		return currentChunk.Model:FindFirstChild("Essentials")
	end
	return nil
end

local function tweenLookAt(fromPart: BasePart, toPart: BasePart)
	local targetPos = Vector3.new(toPart.Position.X, fromPart.Position.Y, toPart.Position.Z)
	local lookCFrame = CFrame.new(fromPart.Position, targetPos)
	TweenService:Create(fromPart, TweenInfo.new(0.5), { CFrame = lookCFrame }):Play()
end

return function(currentChunk: any, handle: any): boolean
	DBG:print("[Chunk7_CityEntrance] Begin")
	local camera = workspace.CurrentCamera
	local essentials = resolveEssentials(currentChunk)
	if not essentials then
		DBG:print("[Chunk7_CityEntrance] Essentials not found")
		return false
	end
	
	local cutsceneFolder = essentials:FindFirstChild("Cutscene")
	if not cutsceneFolder then
		DBG:print("[Chunk7_CityEntrance] Cutscene folder not found")
		return false
	end
	
	local function getPart(name: string): BasePart?
		local p = cutsceneFolder:FindFirstChild(name)
		return (p and p:IsA("BasePart")) and p or nil
	end
	
	local function getModel(name: string): Model?
		local m = cutsceneFolder:FindFirstChild(name)
		return (m and m:IsA("Model")) and m or nil
	end
	
	local function getHRP(model: Model?): BasePart?
		return model and (model:FindFirstChild("HumanoidRootPart") :: BasePart?) or nil
	end
	
	-- Resolve all required assets
	local Cam1 = getPart("Cam1")
	local Cam2 = getPart("Cam2")
	local Cam3 = getPart("Cam3")
	local Cam4 = getPart("Cam4")
	local CutscenePosition = getPart("CutscenePosition")
	local Duckaroo = getModel("Duckaroo")
	local GymLeader = getModel("Range Champion Harlan")
	local Kyro = getModel("Kyro")
	local Ayla = getModel("Ayla")
	
	-- Debug which references are missing
	local missing = {}
	if not Cam1 then table.insert(missing, "Cam1") end
	if not Cam2 then table.insert(missing, "Cam2") end
	if not Cam3 then table.insert(missing, "Cam3") end
	if not Cam4 then table.insert(missing, "Cam4") end
	if not CutscenePosition then table.insert(missing, "CutscenePosition") end
	if not Duckaroo then table.insert(missing, "Duckaroo") end
	if not GymLeader then table.insert(missing, "Range Champion Harlan") end
	if not Kyro then table.insert(missing, "Kyro") end
	if not Ayla then table.insert(missing, "Ayla") end
	if #missing > 0 then
		DBG:print("[Chunk7_CityEntrance] Missing assets:", table.concat(missing, ", "))
		return false
	end
	
	local player = PlayersService.LocalPlayer
	local character = player.Character or player.CharacterAdded:Wait()
	local playerHRP = character:FindFirstChild("HumanoidRootPart")
	local playerHumanoid = character:FindFirstChildOfClass("Humanoid")
	
	if not playerHRP then
		DBG:print("[Chunk7_CityEntrance] Player HRP not found")
		return false
	end
	
	-- Store original player state
	local originalCFrame = playerHRP.CFrame
	local wasAnchored = playerHRP.Anchored
	local wasAutoRotate = playerHumanoid and playerHumanoid.AutoRotate or true
	
	-- Position player at cutscene position
	playerHRP.CFrame = CutscenePosition.CFrame
	if playerHumanoid then
		playerHumanoid.AutoRotate = false
	end
	
	-- Get character HRPs
	local duckarooHRP = getHRP(Duckaroo)
	local gymLeaderHRP = getHRP(GymLeader)
	local kyroHRP = getHRP(Kyro)
	local aylaHRP = getHRP(Ayla)
	
	-- Ensure all character models are visible and positioned
	if duckarooHRP then duckarooHRP.Anchored = true end
	if gymLeaderHRP then gymLeaderHRP.Anchored = true end
	if kyroHRP then kyroHRP.Anchored = true end
	if aylaHRP then aylaHRP.Anchored = true end
	
	-- Preload Duckaroo animations
	local duckarooAnimations = Duckaroo:FindFirstChild("Animations")
	local duckarooIdleAnim = duckarooAnimations and duckarooAnimations:FindFirstChild("Idle")
	local duckarooMoveAnim = duckarooAnimations and duckarooAnimations:FindFirstChild("Move")
	
	if duckarooIdleAnim and duckarooIdleAnim:IsA("Animation") then
		pcall(function() ContentProvider:PreloadAsync({duckarooIdleAnim}) end)
	end
	if duckarooMoveAnim and duckarooMoveAnim:IsA("Animation") then
		pcall(function() ContentProvider:PreloadAsync({duckarooMoveAnim}) end)
	end
	
	-- Helper function to play animation on Duckaroo
	local function playDuckarooAnimation(animName: string): AnimationTrack?
		if not Duckaroo then return nil end
		local animFolder = Duckaroo:FindFirstChild("Animations")
		if not animFolder then return nil end
		
		local anim = animFolder:FindFirstChild(animName)
		if not anim or not anim:IsA("Animation") then return nil end
		
		local humanoid = Duckaroo:FindFirstChildOfClass("Humanoid")
		local animController = Duckaroo:FindFirstChildOfClass("AnimationController")
		local loader = humanoid or animController
		
		if loader and loader.LoadAnimation then
			local track = loader:LoadAnimation(anim)
			if animName == "Idle" then
				track.Priority = Enum.AnimationPriority.Idle
				track.Looped = true
			elseif animName == "Move" then
				track.Priority = Enum.AnimationPriority.Movement
				track.Looped = true
			end
			track:Play()
			return track
		end
		return nil
	end
	
	-- Start camera sequence
	UIFunctions:Transition(true)
	UI.TopBar:SetSuppressed(true)
	UI.TopBar:Hide()
	CharacterFunctions:CanMove(false)
	
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = Cam1.CFrame
	UIFunctions:Transition(false)
	task.wait(0.35)

	playerHRP.Anchored = true
	
	-- Camera pan through city overview
	TweenService:Create(camera, TweenInfo.new(5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { CFrame = Cam2.CFrame }):Play()
	task.wait(5)
	
	camera.CFrame = Cam3.CFrame
	TweenService:Create(camera, TweenInfo.new(5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { CFrame = Cam4.CFrame }):Play()
	task.wait(5)
	UIFunctions:Transition(true)
	task.wait(1)
	UIFunctions:Transition(false)
	DBG:print("[Chunk7_CityEntrance] Camera sequence complete")
	
	-- Transition camera to focus on characters
	-- Position camera to show Kyro, Ayla, and player
	if kyroHRP and aylaHRP and playerHRP then
		local centerPos = (kyroHRP.Position + aylaHRP.Position + playerHRP.Position) / 3
		local camPos = centerPos + Vector3.new(0, 5, -18) -- Further back to show Kyro
		camera.CFrame = CFrame.lookAt(camPos, centerPos)
		
		-- Make characters face each other
		if kyroHRP then
			tweenLookAt(kyroHRP, playerHRP)
		end
		if aylaHRP then
			tweenLookAt(aylaHRP, playerHRP)
		end
	end
	
	task.wait(0.5)

	gymLeaderHRP.Anchored = false
	
	-- Dialogue sequence
	Say:Say("Kyro", true, {
		{ Text = "WOAH! This place is awesome!", Emotion = "Happy" },
		{ Text = "Honestly? Kinda cooler than Asterden.", Emotion = "Happy" },
	}, Kyro)
	
	Say:Say("Ayla", true, {
		{ Text = "Heh, pretty neat, right?", Emotion = "Happy" },
	}, Ayla)
	
	-- Duckaroo runs across street
	Say:Say("???", true, {
		{ Text = "DUCKAROOO—!!", Emotion = "Angry" },
	}, GymLeader)
	
	-- Adjust camera to show Duckaroo running if possible
	if duckarooHRP and playerHRP and kyroHRP and aylaHRP then
		local duckarooStartPos = duckarooHRP.Position
		local midPoint = (duckarooStartPos + playerHRP.Position) / 2
		-- Include Kyro in camera calculation to keep him in view
		local allPoints = {duckarooStartPos, playerHRP.Position, kyroHRP.Position, aylaHRP.Position}
		local sumPos = Vector3.new(0, 0, 0)
		for _, pos in ipairs(allPoints) do
			sumPos = sumPos + pos
		end
		local centerPos = sumPos / #allPoints
		local camPos = centerPos + Vector3.new(0, 5, -18) -- Further back to show all characters
		TweenService:Create(camera, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			CFrame = CFrame.lookAt(camPos, centerPos)
		}):Play()
	end
	
	task.wait(0.3)
	
	-- Play Duckaroo Move animation and move across street
	local duckarooReached = false
	if duckarooHRP then
		local duckarooHumanoid = Duckaroo:FindFirstChildOfClass("Humanoid")
		if duckarooHumanoid then
			-- Unanchor Duckaroo for movement
			duckarooHRP.Anchored = false
			
			-- Move Duckaroo to stop further from the player
			local playerPos = playerHRP.Position
			local playerLook = playerHRP.CFrame.LookVector
			-- Position Duckaroo further away from player (8 studs away)
			local endPos = playerPos + (playerLook * 8) + Vector3.new(0, 0, 2) -- Further distance
			
			-- Play Move animation when movement starts
			local moveTrack = playDuckarooAnimation("Move")
			
			-- Use MoveTo for Duckaroo movement
			MoveTo.MoveHumanoidToTarget(duckarooHumanoid, duckarooHRP, endPos, {
				minWalkSpeed = 16,
				timeout = 3.0,
				arriveRadius = 1.5,
				retryInterval = 0.3,
				onStart = function()
					-- Ensure move animation is playing
					if not moveTrack then
						moveTrack = playDuckarooAnimation("Move")
					end
				end,
				onComplete = function(reached)
					duckarooReached = true
					-- Stop move animation and switch to idle
					if moveTrack then
						moveTrack:Stop(0.2)
					end
					playDuckarooAnimation("Idle")
					
					-- Make Duckaroo face player
					if duckarooHRP and playerHRP then
						tweenLookAt(duckarooHRP, playerHRP)
					end
					
					-- Now move Gym Leader to position behind Duckaroo
					if gymLeaderHRP and duckarooHRP then
						local gymLeaderHumanoid = GymLeader:FindFirstChildOfClass("Humanoid")
						if gymLeaderHumanoid then
							-- Unanchor Gym Leader for movement

							
							-- Calculate position behind Duckaroo (opposite direction from player)
							local duckarooPos = duckarooHRP.Position
							local duckarooLook = duckarooHRP.CFrame.LookVector
							-- Position Gym Leader behind Duckaroo (3 studs behind)
							local behindDuckarooPos = duckarooPos - (duckarooLook * 3)
							behindDuckarooPos = Vector3.new(behindDuckarooPos.X, gymLeaderHRP.Position.Y, behindDuckarooPos.Z)
							
							-- Move Gym Leader behind Duckaroo
							MoveTo.MoveHumanoidToTarget(gymLeaderHumanoid, gymLeaderHRP, behindDuckarooPos, {
								minWalkSpeed = 12,
								timeout = 2.5,
								arriveRadius = 1.5,
								retryInterval = 0.3,
								onComplete = function()
									-- Face player after movement
									if gymLeaderHRP and playerHRP then
										tweenLookAt(gymLeaderHRP, playerHRP)
									end
								end
							})
						end
					end
				end
			})
		end
	end
	
	-- Wait for Duckaroo to reach position before adjusting camera
	task.wait(1.5)
	
	-- Adjust camera to show Gym Leader, Duckaroo, and all characters
	if gymLeaderHRP and playerHRP and kyroHRP and aylaHRP and duckarooHRP then
		local centerPos = (gymLeaderHRP.Position + playerHRP.Position + kyroHRP.Position + aylaHRP.Position + duckarooHRP.Position) / 5
		local camPos = centerPos + Vector3.new(0, 5, -20) -- Further back to show all characters including Kyro
		TweenService:Create(camera, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			CFrame = CFrame.lookAt(camPos, centerPos)
		}):Play()
	end
	
	-- Make characters face appropriate directions
	if playerHumanoid and gymLeaderHRP then
		local lookAtGymLeader = CFrame.new(playerHRP.Position, gymLeaderHRP.Position)
		playerHRP.CFrame = lookAtGymLeader
	end
	-- Make other characters face Gym Leader
	if kyroHRP and gymLeaderHRP then
		tweenLookAt(kyroHRP, gymLeaderHRP)
	end
	if aylaHRP and gymLeaderHRP then
		tweenLookAt(aylaHRP, gymLeaderHRP)
	end
	
	task.wait(0.5)
	
	Say:Say("???", true, {
		{ Text = "Easy there, partner!", Emotion = "Happy" },
		{ Text = "Sorry 'bout that—Duckaroo's been causin' a ruckus all day.", Emotion = "Neutral" },
	}, GymLeader)
	
	Say:Say("Kyro", true, {
		{ Text = "You're good. He didn't really do much…", Emotion = "Neutral" },
	}, Kyro)
	
	Say:Say("Ayla", true, {
		{ Text = "Yeah, no trouble at all, sir.", Emotion = "Neutral" },
	}, Ayla)
	
	Say:Say("???", true, {
		{ Text = "Whew… that's a relief.", Emotion = "Happy" },
		{ Text = "Truth is, my partner here lost his hat—and without it, well… he's gone plumb wild.", Emotion = "Neutral" },
		{ Text = "Been runnin' around town, kickin' up dust where he shouldn't.", Emotion = "Neutral" },
		{ Text = "Had no choice but to shut the Gym down.", Emotion = "Neutral" },
	}, GymLeader)
	
	Say:Say("Kyro", true, {
		{ Text = "Wait—close the Gym?", Emotion = "Confused" },
	}, Kyro)
	
	-- Name swap from ??? to Range Champion Harlan
	Say:Say("Range Champion Harlan", true, {
		{ Text = "Heh… reckon I should introduce myself.", Emotion = "Happy" },
		{ Text = "Name's Range Champion Harlan, sheriff of battles 'round these parts… and the Gym Leader of Dustnook City.", Emotion = "Neutral" },
	}, GymLeader)
	
	Say:Say("Range Champion Harlan", true, {
		{ Text = "Me an' Duckaroo here?", Emotion = "Neutral" },
		{ Text = "We've been partners—and protectors of this Gym—for ten long years.", Emotion = "Happy" },
	}, GymLeader)
	
	Say:Say("Ayla", true, {
		{ Text = "That's amazing!", Emotion = "Happy" },
		{ Text = "Can't believe we ran into the Gym Leader so fast!", Emotion = "Happy" },
	}, Ayla)
	
	Say:Say("Ayla", true, {
		{ Text = "If Duckaroo lost his hat, we can help find it!", Emotion = "Happy" },
		{ Text = "Plus… we really need that Gym Badge.", Emotion = "Neutral" },
	}, Ayla)
	
	Say:Say("Range Champion Harlan", true, {
		{ Text = "Hoho! Appreciate the spirit.", Emotion = "Happy" },
		{ Text = "But don't go thinkin' I'll go easy on ya—even if you help us out.", Emotion = "Smug" },
	}, GymLeader)
	
	Say:Say("Kyro", true, {
		{ Text = "Wouldn't want it any other way.", Emotion = "Smug" },
		{ Text = "A real challenge is how you get stronger.", Emotion = "Neutral" },
	}, Kyro)
	
	Say:Say("Range Champion Harlan", true, {
		{ Text = "That's the kinda talk I like hearin'.", Emotion = "Happy" },
		{ Text = "Last I reckon, that hat's still somewhere in this city.", Emotion = "Neutral" },
		{ Text = "I'll be waitin' outside the Gym.", Emotion = "Neutral" },
		{ Text = "Bring it back, partners.", Emotion = "Happy" },
	}, GymLeader)
	
	Say:Say("Ayla", true, {
		{ Text = "You got it!", Emotion = "Happy" },
	}, Ayla)
	
	Say:Say("Kyro", true, {
		{ Text = "Let's do this.", Emotion = "Neutral" },
	}, Kyro)
	
	Say:Say("Kyro", true, {
		{ Text = "Alright—split up and search the city!", Emotion = "Happy" },
	}, Kyro)
	
	Say:Say("Ayla", true, {
		{ Text = "Yeah! Let's meet back with Range Champion Harlan once we find it!", Emotion = "Happy" },
	}, Ayla)
	
	task.wait(1)
	
	-- Exit dialogue and cleanup
	Say:Exit()
	
	-- Fade to black
	UIFunctions:Transition(true)
	task.wait(0.5)
	
	-- Position characters for hat return quest
	if gymLeaderHRP then
		gymLeaderHRP.CFrame = CFrame.new(-20.251, 989.76, 859.898)
		gymLeaderHRP.Anchored = true
	end
	
	if duckarooHRP then
		duckarooHRP.CFrame = CFrame.new(-20.349, 989.351, 855.421) * CFrame.Angles(0, math.rad(-107.78), 0)
		duckarooHRP.Anchored = true
	end
	
	if kyroHRP then
		kyroHRP.CFrame = CFrame.new(465.426, 1087.646, 923.702)
		kyroHRP.Anchored = true
	end
	
	if aylaHRP then
		aylaHRP.CFrame = CFrame.new(465.426, 1087.646, 923.702)
		aylaHRP.Anchored = true
	end
	
	-- Restore player state
	pcall(function()
		playerHRP.Anchored = wasAnchored
		if playerHumanoid then
			playerHumanoid.AutoRotate = wasAutoRotate
		end
	end)
	
	-- Restore camera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70

	task.wait(1)
	-- Don't destroy cutscene folder - we need it for hat return quest
	
	-- Restore UI and movement
	UIFunctions:Transition(false)
	UI.TopBar:SetSuppressed(false)
	UI.TopBar:Show()
	CharacterFunctions:CanMove(true)


	
	DBG:print("[Chunk7_CityEntrance] Cutscene complete")
	
	
	if handle and handle.End then
		handle:End()
	end
	
	return false
end


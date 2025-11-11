local Door = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local RSAssets = ReplicatedStorage:WaitForChild("Assets")

local CharacterFunctions = require(script.Parent.CharacterFunctions)
local DBG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DBG"))
local UIFunctions = require(script.Parent.Parent.UI.UIFunctions)
local UI = require(script.Parent.Parent.UI)

-- Get the local player and their character
local LocalPlayer = Players.LocalPlayer

-- Track active door interactions to prevent multiple triggers
local ActiveDoorInteractions = {}
-- Global post-load cooldown to avoid immediate re-entry loops (e.g., CatchCare exit)
local GlobalDoorCooldownUntil = 0

-- Door model animation handling (original functionality)
local function PlayDoorAnimation(DoorModel, DoorType)
	if DoorType == "Single" then
		-- Get the animation from ReplicatedStorage
		local Animation = RSAssets.Animations:FindFirstChild("SingleDoorOpening")
		if Animation then
			-- Find the DoorModel with AnimationController
			local DoorModelPart = DoorModel:FindFirstChild("DoorModel")
			if DoorModelPart then
				local AnimationController = DoorModelPart:FindFirstChild("AnimationController")
				if AnimationController then
					local Animator = AnimationController:FindFirstChild("Animator")
					if Animator then
						-- Load and play the animation
						local AnimationTrack = Animator:LoadAnimation(Animation)
						AnimationTrack:Play()
						DBG:print("Playing door model animation for:", DoorModel.Name)
					else
						DBG:warn("Animator not found in DoorModel.AnimationController")
					end
				else
					DBG:warn("AnimationController not found in DoorModel")
				end
			else
				DBG:warn("DoorModel not found in door:", DoorModel.Name)
			end
		else
			DBG:warn("SingleDoorOpening animation not found in Assets.Animations")
		end
	else
		DBG:print("Door type", DoorType, "does not have door model animation support yet")
	end
end

-- Character door animation handling
local function PlayCharacterDoorAnimation(DoorType)
	-- Get the character and humanoid
	local Character = LocalPlayer.Character
	if not Character then
		DBG:warn("Character not found for door animation")
		return
	end
	
	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	if not Humanoid then
		DBG:warn("Humanoid not found for door animation")
		return
	end
	
	-- Try to find the animation in StarterPlayerScripts.Client.Assets.Animations.Door
	local StarterPlayerScripts = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
	local Client = StarterPlayerScripts:WaitForChild("Client")
	local Assets = Client:WaitForChild("Assets")
	
	if Assets then
		local Animations = Assets:FindFirstChild("Animations")
		if Animations then
			local DoorAnimations = Animations:FindFirstChild("Door")
			if DoorAnimations then
				-- Look for an animation with the same name as the door type
				local Animation = DoorAnimations:FindFirstChild(DoorType)
				if Animation then
					-- Load and play the animation on the character
					local AnimationTrack = Humanoid:LoadAnimation(Animation)
					AnimationTrack:Play()
					DBG:print("Playing character door animation:", DoorType, "for door")
					return
				else
					DBG:warn("No character animation found for door type:", DoorType, "in Assets.Animations.Door")
				end
			else
				DBG:warn("Door animations folder not found in Assets.Animations")
			end
		else
			DBG:warn("Animations folder not found in Assets")
		end
	else
		DBG:warn("Assets folder not found in StarterPlayerScripts.Client")
	end
	
	-- Fallback: if no animation is found, just log it
	DBG:print("No character animation found for door type:", DoorType)
end

-- Handle door interaction when player touches trigger
local function OnDoorTrigger(DoorModel, Hit, ChunkLoadFunction)
	local Character = Hit.Parent
	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	local Player = game.Players:GetPlayerFromCharacter(Character)
	
	-- Check if it's a player character
	if not Humanoid or not Player then
		return
	end
	
	-- Global cooldown gate (prevents auto re-trigger right after a chunk load)
	if os.clock() < GlobalDoorCooldownUntil then
		return
	end
	
	-- Check if this door interaction is already active for this player
	local InteractionKey = Player.UserId .. "_" .. DoorModel.Name
	if ActiveDoorInteractions[InteractionKey] then
		return
	end
	
	local LoadChunk = DoorModel:GetAttribute("LoadChunk")
	local DoorType = DoorModel:GetAttribute("DoorType")
	
	-- Debug: Print all attributes on the door
	DBG:print("Door attributes for", DoorModel.Name, ":")
	for _, attribute in ipairs(DoorModel:GetAttributes()) do
		DBG:print("  ", attribute, "=", DoorModel:GetAttribute(attribute))
	end
	
	if not LoadChunk then
		DBG:warn("Door", DoorModel.Name, "has no LoadChunk attribute")
		return
	end
	
	-- Before proceeding, gate exiting Professor's Lab until a starter is chosen
	local ChunkLoader = require(script.Parent.ChunkLoader)
	local currentChunk = ChunkLoader:GetCurrentChunk()
	local currentChunkName = currentChunk and (currentChunk.Model and currentChunk.Model.Name) or (currentChunk and currentChunk.Name) or nil
	if currentChunkName == "Professor's Lab" then
		local target = tostring(LoadChunk)
		if target ~= "Professor's Lab" then
			local ClientData = require(script.Parent.Parent.Plugins.ClientData)
			local pd = ClientData:Get()
			local hasStarter = (pd and ((pd.SelectedStarter ~= nil) or (pd.Party and #pd.Party > 0))) and true or false
			if not hasStarter then
				-- Show guidance and block transition
				local Say = require(script.Parent.Say)
				Say:Say("Professor", true, {"You should choose your starter before heading out."})
				-- Walk player back away from the door similarly to the NonStarterBlocker pushback
				local Trigger = DoorModel:FindFirstChild("Trigger")
				local character = LocalPlayer.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				if Trigger and hrp and Trigger:IsA("BasePart") then
					local look = Trigger.CFrame.LookVector
					local retreatPoint = Trigger.Position + (look * -6) -- move 6 studs back from door
					local target = Vector3.new(retreatPoint.X, hrp.Position.Y, retreatPoint.Z)
					local MoveTo = require(script.Parent.MoveTo)
					MoveTo.MoveToTarget(target, {
						minWalkSpeed = 12,
						timeout = 1.5,
						delayAfter = 0.5,
						preserveFacing = true,
					})
				end
				return
			end
		end
	end

	-- Mark this interaction as active
	ActiveDoorInteractions[InteractionKey] = true
	
	DBG:print("Door triggered by player:", DoorModel.Name, "Loading chunk:", LoadChunk)
	
	-- Disable player movement immediately (like Brick Bronze)
	CharacterFunctions:SetSuppressed(true)
	CharacterFunctions:CanMove(false)


    -- Start circular transition (screen goes black)
	local PlayerGui = game.Players.LocalPlayer.PlayerGui
	local GameUI = PlayerGui:FindFirstChild("GameUI")
	local CircleTransition = GameUI and GameUI:FindFirstChild("CircularTransition")
	if CircleTransition then
		UIFunctions:CircularTransition(CircleTransition, true)
		DBG:print("Started circular transition")
	end
	
	-- Hide TopBar during transition
	UI.TopBar:Hide()
	DBG:print("Hidden TopBar during transition")
	
	-- Get the door's position and direction for walking (skip autowalk for StandStill doors)
	local Trigger = DoorModel:FindFirstChild("Trigger")
	
	-- Camera transition to look at the door
	if DoorType ~= "StandStill" and Trigger then
		workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
		local CamCF = CFrame.lookAt(Trigger.Position - Trigger.CFrame.LookVector * 20 + Vector3.new(0, 5, 0), Trigger.Position)
		TweenService:Create(workspace.CurrentCamera, TweenInfo.new(0.35,Enum.EasingStyle.Circular,Enum.EasingDirection.InOut), {CFrame = CamCF}):Play()
	end
	
	-- Play both door model animation and character animation
	-- Play animations if door type is specified (skip for StandStill doors)
	if DoorType and DoorType ~= "StandStill" then
		-- Play door model animation
		PlayDoorAnimation(DoorModel, DoorType)
		-- Play character animation
		PlayCharacterDoorAnimation(DoorType)
		-- Wait for animations to play (0.23 seconds like Brick Bronze)
		task.wait(0.23)
	elseif DoorType == "StandStill" then
		DBG:print("StandStill door - skipping animations but maintaining timing")
		-- Wait the same amount of time as animated doors for consistency
		task.wait(0.23)
	end
	
	-- Only autowalk if door type is not "StandStill"
	DBG:print("DoorType:", DoorType, "Will autowalk:", DoorType ~= "StandStill")
	if DoorType ~= "StandStill" then
		local DoorPosition = Trigger and Trigger.Position or Vector3.new(0, 0, 0)
		
		-- Calculate direction to walk through the door (6 studs forward from trigger)
		local TriggerCFrame = Trigger and Trigger.CFrame or CFrame.new(DoorPosition)
		local WalkTarget = (TriggerCFrame * CFrame.new(0, 0, -6)).Position -- Walk 6 studs forward from trigger
		
		-- Make player automatically walk through the door
		Humanoid:MoveTo(WalkTarget)
		
		-- Wait for player to walk through the door
		task.wait(1.5) -- Give time for walking
	else
		DBG:print("StandStill door - skipping autowalk")
		-- Wait the same amount of time as autowalk doors for consistency
		task.wait(1.5)
	end
	
	-- Handle "Previous" LoadChunk by getting the last chunk from player data
	local ActualLoadChunk = LoadChunk
	if LoadChunk == "Previous" then
		-- Get player data to find the last chunk
		local ClientData = require(script.Parent.Parent.Plugins.ClientData)
		local PlayerData = ClientData:Get()
		
		if PlayerData and PlayerData.LastChunk then
			ActualLoadChunk = PlayerData.LastChunk
			DBG:print("Previous chunk requested, loading:", ActualLoadChunk)
		else
			DBG:warn("Previous chunk requested but no LastChunk found in player data")
			-- Fallback to a default chunk or handle error
			ActualLoadChunk = "Chunk1" -- You might want to change this to a more appropriate default
		end
	end
	
	-- Request the new chunk using the provided function
	DBG:print("About to call ChunkLoadFunction with:", ActualLoadChunk)
	

	
	-- Track this door as the entry door for the target chunk
	local ChunkLoader = require(script.Parent.ChunkLoader)
	ChunkLoader.LastDoorUsed = DoorModel
	ChunkLoader.LastDoorLoadChunk = ActualLoadChunk
	
	-- Track the current chunk as the previous chunk for return logic
	-- The door structure is: Workspace.ChunkName.Doors.DoorModel
	-- So we need to go up 2 levels to get the chunk name
	local CurrentChunk = ChunkLoader.CurrentChunk and ChunkLoader.CurrentChunk.Model
	if CurrentChunk then
		ChunkLoader.PreviousChunk = CurrentChunk.Name
		DBG:print("Set PreviousChunk to:", ChunkLoader.PreviousChunk, "LastDoorLoadChunk:", ChunkLoader.LastDoorLoadChunk)
		-- If heading into a universal facility like CatchCare, set LastChunk to the current chunk
		-- so that exiting returns to the immediate origin (not an older chunk)
		if tostring(ActualLoadChunk) == "CatchCare" then
			local ClientData = require(script.Parent.Parent.Plugins.ClientData)
			local pd = ClientData:Get()
			if pd then
				pd.LastChunk = CurrentChunk.Name
				pcall(function()
					local Events = game.ReplicatedStorage.Events
					if Events and Events.Request then
						Events.Request:InvokeServer({"UpdateLastChunk", pd.LastChunk})
					end
				end)
				DBG:print("Updated LastChunk for facility entry to:", pd.LastChunk)
			end
		end
		
	else
		DBG:warn("Could not get current chunk name for PreviousChunk tracking")
	end
	
	local success = ChunkLoadFunction(ActualLoadChunk)
	
	if success then
		DBG:print("Successfully loaded chunk:", ActualLoadChunk)
		-- After any successful chunk load, block door interactions briefly
		GlobalDoorCooldownUntil = os.clock() + 1.2
		-- Reset camera type back to Custom after door transition
		workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
		-- Re-enable movement after transition completes
		CharacterFunctions:SetSuppressed(false)
		CharacterFunctions:CanMove(true)
	else
		DBG:warn("Failed to load chunk:", ActualLoadChunk)
		-- Re-enable movement if chunk loading failed
		CharacterFunctions:SetSuppressed(false)
		CharacterFunctions:CanMove(true)
		-- Reset camera type back to Custom even if chunk loading failed
		workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	end
	
	-- Clear the interaction after a delay to allow re-entry
	task.delay(3, function()
		ActiveDoorInteractions[InteractionKey] = nil
	end)
end

-- Set up a door for interaction
function Door:Setup(DoorModel, ChunkLoadFunction)
	if not DoorModel then
		DBG:warn("Door:Setup called with nil DoorModel")
		return
	end
	
	if not ChunkLoadFunction then
		DBG:warn("Door:Setup called without ChunkLoadFunction")
		return
	end
	
	-- Check if door has required attributes
	local LoadChunk = DoorModel:GetAttribute("LoadChunk")
	if not LoadChunk then
		DBG:warn("Door", DoorModel.Name, "missing LoadChunk attribute")
		return
	end
	
	-- Find the Trigger part for the Touched event
	local Trigger = DoorModel:FindFirstChild("Trigger")
	if not Trigger then
		DBG:warn("Door", DoorModel.Name, "missing Trigger part")
		return
	end
	
	-- Make sure the Trigger is a BasePart that can detect touches
	if not Trigger:IsA("BasePart") then
		DBG:warn("Door", DoorModel.Name, "Trigger is not a BasePart")
		return
	end
	
	-- Connect Touched event
	local Connection = Trigger.Touched:Connect(function(Hit)
		OnDoorTrigger(DoorModel, Hit, ChunkLoadFunction)
	end)
	
	DBG:print("Door setup complete:", DoorModel.Name, "->", LoadChunk)
	
	return Connection
end

return Door

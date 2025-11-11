local ChunkManager = {}

local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DBG = require(ReplicatedStorage.Shared.DBG)
local NPCModule = require(script.Parent.NPC)
local ChunkEvents = require(script.Parent.ChunkEvents)
local DoorModule = require(script.Parent.Door)
local CharacterFunctions = require(script.Parent.CharacterFunctions)
local EncounterZone = require(script.Parent.EncounterZone)
local MusicManager = require(script.Parent.MusicManager)
local UIFunctions = require(script.Parent.Parent.UI.UIFunctions)
local UI = require(script.Parent.Parent.UI)
local CutsceneRegistry = require(script.Parent:WaitForChild("CutsceneRegistry"))

local Events = game.ReplicatedStorage.Events

ChunkManager.CurrentChunk = {
	Model = nil,
	NPCs = nil,
	Essentials = nil,
	Doors = nil,
	EncounterZones = nil,
	Connections = nil,
}

-- Track pending UI actions for location banner after transition hides
ChunkManager._pendingShowLocation = false
ChunkManager._pendingLocationName = nil

-- Track the last door used for entry (for proper exit positioning)
ChunkManager.LastDoorUsed = nil
-- Track the previous chunk name for return door logic
ChunkManager.PreviousChunk = nil
-- Track the LoadChunk attribute of the door we used to enter
ChunkManager.LastDoorLoadChunk = nil

local PlayerGui = game.Players.LocalPlayer.PlayerGui
local LightingManager = require(script.Parent.Parent:WaitForChild("Utilities"):WaitForChild("LightingManager"))

-- Helper function to safely enable movement (respects cutscene context)
local function SafeCanMove(enable, reason)
    local IsCutsceneActive = CutsceneRegistry:IsAnyActive()
	
	-- Also respect CharacterFunctions suppression directly
	local CharacterFunctions = require(script.Parent:WaitForChild("CharacterFunctions"))
	local MovementSuppressed = false
	pcall(function()
		MovementSuppressed = CharacterFunctions.IsSuppressed and CharacterFunctions:IsSuppressed() or false
	end)

    if not IsCutsceneActive and MovementSuppressed ~= true then
		CharacterFunctions:CanMove(enable)
		if reason then
			DBG:print("Re-enabled player movement -", reason)
		end
	else
		DBG:print("Skipped CanMove(" .. tostring(enable) .. ") - cutscene/suppression active")
	end
end

--tbl functions

-- Listen for when the circular transition finishes hiding, then show location after 0.5s if pending
pcall(function()
	UIFunctions.OnCircularTransitionHidden:Connect(function()
		if ChunkManager._pendingShowLocation == true then
			ChunkManager._pendingShowLocation = false
			local pendingName = ChunkManager._pendingLocationName
			ChunkManager._pendingLocationName = nil
			task.delay(0.5, function()
				local playerGui = game.Players.LocalPlayer.PlayerGui
				local gameUI = playerGui and playerGui:FindFirstChild("GameUI")
				local locFrame = gameUI and gameUI:FindFirstChild("NewLocation")
				if locFrame and pendingName then
					UIFunctions:ShowLocationName(locFrame, pendingName)
				end
			end)
		end
	end)
end)

function ChunkManager:ClearCurrentChunk()
	if ChunkManager.CurrentChunk then
		-- Clean up encounter zones before destroying chunk
		EncounterZone:Cleanup()
		
		if ChunkManager.CurrentChunk.Model then
			ChunkManager.CurrentChunk.Model:Destroy()
		end
		ChunkManager.CurrentChunk = nil
	else
		warn("No chunk to clear!")
	end
end

function ChunkManager:Load(Chunk: Folder, Visual: boolean, ClearCurrentChunk)
	
	local LoadStartTime = tick() 
	
	-- Should we clear our current chunk in favor for this new one?
	if ClearCurrentChunk == nil then ClearCurrentChunk = true end
	if ClearCurrentChunk then
		ChunkManager:ClearCurrentChunk()
	end
	
	Chunk.Parent = workspace

	-- Store current chunk data
	ChunkManager.CurrentChunk = {
		Model = Chunk,
		NPCs = Chunk:WaitForChild("NPCs"):GetChildren(),
		Essentials = Chunk:WaitForChild("Essentials"),
		Doors = Chunk:WaitForChild("Doors"):GetChildren(),
		EncounterZones = Chunk:WaitForChild("EncounterZones"):GetChildren(),
		Interactables = Chunk:FindFirstChild("Interactables"),
		Connections = {},
	}

	-- Set lighting if preset exists in main chunk
	local LightingPreset = ChunkManager.CurrentChunk.Essentials:FindFirstChild("Lighting")
	if LightingPreset then
		LightingManager:SetLighting(LightingPreset)
	end
	
	-- Set music if chunk has music
	MusicManager:SetChunkMusic(ChunkManager.CurrentChunk.Essentials)

	if Visual == true then -- Basically we have "Visual" chunks which only have 1 purpose and that is just for visuals, no npcs or anything / an example of this is the title chunk
		-- Still need to re-enable movement for visual chunks
		task.delay(0.8, function()
			SafeCanMove(true, "visual chunk")
		end)
		return true, ChunkManager.CurrentChunk
	end
	
	--Setup Npcs
	for _,NPC in ipairs(ChunkManager.CurrentChunk.NPCs) do
		ChunkManager.CurrentChunk.Connections[NPC.Name] = NPCModule:Setup(NPC)
	end
	
	--Setup Doors
	DBG:print("Setting up", #ChunkManager.CurrentChunk.Doors, "doors")
	for _,Door in ipairs(ChunkManager.CurrentChunk.Doors) do
		DBG:print("Setting up door:", Door.Name)
		-- Create a wrapper function that properly calls ClientRequestChunk with self
		local ChunkLoadWrapper = function(ChunkName)
			return ChunkManager:ClientRequestChunk(ChunkName)
		end
		ChunkManager.CurrentChunk.Connections[Door.Name] = DoorModule:Setup(Door, ChunkLoadWrapper)
	end
	
	--Setup Encounter Zones
	DBG:print("Setting up", #ChunkManager.CurrentChunk.EncounterZones, "encounter zones")
	for _,EncounterZonePart in ipairs(ChunkManager.CurrentChunk.EncounterZones) do
		DBG:print("Setting up encounter zone:", EncounterZonePart.Name)
		ChunkManager.CurrentChunk.Connections[EncounterZonePart.Name] = EncounterZone:Setup(EncounterZonePart)
	end
	
	--Setup Interactables (if they exist)
	if ChunkManager.CurrentChunk.Interactables then
		DBG:print("Setting up interactables for chunk:", Chunk.Name)
		local InteractablesModule = require(script.Parent.Interactables)
		InteractablesModule:Setup(ChunkManager.CurrentChunk.Interactables, Chunk.Name)
	else
		DBG:print("No interactables folder found in chunk:", Chunk.Name)
	end
	
	-- Set current chunk for encounter system
	EncounterZone:SetCurrentChunk(Chunk.Name)
	
	-- Save the previous chunk as LastChunk in player data for "Previous" door functionality
	-- Only do this if we're not loading a visual chunk and we have a valid chunk name
	-- IMPORTANT: Do NOT override LastChunk when entering universal facilities like CatchCare;
	-- it must remain the blackout return target computed server-side.
	if Visual ~= true and Chunk.Name and Chunk.Name ~= "CatchCare" then
		task.spawn(function()
			local ClientData = require(script.Parent.Parent.Plugins.ClientData)
			local PlayerData = ClientData:Get()
			
			if PlayerData then
				-- Get the previous chunk from ChunkLoader's PreviousChunk
				local PreviousChunk = ChunkManager.PreviousChunk
				if PreviousChunk then
					-- Save the previous chunk as LastChunk (the chunk we came from)
					PlayerData.LastChunk = PreviousChunk
					DBG:print("Saved LastChunk as previous chunk:", PreviousChunk, "for new chunk:", Chunk.Name)
				else
					-- If no previous chunk, save the current chunk (first time loading)
					PlayerData.LastChunk = Chunk.Name
					DBG:print("No previous chunk found, saved LastChunk as current chunk:", Chunk.Name)
				end
				
				-- Request server to update the player data
				local Events = game.ReplicatedStorage.Events
				if Events and Events.Request then
					Events.Request:InvokeServer({"UpdateLastChunk", PlayerData.LastChunk})
				end
			else
				DBG:warn("Could not get player data to save LastChunk")
			end
		end)
	end
	
	-- Position player at starting door if one exists
	ChunkManager:PositionPlayerAtStartDoor()
	
	--This should be done last: Call chunk events load function
	local LoadChunkEvent = task.spawn(function()
		local ChunkEventFunction = ChunkEvents["Load_"..Chunk.Name]
		if ChunkEventFunction then
			ChunkEventFunction(ChunkManager.CurrentChunk)
		else
			DBG:print("No chunk event function found for:", "Load_"..Chunk.Name)
		end
	end)

	DBG:print(string.format("Chunk setup in %.2f seconds!", tick() - LoadStartTime))


	return true, ChunkManager.CurrentChunk
end


function ChunkManager:GetCurrentChunk()
	return ChunkManager.CurrentChunk
end

-- Position player based on door entry logic
function ChunkManager:PositionPlayerAtStartDoor()
	DBG:print("PositionPlayerAtStartDoor called for chunk:", ChunkManager.CurrentChunk and ChunkManager.CurrentChunk.Model and ChunkManager.CurrentChunk.Model.Name or "nil")
	
	-- Priority 0: Check for LeaveData CFrame positioning (highest priority)
	local ClientData = require(script.Parent.Parent.Plugins.ClientData)
	local PlayerData = ClientData:Get()
	
    -- If we left mid-battle, use the pre-battle snapshot to place away from immediate LOS
    if PlayerData and PlayerData.PendingBattle and type(PlayerData.PendingBattle) == "table" then
        local snap = PlayerData.PendingBattle
        local currentChunkName = ChunkManager.CurrentChunk and ChunkManager.CurrentChunk.Model and ChunkManager.CurrentChunk.Model.Name
        if type(snap.Chunk) == "string" and snap.Chunk == currentChunkName then
            -- Try to place the player at a safe fallback spawn in this chunk
            local Player = game.Players.LocalPlayer
            local Character = Player.Character
            if Character and Character:FindFirstChild("HumanoidRootPart") then
                local Essentials = ChunkManager.CurrentChunk and ChunkManager.CurrentChunk.Essentials
                local fallback = Essentials and Essentials:FindFirstChild("ChunkSpawnFallBack")
                if fallback and fallback:IsA("BasePart") then
                    Character.HumanoidRootPart.CFrame = fallback.CFrame
                    DBG:print("Positioned player at safe fallback due to PendingBattle snapshot")
                end
            end
            -- Briefly suppress LOS right after spawn (client-side grace)
            local LOS = require(script.Parent.LineOfSightTriggers)
            if LOS and LOS.SetGraceUntil then
                LOS:SetGraceUntil(os.clock() + 2.0)
            end
        end
    end

    if PlayerData and PlayerData.LeaveData and PlayerData.LeaveData.Position and PlayerData.LeaveData.Rotation then
        -- Safety: ensure the loaded chunk matches LeaveData.Chunk; if not, skip using LeaveData to avoid mismatched placement
        local leaveChunkName = PlayerData.LeaveData.Chunk
        local currentChunkName = ChunkManager.CurrentChunk and ChunkManager.CurrentChunk.Model and ChunkManager.CurrentChunk.Model.Name
        if type(leaveChunkName) == "string" and leaveChunkName ~= currentChunkName then
            DBG:print("LeaveData chunk mismatch (", tostring(leaveChunkName), "!=", tostring(currentChunkName), ") - skipping LeaveData positioning")
        else
        local Player = game.Players.LocalPlayer
        local Position = Vector3.new(
            PlayerData.LeaveData.Position.X,
            PlayerData.LeaveData.Position.Y,
            PlayerData.LeaveData.Position.Z
        )
        local rot = PlayerData.LeaveData.Rotation
        -- Use only yaw (Y) to avoid pitch/roll anomalies from physics
        local yaw = (rot and rot.Y) or 0
        local SavedCFrame = CFrame.new(Position) * CFrame.Angles(0, yaw, 0)

        local function applyLeaveCFrame()
            local Character = Player.Character
            local hrp = Character and Character:FindFirstChild("HumanoidRootPart")
            if Character and hrp then
                (hrp :: BasePart).CFrame = SavedCFrame
                DBG:print("Positioned player at LeaveData position:", Position)

                -- Clear LeaveData after using it (one-time use only)
                PlayerData.LeaveData.Position = nil
                PlayerData.LeaveData.Rotation = nil
                DBG:print("Cleared LeaveData after positioning (one-time use)")

                -- Request server to clear the LeaveData
                local Events = game.ReplicatedStorage.Events
                if Events and Events.Request then
                    Events.Request:InvokeServer({"ClearLeaveDataCFrame"})
                end

                task.delay(0.8, function()
                    SafeCanMove(true, "LeaveData positioning")
                end)

                -- End circular transition (screen comes back)
                local PlayerGui = game.Players.LocalPlayer.PlayerGui
                local GameUI = PlayerGui:FindFirstChild("GameUI")
                local CircleTransition = GameUI and GameUI:FindFirstChild("CircularTransition")
                if CircleTransition then
                    UIFunctions:CircularTransition(CircleTransition, false)
                    DBG:print("Ended circular transition")
                end

                -- Show TopBar after transition (with delay)
                task.delay(1.75, function()
                    if UI and UI.TopBar then
                        UI.TopBar:Show()
                        DBG:print("Showed TopBar after transition (delayed)")
                    else
                        DBG:warn("UI or TopBar not available for showing")
                    end
                end)
                return true
            end
            return false
        end

        if not applyLeaveCFrame() then
            -- Character not ready yet; apply when it spawns
            Player.CharacterAdded:Once(function()
                task.defer(applyLeaveCFrame)
            end)
        end
        return
        end
        end
	
	if not ChunkManager.CurrentChunk or not ChunkManager.CurrentChunk.Doors then
		
		-- Show TopBar after transition (with delay) - fallback case
		task.delay(1.75, function()
			if UI and UI.TopBar then
                -- Check if any cutscene is active before showing TopBar
                local IsCutsceneActive = CutsceneRegistry:IsAnyActive()
				if not IsCutsceneActive then
					UI.TopBar:Show()
					DBG:print("Showed TopBar after transition (delayed) - fallback case")
				else
					DBG:print("Skipped TopBar:Show() - cutscene is active")
				end
			else
				DBG:warn("UI or TopBar not available for showing - fallback case")
			end
		end)

		task.delay(0.8, function()
			SafeCanMove(true, "fallback case")
		end)
		return
	end
	
	local SpawnDoor = nil
	local SpawnReason = ""
	
	-- Priority 1: Use the last door we came through (for returning to previous chunk)
	if ChunkManager.PreviousChunk and ChunkManager.LastDoorLoadChunk then
		DBG:print("Looking for return door. PreviousChunk:", ChunkManager.PreviousChunk, "LastDoorLoadChunk:", ChunkManager.LastDoorLoadChunk, "CurrentChunk:", ChunkManager.CurrentChunk.Model.Name)
		
		-- Find the door that leads back to the previous chunk
		-- We want to find a door whose LoadChunk equals the PreviousChunk
		for _, Door in ipairs(ChunkManager.CurrentChunk.Doors) do
			DBG:print("Checking door:", Door.Name, "LoadChunk:", Door:GetAttribute("LoadChunk"))
			if Door:GetAttribute("LoadChunk") == ChunkManager.PreviousChunk then
				SpawnDoor = Door
				SpawnReason = "returning through last door: " .. Door.Name
				DBG:print("Found matching return door!")
				break
			end
		end
		
		if not SpawnDoor then
			DBG:print("No return door found for PreviousChunk:", ChunkManager.PreviousChunk)
		end
	else
		DBG:print("No PreviousChunk or LastDoorLoadChunk tracked")
	end
	
	-- Priority 2: Use Start = true door (for first time entry)
	if not SpawnDoor then
		for _, Door in ipairs(ChunkManager.CurrentChunk.Doors) do
			if Door:GetAttribute("Start") == true then
				SpawnDoor = Door
				SpawnReason = "start door: " .. Door.Name
				break
			end
		end
	end
	
	-- Priority 3: Fallback to ChunkSpawnFallBack
	if not SpawnDoor then
		local FallbackSpawn = ChunkManager.CurrentChunk.Essentials:FindFirstChild("ChunkSpawnFallBack")
		if FallbackSpawn then
			local Player = game.Players.LocalPlayer
			local Character = Player.Character
			if Character and Character:FindFirstChild("HumanoidRootPart") then
				Character.HumanoidRootPart.CFrame = FallbackSpawn.CFrame
				DBG:print("Positioned player at fallback spawn:", FallbackSpawn.Name)

				task.delay(0.8, function()
					SafeCanMove(true, "door positioning")
				end)
				
				-- End circular transition (screen comes back)
				local PlayerGui = game.Players.LocalPlayer.PlayerGui
				local GameUI = PlayerGui:FindFirstChild("GameUI")
				local CircleTransition = GameUI and GameUI:FindFirstChild("CircularTransition")
				if CircleTransition then
					UIFunctions:CircularTransition(CircleTransition, false)
					DBG:print("Ended circular transition")
				end
				
				-- Show TopBar after transition (with delay)
				task.delay(1.75, function()
					if UI and UI.TopBar then
						UI.TopBar:Show()
						DBG:print("Showed TopBar after transition (delayed)")
					else
						DBG:warn("UI or TopBar not available for showing")
					end
				end)
				
				-- Show TopBar after transition (with delay)
				task.delay(1.75, function()
					if UI and UI.TopBar then
						UI.TopBar:Show()
						DBG:print("Showed TopBar after transition (delayed)")
					else
						DBG:warn("UI or TopBar not available for showing")
					end
				end)
				return
			end
		else
			DBG:print("No spawn method found - re-enabling movement anyway")
			task.delay(0.8, function()
				SafeCanMove(true, "no spawn method found")
			end)
			
			-- End circular transition (screen comes back)
			local PlayerGui = game.Players.LocalPlayer.PlayerGui
			local GameUI = PlayerGui:FindFirstChild("GameUI")
			local CircleTransition = GameUI and GameUI:FindFirstChild("CircularTransition")
			if CircleTransition then
				UIFunctions:CircularTransition(CircleTransition, false)
				DBG:print("Ended circular transition")
			end
			return
		end
	end
	
	-- Position player at the determined door
	local Trigger = SpawnDoor:FindFirstChild("Trigger")
	if not Trigger then
		DBG:warn("Spawn door has no Trigger part - re-enabling movement anyways")
		task.delay(0.8, function()
			SafeCanMove(true, "spawn door no trigger")
		end)
		
		-- End circular transition (screen comes back)
		local PlayerGui = game.Players.LocalPlayer.PlayerGui
		local GameUI = PlayerGui:FindFirstChild("GameUI")
		local CircleTransition = GameUI and GameUI:FindFirstChild("CircularTransition")
		if CircleTransition then
			UIFunctions:CircularTransition(CircleTransition, false)
			DBG:print("Ended circular transition")
		end
		return
	end
	
	-- Calculate spawn position 10 studs behind the door trigger with 180 degree rotation (and slight Y lift)
	local TriggerCFrame = Trigger.CFrame
	local SpawnCFrame = (TriggerCFrame + TriggerCFrame.LookVector * -10 + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, math.rad(180), 0)
	local SpawnPosition = SpawnCFrame.Position
	
	-- Get player character and position them (robust to Character spawn timing)
	local Player = game.Players.LocalPlayer
	local function applyDoorSpawn()
		local Character = Player.Character
		local hrp = Character and Character:FindFirstChild("HumanoidRootPart")
		if Character and hrp then
			-- Set position and rotation (Y-axis only, no X rotation)
			local LookDirection = SpawnCFrame.LookVector
			local YRotation = math.atan2(-LookDirection.X, LookDirection.Z)
			local targetCFrame = CFrame.new(SpawnPosition) * CFrame.Angles(0, YRotation, 0)
			hrp.CFrame = targetCFrame
			-- Clear any residual physics velocities that can cause fling/tumble on spawn
			if hrp.AssemblyLinearVelocity then
				hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			end
			if hrp.AssemblyAngularVelocity then
				hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
			end
			-- Nudge humanoid out of ragdoll if applicable
			local humanoid = Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				pcall(function()
					humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				end)
			end
			DBG:print("Positioned player at", SpawnReason, "Position:", SpawnPosition, "YRotation:", math.deg(YRotation))
			return true
		end
		return false
	end
	
	if applyDoorSpawn() then
		-- Re-apply shortly after to overcome physics settling, if needed
		task.defer(function()
			if applyDoorSpawn() then
				-- Re-zero velocities one more time to resist fling
				local Character = Player.Character
				local hrp = Character and Character:FindFirstChild("HumanoidRootPart")
				if hrp and hrp:IsA("BasePart") then
					hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
					hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
				end
			end
		end)

		-- Orient camera to face the door (180 degrees of player facing) on spawn
		local cam = workspace.CurrentCamera
		if cam then
			local isCutscene = CutsceneRegistry:IsAnyActive()
			if not isCutscene then
				local ch = Player.Character
				local h2 = ch and ch:FindFirstChild("HumanoidRootPart")
				if h2 and h2:IsA("BasePart") then
					local hrpPos = h2.Position
					local camPos = hrpPos + Vector3.new(0, 2.5, 0)
					local doorAim = Trigger.Position + Vector3.new(0, (Trigger.Size and Trigger.Size.Y * 0.5) or 0, 0)
					cam.CameraType = Enum.CameraType.Scriptable
					cam.CFrame = CFrame.new(camPos, doorAim)
					task.delay(0.15, function()
						cam.CameraType = Enum.CameraType.Custom
					end)
				end
			end
		end
		
		-- Re-enable player movement after positioning
		task.delay(0.8, function()
			SafeCanMove(true, "after chunk load")
		end)
		
		-- End circular transition (screen comes back)
		local PlayerGui = game.Players.LocalPlayer.PlayerGui
		local GameUI = PlayerGui:FindFirstChild("GameUI")
		local CircleTransition = GameUI and GameUI:FindFirstChild("CircularTransition")
		if CircleTransition then
			task.spawn(function()
				task.wait(0.45)
				UIFunctions:CircularTransition(CircleTransition, false)
			end)
		end
		
		-- Show TopBar after transition (with delay)
		DBG:print("Scheduling TopBar:Show() for", SpawnReason)
		task.delay(1.75, function()
			if UI and UI.TopBar then
                -- Check if any cutscene is active before showing TopBar
                local IsCutsceneActive = CutsceneRegistry:IsAnyActive()
				if not IsCutsceneActive then
					UI.TopBar:Show()
					DBG:print("Showed TopBar after transition (delayed) -", SpawnReason)
				else
					DBG:print("Skipped TopBar:Show() - cutscene is active for", SpawnReason)
				end
			else
				DBG:warn("UI or TopBar not available for showing -", SpawnReason)
			end
		end)
	else
		DBG:warn("Player character not found for positioning - deferring until CharacterAdded")
		Player.CharacterAdded:Once(function()
			task.defer(function()
				if not applyDoorSpawn() then
					-- Final attempt after a brief delay
					task.wait(0.1)
					applyDoorSpawn()
				end
			end)
		end)
	end
end

-- This is a client request to the server for a chunk. The server will then send the chunk data to the client.
function ChunkManager:ClientRequestChunk(ChunkName)
	local Call = Events.Request:InvokeServer({"RequestChunk",ChunkName})
	local properName
	if typeof(Call) == "table" then
		-- Server may redirect the requested chunk (e.g., Title Continue, CatchCare recovery)
		local serverChunkName = Call[1] or ChunkName
		properName = Call[2]
		local FoundChunk = PlayerGui:WaitForChild(serverChunkName)
		local ok, chunk = ChunkManager:Load(FoundChunk,false,true)
		if ok then
			-- Stash for post-transition location banner
			ChunkManager._pendingShowLocation = true
			ChunkManager._pendingLocationName = properName or serverChunkName
			-- Also store on current chunk for reference
			pcall(function()
				ChunkManager.CurrentChunk.ProperName = properName or serverChunkName
			end)
		end
		return ok, chunk
	end
end

return ChunkManager
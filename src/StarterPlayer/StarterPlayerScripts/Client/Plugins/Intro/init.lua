local Intro = {}

local HasSaveData = false

local TweenService = game:GetService("TweenService")
local PlayerGui = game.Players.LocalPlayer.PlayerGui

local Utilities = script.Parent.Parent:WaitForChild("Utilities")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DBG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DBG"))
local Events = ReplicatedStorage:WaitForChild("Events")

local ChunkLoader = require(Utilities:WaitForChild("ChunkLoader"))
local CharacterFunctions = require(Utilities:WaitForChild("CharacterFunctions"))
local Say = require(Utilities:WaitForChild("Say"))
local UIFunctions = require(Utilities.Parent.UI:WaitForChild("UIFunctions"))
local UI = require(Utilities.Parent:WaitForChild("UI"))

-- Safely get Audio assets
local Audio = nil
local success, result = pcall(function()
	return script.Parent.Parent:WaitForChild("Assets"):WaitForChild("Audio")
end)
if success then
	Audio = result
else
	DBG:warn("Audio assets not found, continuing without audio")
end

-- Safely get IntroUI
local IntroUI = nil
local success, result = pcall(function()
	return script.IntroUI:Clone()
end)
if success then
	IntroUI = result
else
	DBG:warn("IntroUI not found, creating minimal UI")
	-- Create a minimal UI if IntroUI doesn't exist
	IntroUI = Instance.new("ScreenGui")
	IntroUI.Name = "IntroUI"
	local Frame = Instance.new("Frame")
	Frame.Size = UDim2.fromScale(1, 1)
	Frame.BackgroundColor3 = Color3.new(0, 0, 0)
	Frame.Parent = IntroUI
	local TextLabel = Instance.new("TextLabel")
	TextLabel.Size = UDim2.fromScale(1, 1)
	TextLabel.BackgroundTransparency = 1
	TextLabel.Text = "Loading..."
	TextLabel.TextColor3 = Color3.new(1, 1, 1)
	TextLabel.TextScaled = true
	TextLabel.Parent = Frame
end

local function ToGame(Data: any, IntroChunk: Instance?)
	-- Safely destroy the intro/title chunk if it exists
	if IntroChunk then
		IntroChunk:Destroy()
	end

    -- Determine target chunk with robust priority:
    -- 1) LeaveData.Chunk (explicit save position)
    -- 2) Current saved Chunk (authoritative current location)
    -- 3) LastChunk (previous chunk fallback)
    -- 4) Chunk1 for brand-new players
    local TargetChunk = "Chunk1"
    local safeData = (type(Data) == "table" and Data) or nil
    if HasSaveData and safeData then
        -- If a pending battle snapshot exists (left mid-battle), prefer its chunk to avoid LOS re-trigger
        if safeData.PendingBattle and type(safeData.PendingBattle) == "table" then
            local snapChunk = safeData.PendingBattle.Chunk
            if type(snapChunk) == "string" and #snapChunk > 0 then
                TargetChunk = snapChunk
            end
        end
        local leaveChunk = safeData.LeaveData and safeData.LeaveData.Chunk or nil
        local currentChunk = safeData.Chunk
        local lastChunk = safeData.LastChunk
        if type(leaveChunk) == "string" and #leaveChunk > 0 then
            TargetChunk = leaveChunk
        elseif type(currentChunk) == "string" and #currentChunk > 0 then
            TargetChunk = currentChunk
        elseif type(lastChunk) == "string" and #lastChunk > 0 then
            TargetChunk = lastChunk
        else
            TargetChunk = "Chunk1"
        end
    else
        TargetChunk = "Chunk1"
    end

	-- Attempt to load target chunk
	local chunkLoaded = ChunkLoader:ClientRequestChunk(TargetChunk)
	
	-- If initial load failed and we're not already trying Chunk1, retry with Chunk1 as fallback
	if not chunkLoaded and TargetChunk ~= "Chunk1" then
		DBG:warn("[ToGame] Initial chunk load failed for:", TargetChunk, "- Retrying with Chunk1 fallback")
		task.wait(0.5) -- Brief delay before retry
		chunkLoaded = ChunkLoader:ClientRequestChunk("Chunk1")
		if chunkLoaded then
			DBG:print("[ToGame] Successfully loaded Chunk1 as fallback")
			TargetChunk = "Chunk1" -- Update for UI purposes
		end
	end
	
	if chunkLoaded then
		workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
		workspace.CurrentCamera.FieldOfView = 70
		CharacterFunctions:CanMove(true)
		if IntroUI then
			IntroUI:Destroy()
		end
		-- Avoid conflicting with Chunk1 cutscene blackout; skip transition for new players
		if safeData and safeData.Events and safeData.Events.GAME_INTRO == true then
			UIFunctions:Transition(false)
		end
		UI.TopBar:Create()
	else
		DBG:warn("[ToGame] CRITICAL: Failed to load chunk after fallback:", TargetChunk)
		DBG:warn("[ToGame] Player may be stuck on loading screen - attempting emergency Chunk1 load")
		-- Emergency fallback: try one more time with Chunk1 after a longer delay
		task.wait(1.0)
		local emergencyLoad = ChunkLoader:ClientRequestChunk("Chunk1")
		if emergencyLoad then
			DBG:print("[ToGame] Emergency Chunk1 load succeeded")
			workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
			workspace.CurrentCamera.FieldOfView = 70
			CharacterFunctions:CanMove(true)
			if IntroUI then
				IntroUI:Destroy()
			end
			UI.TopBar:Create()
		else
			DBG:warn("[ToGame] EMERGENCY LOAD FAILED - Player will be stuck!")
			-- Re-enable movement as last resort
			CharacterFunctions:CanMove(true)
		end
	end
end

function Intro:Perform(Data:any)
	DBG:print("Performing Intro!")
	
	CharacterFunctions:CanMove(false)
	
	-- Safely get Loading screen
	local Loading = nil
	local success, result = pcall(function()
		return PlayerGui:WaitForChild("Loading", 5) -- 5 second timeout instead of 99999
	end)
	if success then
		Loading = result
	else
		DBG:warn("Loading screen not found, skipping loading animations")
	end
	
	local IntroSpin = nil
	if Loading and Loading.Main and Loading.Main.Icon then
		IntroSpin = task.spawn(function()
			while true do
				task.wait()
				Loading.Main.Icon.Rotation += .1
			end
		end)
	end
	
	-- Safely load IntroChunk
	local IntroChunk = nil
	local success, result = pcall(function()
		return script:WaitForChild("IntroChunk", 5) -- 5 second timeout
	end)
	if not success then
		DBG:warn("IntroChunk not found, skipping to game")
		ToGame(Data, nil)
		return
	end
	IntroChunk = result
	
	-- Load chunk with timeout protection
	local ChunkLoaded, ChunkData = ChunkLoader:Load(IntroChunk, true)
	if not ChunkLoaded then
		DBG:warn("Failed to load IntroChunk, skipping to game")
		ToGame(Data, IntroChunk)
		return
	end
	
	-- Set camera with timeout protection
	local Camera = workspace.CurrentCamera
	Camera.CameraType = Enum.CameraType.Scriptable
	
	-- Safely set camera position
	if ChunkData and ChunkData.Essentials then
		local CameraPoint = ChunkData.Essentials:FindFirstChild("CameraPoint")
		if CameraPoint then
			Camera.CFrame = CameraPoint.CFrame
		end
	end
	
	Camera.FieldOfView = 50
	
	DBG:print("Title loaded!")
	
	task.wait(1)
	
	-- Safely handle loading screen animations
	if Loading and Loading.Main and Loading.Main.Icon then
		TweenService:Create(Loading.Main.Icon, TweenInfo.new(0.76, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
			Rotation = 500,
		}):Play()
		
		TweenService:Create(Loading.Main, TweenInfo.new(0.75, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		}):Play()
		
		TweenService:Create(Loading.Main.Icon, TweenInfo.new(0.75, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(0, 0),
		}):Play()
		
		if Loading.Main.IconShadow then
			TweenService:Create(Loading.Main.IconShadow, TweenInfo.new(0.75, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Size = UDim2.fromScale(0, 0),
			}):Play()
		end
		
		task.delay(1, function()
			if IntroSpin then
				task.cancel(IntroSpin)
			end
			Loading:Destroy()
		end)
	end
	
	IntroUI.Parent = PlayerGui
	
	local hasIntro = (type(Data) == "table" and Data.Events and Data.Events.GAME_INTRO == true)
	if hasIntro then
		DBG:print("Player has save data!")
		IntroUI.Intro.Continue.Visible = true
		HasSaveData = true
	else
		DBG:print("Player has NO save data!")
		IntroUI.Intro.Continue.Visible = false
		IntroUI.Intro.Continue.Visible = false
	end
	
	-- Safely set up Continue button
	if IntroUI.Intro and IntroUI.Intro.Continue then
		UIFunctions:NewButton(
			IntroUI.Intro.Continue,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.7,
			function()
				if Audio and Audio.SFX and Audio.SFX.StartGame then
					Audio.SFX.StartGame:Play()
				end
				if IntroUI.Intro.NewGame then
					IntroUI.Intro.NewGame.Visible = false
				end
				IntroUI.Intro.Continue.Visible = false
				UIFunctions:Transition(true)
				task.wait(0.5)
				--[[	
				Say:Say("Temp", true, {
					"Welcome to the Brainrot Catchers demo "..game.Players.LocalPlayer.DisplayName .. "!",
					"Thank you for checking out the game! We really appreciate the support!",
					"We hope you enjoy it!"
				})
				]]--
				ToGame(Data,IntroChunk)
			end
		)
	end
	
	-- Safely set up NewGame button
	if IntroUI.Intro and IntroUI.Intro.NewGame then
		UIFunctions:NewButton(
			IntroUI.Intro.NewGame,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.7,
			function()
				if Audio and Audio.SFX and Audio.SFX.StartGame then
					Audio.SFX.StartGame:Play()
				end
				IntroUI.Intro.NewGame.Visible = false
				if IntroUI.Intro.Continue then
					IntroUI.Intro.Continue.Visible = false
				end
				UIFunctions:Transition(true)
				task.wait(0.5)
				if HasSaveData then
Say:Say("System", true, {
	{ Text = "You selected to start a new game.", Emotion = "Neutral" },
	{ Text = "Starting a new game will erase all your previous progress.", Emotion = "Talking" },
	{ Text = "This action CANNOT be undone.", Emotion = "Angry" },
})
Say:Say("System", false, {
	{ Text = "Are you sure you want to restart your progress?", Emotion = "Thinking" }
})
					local Choice = Say:YieldChoice()
					Say:Exit()
					if Choice == true then
						-- Request secure server-side reset
                    local ok, res = pcall(function()
                        return Events.Request:InvokeServer({"NewGame"})
                    end)
                    if not ok or res ~= true then
							Say:Say("System", true, {
								"Failed to start a new game. Please try again."
							})
							UIFunctions:Transition(false)
							IntroUI.Intro.NewGame.Visible = true
							if IntroUI.Intro.Continue then IntroUI.Intro.Continue.Visible = true end
							return
						end
                    -- Verify reset by reloading and validating defaults
                    local newData = nil
                    pcall(function()
                        newData = Events.Request:InvokeServer({"DataGet"})
                    end)
                    local function isFresh(pd)
                        if type(pd) ~= "table" then return false end
                        if pd.SelectedStarter ~= nil then return false end
                        if pd.Starters ~= nil then return false end
                        if pd.Party and #pd.Party > 0 then return false end
                        if pd.DefeatedTrainers and next(pd.DefeatedTrainers) ~= nil then return false end
                        if pd.LeaveData ~= nil then return false end
                        return true
                    end
                    if not isFresh(newData) then
                        Say:Say("System", true, {
                            "New Game verification failed. Your data could not be cleared."
                        })
                        UIFunctions:Transition(false)
                        IntroUI.Intro.NewGame.Visible = true
                        if IntroUI.Intro.Continue then IntroUI.Intro.Continue.Visible = true end
                        return
                    end
                    HasSaveData = false
                    ToGame(newData, IntroChunk)
					else
						Say:Say("System", true, {
							"You have chosen NOT to start a new game.",
							"You will now be returned to the title screen."
						})
						UIFunctions:Transition(false)
						IntroUI.Intro.NewGame.Visible = true
						if IntroUI.Intro.Continue then
							IntroUI.Intro.Continue.Visible = true
						end
					end
				else
					
					Say:Say("Temp", true, {
						"Welcome to the Brainrot Catchers demo "..game.Players.LocalPlayer.DisplayName .. "!",
						"Thank you for checking out the game! We really appreciate the support!",
						"We hope you enjoy it!"
					})
					
                -- Ensure we initialize a fresh save on brand-new players and verify
                local _ = pcall(function()
                    Events.Request:InvokeServer({"NewGame"})
                end)
                local newData = nil
                pcall(function()
                    newData = Events.Request:InvokeServer({"DataGet"})
                end)
                local function isFresh(pd)
                    if type(pd) ~= "table" then return false end
                    if pd.SelectedStarter ~= nil then return false end
                    if pd.Starters ~= nil then return false end
                    if pd.Party and #pd.Party > 0 then return false end
                    if pd.DefeatedTrainers and next(pd.DefeatedTrainers) ~= nil then return false end
                    if pd.LeaveData ~= nil then return false end
                    return true
                end
                if not isFresh(newData) then
                    Say:Say("System", true, {
                        "New Game verification failed. Your data could not be initialized."
                    })
                    UIFunctions:Transition(false)
                    IntroUI.Intro.NewGame.Visible = true
                    if IntroUI.Intro.Continue then IntroUI.Intro.Continue.Visible = true end
                    return
                end
                ToGame(newData, IntroChunk)
				end
			end
		)
	else
		-- If no proper UI exists, just skip to game after a delay
		DBG:print("No proper intro UI found, skipping to game in 3 seconds...")
		task.delay(3, function()
			ToGame(Data, IntroChunk)
		end)
	end

end

return Intro

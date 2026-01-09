--[[
	Challenges.lua
	Client-side module for the Daily/Weekly Challenges system.
	
	Features:
	- Opens a special Challenges scene with camera positioning
	- Displays daily and weekly challenges with progress
	- Shows countdown timers until next refresh
	- Auto-refreshes when challenges update at 00:00 UTC
	- Handles notifications for challenge completion
	- Professor dialogue based on progress
]]

--// Types
type ChallengeEntry = {
	Id: string,
	Name: string,
	Description: string,
	Goal: number,
	Progress: number,
	Completed: boolean,
	Claimed: boolean,
	RewardText: string,
	Category: "Daily" | "Weekly",
}

type ChallengesData = {
	Daily: { ChallengeEntry },
	Weekly: { ChallengeEntry },
	DailyRefreshTime: number,
	WeeklyRefreshTime: number,
}

--// Module
local ChallengesModule = {}

--// State
local isOpen = false
local ChallengesChunk = nil
local OriginalCameraType = nil
local OriginalCameraCFrame = nil
local NotificationDismissThread = nil
local CurrentFilter: "Daily" | "Weekly" = "Daily"
local CachedChallengesData: ChallengesData? = nil
local PendingNotifications: { any } = {}
local IsProcessingQueue = false
local TimerUpdateThread = nil

--// Services
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

--// Module dependencies
local UIFunctions = require(script.Parent:WaitForChild("UIFunctions"))
local TopBarControl = require(script.Parent:WaitForChild("TopBarControl"))
local CharacterFunctions = require(script.Parent.Parent.Utilities.CharacterFunctions)

local Audio = script.Parent.Parent.Assets:WaitForChild("Audio")
local Events = ReplicatedStorage:WaitForChild("Events")
local Request = Events:WaitForChild("Request")
local ClientData = require(script.Parent.Parent.Plugins.ClientData)
local ChallengesConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ChallengesConfig"))

--// Animation Constants
local NOTIFICATION_OFF_POS = UDim2.new(0.5, 0, 1.2, 0)
local NOTIFICATION_ON_POS = UDim2.new(0.5, 0, 0.8, 0)
local BATTLE_END_NOTIFICATION_DELAY = 2.5

--// Color Constants
local UNCOMPLETE_BG_COLOR = Color3.fromHex("#ff5252")
local UNCOMPLETE_STROKE_COLOR = Color3.fromHex("#872b2b")
local COMPLETE_BG_COLOR = Color3.fromHex("#28da00")
local COMPLETE_STROKE_COLOR = Color3.fromHex("#177100")

--============================================================================--
-- HELPER: Battle/Encounter State Checks
--============================================================================--

local EncounterZone = nil

--- Check if player is currently in battle
--- @return boolean True if in battle
local function isInBattle(): boolean
	local pd
	pcall(function() pd = ClientData:Get() end)
	return (pd and pd.InBattle == true) or false
end

--- Check if player is currently in an encounter transition
--- @return boolean True if in encounter
local function isInEncounter(): boolean
	if not EncounterZone then
		pcall(function()
			EncounterZone = require(script.Parent.Parent.Utilities.EncounterZone)
		end)
	end
	
	if EncounterZone and EncounterZone.IsInEncounter then
		local result = false
		pcall(function()
			result = EncounterZone:IsInEncounter()
		end)
		return result
	end
	
	return false
end

--- Check if notifications should be suppressed
--- @return boolean True if in battle or encounter
local function shouldSuppressNotification(): boolean
	return isInBattle() or isInEncounter()
end

--============================================================================--
-- HELPER: Chunk Loading
--============================================================================--

--- Load the Challenges chunk from ClientChunks
--- @return Model? Cloned chunk or nil
local function loadChallengesChunk(): Model?
	local Assets = script.Parent.Parent:FindFirstChild("Assets")
	if not Assets then
		warn("[Challenges] Assets folder not found")
		return nil
	end
	
	local ClientChunks = Assets:FindFirstChild("ClientChunks")
	if not ClientChunks then
		warn("[Challenges] ClientChunks folder not found")
		return nil
	end
	
	local ChallengesSource = ClientChunks:FindFirstChild("Challenges")
	if not ChallengesSource then
		warn("[Challenges] Challenges folder not found in ClientChunks")
		return nil
	end
	
	local chunk = ChallengesSource:Clone()
	chunk.Name = "Challenges_Scene"
	chunk.Parent = Workspace
	
	return chunk
end

--============================================================================--
-- HELPER: Camera Management
--============================================================================--

--- Setup camera for the challenges scene
--- @param chunk Model The challenges chunk
local function setupCamera(chunk: Model?)
	if not chunk then return end
	
	local Essentials = chunk:FindFirstChild("Essentials")
	if not Essentials then return end
	
	local CamPos = Essentials:FindFirstChild("CamPos")
	if not CamPos then return end
	
	local camera = Workspace.CurrentCamera
	if not camera then return end
	
	OriginalCameraType = camera.CameraType
	OriginalCameraCFrame = camera.CFrame
	
	camera.CameraType = Enum.CameraType.Scriptable
	Workspace.CurrentCamera.FieldOfView = 50
	camera.CFrame = CamPos.CFrame
end

--- Restore camera to original state
local function restoreCamera()
	local camera = Workspace.CurrentCamera
	if not camera then return end
	
	if OriginalCameraType then
		camera.CameraType = OriginalCameraType
	else
		camera.CameraType = Enum.CameraType.Custom
	end
	
	Workspace.CurrentCamera.FieldOfView = 70
	
	OriginalCameraType = nil
	OriginalCameraCFrame = nil
end

--- Cleanup the challenges chunk
local function cleanupChunk()
	if ChallengesChunk then
		ChallengesChunk:Destroy()
		ChallengesChunk = nil
	end
end

--============================================================================--
-- UI: Challenge List Population
--============================================================================--

--- Populate challenges list with staggered reveal animation
--- @param scrollingFrame ScrollingFrame Frame to populate
--- @param challenges Challenges to display
local function populateChallengesList(scrollingFrame: ScrollingFrame, challenges: {any})
	if not scrollingFrame then return end
	
	local template = scrollingFrame:FindFirstChild("ChallengeTemplate")
	if not template then
		warn("[Challenges] ChallengeTemplate not found in", scrollingFrame.Name)
		return
	end
	
	-- Clear existing entries (except template, UIListLayout, UIPadding)
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:IsA("ImageButton") and child.Name ~= "ChallengeTemplate" then
			child:Destroy()
		end
	end
	
	-- Animation constants
	local STAGGER_DELAY = 0.04
	local FADE_IN_TIME = 0.2
	
	for i, challenge in ipairs(challenges) do
		local entry = template:Clone()
		entry.Name = "Challenge_" .. challenge.Id
		entry.LayoutOrder = i
		entry.Visible = true
		
		-- Apply colors based on completion status
		local targetBgColor: Color3
		local targetStrokeColor: Color3
		
		if challenge.Completed then
			targetBgColor = COMPLETE_BG_COLOR
			targetStrokeColor = COMPLETE_STROKE_COLOR
		else
			targetBgColor = UNCOMPLETE_BG_COLOR
			targetStrokeColor = UNCOMPLETE_STROKE_COLOR
		end
		
		entry.BackgroundColor3 = targetBgColor
		
		local uiStroke = entry:FindFirstChild("UIStroke")
		if uiStroke then
			uiStroke.Color = targetStrokeColor
		end
		
		-- Populate text fields
		local descLabel = entry:FindFirstChild("Description")
		if descLabel then
			descLabel.Text = challenge.Description
		end
		
		local taskNameLabel = entry:FindFirstChild("TaskName")
		if taskNameLabel then
			taskNameLabel.Text = challenge.Name or "Quest"
		end
		
		local rewardLabel = entry:FindFirstChild("Reward")
		if rewardLabel then
			rewardLabel.Text = challenge.RewardText or ""
		end
		
		-- Setup progress bar
		local progressFrame = entry:FindFirstChild("ProgressFrame")
		local progressCurrent = progressFrame and progressFrame:FindFirstChild("ProgressCurrent")
		local progressText = progressFrame and progressFrame:FindFirstChild("ProgressText")
		
		local targetProgress: number
		if challenge.Completed then
			targetProgress = 1
			if progressText then
				progressText.Text = string.format("%d/%d", challenge.Goal, challenge.Goal)
			end
		else
			targetProgress = math.clamp(challenge.Progress / challenge.Goal, 0, 1)
			if progressText then
				progressText.Text = string.format("%d/%d", challenge.Progress, challenge.Goal)
			end
		end
		
		if progressCurrent then
			progressCurrent.Size = UDim2.new(0, 0, 1, 0)
		end
		
		-- Store original transparency values for animation
		local originalBgTransparency = entry.BackgroundTransparency
		local childOriginalTransparencies: { [any]: { type: string, value: number } } = {}
		
		for _, child in ipairs(entry:GetDescendants()) do
			if child:IsA("TextLabel") then
				childOriginalTransparencies[child] = { type = "text", value = child.TextTransparency }
			elseif child:IsA("ImageLabel") then
				childOriginalTransparencies[child] = { type = "image", value = child.ImageTransparency }
			elseif child:IsA("UIStroke") then
				childOriginalTransparencies[child] = { type = "stroke", value = child.Transparency }
			end
		end
		
		-- Set to transparent for fade-in
		entry.BackgroundTransparency = 1
		for child, data in pairs(childOriginalTransparencies) do
			if data.type == "text" then
				(child :: TextLabel).TextTransparency = 1
			elseif data.type == "image" then
				(child :: ImageLabel).ImageTransparency = 1
			elseif data.type == "stroke" then
				(child :: UIStroke).Transparency = 1
			end
		end
		
		entry.Parent = scrollingFrame
		
		-- Staggered fade-in animation
		task.delay(i * STAGGER_DELAY, function()
			if not entry or not entry.Parent then return end
			
			TweenService:Create(entry, TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundTransparency = originalBgTransparency
			}):Play()
			
			for child, data in pairs(childOriginalTransparencies) do
				if child and child.Parent then
					if data.type == "text" then
						TweenService:Create(child, TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							TextTransparency = data.value
						}):Play()
					elseif data.type == "image" then
						TweenService:Create(child, TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							ImageTransparency = data.value
						}):Play()
					elseif data.type == "stroke" then
						TweenService:Create(child, TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							Transparency = data.value
						}):Play()
					end
				end
			end
			
			-- Animate progress bar
			if progressCurrent then
				TweenService:Create(progressCurrent, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
					Size = UDim2.new(targetProgress, 0, 1, 0)
				}):Play()
			end
		end)
	end
end

--============================================================================--
-- UI: Timer Updates
--============================================================================--

--- Update the refresh time labels
local function updateRefreshTimers()
	local GameUI = PlayerGui:FindFirstChild("GameUI")
	if not GameUI then return end
	
	local ChallengesFrame = GameUI:FindFirstChild("Challenges")
	if not ChallengesFrame then return end
	
	-- Update Daily Refresh Time
	local dailyRefreshLabel = ChallengesFrame:FindFirstChild("DailyRefreshTime")
	if dailyRefreshLabel and dailyRefreshLabel:IsA("TextLabel") then
		local seconds = ChallengesConfig.GetSecondsUntilDailyRefresh()
		dailyRefreshLabel.Text = "Daily Refresh: " .. ChallengesConfig.FormatTimeRemaining(seconds)
	end
	
	-- Update Weekly Refresh Time
	local weeklyRefreshLabel = ChallengesFrame:FindFirstChild("WeeklyRefreshTime")
	if weeklyRefreshLabel and weeklyRefreshLabel:IsA("TextLabel") then
		local seconds = ChallengesConfig.GetSecondsUntilWeeklyRefresh()
		weeklyRefreshLabel.Text = "Weekly Refresh: " .. ChallengesConfig.FormatTimeRemaining(seconds)
	end
end

--- Start the timer update loop
local function startTimerUpdates()
	if TimerUpdateThread then
		pcall(task.cancel, TimerUpdateThread)
	end
	
	TimerUpdateThread = task.spawn(function()
		while isOpen do
			updateRefreshTimers()
			task.wait(1)
		end
	end)
end

--- Stop the timer update loop
local function stopTimerUpdates()
	if TimerUpdateThread then
		pcall(task.cancel, TimerUpdateThread)
		TimerUpdateThread = nil
	end
end

--============================================================================--
-- UI: Listings Update
--============================================================================--

--- Update the listings based on current filter
local function updateListings()
	local GameUI = PlayerGui:FindFirstChild("GameUI")
	if not GameUI then return end
	
	local ChallengesFrame = GameUI:FindFirstChild("Challenges")
	if not ChallengesFrame then return end
	
	if not CachedChallengesData then return end
	
	-- Update the "Current" text label
	local currentLabel = ChallengesFrame:FindFirstChild("Current")
	if currentLabel and currentLabel:IsA("TextLabel") then
		currentLabel.Text = CurrentFilter
	end
	
	-- Populate the Listings frame based on current filter
	local listingsFrame = ChallengesFrame:FindFirstChild("Listings")
	if listingsFrame then
		if CurrentFilter == "Daily" then
			populateChallengesList(listingsFrame, CachedChallengesData.Daily or {})
		else
			populateChallengesList(listingsFrame, CachedChallengesData.Weekly or {})
		end
	end
end

--============================================================================--
-- UI: Full Refresh
--============================================================================--

--- Refresh the challenges UI with latest data from server
local function refreshChallengesUI()
	local GameUI = PlayerGui:FindFirstChild("GameUI")
	if not GameUI then return end
	
	local ChallengesFrame = GameUI:FindFirstChild("Challenges")
	if not ChallengesFrame then return end
	
	-- Request latest challenges from server
	local ok, challengesData = pcall(function()
		return Request:InvokeServer({"GetChallenges"})
	end)
	
	if not ok or not challengesData then
		warn("[Challenges] Failed to get challenges data from server")
		return
	end
	
	-- Cache the data for filter switching
	CachedChallengesData = challengesData :: ChallengesData
	
	-- Update listings based on current filter
	updateListings()
	
	-- Update refresh timers
	updateRefreshTimers()
	
	-- Update Professor dialogue
	local professorTalk = ChallengesFrame:FindFirstChild("ProfessorTalk")
	if professorTalk then
		local professorSay = professorTalk:FindFirstChild("ProfessorSay")
		if professorSay and professorSay:IsA("TextLabel") then
			local playerData = ClientData:Get()
			local nickname = (playerData and playerData.Nickname) or Player.Name
			
			-- Count completed challenges
			local dailyCompleted = 0
			local weeklyCompleted = 0
			
			for _, challenge in ipairs(challengesData.Daily or {}) do
				if challenge.Completed then
					dailyCompleted = dailyCompleted + 1
				end
			end
			
			for _, challenge in ipairs(challengesData.Weekly or {}) do
				if challenge.Completed then
					weeklyCompleted = weeklyCompleted + 1
				end
			end
			
			local totalCompleted = dailyCompleted + weeklyCompleted
			local totalChallenges = #(challengesData.Daily or {}) + #(challengesData.Weekly or {})
			
			if totalCompleted == 0 then
				professorSay.Text = string.format(
					"Welcome to the Research Center, %s! Complete daily and weekly tasks to earn rewards.",
					nickname
				)
			elseif totalCompleted == totalChallenges then
				professorSay.Text = string.format(
					"Incredible work, %s! You've completed all available challenges!",
					nickname
				)
			else
				local messages = {
					string.format("I see your research is going well, keep it up %s!", nickname),
					string.format("Great progress on your challenges, %s!", nickname),
					string.format("Your dedication to research is admirable, %s!", nickname),
					string.format("Keep up the excellent work, %s!", nickname),
				}
				professorSay.Text = messages[math.random(1, #messages)]
			end
		end
	end
	
	-- Setup sort button handlers
	local sortDailyBtn = ChallengesFrame:FindFirstChild("SortDaily")
	local sortWeeklyBtn = ChallengesFrame:FindFirstChild("SortWeekly")
	
	if sortDailyBtn and not sortDailyBtn:GetAttribute("Connected") then
		sortDailyBtn:SetAttribute("Connected", true)
		UIFunctions:NewButton(
			sortDailyBtn,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.7,
			function()
				Audio.SFX.Click:Play()
				CurrentFilter = "Daily"
				updateListings()
			end
		)
	end
	
	if sortWeeklyBtn and not sortWeeklyBtn:GetAttribute("Connected") then
		sortWeeklyBtn:SetAttribute("Connected", true)
		UIFunctions:NewButton(
			sortWeeklyBtn,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.7,
			function()
				Audio.SFX.Click:Play()
				CurrentFilter = "Weekly"
				updateListings()
			end
		)
	end
end

--============================================================================--
-- PUBLIC: Open/Close
--============================================================================--

--- Open the Challenges scene
function ChallengesModule:Open()
	if isOpen then return end
	isOpen = true
	
	-- Reset filter to default
	CurrentFilter = "Daily"
	
	Audio.SFX.Open:Play()
	
	-- Load the challenges chunk
	ChallengesChunk = loadChallengesChunk()
	
	-- Setup camera
	if ChallengesChunk then
		setupCamera(ChallengesChunk)
	end
	
	-- Show the UI
	local GameUI = PlayerGui:FindFirstChild("GameUI")
	if not GameUI then
		warn("[Challenges] GameUI not found")
		return
	end
	
	local ChallengesFrame = GameUI:FindFirstChild("Challenges")
	if not ChallengesFrame then
		warn("[Challenges] Challenges frame not found in GameUI")
		return
	end
	
	-- Refresh the challenges data
	refreshChallengesUI()
	
	-- Start timer updates
	startTimerUpdates()
	
	-- Show the frame
	ChallengesFrame.Visible = true
end

--- Close the Challenges scene
function ChallengesModule:Close()
	if not isOpen then return end
	isOpen = false
	
	-- Stop timer updates
	stopTimerUpdates()
	
	-- Notify TopBar that we're closed
	pcall(function()
		TopBarControl.NotifyClosed("Challenges")
	end)
	
	Audio.SFX.Close:Play()
	
	-- Restore camera
	restoreCamera()
	
	-- Cleanup chunk
	cleanupChunk()
	
	-- Re-enable movement
	CharacterFunctions:CanMove(true)
	
	local GameUI = PlayerGui:FindFirstChild("GameUI")
	if not GameUI then return end
	
	local ChallengesFrame = GameUI:FindFirstChild("Challenges")
	if not ChallengesFrame then return end
	
	ChallengesFrame.Visible = false
end

--============================================================================--
-- NOTIFICATIONS: Queue Processing
--============================================================================--

--- Process pending notifications queue
local function processNotificationQueue()
	if IsProcessingQueue then return end
	if #PendingNotifications == 0 then return end
	
	IsProcessingQueue = true
	
	while #PendingNotifications > 0 do
		while shouldSuppressNotification() do
			task.wait(0.5)
		end
		
		local data = table.remove(PendingNotifications, 1)
		if data then
			ChallengesModule:_showNotificationImmediate(data)
			task.wait(6)
		end
	end
	
	IsProcessingQueue = false
end

--- Show challenge completion notification (queues if in battle)
--- @param data table Notification data
function ChallengesModule:ShowCompletionNotification(data: any)
	if shouldSuppressNotification() then
		table.insert(PendingNotifications, data)
		return
	end
	
	self:_showNotificationImmediate(data)
end

--- Internal: Display the notification immediately
--- @param data table Notification data
function ChallengesModule:_showNotificationImmediate(data: any)
	local GameUI = PlayerGui:FindFirstChild("GameUI")
	if not GameUI then return end
	
	local notification = GameUI:FindFirstChild("ChallengeCompletedNotification")
	if not notification then
		warn("[Challenges] ChallengeCompletedNotification not found in GameUI")
		return
	end
	
	-- Cancel any existing dismiss thread
	if NotificationDismissThread then
		pcall(task.cancel, NotificationDismissThread)
		NotificationDismissThread = nil
	end
	
	-- Populate notification data
	local descLabel = notification:FindFirstChild("ChallengeDescription")
	if descLabel and descLabel:IsA("TextLabel") then
		descLabel.Text = data.Description or "Challenge completed!"
	end
	
	local receivedFrame = notification:FindFirstChild("Recieved")
	if receivedFrame then
		local receivedLabel = receivedFrame:FindFirstChild("RecievedItem")
		if receivedLabel and receivedLabel:IsA("TextLabel") then
			receivedLabel.Text = "Recieved: " .. (data.RewardText or "Reward")
		end
	end
	
	-- Setup dismiss button
	local dismissButton = notification:FindFirstChild("DismissButton")
	local dismissCountdown = 5
	
	if dismissButton then
		local dontChange = dismissButton:FindFirstChild("DontChange")
		if dontChange and dontChange:IsA("TextLabel") then
			dontChange.Text = string.format("Dismiss (%d)", dismissCountdown)
		end
		
		if not dismissButton:GetAttribute("DismissConnected") then
			dismissButton:SetAttribute("DismissConnected", true)
			UIFunctions:NewButton(
				dismissButton,
				{"Action"},
				{ Click = "One", HoverOn = "One", HoverOff = "One" },
				0.3,
				function()
					Audio.SFX.Click:Play()
					ChallengesModule:HideCompletionNotification()
				end
			)
		end
	end
	
	-- Show notification
	notification.Position = NOTIFICATION_OFF_POS
	notification.Visible = true
	
	TweenService:Create(notification, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Position = NOTIFICATION_ON_POS,
	}):Play()
	
	-- Start countdown
	NotificationDismissThread = task.spawn(function()
		for i = dismissCountdown, 1, -1 do
			if dismissButton then
				local dontChange = dismissButton:FindFirstChild("DontChange")
				if dontChange and dontChange:IsA("TextLabel") then
					dontChange.Text = string.format("Dismiss (%d)", i)
				end
			end
			task.wait(1)
		end
		ChallengesModule:HideCompletionNotification()
	end)
	
	pcall(function()
		Audio.SFX.Click:Play()
	end)
end

--- Hide challenge completion notification
function ChallengesModule:HideCompletionNotification()
	if NotificationDismissThread then
		pcall(task.cancel, NotificationDismissThread)
		NotificationDismissThread = nil
	end
	
	local GameUI = PlayerGui:FindFirstChild("GameUI")
	if not GameUI then return end
	
	local notification = GameUI:FindFirstChild("ChallengeCompletedNotification")
	if not notification then return end
	
	TweenService:Create(notification, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Position = NOTIFICATION_OFF_POS,
	}):Play()
	
	task.delay(0.35, function()
		notification.Visible = false
	end)
end

--============================================================================--
-- INITIALIZATION
--============================================================================--

--- Initialize the module and connect to server events
function ChallengesModule:Init()
	local Communicate = Events:FindFirstChild("Communicate")
	if Communicate then
		Communicate.OnClientEvent:Connect(function(eventType: string, data: any)
			if eventType == "ChallengeCompleted" then
				ChallengesModule:ShowCompletionNotification(data)
				
			elseif eventType == "ChallengesRefreshed" then
				-- Challenges have refreshed on the server
				-- If we're on the challenges screen, auto-refresh
				if isOpen then
					refreshChallengesUI()
				end
				
			elseif eventType == "BattleOver" then
				-- Battle has ended, process queued notifications
				if #PendingNotifications > 0 then
					task.delay(BATTLE_END_NOTIFICATION_DELAY, function()
						processNotificationQueue()
					end)
				end
			end
		end)
	end
end

-- Auto-initialize
task.spawn(function()
	ChallengesModule:Init()
end)

return ChallengesModule

--// Services
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Events = ReplicatedStorage:WaitForChild("Events")

--// Player
local Player = Players.LocalPlayer

--// Module Requires
local Utilities = script:WaitForChild("Utilities")
local Plugins = script:WaitForChild("Plugins")

local DeviceService = require(Utilities:WaitForChild("DeviceService"))
print("DeviceService loaded")
local DBG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DBG"))
print("DBG loaded")
local CharacterFunctions = require(Utilities:WaitForChild("CharacterFunctions"))
print("CharacterFunctions loaded")
local EncounterZone = require(Utilities:WaitForChild("EncounterZone"))
print("EncounterZone loaded")
local MusicManager = require(Utilities:WaitForChild("MusicManager"))
print("MusicManager loaded")
local ClientInit = require(Utilities:WaitForChild("ClientInit"))
print("ClientInit loaded")
local ClientData = require(Plugins:WaitForChild("ClientData"))
print("ClientData loaded")
local Intro = require(Plugins:WaitForChild("Intro"))
print("Intro loaded")
-- Note: Delay requiring UI to avoid early init issues before GameUI exists

-- Preload core animations in the background
pcall(function()
	local Preloader = require(Utilities:WaitForChild("AnimationPreloader"))
	task.spawn(function()
		Preloader:PreloadCore()
	end)
end)

DBG:Init(true) -- Change to true/false to enable/disable debug messages in the output.

local printDebugInfo = true

if printDebugInfo then
	DBG:print("=== DEBUG INFO ===")
	DBG:print("Username:", Player.Name)
	DBG:print("DisplayName:", Player.DisplayName)
	DBG:print("UserId:", Player.UserId)
	DBG:print("Account Age (days):", Player.AccountAge)
	DBG:print("MembershipType:", tostring(Player.MembershipType))
	DBG:print("LocaleId:", Player.LocaleId)

	DBG:print("=== PLATFORM ===")
	DBG:print("Platform:", DeviceService.Enumate.Platform.Name[DeviceService:GetDevicePlatform()])

	DBG:print("=== INPUT CAPABILITIES ===")
	DBG:print("Touch Enabled:", UserInputService.TouchEnabled)
	DBG:print("Keyboard Enabled:", UserInputService.KeyboardEnabled)
	DBG:print("Mouse Enabled:", UserInputService.MouseEnabled)
	DBG:print("Gamepad Enabled:", UserInputService.GamepadEnabled)
	DBG:print("VREnabled:", UserInputService.VREnabled)

	DBG:print("=== ENVIRONMENT ===")
	DBG:print("Is Studio:", RunService:IsStudio())
	DBG:print("Is Client:", RunService:IsClient())
	DBG:print("PlaceId:", game.PlaceId)
	DBG:print("GameId:", game.GameId)
	DBG:print("JobId:", game.JobId)

end

DBG:print("=== Welcome to Brainrot Catchers, " .. Player.DisplayName .. "! Please report any bugs you see below this line. ===")

--Init client
--Get client data
local Data = nil
local function tryInitClientData(): any
	local attempts = 0
	local maxAttempts = 8
	local waitTime = 0.05
	while attempts < maxAttempts and Data == nil do
		attempts += 1
		pcall(function()
			Data = ClientData:Init()
		end)
		if Data == nil then
			task.wait(waitTime)
			waitTime = math.min(waitTime * 2, 0.5)
		end
	end
	return Data
end

tryInitClientData()
if not Data then
	DBG:warn("ClientData.Init returned nil after retries.")
	-- One more passive wait in case the server is about to push
	local start = os.clock()
	while (os.clock() - start) < 1.0 and Data == nil do
		pcall(function()
			Data = ClientData:Init()
		end)
		if Data then break end
		task.wait(0.1)
	end
end
if not Data then
	DBG:warn("Client data failed to load. You may be kicked by the server.")
end

--Perform intro


--Wait for our character to exist
repeat task.wait() until game.Players.LocalPlayer.Character
CharacterFunctions:Init(game.Players.LocalPlayer.Character)

-- Initialize encounter system
EncounterZone:Init()

-- Initialize music manager
MusicManager:Init()

-- Initialize battle system (BattleSystemV2 via ClientInit)
-- ClientInit automatically initializes and connects BattleSystemV2

-- Disable original Roblox PlayerList
game.StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)

-- Disable Reset button
pcall(function()
    game:GetService("StarterGui"):SetCore("ResetButtonCallback", false)
end)

-- Initialize UI systems
local UI = require(script.UI)
UI.PlayerList:Init()
local UIFunctions = require(script.UI.UIFunctions)

-- Initialize Save UI bindings (ConfirmSave button callback)
pcall(function()
    if UI and UI.Save and UI.Save.Init then
        UI.Save:Init()
    end
end)

Intro:Perform(Data) --We need to pass our data into the intro as it needs to display some info.

-- Show PlayerList when TopBar is shown (only once per session)
local playerListShown = false

-- Hook into TopBar Show method to trigger PlayerList
local originalTopBarShow = UI.TopBar.Show
UI.TopBar.Show = function(self, ...)
	-- Call original Show method
	originalTopBarShow(self, ...)
	
	-- Show PlayerList only once per session when TopBar is shown
	if not playerListShown then
		playerListShown = true
		UI.PlayerList:ShowWhenReady()
	end
end

-- Handle server-sent client data updates
Events.Communicate.OnClientEvent:Connect(function(EventType, Data)
	if EventType == "ClientData" then
		DBG:print("CLIENT DATA: Received update from server")
		DBG:print("Data received:", Data)
		ClientData:ServerForceUpdateData(Data)
	elseif EventType == "SaveSuccess" then
		print("[Client] SaveSuccess received - autosave completed")
		-- Show SaveNotification animation if available
		pcall(function()
			local pg = Players.LocalPlayer.PlayerGui
			local gui = pg and pg:FindFirstChild("GameUI")
			local frame = gui and gui:FindFirstChild("SaveNotification")
			if frame and UIFunctions and UIFunctions.SaveNotificationSuccess then
				UIFunctions:SaveNotificationSuccess(frame)
			end
		end)
	end
end)

-- Start client-side AutoSave loop (saves only when conditions are safe)
pcall(function()
    local AutoSave = require(Utilities:WaitForChild("AutoSave"))
    AutoSave:Start()
end)


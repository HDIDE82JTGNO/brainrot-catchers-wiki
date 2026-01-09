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
local GameContext = require(Utilities:WaitForChild("GameContext"))
print("GameContext loaded")
local Intro = require(Plugins:WaitForChild("Intro"))
print("Intro loaded")
-- Initialize player click detectors for Trade context
pcall(function()
	require(Utilities:WaitForChild("PlayerClickDetectors"))
end)
-- Note: Delay requiring UI to avoid early init issues before GameUI exists

local function refreshContext(): string
	local ctx = GameContext:Get()
	pcall(function()
		Player:SetAttribute("ClientContext", ctx)
	end)
	return ctx
end

local CurrentContext = refreshContext()

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

	DBG:print("=== CONTEXT ===")
	DBG:print("Context:", CurrentContext)

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

-- Set camera max zoom distance
Player.CameraMaxZoomDistance = 20

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
local CurrentRequest = UI.CurrentRequest
local TradeUI = UI.Trade
UI.PlayerList:Init()
UI.WorldInfo:Init()
local UIFunctions = require(script.UI.UIFunctions)

-- Initialize Save UI bindings (ConfirmSave button callback)
pcall(function()
    if UI and UI.Save and UI.Save.Init then
        UI.Save:Init()
    end
end)

-- Initialize CTRL UI bindings (LocationList buttons)
pcall(function()
    local CTRLModule = require(script.UI.CTRL)
    if CTRLModule and CTRLModule.Init then
        CTRLModule:Init()
    end
end)

-- Initialize Admin Panel
	pcall(function()
    if UI and UI.AdminPanel and UI.AdminPanel.Init then
        UI.AdminPanel:Init()
    end
end)


CurrentContext = refreshContext()
local targetChunkOverride = GameContext:GetTargetChunk()

--We need to pass our data into the intro as it needs to display some info.
if CurrentContext == "Trade" then
	Intro:Perform(Data, {
		Context = CurrentContext,
		SkipIntro = true,
		TargetChunkOverride = targetChunkOverride,
	})
else
	Intro:Perform(Data, {
		Context = CurrentContext,
		TargetChunkOverride = targetChunkOverride,
	})
end

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

-- Check Port-A-Vault ownership after intro completes (TopBar should be created by then)
task.spawn(function()
	-- Wait a bit for TopBar to be fully initialized
	task.wait(1)
	if UI and UI.TopBar and UI.TopBar.CheckPortAVaultOwnership then
		UI.TopBar:CheckPortAVaultOwnership()
	end
end)

-- Handle server-sent client data updates
Events.Communicate.OnClientEvent:Connect(function(EventType, Data)
	if EventType == "ClientData" then
		DBG:print("CLIENT DATA: Received update from server")
		DBG:print("Data received:", Data)
		ClientData:ServerForceUpdateData(Data)
		
		-- Restore repel state if present
		if Data and Data.RepelState and Data.RepelState.ActiveSteps and Data.RepelState.ActiveSteps > 0 then
			EncounterZone:AddImmunitySteps(Data.RepelState.ActiveSteps)
			DBG:print("[Repel] Restored repel state:", Data.RepelState.ItemName, "with", Data.RepelState.ActiveSteps, "steps")
		end
		
		-- Check Port-A-Vault ownership when client data updates
		task.spawn(function()
			if UI and UI.TopBar and UI.TopBar.CheckPortAVaultOwnership then
				UI.TopBar:CheckPortAVaultOwnership()
			end
		end)
	elseif EventType == "RepelActivated" then
		-- Handle repel activation
		if Data and Data.Steps and Data.Steps > 0 then
			EncounterZone:AddImmunitySteps(Data.Steps)
			DBG:print("[Repel] Activated", Data.ItemName, "for", Data.Steps, "steps")
		end
	elseif EventType == "BattleRequestIncoming" or EventType == "TradeRequestIncoming" or EventType == "ClearRequests" then
		CurrentRequest:HandleIncoming(EventType, Data)
	elseif EventType == "BattleRequestReply" then
		-- Reply to the requester (declined/accepted)
		if Data and type(Data) == "table" then
			local Say = require(Utilities:WaitForChild("Say"))
			-- Always close any waiting prompt
			Say:Exit()
			-- Only show decline/error messages; on accept, stay silent
			if Data.Accepted == false then
				local msg = Data.Message or ((Data.FromDisplayName or "Player") .. " has declined your battle request.")
				Say:Say("System", true, {msg})
			elseif type(Data.Message) == "string" and Data.Message ~= "" then
				Say:Say("System", true, {Data.Message})
			end
			-- Restore TopBar if it was hidden
			pcall(function()
				local UI = require(script.UI)
				if UI and UI.TopBar then
					UI.TopBar:SetSuppressed(false)
					UI.TopBar:Show()
				end
			end)
		end
	elseif EventType == "TradeRequestReply" then
		if Data and type(Data) == "table" then
			local Say = require(Utilities:WaitForChild("Say"))
			Say:Exit()
			if Data.Accepted == false then
				local msg = Data.Message or ((Data.FromDisplayName or "Player") .. " has declined your trade request.")
				Say:Say("System", true, {msg})
			elseif Data.Accepted == true then
				print(("[Trade] %s accepted your trade request (placeholder)."):format(Data.FromDisplayName or "Player"))
			elseif type(Data.Message) == "string" and Data.Message ~= "" then
				Say:Say("System", true, {Data.Message})
			end
			-- Restore TopBar if it was hidden
			pcall(function()
				local UI = require(script.UI)
				if UI and UI.TopBar then
					UI.TopBar:SetSuppressed(false)
					UI.TopBar:Show()
				end
			end)
		end
	elseif EventType == "TradeStarted" or EventType == "TradeChat" or EventType == "TradeReady" or EventType == "TradeConfirm" or EventType == "TradeCancelled" or EventType == "TradeOfferUpdated" or EventType == "TradeFinalized" then
		if TradeUI and TradeUI.HandleEvent then
			TradeUI:HandleEvent(EventType, Data)
		end
	elseif EventType == "StartBattle" then
		-- Clear any waiting messages before battle starts
		pcall(function()
			local Say = require(Utilities:WaitForChild("Say"))
			Say:Exit()
		end)
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


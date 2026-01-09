--!nocheck
local CTRLModule = {}
local isOpen = false

--// Services
local TweenService: TweenService = game:GetService("TweenService")
local TeleportService: TeleportService = game:GetService("TeleportService")

local Audio = script.Parent.Parent.Assets:WaitForChild("Audio")

--// Modules
local UIFunctions = require(script.Parent:WaitForChild("UIFunctions"))
local TopBarControl = require(script.Parent:WaitForChild("TopBarControl"))
local Say = require(script.Parent.Parent.Utilities:WaitForChild("Say"))
local CharacterFunctions = require(script.Parent.Parent.Utilities:WaitForChild("CharacterFunctions"))
local MusicManager = require(script.Parent.Parent.Utilities:WaitForChild("MusicManager"))
local GameContext = require(script.Parent.Parent.Utilities:WaitForChild("GameContext"))
local StudBurstEmitter = require(script.Parent:WaitForChild("Effects"):WaitForChild("StudBurstEmitter"))
local SaveModule = require(script.Parent:WaitForChild("Save"))
local SettingsModule = require(script.Parent:WaitForChild("Settings"))
local ShopModule = require(script.Parent:WaitForChild("Shop"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Events = ReplicatedStorage:WaitForChild("Events")
local Request = Events:WaitForChild("Request")

--// Helper function to get UI reference
local function getUI()
	local ok, UI = pcall(function()
		return require(script.Parent.Parent.UI)
	end)
	return ok and UI or nil
end

--// Place IDs
local BATTLE_HUB_PLACE_ID = 118790003195513
local TRADE_HUB_PLACE_ID = 87280409692047
local STORY_MODE_PLACE_ID = 71897468985259 -- MAIN_GAME_PLACE_ID from Config

--// Animation Constants
local OPEN_SIZE: UDim2 = UDim2.new(0.646, 0, 0.775, 0)
local CLOSED_SIZE: UDim2 = UDim2.fromScale(0, 0)

--// Teleport Animation Function
local function playSquareGridTeleportAnimation()
	local PlayerGui = game.Players.LocalPlayer.PlayerGui
	local GameUI = PlayerGui:WaitForChild("GameUI")
	
	-- Create black frame covering entire screen
	local blackScreen = Instance.new("Frame")
	blackScreen.Name = "TeleportTransition"
	blackScreen.BackgroundColor3 = Color3.new(0, 0, 0) -- Black
	blackScreen.BackgroundTransparency = 1 -- Start fully transparent
	blackScreen.BorderSizePixel = 0
	blackScreen.Size = UDim2.new(1, 0, 1, 0)
	blackScreen.Position = UDim2.new(0.5, 0, 0.5, 0)
	blackScreen.AnchorPoint = Vector2.new(0.5, 0.5)
	blackScreen.ZIndex = 1000 -- High z-index to appear on top
	blackScreen.Visible = true
	blackScreen.Parent = GameUI
	
	-- Animation sequence
	return task.spawn(function()
		-- Call StudBurstEmitter (needs a ScreenGui, GameUI should be a ScreenGui)
		if GameUI:IsA("ScreenGui") then
			StudBurstEmitter.playBurst(GameUI)
		end
		
		-- Fade out chunk music and fade black screen simultaneously
		MusicManager:StopMusic()
		
		-- Fade black screen from transparency 1 to 0 over 0.75 seconds
		local fadeTween = TweenService:Create(
			blackScreen,
			TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{BackgroundTransparency = 0}
		)
		fadeTween:Play()
		fadeTween.Completed:Wait()
		
		-- Wait 0.5 seconds
		task.wait(0.5)
	end)
end

--// CTRL Open
function CTRLModule:Open(All)
	if isOpen then return end -- Already open, don't open again
	
	isOpen = true
	local CTRL: ScreenGui & {
		Shadow: { Image: ImageLabel },
		Topbar: {
			Size: UDim2,
			Icon: ImageLabel,
			IconShadow: ImageLabel,
			Title: TextLabel,
		},
		Darken: Frame,
	} = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("CTRL")
	
	Audio.SFX.Open:Play()

	CTRL.Visible = true
	CTRL.Size = CLOSED_SIZE

	-- Main Frame
	TweenService:Create(CTRL, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Size = OPEN_SIZE,
	}):Play()
	
	CTRL.Position = UDim2.new(0.5, 0, 0.5, 0)

	-- Shadow
	if CTRL:FindFirstChild("Shadow") and CTRL.Shadow:FindFirstChild("Image") then
		CTRL.Shadow.Image.ImageTransparency = 1
		TweenService:Create(CTRL.Shadow.Image, TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			ImageTransparency = 0.5,
		}):Play()
	end

	-- Topbar
	if CTRL:FindFirstChild("Topbar") then
		CTRL.Topbar.Size = UDim2.fromScale(1, 0.165)
		TweenService:Create(CTRL.Topbar, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(1, 0.107),
		}):Play()

		-- Icon + Shadow
		if CTRL.Topbar:FindFirstChild("Icon") then
			CTRL.Topbar.Icon.Rotation = 25
			CTRL.Topbar.Icon.Position = UDim2.new(0.05, 0, 0.341, 0)
			TweenService:Create(CTRL.Topbar.Icon, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Rotation = 0,
				Position = UDim2.new(0.041, 0, 0.185, 0),
			}):Play()
		end
		
		if CTRL.Topbar:FindFirstChild("IconShadow") then
			CTRL.Topbar.IconShadow.Position = UDim2.new(0.084, 0, 0.682, 0)
			TweenService:Create(CTRL.Topbar.IconShadow, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.066, 0, 0.526, 0),
			}):Play()
		end

		-- Title
		if CTRL.Topbar:FindFirstChild("Title") then
			CTRL.Topbar.Title.MaxVisibleGraphemes = 0
			TweenService:Create(CTRL.Topbar.Title, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				MaxVisibleGraphemes = 11,
			}):Play()
		end
	end

	-- Darken
	if CTRL:FindFirstChild("Darken") then
		CTRL.Darken.Size = CLOSED_SIZE
		TweenService:Create(CTRL.Darken, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
			Size = UDim2.new(4.0125*1.2, 0,6.0945*1.2, 0),	
		}):Play()
	end
end

--// CTRL Close
function CTRLModule:Close(All)
	All = All or {} -- Make All parameter optional
	if not isOpen then return end -- Not open, don't close
	
	isOpen = false
	
	-- Close Shop if it's open (since Shop is opened from CTRL)
	pcall(function()
		ShopModule:Close()
	end)
	
	-- Notify TopBar that we're closed
	pcall(function()
		TopBarControl.NotifyClosed("CTRL")
	end)
	
	local CTRL: ScreenGui & {
		Shadow: { Image: ImageLabel },
		Topbar: {
			Size: UDim2,
			Icon: ImageLabel,
			IconShadow: ImageLabel,
			Title: TextLabel,
		},
		Darken: Frame,
	} = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("CTRL")

	Audio.SFX.Close:Play()
	
	task.delay(0.1, function()
		TweenService:Create(CTRL, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Size = CLOSED_SIZE,
		}):Play()
	end)

	if CTRL:FindFirstChild("Shadow") and CTRL.Shadow:FindFirstChild("Image") then
		TweenService:Create(CTRL.Shadow.Image, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			ImageTransparency = 1,
		}):Play()
	end

	if CTRL:FindFirstChild("Topbar") then
		TweenService:Create(CTRL.Topbar, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(1, 0.1),
		}):Play()

		if CTRL.Topbar:FindFirstChild("Icon") then
			TweenService:Create(CTRL.Topbar.Icon, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Rotation = 25,
				Position = UDim2.new(0.05, 0, 0.341, 0),
			}):Play()
		end
		
		if CTRL.Topbar:FindFirstChild("IconShadow") then
			TweenService:Create(CTRL.Topbar.IconShadow, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.084, 0, 0.682, 0),
			}):Play()
		end

		if CTRL.Topbar:FindFirstChild("Title") then
			TweenService:Create(CTRL.Topbar.Title, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				MaxVisibleGraphemes = 0,
			}):Play()
		end
	end

	if CTRL:FindFirstChild("Darken") then
		TweenService:Create(CTRL.Darken, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Size = CLOSED_SIZE,
		}):Play()
	end

	task.delay(0.4, function()
		CTRL.Visible = false
	end)
end

--// Handle Location Button Click
local function handleLocationButtonClick(placeId: number)
	task.spawn(function()
		-- Show save confirmation dialog
		Say:Say("System", false, {"You must save before using the CTRL Center, proceed?"})
		local choice = Say:YieldChoice()
		
		-- Close the confirmation dialog
		Say:Exit()
		
		if choice == true then
			-- User chose Yes - attempt to save
			local ok, reason = Request:InvokeServer({"ManualSave"})
			
			if ok == true then
				-- Save successful
				Say:Say("System", true, {"Save successful!"})
				-- Wait for the Say message to close
				repeat
					task.wait(0.1)
				until not Say:IsActive()
				
				-- Play square grid teleport animation and wait for completion
				-- Animation duration: appear (0.1s) + resize (0.5s) + wait (0.5s) = 1.1s total
				playSquareGridTeleportAnimation()
				-- Wait for animation to complete
				task.wait(2)
				
				-- Teleport to the requested place
				local success, err = pcall(function()
					-- If teleporting to Story Mode from Battle Hub or Trade Hub, pass teleport data
					if placeId == STORY_MODE_PLACE_ID then
						local currentContext = GameContext:Get()
						local teleportData = nil
						
						-- Determine source place based on current context
						if currentContext == "Battle" then
							teleportData = { sourcePlace = "BattleHub" }
						elseif currentContext == "Trade" then
							teleportData = { sourcePlace = "TradeHub" }
						end
						
						-- Use TeleportAsync with teleport data if we have it, otherwise use Teleport
						if teleportData then
							local teleportOptions = Instance.new("TeleportOptions")
							teleportOptions:SetTeleportData(teleportData)
							TeleportService:TeleportAsync(placeId, {game.Players.LocalPlayer}, teleportOptions)
						else
							TeleportService:Teleport(placeId, game.Players.LocalPlayer)
						end
					else
						-- For other places, use regular Teleport
						TeleportService:Teleport(placeId, game.Players.LocalPlayer)
					end
				end)
				
				if not success then
					warn("[CTRL] Failed to teleport:", err)
				end
			else
				-- Save failed - restore TopBar and movement
				Say:Say("System", true, {"Save failed!"})
				-- Wait for the Say message to close
				repeat
					task.wait(0.1)
				until not Say:IsActive()
				
				-- Restore TopBar and movement
				local UI = getUI()
				if UI and UI.TopBar then
					UI.TopBar:SetSuppressed(false)
					UI.TopBar:Show()
				end
				CharacterFunctions:CanMove(true)
			end
		else
			-- User chose No - restore TopBar and movement
			local UI = getUI()
			if UI and UI.TopBar then
				UI.TopBar:SetSuppressed(false)
				UI.TopBar:Show()
			end
			CharacterFunctions:CanMove(true)
		end
	end)
end

--// CTRL Init
function CTRLModule:Init()
	local CTRL = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("CTRL")
	local LocationList = CTRL:WaitForChild("LocationList")
	
	-- Get current context
	local currentContext = GameContext:Get()
	
	-- Set up StoryMode button
	local StoryModeButton = LocationList:WaitForChild("StoryMode")
	if StoryModeButton then
		-- Hide and unhook if we're already in Story mode
		if currentContext == "Story" then
			StoryModeButton.Visible = false
			-- Clear any existing connections
			UIFunctions:ClearConnection(StoryModeButton)
		else
			UIFunctions:NewButton(
				StoryModeButton,
				{"Action"},
				{Click = "One", HoverOn = "One", HoverOff = "One"},
				0.7,
				function()
					Audio.SFX.Click:Play()
					handleLocationButtonClick(STORY_MODE_PLACE_ID)
				end
			)
		end
	end
	
	-- Set up TradeHub button
	local TradeHubButton = LocationList:WaitForChild("TradeHub")
	if TradeHubButton then
		-- Hide and unhook if we're already in Trade mode
		if currentContext == "Trade" then
			TradeHubButton.Visible = false
			-- Clear any existing connections
			UIFunctions:ClearConnection(TradeHubButton)
		else
			UIFunctions:NewButton(
				TradeHubButton,
				{"Action"},
				{Click = "One", HoverOn = "One", HoverOff = "One"},
				0.7,
				function()
					Audio.SFX.Click:Play()
					handleLocationButtonClick(TRADE_HUB_PLACE_ID)
				end
			)
		end
	end
	
	-- Set up BattleHub button
	local BattleHubButton = LocationList:WaitForChild("BattleHub")
	if BattleHubButton then
		-- Hide and unhook if we're already in Battle mode
		if currentContext == "Battle" then
			BattleHubButton.Visible = false
			-- Clear any existing connections
			UIFunctions:ClearConnection(BattleHubButton)
		else
			UIFunctions:NewButton(
				BattleHubButton,
				{"Action"},
				{Click = "One", HoverOn = "One", HoverOff = "One"},
				0.7,
				function()
					Audio.SFX.Click:Play()
					handleLocationButtonClick(BATTLE_HUB_PLACE_ID)
				end
			)
		end
	end
	
	-- Set up Save button
	local SaveButton = CTRL:WaitForChild("Save")
	if SaveButton then
		UIFunctions:NewButton(
			SaveButton,
			{"Action"},
			{Click = "One", HoverOn = "One", HoverOff = "One"},
			0.7,
			function()
				Audio.SFX.Click:Play()
				CTRLModule:Close()
				task.wait(0.15)
				SaveModule:Open()
			end
		)
	end
	
	-- Set up Settings button
	local SettingsButton = CTRL:WaitForChild("Settings")
	if SettingsButton then
		UIFunctions:NewButton(
			SettingsButton,
			{"Action"},
			{Click = "One", HoverOn = "One", HoverOff = "One"},
			0.7,
			function()
				Audio.SFX.Click:Play()
				CTRLModule:Close()
				task.wait(0.15)
				SettingsModule:Open()
			end
		)
	end
	
	-- Set up Shop button
	local ShopButton = CTRL:FindFirstChild("Shop")
	if ShopButton then
		UIFunctions:NewButton(
			ShopButton,
			{"Action"},
			{Click = "One", HoverOn = "One", HoverOff = "One"},
			0.7,
			function()
				Audio.SFX.Click:Play()
				CTRLModule:Close()
				task.wait(0.15)
				ShopModule:Open()
			end
		)
	end
	
	-- Set up MysteryTrade button
	local MysteryTradeButton = CTRL:FindFirstChild("MysteryTrade")
	if MysteryTradeButton then
		UIFunctions:NewButton(
			MysteryTradeButton,
			{"Action"},
			{Click = "One", HoverOn = "One", HoverOff = "One"},
			0.7,
			function()
				Audio.SFX.Click:Play()
				CTRLModule:Close()
				task.wait(0.15)
				local MysteryTrade = require(script.Parent:WaitForChild("MysteryTrade"))
				if MysteryTrade:CanStartTrade() then
					MysteryTrade:StartTrade()
				else
					local Say = require(script.Parent.Parent.Utilities:WaitForChild("Say"))
					local state = MysteryTrade:GetState()
					if state == "Cooldown" then
						Say:Say("System", true, {"Please wait before starting another Mystery Trade."})
					else
						Say:Say("System", true, {"You are already in a Mystery Trade."})
					end
				end
			end
		)
	end
end

return CTRLModule


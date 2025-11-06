--!nocheck
local SettingsModule = {}
local isOpen = false

--// Services
local TweenService: TweenService = game:GetService("TweenService")
local UIFunctions = require(script.Parent:WaitForChild("UIFunctions"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Audio = script.Parent.Parent.Assets:WaitForChild("Audio")
local Events = ReplicatedStorage:WaitForChild("Events")
local ClientData = require(script.Parent.Parent.Plugins.ClientData)
local MusicManager = require(script.Parent.Parent.Utilities.MusicManager)

--// Animation Constants
local OPEN_SIZE: UDim2 = UDim2.fromScale(0.5, 0.5)
local CLOSED_SIZE: UDim2 = UDim2.fromScale(0, 0)

-- Function to get setting description
local function GetSettingDescription(SettingName)
	local descriptions = {
		AutoSave = "Automatically saves your progress when you exit the game.",
		MuteMusic = "Disables all background music in the game.",
			FastText = "Makes dialogue text appear 1.5x faster for quicker reading.",
			XPSpread = "Awards 50% XP to non-fainted party members who did not battle; participating creature still receives full XP."
	}
	return descriptions[SettingName] or "No description available."
end

-- Function to update a setting
local function UpdateSetting(SettingName, NewValue)
	-- Update on server
	local success = Events.Request:InvokeServer({"UpdateSettings", SettingName, NewValue})
	
	if success then
		-- Update local client data
		local playerData = ClientData:Get()
		if not playerData.Settings then
			playerData.Settings = {}
		end
		playerData.Settings[SettingName] = NewValue
		
		-- Handle specific setting changes
		if SettingName == "MuteMusic" then
			print("Settings: Calling MusicManager:UpdateMuteSetting with value:", NewValue)
			MusicManager:UpdateMuteSetting(NewValue)
		end
		
		print("Setting updated:", SettingName, "=", NewValue)
	else
		warn("Failed to update setting:", SettingName)
	end
end

function SettingsModule:Init(All)
	--Populate settings
	local defaults = {
		AutoSave = true,
		MuteMusic = false,
		FastText = false,
		XPSpread = true,
	}
	-- Always derive from live client data; avoid stale defaults
	local live = ClientData:Get()
	local SettingsData = {}
	if live and live.Settings and typeof(live.Settings) == "table" then
		for k, v in pairs(defaults) do
			local val = live.Settings[k]
			if val == nil then
				SettingsData[k] = v
			else
				SettingsData[k] = val
			end
		end
	else
		SettingsData = defaults
	end

	local SettingsUI = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Settings")
	local GeneralList = SettingsUI:WaitForChild("Elements"):WaitForChild("General")
	local Template = GeneralList:WaitForChild("Template")
	
	-- Initialize preview position
	local Preview = SettingsUI:WaitForChild("Preview")
	Preview.Position = UDim2.new(0.75, 0, 0.5, 0)
	
	-- Clear existing settings
	for _, child in pairs(GeneralList:GetChildren()) do
		if child.Name ~= "Template" and child.Name ~= "UIListLayout" and child.Name ~= "UIPadding" then
			child:Destroy()
		end
	end
	
	for SettingName, Value in pairs(SettingsData) do
		if SettingName ~= "DataFailedToLoad" then
			local NewSetting = Template:Clone()
			NewSetting.Parent = GeneralList
			NewSetting.Visible = true
			NewSetting.Name = SettingName
			NewSetting.Title.Text = UIFunctions:AddSpacesToCaps(SettingName)
			
			-- Set initial toggle state
			local ToggleFrame = NewSetting:FindFirstChild("Toggle")
			if ToggleFrame then
				local ToggleButton = ToggleFrame:FindFirstChild("Button")
				if ToggleButton then
					-- Set initial position based on value
					if Value then
						ToggleButton.Position = UDim2.new(0.5, 0, 0.5, 0) -- On position
					else
						ToggleButton.Position = UDim2.new(0, 0, 0.5, 0) -- Off position
					end
				end
			end
			
			-- Create hover functions for preview
			local function ShowPreview()
				local SettingsUI = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Settings")
				local Preview = SettingsUI:WaitForChild("Preview")
				
				-- Update preview information
				Preview.Title.Text = UIFunctions:AddSpacesToCaps(SettingName)
				Preview.Description.Text = GetSettingDescription(SettingName)
				Preview.State.Text = Value and "Enabled" or "Disabled"
				
				-- Animate preview in
				Preview.Position = UDim2.new(0.75, 0, 0.5, 0)
				TweenService:Create(Preview, TweenInfo.new(0.15, Enum.EasingStyle.Circular, Enum.EasingDirection.Out), {
					Position = UDim2.new(1.2, 0, 0.5, 0)
				}):Play()
			end
			
			local function HidePreview()
				local SettingsUI = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Settings")
				local Preview = SettingsUI:WaitForChild("Preview")
				
				-- Animate preview out
				TweenService:Create(Preview, TweenInfo.new(0.15, Enum.EasingStyle.Circular, Enum.EasingDirection.Out), {
					Position = UDim2.new(0.75, 0, 0.5, 0)
				}):Play()
			end
			
			-- Add hover events to the entire setting element
			NewSetting.MouseEnter:Connect(ShowPreview)
			NewSetting.MouseLeave:Connect(HidePreview)
			
			UIFunctions:NewButton(NewSetting, {"Switch", Value}, nil, 0.2, function()
				-- Get current value from live client data to avoid drift
				local currentSettings = (ClientData:Get() and ClientData:Get().Settings) or SettingsData
				local CurrentValue = currentSettings[SettingName]
				local NewValue = not CurrentValue
				print("Settings Toggle Debug - SettingName:", SettingName, "Current Value:", CurrentValue, "New Value:", NewValue)
				
				-- Update the toggle visual
				local ToggleFrame = NewSetting:FindFirstChild("Toggle")
				if ToggleFrame then
					local ToggleButton = ToggleFrame:FindFirstChild("Button")
					if ToggleButton then
						if NewValue then
							ToggleButton.Position = UDim2.new(0.5, 0, 0.5, 0) -- On position
						else
							ToggleButton.Position = UDim2.new(0, 0, 0.5, 0) -- Off position
						end
					end
				end
				
				-- Update the setting (server + client)
				UpdateSetting(SettingName, NewValue)
				
				-- Update local snapshot for next toggle
				SettingsData[SettingName] = NewValue
				
				-- Update preview if it's currently showing
				local SettingsUI = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Settings")
				local Preview = SettingsUI:WaitForChild("Preview")
				if Preview.Position.X.Scale > 0.75 then -- Preview is visible
					Preview.State.Text = NewValue and "Enabled" or "Disabled"
				end
			end)
		end
	end
end

--// Settings Open
function SettingsModule:Open(All)
	All = All or {} -- Make All parameter optional
	if isOpen then return end -- Already open, don't open again
	
	-- Initialize settings if not already done
	if not SettingsModule._initialized then
		SettingsModule:Init(All)
		SettingsModule._initialized = true
	end
	
	isOpen = true
	local Settings: ScreenGui & {
		Shadow: { Image: ImageLabel },
		Topbar: {
			Size: UDim2,
			Icon: ImageLabel,
			IconShadow: ImageLabel,
			Title: TextLabel,
		},
		Seperator: Frame,
		Darken: Frame,
	} = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Settings")
	
	Audio.SFX.Open:Play()

	Settings.Visible = true
	Settings.Size = CLOSED_SIZE

	-- Main Frame
	TweenService:Create(Settings, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Size = OPEN_SIZE,
	}):Play()
	
	Settings.Position = UDim2.new(0.69, 0,0.1, 0)
	TweenService:Create(Settings, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5,0,0.5,0),
	}):Play()

	-- Shadow
	Settings.Shadow.Image.ImageTransparency = 1
	TweenService:Create(Settings.Shadow.Image, TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		ImageTransparency = 0.5,
	}):Play()

	-- Topbar
	Settings.Topbar.Size = UDim2.fromScale(1, 0.165)
	TweenService:Create(Settings.Topbar, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1, 0.107),
	}):Play()

	-- Separator
	Settings.Seperator.Size = UDim2.fromOffset(0, 0)
	task.delay(0.15, function()
		TweenService:Create(Settings.Seperator, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
			Size = UDim2.new(0.944, 0, 0.071, 0),
		}):Play()
	end)

	-- Icon + Shadow
	Settings.Topbar.Icon.Rotation = 25
	Settings.Topbar.Icon.Position = UDim2.new(0.05, 0, 0.341, 0)
	Settings.Topbar.IconShadow.Position = UDim2.new(0.084, 0, 0.682, 0)

	TweenService:Create(Settings.Topbar.Icon, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Rotation = 0,
		Position = UDim2.new(0.041, 0, 0.185, 0),
	}):Play()
	TweenService:Create(Settings.Topbar.IconShadow, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.066, 0, 0.526, 0),
	}):Play()

	-- Title
	Settings.Topbar.Title.MaxVisibleGraphemes = 0
	TweenService:Create(Settings.Topbar.Title, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		MaxVisibleGraphemes = 8,
	}):Play()

	-- Darken
	Settings.Darken.Size = CLOSED_SIZE
	TweenService:Create(Settings.Darken, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Size = UDim2.new(4.0125*1.2, 0,6.0945*1.2, 0),
	}):Play()
end

--// Settings Close
function SettingsModule:Close(All)
	All = All or {} -- Make All parameter optional
	if not isOpen then return end -- Not open, don't close
	
	isOpen = false
	local Settings: ScreenGui & {
		Shadow: { Image: ImageLabel },
		Topbar: {
			Size: UDim2,
			Icon: ImageLabel,
			IconShadow: ImageLabel,
			Title: TextLabel,
		},
		Seperator: Frame,
		Darken: Frame,
	} = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Settings")

	Audio.SFX.Close:Play()
	
	task.delay(0.1, function()
		TweenService:Create(Settings, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Size = CLOSED_SIZE,
		}):Play()
	end)
	
	task.delay(0.15,function()
		TweenService:Create(Settings, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.69, 0,0.1, 0),
		}):Play()
	end)

	TweenService:Create(Settings.Shadow.Image, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		ImageTransparency = 1,
	}):Play()

	TweenService:Create(Settings.Topbar, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1, 0.1),
	}):Play()

	TweenService:Create(Settings.Seperator, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 0, 0.071, 0),
	}):Play()

	TweenService:Create(Settings.Topbar.Icon, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Rotation = 25,
		Position = UDim2.new(0.05, 0, 0.341, 0),
	}):Play()
	TweenService:Create(Settings.Topbar.IconShadow, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.084, 0, 0.682, 0),
	}):Play()

	TweenService:Create(Settings.Topbar.Title, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		MaxVisibleGraphemes = 0,
	}):Play()

	TweenService:Create(Settings.Darken, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Size = CLOSED_SIZE,
	}):Play()

	task.delay(0.4, function()
		Settings.Visible = false
	end)
end

return SettingsModule


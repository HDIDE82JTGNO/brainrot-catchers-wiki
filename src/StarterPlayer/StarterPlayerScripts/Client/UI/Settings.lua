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
	
	-- Wire up Get Unstuck button if present
	do
		local SettingsUI = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Settings")
		local Elements = SettingsUI:FindFirstChild("Elements")
		local GetUnstuck = nil
		if Elements then
			-- Try direct first, then recursive search to tolerate layout changes
			GetUnstuck = Elements:FindFirstChild("GetUnstuck") or Elements:FindFirstChild("GetUnstuck", true)
			-- If the found instance is not a button, try to find a button under it
			if GetUnstuck and (not GetUnstuck:IsA("TextButton") and not GetUnstuck:IsA("ImageButton")) then
				local childBtn = GetUnstuck:FindFirstChildWhichIsA("TextButton", true) or GetUnstuck:FindFirstChildWhichIsA("ImageButton", true)
				if childBtn then
					GetUnstuck = childBtn
				end
			end
		end
		if GetUnstuck and (GetUnstuck:IsA("TextButton") or GetUnstuck:IsA("ImageButton")) then
			local TitleLabel = GetUnstuck:FindFirstChild("Title")
			local function setTitle(txt: string)
				if TitleLabel and TitleLabel:IsA("TextLabel") then
					TitleLabel.Text = txt
				end
			end
			-- Helper to apply a UI cooldown that disables clicking until expiry
			local function applyCooldown(seconds: number)
				seconds = tonumber(seconds) or 0
				if seconds <= 0 then return end
				setTitle("On cooldown")
				GetUnstuck.Active = false
				if GetUnstuck:IsA("TextButton") then GetUnstuck.AutoButtonColor = false end
				GetUnstuck:SetAttribute("CooldownUntil", os.clock() + seconds)
				task.delay(seconds, function()
					-- Re-enable only if not extended by a later click
					local untilTs = tonumber(GetUnstuck:GetAttribute("CooldownUntil")) or 0
					if os.clock() >= untilTs then
						GetUnstuck.Active = true
						if GetUnstuck:IsA("TextButton") then GetUnstuck.AutoButtonColor = true end
						setTitle("Get unstuck")
						GetUnstuck:SetAttribute("CooldownUntil", nil)
					end
				end)
			end
			-- If a cooldown is already in progress (UI reopened), enforce it
			do
				local untilTs = tonumber(GetUnstuck:GetAttribute("CooldownUntil")) or 0
				local rem = untilTs - os.clock()
				if rem > 0 then
					applyCooldown(rem)
				end
			end
			UIFunctions:NewButton(GetUnstuck, {"Action"}, { Click = "One", HoverOn = "One", HoverOff = "One" }, 0.7, function()
				Audio.SFX.Click:Play()
				-- Prevent clicks during cooldown
				local untilTs = tonumber(GetUnstuck:GetAttribute("CooldownUntil")) or 0
				if os.clock() < untilTs then
					return
				end
				-- Begin transition
				pcall(function() UIFunctions:Transition(true) end)

				task.wait(0.75)
				
				-- Ask server for cooldown authorization
				local res = nil
				local ok = pcall(function()
					res = Events.Request:InvokeServer({"GetUnstuck"})
				end)
				local success = ok and type(res) == "table" and (res.Success == true)
				local cooldown = (type(res) == "table" and tonumber(res.CooldownSeconds)) or 180
				
				-- If authorized, teleport to chunk start door locally
				if success then
					pcall(function()
						local ChunkLoader = require(script.Parent.Parent.Utilities.ChunkLoader)
						ChunkLoader:PositionPlayerAtStartDoor()
					end)
					applyCooldown(cooldown)
				else
					-- If server reports remaining cooldown, enforce it client-side too
					local remaining = (type(res) == "table" and tonumber(res.CooldownSeconds)) or 0
					if remaining > 0 then
						applyCooldown(remaining)
					end
				end
				
				-- End transition after delay regardless of result
				task.delay(2, function()
					pcall(function() UIFunctions:Transition(false) end)
				end)
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


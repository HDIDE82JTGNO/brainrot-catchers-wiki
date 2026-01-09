--!nocheck
local PlayerList = {}
PlayerList.__index = PlayerList

-- Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Events = ReplicatedStorage:WaitForChild("Events")

-- Modules
local ClientData = require(script.Parent.Parent.Plugins.ClientData)
local ViewPlayerManager = require(script.Parent.ViewPlayerManager)

-- Chat Colors Module (from devforum post)
local function GetNameColor(username: string, version_: number?): Color3
	-- Chat colors by version implementation
	local CHAT_COLORS_BY_VERSION = (function()
		local fakePersimmon = Color3.fromRGB(253, 41, 67)
		local fakeCyan = Color3.fromRGB(1, 162, 255)
		local fakeDarkGreen = Color3.fromRGB(2, 184, 87)
		local brightViolet = BrickColor.new("Bright violet").Color
		
		local versions = {
			{ -- v1
				BrickColor.Red().Color,
				BrickColor.Blue().Color,
				BrickColor.new("Earth green").Color,
				brightViolet
			},
			{ -- v2
				fakePersimmon,
				fakeCyan,
				fakeDarkGreen,
				brightViolet
			},
			{ -- v3
				fakePersimmon,
				fakeCyan,
				fakeDarkGreen,
				BrickColor.new("Alder").Color
			}
		}	
		
		local unchangedColors = { 
			BrickColor.new("Bright orange").Color,
			BrickColor.Yellow().Color,
			BrickColor.new("Light reddish violet").Color,
			BrickColor.new("Brick yellow").Color,
		}
		
		for _, colorList in versions do
			table.move(unchangedColors, 1, #unchangedColors, #colorList + 1, colorList)
		end
		table.freeze(versions)
		return versions
	end)()

	local function ComputeNameValue(username: string): number
		local value = 0
		for index = 1, #username do
			local cValue = string.byte(string.sub(username, index, index))
			local reverseIndex = #username - index + 1
			if #username%2 == 1 then
				reverseIndex = reverseIndex - 1
			end
			if reverseIndex%4 >= 2 then
				cValue = -cValue
			end
			value = value + cValue
		end
		return value
	end
	
	local chatColors = CHAT_COLORS_BY_VERSION[version_]
	if not chatColors then
		if version_ == nil then
			chatColors = CHAT_COLORS_BY_VERSION[#CHAT_COLORS_BY_VERSION]
		else
			error(`Invalid version '{tostring(version_)}'`)
		end
	end
	
	local value = (ComputeNameValue(username) % #chatColors) + 1
	return chatColors[value]
end

-- Helper function to darken a color
local function DarkenColor(color: Color3, factor: number): Color3
	return Color3.new(
		math.max(0, color.R * factor),
		math.max(0, color.G * factor),
		math.max(0, color.B * factor)
	)
end

-- State management
local _isVisible = true
local _playerEntries = {} -- [Player] -> GuiObject
local _connections = {}
local _isInitialized = false -- Track if PlayerList is ready to be shown

-- Animation constants (1.5x faster)
local TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- UI References (lazy loading)
local _playerListFrame: Frame?
local _listFrame: ScrollingFrame?
local _template: Frame?
local _hideShowButton: TextButton?

-- Use ViewPlayerManager for tweening
local function _tweenViewPlayer(vp: GuiObject, show: boolean)
	ViewPlayerManager.TweenViewPlayer(vp, show)
end

--[[
	Internal: Gets UI references with lazy loading
]]
local function GetUIReferences()
	if not _playerListFrame then
		local gameUI = Players.LocalPlayer.PlayerGui:WaitForChild("GameUI")
		_playerListFrame = gameUI:WaitForChild("PlayerList")
		_listFrame = _playerListFrame:WaitForChild("List")
		_template = _listFrame:WaitForChild("Template")
		_hideShowButton = _playerListFrame:WaitForChild("HideShow")
	end
	return _playerListFrame, _listFrame, _template, _hideShowButton
end

--[[
	Internal: Updates the player list visibility state
]]
local function UpdateVisibilityState()
	local playerListFrame, listFrame, _, hideShowButton = GetUIReferences()
	
	-- If not initialized, hide completely
	if not _isInitialized then
		playerListFrame.Visible = false
		return
	end
	
	-- Make sure PlayerList is visible when initialized
	playerListFrame.Visible = true
	
	if _isVisible then
		-- On screen state
		TweenService:Create(listFrame, TWEEN_INFO, {
			Position = UDim2.new(0.023, 0, 0.106, 0)
		}):Play()
		TweenService:Create(playerListFrame, TWEEN_INFO, {
			Position = UDim2.new(0.887, 0, 0.311, 0)
		}):Play()
		hideShowButton.Text = "Hide Players"
	else
		-- Off screen state
		TweenService:Create(listFrame, TWEEN_INFO, {
			Position = UDim2.new(1, 0, 0.106, 0)
		}):Play()
		TweenService:Create(playerListFrame, TWEEN_INFO, {
			Position = UDim2.new(1, 0, 0.311, 0)
		}):Play()
		hideShowButton.Text = "Show Players"
	end
end

--[[
	Internal: Creates a player entry in the list
]]
local function CreatePlayerEntry(player: Player): GuiObject
	local _, listFrame, template = GetUIReferences()
	
	-- Clone template
	local entry = template:Clone()
	entry.Name = player.Name
	entry.Visible = true
	entry.Parent = listFrame
	entry.Active = true
	entry.Selectable = true
	
	-- Set player information (Dex number will be updated via server broadcast)
	local actualNameLabel = entry:FindFirstChild("ActualName")
	local dexNumberLabel = entry:FindFirstChild("DexNumber")
	local displayNameLabel = entry:FindFirstChild("DisplayName")
	
	if actualNameLabel then
		actualNameLabel.Text = "@"..player.Name
	end
	
	if dexNumberLabel then
		dexNumberLabel.Text = "0" -- Default, will be updated by server
	end
	
	if displayNameLabel then
		displayNameLabel.Text = player.DisplayName
	end
	
	-- Set user headshot
	local icon = entry:FindFirstChild("Icon")
	if icon then
		icon.Image = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. player.UserId .. "&width=150&height=150&format=png"
	end
	
	-- Set colors based on player's chat color
	local chatColor = GetNameColor(player.Name)
	entry.BackgroundColor3 = chatColor
	
	-- Set UIStroke to darker version
	local uiStroke = entry:FindFirstChild("UIStroke")
	if uiStroke then
		uiStroke.Color = DarkenColor(chatColor, 0.7)
	end

	-- Click handler to open ViewPlayer UI (ignore self)
	local localPlayer = Players.LocalPlayer
	entry.MouseButton1Click:Connect(function()
		if not player or not player.Parent then return end

		
		-- Use ViewPlayerManager with level mode storage via entry attribute
		local function levelModeStorage(mode: string?): string?
			if mode ~= nil then
				entry:SetAttribute("SelectedLevelMode", mode)
				return mode
			else
				return entry:GetAttribute("SelectedLevelMode") or "keep"
			end
		end
		
		ViewPlayerManager.OpenForPlayer(player, levelModeStorage)
	end)
	
	return entry
end

--[[
	Internal: Removes a player entry from the list
]]
local function RemovePlayerEntry(player: Player)
	local entry = _playerEntries[player]
	if entry then
		entry:Destroy()
		_playerEntries[player] = nil
	end
end


--[[
	Internal: Handles player joining
]]
local function OnPlayerAdded(player: Player)
    _playerEntries[player] = CreatePlayerEntry(player)
end

--[[
	Internal: Handles player leaving
]]
local function OnPlayerRemoving(player: Player)
    RemovePlayerEntry(player)
end

--[[
	Internal: Handles Tab key input
]]
local function OnInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	
	if input.KeyCode == Enum.KeyCode.Tab then
		PlayerList:ToggleVisibility()
	end
end

--[[
	Internal: Handles HideShow button click
]]
local function OnHideShowClicked()
	PlayerList:ToggleVisibility()
end

--[[
	Internal: Handles server Dex updates
]]
local function OnPlayerDexUpdate(data: any)
	
	if data and data.Player and data.DexNumber ~= nil then
		local player = data.Player
		local dexNumber = data.DexNumber
		
		
		if _playerEntries[player] then
			local entry = _playerEntries[player]
			local dexNumberLabel = entry:FindFirstChild("DexNumber")
            if dexNumberLabel then
                dexNumberLabel.Text = tostring(dexNumber)
            end
        else
            -- No entry found; ignore
		end
	elseif data and data.Player and data.DexNumber == nil then
		-- Player left, remove their entry
		local player = data.Player
		RemovePlayerEntry(player)
	end
end

--[[
	Public: Initializes the PlayerList system (but doesn't show it yet)
]]
function PlayerList:Init()
	
	-- Get UI references
	local _, _, _, hideShowButton = GetUIReferences()
	
	-- Set up connections
	table.insert(_connections, Players.PlayerAdded:Connect(OnPlayerAdded))
	table.insert(_connections, Players.PlayerRemoving:Connect(OnPlayerRemoving))
	table.insert(_connections, UserInputService.InputBegan:Connect(OnInputBegan))
	table.insert(_connections, hideShowButton.MouseButton1Click:Connect(OnHideShowClicked))
	
	-- Listen for server Dex updates
	local Events = ReplicatedStorage:WaitForChild("Events")
	table.insert(_connections, Events.Communicate.OnClientEvent:Connect(function(eventType, data)
		if eventType == "PlayerDexUpdate" then
			OnPlayerDexUpdate(data)
		end
	end))
	
	-- Create entries for existing players
	for _, player in ipairs(Players:GetPlayers()) do
		OnPlayerAdded(player)
	end
	
	-- Set initial visibility state (hidden until game is ready)
	UpdateVisibilityState()
	
end

--[[
	Public: Shows the PlayerList when the game is ready (after chunk load)
]]
function PlayerList:ShowWhenReady()
	_isInitialized = true
	UpdateVisibilityState()
end

--[[
	Public: Toggles the visibility of the player list
]]
function PlayerList:ToggleVisibility()
	_isVisible = not _isVisible
	UpdateVisibilityState()
end

--[[
	Public: Shows the player list
]]
function PlayerList:Show()
	if not _isVisible then
		_isVisible = true
		UpdateVisibilityState()
	end
end

--[[
	Public: Hides the player list
]]
function PlayerList:Hide()
	if _isVisible then
		_isVisible = false
		UpdateVisibilityState()
	end
end

--[[
	Public: Gets the current visibility state
]]
function PlayerList:IsVisible(): boolean
	return _isVisible
end

--[[
	Public: Cleans up connections and resources
]]
function PlayerList:Cleanup()
	
	-- Disconnect all connections
	for _, connection in ipairs(_connections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	_connections = {}
	
	-- Clear player entries
	for player, entry in pairs(_playerEntries) do
		if entry then
			entry:Destroy()
		end
	end
	_playerEntries = {}
	
end

return PlayerList

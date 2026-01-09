--!strict
-- ViewPlayerManager: Shared module for opening and managing ViewPlayer UI
-- Used by both PlayerList and PlayerClickDetectors

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Events = ReplicatedStorage:WaitForChild("Events")
local BadgeConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BadgeConfig"))

local ViewPlayerManager = {}

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

-- Helper function to scale UDim2
local function _scaleSize(size: UDim2, factor: number): UDim2
	return UDim2.new(
		size.X.Scale * factor,
		size.X.Offset * factor,
		size.Y.Scale * factor,
		size.Y.Offset * factor
	)
end

-- Ensure ViewPlayer defaults are stored
local function _ensureViewPlayerDefaults(vp: GuiObject)
	if not vp then return end
	if vp:GetAttribute("OrigSize") == nil then
		vp:SetAttribute("OrigSize", vp.Size)
	end
	if vp:GetAttribute("OrigPos") == nil then
		vp:SetAttribute("OrigPos", vp.Position)
	end
end

-- Tween ViewPlayer UI in/out
function ViewPlayerManager.TweenViewPlayer(vp: GuiObject, show: boolean)
	if not vp then return end
	_ensureViewPlayerDefaults(vp)
	local origSize: UDim2 = vp:GetAttribute("OrigSize") or vp.Size
	local origPos: UDim2 = vp:GetAttribute("OrigPos") or vp.Position
	local tweenInfo = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	
	if show then
		vp.Visible = true
		vp.Size = _scaleSize(origSize, 0.8)
		vp.Position = origPos
		TweenService:Create(vp, tweenInfo, {Size = origSize}):Play()
	else
		local targetSize = _scaleSize(origSize, 0.8)
		local tween = TweenService:Create(vp, tweenInfo, {Size = targetSize})
		tween.Completed:Connect(function()
			vp.Visible = false
			vp.Size = origSize
			vp.Position = origPos
		end)
		tween:Play()
	end
end

-- Get ViewPlayer UI references
local function getViewRefs(vp: GuiObject)
	local brb = vp:FindFirstChild("BattleReqeuestBuilder", true) or vp:FindFirstChild("BattleRequestBuilder", true)
	local showBtn = vp:FindFirstChild("ShowBattleOptions", true)
	local dropdown = nil
	if showBtn then
		dropdown = showBtn:FindFirstChild("Dropdown")
		if not dropdown then
			dropdown = showBtn:FindFirstChildWhichIsA("ImageLabel", true)
		end
	end
	local tradeReq = vp:FindFirstChild("TradeRequest", true)
	return brb, showBtn, dropdown, tradeReq
end

-- Open ViewPlayer UI for a player
-- levelModeStorage: optional function that gets/sets the level mode
--   When called with nil: returns current mode (string)
--   When called with string: sets the mode
function ViewPlayerManager.OpenForPlayer(player: Player, levelModeStorage: ((string?) -> string?)?)
	if not player or not player.Parent then return end
	local isViewingSelf = player == LocalPlayer
	
	local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then return end
	local gameUI = pg:FindFirstChild("GameUI")
	if not gameUI then return end
	local vp = gameUI:FindFirstChild("ViewPlayer")
	if not vp then return end
	local battleUI = gameUI:FindFirstChild("BattleUI")
	
	-- Block while in battle
	if battleUI and battleUI.Visible == true then
		return
	end

	-- Populate names and headshot
	local actualNameLabel = vp:FindFirstChild("ActualName")
	if actualNameLabel and actualNameLabel:IsA("TextLabel") then
		actualNameLabel.Text = player.Name
	end
	local displayNameLabel = vp:FindFirstChild("DisplayName")
	if displayNameLabel and displayNameLabel:IsA("TextLabel") then
		displayNameLabel.Text = player.DisplayName
	end
	local iconImg = vp:FindFirstChild("Icon", true)
	if iconImg and iconImg:IsA("ImageLabel") then
		iconImg.Image = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. tostring(player.UserId) .. "&width=150&height=150&format=png"
	end

	-- Set colors based on player's chat color
	local chatColor = GetNameColor(player.Name)
	local darkerColor = DarkenColor(chatColor, 0.7)
	
	vp.BackgroundColor3 = chatColor
	local vpStroke = vp:FindFirstChild("UIStroke")
	if vpStroke and vpStroke:IsA("UIStroke") then
		vpStroke.Color = darkerColor
	end
	
	local viewingPlayer = vp:FindFirstChild("ViewingPlayer")
	if viewingPlayer and viewingPlayer:IsA("GuiObject") then
		viewingPlayer.BackgroundColor3 = chatColor
		local viewingPlayerStroke = viewingPlayer:FindFirstChild("UIStroke")
		if viewingPlayerStroke and viewingPlayerStroke:IsA("UIStroke") then
			viewingPlayerStroke.Color = darkerColor
		end
	end
	
	local otherListings = vp:FindFirstChild("OtherListings")
	if otherListings and otherListings:IsA("GuiObject") then
		otherListings.BackgroundColor3 = chatColor
		local otherListingsStroke = otherListings:FindFirstChild("UIStroke")
		if otherListingsStroke and otherListingsStroke:IsA("UIStroke") then
			otherListingsStroke.Color = darkerColor
		end
	end

	-- Request player info from server (badges, studs)
	local playerInfo = nil
	if not isViewingSelf then
		print("[ViewPlayerManager] Requesting info for other player:", player.Name, "UserId:", player.UserId)
		local ok, result = pcall(function()
			return Events.Request:InvokeServer({"ViewPlayerInfo", player.UserId})
		end)
		print("[ViewPlayerManager] Server response - ok:", ok, "result:", result)
		if ok and result then
			playerInfo = result
			print("[ViewPlayerManager] Got playerInfo - Badges:", playerInfo.Badges, "Studs:", playerInfo.Studs)
		else
			print("[ViewPlayerManager] Failed to get playerInfo")
		end
	else
		-- For viewing self, get data from local client data
		print("[ViewPlayerManager] Viewing self, using local ClientData")
		local ClientData = require(script.Parent.Parent.Plugins.ClientData)
		local currentData = ClientData:Get()
		print("[ViewPlayerManager] ClientData:Get() returned:", currentData and "data" or "nil")
		if currentData then
			print("[ViewPlayerManager] currentData.Studs:", currentData.Studs, "currentData.Badges:", currentData.Badges)
			playerInfo = {
				Badges = currentData.Badges or 0,
				Studs = currentData.Studs or 0,
			}
			print("[ViewPlayerManager] playerInfo constructed - Badges:", playerInfo.Badges, "Studs:", playerInfo.Studs)
		else
			print("[ViewPlayerManager] currentData is nil!")
		end
	end

	-- Display badges
	local badgeList = vp:FindFirstChild("BadgeList", true)
	local badgeContainer = badgeList and badgeList:FindFirstChild("Container")
	if badgeContainer and playerInfo then
		local badgeCount = playerInfo.Badges or 0
		local badgeImages = BadgeConfig.BadgeImages
		
		-- Set badges 1-8
		for i = 1, BadgeConfig.MaxBadges do
			local badge = badgeContainer:FindFirstChild(tostring(i))
			if badge and badge:IsA("GuiObject") then
				if i <= badgeCount then
					-- Badge earned: 0 transparency
					badge.BackgroundTransparency = 1
					if badge:IsA("ImageLabel") or badge:FindFirstChildWhichIsA("ImageLabel", true) then
						local imgLabel = badge:IsA("ImageLabel") and badge or badge:FindFirstChildWhichIsA("ImageLabel", true)
						if imgLabel then
							imgLabel.ImageTransparency = 0
							imgLabel.Image = badgeImages[i] or "rbxassetid://0"
						end
					end
				elseif i == badgeCount + 1 and badgeCount < BadgeConfig.MaxBadges then
					-- Next badge: 0.8 transparency with locked image (only if not all badges earned)
					badge.BackgroundTransparency = 1
					if badge:IsA("ImageLabel") or badge:FindFirstChildWhichIsA("ImageLabel", true) then
						local imgLabel = badge:IsA("ImageLabel") and badge or badge:FindFirstChildWhichIsA("ImageLabel", true)
						if imgLabel then
							imgLabel.ImageTransparency = 0.8
							imgLabel.Image = BadgeConfig.LockedBadgeImage
						end
					end
				else
					-- Future badges: set to rbxassetid://0 (badges 3-8 that aren't earned or next)
					badge.BackgroundTransparency = 1
					if badge:IsA("ImageLabel") or badge:FindFirstChildWhichIsA("ImageLabel", true) then
						local imgLabel = badge:IsA("ImageLabel") and badge or badge:FindFirstChildWhichIsA("ImageLabel", true)
						if imgLabel then
							imgLabel.ImageTransparency = 1
							imgLabel.Image = "rbxassetid://0"
						end
					end
				end
			end
		end
	end

	-- Display studs
	local otherListings = vp:FindFirstChild("OtherListings", true)
	print("[ViewPlayerManager] otherListings found:", otherListings and "yes" or "no")
	local studsLabel = otherListings and otherListings:FindFirstChild("StudCount")
	print("[ViewPlayerManager] studsLabel found:", studsLabel and "yes" or "no", "IsTextLabel:", studsLabel and studsLabel:IsA("TextLabel") or "N/A")
	print("[ViewPlayerManager] playerInfo exists:", playerInfo and "yes" or "no")
	if studsLabel and studsLabel:IsA("TextLabel") and playerInfo then
		local studs = playerInfo.Studs or 0
		print("[ViewPlayerManager] Setting studs text to:", studs)
		studsLabel.Text = "Studs: " .. tostring(studs)
	else
		print("[ViewPlayerManager] NOT setting studs text - missing studsLabel or playerInfo")
	end

	-- Setup BattleRequestBuilder visibility state and dropdown rotation + TradeRequest visibility
	local brb, showBtn, dropdown, tradeReq = getViewRefs(vp)
	if brb and brb:IsA("Frame") then
		brb.Visible = false
	end
	if dropdown and dropdown:IsA("ImageLabel") then
		dropdown.Rotation = 0
	end
	if tradeReq and tradeReq:IsA("GuiObject") then
		tradeReq.Visible = not isViewingSelf
	end
	if showBtn and showBtn:IsA("GuiObject") then
		showBtn.Visible = not isViewingSelf
	end

	-- Initialize level selection (KeepLv selected by default)
	local KEEP_COLOR = Color3.fromRGB(158, 239, 255)
	local NOT_COLOR = Color3.fromRGB(48, 162, 238)
	local keepBtn = brb and brb:FindFirstChild("KeepLv")
	local f50Btn = brb and brb:FindFirstChild("ForceLv50")
	local f100Btn = brb and brb:FindFirstChild("ForceLv100")
	
	-- Level mode storage: use provided storage or default to local variable
	local levelMode = "keep"
	local function getLevelMode(): string
		if levelModeStorage then
			local stored = levelModeStorage(nil)
			return stored or "keep"
		end
		return levelMode
	end
	local function setLevelMode(mode: string)
		if levelModeStorage then
			levelModeStorage(mode)
		else
			levelMode = mode
		end
	end
	
	local function setSelection(which: string)
		if keepBtn and keepBtn:IsA("TextButton") then
			keepBtn.BackgroundColor3 = (which == "keep") and KEEP_COLOR or NOT_COLOR
		end
		if f50Btn and f50Btn:IsA("TextButton") then
			f50Btn.BackgroundColor3 = (which == "50") and KEEP_COLOR or NOT_COLOR
		end
		if f100Btn and f100Btn:IsA("TextButton") then
			f100Btn.BackgroundColor3 = (which == "100") and KEEP_COLOR or NOT_COLOR
		end
		setLevelMode(which)
	end
	setSelection("keep")

	-- Wire level buttons
	if keepBtn and keepBtn:IsA("TextButton") then
		keepBtn.MouseButton1Click:Connect(function()
			setSelection("keep")
		end)
	end
	if f50Btn and f50Btn:IsA("TextButton") then
		f50Btn.MouseButton1Click:Connect(function()
			setSelection("50")
		end)
	end
	if f100Btn and f100Btn:IsA("TextButton") then
		f100Btn.MouseButton1Click:Connect(function()
			setSelection("100")
		end)
	end

	-- Toggle ShowBattleOptions
	if showBtn and showBtn:IsA("TextButton") then
		showBtn.MouseButton1Click:Connect(function()
			-- Refresh references each click in case UI changed
			brb, showBtn, dropdown, tradeReq = getViewRefs(vp)
			-- Abort if dialogue/topbar/battle active
			local UI = require(script.Parent)
			local TopBar = UI and UI.TopBar
			local Say = require(script.Parent.Parent.Utilities.Say)
			local battleUI = gameUI:FindFirstChild("BattleUI")
			if (Say and Say.IsActive and Say:IsActive()) or (TopBar and TopBar.IsMenuOpen and TopBar:IsMenuOpen()) or (battleUI and battleUI.Visible == true) then
				ViewPlayerManager.TweenViewPlayer(vp, false)
				return
			end
			if not brb then
				warn("[ViewPlayer] BattleRequestBuilder not found; cannot toggle")
				return
			end
			local nowVisible = not brb.Visible
			brb.Visible = nowVisible
			if dropdown and dropdown:IsA("ImageLabel") then
				dropdown.Rotation = nowVisible and 90 or 0
			end
			if tradeReq and tradeReq:IsA("GuiObject") then
				tradeReq.Visible = not nowVisible
			end
		end)
	end

	-- Close button
	local closeBtn = vp:FindFirstChild("Close", true)
	if closeBtn and closeBtn:IsA("TextButton") then
		closeBtn.MouseButton1Click:Connect(function()
			ViewPlayerManager.TweenViewPlayer(vp, false)
		end)
	end

	-- Confirm battle (send request)
	local confirmBtn = brb and brb:FindFirstChild("Confirm", true)
	if confirmBtn and confirmBtn:IsA("TextButton") then
		confirmBtn.MouseButton1Click:Connect(function()
			local mode = getLevelMode()
			-- Close the view
			ViewPlayerManager.TweenViewPlayer(vp, false)
			-- Notify waiting
			local Say = require(script.Parent.Parent.Utilities.Say)
			Say:Say("System", false, {"Waiting for server response..."})
			local result = nil
			local ok = pcall(function()
				result = Events.Request:InvokeServer({"BattleRequest", {
					TargetUserId = player.UserId,
					LevelMode = mode,
				}})
			end)
			Say:Exit()
			if not ok or result == nil then
				Say:Say("System", true, {"Cannot proceed."})
				return
			end
			if result == true then
				Say:Say("System", false, {"Waiting for " .. player.DisplayName .. " to respond..."})
			elseif type(result) == "string" then
				Say:Say("System", true, {result})
			else
				Say:Say("System", true, {"Cannot proceed."})
			end
		end)
	end

	-- Send trade request
	if tradeReq and tradeReq:IsA("GuiButton") then
		tradeReq.MouseButton1Click:Connect(function()
			ViewPlayerManager.TweenViewPlayer(vp, false)
			local Say = require(script.Parent.Parent.Utilities.Say)
			Say:Say("System", false, {"Waiting for server response..."})
			local result = nil
			local ok = pcall(function()
				result = Events.Request:InvokeServer({"TradeRequest", {
					TargetUserId = player.UserId,
				}})
			end)
			Say:Exit()
			if not ok or result == nil then
				Say:Say("System", true, {"Cannot proceed."})
				return
			end
			if result == true then
				Say:Say("System", false, {"Waiting for " .. player.DisplayName .. " to respond..."})
			elseif type(result) == "string" then
				Say:Say("System", true, {result})
			else
				Say:Say("System", true, {"Cannot proceed."})
			end
		end)
	end

	-- Show the ViewPlayer UI (but abort if dialogue/topbar/battle already active)
	local UI = require(script.Parent)
	local TopBar = UI and UI.TopBar
	local Say = require(script.Parent.Parent.Utilities.Say)
	if (Say and Say.IsActive and Say:IsActive()) or (TopBar and TopBar.IsMenuOpen and TopBar:IsMenuOpen()) or (battleUI and battleUI.Visible == true) then
		return
	end
	ViewPlayerManager.TweenViewPlayer(vp, true)

	-- Watch for interruptions (Say or TopBar menu), close view if they occur
	task.spawn(function()
		while vp and vp.Parent and vp.Visible do
			if (Say and Say.IsActive and Say:IsActive()) or (TopBar and TopBar.IsMenuOpen and TopBar:IsMenuOpen()) or (battleUI and battleUI.Visible == true) then
				ViewPlayerManager.TweenViewPlayer(vp, false)
				break
			end
			task.wait(0.2)
		end
	end)
end

return ViewPlayerManager


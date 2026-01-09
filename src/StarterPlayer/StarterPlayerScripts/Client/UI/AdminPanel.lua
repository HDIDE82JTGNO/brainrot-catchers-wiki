--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local Events = ReplicatedStorage:WaitForChild("Events")
local Request = Events:WaitForChild("Request")
local Creatures = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Creatures"))
local Items = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Items"))

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Constants
local NATURES = {
	"Hardy", "Lonely", "Brave", "Adamant", "Naughty",
	"Bold", "Docile", "Relaxed", "Impish", "Lax",
	"Timid", "Hasty", "Serious", "Jolly", "Naive",
	"Modest", "Mild", "Quiet", "Bashful", "Rash",
	"Calm", "Gentle", "Sassy", "Careful", "Quirky"
}

local COLORS = {
	Background = Color3.fromRGB(30, 30, 35),
	Foreground = Color3.fromRGB(45, 45, 50),
	Accent = Color3.fromRGB(0, 120, 215),
	Text = Color3.fromRGB(240, 240, 240),
	TextDim = Color3.fromRGB(180, 180, 180),
	Success = Color3.fromRGB(40, 167, 69),
	Danger = Color3.fromRGB(220, 53, 69),
	Border = Color3.fromRGB(60, 60, 65)
}

-- State
local isAdmin = false
local permissionLevel = "None"
local isVisible = false
local currentTab = "Players"

-- Data Lists
local creatureNames = {}
for name, _ in pairs(Creatures) do
	table.insert(creatureNames, name)
end
table.sort(creatureNames)

local itemNames = {}
for name, _ in pairs(Items) do
	table.insert(itemNames, name)
end
table.sort(itemNames)

-- UI Elements Reference
local mainFrame: Frame?
local contentFrames = {}

-- Helper Functions
local function createCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function createStroke(parent: Instance, thickness: number, color: Color3)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness
	stroke.Color = color
	stroke.Parent = parent
	return stroke
end

local function createPadding(parent: Instance, padding: number)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, padding)
	pad.PaddingBottom = UDim.new(0, padding)
	pad.PaddingLeft = UDim.new(0, padding)
	pad.PaddingRight = UDim.new(0, padding)
	pad.Parent = parent
	return pad
end

local function createLabel(parent: Instance, text: string, size: UDim2, pos: UDim2, zIndex: number?)
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = pos
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = COLORS.Text
	label.Font = Enum.Font.Gotham
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = zIndex or 1
	label.Parent = parent
	return label
end

local function createInput(parent: Instance, placeholder: string, size: UDim2, pos: UDim2, zIndex: number?): TextBox
	local container = Instance.new("Frame")
	container.Size = size
	container.Position = pos
	container.BackgroundColor3 = COLORS.Foreground
	container.BorderSizePixel = 0
	container.ZIndex = zIndex or 1
	container.Parent = parent
	createCorner(container, 4)
	createStroke(container, 1, COLORS.Border)

	local input = Instance.new("TextBox")
	input.Size = UDim2.new(1, 0, 1, 0)
	input.BackgroundTransparency = 1
	input.PlaceholderText = placeholder
	input.PlaceholderColor3 = COLORS.TextDim
	input.Text = ""
	input.TextColor3 = COLORS.Text
	input.Font = Enum.Font.Gotham
	input.TextSize = 14
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.ClearTextOnFocus = false
	input.ZIndex = (zIndex or 1) + 1
	input.Parent = container
	createPadding(input, 8)
	
	return input
end

local function createButton(parent: Instance, text: string, size: UDim2, pos: UDim2, color: Color3, callback: () -> (), zIndex: number?): TextButton
	local btn = Instance.new("TextButton")
	btn.Size = size
	btn.Position = pos
	btn.BackgroundColor3 = color
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = COLORS.Text
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 14
	btn.AutoButtonColor = true
	btn.ZIndex = zIndex or 1
	btn.Parent = parent
	createCorner(btn, 4)
	
	btn.MouseButton1Click:Connect(callback)
	return btn
end

local function createToggle(parent: Instance, text: string, size: UDim2, pos: UDim2, default: boolean, zIndex: number?): (Frame, () -> boolean)
	local container = Instance.new("Frame")
	container.Size = size
	container.Position = pos
	container.BackgroundTransparency = 1
	container.ZIndex = zIndex or 1
	container.Parent = parent
	
	local label = createLabel(container, text, UDim2.new(0.7, -10, 1, 0), UDim2.new(0, 0, 0, 0), (zIndex or 1) + 1)
	
	local box = Instance.new("TextButton")
	box.Size = UDim2.new(0, 24, 0, 24)
	box.AnchorPoint = Vector2.new(1, 0.5)
	box.Position = UDim2.new(1, 0, 0.5, 0)
	box.BackgroundColor3 = COLORS.Foreground
	box.Text = default and "✓" or ""
	box.TextColor3 = COLORS.Accent
	box.Font = Enum.Font.GothamBold
	box.TextSize = 18
	box.ZIndex = (zIndex or 1) + 1
	box.Parent = container
	createCorner(box, 4)
	createStroke(box, 1, COLORS.Border)
	
	local active = default
	
	box.MouseButton1Click:Connect(function()
		active = not active
		box.Text = active and "✓" or ""
	end)
	
	return container, function() return active end
end

local function createDropdown(parent: Instance, placeholder: string, size: UDim2, pos: UDim2, items: {string}, baseZIndex: number?): (Frame, () -> string)
	local wrapper = Instance.new("Frame")
	wrapper.Size = size
	wrapper.Position = pos
	wrapper.BackgroundTransparency = 1
	wrapper.ZIndex = baseZIndex or 10
	wrapper.Parent = parent
	
	local input = createInput(wrapper, placeholder, UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 0), (baseZIndex or 10) + 1)
	local box = input.Parent :: Frame
	
	local listFrame = Instance.new("ScrollingFrame")
	listFrame.Size = UDim2.new(1, 0, 0, 150)
	listFrame.Position = UDim2.new(0, 0, 1, 2)
	listFrame.BackgroundColor3 = COLORS.Foreground
	listFrame.BorderSizePixel = 0
	listFrame.Visible = false
	listFrame.ZIndex = (baseZIndex or 10) + 20
	listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	listFrame.ScrollBarThickness = 4
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.Parent = wrapper
	createCorner(listFrame, 4)
	createStroke(listFrame, 1, COLORS.Border)
	
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.Parent = listFrame
	
	createPadding(listFrame, 4)
	
	local function updateList(filter: string)
		for _, child in ipairs(listFrame:GetChildren()) do
			if child:IsA("TextButton") then child:Destroy() end
		end
		
		local count = 0
		for _, item in ipairs(items) do
			if filter == "" or string.find(string.lower(item), string.lower(filter)) then
				count += 1
				if count > 50 then break end -- Limit results
				
				local btn = Instance.new("TextButton")
				btn.Size = UDim2.new(1, 0, 0, 24)
				btn.BackgroundTransparency = 1
				btn.Text = item
				btn.TextColor3 = COLORS.Text
				btn.Font = Enum.Font.Gotham
				btn.TextSize = 14
				btn.TextXAlignment = Enum.TextXAlignment.Left
				btn.LayoutOrder = count
				btn.ZIndex = (baseZIndex or 10) + 21
				btn.Parent = listFrame
				createPadding(btn, 4)
				
				btn.MouseButton1Click:Connect(function()
					input.Text = item
					listFrame.Visible = false
				end)
			end
		end
		listFrame.Size = UDim2.new(1, 0, 0, math.min(count * 26 + 8, 200))
	end
	
	input:GetPropertyChangedSignal("Text"):Connect(function()
		if input:IsFocused() then
			listFrame.Visible = true
			updateList(input.Text)
		end
	end)
	
	input.Focused:Connect(function()
		listFrame.Visible = true
		updateList(input.Text)
	end)
	
	-- Close dropdown when focus is lost (with small delay to allow button clicks)
	input.FocusLost:Connect(function()
		task.wait(0.1)
		if not input:IsFocused() then
			listFrame.Visible = false
		end
	end)
	
	return wrapper, function() return input.Text end
end

local function getPlayerList(): {string}
	local playerList = {}
	for _, p in ipairs(Players:GetPlayers()) do
		-- Include both name and display name for easier finding
		local entry = p.DisplayName ~= p.Name and (p.DisplayName .. " (" .. p.Name .. ")") or p.Name
		table.insert(playerList, entry)
	end
	table.sort(playerList)
	return playerList
end

local function getPlayerId(identifier: string): number?
	if tonumber(identifier) then
		return tonumber(identifier)
	end
	-- Try to find player by name or display name
	for _, p in ipairs(Players:GetPlayers()) do
		if string.lower(p.Name) == string.lower(identifier) or string.lower(p.DisplayName) == string.lower(identifier) then
			return p.UserId
		end
		-- Also check if identifier matches "DisplayName (Name)" format
		local displayFormat = p.DisplayName .. " (" .. p.Name .. ")"
		if string.lower(displayFormat) == string.lower(identifier) then
			return p.UserId
		end
	end
	return nil
end

local function createPlayerDropdown(parent: Instance, placeholder: string, size: UDim2, pos: UDim2, baseZIndex: number?): (Frame, () -> string)
	local wrapper = Instance.new("Frame")
	wrapper.Size = size
	wrapper.Position = pos
	wrapper.BackgroundTransparency = 1
	wrapper.ZIndex = baseZIndex or 10
	wrapper.Parent = parent
	
	local input = createInput(wrapper, placeholder, UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 0), (baseZIndex or 10) + 1)
	local box = input.Parent :: Frame
	
	local listFrame = Instance.new("ScrollingFrame")
	listFrame.Size = UDim2.new(1, 0, 0, 150)
	listFrame.Position = UDim2.new(0, 0, 1, 2)
	listFrame.BackgroundColor3 = COLORS.Foreground
	listFrame.BorderSizePixel = 0
	listFrame.Visible = false
	listFrame.ZIndex = (baseZIndex or 10) + 20
	listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	listFrame.ScrollBarThickness = 4
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.Parent = wrapper
	createCorner(listFrame, 4)
	createStroke(listFrame, 1, COLORS.Border)
	
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.Parent = listFrame
	
	createPadding(listFrame, 4)
	
	local function updateList(filter: string)
		for _, child in ipairs(listFrame:GetChildren()) do
			if child:IsA("TextButton") then child:Destroy() end
		end
		
		local playerList = getPlayerList()
		local count = 0
		for _, item in ipairs(playerList) do
			if filter == "" or string.find(string.lower(item), string.lower(filter)) then
				count += 1
				if count > 50 then break end -- Limit results
				
				local btn = Instance.new("TextButton")
				btn.Size = UDim2.new(1, 0, 0, 24)
				btn.BackgroundTransparency = 1
				btn.Text = item
				btn.TextColor3 = COLORS.Text
				btn.Font = Enum.Font.Gotham
				btn.TextSize = 14
				btn.TextXAlignment = Enum.TextXAlignment.Left
				btn.LayoutOrder = count
				btn.ZIndex = (baseZIndex or 10) + 21
				btn.Parent = listFrame
				createPadding(btn, 4)
				
				btn.MouseButton1Click:Connect(function()
					input.Text = item
					listFrame.Visible = false
				end)
			end
		end
		listFrame.Size = UDim2.new(1, 0, 0, math.min(count * 26 + 8, 200))
	end
	
	input:GetPropertyChangedSignal("Text"):Connect(function()
		if input:IsFocused() then
			listFrame.Visible = true
			updateList(input.Text)
		end
	end)
	
	input.Focused:Connect(function()
		listFrame.Visible = true
		updateList(input.Text)
	end)
	
	-- Close dropdown when focus is lost (with small delay to allow button clicks)
	input.FocusLost:Connect(function()
		task.wait(0.1)
		if not input:IsFocused() then
			listFrame.Visible = false
		end
	end)
	
	return wrapper, function() return input.Text end
end

local function notify(message: string, isError: boolean)
	StarterGui:SetCore("SendNotification", {
		Title = isError and "Admin Error" or "Admin Action";
		Text = message;
		Duration = 5;
	})
end

-- Main UI Creation
local function createAdminPanel()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AdminPanel"
	screenGui.ResetOnSpawn = false
	screenGui.Enabled = false
	screenGui.Parent = PlayerGui
	
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 600, 0, 400)
	frame.Position = UDim2.new(0.5, -300, 0.5, -200)
	frame.BackgroundColor3 = COLORS.Background
	frame.BorderSizePixel = 0
	frame.Parent = screenGui
	createCorner(frame, 8)
	createStroke(frame, 1, COLORS.Border)
	mainFrame = frame
	
	-- Draggable
	local dragInput
	local dragStart
	local startPos
	local dragging = false
	
	frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
			
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	
	frame.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)
	
	UserInputService.InputChanged:Connect(function(input)
		if input == dragInput and dragging then
			local delta = input.Position - dragStart
			frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
	
	-- Header
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 40)
	header.BackgroundTransparency = 1
	header.Parent = frame
	
	local title = createLabel(header, "Admin Panel (" .. permissionLevel .. ")", UDim2.new(1, -20, 1, 0), UDim2.new(0, 15, 0, 0))
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.Position = UDim2.new(1, -40, 0, 0)
	closeBtn.BackgroundTransparency = 1
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = COLORS.TextDim
	closeBtn.TextSize = 20
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Parent = header
	closeBtn.MouseButton1Click:Connect(function()
		isVisible = false
		screenGui.Enabled = false
	end)
	
	-- Tabs
	local tabContainer = Instance.new("Frame")
	tabContainer.Size = UDim2.new(1, 0, 0, 36)
	tabContainer.Position = UDim2.new(0, 0, 0, 40)
	tabContainer.BackgroundColor3 = COLORS.Foreground
	tabContainer.BorderSizePixel = 0
	tabContainer.Parent = frame
	
	local contentContainer = Instance.new("Frame")
	contentContainer.Size = UDim2.new(1, -30, 1, -86)
	contentContainer.Position = UDim2.new(0, 15, 0, 86)
	contentContainer.BackgroundTransparency = 1
	contentContainer.Parent = frame
	
	local tabs = {"Players", "Creatures", "Items", "Data", "Misc"}
	local tabBtns = {}
	
	local function switchTab(name: string)
		currentTab = name
		for _, btn in pairs(tabBtns) do
			btn.TextColor3 = btn.Name == name and COLORS.Accent or COLORS.TextDim
			if btn:FindFirstChild("Indicator") then
				btn.Indicator.Visible = btn.Name == name
			end
		end
		for tabName, content in pairs(contentFrames) do
			content.Visible = tabName == name
		end
	end
	
	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.Parent = tabContainer
	
	for _, name in ipairs(tabs) do
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.Size = UDim2.new(1 / #tabs, 0, 1, 0)
		btn.BackgroundTransparency = 1
		btn.Text = name
		btn.TextColor3 = COLORS.TextDim
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 14
		btn.Parent = tabContainer
		
		local indicator = Instance.new("Frame")
		indicator.Name = "Indicator"
		indicator.Size = UDim2.new(1, 0, 0, 2)
		indicator.Position = UDim2.new(0, 0, 1, -2)
		indicator.BackgroundColor3 = COLORS.Accent
		indicator.BorderSizePixel = 0
		indicator.Visible = false
		indicator.Parent = btn
		
		btn.MouseButton1Click:Connect(function() switchTab(name) end)
		table.insert(tabBtns, btn)
		
		-- Create Content Frame
		local content = Instance.new("Frame")
		content.Name = name
		content.Size = UDim2.new(1, 0, 1, 0)
		content.BackgroundTransparency = 1
		content.Visible = false
		content.Parent = contentContainer
		contentFrames[name] = content
	end
	
	-- Implement Players Tab
	do
		local page = contentFrames["Players"]
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 10)
		layout.Parent = page
		
		local _, getTargetPlayer = createPlayerDropdown(page, "Target Player (Name or UserId)", UDim2.new(1, 0, 0, 36), UDim2.new(0, 0, 0, 0))
		local reasonInput = createInput(page, "Reason", UDim2.new(1, 0, 0, 36), UDim2.new(0, 0, 0, 0))
		local durationInput = createInput(page, "Ban Duration (Seconds, empty for perm)", UDim2.new(1, 0, 0, 36), UDim2.new(0, 0, 0, 0))
		
		local btnRow = Instance.new("Frame")
		btnRow.Size = UDim2.new(1, 0, 0, 40)
		btnRow.BackgroundTransparency = 1
		btnRow.Parent = page
		
		local btnLayout = Instance.new("UIListLayout")
		btnLayout.FillDirection = Enum.FillDirection.Horizontal
		btnLayout.Padding = UDim.new(0, 10)
		btnLayout.Parent = btnRow
		
		createButton(btnRow, "Kick", UDim2.new(0.3, 0, 1, 0), UDim2.new(0, 0, 0, 0), COLORS.Accent, function()
			local target = getPlayerId(getTargetPlayer())
			if not target then notify("Player not found", true) return end
			local res = Request:InvokeServer({"AdminAction", "KickPlayer", target, { Reason = reasonInput.Text }})
			notify(res.Message, not res.Success)
		end)
		
		createButton(btnRow, "Ban", UDim2.new(0.3, 0, 1, 0), UDim2.new(0, 0, 0, 0), COLORS.Danger, function()
			local target = getPlayerId(getTargetPlayer())
			if not target then notify("Player not found", true) return end
			local dur = tonumber(durationInput.Text)
			local res = Request:InvokeServer({"AdminAction", "BanPlayer", target, { Reason = reasonInput.Text, Duration = dur }})
			notify(res.Message, not res.Success)
		end)
		
		createButton(btnRow, "Unban", UDim2.new(0.3, 0, 1, 0), UDim2.new(0, 0, 0, 0), COLORS.Success, function()
			local targetText = getTargetPlayer()
			local target = tonumber(targetText) -- Unban usually needs raw ID since player isn't in game
			if not target then notify("Please enter UserId for Unban", true) return end
			local res = Request:InvokeServer({"AdminAction", "UnbanPlayer", target})
			notify(res.Message, not res.Success)
		end)
	end
	
	-- Implement Creatures Tab
	do
		local page = contentFrames["Creatures"]
		local scroll = Instance.new("ScrollingFrame")
		scroll.Size = UDim2.new(1, 0, 1, 0)
		scroll.BackgroundTransparency = 1
		scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.ScrollBarThickness = 4
		scroll.ZIndex = 1
		scroll.Parent = page
		
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 10)
		layout.Parent = scroll
		
		-- Base ZIndex for elements inside scroll frame
		local scrollZIndex = 2
		
		createLabel(scroll, "Spawn Creature", UDim2.new(1, 0, 0, 20), UDim2.new(0,0,0,0), scrollZIndex)
		
		local _, getTargetPlayer = createPlayerDropdown(scroll, "Target Player (Name/ID)", UDim2.new(1, 0, 0, 36), UDim2.new(0,0,0,0), scrollZIndex)
		local _, getSpecies = createDropdown(scroll, "Species", UDim2.new(1, 0, 0, 36), UDim2.new(0,0,0,0), creatureNames, scrollZIndex)
		local levelInput = createInput(scroll, "Level (1-100)", UDim2.new(1, 0, 0, 36), UDim2.new(0,0,0,0), scrollZIndex)
		local _, getNature = createDropdown(scroll, "Nature", UDim2.new(1, 0, 0, 36), UDim2.new(0,0,0,0), NATURES, scrollZIndex)
		local abilityInput = createInput(scroll, "Ability (Optional override)", UDim2.new(1, 0, 0, 36), UDim2.new(0,0,0,0), scrollZIndex)
		
		-- IV Inputs
		createLabel(scroll, "IVs (0-31, empty = random)", UDim2.new(1, 0, 0, 20), UDim2.new(0,0,0,0), scrollZIndex)
		local ivRow = Instance.new("Frame")
		ivRow.Size = UDim2.new(1, 0, 0, 36)
		ivRow.BackgroundTransparency = 1
		ivRow.ZIndex = scrollZIndex
		ivRow.Parent = scroll
		local ivLayout = Instance.new("UIListLayout")
		ivLayout.FillDirection = Enum.FillDirection.Horizontal
		ivLayout.Padding = UDim.new(0, 10)
		ivLayout.Parent = ivRow
		
		local ivInputs = {
			HP = createInput(ivRow, "HP", UDim2.new(0.22, 0, 1, 0), UDim2.new(0,0,0,0), scrollZIndex),
			Attack = createInput(ivRow, "Atk", UDim2.new(0.22, 0, 1, 0), UDim2.new(0,0,0,0), scrollZIndex),
			Defense = createInput(ivRow, "Def", UDim2.new(0.22, 0, 1, 0), UDim2.new(0,0,0,0), scrollZIndex),
			Speed = createInput(ivRow, "Spe", UDim2.new(0.22, 0, 1, 0), UDim2.new(0,0,0,0), scrollZIndex),
		}
		
		-- Placement / Swap Logic
		createLabel(scroll, "Placement (Optional)", UDim2.new(1, 0, 0, 20), UDim2.new(0,0,0,0), scrollZIndex)
		local placementRow = Instance.new("Frame")
		placementRow.Size = UDim2.new(1, 0, 0, 36)
		placementRow.BackgroundTransparency = 1
		placementRow.ZIndex = scrollZIndex
		placementRow.Parent = scroll
		local pLayout = Instance.new("UIListLayout")
		pLayout.FillDirection = Enum.FillDirection.Horizontal
		pLayout.Padding = UDim.new(0, 10)
		pLayout.Parent = placementRow
		
		local _, getDestType = createDropdown(placementRow, "Dest", UDim2.new(0.3, 0, 1, 0), UDim2.new(0,0,0,0), {"Auto", "Party", "Box"}, scrollZIndex)
		local slotIdxInput = createInput(placementRow, "Slot (1-6/1-30)", UDim2.new(0.3, 0, 1, 0), UDim2.new(0,0,0,0), scrollZIndex)
		local boxIdxInput = createInput(placementRow, "Box #", UDim2.new(0.3, 0, 1, 0), UDim2.new(0,0,0,0), scrollZIndex)

		local toggleRow = Instance.new("Frame")
		toggleRow.Size = UDim2.new(1, 0, 0, 30)
		toggleRow.BackgroundTransparency = 1
		toggleRow.ZIndex = scrollZIndex
		toggleRow.Parent = scroll
		local tLayout = Instance.new("UIListLayout")
		tLayout.FillDirection = Enum.FillDirection.Horizontal
		tLayout.Padding = UDim.new(0, 20)
		tLayout.Parent = toggleRow
		
		local _, getShiny = createToggle(toggleRow, "Shiny", UDim2.new(0.3, 0, 1, 0), UDim2.new(0,0,0,0), false, scrollZIndex)
		local _, getLocked = createToggle(toggleRow, "Trade Locked", UDim2.new(0.3, 0, 1, 0), UDim2.new(0,0,0,0), false, scrollZIndex)
		local _, getHidden = createToggle(toggleRow, "Hidden Ability", UDim2.new(0.3, 0, 1, 0), UDim2.new(0,0,0,0), false, scrollZIndex)
		
		createButton(scroll, "Create Creature", UDim2.new(1, 0, 0, 40), UDim2.new(0,0,0,0), COLORS.Accent, function()
			local target = getPlayerId(getTargetPlayer())
			if not target then notify("Player not found", true) return end
			
			local ivs = {}
			if tonumber(ivInputs.HP.Text) then ivs.HP = tonumber(ivInputs.HP.Text) end
			if tonumber(ivInputs.Attack.Text) then ivs.Attack = tonumber(ivInputs.Attack.Text) end
			if tonumber(ivInputs.Defense.Text) then ivs.Defense = tonumber(ivInputs.Defense.Text) end
			if tonumber(ivInputs.Speed.Text) then ivs.Speed = tonumber(ivInputs.Speed.Text) end
			
			local dest = getDestType()
			if dest == "" or dest == "Dest" then dest = "Auto" end
			
			local info = {
				Creature = getSpecies(),
				Level = tonumber(levelInput.Text) or 5,
				Nature = getNature(),
				Ability = abilityInput.Text ~= "" and abilityInput.Text or nil,
				Shiny = getShiny(),
				TradeLocked = getLocked(),
				HiddenAbility = getHidden(),
				IVs = ivs,
				Placement = {
					Type = dest,
					Slot = tonumber(slotIdxInput.Text),
					Box = tonumber(boxIdxInput.Text)
				}
			}
			
			if info.Creature == "" then notify("Select a species", true) return end
			
			local res = Request:InvokeServer({"AdminAction", "CreateCreature", target, { CreatureInfo = info }})
			notify(res.Message, not res.Success)
		end, scrollZIndex)
		
		createLabel(scroll, "Remove Creature", UDim2.new(1, 0, 0, 20), UDim2.new(0,0,0,0), scrollZIndex)
		
		local removeSlotInput = createInput(scroll, "Slot Index", UDim2.new(1, 0, 0, 36), UDim2.new(0,0,0,0), scrollZIndex)
		local removeBoxInput = createInput(scroll, "Box Index (Optional)", UDim2.new(1, 0, 0, 36), UDim2.new(0,0,0,0), scrollZIndex)
		
		createButton(scroll, "Remove Creature", UDim2.new(1, 0, 0, 40), UDim2.new(0,0,0,0), COLORS.Danger, function()
			local target = getPlayerId(getTargetPlayer())
			if not target then notify("Player not found", true) return end
			
			local slot = tonumber(removeSlotInput.Text)
			local box = tonumber(removeBoxInput.Text)
			
			if not slot then notify("Enter slot index", true) return end
			
			local res = Request:InvokeServer({"AdminAction", "RemoveCreature", target, { SlotIndex = slot, BoxIndex = box }})
			notify(res.Message, not res.Success)
		end, scrollZIndex)
		
		-- Padding bottom
		local pad = Instance.new("Frame")
		pad.Size = UDim2.new(1, 0, 0, 20)
		pad.BackgroundTransparency = 1
		pad.ZIndex = scrollZIndex
		pad.Parent = scroll
	end
	
	-- Implement Items Tab
	do
		local page = contentFrames["Items"]
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 10)
		layout.Parent = page
		
		local _, getTargetPlayer = createPlayerDropdown(page, "Target Player (Name/ID)", UDim2.new(1, 0, 0, 36), UDim2.new(0,0,0,0))
		local _, getItem = createDropdown(page, "Item", UDim2.new(1, 0, 0, 36), UDim2.new(0,0,0,0), itemNames)
		local qtyInput = createInput(page, "Quantity", UDim2.new(1, 0, 0, 36), UDim2.new(0,0,0,0))
		qtyInput.Text = "1"
		
		createButton(page, "Give Item", UDim2.new(1, 0, 0, 40), UDim2.new(0,0,0,0), COLORS.Accent, function()
			local target = getPlayerId(getTargetPlayer())
			if not target then notify("Player not found", true) return end
			
			local item = getItem()
			if item == "" then notify("Select an item", true) return end
			
			local qty = tonumber(qtyInput.Text) or 1
			
			local res = Request:InvokeServer({"AdminAction", "GiveItem", target, { ItemName = item, Quantity = qty }})
			notify(res.Message, not res.Success)
		end)
	end
	
	-- Implement Data Tab
	do
		local page = contentFrames["Data"]
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 10)
		layout.Parent = page
		
		local _, getTargetPlayer = createPlayerDropdown(page, "Target Player (Name/ID)", UDim2.new(1, 0, 0, 36), UDim2.new(0,0,0,0))
		local fieldInput = createInput(page, "Data Field Name (e.g. Studs)", UDim2.new(1, 0, 0, 36), UDim2.new(0,0,0,0))
		local valInput = createInput(page, "Value", UDim2.new(1, 0, 0, 36), UDim2.new(0,0,0,0))
		
		createLabel(page, "Note: Dangerous! Be careful with types.", UDim2.new(1, 0, 0, 20), UDim2.new(0,0,0,0))
		
		createButton(page, "Set Data", UDim2.new(1, 0, 0, 40), UDim2.new(0,0,0,0), COLORS.Danger, function()
			local target = getPlayerId(getTargetPlayer())
			if not target then notify("Player not found", true) return end
			
			local field = fieldInput.Text
			if field == "" then notify("Enter field name", true) return end
			
			local rawVal = valInput.Text
			local val: any = rawVal
			
			-- Attempt basic type conversion
			if tonumber(rawVal) then
				val = tonumber(rawVal)
			elseif rawVal == "true" then
				val = true
			elseif rawVal == "false" then
				val = false
			end
			
			local res = Request:InvokeServer({"AdminAction", "SetPlayerData", target, { Field = field, Value = val }})
			notify(res.Message, not res.Success)
		end)
		
		createButton(page, "View Data (Output console)", UDim2.new(1, 0, 0, 40), UDim2.new(0,0,0,0), COLORS.Accent, function()
			local target = getPlayerId(getTargetPlayer())
			if not target then notify("Player not found", true) return end
			
			local res = Request:InvokeServer({"ViewPlayerData", target})
			if res.Success then
				print("=== PLAYER DATA (" .. tostring(target) .. ") ===")
				print(res.Data)
				print("===========================================")
				notify("Data printed to console (F9)", false)
			else
				notify(res.Message, true)
			end
		end)
	end
	
	-- Implement Misc Tab
	do
		local page = contentFrames["Misc"]
		local scroll = Instance.new("ScrollingFrame")
		scroll.Size = UDim2.new(1, 0, 1, 0)
		scroll.BackgroundTransparency = 1
		scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.ScrollBarThickness = 4
		scroll.ZIndex = 1
		scroll.Parent = page
		
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 10)
		layout.Parent = scroll
		
		local scrollZIndex = 2
		
		createLabel(scroll, "Start Encounter", UDim2.new(1, 0, 0, 20), UDim2.new(0,0,0,0), scrollZIndex)
		
		local _, getTargetPlayer = createPlayerDropdown(scroll, "Target Player", UDim2.new(1, 0, 0, 36), UDim2.new(0,0,0,0), scrollZIndex)
		local _, getCreature = createDropdown(scroll, "Creature", UDim2.new(1, 0, 0, 36), UDim2.new(0,0,0,0), creatureNames, scrollZIndex)
		local levelInput = createInput(scroll, "Level (1-100)", UDim2.new(1, 0, 0, 36), UDim2.new(0,0,0,0), scrollZIndex)
		
		-- Get chunk list for battle scene selection
		local chunkNames = {"Chunk1", "Chunk2", "Professor's Lab", "PvP"}
		local _, getChunk = createDropdown(scroll, "Battle Scene (Chunk)", UDim2.new(1, 0, 0, 36), UDim2.new(0,0,0,0), chunkNames, scrollZIndex)
		
		local toggleRow = Instance.new("Frame")
		toggleRow.Size = UDim2.new(1, 0, 0, 30)
		toggleRow.BackgroundTransparency = 1
		toggleRow.ZIndex = scrollZIndex
		toggleRow.Parent = scroll
		local tLayout = Instance.new("UIListLayout")
		tLayout.FillDirection = Enum.FillDirection.Horizontal
		tLayout.Padding = UDim.new(0, 20)
		tLayout.Parent = toggleRow
		
		local _, getShiny = createToggle(toggleRow, "Shiny", UDim2.new(0.3, 0, 1, 0), UDim2.new(0,0,0,0), false, scrollZIndex)
		local _, getStatic = createToggle(toggleRow, "Static", UDim2.new(0.3, 0, 1, 0), UDim2.new(0,0,0,0), false, scrollZIndex)
		local _, getBoss = createToggle(toggleRow, "Boss", UDim2.new(0.3, 0, 1, 0), UDim2.new(0,0,0,0), false, scrollZIndex)
		
		createButton(scroll, "Start Encounter", UDim2.new(1, 0, 0, 40), UDim2.new(0,0,0,0), COLORS.Accent, function()
			local targetUserId = getPlayerId(getTargetPlayer())
			if not targetUserId then notify("Player not found", true) return end
			
			local creature = getCreature()
			if creature == "" then notify("Select a creature", true) return end
			
			local level = tonumber(levelInput.Text)
			if not level or level < 1 or level > 100 then notify("Enter valid level (1-100)", true) return end
			
			local chunk = getChunk()
			if chunk == "" or chunk == "Battle Scene (Chunk)" then chunk = "Chunk1" end
			
			-- Build battle data
			local battleData = {
				CreatureName = creature,
				Level = level,
				Shiny = getShiny(),
				IsStatic = getStatic(),
				IsBoss = getBoss()
			}
			
			-- Use admin action to start encounter for target player
			local res = Request:InvokeServer({"AdminAction", "StartEncounter", targetUserId, { BattleData = battleData, ChunkName = chunk }})
			notify(res.Message, not res.Success)
		end, scrollZIndex)
		
		-- Padding bottom
		local pad = Instance.new("Frame")
		pad.Size = UDim2.new(1, 0, 0, 20)
		pad.BackgroundTransparency = 1
		pad.ZIndex = scrollZIndex
		pad.Parent = scroll
	end
	
	switchTab("Players")
	return screenGui
end

-- Module Export
local AdminPanel = {}

function AdminPanel.Init()
	task.spawn(function()
		-- Check permissions first
		local success, result = pcall(function()
			return Request:InvokeServer({"CheckAdminPermission"})
		end)
		
		if success and result and result.Success then
			permissionLevel = result.Level
			if permissionLevel == "Admin" or permissionLevel == "Mod" then
				isAdmin = true
				print("[AdminPanel] Admin access granted. Level:", permissionLevel)
				
				local gui = createAdminPanel()
				
				-- Toggle Bind
				UserInputService.InputBegan:Connect(function(input, gpe)
					if gpe then return end
					if input.KeyCode == Enum.KeyCode.F2 or input.KeyCode == Enum.KeyCode.Quote then
						isVisible = not isVisible
						gui.Enabled = isVisible
					end
				end)
			end
		else
			-- Not admin or error
			print("[AdminPanel] No admin access or permission check failed.")
		end
	end)
end

return AdminPanel


--!strict

-- Dex.lua
-- Responsible for rendering the Dex list and current creature info panel.

local DexModule = {}

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService: TweenService = game:GetService("TweenService")

--// Shared modules
local Creatures = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Creatures"))
local TypesModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local LuaTypes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LuaTypes"))

-- Client-side data cache
local ClientData = require(script.Parent.Parent:WaitForChild("Plugins"):WaitForChild("ClientData"))

--// Types
type CreatureDef = LuaTypes.Creature

type DexEntry = {
	Name: string,
	Base: CreatureDef,
}

type CaughtFlags = {
	[ string ]: {
		Normal: boolean,
		Shiny: boolean,
	},
}

--// Constants
local OPEN_SIZE: UDim2 = UDim2.fromScale(0.543, 0.58)
local CLOSED_SIZE: UDim2 = UDim2.fromScale(0, 0)

local RARITY_COLORS: { [string]: Color3 } = {
	Basic = Color3.fromRGB(0x9D, 0x9D, 0x9D),
	Advanced = Color3.fromRGB(0x1E, 0xFF, 0x00),
	Rare = Color3.fromRGB(0x00, 0x70, 0xDD),
	Legendary = Color3.fromRGB(0xA3, 0x35, 0xEE),
	Transcendent = Color3.fromRGB(0xFF, 0x80, 0x00),
}

--// State
local isOpen = false
local _entries: { DexEntry } = {}

--// Helpers
local function getGui(): GuiObject?
	local player = Players.LocalPlayer
	if not player then
		print("[Dex] getGui: no LocalPlayer")
		return nil
	end

	local pg = player:FindFirstChild("PlayerGui")
	if not pg then
		print("[Dex] getGui: no PlayerGui")
		return nil
	end

	local gameUi = pg:FindFirstChild("GameUI")
	if not gameUi then
		print("[Dex] getGui: no GameUI under PlayerGui")
		return nil
	end

	local dexGui = gameUi:FindFirstChild("Dex")
	if dexGui and dexGui:IsA("GuiObject") then
		print("[Dex] getGui: found Dex GuiObject", dexGui:GetFullName())
		return dexGui
	end

	print("[Dex] getGui: Dex GuiObject not found under GameUI")
	return nil
end

local function buildDexEntries(): { DexEntry }
	-- Cache once per session; creatures table is static
	if #_entries > 0 then
		print("[Dex] buildDexEntries: using cached entries, count =", #_entries)
		return _entries
	end

	local tmp: { DexEntry } = {}
	for name, def in pairs(Creatures :: any) do
		if type(def) == "table" and typeof(def.DexNumber) == "number" then
			table.insert(tmp, {
				Name = name,
				Base = def :: CreatureDef,
			})
		end
	end

	table.sort(tmp, function(a, b)
		local da = a.Base.DexNumber or 0
		local db = b.Base.DexNumber or 0
		if da == db then
			return a.Name < b.Name
		end
		return da < db
	end)

	_entries = tmp
	print("[Dex] buildDexEntries: built entries, count =", #_entries)
	return _entries
end

local function computeCaughtFlags(): (CaughtFlags, number)
	local data = ClientData:Get()
	local flags: CaughtFlags = {}

	if not data then
		return flags, 0
	end

	local function markCreature(creature: any)
		if not creature or type(creature.Name) ~= "string" then
			return
		end
		local name = creature.Name
		flags[name] = flags[name] or { Normal = false, Shiny = false }
		if creature.Shiny == true then
			flags[name].Shiny = true
		else
			flags[name].Normal = true
		end
	end

	-- Party
	if type(data.Party) == "table" then
		for _, c in ipairs(data.Party) do
			markCreature(c)
		end
	end

	-- Boxes (new schema: { Name = string, Creatures = { ... } })
	if type(data.Boxes) == "table" then
		for _, box in ipairs(data.Boxes) do
			if type(box) == "table" and type(box.Creatures) == "table" then
				for _, c in ipairs(box.Creatures) do
					markCreature(c)
				end
			end
		end
	end

	-- Count unique entries with at least one variant caught
	local uniqueCount = 0
	for _, v in pairs(flags) do
		if v and (v.Normal or v.Shiny) then
			uniqueCount += 1
		end
	end

	print("[Dex] computeCaughtFlags: uniqueCaught =", uniqueCount)
	return flags, uniqueCount
end

local function setTypeFrame(frame: Instance?, typeName: string?)
	if not frame or not typeName or type(typeName) ~= "string" or typeName == "" then
		if frame and frame:IsA("Frame") then
			frame.Visible = false
		elseif frame and frame:IsA("TextLabel") then
			frame.Text = "-"
		end
		return
	end

	local typeData = TypesModule[typeName]
	if frame:IsA("Frame") then
		if typeData and typeData.uicolor then
			local c: Color3 = typeData.uicolor
			frame.BackgroundColor3 = c
			local stroke = frame:FindFirstChild("UIStroke")
			if stroke and stroke:IsA("UIStroke") then
				local darker = Color3.new(math.max(0, c.R * 0.6), math.max(0, c.G * 0.6), math.max(0, c.B * 0.6))
				stroke.Color = darker
			end
		end
		local typeText = frame:FindFirstChild("TypeText")
		if typeText and typeText:IsA("TextLabel") then
			typeText.Text = typeName
			local ttStroke = typeText:FindFirstChild("UIStroke")
			if ttStroke and typeData and typeData.uicolor then
				local c: Color3 = typeData.uicolor
				local darker = Color3.new(math.max(0, c.R * 0.6), math.max(0, c.G * 0.6), math.max(0, c.B * 0.6))
				ttStroke.Color = darker
			end
		end
		frame.Visible = true
	elseif frame:IsA("TextLabel") then
		frame.Text = typeName
	end
end

local function clearCurrentInfo(dexGui: GuiObject)
	local currentInfo = dexGui:FindFirstChild("CurrentInfo")
	if not currentInfo or not currentInfo:IsA("Frame") then
		print("[Dex] clearCurrentInfo: no CurrentInfo frame on", dexGui.Name)
		return
	end

	local main = currentInfo:FindFirstChild("Main")
	if main and main:IsA("Frame") then
		print("[Dex] clearCurrentInfo: hiding CurrentInfo.Main")
		main.Visible = false
	else
		print("[Dex] clearCurrentInfo: Main not found under CurrentInfo")
	end
end

local function showCurrentInfo(dexGui: GuiObject, def: CreatureDef)
	local currentInfo = dexGui:FindFirstChild("CurrentInfo")
	if not currentInfo or not currentInfo:IsA("Frame") then
		return
	end

	local main = currentInfo:FindFirstChild("Main")
	if not main or not main:IsA("Frame") then
		print("[Dex] showCurrentInfo: Main frame missing under CurrentInfo")
		return
	end

	print("[Dex] showCurrentInfo: showing info for", def.Name, "DexNumber =", def.DexNumber)
	main.Visible = true

	-- Basic text fields
	local nameLabel = main:FindFirstChild("CreatureName")
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = def.Name
	end

	local description = main:FindFirstChild("Description")
	if description and description:IsA("TextLabel") then
		description.Text = def.Description or ""
	end

	-- Stats (base stats)
	local atkInfo = main:FindFirstChild("ATKInfo")
	local defInfo = main:FindFirstChild("DEFInfo")
	local hpInfo = main:FindFirstChild("HPInfo")
	local spdInfo = main:FindFirstChild("SPDInfo")

	local function setAmount(frame: Instance?, value: number?)
		if not frame then
			return
		end
		local amount = frame:FindFirstChild("Amount")
		if amount and amount:IsA("TextLabel") then
			amount.Text = tostring(value or 0)
		end
	end

	setAmount(atkInfo, def.BaseStats.Attack)
	setAmount(defInfo, def.BaseStats.Defense)
	setAmount(hpInfo, def.BaseStats.HP)
	setAmount(spdInfo, def.BaseStats.Speed)

	-- Rarity
	local rarityFrame = main:FindFirstChild("Rarity")
	local rarityTitle = main:FindFirstChild("RarityTitle")
	local rarityName = def.Class or "Basic"
	local rarityColor = RARITY_COLORS[rarityName] or RARITY_COLORS.Basic

	if rarityFrame then
		if rarityFrame:IsA("TextLabel") then
			rarityFrame.Text = rarityName
			rarityFrame.TextColor3 = rarityColor
		elseif rarityFrame:IsA("ImageLabel") then
			rarityFrame.ImageColor3 = rarityColor
			local label = rarityFrame:FindFirstChild("Text")
			if label and label:IsA("TextLabel") then
				label.Text = rarityName
			end
		end
	end

	-- Separate title label for rarity text (if present)
	if rarityTitle and rarityTitle:IsA("TextLabel") then
		rarityTitle.Text = rarityName
	end

	-- Types (mirror Summary / Caught behavior)
	local firstType = main:FindFirstChild("FirstType")
	local secondType = main:FindFirstChild("SecondType")

	local typesList: { string } = {}
	if typeof(def.Type) == "table" then
		for i, t in ipairs(def.Type) do
			if typeof(t) == "string" then
				typesList[i] = t
			end
		end
	elseif typeof(def.Type) == "string" then
		typesList[1] = def.Type
	end

	if firstType then
		setTypeFrame(firstType, typesList[1])
	end

	if secondType then
		if typesList[2] then
			setTypeFrame(secondType, typesList[2])
			if secondType:IsA("GuiObject") then
				secondType.Visible = true
			end
		else
			if secondType:IsA("GuiObject") then
				secondType.Visible = false
			end
		end
	end
end

local function renderList(dexGui: GuiObject, entries: { DexEntry }, flags: CaughtFlags)
	local listRoot = dexGui:FindFirstChild("List")
	if not listRoot or not listRoot:IsA("ScrollingFrame") then
		print("[Dex] renderList: List scrolling frame not found under Dex")
		return
	end

	local template = listRoot:FindFirstChild("Template")
	if not template or not (template:IsA("TextButton") or template:IsA("ImageButton")) then
		print(
			"[Dex] renderList: Template missing or not a button; found =",
			template ~= nil and template.ClassName or "nil"
		)
		return
	end

	-- Clear existing rows (keep Template and layout objects)
	for _, child in ipairs(listRoot:GetChildren()) do
		if child ~= template and child:IsA("GuiObject") and child.Name ~= "UIListLayout" and child.Name ~= "UIPadding" then
			child:Destroy()
		end
	end

	clearCurrentInfo(dexGui)

	print("[Dex] renderList: rendering", #entries, "entries")

	for index, entry in ipairs(entries) do
		local base = entry.Base
		local row = template:Clone()
		row.Name = base.Name
		row.Visible = true
		row.LayoutOrder = index
		row.Parent = listRoot

		-- Creature name
		local nameLabel = row:FindFirstChild("CreatureName")
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = base.Name
		end

		-- Dex number
		local numLabel = row:FindFirstChild("BGNum")
		if numLabel and numLabel:IsA("TextLabel") then
			local dn = base.DexNumber or index
			if dn < 100 then
				numLabel.Text = string.format("#%02d", dn)
			else
				numLabel.Text = "#" .. tostring(dn)
			end
		end

		-- Rarity chip
		local rarity = row:FindFirstChild("Rarity")
		local rarityName = base.Class or "Basic"
		local rarityColor = RARITY_COLORS[rarityName] or RARITY_COLORS.Basic
		if rarity then
			if rarity:IsA("ImageLabel") then
				rarity.ImageColor3 = rarityColor
			elseif rarity:IsA("Frame") then
				rarity.BackgroundColor3 = rarityColor
			elseif rarity:IsA("TextLabel") then
				rarity.TextColor3 = rarityColor
			end
		end

		-- Icons (normal + shiny)
		local normalIcon = row:FindFirstChild("CreatureIcon")
		local shinyIcon = row:FindFirstChild("CreatureIconShiny")

		if normalIcon and normalIcon:IsA("ImageLabel") then
			if base.Sprite and type(base.Sprite) == "string" then
				normalIcon.Image = base.Sprite
			end
		end

		if shinyIcon and shinyIcon:IsA("ImageLabel") then
			if base.ShinySprite and type(base.ShinySprite) == "string" then
				shinyIcon.Image = base.ShinySprite
			else
				-- fallback to normal sprite if shiny sprite is missing
				if base.Sprite and type(base.Sprite) == "string" then
					shinyIcon.Image = base.Sprite
				end
			end
		end

		-- Icon tint based on whether we've caught this variant
		local caught = flags[base.Name]
		local hasNormal = caught and caught.Normal or false
		local hasShiny = caught and caught.Shiny or false

		local seenColor = Color3.fromRGB(255, 255, 255)
		local unseenColorNormal = Color3.fromRGB(47, 47, 47)
		local unseenColorShiny = Color3.fromRGB(0, 0, 0)

		if normalIcon and normalIcon:IsA("ImageLabel") then
			normalIcon.ImageColor3 = hasNormal and seenColor or unseenColorNormal
		end

		if shinyIcon and shinyIcon:IsA("ImageLabel") then
			-- Shiny unseen state uses pure black, per spec
			shinyIcon.ImageColor3 = hasShiny and seenColor or unseenColorShiny
		end

		-- Selection handler to load CurrentInfo for this base creature
		row.MouseButton1Click:Connect(function()
			print("[Dex] row clicked:", base.Name, "DexNumber =", base.DexNumber)
			showCurrentInfo(dexGui, base)
		end)
	end
end

local function updateTitle(dexGui: GuiObject, total: number, caughtUnique: number)
	local titleHolder = dexGui:FindFirstChild("TitleHolder")
	if not titleHolder or not titleHolder:IsA("Frame") then
		return
	end

	local title = titleHolder:FindFirstChild("Title")
	if not title or not title:IsA("TextLabel") then
		return
	end

	title.Text = string.format("Dex Entries - Total: %d  |  Caught: %d", total, caughtUnique)
end

function DexModule:Refresh()
	local dexGui = getGui()
	if not dexGui then
		print("[Dex] Refresh: Dex GUI not available, abort")
		return
	end

	local entries = buildDexEntries()
	local flags, caughtUnique = computeCaughtFlags()

	updateTitle(dexGui, #entries, caughtUnique)
	renderList(dexGui, entries, flags)
end

function DexModule:Open()
	if isOpen then
		print("[Dex] Open: already open, skipping")
		return
	end

	local dexGui = getGui()
	if not dexGui then
		print("[Dex] Open: Dex GUI not found")
		return
	end

	isOpen = true

	-- Always refresh content on open so new captures are reflected
	print("[Dex] Open: refreshing content and playing open tween")
	self:Refresh()

	dexGui.Visible = true
	dexGui.Size = CLOSED_SIZE

	-- Position and size tween (match other menus style)
	dexGui.Position = UDim2.new(0.5 - (OPEN_SIZE.X.Scale / 2), 0, 0.1, 0)

	TweenService:Create(dexGui, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Size = OPEN_SIZE,
		Position = UDim2.new(0.5, 0, 0.5, 0),
	}):Play()
end

function DexModule:Close()
	if not isOpen then
		return
	end

	local dexGui = getGui()
	if not dexGui then
		isOpen = false
		return
	end

	isOpen = false

	TweenService:Create(dexGui, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Size = CLOSED_SIZE,
	}):Play()

	-- Small delay before fully hiding to let the tween finish
	task.delay(0.25, function()
		local guiNow = getGui()
		if guiNow then
			guiNow.Visible = false
		end
	end)
end

return DexModule



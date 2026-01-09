--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local GameUI = PlayerGui:WaitForChild("GameUI")
local UIFunctions = require(script.Parent:WaitForChild("UIFunctions"))
local Audio = script.Parent.Parent:WaitForChild("Assets"):WaitForChild("Audio")

local function getGui(): Frame?
	local gui = GameUI:FindFirstChild("Trade")
	if gui and gui:IsA("Frame") then
		return gui
	end
	return nil
end

local Utilities = script.Parent.Parent:WaitForChild("Utilities")
local Say = require(Utilities:WaitForChild("Say"))
local BoxBackgrounds = require(Utilities:WaitForChild("BoxBackgrounds"))
local SummaryUI = require(script.Parent:WaitForChild("Summary"))
local Creatures = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Creatures"))
local Items = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Items"))
local CharacterFunctions = require(Utilities:WaitForChild("CharacterFunctions"))

local Events = ReplicatedStorage:WaitForChild("Events")
local Request = Events:WaitForChild("Request")

local TradeUI = {}

type TradeState = {
	SessionId: string?,
	PartnerDisplayName: string?,
	PartnerUserId: number?,
	TotalBoxes: number,
	CurrentBox: number,
	Ready: {[number]: boolean},
	Confirmed: {[number]: boolean},
	ChatOrder: number,
}

local state: TradeState = {
	SessionId = nil,
	PartnerDisplayName = nil,
	PartnerUserId = nil,
	TotalBoxes = 1,
	CurrentBox = 1,
	Ready = {},
	Confirmed = {},
	ChatOrder = 0,
}

local _buttonContext: {[Instance]: any} = {}
local _optionsConnections: {RBXScriptConnection} = {}
local _optionsClickOffConn: RBXScriptConnection? = nil
local _optionsTemplate: Instance? = nil
local _optionsActive: Instance? = nil
local _cooldownEnd: number? = nil
local _tradeLocked: boolean = false
local showOptionsOnButton: ((Instance, any) -> ())? = nil
local updateActionButtons: (() -> ())? = nil
local markOfferChanged: (() -> ())? = nil
local appendChat: ((string, string, number?, boolean?) -> ())? = nil
local setIconState: ((Instance, any) -> ())? = nil
local _offeredSlots: {[string]: boolean} = {}
local _partnerOffers: {[string]: any} = {}
local requestBox: ((number) -> ())? = nil
local _uiModule: any = nil
local _partySnapshot: any = nil

local function getUI()
	if _uiModule then
		return _uiModule
	end
	local ok, ui = pcall(function()
		return require(script.Parent) -- UI/init.lua
	end)
	if ok and ui then
		_uiModule = ui
	end
	return _uiModule
end

local function setTradeSuppressed(active: boolean)
	local ui = getUI()
	pcall(function()
		CharacterFunctions:SetSuppressed(active)
		CharacterFunctions:CanMove(not active)
	end)
	if ui and ui.TopBar then
		if active then
			-- Trading is starting: suppress and hide TopBar
			ui.TopBar:SetSuppressed(true)
			if ui.TopBar.HideImmediate then
				ui.TopBar:HideImmediate()
			elseif ui.TopBar.Hide then
				ui.TopBar:Hide()
			end
		else
			-- Trading is ending: restore TopBar
			ui.TopBar:SetSuppressed(false)
			if ui.TopBar.Show then
				ui.TopBar:Show()
			end
		end
	end
end

local function clearOptionsConnections()
	for _, c in ipairs(_optionsConnections) do
		if c and c.Connected then
			c:Disconnect()
		end
	end
	_optionsConnections = {}
	if _optionsClickOffConn and _optionsClickOffConn.Connected then
		_optionsClickOffConn:Disconnect()
	end
	_optionsClickOffConn = nil
end

local function hideCreatureOptions()
	local gui = getGui()
	if not gui then return end
	if _optionsActive then
		_optionsActive:Destroy()
		_optionsActive = nil
	end
	clearOptionsConnections()
end

-- Visually clear a box button while keeping its layout slot and blocking clicks.
local function hideButtonVisuals(btn: Instance?)
	if not (btn and btn:IsA("GuiButton")) then
		return
	end
	btn.Active = false
	btn.AutoButtonColor = false
	btn.Selectable = false
	btn.BackgroundTransparency = 1
	for _, child in ipairs(btn:GetChildren()) do
		if child:IsA("GuiObject") then
			if child:IsA("TextLabel") then
				child.TextTransparency = 1
			elseif child:IsA("ImageLabel") or child:IsA("ImageButton") then
				child.ImageTransparency = 1
			end
			child.Visible = true -- keep size/layout but hide content via transparency
		end
	end
end

local function hideBoxButtonForKey(boxKey: string?)
	if not boxKey then return end
	for inst, ctx in pairs(_buttonContext) do
		if ctx and ctx.Source == "Box" and ctx.BoxKey == boxKey and inst and inst:IsA("GuiButton") then
			hideButtonVisuals(inst)
		end
	end
end

local function attachClickOff()
	if _optionsClickOffConn and _optionsClickOffConn.Connected then
		_optionsClickOffConn:Disconnect()
	end
	local UIS = game:GetService("UserInputService")
	_optionsClickOffConn = UIS.InputBegan:Connect(function(input, gp)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
		-- Note: allow clicks that are already gameProcessed (e.g., UI buttons) so clicking anywhere closes the options.
		task.defer(function()
			local opts = _optionsActive
			if not opts or not opts.Parent then
				hideCreatureOptions()
				return
			end
			local mouse = LocalPlayer:GetMouse()
			local pos = Vector2.new(mouse.X, mouse.Y)
			local absPos = opts.AbsolutePosition
			local absSize = opts.AbsoluteSize
			local inside = pos.X >= absPos.X and pos.X <= absPos.X + absSize.X and pos.Y >= absPos.Y and pos.Y <= absPos.Y + absSize.Y
			if not inside then
				hideCreatureOptions()
			end
		end)
	end)
end

local function countOfferListings(listings: Instance?): number
	if not listings then
		return 0
	end
	local count = 0
	for _, child in ipairs(listings:GetChildren()) do
		local isLayout = child.Name == "ListingTemplate" or child.Name == "UIGridLayout" or child.Name == "UIPadding"
		local isAdd = child.Name == "Add"
		if child:IsA("GuiObject") and child.Visible and (not isLayout) and (not isAdd) then
			count += 1
		end
	end
	return count
end

local function addToOffer(creature: any, srcCtx: any?)
	if _tradeLocked then
		return
	end
	-- Prevent trading away the last party member.
	if srcCtx and srcCtx.Source == "Box" and srcCtx.BoxIndex == 1 then
		local snapshot = _partySnapshot
		local creatures = snapshot and snapshot.Creatures
		local partyCount = 0
		for i = 1, 6 do
			if creatures and creatures[i] then
				partyCount += 1
			end
		end
		local offeredParty = 0
		for key in pairs(_offeredSlots) do
			if string.match(key, "^P:%d+$") then
				offeredParty += 1
			end
		end
		local remaining = partyCount - offeredParty
		if remaining <= 1 then
			if appendChat then
				appendChat("System", "You must keep at least one party member.", nil, true)
			end
			return
		end
	end
	local gui = getGui(); if not gui then return end
	local boxView = gui:FindFirstChild("BoxView"); if not boxView then return end
	local boxTemplate = boxView:FindFirstChild("BoxTemplate"); if not boxTemplate then return end
	local yourOffer = gui:FindFirstChild("YourOffer")
	local listings = yourOffer and yourOffer:FindFirstChild("Listings")
	if not (yourOffer and listings) then
		warn("[TradeUI] addToOffer missing listings")
		return
	end
	if countOfferListings(listings) >= 9 then
		if appendChat then
			appendChat("System", "You cannot add more than 9 creatures to a trade.", nil, true)
		end
		return
	end
	local clone = boxTemplate:Clone()
	setIconState(clone, creature)
	clone.Position = UDim2.new(0.5, 0, 0.5, 0)
	clone.Size = UDim2.new(0.8, 0, 0.8, 0)
	clone.Visible = true
	clone.Parent = listings
	local key = nil
	if srcCtx and srcCtx.BoxIndex and srcCtx.SlotIndex then
		if srcCtx.BoxIndex == 1 then
			key = "P:" .. tostring(srcCtx.SlotIndex)
		else
			local trueBoxIndex = (srcCtx.BoxIndex or 1) - 1
			key = tostring(trueBoxIndex) .. ":" .. tostring(srcCtx.SlotIndex)
		end
		_offeredSlots[key] = true
	end
	print("[TradeUI] addToOffer", key or "no-key")
	_buttonContext[clone] = {
		Source = "Offer",
		Owner = "Self",
		Creature = creature,
		BoxKey = key,
	}
	clone.MouseButton1Click:Connect(function()
		if showOptionsOnButton then
			showOptionsOnButton(clone, _buttonContext[clone])
		end
	end)
	-- Notify server so partner sees update
	if state.SessionId and key then
		local ok = Request:InvokeServer({"TradeUpdateOffer", {
			SessionId = state.SessionId,
			Action = "Add",
			BoxKey = key,
			Creature = creature,
		}})
		print("[TradeUI] TradeUpdateOffer Add result", ok)
	end
	if key then
		hideBoxButtonForKey(key)
	end
	markOfferChanged()
end

local function removeOffer(button: Instance)
	if _tradeLocked then
		return
	end
	-- Ensure options are not parented to a button we're about to destroy
	do
		local gui = getGui()
		local boxView = gui and gui:FindFirstChild("BoxView")
		local opts = boxView and boxView:FindFirstChild("CreatureOptions")
		if opts and opts.Parent == button then
		if boxView then
			opts.Parent = boxView
		end
			opts.Visible = false
		end
	end
	if button and button.Parent then
		button:Destroy()
	end
	local ctx = _buttonContext[button]
	if ctx and ctx.BoxKey then
		_offeredSlots[ctx.BoxKey] = nil
		requestBox(state.CurrentBox)
		if state.SessionId then
			Request:InvokeServer({"TradeUpdateOffer", {
				SessionId = state.SessionId,
				Action = "Remove",
				BoxKey = ctx.BoxKey,
			}})
		end
	end
	_buttonContext[button] = nil
	markOfferChanged()
	hideCreatureOptions()
end

local function showSummary(creature: any)
	-- Set up navigation callbacks (no navigation in Trade context)
	SummaryUI:SetNavigationCallbacks(
		nil, -- No Next
		nil, -- No Previous
		function()
			-- Close callback: hide summary
			SummaryUI:Hide()
		end
	)
	
	-- Hide navigation buttons (Trade context doesn't support navigation)
	SummaryUI:UpdateNavigationVisibility(false, false)
	
	-- Show summary with creature data
	SummaryUI:Show(creature, "Trade")
end

local function _showOptions(button: Instance, ctx: any)
	if _tradeLocked then
		return
	end
	local gui = getGui(); if not gui then return end
	local boxView = gui:FindFirstChild("BoxView"); if not boxView then return end
	if not _optionsTemplate then
		_optionsTemplate = boxView:FindFirstChild("CreatureOptions")
	end
	if not (_optionsTemplate and _optionsTemplate:IsA("Frame")) then
		warn("[TradeUI] CreatureOptions template missing in showOptionsOnButton")
		return
	end
	print("[TradeUI] showOptionsOnButton", button.Name, ctx and ctx.Source, ctx and ctx.BoxKey)

	clearOptionsConnections()
	if _optionsActive then
		_optionsActive:Destroy()
		_optionsActive = nil
	end
	local opts = _optionsTemplate:Clone()
	_optionsActive = opts
	opts.Visible = true
	opts.Parent = button
	attachClickOff()

	local action1 = opts:FindFirstChild("Action1")
	local action2 = opts:FindFirstChild("Action2")
	local title1 = action1 and action1:FindFirstChild("Title")
	local title2 = action2 and action2:FindFirstChild("Title")

	if action1 then action1.Visible = true end
	if title1 and title1:IsA("TextLabel") then title1.Text = "" end
	if title2 and title2:IsA("TextLabel") then title2.Text = "Summary" end

	if ctx.Source == "Box" then
		if title1 and title1:IsA("TextLabel") then
			title1.Text = "Add to trade"
		end
		if action1 and action1:IsA("GuiButton") then
			table.insert(_optionsConnections, action1.MouseButton1Click:Connect(function()
				addToOffer(ctx.Creature, ctx)
				hideCreatureOptions()
			end))
		end
	elseif ctx.Source == "Offer" then
		if ctx.Owner == "Self" then
			if title1 and title1:IsA("TextLabel") then
				title1.Text = "Remove from trade"
			end
			if action1 and action1:IsA("GuiButton") then
				table.insert(_optionsConnections, action1.MouseButton1Click:Connect(function()
					removeOffer(button)
					hideCreatureOptions()
				end))
			end
		else
			if action1 and action1:IsA("GuiButton") then
				action1.Visible = false
			end
		end
	end

	if action2 and action2:IsA("GuiButton") then
		table.insert(_optionsConnections, action2.MouseButton1Click:Connect(function()
			showSummary(ctx.Creature)
			hideCreatureOptions()
		end))
	end
end

showOptionsOnButton = _showOptions

local function _hasIconParts(inst: Instance?): boolean
	if not inst then return false end
	return inst:FindFirstChild("CreatureIcon")
		and inst:FindFirstChild("IconShadow")
		and inst:FindFirstChild("Shiny")
		and inst:FindFirstChild("ShinyShadow")
		and inst:FindFirstChild("HeldItem")
		and inst:FindFirstChild("HeldItemShadow") ~= nil
end

local function renderOfferList(frameName: string, offers: {[string]: any}, owner: "Self" | "Them")
	local gui = getGui(); if not gui then return end
	local frame = gui:FindFirstChild(frameName)
	if not frame then return end
	local listings = frame:FindFirstChild("Listings")
	local boxView = gui:FindFirstChild("BoxView")
	local boxTemplate = boxView and boxView:FindFirstChild("BoxTemplate")
	local template = listings and listings:FindFirstChild("ListingTemplate")

	-- Ensure partner offers render with the same icon/shiny/held visuals as our own box buttons.
	if not _hasIconParts(template) then
		template = nil
	end
	template = template or (_hasIconParts(boxTemplate) and boxTemplate) or template
	if not (listings and template) then return end

	for _, child in ipairs(listings:GetChildren()) do
		if child:IsA("GuiObject") and child.Name ~= "ListingTemplate" and child.Name ~= "UIGridLayout" and child.Name ~= "UIPadding" then
			child:Destroy()
			_buttonContext[child] = nil
		end
	end

	if type(offers) ~= "table" then return end
	for key, creature in pairs(offers) do
		if type(creature) == "table" then
			local clone = template:Clone()
			setIconState(clone, creature)
			clone.Position = UDim2.new(0.5, 0, 0.5, 0)
			clone.Size = UDim2.new(0.8, 0, 0.8, 0)
			clone.Visible = true
			clone.Parent = listings
			_buttonContext[clone] = {
				Source = "Offer",
				Owner = owner == "Self" and "Self" or "Other",
				Creature = creature,
				BoxKey = key,
			}
			clone.MouseButton1Click:Connect(function()
				if showOptionsOnButton then
					showOptionsOnButton(clone, _buttonContext[clone])
				end
			end)
		end
	end
end

local function getGui(): Frame?
	local gui = GameUI:FindFirstChild("Trade")
	if gui and gui:IsA("Frame") then
		return gui
	end
	return nil
end

local function setStatus(text: string)
	local gui = getGui()
	if not gui then
		return
	end
	local info = gui:FindFirstChild("TradeStatusInfo")
	local label = info and info:FindFirstChild("TradeStatus")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function setReadyStates()
	local gui = getGui()
	if not gui then
		return
	end
	local yourOffer = gui:FindFirstChild("YourOffer")
	local theirOffer = gui:FindFirstChild("TheirOffer")
	local yourReady = yourOffer and yourOffer:FindFirstChild("PlayerReady")
	local yourConfirmed = yourOffer and yourOffer:FindFirstChild("PlayerConfirmed")
	local theirReady = theirOffer and theirOffer:FindFirstChild("Ready")
	local theirConfirmed = theirOffer and theirOffer:FindFirstChild("Confirmed")

	local meReady = state.Ready[LocalPlayer.UserId] == true
	local themReady = state.Ready[state.PartnerUserId or -1] == true
	local meConf = state.Confirmed[LocalPlayer.UserId] == true
	local themConf = state.Confirmed[state.PartnerUserId or -1] == true

	if yourReady and yourReady:IsA("GuiObject") then
		yourReady.Visible = meReady and not meConf
	end
	if yourConfirmed and yourConfirmed:IsA("GuiObject") then
		yourConfirmed.Visible = meConf
	end
	if theirReady and theirReady:IsA("GuiObject") then
		theirReady.Visible = themReady and not themConf
	end
	if theirConfirmed and theirConfirmed:IsA("GuiObject") then
		theirConfirmed.Visible = themConf
	end

	if meReady and themReady then
		setStatus("TRADE STATUS: BOTH PLAYERS READY")
	else
		setStatus("TRADE STATUS: AWAITING INPUT")
	end

	-- Also refresh button visuals (color/text) based on cooldown state.
	updateActionButtons()
end

local function isCooldownActive(): boolean
	return _cooldownEnd ~= nil and _cooldownEnd > os.clock()
end

local function _getTextLabel(btn: Instance?): TextLabel?
	if not btn then return nil end
	local label = btn:FindFirstChild("TextLabel")
	if label and label:IsA("TextLabel") then
		return label
	end
	for _, child in ipairs(btn:GetChildren()) do
		if child:IsA("TextLabel") then
			return child
		end
	end
	return nil
end

function updateActionButtons()
	local gui = getGui()
	if not gui then return end
	local readyBtn = gui:FindFirstChild("ReadyUp")
	local confirmBtn = gui:FindFirstChild("ConfirmTrade")
	local cancelBtn = gui:FindFirstChild("CancelTrade")
	local now = os.clock()
	local blocked = isCooldownActive()
	local remaining = 0
	if blocked and _cooldownEnd then
		remaining = math.max(math.ceil(_cooldownEnd - now), 0)
	end
	local meReady = state.Ready[LocalPlayer.UserId] == true
	local themReady = state.Ready[state.PartnerUserId or -1] == true
	local readyBase = meReady and "UNREADY" or "READY"
	local confirmBlocked = _tradeLocked or blocked or not (meReady and themReady)

	local function apply(btn: Instance?, baseText: string, forceBlock: boolean)
		if not (btn and btn:IsA("GuiButton")) then return end
		local label = _getTextLabel(btn)
		local isBlocked = _tradeLocked or forceBlock or blocked
		btn.Active = not isBlocked
		btn.AutoButtonColor = not isBlocked
		btn.BackgroundColor3 = isBlocked and Color3.fromRGB(168, 168, 168) or Color3.fromRGB(55, 255, 0)
		if label then
			label.TextColor3 = isBlocked and Color3.fromRGB(79, 79, 79) or Color3.fromRGB(255, 255, 255)
			if isBlocked and blocked then
				label.Text = string.format("%s (%d)", baseText, remaining)
			else
				label.Text = baseText
			end
		end
	end
	apply(readyBtn, readyBase, false)
	apply(confirmBtn, "CONFIRM", confirmBlocked)
	if cancelBtn and cancelBtn:IsA("GuiButton") then
		cancelBtn.Active = not _tradeLocked
		cancelBtn.AutoButtonColor = not _tradeLocked
	end
end

local function startCooldown()
	_cooldownEnd = os.clock() + 5
	updateActionButtons()
	local thisCooldown = _cooldownEnd
	task.spawn(function()
		while _cooldownEnd and _cooldownEnd == thisCooldown and _cooldownEnd > os.clock() do
			updateActionButtons()
			task.wait(0.25)
		end
		if _cooldownEnd == thisCooldown then
			_cooldownEnd = nil
		end
		updateActionButtons()
	end)
end

function markOfferChanged()
	-- Any offer change should reset readiness/confirmation to prevent scams.
	state.Ready[LocalPlayer.UserId] = false
	if state.PartnerUserId then
		state.Ready[state.PartnerUserId] = false
		state.Confirmed[state.PartnerUserId] = false
	end
	state.Confirmed[LocalPlayer.UserId] = false
	_tradeLocked = false
	startCooldown()
	setReadyStates()
end

local function clearChat()
	local gui = getGui()
	if not gui then
		return
	end
	local chatBox = gui:FindFirstChild("ChatBox")
	if not chatBox then
		return
	end
	local list = chatBox:FindFirstChild("MessageList")
	if not list then
		return
	end
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") and child.Name ~= "MessageTemplate" and child.Name ~= "UIListLayout" then
			child:Destroy()
		end
	end
	state.ChatOrder = 0
end

local function scrollChatToBottom()
	local gui = getGui()
	if not gui then
		return
	end
	local chatBox = gui:FindFirstChild("ChatBox")
	if not chatBox then
		return
	end
	local list = chatBox:FindFirstChild("MessageList")
	if list and list:IsA("ScrollingFrame") then
		list.CanvasPosition = Vector2.new(0, 200000)
	end
end

function appendChat(fromName: string, message: string, fromUserId: number?, isSystem: boolean?)
	local gui = getGui()
	if not gui then
		return
	end
	local chatBox = gui:FindFirstChild("ChatBox")
	if not chatBox then
		return
	end
	local list = chatBox:FindFirstChild("MessageList")
	local template = list and list:FindFirstChild("MessageTemplate")
	if not (list and template and template:IsA("Frame")) then
		return
	end

	local entry = template:Clone()
	entry.Visible = true
	entry.LayoutOrder = state.ChatOrder
	state.ChatOrder += 1
	local userLabel = entry:FindFirstChild("Username")
	if userLabel and userLabel:IsA("TextLabel") then
		userLabel.Text = tostring(fromName) .. ":"
		if isSystem then
			userLabel.TextColor3 = Color3.fromRGB(255, 170, 0)
		elseif fromUserId == LocalPlayer.UserId then
			userLabel.TextColor3 = Color3.fromRGB(64, 224, 255)
		else
			userLabel.TextColor3 = Color3.fromRGB(255, 89, 89)
		end
	end
	local content = entry:FindFirstChild("Content")
	if content and content:IsA("TextLabel") then
		content.Text = message
	end
	entry.Parent = list
	scrollChatToBottom()
end

local function setTradeWithText()
	local gui = getGui()
	if not gui then
		return
	end
	local label = gui:FindFirstChild("TradeWith")
	if label and label:IsA("TextLabel") then
		label.Text = "Trade with @" .. tostring(state.PartnerDisplayName or "Player")
	end
end

local function setBackgroundForBox(boxFrame: Instance?, bgId: any)
	if not boxFrame then
		return
	end
	if not bgId or bgId == "" then
		return
	end
	local url = "rbxassetid://" .. tostring(bgId)
	if boxFrame:IsA("ImageLabel") or boxFrame:IsA("ImageButton") then
		(boxFrame :: any).Image = url
	end
end

setIconState = function(button: Instance, creature: any)
	local icon = button:FindFirstChild("CreatureIcon")
	if icon and icon:IsA("ImageLabel") then
		local base = creature.Name and Creatures[creature.Name]
		if base then
			local useShiny = creature.Shiny == true
			icon.Image = (useShiny and base.ShinySprite) or base.Sprite
		end
	end
	local shiny = button:FindFirstChild("Shiny")
	local shinyShadow = button:FindFirstChild("ShinyShadow")
	if shiny and shiny:IsA("ImageLabel") then
		shiny.Visible = creature.Shiny == true
	end
	if shinyShadow and shinyShadow:IsA("ImageLabel") then
		shinyShadow.Visible = creature.Shiny == true
	end
	local held = button:FindFirstChild("HeldItem")
	local heldShadow = button:FindFirstChild("HeldItemShadow")
	local hasHeld = creature.HeldItem ~= nil and creature.HeldItem ~= ""
	if held and held:IsA("ImageLabel") then
		held.Visible = hasHeld
		if hasHeld and Items and Items[creature.HeldItem] then
			local def = Items[creature.HeldItem]
			local img = (def and def.Image) or "rbxassetid://0"
			held.Image = img
		end
	end
	if heldShadow and heldShadow:IsA("ImageLabel") then
		heldShadow.Visible = hasHeld
	end
end

local function renderBox(boxData)
	local gui = getGui()
	if not gui then
		warn("[TradeUI] renderBox: no gui")
		return
	end
	local boxView = gui:FindFirstChild("BoxView")
	local current = boxView and boxView:FindFirstChild("CurrentBox")
	local boxTemplate = boxView and boxView:FindFirstChild("BoxTemplate")
	if boxView and not _optionsTemplate then
		_optionsTemplate = boxView:FindFirstChild("CreatureOptions")
	end

	if not boxView then
		warn("[TradeUI] renderBox: missing BoxView")
		return
	end
	if not current then
		warn("[TradeUI] renderBox: missing CurrentBox")
		return
	end
	if not boxTemplate then
		warn("[TradeUI] renderBox: missing BoxTemplate")
		return
	end

	local creatureOptions = boxView:FindFirstChild("CreatureOptions")

	local isParty = (boxData and boxData.BoxIndex == 1) or (boxData and boxData.BoxName == "Party")
	if isParty then
		_partySnapshot = boxData
	end
	state.CurrentBox = (boxData and boxData.BoxIndex) or 1
	state.TotalBoxes = (boxData and boxData.TotalBoxes) or state.TotalBoxes or 1

	local nameLabel = gui:FindFirstChild("ViewingBoxName")
	if nameLabel then
		local displayName = nil
		if isParty then
			displayName = "Party"
		else
			-- BoxIndex includes the party; subtract to show the actual box number.
			local boxNumber = ((boxData and boxData.BoxIndex) or state.CurrentBox) - 1
			if boxData and boxData.BoxName then
				displayName = boxData.BoxName
			else
				displayName = "Box " .. tostring(math.max(boxNumber, 1))
			end
		end
		nameLabel.Text = tostring(displayName)
	end

	local bgId = nil
	if isParty then
		-- Party always uses the default CatchInc image
		bgId = BoxBackgrounds.GetPartyBackground()
	elseif boxData and boxData.Background then
		bgId = boxData.Background
	else
		-- Use default background based on box index (BoxIndex - 1 because Party is index 1)
		local actualBoxIndex = ((boxData and boxData.BoxIndex) or state.CurrentBox) - 1
		bgId = BoxBackgrounds.GetDefaultBackgroundForBox(actualBoxIndex)
	end
	if bgId then
		setBackgroundForBox(current, bgId)
	end

	for _, child in ipairs(current:GetChildren()) do
		if child.Name ~= "UIGridLayout" and child.Name ~= "UIPadding" and child.Name ~= "CreatureOptions" then
			_buttonContext[child] = nil
			child:Destroy()
		end
	end

	local maxSlots = isParty and 6 or 30
	for i = 1, maxSlots do
		local creature = boxData and boxData.Creatures and boxData.Creatures[i] or nil
		if creature then
			local trueBoxIndex = isParty and 0 or (((boxData and boxData.BoxIndex) or state.CurrentBox) - 1)
			local key = isParty and ("P:" .. tostring(i)) or (tostring(trueBoxIndex) .. ":" .. tostring(i))
			local b = boxTemplate:Clone()
			b.Visible = true
			b.Name = "BoxBtn_" .. tostring(i)
			b.Parent = current
			setIconState(b, creature)
			_buttonContext[b] = {
				Source = "Box",
				Owner = "Self",
				BoxIndex = (boxData and boxData.BoxIndex) or state.CurrentBox,
				SlotIndex = i,
				Creature = creature,
				BoxKey = key,
			}
			if _offeredSlots[key] then
				hideButtonVisuals(b)
			else
				b.MouseButton1Click:Connect(function()
					-- Guard: if this slot was offered after the button was created, ignore further clicks.
					if _offeredSlots[key] then
						return
					end
					if creatureOptions then
						local ctx = _buttonContext[b]
						if ctx and showOptionsOnButton then
							showOptionsOnButton(b, ctx)
						end
					else
						warn("[TradeUI] CreatureOptions missing when clicking box button")
					end
				end)
			end
		end
	end
	print(string.format("[TradeUI] Rendered box %d/%d name=%s creatures=%d", state.CurrentBox, state.TotalBoxes or 1, tostring((boxData and boxData.BoxName) or "nil"), boxData and boxData.Creatures and #boxData.Creatures or 0))
end

requestBox = function(index: number)
	if _tradeLocked then
		return
	end
	if not state.SessionId then
		return
	end
	local total = state.TotalBoxes or 1
	if total < 1 then
		total = 1
	end
	local target = index
	if target < 1 then
		target = total
	elseif target > total then
		target = 1
	end
	local result = Request:InvokeServer({"TradeFetchBox", {
		SessionId = state.SessionId,
		BoxIndex = target,
	}})
	if type(result) == "table" and result.Creatures then
		print(string.format("[TradeUI] TradeFetchBox ok idx=%s total=%s name=%s creatures=%s", tostring(result.BoxIndex), tostring(result.TotalBoxes), tostring(result.BoxName), #result.Creatures))
		renderBox(result)
	elseif not _tradeLocked then
		warn("[TradeUI] TradeFetchBox returned invalid payload", result)
	end
end

local function resetUI()
	local gui = getGui()
	if not gui then
		return
	end
	clearChat()
	state.Ready = {}
	state.Confirmed = {}
	state.TotalBoxes = 1
	state.CurrentBox = 1
	_cooldownEnd = nil
	_tradeLocked = false
	_offeredSlots = {}
	_partnerOffers = {}
	setReadyStates()
	local confirmNote = gui:FindFirstChild("ConfirmNotification")
	if confirmNote and confirmNote:IsA("GuiObject") then
		confirmNote.Visible = false
	end
	setStatus("TRADE STATUS: AWAITING INPUT")
	updateActionButtons()
end

function TradeUI:Open(session)
	local gui = getGui()
	if not gui then
		return
	end
	setTradeSuppressed(true)
	state.SessionId = session.SessionId
	state.PartnerDisplayName = session.PartnerDisplayName
	state.PartnerUserId = session.PartnerUserId
	state.Ready = {}
	state.Confirmed = {}
	state.ChatOrder = 0
	_cooldownEnd = nil
	gui.Visible = true
	setTradeWithText()
	resetUI()
	updateActionButtons()
	requestBox(1)
end

function TradeUI:Close()
	local gui = getGui()
	if gui then
		gui.Visible = false
	end
	setTradeSuppressed(false)
	_cooldownEnd = nil
	_tradeLocked = false
	state.SessionId = nil
	state.PartnerDisplayName = nil
	state.PartnerUserId = nil
	state.Ready = {}
	state.Confirmed = {}
	_offeredSlots = {}
	_partnerOffers = {}
end

local function onSendChat()
	local gui = getGui()
	if not gui then
		return
	end
	local chatBox = gui:FindFirstChild("ChatBox")
	if not chatBox then
		return
	end
	local inputFrame = chatBox:FindFirstChild("TextInput")
	local input = inputFrame and inputFrame:FindFirstChild("Input")
	if not (input and input:IsA("TextBox")) then
		return
	end
	local text = input.Text or ""
	if text == "" or not state.SessionId then
		return
	end
	input.Text = ""
	Request:InvokeServer({"TradeSendMessage", {
		SessionId = state.SessionId,
		Message = text,
	}})
end

local function toggleReady()
	if not state.SessionId then
		return
	end
	if _tradeLocked then
		return
	end
	if isCooldownActive() then
		return
	end
	local newReady = state.Ready[LocalPlayer.UserId] ~= true
	if newReady then
		local gui = getGui()
		if gui then
			local yourList = gui:FindFirstChild("YourOffer") and gui.YourOffer:FindFirstChild("Listings")
			local theirList = gui:FindFirstChild("TheirOffer") and gui.TheirOffer:FindFirstChild("Listings")
			local function hasOffer(list: Instance?): boolean
				if not list then
					return false
				end
				for _, child in ipairs(list:GetChildren()) do
					local isLayout = child.Name == "ListingTemplate" or child.Name == "UIGridLayout" or child.Name == "UIPadding"
					local isAdd = child.Name == "Add"
					if child:IsA("GuiObject") and child.Visible and (not isLayout) and (not isAdd) then
						return true
					end
				end
				return false
			end
			local hasAny = hasOffer(yourList) or hasOffer(theirList)
			if not hasAny then
				appendChat("System", "You must add a creature before readying.", nil, true)
				return
			end
		end
	end
	local ok = Request:InvokeServer({"TradeSetReady", {
		SessionId = state.SessionId,
		Ready = newReady,
	}})
	if ok then
		state.Ready[LocalPlayer.UserId] = newReady
		if not newReady then
			state.Confirmed[LocalPlayer.UserId] = false
		end
		setReadyStates()
	end
end

local function tryConfirm()
	if not state.SessionId then
		return
	end
	if _tradeLocked then
		return
	end
	if isCooldownActive() then
		return
	end
	local meReady = state.Ready[LocalPlayer.UserId] == true
	local themReady = state.Ready[state.PartnerUserId or -1] == true
	local gui = getGui()
	if not meReady or not themReady then
		local note = gui and gui:FindFirstChild("ConfirmNotification")
		if note and note:IsA("GuiObject") then
			note.Visible = true
			task.delay(2, function()
				if note then
					note.Visible = false
				end
			end)
		end
		return
	end
	local result = Request:InvokeServer({"TradeConfirm", {
		SessionId = state.SessionId,
	}})
	if type(result) == "table" and result.Success == false and result.Message then
		Say:Say("System", true, {result.Message})
	end
end

local function confirmCancel()
	if not state.SessionId then
		return
	end
	if _tradeLocked then
		return
	end
	Say:Say("System", false, {"Are you sure you want to cancel the trade?"})
	local choice = Say:YieldChoice()
	if choice == true then
		Say:Exit()
		Request:InvokeServer({"TradeCancel", {
			SessionId = state.SessionId,
			Reason = "Cancelled",
			Message = LocalPlayer.DisplayName .. " cancelled the trade.",
		}})
	else
		Say:Exit()
	end
end

local function bindUI()
	local gui = getGui()
	if not gui then
		return
	end
	
	-- Use UIFunctions for consistent button behavior with animations
	local readyBtn = gui:FindFirstChild("ReadyUp")
	if readyBtn and readyBtn:IsA("GuiButton") and not readyBtn:GetAttribute("TradeUIBound") then
		readyBtn:SetAttribute("TradeUIBound", true)
		UIFunctions:NewButton(
			readyBtn,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.3,
			function()
				Audio.SFX.Click:Play()
				toggleReady()
			end
		)
	end
	
	local confirmBtn = gui:FindFirstChild("ConfirmTrade")
	if confirmBtn and confirmBtn:IsA("GuiButton") and not confirmBtn:GetAttribute("TradeUIBound") then
		confirmBtn:SetAttribute("TradeUIBound", true)
		UIFunctions:NewButton(
			confirmBtn,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.3,
			function()
				Audio.SFX.Click:Play()
				tryConfirm()
			end
		)
	end
	
	local cancelBtn = gui:FindFirstChild("CancelTrade")
	if cancelBtn and cancelBtn:IsA("GuiButton") and not cancelBtn:GetAttribute("TradeUIBound") then
		cancelBtn:SetAttribute("TradeUIBound", true)
		UIFunctions:NewButton(
			cancelBtn,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.3,
			function()
				Audio.SFX.Click:Play()
				confirmCancel()
			end
		)
	end
	
	local chatBox = gui:FindFirstChild("ChatBox")
	if chatBox then
		local sendBtn = chatBox:FindFirstChild("SendMessage")
		if sendBtn and sendBtn:IsA("GuiButton") and not sendBtn:GetAttribute("TradeUIBound") then
			sendBtn:SetAttribute("TradeUIBound", true)
			UIFunctions:NewButton(
				sendBtn,
				{"Action"},
				{ Click = "One", HoverOn = "One", HoverOff = "One" },
				0.2,
				function()
					Audio.SFX.Click:Play()
					onSendChat()
				end
			)
		end
		local inputFrame = chatBox:FindFirstChild("TextInput")
		local input = inputFrame and inputFrame:FindFirstChild("Input")
		if input and input:IsA("TextBox") then
			input.FocusLost:Connect(function(enterPressed)
				if enterPressed then
					onSendChat()
				end
			end)
		end
	end
	
	local nextBtn = gui:FindFirstChild("NextBox")
	if nextBtn and nextBtn:IsA("GuiButton") and not nextBtn:GetAttribute("TradeUIBound") then
		nextBtn:SetAttribute("TradeUIBound", true)
		UIFunctions:NewButton(
			nextBtn,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.2,
			function()
				Audio.SFX.Click:Play()
				local nextIndex = state.CurrentBox + 1
				requestBox(nextIndex)
			end
		)
	end
	
	local lastBtn = gui:FindFirstChild("LastBox")
	if lastBtn and lastBtn:IsA("GuiButton") and not lastBtn:GetAttribute("TradeUIBound") then
		lastBtn:SetAttribute("TradeUIBound", true)
		UIFunctions:NewButton(
			lastBtn,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.2,
			function()
				Audio.SFX.Click:Play()
				local prev = state.CurrentBox - 1
				requestBox(prev)
			end
		)
	end
end

local function tweenAndWait(inst: Instance?, props: any, duration: number)
	if not (inst and TweenService) then
		if duration and duration > 0 then
			task.wait(duration)
		end
		return nil
	end
	local tween = TweenService:Create(inst, TweenInfo.new(duration or 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tween:Play()
	local ok, _ = pcall(function()
		tween.Completed:Wait()
	end)
	if not ok and duration and duration > 0 then
		task.wait(duration)
	end
	return tween
end

local function populateConfirmedListings(listings: Instance?, creatures: {any}?)
	if not (listings and listings:IsA("GuiObject")) then
		return
	end
	local template = listings:FindFirstChild("BoxTemplate")
	if not (template and template:IsA("GuiObject")) then
		return
	end
	for _, child in ipairs(listings:GetChildren()) do
		if child:IsA("GuiObject") and child.Name ~= "BoxTemplate" and child.Name ~= "UIGridLayout" then
			child:Destroy()
		end
	end
	for _, creature in ipairs(creatures or {}) do
		if type(creature) == "table" then
			local clone = template:Clone()
			setIconState(clone, creature)
			clone.Visible = true
			clone.Parent = listings
			clone.Name = "s"
		end
	end
end

local function playTradeFinalizedAnimation(payload: any)
	-- Lock all inputs while the animation plays.
	_tradeLocked = true
	updateActionButtons()

	print("[TradeUI] playTradeFinalizedAnimation start; payload has", payload and #((payload.YourOffer) or {}), "your,",
		payload and #((payload.PartnerOffer) or {}), "partner")

	local frame = GameUI:FindFirstChild("TradeConfirmed")
	if not (frame and frame:IsA("Frame")) then
		warn("[TradeUI] TradeConfirmed frame missing; abort animation")
		TradeUI:Close()
		return
	end

	local holder = frame:FindFirstChild("CreatureHolder")
	local listings = holder and holder:FindFirstChild("Listings")
	local studs = frame:FindFirstChild("Studs")
	local visual = holder and holder:FindFirstChild("Visual")
	if not holder or not listings then
		warn("[TradeUI] TradeConfirmed holder/listings missing; abort animation")
		TradeUI:Close()
		return
	end
	local defaultPos = UDim2.new(0.5, 0, 0.709, 0)
	local flyOutPos = UDim2.new(0.5, 0, -0.2, 0)
	local returnPos = UDim2.new(0.5, 0, 0.709, 0)

	frame.Visible = true
	frame.BackgroundTransparency = 1
	if studs and studs:IsA("ImageLabel") then
		studs.ImageTransparency = 1
	end
	if holder and holder:IsA("GuiObject") then
		holder.Visible = false
		holder.Position = defaultPos
	end
	if visual then
		pcall(function()
			(visual :: any).Rotation = 0
		end)
	end

	-- Fade in backdrop and studs
	local bgTweenIn = TweenService:Create(frame, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0})
	bgTweenIn:Play()
	local studsTweenIn = nil
	if studs and studs:IsA("ImageLabel") then
		studsTweenIn = TweenService:Create(studs, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {ImageTransparency = 0.95})
		studsTweenIn:Play()
	end
	print("[TradeUI] TradeConfirmed fade-in started")
	bgTweenIn.Completed:Wait()

	task.wait(0.5)

	-- Show our offer clones
	if holder and holder:IsA("GuiObject") then
		holder.Visible = true
	end
	populateConfirmedListings(listings, payload and payload.YourOffer or {})
	print("[TradeUI] Populated our offer into TradeConfirmed", #((payload and payload.YourOffer) or {}))

	task.wait(2.5)

	-- Slide out
	if holder and holder:IsA("GuiObject") then
		tweenAndWait(holder, {Position = flyOutPos}, 0.5)
	end
	print("[TradeUI] TradeConfirmed slid out")

	task.wait(1)

	-- Swap listings to partner's offer and rotate visual
	populateConfirmedListings(listings, payload and payload.PartnerOffer or {})
	print("[TradeUI] Populated partner offer into TradeConfirmed", #((payload and payload.PartnerOffer) or {}))
	if visual then
		pcall(function()
			(visual :: any).Rotation = 180
		end)
	end
	if holder and holder:IsA("GuiObject") then
		tweenAndWait(holder, {Position = returnPos}, 0.5)
	end

	task.wait(2)

	if holder and holder:IsA("GuiObject") then
		holder.Visible = false
	end

	-- Fade out and clean up
	local bgTweenOut = TweenService:Create(frame, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1})
	bgTweenOut:Play()
	local studsTweenOut = nil
	if studs and studs:IsA("ImageLabel") then
		studsTweenOut = TweenService:Create(studs, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {ImageTransparency = 1})
		studsTweenOut:Play()
	end
	print("[TradeUI] TradeConfirmed fade-out started")

	TradeUI:Close()

	bgTweenOut.Completed:Wait()
	frame.Visible = false

	state.SessionId = nil
	state.Ready = {}
	state.Confirmed = {}
	_offeredSlots = {}
	_partnerOffers = {}
	_tradeLocked = false
	updateActionButtons()
	Say:Say("System", true, {"Trade completed."})
end

function TradeUI:HandleEvent(eventType, data)
	if eventType == "TradeStarted" then
		self:Open(data)
	elseif eventType == "TradeChat" then
		if data and data.Message then
			appendChat(data.FromDisplayName or "Player", data.Message, data.FromUserId, false)
		end
	elseif eventType == "TradeReady" then
		if data and data.UserId then
			state.Ready[data.UserId] = data.Ready == true
			if data.UserId == LocalPlayer.UserId and data.Ready ~= true then
				state.Confirmed[data.UserId] = false
			end
			setReadyStates()
		end
	elseif eventType == "TradeConfirm" then
		if data and data.UserId then
			state.Confirmed[data.UserId] = data.Confirmed == true
			local bothConfirmed = state.Confirmed[LocalPlayer.UserId] == true and state.Confirmed[state.PartnerUserId or -1] == true
			_tradeLocked = bothConfirmed
			print("[TradeUI] TradeConfirm received from", data.UserId, "bothConfirmed=", bothConfirmed)
			setReadyStates()
		end
	elseif eventType == "TradeFinalized" then
		if data and data.SessionId == state.SessionId then
			_tradeLocked = true
			updateActionButtons()
			print("[TradeUI] TradeFinalized received; playing animation. Session:", data.SessionId)
			playTradeFinalizedAnimation(data)
		else
			print("[TradeUI] TradeFinalized ignored; session mismatch", data and data.SessionId, state.SessionId)
		end
	elseif eventType == "MysteryTradeFinalized" then
		-- Mystery Trade doesn't use TradeUI state, just play animation directly
		_tradeLocked = true
		print("[TradeUI] MysteryTradeFinalized received; playing animation. Session:", data and data.SessionId)
		playTradeFinalizedAnimation(data)
	elseif eventType == "TradeCancelled" then
		local msg = (data and data.Message) or "Trade cancelled."
		Say:Say("System", true, {msg})
		self:Close()
	elseif eventType == "TradeOfferUpdated" then
		if data and data.SessionId == state.SessionId and data.UserId and data.Offers then
			if data.UserId == state.PartnerUserId then
				local previousOffers = _partnerOffers or {}
				_partnerOffers = data.Offers
				-- Debug so we know when the partner adds something while we cannot see their UI.
				if type(previousOffers) == "table" and type(_partnerOffers) == "table" then
					for key, creature in pairs(_partnerOffers) do
						if previousOffers[key] == nil and type(creature) == "table" then
							local name = tostring(creature.Name or "Unknown creature")
							print("[TradeUI] Partner added creature", name, "at", key)
						end
					end
				end
				markOfferChanged()
				renderOfferList("TheirOffer", _partnerOffers, "Them")
			end
		end
	end
end

bindUI()

return TradeUI

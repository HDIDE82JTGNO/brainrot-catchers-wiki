local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events = ReplicatedStorage:WaitForChild("Events")

local UIFunctions = require(script.Parent:WaitForChild("UIFunctions"))
local ClientData = require(script.Parent.Parent:WaitForChild("Plugins"):WaitForChild("ClientData"))
local Say = require(script.Parent.Parent:WaitForChild("Utilities"):WaitForChild("Say"))

local CatchCareShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CatchCareShopConfig"))
local ItemsModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Items"))

type ShopItem = CatchCareShopConfig.ShopItem

local CatchCareShop = {}
CatchCareShop.__index = CatchCareShop

local function formatNumber(value: number): string
	local int = math.floor(value + 0.5)
	local str = tostring(int)
	local len = #str
	if len <= 3 then
		return str
	end
	local chunks = {}
	while len > 3 do
		table.insert(chunks, 1, string.sub(str, len - 2, len))
		len -= 3
	end
	table.insert(chunks, 1, string.sub(str, 1, len))
	return table.concat(chunks, ",")
end

local function formatPrice(value: number): string
	return string.format("%s Studs", formatNumber(value))
end

local function cloneItems(items: {ShopItem}?): {ShopItem}
	local output: {ShopItem} = {}
	if type(items) ~= "table" then
		return output
	end
	for _, entry in ipairs(items) do
		if type(entry) == "table" and type(entry.ItemName) == "string" and type(entry.Price) == "number" then
			table.insert(output, {
				ItemName = entry.ItemName,
				Price = entry.Price,
				IconOverride = entry.IconOverride,
			})
		end
	end
	return output
end

local function resolveItemIcon(itemName: string, override: string?): string
	if type(override) == "string" and override ~= "" then
		return override
	end
	local def = ItemsModule[itemName]
	if def and type(def.Image) == "string" and def.Image ~= "" then
		return def.Image
	end
	return "rbxassetid://0"
end

function CatchCareShop.new()
	local self = setmetatable({
		_ui = nil :: Frame?,
		_activeButtons = {} :: {GuiButton},
		_listButtons = {} :: {GuiButton},
		_currentItems = {} :: {ShopItem},
		_selectedIndex = nil :: number?,
		_currentPage = 1,
		_pageCount = 1,
		_locationName = CatchCareShopConfig.DefaultLocationName,
		_locationTier = CatchCareShopConfig.DefaultTier,
		_onClosed = nil :: (() -> ())?,
		_isOpen = false,
		_isPurchasing = false,
		_confirmQuantity = 1,
	}, CatchCareShop)
	return self
end

function CatchCareShop:_getGui(): Frame?
	if self._ui and self._ui.Parent then
		return self._ui
	end
	local player = Players.LocalPlayer
	if not player then
		return nil
	end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local gameUi = pg and pg:FindFirstChild("GameUI")
	local gui = gameUi and gameUi:FindFirstChild("CatchCareShop")
	if gui and gui:IsA("Frame") then
		self._ui = gui
		local listFrame = gui:FindFirstChild("List")
		if listFrame and listFrame:IsA("Frame") then
			self._listButtons = {}
			for index = 1, CatchCareShopConfig.ItemsPerPage do
				local slot = listFrame:FindFirstChild(tostring(index))
				if slot and slot:IsA("GuiButton") then
					self._listButtons[index] = slot
				end
			end
		end
	end
	return self._ui
end

function CatchCareShop:_clearButtonBindings()
	for _, button in ipairs(self._activeButtons) do
		UIFunctions:ClearConnection(button)
	end
	table.clear(self._activeButtons)
end

function CatchCareShop:_bindButton(button: GuiButton?, handler: (GuiButton) -> ()): ()
	if not button or not button:IsA("GuiButton") then
		return
	end
	UIFunctions:ClearConnection(button)
	UIFunctions:NewButton(button, {"Action"}, { Click = "One", HoverOn = "One", HoverOff = "One" }, 0.25, function(btn)
		handler(btn :: GuiButton)
	end)
	table.insert(self._activeButtons, button)
end

function CatchCareShop:_updatePlayerInfo()
	local gui = self._ui
	if not gui then
		return
	end
	local topBar = gui:FindFirstChild("TopBar") or gui:FindFirstChild("Topbar")
	if not (topBar and topBar:IsA("Frame")) then
		return
	end
	
	local data = ClientData:Get()
	
	-- Update PlayerName (trainer's nickname, not username or display name)
	local playerNameLabel = topBar:FindFirstChild("PlayerName")
	if playerNameLabel and playerNameLabel:IsA("TextLabel") then
		local nickname = (data and data.Nickname) or nil
		playerNameLabel.Text = (type(nickname) == "string" and nickname ~= "") and nickname or ""
	end
	
	-- Update StudCount
	local studCountLabel = topBar:FindFirstChild("StudCount")
	if studCountLabel and studCountLabel:IsA("TextLabel") then
		local studs = (data and type(data.Studs) == "number") and data.Studs or 0
		studCountLabel.Text = formatNumber(studs)
	end
end

function CatchCareShop:_applyLocationMetadata()
	local data = ClientData:Get()
	local lastChunk = (data and data.LastChunk) or ""
	if type(lastChunk) ~= "string" then
		lastChunk = ""
	end
	local locationConfig = lastChunk ~= "" and CatchCareShopConfig.Locations[lastChunk] or nil
	if locationConfig then
		self._locationName = locationConfig.DisplayName
		self._locationTier = locationConfig.Tier
	else
		self._locationName = (lastChunk ~= "" and lastChunk) or CatchCareShopConfig.DefaultLocationName
		self._locationTier = CatchCareShopConfig.DefaultTier
	end

	local tierDef = CatchCareShopConfig.Tiers[self._locationTier]
	if not tierDef then
		self._locationTier = CatchCareShopConfig.DefaultTier
		tierDef = CatchCareShopConfig.Tiers[self._locationTier]
	end

	self._currentItems = cloneItems(tierDef and tierDef.Items or {})
	self._pageCount = math.max(1, math.ceil(#self._currentItems / CatchCareShopConfig.ItemsPerPage))

	local gui = self._ui
	if not gui then
		return
	end
	local topBar = gui:FindFirstChild("TopBar") or gui:FindFirstChild("Topbar")
	if topBar and topBar:IsA("Frame") then
		local locLabel = topBar:FindFirstChild("LocationName")
		local tierLabel = topBar:FindFirstChild("LocationTier")
		if locLabel and locLabel:IsA("TextLabel") then
			locLabel.Text = self._locationName
		end
		if tierLabel and tierLabel:IsA("TextLabel") then
			tierLabel.Text = string.format("Tier %d", self._locationTier)
		end
	end
	
	-- Update player info (name and studs)
	self:_updatePlayerInfo()
end

function CatchCareShop:_resetItemInfoPanel()
	self._selectedIndex = nil
	local gui = self._ui
	if not gui then
		return
	end
	local infoFrame = gui:FindFirstChild("ItemInfo")
	if not (infoFrame and infoFrame:IsA("Frame")) then
		return
	end
	local priceFrame = infoFrame:FindFirstChild("PriceFrame")
	if priceFrame and priceFrame:IsA("Frame") then
		priceFrame.Visible = false
		local priceText = priceFrame:FindFirstChild("PriceText")
		if priceText and priceText:IsA("TextLabel") then
			priceText.Text = ""
		end
	end
	local buyButton = infoFrame:FindFirstChild("Buy")
	if buyButton and buyButton:IsA("GuiButton") then
		buyButton.Visible = false
		buyButton.AutoButtonColor = false
	end
	for _, childName in ipairs({"ItemIcon", "IconShadow", "Description", "ItemName"}) do
		local child = infoFrame:FindFirstChild(childName)
		if child and (child:IsA("ImageLabel") or child:IsA("TextLabel")) then
			child.Visible = false
			if child:IsA("TextLabel") then
				child.Text = ""
			end
		end
	end
end

function CatchCareShop:_resetConfirmPanel()
	local gui = self._ui
	if not gui then
		return
	end
	local confirm = gui:FindFirstChild("ConfirmBuy")
	if not (confirm and confirm:IsA("Frame")) then
		return
	end
	confirm.Visible = false
	self._confirmQuantity = 1
	local amountLabel = confirm:FindFirstChild("BuyAmount")
	if amountLabel and amountLabel:IsA("TextLabel") then
		amountLabel.Text = ""
	end
	local priceLabel = confirm:FindFirstChild("PriceText")
	if priceLabel and priceLabel:IsA("TextLabel") then
		priceLabel.Text = ""
	end
end

function CatchCareShop:_updateConfirmPanel()
	local gui = self._ui
	if not gui then
		return
	end
	local confirm = gui:FindFirstChild("ConfirmBuy")
	if not (confirm and confirm:IsA("Frame")) then
		return
	end
	local itemIndex = self._selectedIndex
	local itemData = itemIndex and self._currentItems[itemIndex] or nil
	if not itemData then
		return
	end

	local quantity = math.max(1, self._confirmQuantity or 1)
	self._confirmQuantity = quantity
	local totalPrice = quantity * itemData.Price

	local amountLabel = confirm:FindFirstChild("BuyAmount")
	if amountLabel and amountLabel:IsA("TextLabel") then
		amountLabel.Text = string.format("Buying %d", quantity)
	end
	local priceLabel = confirm:FindFirstChild("PriceText")
	if priceLabel and priceLabel:IsA("TextLabel") then
		priceLabel.Text = string.format("Cost: %s Studs", formatNumber(totalPrice))
	end
end

function CatchCareShop:_updatePaginationButtons()
	local gui = self._ui
	if not gui then
		return
	end
	local pageFrame = gui:FindFirstChild("Page")
	if not (pageFrame and pageFrame:IsA("Frame")) then
		return
	end
	local nextButton = pageFrame:FindFirstChild("Next")
	local backButton = pageFrame:FindFirstChild("Back")
	local hasNext = self._currentPage < self._pageCount
	local hasPrev = self._currentPage > 1
	if nextButton and nextButton:IsA("GuiButton") then
		nextButton.Active = hasNext
		nextButton.AutoButtonColor = hasNext
		nextButton.Visible = true
	end
	if backButton and backButton:IsA("GuiButton") then
		backButton.Active = hasPrev
		backButton.AutoButtonColor = hasPrev
		backButton.Visible = true
	end
end

function CatchCareShop:_updatePageLabel()
	local gui = self._ui
	if not gui then
		return
	end
	local pageFrame = gui:FindFirstChild("Page")
	if not (pageFrame and pageFrame:IsA("Frame")) then
		return
	end
	local label = pageFrame:FindFirstChild("CurrentPageText")
	if label and label:IsA("TextLabel") then
		label.Text = string.format("Page %d", self._currentPage)
	end
end

function CatchCareShop:_applyButtonVisual(button: GuiButton, itemData: ShopItem)
	local nameLabel = button:FindFirstChild("ItemName")
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = itemData.ItemName
	end
	local priceFrame = button:FindFirstChild("PriceFrame")
	local priceText = priceFrame and priceFrame:FindFirstChild("PriceText")
	if priceText and priceText:IsA("TextLabel") then
		priceText.Text = formatPrice(itemData.Price)
	end
	local icon = button:FindFirstChild("ItemIcon")
	if icon and icon:IsA("ImageLabel") then
		icon.Image = resolveItemIcon(itemData.ItemName, itemData.IconOverride)
	end
end

function CatchCareShop:_renderPage(page: number)
	self:_resetItemInfoPanel()
	self._currentPage = math.clamp(page, 1, self._pageCount)
	local startIndex = ((self._currentPage - 1) * CatchCareShopConfig.ItemsPerPage) + 1
	for slotIndex, button in ipairs(self._listButtons) do
		if button then
			local itemIndex = startIndex + slotIndex - 1
			local data = self._currentItems[itemIndex]
			if data then
				button.Visible = true
				button:SetAttribute("GlobalIndex", itemIndex)
				self:_applyButtonVisual(button, data)
			else
				button.Visible = false
				button:SetAttribute("GlobalIndex", nil)
			end
		end
	end
	self:_updatePaginationButtons()
	self:_updatePageLabel()
end

function CatchCareShop:_updateItemInfo(itemIndex: number)
	local itemData = self._currentItems[itemIndex]
	if not itemData then
		self:_resetItemInfoPanel()
		return
	end
	self._selectedIndex = itemIndex
	local gui = self._ui
	if not gui then
		return
	end
	local infoFrame = gui:FindFirstChild("ItemInfo")
	if not (infoFrame and infoFrame:IsA("Frame")) then
		return
	end

	local itemNameLabel = infoFrame:FindFirstChild("ItemName")
	if itemNameLabel and itemNameLabel:IsA("TextLabel") then
		itemNameLabel.Text = itemData.ItemName
		itemNameLabel.Visible = true
	end

	local descriptionLabel = infoFrame:FindFirstChild("Description")
	if descriptionLabel and descriptionLabel:IsA("TextLabel") then
		local def = ItemsModule[itemData.ItemName]
		local desc = (def and def.Description) or "No description available."
		descriptionLabel.Text = desc
		descriptionLabel.Visible = true
	end

	local icon = infoFrame:FindFirstChild("ItemIcon")
	if icon and icon:IsA("ImageLabel") then
		icon.Image = resolveItemIcon(itemData.ItemName, itemData.IconOverride)
		icon.Visible = true
	end

	local shadow = infoFrame:FindFirstChild("IconShadow")
	if shadow and shadow:IsA("ImageLabel") then
		shadow.Visible = true
	end

	local priceFrame = infoFrame:FindFirstChild("PriceFrame")
	if priceFrame and priceFrame:IsA("Frame") then
		local priceText = priceFrame:FindFirstChild("PriceText")
		if priceText and priceText:IsA("TextLabel") then
			priceText.Text = formatPrice(itemData.Price)
		end
		priceFrame.Visible = true
	end

	local buyButton = infoFrame:FindFirstChild("Buy")
	if buyButton and buyButton:IsA("GuiButton") then
		buyButton.Visible = true
		buyButton.AutoButtonColor = true
	end
end

function CatchCareShop:_handleListButtonActivated(button: GuiButton)
	local itemIndex = button:GetAttribute("GlobalIndex")
	if type(itemIndex) ~= "number" then
		return
	end
	self:_updateItemInfo(itemIndex)
end

function CatchCareShop:_openConfirmBuy()
	if not self._selectedIndex then
		return
	end
	local gui = self._ui
	if not gui then
		return
	end
	local confirm = gui:FindFirstChild("ConfirmBuy")
	if not (confirm and confirm:IsA("Frame")) then
		return
	end
	self._confirmQuantity = 1
	confirm.Visible = true
	self:_updateConfirmPanel()
end

function CatchCareShop:_commitPurchase()
	if self._isPurchasing then
		return
	end
	if not self._selectedIndex then
		return
	end
	local itemData = self._currentItems[self._selectedIndex]
	if not itemData then
		return
	end
	local quantity = math.max(1, self._confirmQuantity or 1)
	self._isPurchasing = true
	local success, response = pcall(function()
		return Events.Request:InvokeServer({"PurchaseCatchCareItem", {
			ItemName = itemData.ItemName,
			Tier = self._locationTier,
			Quantity = quantity,
		}})
	end)
	self._isPurchasing = false
	local resultMessage = "Unable to process purchase."
	local ok = false
	if success and typeof(response) == "table" then
		if response.Success == true then
			ok = true
			resultMessage = response.Message or ("Purchased " .. itemData.ItemName .. "!")
			-- Update player info after successful purchase (studs may have changed)
			self:_updatePlayerInfo()
		else
			resultMessage = response.Message or "Purchase failed."
		end
	else
		resultMessage = "The shop did not respond. Try again in a moment."
	end
	Say:Say("", true, {
		{ Text = resultMessage, Emotion = ok and "Happy" or "Confused" },
	})
end

function CatchCareShop:_connectButtons()
	self:_clearButtonBindings()
	local gui = self._ui
	if not gui then
		return
	end
	local exitButton = gui:FindFirstChild("Exit")
	if exitButton and exitButton:IsA("GuiButton") then
		self:_bindButton(exitButton, function()
			self:Close()
		end)
	end
	local pageFrame = gui:FindFirstChild("Page")
	if pageFrame and pageFrame:IsA("Frame") then
		local nextButton = pageFrame:FindFirstChild("Next")
		if nextButton and nextButton:IsA("GuiButton") then
			self:_bindButton(nextButton, function()
				if self._currentPage < self._pageCount then
					self:_renderPage(self._currentPage + 1)
				end
			end)
		end
		local backButton = pageFrame:FindFirstChild("Back")
		if backButton and backButton:IsA("GuiButton") then
			self:_bindButton(backButton, function()
				if self._currentPage > 1 then
					self:_renderPage(self._currentPage - 1)
				end
			end)
		end
	end
	for _, button in ipairs(self._listButtons) do
		if button then
			self:_bindButton(button, function(btn)
				self:_handleListButtonActivated(btn)
			end)
		end
	end
	local infoFrame = gui:FindFirstChild("ItemInfo")
	if infoFrame and infoFrame:IsA("Frame") then
		local buyButton = infoFrame:FindFirstChild("Buy")
		if buyButton and buyButton:IsA("GuiButton") then
			self:_bindButton(buyButton, function()
				self:_openConfirmBuy()
			end)
		end
	end
	local confirm = gui:FindFirstChild("ConfirmBuy")
	if confirm and confirm:IsA("Frame") then
		local nevermindBtn = confirm:FindFirstChild("Nevermind")
		if nevermindBtn and nevermindBtn:IsA("GuiButton") then
			self:_bindButton(nevermindBtn, function()
				self:_resetConfirmPanel()
			end)
		end
		local purchaseBtn = confirm:FindFirstChild("Purchase")
		if purchaseBtn and purchaseBtn:IsA("GuiButton") then
			self:_bindButton(purchaseBtn, function()
				self:_commitPurchase()
				self:_resetConfirmPanel()
			end)
		end
		local addOne = confirm:FindFirstChild("AddOne")
		if addOne and addOne:IsA("GuiButton") then
			self:_bindButton(addOne, function()
				self._confirmQuantity = math.max(1, (self._confirmQuantity or 1) + 1)
				self:_updateConfirmPanel()
			end)
		end
		local addTen = confirm:FindFirstChild("AddTen")
		if addTen and addTen:IsA("GuiButton") then
			self:_bindButton(addTen, function()
				self._confirmQuantity = math.max(1, (self._confirmQuantity or 1) + 10)
				self:_updateConfirmPanel()
			end)
		end
		local subOne = confirm:FindFirstChild("SubtractOne")
		if subOne and subOne:IsA("GuiButton") then
			self:_bindButton(subOne, function()
				self._confirmQuantity = math.max(1, (self._confirmQuantity or 1) - 1)
				self:_updateConfirmPanel()
			end)
		end
		local subTen = confirm:FindFirstChild("SubtractTen")
		if subTen and subTen:IsA("GuiButton") then
			self:_bindButton(subTen, function()
				self._confirmQuantity = math.max(1, (self._confirmQuantity or 1) - 10)
				self:_updateConfirmPanel()
			end)
		end
	end
end

function CatchCareShop:Open(onClosed: (() -> ())?): boolean
	local gui = self:_getGui()
	if not gui then
		warn("[CatchCareShop] GameUI.CatchCareShop frame was not found")
		return false
	end
	if self._isOpen then
		if onClosed then
			self._onClosed = onClosed
		end
		return true
	end
	self._isOpen = true
	self._onClosed = onClosed
	self._isPurchasing = false
	gui.Visible = true
	gui.Active = true
	self:_applyLocationMetadata()
	self:_connectButtons()
	self:_resetItemInfoPanel()
	self:_resetConfirmPanel()
	self:_renderPage(1)
	return true
end

function CatchCareShop:Close()
	if not self._isOpen then
		return
	end
	self._isOpen = false
	self:_clearButtonBindings()
	local gui = self._ui
	if gui then
		gui.Visible = false
		gui.Active = false
	end
	self:_resetItemInfoPanel()
	self:_resetConfirmPanel()
	self._currentItems = {}
	self._pageCount = 1
	self._currentPage = 1
	local callback = self._onClosed
	self._onClosed = nil
	if callback then
		task.spawn(callback)
	end
end

return CatchCareShop.new()


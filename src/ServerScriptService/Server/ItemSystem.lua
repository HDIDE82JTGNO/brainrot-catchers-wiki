--!strict
--[[
	ItemSystem.lua
	Handles item management: usage, giving items, purchasing items
	Separated from ServerFunctions for better organization
]]

local ItemSystem = {}

-- Dependencies (will be injected)
local ClientData: any = nil
local GameData: any = nil
local DBG: any = nil
local Events: any = nil
local ActiveBattles: {[Player]: any} = {}
local StatCalc: any = nil
local CreatureFactory: any = nil
local CreaturesModule: any = nil
local CatchCareShopConfig: any = nil

--[[
	Initialize ItemSystem with dependencies
]]
function ItemSystem.Initialize(dependencies: {[string]: any})
	ClientData = dependencies.ClientData
	GameData = dependencies.GameData
	DBG = dependencies.DBG
	Events = dependencies.Events
	ActiveBattles = dependencies.ActiveBattles
	StatCalc = dependencies.StatCalc
	CreatureFactory = dependencies.CreatureFactory
	CreaturesModule = dependencies.CreaturesModule
	CatchCareShopConfig = dependencies.CatchCareShopConfig
end

--[[
	Give an item to a creature in the overworld (sets HeldItem)
	@param Player The player
	@param payload Item data {Name: string, SlotIndex: number}
	@return boolean|string Success status or error message
]]
function ItemSystem.GiveItem(Player: Player, payload: any): boolean | string
	local itemName = payload.Name
	local slotIndex = tonumber(payload.SlotIndex or 0)
	DBG:print("[Server] GiveItem called by", Player and Player.Name, "item=", itemName, "slot=", slotIndex)
	if type(itemName) ~= "string" or slotIndex < 1 then return false end
	local PlayerData = ClientData:Get(Player)
	if not PlayerData then return false end
	local Items = GameData.Items
	local itemDef = Items[itemName]
	if not itemDef then return false end

	-- Disallow MoveLearners as held items
	if itemDef.Category == "MoveLearners" then
		DBG:print("[Server] GiveItem blocked - item is MoveLearners")
		return "Cannot give this item."
	end

	-- Disallow Shiny Core as held item
	if itemName == "Shiny Core" then
		DBG:print("[Server] GiveItem blocked - item is Shiny Core")
		return "Cannot give this item."
	end

	-- Validate inventory
	PlayerData.Items = PlayerData.Items or {}
	local count = PlayerData.Items[itemName] or 0
	if count <= 0 then
		DBG:print("[Server] GiveItem blocked - no inventory for", itemName)
		return false
	end

	-- Validate party and target
	local party = PlayerData.Party
	if not party or #party == 0 then
		DBG:print("[Server] GiveItem blocked - no party")
		return "No creatures in party."
	end
	local creature = party[slotIndex]
	if not creature then
		DBG:print("[Server] GiveItem blocked - invalid slot")
		return false
	end

	-- Prevent giving if already holding something
	if type(creature.HeldItem) == "string" and creature.HeldItem ~= "" then
		DBG:print("[Server] GiveItem blocked - creature already holds", creature.HeldItem)
		return "This creature is already holding an item."
	end

	-- Assign and deduct
	creature.HeldItem = itemName
	PlayerData.Items[itemName] = math.max(0, count - 1)

	-- Persist to client
	if ClientData.UpdateClientData then ClientData:UpdateClientData(Player, PlayerData) end
	DBG:print("[Server] GiveItem success -", itemName, "-> slot", slotIndex)
	return true
end

--[[
	Purchase item from CatchCare shop
	@param Player The player
	@param payload Purchase data {ItemName: string, Quantity: number}
	@return table Result {Success: boolean, Message: string, Studs: number?}
]]
function ItemSystem.PurchaseCatchCareItem(Player: Player, payload: any): {Success: boolean, Message: string, Studs: number?}
	if typeof(payload) ~= "table" then
		return { Success = false, Message = "Invalid request." }
	end

	local itemName = payload.ItemName
	if type(itemName) ~= "string" or itemName == "" then
		return { Success = false, Message = "Invalid item." }
	end

	local quantity = tonumber(payload.Quantity) or 1
	if quantity < 1 then
		quantity = 1
	end

	local PlayerData = ClientData:Get(Player)
	if not PlayerData then
		return { Success = false, Message = "No player data." }
	end

	if tostring(PlayerData.Chunk) ~= "CatchCare" then
		return { Success = false, Message = "You're not at a CatchCare counter." }
	end

	local lastChunk = tostring(PlayerData.LastChunk or "")
	if lastChunk == "CatchCare" then
		lastChunk = ""
	end
	local locationConfig = (lastChunk ~= "" and CatchCareShopConfig.Locations[lastChunk]) or nil
	local effectiveTier = (locationConfig and locationConfig.Tier) or CatchCareShopConfig.DefaultTier
	local tierDefinition = CatchCareShopConfig.Tiers[effectiveTier]
	if not tierDefinition then
		return { Success = false, Message = "Shop data unavailable." }
	end

	local targetEntry: any?
	for _, entry in ipairs(tierDefinition.Items or {}) do
		if entry.ItemName == itemName then
			targetEntry = entry
			break
		end
	end

	if not targetEntry then
		return { Success = false, Message = "That item isn't sold here." }
	end

	local unitPrice = tonumber(targetEntry.Price)
	if not unitPrice or unitPrice <= 0 then
		return { Success = false, Message = "Invalid price data." }
	end
	local totalPrice = unitPrice * quantity

	local itemsCatalog = GameData.Items
	if not itemsCatalog[itemName] then
		return { Success = false, Message = "Unknown item." }
	end

	if type(PlayerData.Studs) ~= "number" then
		PlayerData.Studs = 0
		ClientData:UpdateClientData(Player, PlayerData)
	end

	if PlayerData.Studs < totalPrice then
		return { Success = false, Message = "You don't have enough Studs." }
	end

	PlayerData.Studs -= totalPrice
	PlayerData.Items = PlayerData.Items or {}
	PlayerData.Items[itemName] = (PlayerData.Items[itemName] or 0) + quantity
	ClientData:UpdateClientData(Player, PlayerData)

	DBG:print(string.format("[CatchCareShop] %s purchased %dx %s for %d studs", Player.Name, quantity, itemName, totalPrice))

	local message: string
	if quantity == 1 then
		message = string.format("%s purchased!", itemName)
	else
		message = string.format("%dx %s purchased!", quantity, itemName)
	end

	return {
		Success = true,
		Message = message,
		Studs = PlayerData.Studs,
	}
end

-- Note: UseItem is complex and battle-dependent, so it will remain in ServerFunctions
-- but can be refactored later if needed

return ItemSystem


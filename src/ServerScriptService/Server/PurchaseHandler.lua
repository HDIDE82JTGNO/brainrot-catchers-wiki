--!strict
local PurchaseHandler = {}

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DBG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DBG"))
local ServerFunctions = require(script.Parent:WaitForChild("ServerFunctions"))

-- Product ID to stud amount mapping
local PRODUCT_STUDS_MAP: {[number]: number} = {
	[3502450743] = 3000,  -- StarterPack
	[3502518875] = 8000,  -- RegularPack
	[3502519215] = 18000, -- PowerPack
	[3502519477] = 26000, -- PlusPack
	[3502520258] = 40000, -- GiantPack
}

-- Process receipt handler
function PurchaseHandler.ProcessReceipt(receiptInfo: ReceiptInfo): Enum.ProductPurchaseDecision
	local productId = receiptInfo.ProductId
	local playerId = receiptInfo.PlayerId
	
	-- Check if product ID is in our mapping
	local studAmount = PRODUCT_STUDS_MAP[productId]
	if not studAmount then
		DBG:warn("[PurchaseHandler] Unknown product ID:", productId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	-- Get player by UserId
	local player = Players:GetPlayerByUserId(playerId)
	if not player then
		-- Player left before purchase completed, but we should still grant it
		-- Store for later processing or handle offline
		DBG:warn("[PurchaseHandler] Player", playerId, "not found for product", productId)
		-- Return NotProcessedYet so Roblox will retry when player rejoins
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	-- Grant studs to player
	local success, err = pcall(function()
		ServerFunctions:GrantStuds(player, studAmount)
		DBG:print(string.format(
			"[PurchaseHandler] Granted %d studs to %s (Product ID: %d)",
			studAmount,
			player.Name,
			productId
		))
	end)
	
	if not success then
		DBG:warn("[PurchaseHandler] Error granting studs:", err)
		-- Return NotProcessedYet so Roblox will retry
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	-- Purchase successfully processed
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Initialize the purchase handler
function PurchaseHandler:Init()
	MarketplaceService.ProcessReceipt = PurchaseHandler.ProcessReceipt
	DBG:print("[PurchaseHandler] Initialized - ProcessReceipt handler connected")
end

return PurchaseHandler


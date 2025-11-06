local Interactables = {}
-- Active transient animation tracks managed by this module
Interactables._activePickupTrack = nil

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RSAssets = ReplicatedStorage:WaitForChild("Assets")

local Say = require(script.Parent.Say)
local UI = require(script.Parent.Parent.UI)
local ClientData = require(script.Parent.Parent.Plugins.ClientData)
local DBG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DBG"))

-- Get the pickup sound
local PickupSound = ReplicatedStorage:WaitForChild("Audio"):WaitForChild("SFX"):WaitForChild("PickupItem")
local PICKUP_ANIMATION_ID = "rbxassetid://118323350560193"

-- Track picked up items to prevent duplicate pickups
local PickedUpItems = {}

-- Setup all interactables in a chunk
function Interactables:Setup(InteractablesFolder, ChunkName)
	DBG:print("Setting up interactables for chunk:", ChunkName)
	
	-- Load picked up items from server
	Interactables:LoadPickedUpItemsFromServer()
	
	-- Setup Items folder
	local ItemsFolder = InteractablesFolder:FindFirstChild("Items")
	if ItemsFolder then
		DBG:print("Found Items folder with", #ItemsFolder:GetChildren(), "items")
		Interactables:SetupItems(ItemsFolder, ChunkName)
	else
		DBG:print("No Items folder found in interactables")
	end
	
	-- Setup CareBox folder
	local CareBoxFolder = InteractablesFolder:FindFirstChild("CareBox")
	if CareBoxFolder then
		DBG:print("Found CareBox folder with", #CareBoxFolder:GetChildren(), "care boxes")
		Interactables:SetupCareBoxes(CareBoxFolder, ChunkName)
	else
		DBG:print("No CareBox folder found in interactables")
	end
end
-- Play a one-shot animation on the local player's humanoid
function Interactables:_playPickupAnimation()
    local Players = game:GetService("Players")
    local localPlayer = Players.LocalPlayer
    if not localPlayer then return end
    local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
    local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    local animator: Animator? = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    -- Stop any previous pickup track managed by us
    local prev = self._activePickupTrack
    if prev and prev.IsPlaying then
        pcall(function() prev:Stop() end)
    end

    local anim = Instance.new("Animation")
    anim.AnimationId = PICKUP_ANIMATION_ID
    local ok, track = pcall(function()
        return animator:LoadAnimation(anim)
    end)
    if ok and track then
        track.Priority = Enum.AnimationPriority.Action
        track.Looped = false
        self._activePickupTrack = track
        pcall(function() track:Play() end)
        -- Clear reference when done
        track.Stopped:Connect(function()
            if self._activePickupTrack == track then
                self._activePickupTrack = nil
            end
        end)
    end
end


-- Setup items in the Items folder
function Interactables:SetupItems(ItemsFolder, ChunkName)
	for _, ItemPart in ipairs(ItemsFolder:GetChildren()) do
		if ItemPart:IsA("BasePart") then
			-- Check if this item has already been picked up
			local ItemKey = ChunkName .. "_" .. ItemPart.Name
			if PickedUpItems[ItemKey] then
				DBG:print("Item already picked up, hiding:", ItemPart.Name)
				ItemPart.Transparency = 1
				ItemPart.CanCollide = false
				
				-- Destroy any attachments in the item part
				for _, attachment in ipairs(ItemPart:GetChildren()) do
					if attachment:IsA("Attachment") then
						attachment:Destroy()
						DBG:print("Destroyed attachment:", attachment.Name, "from picked up item:", ItemPart.Name)
					end
				end
				continue
			end
			
			-- Get item attributes
			local GivesItem = ItemPart:GetAttribute("Gives")
			local Amount = ItemPart:GetAttribute("Amount")
			
			if not GivesItem or not Amount then
				DBG:warn("Item", ItemPart.Name, "missing Gives or Amount attribute")
				continue
			end
			
			-- Make sure the part can be touched
			ItemPart.CanTouch = true
			
			-- Connect touched event
			ItemPart.Touched:Connect(function(Hit)
				Interactables:OnItemTouched(ItemPart, Hit, GivesItem, Amount, ChunkName)
			end)
			
			DBG:print("Setup item:", ItemPart.Name, "Gives:", GivesItem, "Amount:", Amount)
		end
	end
end

-- Handle item touched event
function Interactables:OnItemTouched(ItemPart, Hit, GivesItem, Amount, ChunkName)
	local Character = Hit.Parent
	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	local Player = game.Players:GetPlayerFromCharacter(Character)
	
	-- Check if it's a player character
	if not Humanoid or not Player then
		return
	end
	
	-- Check if this is the local player
	if Player ~= game.Players.LocalPlayer then
		return
	end
	
	-- Check if any TopBar menu is open - prevent item pickup
	if UI.TopBar:IsMenuOpen() then
		return
	end
	
	-- Check if item has already been picked up
	local ItemKey = ChunkName .. "_" .. ItemPart.Name
	if PickedUpItems[ItemKey] then
		return
	end
	
	-- Proceed with pickup
	Interactables:PickupItem(ItemPart, GivesItem, Amount, ChunkName)
end

-- Handle item pickup
function Interactables:PickupItem(ItemPart, GivesItem, Amount, ChunkName)
	-- Check if it's studs or a valid item
	local Items = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Items"))
	
	if GivesItem ~= "Studs" and not Items[GivesItem] then
		DBG:warn("Invalid item:", GivesItem)
		Say:Say("System", true, {"This item doesn't exist!"})
		UI.TopBar:Show()
		return
	end
	
	-- Mark item as picked up
	local ItemKey = ChunkName .. "_" .. ItemPart.Name
	PickedUpItems[ItemKey] = true
	
	-- Hide the item
	ItemPart.Transparency = 1
	ItemPart.CanCollide = false
	
	-- Destroy any attachments in the item part
	for _, attachment in ipairs(ItemPart:GetChildren()) do
		if attachment:IsA("Attachment") then
			attachment:Destroy()
			DBG:print("Destroyed attachment:", attachment.Name, "from collected item:", ItemPart.Name)
		end
	end
	
	-- Grant item/studs to player
	local success
	if GivesItem == "Studs" then
		success = Interactables:GrantStudsToPlayer(Amount)
	else
		success = Interactables:GrantItemToPlayer(GivesItem, Amount)
	end
	
	if success then
		-- Show pickup message
		local message
		if GivesItem == "Studs" then
			message = "Found " .. Amount .. " studs!"
		elseif Amount == 1 then
			message = "Picked up " .. GivesItem .. "!"
		else
			message = "Picked up " .. Amount .. " of " .. GivesItem .. "!"
		end
		
		-- Play pickup sound
		PickupSound:Play()
		-- Play pickup animation on player
		self:_playPickupAnimation()
		
		Say:Say("System", true, {message})
		UI.TopBar:Show()
		DBG:print("Player picked up:", Amount, "x", GivesItem)
		
		-- Refresh Bag UI to show new items
		if UI.Bag and UI.Bag.RefreshBag then
			UI.Bag:RefreshBag()
			print("[Interactables] Refreshed Bag UI after item pickup")
		end
		
		-- Save the pickup to server
		Interactables:SaveItemPickup(ChunkName, ItemPart.Name)
	else
		DBG:warn("Failed to grant item/studs to player:", GivesItem)
		Say:Say("System", true, {"Failed to pick up item!"})
		UI.TopBar:Show()
	end
end

-- Grant studs to player
function Interactables:GrantStudsToPlayer(Amount)
	local PlayerData = ClientData:Get()
	if not PlayerData then
		DBG:warn("Could not get player data for studs granting")
		return false
	end
	
	-- Add studs to player's total
	PlayerData.Studs = (PlayerData.Studs or 0) + Amount
	
	-- Notify server to update studs
	local Events = game.ReplicatedStorage.Events
	if Events and Events.Request then
		Events.Request:InvokeServer({"GrantStuds", Amount})
	end
	
	DBG:print("Granted", Amount, "studs to player. Total:", PlayerData.Studs)
	return true
end

-- Grant item to player
function Interactables:GrantItemToPlayer(ItemName, Amount)
	local PlayerData = ClientData:Get()
	if not PlayerData then
		DBG:warn("Could not get player data for item granting")
		return false
	end
	
	-- Initialize Items table if it doesn't exist
	if not PlayerData.Items then
		PlayerData.Items = {}
	end
	
	-- Add item to player's inventory
	if PlayerData.Items[ItemName] then
		PlayerData.Items[ItemName] = PlayerData.Items[ItemName] + Amount
	else
		PlayerData.Items[ItemName] = Amount
	end
	
	DBG:print("Granted", Amount, "x", ItemName, "to player. Total:", PlayerData.Items[ItemName])
	
	-- Refresh Bag UI to show new items
	local UI = require(script.Parent.Parent.UI)
	if UI and UI.Bag and UI.Bag.RefreshBag then
		UI.Bag:RefreshBag()
		print("[Interactables] Refreshed Bag UI after granting item")
	end
	
	return true
end

-- Save item pickup to server
function Interactables:SaveItemPickup(ChunkName, ItemName)
	local Events = game.ReplicatedStorage.Events
	if Events and Events.Request then
		Events.Request:InvokeServer({"SaveItemPickup", ChunkName, ItemName})
	end
end

-- Setup care boxes
function Interactables:SetupCareBoxes(CareBoxFolder, ChunkName)
	for _, CareBoxModel in ipairs(CareBoxFolder:GetChildren()) do
		if CareBoxModel:IsA("Model") then
			-- Create click detector for the care box
			local ClickDetector = RSAssets.ClickDetector:Clone()
			ClickDetector.Parent = CareBoxModel
			
			-- Connect click event
			ClickDetector.MouseClick:Connect(function()
				Interactables:OnCareBoxClick(CareBoxModel, ChunkName)
			end)
			
			DBG:print("Setup care box:", CareBoxModel.Name)
		end
	end
end

-- Handle care box click
function Interactables:OnCareBoxClick(CareBoxModel, ChunkName)
	-- Check if any TopBar menu is open - prevent care box interaction
	if UI.TopBar:IsMenuOpen() then
		return
	end
	
	DBG:print("Care box clicked:", CareBoxModel.Name, "in chunk:", ChunkName)
	local UI = require(script.Parent.Parent.UI)
	if UI and UI.Vault and UI.Vault.Open then
		UI.Vault:Open()
	else
		print("[Interactables] Vault module not available; cannot open Vault UI")
	end
end

-- Load picked up items from server data
function Interactables:LoadPickedUpItems(PickedUpItemsData)
	if PickedUpItemsData then
		PickedUpItems = PickedUpItemsData
		local count = 0
		for _ in pairs(PickedUpItems) do count = count + 1 end
		DBG:print("Loaded", count, "picked up items")
	end
end

-- Load picked up items from server
function Interactables:LoadPickedUpItemsFromServer()
	local Events = game.ReplicatedStorage.Events
	if Events and Events.Request then
		local PickedUpItemsData = Events.Request:InvokeServer({"GetPickedUpItems"})
		if PickedUpItemsData then
			PickedUpItems = PickedUpItemsData
			local count = 0
			for _ in pairs(PickedUpItems) do count = count + 1 end
			DBG:print("Loaded", count, "picked up items from server")
		end
	end
end

return Interactables

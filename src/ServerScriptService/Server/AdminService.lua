--!strict
--[[
	AdminService.lua
	Handles admin permission checking and ban management
	Uses Roblox Group ranks for permission validation
]]

local AdminService = {}

-- Dependencies (will be injected)
local Config: any = nil
local DBG: any = nil
local Players: any = nil
local DataStoreService: any = nil

-- Permission levels
export type PermissionLevel = "Admin" | "Mod" | "None"

-- Ban data structure
export type BanData = {
	UserId: number,
	BannedBy: number, -- Admin UserId
	Reason: string,
	BannedAt: number, -- os.time()
	ExpiresAt: number?, -- nil for permanent bans
	IsActive: boolean
}

-- Initialize AdminService with dependencies
function AdminService.Initialize(dependencies: {[string]: any})
	Config = dependencies.Config
	DBG = dependencies.DBG
	Players = dependencies.Players
	DataStoreService = dependencies.DataStoreService
end

-- Get player's group rank
local function getPlayerRank(player: Player): number
	local success, rank = pcall(function()
		if not Config.ADMIN_GROUP_ID then return 0 end
		return player:GetRankInGroup(Config.ADMIN_GROUP_ID)
	end)
	return success and rank or 0
end

-- Check if player has admin permissions
function AdminService.IsAdmin(player: Player): boolean
	if not Config.ADMIN_GROUP_ID or not Config.ADMIN_RANK then
		return false
	end
	local rank = getPlayerRank(player)
	return rank >= Config.ADMIN_RANK
end

-- Check if player has mod permissions
function AdminService.IsMod(player: Player): boolean
	if not Config.ADMIN_GROUP_ID or not Config.MOD_RANK then
		return false
	end
	local rank = getPlayerRank(player)
	return rank >= Config.MOD_RANK
end

-- Get player's permission level
function AdminService.GetPermissionLevel(player: Player): PermissionLevel
	if AdminService.IsAdmin(player) then
		return "Admin"
	elseif AdminService.IsMod(player) then
		return "Mod"
	else
		return "None"
	end
end

-- Check if player can perform an action
function AdminService.CanPerformAction(player: Player, action: string): boolean
	local level = AdminService.GetPermissionLevel(player)
	
	if level == "Admin" then
		return true -- Admins can do everything
	elseif level == "Mod" then
		-- Mods can only kick
		return action == "KickPlayer"
	end
	
	return false
end

-- Get ban DataStore
local function getBanStore()
	if not DataStoreService then
		DataStoreService = game:GetService("DataStoreService")
	end
	return DataStoreService:GetDataStore("AdminBans")
end

-- Check if a user is banned
function AdminService.IsBanned(userId: number): (boolean, BanData?)
	local banStore = getBanStore()
	local success, banData = pcall(function()
		return banStore:GetAsync(tostring(userId))
	end)
	
	if not success or not banData then
		return false, nil
	end
	
	-- Check if ban is still active
	if not banData.IsActive then
		return false, nil
	end
	
	-- Check if ban has expired
	if banData.ExpiresAt and os.time() >= banData.ExpiresAt then
		-- Ban expired, mark as inactive
		banData.IsActive = false
		pcall(function()
			banStore:SetAsync(tostring(userId), banData)
		end)
		return false, nil
	end
	
	return true, banData
end

-- Ban a player
function AdminService.BanPlayer(admin: Player, userId: number, duration: number?, reason: string?): (boolean, string)
	if not AdminService.IsAdmin(admin) then
		return false, "You do not have permission to ban players."
	end
	
	local banStore = getBanStore()
	local banData: BanData = {
		UserId = userId,
		BannedBy = admin.UserId,
		Reason = reason or "No reason provided",
		BannedAt = os.time(),
		ExpiresAt = duration and (os.time() + duration) or nil,
		IsActive = true
	}
	
	local success, err = pcall(function()
		banStore:SetAsync(tostring(userId), banData)
	end)
	
	if not success then
		DBG:warn("[AdminService] Failed to ban user:", userId, err)
		return false, "Failed to ban player: " .. tostring(err)
	end
	
	-- Kick player if they're in game
	local targetPlayer = Players:GetPlayerByUserId(userId)
	if targetPlayer then
		local banMessage = "You have been banned"
		if duration then
			local hours = math.floor(duration / 3600)
			banMessage = banMessage .. " for " .. tostring(hours) .. " hours"
		else
			banMessage = banMessage .. " permanently"
		end
		if reason then
			banMessage = banMessage .. ". Reason: " .. reason
		end
		targetPlayer:Kick(banMessage)
	end
	
	return true, "Player banned successfully."
end

-- Unban a player
function AdminService.UnbanPlayer(admin: Player, userId: number): (boolean, string)
	if not AdminService.IsAdmin(admin) then
		return false, "You do not have permission to unban players."
	end
	
	local banStore = getBanStore()
	local success, banData = pcall(function()
		return banStore:GetAsync(tostring(userId))
	end)
	
	if not success or not banData then
		return false, "Ban record not found."
	end
	
	banData.IsActive = false
	
	local success2, err = pcall(function()
		banStore:SetAsync(tostring(userId), banData)
	end)
	
	if not success2 then
		DBG:warn("[AdminService] Failed to unban user:", userId, err)
		return false, "Failed to unban player: " .. tostring(err)
	end
	
	return true, "Player unbanned successfully."
end

-- Get all active bans
function AdminService.GetAllBans(): {BanData}
	local banStore = getBanStore()
	local bans: {BanData} = {}
	
	-- Note: DataStore doesn't support listing all keys, so we'll need to track bans separately
	-- For now, return empty array - this can be enhanced with a separate tracking system
	-- if needed (e.g., using OrderedDataStore or a separate list DataStore)
	
	return bans
end

-- Get ban for a specific user
function AdminService.GetBan(userId: number): BanData?
	local isBanned, banData = AdminService.IsBanned(userId)
	if isBanned then
		return banData
	end
	return nil
end

return AdminService


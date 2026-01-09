local PlayersService = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game.ServerScriptService
local MarketplaceService = game:GetService("MarketplaceService")

local PlayerDataTemplate = require(ReplicatedStorage.Shared.PlayerData)

local ProfileStore = require(ServerScriptService.Packages.ProfileStore)
local DATA_STORE_KEY = RunService:IsStudio() and "435g6hyu7tefr" or "Test-2"


local PlayerStore = ProfileStore.New(DATA_STORE_KEY,PlayerDataTemplate.DEFAULT_PLAYER_DATA)
local Profiles: {[Player]: typeof(PlayerStore:StartSessionAsync())} = {}
local LoadingProfiles: {[number]: boolean} = {} -- Track UserId of profiles currently being loaded

local Local = {}
local Shared = {}

-- Vault+ gamepass ID
local VAULTPLUS_GAMEPASS_ID = 1656816296

-- Get maximum box count based on Vault+ ownership
local function getMaxBoxCount(player: Player): number
	local success, ownsGamepass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, VAULTPLUS_GAMEPASS_ID)
	end)
	
	if success and ownsGamepass then
		return 50
	else
		return 8
	end
end

-- Non-story chunks that should not have their location saved
-- CatchCare is a universal facility accessible from multiple chunks,
-- so LastChunk must be preserved to ensure correct exit destination
local NON_STORY_CHUNKS = {
	["Title"] = true,
	["Battle"] = true,
	["Trade"] = true,
	["CatchCare"] = true,
}

function Local.OnStart()
	for _,p in ipairs(PlayersService:GetChildren()) do
		task.spawn(Local.LoadProfile,p)
	end
	PlayersService.PlayerAdded:Connect(Local.LoadProfile)
	
	-- Ensure profiles are properly cleaned up when players leave
	PlayersService.PlayerRemoving:Connect(function(player)
		-- Clear loading state if player leaves during load
		LoadingProfiles[player.UserId] = nil
		
		-- Only call RemoveProfile if AutoSave is not handling it via AncestryChanged
		-- Check if profile exists and if AutoSave is disabled
		local profile = Profiles[player]
		if profile then
			local autoSaveEnabled = profile.Data and profile.Data.Settings and profile.Data.Settings.AutoSave == true
			if not autoSaveEnabled then
				-- AutoSave is disabled, so AncestryChanged won't trigger - we need to clean up
				Local.RemoveProfile(player)
			end
			-- If AutoSave is enabled, AncestryChanged will handle cleanup
		end
	end)
	
	-- Handle server shutdown / game:BindToClose
	game:BindToClose(function()
		-- End all active sessions on shutdown
		for player, profile in pairs(Profiles) do
			if profile then
				pcall(function()
					profile:EndSession()
				end)
			end
		end
	end)
end

function Shared.ResetData(player: Player)
	local profile = Profiles[player]
	if not profile then return end

	-- Deep copy defaults to avoid shared references across players
	local defaults = PlayerDataTemplate.DEFAULT_PLAYER_DATA
	local fresh = table.clone(defaults)
	fresh.Settings = table.clone(defaults.Settings)
	fresh.Events = table.clone(defaults.Events)
	-- Reset containers explicitly
	fresh.Party = {}
	fresh.Boxes = {}
	fresh.Items = {}
	fresh.Creatures = {}
	fresh.Gamepasses = {}
	fresh.PickedUpItems = {}
	fresh.DefeatedTrainers = {}
	fresh.RedeemedCodes = {}
	-- Remove optional runtime/session fields explicitly
	fresh.SelectedStarter = nil
	fresh.Starters = nil
	fresh.PendingCapture = nil
	-- Clear positional/session fields
    fresh.LastChunk = nil
    fresh.LastCF = nil
    fresh.LeaveData = nil
	fresh.Sequence = nil
	fresh.Chunk = nil
	fresh.DexNumber = 0

	-- Initialize Boxes based on Vault+ ownership
	local maxBoxes = getMaxBoxCount(player)
	for i = 1, maxBoxes do
		fresh.Boxes[i] = { Name = "Box " .. tostring(i), Creatures = {} }
	end

	profile.Data = fresh
	return profile.Data
end

function Local.LoadProfile(player:Player)
	local userId = player.UserId
	
	-- Prevent duplicate load attempts
	if LoadingProfiles[userId] then
		warn(`[DATA] Profile for {player.Name} ({userId}) is already being loaded. Kicking to prevent duplicate session.`)
		player:Kick("Your data is already loading. Please wait and rejoin.")
		return
	end
	
	-- Check if profile is already loaded for this player
	if Profiles[player] then
		warn(`[DATA] Profile for {player.Name} ({userId}) is already loaded. Ignoring duplicate load request.`)
		return
	end
	
	-- Check if player is banned
	do
		local success, AdminService = pcall(function()
			return require(ServerScriptService.Server.AdminService)
		end)
		if success and AdminService then
			local isBanned, banData = AdminService.IsBanned(userId)
			if isBanned and banData then
				local banMessage = "You have been banned"
				if banData.ExpiresAt then
					local hours = math.floor((banData.ExpiresAt - os.time()) / 3600)
					if hours > 0 then
						banMessage = banMessage .. " for " .. tostring(hours) .. " more hours"
					else
						banMessage = banMessage .. " (expires soon)"
					end
				else
					banMessage = banMessage .. " permanently"
				end
				if banData.Reason then
					banMessage = banMessage .. ". Reason: " .. banData.Reason
				end
				player:Kick(banMessage)
				return
			end
		end
	end
	
	-- Mark as loading
	LoadingProfiles[userId] = true
	
	local Profile
	local success, err = pcall(function()
		Profile = PlayerStore:StartSessionAsync(`{userId}`, {
			Cancel = function()
				return player.Parent ~= PlayersService
			end,	
		})
	end)
	
	-- Clear loading state regardless of outcome
	LoadingProfiles[userId] = nil
	
	-- Handle pcall failure (including "already loaded" error)
	if not success then
		warn(`[DATA] Failed to start session for {player.Name} ({userId}): {err}`)
		player:Kick("Failed to load your data. Please rejoin.")
		return
	end
	
	if Profile == nil then
		return player:Kick("Your data failed to load! Please rejoin.")
	end
	
	Profile:AddUserId(player.UserId)
	Profile:Reconcile()

	-- Initialize Boxes if missing and ensure correct count based on Vault+ ownership
	local maxBoxes = getMaxBoxCount(player)
	if not Profile.Data.Boxes or type(Profile.Data.Boxes) ~= "table" then
		Profile.Data.Boxes = {}
	end
	
	-- Ensure all existing boxes have proper structure (convert legacy format if needed)
	for i = 1, #Profile.Data.Boxes do
		if Profile.Data.Boxes[i] == nil then
			Profile.Data.Boxes[i] = { Name = "Box " .. tostring(i), Creatures = {} }
		elseif type(Profile.Data.Boxes[i]) == "table" and Profile.Data.Boxes[i].Creatures == nil then
			-- Legacy format: convert to new schema
			Profile.Data.Boxes[i] = { Name = Profile.Data.Boxes[i].Name or ("Box " .. tostring(i)), Creatures = Profile.Data.Boxes[i] }
		end
	end
	
	-- Ensure boxes array has correct count (add new boxes if needed)
	if #Profile.Data.Boxes < maxBoxes then
		for i = #Profile.Data.Boxes + 1, maxBoxes do
			Profile.Data.Boxes[i] = { Name = "Box " .. tostring(i), Creatures = {} }
		end
	end
	
	Profile.OnSessionEnd:Connect(function()
		Profiles[player] = nil
		player:Kick("Profile session has ended, please rejoin.")
	end)
	
	if player.Parent == PlayersService then
		Profiles[player] = Profile
		
		-- Proactively push initial data to client once the profile is ready
		do
			local ok, mod = pcall(function()
				return require(ServerScriptService.Server.ClientData)
			end)
			if ok and mod and mod.UpdateClientData then
				mod:UpdateClientData(player, Profile.Data)
			else
				-- Fallback to direct event to avoid tight coupling if module is unavailable
				pcall(function()
					local Events = game:GetService("ReplicatedStorage"):WaitForChild("Events")
					Events.Communicate:FireClient(player, "ClientData", Profile.Data)
				end)
			end
		end

		-- Roll back any mid-battle state from a previous session using PendingBattle snapshot
		local data = Profile.Data
		if data and data.PendingBattle and type(data.PendingBattle) == "table" then
			local snap = data.PendingBattle
			-- Restore party
			if type(snap.Party) == "table" then
				data.Party = {}
				for i, c in ipairs(snap.Party) do
					data.Party[i] = c and table.clone(c) or nil
				end
			end
			-- Restore basic fields
			if snap.Studs ~= nil then data.Studs = snap.Studs end
			if type(snap.DefeatedTrainers) == "table" then data.DefeatedTrainers = table.clone(snap.DefeatedTrainers) end
			if type(snap.Chunk) == "string" then data.Chunk = snap.Chunk end
			if type(snap.LastChunk) == "string" then data.LastChunk = snap.LastChunk end
			if type(snap.LeaveData) == "table" then
				-- Only overwrite when snapshot includes LeaveData; otherwise preserve existing saved LeaveData
				data.LeaveData = table.clone(snap.LeaveData)
			end
			-- Clear snapshot after restore
			data.PendingBattle = nil
		end

		-- Only connect RemoveProfile if AutoSave is enabled in their settings
		if Profile.Data.Settings.AutoSave == true then
			player.AncestryChanged:Connect(function(_, parent)
				if not parent then
					warn("AUTO SAVE IS ENABLED FOR THIS PLAYER")
					Local.RemoveProfile(player)
				end
			end)
		else
			warn("AUTO SAVE IS DISABLED")
		end
	else
		Profile:EndSession()
	end
end

function Local.RemoveProfile(player: Player)
	-- Clear loading state as a safety measure
	LoadingProfiles[player.UserId] = nil
	
	local profile = Profiles[player]
	if not profile then 
		print(`[DATA] Tried to remove profile for {player.Name}, but no profile was found.`)
		return 
	end

	-- Get the "active" data from ClientData (handles debug mode properly)
	local ClientData = require(script.Parent)
	local data = ClientData:Get(player)
	
	if not data then
		print(`[DATA] No active data for {player.Name}, ending session without save.`)
		profile:EndSession()
		Profiles[player] = nil
		return
	end

	-- Check blocking conditions
	local inBattle = data.InBattle == true
	local inCutscene = data.InCutscene == true
	local inSayMessage = data.InSayMessage == true
	local currentChunk = data.Chunk
	local autoSaveEnabled = data.Settings and data.Settings.AutoSave == true

	-- Invalid chunk states that block saving
	local chunkInvalid = (currentChunk == nil) or (currentChunk == "nil")
	local atTitle = (currentChunk == "Title")

	-- Log state for debugging
	print(`[DATA] RemoveProfile for {player.Name}: AutoSave={tostring(autoSaveEnabled)}, Chunk="{tostring(currentChunk)}", LastChunk="{tostring(data.LastChunk)}", InBattle={tostring(inBattle)}, InCutscene={tostring(inCutscene)}, InSayMessage={tostring(inSayMessage)}, __DebugData={tostring(data.__DebugData)}`)

	-- In debug mode, just end the session without saving
	if data.__DebugData == true then
		print(`[DATA] Debug mode - ending session without persisting`)
		profile:EndSession()
		Profiles[player] = nil
		return
	end

	-- Determine if we should save
	local shouldSave = autoSaveEnabled and not inBattle and not inCutscene and not inSayMessage and not atTitle and not chunkInvalid

	if shouldSave then
		-- Only save location for Story mode chunks
		local isStoryChunk = not NON_STORY_CHUNKS[currentChunk]
		local profileData = profile.Data
		
		if isStoryChunk then
			-- Update LeaveData before session ends
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") then
				local cf = hrp.CFrame
				local rx, ry, rz = cf:ToOrientation()
				profileData.LeaveData = {
					Position = { X = hrp.Position.X, Y = hrp.Position.Y, Z = hrp.Position.Z },
					Rotation = { X = rx, Y = ry, Z = rz },
					Chunk = currentChunk,
				}
				profileData.LastChunk = currentChunk
			end
		else
			print(`[DATA] In {currentChunk} hub - preserving existing Story location`)
		end
		print(`[DATA] AutoSave is ON for {player.Name}, saving + ending session...`)
	else
		local reason = not autoSaveEnabled and "AutoSave disabled" 
			or inBattle and "in battle" 
			or inCutscene and "in cutscene" 
			or inSayMessage and "in Say message"
			or atTitle and "on title screen"
			or chunkInvalid and "invalid chunk state"
			or "unknown"
		print(`[DATA] Ending session without saving for {player.Name} ({reason})`)
	end

	profile:EndSession()
	Profiles[player] = nil
	print(`[DATA] Profile removed for {player.Name}`)
end

function Shared.ManualSave(player: Player)
	local profile = Profiles[player]
	if not profile then 
		print(`[DATA] ManualSave failed: {player.Name} has no profile loaded.`)
		return false 
	end

	-- Get the "active" data from ClientData (handles debug mode properly)
	-- This deferred require avoids circular dependency issues
	local ClientData = require(script.Parent)
	local data = ClientData:Get(player)
	
	if not data then
		warn(`[DATA] ManualSave blocked: {player.Name} has no active data.`)
		return false
	end

	-- Check each blocking condition separately for clear debugging
	local inBattle = data.InBattle == true
	local inCutscene = data.InCutscene == true
	local inSayMessage = data.InSayMessage == true
	local currentChunk = data.Chunk

	-- Log current state for debugging
	print(`[DATA] ManualSave check for {player.Name}: Chunk="{tostring(currentChunk)}", LastChunk="{tostring(data.LastChunk)}", InBattle={tostring(inBattle)}, InCutscene={tostring(inCutscene)}, InSayMessage={tostring(inSayMessage)}, __DebugData={tostring(data.__DebugData)}`)

	-- Block if Chunk is nil or invalid (player hasn't loaded into the game yet)
	if currentChunk == nil or currentChunk == "nil" then
		warn(`[DATA] ManualSave blocked: {player.Name} has invalid Chunk state (nil).`)
		return false
	end

	-- Block for title screen
	if currentChunk == "Title" then
		warn(`[DATA] ManualSave blocked: {player.Name} is on the title screen.`)
		return false
	end

	-- Block for active battles
	if inBattle then
		warn(`[DATA] ManualSave blocked: {player.Name} is currently in battle.`)
		return false
	end

	-- Block for cutscenes
	if inCutscene then
		warn(`[DATA] ManualSave blocked: {player.Name} is currently in a cutscene.`)
		return false
	end

	-- Block for Say messages
	if inSayMessage then
		warn(`[DATA] ManualSave blocked: {player.Name} is currently in a Say message.`)
		return false
	end

	print(`[DATA] {player.Name} manually saved. Committing data...`)

	-- Only save location/LeaveData for Story mode chunks (not Battle, Trade, Title)
	local isStoryChunk = not NON_STORY_CHUNKS[currentChunk]
	
	if isStoryChunk then
		-- Save position and update LastChunk for Story mode
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			local cf = hrp.CFrame
			local rx, ry, rz = cf:ToOrientation()
			data.LeaveData = {
				Position = { X = hrp.Position.X, Y = hrp.Position.Y, Z = hrp.Position.Z },
				Rotation = { X = rx, Y = ry, Z = rz },
				Chunk = currentChunk,
			}
			data.LastChunk = currentChunk
			print(`[DATA] Saved location for Story chunk: {currentChunk}`)
		end
	else
		-- For Battle/Trade hubs, don't update LeaveData or LastChunk - preserve existing Story location
		print(`[DATA] In {currentChunk} hub - preserving existing Story location (LastChunk="{tostring(data.LastChunk)}")`)
	end

	-- In debug mode, just update the client data without persisting
	if data.__DebugData == true then
		print(`[DATA] Debug mode - updating client data without persisting to DataStore`)
		ClientData:UpdateClientData(player, data)
		return true
	end

	-- Copy relevant fields from active data to profile data for saving
	local profileData = profile.Data
	if isStoryChunk then
		profileData.LeaveData = data.LeaveData
		profileData.LastChunk = data.LastChunk
	end

	-- Force a save
	local success, err = pcall(function()
		-- Mark this save as explicitly user-initiated to bypass autosave gating
		profileData._AllowOneSave = true
		profile:Save()
	end)

	if success then
		print(`[DATA] Manual save successful for {player.Name}`)
		return true
	else
		warn(`[DATA] Manual save FAILED for {player.Name}: {err}`)
		return false
	end
end


function Shared.GetData(player: Player, timeoutSeconds: number?): PlayerDataTemplate.PlayerData?
	local profile = Profiles[player]
	if not profile then return end
	return profile.Data
end


function Shared.UpdateGems(player:Player,amount:number)
	local data = Shared.GetData(player)
	if not data then return end
	
	local gems = data.Gems
	print(`Player had {gems}`)
	data.Gems += amount
	print(`Player now has {data.Gems}`)
end

Local.OnStart()

return Shared
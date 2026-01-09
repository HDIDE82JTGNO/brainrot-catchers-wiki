local PlayerProfile = {}

function PlayerProfile.apply(ServerFunctions, deps)
	local ClientData = deps.ClientData
	local WorldSystem = deps.WorldSystem
	local StarterService = deps.StarterService
	local ChunkService = deps.ChunkService
	local ItemSystem = deps.ItemSystem
	local CreatureSpawnService = deps.CreatureSpawnService
	local DBG = deps.DBG
	local saveNow = deps.saveNow

	-- Give an item to a creature in the overworld (sets HeldItem)
	function ServerFunctions:GiveItem(Player, payload)
		return ItemSystem.GiveItem(Player, payload)
	end

	function ServerFunctions:PurchaseCatchCareItem(Player: Player, payload: any)
		return ItemSystem.PurchaseCatchCareItem(Player, payload)
	end

	--[[
		Despawns a player's creature model
		@param Player The player who owns the creature
	]]
	function ServerFunctions:DespawnPlayerCreature(Player: Player): ()
		CreatureSpawnService.DespawnPlayerCreature(Player)
	end

	function ServerFunctions:SpawnPlayerCreature(Player: Player, slotIndex: number, creatureData: any): Model?
		return CreatureSpawnService.SpawnPlayerCreature(Player, slotIndex, creatureData)
	end

	function ServerFunctions:LoadChunkPlayer(Player, ChunkName)
		return WorldSystem.LoadChunkPlayer(Player, ChunkName)
	end

	function ServerFunctions:FilterName(Player, Name)
		local TextService = game:GetService("TextService")

		-- Filter the name through Roblox's TextService
		local success, result = pcall(function()
			return TextService:FilterStringAsync(Name, Player.UserId)
		end)

		if success then
			return result:GetNonChatStringForBroadcastAsync()
		else
			DBG:warn("Failed to filter name for player:", Player.Name, "Name:", Name)
			return Name -- Return original name if filtering fails
		end
	end

	function ServerFunctions:UpdateNickname(Player, Nickname)
		local PlayerData = ClientData:Get(Player)
		PlayerData.Nickname = Nickname
		ClientData:UpdateClientData(Player, PlayerData)
		DBG:print("Updated nickname for player:", Player.Name, "to:", Nickname)
		return true
	end

	function ServerFunctions:SetEvent(Player, EventName, EventValue)
		local PlayerData = ClientData:Get(Player)

		if not PlayerData.Events then
			PlayerData.Events = {}
		end

		local previous = PlayerData.Events[EventName]
		PlayerData.Events[EventName] = EventValue

		if EventName == "FINISHED_TUTORIAL" and EventValue == true and previous ~= true then
			pcall(function()
				ServerFunctions:GrantItem(Player, "Capture Cube", 500)
			end)
		end
		ClientData:UpdateClientData(Player, PlayerData)

		DBG:print("Set event for player:", Player.Name, "Event:", EventName, "Value:", EventValue)
		return true
	end

	function ServerFunctions:RequestStarters(Player: Player)
		return StarterService.RequestStarters(Player)
	end

	function ServerFunctions:PickStarter(Player: Player, StarterName: string)
		return StarterService.PickStarter(Player, StarterName)
	end

	function ServerFunctions:GetEncounterData(Player, ChunkName)
		return WorldSystem.GetEncounterData(Player, ChunkName)
	end

	-- Server-authoritative encounter step: roll and start wild battle if triggered
	function ServerFunctions:TryEncounterStep(Player)
		local ok, encounterData = WorldSystem.TryEncounterStep(Player)
		if ok and encounterData then
			-- Start battle with encounter data
			local battleOk, _ = ServerFunctions:StartBattle(Player, "Wild", encounterData)
			DBG:print("StartBattle result:", battleOk)
			return battleOk == true
		end
		return ok
	end

	function ServerFunctions:UpdateSettings(Player, SettingName, SettingValue)
		local PlayerData = ClientData:Get(Player)

		if not PlayerData.Settings then
			PlayerData.Settings = {}
		end

		-- Validate setting name and value
		local validSettings = {"AutoSave", "MuteMusic", "FastText", "XPSpread"}
		if not table.find(validSettings, SettingName) then
			DBG:warn("Invalid setting name:", SettingName)
			return false
		end

		-- Validate setting value type
		-- All current settings are boolean toggles
		if type(SettingValue) ~= "boolean" then
			DBG:warn("Invalid setting value type for", SettingName, "expected boolean, got", type(SettingValue))
			return false
		end

		-- Back-compat specific checks (kept for clarity)
		if SettingName == "AutoSave" or SettingName == "MuteMusic" or SettingName == "FastText" or SettingName == "XPSpread" then
			if type(SettingValue) ~= "boolean" then
				DBG:warn("Invalid setting value type for", SettingName, "expected boolean, got", type(SettingValue))
				return false
			end
		end

		-- Update the setting
		PlayerData.Settings[SettingName] = SettingValue

		-- Immediately push to client to keep UI in sync
		ClientData:UpdateClientData(Player, PlayerData)

		-- Persist immediately only if AutoSave is enabled and not in a cutscene; otherwise require manual save
		local allowAuto = (PlayerData.Settings and PlayerData.Settings.AutoSave) == true and (PlayerData.InCutscene ~= true)
		if allowAuto then
			local saved = saveNow(Player)
			if not saved then
				DBG:warn("Settings change saved in memory but immediate save failed for", Player.Name)
			end
		end

		DBG:print("Updated setting for", Player.Name, ":", SettingName, "=", SettingValue)

		return true
	end

	function ServerFunctions:UpdateLastChunk(Player, ChunkName)
		return ChunkService:UpdateLastChunk(Player, ChunkName)
	end

	-- Compute and set the nearest previous chunk that has a CatchCare door
	-- Used on blackout so exiting CatchCare via a "Previous" door returns to the correct location
	function ServerFunctions:SetBlackoutReturnChunk(Player: Player)
		return ChunkService:SetBlackoutReturnChunk(Player)
	end

	function ServerFunctions:ClearLeaveDataCFrame(Player)
		return ChunkService:ClearLeaveDataCFrame(Player)
	end

	function ServerFunctions:SaveItemPickup(Player, ChunkName, ItemName)
		local PlayerData = ClientData:Get(Player)

		-- Initialize PickedUpItems table if it doesn't exist
		if not PlayerData.PickedUpItems then
			PlayerData.PickedUpItems = {}
		end

		-- Mark item as picked up
		local ItemKey = ChunkName .. "_" .. ItemName
		PlayerData.PickedUpItems[ItemKey] = true

		-- Update the client's data
		ClientData:UpdateClientData(Player, PlayerData)

		-- Event-based save for item pickups ONLY when AutoSave is enabled and not during cutscenes
		local allowAuto = (PlayerData.Settings and PlayerData.Settings.AutoSave) == true and (PlayerData.InCutscene ~= true)
		if allowAuto then
			saveNow(Player)
		end

		DBG:print("Saved item pickup for player:", Player.Name, "Item:", ItemName, "in chunk:", ChunkName)
		return true
	end

	function ServerFunctions:GetPickedUpItems(Player)
		local PlayerData = ClientData:Get(Player)
		return PlayerData.PickedUpItems or {}
	end

	function ServerFunctions:GrantStuds(Player, Amount)
		local PlayerData = ClientData:Get(Player)

		-- Add studs to player's total
		PlayerData.Studs = (PlayerData.Studs or 0) + Amount

		-- Update the client's data
		ClientData:UpdateClientData(Player, PlayerData)

		DBG:print("Granted", Amount, "studs to player:", Player.Name, "Total:", PlayerData.Studs)
		return true
	end

	-- Server-authoritative item grant
	function ServerFunctions:GrantItem(Player: Player, ItemName: string, Amount: number)
		if type(ItemName) ~= "string" or type(Amount) ~= "number" or Amount <= 0 then
			return false
		end
		local PlayerData = ClientData:Get(Player)
		if not PlayerData then return false end
		PlayerData.Items = PlayerData.Items or {}
		PlayerData.Items[ItemName] = (PlayerData.Items[ItemName] or 0) + Amount
		-- Push update to client
		if ClientData.UpdateClientData then
			ClientData:UpdateClientData(Player, PlayerData)
		end
		DBG:print("[GrantItem] Granted", Amount, "x", ItemName, "to", Player.Name)
		return true
	end

	-- Get player info for viewing (badges, studs, etc.)
	function ServerFunctions:GetViewPlayerInfo(Player: Player, TargetUserId: number)
		local Players = game:GetService("Players")
		local targetPlayer = Players:GetPlayerByUserId(TargetUserId)
		
		DBG:print("[GetViewPlayerInfo] Request from", Player.Name, "for UserId:", TargetUserId)
		
		if not targetPlayer then
			DBG:print("[GetViewPlayerInfo] Target player not found")
			return nil
		end
		
		DBG:print("[GetViewPlayerInfo] Target player found:", targetPlayer.Name)
		
		local TargetPlayerData = ClientData:Get(targetPlayer)
		if not TargetPlayerData then
			DBG:print("[GetViewPlayerInfo] No player data found for", targetPlayer.Name)
			return nil
		end
		
		local result = {
			Badges = TargetPlayerData.Badges or 0,
			Studs = TargetPlayerData.Studs or 0,
		}
		
		DBG:print("[GetViewPlayerInfo] Returning for", targetPlayer.Name, "- Badges:", result.Badges, "Studs:", result.Studs)
		
		return result
	end
end

return PlayerProfile


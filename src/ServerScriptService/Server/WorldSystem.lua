--!strict
--[[
	WorldSystem.lua
	Handles world/chunk management: loading chunks, encounters, chunk transitions
	Separated from ServerFunctions for better organization
]]

local WorldSystem = {}

-- Dependencies (will be injected)
local ClientData: any = nil
local GameData: any = nil
local GameConfig: any = nil
local ChunkService: any = nil
local DBG: any = nil
local ActiveBattles: {[Player]: any} = {}

--[[
	Initialize WorldSystem with dependencies
]]
function WorldSystem.Initialize(dependencies: {[string]: any})
	ClientData = dependencies.ClientData
	GameData = dependencies.GameData
	GameConfig = dependencies.GameConfig
	ChunkService = dependencies.ChunkService
	DBG = dependencies.DBG
	ActiveBattles = dependencies.ActiveBattles
end

--[[
	Load chunk for player
	@param Player The player
	@param ChunkName The chunk name to load
	@return table? Chunk name and proper name, or nil
]]
function WorldSystem.LoadChunkPlayer(Player: Player, ChunkName: string): any?
	local PlayerData = ClientData:Get(Player)
	local Authorized = false

	DBG:warn("[LoadChunkPlayer] Player:", Player.Name, "| Requested Chunk:", ChunkName)

	-- CRITICAL: Chunk1 should always be accessible as emergency fallback
	-- Check this FIRST before any other validation to prevent players from getting stuck
	if ChunkName == "Chunk1" then
		DBG:warn("[LoadChunkPlayer] Chunk1 requested - will always allow as emergency fallback")
		Authorized = true
	end

	-- Validate PlayerData exists
	if not PlayerData then
		DBG:warn("[LoadChunkPlayer] CRITICAL: PlayerData is nil for player:", Player.Name)
		-- If Chunk1 was requested, still try to load it even without PlayerData
		if ChunkName == "Chunk1" and Authorized then
			DBG:warn("[LoadChunkPlayer] Attempting Chunk1 load despite nil PlayerData")
			-- Create minimal PlayerData for Chunk1 load
			PlayerData = {
				Chunk = "nil",
				LastChunk = nil,
				LeaveData = nil,
			}
		else
			-- Return nil instead of kicking - let client handle retry
			return nil
		end
	end

	if not PlayerData.Chunk then
		PlayerData.Chunk = "nil"
		DBG:warn("[LoadChunkPlayer] No previous Chunk found in session, defaulted to 'nil'")
	end

	-- Failsafe: prevent re-entering CatchCare from its own exit
	do
		local current = tostring(PlayerData.Chunk or "")
		local requested = tostring(ChunkName or "")
		if current == "CatchCare" and requested == "CatchCare" then
			DBG:warn("[CatchCare Failsafe] Preventing re-entry into CatchCare from CatchCare; selecting fallback")
			local ChunkList = GameData.ChunkList
			local fallback = nil
			local last = tostring(PlayerData.LastChunk or "")
			if last ~= "" and last ~= "CatchCare" and ChunkList[last] then
				fallback = last
			end
			if not fallback then
				local ld = PlayerData.LeaveData
				local ldChunk = type(ld) == "table" and tostring(ld.Chunk or "") or ""
				if ldChunk ~= "" and ldChunk ~= "CatchCare" and ChunkList[ldChunk] then
					fallback = ldChunk
				end
			end
			if not fallback and ChunkList["Chunk1"] then
				fallback = "Chunk1"
			end
			if fallback then
				DBG:warn("[CatchCare Failsafe] Redirecting requested chunk from CatchCare to:", fallback)
				ChunkName = fallback
				-- Update authorization if redirected to Chunk1
				if fallback == "Chunk1" then
					Authorized = true
				end
			end
		end
	end

	local ChunkData, ParentChunk = ChunkService:GetChunkRecord(ChunkName)

	if not ChunkData then
		DBG:warn("Chunk not found in GameData:", tostring(ChunkName))
		-- If Chunk1 is missing from ChunkList, this is a critical configuration error
		if ChunkName == "Chunk1" then
			DBG:warn("[CRITICAL] Chunk1 not found in ChunkList! This is a critical configuration error.")
			DBG:warn("[CRITICAL] Chunk1 must exist in ChunkList - game cannot function without it!")
			return nil
		end
		Player:Kick("Unable to find requested chunk! RQ: " .. tostring(ChunkName))
		return nil
	end

	if PlayerData.Chunk == ChunkName then
		Authorized = true
		DBG:warn("Player came from same chunk: Authorized")
	end

	-- Only check authorization if not already authorized (e.g., Chunk1 emergency fallback)
	if not Authorized then
		local ok, errMsg = ChunkService:IsChunkTransitionAuthorized(Player, PlayerData, ChunkName)
		if ok then
			Authorized = true
		else
			DBG:warn(errMsg or ("Unauthorized chunk transition to " .. tostring(ChunkName)))
			-- Special case: Chunk1 should always be accessible as a safe fallback
			-- This prevents players from getting stuck on the loading screen
			-- Allow Chunk1 regardless of current chunk state (nil, Title, or any other chunk)
			if ChunkName == "Chunk1" then
				DBG:warn("[LoadChunkPlayer] Allowing Chunk1 load as emergency fallback for player coming from:", tostring(PlayerData.Chunk))
				Authorized = true
			end
		end
	end

	-- Starter gate: prevent leaving Professor's Lab without a starter
	if Authorized then
		local leavingProfsLab = (PlayerData.Chunk == "Professor's Lab") and (ChunkName ~= "Professor's Lab")
		if leavingProfsLab then
			local hasStarter = (PlayerData.SelectedStarter ~= nil) or (PlayerData.Party and #PlayerData.Party > 0)
			if not hasStarter then
				DBG:warn("Blocking exit: Player has not chosen a starter yet")
				return nil
			end
			if tostring(ChunkName) == "PlayersHouse" then
				pcall(function()
					PlayerData.Events = PlayerData.Events or {}
					if PlayerData.Events.MET_PROFESSOR ~= true then
						PlayerData.Events.MET_PROFESSOR = true
						DBG:print("[LoadChunkPlayer] Marked MET_PROFESSOR for player:", Player.Name)
					end
					ClientData:UpdateClientData(Player, PlayerData)
				end)
			end
		end
	end

	if not Authorized then
		local current = tostring(PlayerData and PlayerData.Chunk or "nil")
		local last = tostring(PlayerData and PlayerData.LastChunk or "nil")
		local msg = string.format("Tried to load an unauthorized chunk! :: RQ:%s | Curr:%s | Last:%s", tostring(ChunkName), current, last)
		Player:Kick(msg)
		return nil
	end
	
	-- If entering CatchCare, remember where the player came from
	do
		local previousChunk = tostring(PlayerData.Chunk or "")
		if ChunkName == "CatchCare" then
			local ChunkList = GameData.ChunkList
			if previousChunk ~= "" and previousChunk ~= "CatchCare" and ChunkList[previousChunk] then
				PlayerData.LastChunk = previousChunk
				DBG:warn("[CatchCare Entry] Set LastChunk to previous:", previousChunk)
				pcall(function() ClientData:UpdateClientData(Player, PlayerData) end)
			end
		end
	end
	
	PlayerData.Chunk = ChunkName

	local SourceFolder = ChunkService:GetSourceFolder(ChunkName)

	if not SourceFolder then
		DBG:warn("Could not locate chunk in storage:", ChunkName, "IsSubRoom:", ChunkData.IsSubRoom)
		
		-- Enhanced debugging for missing chunks
		local ServerStorage = game:GetService("ServerStorage")
		local ChunksFolder = ServerStorage:FindFirstChild("Chunks")
		local InteriorsFolder = ServerStorage:FindFirstChild("Interiors")
		
		if ChunkName == "Chunk1" then
			DBG:warn("[CRITICAL] Chunk1 not found in ServerStorage! This is a critical configuration error.")
			DBG:warn("[CRITICAL] Chunk1 must exist in ServerStorage.Chunks - game cannot function without it!")
			if ChunksFolder then
				DBG:warn("[CRITICAL] ServerStorage.Chunks exists. Available chunks:")
				for _, child in ipairs(ChunksFolder:GetChildren()) do
					DBG:warn("  -", child.Name)
				end
			else
				DBG:warn("[CRITICAL] ServerStorage.Chunks folder does not exist!")
			end
			-- Return nil instead of kicking - let client handle the error gracefully
			return nil
		end
		
		-- For other chunks, provide more detailed error info
		if ChunkData.IsSubRoom then
			if InteriorsFolder then
				DBG:warn("Available interior chunks:")
				for _, child in ipairs(InteriorsFolder:GetChildren()) do
					DBG:warn("  -", child.Name)
				end
			else
				DBG:warn("ServerStorage.Interiors folder does not exist!")
			end
		else
			if ChunksFolder then
				DBG:warn("Available main chunks:")
				for _, child in ipairs(ChunksFolder:GetChildren()) do
					DBG:warn("  -", child.Name)
				end
			else
				DBG:warn("ServerStorage.Chunks folder does not exist!")
			end
		end
		
		Player:Kick("Requested chunk not found in storage! :: RQ: " .. ChunkName)
		return nil
	end

	local ClonedChunk = SourceFolder:Clone()
	ClonedChunk.Name = ChunkName
	ClonedChunk.Parent = Player.PlayerGui
	pcall(function()
		ClonedChunk:SetAttribute("IsInterior", ChunkData.IsSubRoom == true)
		ClonedChunk:SetAttribute("ScriptedCam", ChunkData.ScriptedCam == true)
	end)
	
	-- Validate LeaveData vs chunk fallback spawn
	do
		local ld = PlayerData.LeaveData
		local essentials = ClonedChunk:FindFirstChild("Essentials")
		local fallbackPart = essentials and essentials:FindFirstChild("ChunkSpawnFallBack")
		if type(ld) == "table" and type(ld.Position) == "table" and fallbackPart and fallbackPart:IsA("BasePart") then
			local ldChunk = tostring(ld.Chunk or ChunkName)
			if ldChunk == ChunkName then
				local p = ld.Position
				local dx = math.abs((p.X or 0) - fallbackPart.Position.X)
				local dy = math.abs((p.Y or 0) - fallbackPart.Position.Y)
				local dz = math.abs((p.Z or 0) - fallbackPart.Position.Z)
				if dx >= 600 or dy >= 600 or dz >= 600 then
					DBG:warn(string.format("[LeaveData] Clearing LeaveData for %s due to large offset from fallback (dx=%.1f, dy=%.1f, dz=%.1f)", Player.Name, dx, dy, dz))
					PlayerData.LeaveData = nil
					pcall(function() ClientData:UpdateClientData(Player, PlayerData) end)
				end
			end
		end
	end
	
	DBG:warn("Successfully cloned and parented chunk as:", ClonedChunk.Name)
	DBG:warn("Successfully cloned and parented chunk:", ChunkName)

	return {ChunkName, ChunkData and ChunkData.ProperName}
end

--[[
	Get encounter data for a chunk
	@param Player The player
	@param ChunkName The chunk name
	@return {any} Encounter data array
]]
function WorldSystem.GetEncounterData(Player: Player, ChunkName: string): {any}
	local ChunkData = GameData.ChunkList[ChunkName]
	
	if not ChunkData then
		DBG:warn("Chunk not found for encounter data:", ChunkName)
		return {}
	end
	
	return ChunkData.Encounters or {}
end

--[[
	Try encounter step: roll and start wild battle if triggered
	@param Player The player
	@return boolean Whether an encounter was triggered
]]
function WorldSystem.TryEncounterStep(Player: Player): boolean
	DBG:print("=== TryEncounterStep called for", Player.Name, "===")
	
	-- SECURITY: Prevent multiple battles
	if ActiveBattles[Player] then
		DBG:print("Player", Player.Name, "already in battle, refusing encounter request")
		return false
	end
	
	local PlayerData = ClientData:Get(Player)
	if not PlayerData then
		DBG:warn("No player data found for", Player.Name)
		return false
	end
	local ChunkName = PlayerData.Chunk
	DBG:print("Player", Player.Name, "is in chunk:", ChunkName)
	
	local ChunkData = GameData.ChunkList[ChunkName]
	if not ChunkData then
		DBG:warn("No chunk data found for:", ChunkName)
		return false
	end
	local encounterList = ChunkData.Encounters or {}
	DBG:print("Encounter list length:", #encounterList)
	if #encounterList == 0 then
		DBG:print("No encounters available in chunk:", ChunkName)
		return false
	end

	-- Global roll to throttle encounter frequency
	if math.random(1, 100) > (GameConfig.ENCOUNTER_BASE_CHANCE or 15) then
		DBG:print("No encounter triggered (global roll)")
		return false
	end

	-- Roll per-entry server-side
	for i, entry in ipairs(encounterList) do
		local creatureName = entry[1]
		local minLevel = entry[2]
		local maxLevel = entry[3]
		local chance = entry[4]
		local roll = math.random(1, 100)
		DBG:print("Encounter", i, "- Creature:", creatureName, "Level:", minLevel, "-", maxLevel, "Chance:", chance, "Roll:", roll)
		if roll <= chance then
			DBG:print("Encounter triggered! Starting battle with", creatureName)
			-- Return encounter data - StartBattle will be called by ServerFunctions
			return true, {
				CreatureName = creatureName,
				Level = math.random(minLevel, maxLevel),
			}
		end
	end

	DBG:print("No encounter triggered for", Player.Name)
	return false
end

-- Note: UpdateLastChunk, SetBlackoutReturnChunk, ClearLeaveDataCFrame delegate to ChunkService
-- so they can remain thin wrappers in ServerFunctions

return WorldSystem


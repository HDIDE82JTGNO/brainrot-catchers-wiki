--!nocheck
local MysteryTradeService = {}

-- Services
local Players = game:GetService("Players")
local MessagingService = game:GetService("MessagingService")
local HttpService = game:GetService("HttpService")

-- State machine states
local STATE_IDLE = "Idle"
local STATE_SEARCHING = "Searching"
local STATE_SELECTING = "Selecting"
local STATE_CONFIRMING = "Confirming"
local STATE_WAITING = "Waiting"
local STATE_COOLDOWN = "Cooldown"

-- Phase timeouts (in seconds) - only Searching has a timeout, others are infinite
local PHASE_TIMEOUTS = {
	[STATE_SEARCHING] = 10,
	-- All other phases have no timeout (infinite)
}

-- Cooldown durations (in seconds)
local COOLDOWN_CANCEL = 30
local COOLDOWN_FAILED = 15
local COOLDOWN_SUCCESS = 60

-- Rate limiting
local RATE_LIMIT_SECONDS = 5

-- Cross-server timeout
local CROSS_SERVER_ACK_TIMEOUT = 5
local CROSS_SERVER_MESSAGE_MAX_AGE = 10 -- Maximum age of cross-server messages in seconds

-- State tracking
local playerStates: {[Player]: string} = {}
local playerCooldowns: {[Player]: {cooldownEnd: number, lastRequest: number}} = {}
local activeSessions: {[string]: any} = {}
local searchQueue: {Player} = {}
local creatureLocks: {[string]: {SessionId: string, PlayerId: number, Location: any}} = {} -- Key: "PlayerId_LocationType_BoxIndex_SlotIndex"

-- Server ID for cross-server communication
local SERVER_ID = HttpService:GenerateGUID(false)

-- MessagingService topics
local TOPIC_SEARCH = "MysteryTrade_Search"
local TOPIC_MATCH_REQUEST = "MysteryTrade_MatchRequest"
local TOPIC_MATCH_ACK = "MysteryTrade_MatchAck"

-- Dependencies (will be injected)
local ClientData = nil
local Events = nil
local DBG = nil

-- Validate creature for MysteryTrade (more lenient than battle validation)
-- Stored creatures may not have Stats computed, so we only validate essential fields
local function validateCreatureForTrade(creature: any): (boolean, string?)
	if not creature or type(creature) ~= "table" then
		return false, "Invalid creature data"
	end
	
	if not creature.Name or type(creature.Name) ~= "string" or creature.Name == "" then
		return false, "Invalid creature name"
	end
	
	if not creature.Level or type(creature.Level) ~= "number" or creature.Level < 1 or creature.Level > 100 then
		return false, "Invalid creature level"
	end
	
	-- Stats is optional for stored creatures (can be computed on-demand)
	-- But if it exists, validate it's a table
	if creature.Stats ~= nil and type(creature.Stats) ~= "table" then
		return false, "Invalid creature stats format"
	end
	
	-- If Stats exists and has HP, validate it
	if creature.Stats and creature.Stats.HP ~= nil then
		if type(creature.Stats.HP) ~= "number" or creature.Stats.HP < 0 then
			return false, "Invalid creature HP"
		end
	end
	
	-- CurrentHP is optional but if present should be 0-100
	if creature.CurrentHP ~= nil then
		if type(creature.CurrentHP) ~= "number" or creature.CurrentHP < 0 or creature.CurrentHP > 100 then
			return false, "Invalid CurrentHP (must be 0-100)"
		end
	end
	
	return true, nil
end

-- Helper function to get creature lock key
local function getCreatureLockKey(playerId: number, location: any): string
	if location.where == "Party" then
		return string.format("%d_Party_%d", playerId, location.index)
	elseif location.where == "Box" then
		return string.format("%d_Box_%d_%d", playerId, location.box or 0, location.index)
	end
	return ""
end

-- Helper function to check if creature is locked
local function isCreatureLocked(playerId: number, location: any): boolean
	local key = getCreatureLockKey(playerId, location)
	return creatureLocks[key] ~= nil
end

-- Lock a creature
function MysteryTradeService:LockCreature(sessionId: string, playerId: number, location: any)
	local key = getCreatureLockKey(playerId, location)
	creatureLocks[key] = {
		SessionId = sessionId,
		PlayerId = playerId,
		Location = location,
	}
end

-- Unlock a creature
function MysteryTradeService:UnlockCreature(playerId: number, location: any)
	local key = getCreatureLockKey(playerId, location)
	creatureLocks[key] = nil
end

-- Unlock all creatures for a session
function MysteryTradeService:UnlockSessionCreatures(sessionId: string)
	for key, lock in pairs(creatureLocks) do
		if lock.SessionId == sessionId then
			creatureLocks[key] = nil
		end
	end
end

-- Get player state
function MysteryTradeService:GetPlayerState(player: Player): string
	return playerStates[player] or STATE_IDLE
end

-- Set player state
function MysteryTradeService:SetPlayerState(player: Player, state: string)
	playerStates[player] = state
end

-- Check if player can start Mystery Trade
function MysteryTradeService:CanStartTrade(player: Player): (boolean, string?)
	local state = self:GetPlayerState(player)
	if state ~= STATE_IDLE then
		return false, "You are already in a Mystery Trade."
	end
	
	-- Check cooldown
	local cooldown = playerCooldowns[player]
	if cooldown and os.clock() < cooldown.cooldownEnd then
		local remaining = math.ceil(cooldown.cooldownEnd - os.clock())
		return false, string.format("Please wait %d seconds before starting another Mystery Trade.", remaining)
	end
	
	-- Check rate limit
	if cooldown and os.clock() - cooldown.lastRequest < RATE_LIMIT_SECONDS then
		return false, "Please wait a moment before trying again."
	end
	
	return true
end

-- Start cooldown
function MysteryTradeService:StartCooldown(player: Player, duration: number)
	if not playerCooldowns[player] then
		playerCooldowns[player] = {cooldownEnd = 0, lastRequest = 0}
	end
	playerCooldowns[player].cooldownEnd = os.clock() + duration
	self:SetPlayerState(player, STATE_COOLDOWN)
	
	-- Return to idle after cooldown
	task.delay(duration, function()
		if player and player.Parent and self:GetPlayerState(player) == STATE_COOLDOWN then
			self:SetPlayerState(player, STATE_IDLE)
		end
	end)
end

-- Update last request time
function MysteryTradeService:UpdateLastRequest(player: Player)
	if not playerCooldowns[player] then
		playerCooldowns[player] = {cooldownEnd = 0, lastRequest = 0}
	end
	playerCooldowns[player].lastRequest = os.clock()
end

-- Rate limiting per action type
local actionTimestamps: {[Player]: {[string]: number}} = {}

-- Check rate limit for specific action
function MysteryTradeService:CheckRateLimit(player: Player, actionType: string): (boolean, string?)
	-- Use per-action rate limiting only (not global lastRequest)
	-- This prevents actions from blocking each other unnecessarily
	if not actionTimestamps[player] then
		actionTimestamps[player] = {}
	end
	
	local lastAction = actionTimestamps[player][actionType] or 0
	if os.clock() - lastAction < RATE_LIMIT_SECONDS then
		return false, "Please wait a moment before trying again."
	end
	
	actionTimestamps[player][actionType] = os.clock()
	-- Update global lastRequest for cooldown tracking (but don't use it for rate limiting)
	self:UpdateLastRequest(player)
	return true
end

-- Track search start times for timeout handling
local searchStartTimes: {[Player]: number} = {}

-- Start search
function MysteryTradeService:StartSearch(player: Player): (boolean, string?)
	local canStart, reason = self:CanStartTrade(player)
	if not canStart then
		return false, reason
	end
	
	self:UpdateLastRequest(player)
	self:SetPlayerState(player, STATE_SEARCHING)
	searchStartTimes[player] = os.clock()
	
	-- Add to local search queue
	for i, queuedPlayer in ipairs(searchQueue) do
		if queuedPlayer == player then
			return false, "You are already searching."
		end
	end
	table.insert(searchQueue, player)
	
	-- Try to match locally first
	task.spawn(function()
		self:TryLocalMatch(player)
	end)
	
	return true
end

-- Try to match locally
function MysteryTradeService:TryLocalMatch(player: Player)
	-- Wait a bit for local matches
	local startTime = os.clock()
	local searchTimeout = PHASE_TIMEOUTS[STATE_SEARCHING]
	
	while os.clock() - startTime < searchTimeout do
		-- Check if player is still searching
		if self:GetPlayerState(player) ~= STATE_SEARCHING then
			return
		end
		
		-- Try to find a match (check queue in reverse to avoid index issues when removing)
		for i = #searchQueue, 1, -1 do
			local otherPlayer = searchQueue[i]
			if otherPlayer ~= player and otherPlayer.Parent and self:GetPlayerState(otherPlayer) == STATE_SEARCHING then
				-- Found a match! Remove both from queue atomically
				for j = #searchQueue, 1, -1 do
					if searchQueue[j] == player or searchQueue[j] == otherPlayer then
						table.remove(searchQueue, j)
					end
				end
				-- Create session
				self:CreateSession(player, otherPlayer)
				return
			end
		end
		
		task.wait(0.1) -- Check more frequently
	end
	
	-- No local match found, try cross-server
	if self:GetPlayerState(player) == STATE_SEARCHING then
		self:TryCrossServerMatch(player, startTime)
	end
end

-- Try cross-server match
function MysteryTradeService:TryCrossServerMatch(player: Player, searchStartTime: number?)
	-- Calculate remaining time
	local elapsed = searchStartTime and (os.clock() - searchStartTime) or 0
	local remainingTime = math.max(0, PHASE_TIMEOUTS[STATE_SEARCHING] - elapsed)
	
	if remainingTime <= 0 then
		self:CancelSearch(player, "Unable to find a trade partner.")
		return
	end
	
	-- Publish search request
	local searchMessage = {
		Type = "Search",
		UserId = player.UserId,
		ServerId = SERVER_ID,
		Timestamp = os.clock(),
	}
	
	local ok, err = pcall(function()
		MessagingService:PublishAsync(TOPIC_SEARCH, searchMessage)
	end)
	
	if not ok then
		DBG:warn("[MysteryTrade] Failed to publish cross-server search:", err)
		self:CancelSearch(player, "Unable to search across servers.")
		return
	end
	
	-- Wait for remaining time, then cancel if no match found
	task.delay(remainingTime, function()
		if self:GetPlayerState(player) == STATE_SEARCHING then
			self:CancelSearch(player, "Unable to find a trade partner.")
		end
	end)
end

-- Create session
function MysteryTradeService:CreateSession(playerA: Player, playerB: Player)
	-- Players should already be removed from queue by TryLocalMatch
	-- But ensure they're removed just in case
	for i = #searchQueue, 1, -1 do
		if searchQueue[i] == playerA or searchQueue[i] == playerB then
			table.remove(searchQueue, i)
		end
	end
	
	local sessionId = string.format("%s_%d_%s", SERVER_ID, os.time(), HttpService:GenerateGUID(false))
	
	local session = {
		SessionId = sessionId,
		PlayerA = playerA,
		PlayerB = playerB,
		State = STATE_SELECTING,
		PhaseStartTime = os.clock(),
		CreatureA = nil,
		CreatureB = nil,
		LocationA = nil,
		LocationB = nil,
		ConfirmedA = false,
		ConfirmedB = false,
		ServerA = SERVER_ID,
		ServerB = SERVER_ID,
		MatchAcknowledged = true, -- Local match, no need for ack
	}
	
	activeSessions[sessionId] = session
	self:SetPlayerState(playerA, STATE_SELECTING)
	self:SetPlayerState(playerB, STATE_SELECTING)
	
	-- Notify clients
	Events.Communicate:FireClient(playerA, "MysteryTradeFound", {
		SessionId = sessionId,
		PartnerName = playerB.DisplayName,
		PartnerUserId = playerB.UserId,
	})
	
	Events.Communicate:FireClient(playerB, "MysteryTradeFound", {
		SessionId = sessionId,
		PartnerName = playerA.DisplayName,
		PartnerUserId = playerA.UserId,
	})
end

-- Cancel search
function MysteryTradeService:CancelSearch(player: Player, reason: string?)
	-- Remove from queue
	for i = #searchQueue, 1, -1 do
		if searchQueue[i] == player then
			table.remove(searchQueue, i)
			break
		end
	end
	
	-- Clear search start time
	searchStartTimes[player] = nil
	
	-- Always ensure player is reset to idle state when search fails
	-- Check if player was searching to determine if we should notify and apply cooldown
	local wasSearching = self:GetPlayerState(player) == STATE_SEARCHING
	
	-- Reset state to idle (ensures player can search again)
	-- Note: StartCooldown will set it to COOLDOWN temporarily, but will return to IDLE after cooldown expires
	self:SetPlayerState(player, STATE_IDLE)
	
	if wasSearching then
		-- Only apply cooldown and notify if player was actually searching
		self:StartCooldown(player, COOLDOWN_FAILED)
		
		if reason then
			Events.Communicate:FireClient(player, "MysteryTradeCancelled", {
				Reason = reason,
			})
		end
	else
		-- If player wasn't searching but we're cleaning up, ensure state is definitely idle
		-- This handles edge cases where state might be stuck
		self:SetPlayerState(player, STATE_IDLE)
	end
end

-- Cancel session
function MysteryTradeService:CancelSession(sessionId: string, reason: string)
	local session = activeSessions[sessionId]
	if not session then return end
	
	-- Unlock creatures
	self:UnlockSessionCreatures(sessionId)
	
	-- Notify players
	if session.PlayerA and session.PlayerA.Parent then
		self:SetPlayerState(session.PlayerA, STATE_IDLE)
		self:StartCooldown(session.PlayerA, COOLDOWN_CANCEL)
		Events.Communicate:FireClient(session.PlayerA, "MysteryTradeCancelled", {
			Reason = reason,
			SessionId = sessionId,
		})
	end
	
	if session.PlayerB and session.PlayerB.Parent then
		self:SetPlayerState(session.PlayerB, STATE_IDLE)
		self:StartCooldown(session.PlayerB, COOLDOWN_CANCEL)
		Events.Communicate:FireClient(session.PlayerB, "MysteryTradeCancelled", {
			Reason = reason,
			SessionId = sessionId,
		})
	end
	
	activeSessions[sessionId] = nil
end

-- Select creature
function MysteryTradeService:SelectCreature(player: Player, sessionId: string, creature: any, location: any): (boolean, string?)
	-- SECURITY: Rate limiting
	local rateLimitOk, rateLimitError = self:CheckRateLimit(player, "SelectCreature")
	if not rateLimitOk then
		return false, rateLimitError
	end
	
	local session = activeSessions[sessionId]
	if not session then
		return false, "Session not found."
	end
	
	-- Validate state
	if session.State ~= STATE_SELECTING then
		return false, "Invalid session state."
	end
	
	-- Check if this is player A or B
	local isPlayerA = session.PlayerA == player
	local isPlayerB = session.PlayerB == player
	
	if not isPlayerA and not isPlayerB then
		return false, "You are not part of this session."
	end
	
	-- Check if creature already selected
	if isPlayerA and session.CreatureA then
		return false, "You have already selected a creature."
	end
	if isPlayerB and session.CreatureB then
		return false, "You have already selected a creature."
	end
	
	-- SECURITY: Validate location structure
	if not location or type(location) ~= "table" then
		return false, "Invalid location data."
	end
	
	if location.where ~= "Party" and location.where ~= "Box" then
		return false, "Invalid location type."
	end
	
	-- SECURITY: Lock creature FIRST to prevent race conditions
	-- Check if creature is already locked
	if isCreatureLocked(player.UserId, location) then
		return false, "This creature is already in a trade."
	end
	
	-- Lock creature immediately (before validation)
	self:LockCreature(sessionId, player.UserId, location)
	
	-- SECURITY: Get player data and validate creature ownership
	local playerData = ClientData:Get(player)
	if not playerData then
		-- Unlock creature if validation fails
		self:UnlockCreature(player.UserId, location)
		return false, "Player data not available."
	end
	
	-- SECURITY: Validate location bounds and get actual creature from server
	local actualCreature = nil
	local locationIndex = nil
	
	if location.where == "Party" then
		locationIndex = tonumber(location.index)
		if not locationIndex or locationIndex < 1 or locationIndex > 6 then
			self:UnlockCreature(player.UserId, location)
			return false, "Invalid party slot index."
		end
		
		if not playerData.Party or not playerData.Party[locationIndex] then
			self:UnlockCreature(player.UserId, location)
			return false, "No creature at that party slot."
		end
		
		actualCreature = playerData.Party[locationIndex]
		
	elseif location.where == "Box" then
		local boxIndex = tonumber(location.box)
		locationIndex = tonumber(location.index)
		
		if not boxIndex or boxIndex < 1 or boxIndex > 8 then
			self:UnlockCreature(player.UserId, location)
			return false, "Invalid box index."
		end
		
		if not locationIndex or locationIndex < 1 or locationIndex > 30 then
			self:UnlockCreature(player.UserId, location)
			return false, "Invalid box slot index."
		end
		
		if not playerData.Boxes or not playerData.Boxes[boxIndex] or not playerData.Boxes[boxIndex].Creatures then
			self:UnlockCreature(player.UserId, location)
			return false, "Invalid box structure."
		end
		
		if not playerData.Boxes[boxIndex].Creatures[locationIndex] then
			self:UnlockCreature(player.UserId, location)
			return false, "No creature at that box slot."
		end
		
		actualCreature = playerData.Boxes[boxIndex].Creatures[locationIndex]
	end
	
	if not actualCreature then
		self:UnlockCreature(player.UserId, location)
		return false, "Creature not found at specified location."
	end
	
	-- SECURITY: Validate creature data structure
	-- Use lenient validation for stored creatures (Stats is optional)
	local creatureValid, creatureError = validateCreatureForTrade(actualCreature)
	if not creatureValid then
		self:UnlockCreature(player.UserId, location)
		return false, "Invalid creature data: " .. (creatureError or "Unknown error")
	end
	
	-- SECURITY: Compare client-provided creature with server-side creature
	-- Basic comparison to ensure client isn't sending fake data
	-- We trust the server-side creature, but verify key fields match
	if creature and type(creature) == "table" then
		if creature.Name ~= actualCreature.Name then
			self:UnlockCreature(player.UserId, location)
			return false, "Creature data mismatch."
		end
		if creature.Level ~= actualCreature.Level then
			self:UnlockCreature(player.UserId, location)
			return false, "Creature data mismatch."
		end
	end
	
	-- Store server-side creature data (not client-provided data)
	if isPlayerA then
		session.CreatureA = actualCreature
		session.LocationA = location
		self:SetPlayerState(player, STATE_CONFIRMING)
	else
		session.CreatureB = actualCreature
		session.LocationB = location
		self:SetPlayerState(player, STATE_CONFIRMING)
	end
	
	session.PhaseStartTime = os.clock()
	
	-- Notify both players that selection was made
	-- If both have selected, notify them to confirm
	if session.CreatureA and session.CreatureB then
		-- Transition session state to CONFIRMING when both players have selected
		session.State = STATE_CONFIRMING
		session.PhaseStartTime = os.clock()
		
		if session.PlayerA and session.PlayerA.Parent then
			Events.Communicate:FireClient(session.PlayerA, "MysteryTradePartnerSelected", {
				SessionId = sessionId,
			})
		end
		if session.PlayerB and session.PlayerB.Parent then
			Events.Communicate:FireClient(session.PlayerB, "MysteryTradePartnerSelected", {
				SessionId = sessionId,
			})
		end
	end
	
	return true
end

-- Confirm trade
function MysteryTradeService:ConfirmTrade(player: Player, sessionId: string): (boolean, string?)
	-- SECURITY: Rate limiting
	local rateLimitOk, rateLimitError = self:CheckRateLimit(player, "ConfirmTrade")
	if not rateLimitOk then
		return false, rateLimitError
	end
	
	local session = activeSessions[sessionId]
	if not session then
		return false, "Session not found."
	end
	
	-- Validate state
	if session.State ~= STATE_CONFIRMING then
		return false, "Invalid session state."
	end
	
	-- Check if this is player A or B
	local isPlayerA = session.PlayerA == player
	local isPlayerB = session.PlayerB == player
	
	if not isPlayerA and not isPlayerB then
		return false, "You are not part of this session."
	end
	
	-- Mark as confirmed
	if isPlayerA then
		session.ConfirmedA = true
	else
		session.ConfirmedB = true
	end
	
	-- Check if both confirmed
	if session.ConfirmedA and session.ConfirmedB then
		session.State = STATE_WAITING
		session.PhaseStartTime = os.clock()
		self:SetPlayerState(session.PlayerA, STATE_WAITING)
		self:SetPlayerState(session.PlayerB, STATE_WAITING)
		
		-- Execute trade
		self:ExecuteTrade(sessionId)
	end
	
	return true
end

-- Execute trade
function MysteryTradeService:ExecuteTrade(sessionId: string)
	local session = activeSessions[sessionId]
	if not session then return end
	
	-- Get player data
	local playerAData = ClientData:Get(session.PlayerA)
	local playerBData = ClientData:Get(session.PlayerB)
	
	if not playerAData or not playerBData then
		self:CancelSession(sessionId, "Player data not available.")
		return
	end
	
	-- Swap creatures
	if session.LocationA.where == "Party" then
		local idx = session.LocationA.index
		if playerAData.Party and playerAData.Party[idx] then
			playerAData.Party[idx] = session.CreatureB
		end
	elseif session.LocationA.where == "Box" then
		local boxIdx = session.LocationA.box
		local slotIdx = session.LocationA.index
		if playerAData.Boxes and playerAData.Boxes[boxIdx] and playerAData.Boxes[boxIdx].Creatures then
			playerAData.Boxes[boxIdx].Creatures[slotIdx] = session.CreatureB
		end
	end
	
	if session.LocationB.where == "Party" then
		local idx = session.LocationB.index
		if playerBData.Party and playerBData.Party[idx] then
			playerBData.Party[idx] = session.CreatureA
		end
	elseif session.LocationB.where == "Box" then
		local boxIdx = session.LocationB.box
		local slotIdx = session.LocationB.index
		if playerBData.Boxes and playerBData.Boxes[boxIdx] and playerBData.Boxes[boxIdx].Creatures then
			playerBData.Boxes[boxIdx].Creatures[slotIdx] = session.CreatureA
		end
	end
	
	-- Update client data
	ClientData:UpdateClientData(session.PlayerA, playerAData)
	ClientData:UpdateClientData(session.PlayerB, playerBData)
	
	-- Notify clients
	Events.Communicate:FireClient(session.PlayerA, "MysteryTradeFinalized", {
		SessionId = sessionId,
		YourOffer = {session.CreatureA},
		PartnerOffer = {session.CreatureB},
	})
	
	Events.Communicate:FireClient(session.PlayerB, "MysteryTradeFinalized", {
		SessionId = sessionId,
		YourOffer = {session.CreatureB},
		PartnerOffer = {session.CreatureA},
	})
	
	-- Unlock creatures
	self:UnlockSessionCreatures(sessionId)
	
	-- Set cooldowns
	self:StartCooldown(session.PlayerA, COOLDOWN_SUCCESS)
	self:StartCooldown(session.PlayerB, COOLDOWN_SUCCESS)
	
	-- Clean up session
	activeSessions[sessionId] = nil
end

-- Watchdog thread
function MysteryTradeService:StartWatchdog()
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			
			-- Check for timed out sessions (only Searching phase has timeout)
			for sessionId, session in pairs(activeSessions) do
				-- Only check timeout for Searching state
				if session.State == STATE_SEARCHING then
					local phaseDuration = now - session.PhaseStartTime
					local timeout = PHASE_TIMEOUTS[STATE_SEARCHING]
					
					if timeout and phaseDuration > timeout then
						self:CancelSession(sessionId, "Trade timed out.")
					end
				end
				-- All other states have no timeout
			end
			
			-- Check for timed out searches
			for player, startTime in pairs(searchStartTimes) do
				if not player.Parent then
					searchStartTimes[player] = nil
				elseif self:GetPlayerState(player) == STATE_SEARCHING then
					local searchDuration = now - startTime
					if searchDuration > PHASE_TIMEOUTS[STATE_SEARCHING] then
						DBG:warn("[MysteryTrade] Search timeout for", player.Name, "after", searchDuration, "seconds")
						self:CancelSearch(player, "Unable to find a trade partner.")
					end
				else
					-- Player is no longer searching, clear start time
					searchStartTimes[player] = nil
				end
			end
			
			-- Clean up disconnected players
			for player, state in pairs(playerStates) do
				if not player.Parent then
					playerStates[player] = nil
					playerCooldowns[player] = nil
					searchStartTimes[player] = nil
					actionTimestamps[player] = nil
					
					-- Cancel any active sessions
					for sessionId, session in pairs(activeSessions) do
						if session.PlayerA == player or session.PlayerB == player then
							self:CancelSession(sessionId, "Player disconnected.")
						end
					end
				end
			end
		end
	end)
end

-- Initialize
function MysteryTradeService:Init(deps)
	ClientData = deps.ClientData
	Events = deps.Events
	DBG = deps.DBG
	
	-- Start watchdog
	self:StartWatchdog()
	
	-- Subscribe to cross-server messages
	MessagingService:SubscribeAsync(TOPIC_SEARCH, function(message)
		self:HandleCrossServerSearch(message)
	end)
	
	MessagingService:SubscribeAsync(TOPIC_MATCH_REQUEST, function(message)
		self:HandleMatchRequest(message)
	end)
	
	MessagingService:SubscribeAsync(TOPIC_MATCH_ACK, function(message)
		self:HandleMatchAck(message)
	end)
end

-- Handle cross-server search
function MysteryTradeService:HandleCrossServerSearch(message: any)
	if not message or message.Type ~= "Search" then return end
	if message.ServerId == SERVER_ID then return end -- Ignore our own messages
	
	-- SECURITY: Validate UserId
	if not message.UserId or type(message.UserId) ~= "number" or message.UserId <= 0 then
		DBG:warn("[MysteryTrade] Invalid UserId in cross-server search message:", message.UserId)
		return
	end
	
	-- SECURITY: Validate timestamp to prevent replay attacks
	if not message.Timestamp or type(message.Timestamp) ~= "number" then
		DBG:warn("[MysteryTrade] Missing timestamp in cross-server search message")
		return
	end
	
	local messageAge = os.clock() - message.Timestamp
	if messageAge < 0 or messageAge > CROSS_SERVER_MESSAGE_MAX_AGE then
		DBG:warn("[MysteryTrade] Cross-server search message too old or invalid:", messageAge, "seconds")
		return
	end
	
	-- SECURITY: Validate ServerId format
	if not message.ServerId or type(message.ServerId) ~= "string" or message.ServerId == "" then
		DBG:warn("[MysteryTrade] Invalid ServerId in cross-server search message")
		return
	end
	
	-- Check if we have a player searching
	for i, player in ipairs(searchQueue) do
		if player.Parent and self:GetPlayerState(player) == STATE_SEARCHING then
			-- Found a potential match
			local matchMessage = {
				Type = "MatchRequest",
				UserIdA = message.UserId,
				UserIdB = player.UserId,
				ServerIdA = message.ServerId,
				ServerIdB = SERVER_ID,
				SessionId = string.format("%s_%d_%s", SERVER_ID, os.time(), HttpService:GenerateGUID(false)),
				Timestamp = os.clock(),
			}
			
			pcall(function()
				MessagingService:PublishAsync(TOPIC_MATCH_REQUEST, matchMessage)
			end)
			break
		end
	end
end

-- Handle match request
function MysteryTradeService:HandleMatchRequest(message: any)
	if not message or message.Type ~= "MatchRequest" then return end
	if message.ServerIdB ~= SERVER_ID then return end -- Not for us
	
	-- SECURITY: Validate UserId
	if not message.UserIdB or type(message.UserIdB) ~= "number" or message.UserIdB <= 0 then
		DBG:warn("[MysteryTrade] Invalid UserIdB in match request:", message.UserIdB)
		return
	end
	
	if not message.UserIdA or type(message.UserIdA) ~= "number" or message.UserIdA <= 0 then
		DBG:warn("[MysteryTrade] Invalid UserIdA in match request:", message.UserIdA)
		return
	end
	
	-- SECURITY: Validate timestamp to prevent replay attacks
	if not message.Timestamp or type(message.Timestamp) ~= "number" then
		DBG:warn("[MysteryTrade] Missing timestamp in match request")
		return
	end
	
	local messageAge = os.clock() - message.Timestamp
	if messageAge < 0 or messageAge > CROSS_SERVER_MESSAGE_MAX_AGE then
		DBG:warn("[MysteryTrade] Match request message too old or invalid:", messageAge, "seconds")
		return
	end
	
	-- SECURITY: Validate ServerId format
	if not message.ServerIdA or type(message.ServerIdA) ~= "string" or message.ServerIdA == "" then
		DBG:warn("[MysteryTrade] Invalid ServerIdA in match request")
		return
	end
	
	if not message.SessionId or type(message.SessionId) ~= "string" or message.SessionId == "" then
		DBG:warn("[MysteryTrade] Invalid SessionId in match request")
		return
	end
	
	-- Find the player
	local player = Players:GetPlayerByUserId(message.UserIdB)
	if not player or not player.Parent then return end
	if self:GetPlayerState(player) ~= STATE_SEARCHING then return end
	
	-- Validate both players are still available
	-- (We can't check the other server's player, but we can check ours)
	
	-- Send acknowledgment
	local ackMessage = {
		Type = "MatchAck",
		SessionId = message.SessionId,
		Accepted = true,
		ServerId = SERVER_ID,
		Timestamp = os.clock(),
	}
	
	pcall(function()
		MessagingService:PublishAsync(TOPIC_MATCH_ACK, ackMessage)
	end)
	
	-- Remove from queue
	for i, p in ipairs(searchQueue) do
		if p == player then
			table.remove(searchQueue, i)
			break
		end
	end
	
	-- Create cross-server session (playerB will be UserId only)
	local session = {
		SessionId = message.SessionId,
		PlayerA = nil, -- Will be set by other server
		PlayerB = player,
		State = STATE_SELECTING,
		PhaseStartTime = os.clock(),
		CreatureA = nil,
		CreatureB = nil,
		LocationA = nil,
		LocationB = nil,
		ConfirmedA = false,
		ConfirmedB = false,
		ServerA = message.ServerIdA,
		ServerB = SERVER_ID,
		MatchAcknowledged = true,
		CrossServer = true,
		PartnerUserId = message.UserIdA,
	}
	
	activeSessions[message.SessionId] = session
	self:SetPlayerState(player, STATE_SELECTING)
	
	-- Notify client
	Events.Communicate:FireClient(player, "MysteryTradeFound", {
		SessionId = message.SessionId,
		PartnerName = "Player", -- Will be updated when we get partner info
		PartnerUserId = message.UserIdA,
	})
end

-- Handle match acknowledgment
function MysteryTradeService:HandleMatchAck(message: any)
	if not message or message.Type ~= "MatchAck" then return end
	
	-- SECURITY: Validate SessionId
	if not message.SessionId or type(message.SessionId) ~= "string" or message.SessionId == "" then
		DBG:warn("[MysteryTrade] Invalid SessionId in match ack")
		return
	end
	
	-- SECURITY: Validate timestamp if present
	if message.Timestamp and type(message.Timestamp) == "number" then
		local messageAge = os.clock() - message.Timestamp
		if messageAge < 0 or messageAge > CROSS_SERVER_MESSAGE_MAX_AGE then
			DBG:warn("[MysteryTrade] Match ack message too old or invalid:", messageAge, "seconds")
			return
		end
	end
	
	-- Find session waiting for ack
	for sessionId, session in pairs(activeSessions) do
		if sessionId == message.SessionId and not session.MatchAcknowledged then
			if message.Accepted then
				session.MatchAcknowledged = true
				-- Session is confirmed, both players notified
			else
				-- Match rejected, cancel and continue searching
				self:CancelSession(sessionId, "Match rejected.")
				if session.PlayerA and session.PlayerA.Parent then
					self:TryLocalMatch(session.PlayerA)
				end
			end
			break
		end
	end
end

-- Check if creature is locked (public API)
function MysteryTradeService:IsCreatureLocked(playerId: number, location: any): boolean
	return isCreatureLocked(playerId, location)
end

return MysteryTradeService


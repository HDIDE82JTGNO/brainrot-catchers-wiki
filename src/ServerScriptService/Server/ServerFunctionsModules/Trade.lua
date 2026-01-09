local Trade = {}

function Trade.apply(ServerFunctions, deps)
	local Players = deps.Players
	local HttpService = deps.HttpService
	local ClientData = deps.ClientData
	local Events = deps.Events
	local DBG = deps.DBG
	local activeTradeSessions = deps.ActiveTradeSessions

	local TextService = game:GetService("TextService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	-- Track session membership per-player for quick lookup
	local playerSession: {[Player]: string} = {}
	local sessionOffers: {[string]: {[number]: {[string]: any}}} = {}
	-- Track trading status billboards per player
	local tradingBillboards: {[Player]: BillboardGui} = {}
	local characterRemovedConnections: {[Player]: RBXScriptConnection} = {}

	local function createTradingBillboard(player: Player)
		-- Remove existing billboard if any
		if tradingBillboards[player] then
			tradingBillboards[player]:Destroy()
			tradingBillboards[player] = nil
		end
		
		-- Disconnect previous character removal handler
		if characterRemovedConnections[player] then
			characterRemovedConnections[player]:Disconnect()
			characterRemovedConnections[player] = nil
		end
		
		local character = player.Character
		if not character then
			-- Wait for character to spawn
			character = player.CharacterAdded:Wait()
		end
		
		local head = character:WaitForChild("Head", 5)
		if not head then
			DBG:warn("[Trade] Could not find Head to attach TradingStatus billboard for", player.Name)
			return
		end
		
		-- Get TradingStatus template from ReplicatedStorage
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		if not assets then
			DBG:warn("[Trade] Could not find ReplicatedStorage.Assets")
			return
		end
		
		local template = assets:FindFirstChild("TradingStatus")
		if not template or not template:IsA("BillboardGui") then
			DBG:warn("[Trade] Could not find TradingStatus BillboardGui in ReplicatedStorage.Assets")
			return
		end
		
		-- Clone and attach to head
		local billboard = template:Clone()
		billboard.Adornee = head
		billboard.Parent = head
		tradingBillboards[player] = billboard
		
		-- Clean up billboard if character is removed
		characterRemovedConnections[player] = player.CharacterRemoving:Connect(function()
			if tradingBillboards[player] then
				tradingBillboards[player]:Destroy()
				tradingBillboards[player] = nil
			end
			if characterRemovedConnections[player] then
				characterRemovedConnections[player]:Disconnect()
				characterRemovedConnections[player] = nil
			end
		end)
		
		DBG:print("[Trade] Created TradingStatus billboard for", player.Name)
	end
	
	local function removeTradingBillboard(player: Player)
		if tradingBillboards[player] then
			tradingBillboards[player]:Destroy()
			tradingBillboards[player] = nil
			DBG:print("[Trade] Removed TradingStatus billboard for", player.Name)
		end
		
		-- Disconnect character removal handler
		if characterRemovedConnections[player] then
			characterRemovedConnections[player]:Disconnect()
			characterRemovedConnections[player] = nil
		end
	end

	local function sanitizeMessage(player: Player, message: string): string
		if type(message) ~= "string" or message == "" then
			return ""
		end
		local ok, result = pcall(function()
			return TextService:FilterStringAsync(message, player.UserId)
		end)
		if ok and result then
			local filteredOk, filtered = pcall(function()
				return result:GetNonChatStringForBroadcastAsync()
			end)
			if filteredOk and filtered then
				return filtered
			end
		end
		return message
	end

	local function coalesceBoxes(pd)
		local boxes = (pd and pd.Boxes) or {}
		local out = {}
		for i, entry in ipairs(boxes) do
			local name = (type(entry) == "table" and entry.Name) or ("Box " .. tostring(i))
			local list = (type(entry) == "table" and entry.Creatures) or {}
			table.insert(out, { Name = tostring(name), Creatures = list, Background = entry and entry.Background })
		end
		if #out == 0 then
			table.insert(out, { Name = "Box 1", Creatures = {} })
		end
		return out
	end

	local function filterTradeCreatures(list, maxSlots)
		-- Preserve sparse slots so creatures beyond the first nil are still visible.
		local out = {}
		local limit = maxSlots or 30
		for idx = 1, limit do
			local c = list[idx]
			if c and c.TradeLocked ~= true then
				out[idx] = {
					Name = c.Name,
					Level = c.Level,
					Gender = c.Gender,
					Shiny = c.Shiny,
					HeldItem = c.HeldItem,
					Nickname = c.Nickname,
				}
			else
				out[idx] = nil
			end
		end
		return out
	end

	local function parseBoxKey(boxKey: string)
		if type(boxKey) ~= "string" then
			return nil, nil, nil
		end
		local partyIndex = string.match(boxKey, "^P:(%d+)$")
		if partyIndex then
			local slotIndex = tonumber(partyIndex)
			if not slotIndex then
				return nil, nil, nil
			end
			return "Party", 0, slotIndex
		end
		local boxIndexStr, slotIndexStr = string.match(boxKey, "^(%d+):(%d+)$")
		if not boxIndexStr or not slotIndexStr then
			return nil, nil, nil
		end
		local boxIndex = tonumber(boxIndexStr)
		local slotIndex = tonumber(slotIndexStr)
		if not boxIndex or not slotIndex then
			return nil, nil, nil
		end
		return "Box", boxIndex, slotIndex
	end

	-- Resolve a BoxKey to a server-side creature instance (authoritative).
	-- Returns (creatureTable, errorMessage?)
	local function getCreatureAtBoxKey(player: Player, boxKey: string): (any?, string?)
		local kind, boxIndex, slotIndex = parseBoxKey(boxKey)
		if not kind or not slotIndex then
			return nil, "Invalid offer slot."
		end
		-- Bound indices (party is fixed-size; boxes should be positive indices)
		if kind == "Party" then
			if slotIndex < 1 or slotIndex > 6 then
				return nil, "Invalid offer slot."
			end
		else
			if (boxIndex :: number) < 1 or slotIndex < 1 then
				return nil, "Invalid offer slot."
			end
		end

		local pd = ClientData:Get(player)
		if not pd then
			return nil, "Player data unavailable."
		end
		pd.Party = pd.Party or {}
		pd.Boxes = pd.Boxes or {}

		local creatureArray
		if kind == "Party" then
			creatureArray = pd.Party
		else
			local boxEntry = pd.Boxes[boxIndex]
			if type(boxEntry) ~= "table" then
				return nil, "Invalid offer box."
			end
			-- Support legacy box schema where the box itself is an array of creatures.
			creatureArray = boxEntry.Creatures or boxEntry
			if type(creatureArray) ~= "table" then
				return nil, "Invalid offer box contents."
			end
		end

		local creatureInstance = creatureArray[slotIndex]
		if not creatureInstance then
			return nil, "Offered creature missing."
		end
		if creatureInstance.TradeLocked == true then
			return nil, "One or more creatures are trade locked."
		end
		return creatureInstance, nil
	end

	local function deepCopy(value: any)
		if type(value) ~= "table" then
			return value
		end
		local out = {}
		for k, v in pairs(value) do
			out[k] = deepCopy(v)
		end
		return out
	end

	local function getBadgeCount(player: Player): number
		local pd = ClientData:Get(player)
		return tonumber(pd and pd.Badges) or 0
	end

	local function getTradeLevelCap(badges: number): number?
		if badges >= 8 then
			return nil
		end
		if badges >= 6 then
			return 70
		end
		if badges >= 3 then
			return 45
		end
		if badges >= 1 then
			return 16
		end
		return 0
	end

	local function hasUnlockedTrading(player: Player): (boolean, number, string?)
		local badges = getBadgeCount(player)
		if badges < 1 then
			return false, badges, (player.DisplayName .. " has not unlocked trading yet.")
		end
		return true, badges, nil
	end

	local function sendTradeSystemChat(session, message: string?)
		if not session or type(message) ~= "string" or message == "" then
			return
		end
		for _, plr in ipairs(session.Players or {}) do
			if plr and plr.Parent then
				Events.Communicate:FireClient(plr, "TradeChat", {
					FromUserId = 0,
					FromDisplayName = "System",
					Message = message,
				})
			end
		end
	end

	local function endSession(sessionId: string, reason: string?, notifyMessage: string?, initiator: Player?)
		local session = activeTradeSessions[sessionId]
		if not session then return end
		activeTradeSessions[sessionId] = nil
		sessionOffers[sessionId] = nil
		for _, plr in ipairs(session.Players or {}) do
			playerSession[plr] = nil
			-- Remove trading billboard
			removeTradingBillboard(plr)
			
			-- Restore Chunk from LastChunk when leaving Trade
			local pd = ClientData:Get(plr)
			if pd and pd.Chunk == "Trade" then
				pd.Chunk = pd.LastChunk or "Chunk1"
				DBG:print("[Trade] Restored Chunk to", pd.Chunk, "for", plr.Name)
				if ClientData.UpdateClientData then
					ClientData:UpdateClientData(plr, pd)
				end
			end
			
			if plr and plr.Parent then
				Events.Communicate:FireClient(plr, "TradeCancelled", {
					Reason = reason or "Cancelled",
					Message = notifyMessage,
					InitiatorUserId = initiator and initiator.UserId or nil,
				})
			end
		end
	end

	local function cleanupSession(sessionId: string)
		local session = activeTradeSessions[sessionId]
		if not session then
			return
		end
		activeTradeSessions[sessionId] = nil
		sessionOffers[sessionId] = nil
		for _, plr in ipairs(session.Players or {}) do
			playerSession[plr] = nil
			-- Remove trading billboard
			removeTradingBillboard(plr)
			
			-- Restore Chunk from LastChunk when leaving Trade
			local pd = ClientData:Get(plr)
			if pd and pd.Chunk == "Trade" then
				pd.Chunk = pd.LastChunk or "Chunk1"
				DBG:print("[Trade] Restored Chunk to", pd.Chunk, "for", plr.Name)
				if ClientData.UpdateClientData then
					ClientData:UpdateClientData(plr, pd)
				end
			end
		end
	end

	local function countOffers(offerMap)
		local count = 0
		if type(offerMap) ~= "table" then
			return count
		end
		for _, creature in pairs(offerMap) do
			if creature ~= nil then
				count += 1
			end
		end
		return count
	end

	local function getOfferedCreaturesForPlayer(player: Player, sessionId: string)
		local offers = sessionOffers[sessionId]
		if not offers then
			return nil, "No offers."
		end
		local pd = ClientData:Get(player)
		if not pd then
			return nil, "Player data unavailable."
		end
		pd.Party = pd.Party or {}
		pd.Boxes = pd.Boxes or {}
		local offerMap = offers[player.UserId] or {}
		local list = {}
		for boxKey, entry in pairs(offerMap) do
			if entry ~= nil then
				local kind, boxIndex, slotIndex = parseBoxKey(boxKey)
				if not kind or not slotIndex then
					return nil, "Invalid offer slot."
				end
				local creatureArray
				if kind == "Party" then
					creatureArray = pd.Party
				else
					local boxEntry = pd.Boxes[boxIndex]
					if type(boxEntry) ~= "table" then
						return nil, "Invalid offer box."
					end
					creatureArray = boxEntry.Creatures or boxEntry
					if type(creatureArray) ~= "table" then
						return nil, "Invalid offer box contents."
					end
				end
				local creatureInstance = creatureArray[slotIndex]
				if not creatureInstance then
					return nil, "Offered creature missing."
				end
				table.insert(list, creatureInstance)
			end
		end
		return list, nil
	end

	local function validateTradeLevelCaps(sessionId: string)
		local session = activeTradeSessions[sessionId]
		if not session then
			return true, nil
		end
		local players = session.Players or {}
		local playerA = players[1]
		local playerB = players[2]
		if not (playerA and playerB) then
			return false, "Trade failed: invalid session players."
		end

		local function checkRecipient(recipient: Player, sender: Player)
			local unlocked, badges, unlockMessage = hasUnlockedTrading(recipient)
			if not unlocked then
				return false, unlockMessage
			end
			local cap = getTradeLevelCap(badges)
			if cap == nil then
				return true, nil
			end
			if cap <= 0 then
				return false, (recipient.DisplayName .. " has not unlocked trading yet.")
			end
			local offeredCreatures, err = getOfferedCreaturesForPlayer(sender, sessionId)
			if not offeredCreatures then
				return false, err or "Unable to read offers."
			end
			for _, creature in ipairs(offeredCreatures) do
				if creature and type(creature.Level) == "number" and creature.Level > cap then
					return false, string.format("%s cannot receive this level creature.", recipient.DisplayName)
				end
			end
			return true, nil
		end

		local okA, msgA = checkRecipient(playerA, playerB)
		if not okA then
			return false, msgA
		end
		local okB, msgB = checkRecipient(playerB, playerA)
		if not okB then
			return false, msgB
		end
		return true, nil
	end

	local function finalizeTrade(sessionId: string)
		local session = activeTradeSessions[sessionId]
		if not session then
			DBG:print("[Trade] finalizeTrade aborted: no session", sessionId)
			return
		end
		if session.State == "Finalizing" or session.State == "Completed" then
			DBG:print("[Trade] finalizeTrade skipped: state", session.State)
			return
		end

		session.State = "Finalizing"
		DBG:print("[Trade] finalizeTrade start", sessionId)

		local players = session.Players or {}
		local playerA = players[1]
		local playerB = players[2]
		if not (playerA and playerB) then
			endSession(sessionId, "InvalidSession", "Trade failed: invalid session players.")
			return
		end

		local offers = sessionOffers[sessionId] or {}

		local levelOk, levelMessage = validateTradeLevelCaps(sessionId)
		if not levelOk then
			sendTradeSystemChat(session, levelMessage or "Trade blocked.")
			endSession(sessionId, "LevelRestricted", levelMessage or "Trade blocked.")
			return
		end

		local function placeIncoming(targetPd, incomingList)
			if type(targetPd) ~= "table" then
				return
			end
			targetPd.Party = targetPd.Party or {}
			targetPd.Boxes = targetPd.Boxes or {}

			for _, creature in ipairs(incomingList or {}) do
				local placed = false
				-- Fill empty party slots first (up to 6)
				for i = 1, 6 do
					if targetPd.Party[i] == nil then
						targetPd.Party[i] = deepCopy(creature)
						placed = true
						break
					end
				end

				-- Then fill the next available box slot
				if not placed then
					if #targetPd.Boxes == 0 then
						targetPd.Boxes[1] = { Name = "Box 1", Creatures = {} }
					end
					for bi, boxEntry in ipairs(targetPd.Boxes) do
						if type(boxEntry) ~= "table" then
							boxEntry = { Name = "Box " .. tostring(bi), Creatures = {} }
							targetPd.Boxes[bi] = boxEntry
						end
						local arr = boxEntry.Creatures or boxEntry
						if type(arr) ~= "table" then
							boxEntry.Creatures = {}
							arr = boxEntry.Creatures
						end
						local found = nil
						local maxSlots = math.max(#arr, 30)
						for si = 1, maxSlots do
							if arr[si] == nil then
								found = si
								break
							end
						end
						if not found then
							found = #arr + 1
						end
						if found then
							arr[found] = deepCopy(creature)
							placed = true
							break
						end
					end

					-- If somehow still not placed (no boxes), append a new box
					if not placed then
						local idx = #targetPd.Boxes + 1
						targetPd.Boxes[idx] = { Name = "Box " .. tostring(idx), Creatures = { deepCopy(creature) } }
					end
				end
			end
		end

		local function collect(player: Player)
			local pd = ClientData:Get(player)
			if not pd or type(pd.Boxes) ~= "table" then
				return nil, "Player data unavailable."
			end
			pd.Party = pd.Party or {}
			local offerMap = offers[player.UserId] or {}
			local entries = {}
			local slotList = {}
			local creatureList = {}

			for boxKey, _ in pairs(offerMap) do
				local kind, boxIndex, slotIndex = parseBoxKey(boxKey)
				if not kind or not slotIndex then
					return nil, "Invalid offer slot."
				end
				local creatureArray
				if kind == "Party" then
					creatureArray = pd.Party
				else
					local boxEntry = pd.Boxes[boxIndex]
					if type(boxEntry) ~= "table" then
						return nil, "Invalid offer box."
					end
					creatureArray = boxEntry.Creatures or boxEntry
					if type(creatureArray) ~= "table" then
						return nil, "Invalid offer box contents."
					end
				end
				local creatureInstance = creatureArray[slotIndex]
				if not creatureInstance then
					return nil, "Offered creature missing."
				end
				if creatureInstance.TradeLocked == true then
					return nil, "One or more creatures are trade locked."
				end
				table.insert(entries, {
					kind = kind,
					boxIndex = boxIndex,
					slotIndex = slotIndex,
					array = creatureArray,
					creature = deepCopy(creatureInstance),
				})
			end

			table.sort(entries, function(a, b)
				if a.kind ~= b.kind then
					return a.kind < b.kind
				end
				if a.boxIndex == b.boxIndex then
					return a.slotIndex < b.slotIndex
				end
				return (a.boxIndex or 0) < (b.boxIndex or 0)
			end)

			for _, entry in ipairs(entries) do
				table.insert(slotList, {
					kind = entry.kind,
					boxIndex = entry.boxIndex,
					slotIndex = entry.slotIndex,
					array = entry.array,
				})
				table.insert(creatureList, entry.creature)
			end

			return {
				player = player,
				data = pd,
				slots = slotList,
				creatures = creatureList,
				offerCount = countOffers(offerMap),
			}, nil
		end

		local collectA, errA = collect(playerA)
		local collectB, errB = collect(playerB)

		if not collectA or errA then
			endSession(sessionId, "InvalidOffer", errA or "Trade failed.")
			return
		end
		if not collectB or errB then
			endSession(sessionId, "InvalidOffer", errB or "Trade failed.")
			return
		end

		-- Remove offered creatures from their original locations
		for _, slot in ipairs(collectA.slots) do
			slot.array[slot.slotIndex] = nil
		end
		for _, slot in ipairs(collectB.slots) do
			slot.array[slot.slotIndex] = nil
		end

		-- Deliver incoming creatures: fill party first, then boxes
		placeIncoming(collectA.data, collectB.creatures)
		placeIncoming(collectB.data, collectA.creatures)
		
		-- Mark received creatures as seen for each player (caught/received implies seen)
		local function markCreaturesAsSeen(playerData, creatures)
			if not playerData or type(creatures) ~= "table" then return end
			playerData.SeenCreatures = playerData.SeenCreatures or {}
			for _, creature in ipairs(creatures) do
				if creature and creature.Name and not playerData.SeenCreatures[creature.Name] then
					playerData.SeenCreatures[creature.Name] = true
					DBG:print("[Seen] Marked", creature.Name, "as seen (received via trade)")
				end
			end
		end
		markCreaturesAsSeen(collectA.data, collectB.creatures)
		markCreaturesAsSeen(collectB.data, collectA.creatures)

		if ClientData and ClientData.UpdateClientData then
			pcall(function()
				ClientData:UpdateClientData(playerA, collectA.data)
				ClientData:UpdateClientData(playerB, collectB.data)
			end)
		end

		for _, plr in ipairs(session.Players or {}) do
			if plr and plr.Parent then
				local payload = {
					SessionId = sessionId,
					YourOffer = plr == playerA and collectA.creatures or collectB.creatures,
					PartnerOffer = plr == playerA and collectB.creatures or collectA.creatures,
				}
				DBG:print("[Trade] firing TradeFinalized to", plr.UserId, "offers", collectA.offerCount, collectB.offerCount)
				Events.Communicate:FireClient(plr, "TradeFinalized", payload)
			end
		end

		session.State = "Completed"
		DBG:print("[Trade] finalizeTrade complete", sessionId)
		-- Remove billboards before cleanup
		for _, plr in ipairs(session.Players or {}) do
			removeTradingBillboard(plr)
		end
		cleanupSession(sessionId)
	end

	local function startCooldown(session)
		if not session then return end
		session.CooldownEnd = os.clock() + 5
	end

	local function isCooldownActive(session)
		return session and session.CooldownEnd and session.CooldownEnd > os.clock()
	end

	function ServerFunctions:BeginTradeSession(playerA: Player, playerB: Player)
		if not playerA or not playerB then
			return false, "Invalid players."
		end
		local unlockedA, _, unlockMsgA = hasUnlockedTrading(playerA)
		if not unlockedA then
			return false, unlockMsgA or "Trading is locked."
		end
		local unlockedB, _, unlockMsgB = hasUnlockedTrading(playerB)
		if not unlockedB then
			return false, unlockMsgB or "Trading is locked."
		end
		-- Cancel any existing sessions for these players
		local existingA = playerSession[playerA]
		if existingA then
			endSession(existingA, "Replaced")
		end
		local existingB = playerSession[playerB]
		if existingB then
			endSession(existingB, "Replaced")
		end

		local sessionId = HttpService:GenerateGUID(false)
		local session = {
			Id = sessionId,
			Players = {playerA, playerB},
			Partner = {[playerA] = playerB, [playerB] = playerA},
			Ready = {},
			Confirmed = {},
			State = "Active",
			CooldownEnd = nil,
		}
		activeTradeSessions[sessionId] = session
		playerSession[playerA] = sessionId
		playerSession[playerB] = sessionId
		sessionOffers[sessionId] = {}

		local function fireStart(p: Player, partner: Player)
			if p and p.Parent then
				-- Set Chunk to "Trade" and preserve LastChunk for restoration
				local pd = ClientData:Get(p)
				if pd then
					-- Only update LastChunk if current chunk is a valid Story chunk
					if pd.Chunk and pd.Chunk ~= "Trade" and pd.Chunk ~= "Battle" and pd.Chunk ~= "Title" and pd.Chunk ~= "nil" then
						pd.LastChunk = pd.Chunk
					end
					pd.Chunk = "Trade"
					DBG:print("[Trade] Set Chunk to Trade for", p.Name, "(LastChunk:", pd.LastChunk, ")")
					if ClientData.UpdateClientData then
						ClientData:UpdateClientData(p, pd)
					end
				end
				
				-- Create trading billboard for this player
				createTradingBillboard(p)
				Events.Communicate:FireClient(p, "TradeStarted", {
					SessionId = sessionId,
					PartnerUserId = partner.UserId,
					PartnerDisplayName = partner.DisplayName,
				})
			end
		end
		fireStart(playerA, playerB)
		fireStart(playerB, playerA)
		return sessionId, nil
	end

	function ServerFunctions:TradeSendMessage(player: Player, payload: any)
		local sessionId = type(payload.SessionId) == "string" and payload.SessionId or playerSession[player]
		local msg = sanitizeMessage(player, payload.Message)
		if msg == "" then
			return false
		end
		local sid = playerSession[player]
		if not sid or sid ~= sessionId then
			return false
		end
		local session = activeTradeSessions[sid]
		if not session then
			return false
		end

		for _, plr in ipairs(session.Players or {}) do
			if plr and plr.Parent then
				Events.Communicate:FireClient(plr, "TradeChat", {
					FromUserId = player.UserId,
					FromDisplayName = player.DisplayName,
					Message = msg,
				})
			end
		end
		return true
	end

	function ServerFunctions:TradeFetchBox(player: Player, payload: any)
		local sessionId = type(payload.SessionId) == "string" and payload.SessionId or playerSession[player]
		local sid = playerSession[player]
		if not sid or sid ~= sessionId then
			return false
		end

		local session = activeTradeSessions[sid]
		if not session then
			return false
		end

		local requestedIndex = tonumber(payload.BoxIndex) or 1
		if requestedIndex < 1 then
			requestedIndex = 1
		end

		local pd = ClientData:Get(player)
		if not pd then
			return false
		end

		local boxes = coalesceBoxes(pd)
		local total = (#boxes) + 1 -- include party as first pseudo-box
		if requestedIndex > total then
			requestedIndex = total
		end

		if requestedIndex == 1 then
			local partyList = pd.Party or {}
			local creatures = filterTradeCreatures(partyList, 6)
			return {
				SessionId = sid,
				BoxIndex = requestedIndex,
				TotalBoxes = total,
				BoxName = "Party",
				Background = nil,
				Creatures = creatures,
			}
		end

		local actualBoxIndex = requestedIndex - 1
		local entry = boxes[actualBoxIndex] or boxes[1]
		local creatures = filterTradeCreatures((entry and entry.Creatures) or {}, 30)

		return {
			SessionId = sid,
			BoxIndex = requestedIndex,
			TotalBoxes = total,
			BoxName = entry and entry.Name,
			Background = entry and entry.Background,
			Creatures = creatures,
		}
	end

	function ServerFunctions:TradeSetReady(player: Player, payload: any)
		local sessionId = type(payload.SessionId) == "string" and payload.SessionId or playerSession[player]
		local ready = payload.Ready == true
		local sid = playerSession[player]
		if not sid or sid ~= sessionId then
			return false
		end
		local session = activeTradeSessions[sid]
		if not session then
			return false
		end
		if session.State ~= "Active" then
			return false
		end
		if isCooldownActive(session) then
			return false
		end
		local levelOk, levelMessage = validateTradeLevelCaps(sid)
		if not levelOk then
			sendTradeSystemChat(session, levelMessage or "Trade cannot proceed.")
			return false
		end
		session.Ready = session.Ready or {}
		session.Confirmed = session.Confirmed or {}
		session.Ready[player.UserId] = ready
		-- Reset confirm if un-ready
		if not ready then
			session.Confirmed[player.UserId] = false
		end

		for _, plr in ipairs(session.Players or {}) do
			if plr and plr.Parent then
				Events.Communicate:FireClient(plr, "TradeReady", {
					SessionId = sid,
					UserId = player.UserId,
					Ready = ready,
				})
			end
		end
		return true
	end

	function ServerFunctions:TradeConfirm(player: Player, payload: any)
		local sessionId = type(payload.SessionId) == "string" and payload.SessionId or playerSession[player]
		local sid = playerSession[player]
		if not sid or sid ~= sessionId then
			return { Success = false, Message = "No active trade." }
		end
		local session = activeTradeSessions[sid]
		if not session then
			return { Success = false, Message = "No active trade." }
		end
		if session.State ~= "Active" then
			return { Success = false, Message = "Trade is finalizing." }
		end
		if isCooldownActive(session) then
			return { Success = false, Message = "Please wait before confirming." }
		end
		session.Ready = session.Ready or {}
		if session.Ready[player.UserId] ~= true then
			return { Success = false, Message = "You must be ready first." }
		end
		-- Require partner ready as well
		local partner = session.Partner[player]
		if not partner or session.Ready[partner.UserId] ~= true then
			return { Success = false, Message = "Waiting for the other player to ready." }
		end

		local levelOk, levelMessage = validateTradeLevelCaps(sid)
		if not levelOk then
			sendTradeSystemChat(session, levelMessage or "Trade cannot proceed.")
			return { Success = false, Message = levelMessage or "Trade cannot proceed." }
		end

		session.Confirmed = session.Confirmed or {}
		session.Confirmed[player.UserId] = true

		for _, plr in ipairs(session.Players or {}) do
			if plr and plr.Parent then
				Events.Communicate:FireClient(plr, "TradeConfirm", {
					SessionId = sid,
					UserId = player.UserId,
					Confirmed = true,
				})
			end
		end

		local partnerConfirmed = session.Confirmed[partner.UserId] == true
		if partnerConfirmed then
			session.State = "Locked"
			finalizeTrade(sid)
		end

		return { Success = true }
	end

	function ServerFunctions:TradeCancel(player: Player, payload: any)
		local sessionId = (payload and type(payload.SessionId) == "string") and payload.SessionId or playerSession[player]
		local sid = playerSession[player]
		if not sid or sid ~= sessionId then
			return false
		end
		local session = activeTradeSessions[sid]
		if not session then
			return false
		end
		if session.State ~= "Active" then
			return false
		end
		local reason = (payload and payload.Reason) or "Cancelled"
		local msg = (payload and payload.Message) or (player.DisplayName .. " cancelled the trade.")
		endSession(sid, reason, msg, player)
		return true
	end

	function ServerFunctions:TradeUpdateOffer(player: Player, payload: any)
		local sessionId = type(payload.SessionId) == "string" and payload.SessionId or playerSession[player]
		local sid = playerSession[player]
		if not sid or sid ~= sessionId then
			return false
		end
		local session = activeTradeSessions[sid]
		if not session then
			return false
		end
		if session.State ~= "Active" then
			return false
		end
		local action = payload.Action
		local boxKey = payload.BoxKey
		if type(boxKey) ~= "string" or boxKey == "" then
			return false
		end
		sessionOffers[sid] = sessionOffers[sid] or {}
		local offersForUser = sessionOffers[sid][player.UserId] or {}
		if action == "Add" then
			local count = 0
			for _, v in pairs(offersForUser) do
				if v ~= nil then
					count += 1
				end
			end
			-- Allow re-adding/replacing the same slot without counting against the limit.
			if offersForUser[boxKey] == nil and count >= 9 then
				return false
			end

			-- Server-authoritative offer: resolve creature by BoxKey and snapshot safe fields.
			local creatureInstance, err = getCreatureAtBoxKey(player, boxKey)
			if not creatureInstance then
				return false
			end
			offersForUser[boxKey] = {
				Name = creatureInstance.Name,
				Level = creatureInstance.Level,
				Gender = creatureInstance.Gender,
				Shiny = creatureInstance.Shiny,
				HeldItem = creatureInstance.HeldItem,
				Nickname = creatureInstance.Nickname,
			}
		elseif action == "Remove" then
			offersForUser[boxKey] = nil
		else
			return false
		end
		sessionOffers[sid][player.UserId] = offersForUser

		-- Any offer change resets readiness/confirmation to prevent scams and starts cooldown.
		session.Ready = session.Ready or {}
		session.Confirmed = session.Confirmed or {}
		for _, plr in ipairs(session.Players or {}) do
			if plr then
				session.Ready[plr.UserId] = false
				session.Confirmed[plr.UserId] = false
			end
		end
		startCooldown(session)

		for _, plr in ipairs(session.Players or {}) do
			if plr and plr.Parent then
				Events.Communicate:FireClient(plr, "TradeReady", {
					SessionId = sid,
					UserId = plr.UserId,
					Ready = false,
				})
				Events.Communicate:FireClient(plr, "TradeConfirm", {
					SessionId = sid,
					UserId = plr.UserId,
					Confirmed = false,
				})
				Events.Communicate:FireClient(plr, "TradeOfferUpdated", {
					SessionId = sid,
					UserId = player.UserId,
					Offers = offersForUser,
				})
			end
		end
		return true
	end

	-- Player cleanup on leave
	local function onPlayerRemoving(plr: Player)
		local sid = playerSession[plr]
		-- Always remove billboard when player leaves
		removeTradingBillboard(plr)
		if not sid then return end
		local msg = (plr.DisplayName .. " has left the experience. The trade will now be cancelled.")
		endSession(sid, "PlayerLeft", msg, plr)
	end

	deps.OnPlayerRemovingTrade = onPlayerRemoving
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return Trade

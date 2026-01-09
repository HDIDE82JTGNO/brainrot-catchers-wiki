local BattleRequests = {}

function BattleRequests.apply(ServerFunctions, deps)
	local Players = deps.Players
	local HttpService = deps.HttpService
	local ClientData = deps.ClientData
	local Events = deps.Events
	local DBG = deps.DBG
	local ActiveBattles = deps.ActiveBattles
	local pendingBattleRequests = deps.PendingBattleRequests
	local pendingTradeRequests = deps.PendingTradeRequests
	local BattleSystemHelpers = require(script.Parent:WaitForChild("BattleSystemHelpers"))
	local HeldItemEffects = require(script.Parent.Parent:WaitForChild("Battle"):WaitForChild("HeldItemEffects"))
	local Creatures = require(game:GetService("ReplicatedStorage").Shared.Creatures)

	local function getBadgeCount(player: Player): number
		local pd = ClientData:Get(player)
		return tonumber(pd and pd.Badges) or 0
	end

	local function hasUnlockedFirstBadge(player: Player, featureLabel: string): (boolean, string)
		local badges = getBadgeCount(player)
		if badges < 1 then
			return false, (player.DisplayName .. " has not unlocked " .. featureLabel .. " yet.")
		end
		return true, ""
	end

	local function playerIsBusy(player: Player): (boolean, string)
		local pd = ClientData:Get(player)
		if not pd then
			return true, "Player has not loaded in."
		end
		-- Not past title/continue: Chunk will be nil until they load into the world
		if pd.Chunk == nil then
			return true, "Player has not loaded in."
		end
		-- Title screen / not finished intro
		if pd.Events and pd.Events.FINISHED_TUTORIAL == false then
			return true, "Player has not finished the intro."
		end
		local unlocked, unlockReason = hasUnlockedFirstBadge(player, "battling")
		if not unlocked then
			return true, unlockReason
		end
		-- GameUI not ready yet
		local pg = player:FindFirstChildOfClass("PlayerGui")
		local gameUI = pg and pg:FindFirstChild("GameUI")
		if not gameUI then
			return true, "Player has not loaded in."
		end
		if ActiveBattles[player] or pd.InBattle then
			return true, "Player is currently in a battle."
		end
		if not pd.Party or #pd.Party == 0 then
			return true, "Player has no creatures."
		end
		return false, ""
	end

	local function playerBusyForTrade(player: Player): (boolean, string)
		local pd = ClientData:Get(player)
		if not pd then
			return true, "Player has not loaded in."
		end
		if pd.Chunk == nil then
			return true, "Player has not loaded in."
		end
		if pd.Events and pd.Events.FINISHED_TUTORIAL == false then
			return true, "Player has not finished the intro."
		end
		local unlocked, unlockReason = hasUnlockedFirstBadge(player, "trading")
		if not unlocked then
			return true, unlockReason
		end
		local pg = player:FindFirstChildOfClass("PlayerGui")
		local gameUI = pg and pg:FindFirstChild("GameUI")
		if not gameUI then
			return true, "Player has not loaded in."
		end
		if ActiveBattles[player] or pd.InBattle then
			return true, "Player is currently in a battle."
		end
		return false, ""
	end

	-- Helper to create a PvP-ready copy of the player's lead creature (forced level if needed)
	local function buildPvPCreature(player: Player, levelMode: string?): (any?, number?)
		local pd = ClientData:Get(player)
		if not pd or not pd.Party or #pd.Party == 0 then
			return nil, nil
		end
		local creature, idx = BattleSystemHelpers.FindFirstAliveCreature(pd.Party)
		if not creature then
			return nil, nil
		end

		local forcedLevel = nil
		if levelMode == "50" then
			forcedLevel = 50
		elseif levelMode == "100" then
			forcedLevel = 100
		end
		local level = forcedLevel or creature.Level or 1
		creature = table.clone(creature)
		creature.Level = level
		-- Ensure Type exists on the PvP payload creature (party saves often omit it).
		local creatureDef = creature.Name and Creatures[creature.Name]
		if (creature.Type == nil or creature.Type == "" or (type(creature.Type) == "table" and #creature.Type == 0))
			and creatureDef and creatureDef.Type ~= nil then
			creature.Type = creatureDef.Type
		end

		BattleSystemHelpers.EnsurePartyMoves({creature})
		BattleSystemHelpers.EnsurePartyAbilities({creature})

		local StatCalc = require(game:GetService("ReplicatedStorage").Shared.StatCalc)
		local stats, maxStats = StatCalc.ComputeStats(creature.Name, level, creature.IVs, creature.Nature)
		local currentHPPercent = creature.CurrentHP
		local currentHPAbs: number
		if currentHPPercent == nil then
			currentHPPercent = 100
			currentHPAbs = maxStats.HP
			creature.CurrentHP = currentHPPercent
		else
			currentHPPercent = math.clamp(currentHPPercent, 0, 100)
			currentHPAbs = math.floor(maxStats.HP * (currentHPPercent / 100) + 0.5)
		end
		creature.Stats = stats
		creature.Stats.HP = currentHPAbs
		creature.MaxStats = maxStats
		HeldItemEffects.ApplyStatMods(creature)

		return creature, idx
	end

	local function buildPvpBattlePayload(requester: Player, opponent: Player, levelMode: string)
		local foe, foeIndex = buildPvPCreature(opponent, levelMode)
		if not foe then
			return nil, "Player has no available creatures."
		end
		return {
			FoeCreature = foe,
			FoeCreatureIndex = foeIndex or 1,
			OpponentName = opponent.DisplayName,
			OpponentUserId = opponent.UserId,
			LevelMode = levelMode,
		}, nil
	end

	-- Restore the player's party HP/status from their pre-battle snapshot
	-- without overwriting progression (XP, studs, etc).
	local function restorePendingBattleSnapshot(player: Player)
		local pd = ClientData:Get(player)
		if not pd or type(pd.PendingBattle) ~= "table" then
			return
		end

		local snap = pd.PendingBattle
		if type(snap.Party) == "table" and type(pd.Party) == "table" then
			for i, pre in ipairs(snap.Party) do
				if pre then
					local cur = pd.Party[i]
					if cur then
						-- Restore health/state fields only to avoid losing progression
						cur.Stats = cur.Stats or {}
						if pre.Stats and pre.Stats.HP ~= nil then
							cur.Stats.HP = pre.Stats.HP
						end
						if pre.MaxStats then
							cur.MaxStats = pre.MaxStats
						end
						if pre.CurrentHP ~= nil then
							cur.CurrentHP = pre.CurrentHP
						end
						cur.Status = pre.Status
						cur.VolatileStatus = pre.VolatileStatus
					else
						-- Slot was missing; fall back to restoring full creature snapshot
						pd.Party[i] = table.clone(pre)
					end
				end
			end
			if ClientData.UpdateClientData then
				ClientData:UpdateClientData(player, pd)
			end
		end

		-- Clear snapshot after restoration
		pd.PendingBattle = nil
	end

	function ServerFunctions:SendBattleRequest(fromPlayer: Player, payload: any)
		local targetId = payload.TargetUserId
		local levelMode = tostring(payload.LevelMode or "keep")
		if type(targetId) ~= "number" then
			return "Invalid target."
		end
		if fromPlayer.UserId == targetId then
			return "Cannot battle yourself."
		end

		local targetPlayer = Players:GetPlayerByUserId(targetId)
		if not targetPlayer then
			return "Player not found."
		end

		local busy, reason = playerIsBusy(fromPlayer)
		if busy then
			return reason
		end
		local tBusy, tReason = playerIsBusy(targetPlayer)
		if tBusy then
			return tReason
		end

		local requestId = HttpService:GenerateGUID(false)
		pendingBattleRequests[requestId] = {
			From = fromPlayer,
			Target = targetPlayer,
			LevelMode = levelMode,
		}

		Events.Communicate:FireClient(targetPlayer, "BattleRequestIncoming", {
			RequestId = requestId,
			FromUserId = fromPlayer.UserId,
			FromDisplayName = fromPlayer.DisplayName,
			LevelMode = levelMode,
		})

		return true
	end

	function ServerFunctions:HandleBattleRequestReply(targetPlayer: Player, payload: any)
		local requestId = payload.RequestId
		local accepted = payload.Accepted == true
		if type(requestId) ~= "string" then
			return false
		end
		local pending = pendingBattleRequests[requestId]
		if not pending then
			return false
		end
		if pending.Target ~= targetPlayer then
			return false
		end

		local requester = pending.From
		pendingBattleRequests[requestId] = nil
		-- If declined or invalid, notify requester; on accept we stay silent
		if not accepted then
			if requester and requester.Parent then
				Events.Communicate:FireClient(requester, "BattleRequestReply", {
					Accepted = false,
					FromDisplayName = targetPlayer.DisplayName,
					Message = (targetPlayer.DisplayName .. " has declined your battle request."),
				})
			end
			return true
		end

		-- Re-check availability before starting battle
		local busyReq, reasonReq = playerIsBusy(requester)
		local busyTgt, reasonTgt = playerIsBusy(targetPlayer)
		if busyReq or busyTgt then
			local reason = busyReq and reasonReq or reasonTgt
			-- Inform requester of failure
			if requester and requester.Parent then
				Events.Communicate:FireClient(requester, "BattleRequestReply", {Accepted = false, Message = reason})
			end
			-- Inform target to clear current request
			if targetPlayer and targetPlayer.Parent then
				Events.Communicate:FireClient(targetPlayer, "ClearRequests")
			end
			return false
		end

		-- Build battle data for both players
		local reqBattleData, err1 = buildPvpBattlePayload(requester, targetPlayer, pending.LevelMode)
		local tgtBattleData, err2 = buildPvpBattlePayload(targetPlayer, requester, pending.LevelMode)
		if not reqBattleData or not tgtBattleData then
			local msg = err1 or err2 or "Unable to start battle."
			if requester and requester.Parent then
				Events.Communicate:FireClient(requester, "BattleRequestReply", {Accepted = false, Message = msg})
			end
			if targetPlayer and targetPlayer.Parent then
				Events.Communicate:FireClient(targetPlayer, "ClearRequests")
			end
			return false
		end

		-- Link opponent references
		reqBattleData.OpponentPlayer = targetPlayer
		tgtBattleData.OpponentPlayer = requester

		-- Start PvP for both players
		local okReq = ServerFunctions:StartBattle(requester, "PvP", reqBattleData)
		local okTgt = ServerFunctions:StartBattle(targetPlayer, "PvP", tgtBattleData)
		if not okReq or not okTgt then
			-- If start failed for any, notify requester with generic message
			if requester and requester.Parent then
				Events.Communicate:FireClient(requester, "BattleRequestReply", {Accepted = false, Message = "Unable to start battle."})
			end
			if targetPlayer and targetPlayer.Parent then
				Events.Communicate:FireClient(targetPlayer, "ClearRequests")
			end
		end
		return okReq == true and okTgt == true
	end

	function ServerFunctions:SendTradeRequest(fromPlayer: Player, payload: any)
		local targetId = payload.TargetUserId
		if type(targetId) ~= "number" then
			return "Invalid target."
		end
		if fromPlayer.UserId == targetId then
			return "Cannot trade with yourself."
		end

		local targetPlayer = Players:GetPlayerByUserId(targetId)
		if not targetPlayer then
			return "Player not found."
		end

		local busy, reason = playerBusyForTrade(fromPlayer)
		if busy then
			return reason
		end
		local tBusy, tReason = playerBusyForTrade(targetPlayer)
		if tBusy then
			return tReason
		end

		local requestId = HttpService:GenerateGUID(false)
		pendingTradeRequests[requestId] = {
			From = fromPlayer,
			Target = targetPlayer,
		}

		Events.Communicate:FireClient(targetPlayer, "TradeRequestIncoming", {
			RequestId = requestId,
			FromUserId = fromPlayer.UserId,
			FromDisplayName = fromPlayer.DisplayName,
		})

		return true
	end

	function ServerFunctions:HandleTradeRequestReply(targetPlayer: Player, payload: any)
		local requestId = payload.RequestId
		local accepted = payload.Accepted == true
		if type(requestId) ~= "string" then
			return false
		end
		local pending = pendingTradeRequests[requestId]
		if not pending then
			return false
		end
		if pending.Target ~= targetPlayer then
			return false
		end

		local requester = pending.From
		pendingTradeRequests[requestId] = nil

		if not accepted then
			if requester and requester.Parent then
				Events.Communicate:FireClient(requester, "TradeRequestReply", {
					Accepted = false,
					FromDisplayName = targetPlayer.DisplayName,
					Message = (targetPlayer.DisplayName .. " has declined your trade request."),
				})
			end
			return true
		end

		local sessionId, err = ServerFunctions:BeginTradeSession(requester, targetPlayer)
		if not sessionId then
			if requester and requester.Parent then
				Events.Communicate:FireClient(requester, "TradeRequestReply", {
					Accepted = false,
					FromDisplayName = targetPlayer.DisplayName,
					Message = err or "Unable to start trade.",
				})
			end
			if targetPlayer and targetPlayer.Parent then
				Events.Communicate:FireClient(targetPlayer, "ClearRequests")
			end
			return false
		end

		if requester and requester.Parent then
			Events.Communicate:FireClient(requester, "TradeRequestReply", {
				Accepted = true,
				FromDisplayName = targetPlayer.DisplayName,
				SessionId = sessionId,
			})
		end
		return true
	end

	deps.RestorePendingBattleSnapshot = restorePendingBattleSnapshot
end

return BattleRequests


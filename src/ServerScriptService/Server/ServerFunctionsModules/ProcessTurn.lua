local ProcessTurn = {}

local ActiveBattles
local BattleSystem
local ClientData
local DBG
local _pvpTurnBuffer
local _pvpResolving
local _pvpKey
local _pendingMoveReplace
local _logBattleMessages
local _restorePendingBattleSnapshot
local _saveNow
local FindFirstAliveCreature
local ChallengesSystem

function ProcessTurn.apply(ServerFunctions, deps)
	ActiveBattles = deps.ActiveBattles
	BattleSystem = deps.BattleSystem
	ClientData = deps.ClientData
	DBG = deps.DBG
	_pvpTurnBuffer = deps.PvPTurnBuffer
	_pvpResolving = deps.PvPResolving
	_pvpKey = deps.PvPKey
	_pendingMoveReplace = deps.PendingMoveReplace
	_logBattleMessages = deps.LogBattleMessages
	_restorePendingBattleSnapshot = deps.RestorePendingBattleSnapshot
	_saveNow = deps.SaveNow or deps.saveNow
	FindFirstAliveCreature = deps.FindFirstAliveCreature
	ChallengesSystem = deps.ChallengesSystem

	function ServerFunctions:ProcessTurn(Player)
		local battle = ActiveBattles[Player]
		if not battle then
			DBG:warn("No active battle found for player:", Player.Name)
			return false
		end
		-- PvP: buffer actions and resolve only when both sides submitted
		if battle.Type == "PvP" then
			DBG:print("[PvP] Processing turn for player:", Player.Name)
			if not battle.PlayerAction then
				DBG:warn("No player action found for PvP turn processing")
				return false
			end
			DBG:print("[PvP] Player action type:", battle.PlayerAction.Type, "Move:", battle.PlayerAction.Move)

			-- SECURITY: Validate forced switch - player MUST switch if their creature is fainted
			if battle.SwitchMode == "Forced" then
				if battle.PlayerAction.Type ~= "Switch" then
					DBG:warn("[PvP] Player", Player.Name, "attempted non-switch action during forced switch")
					-- Don't reject - just clear the invalid action and wait
					battle.PlayerAction = nil
					return false
				end
				-- Clear switch mode now that valid switch is submitted
				battle.SwitchMode = nil
				DBG:print("[PvP] Forced switch action accepted for", Player.Name)
			end

			local opponent = battle.OpponentPlayer
			if not opponent or not opponent.Parent then
				DBG:warn("[PvP] No opponent or opponent left - ending battle as win")
				-- Get opponent name before they disconnect (may be nil)
				local opponentName = opponent and (opponent.DisplayName or opponent.Name) or "Opponent"
				-- Send battle message to player before ending
				local Events = game.ReplicatedStorage.Events
				if Events and Events.Communicate then
					local hpData = {
						Player = battle.PlayerCreature.Stats.HP,
						PlayerMax = battle.PlayerCreature.MaxStats.HP,
						Enemy = battle.FoeCreature and battle.FoeCreature.Stats.HP or 0,
						EnemyMax = battle.FoeCreature and battle.FoeCreature.MaxStats.HP or 0,
					}
					local turnResult = {
						Friendly = {
							{ Type = "Message", Message = opponentName .. " has left the match. The battle will now end.", IsPlayer = true }
						},
						Enemy = {},
						HP = hpData,
						PlayerCreature = battle.PlayerCreature,
						FoeCreature = battle.FoeCreature,
						TurnId = (battle.TurnId or 0) + 1,
						BattleEnd = true,
					}
					DBG:print("[PvP] Sending opponent left message to", Player.Name)
					Events.Communicate:FireClient(Player, "TurnResult", turnResult)
					-- Wait a moment for message to display before ending battle
					task.wait(2)
				end
				ServerFunctions:EndBattle(Player, "Win")
				return false
			end
			DBG:print("[PvP] Opponent:", opponent.Name, "UserId:", opponent.UserId)
			local oppBattle = ActiveBattles[opponent]
			if not oppBattle then
				DBG:warn("[PvP] No active battle for opponent - ending as win")
				-- Get opponent name before ending
				local opponentName = opponent and (opponent.DisplayName or opponent.Name) or "Opponent"
				-- Send battle message to player before ending
				local Events = game.ReplicatedStorage.Events
				if Events and Events.Communicate then
					local hpData = {
						Player = battle.PlayerCreature.Stats.HP,
						PlayerMax = battle.PlayerCreature.MaxStats.HP,
						Enemy = battle.FoeCreature and battle.FoeCreature.Stats.HP or 0,
						EnemyMax = battle.FoeCreature and battle.FoeCreature.MaxStats.HP or 0,
					}
					local turnResult = {
						Friendly = {
							{ Type = "Message", Message = opponentName .. " has left the match. The battle will now end.", IsPlayer = true }
						},
						Enemy = {},
						HP = hpData,
						PlayerCreature = battle.PlayerCreature,
						FoeCreature = battle.FoeCreature,
						TurnId = (battle.TurnId or 0) + 1,
						BattleEnd = true,
					}
					DBG:print("[PvP] Sending opponent left message to", Player.Name)
					Events.Communicate:FireClient(Player, "TurnResult", turnResult)
					-- Wait a moment for message to display before ending battle
					task.wait(2)
				end
				ServerFunctions:EndBattle(Player, "Win")
				return false
			end
			local key = _pvpKey(Player, opponent)
			DBG:print("[PvP] Buffer key:", key, "| Player.UserId:", Player.UserId, "| opponent.UserId:", opponent.UserId)
			local bufferExisted = _pvpTurnBuffer[key] ~= nil
			_pvpTurnBuffer[key] = _pvpTurnBuffer[key] or { TurnId = battle.TurnId or 0, Actions = {} }
			local buf = _pvpTurnBuffer[key]
			DBG:print("[PvP] Buffer existed:", bufferExisted, "| Buffer TurnId:", buf.TurnId, "| Battle TurnId:", battle.TurnId)
			-- Debug: show all actions currently in buffer
			local actionCount = 0
			for userId, _ in pairs(buf.Actions) do
				actionCount = actionCount + 1
				DBG:print("[PvP] Buffer contains action from UserId:", userId)
			end
			DBG:print("[PvP] Total actions in buffer:", actionCount)
			-- Reject stale TurnId
			if (battle.TurnId or 0) ~= (buf.TurnId or 0) then
				DBG:print("[PvP] TurnId mismatch - resetting buffer. Battle:", battle.TurnId, "Buffer:", buf.TurnId)
				buf.TurnId = battle.TurnId or 0
				buf.Actions = {}
			end
			buf.Actions[tostring(Player.UserId)] = battle.PlayerAction
			DBG:print("[PvP] Stored action for UserId:", Player.UserId)
			-- Expose pending buffer on each battle for visibility/debugging
			local snapshotActions = table.clone(buf.Actions)
			battle.PendingActions = { TurnId = buf.TurnId, Actions = snapshotActions }
			oppBattle.PendingActions = { TurnId = buf.TurnId, Actions = table.clone(snapshotActions) }
			
			-- FORCED SWITCH: If the opponent has SwitchMode = "Forced" and just submitted their switch,
			-- OR if this player just submitted a forced switch, resolve immediately without waiting
			-- for the other player's action (they are waiting for the switch)
			local thisIsPlayerForcedSwitch = battle.PlayerAction.Type == "Switch" and battle.PlayerCreature.Stats.HP <= 0
			local oppIsWaitingForUs = oppBattle.SwitchMode ~= "Forced" and battle.PlayerCreature.Stats.HP <= 0
			
			DBG:print("[PvP] Forced switch check - ActionType:", battle.PlayerAction.Type, "PlayerHP:", battle.PlayerCreature.Stats.HP)
			DBG:print("[PvP] Forced switch check - thisIsForcedSwitch:", thisIsPlayerForcedSwitch, "oppIsWaiting:", oppIsWaitingForUs, "oppSwitchMode:", oppBattle.SwitchMode)
			
			if thisIsPlayerForcedSwitch and oppIsWaitingForUs then
				DBG:print("[PvP] Forced switch detected - resolving immediately without waiting for opponent")
				-- Prevent double-resolution
				if _pvpResolving[key] == (battle.TurnId or 0) then
					DBG:print("[PvP] Resolution already in progress for TurnId:", battle.TurnId, "key:", key)
					return true
				end
				_pvpResolving[key] = battle.TurnId or 0
				
				-- Execute just the switch action
				local switchResult = BattleSystem.ExecuteSwitchAction(Player, battle.PlayerAction, battle, true)
				
				-- Build turn results for both players with just the switch
				local playerFriendly = {}
				local playerEnemy = {}
				local oppFriendly = {}
				local oppEnemy = {}
				local executionOrder = {}
				
				-- Add switch steps to execution order
				if type(switchResult) == "table" then
					if switchResult[1] then
						-- Multiple steps (recall + sendout)
						for _, step in ipairs(switchResult) do
							local stepClone = table.clone(step)
							stepClone.ExecOrder = #executionOrder + 1
							table.insert(executionOrder, {step = stepClone, isPlayerActor = true})
							table.insert(playerFriendly, stepClone)
							-- For opponent, flip IsPlayer and add to their enemy list
							local oppStep = table.clone(step)
							oppStep.ExecOrder = stepClone.ExecOrder
							oppStep.IsPlayer = false
							table.insert(oppEnemy, oppStep)
						end
					else
						-- Single step
						local stepClone = table.clone(switchResult)
						stepClone.ExecOrder = 1
						table.insert(executionOrder, {step = stepClone, isPlayerActor = true})
						table.insert(playerFriendly, stepClone)
						local oppStep = table.clone(switchResult)
						oppStep.ExecOrder = 1
						oppStep.IsPlayer = false
						table.insert(oppEnemy, oppStep)
					end
				end
				
				-- HP data after switch - CRITICAL: Ensure HP values are synchronized
				-- After switch, battle.PlayerCreature = new creature, oppBattle.FoeCreature should match
				-- Explicitly sync HP values to prevent desync
				if oppBattle.FoeCreature and battle.PlayerCreature then
					oppBattle.FoeCreature.Stats = oppBattle.FoeCreature.Stats or {}
					oppBattle.FoeCreature.Stats.HP = battle.PlayerCreature.Stats.HP
					oppBattle.FoeCreature.MaxStats = oppBattle.FoeCreature.MaxStats or {}
					oppBattle.FoeCreature.MaxStats.HP = battle.PlayerCreature.MaxStats.HP
				end
				if oppBattle.PlayerCreature and battle.FoeCreature then
					oppBattle.PlayerCreature.Stats = oppBattle.PlayerCreature.Stats or {}
					oppBattle.PlayerCreature.Stats.HP = battle.FoeCreature.Stats.HP
					oppBattle.PlayerCreature.MaxStats = oppBattle.PlayerCreature.MaxStats or {}
					oppBattle.PlayerCreature.MaxStats.HP = battle.FoeCreature.MaxStats.HP
				end
				
				local hpData = {
					Player = battle.PlayerCreature.Stats.HP,
					PlayerMax = battle.PlayerCreature.MaxStats.HP,
					Enemy = battle.FoeCreature.Stats.HP,
					EnemyMax = battle.FoeCreature.MaxStats.HP,
				}
				local oppHP = {
					Player = oppBattle.PlayerCreature.Stats.HP,
					PlayerMax = oppBattle.PlayerCreature.MaxStats.HP,
					Enemy = oppBattle.FoeCreature.Stats.HP,
					EnemyMax = oppBattle.FoeCreature.MaxStats.HP,
				}
				
				-- VALIDATION: Ensure HP values are synchronized (opponent's Player = our Enemy, opponent's Enemy = our Player)
				if oppHP.Player ~= hpData.Enemy or oppHP.Enemy ~= hpData.Player then
					DBG:warn("[PvP][ForcedSwitch] HP sync mismatch detected - forcing sync")
					DBG:warn("[PvP][ForcedSwitch] hpData:", hpData.Player, hpData.Enemy, "oppHP:", oppHP.Player, oppHP.Enemy)
					oppHP.Player = hpData.Enemy
					oppHP.PlayerMax = hpData.EnemyMax
					oppHP.Enemy = hpData.Player
					oppHP.EnemyMax = hpData.PlayerMax
				end
				
				-- Advance TurnId
				local nextTurnId = (battle.TurnId or 0) + 1
				ActiveBattles[Player].TurnId = nextTurnId
				ActiveBattles[opponent].TurnId = nextTurnId
				
				-- Clone creature data
				local playerCreatureClone = table.clone(battle.PlayerCreature)
				local foeCreatureClone = table.clone(battle.FoeCreature)
				local oppPlayerCreatureClone = table.clone(oppBattle.PlayerCreature)
				local oppFoeCreatureClone = table.clone(oppBattle.FoeCreature)
				
				local playerResult = {
					Friendly = playerFriendly,
					Enemy = playerEnemy,
					HP = hpData,
					PlayerCreature = playerCreatureClone,
					FoeCreature = foeCreatureClone,
					TurnId = nextTurnId,
					SwitchMode = nil, -- Switch complete, clear mode
				}
				
				local oppResult = {
					Friendly = oppFriendly,
					Enemy = oppEnemy,
					HP = oppHP,
					PlayerCreature = oppPlayerCreatureClone,
					FoeCreature = oppFoeCreatureClone,
					TurnId = nextTurnId,
					SwitchMode = nil, -- Opponent's wait is over
				}
				
				DBG:print("[PvP] Sending forced switch results to both players")
				local Events = game.ReplicatedStorage.Events
				Events.Communicate:FireClient(Player, "TurnResult", playerResult)
				Events.Communicate:FireClient(opponent, "TurnResult", oppResult)
				
				-- CRITICAL: Clear player actions and pending state for next turn (match normal resolution cleanup)
				battle.PlayerAction = nil
				oppBattle.PlayerAction = nil
				battle.PendingActions = nil
				oppBattle.PendingActions = nil
				-- Ensure SwitchMode is cleared for both
				battle.SwitchMode = nil
				oppBattle.SwitchMode = nil
				
				-- Update TurnId on the battle objects as well (critical for next turn)
				battle.TurnId = nextTurnId
				oppBattle.TurnId = nextTurnId
				
				-- Replace the buffer entirely (match normal resolution)
				_pvpTurnBuffer[key] = { TurnId = nextTurnId, Actions = {} }
				_pvpResolving[key] = nil
				
				DBG:print("[PvP] Forced switch complete - cleared actions and buffer for TurnId:", nextTurnId)
				DBG:print("[PvP] Both battles TurnId updated to:", nextTurnId)
				DBG:print("[PvP] Buffer reset to TurnId:", nextTurnId)
				
				return true
			end
			
			-- If opponent already acted for this turn, resolve
			local oppAction = buf.Actions[tostring(opponent.UserId)]
			DBG:print("[PvP] Looking for opponent action under UserId:", opponent.UserId, "Found:", oppAction ~= nil)
			if oppAction then
				-- Prevent double-resolution if both players trigger ProcessTurn concurrently
				if _pvpResolving[key] == (battle.TurnId or 0) then
					DBG:print("[PvP] Resolution already in progress for TurnId:", battle.TurnId, "key:", key)
					return true
				end
				_pvpResolving[key] = battle.TurnId or 0
				local okResolve, errResolve = pcall(function()
					DBG:print("[PvP] === BOTH PLAYERS READY - RESOLVING TURN ===")
					DBG:print("[PvP] Player action:", battle.PlayerAction.Move, "Opponent action:", oppAction.Move)
					-- Determine turn order using player + opponent actions
					local turnOrder = BattleSystem.DetermineTurnOrder(battle, battle.PlayerAction, oppAction)
					local friendlyActions = {}
					local enemyActions = {}
					-- CRITICAL: Track execution order to maintain sync between both players
					-- This list preserves the order actions were executed, regardless of which side they belong to
					local executionOrder: {{step: any, isPlayerActor: boolean}} = {}
					-- Capture a pre-turn HP snapshot to guard against accidental zeroing
					local preTurnHp = {
						Player = battle.PlayerCreature.Stats.HP,
						PlayerMax = battle.PlayerCreature.MaxStats.HP,
						Enemy = battle.FoeCreature.Stats.HP,
						EnemyMax = battle.FoeCreature.MaxStats.HP,
					}
					-- hpData will be replaced with post-turn values before sending to clients
					local hpData = preTurnHp
					local playerFaintedThisTurn = false
					local foeFaintedThisTurn = false
					-- Track WHO fainted FIRST to determine winner (nil = no faint yet)
					local firstFaintIsPlayer

					local function _applyCurrentHP(creature)
						if not creature or not creature.MaxStats or not creature.Stats or not creature.Stats.HP then
							return
						end
						local maxHP = creature.MaxStats.HP
						local hp = creature.Stats.HP
						creature.CurrentHP = math.clamp(math.floor((hp / math.max(1, maxHP)) * 100 + 0.5), 0, 100)
					end

					local function _mirrorState()
						-- Sync opponent's view of HP/state to keep both battle tables aligned
						if oppBattle and oppBattle.PlayerCreature and battle.FoeCreature then
							oppBattle.PlayerCreature.Stats = oppBattle.PlayerCreature.Stats or {}
							oppBattle.PlayerCreature.Stats.HP = battle.FoeCreature.Stats.HP
							oppBattle.PlayerCreature.MaxStats = oppBattle.PlayerCreature.MaxStats or battle.FoeCreature.MaxStats
							_applyCurrentHP(oppBattle.PlayerCreature)
						end
						if oppBattle and oppBattle.FoeCreature and battle.PlayerCreature then
							oppBattle.FoeCreature.Stats = oppBattle.FoeCreature.Stats or {}
							oppBattle.FoeCreature.Stats.HP = battle.PlayerCreature.Stats.HP
							oppBattle.FoeCreature.MaxStats = oppBattle.FoeCreature.MaxStats or battle.PlayerCreature.MaxStats
							_applyCurrentHP(oppBattle.FoeCreature)
						end
					end

					-- Mirror the authoritative in-battle HP back into each owner's saved party slot.
					-- This prevents defeat detection from reading stale HP that still looks alive.
					local function _syncPartyHpToSave(owner: Player?, creature: any?, slotIndex: number?)
						if not owner or not owner.Parent then
							return
						end
						if type(slotIndex) ~= "number" then
							return
						end
						if not creature or not creature.Stats then
							return
						end

						local pd = ClientData:Get(owner)
						if not pd or not pd.Party or not pd.Party[slotIndex] then
							return
						end
						local slot = pd.Party[slotIndex]

						slot.Stats = slot.Stats or {}
						slot.Stats.HP = creature.Stats.HP or 0
						slot.MaxStats = slot.MaxStats or creature.MaxStats

						local maxHP = (slot.MaxStats and slot.MaxStats.HP) or (creature.MaxStats and creature.MaxStats.HP)
						if maxHP then
							slot.CurrentHP = math.clamp(math.floor(((slot.Stats.HP or 0) / math.max(1, maxHP)) * 100 + 0.5), 0, 100)
						end

						if ClientData.UpdateClientData then
							ClientData:UpdateClientData(owner, pd)
						end
					end

					local playedActions = {}

					-- Safety: ensure PvP battle creatures do NOT share Stats/MaxStats tables (can happen if payloads alias)
					local function detachStats(creature)
						if creature then
							if creature.Stats then
								creature.Stats = table.clone(creature.Stats)
							end
							if creature.MaxStats then
								creature.MaxStats = table.clone(creature.MaxStats)
							end
						end
					end
					if battle.Type == "PvP" then
						if battle.PlayerCreature and battle.FoeCreature and battle.PlayerCreature.Stats == battle.FoeCreature.Stats then
							detachStats(battle.PlayerCreature)
							detachStats(battle.FoeCreature)
						end
						if oppBattle then
							-- Player's foe is opponent's player creature
							if battle.FoeCreature and oppBattle.PlayerCreature and battle.FoeCreature.Stats == oppBattle.PlayerCreature.Stats then
								detachStats(battle.FoeCreature)
								detachStats(oppBattle.PlayerCreature)
							end
							-- Player's creature is opponent's foe creature
							if battle.PlayerCreature and oppBattle.FoeCreature and battle.PlayerCreature.Stats == oppBattle.FoeCreature.Stats then
								detachStats(battle.PlayerCreature)
								detachStats(oppBattle.FoeCreature)
							end
						end
					end

					DBG:print("[PvP] Turn order count:", #turnOrder)
					DBG:print("[PvP] Initial HP - Player:", battle.PlayerCreature.Stats.HP, "Enemy:", battle.FoeCreature.Stats.HP)
					for i, action in ipairs(turnOrder) do
						DBG:print("[PvP] Executing action", i, "- IsPlayer:", action.IsPlayer, "Type:", action.Action and action.Action.Type, "Move:", action.Action and action.Action.Move)
						if playerFaintedThisTurn or foeFaintedThisTurn then
							DBG:print("[PvP] Skipping action", i, "due to faint - playerFainted:", playerFaintedThisTurn, "foeFainted:", foeFaintedThisTurn)
							break
						end
						-- Skip an action if that actor is already fainted before it starts (simultaneous KOs)
						if action.IsPlayer == true and (battle.PlayerCreature.Stats.HP <= 0) then
							DBG:print("[PvP] Skipping action", i, "because player actor already fainted")
							playerFaintedThisTurn = true
							break
						elseif action.IsPlayer == false and (battle.FoeCreature.Stats.HP <= 0) then
							DBG:print("[PvP] Skipping action", i, "because foe actor already fainted")
							foeFaintedThisTurn = true
							break
						end
						-- Capture HP before action to derive deltas
						local prePlayerHP = battle.PlayerCreature.Stats.HP
						local preFoeHP = battle.FoeCreature.Stats.HP
						DBG:print("[PvP] Pre-action HP - Player:", prePlayerHP, "Enemy:", preFoeHP)
						local result = BattleSystem.ExecuteAction(Player, action, battle)
						DBG:print("[PvP] Post-action HP - Player:", battle.PlayerCreature.Stats.HP, "Enemy:", battle.FoeCreature.Stats.HP)
						DBG:print("[PvP] Action result type:", type(result), "is array:", type(result) == "table" and result[1] ~= nil)
						local actName = (action.Action and action.Action.Move) or action.Actor or "Action"
						table.insert(playedActions, { Name = actName, IsPlayer = action.IsPlayer == true })

						-- Resolve which side actually fainted; do not trust missing IsPlayer flags
						-- because nil was previously treated as "foe fainted", causing false draws.
						local function resolveFaintTarget(step, actorIsPlayer: boolean)
							-- 1) Explicit flag wins
							if type(step.IsPlayer) == "boolean" then
								return step.IsPlayer
							end

							-- 2) Match creature name to active creatures
							local creatureName = step.Creature
							if type(creatureName) == "string" then
								local playerName = (battle.PlayerCreature and (battle.PlayerCreature.Nickname or battle.PlayerCreature.Name)) or ""
								local foeName = (battle.FoeCreature and (battle.FoeCreature.Nickname or battle.FoeCreature.Name)) or ""
								if creatureName == playerName then
									return true
								elseif creatureName == foeName then
									return false
								end
							end

							-- 3) Use HP transitions for this action to determine who hit zero
							local playerKO = (prePlayerHP > 0) and (battle.PlayerCreature.Stats.HP <= 0)
							local foeKO = (preFoeHP > 0) and (battle.FoeCreature.Stats.HP <= 0)
							if playerKO ~= foeKO then
								return playerKO
							end

							-- 4) Fallback: assume faint belongs to the target (opposite the actor)
							return not actorIsPlayer
						end

						local function addResult(step, isPlayerSide)
							-- CRITICAL: Clone step before mutating to prevent affecting both players' results
							local stepClone = table.clone(step)
							
							-- CRITICAL FIX: Set IsPlayer flag for ALL step types to ensure correct
							-- animation targeting in PvP. Without this, Move/Damage steps have nil IsPlayer
							-- which causes the client to misidentify attacker/defender models.
							-- Note: Faint steps will override this below with resolved ownership.
							if stepClone.IsPlayer == nil then
								stepClone.IsPlayer = isPlayerSide
								DBG:print("[PvP] Setting IsPlayer for step Type:", stepClone.Type, "isPlayerSide:", isPlayerSide)
							end
							
							-- CRITICAL: Track execution order for proper synchronization
							-- Store the step with its actor information to maintain order
							table.insert(executionOrder, {step = stepClone, isPlayerActor = isPlayerSide})
							
							-- Resolve faint ownership before mutating state or sending to client
							if stepClone.Type == "Faint" then
								local faintIsPlayer = resolveFaintTarget(stepClone, isPlayerSide)
								stepClone.IsPlayer = faintIsPlayer

								-- Track WHO fainted FIRST to determine winner in "both out" scenarios
								-- Only record the first faint; subsequent faints are secondary
								if firstFaintIsPlayer == nil then
									firstFaintIsPlayer = faintIsPlayer
									DBG:print("[PvP][FirstFaint] First faint recorded - IsPlayer:", faintIsPlayer)
								end

								-- Keep authoritative HP at 0 when a faint is produced (prevents later fallback from reviving)
								if faintIsPlayer then
									if battle.PlayerCreature and battle.PlayerCreature.Stats then
										battle.PlayerCreature.Stats.HP = 0
									end
									-- Clear status conditions when creature faints (matches non-PvP behavior)
									local StatusModule = require(game:GetService("ReplicatedStorage").Shared.Status)
									if StatusModule and StatusModule.Remove then
										StatusModule.Remove(battle.PlayerCreature)
									else
										battle.PlayerCreature.Status = nil
									end
									battle.PlayerCreature.VolatileStatus = nil
									-- Also clear status in party data
									local pd = ClientData:Get(Player)
									if pd and pd.Party and battle.PlayerCreatureIndex then
										local partyCreature = pd.Party[battle.PlayerCreatureIndex]
										if partyCreature then
											if StatusModule and StatusModule.Remove then
												StatusModule.Remove(partyCreature)
											else
												partyCreature.Status = nil
											end
											partyCreature.VolatileStatus = nil
										end
									end
									playerFaintedThisTurn = true
								else
									if battle.FoeCreature and battle.FoeCreature.Stats then
										battle.FoeCreature.Stats.HP = 0
									end
									-- Clear status conditions when foe creature faints (matches non-PvP behavior)
									local StatusModule = require(game:GetService("ReplicatedStorage").Shared.Status)
									if StatusModule and StatusModule.Remove then
										StatusModule.Remove(battle.FoeCreature)
									else
										battle.FoeCreature.Status = nil
									end
									battle.FoeCreature.VolatileStatus = nil
									-- Also clear status in opponent's party data
									local oppPd = ClientData:Get(opponent)
									if oppPd and oppPd.Party and oppBattle and oppBattle.PlayerCreatureIndex then
										local oppPartyCreature = oppPd.Party[oppBattle.PlayerCreatureIndex]
										if oppPartyCreature then
											if StatusModule and StatusModule.Remove then
												StatusModule.Remove(oppPartyCreature)
											else
												oppPartyCreature.Status = nil
											end
											oppPartyCreature.VolatileStatus = nil
										end
									end
									foeFaintedThisTurn = true
								end
							end

							if isPlayerSide then
								table.insert(friendlyActions, stepClone)
							else
								table.insert(enemyActions, stepClone)
							end
						end
						local function ensureHpDeltaAndDamage(stepList, isPlayerActor)
							-- After action resolved, derive HPDelta and Damage if missing
							local postPlayerHP = battle.PlayerCreature.Stats.HP
							local postFoeHP = battle.FoeCreature.Stats.HP
							local deltaEnemy = postFoeHP - preFoeHP
							local deltaPlayer = postPlayerHP - prePlayerHP
							local hasFaintStep = false
							for _, s in ipairs(stepList) do
								if s.Type == "Faint" then
									hasFaintStep = true
									break
								end
							end
							for _, s in ipairs(stepList) do
								if s.Type == "Move" then
									s.HPDelta = s.HPDelta or (isPlayerActor and { Enemy = deltaEnemy } or { Player = deltaPlayer })
								end
							end
							-- If damage occurred and no explicit Damage step exists, add one
							local function hasDamageStep(list)
								for _, s in ipairs(list) do
									if s.Type == "Damage" then
										return true
									end
								end
								return false
							end
							local tookDamage = (deltaEnemy < 0) or (deltaPlayer < 0)
							if tookDamage and not hasDamageStep(stepList) then
								if deltaEnemy < 0 then
									table.insert(stepList, { Type = "Damage", Effectiveness = "Normal", IsPlayer = false, NewHP = postFoeHP })
								elseif deltaPlayer < 0 then
									table.insert(stepList, { Type = "Damage", Effectiveness = "Normal", IsPlayer = true, NewHP = postPlayerHP })
								end
							end
						end
						if type(result) == "table" and result[1] then
							for _, step in ipairs(result) do
								addResult(step, action.IsPlayer)
							end
							ensureHpDeltaAndDamage(action.IsPlayer and friendlyActions or enemyActions, action.IsPlayer)
						elseif result then
							addResult(result, action.IsPlayer)
							if action.IsPlayer then
								ensureHpDeltaAndDamage(friendlyActions, true)
							else
								ensureHpDeltaAndDamage(enemyActions, false)
							end
						end
						_mirrorState()
					end

					-- Ensure there is at least one visible message per side if no steps were produced
					local function ensureMessages(actionsList, isPlayerSide)
						if #actionsList > 0 then
							return
						end
						for _, info in ipairs(playedActions) do
							if info.IsPlayer == isPlayerSide then
								local msg = string.format("%s used %s!", isPlayerSide and "You" or "Foe", info.Name)
								DBG:print("[PvP][Message][Ensure] ->", isPlayerSide and "Friendly" or "Enemy", "|", msg)
								local messageStep = { Type = "Message", Message = msg, IsPlayer = isPlayerSide }
								table.insert(actionsList, messageStep)
								-- Also add to execution order to maintain sync
								table.insert(executionOrder, {step = messageStep, isPlayerActor = isPlayerSide})
								return
							end
						end
					end
					ensureMessages(friendlyActions, true)
					ensureMessages(enemyActions, false)

					-- Clamp fainted creatures to 0 HP/CurrentHP before snapshot
					local function clampFaint(creature)
						if creature and creature.Stats then
							if creature.Stats.HP <= 0 then
								creature.Stats.HP = 0
								creature.CurrentHP = 0
							end
						end
					end
					clampFaint(battle.PlayerCreature)
					clampFaint(battle.FoeCreature)

					-- Refresh HP snapshot after actions
					hpData = {
						Player = math.max(0, battle.PlayerCreature.Stats.HP),
						PlayerMax = battle.PlayerCreature.MaxStats.HP,
						Enemy = math.max(0, battle.FoeCreature.Stats.HP),
						EnemyMax = battle.FoeCreature.MaxStats.HP,
					}
					_applyCurrentHP(battle.PlayerCreature)
					_applyCurrentHP(battle.FoeCreature)
					_mirrorState()
					
					-- End-of-turn effects (skip if battle ends due to faint)
					-- IMPORTANT: These effects are part of the CURRENT turn, not a new turn.
					-- Order: All moves execute first, THEN end-of-turn effects (status damage, then healing)
					-- This ensures proper Pokemon-like turn order: Move -> Status from move -> End-of-turn effects
					if not playerFaintedThisTurn and not foeFaintedThisTurn then
						-- Process Status end-of-turn damage FIRST (before healing, as damage happens before healing in Pokemon)
						local StatusModule = require(game:GetService("ReplicatedStorage").Shared.Status)
						
						local function applyStatusDamage(creature, isPlayerSide)
							if not creature or not creature.Stats or creature.Stats.HP <= 0 then
								return
							end
							if not creature.Status then
								return
							end
							
							local statusDamage = StatusModule.ProcessEndOfTurn(creature)
							if not statusDamage or statusDamage <= 0 then
								return
							end
							
							local maxHP = creature.MaxStats and creature.MaxStats.HP or 1
							local beforeHP = creature.Stats.HP or 0
							creature.Stats.HP = math.max(0, beforeHP - statusDamage)
							
							local statusType = creature.Status and creature.Status.Type
							local creatureName = creature.Nickname or creature.Name or (isPlayerSide and "Your creature" or "Foe")
							local statusMessage = statusType == "BRN" and (creatureName .. " is hurt by its burn!") or statusType == "PSN" and (creatureName .. " is hurt by poison!") or statusType == "TOX" and (creatureName .. " is hurt by toxic poison!") or (creatureName .. " is hurt by its status!")
							
							local step = {
								Type = "Damage",
								Effectiveness = "Normal",
								IsPlayer = isPlayerSide,
								Message = statusMessage,
								DelaySeconds = 0.6,
								EndOfTurn = true,
								NewHP = creature.Stats.HP,
								MaxHP = maxHP,
							}
							
							DBG:print("[PvP][Status] applying:", creatureName, "before:", beforeHP, "-", statusDamage, "->", creature.Stats.HP, "Status:", statusType)
							
							-- Add to execution order to maintain sync (end-of-turn effects come after main actions)
							table.insert(executionOrder, {step = step, isPlayerActor = isPlayerSide})
							
							if isPlayerSide then
								table.insert(friendlyActions, step)
								-- Update player party data
								local pd = ClientData:Get(Player)
								if pd and pd.Party and battle.PlayerCreatureIndex then
									local slot = pd.Party[battle.PlayerCreatureIndex]
									if slot then
										slot.Stats = slot.Stats or {}
										slot.Stats.HP = creature.Stats.HP
										local m = creature.MaxStats and creature.MaxStats.HP or slot.MaxStats and slot.MaxStats.HP
										if m and m > 0 then
											slot.CurrentHP = math.clamp(math.floor((creature.Stats.HP / m) * 100 + 0.5), 0, 100)
										end
										if ClientData.UpdateClientData then
											ClientData:UpdateClientData(Player, pd)
										end
									end
								end
							else
								table.insert(enemyActions, step)
							end
						end
						
						-- Apply status damage to both creatures
						applyStatusDamage(battle.PlayerCreature, true)
						applyStatusDamage(battle.FoeCreature, false)
						
						-- Process Sandstorm end-of-turn chip damage (after status damage, before healing)
						local function isImmuneToSandstorm(creature)
							if not creature or not creature.Type then
								return false
							end
							local types = {}
							local defT = creature.Type
							if type(defT) == "string" then
								table.insert(types, defT)
							elseif type(defT) == "table" then
								for _, t in ipairs(defT) do
									if type(t) == "string" then
										table.insert(types, t)
									end
								end
							end
							for _, t in ipairs(types) do
								if t == "Rock" or t == "Ground" or t == "Steel" then
									return true
								end
							end
							return false
						end
						
						local function applySandstormDamage(creature, isPlayerSide)
							if not creature or not creature.Stats or creature.Stats.HP <= 0 then
								return
							end
							if battle.Weather ~= "Sandstorm" then
								return
							end
							if isImmuneToSandstorm(creature) then
								return
							end
							
							local maxHP = creature.MaxStats and creature.MaxStats.HP or 1
							local sandstormDamage = math.max(1, math.floor(maxHP / 16))
							local beforeHP = creature.Stats.HP or 0
							creature.Stats.HP = math.max(0, beforeHP - sandstormDamage)
							
							local creatureName = creature.Nickname or creature.Name or (isPlayerSide and "Your creature" or "Foe")
							local step = {
								Type = "Damage",
								Effectiveness = "Normal",
								IsPlayer = isPlayerSide,
								Message = creatureName .. " is buffeted by the sandstorm!",
								DelaySeconds = 0.6,
								EndOfTurn = true,
								NewHP = creature.Stats.HP,
								MaxHP = maxHP,
							}
							
							DBG:print("[PvP][Sandstorm] applying:", creatureName, "before:", beforeHP, "-", sandstormDamage, "->", creature.Stats.HP)
							
							-- Add to execution order to maintain sync (end-of-turn effects come after main actions)
							table.insert(executionOrder, {step = step, isPlayerActor = isPlayerSide})
							
							if isPlayerSide then
								table.insert(friendlyActions, step)
								-- Update player party data
								local pd = ClientData:Get(Player)
								if pd and pd.Party and battle.PlayerCreatureIndex then
									local slot = pd.Party[battle.PlayerCreatureIndex]
									if slot then
										slot.Stats = slot.Stats or {}
										slot.Stats.HP = creature.Stats.HP
										local m = creature.MaxStats and creature.MaxStats.HP or slot.MaxStats and slot.MaxStats.HP
										if m and m > 0 then
											slot.CurrentHP = math.clamp(math.floor((creature.Stats.HP / m) * 100 + 0.5), 0, 100)
										end
										if ClientData.UpdateClientData then
											ClientData:UpdateClientData(Player, pd)
										end
									end
								end
							else
								table.insert(enemyActions, step)
							end
						end
						
						-- Apply Sandstorm damage to both creatures
						applySandstormDamage(battle.PlayerCreature, true)
						applySandstormDamage(battle.FoeCreature, false)
						
						-- THEN process held item effects (like Crumbs healing) - healing happens after damage
						-- IMPORTANT: To get correct turn order in PvP, we add player Crumbs to enemyActions
						-- so it appears after enemy moves, matching non-PvP behavior
						local function processCrumbsForOrder(holder, isPlayerSide)
							local heldName = holder and holder.HeldItem and tostring(holder.HeldItem) or ""
							heldName = heldName:lower():gsub("^%s+", " "):gsub("%s+$", " ")
							if holder and heldName == "crumbs" then
								if holder.Stats and holder.MaxStats and holder.Stats.HP > 0 then
									local maxHP = holder.MaxStats.HP or 1
									local heal = math.max(1, math.floor(maxHP / 16))
									local beforeHP = holder.Stats.HP or 0
									holder.Stats.HP = math.min(maxHP, beforeHP + heal)
									local cname = (holder.Nickname or holder.Name or (isPlayerSide and "Your creature" or "Foe"))
									local step = {
										Type = "Heal",
										Amount = heal,
										IsPlayer = isPlayerSide,
										Message = tostring(cname) .. " regained some HP thanks to Crumbs!",
									DelaySeconds = 0.6,
									EndOfTurn = true,
									NewHP = holder.Stats.HP,
									MaxHP = maxHP,
								}
								-- Add ALL Crumbs to enemyActions to ensure correct order (matches non-PvP)
								table.insert(enemyActions, step)
								-- Also add to execution order to maintain sync (end-of-turn effects come after main actions)
								table.insert(executionOrder, {step = step, isPlayerActor = isPlayerSide})
									if isPlayerSide then
										local pd = ClientData:Get(Player)
										if pd and pd.Party and battle.PlayerCreatureIndex then
											local slot = pd.Party[battle.PlayerCreatureIndex]
											if slot then
												slot.Stats = slot.Stats or {}
												slot.Stats.HP = holder.Stats.HP
												local m = holder.MaxStats and holder.MaxStats.HP or slot.MaxStats and slot.MaxStats.HP
												if m and m > 0 then
													slot.CurrentHP = math.clamp(math.floor((holder.Stats.HP / m) * 100 + 0.5), 0, 100)
												end
												if ClientData.UpdateClientData then
													ClientData:UpdateClientData(Player, pd)
												end
											end
										end
									end
								end
							end
						end
						
						processCrumbsForOrder(battle.PlayerCreature, true)
						processCrumbsForOrder(battle.FoeCreature, false)
						
						-- Process Ability end-of-turn effects (Speed Boost, Desert Reservoir, etc.)
						local function processAbilityEndTurn(creature, isPlayerCreature)
							local Abilities = require(game:GetService("ReplicatedStorage").Shared.Abilities)
							local ability = Abilities.GetName(creature)
							if not ability then
								return
							end
							local norm = string.lower(ability)
							
							-- Desert Reservoir: Recovers HP in sunlight (or switch out, handled elsewhere)
							-- if norm == "desert reservoir" and battle.Weather == "Sunlight" then
							-- Heal(creature, 1/16)
							-- end
							
							-- Speed Boost (Steadspeed?)
							-- if norm == "speed boost" then ... end
						end
						processAbilityEndTurn(battle.PlayerCreature, true)
						processAbilityEndTurn(battle.FoeCreature, false)
						
						-- Re-mirror state after end-of-turn effects
						_mirrorState()
						_applyCurrentHP(battle.PlayerCreature)
						_applyCurrentHP(battle.FoeCreature)
						
						-- Refresh HP snapshot after end-of-turn effects (matches non-PvP behavior)
						hpData = {
							Player = math.max(0, battle.PlayerCreature.Stats.HP),
							PlayerMax = battle.PlayerCreature.MaxStats.HP,
							Enemy = math.max(0, battle.FoeCreature.Stats.HP),
							EnemyMax = battle.FoeCreature.MaxStats.HP,
						}
					end
					
					-- Ensure the stored party data matches the authoritative battle HP before defeat checks
					_syncPartyHpToSave(Player, battle.PlayerCreature, battle.PlayerCreatureIndex)
					_syncPartyHpToSave(opponent, battle.FoeCreature, oppBattle and oppBattle.PlayerCreatureIndex or battle.FoeCreatureIndex)

					-- CRITICAL: Also sync any previously fainted creatures to ensure accurate defeat detection
					-- This handles cases where a creature fainted in a previous turn but party data wasn't synced
					local function ensureAllFaintedSynced(owner: Player?, party: any?)
						if not owner or not party then
							return
						end
						for idx, creature in ipairs(party) do
							if creature then
								local hpAbs = creature.Stats and creature.Stats.HP
								local hpPct = creature.CurrentHP
								-- If Stats.HP is 0, ensure CurrentHP is also 0
								if hpAbs ~= nil and hpAbs <= 0 then
									if hpPct ~= 0 then
										creature.CurrentHP = 0
										DBG:print("[PvP][Sync] Fixed stale CurrentHP for fainted creature at slot", idx)
									end
								end
							end
						end
					end
					local playerParty = ClientData:Get(Player)
					local oppParty = ClientData:Get(opponent)
					ensureAllFaintedSynced(Player, playerParty and playerParty.Party)
					ensureAllFaintedSynced(opponent, oppParty and oppParty.Party)
					if playerParty and ClientData.UpdateClientData then
						ClientData:UpdateClientData(Player, playerParty)
					end
					if oppParty and ClientData.UpdateClientData then
						ClientData:UpdateClientData(opponent, oppParty)
					end

					-- Defeat/loss detection (server authoritative)
					local function hasRemainingCreatures(p: Player?, activeIndex: number?): boolean
						if not p or not p.Parent then
							DBG:print("[PvP][Defeat] Player invalid or left")
							return false
						end
						local pd = ClientData:Get(p)
						if not pd or not pd.Party then
							DBG:print("[PvP][Defeat] No party data")
							return false
						end

						DBG:print("[PvP][Defeat] Checking party for", p.Name, "- activeIndex:", activeIndex, "party size:", #pd.Party)

						-- If activeIndex is invalid, we can't properly skip the active creature
						if type(activeIndex) ~= "number" or activeIndex < 1 then
							DBG:warn("[PvP][Defeat] Invalid activeIndex:", activeIndex)
							activeIndex = 1 -- Default to slot 1
						end

						for idx, creature in ipairs(pd.Party) do
							DBG:print("[PvP][Defeat] Slot", idx, "- checking (active:", activeIndex, ")")

							-- Skip the currently active creature (it's the one that just fainted)
							if idx == activeIndex then
								DBG:print("[PvP][Defeat] Slot", idx, "is active creature - skipping")
								continue
							end

							if not creature then
								DBG:print("[PvP][Defeat] Slot", idx, "is empty")
								continue
							end

							-- Check HP - prioritize Stats.HP as the authoritative source
							local hpAbs = creature.Stats and creature.Stats.HP
							local hpPct = creature.CurrentHP

							DBG:print("[PvP][Defeat] Slot", idx, ":", creature.Name or "?", "Stats.HP:", hpAbs, "CurrentHP%:", hpPct)

							-- If Stats.HP exists, use it as the source of truth
							if hpAbs ~= nil then
								if hpAbs > 0 then
									DBG:print("[PvP][Defeat] Found ALIVE creature at slot", idx)
									return true
								else
									DBG:print("[PvP][Defeat] Creature at slot", idx, "is FAINTED (HP=0)")
									-- Continue checking other slots
								end
							elseif hpPct ~= nil then
								-- No Stats.HP, use CurrentHP percentage
								if hpPct > 0 then
									DBG:print("[PvP][Defeat] Found creature at slot", idx, "with CurrentHP%:", hpPct, "- considering ALIVE")
									return true
								else
									DBG:print("[PvP][Defeat] Creature at slot", idx, "is FAINTED (CurrentHP=0)")
								end
							else
								-- No HP data at all - creature was never in battle, consider alive
								DBG:print("[PvP][Defeat] Creature at slot", idx, "has no HP data - considering ALIVE")
								return true
							end
						end

						DBG:print("[PvP][Defeat] No remaining creatures found for", p.Name)
						return false
					end

					-- CRITICAL FIX: If a faint was detected during the turn, FORCE HP to 0
					-- This prevents any HP reset bugs from causing incorrect defeat detection
					DBG:print("[PvP][Fix] Checking faint flags - playerFaintedThisTurn:", playerFaintedThisTurn, "foeFaintedThisTurn:", foeFaintedThisTurn)
					if playerFaintedThisTurn then
						DBG:print("[PvP][Fix] Player fainted this turn - forcing HP to 0 (was:", battle.PlayerCreature.Stats.HP, ")")
						battle.PlayerCreature.Stats.HP = 0
						battle.PlayerCreature.CurrentHP = 0
						-- Also sync to opponent's battle table
						if oppBattle and oppBattle.FoeCreature then
							oppBattle.FoeCreature.Stats = oppBattle.FoeCreature.Stats or {}
							oppBattle.FoeCreature.Stats.HP = 0
							oppBattle.FoeCreature.CurrentHP = 0
						end
						DBG:print("[PvP][Fix] After force - battle.PlayerCreature.Stats.HP:", battle.PlayerCreature.Stats.HP)
					end
					if foeFaintedThisTurn then
						DBG:print("[PvP][Fix] Foe fainted this turn - forcing HP to 0 (was:", battle.FoeCreature.Stats.HP, ")")
						battle.FoeCreature.Stats.HP = 0
						battle.FoeCreature.CurrentHP = 0
						-- Also sync to opponent's battle table
						if oppBattle and oppBattle.PlayerCreature then
							oppBattle.PlayerCreature.Stats = oppBattle.PlayerCreature.Stats or {}
							oppBattle.PlayerCreature.Stats.HP = 0
							oppBattle.PlayerCreature.CurrentHP = 0
						end
						DBG:print("[PvP][Fix] After force - battle.FoeCreature.Stats.HP:", battle.FoeCreature.Stats.HP)
					end

					-- Safety: if a side did NOT faint but somehow got clamped to 0, restore from the
					-- authoritative snapshot we captured just after actions (hpData).
					if not playerFaintedThisTurn and (battle.PlayerCreature.Stats.HP or 0) <= 0 and preTurnHp.Player and preTurnHp.Player > 0 then
						DBG:print("[PvP][Fix] Player HP desynced to 0 without faint - restoring to snapshot:", preTurnHp.Player)
						battle.PlayerCreature.Stats.HP = preTurnHp.Player
						_applyCurrentHP(battle.PlayerCreature)
					end
					if not foeFaintedThisTurn and (battle.FoeCreature.Stats.HP or 0) <= 0 and preTurnHp.Enemy and preTurnHp.Enemy > 0 then
						DBG:print("[PvP][Fix] Foe HP desynced to 0 without faint - restoring to snapshot:", preTurnHp.Enemy)
						battle.FoeCreature.Stats.HP = preTurnHp.Enemy
						_applyCurrentHP(battle.FoeCreature)
					end
					-- Re-mirror after possible restore to keep both battle tables aligned
					_mirrorState()
					-- Refresh hpData to reflect any restores
					hpData = {
						Player = math.max(0, battle.PlayerCreature.Stats.HP),
						PlayerMax = battle.PlayerCreature.MaxStats.HP,
						Enemy = math.max(0, battle.FoeCreature.Stats.HP),
						EnemyMax = battle.FoeCreature.MaxStats.HP,
					}

					local playerHasBackup = hasRemainingCreatures(Player, battle.PlayerCreatureIndex)
					local oppHasBackup = hasRemainingCreatures(opponent, oppBattle.PlayerCreatureIndex)

					-- In PvP we've seen HP get bounced back to the pre-turn value when faint steps fire
					-- (due to aliasing or later restores). Use the authoritative faint flags as part of
					-- the defeat check so a recorded faint will always end the battle even if HP desyncs.
					if playerFaintedThisTurn then
						battle.PlayerCreature.Stats.HP = 0
						battle.PlayerCreature.CurrentHP = 0
						_applyCurrentHP(battle.PlayerCreature)
					end
					if foeFaintedThisTurn then
						battle.FoeCreature.Stats.HP = 0
						battle.FoeCreature.CurrentHP = 0
						_applyCurrentHP(battle.FoeCreature)
					end

					local playerOut = (playerFaintedThisTurn or battle.PlayerCreature.Stats.HP <= 0) and not playerHasBackup
					local oppOut = (foeFaintedThisTurn or battle.FoeCreature.Stats.HP <= 0) and not oppHasBackup
					local battleEnded = playerOut or oppOut

					DBG:print("[PvP][Defeat] === DEFEAT CHECK RESULTS ===")
					DBG:print("[PvP][Defeat] Player creature HP:", battle.PlayerCreature.Stats.HP)
					DBG:print("[PvP][Defeat] playerHasBackup:", playerHasBackup)
					DBG:print("[PvP][Defeat] playerOut:", playerOut)
					DBG:print("[PvP][Defeat] Opponent creature HP:", battle.FoeCreature.Stats.HP)
					DBG:print("[PvP][Defeat] oppHasBackup:", oppHasBackup)
					DBG:print("[PvP][Defeat] oppOut:", oppOut)
					DBG:print("[PvP][Defeat] battleEnded:", battleEnded)
					DBG:print("[PvP][Defeat] === END DEFEAT CHECK ===")

					-- PvP FORCED SWITCH: ONLY set SwitchMode if battle is NOT ending AND player has backup
					-- CRITICAL: Never prompt for switch if the battle is ending!
					local playerNeedsSwitch = false
					local oppNeedsSwitch = false

					if not battleEnded then
						-- Battle continues - check if anyone needs to switch
						playerNeedsSwitch = (battle.PlayerCreature.Stats.HP <= 0) and playerHasBackup
						oppNeedsSwitch = (battle.FoeCreature.Stats.HP <= 0) and oppHasBackup

						if playerNeedsSwitch then
							battle.SwitchMode = "Forced"
							DBG:print("[PvP] Player", Player.Name, "needs forced switch - creature fainted with backup available")
						end
						if oppNeedsSwitch then
							oppBattle.SwitchMode = "Forced"
							DBG:print("[PvP] Opponent", opponent.Name, "needs forced switch - creature fainted with backup available")
						end
					else
						-- Battle is ending - ensure no switch mode is set
						battle.SwitchMode = nil
						oppBattle.SwitchMode = nil
						DBG:print("[PvP] Battle ending - SwitchMode cleared for both players")
					end

					-- Add battle end messages
					-- friendlyActions -> player's Friendly, opponent's Enemy (after remap)
					-- enemyActions -> player's Enemy, opponent's Friendly (after remap)
					if battleEnded then
						-- Determine actual winner using firstFaintIsPlayer when both are out
						-- The creature that fainted FIRST loses; the one who landed the KO first wins
						local actualPlayerWins -- nil = draw, true = player wins, false = opponent wins

						if playerOut and oppOut then
							-- Both creatures are out - use firstFaintIsPlayer to determine winner
							if firstFaintIsPlayer == nil then
								-- True simultaneous KO (no faint was recorded, or same-action mutual KO)
								actualPlayerWins = nil -- Draw
								DBG:print("[PvP][Outcome] Both out, no first faint recorded - TRUE DRAW")
							elseif firstFaintIsPlayer == true then
								-- Player's creature fainted first - OPPONENT wins
								actualPlayerWins = false
								DBG:print("[PvP][Outcome] Both out, player fainted FIRST - OPPONENT WINS")
							else
								-- Opponent's creature fainted first - PLAYER wins
								actualPlayerWins = true
								DBG:print("[PvP][Outcome] Both out, opponent fainted FIRST - PLAYER WINS")
							end
						elseif playerOut then
							actualPlayerWins = false
							DBG:print("[PvP][Outcome] Only player out - OPPONENT WINS")
						elseif oppOut then
							actualPlayerWins = true
							DBG:print("[PvP][Outcome] Only opponent out - PLAYER WINS")
						end

						-- Generate appropriate messages based on actual winner
						if actualPlayerWins == nil then
							-- Draw - both see draw message
							local drawMsgPlayer = { Type = "Message", Message = "Battle ended in a draw!", IsPlayer = true, Audience = "Player" }
							local drawMsgOpp = { Type = "Message", Message = "Battle ended in a draw!", IsPlayer = true, Audience = "Opponent" }
							table.insert(friendlyActions, drawMsgPlayer)
							table.insert(enemyActions, drawMsgOpp)
							-- Add to execution order (battle end messages come last)
							table.insert(executionOrder, {step = drawMsgPlayer, isPlayerActor = true})
							table.insert(executionOrder, {step = drawMsgOpp, isPlayerActor = false})
							DBG:print("[PvP][Message] Draw - both players")
						elseif actualPlayerWins == false then
							-- Player lost, opponent won
							local name = Player.DisplayName or Player.Name
							-- Player sees: "X has no more creatures" + "You lost"
							local lossMsg1 = {
								Type = "Message",
								Message = string.format("%s has no more creatures left to fight!", name),
								IsPlayer = true,
								Audience = "Player",
							}
							local lossMsg2 = { Type = "Message", Message = "You lost the battle!", IsPlayer = true, Audience = "Player" }
							table.insert(friendlyActions, lossMsg1)
							table.insert(friendlyActions, lossMsg2)
							-- Opponent sees (via enemyActions->oppFriendly): "X has no more creatures" + "You won"
							local winMsg1 = {
								Type = "Message",
								Message = string.format("%s has no more creatures left to fight!", name),
								IsPlayer = true,
								Audience = "Opponent",
							}
							local winMsg2 = { Type = "Message", Message = "You won the battle!", IsPlayer = true, Audience = "Opponent" }
							table.insert(enemyActions, winMsg1)
							table.insert(enemyActions, winMsg2)
							-- Add to execution order (battle end messages come last)
							table.insert(executionOrder, {step = lossMsg1, isPlayerActor = true})
							table.insert(executionOrder, {step = lossMsg2, isPlayerActor = true})
							table.insert(executionOrder, {step = winMsg1, isPlayerActor = false})
							table.insert(executionOrder, {step = winMsg2, isPlayerActor = false})
							DBG:print("[PvP][Message] Player", Player.Name, "lost, opponent won")
						else
							-- Opponent lost, player won
							local name = opponent.DisplayName or opponent.Name
							-- Player sees: "X has no more creatures" + "You won"
							local winMsg1Player = {
								Type = "Message",
								Message = string.format("%s has no more creatures left to fight!", name),
								IsPlayer = true,
								Audience = "Player",
							}
							local winMsg2Player = { Type = "Message", Message = "You won the battle!", IsPlayer = true, Audience = "Player" }
							table.insert(friendlyActions, winMsg1Player)
							table.insert(friendlyActions, winMsg2Player)
							-- Opponent sees (via enemyActions->oppFriendly): "X has no more creatures" + "You lost"
							local lossMsg1Opp = {
								Type = "Message",
								Message = string.format("%s has no more creatures left to fight!", name),
								IsPlayer = true,
								Audience = "Opponent",
							}
							local lossMsg2Opp = { Type = "Message", Message = "You lost the battle!", IsPlayer = true, Audience = "Opponent" }
							table.insert(enemyActions, lossMsg1Opp)
							table.insert(enemyActions, lossMsg2Opp)
							-- Add to execution order (battle end messages come last)
							table.insert(executionOrder, {step = winMsg1Player, isPlayerActor = true})
							table.insert(executionOrder, {step = winMsg2Player, isPlayerActor = true})
							table.insert(executionOrder, {step = lossMsg1Opp, isPlayerActor = false})
							table.insert(executionOrder, {step = lossMsg2Opp, isPlayerActor = false})
							DBG:print("[PvP][Message] Opponent", opponent.Name, "lost, player won")
						end
					end

					-- CRITICAL SYNCHRONIZATION: Ensure both battle tables have identical HP values
					-- Final mirror state sync before creating result packets
					_mirrorState()
					_applyCurrentHP(battle.PlayerCreature)
					_applyCurrentHP(battle.FoeCreature)
					_applyCurrentHP(oppBattle.PlayerCreature)
					_applyCurrentHP(oppBattle.FoeCreature)
					
					-- Refresh HP data from authoritative battle table (player's perspective)
					hpData = {
						Player = math.max(0, battle.PlayerCreature.Stats.HP),
						PlayerMax = battle.PlayerCreature.MaxStats.HP,
						Enemy = math.max(0, battle.FoeCreature.Stats.HP),
						EnemyMax = battle.FoeCreature.MaxStats.HP,
					}
					
					-- CRITICAL: Opponent's HP data must be identical but mirrored (their Player = our Enemy, their Enemy = our Player)
					-- Verify synchronization: oppBattle.PlayerCreature should match battle.FoeCreature
					-- and oppBattle.FoeCreature should match battle.PlayerCreature
					if oppBattle and oppBattle.PlayerCreature and battle.FoeCreature then
						if oppBattle.PlayerCreature.Stats.HP ~= battle.FoeCreature.Stats.HP then
							DBG:warn("[PvP][Sync] HP mismatch detected - syncing oppBattle.PlayerCreature to battle.FoeCreature")
							oppBattle.PlayerCreature.Stats.HP = battle.FoeCreature.Stats.HP
							oppBattle.PlayerCreature.CurrentHP = battle.FoeCreature.CurrentHP
						end
						if oppBattle.PlayerCreature.MaxStats.HP ~= battle.FoeCreature.MaxStats.HP then
							oppBattle.PlayerCreature.MaxStats.HP = battle.FoeCreature.MaxStats.HP
						end
					end
					if oppBattle and oppBattle.FoeCreature and battle.PlayerCreature then
						if oppBattle.FoeCreature.Stats.HP ~= battle.PlayerCreature.Stats.HP then
							DBG:warn("[PvP][Sync] HP mismatch detected - syncing oppBattle.FoeCreature to battle.PlayerCreature")
							oppBattle.FoeCreature.Stats.HP = battle.PlayerCreature.Stats.HP
							oppBattle.FoeCreature.CurrentHP = battle.PlayerCreature.CurrentHP
						end
						if oppBattle.FoeCreature.MaxStats.HP ~= battle.PlayerCreature.MaxStats.HP then
							oppBattle.FoeCreature.MaxStats.HP = battle.PlayerCreature.MaxStats.HP
						end
					end

					local nextTurnId = (battle.TurnId or 0) + 1
					-- For the opponent's view, flip any IsPlayer flags so they still point to
					-- the correct target (player vs foe) after the perspective swap.
					local function remapStepsForOpponent(list)
						if type(list) ~= "table" then
							return {}
						end
						local out = {}
						for _, step in ipairs(list) do
							if type(step) == "table" then
								local clone = table.clone(step)
								if type(clone.IsPlayer) == "boolean" then
									clone.IsPlayer = not clone.IsPlayer
								end
								table.insert(out, clone)
							else
								table.insert(out, step)
							end
						end
						return out
					end

					local function filterByAudience(list, audience)
						if type(list) ~= "table" then
							return {}
						end
						local filtered = {}
						for _, step in ipairs(list) do
							if step.Audience == nil or step.Audience == audience or step.Audience == "All" then
								table.insert(filtered, step)
							end
						end
						return filtered
					end

					local battleEndFlag = battleEnded and {
						PlayerOut = playerOut,
						OppOut = oppOut,
					} or nil

					-- CRITICAL FIX: Build action lists in execution order to maintain synchronization
					-- Instead of splitting by friendly/enemy, we build ordered lists that preserve execution order
					-- Each step gets an ExecOrder field so the client can merge and sort them properly
					local function buildOrderedActionLists(execOrder, forPlayerPerspective: boolean)
						-- forPlayerPerspective: true = Player 1's view, false = Opponent's view
						local friendlyList = {}
						local enemyList = {}
						
						for execIdx, entry in ipairs(execOrder) do
							local step = entry.step
							local isPlayerActor = entry.isPlayerActor
							
							-- Filter by audience first
							local audience = step.Audience
							if audience ~= nil and audience ~= (forPlayerPerspective and "Player" or "Opponent") and audience ~= "All" then
								-- Skip this step for this perspective
								continue
							end
							
							-- Clone step for this perspective
							local stepClone = table.clone(step)
							
							-- CRITICAL: Add execution order so client can properly interleave Friendly+Enemy
							stepClone.ExecOrder = execIdx
							
							-- For opponent's perspective, flip IsPlayer flags
							if not forPlayerPerspective and type(stepClone.IsPlayer) == "boolean" then
								stepClone.IsPlayer = not stepClone.IsPlayer
							end
							
							-- Categorize based on actor (from this perspective)
							-- If this is Player 1's perspective:
							--   - Player 1's actions (isPlayerActor=true) -> friendlyList
							--   - Player 2's actions (isPlayerActor=false) -> enemyList
							-- If this is Player 2's perspective:
							--   - Player 2's actions (isPlayerActor=false) -> friendlyList (their own actions)
							--   - Player 1's actions (isPlayerActor=true) -> enemyList (opponent's actions)
							local goesToFriendly = (forPlayerPerspective and isPlayerActor) or (not forPlayerPerspective and not isPlayerActor)
							
							if goesToFriendly then
								table.insert(friendlyList, stepClone)
							else
								table.insert(enemyList, stepClone)
							end
						end
						
						return friendlyList, enemyList
					end
					
					-- Build ordered action lists for both players
					local playerFriendly, playerEnemy = buildOrderedActionLists(executionOrder, true)
					local oppFriendly, oppEnemy = buildOrderedActionLists(executionOrder, false)
					
					-- Legacy code kept for reference but not used:
					-- local playerFriendly = filterByAudience(friendlyActions, "Player")
					-- local playerEnemy = filterByAudience(enemyActions, "Player")
					-- local oppFriendlyRaw = filterByAudience(enemyActions, "Opponent")
					-- local oppEnemyRaw = filterByAudience(friendlyActions, "Opponent")

					-- CRITICAL: Deep clone creature data to prevent mutations
					local playerCreatureClone = table.clone(battle.PlayerCreature)
					local foeCreatureClone = table.clone(battle.FoeCreature)
					local oppPlayerCreatureClone = table.clone(oppBattle.PlayerCreature)
					local oppFoeCreatureClone = table.clone(oppBattle.FoeCreature)
					
					-- Deep clone Stats and MaxStats to prevent shared references
					if playerCreatureClone.Stats then
						playerCreatureClone.Stats = table.clone(playerCreatureClone.Stats)
					end
					if playerCreatureClone.MaxStats then
						playerCreatureClone.MaxStats = table.clone(playerCreatureClone.MaxStats)
					end
					if foeCreatureClone.Stats then
						foeCreatureClone.Stats = table.clone(foeCreatureClone.Stats)
					end
					if foeCreatureClone.MaxStats then
						foeCreatureClone.MaxStats = table.clone(foeCreatureClone.MaxStats)
					end
					if oppPlayerCreatureClone.Stats then
						oppPlayerCreatureClone.Stats = table.clone(oppPlayerCreatureClone.Stats)
					end
					if oppPlayerCreatureClone.MaxStats then
						oppPlayerCreatureClone.MaxStats = table.clone(oppPlayerCreatureClone.MaxStats)
					end
					if oppFoeCreatureClone.Stats then
						oppFoeCreatureClone.Stats = table.clone(oppFoeCreatureClone.Stats)
					end
					if oppFoeCreatureClone.MaxStats then
						oppFoeCreatureClone.MaxStats = table.clone(oppFoeCreatureClone.MaxStats)
					end

					local playerResult = {
						Friendly = playerFriendly,
						Enemy = playerEnemy,
						HP = hpData,
						PlayerCreature = playerCreatureClone,
						FoeCreature = foeCreatureClone,
						TurnId = nextTurnId,
						BattleEnd = battleEndFlag ~= nil and true or nil,
						-- Signal forced switch to player if their creature fainted with backup
						SwitchMode = playerNeedsSwitch and "Forced" or nil,
						-- Signal to wait for opponent's forced switch (don't show options yet)
						WaitingForOpponentSwitch = oppNeedsSwitch and true or nil,
					}
					-- Opponent's HP data: their Player = our Enemy, their Enemy = our Player
					local oppHP = {
						Player = math.max(0, oppBattle.PlayerCreature.Stats.HP),
						PlayerMax = oppBattle.PlayerCreature.MaxStats.HP,
						Enemy = math.max(0, oppBattle.FoeCreature.Stats.HP),
						EnemyMax = oppBattle.FoeCreature.MaxStats.HP,
					}
					
					-- VALIDATION: Ensure HP values are synchronized (opponent's Player = our Enemy, opponent's Enemy = our Player)
					if math.abs(oppHP.Player - hpData.Enemy) > 0.1 or math.abs(oppHP.Enemy - hpData.Player) > 0.1 then
						DBG:warn("[PvP][Sync] HP validation failed - forcing sync")
						DBG:warn("[PvP][Sync] Player HP - Player:", hpData.Player, "Opponent Enemy:", oppHP.Enemy)
						DBG:warn("[PvP][Sync] Enemy HP - Enemy:", hpData.Enemy, "Opponent Player:", oppHP.Player)
						oppHP.Player = hpData.Enemy
						oppHP.PlayerMax = hpData.EnemyMax
						oppHP.Enemy = hpData.Player
						oppHP.EnemyMax = hpData.PlayerMax
					end
					-- Note: oppFriendly and oppEnemy are already built with correct IsPlayer flags in buildOrderedActionLists
					-- No need to remap since we built them correctly from the start
					local oppResult = {
						Friendly = oppFriendly,
						Enemy = oppEnemy,
						HP = oppHP,
						PlayerCreature = oppPlayerCreatureClone,
						FoeCreature = oppFoeCreatureClone,
						TurnId = nextTurnId,
						BattleEnd = battleEndFlag ~= nil and true or nil,
						-- Signal forced switch to opponent if their creature fainted with backup
						SwitchMode = oppNeedsSwitch and "Forced" or nil,
						-- Signal to wait for player's forced switch (don't show options yet)
						WaitingForOpponentSwitch = playerNeedsSwitch and true or nil,
					}

					DBG:print("[PvP] === SENDING TURN RESULTS ===")
					DBG:print("[PvP] BattleEnd flag:", battleEndFlag ~= nil and true or nil, "battleEnded:", battleEnded)
					DBG:print("[PvP] playerNeedsSwitch:", playerNeedsSwitch, "oppNeedsSwitch:", oppNeedsSwitch)
					DBG:print("[PvP] Player result - Friendly actions count:", #playerFriendly, "Enemy actions count:", #playerEnemy)
					DBG:print("[PvP] Opponent result - Friendly actions count:", #oppFriendly, "Enemy actions count:", #oppEnemy)
					DBG:print("[PvP] Final HP - Player:", hpData.Player, "/", hpData.PlayerMax, "Enemy:", hpData.Enemy, "/", hpData.EnemyMax)
					DBG:print("[PvP] Opponent HP - Player:", oppHP.Player, "/", oppHP.PlayerMax, "Enemy:", oppHP.Enemy, "/", oppHP.EnemyMax)
					for idx, step in ipairs(playerFriendly) do
						DBG:print("[PvP][Player] Friendly step", idx, "- Type:", step.Type, "Move:", step.Move, "IsPlayer:", step.IsPlayer, "NewHP:", step.NewHP)
					end
					for idx, step in ipairs(playerEnemy) do
						DBG:print("[PvP][Player] Enemy step", idx, "- Type:", step.Type, "Move:", step.Move, "IsPlayer:", step.IsPlayer, "NewHP:", step.NewHP)
					end
					for idx, step in ipairs(oppFriendly) do
						DBG:print("[PvP][Opponent] Friendly step", idx, "- Type:", step.Type, "Move:", step.Move, "IsPlayer:", step.IsPlayer, "NewHP:", step.NewHP)
					end
					for idx, step in ipairs(oppEnemy) do
						DBG:print("[PvP][Opponent] Enemy step", idx, "- Type:", step.Type, "Move:", step.Move, "IsPlayer:", step.IsPlayer, "NewHP:", step.NewHP)
					end

					local Events = game.ReplicatedStorage.Events
					if Events and Events.Communicate then
						DBG:print("[PvP] Firing TurnResult to", Player.Name, "and", opponent.Name)
						_logBattleMessages("PvP:" .. Player.Name .. ":Self", playerResult)
						_logBattleMessages("PvP:" .. Player.Name .. ":Opponent", oppResult)
						-- CRITICAL: Ensure both clients receive identical step data (just with different IsPlayer flags)
						-- Deep clone results to prevent any mutation - results are already cloned above, but clone again for safety
						local function deepCloneResult(result)
							local cloned = table.clone(result)
							-- Deep clone HP data
							if cloned.HP then
								cloned.HP = table.clone(cloned.HP)
							end
							-- Deep clone action arrays
							if cloned.Friendly then
								local friendlyClone = {}
								for _, step in ipairs(cloned.Friendly) do
									table.insert(friendlyClone, table.clone(step))
								end
								cloned.Friendly = friendlyClone
							end
							if cloned.Enemy then
								local enemyClone = {}
								for _, step in ipairs(cloned.Enemy) do
									table.insert(enemyClone, table.clone(step))
								end
								cloned.Enemy = enemyClone
							end
							-- Creature data already cloned above
							return cloned
						end
						local playerResultClone = deepCloneResult(playerResult)
						local oppResultClone = deepCloneResult(oppResult)
						
						-- VALIDATION: Ensure TurnId is synchronized
						if playerResultClone.TurnId ~= oppResultClone.TurnId then
							DBG:warn("[PvP][Sync] TurnId mismatch - forcing sync")
							local syncTurnId = math.max(playerResultClone.TurnId or 0, oppResultClone.TurnId or 0)
							playerResultClone.TurnId = syncTurnId
							oppResultClone.TurnId = syncTurnId
						end
						
						-- Send results simultaneously to both clients
						Events.Communicate:FireClient(Player, "TurnResult", playerResultClone)
						Events.Communicate:FireClient(opponent, "TurnResult", oppResultClone)
					end

					battle.TurnId = nextTurnId
					oppBattle.TurnId = nextTurnId
					battle.PlayerAction = nil
					oppBattle.PlayerAction = nil
					battle.PendingActions = nil
					oppBattle.PendingActions = nil
					_pvpTurnBuffer[key] = { TurnId = nextTurnId, Actions = {} }
					if battleEnded then
						-- Determine actual winner using firstFaintIsPlayer (same logic as message generation)
						local playerReason = "Win"
						local oppReason = "Loss"

						if playerOut and oppOut then
							-- Both out - use firstFaintIsPlayer to determine winner
							if firstFaintIsPlayer == nil then
								-- True simultaneous KO - Draw
								playerReason = "Draw"
								oppReason = "Draw"
							elseif firstFaintIsPlayer == true then
								-- Player fainted first - Player loses
								playerReason = "Loss"
								oppReason = "Win"
							else
								-- Opponent fainted first - Player wins
								playerReason = "Win"
								oppReason = "Loss"
							end
						elseif playerOut then
							playerReason = "Loss"
							oppReason = "Win"
						end
						-- else: oppOut only, defaults (Win/Loss) are correct

						DBG:print("[PvP][EndBattle] Player:", Player.Name, "->", playerReason, "| Opponent:", opponent.Name, "->", oppReason)
						ServerFunctions:EndBattle(Player, playerReason)
						ServerFunctions:EndBattle(opponent, oppReason)
					end
				end)
				_pvpResolving[key] = nil
				if not okResolve then
					DBG:warn("[PvP] Turn resolution error:", errResolve)
					return false
				end
				DBG:print("[PvP] === TURN RESOLUTION COMPLETE - Next TurnId:", battle.TurnId, "===")
			else
				DBG:print("[PvP] Opponent has not acted yet - waiting for their action")
			end
			return true
		end

		-- Trainer pending send-out handling at turn start (prevents same-turn attacks after faint)
		if battle.Type == "Trainer" and battle.PendingTrainerSendOut and battle.NextFoeCreature then
			-- If the previous TurnResult already included an inline SendOut, just promote the next foe now
			-- and do NOT emit another TurnResult.
			if battle.SendOutInline then
				battle.PendingTrainerSendOut = false
				battle.SendOutInline = nil
				battle.FoeCreature = battle.NextFoeCreature
				battle.FoeCreatureIndex = battle.NextFoeCreatureIndex
				battle.NextFoeCreature = nil
				battle.NextFoeCreatureIndex = nil
				-- Continue into normal turn processing
			else
				battle.PendingTrainerSendOut = false
				-- Promote the pending next foe creature now and send a clean Switch TurnResult
				battle.FoeCreature = battle.NextFoeCreature
				battle.FoeCreatureIndex = battle.NextFoeCreatureIndex
				battle.NextFoeCreature = nil
				battle.NextFoeCreatureIndex = nil
				local foeName = battle.FoeCreature.Nickname or battle.FoeCreature.Name or "Foe"

				-- Mark new trainer creature as seen
				if battle.FoeCreature and battle.FoeCreature.Name then
					local PlayerData = ClientData:Get(Player)
					if PlayerData then
						PlayerData.SeenCreatures = PlayerData.SeenCreatures or {}
						PlayerData.SeenCreatures[battle.FoeCreature.Name] = true
						DBG:print("[Seen] Marked", battle.FoeCreature.Name, "as seen (trainer send out)")
						ClientData:UpdateClientData(Player, PlayerData)
					end
				end
				-- Deep clone creature data for SendOut step
				local creatureDataClone = table.clone(battle.FoeCreature)
				if creatureDataClone.Stats then
					creatureDataClone.Stats = table.clone(creatureDataClone.Stats)
				end
				if creatureDataClone.MaxStats then
					creatureDataClone.MaxStats = table.clone(creatureDataClone.MaxStats)
				end
				local friendlyActions = {}
				local execOrder = 0
				local sendOutStep = { Type = "Switch", Action = "SendOut", Creature = foeName, CreatureData = creatureDataClone, IsPlayer = false }
				execOrder = execOrder + 1
				sendOutStep.ExecOrder = execOrder
				local enemyActions = { sendOutStep }
				
				-- Apply entry hazard damage to the trainer's incoming creature
				local EntryHazards = require(game:GetService("ReplicatedStorage").Shared.EntryHazards)
				if battle.FoeHazards then
					DBG:print("[HAZARD] Checking FoeHazards for trainer switch-in (ProcessTurn):", battle.FoeHazards)
					local hazardSteps, updatedHazards = EntryHazards.ApplyOnSwitchIn(battle.FoeCreature, battle.FoeHazards, false)
					
					-- Update hazards state (Toxic Spikes may have been absorbed)
					if updatedHazards then
						battle.FoeHazards = updatedHazards
					end
					
					-- Add hazard damage steps to enemy actions
					for _, hazardStep in ipairs(hazardSteps) do
						execOrder = execOrder + 1
						hazardStep.ExecOrder = execOrder
						table.insert(enemyActions, hazardStep)
						DBG:print("[HAZARD] Added hazard step for trainer switch-in (ProcessTurn):", hazardStep.Type, hazardStep.HazardType)
					end
					
					-- Update the cloned creature data with post-hazard HP
					if #hazardSteps > 0 and battle.FoeCreature.Stats then
						creatureDataClone.Stats = creatureDataClone.Stats or {}
						creatureDataClone.Stats.HP = battle.FoeCreature.Stats.HP
						DBG:print("[HAZARD] Updated trainer creature HP after hazard damage (ProcessTurn):", battle.FoeCreature.Stats.HP)
					end
				end
				
				local hpData = {
					Player = battle.PlayerCreature.Stats.HP,
					PlayerMax = battle.PlayerCreature.MaxStats.HP,
					Enemy = battle.FoeCreature.Stats.HP,
					EnemyMax = battle.FoeCreature.MaxStats.HP,
				}
				local turnResult = {
					Friendly = friendlyActions,
					Enemy = enemyActions,
					HP = hpData,
					PlayerCreature = battle.PlayerCreature,
					FoeCreature = battle.FoeCreature,
				}
				local Events = game.ReplicatedStorage.Events
				if Events and Events.Communicate then
					_logBattleMessages("TrainerSendOut:" .. Player.Name, turnResult)
					Events.Communicate:FireClient(Player, "TurnResult", turnResult)
				end
				return true
			end
		end

		-- Get player action (already stored in ExecuteMove)
		local playerAction = battle.PlayerAction
		if not playerAction then
			DBG:warn("No player action found for turn processing")
			return false
		end

		-- Check if player fainted in previous turn (from switch damage)
		DBG:print("=== PROCESS TURN DEBUG ===")
		DBG:print("Battle.PlayerFainted:", battle.PlayerFainted)
		DBG:print("Player creature HP:", battle.PlayerCreature.Stats.HP)
		DBG:print("=== END PROCESS TURN DEBUG ===")

		-- Check if player creature is fainted (either from flag or current HP)
		local playerFainted = battle.PlayerFainted or (battle.PlayerCreature.Stats.HP <= 0)

		if playerFainted then
			DBG:print("=== PLAYER FAINT DETECTED ===")
			DBG:print("Player creature:", battle.PlayerCreature.Name, "HP:", battle.PlayerCreature.Stats.HP)
			DBG:print("Faint reason - Flag:", battle.PlayerFainted, "HP <= 0:", battle.PlayerCreature.Stats.HP <= 0)

			-- Clear status conditions when creature faints
			local StatusModule = require(game:GetService("ReplicatedStorage").Shared.Status)
			if StatusModule and StatusModule.Remove then
				StatusModule.Remove(battle.PlayerCreature)
			else
				battle.PlayerCreature.Status = nil
			end
			battle.PlayerCreature.VolatileStatus = nil

			-- Also clear status in party data
			local PlayerData = ClientData:Get(Player)
			if PlayerData and PlayerData.Party and battle.PlayerCreatureIndex then
				local partyCreature = PlayerData.Party[battle.PlayerCreatureIndex]
				if partyCreature then
					if StatusModule and StatusModule.Remove then
						StatusModule.Remove(partyCreature)
					else
						partyCreature.Status = nil
					end
					partyCreature.VolatileStatus = nil
				end
			end

			-- Create faint step for the player creature
			local faintStep = {
				Type = "Faint",
				Creature = battle.PlayerCreature.Name or "Your creature",
				IsPlayer = true,
			}

			-- Add faint step to friendly actions (player fainted)
			local friendlyActions = { faintStep }
			local enemyActions = {}

			-- Clear the faint flag
			battle.PlayerFainted = false

			-- Send turn result with faint step
			local turnResult = {
				Friendly = friendlyActions,
				Enemy = enemyActions,
				HP = {
					Player = battle.PlayerCreature.Stats.HP,
					PlayerMax = battle.PlayerCreature.MaxStats.HP,
					Enemy = battle.FoeCreature.Stats.HP,
					EnemyMax = battle.FoeCreature.MaxStats.HP,
				},
				PlayerCreature = battle.PlayerCreature,
				FoeCreature = battle.FoeCreature,
			}

			DBG:print("=== SENDING FAINT TURN RESULT TO CLIENT ===")
			DBG:print("Friendly actions count:", #friendlyActions)
			for i, action in ipairs(friendlyActions) do
				DBG:print("Friendly", i, "Type:", action.Type, "IsPlayer:", action.IsPlayer, "Creature:", action.Creature)
			end
			DBG:print("=== END FAINT TURN RESULT ===")

			local Events = game.ReplicatedStorage.Events
			if Events and Events.Communicate then
				_logBattleMessages("Faint:" .. Player.Name, turnResult)
				Events.Communicate:FireClient(Player, "TurnResult", turnResult)
			end

			return true
		end

		-- PvP: handled earlier; should not reach here
		if battle.Type == "PvP" then
			return true
		end

		-- Determine turn order based on speed and priority
		local enemyActionLocal = BattleSystem.BuildEnemyAction(Player)
		local turnOrder = BattleSystem.DetermineTurnOrder(battle, playerAction, enemyActionLocal)

		-- Safe debug log for turn order when enemyAction may be skipped
		local firstActor = turnOrder[1] and turnOrder[1].Actor or "?"
		local secondActor = turnOrder[2] and turnOrder[2].Actor or "None"
		DBG:print("Turn order determined:", firstActor, "goes first, then", secondActor)

		-- Execute actions in order
		local friendlyActions = {}
		local enemyActions = {}
		-- Track if a faint step has already been added for each side to prevent duplicates
		local playerFaintAdded = false
		local foeFaintAdded = false
		local faintAddedByCreature = {}
		local hpData = {
			Player = battle.PlayerCreature.Stats.HP,
			PlayerMax = battle.PlayerCreature.MaxStats.HP,
			Enemy = battle.FoeCreature.Stats.HP,
			EnemyMax = battle.FoeCreature.MaxStats.HP,
		}
		
		-- Track execution order for correct client-side step processing
		-- The client will merge Friendly+Enemy steps and sort by ExecOrder to process in correct order
		local execOrderCounter = 0
		local function addStepWithOrder(stepList, step)
			execOrderCounter = execOrderCounter + 1
			step.ExecOrder = execOrderCounter
			table.insert(stepList, step)
		end
		
		-- Helper function to award XP immediately after a foe faint step is added
		-- This ensures XP steps have ExecOrder values right after the faint step
		local function awardXPAfterFoeFaint(defeatedCreature)
			-- Only award XP for trainer battles (wild battles award at battle end)
			if battle.Type ~= "Trainer" then
				return
			end
			
			-- Check if XP was already awarded for this creature
			if battle.TrainerParty and battle.FoeCreatureIndex and battle.TrainerParty[battle.FoeCreatureIndex] then
				if battle.TrainerParty[battle.FoeCreatureIndex]._XPAwarded == true then
					DBG:print("[XP] XP already awarded for this trainer creature - skipping")
					return
				end
			end
			
			if defeatedCreature then
				DBG:print("[XP] Awarding XP immediately after foe faint step")
				local xpSteps = ServerFunctions:AwardBattleXP(Player, defeatedCreature, battle)
				if type(xpSteps) == "table" and #xpSteps > 0 then
					for _, step in ipairs(xpSteps) do
						addStepWithOrder(friendlyActions, step)
					end
					DBG:print("[XP] Added", #xpSteps, "XP steps immediately after faint")
				end
				-- Mark XP as already awarded for this trainer creature to avoid double-award
				if battle.TrainerParty and battle.FoeCreatureIndex and battle.TrainerParty[battle.FoeCreatureIndex] then
					battle.TrainerParty[battle.FoeCreatureIndex]._XPAwarded = true
				end
			end
		end

		local playerFaintedThisTurn = false
		local foeFaintedThisTurn = false
		for i, action in ipairs(turnOrder) do
			-- Check if we should skip this action due to a KO in the previous action
			if playerFaintedThisTurn or foeFaintedThisTurn then
				DBG:print("[ProcessTurn] Skipping remaining action", i, "due to KO")
				break
			end
			
			-- CRITICAL: Check HP directly before executing action (similar to PvP)
			-- This catches cases where faint flags weren't set correctly (e.g., recoil faint)
			if action.IsPlayer == true and battle.PlayerCreature and battle.PlayerCreature.Stats and battle.PlayerCreature.Stats.HP <= 0 then
				DBG:print("[ProcessTurn] Skipping action", i, "- player creature already fainted (HP:", battle.PlayerCreature.Stats.HP, ")")
				playerFaintedThisTurn = true
				break
			elseif action.IsPlayer == false and battle.FoeCreature and battle.FoeCreature.Stats and battle.FoeCreature.Stats.HP <= 0 then
				DBG:print("[ProcessTurn] Skipping action", i, "- foe creature already fainted (HP:", battle.FoeCreature.Stats.HP, ")")
				foeFaintedThisTurn = true
				break
			end
			
			-- Also skip enemy action if player fainted (enemy doesn't need to attack a fainted target)
			if action.IsPlayer == false and battle.PlayerCreature and battle.PlayerCreature.Stats and battle.PlayerCreature.Stats.HP <= 0 then
				DBG:print("[ProcessTurn] Skipping enemy action", i, "- player creature already fainted from previous action")
				playerFaintedThisTurn = true
				break
			end

			local result = BattleSystem.ExecuteAction(Player, action, battle)

			-- Handle multiple results (e.g., move + faint)
			if type(result) == "table" and result[1] then
				-- Multiple results returned
				DBG:print("=== MULTIPLE RESULTS DETECTED ===")
				DBG:print("Number of results:", #result)
				for i2, singleResult in ipairs(result) do
					DBG:print("Result", i2, "Type:", singleResult.Type, "IsPlayer:", singleResult.IsPlayer, "Creature:", singleResult.Creature)
				end
				DBG:print("=== END MULTIPLE RESULTS ===")

				for _, singleResult in ipairs(result) do
					-- Resolve actor side for this step
					-- Move, Damage, and Recoil steps should ALWAYS stay with the action that caused them
					-- This ensures attack animations and their effects are shown together
					local stepIsPlayer
					if singleResult.Type == "Move" or singleResult.Type == "Damage" or singleResult.Type == "Recoil" then
						stepIsPlayer = action.IsPlayer
					elseif singleResult.IsPlayer ~= nil then
						stepIsPlayer = singleResult.IsPlayer
					elseif singleResult.Type == "Faint" and singleResult.Creature then
						-- Robust resolution by matching creature name against current battle creatures
						local playerName = (battle.PlayerCreature and (battle.PlayerCreature.Nickname or battle.PlayerCreature.Name)) or ""
						local foeName = (battle.FoeCreature and (battle.FoeCreature.Nickname or battle.FoeCreature.Name)) or ""
						if singleResult.Creature == playerName then
							stepIsPlayer = true
						elseif singleResult.Creature == foeName then
							stepIsPlayer = false
						end
					end
					if stepIsPlayer == nil then
						stepIsPlayer = action.IsPlayer
					end

					DBG:print("Categorizing result - Type:", singleResult.Type, "stepIsPlayer:", stepIsPlayer, "action.IsPlayer:", action.IsPlayer)

					if singleResult.Type == "Faint" then
						local faintKey = tostring(singleResult.Creature or "")
						if faintKey ~= "" and faintAddedByCreature[faintKey] then
							DBG:print("Skipping duplicate FAINT for creature:", faintKey)
							continue
						end
						-- For ordering: attach FAINT to the same side as the triggering action
						stepIsPlayer = action.IsPlayer
						
						-- ROBUST faint detection: check IsPlayer flag, creature name, or HP values
						local faintIsPlayerCreature = false
						if singleResult.IsPlayer == true then
							faintIsPlayerCreature = true
						elseif singleResult.IsPlayer == false then
							faintIsPlayerCreature = false
						elseif singleResult.Creature then
							-- Match creature name to determine who fainted
							local playerName = (battle.PlayerCreature and (battle.PlayerCreature.Nickname or battle.PlayerCreature.Name)) or ""
							local foeName = (battle.FoeCreature and (battle.FoeCreature.Nickname or battle.FoeCreature.Name)) or ""
							if singleResult.Creature == playerName then
								faintIsPlayerCreature = true
							elseif singleResult.Creature == foeName then
								faintIsPlayerCreature = false
							end
						end
						-- Fallback: check HP values to determine who fainted
						if singleResult.IsPlayer == nil and singleResult.Creature == nil then
							local playerHP = battle.PlayerCreature and battle.PlayerCreature.Stats and battle.PlayerCreature.Stats.HP or 1
							local foeHP = battle.FoeCreature and battle.FoeCreature.Stats and battle.FoeCreature.Stats.HP or 1
							if playerHP <= 0 and foeHP > 0 then
								faintIsPlayerCreature = true
							elseif foeHP <= 0 and playerHP > 0 then
								faintIsPlayerCreature = false
							end
						end
						
						DBG:print("[Faint] Resolved faintIsPlayerCreature:", faintIsPlayerCreature, "IsPlayer:", singleResult.IsPlayer, "Creature:", singleResult.Creature)
						
						-- CRITICAL: Set the IsPlayer field on the result to indicate WHICH CREATURE fainted
						-- This is essential for client-side reordering logic which checks step.IsPlayer == false
						-- to detect foe faints and properly order SwitchPreview before SendOut
						singleResult.IsPlayer = faintIsPlayerCreature
						
						if faintIsPlayerCreature then
							playerFaintedThisTurn = true
						else
							foeFaintedThisTurn = true
							-- Clear status conditions when foe creature faints
							local StatusModule = require(game:GetService("ReplicatedStorage").Shared.Status)
							if battle.FoeCreature then
								if StatusModule and StatusModule.Remove then
									StatusModule.Remove(battle.FoeCreature)
								else
									battle.FoeCreature.Status = nil
								end
								battle.FoeCreature.VolatileStatus = nil
							end
						end
						-- Use faintIsPlayerCreature to determine which list to add the step to
						-- This ensures the Faint step is correctly categorized based on WHO FAINTED, not who triggered it
						if faintIsPlayerCreature then
							if not playerFaintAdded then
								addStepWithOrder(friendlyActions, singleResult)
								playerFaintAdded = true
								if faintKey ~= "" then
									faintAddedByCreature[faintKey] = true
								end
								DBG:print("Added PLAYER faint to friendlyActions")
							else
								DBG:print("Skipping duplicate PLAYER faint step")
							end
						else
							if not foeFaintAdded then
								addStepWithOrder(enemyActions, singleResult)
								foeFaintAdded = true
								if faintKey ~= "" then
									faintAddedByCreature[faintKey] = true
								end
								DBG:print("Added FOE faint to enemyActions")
								-- Award XP immediately after foe faint step (for trainer battles)
								-- This ensures XP steps have ExecOrder values right after the faint step
								awardXPAfterFoeFaint(battle.FoeCreature)
							else
								DBG:print("Skipping duplicate FOE faint step")
							end
						end
					else
						if stepIsPlayer then
							addStepWithOrder(friendlyActions, singleResult)
							DBG:print("Added to friendlyActions")
						else
							addStepWithOrder(enemyActions, singleResult)
							DBG:print("Added to enemyActions")
						end
					end
				end
			else
				-- Single result
				-- Move, Damage, and Recoil steps should ALWAYS stay with the action that caused them
				local stepIsPlayer
				if result.Type == "Move" or result.Type == "Damage" or result.Type == "Recoil" then
					stepIsPlayer = action.IsPlayer
				elseif result.IsPlayer ~= nil then
					stepIsPlayer = result.IsPlayer
				elseif result.Type == "Faint" and result.Creature then
					local playerName = (battle.PlayerCreature and (battle.PlayerCreature.Nickname or battle.PlayerCreature.Name)) or ""
					local foeName = (battle.FoeCreature and (battle.FoeCreature.Nickname or battle.FoeCreature.Name)) or ""
					if result.Creature == playerName then
						stepIsPlayer = true
					elseif result.Creature == foeName then
						stepIsPlayer = false
					end
				end
				if stepIsPlayer == nil then
					stepIsPlayer = action.IsPlayer
				end

				if result.Type == "Faint" then
					local faintKey = tostring(result.Creature or "")
					if faintKey ~= "" and faintAddedByCreature[faintKey] then
						DBG:print("Skipping duplicate FAINT for creature:", faintKey)
					else
						-- For ordering: attach FAINT to the same side as the triggering action
						stepIsPlayer = action.IsPlayer
						
						-- ROBUST faint detection: check IsPlayer flag, creature name, or HP values
						local faintIsPlayerCreature = false
						if result.IsPlayer == true then
							faintIsPlayerCreature = true
						elseif result.IsPlayer == false then
							faintIsPlayerCreature = false
						elseif result.Creature then
							-- Match creature name to determine who fainted
							local playerName = (battle.PlayerCreature and (battle.PlayerCreature.Nickname or battle.PlayerCreature.Name)) or ""
							local foeName = (battle.FoeCreature and (battle.FoeCreature.Nickname or battle.FoeCreature.Name)) or ""
							if result.Creature == playerName then
								faintIsPlayerCreature = true
							elseif result.Creature == foeName then
								faintIsPlayerCreature = false
							end
						end
						-- Fallback: check HP values to determine who fainted
						if result.IsPlayer == nil and result.Creature == nil then
							local playerHP = battle.PlayerCreature and battle.PlayerCreature.Stats and battle.PlayerCreature.Stats.HP or 1
							local foeHP = battle.FoeCreature and battle.FoeCreature.Stats and battle.FoeCreature.Stats.HP or 1
							if playerHP <= 0 and foeHP > 0 then
								faintIsPlayerCreature = true
							elseif foeHP <= 0 and playerHP > 0 then
								faintIsPlayerCreature = false
							end
						end
						
						DBG:print("[Faint] Single result - faintIsPlayerCreature:", faintIsPlayerCreature, "IsPlayer:", result.IsPlayer, "Creature:", result.Creature)
						
						-- CRITICAL: Set the IsPlayer field on the result to indicate WHICH CREATURE fainted
						-- This is essential for client-side reordering logic which checks step.IsPlayer == false
						-- to detect foe faints and properly order SwitchPreview before SendOut
						result.IsPlayer = faintIsPlayerCreature
						
						if faintIsPlayerCreature then
							playerFaintedThisTurn = true
						else
							foeFaintedThisTurn = true
							-- Clear status conditions when foe creature faints
							local StatusModule = require(game:GetService("ReplicatedStorage").Shared.Status)
							if battle.FoeCreature then
								if StatusModule and StatusModule.Remove then
									StatusModule.Remove(battle.FoeCreature)
								else
									battle.FoeCreature.Status = nil
								end
								battle.FoeCreature.VolatileStatus = nil
							end
						end
						-- Use faintIsPlayerCreature to determine which list to add the step to
						-- This ensures the Faint step is correctly categorized based on WHO FAINTED, not who triggered it
						if faintIsPlayerCreature then
							if not playerFaintAdded then
								addStepWithOrder(friendlyActions, result)
								playerFaintAdded = true
								if faintKey ~= "" then
									faintAddedByCreature[faintKey] = true
								end
							else
								DBG:print("Skipping duplicate PLAYER faint step (single result)")
							end
						else
							if not foeFaintAdded then
								addStepWithOrder(enemyActions, result)
								foeFaintAdded = true
								if faintKey ~= "" then
									faintAddedByCreature[faintKey] = true
								end
								-- Award XP immediately after foe faint step (for trainer battles)
								-- This ensures XP steps have ExecOrder values right after the faint step
								awardXPAfterFoeFaint(battle.FoeCreature)
							else
								DBG:print("Skipping duplicate FOE faint step (single result)")
							end
						end
					end
				else
					if stepIsPlayer then
						addStepWithOrder(friendlyActions, result)
					else
						addStepWithOrder(enemyActions, result)
					end
				end
			end

			-- Check if battle should end (creature fainted or capture completed)
			-- Allow forced switch if player fainted but has remaining party
			local endNow = false
			if battle.CaptureCompleted then
				endNow = true
			elseif battle.FoeCreature and battle.FoeCreature.Stats and battle.FoeCreature.Stats.HP <= 0 then
				-- Clear status conditions when foe creature faints
				local StatusModule = require(game:GetService("ReplicatedStorage").Shared.Status)
				if StatusModule and StatusModule.Remove then
					StatusModule.Remove(battle.FoeCreature)
				else
					battle.FoeCreature.Status = nil
				end
				battle.FoeCreature.VolatileStatus = nil

				-- Mark current foe as defeated in the party (update HP to reflect fainted state)
				if battle.Type == "Trainer" and type(battle.TrainerParty) == "table" and battle.FoeCreatureIndex then
					local currentFoe = battle.TrainerParty[battle.FoeCreatureIndex]
					if currentFoe then
						if currentFoe.Stats then
							currentFoe.Stats.HP = 0
						end
						if currentFoe.CurrentHP ~= nil then
							currentFoe.CurrentHP = 0
						end
						-- Clear status in trainer party data too
						if StatusModule and StatusModule.Remove then
							StatusModule.Remove(currentFoe)
						else
							currentFoe.Status = nil
						end
						currentFoe.VolatileStatus = nil
						DBG:print("[KO/Switch] Marked party slot", battle.FoeCreatureIndex, "as defeated:", (currentFoe.Nickname or currentFoe.Name))
					end
				end

				-- If trainer has more usable creatures, send out the next one instead of ending
				if battle.Type == "Trainer" and type(battle.TrainerParty) == "table" then
					local nextIndex, nextCreature
					for i2, c in ipairs(battle.TrainerParty) do
						local hp = (c and ((c.Stats and c.Stats.HP) or c.CurrentHP)) or 0
						DBG:print("[KO/Switch] Checking party slot", i2, ":", (c and (c.Nickname or c.Name) or "nil"), "HP:", hp)
						if c and hp > 0 then
							nextIndex = i2
							nextCreature = c
							DBG:print("[KO/Switch] Found usable creature at slot", i2)
							break
						end
					end
					if nextCreature then
						DBG:print("[KO/Switch] Trainer creature KO detected - sending out next creature")
						DBG:print("[KO/Switch] Current foe:", (battle.FoeCreature.Nickname or battle.FoeCreature.Name), "HP:", battle.FoeCreature.Stats.HP)
						DBG:print("[KO/Switch] Next creature:", (nextCreature.Nickname or nextCreature.Name), "HP:", (nextCreature.Stats and nextCreature.Stats.HP or nextCreature.CurrentHP or "?"))
						DBG:print("[KO/Switch] Next creature index:", nextIndex)

						-- NOTE: XP is now awarded immediately after the faint step is added in the turn loop
						-- This ensures correct message order: Move -> Damage -> Faint -> XP -> LevelUp -> SwitchPreview -> SendOut

						-- Add SwitchPreview step to ask player if they want to switch
						addStepWithOrder(enemyActions, {
							Type = "SwitchPreview",
							TrainerName = battle.TrainerName,
							NextCreature = (nextCreature.Nickname or nextCreature.Name),
							IsPlayer = false,
						})
						-- Set flag to allow switch during preview
						battle.AllowPreviewSwitch = true
						DBG:print("[KO/Switch] Added SwitchPreview step for", (nextCreature.Nickname or nextCreature.Name))
						DBG:print("[KO/Switch] Enabled AllowPreviewSwitch flag")

						-- Store next creature info but DON'T send it out inline.
						-- The send-out will be emitted at the start of the next turn AFTER the player answers the preview prompt.
						battle.NextFoeCreature = nextCreature
						battle.NextFoeCreatureIndex = nextIndex
						battle.PendingTrainerSendOut = true
						-- Explicitly mark that the send-out is deferred so the turn-start handler will emit a fresh TurnResult.
						battle.SendOutInline = false
						DBG:print("[KO/Switch] Stored next creature for deferred send-out (SendOutInline=false)")
						-- Don't end the battle yet - trainer still has creatures
						endNow = false
					else
						DBG:print("[KO/Switch] No remaining creatures found - battle will end")
						endNow = true
					end
				else
					endNow = true
				end
			elseif battle.PlayerCreature.Stats.HP <= 0 then
				local pd = ClientData:Get(Player)
				local alive = FindFirstAliveCreature(pd and pd.Party)
				if not alive then
					endNow = true
				else
					battle.SwitchMode = "Forced"
				end
			end
			if endNow then
				break -- Stop processing remaining actions
			end
		end

		-- Update HP data with values AFTER moves but BEFORE end-of-turn effects
		hpData.Player = battle.PlayerCreature.Stats.HP
		hpData.PlayerMax = battle.PlayerCreature.MaxStats.HP
		hpData.Enemy = battle.FoeCreature.Stats.HP
		hpData.EnemyMax = battle.FoeCreature.MaxStats.HP

		-- Determine if foe fainted and whether the battle will end immediately (final foe)
		local isFinalFoeFaint = false
		if foeFaintedThisTurn then
			if battle.Type == "Trainer" then
				-- If a trainer has a next creature queued (PendingTrainerSendOut), it's NOT final
				isFinalFoeFaint = (battle.PendingTrainerSendOut ~= true)
			else
				-- Wild battles end on foe faint
				isFinalFoeFaint = true
			end
		end

		-- NOTE: XP is now awarded immediately after the faint step is added in the turn loop
		-- This ensures correct message order: Move -> Damage -> Faint -> XP -> LevelUp -> SwitchPreview -> SendOut.
		-- This section is kept as a fallback for any edge cases where XP wasn't awarded during the faint handling.
		if foeFaintedThisTurn and not isFinalFoeFaint then
			local defeated = battle.FoeCreature
			-- Only award if not already marked (faint handling should have already awarded XP)
			local alreadyAwarded = battle.Type == "Trainer" 
				and battle.TrainerParty 
				and battle.FoeCreatureIndex 
				and battle.TrainerParty[battle.FoeCreatureIndex] 
				and battle.TrainerParty[battle.FoeCreatureIndex]._XPAwarded == true
			if defeated and not alreadyAwarded then
				DBG:print("[XP] Fallback XP award - this should not normally happen (XP should be awarded immediately after faint step)")
				local xpSteps = ServerFunctions:AwardBattleXP(Player, defeated, battle)
				if type(xpSteps) == "table" and #xpSteps > 0 then
					for _, step in ipairs(xpSteps) do
						addStepWithOrder(friendlyActions, step)
					end
				end
				-- Mark XP as already awarded for this trainer creature to avoid double-award at battle end
				if battle.Type == "Trainer" and battle.TrainerParty and battle.FoeCreatureIndex and battle.TrainerParty[battle.FoeCreatureIndex] then
					battle.TrainerParty[battle.FoeCreatureIndex]._XPAwarded = true
				end
			end
		end

		-- End-of-turn effects (skip if battle ends now due to final foe faint or capture completed)
		-- IMPORTANT: These effects are part of the CURRENT turn, not a new turn.
		-- They are added to friendlyActions/enemyActions BEFORE TurnId increments.
		-- Order: All moves execute first, THEN end-of-turn effects (status damage, then healing)
		-- This ensures proper Pokemon-like turn order: Move -> Status from move -> End-of-turn effects
		if not isFinalFoeFaint and not (battle and battle.CaptureCompleted == true) then
			-- Process Status end-of-turn damage FIRST (before healing, as damage happens before healing in Pokemon)
			-- These steps are added to the action lists and will be processed as part of this turn's TurnResult
			local StatusModule = require(game:GetService("ReplicatedStorage").Shared.Status)

			local function applyStatusDamage(creature, isPlayerSide)
				if not creature or not creature.Stats or creature.Stats.HP <= 0 then
					return
				end
				if not creature.Status then
					return
				end

				local statusDamage = StatusModule.ProcessEndOfTurn(creature)
				if not statusDamage or statusDamage <= 0 then
					return
				end

				local maxHP = creature.MaxStats and creature.MaxStats.HP or 1
				local beforeHP = creature.Stats.HP or 0
				creature.Stats.HP = math.max(0, beforeHP - statusDamage)

				local statusType = creature.Status and creature.Status.Type
				local creatureName = creature.Nickname or creature.Name or (isPlayerSide and "Your creature" or "Foe")
				local statusMessage = statusType == "BRN" and (creatureName .. " is hurt by its burn!") or statusType == "PSN" and (creatureName .. " is hurt by poison!") or statusType == "TOX" and (creatureName .. " is hurt by toxic poison!") or (creatureName .. " is hurt by its status!")

				local step = {
					Type = "Damage",
					Effectiveness = "Normal",
					IsPlayer = isPlayerSide,
					Message = statusMessage,
					DelaySeconds = 0.6, -- allow UI time to display message before HP tween
					EndOfTurn = true, -- signal client to avoid pre-damage visual adjustments
					NewHP = creature.Stats.HP, -- explicit target HP after the damage
					MaxHP = maxHP,
				}

				DBG:print("[ServerFunctions][Status] applying:", creatureName, "before:", beforeHP, "-", statusDamage, "->", creature.Stats.HP, "Status:", statusType)

				if isPlayerSide then
					addStepWithOrder(friendlyActions, step)
					-- Update player party data
					local pd = ClientData:Get(Player)
					if pd and pd.Party and battle.PlayerCreatureIndex then
						local slot = pd.Party[battle.PlayerCreatureIndex]
						if slot then
							slot.Stats = slot.Stats or {}
							slot.Stats.HP = creature.Stats.HP
							local m = creature.MaxStats and creature.MaxStats.HP or slot.MaxStats and slot.MaxStats.HP
							if m and m > 0 then
								slot.CurrentHP = math.clamp(math.floor((creature.Stats.HP / m) * 100 + 0.5), 0, 100)
							end
							if ClientData.UpdateClientData then
								ClientData:UpdateClientData(Player, pd)
							end
						end
					end
				else
					addStepWithOrder(enemyActions, step)
				end
			end

			-- Apply status damage to both creatures
			-- Note: Status damage affects the creature, so player damage goes to friendlyActions, foe damage goes to enemyActions
			applyStatusDamage(battle.PlayerCreature, true)
			applyStatusDamage(battle.FoeCreature, false)

			-- Process Sandstorm end-of-turn chip damage (after status damage, before healing)
			local function isImmuneToSandstorm(creature)
				if not creature or not creature.Type then
					return false
				end
				local types = {}
				local defT = creature.Type
				if type(defT) == "string" then
					table.insert(types, defT)
				elseif type(defT) == "table" then
					for _, t in ipairs(defT) do
						if type(t) == "string" then
							table.insert(types, t)
						end
					end
				end
				for _, t in ipairs(types) do
					if t == "Rock" or t == "Ground" or t == "Steel" then
						return true
					end
				end
				return false
			end
			
			local function applySandstormDamage(creature, isPlayerSide)
				if not creature or not creature.Stats or creature.Stats.HP <= 0 then
					return
				end
				if battle.Weather ~= "Sandstorm" then
					return
				end
				if isImmuneToSandstorm(creature) then
					return
				end
				
				local maxHP = creature.MaxStats and creature.MaxStats.HP or 1
				local sandstormDamage = math.max(1, math.floor(maxHP / 16))
				local beforeHP = creature.Stats.HP or 0
				creature.Stats.HP = math.max(0, beforeHP - sandstormDamage)
				
				local creatureName = creature.Nickname or creature.Name or (isPlayerSide and "Your creature" or "Foe")
				local step = {
					Type = "Damage",
					Effectiveness = "Normal",
					IsPlayer = isPlayerSide,
					Message = creatureName .. " is buffeted by the sandstorm!",
					DelaySeconds = 0.6,
					EndOfTurn = true,
					NewHP = creature.Stats.HP,
					MaxHP = maxHP,
				}
				
				DBG:print("[ServerFunctions][Sandstorm] applying:", creatureName, "before:", beforeHP, "-", sandstormDamage, "->", creature.Stats.HP)
				
				if isPlayerSide then
					addStepWithOrder(friendlyActions, step)
					-- Update player party data
					local pd = ClientData:Get(Player)
					if pd and pd.Party and battle.PlayerCreatureIndex then
						local slot = pd.Party[battle.PlayerCreatureIndex]
						if slot then
							slot.Stats = slot.Stats or {}
							slot.Stats.HP = creature.Stats.HP
							local m = creature.MaxStats and creature.MaxStats.HP or slot.MaxStats and slot.MaxStats.HP
							if m and m > 0 then
								slot.CurrentHP = math.clamp(math.floor((creature.Stats.HP / m) * 100 + 0.5), 0, 100)
							end
							if ClientData.UpdateClientData then
								ClientData:UpdateClientData(Player, pd)
							end
						end
					end
				else
					addStepWithOrder(enemyActions, step)
				end
			end
			
			-- Apply Sandstorm damage to both creatures
			applySandstormDamage(battle.PlayerCreature, true)
			applySandstormDamage(battle.FoeCreature, false)

			-- THEN process held item effects (like Crumbs healing) - healing happens after damage
			-- IMPORTANT: To get correct turn order (Player move -> Status -> Enemy move -> Player Crumbs -> Enemy Crumbs -> Burn damage),
			-- we need to add player Crumbs to enemyActions so it appears after enemy moves.
			-- The client processes friendlyActions first, then enemyActions, so:
			-- - friendlyActions: [Player move]
			-- - enemyActions: [Status, Enemy move, Player Crumbs, Enemy Crumbs, Burn damage]
			-- This gives the correct order!
			local function processCrumbsForOrder(holder, isPlayerSide)
				local heldName = holder and holder.HeldItem and tostring(holder.HeldItem) or ""
				heldName = heldName:lower():gsub("^%s+", " "):gsub("%s+$", " ")
				if holder and heldName == "crumbs" then
					if holder.Stats and holder.MaxStats and holder.Stats.HP > 0 then
						local maxHP = holder.MaxStats.HP or 1
						local heal = math.max(1, math.floor(maxHP / 16))
						local beforeHP = holder.Stats.HP or 0
						holder.Stats.HP = math.min(maxHP, beforeHP + heal)
						local cname = (holder.Nickname or holder.Name or (isPlayerSide and "Your creature" or "Foe"))
						local step = {
							Type = "Heal",
							Amount = heal,
							IsPlayer = isPlayerSide, -- Keep IsPlayer flag correct for UI targeting
							Message = tostring(cname) .. " regained some HP thanks to Crumbs!",
							DelaySeconds = 0.6,
							EndOfTurn = true,
							NewHP = holder.Stats.HP,
							MaxHP = maxHP,
						}
						-- Add ALL Crumbs to enemyActions to ensure correct order
						addStepWithOrder(enemyActions, step)
						if isPlayerSide then
							local pd = ClientData:Get(Player)
							if pd and pd.Party and battle.PlayerCreatureIndex then
								local slot = pd.Party[battle.PlayerCreatureIndex]
								if slot then
									slot.Stats = slot.Stats or {}
									slot.Stats.HP = holder.Stats.HP
									local m = holder.MaxStats and holder.MaxStats.HP or slot.MaxStats and slot.MaxStats.HP
									if m and m > 0 then
										slot.CurrentHP = math.clamp(math.floor((holder.Stats.HP / m) * 100 + 0.5), 0, 100)
									end
									if ClientData.UpdateClientData then
										ClientData:UpdateClientData(Player, pd)
									end
								end
							end
						end
					end
				end
			end

			processCrumbsForOrder(battle.PlayerCreature, true)
			processCrumbsForOrder(battle.FoeCreature, false)

			-- Process Ability end-of-turn effects (Speed Boost, Desert Reservoir, etc.)
			local function processAbilityEndTurn(creature, isPlayerCreature)
				local Abilities = require(game:GetService("ReplicatedStorage").Shared.Abilities)
				local ability = Abilities.GetName(creature)
				if not ability then
					return
				end
				local norm = string.lower(ability)

				-- Desert Reservoir: Recovers HP in sunlight (or switch out, handled elsewhere)
				-- if norm == "desert reservoir" and battle.Weather == "Sunlight" then
				-- Heal(creature, 1/16)
				-- end

				-- Speed Boost (Steadspeed?)
				-- if norm == "speed boost" then ... end
			end
			processAbilityEndTurn(battle.PlayerCreature, true)
			processAbilityEndTurn(battle.FoeCreature, false)
		end

		-- Ensure every Damage step carries NewHP for the defender so client can apply at the correct time
		local function backfillDamageNewHP(stepList)
			if type(stepList) ~= "table" then
				return
			end
			for _, s in ipairs(stepList) do
				if type(s) == "table" and s.Type == "Damage" and type(s.NewHP) ~= "number" then
					-- If the actor was the player, the defender was the enemy; otherwise the player
					-- We infer defender side by reading IsPlayer on the preceding Move in turn building,
					-- but here we can map by presence of Enemy vs Player damage patterns already applied.
					-- When IsPlayer is true on the Damage step, it represents the attacker (our pipeline sets it to the attacker side).
					local attackerIsPlayer = (s.IsPlayer == true)
					if attackerIsPlayer then
						s.NewHP = battle.FoeCreature and battle.FoeCreature.Stats and battle.FoeCreature.Stats.HP or nil
					else
						s.NewHP = battle.PlayerCreature and battle.PlayerCreature.Stats and battle.PlayerCreature.Stats.HP or nil
					end
				end
			end
		end

		backfillDamageNewHP(friendlyActions)
		backfillDamageNewHP(enemyActions)

		-- Clear stale switch mode if player is alive at end of turn (prevents client from waiting)
		if not playerFaintedThisTurn then
			local playerAlive = battle.PlayerCreature and battle.PlayerCreature.Stats and (battle.PlayerCreature.Stats.HP > 0)
			if playerAlive then
				battle.SwitchMode = nil
			end
		end

		-- Award XP for wild battles immediately after foe faint (before sending TurnResult)
		-- This ensures XP steps are part of the sequential turn result, appearing after faint
		if foeFaintedThisTurn and battle.Type ~= "Trainer" then
			-- Wild battle: award XP now and add to turn result steps
			local defeatedCreature = battle.FoeCreature
			if defeatedCreature and not defeatedCreature._XPAwarded then
				DBG:print("[XP][Wild] Awarding XP before TurnResult for wild battle")
				local xpSteps = ServerFunctions:AwardBattleXP(Player, defeatedCreature, battle)
				if type(xpSteps) == "table" and #xpSteps > 0 then
					for _, step in ipairs(xpSteps) do
						addStepWithOrder(friendlyActions, step)
					end
					DBG:print("[XP][Wild] Added", #xpSteps, "XP steps to turn result")
				end
				-- Mark XP as awarded to prevent double-awarding at battle end
				defeatedCreature._XPAwarded = true
			end
		end

		-- Advance TurnId and send turn result to client
		battle.TurnId = (battle.TurnId or 0) + 1
		-- Prefer sending ExecOrder-ordered lists when available so clients can
		-- merge/sort steps in true execution order. Fall back to legacy lists.
		local sendFriendly = friendlyActions
		local sendEnemy = enemyActions
		-- If either list already contains ExecOrder tags, merge+sort them here
		-- and re-split into perspective lists. This avoids relying on helper
		-- functions that may be out of scope in some call paths.
		local function listsContainExec(a, b)
			if type(a) == "table" then
				for _, v in ipairs(a) do
					if type(v) == "table" and v.ExecOrder then return true end
				end
			end
			if type(b) == "table" then
				for _, v in ipairs(b) do
					if type(v) == "table" and v.ExecOrder then return true end
				end
			end
			return false
		end
		if listsContainExec(friendlyActions, enemyActions) then
			local all = {}
			-- Tag origin so we can split after sorting
			for _, s in ipairs(friendlyActions) do
				if type(s) == "table" then
					s.__fromFriendly = true
					table.insert(all, s)
				end
			end
			for _, s in ipairs(enemyActions) do
				if type(s) == "table" then
					s.__fromFriendly = false
					table.insert(all, s)
				end
			end
			table.sort(all, function(a, b)
				return (a.ExecOrder or 9999) < (b.ExecOrder or 9999)
			end)
			local pf, pe = {}, {}
			for _, s in ipairs(all) do
				if s.__fromFriendly then
					table.insert(pf, s)
				else
					table.insert(pe, s)
				end
				-- cleanup temp flag
				s.__fromFriendly = nil
			end
			sendFriendly = pf
			sendEnemy = pe
		end

		DBG:print("=== SENDING TURN RESULT TO CLIENT ===")
		DBG:print("Friendly actions count (sent):", #sendFriendly)
		for i, action in ipairs(sendFriendly) do
			DBG:print("Friendly", i, "Type:", action.Type, "IsPlayer:", action.IsPlayer, "Creature:", action.Creature, "Move:", action.Move, "Message:", action.Message, "ExecOrder:", action.ExecOrder)
		end
		DBG:print("Enemy actions count (sent):", #sendEnemy)
		for i, action in ipairs(sendEnemy) do
			DBG:print("Enemy", i, "Type:", action.Type, "IsPlayer:", action.IsPlayer, "Creature:", action.Creature, "Move:", action.Move, "Message:", action.Message, "ExecOrder:", action.ExecOrder)
		end
		DBG:print("=== END TURN RESULT ===")

		-- CRITICAL: Update hpData to reflect new creature if trainer switched out
		-- This prevents the client from "syncing" to the old fainted creature's HP (0)
		if battle.PendingTrainerSendOut and battle.SendOutInline and battle.NextFoeCreature then
			hpData = {
				Player = battle.PlayerCreature.Stats.HP,
				PlayerMax = battle.PlayerCreature.MaxStats.HP,
				Enemy = battle.NextFoeCreature.Stats.HP,
				EnemyMax = battle.NextFoeCreature.MaxStats.HP,
			}
			DBG:print("[ProcessTurn] Updated hpData for new trainer creature - Enemy HP:", hpData.Enemy, "/", hpData.EnemyMax)
		end

		local Events = game.ReplicatedStorage.Events
		if Events and Events.Communicate then
			-- Hint to client if this turn will end the battle (prevents edge-case stalls)
			local willEnd = false
			if foeFaintedThisTurn then
				if battle.Type == "Trainer" and type(battle.TrainerParty) == "table" then
					local hasRemaining = false
					for _, c in ipairs(battle.TrainerParty) do
						if c and c ~= battle.FoeCreature then
							local hp = (c.CurrentHP or (c.Stats and c.Stats.HP) or 0)
							if hp > 0 then
								hasRemaining = true
								break
							end
						end
					end
					willEnd = not hasRemaining
				else
					-- Wild: foe faint ends battle
					willEnd = true
				end
			end
			local turnResult = {
				-- Send ordered lists when available so client preserves server chronology.
				Friendly = sendFriendly,
				Enemy = sendEnemy,
				HP = hpData,
				PlayerCreatureIndex = battle.PlayerCreatureIndex or 1,
				PlayerCreature = battle.PlayerCreature,
				FoeCreatureIndex = battle.FoeCreatureIndex or 1,
				FoeCreature = battle.FoeCreature,
				TurnId = battle.TurnId,
				-- Only signal Forced when it occurred this turn; otherwise omit to avoid stale client state
				SwitchMode = (playerFaintedThisTurn and "Forced") or nil,
				BattleEnd = willEnd,
			}
			_logBattleMessages("TurnResult:" .. Player.Name, turnResult)
			Events.Communicate:FireClient(Player, "TurnResult", turnResult)
		end

		-- Clear player action for next turn
		battle.PlayerAction = nil

		-- Check if battle should end BEFORE promoting next creature (to avoid checking wrong creature)
		local shouldEndAfterPromotion = false
		if battle.PendingTrainerSendOut and not battle.NextFoeCreature then
			-- Pending send-out but no next creature means all trainer creatures are defeated
			shouldEndAfterPromotion = true
			DBG:print("[PostTurn] No next creature available - battle will end after current turn")
		end

		-- Promote next creature AFTER TurnResult is sent (so HP data is correct)
		if battle.PendingTrainerSendOut and battle.SendOutInline and battle.NextFoeCreature then
			DBG:print("[PostTurn] Promoting next creature to battle.FoeCreature (no enemy action this frame)")
			DBG:print("[PostTurn] Old foe:", (battle.FoeCreature.Nickname or battle.FoeCreature.Name), "HP:", battle.FoeCreature.Stats.HP)
			battle.FoeCreature = battle.NextFoeCreature
			battle.FoeCreatureIndex = battle.NextFoeCreatureIndex
			DBG:print("[PostTurn] New foe:", (battle.FoeCreature.Nickname or battle.FoeCreature.Name), "HP:", battle.FoeCreature.Stats.HP)
			battle.NextFoeCreature = nil
			battle.NextFoeCreatureIndex = nil
			battle.PendingTrainerSendOut = false
			-- Do not freeze enemy action for the next turn; skipping is handled within the preview switch turn itself
		end

		-- End battle only when capture completed or a side has no remaining creatures
		local endBattle = false
		local endReason = nil
		if battle.CaptureCompleted then
			endBattle = true
			endReason = "Capture"
		elseif shouldEndAfterPromotion or isFinalFoeFaint or (foeFaintedThisTurn and battle.Type == "Wild") or (battle.FoeCreature and battle.FoeCreature.Stats and battle.FoeCreature.Stats.HP <= 0) then
			-- For trainer battles, check if there are any remaining usable creatures
			if battle.Type == "Trainer" and type(battle.TrainerParty) == "table" then
				DBG:print("[BattleEnd] Checking trainer party for remaining creatures")
				DBG:print("[BattleEnd] Current foe:", (battle.FoeCreature.Nickname or battle.FoeCreature.Name), "HP:", battle.FoeCreature.Stats.HP)
				DBG:print("[BattleEnd] Trainer party size:", #battle.TrainerParty)
				local hasRemainingCreatures = false
				for i2, c in ipairs(battle.TrainerParty) do
					if c then
						local hp = (c.CurrentHP or (c.Stats and c.Stats.HP) or 0)
						local name = (c.Nickname or c.Name or "?")
						local isCurrent = (c == battle.FoeCreature)
						DBG:print("[BattleEnd] Party slot", i2, ":", name, "HP:", hp, "IsCurrent:", isCurrent)
						if c ~= battle.FoeCreature and hp > 0 then
							hasRemainingCreatures = true
						end
					end
				end
				if hasRemainingCreatures then
					endBattle = false
					DBG:print("[BattleEnd] Trainer has remaining creatures - battle continues")
				else
					endBattle = true
					endReason = "Win"
					DBG:print("[BattleEnd] Trainer has no remaining creatures - battle ends")
				end
			else
				-- Wild battle: foe faint always ends battle
				endBattle = true
				endReason = "Win"
				DBG:print("[BattleEnd] Wild battle - foe fainted, battle ends")
			end
		elseif battle.PlayerCreature.Stats.HP <= 0 then
			local pd = ClientData:Get(Player)
			local alive = FindFirstAliveCreature(pd and pd.Party)
			if not alive then
				endBattle = true
				endReason = "Loss"
			end
		end
		if endBattle then
			-- Clear SwitchMode when battle ends (prevents client from waiting for switch)
			battle.SwitchMode = nil

			-- Award XP if player won
			if endReason == "Win" then
				local PlayerData = ClientData:Get(Player)
				if PlayerData and PlayerData.Party then
					-- Determine which creatures to award XP for
					-- In trainer battles: all defeated trainer creatures
					-- In wild battles: the single wild creature
					local defeatedCreatures = {}

				if battle.Type == "Trainer" and battle.TrainerParty then
					-- Collect all defeated trainer creatures that have not already had XP awarded mid-battle
					for _, trainerCreature in ipairs(battle.TrainerParty) do
						if trainerCreature and trainerCreature.Stats and trainerCreature.Stats.HP <= 0 and trainerCreature._XPAwarded ~= true then
							table.insert(defeatedCreatures, trainerCreature)
						end
					end
				else
					-- Wild battle - only award XP if not already awarded during turn processing
					if battle.FoeCreature and not battle.FoeCreature._XPAwarded then
						table.insert(defeatedCreatures, battle.FoeCreature)
					end
				end

					-- Award XP for all defeated creatures (accumulated)
					local xpSteps = ServerFunctions:AwardBattleXPForAll(Player, defeatedCreatures, battle)

					-- Send XP steps to client before BattleOver
					if xpSteps and #xpSteps > 0 then
						for _, step in ipairs(xpSteps) do
							-- Track MoveReplacePrompt to validate subsequent decisions
							if step.Type == "MoveReplacePrompt" and type(step.SlotIndex) == "number" then
								_pendingMoveReplace[Player] = _pendingMoveReplace[Player] or {}
								_pendingMoveReplace[Player][step.SlotIndex] = { Move = step.Move, ExpiresAt = os.clock() + 120 }
							end
							Events.Communicate:FireClient(Player, "BattleEvent", step)
						end
					end
				end
			end

			-- Mark trainer as defeated if player won a trainer battle
			DBG:print("[BattleEnd] endReason:", endReason, "Type:", battle.Type, "TrainerId:", battle.TrainerId)
			if endReason == "Win" and battle.Type == "Trainer" and battle.TrainerId then
				local pd = ClientData:Get(Player)
				DBG:print("[BattleEnd] PlayerData exists:", pd ~= nil, "DefeatedTrainers exists:", pd and pd.DefeatedTrainers ~= nil)
				if pd then
					-- Initialize DefeatedTrainers if it doesn't exist (for backwards compatibility)
					if not pd.DefeatedTrainers then
						pd.DefeatedTrainers = {}
						DBG:print("[BattleEnd] Initialized DefeatedTrainers table for player:", Player.Name)
					end
					pd.DefeatedTrainers[battle.TrainerId] = true
					DBG:print("[BattleEnd] Marked trainer", battle.TrainerId, "as defeated for player:", Player.Name)

					-- Special case: first rival battle vs Kyro
					if tostring(battle.TrainerId) == "Rival_Kyro_Intro" then
						pd.Events = pd.Events or {}
						if pd.Events.FIRST_BATTLE ~= true then
							pd.Events.FIRST_BATTLE = true
							DBG:print("[BattleEnd] Marked FIRST_BATTLE for player:", Player.Name)
						end
					end

					-- Special case: first gym leader (Vincent) – award first badge
					if tostring(battle.TrainerId) == "Gym1_Leader_Vincent" then
						pd.Badges = math.max(pd.Badges or 0, 1)
						pd.Events = pd.Events or {}
						if pd.Events.FIRST_GYM_COMPLETED ~= true then
							pd.Events.FIRST_GYM_COMPLETED = true
						end
						DBG:print("[BattleEnd] Awarded first gym badge to player:", Player.Name, "Badges now:", pd.Badges)
					end
					
					-- Update challenge progress for defeating trainer
					if ChallengesSystem then
						pcall(function()
							ChallengesSystem.UpdateProgress(Player, "DefeatTrainers", 1)
						end)
					end
				else
					DBG:warn("[BattleEnd] Could not mark trainer as defeated - PlayerData missing")
				end
			else
				DBG:print("[BattleEnd] Not marking trainer as defeated - conditions not met")
				
				-- If player won a wild battle, update challenge progress
				if endReason == "Win" and battle.Type == "Wild" then
					if ChallengesSystem then
						pcall(function()
							ChallengesSystem.UpdateProgress(Player, "WinWildBattles", 1)
						end)
					end
				end
			end

			if Events and Events.Communicate then
				-- Include trainer defeat info for client to update its cache
				local battleOverData = {
					Reason = endReason,
					Rewards = { XP = 0, Studs = 0 },
				}

				-- Calculate studs loss if player lost
				if endReason == "Loss" then
					local PlayerData = ClientData:Get(Player)
					local highestLevel = 1
					if PlayerData and PlayerData.Party then
						for _, creature in ipairs(PlayerData.Party) do
							if creature and creature.Level and creature.Level > highestLevel then
								highestLevel = creature.Level
							end
						end
					end

					-- Studs Lost = Highest creature Level × Base Payout (based on badges)
					local basePayout = { 8, 16, 24, 36, 48, 60, 80, 100, 120 }
					local badges = PlayerData.Badges or 0
					local badgeIndex = math.min(badges + 1, #basePayout) -- 1-based index, cap at max badges
					local baseReward = basePayout[badgeIndex] or basePayout[1] -- Default to 8 if no badges

					local studsLoss = highestLevel * baseReward
					battleOverData.StudsLost = studsLoss

					-- Deduct studs from player
					PlayerData.Studs = math.max(0, (PlayerData.Studs or 0) - studsLoss)
					ClientData:UpdateClientData(Player, PlayerData)

					DBG:print("[BattleEnd] Player lost - deducted", studsLoss, "studs (highest level:", highestLevel, ", badges:", badges, ", base payout:", baseReward, ")")
				end

				-- If trainer was defeated, tell client to update its cache
				if endReason == "Win" and battle.Type == "Trainer" and battle.TrainerId then
					battleOverData.DefeatedTrainerId = battle.TrainerId
				end
				-- Clear any pending requests on both players in PvP
				if battle.Type == "PvP" then
					Events.Communicate:FireClient(Player, "ClearRequests")
					local foePlayer = battle.OpponentPlayer
					if foePlayer and foePlayer.Parent then
						Events.Communicate:FireClient(foePlayer, "ClearRequests")
					end
				end
				-- Finalize: restore party state from pre-battle snapshot, then clear it
				_restorePendingBattleSnapshot(Player)
				if battle.Type == "PvP" and battle.OpponentPlayer then
					_restorePendingBattleSnapshot(battle.OpponentPlayer)
				end
				Events.Communicate:FireClient(Player, "BattleOver", battleOverData)
				-- Event-based save after battle completes ONLY if AutoSave is enabled and not during cutscenes
				local currentData = ClientData:Get(Player)
				local allowAuto = (currentData and currentData.Settings and currentData.Settings.AutoSave) == true
					and (currentData and currentData.InCutscene ~= true)
				if allowAuto and _saveNow then
					_saveNow(Player)
				end
				-- Clear in-battle flag so autosave resumes
				local pd2 = ClientData:Get(Player)
				if pd2 then
					pd2.InBattle = false
					ClientData:UpdateClientData(Player, pd2)
				end
			end

			-- Check for evolutions after battle (after sending BattleOver to avoid blocking)
			if endReason == "Win" then
				DBG:print("[Evolution] Battle won - scheduling evolution check for player:", Player.Name)
				task.spawn(function()
					task.wait(0.1) -- Small delay to ensure ClientData is updated
					local success, err = pcall(function()
						DBG:print("[Evolution] Running CheckPartyEvolutions for player:", Player.Name)
						ServerFunctions:CheckPartyEvolutions(Player)
					end)
					if not success then
						warn("[Evolution] Error checking party for evolutions:", err)
					end
				end)
			else
				DBG:print("[Evolution] Battle not won (endReason:", endReason, ") - skipping evolution check")
			end

			ServerFunctions:ClearBattleData(Player)
		end

		return true
	end
end

return ProcessTurn


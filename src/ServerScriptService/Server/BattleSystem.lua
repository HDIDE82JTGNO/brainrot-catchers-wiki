--!strict
--[[
	BattleSystem.lua
	Handles battle execution logic: move processing, turn order, action execution
	Separated from ServerFunctions for better organization
]]

local BattleSystem = {}

-- Dependencies (will be injected)
local ActiveBattles: {[Player]: any} = {}
local ClientData: any = nil
local Events: any = nil
local DBG: any = nil
local MovesModule: any = nil
local AbilitiesModule: any = nil
local CreaturesModule: any = nil
local StatCalc: any = nil
local Natures: any = nil
local CreatureFactory: any = nil
local TypesModule: any = nil
local DamageCalculator: any = nil
local HeldItemEffects: any = nil
local XPManager: any = nil
local XPAwarder: any = nil
local CreatureSystem: any = nil
local StatStages: any = nil
local ObedienceModule: any = nil

-- Config module (required directly)
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ServerScriptService.Server.GameData.Config)

-- Trainer/Wild AI
local AIController = require(script.Parent.Battle.AIController)

--[[
	Initialize BattleSystem with dependencies
	@param dependencies Table containing all required modules
]]
function BattleSystem.Initialize(dependencies: {[string]: any})
	ActiveBattles = dependencies.ActiveBattles
	ClientData = dependencies.ClientData
	Events = dependencies.Events
	DBG = dependencies.DBG
	MovesModule = dependencies.MovesModule
	AbilitiesModule = dependencies.AbilitiesModule
	CreaturesModule = dependencies.CreaturesModule
	StatCalc = dependencies.StatCalc
	Natures = dependencies.Natures
	CreatureFactory = dependencies.CreatureFactory
	TypesModule = dependencies.TypesModule
	DamageCalculator = dependencies.DamageCalculator
	HeldItemEffects = dependencies.HeldItemEffects
	XPManager = dependencies.XPManager
	XPAwarder = dependencies.XPAwarder
	CreatureSystem = dependencies.CreatureSystem
	ObedienceModule = dependencies.ObedienceModule
	
	-- Load StatStages module
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	StatStages = require(ReplicatedStorage.Shared.StatStages)
end

-- Damage + accuracy are handled by `Server/Battle/DamageCalculator.lua` (single source of truth).

--[[
	Calculates the number of hits for a multi-hit move
	Uses Pokemon-style probability distribution for 2-5 hit moves:
	- 2 hits: 35% (35/100)
	- 3 hits: 35% (35/100)
	- 4 hits: 15% (15/100)
	- 5 hits: 15% (15/100)
	@param multiHitConfig The MultiHit configuration from the move
	@return number The number of hits this attack will perform
]]
local function CalculateMultiHitCount(multiHitConfig: any): number
	if not multiHitConfig then return 1 end
	
	local minHits = multiHitConfig.MinHits or 2
	local maxHits = multiHitConfig.MaxHits or 5
	local fixed = multiHitConfig.Fixed
	
	-- Fixed hit count (e.g., Double Kick always hits exactly twice)
	if fixed then
		return minHits
	end
	
	-- Variable hit count with Pokemon-style distribution
	if minHits == 2 and maxHits == 5 then
		-- Standard 2-5 hit distribution
		local roll = math.random(1, 100)
		if roll <= 35 then
			return 2
		elseif roll <= 70 then
			return 3
		elseif roll <= 85 then
			return 4
		else
			return 5
		end
	elseif minHits == 3 and maxHits == 3 then
		-- Fixed 3 hits (e.g., Triple Kick)
		return 3
	else
		-- Generic random between min and max
		return math.random(minHits, maxHits)
	end
end

--[[
	Execute player move and process enemy turn
	@param Player The player executing the move
	@param MoveData Move data from client
	@return boolean Success status
]]
function BattleSystem.ExecuteMove(Player: Player, MoveData: any): boolean
	DBG:print("Player", Player.Name, "executed move:", MoveData)
	
	-- Get player data
	local PlayerData = ClientData:Get(Player)
	if not PlayerData then
		DBG:warn("No player data found for", Player.Name)
		return false
	end
	
	-- SECURITY: Validate move request
	if not MoveData or not MoveData.MoveIndex or not MoveData.MoveName then
		DBG:warn("Invalid move data from player:", Player.Name, MoveData)
		return false
	end

	-- SECURITY: Validate TurnId to prevent replays/stale actions
	local battle = ActiveBattles[Player]
	local clientTurn = (type(MoveData.TurnId) == "number") and MoveData.TurnId or 0
	if not battle or clientTurn ~= (battle.TurnId or 0) then
		DBG:warn("TurnId mismatch or no battle for", Player.Name, MoveData.TurnId, (battle and battle.TurnId))
		return false
	end
	
	-- SECURITY: Check if player is in an active battle
	if not ActiveBattles[Player] then
		DBG:warn("Player", Player.Name, "attempted to use move without active battle")
		return false
	end
	
	-- Check if player creature is fainted before processing move
	battle = ActiveBattles[Player]
	if battle.PlayerFainted or (battle.PlayerCreature.Stats.HP <= 0) then
		DBG:print("=== PLAYER FAINT DETECTED IN EXECUTE MOVE ===")
		DBG:print("Player creature:", battle.PlayerCreature.Name, "HP:", battle.PlayerCreature.Stats.HP)
		DBG:print("Faint reason - Flag:", battle.PlayerFainted, "HP <= 0:", battle.PlayerCreature.Stats.HP <= 0)
		
		-- Create faint step for the player creature
		local faintStep = {
			Type = "Faint",
			Creature = battle.PlayerCreature.Name or "Your creature",
			IsPlayer = true
		}
		
		-- Send turn result with faint step
		battle.TurnId = (battle.TurnId or 0) + 1
		local turnResult = {
			Friendly = {faintStep},
			Enemy = {},
			HP = {
				Player = battle.PlayerCreature.Stats.HP,
				PlayerMax = battle.PlayerCreature.MaxStats.HP,
				Enemy = battle.FoeCreature.Stats.HP,
				EnemyMax = battle.FoeCreature.MaxStats.HP,
			},
			PlayerCreature = battle.PlayerCreature,
			FoeCreature = battle.FoeCreature,
			TurnId = battle.TurnId,
		}
		
		DBG:print("=== SENDING FAINT TURN RESULT FROM EXECUTE MOVE ===")
		DBG:print("Friendly actions count:", #turnResult.Friendly)
		for i, action in ipairs(turnResult.Friendly) do
			DBG:print("Friendly", i, "Type:", action.Type, "IsPlayer:", action.IsPlayer, "Creature:", action.Creature)
		end
		DBG:print("=== END FAINT TURN RESULT FROM EXECUTE MOVE ===")
		
		if Events and Events.Communicate then
			Events.Communicate:FireClient(Player, "TurnResult", turnResult)
		end
		
		-- Clear the faint flag
		battle.PlayerFainted = false
		
		return true
	end
	
	-- SECURITY: Validate move index (1-4)
	local moveIndex = MoveData.MoveIndex
	if type(moveIndex) ~= "number" or moveIndex < 1 or moveIndex > 4 then
		DBG:warn("Invalid move index from player:", Player.Name, moveIndex)
		return false
	end
	
	-- SECURITY: Get player's active creature and validate move
	local playerCreature = ActiveBattles[Player].PlayerCreature
	if not playerCreature or not playerCreature.CurrentMoves then
		DBG:warn("No active creature or moves for player:", Player.Name)
		return false
	end
	
	-- SECURITY: Check if the move exists in the creature's move set
	local creatureMoves = playerCreature.CurrentMoves
	if not creatureMoves[moveIndex] then
		DBG:warn("Player", Player.Name, "attempted to use non-existent move at index:", moveIndex)
		return false
	end
	
	-- SECURITY: Validate that the move name matches what the creature actually has
	local actualMoveName = creatureMoves[moveIndex]
	if type(actualMoveName) == "string" and actualMoveName ~= MoveData.MoveName then
		DBG:warn("Player", Player.Name, "attempted to use move", MoveData.MoveName, "but creature has", actualMoveName)
		return false
	end
	
	-- Get current battle info and store player's move choice
	DBG:print("Processing move:", MoveData.MoveName or MoveData.Name or "Unknown Move")
	
	-- Resolve move name (check both MoveName and Name for compatibility)
	local moveName = MoveData and (MoveData.MoveName or MoveData.Name or MoveData.Move) or "Unknown Move"
	
	-- Store player's move choice for turn order resolution
	battle = ActiveBattles[Player]
	if not battle then
		DBG:warn("No active battle found for player:", Player.Name)
		return false
	end
	
	-- Store player action
	battle.PlayerAction = {
		Type = "Move",
		Move = moveName,
		MoveIndex = moveIndex,
		MoveData = MoveData
	}
	
	-- Return true - ProcessTurn will be called by ServerFunctions
	-- This allows ServerFunctions:ProcessTurn to handle battle end logic
	return true
end

--[[
	Process turn with proper speed-based order (Pokemon-style)
	@param Player The player whose turn is being processed
	@return boolean Success status
]]
function BattleSystem.ProcessTurn(Player: Player): boolean
	DBG:print("[BattleSystem] ProcessTurn called for player:", Player.Name)
	local battle = ActiveBattles[Player]
	if not battle then
		DBG:warn("No active battle found for player:", Player.Name)
		return false
	end
	DBG:print("[BattleSystem] ProcessTurn - Battle found, Type:", battle.Type)

	-- PvP turn resolution handled in ServerFunctions (action buffering). Do not process here.
	if battle.Type == "PvP" then
		return true
	end
	
	-- Trainer pending send-out handling at turn start
	if battle.Type == "Trainer" and battle.PendingTrainerSendOut and battle.NextFoeCreature then
		if battle.SendOutInline then
			battle.PendingTrainerSendOut = false
			battle.SendOutInline = nil
			battle.FoeCreature = battle.NextFoeCreature
			battle.FoeCreatureIndex = battle.NextFoeCreatureIndex
			battle.NextFoeCreature = nil
			battle.NextFoeCreatureIndex = nil
			-- Reset stat stages for the new trainer creature
			if StatStages then
				StatStages.ResetAll(battle.FoeCreature)
				StatStages.EnsureCreatureHasStages(battle.FoeCreature)
			end
		else
			battle.PendingTrainerSendOut = false
			battle.FoeCreature = battle.NextFoeCreature
			battle.FoeCreatureIndex = battle.NextFoeCreatureIndex
			battle.NextFoeCreature = nil
			battle.NextFoeCreatureIndex = nil
			-- Reset stat stages for the new trainer creature
			if StatStages then
				StatStages.ResetAll(battle.FoeCreature)
				StatStages.EnsureCreatureHasStages(battle.FoeCreature)
			end
			local foeName = battle.FoeCreature.Nickname or battle.FoeCreature.Name or "Foe"
			-- Deep clone creature data for SendOut step
			local creatureDataClone = table.clone(battle.FoeCreature)
			if creatureDataClone.Stats then
				creatureDataClone.Stats = table.clone(creatureDataClone.Stats)
			end
			if creatureDataClone.MaxStats then
				creatureDataClone.MaxStats = table.clone(creatureDataClone.MaxStats)
			end
			local friendlyActions = {}
			local enemyActions = {
				{ Type = "Switch", Action = "SendOut", Creature = foeName, CreatureData = creatureDataClone, IsPlayer = false }
			}
			
			-- Apply entry hazard damage to the trainer's incoming creature
			local EntryHazards = require(game:GetService("ReplicatedStorage").Shared.EntryHazards)
			if battle.FoeHazards then
				DBG:print("[HAZARD] Checking FoeHazards for deferred trainer switch-in:", battle.FoeHazards)
				local hazardSteps, updatedHazards = EntryHazards.ApplyOnSwitchIn(battle.FoeCreature, battle.FoeHazards, false)
				
				-- Update hazards state (Toxic Spikes may have been absorbed)
				if updatedHazards then
					battle.FoeHazards = updatedHazards
				end
				
				-- Add hazard damage steps to enemy actions
				for _, hazardStep in ipairs(hazardSteps) do
					table.insert(enemyActions, hazardStep)
					DBG:print("[HAZARD] Added hazard step for deferred trainer switch-in:", hazardStep.Type, hazardStep.HazardType)
				end
				
				-- Update the cloned creature data with post-hazard HP
				if #hazardSteps > 0 and battle.FoeCreature.Stats then
					creatureDataClone.Stats = creatureDataClone.Stats or {}
					creatureDataClone.Stats.HP = battle.FoeCreature.Stats.HP
					DBG:print("[HAZARD] Updated deferred trainer creature HP after hazard damage:", battle.FoeCreature.Stats.HP)
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
			if Events and Events.Communicate then
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
	
	-- Check if player creature is fainted
	local playerFainted = battle.PlayerFainted or (battle.PlayerCreature.Stats.HP <= 0)
	
	if playerFainted then
		DBG:print("=== PLAYER FAINT DETECTED ===")
		DBG:print("Player creature:", battle.PlayerCreature.Name, "HP:", battle.PlayerCreature.Stats.HP)
		
		local faintStep = {
			Type = "Faint",
			Creature = battle.PlayerCreature.Name or "Your creature",
			IsPlayer = true
		}
		
		local friendlyActions = {faintStep}
		local enemyActions = {}
		
		battle.PlayerFainted = false
		
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
		
		if Events and Events.Communicate then
			Events.Communicate:FireClient(Player, "TurnResult", turnResult)
		end
		
		return true
	end
	
	-- Generate enemy action
	local enemyAction = nil
	do
		local pa = battle.PlayerAction
		if battle.SkipEnemyActionOnce == true then
			DBG:print("Skipping enemy action due to SkipEnemyActionOnce flag (preview switch)")
			battle.SkipEnemyActionOnce = nil
		elseif not (pa and pa.Type == "Capture" and battle.CaptureSuccess == true) then
			enemyAction = BattleSystem.BuildEnemyAction(Player)
		else
			DBG:print("Skipping enemy action due to successful capture")
		end
	end
	
	-- Determine turn order based on speed and priority
	local turnOrder = BattleSystem.DetermineTurnOrder(battle, playerAction, enemyAction)
	
	-- Safe debug log for turn order
	local firstActor = turnOrder[1] and turnOrder[1].Actor or "?"
	local secondActor = turnOrder[2] and turnOrder[2].Actor or "None"
	DBG:print("Turn order determined:", firstActor, "goes first, then", secondActor)
	
	-- Execute actions in order
	local friendlyActions = {}
	local enemyActions = {}
	local playerFaintAdded = false
	local foeFaintAdded = false
	local faintAddedByCreature: {[string]: boolean} = {}
	local hpData = {
		Player = battle.PlayerCreature.Stats.HP,
		PlayerMax = battle.PlayerCreature.MaxStats.HP,
		Enemy = battle.FoeCreature.Stats.HP,
		EnemyMax = battle.FoeCreature.MaxStats.HP,
	}
	
	local playerFaintedThisTurn = false
	local foeFaintedThisTurn = false
	for i, action in ipairs(turnOrder) do
		-- Check if we should skip this action due to a KO in the previous action
		if playerFaintedThisTurn or foeFaintedThisTurn then
			DBG:print("[ProcessTurn] Skipping remaining action", i, "due to KO")
			break
		end
		
		local result = BattleSystem.ExecuteAction(Player, action, battle)
		
		-- Handle multiple results (e.g., move + faint)
		if type(result) == "table" and result[1] then
			-- Multiple results returned
			DBG:print("=== MULTIPLE RESULTS DETECTED ===")
			DBG:print("Number of results:", #result)
			for i, singleResult in ipairs(result) do
				DBG:print("Result", i, "Type:", singleResult.Type, "IsPlayer:", singleResult.IsPlayer, "Creature:", singleResult.Creature)
			end
			DBG:print("=== END MULTIPLE RESULTS ===")
			
			for _, singleResult in ipairs(result) do
				local stepIsPlayer
				
				-- Move, Damage, and Recoil steps should ALWAYS stay with the action that caused them
				-- This ensures the attack animation and its resulting effects are shown together
				-- For Damage steps, IsPlayer indicates who was damaged (the defender), not who attacked
				-- For Recoil steps, IsPlayer indicates who took recoil (the attacker), stays with their action
				-- We want these steps categorized by who attacked (action.IsPlayer)
				if singleResult.Type == "Move" or singleResult.Type == "Damage" or singleResult.Type == "Recoil" then
					stepIsPlayer = action.IsPlayer
				elseif singleResult.IsPlayer ~= nil then
					stepIsPlayer = singleResult.IsPlayer
				elseif singleResult.Type == "Faint" and singleResult.Creature then
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
					stepIsPlayer = action.IsPlayer
					if (singleResult.IsPlayer == true) then
						playerFaintedThisTurn = true
					else
						foeFaintedThisTurn = true
					end
					if stepIsPlayer then
						if not playerFaintAdded then
							table.insert(friendlyActions, singleResult)
							playerFaintAdded = true
							if faintKey ~= "" then faintAddedByCreature[faintKey] = true end
							DBG:print("Added PLAYER faint to friendlyActions")
						else
							DBG:print("Skipping duplicate PLAYER faint step")
						end
					else
						if not foeFaintAdded then
							table.insert(enemyActions, singleResult)
							foeFaintAdded = true
							if faintKey ~= "" then faintAddedByCreature[faintKey] = true end
							DBG:print("Added FOE faint to enemyActions")
						else
							DBG:print("Skipping duplicate FOE faint step")
						end
					end
				else
					if stepIsPlayer then
						table.insert(friendlyActions, singleResult)
						DBG:print("Added to friendlyActions")
					else
						table.insert(enemyActions, singleResult)
						DBG:print("Added to enemyActions")
					end
				end
			end
		else
			-- Single result
			local stepIsPlayer
			
			-- Move, Damage, and Recoil steps should ALWAYS stay with the action that caused them
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
					stepIsPlayer = action.IsPlayer
					if (result.IsPlayer == true) then
						playerFaintedThisTurn = true
					else
						foeFaintedThisTurn = true
					end
					if stepIsPlayer then
						if not playerFaintAdded then
							table.insert(friendlyActions, result)
							playerFaintAdded = true
							if faintKey ~= "" then faintAddedByCreature[faintKey] = true end
						else
							DBG:print("Skipping duplicate PLAYER faint step (single result)")
						end
					else
						if not foeFaintAdded then
							table.insert(enemyActions, result)
							foeFaintAdded = true
							if faintKey ~= "" then faintAddedByCreature[faintKey] = true end
						else
							DBG:print("Skipping duplicate FOE faint step (single result)")
						end
					end
				end
			else
				if stepIsPlayer then
					table.insert(friendlyActions, result)
				else
					table.insert(enemyActions, result)
				end
			end
		end
		
		-- Check if battle should end
		local endNow = false
		if battle.CaptureCompleted then
			endNow = true
		elseif battle.FoeCreature and battle.FoeCreature.Stats and battle.FoeCreature.Stats.HP <= 0 then
			if battle.Type == "Trainer" and type(battle.TrainerParty) == "table" and battle.FoeCreatureIndex then
				local currentFoe = battle.TrainerParty[battle.FoeCreatureIndex]
				if currentFoe then
					if currentFoe.Stats then
						currentFoe.Stats.HP = 0
					end
					if currentFoe.CurrentHP ~= nil then
						currentFoe.CurrentHP = 0
					end
					DBG:print("[KO/Switch] Marked party slot", battle.FoeCreatureIndex, "as defeated:", (currentFoe.Nickname or currentFoe.Name))
				end
			end
			
			-- If trainer has more usable creatures, send out the next one instead of ending
			if battle.Type == "Trainer" and type(battle.TrainerParty) == "table" then
				local nextIndex, nextCreature
				for i, c in ipairs(battle.TrainerParty) do
					local hp = (c and ((c.Stats and c.Stats.HP) or c.CurrentHP)) or 0
					DBG:print("[KO/Switch] Checking party slot", i, ":", (c and (c.Nickname or c.Name) or "nil"), "HP:", hp)
					if c and hp > 0 then
						nextIndex = i
						nextCreature = c
						DBG:print("[KO/Switch] Found usable creature at slot", i)
						break
					end
				end
				if nextCreature then
					DBG:print("[KO/Switch] Trainer creature KO detected - sending out next creature")
					DBG:print("[KO/Switch] Current foe:", (battle.FoeCreature.Nickname or battle.FoeCreature.Name), "HP:", battle.FoeCreature.Stats.HP)
					DBG:print("[KO/Switch] Next creature:", (nextCreature.Nickname or nextCreature.Name), "HP:", (nextCreature.Stats and nextCreature.Stats.HP or nextCreature.CurrentHP or "?"))
					DBG:print("[KO/Switch] Next creature index:", nextIndex)
					
					table.insert(enemyActions, {
						Type = "SwitchPreview",
						TrainerName = battle.TrainerName,
						NextCreature = (nextCreature.Nickname or nextCreature.Name),
						IsPlayer = false,
					})
					battle.AllowPreviewSwitch = true
					DBG:print("[KO/Switch] Added SwitchPreview step for", (nextCreature.Nickname or nextCreature.Name))
					DBG:print("[KO/Switch] Enabled AllowPreviewSwitch flag")
					
					-- Deep clone creature data to ensure Stats are captured before any modifications
					local creatureDataClone = table.clone(nextCreature)
					if creatureDataClone.Stats then
						creatureDataClone.Stats = table.clone(creatureDataClone.Stats)
					end
					if creatureDataClone.MaxStats then
						creatureDataClone.MaxStats = table.clone(creatureDataClone.MaxStats)
					end
					DBG:print("[KO/Switch] SendOut CreatureData HP:", creatureDataClone.Stats and creatureDataClone.Stats.HP or "nil", "/", creatureDataClone.MaxStats and creatureDataClone.MaxStats.HP or "nil")
					
					table.insert(enemyActions, {
						Type = "Switch",
						Action = "SendOut",
						Creature = (nextCreature.Nickname or nextCreature.Name),
						CreatureData = creatureDataClone,
						IsPlayer = false,
						TrainerName = battle.TrainerName,
					})
					
					-- Apply entry hazard damage to the trainer's incoming creature
					local EntryHazards = require(game:GetService("ReplicatedStorage").Shared.EntryHazards)
					if battle.FoeHazards then
						DBG:print("[HAZARD] Checking FoeHazards for trainer switch-in:", battle.FoeHazards)
						local hazardSteps, updatedHazards = EntryHazards.ApplyOnSwitchIn(nextCreature, battle.FoeHazards, false)
						
						-- Update hazards state (Toxic Spikes may have been absorbed)
						if updatedHazards then
							battle.FoeHazards = updatedHazards
						end
						
						-- Add hazard damage steps to enemy actions
						for _, hazardStep in ipairs(hazardSteps) do
							table.insert(enemyActions, hazardStep)
							DBG:print("[HAZARD] Added hazard step for trainer switch-in:", hazardStep.Type, hazardStep.HazardType)
						end
						
						-- Update the cloned creature data with post-hazard HP
						if #hazardSteps > 0 and nextCreature.Stats then
							creatureDataClone.Stats = creatureDataClone.Stats or {}
							creatureDataClone.Stats.HP = nextCreature.Stats.HP
							DBG:print("[HAZARD] Updated trainer creature HP after hazard damage:", nextCreature.Stats.HP)
						end
					end
					
					battle.NextFoeCreature = nextCreature
					battle.NextFoeCreatureIndex = nextIndex
					battle.PendingTrainerSendOut = true
					DBG:print("[KO/Switch] Stored next creature for post-turn promotion")
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
			-- FindFirstAliveCreature will be moved to CreatureSystem
			local alive = nil
			if pd and pd.Party then
				for i = 1, #pd.Party do
					local creature = pd.Party[i]
					local hp = (creature.CurrentHP ~= nil) and creature.CurrentHP or (creature.Stats and creature.Stats.HP)
					if creature and hp and hp > 0 then
						alive = creature
						break
					end
				end
			end
			if not alive then
				endNow = true
			else
				battle.SwitchMode = "Forced"
			end
		end
		if endNow then
			break
		end
	end
	
	-- Update HP data with values AFTER moves but BEFORE end-of-turn effects
	DBG:print("[BattleSystem] Turn execution loop completed - updating HP data")
	hpData.Player = battle.PlayerCreature.Stats.HP
	hpData.PlayerMax = battle.PlayerCreature.MaxStats.HP
	hpData.Enemy = battle.FoeCreature.Stats.HP
	hpData.EnemyMax = battle.FoeCreature.MaxStats.HP

	-- Determine if foe fainted and whether the battle will end immediately
	local isFinalFoeFaint = false
	if foeFaintedThisTurn then
		if battle.Type == "Trainer" then
			isFinalFoeFaint = (battle.PendingTrainerSendOut ~= true)
		else
			isFinalFoeFaint = true
		end
	end
	DBG:print("[BattleSystem] Foe fainted check - foeFaintedThisTurn:", foeFaintedThisTurn, "isFinalFoeFaint:", isFinalFoeFaint)

	-- If foe fainted and battle continues (trainer has more), award XP now
	if foeFaintedThisTurn and not isFinalFoeFaint then
		local defeated = battle.FoeCreature
		if defeated then
			-- AwardBattleXP will be handled by ServerFunctions (needs access to full context)
			-- For now, we'll return a flag indicating XP should be awarded
		end
	end

	-- Held item end-of-turn effects
	DBG:print("[BattleSystem] Checking end-of-turn conditions - isFinalFoeFaint:", isFinalFoeFaint, "CaptureCompleted:", battle and battle.CaptureCompleted or false)
	if not isFinalFoeFaint and not (battle and battle.CaptureCompleted == true) then
		DBG:print("[BattleSystem] Processing end-of-turn effects")
		local endTurnSteps = {}
		HeldItemEffects.ProcessEndOfTurn(battle, Player, friendlyActions, enemyActions)
		
		-- Process Status end-of-turn effects (following Crumbs pattern exactly)
		local StatusModule = require(game:GetService("ReplicatedStorage").Shared.Status)
		
		-- Process player creature status (burn/poison damage at end of turn)
		local function applyStatusDamage(creature, isPlayerSide)
			DBG:print("[BattleSystem][Status] applyStatusDamage called - isPlayerSide:", isPlayerSide, "creature exists:", creature ~= nil)
			if not creature then
				DBG:print("[BattleSystem][Status] No creature - returning")
				return
			end
			if not creature.Stats then
				DBG:print("[BattleSystem][Status] No creature.Stats - returning")
				return
			end
			if creature.Stats.HP <= 0 then
				DBG:print("[BattleSystem][Status] Creature HP <= 0:", creature.Stats.HP, "- returning")
				return
			end
			if not creature.Status then
				DBG:print("[BattleSystem][Status] No creature.Status - returning")
				return
			end
			
			DBG:print("[BattleSystem][Status] Creature has status:", creature.Status.Type, "Full status:", creature.Status)
			
			local statusDamage = StatusModule.ProcessEndOfTurn(creature)
			DBG:print("[BattleSystem][Status] ProcessEndOfTurn returned:", statusDamage, "type:", type(statusDamage))
			
			if not statusDamage then
				DBG:print("[BattleSystem][Status] No statusDamage returned - returning")
				return
			end
			if statusDamage <= 0 then
				DBG:print("[BattleSystem][Status] statusDamage <= 0:", statusDamage, "- returning")
				return
			end
			
			local maxHP = creature.MaxStats and creature.MaxStats.HP or 1
			local beforeHP = creature.Stats.HP or 0
			creature.Stats.HP = math.max(0, beforeHP - statusDamage)
			
			local statusType = creature.Status and creature.Status.Type
			local creatureName = creature.Nickname or creature.Name or (isPlayerSide and "Your creature" or "Foe")
			local statusMessage = statusType == "BRN" and (creatureName .. " is hurt by its burn!") or
				statusType == "PSN" and (creatureName .. " is hurt by poison!") or
				statusType == "TOX" and (creatureName .. " is hurt by toxic poison!") or 
				(creatureName .. " is hurt by its status!")
			
			local step = {
				Type = "Damage",
				Effectiveness = "Normal",
				IsPlayer = isPlayerSide,
				Message = statusMessage,
				DelaySeconds = 0, -- No delay - HP should update immediately when message appears (Pokemon-style)
				EndOfTurn = true, -- signal client to avoid pre-damage visual adjustments
				NewHP = creature.Stats.HP, -- explicit target HP after the damage
				MaxHP = maxHP,
			}
			
			DBG:print("[BattleSystem][Status] Creating damage step - creatureName:", creatureName, "beforeHP:", beforeHP, "damage:", statusDamage, "newHP:", creature.Stats.HP, "statusType:", statusType)
			DBG:print("[BattleSystem][Status] Step details - Type:", step.Type, "IsPlayer:", step.IsPlayer, "Message:", step.Message, "NewHP:", step.NewHP, "MaxHP:", step.MaxHP)
			
			if isPlayerSide then
				DBG:print("[BattleSystem][Status] Adding to friendlyActions - current count:", #friendlyActions)
				table.insert(friendlyActions, step)
				DBG:print("[BattleSystem][Status] Added to friendlyActions - new count:", #friendlyActions)
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
						if ClientData.UpdateClientData then ClientData:UpdateClientData(Player, pd) end
					end
				end
			else
				DBG:print("[BattleSystem][Status] Adding to enemyActions - current count:", #enemyActions)
				table.insert(enemyActions, step)
				DBG:print("[BattleSystem][Status] Added to enemyActions - new count:", #enemyActions)
			end
		end
		
		DBG:print("[BattleSystem][Status] Processing player creature status damage")
		applyStatusDamage(battle.PlayerCreature, true)
		DBG:print("[BattleSystem][Status] Processing foe creature status damage")
		applyStatusDamage(battle.FoeCreature, false)
		DBG:print("[BattleSystem][Status] End-of-turn status processing complete - friendlyActions:", #friendlyActions, "enemyActions:", #enemyActions)
		
		-- Process Ability end-of-turn effects
		local function processAbilityEndTurn(creature, isPlayerCreature)
			local Abilities = require(game:GetService("ReplicatedStorage").Shared.Abilities)
			local ability = Abilities.GetName(creature)
			if not ability then return end
			-- Placeholder for ability end-turn effects
		end
		processAbilityEndTurn(battle.PlayerCreature, true)
		processAbilityEndTurn(battle.FoeCreature, false)
	end

	-- Ensure every Damage step carries NewHP
	local function backfillDamageNewHP(stepList)
		if type(stepList) ~= "table" then return end
		for _, s in ipairs(stepList) do
			if type(s) == "table" and s.Type == "Damage" and type(s.NewHP) ~= "number" then
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
	
	-- Clear stale switch mode if player is alive at end of turn
	if not playerFaintedThisTurn then
		local playerAlive = battle.PlayerCreature and battle.PlayerCreature.Stats and (battle.PlayerCreature.Stats.HP > 0)
		if playerAlive then
			battle.SwitchMode = nil
		end
	end

	-- Advance TurnId and send turn result to client
	battle.TurnId = (battle.TurnId or 0) + 1
	DBG:print("=== SENDING TURN RESULT TO CLIENT ===")
	DBG:print("Friendly actions count:", #friendlyActions)
	for i, action in ipairs(friendlyActions) do
		DBG:print("Friendly", i, "Type:", action.Type, "IsPlayer:", action.IsPlayer, "Creature:", action.Creature)
	end
	DBG:print("Enemy actions count:", #enemyActions)
	for i, action in ipairs(enemyActions) do
		DBG:print("Enemy", i, "Type:", action.Type, "IsPlayer:", action.IsPlayer, "Creature:", action.Creature)
	end
	DBG:print("=== END TURN RESULT ===")
	
	-- CRITICAL: Update hpData to reflect new creature if trainer switched out
	-- This prevents the client from "syncing" to the old fainted creature's HP (0)
	if battle.PendingTrainerSendOut and battle.NextFoeCreature then
		hpData = {
			Player = battle.PlayerCreature.Stats.HP,
			PlayerMax = battle.PlayerCreature.MaxStats.HP,
			Enemy = battle.NextFoeCreature.Stats.HP,
			EnemyMax = battle.NextFoeCreature.MaxStats.HP,
		}
		DBG:print("[ProcessTurn] Updated hpData for new trainer creature - Enemy HP:", hpData.Enemy, "/", hpData.EnemyMax)
	end
	
	if Events and Events.Communicate then
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
				willEnd = true
			end
		end
		Events.Communicate:FireClient(Player, "TurnResult", {
			Friendly = friendlyActions,
			Enemy = enemyActions,
			HP = hpData,
			PlayerCreatureIndex = battle.PlayerCreatureIndex or 1,
			PlayerCreature = battle.PlayerCreature,
			FoeCreatureIndex = battle.FoeCreatureIndex or 1,
			FoeCreature = battle.FoeCreature,
			TurnId = battle.TurnId,
			SwitchMode = (playerFaintedThisTurn and "Forced") or nil,
			BattleEnd = willEnd,
		})
	end
	
	-- Clear player action for next turn
	battle.PlayerAction = nil
	
	-- Check if battle should end BEFORE promoting next creature
	local shouldEndAfterPromotion = false
	if battle.PendingTrainerSendOut and not battle.NextFoeCreature then
		shouldEndAfterPromotion = true
		DBG:print("[PostTurn] No next creature available - battle will end after current turn")
	end
	
	-- Promote next creature AFTER TurnResult is sent
	if battle.PendingTrainerSendOut and battle.NextFoeCreature then
		DBG:print("[PostTurn] Promoting next creature to battle.FoeCreature")
		DBG:print("[PostTurn] Old foe:", (battle.FoeCreature.Nickname or battle.FoeCreature.Name), "HP:", battle.FoeCreature.Stats.HP)
		battle.FoeCreature = battle.NextFoeCreature
		battle.FoeCreatureIndex = battle.NextFoeCreatureIndex
		DBG:print("[PostTurn] New foe:", (battle.FoeCreature.Nickname or battle.FoeCreature.Name), "HP:", battle.FoeCreature.Stats.HP)
		-- Reset stat stages for the newly promoted creature
		if StatStages then
			StatStages.ResetAll(battle.FoeCreature)
			StatStages.EnsureCreatureHasStages(battle.FoeCreature)
		end
		battle.NextFoeCreature = nil
		battle.NextFoeCreatureIndex = nil
		battle.PendingTrainerSendOut = false
	end

	-- Return flag indicating if battle should end (handled by ServerFunctions)
	return true, {
		shouldEnd = shouldEndAfterPromotion or (battle.FoeCreature and battle.FoeCreature.Stats and battle.FoeCreature.Stats.HP <= 0) or (battle.PlayerCreature.Stats.HP <= 0),
		foeFainted = foeFaintedThisTurn,
		playerFainted = playerFaintedThisTurn,
		captureCompleted = battle.CaptureCompleted,
	}
end

--[[
	Determine turn order based on speed and priority (Pokemon-style)
	@param battle The battle state
	@param playerAction The player's action
	@param enemyAction The enemy's action
	@return table Array of actions in order
]]
function BattleSystem.DetermineTurnOrder(battle: any, playerAction: any, enemyAction: any?): {any}
	local playerCreature = battle.PlayerCreature
	local foeCreature = battle.FoeCreature
	
	-- PvP: If one player switches and the other doesn't, switch has absolute priority
	if battle.Type == "PvP" then
		local playerSwitching = playerAction and playerAction.Type == "Switch"
		local enemySwitching = enemyAction and enemyAction.Type == "Switch"
		
		if playerSwitching and not enemySwitching then
			-- Player switches, enemy doesn't - player goes first
			DBG:print("[PvP] Player switches, enemy doesn't - switch has priority")
			local turnOrder = {}
			table.insert(turnOrder, {Action = playerAction, IsPlayer = true, Actor = "Player"})
			if enemyAction then
				table.insert(turnOrder, {Action = enemyAction, IsPlayer = false, Actor = "Enemy"})
			end
			return turnOrder
		elseif enemySwitching and not playerSwitching then
			-- Enemy switches, player doesn't - enemy goes first
			DBG:print("[PvP] Enemy switches, player doesn't - switch has priority")
			local turnOrder = {}
			table.insert(turnOrder, {Action = enemyAction, IsPlayer = false, Actor = "Enemy"})
			table.insert(turnOrder, {Action = playerAction, IsPlayer = true, Actor = "Player"})
			return turnOrder
		end
		-- If both switch or neither switches, fall through to normal priority logic
	end
	
	-- Get move priorities
	local playerPriority = 0
	local enemyPriority = 0
	
	-- Item usage should act with high priority
	if playerAction.Type == "Item" then
		playerPriority = 99
	elseif playerAction.Type == "Switch" then
		-- Switching should occur before standard moves so replacement is on field
		playerPriority = 99
	elseif playerAction.Move then
		local Moves = require(game.ReplicatedStorage.Shared.Moves)
		local moveData = Moves[playerAction.Move]
		if moveData then
			playerPriority = (moveData.Priority or 0) + (AbilitiesModule.PriorityBonus(playerCreature, playerAction.Move) or 0)
		end
	end
	
	if enemyAction and enemyAction.Type == "Item" then
		enemyPriority = 99
	elseif enemyAction and enemyAction.Type == "Switch" then
		enemyPriority = 99
	elseif enemyAction and enemyAction.Move then
		local Moves = require(game.ReplicatedStorage.Shared.Moves)
		local moveData = Moves[enemyAction.Move]
		if moveData then
			enemyPriority = (moveData.Priority or 0) + (AbilitiesModule.PriorityBonus(foeCreature, enemyAction.Move) or 0)
		end
	end
	
	-- Get speeds (apply stat stage modifiers first)
	local playerSpeed = playerCreature.Stats.Speed or 0
	local enemySpeed = foeCreature.Stats.Speed or 0
	
	-- Apply stat stage modifiers to speed
	if StatStages then
		playerSpeed = StatStages.ApplyStage(playerSpeed, StatStages.GetStage(playerCreature, "Speed"), false)
		enemySpeed = StatStages.ApplyStage(enemySpeed, StatStages.GetStage(foeCreature, "Speed"), false)
	end
	
	-- Apply Status Speed Modifiers (Paralysis reduces speed)
	local StatusModule = require(game:GetService("ReplicatedStorage").Shared.Status)
	local playerStatusMult = StatusModule.GetSpeedMultiplier(playerCreature)
	local enemyStatusMult = StatusModule.GetSpeedMultiplier(foeCreature)
	playerSpeed = math.floor(playerSpeed * playerStatusMult)
	enemySpeed = math.floor(enemySpeed * enemyStatusMult)
	
	-- Apply Ability Speed Modifiers (Sand Speed, Swift Current)
	local Abilities = require(game:GetService("ReplicatedStorage").Shared.Abilities)
	local pAbil = Abilities.GetName(playerCreature)
	local fAbil = Abilities.GetName(foeCreature)
	
	if pAbil then
		local a = string.lower(pAbil)
		if a == "sand speed" and battle.Weather == "Sandstorm" then playerSpeed *= 2 end
		if a == "swift current" and battle.Weather == "Rain" then playerSpeed *= 2 end
	end
	if fAbil then
		local a = string.lower(fAbil)
		if a == "sand speed" and battle.Weather == "Sandstorm" then enemySpeed *= 2 end
		if a == "swift current" and battle.Weather == "Rain" then enemySpeed *= 2 end
	end
	
	-- Determine order based on priority first, then speed
	local playerFirst = false
	
	if playerPriority > enemyPriority then
		playerFirst = true
		DBG:print("Player goes first due to higher priority:", playerPriority, "vs", enemyPriority)
	elseif enemyPriority > playerPriority then
		playerFirst = false
		DBG:print("Enemy goes first due to higher priority:", enemyPriority, "vs", playerPriority)
	else
		-- Same priority, use speed
		if playerSpeed > enemySpeed then
			playerFirst = true
			DBG:print("Player goes first due to higher speed:", playerSpeed, "vs", enemySpeed)
		elseif enemySpeed > playerSpeed then
			playerFirst = false
			DBG:print("Enemy goes first due to higher speed:", enemySpeed, "vs", playerSpeed)
		else
			-- Same speed: server-roll coin flip to keep it fair and authoritative
			playerFirst = math.random(1, 2) == 1
			DBG:print("Same speed tie - random coin flip. Player first:", playerFirst)
		end
	end
	
	-- Build turn order array
	local turnOrder = {}
	if playerFirst then
		table.insert(turnOrder, {Action = playerAction, IsPlayer = true, Actor = "Player"})
		if enemyAction then
			table.insert(turnOrder, {Action = enemyAction, IsPlayer = false, Actor = "Enemy"})
		end
	else
		if enemyAction then
			table.insert(turnOrder, {Action = enemyAction, IsPlayer = false, Actor = "Enemy"})
		end
		table.insert(turnOrder, {Action = playerAction, IsPlayer = true, Actor = "Player"})
	end
	
	return turnOrder
end

-- Mirror the live battle creature HP back into the owner's party data
-- This keeps PvP defeat detection in sync with the actual battle state
local function syncPartyHpFromBattle(targetPlayer: Player?, creature: any?, slotIndex: number?)
	if not targetPlayer or not targetPlayer.Parent then
		return
	end
	if type(slotIndex) ~= "number" then
		return
	end
	if not creature or not creature.Stats then
		return
	end

	local pd = ClientData:Get(targetPlayer)
	if not pd or not pd.Party or not pd.Party[slotIndex] then
		return
	end

	local partySlot = pd.Party[slotIndex]
	partySlot.Stats = partySlot.Stats or {}
	partySlot.Stats.HP = creature.Stats.HP
	partySlot.MaxStats = partySlot.MaxStats or creature.MaxStats

	local maxHP = (partySlot.MaxStats and partySlot.MaxStats.HP) or (creature.MaxStats and creature.MaxStats.HP)
	if maxHP then
		partySlot.CurrentHP = math.clamp(math.floor((partySlot.Stats.HP / math.max(1, maxHP)) * 100 + 0.5), 0, 100)
	end

	if ClientData.UpdateClientData then
		ClientData:UpdateClientData(targetPlayer, pd)
	end
end

-- Gen 8–9: Toxic counter (bad poison) resets when the creature switches out.
local function resetToxicCounterOnSwitchOut(creature: any?)
	if creature and creature.Status and creature.Status.Type == "TOX" then
		creature.Status.ToxicCounter = 1
	end
end

--[[
	Execute a single action and return the result
	@param Player The player
	@param actionData The action data
	@param battle The battle state
	@return table|{table} Action result(s)
]]
function BattleSystem.ExecuteAction(Player: Player, actionData: any, battle: any): any
	DBG:print("[BattleSystem.ExecuteAction] Called for player:", Player.Name)
	DBG:print("[BattleSystem.ExecuteAction] actionData:", actionData)
	local action = actionData.Action
	local isPlayer = actionData.IsPlayer
	DBG:print("[BattleSystem.ExecuteAction] action:", action, "isPlayer:", isPlayer)
	
	if not action then
		DBG:warn("[BattleSystem.ExecuteAction] action is nil!")
		return {Type = "Message", Message = "Invalid action data"}
	end
	
	DBG:print("[BattleSystem.ExecuteAction] action.Type:", action.Type, "action.Move:", action.Move)
	
	if action.Type == "Move" then
		DBG:print("[BattleSystem.ExecuteAction] Calling ExecuteMoveAction")
		return BattleSystem.ExecuteMoveAction(Player, action, battle, isPlayer)
	elseif action.Type == "Switch" then
		return BattleSystem.ExecuteSwitchAction(Player, action, battle, isPlayer)
	elseif action.Type == "Capture" then
		local foe = battle.FoeCreature
		local foeName = foe and (foe.Nickname or foe.Name) or "Wild"
		local steps = {}
		table.insert(steps, {Type = "Message", Message = "You used a capture cube." , IsPlayer = true})
		table.insert(steps, {Type = "Message", Message = string.format("It's attempting to scan the wild %s!", foeName), IsPlayer = true})
		local scans = action.Scans or {false,false,false}
		for i = 1, 3 do
			local okScan = scans[i] == true
			table.insert(steps, {Type = "CaptureScan", Success = okScan, IsPlayer = true})
			if not okScan then
				break
			end
		end
		if battle.CaptureSuccess then
			table.insert(steps, {Type = "CaptureSuccess", Creature = foeName, IsPlayer = true})
			battle.CaptureCompleted = true
		else
			local failVariants = {"Agh! Almost had it!", "Ah! It was so close!"}
			table.insert(steps, {Type = "Message", Message = failVariants[math.random(1, #failVariants)], IsPlayer = true})
		end
		table.insert(steps, {Type = "WaitDrain"})
		return steps
	elseif action.Type == "Item" then
		local amount = tonumber(action.Healed) or 0
		return {Type = "Heal", Amount = amount, IsPlayer = isPlayer}
	end
	
	return {Type = "Message", Message = "Unknown action type"}
end

--[[
	Execute a move action
	@param Player The player
	@param action The move action
	@param battle The battle state
	@param isPlayer Whether this is the player's move
	@return table|{table} Action result(s)
]]
function BattleSystem.ExecuteMoveAction(Player: Player, action: any, battle: any, isPlayer: boolean): any
	DBG:print("[ExecuteMoveAction] Called - isPlayer:", isPlayer, "Move:", action and action.Move or "nil")
	local attacker = isPlayer and battle.PlayerCreature or battle.FoeCreature
	local defender = isPlayer and battle.FoeCreature or battle.PlayerCreature
	local moveName = action.Move
	DBG:print("[ExecuteMoveAction] attacker:", attacker and attacker.Name or "nil", "HP:", attacker and attacker.Stats and attacker.Stats.HP or "nil")
	DBG:print("[ExecuteMoveAction] defender:", defender and defender.Name or "nil", "HP:", defender and defender.Stats and defender.Stats.HP or "nil")
	local Abilities = require(game:GetService("ReplicatedStorage").Shared.Abilities)
	local StatusModule = require(game:GetService("ReplicatedStorage").Shared.Status)
	
	-- Defensive: capture attacker HP and detach shared stat tables so damage to the defender
	-- cannot bleed into the attacker (can happen if tables alias in PvP payloads).
	local attackerHPBefore = attacker and attacker.Stats and attacker.Stats.HP
	if attacker and defender and attacker.Stats and defender.Stats and attacker.Stats == defender.Stats then
		defender.Stats = table.clone(defender.Stats)
		if defender.MaxStats and attacker.MaxStats == defender.MaxStats then
			defender.MaxStats = table.clone(defender.MaxStats)
		end
	end

	-- Check if attacker can act (status conditions)
	local canAct, statusMessage = StatusModule.CanAct(attacker)
	local wakeUpMessage = nil
	
	-- Check if creature woke up this turn
	if canAct and statusMessage and string.find(string.lower(statusMessage or ""), "woke up", 1, true) then
		wakeUpMessage = statusMessage
	end
	
	-- Helper function to prepend wake-up message to steps if needed
	local function prependWakeUpMessage(steps)
		if wakeUpMessage then
			local result = {
				{ Type = "Message", Message = wakeUpMessage, IsPlayer = isPlayer }
			}
			for _, step in ipairs(steps) do
				table.insert(result, step)
			end
			return result
		end
		return steps
	end
	
	if not canAct then
		-- Check if this is sleep status - if so, don't show move attempt
		if statusMessage and string.find(string.lower(statusMessage or ""), "fast asleep", 1, true) then
			-- Sleep: only show the message, no move attempt
			local steps = {
				{ Type = "Message", Message = statusMessage or "The creature can't move!", IsPlayer = isPlayer }
			}
			return steps
		else
			-- Other status conditions: show move attempt then message
			local steps = {
				{ Type = "Move", Move = moveName, Actor = attacker.Name or (isPlayer and "Your creature" or "Foe"), IsPlayer = isPlayer },
				{ Type = "Message", Message = statusMessage or "The creature can't move!", IsPlayer = isPlayer }
			}
			return steps
		end
	end
	
	-- Check volatile status conditions (Flinch, Confusion, Infatuation)
	local canActVolatile, volatileMessage, selfDamage = StatusModule.CanActVolatile(attacker)
	if not canActVolatile then
		local steps = {}
		-- For Flinch, don't show any message - the flinch message was already added
		-- when flinch was applied by the opponent's move
		if volatileMessage and string.find(volatileMessage, "flinched", 1, true) then
			-- Flinch: remove flinch silently, don't add message (already added when applied)
			-- Just return empty steps to prevent the creature from acting
			return steps
		else
			-- Other volatile statuses: show move attempt then message
			table.insert(steps, { Type = "Move", Move = moveName, Actor = attacker.Name or (isPlayer and "Your creature" or "Foe"), IsPlayer = isPlayer })
			table.insert(steps, { Type = "Message", Message = volatileMessage or "The creature can't move!", IsPlayer = isPlayer })
		end
		-- If confusion self-hit, apply damage
		if selfDamage and selfDamage > 0 then
			local beforeHP = attacker.Stats.HP or 0
			attacker.Stats.HP = math.max(0, beforeHP - selfDamage)
			table.insert(steps, { Type = "Damage", Effectiveness = "Normal", IsPlayer = isPlayer, NewHP = attacker.Stats.HP })
		end
		return steps
	end
	
	-- Check obedience for player's traded creatures
	if isPlayer and ObedienceModule then
		-- Get player's badge count
		local playerData = ClientData:Get(Player)
		local badges = tonumber(playerData and playerData.Badges) or 0
		
		local obeys, disobedienceMessage, disobedienceBehavior = ObedienceModule.CheckObedience(Player, attacker, badges)
		if not obeys then
			-- Creature disobeys - determine behavior
			local behavior = disobedienceBehavior or ObedienceModule.GetDisobedienceBehavior(attacker)
			local steps = {}
			-- local creatureName = attacker.Nickname or attacker.Name or "Creature"
			
			if behavior == "ignore" then
				-- Most common: just ignore orders
				table.insert(steps, { Type = "Message", Message = disobedienceMessage, IsPlayer = isPlayer })
				return steps
			elseif behavior == "randomMove" then
				-- Use a random move instead
				local currentMoves = attacker.CurrentMoves or {}
				local validMoves = {}
				for _, move in ipairs(currentMoves) do
					if move and type(move) == "string" and MovesModule[move] then
						table.insert(validMoves, move)
					end
				end
				
				if #validMoves > 0 then
					local randomMove = validMoves[math.random(1, #validMoves)]
					local randomMoveMessage = ObedienceModule.GetDisobedienceMessage(attacker, behavior, randomMove)
					table.insert(steps, { Type = "Message", Message = randomMoveMessage, IsPlayer = isPlayer })
					-- Recursively execute the random move
					local randomMoveAction = { Type = "Move", Move = randomMove }
					local randomMoveResult = BattleSystem.ExecuteMoveAction(Player, randomMoveAction, battle, isPlayer)
					if type(randomMoveResult) == "table" then
						for _, step in ipairs(randomMoveResult) do
							table.insert(steps, step)
						end
					end
					return steps
				else
					-- No valid moves, just ignore
					table.insert(steps, { Type = "Message", Message = disobedienceMessage, IsPlayer = isPlayer })
					return steps
				end
			elseif behavior == "sleep" then
				-- Check if creature can actually fall asleep (not already status'd)
				if StatusModule.CanBeInflicted(attacker, "SLP") then
					-- Fall asleep
					table.insert(steps, { Type = "Message", Message = disobedienceMessage, IsPlayer = isPlayer })
					-- Apply sleep status
					local statusApplied = StatusModule.Apply(attacker, "SLP", math.random(1, 3))
					if statusApplied then
						table.insert(steps, { Type = "Status", Status = "SLP", IsPlayer = isPlayer })
					end
				else
					-- Can't fall asleep (already has status), so just ignore orders instead
					local ignoreMessage = ObedienceModule.GetDisobedienceMessage(attacker, "ignore")
					table.insert(steps, { Type = "Message", Message = ignoreMessage, IsPlayer = isPlayer })
				end
				return steps
			elseif behavior == "hurtSelf" then
				-- Hurt itself
				table.insert(steps, { Type = "Message", Message = disobedienceMessage, IsPlayer = isPlayer })
				-- Deal damage to self (~1/8 max HP)
				if attacker.MaxStats and attacker.MaxStats.HP then
					local maxHP = attacker.MaxStats.HP
					local selfDamage = math.max(1, math.floor(maxHP / 8))
					local beforeHP = attacker.Stats.HP or maxHP
					attacker.Stats.HP = math.max(0, beforeHP - selfDamage)
					table.insert(steps, { Type = "Damage", Effectiveness = "Normal", IsPlayer = isPlayer, NewHP = attacker.Stats.HP })
				end
				return steps
			else
				-- Fallback: just ignore
				table.insert(steps, { Type = "Message", Message = disobedienceMessage, IsPlayer = isPlayer })
				return steps
			end
		end
	end
	
	local moveDef = MovesModule[moveName]
	
	-- Apply ability move type modification
	local modifiedType = moveDef and Abilities.ModifyMoveType(attacker, moveDef.Type) or (moveDef and moveDef.Type)
	
	-- Check if Fire-type move thaws frozen defender
	if defender.Status and defender.Status.Type == "FRZ" and modifiedType == "Fire" then
		StatusModule.Thaw(defender)
	end
	
	if moveDef and type(moveDef.HealsPercent) == "number" and moveDef.HealsPercent > 0 then
		local function getCurrentHP(creature)
			if not creature or not creature.MaxStats then return 0, 1 end
			local maxHP = creature.MaxStats.HP or 1
			local currentHP = creature.Stats and creature.Stats.HP or maxHP
			return currentHP, maxHP
		end
		local function applyHealPercent(creature, percent)
			if not creature or not creature.MaxStats then return 0 end
			local currentHP, maxHP = getCurrentHP(creature)
			local add = math.floor(maxHP * (math.max(0, percent) / 100) + 0.5)
			local newHP = math.min(maxHP, currentHP + add)
			creature.Stats = creature.Stats or {}
			creature.Stats.HP = newHP
			creature.CurrentHP = math.clamp(math.floor((newHP / maxHP) * 100 + 0.5), 0, 100)
			return math.max(0, newHP - currentHP)
		end
		local beforeHP = attacker and attacker.Stats and attacker.Stats.HP or -1
		local healed = applyHealPercent(attacker, moveDef.HealsPercent)
		local afterHP = attacker and attacker.Stats and attacker.Stats.HP or -1
		DBG:print("[HEAL]", attacker and (attacker.Nickname or attacker.Name) or "?", "used", moveName, "healed:", healed, "HP:", beforeHP, "->", afterHP)
		return prependWakeUpMessage({
			{ Type = "Move", Move = moveName, Actor = attacker.Name or "You", IsPlayer = isPlayer },
			{ Type = "Heal", Amount = healed, IsPlayer = isPlayer, Message = string.format("%s perched and recovered HP!", attacker.Nickname or attacker.Name) }
		})
	end
	
	-- Handle pure stat-changing moves (status moves with 0 base power)
	-- These moves only apply stat changes, no damage calculation needed
	if moveDef and moveDef.BasePower == 0 and moveDef.StatChanges and #moveDef.StatChanges > 0 then
		local steps = {}
		local actorName = attacker.Nickname or attacker.Name or (isPlayer and "Your creature" or "Foe")
		
		-- First show the move was used
		table.insert(steps, {
			Type = "Move",
			Move = moveName,
			Actor = actorName,
			IsPlayer = isPlayer,
		})
		
		-- Check accuracy for moves that target the opponent (like Growl, Leer)
		local hasOpponentTarget = false
		for _, statChange in ipairs(moveDef.StatChanges) do
			local target = statChange.Target or (statChange.Stages > 0 and "Self" or "Opponent")
			if target == "Opponent" then
				hasOpponentTarget = true
				break
			end
		end
		
		-- If move targets opponent, check accuracy
		if hasOpponentTarget and moveDef.Accuracy and moveDef.Accuracy > 0 then
			local accuracyStage = StatStages and StatStages.GetStage(attacker, "Accuracy") or 0
			local evasionStage = StatStages and StatStages.GetStage(defender, "Evasion") or 0
			local hit = DamageCalculator.CheckAccuracy(moveName, accuracyStage, evasionStage, attacker)
			
			if not hit then
				local missMessage = isPlayer and "But it missed!" or "Your creature avoided the attack!"
				table.insert(steps, { Type = "Miss", Message = missMessage, Move = moveName, Actor = actorName, IsPlayer = isPlayer })
				return prependWakeUpMessage(steps)
			end
		end
		
		-- Apply all stat changes
		for _, statChange in ipairs(moveDef.StatChanges) do
			local stat = statChange.Stat
			local stages = statChange.Stages
			local target = statChange.Target or (stages > 0 and "Self" or "Opponent")
			local chance = statChange.Chance or 100
			
			-- Roll for stat change chance
			if math.random(1, 100) <= chance then
				-- Determine which creature to apply the stat change to
				local targetCreature = nil
				local targetIsPlayer = false
				local creatureName = ""
				
				if target == "Self" then
					targetCreature = attacker
					targetIsPlayer = isPlayer
					creatureName = attacker.Nickname or attacker.Name or "Creature"
				else -- "Opponent"
					targetCreature = defender
					targetIsPlayer = not isPlayer
					creatureName = defender.Nickname or defender.Name or "Creature"
				end
				
				-- Apply the stat change using StatStages module
				if targetCreature and StatStages then
					local newStage, actualChange = StatStages.ModifyStage(targetCreature, stat, stages)
					
					-- Generate message based on actual change
					local message = StatStages.GetChangeMessage(creatureName, stat, stages, actualChange)
					
					-- Add stat stage step to battle result
					table.insert(steps, {
						Type = "StatStage",
						Stat = stat,
						Stages = actualChange,
						Message = message,
						IsPlayer = targetIsPlayer,
					})
					
					DBG:print("[STAT MOVE] Applied", actualChange, "stages to", stat, "for", creatureName, "- New stage:", newStage)
				end
			end
		end
		
		return prependWakeUpMessage(steps)
	end
	
	-- Handle entry hazard moves (Stealth Rock, Spikes, Toxic Spikes)
	if moveDef and moveDef.IsHazard and moveDef.HazardType then
		local EntryHazards = require(game:GetService("ReplicatedStorage").Shared.EntryHazards)
		local steps = {}
		local actorName = attacker.Nickname or attacker.Name or (isPlayer and "Your creature" or "Foe")
		
		-- First show the move was used
		table.insert(steps, {
			Type = "Move",
			Move = moveName,
			Actor = actorName,
			IsPlayer = isPlayer,
		})
		
		-- Hazards are set on the opponent's side
		local hazardType = moveDef.HazardType
		local targetHazards = isPlayer and battle.FoeHazards or battle.PlayerHazards
		
		-- Initialize hazards if needed
		if not targetHazards then
			targetHazards = EntryHazards.CreateEmpty()
		end
		
		-- Check if already at max
		if EntryHazards.IsAtMax(targetHazards, hazardType) then
			local failMessage = EntryHazards.GetFailMessage(hazardType)
			table.insert(steps, {
				Type = "Message",
				Message = failMessage,
				IsPlayer = isPlayer,
			})
		else
			-- Set the hazard
			local updatedHazards, success, layers = EntryHazards.SetHazard(targetHazards, hazardType)
			
			if success then
				-- Update battle state with new hazards
				if isPlayer then
					battle.FoeHazards = updatedHazards
					DBG:print("[HAZARD] Updated battle.FoeHazards:", battle.FoeHazards)
					DBG:print("[HAZARD] FoeHazards.StealthRock:", battle.FoeHazards and battle.FoeHazards.StealthRock)
					DBG:print("[HAZARD] FoeHazards.Spikes:", battle.FoeHazards and battle.FoeHazards.Spikes)
					DBG:print("[HAZARD] FoeHazards.ToxicSpikes:", battle.FoeHazards and battle.FoeHazards.ToxicSpikes)
				else
					battle.PlayerHazards = updatedHazards
					DBG:print("[HAZARD] Updated battle.PlayerHazards:", battle.PlayerHazards)
					DBG:print("[HAZARD] PlayerHazards.StealthRock:", battle.PlayerHazards and battle.PlayerHazards.StealthRock)
					DBG:print("[HAZARD] PlayerHazards.Spikes:", battle.PlayerHazards and battle.PlayerHazards.Spikes)
					DBG:print("[HAZARD] PlayerHazards.ToxicSpikes:", battle.PlayerHazards and battle.PlayerHazards.ToxicSpikes)
				end
				
				local setMessage = EntryHazards.GetSetMessage(hazardType, isPlayer, layers)
				table.insert(steps, {
					Type = "EntryHazard",
					HazardType = hazardType,
					Layers = layers,
					IsPlayer = isPlayer,
					Message = setMessage,
				})
				DBG:print("[HAZARD] Set", hazardType, "layer", layers, "on", isPlayer and "foe's side" or "player's side")
			end
		end
		
		return prependWakeUpMessage(steps)
	end
	
	-- Handle hazard removal moves (Rapid Spin, Defog)
	if moveDef and (moveDef.RemovesHazards or moveName == "Rapid Spin" or moveName == "Defog") then
		local EntryHazards = require(game:GetService("ReplicatedStorage").Shared.EntryHazards)
		local steps = {}
		local actorName = attacker.Nickname or attacker.Name or (isPlayer and "Your creature" or "Foe")
		
		-- First show the move was used
		table.insert(steps, {
			Type = "Move",
			Move = moveName,
			Actor = actorName,
			IsPlayer = isPlayer,
		})
		
		-- Rapid Spin deals damage and clears user's side hazards
		if moveName == "Rapid Spin" then
			-- Calculate and apply damage first
			local isCrit = DamageCalculator and DamageCalculator.RollCriticalHit(attacker, moveDef.Flags and moveDef.Flags.highCrit) or (math.random(1, 16) == 1)
			local dmgRes = DamageCalculator.CalculateDamage(attacker, defender, moveDef, isCrit, nil, nil, battle.Weather)
			local damage = dmgRes.damage
			
			if damage > 0 then
				local before = defender.Stats.HP or 0
				defender.Stats.HP = math.max(0, before - damage)
				
				local effCat = "Normal"
				local effNum = (dmgRes and type(dmgRes.effectiveness) == "number") and dmgRes.effectiveness or 1
				if effNum >= 2 then
					effCat = "Super"
				elseif effNum <= 0.5 then
					effCat = "NotVery"
				elseif effNum == 0 then
					effCat = "Immune"
				end
				
				table.insert(steps, {
					Type = "Damage",
					Damage = damage,
					NewHP = defender.Stats.HP,
					MaxHP = defender.MaxStats and defender.MaxStats.HP,
					Effectiveness = effCat,
					Critical = isCrit,
					IsPlayer = not isPlayer,
				})
				
				if isCrit then
					table.insert(steps, { Type = "Crit", Message = "A critical hit!", IsPlayer = isPlayer })
				end
			end
		end
		
		-- Clear hazards from appropriate side(s)
		local userHazards = isPlayer and battle.PlayerHazards or battle.FoeHazards
		local opponentHazards = isPlayer and battle.FoeHazards or battle.PlayerHazards
		
		-- Rapid Spin clears user's side, Defog clears both
		if userHazards then
			local hadSR = userHazards.StealthRock == true
			local hadSpikes = (userHazards.Spikes or 0) > 0
			local hadToxic = (userHazards.ToxicSpikes or 0) > 0
			
			if hadSR or hadSpikes or hadToxic then
				local clearedHazards, wasCleared = EntryHazards.ClearAll(userHazards)
				if isPlayer then
					battle.PlayerHazards = clearedHazards
				else
					battle.FoeHazards = clearedHazards
				end
				
				local clearMessage = EntryHazards.GetClearMessage(isPlayer, hadSR, hadSpikes, hadToxic)
				if clearMessage ~= "" then
					table.insert(steps, {
						Type = "Message",
						Message = clearMessage,
						IsPlayer = isPlayer,
					})
				end
				DBG:print("[HAZARD] Cleared hazards from", isPlayer and "player's side" or "foe's side")
			end
		end
		
		-- Defog also clears opponent's hazards
		if moveName == "Defog" and opponentHazards then
			local hadSR = opponentHazards.StealthRock == true
			local hadSpikes = (opponentHazards.Spikes or 0) > 0
			local hadToxic = (opponentHazards.ToxicSpikes or 0) > 0
			
			if hadSR or hadSpikes or hadToxic then
				local clearedHazards, wasCleared = EntryHazards.ClearAll(opponentHazards)
				if isPlayer then
					battle.FoeHazards = clearedHazards
				else
					battle.PlayerHazards = clearedHazards
				end
				
				local clearMessage = EntryHazards.GetClearMessage(not isPlayer, hadSR, hadSpikes, hadToxic)
				if clearMessage ~= "" then
					table.insert(steps, {
						Type = "Message",
						Message = clearMessage,
						IsPlayer = not isPlayer,
					})
				end
				DBG:print("[HAZARD] Defog cleared hazards from", isPlayer and "foe's side" or "player's side")
			end
		end
		
		-- Apply Rapid Spin's stat change (Speed +1)
		if moveName == "Rapid Spin" and moveDef.StatChanges then
			for _, statChange in ipairs(moveDef.StatChanges) do
				local stat = statChange.Stat
				local stages = statChange.Stages
				local chance = statChange.Chance or 100
				
				if math.random(1, 100) <= chance then
					if attacker and StatStages then
						local newStage, actualChange = StatStages.ModifyStage(attacker, stat, stages)
						local message = StatStages.GetChangeMessage(actorName, stat, stages, actualChange)
						table.insert(steps, {
							Type = "StatStage",
							Stat = stat,
							Stages = actualChange,
							Message = message,
							IsPlayer = isPlayer,
						})
					end
				end
			end
		end
		
		-- Apply Defog's evasion drop
		if moveName == "Defog" and moveDef.StatChanges then
			for _, statChange in ipairs(moveDef.StatChanges) do
				local stat = statChange.Stat
				local stages = statChange.Stages
				local target = statChange.Target or "Opponent"
				
				local targetCreature = (target == "Self") and attacker or defender
				local targetIsPlayer = (target == "Self") and isPlayer or (not isPlayer)
				local creatureName = targetCreature.Nickname or targetCreature.Name or "Creature"
				
				if targetCreature and StatStages then
					local newStage, actualChange = StatStages.ModifyStage(targetCreature, stat, stages)
					local message = StatStages.GetChangeMessage(creatureName, stat, stages, actualChange)
					table.insert(steps, {
						Type = "StatStage",
						Stat = stat,
						Stages = actualChange,
						Message = message,
						IsPlayer = targetIsPlayer,
					})
				end
			end
		end
		
		return prependWakeUpMessage(steps)
	end

	-- Check for type immunity abilities (Sap Siphon, Water Press, Amphibious, etc.)
	local typeImmune, immuneAbilityName = Abilities.CheckTypeImmunity(defender, modifiedType)
	if typeImmune then
		local defenderName = defender.Nickname or defender.Name or "Creature"
		local actorName = attacker.Name or (isPlayer and "Your creature" or "Foe")
		
		-- First show the move was used
		local moveStep = {
			Type = "Move",
			Move = moveName,
			Actor = actorName,
			IsPlayer = isPlayer,
		}
		
		-- Then show ability activation with immunity effect
		local abilityStep = {
			Type = "AbilityActivation",
			Ability = immuneAbilityName,
			Creature = defenderName,
			Message = "It doesn't affect " .. defenderName .. "...",
			IsPlayer = not isPlayer,
		}
		
		-- Check if the ability heals or boosts stats on absorption
		local abilityEffect = Abilities.OnHitByType(defender, modifiedType)
		if abilityEffect then
			if abilityEffect.HealPercent then
				local maxHP = defender.MaxStats and defender.MaxStats.HP or 1
				local healAmount = math.floor(maxHP * (abilityEffect.HealPercent / 100))
				defender.Stats.HP = math.min(maxHP, defender.Stats.HP + healAmount)
				abilityStep.Message = defenderName .. " restored HP using its " .. immuneAbilityName .. "!"
				DBG:print("[ABILITY]", immuneAbilityName, "- Absorbed and healed", healAmount, "HP")
				return {moveStep, abilityStep, { Type = "Heal", Amount = healAmount, IsPlayer = not isPlayer }}
			elseif abilityEffect.StatChange then
				defender.StatStages = defender.StatStages or {}
				local stat = abilityEffect.StatChange.Stat
				local stages = abilityEffect.StatChange.Stages
				defender.StatStages[stat] = (defender.StatStages[stat] or 0) + stages
				defender.StatStages[stat] = math.clamp(defender.StatStages[stat], -6, 6)
				
				local statNames = { Attack = "Attack", Defense = "Defense", Speed = "Speed" }
				local statName = statNames[stat] or stat
				local changeText = stages > 0 and "rose" or "fell"
				abilityStep.Message = defenderName .. "'s " .. statName .. " " .. changeText .. "!"
				abilityStep.StatChange = abilityEffect.StatChange
				DBG:print("[ABILITY]", immuneAbilityName, "- Absorbed and boosted", stat, "by", stages)
				return {moveStep, abilityStep}
			end
		end
		
		DBG:print("[ABILITY]", immuneAbilityName, "- Type immunity triggered for", defenderName)
		return {moveStep, abilityStep}
	end
	
	-- Check accuracy before dealing damage
	local accuracyStage = (attacker.StatStages and attacker.StatStages.Accuracy) or 0
	local evasionStage = (defender.StatStages and defender.StatStages.Evasion) or 0
	
	local hit = DamageCalculator.CheckAccuracy(moveName, accuracyStage, evasionStage, attacker)
	if not hit then
		local missMessage = isPlayer and "The foe avoided the attack!" or "Your creature avoided the attack!"
		DBG:print("[MISS]", (attacker.Nickname or attacker.Name or (isPlayer and "Player" or "Enemy")), "used", moveName, "but it missed!")
		-- Return only Miss step - don't include Move step to prevent double execution
		-- The Miss step will display the move name in the message
		return prependWakeUpMessage({
			{ Type = "Miss", Message = missMessage, Move = moveName, Actor = attacker.Name or (isPlayer and "Your creature" or "Foe"), IsPlayer = isPlayer }
		})
	end

	-- Prepare effective move data with type modifications
	local effectiveMoveData = moveDef
	if modifiedType ~= moveDef.Type then
		effectiveMoveData = table.clone(moveDef)
		effectiveMoveData.Type = modifiedType
	end

	-- Multi-hit move handling
	local multiHitConfig = moveDef and moveDef.MultiHit
	local hitCount = multiHitConfig and CalculateMultiHitCount(multiHitConfig) or 1
	local isMultiHit = hitCount > 1
	
	local actorName = attacker.Name or (isPlayer and "Your creature" or "Foe")
	local steps = {}
	local totalDamage = 0
	local actualHits = 0
	local anyCrit = false
	local lastEffCat = "Normal"
	
	-- Add initial Move step (shows the move name once at the start)
	local moveStep = {
		Type = "Move",
		Move = moveName,
		Actor = actorName,
		IsPlayer = isPlayer,
		IsMultiHit = isMultiHit,
		ExpectedHits = hitCount,
	}
	table.insert(steps, moveStep)
	
	-- Process each hit
	for hitNum = 1, hitCount do
		-- Stop if defender already fainted
		if defender.Stats.HP <= 0 then
			DBG:print("[MULTI-HIT] Stopping at hit", hitNum, "- defender fainted")
			break
		end
		
		-- Calculate damage for this hit (each hit can crit independently)
		local isCrit = DamageCalculator and DamageCalculator.RollCriticalHit(attacker, moveDef.Flags and moveDef.Flags.highCrit) or (math.random(1, 16) == 1)
		if isCrit then anyCrit = true end
		
		-- For Triple Kick-style moves, increase power with each hit
		local hitMoveData = effectiveMoveData
		if moveName == "Triple Kick" and moveDef.BasePower then
			hitMoveData = table.clone(effectiveMoveData)
			hitMoveData.BasePower = moveDef.BasePower * hitNum -- 10, 20, 30
		end
		
		local dmgRes = DamageCalculator.CalculateDamage(attacker, defender, hitMoveData, isCrit, nil, nil, battle.Weather)
		local damage = dmgRes.damage
		
		-- Optional global damage tuning (Pokémon-faithful default is 1.0)
		if not isPlayer and Config and type(Config.ENEMY_DAMAGE_MULT) == "number" and Config.ENEMY_DAMAGE_MULT ~= 1.0 then
			damage = math.max(1, math.floor(damage * Config.ENEMY_DAMAGE_MULT))
		end
		
		-- Determine effectiveness category
		local effCat = "Normal"
		local effNum = (dmgRes and type(dmgRes.effectiveness) == "number") and dmgRes.effectiveness or 1
		if effNum == 0 then
			effCat = "Immune"
		elseif effNum >= 2 then
			effCat = "Super"
		elseif effNum <= 0.5 then
			effCat = "NotVery"
		end
		lastEffCat = effCat
		
		-- Apply damage
		local before = defender.Stats.HP or 0
		local after = math.max(0, before - damage)
		
		-- Focus Bandage check (only on the hit that would KO)
		do
			local held = defender.HeldItem
			if held and string.lower(held) == string.lower("Focus Bandage") and after <= 0 and before > 0 then
				if math.random() < 0.1 then
					after = 1
					DBG:print("[HeldItem] Focus Bandage saved", defender.Name, "at 1 HP")
				end
			end
		end
		defender.Stats.HP = after
		after = defender.Stats.HP or 0
		
		totalDamage = totalDamage + damage
		actualHits = actualHits + 1
		
		DBG:print("[DAMAGE] Hit", hitNum, "/", hitCount, "-", (attacker.Nickname or attacker.Name), "used", moveName, "dmg:", damage, "HP:", before, "->", after, isCrit and "(CRIT)" or "")
		
		-- Add a damage step for this hit
		local damageStep = {
			Type = "Damage",
			Effectiveness = effCat,
			IsPlayer = not isPlayer,
			NewHP = defender.Stats.HP,
			HitNumber = hitNum,
			TotalHits = hitCount,
			IsMultiHit = isMultiHit,
			IsCrit = isCrit,
			DamageAmount = damage,
		}
		table.insert(steps, damageStep)
	end
	
	-- Update the Move step with final totals
	-- For multi-hit moves, DON'T set HPDelta - let individual Damage steps handle HP updates
	-- This prevents all damage being applied at once when the Move animation plays
	if not isMultiHit then
		moveStep.HPDelta = isPlayer and {Enemy = -totalDamage} or {Player = -totalDamage}
	end
	moveStep.Critical = anyCrit
	moveStep.Effectiveness = lastEffCat
	moveStep.ActualHits = actualHits
	moveStep.TotalDamage = totalDamage -- Store for reference but don't use for HP update
	
	-- Add multi-hit summary step if it was a multi-hit move
	if isMultiHit then
		table.insert(steps, {
			Type = "MultiHitSummary",
			HitCount = actualHits,
			TotalDamage = totalDamage,
			MoveName = moveName,
			IsPlayer = isPlayer,
		})
		DBG:print("[MULTI-HIT]", moveName, "hit", actualHits, "time(s) for", totalDamage, "total damage")
	end
	
	-- Update client data if player was damaged
	if not isPlayer then
		local PlayerData = ClientData:Get(Player)
		if PlayerData and PlayerData.Party and battle.PlayerCreatureIndex then
			local slot = PlayerData.Party[battle.PlayerCreatureIndex]
			if slot then
				slot.Stats = slot.Stats or {}
				slot.Stats.HP = defender.Stats.HP
				local maxHP = (battle.PlayerCreature.MaxStats and battle.PlayerCreature.MaxStats.HP) or slot.MaxStats and slot.MaxStats.HP
				if maxHP and maxHP > 0 then
					slot.CurrentHP = math.clamp(math.floor((defender.Stats.HP / maxHP) * 100 + 0.5), 0, 100)
				end
			end
			if ClientData.UpdateClientData then
				ClientData:UpdateClientData(Player, PlayerData)
			end
		end
	end
	
	-- For post-processing, use total damage and whether any hit was a crit
	local damage = totalDamage
	local isCrit = anyCrit
	local effCat = lastEffCat
	
	-- Echo Bell: heal attacker slightly on successful damage
	do
		if attacker and attacker.HeldItem and string.lower(attacker.HeldItem) == string.lower("Echo Bell") then
			if damage > 0 and attacker.Stats and attacker.MaxStats then
				local maxHP = attacker.MaxStats.HP or 1
				local heal = math.max(1, math.floor(maxHP / 16))
				local cur = attacker.Stats.HP or 0
				attacker.Stats.HP = math.min(maxHP, cur + heal)
				table.insert(steps, { Type = "Heal", Amount = heal, IsPlayer = isPlayer, Message = "Echo Bell restored some HP!" })
			end
		end
	end
	
	-- Apply status effects from move (only if move hit and dealt damage)
	if moveDef and moveDef.StatusEffect and damage > 0 then
		local statusType = moveDef.StatusEffect
		local statusChance = moveDef.StatusChance or 100
		
		-- Validate statusType is a string (status code)
		if type(statusType) ~= "string" then
			DBG:warn("[BattleSystem] Invalid StatusEffect type - expected string, got:", type(statusType), "Value:", statusType, "Move:", moveName)
			-- Skip status application if invalid
		-- Check if creature already has this status condition (Pokemon-style: can't re-apply same status)
		elseif defender.Status and defender.Status.Type == statusType then
			-- Creature already has this status - don't apply again
			DBG:print("[BattleSystem] Status", statusType, "already applied to", defender.Nickname or defender.Name, "- skipping")
		-- Check for ability-based status immunity
		else
			local isImmune, immuneAbilityName = Abilities.IsImmuneToStatus(defender, statusType, battle.Weather)
			if isImmune then
				-- Show ability notification for status immunity
				local defenderName = defender.Nickname or defender.Name or "Creature"
				table.insert(steps, {
					Type = "AbilityActivation",
					Ability = immuneAbilityName or "Unknown Ability",
					Creature = defenderName,
					Message = defenderName .. " is protected by its " .. (immuneAbilityName or "ability") .. "!",
					IsPlayer = not isPlayer,
				})
				DBG:print("[ABILITY] Status immunity -", immuneAbilityName, "prevented", statusType, "on", defenderName)
			elseif math.random(1, 100) <= statusChance then
				local statusApplied = StatusModule.Apply(defender, statusType, (statusType == "SLP") and math.random(1, 3) or nil)
				if statusApplied then
					local statusMessage = string.format("%s was %s!", defender.Nickname or defender.Name, 
						statusType == "BRN" and "burned" or
						statusType == "PAR" and "paralyzed" or
						statusType == "PSN" and "poisoned" or
						statusType == "TOX" and "badly poisoned" or
						statusType == "SLP" and "put to sleep" or
						statusType == "FRZ" and "frozen" or "affected")
					table.insert(steps, { Type = "Status", Status = statusType, Message = statusMessage, IsPlayer = not isPlayer })
					DBG:print("[BattleSystem] Status step created - Status:", statusType, "Message:", statusMessage)
				end
			end
		end
	end
	
	-- Apply flinch if move causes flinch (apply when move hits, regardless of damage amount)
	-- Flinch should apply whenever the move successfully hits the target
	-- Check for flinch immunity first (Absolute Focus / Inner Focus)
	if moveDef and moveDef.CausesFlinch and hit then
		local flinchImmune, immuneAbility = Abilities.IsImmuneToFlinch(defender)
		if flinchImmune then
			-- Show ability notification for flinch immunity
			local defenderName = defender.Nickname or defender.Name or "Creature"
			table.insert(steps, {
				Type = "AbilityActivation",
				Ability = immuneAbility or "Absolute Focus",
				Creature = defenderName,
				Message = defenderName .. " won't flinch because of its " .. (immuneAbility or "Absolute Focus") .. "!",
				IsPlayer = not isPlayer,
			})
			DBG:print("[ABILITY] Flinch prevented by", immuneAbility, "for", defenderName)
		else
			StatusModule.ApplyVolatile(defender, "Flinch")
			DBG:print("[FLINCH] Applied flinch to", defender.Nickname or defender.Name, "from move", moveName)
			-- Add flinch message step immediately after the move hits
			-- This ensures the message appears after the move message, not before
			-- Only show flinch message if creature didn't faint (faithful to Pokemon behavior)
			if defender.Stats.HP > 0 then
				local defenderName = defender.Nickname or defender.Name or "Creature"
				table.insert(steps, {
					Type = "Message",
					Message = defenderName .. " flinched!",
					IsPlayer = not isPlayer,
				})
			end
		end
	end
	
	-- Check for ability activation when hit by a specific type (Swift Current, Sap Siphon, Water Press)
	-- Only trigger if defender was hit and didn't faint
	if damage > 0 and defender.Stats.HP > 0 then
		local abilityEffect = Abilities.OnHitByType(defender, modifiedType)
		if abilityEffect then
			local defenderName = defender.Nickname or defender.Name or "Creature"
			local abilityMessage = nil
			
			if abilityEffect.StatChange then
				-- Apply the stat change
				defender.StatStages = defender.StatStages or {}
				local stat = abilityEffect.StatChange.Stat
				local stages = abilityEffect.StatChange.Stages
				defender.StatStages[stat] = (defender.StatStages[stat] or 0) + stages
				defender.StatStages[stat] = math.clamp(defender.StatStages[stat], -6, 6)
				
				-- Generate the message
				local statNames = { Attack = "Attack", Defense = "Defense", Speed = "Speed" }
				local statName = statNames[stat] or stat
				local changeText = stages > 0 and "rose" or "fell"
				if math.abs(stages) >= 2 then
					changeText = stages > 0 and "sharply rose" or "harshly fell"
				end
				abilityMessage = defenderName .. "'s " .. statName .. " " .. changeText .. "!"
				
				-- Add ability activation step with stat change
				table.insert(steps, {
					Type = "AbilityActivation",
					Ability = abilityEffect.Ability,
					Creature = defenderName,
					Message = abilityMessage,
					IsPlayer = not isPlayer,
					StatChange = abilityEffect.StatChange,
				})
				DBG:print("[ABILITY]", abilityEffect.Ability, "triggered for", defenderName, "- StatChange:", stat, stages)
			elseif abilityEffect.HealPercent then
				-- Apply heal
				local maxHP = defender.MaxStats and defender.MaxStats.HP or 1
				local healAmount = math.floor(maxHP * (abilityEffect.HealPercent / 100))
				defender.Stats.HP = math.min(maxHP, defender.Stats.HP + healAmount)
				
				abilityMessage = defenderName .. " restored HP using its " .. abilityEffect.Ability .. "!"
				
				table.insert(steps, {
					Type = "AbilityActivation",
					Ability = abilityEffect.Ability,
					Creature = defenderName,
					Message = abilityMessage,
					IsPlayer = not isPlayer,
				})
				table.insert(steps, {
					Type = "Heal",
					Amount = healAmount,
					IsPlayer = not isPlayer,
				})
				DBG:print("[ABILITY]", abilityEffect.Ability, "triggered for", defenderName, "- Healed:", healAmount)
			end
		end
	end
	
	-- Apply confusion if move causes confusion (only if move hit and dealt damage)
	if moveDef and moveDef.CausesConfusion and damage > 0 then
		StatusModule.ApplyVolatile(defender, "Confusion", math.random(1, 4))
	end
	
	-- Apply stat stage changes from move (process StatChanges array)
	-- This handles moves that modify stats (like Power-Up Punch, Screech, etc.)
	if moveDef and moveDef.StatChanges and hit then
		for _, statChange in ipairs(moveDef.StatChanges) do
			local stat = statChange.Stat
			local stages = statChange.Stages
			local target = statChange.Target or (stages > 0 and "Self" or "Opponent")
			local chance = statChange.Chance or 100
			
			-- Roll for stat change chance
			if math.random(1, 100) <= chance then
				-- Determine which creature to apply the stat change to
				local targetCreature = nil
				local targetIsPlayer = false
				local creatureName = ""
				
				if target == "Self" then
					targetCreature = attacker
					targetIsPlayer = isPlayer
					creatureName = attacker.Nickname or attacker.Name or "Creature"
				else -- "Opponent"
					targetCreature = defender
					targetIsPlayer = not isPlayer
					creatureName = defender.Nickname or defender.Name or "Creature"
				end
				
				-- Apply the stat change using StatStages module
				if targetCreature and StatStages then
					local newStage, actualChange = StatStages.ModifyStage(targetCreature, stat, stages)
					
					-- Generate message based on actual change
					local message = StatStages.GetChangeMessage(creatureName, stat, stages, actualChange)
					
					-- Add stat stage step to battle result
					table.insert(steps, {
						Type = "StatStage",
						Stat = stat,
						Stages = actualChange,
						Message = message,
						IsPlayer = targetIsPlayer,
					})
					
					DBG:print("[STAT STAGE] Applied", actualChange, "stages to", stat, "for", creatureName, "- New stage:", newStage)
				end
			end
		end
	end
	
	-- Apply recoil damage if move has RecoilPercent and damage was dealt
	local recoilApplied = false
	if moveDef and moveDef.RecoilPercent and damage > 0 and attacker and attacker.Stats then
		-- Check if attacker has ability that negates recoil (Hard Head)
		local negatesRecoil = Abilities.NegatesRecoil(attacker)
		if negatesRecoil then
			local attackerName = attacker.Nickname or attacker.Name or "Creature"
			DBG:print("[RECOIL] Negated by Hard Head for", attackerName)
		else
			-- Calculate recoil damage as percentage of damage dealt
			local recoilDamage = math.max(1, math.floor(damage * (moveDef.RecoilPercent / 100)))
			local attackerMaxHP = attacker.MaxStats and attacker.MaxStats.HP or 1
			local attackerBefore = attacker.Stats.HP or 0
			local attackerAfter = math.max(0, attackerBefore - recoilDamage)
			
			attacker.Stats.HP = attackerAfter
			recoilApplied = true
			
			local attackerName = attacker.Nickname or attacker.Name or "Creature"
			DBG:print("[RECOIL]", attackerName, "took", recoilDamage, "recoil damage (", moveDef.RecoilPercent, "% of", damage, ") HP:", attackerBefore, "->", attackerAfter)
			
			-- Add recoil step for client to display
			local recoilStep = {
				Type = "Recoil",
				Creature = attackerName,
				IsPlayer = isPlayer,
				RecoilDamage = recoilDamage,
				NewHP = attackerAfter,
				MaxHP = attackerMaxHP,
			}
			table.insert(steps, recoilStep)
			
			-- Update party data for the attacker taking recoil
			if isPlayer then
				local pd = ClientData:Get(Player)
				if pd and pd.Party and battle.PlayerCreatureIndex then
					local slot = pd.Party[battle.PlayerCreatureIndex]
					if slot then
						slot.Stats = slot.Stats or {}
						slot.Stats.HP = attackerAfter
						if attackerMaxHP > 0 then
							slot.CurrentHP = math.clamp(math.floor((attackerAfter / attackerMaxHP) * 100 + 0.5), 0, 100)
						end
						if ClientData.UpdateClientData then
							ClientData:UpdateClientData(Player, pd)
						end
					end
				end
			else
				-- Enemy took recoil (AI or opponent player)
				local opp = battle.OpponentPlayer
				if opp then
					local pdOpp = ClientData:Get(opp)
					if pdOpp and pdOpp.Party and battle.FoeCreatureIndex then
						local slot = pdOpp.Party[battle.FoeCreatureIndex]
						if slot then
							slot.Stats = slot.Stats or {}
							slot.Stats.HP = attackerAfter
							if attackerMaxHP > 0 then
								slot.CurrentHP = math.clamp(math.floor((attackerAfter / attackerMaxHP) * 100 + 0.5), 0, 100)
							end
							if ClientData.UpdateClientData then
								ClientData:UpdateClientData(opp, pdOpp)
							end
						end
					end
				end
			end
			
			-- Check if attacker fainted from recoil
			if attackerAfter <= 0 then
				attacker.Stats.HP = 0
				attacker.CurrentHP = 0
				local attackerFaintStep = {
					Type = "Faint",
					Creature = attackerName,
					IsPlayer = isPlayer,
					FromRecoil = true,
				}
				table.insert(steps, attackerFaintStep)
				DBG:print("[RECOIL] Attacker", attackerName, "fainted from recoil damage!")
				
				-- Update party data for attacker faint
				if isPlayer then
					local pd = ClientData:Get(Player)
					if pd and pd.Party and battle.PlayerCreatureIndex then
						local slot = pd.Party[battle.PlayerCreatureIndex]
						if slot then
							slot.Stats = slot.Stats or {}
							slot.Stats.HP = 0
							slot.CurrentHP = 0
							if ClientData.UpdateClientData then
								ClientData:UpdateClientData(Player, pd)
							end
						end
					end
				end
			end
		end
	end
	
	-- Check for defender faint AFTER applying effects (flinch should still apply even if target faints)
	if defender.Stats.HP <= 0 then
		local faintStep = {
			Type = "Faint",
			Creature = defender.Name or (isPlayer and "Foe" or "Your creature"),
			IsPlayer = not isPlayer
		}
		
		DBG:print("=== FAINT STEP CREATED ===")
		DBG:print("Defender:", defender.Name, "HP:", defender.Stats.HP)
		DBG:print("IsPlayer (attacker):", isPlayer)
		DBG:print("FaintStep.IsPlayer:", faintStep.IsPlayer)
		DBG:print("FaintStep.Creature:", faintStep.Creature)
		DBG:print("=== END FAINT STEP ===")
		
		-- Authoritatively zero out HP/CurrentHP on the defender (battle state + party mirror)
		defender.Stats.HP = 0
		defender.CurrentHP = 0
		if not isPlayer then
			-- Player took the hit
			local pd = ClientData:Get(Player)
			if pd and pd.Party and battle.PlayerCreatureIndex then
				local slot = pd.Party[battle.PlayerCreatureIndex]
				if slot then
					slot.Stats = slot.Stats or {}
					slot.Stats.HP = 0
					slot.CurrentHP = 0
					slot.MaxStats = slot.MaxStats or defender.MaxStats
					if ClientData.UpdateClientData then
						ClientData:UpdateClientData(Player, pd)
					end
				end
			end
		else
			-- Opponent took the hit; mirror into their party data if available
			local opp = battle.OpponentPlayer
			if opp then
				local pdOpp = ClientData:Get(opp)
				if pdOpp and pdOpp.Party and battle.FoeCreatureIndex then
					local slot = pdOpp.Party[battle.FoeCreatureIndex]
					if slot then
						slot.Stats = slot.Stats or {}
						slot.Stats.HP = 0
						slot.CurrentHP = 0
						slot.MaxStats = slot.MaxStats or defender.MaxStats
						if ClientData.UpdateClientData then
							ClientData:UpdateClientData(opp, pdOpp)
						end
					end
				end
			end
		end

		table.insert(steps, faintStep)
	end
	
	-- Keep both PvP parties' stored HP in sync with in-battle state so defeat detection is accurate
	if battle.Type == "PvP" then
		syncPartyHpFromBattle(Player, battle.PlayerCreature, battle.PlayerCreatureIndex)
		syncPartyHpFromBattle(battle.OpponentPlayer, battle.FoeCreature, battle.FoeCreatureIndex)
	end

	-- Restore attacker HP if it changed unexpectedly (but NOT if recoil was properly applied)
	if not recoilApplied and attacker and attacker.Stats and attackerHPBefore and attacker.Stats.HP ~= attackerHPBefore then
		attacker.Stats.HP = attackerHPBefore
	end

	return prependWakeUpMessage(steps)
end

-- Helper to determine fainted state from either absolute or percent HP
local function isCreatureFainted(creature: any?): boolean
	if not creature then
		return false
	end
	local hpPercent = creature.CurrentHP
	local hpAbs = creature.Stats and creature.Stats.HP
	if hpAbs ~= nil then
		return hpAbs <= 0
	end
	if hpPercent ~= nil then
		return hpPercent <= 0
	end
	return false
end

-- Mirror the live battle creature HP back into the owner's party data
-- This keeps PvP defeat detection in sync with the actual battle state
-- Build a battle-ready clone of a party creature with calculated stats and moves
local function buildBattleCreatureFromParty(source: any): (any, number, number)
	local battleCreature = table.clone(source)
	local level = battleCreature.Level or 1
	local stats, maxStats = StatCalc.ComputeStats(battleCreature.Name, level, battleCreature.IVs, battleCreature.Nature)
	local currentHPPercent = battleCreature.CurrentHP
	local currentHPAbs: number
	if currentHPPercent == nil then
		currentHPPercent = 100
		currentHPAbs = maxStats.HP
		battleCreature.CurrentHP = currentHPPercent
	else
		currentHPPercent = math.clamp(currentHPPercent, 0, 100)
		currentHPAbs = math.floor(maxStats.HP * (currentHPPercent / 100) + 0.5)
	end
	battleCreature.Level = level
	battleCreature.Stats = stats
	battleCreature.Stats.HP = currentHPAbs
	battleCreature.MaxStats = maxStats
	HeldItemEffects.ApplyStatMods(battleCreature)

	local creatureData = CreaturesModule[battleCreature.Name]
	-- Ensure battle creatures always have a Type (used by weather immunity, effectiveness, etc.)
	-- Party data often omits Type to save space, so we copy it from the creature definition.
	if (battleCreature.Type == nil or battleCreature.Type == "" or (type(battleCreature.Type) == "table" and #battleCreature.Type == 0))
		and creatureData and creatureData.Type ~= nil then
		battleCreature.Type = creatureData.Type
	end
	if creatureData and creatureData.LearnableMoves then
		battleCreature.CurrentMoves = CreatureSystem.GetMovesForLevel(creatureData.LearnableMoves, level)
	end

	return battleCreature, currentHPAbs, currentHPPercent
end

--[[
	Execute a switch action (PvP-safe implementation)
	@param Player The player
	@param action The switch action
	@param battle The battle state
	@param isPlayer Whether this is the player's switch
	@return table Action result
]]
function BattleSystem.ExecuteSwitchAction(Player: Player, action: any, battle: any, isPlayer: boolean): any
	if not battle then
		return {Type = "Message", Message = "No active battle", IsPlayer = isPlayer}
	end

	local targetSlot = tonumber(action.Slot or action.Index or action.PartyIndex)
	if not targetSlot then
		return {Type = "Message", Message = "Invalid switch selection", IsPlayer = isPlayer}
	end

	-- Trainer (NPC) switching: uses battle.TrainerParty instead of ClientData/battle.OpponentPlayer.
	if (not isPlayer) and (battle.Type == "Trainer") then
		if type(battle.TrainerParty) ~= "table" then
			return {Type = "Message", Message = "Trainer has no party", IsPlayer = false}
		end

		local trainerParty = battle.TrainerParty
		local currentActive = battle.FoeCreature
		local currentIndex = battle.FoeCreatureIndex

		if currentIndex == targetSlot then
			return {Type = "Message", Message = "Creature already active", IsPlayer = false}
		end
		local targetCreature = trainerParty[targetSlot]
		if not targetCreature then
			return {Type = "Message", Message = "Invalid party slot", IsPlayer = false}
		end
		if isCreatureFainted(targetCreature) then
			return {Type = "Message", Message = "Cannot switch to fainted creature", IsPlayer = false}
		end

		-- Sync the outgoing foe's HP back into trainer party (so it can be switched back in later correctly).
		if type(currentIndex) == "number" and trainerParty[currentIndex] and currentActive and currentActive.Stats then
			local slot = trainerParty[currentIndex]
			slot.Stats = slot.Stats or {}
			slot.Stats.HP = currentActive.Stats.HP or 0
			local maxHP = (currentActive.MaxStats and currentActive.MaxStats.HP) or (slot.MaxStats and slot.MaxStats.HP) or 1
			slot.CurrentHP = math.clamp(math.floor(((slot.Stats.HP or 0) / math.max(1, maxHP)) * 100 + 0.5), 0, 100)
		end

		-- Gen 8–9: Toxic counter resets on switch-out.
		resetToxicCounterOnSwitchOut(currentActive)

		local forcedSwitch = isCreatureFainted(currentActive)

		-- Promote new active
		battle.FoeCreatureIndex = targetSlot
		battle.FoeCreature = targetCreature
		if StatStages then
			StatStages.ResetAll(targetCreature)
			StatStages.EnsureCreatureHasStages(targetCreature)
		end

		-- Build steps matching existing client conventions
		local steps: {any} = {}
		local oldName = currentActive and (currentActive.Nickname or currentActive.Name) or "Creature"
		local newName = targetCreature and (targetCreature.Nickname or targetCreature.Name) or "Creature"
		local variant = math.random(1, 3)

		if not forcedSwitch then
			table.insert(steps, {
				Type = "Switch",
				Action = "Recall",
				Creature = oldName,
				IsPlayer = false,
				TrainerName = battle.TrainerName,
			})
		end

		local creatureDataClone = table.clone(targetCreature)
		if creatureDataClone.Stats then
			creatureDataClone.Stats = table.clone(creatureDataClone.Stats)
		end
		if creatureDataClone.MaxStats then
			creatureDataClone.MaxStats = table.clone(creatureDataClone.MaxStats)
		end

		table.insert(steps, {
			Type = "Switch",
			Action = "SendOut",
			Creature = newName,
			Variant = variant,
			IsPlayer = false,
			TrainerName = battle.TrainerName,
			CreatureData = creatureDataClone,
		})

		-- Apply hazards on the foe's side to the trainer's switch-in
		local EntryHazards = require(game:GetService("ReplicatedStorage").Shared.EntryHazards)
		if battle.FoeHazards then
			local hazardSteps, updatedHazards = EntryHazards.ApplyOnSwitchIn(targetCreature, battle.FoeHazards, false)
			if updatedHazards then
				battle.FoeHazards = updatedHazards
			end
			for _, hazardStep in ipairs(hazardSteps) do
				table.insert(steps, hazardStep)
			end
			if #hazardSteps > 0 and targetCreature.Stats then
				creatureDataClone.Stats = creatureDataClone.Stats or {}
				creatureDataClone.Stats.HP = targetCreature.Stats.HP
			end
		end

		return steps
	end

	-- Identify the player whose party is being switched
	local actorPlayer: Player? = isPlayer and Player or battle.OpponentPlayer
	if not actorPlayer or not actorPlayer.Parent then
		return {Type = "Message", Message = "Opponent unavailable", IsPlayer = isPlayer}
	end

	local actorData = ClientData:Get(actorPlayer)
	if not actorData or not actorData.Party or not actorData.Party[targetSlot] then
		return {Type = "Message", Message = "Invalid party slot", IsPlayer = isPlayer}
	end

	local partyCreature = actorData.Party[targetSlot]
	local currentActive = isPlayer and battle.PlayerCreature or battle.FoeCreature
	local currentIndex = isPlayer and battle.PlayerCreatureIndex or battle.FoeCreatureIndex

	-- Prevent switching to the same slot or to a fainted creature
	if currentIndex == targetSlot then
		return {Type = "Message", Message = "Creature already active", IsPlayer = isPlayer}
	end
	if isCreatureFainted(partyCreature) then
		return {Type = "Message", Message = "Cannot switch to fainted creature", IsPlayer = isPlayer}
	end

	local forcedSwitch = isCreatureFainted(currentActive)

	-- Reset toxic counter on switch-out (Gen 8–9 behavior)
	resetToxicCounterOnSwitchOut(currentActive)

	-- CRITICAL: Sync the OLD creature's HP to party data BEFORE switching
	-- This ensures fainted creatures are properly recorded in party data for defeat detection
	if currentIndex and currentActive and currentActive.Stats then
		local oldSlot = actorData.Party[currentIndex]
		if oldSlot then
			oldSlot.Stats = oldSlot.Stats or {}
			oldSlot.Stats.HP = currentActive.Stats.HP or 0
			-- Also sync CurrentHP percentage
			local maxHP = (currentActive.MaxStats and currentActive.MaxStats.HP) or (oldSlot.MaxStats and oldSlot.MaxStats.HP) or 1
			oldSlot.CurrentHP = math.clamp(math.floor(((currentActive.Stats.HP or 0) / math.max(1, maxHP)) * 100 + 0.5), 0, 100)
			DBG:print("[Switch] Synced old creature HP at slot", currentIndex, ":", oldSlot.Stats.HP, "CurrentHP%:", oldSlot.CurrentHP)
		end
	end

	-- Build battle-ready creature and persist party stats/HP for consistency
	local newBattleCreature, currentHPAbs, currentHPPercent = buildBattleCreatureFromParty(partyCreature)
	actorData.Party[targetSlot].Stats = actorData.Party[targetSlot].Stats or {}
	actorData.Party[targetSlot].Stats.HP = currentHPAbs
	actorData.Party[targetSlot].MaxStats = newBattleCreature.MaxStats
	actorData.Party[targetSlot].CurrentHP = currentHPPercent

	if ClientData.UpdateClientData then
		ClientData:UpdateClientData(actorPlayer, actorData)
	end

	local switchMode: string = forcedSwitch and "Forced" or "Voluntary"

	-- Update the active battle state
	if isPlayer then
		battle.PlayerCreatureIndex = targetSlot
		battle.PlayerCreatureOriginalIndex = targetSlot
		battle.PlayerCreatureOriginalData = partyCreature
		battle.PlayerCreature = newBattleCreature
		battle.SwitchMode = switchMode
		-- Reset stat stages for the new creature
		if StatStages then
			StatStages.ResetAll(newBattleCreature)
			StatStages.EnsureCreatureHasStages(newBattleCreature)
		end
	else
		battle.FoeCreatureIndex = targetSlot
		battle.FoeCreature = newBattleCreature
		-- Reset stat stages for the new creature
		if StatStages then
			StatStages.ResetAll(newBattleCreature)
			StatStages.EnsureCreatureHasStages(newBattleCreature)
		end
	end

	-- Keep the opponent's battle table mirrored
	local opponentPlayer: Player? = battle.OpponentPlayer
	if opponentPlayer and opponentPlayer.Parent then
		local oppBattle = ActiveBattles[opponentPlayer]
		if oppBattle then
			if isPlayer then
				oppBattle.FoeCreatureIndex = targetSlot
				oppBattle.FoeCreature = table.clone(newBattleCreature)
			else
				oppBattle.PlayerCreatureIndex = targetSlot
				oppBattle.PlayerCreatureOriginalIndex = targetSlot
				oppBattle.PlayerCreatureOriginalData = partyCreature
				oppBattle.PlayerCreature = table.clone(newBattleCreature)
				oppBattle.SwitchMode = switchMode
			end
		end
	end

	-- Build action steps; forced switches skip recall
	local steps: {any} = {}
	local oldName = currentActive and (currentActive.Nickname or currentActive.Name) or "Creature"
	local newName = newBattleCreature and (newBattleCreature.Nickname or newBattleCreature.Name) or "Creature"
	local variant = math.random(1, 3)

	if not forcedSwitch then
		table.insert(steps, {Type = "Switch", Action = "Recall", Creature = oldName, IsPlayer = isPlayer})
	end

	-- CRITICAL: Include full CreatureData so client spawns the correct model
	-- Without this, client falls back to stale battle state which may have the old creature
	-- Deep clone to prevent later modifications from affecting the step data
	local creatureDataClone = table.clone(newBattleCreature)
	if creatureDataClone.Stats then
		creatureDataClone.Stats = table.clone(creatureDataClone.Stats)
	end
	if creatureDataClone.MaxStats then
		creatureDataClone.MaxStats = table.clone(creatureDataClone.MaxStats)
	end
	table.insert(steps, {
		Type = "Switch",
		Action = "SendOut",
		Creature = newName,
		Variant = variant,
		IsPlayer = isPlayer,
		CreatureData = creatureDataClone,  -- Include full creature data for spawning
	})
	
	-- Apply entry hazard damage to the switching-in creature
	local EntryHazards = require(game:GetService("ReplicatedStorage").Shared.EntryHazards)
	local hazardsOnSide = isPlayer and battle.PlayerHazards or battle.FoeHazards
	
	DBG:print("[HAZARD SWITCH] Checking hazards for", isPlayer and "player" or "foe", "switch-in")
	DBG:print("[HAZARD SWITCH] battle.PlayerHazards:", battle.PlayerHazards)
	DBG:print("[HAZARD SWITCH] battle.FoeHazards:", battle.FoeHazards)
	DBG:print("[HAZARD SWITCH] hazardsOnSide:", hazardsOnSide)
	
	if hazardsOnSide then
		local hazardSteps, updatedHazards = EntryHazards.ApplyOnSwitchIn(newBattleCreature, hazardsOnSide, isPlayer)
		
		-- Update hazards state (Toxic Spikes may have been absorbed by Poison type)
		if updatedHazards then
			if isPlayer then
				battle.PlayerHazards = updatedHazards
			else
				battle.FoeHazards = updatedHazards
			end
		end
		
		-- Add hazard damage steps to the switch result
		for _, hazardStep in ipairs(hazardSteps) do
			table.insert(steps, hazardStep)
		end
		
		-- Sync updated HP back to party data if hazard damage was dealt
		if #hazardSteps > 0 and newBattleCreature.Stats then
			local partyCreature = actorData.Party[targetSlot]
			if partyCreature then
				local maxHP = newBattleCreature.MaxStats and newBattleCreature.MaxStats.HP or 1
				local currentHP = newBattleCreature.Stats.HP or 0
				partyCreature.Stats = partyCreature.Stats or {}
				partyCreature.Stats.HP = currentHP
				partyCreature.CurrentHP = math.clamp(math.floor((currentHP / math.max(1, maxHP)) * 100 + 0.5), 0, 100)
				
				if ClientData.UpdateClientData then
					ClientData:UpdateClientData(actorPlayer, actorData)
				end
				
				DBG:print("[HAZARD] Switch-in hazard damage applied, new HP:", currentHP, "/", maxHP)
			end
		end
	end
	
	-- Check for entry abilities (Intimidate, Menace, Solar Wrath, etc.)
	local Abilities = require(game:GetService("ReplicatedStorage").Shared.Abilities)
	local entryEffect = Abilities.OnEntry(newBattleCreature)
	if entryEffect then
		local abilityName = entryEffect.Ability
		local creatureName = newBattleCreature.Nickname or newBattleCreature.Name or "Creature"
		
		if entryEffect.Effect == "Intimidate" and entryEffect.StatChange then
			-- Apply Attack drop to the opposing creature
			local opponent = isPlayer and battle.FoeCreature or battle.PlayerCreature
			if opponent and opponent.Stats then
				opponent.StatStages = opponent.StatStages or {}
				local stat = entryEffect.StatChange.Stat
				local stages = entryEffect.StatChange.Stages
				opponent.StatStages[stat] = (opponent.StatStages[stat] or 0) + stages
				opponent.StatStages[stat] = math.clamp(opponent.StatStages[stat], -6, 6)
				
				local opponentName = opponent.Nickname or opponent.Name or "Foe"
				local statNames = { Attack = "Attack", Defense = "Defense", Speed = "Speed" }
				local statName = statNames[stat] or stat
				local changeText = stages > 0 and "rose" or "fell"
				if math.abs(stages) >= 2 then
					changeText = stages > 0 and "sharply rose" or "harshly fell"
				end
				
				table.insert(steps, {
					Type = "AbilityActivation",
					Ability = abilityName,
					Creature = creatureName,
					Message = opponentName .. "'s " .. statName .. " " .. changeText .. "!",
					IsPlayer = isPlayer,
					StatChange = { Stat = stat, Stages = stages },
				})
				DBG:print("[ABILITY]", abilityName, "triggered -", opponentName, statName, changeText)
			end
		elseif entryEffect.Effect == "Sunlight" then
			-- Set weather to Sunlight
			battle.Weather = "Sunlight"
			battle.WeatherTurns = 5
			
			table.insert(steps, {
				Type = "AbilityActivation",
				Ability = abilityName,
				Creature = creatureName,
				Message = "The sunlight turned harsh!",
				IsPlayer = isPlayer,
			})
			DBG:print("[ABILITY]", abilityName, "triggered - Sunlight set")
		end
	end

	return steps
end

--[[
	Build enemy action (wild or trainer)
	@param Player The player
	@return table? Enemy action or nil
]]
function BattleSystem.BuildEnemyAction(Player: Player): any?
	local battle = ActiveBattles[Player]
	if not battle then return nil end

	if battle.Type == "Trainer" then
		return BattleSystem.ProcessTrainerEnemyTurn(Player)
	else
		return BattleSystem.ProcessWildEnemyTurn(Player)
	end
end

--[[
	Process wild enemy turn
	@param Player The player
	@return table Enemy action
]]
function BattleSystem.ProcessWildEnemyTurn(Player: Player): any
	local battle = ActiveBattles[Player]
	if not battle or not battle.FoeCreature or not battle.FoeCreature.CurrentMoves then
		return {Type = "Move", Move = "Tackle", Actor = "Wild creature"}
	end

	local selectedMove = AIController.SelectWildMove(battle.FoeCreature, battle.PlayerCreature) or "Tackle"

	local foeName = battle.FoeCreature.Name or "Wild creature"

	return {
		Type = "Move",
		Move = selectedMove,
		Actor = foeName
	}
end

--[[
	Process trainer enemy turn
	@param Player The player
	@return table Enemy action
]]
function BattleSystem.ProcessTrainerEnemyTurn(Player: Player): any
	local battle = ActiveBattles[Player]
	if not battle or not battle.FoeCreature or not battle.FoeCreature.CurrentMoves then
		return {Type = "Move", Move = "Tackle", Actor = "Trainer's creature"}
	end

	-- Difficulty can be attached to battle in StartBattle; default to Smart.
	local difficulty = battle.AIDifficulty or battle.TrainerAIDifficulty or "Smart"

	-- Trainer switching (real switch action; handled by ExecuteSwitchAction's Trainer branch)
	local shouldSwitch, switchIndex = AIController.ShouldSwitch(battle.FoeCreature, battle.PlayerCreature, battle.TrainerParty, difficulty)
	if shouldSwitch and type(switchIndex) == "number" and battle.FoeCreatureIndex ~= switchIndex then
		return {
			Type = "Switch",
			PartyIndex = switchIndex,
			Actor = battle.TrainerName or "Trainer",
		}
	end

	local selectedMove = AIController.SelectTrainerMove(battle.FoeCreature, battle.PlayerCreature, difficulty) or "Tackle"
	local foeName = battle.FoeCreature.Name or "Trainer's creature"
	local actorName = "Trainer's " .. foeName

	return {
		Type = "Move",
		Move = selectedMove,
		Actor = actorName,
	}
end

--[[
	Calculate escape chance using Pokemon formula
	@param Player The player
	@param PlayerData The player data
	@return boolean Whether escape succeeds
]]
function BattleSystem.CalculateEscapeChance(Player: Player, PlayerData: any): boolean
	-- Check if escape failure is disabled for wild battles
	local battle = ActiveBattles[Player]
	if battle and battle.Type == "Wild" and not Config.WILD_ESCAPE_FAILURE_ENABLED then
		DBG:print("Wild escape failure disabled - guaranteed escape")
		return true
	end
	
	local PlayerCreature = PlayerData.Party[1]
	if not PlayerCreature or not PlayerCreature.Stats then
		DBG:warn("No player creature stats found")
		return false
	end
	
	local EnemySpeed = 50
	local EnemyLevel = 5
	
	if ActiveBattles[Player] and ActiveBattles[Player].FoeCreature then
		local FoeCreature = ActiveBattles[Player].FoeCreature
		EnemySpeed = FoeCreature.Stats and FoeCreature.Stats.Speed or 50
		EnemyLevel = FoeCreature.Level or 5
		DBG:print("Using enemy stats from battle - Speed:", EnemySpeed, "Level:", EnemyLevel)
	else
		DBG:print("No active battle found, using default enemy stats")
	end
	
	local PlayerSpeed = PlayerCreature.Stats.Speed or 50
	local PlayerLevel = PlayerCreature.Level or 5
	
	local attempts = 0
	if ActiveBattles[Player] and ActiveBattles[Player].EscapeAttempts then
		attempts = ActiveBattles[Player].EscapeAttempts
	else
		attempts = PlayerData.EscapeAttempts or 0
	end
	-- Modern-style escape formula (Gen 2+; used as the baseline for Gen 8–9-like behavior):
	-- escapeValue = floor((playerSpeed * 128) / enemySpeed) + 30 * attempts
	-- If escapeValue > 255 => guaranteed escape, else roll [0,255) < escapeValue.
	local enemySpeedSafe = math.max(1, EnemySpeed)
	local escapeValue = math.floor((PlayerSpeed * 128) / enemySpeedSafe) + (30 * attempts)
	if escapeValue > 255 then
		return true
	end
	local roll = math.random(0, 255)
	DBG:print("Escape calculation - PlayerSpeed:", PlayerSpeed, "EnemySpeed:", EnemySpeed, "Attempts:", attempts, "EscapeValue:", escapeValue, "Roll:", roll)
	return roll < escapeValue
end

--[[
	Clear battle data when battle ends
	@param Player The player
]]
function BattleSystem.ClearBattleData(Player: Player)
	if ActiveBattles[Player] then
		ActiveBattles[Player] = nil
		DBG:print("Cleared battle data for player:", Player.Name)
	end
	local pd = ClientData:Get(Player)
	if pd and pd.InBattle == true then
		pd.InBattle = false
		ClientData:UpdateClientData(Player, pd)
	end
end

--[[
	Handles creature switching during battle
	@param Player The player switching creatures
	@param newCreatureSlot The party slot index to switch to (1-6)
	@return boolean, string? Success status and optional error message
]]
function BattleSystem.SwitchCreature(Player: Player, newCreatureSlot: number): (boolean, string?)
	-- Security validation
	if not Player or not newCreatureSlot then
		return false, "Invalid parameters"
	end

	-- Prevent concurrent battle operations
	if not ActiveBattles[Player] then
		return false, "No active battle"
	end

	local battle = ActiveBattles[Player]

	-- Rate limiting: prevent rapid switching
	local now = tick()
	local lastSwitchTime = battle.LastSwitchTime or 0
	if now - lastSwitchTime < 0.5 then -- Minimum 0.5 seconds between switches
		return false, "Switch too fast"
	end
	battle.LastSwitchTime = now

	-- Get player data with timeout protection
	local playerData = ClientData:Get(Player)
	if not playerData or not playerData.Party then
		return false, "No party data"
	end

	-- Validate slot range
	if newCreatureSlot < 1 or newCreatureSlot > #playerData.Party then
		return false, "Invalid slot"
	end

	-- Get creature to switch to
	local newCreature = playerData.Party[newCreatureSlot]
	if not newCreature then
		return false, "Creature not found"
	end

	-- Check if creature is alive
	local hpPercent = newCreature.CurrentHP
	local hpLegacy = newCreature.Stats and newCreature.Stats.HP
	local isFainted = (hpLegacy ~= nil and hpLegacy <= 0) or (hpPercent ~= nil and hpPercent <= 0)

	if isFainted then
		return false, "Cannot switch to fainted creature"
	end

	-- Check if switching to same creature
	if battle.PlayerCreatureIndex == newCreatureSlot then
		return false, "Cannot switch to same creature"
	end

	-- Get the old creature name for "come back" message BEFORE updating
	local oldCreatureName = battle.PlayerCreature and (battle.PlayerCreature.Nickname or battle.PlayerCreature.Name) or "Creature"
	local newCreatureName = newCreature.Nickname or newCreature.Name
	
	-- Capture previous active slot/creature BEFORE changing index
	local prevIndex = battle.PlayerCreatureIndex
	local prevCreature = battle.PlayerCreature
	
	-- DEBUG: Show party HP values before switch
	DBG:print("=== PRE-SWITCH PARTY HP DEBUG ===")
	for i, partyCreature in ipairs(playerData.Party) do
		if partyCreature then
			local hpPercent = partyCreature.CurrentHP
			local hpAbs = partyCreature.Stats and partyCreature.Stats.HP
			DBG:print("Party slot", i, "- HP%:", hpPercent, "HP abs:", hpAbs, "Name:", partyCreature.Name or partyCreature.Nickname)
		end
	end
	DBG:print("Current battle.PlayerCreatureIndex:", battle.PlayerCreatureIndex)
	DBG:print("=== END PRE-SWITCH PARTY HP DEBUG ===")

	-- Determine if the CURRENT active creature has fainted -> forced switch
	-- Prefer checking the previously active battle creature, then its party slot.
	local isCurrentFainted = false
	if prevCreature then
		local hpPercentCur = prevCreature.CurrentHP
		local hpLegacyCur = prevCreature.Stats and prevCreature.Stats.HP
		DBG:print("Faint check - Previous battle creature HP%:", hpPercentCur, "HP abs:", hpLegacyCur)
		if (hpLegacyCur ~= nil and hpLegacyCur <= 0)
			or (hpPercentCur ~= nil and hpPercentCur <= 0) then
			isCurrentFainted = true
			DBG:print("Faint detected via previous battle creature")
		end
	end
	if (not isCurrentFainted) and prevIndex then
		local prevParty = playerData.Party[prevIndex]
		if prevParty then
			local hpPercentParty = prevParty.CurrentHP
			local hpLegacyParty = prevParty.Stats and prevParty.Stats.HP
			DBG:print("Faint check - Previous party slot", prevIndex, "HP%:", hpPercentParty, "HP abs:", hpLegacyParty)
			if (hpLegacyParty ~= nil and hpLegacyParty <= 0)
				or (hpPercentParty ~= nil and hpPercentParty <= 0) then
				isCurrentFainted = true
				DBG:print("Faint detected via previous party slot", prevIndex)
			end
		end
	end
	-- Last-resort fallback: if we lack previous pointers (e.g., server cleared on faint),
	-- treat this switch as forced if any party member has 0 HP and the selected slot is different.
	if (not isCurrentFainted) and (not prevCreature) and (not prevIndex) then
		for idx, c in ipairs(playerData.Party) do
			if idx ~= newCreatureSlot and c then
				local hpPercent = c.CurrentHP
				local hpLegacy = c.Stats and c.Stats.HP
				if (hpPercent ~= nil and hpPercent <= 0) or (hpPercent == nil and hpLegacy ~= nil and hpLegacy <= 0) then
					isCurrentFainted = true
					DBG:print("Faint inferred from party state; treating switch as forced")
					break
				end
			end
		end
	end

	-- Update the battle with new creature
	battle.PlayerCreatureIndex = newCreatureSlot
	
	-- SECURITY: Server determines if this is a forced switch based on faint
	battle.SwitchMode = isCurrentFainted and "Forced" or "Voluntary"
	DBG:print("Server determined switch mode:", battle.SwitchMode, "based on current creature fainted:", isCurrentFainted)
	
	-- IMPORTANT: map the active creature's party slot for HP/damage syncing
	-- After the switch completes, this should point to the NEW active slot
	battle.PlayerCreatureOriginalIndex = newCreatureSlot
	battle.PlayerCreatureOriginalData = newCreature
	-- Build a battle-scoped creature with correct Stats/MaxStats (mirror StartBattle)
	local newBattleCreature = table.clone(newCreature)
	local stats, maxStats = StatCalc.ComputeStats(newCreature.Name, newCreature.Level, newCreature.IVs, newCreature.Nature)
	-- CurrentHP stored as percent (0-100); default to 100 if nil
	local currentHPPercent = newCreature.CurrentHP
	local currentHPAbs
	if currentHPPercent == nil then
		currentHPPercent = 100
		currentHPAbs = maxStats.HP
		newBattleCreature.CurrentHP = currentHPPercent
	else
		currentHPPercent = math.clamp(currentHPPercent, 0, 100)
		currentHPAbs = math.floor(maxStats.HP * (currentHPPercent / 100) + 0.5)
	end
	newBattleCreature.Stats = stats
	newBattleCreature.Stats.HP = currentHPAbs
	newBattleCreature.MaxStats = maxStats
	-- Apply held item stat modifiers on switch-in
	HeldItemEffects.ApplyStatMods(newBattleCreature)
	-- Preserve pre-damage HP for UI send-out; enemy attack happens after
	local preDamageHPAbs = currentHPAbs
	-- Ensure learned moves for switched-in creature
	do
		local creatureData = CreaturesModule[newCreature.Name]
		if creatureData and creatureData.LearnableMoves then
			newBattleCreature.CurrentMoves = CreatureSystem.GetMovesForLevel(creatureData.LearnableMoves, newCreature.Level)
		end
	end
	-- Persist computed fields back to player party slot for consistency
	if playerData.Party and playerData.Party[newCreatureSlot] then
		playerData.Party[newCreatureSlot].MaxStats = maxStats
		playerData.Party[newCreatureSlot].Stats = playerData.Party[newCreatureSlot].Stats or {}
		playerData.Party[newCreatureSlot].Stats.HP = currentHPAbs
		playerData.Party[newCreatureSlot].CurrentHP = currentHPPercent
		-- Also persist CurrentMoves so the client has it if needed
		local creatureData = CreaturesModule[newCreature.Name]
		if creatureData and creatureData.LearnableMoves then
			playerData.Party[newCreatureSlot].CurrentMoves = CreatureSystem.GetMovesForLevel(creatureData.LearnableMoves, newCreature.Level)
		end
	end

	battle.PlayerCreature = newBattleCreature
	
	-- Validate creature data integrity
	if not newBattleCreature.Stats or not newBattleCreature.MaxStats then
		return false, "Failed to initialize creature stats"
	end

	DBG:print("Switch completed successfully for", Player.Name, "to", newCreatureName)
	
	-- DEBUG: Compare party HP before enemy action
	if playerData.Party then
		local logSlots = {}
		for idx, partyCreature in ipairs(playerData.Party) do
			local hp = partyCreature and partyCreature.Stats and partyCreature.Stats.HP or "nil"
			logSlots[#logSlots + 1] = string.format("[%d]=%s", idx, tostring(hp))
		end
		DBG:print("Party HP before enemy action:", table.concat(logSlots, ", "))
	end
	
	-- Random variant for "go" message (1-3)
	local goVariant = math.random(1, 3)

	DBG:print("--- SWITCH DEBUG ---")
	DBG:print("Selected slot:", newCreatureSlot)
	DBG:print("Previous player creature slot:", prevIndex or "nil")
	DBG:print("Old creature name:", oldCreatureName)
	DBG:print("New creature name:", newCreatureName)

	-- Apply entry hazard damage to the player's incoming creature
	local hazardSteps = {}
	local EntryHazards = require(game:GetService("ReplicatedStorage").Shared.EntryHazards)
	if battle.PlayerHazards then
		DBG:print("[HAZARD] Checking PlayerHazards for player switch-in:", battle.PlayerHazards)
		local hazardResults, updatedHazards = EntryHazards.ApplyOnSwitchIn(newBattleCreature, battle.PlayerHazards, true)
		
		-- Update hazards state (Toxic Spikes may have been absorbed)
		if updatedHazards then
			battle.PlayerHazards = updatedHazards
		end
		
		-- Collect hazard damage steps
		for _, hazardStep in ipairs(hazardResults) do
			table.insert(hazardSteps, hazardStep)
			DBG:print("[HAZARD] Added hazard step for player switch-in:", hazardStep.Type, hazardStep.HazardType)
		end
		
		-- Sync updated HP back to party data if hazard damage was dealt
		if #hazardSteps > 0 and newBattleCreature.Stats then
			if playerData.Party and playerData.Party[newCreatureSlot] then
				playerData.Party[newCreatureSlot].Stats = playerData.Party[newCreatureSlot].Stats or {}
				playerData.Party[newCreatureSlot].Stats.HP = newBattleCreature.Stats.HP
				local maxHP = newBattleCreature.MaxStats and newBattleCreature.MaxStats.HP or 1
				playerData.Party[newCreatureSlot].CurrentHP = math.clamp(math.floor((newBattleCreature.Stats.HP / math.max(1, maxHP)) * 100 + 0.5), 0, 100)
				DBG:print("[HAZARD] Updated player party HP after hazard damage:", newBattleCreature.Stats.HP)
			end
		end
	end

	-- Send turn result to client with structured data (no message strings)
	local turnResult
	if battle.SwitchMode == "Forced" then
		-- Forced switch: do NOT show "come back"; only send-out and skip enemy action
		local friendlySteps = {
			{ Type = "Switch", Action = "SendOut", Creature = newCreatureName, Variant = goVariant, IsPlayer = true }
		}
		-- Add hazard damage steps after the send-out
		for _, hazardStep in ipairs(hazardSteps) do
			table.insert(friendlySteps, hazardStep)
		end
		turnResult = {
			Friendly = friendlySteps,
			Enemy = {},
			PlayerCreatureIndex = newCreatureSlot,
			PlayerCreature = battle.PlayerCreature,
			HP = nil,
			SwitchMode = battle.SwitchMode,
		}
	else
		-- Voluntary switch: show recall then send-out
		local friendlySteps = {
			{ Type = "Switch", Action = "Recall", Creature = oldCreatureName, IsPlayer = true },
			{ Type = "Switch", Action = "SendOut", Creature = newCreatureName, Variant = goVariant, IsPlayer = true }
		}
		-- Add hazard damage steps after the send-out
		for _, hazardStep in ipairs(hazardSteps) do
			table.insert(friendlySteps, hazardStep)
		end
		turnResult = {
			Friendly = friendlySteps,
			Enemy = {},
			PlayerCreatureIndex = newCreatureSlot,
			PlayerCreature = battle.PlayerCreature,
			HP = nil,
			SwitchMode = battle.SwitchMode,
		}
	end
	
	-- POKEMON SWITCH PRIORITY SYSTEM:
	-- 1. For Wild encounters: Switch ALWAYS goes first, foe acts after (same as before)
	-- 2. For Trainer encounters: Check if enemy also chose to switch
	-- 3. If double-switch in trainer battle: Speed-based priority (slower goes first)
	
	local battleType = battle.Type or "Wild"
	
	-- Check if trainer also chose to switch (simulate trainer AI decision)
	local hasEnemySwitch = false
	if battleType == "Trainer" then
		-- For trainer battles, simulate whether the trainer also chose to switch
		-- This should ideally come from an AI decision, but simulate for now
		local trainerDecision = math.random(1, 100)
		-- Give trainer a 20% chance to switch (trainer switches less often than player)
		if trainerDecision <= 20 and battle.TrainerParty then
			-- Check if trainer has other usable creatures to switch to
			local hasAlternateCreature = false
			for i, trainerCreature in ipairs(battle.TrainerParty) do
				if trainerCreature and trainerCreature.Stats and trainerCreature.Stats.HP > 0 
					and i ~= battle.FoeCreatureIndex then
					hasAlternateCreature = true
					break
				end
			end
			
			if hasAlternateCreature then
				hasEnemySwitch = true
				DBG:print("TRAINER AI: Trainer chose to switch creatures")
			end
		end
	end
	
	-- TRAINER BATTLE DOUBLE-SWITCH LOGIC
	if battleType == "Trainer" and hasEnemySwitch then
		DBG:print("=== TRAINER DOUBLE-SWITCH DETECTED ===")
		DBG:print("Battle type:", battleType, "| Enemy plans to switch:", hasEnemySwitch)
		DBG:print("Player creature:", battle.PlayerCreature and battle.PlayerCreature.Name or "Unknown")
		DBG:print("Enemy creature:", battle.FoeCreature and battle.FoeCreature.Name or "Unknown")
		
		-- Both sides switching - determine speed-based priority like mainline Pokémon
		local playerSpeed = battle.PlayerCreature.Stats and battle.PlayerCreature.Stats.Speed or 0
		local enemySpeed = battle.FoeCreature.Stats and battle.FoeCreature.Stats.Speed or 0
		
		DBG:print("DOUBLE SWITCH: Player speed:", playerSpeed, "Enemy speed:", enemySpeed)
		
		-- Format for turnResult based on speed priority
		local playerFirst = false
		
		if playerSpeed < enemySpeed then
			-- Slower trainer switches first (your switch is slower, so it goes first)
			playerFirst = true
			DBG:print("DOUBLE SWITCH: Player (slower) switches first")
		elseif enemySpeed < playerSpeed then
			-- Enemy (slower) switches first  
			playerFirst = false
			DBG:print("DOUBLE SWITCH: Enemy (slower) switches first - player switch happens after")
		else
			-- Same speed - random decision (mainline Pokémon behavior)
			playerFirst = math.random(1, 2) == 1
			local whoFirst = playerFirst and "Player" or "Enemy"
			DBG:print("DOUBLE SWITCH: Same speed -", whoFirst, "switches first (random)")
		end
		
		-- Add trainer switch messages to turn result
		local enemySwitchMessages = {}
		if battle and battle.TrainerParty and battle.FoeCreatureIndex then
			local oldTrainerCreatureName = battle.FoeCreature and (battle.FoeCreature.Nickname or battle.FoeCreature.Name) or "Trainer Creature"
			
			for i = 1, #battle.TrainerParty do
				if battle.TrainerParty[i] and ((battle.TrainerParty[i].CurrentHP and battle.TrainerParty[i].CurrentHP > 0) or (battle.TrainerParty[i].Stats and battle.TrainerParty[i].Stats.HP > 0)) 
					and i ~= battle.FoeCreatureIndex then
					-- Found another trainer creature to switch to
					local trainerCreatureName = battle.TrainerParty[i].Nickname or battle.TrainerParty[i].Name
					enemySwitchMessages = {
						{ Type = "Switch", Message = oldTrainerCreatureName .. ", come back!" },
						{ Type = "Switch", Message = "Trainer sent out " .. trainerCreatureName .. "!" }
					}
					break
				end
			end
			
			-- Set the turnResult to show trainer switch messages
			turnResult.Enemy = enemySwitchMessages
			DBG:print("DOUBLE SWITCH: Trainer switch messages created for trainer side")
		end
	else
		-- STANDARD SWITCH BEHAVIOR (Wild or single-side switch in trainer)
		DBG:print("STANDARD SWITCH: Normal switch priority for", battleType)
	end
	
	-- Process foe action AFTER switch (only for VOLUNTARY switches and not double-switch trainer scenario)
	if battle.SwitchMode ~= "Forced" then
		-- Only apply foe action if not a trainer double-switch and not a preview switch reaction
		-- EXCEPTION: For trainer battles, allow foe action after preview switch so trainer sends out creature
		if (battleType ~= "Trainer" or not hasEnemySwitch) and (not battle.PreviewSwitchInProgress or battleType ~= "Trainer") then
			-- Normal switch behavior - foe gets a turn
			DBG:print("VOLUNTARY SWITCH: Enemy gets turn after switch to", battle.PlayerCreature.Name)
			
			-- REDUNDANT CHECK: Ensure the slot we're applying damage to is the ACTIVE creature's party slot:
			DBG:print("=== PRE DAMAGE SECTION CHECK ===")
			DBG:print("battle.PlayerCreatureIndex:", battle.PlayerCreatureIndex)
			DBG:print("battle.PlayerCreatureOriginalIndex:", battle.PlayerCreatureOriginalIndex)
			DBG:print("battle.PlayerCreature:", battle.PlayerCreature.Name)
			DBG:print("=== END PRE DAMAGE SECTION CHECK ===")

			-- Generate enemy action AFTER the switch is complete
			local enemyAction = BattleSystem.BuildEnemyAction(Player)
			local enemySteps = {}
			if enemyAction and enemyAction.Move then
				-- Enemy attacks the newly switched-in creature
				local enemyDamage = 8  
				local currentHP = battle.PlayerCreature.Stats and battle.PlayerCreature.Stats.HP or 0
				local newHP = math.max(0, currentHP - enemyDamage)
				
				enemyAction.HPDelta = { Player = -enemyDamage }
				battle.PlayerCreature.Stats = battle.PlayerCreature.Stats or {}
				battle.PlayerCreature.Stats.HP = newHP
				
				-- Always include the enemy move step first
				table.insert(enemySteps, enemyAction)
				-- Include explicit Damage step so client updates HP UI and plays impact effects
				-- IsPlayer indicates which creature was damaged (defender), not attacker
				table.insert(enemySteps, {
					Type = "Damage",
					IsPlayer = true, -- Player's creature is being damaged by enemy
					NewHP = newHP,
					Effectiveness = "Normal",
				})
				
				-- Check for faint after damage application
				if newHP <= 0 then
					DBG:print("=== PLAYER FAINT DETECTED IN SWITCH FUNCTION ===")
					DBG:print("Player creature:", battle.PlayerCreature.Name, "HP:", newHP)
					DBG:print("Creating faint step for player creature")
					DBG:print("=== END PLAYER FAINT DETECTION ===")
					
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
					
					-- Create a faint step for the player and append it AFTER the enemy move
					local faintStep = {
						Type = "Faint",
						Creature = battle.PlayerCreature.Name or "Your creature",
						IsPlayer = true,
					}
					table.insert(enemySteps, faintStep)
				else
					DBG:print("Enemy damage applied - HP reduced to:", newHP)
				end
				
				-- ENFORCED CORRESPONDENCE CHECK: Ensure active slot mapping is consistent
				if battle.PlayerCreatureIndex ~= battle.PlayerCreatureOriginalIndex then
					warn("INCONSISTENCY WARNING!", battle.PlayerCreatureIndex, "≠", battle.PlayerCreatureOriginalIndex)
				end
				
				-- IMMEDIATE UPDATE CONFIRMATION
				-- Ensure that the playerData for THE party slot contains damage being kicked by SERVER logic	
				if battle.PlayerCreatureIndex then
					local targetPartySlot = playerData.Party[battle.PlayerCreatureIndex]
					local targetSlotCreatureName = (targetPartySlot and (targetPartySlot.Nickname or targetPartySlot.Name)) or "nil"
					
					-- CAUTION ... URGENT CHECK: Tie validation to current active creature confirm MY TARGET ↔ correct slot...
					if battle.PlayerCreature.Name ~= targetSlotCreatureName and 
						battle.PlayerCreature.Nickname ~= targetSlotCreatureName and
						battle.PlayerCreature.Name then
						warn("MISMATCH", "battle.PlayerCreature.Name = "..tostring(battle.PlayerCreature.Name),
							"| slot["..battle.PlayerCreatureIndex.."] = "..tostring(targetSlotCreatureName))
					end
					
					if targetPartySlot and targetPartySlot.Stats then
						targetPartySlot.Stats.HP = newHP
						-- Keep compact percent in sync for client Party UI
						local maxHPForPercent = (battle.PlayerCreature and battle.PlayerCreature.MaxStats and battle.PlayerCreature.MaxStats.HP)
							or (targetPartySlot.MaxStats and targetPartySlot.MaxStats.HP)
							or (targetPartySlot.Stats and targetPartySlot.Stats.HP)
							or 1
						local percent = math.clamp(math.floor(((newHP / maxHPForPercent) * 100) + 0.5), 0, 100)
						targetPartySlot.CurrentHP = percent
						DBG:print("=== CRITICAL DAMAGE DOES IT GO TO THE RIGHT SPECIES? ===")
						DBG:print("battle.PlayerCreature.Name:", battle.PlayerCreature.Name or "nil")
						DBG:print("target slot[" .. battle.PlayerCreatureOriginalIndex .. "] Species>>", targetSlotCreatureName)  
						DBG:print("applied Damage: Enemy reduces HP to ", newHP)
						DBG:print("//")
						
						-- DISPLAY state immediately realize whom damage done applied.
						local damageArray = {}
						for dmgSlot, creatureObj in ipairs(playerData.Party) do
							if creatureObj and creatureObj.Stats then
								local formstatus = string.format("[%s]=H%d",
									creatureObj.Nickname or creatureObj.Name or ("nil"..dmgSlot),
									creatureObj.Stats.HP or -1)
								damageArray[#damageArray + 1] = formstatus
							end
						end
						DBG:print("PARTY → DAMAGE MAP:", table.concat(damageArray, " | "))
						DBG:print("PARTY → DAMAGE MAP done.")
						
						-- Update client data with new HP values
						if ClientData.UpdateClientData then
							ClientData:UpdateClientData(Player, playerData)
							DBG:print("Updated client data with new HP values after switch damage")
						end
					end
				end
				
				-- Send updated HP data for the switched creature
				local playerStats = battle.PlayerCreature.Stats or {}
				local playerMaxStats = battle.PlayerCreature.MaxStats or {}
				local foeStats = battle.FoeCreature.Stats or {}
				local foeMaxStats = battle.FoeCreature.MaxStats or {}
				
				-- Ensure PlayerMax is never nil on the client
				local playerMaxHP = (playerMaxStats and playerMaxStats.HP)
					or (playerStats and playerStats.HP)
					or 1
				local enemyMaxHP = (foeMaxStats and foeMaxStats.HP)
					or (foeStats and foeStats.HP)
					or 1
				
				turnResult.HP = {
					Player = playerStats.HP,
					PlayerMax = playerMaxHP,
					Enemy = foeStats.HP,
					EnemyMax = enemyMaxHP
				}

				-- Send PlayerCreature with pre-damage HP so client shows pre-attack value on send-out
				do
					local pre = table.clone(battle.PlayerCreature)
					pre.Stats = pre.Stats or {}
					pre.Stats.HP = preDamageHPAbs
					turnResult.PlayerCreature = pre
				end
			end
			-- Ensure enemy steps include the attack, and if applicable, a faint step immediately after
			turnResult.Enemy = enemySteps
		else
			-- Double-switch handled by priority system above
			DBG:print("DOUBLE SWITCH: Skipping foe action - switch handled by priority")
			turnResult.Enemy = {}
		end
	else
		-- FORCED SWITCH: No enemy turn, no damage applied
		DBG:print("FORCED SWITCH: Enemy skips turn entirely")
		turnResult.Enemy = {}
	end
	
	-- Damage already applied to party directly above, no need to overwrite here

	-- Advance TurnId for switch result as well
	ActiveBattles[Player].TurnId = (ActiveBattles[Player].TurnId or 0) + 1
	turnResult.TurnId = ActiveBattles[Player].TurnId
	Events.Communicate:FireClient(Player, "TurnResult", turnResult)
	
	DBG:print("Creature switch successful for", Player.Name, "to", newCreature.Name)
	-- Clear preview switch flag after sending turn result so subsequent turns proceed normally
	battle.PreviewSwitchInProgress = nil
	return true
end

return BattleSystem


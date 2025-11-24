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
end

-- Helper: get list of type names from a Type reference
local function GetTypeNames(typeRef: any): {string}
	local names: {string} = {}
	if type(typeRef) == "string" then
		table.insert(names, typeRef)
	elseif type(typeRef) == "table" then
		for _, t in ipairs(typeRef) do
			if type(t) == "string" then
				table.insert(names, t)
			elseif type(t) == "table" then
				for typeName, data in pairs(TypesModule) do
					if data == t then
						table.insert(names, typeName)
						break
					end
				end
			end
		end
	end
	return names
end

-- Helper: compute type effectiveness multiplier
local function ComputeTypeModifier(moveTypeName: string?, defenderTypeNames: {string}?): number
	if not moveTypeName or not defenderTypeNames then return 1 end
	local moveType = TypesModule[moveTypeName]
	if not moveType then return 1 end
	local modifier = 1
	for _, defName in ipairs(defenderTypeNames) do
		if table.find(moveType.immuneTo, defName) then
			modifier = modifier * 0
		elseif table.find(moveType.strongTo, defName) then
			modifier = modifier * 2
		elseif table.find(moveType.resist, defName) then
			modifier = modifier * 0.5
		end
	end
	return modifier
end

-- Helper: compute STAB (same-type attack bonus)
local function ComputeSTAB(moveTypeName: string?, attacker: any): number
	if not moveTypeName or not attacker then return 1 end
	local attackerTypes = {}
	if attacker.Type then
		attackerTypes = GetTypeNames(attacker.Type)
	elseif attacker.Name and CreaturesModule[attacker.Name] and CreaturesModule[attacker.Name].Type then
		attackerTypes = GetTypeNames(CreaturesModule[attacker.Name].Type)
	end
	for _, t in ipairs(attackerTypes) do
		if t == moveTypeName then return 1.5 end
	end
	return 1
end

-- Optimized damage calculation with caching
local function CalculateDamage(attacker: any, defender: any, moveNameOrData: any, isCrit: boolean): (number, any)
	if not attacker or not defender or not attacker.Stats or not defender.Stats then return 1, {} end

	local level = attacker.Level or 1
	local atk = attacker.Stats.Attack or 10
	local def = defender.Stats.Defense or 10

	-- Get move data (cached)
	local moveName: string?, moveData: any, moveTypeName: string?, power: number
	if type(moveNameOrData) == "string" then
		moveName = moveNameOrData
		moveData = MovesModule[moveName]
	elseif type(moveNameOrData) == "table" then
		moveName = moveNameOrData.Name
		moveData = (moveName and MovesModule[moveName]) or moveNameOrData
	end

	power = (moveData and moveData.BasePower) or 10

	-- Get move type (cached lookup)
	if moveData and moveData.Type then
		if type(moveData.Type) == "string" then
			moveTypeName = moveData.Type
		else
			for tname, tdata in pairs(TypesModule) do
				if tdata == moveData.Type then
					moveTypeName = tname
					break
				end
			end
		end
	end

	-- Base damage calculation (optimized)
	local levelFactor = math.floor((2 * level) / 5) + 2
	local attackRatio = atk / math.max(1, def)
	local baseDamage = math.floor((levelFactor * power * attackRatio) / 50) + 2

	-- Ability-based move type conversions
	moveTypeName = AbilitiesModule.ModifyMoveType(attacker, moveTypeName)

	-- Multipliers (computed once)
	local critMultiplier = isCrit and 1.5 or 1
	local stabMultiplier = ComputeSTAB(moveTypeName, attacker)
	local typeEffectiveness = ComputeTypeModifier(moveTypeName, GetTypeNames(defender.Type))
	-- Ability-based immunity overrides (e.g., Magic Eyes)
	typeEffectiveness = AbilitiesModule.OverrideImmunity(attacker, defender, moveTypeName, typeEffectiveness)
	-- Ability-based damage modifiers (attacker/defender)
	local abilityMultiplier = AbilitiesModule.DamageMultiplier(attacker, defender, moveTypeName, moveName)
	-- Held item damage modifiers
	local heldMultiplier = HeldItemEffects.DamageMultiplier(attacker, defender, moveTypeName)
	local randomMultiplier = math.random(85, 100) / 100

	-- Final damage calculation
	local totalMultiplier = critMultiplier * stabMultiplier * typeEffectiveness * randomMultiplier * abilityMultiplier * heldMultiplier
	local damage = 0
	if typeEffectiveness == 0 then
		damage = 0
	else
		damage = math.max(1, math.floor(baseDamage * totalMultiplier + 0.5) + 1)
	end

	-- Return damage and modifiers for client display
	return damage, {
		Crit = (critMultiplier > 1),
		STAB = (stabMultiplier > 1),
		Effectiveness = typeEffectiveness,
		BaseDamage = baseDamage,
		Multipliers = {
			Crit = critMultiplier,
			STAB = stabMultiplier,
			Type = typeEffectiveness,
			Random = randomMultiplier
		}
	}
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
	
	-- Trainer pending send-out handling at turn start
	if battle.Type == "Trainer" and battle.PendingTrainerSendOut and battle.NextFoeCreature then
		if battle.SendOutInline then
			battle.PendingTrainerSendOut = false
			battle.SendOutInline = nil
			battle.FoeCreature = battle.NextFoeCreature
			battle.FoeCreatureIndex = battle.NextFoeCreatureIndex
			battle.NextFoeCreature = nil
			battle.NextFoeCreatureIndex = nil
		else
			battle.PendingTrainerSendOut = false
			battle.FoeCreature = battle.NextFoeCreature
			battle.FoeCreatureIndex = battle.NextFoeCreatureIndex
			battle.NextFoeCreature = nil
			battle.NextFoeCreatureIndex = nil
			local foeName = battle.FoeCreature.Nickname or battle.FoeCreature.Name or "Foe"
			local friendlyActions = {}
			local enemyActions = {
				{ Type = "Switch", Action = "SendOut", Creature = foeName, IsPlayer = false }
			}
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
				if singleResult.IsPlayer ~= nil then
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
			if result.IsPlayer ~= nil then
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
					
					table.insert(enemyActions, {
						Type = "Switch",
						Action = "SendOut",
						Creature = (nextCreature.Nickname or nextCreature.Name),
						CreatureData = nextCreature,
						IsPlayer = false,
						TrainerName = battle.TrainerName,
					})
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
				DelaySeconds = 0.6, -- allow UI time to display message before HP tween
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
	
	-- Get move priorities
	local playerPriority = 0
	local enemyPriority = 0
	
	-- Item usage should act with high priority
	if playerAction.Type == "Item" then
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
	elseif enemyAction and enemyAction.Move then
		local Moves = require(game.ReplicatedStorage.Shared.Moves)
		local moveData = Moves[enemyAction.Move]
		if moveData then
			enemyPriority = (moveData.Priority or 0) + (AbilitiesModule.PriorityBonus(foeCreature, enemyAction.Move) or 0)
		end
	end
	
	-- Get speeds
	local playerSpeed = playerCreature.Stats.Speed or 0
	local enemySpeed = foeCreature.Stats.Speed or 0
	
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
			-- Same speed, random
			playerFirst = math.random(1, 2) == 1
			DBG:print("Same speed, random decision - Player first:", playerFirst)
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

--[[
	Execute a single action and return the result
	@param Player The player
	@param actionData The action data
	@param battle The battle state
	@return table|{table} Action result(s)
]]
function BattleSystem.ExecuteAction(Player: Player, actionData: any, battle: any): any
	local action = actionData.Action
	local isPlayer = actionData.IsPlayer
	
	if action.Type == "Move" then
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
	local attacker = isPlayer and battle.PlayerCreature or battle.FoeCreature
	local defender = isPlayer and battle.FoeCreature or battle.PlayerCreature
	local moveName = action.Move
	local Abilities = require(game:GetService("ReplicatedStorage").Shared.Abilities)
	local StatusModule = require(game:GetService("ReplicatedStorage").Shared.Status)
	
	-- Check if attacker can act (status conditions)
	local canAct, statusMessage = StatusModule.CanAct(attacker)
	if not canAct then
		local steps = {
			{ Type = "Move", Move = moveName, Actor = attacker.Name or (isPlayer and "Your creature" or "Foe"), IsPlayer = isPlayer },
			{ Type = "Message", Message = statusMessage or "The creature can't move!", IsPlayer = isPlayer }
		}
		return steps
	end
	
	-- Check volatile status conditions (Flinch, Confusion, Infatuation)
	local canActVolatile, volatileMessage, selfDamage = StatusModule.CanActVolatile(attacker)
	if not canActVolatile then
		local steps = {}
		-- For Flinch, don't show the move name - just show the flinch message
		if volatileMessage and string.find(volatileMessage, "flinched", 1, true) then
			-- Flinch: just show the flinch message
			table.insert(steps, { Type = "Message", Message = volatileMessage, IsPlayer = isPlayer })
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
		return {
			{ Type = "Move", Move = moveName, Actor = attacker.Name or "You", IsPlayer = isPlayer },
			{ Type = "Heal", Amount = healed, IsPlayer = isPlayer, Message = string.format("%s perched and recovered HP!", attacker.Nickname or attacker.Name) }
		}
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
		return {
			{ Type = "Miss", Message = missMessage, Move = moveName, Actor = attacker.Name or (isPlayer and "Your creature" or "Foe"), IsPlayer = isPlayer }
		}
	end

	-- Calculate damage
	local isCrit = (math.random(1, 16) == 1)
	
	local effectiveMoveData = moveDef
	if modifiedType ~= moveDef.Type then
		effectiveMoveData = table.clone(moveDef)
		effectiveMoveData.Type = modifiedType
	end

	local damage, mods = CalculateDamage(attacker, defender, effectiveMoveData, isCrit)
	-- Global damage tuning: soften incoming damage to the player
	if not isPlayer then
		damage = math.max(1, math.floor(damage * 0.7))
	end
	
	local effCat = "Normal"
	local effNum = (mods and type(mods.Effectiveness) == "number") and mods.Effectiveness or 1
	if effNum == 0 then
		effCat = "Immune"
	elseif effNum >= 2 then
		effCat = "Super"
	elseif effNum <= 0.5 then
		effCat = "NotVery"
	end
	
	-- Apply damage
	local before = defender.Stats.HP or 0
	local after = math.max(0, before - damage)
	
	-- Focus Bandage check
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
	DBG:print("[DAMAGE]", (attacker.Nickname or attacker.Name or (isPlayer and "Player" or "Enemy")), "used", moveName, "on", (defender.Nickname or defender.Name or (isPlayer and "Enemy" or "Player")), "dmg:", damage, "HP:", before, "->", after)
	
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

	local actorName = attacker.Name or (isPlayer and "Your creature" or "Foe")
	
	local result = {
		Type = "Move",
		Move = moveName,
		Actor = actorName,
		HPDelta = isPlayer and {Enemy = -damage} or {Player = -damage},
		Critical = isCrit,
		Effectiveness = effCat,
	}
	
	local damageStep = {
		Type = "Damage",
		Effectiveness = effCat,
		IsPlayer = isPlayer,
		NewHP = defender.Stats and defender.Stats.HP or nil,
	}

	local steps = {result, damageStep}
	
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
	
	-- Apply flinch if move causes flinch (apply when move hits, regardless of damage amount)
	-- Flinch should apply whenever the move successfully hits the target
	if moveDef and moveDef.CausesFlinch and hit then
		StatusModule.ApplyVolatile(defender, "Flinch")
		DBG:print("[FLINCH] Applied flinch to", defender.Nickname or defender.Name, "from move", moveName)
	end
	
	-- Apply confusion if move causes confusion (only if move hit and dealt damage)
	if moveDef and moveDef.CausesConfusion and damage > 0 then
		StatusModule.ApplyVolatile(defender, "Confusion", math.random(1, 4))
	end
	
	-- Check for faint AFTER applying effects (flinch should still apply even if target faints)
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
		
		table.insert(steps, faintStep)
	end
	
	return steps
end

--[[
	Execute a switch action (placeholder)
	@param Player The player
	@param action The switch action
	@param battle The battle state
	@param isPlayer Whether this is the player's switch
	@return table Action result
]]
function BattleSystem.ExecuteSwitchAction(Player: Player, action: any, battle: any, isPlayer: boolean): any
	return {Type = "Message", Message = "Switch action not yet implemented"}
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

	local learnedMoves = battle.FoeCreature.CurrentMoves
	local selectedMove = "Tackle"

	if type(learnedMoves) == "table" and #learnedMoves > 0 then
		local randomIndex = math.random(1, #learnedMoves)
		local moveEntry = learnedMoves[randomIndex]

		if type(moveEntry) == "string" then
			selectedMove = moveEntry
		elseif type(moveEntry) == "table" and moveEntry.Name then
			selectedMove = moveEntry.Name
		elseif type(moveEntry) == "table" and moveEntry.Move then
			selectedMove = moveEntry.Move
		end
	end

	if not selectedMove or selectedMove == "" then
		selectedMove = "Tackle"
	end

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

	local decision = 1

	if decision <= 100 then
		local learnedMoves = battle.FoeCreature.CurrentMoves
		local selectedMove = "Tackle"

		if type(learnedMoves) == "table" and #learnedMoves > 0 then
			local randomIndex = math.random(1, #learnedMoves)
			local moveEntry = learnedMoves[randomIndex]

			if type(moveEntry) == "string" then
				selectedMove = moveEntry
			elseif type(moveEntry) == "table" and moveEntry.Name then
				selectedMove = moveEntry.Name
			elseif type(moveEntry) == "table" and moveEntry.Move then
				selectedMove = moveEntry.Move
			end
		end

		if not selectedMove or selectedMove == "" then
			selectedMove = "Tackle"
		end

		local foeName = battle.FoeCreature.Name or "Trainer's creature"
		local actorName = "Trainer's " .. foeName

		return {
			Type = "Move",
			Move = selectedMove,
			Actor = actorName
		}
	else
		local item = "Potion"
		local message = "Trainer used " .. item .. "!"

		return {
			Type = "Item",
			Item = item,
			Message = message
		}
	end
end

--[[
	Calculate escape chance using Pokemon formula
	@param Player The player
	@param PlayerData The player data
	@return boolean Whether escape succeeds
]]
function BattleSystem.CalculateEscapeChance(Player: Player, PlayerData: any): boolean
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
	local chance = (PlayerSpeed * 32) / (EnemySpeed / 4 % 256) + 30 * attempts
	
	local LevelDifference = PlayerLevel - EnemyLevel
	local LevelModifier = 1 + (LevelDifference * 0.1)
	chance = chance * LevelModifier
	
	chance = chance * 1.6
	
	if chance > 255 then
		return true
	end
	
	local roll = math.random(0, 255)
	DBG:print("Escape calculation - PlayerSpeed:", PlayerSpeed, "EnemySpeed:", EnemySpeed, "LevelDiff:", LevelDifference, "Attempts:", attempts, "Chance:", chance, "Roll:", roll)
	return roll < chance
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

return BattleSystem


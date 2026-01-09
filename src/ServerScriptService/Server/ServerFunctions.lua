local ServerFunctions = {}

--// Services
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")

--// Packages / Modules
local WebhookService = require(ServerScriptService.Packages.WebhookService)
local DBG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DBG"))
local ClientData = require(script.Parent.ClientData)
local GameData = require(script.Parent:WaitForChild("GameData"))
local ChunkService = require(script.Parent:WaitForChild("ChunkService"))
local GameConfig = require(script.Parent.GameData.Config)
local TypesModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local MovesModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Moves"))
local AbilitiesModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Abilities"))
local CreaturesModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Creatures"))
local MoveCompatibility = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MoveCompatibility"))
local StatCalc = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StatCalc"))
local StatStages = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StatStages"))
local Natures = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Natures"))
local CreatureFactory = require(script.Parent:WaitForChild("CreatureFactory"))
local DayNightCycle = require(ServerStorage:WaitForChild("Server"):WaitForChild("DayNightCycle"))
local CatchCareShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CatchCareShopConfig"))

type ShopItem = CatchCareShopConfig.ShopItem

--// Battle System Modules (Refactored)
local Battle = require(script.Parent.Battle)
local BattleStateManager = Battle.StateManager
local BattleValidator = Battle.Validator
local DamageCalculator = Battle.DamageCalculator
local CreatureFactory = require(script.Parent.CreatureFactory)
local AIController = Battle.AIController
local XPManager = Battle.XPManager
local HeldItemEffects = require(script.Parent:WaitForChild("Battle"):WaitForChild("HeldItemEffects"))
local XPAwarder = require(script.Parent:WaitForChild("Battle"):WaitForChild("XPAwarder"))
local ObedienceModule = Battle.Obedience
local StarterService = require(script.Parent:WaitForChild("StarterService"))
local CreatureSpawnService = require(script.Parent:WaitForChild("CreatureSpawnService"))

--// Refactored System Modules
local BattleSystem = require(script.Parent.BattleSystem)
local ItemSystem = require(script.Parent.ItemSystem)
local CreatureSystem = require(script.Parent.CreatureSystem)
local WorldSystem = require(script.Parent.WorldSystem)
local CodeRedemption = require(script.Parent.CodeRedemption)
local ChallengesSystem = require(script.Parent.ChallengesSystem)
local ServerFunctionsModules = script.Parent:WaitForChild("ServerFunctionsModules")
local PlayerProfileModule = require(ServerFunctionsModules:WaitForChild("PlayerProfile"))
local BattleRequestsModule = require(ServerFunctionsModules:WaitForChild("BattleRequests"))
local TradeModule = require(ServerFunctionsModules:WaitForChild("Trade"))
local DayNightApiModule = require(ServerFunctionsModules:WaitForChild("DayNightApi"))
local WeatherApiModule = require(ServerFunctionsModules:WaitForChild("WeatherApi"))
local ProcessTurnModule = require(ServerFunctionsModules:WaitForChild("ProcessTurn"))
local WeatherService = require(script.Parent:WaitForChild("WeatherService"))
local AdminService = require(script.Parent:WaitForChild("AdminService"))
local MysteryTradeService = require(script.Parent:WaitForChild("MysteryTradeService"))

-- Unstuck cooldowns
local _unstuckCooldown: {[Player]: number} = {}

-- Track spawned creature models per player (managed by CreatureSpawnService)
ServerFunctions._spawnedCreatureModels = CreatureSpawnService.GetSpawnedCreatureModels()

--// Instances
local Events = ReplicatedStorage:WaitForChild("Events")

-- Repel step constants (editable for balancing)
local REPEL_STEPS = {
	["Focus Spray"] = 100,
	["Super Focus Spray"] = 200,
	["Max Focus Spray"] = 250,
}

-- Store active battles for escape calculations and battle state management
-- Note: ActiveBattles is now managed by BattleStateManager, but kept for backward compatibility
local ActiveBattles = {}

-- Initialize refactored system modules with dependencies
do
	local dependencies = {
		ActiveBattles = ActiveBattles,
		ClientData = ClientData,
		Events = Events,
		DBG = DBG,
		MovesModule = MovesModule,
		AbilitiesModule = AbilitiesModule,
		CreaturesModule = CreaturesModule,
		StatCalc = StatCalc,
		Natures = Natures,
		CreatureFactory = CreatureFactory,
		TypesModule = TypesModule,
		DamageCalculator = DamageCalculator,
		HeldItemEffects = HeldItemEffects,
		XPManager = XPManager,
		XPAwarder = XPAwarder,
		ObedienceModule = ObedienceModule,
		GameData = GameData,
		GameConfig = GameConfig,
		ChunkService = ChunkService,
		CatchCareShopConfig = CatchCareShopConfig,
		ReplicatedStorage = ReplicatedStorage,
	}
	
	-- Initialize CreatureSystem first so it can be passed to BattleSystem
	CreatureSystem.Initialize(dependencies)
	dependencies.CreatureSystem = CreatureSystem
	
	BattleSystem.Initialize(dependencies)
	ItemSystem.Initialize(dependencies)
	WorldSystem.Initialize(dependencies)
	
	-- Initialize CodeRedemption with ServerFunctions reference
	dependencies.ServerFunctions = ServerFunctions
	CodeRedemption.Initialize(dependencies)
	
	-- Initialize ChallengesSystem
	ChallengesSystem.Initialize(dependencies)
	
	-- Set ChallengesSystem on CreatureSystem (after both are initialized)
	CreatureSystem.SetChallengesSystem(ChallengesSystem)
	
	-- Initialize AdminService
	AdminService.Initialize({
		Config = GameConfig,
		DBG = DBG,
		Players = Players,
		DataStoreService = game:GetService("DataStoreService"),
	})
end

-- Event-based save helper
local function _saveNow(player: Player)
    local ok, _ = pcall(function()
        local PlayerDataModule = require(game:GetService("ServerScriptService").Server.ClientData.PlayerData)
        if PlayerDataModule and PlayerDataModule.ManualSave then
            PlayerDataModule.ManualSave(player)
        end
    end)
    return ok == true
end

-- Manual save rate limiting (per-player)
local _lastManualSaveAt: {[Player]: number} = {}
local MANUAL_SAVE_MIN_INTERVAL = 15 -- seconds

-- Server-side request guard state for remotes
local _requestState: {[Player]: {lastTime: number, tokens: number}} = {}
local _pendingBattleRequests: {[string]: {From: Player, Target: Player, LevelMode: string}} = {}
local _pendingTradeRequests: {[string]: {From: Player, Target: Player}} = {}
local _activeTradeSessions = {}
local _pvpTurnBuffer: {[string]: {TurnId: number, Actions: {[string]: any}}} = {}
-- Per-key lock to ensure a turn resolves exactly once server-authoritatively
local _pvpResolving: {[string]: number} = {}
local PvPTurnResolver = require(script.Parent.Battle.PvPTurnResolver)

local sharedDeps = {
	ClientData = ClientData,
	WorldSystem = WorldSystem,
	StarterService = StarterService,
	ChunkService = ChunkService,
	ItemSystem = ItemSystem,
	CreatureSpawnService = CreatureSpawnService,
	DBG = DBG,
	saveNow = _saveNow,
	Players = Players,
	HttpService = HttpService,
	Events = Events,
	ActiveBattles = ActiveBattles,
	PendingBattleRequests = _pendingBattleRequests,
	PendingTradeRequests = _pendingTradeRequests,
	ActiveTradeSessions = _activeTradeSessions,
	DayNightCycle = DayNightCycle,
	WeatherService = WeatherService,
}

PlayerProfileModule.apply(ServerFunctions, sharedDeps)
TradeModule.apply(ServerFunctions, sharedDeps)
BattleRequestsModule.apply(ServerFunctions, sharedDeps)
local _restorePendingBattleSnapshot = sharedDeps.RestorePendingBattleSnapshot
DayNightApiModule.apply(ServerFunctions, sharedDeps)
WeatherApiModule.apply(ServerFunctions, sharedDeps)

-- Debug helper: log any Message steps in a TurnResult
local function _logBattleMessages(label: string, turnResult: any)
	if not DBG then
		return
	end
	local function logList(name: string, list: any)
		if type(list) ~= "table" then
			return
		end
		for idx, step in ipairs(list) do
			if type(step) == "table" and step.Type == "Message" then
				DBG:print(string.format("[BattleMessage][%s][%s][%d] %s", label, name, idx, tostring(step.Message)))
			end
		end
	end
	logList("Friendly", turnResult and turnResult.Friendly)
	logList("Enemy", turnResult and turnResult.Enemy)
end

local function _pvpKey(p1: Player, p2: Player): string
	local a = math.min(p1.UserId, p2.UserId)
	local b = math.max(p1.UserId, p2.UserId)
	return tostring(a) .. "_" .. tostring(b)
end
local _ALLOWED_VERBS = {
    ExecuteMove = true,
    SwitchCreature = true,
    AttemptEscape = true,
    AttemptRun = true,
    ReorderParty = true,
    DataGet = true,
    RequestChunk = true,
    FilterName = true,
    UpdateNickname = true,
    SetEvent = true,
    RequestStarters = true,
    PickStarter = true,
    GetEncounterData = true,
    TryEncounterStep = true,
    HealParty = true,
    EndBattle = true,
    ManualSave = true,
    UseItem = true,
    NewGame = true,
    FinalizeCapture = true,
	UpdateSettings = true,
	SaveItemPickup =  true,
    UpdateLastChunk = true,
    ClearLeaveDataCFrame = true,
    GetPickedUpItems = true,
    StartBattle = true,
    GrantItem = true,
    GetCurrentTimePeriod = true,
    MoveReplaceDecision = true,
    SetCutsceneActive = true,
    SetSayActive = true,
    UpdateVaultBoxes = true,
    TakeHeldItem = true,
    DesyncCreature = true,
    ProcessDeferredTrainerSendOut = true,
    RenameBox = true,
    DesyncBox = true,
    SetBoxBackground = true,
    SetBlackoutReturnChunk = true,
    GiveItem = true,
    GetUnstuck = true,
    PurchaseCatchCareItem = true,
    RedeemCode = true,
    ToggleCreatureSpawn = true,
    UpdateCreatureAnimation = true,
    RepelStepsDepleted = true,
    UpdateRepelSteps = true,
    BattleRequest = true,
    BattleRequestReply = true,
    TradeRequest = true,
    TradeRequestReply = true,
    TradeSendMessage = true,
    GetChallenges = true,
    ClaimChallengeReward = true,
    TradeFetchBox = true,
    TradeSetReady = true,
    TradeConfirm = true,
    TradeCancel = true,
    TradeUpdateOffer = true,
    ViewPlayerInfo = true,
    GetChunkWeather = true,
    MLMoveReplaceDecision = true,
	OpenVault = true,
	MysteryTradeStart = true,
	MysteryTradeCancel = true,
	MysteryTradeSelectCreature = true,
	MysteryTradeConfirm = true,
	-- Admin verbs
	AdminAction = true,
	GetBannedPlayers = true,
	ViewPlayerData = true,
	CheckAdminPermission = true,
}

local function _rateLimitOk(player: Player): boolean
    local now = os.clock()
    local s = _requestState[player]
    if not s then
        _requestState[player] = { lastTime = now, tokens = 5 }
        return true
    end
    local elapsed = now - s.lastTime
    s.lastTime = now
    -- token bucket: refill 5 tokens/sec up to 10
    s.tokens = math.min(10, s.tokens + elapsed * 5)
    if s.tokens < 1 then
        return false
    end
    s.tokens -= 1
    return true
end

--[[
	Awards XP for defeating multiple creatures, returns steps for client to display
	Accumulates XP from all defeated creatures before awarding
	@param Player The player who won
	@param defeatedCreatures Array of defeated creatures
	@param battle The active battle data
	@return xpSteps Array of XP/LevelUp steps
]]
function ServerFunctions:AwardBattleXPForAll(Player: Player, defeatedCreatures: {any}, battle: any): {any}
	return XPAwarder.AwardBattleXPForAll(Player, defeatedCreatures, battle)
end

--[[
	Awards XP for defeating a single creature (LEGACY - kept for compatibility)
	@param Player The player who won
	@param defeatedCreature The fainted creature
	@param battle The active battle data
	@return xpSteps Array of XP/LevelUp steps
]]
--[[
	Counts the number of non-fainted Pokémon in the party
	@param party The player's party array
	@return number Count of non-fainted Pokémon
]]
local function countNonFaintedPartyMembers(party: {any}): number
	local count = 0
	for _, creature in ipairs(party) do
		local hp = creature.Stats and creature.Stats.HP
		if type(hp) == "number" and hp > 0 then
			count = count + 1
		end
	end
	return count
end

function ServerFunctions:AwardBattleXP(Player: Player, defeatedCreature: any, battle: any): {any}
    local xpSteps = {}
    
    if not defeatedCreature or not battle then 
        return xpSteps
    end
    
    local PlayerData = ClientData:Get(Player)
    if not PlayerData or not PlayerData.Party then 
        return xpSteps
    end
    
    -- Determine if this is a trainer battle
    local isTrainerBattle = battle.Type == "Trainer"
    
    -- Find the active creature
    local activeCreature = battle.PlayerCreature
    if not activeCreature or not activeCreature.Stats or activeCreature.Stats.HP <= 0 then
        return xpSteps
    end
    
    local xpSpreadEnabled = PlayerData.Settings and PlayerData.Settings.XPSpread or false
    
    -- Determine participant count based on EXP Share setting
    local participantCount = 1
    if xpSpreadEnabled then
        participantCount = countNonFaintedPartyMembers(PlayerData.Party)
    end
    
    -- Calculate XP using correct participant count
    local xpAmount = XPManager.CalculateXPYield(
        defeatedCreature,
        activeCreature,
        isTrainerBattle,
        participantCount,
        false
    )
    
    -- Apply EXP Share+ bonus (+30%) if EXP Share is enabled and player owns the gamepass
    if xpSpreadEnabled then
        local EXPSHAREPLUS_GAMEPASS_ID = 1656774306
        local success, ownsGamepass = pcall(function()
            return MarketplaceService:UserOwnsGamePassAsync(Player.UserId, EXPSHAREPLUS_GAMEPASS_ID)
        end)
        if success and ownsGamepass then
            xpAmount = math.floor(xpAmount * 1.3)
        end
    end
    
    -- Track level changes for challenge progress
    local levelChanges = {}
    
    -- Award XP to all eligible Pokémon
    if xpAmount > 0 then
        local activeSlotIndex = battle.PlayerCreatureIndex
        -- Award XP to all non-fainted Pokémon (including battler when EXP Share is on)
        for si, creature in ipairs(PlayerData.Party) do
            local hp = creature.Stats and creature.Stats.HP
            if type(hp) == "number" and hp > 0 then
                -- When EXP Share is off, only award to the active creature (by slot index)
                if not xpSpreadEnabled and si ~= activeSlotIndex then
                    -- Skip non-active creatures when EXP Share is off
                else
                    local prevLevel = creature.Level
                    local levelsGained = XPManager.AwardXP(creature, xpAmount)
                    local creatureName = creature.Nickname or creature.Name
                    local newLevel = creature.Level
                    
                    -- Track level change for challenge progress
                    if levelsGained and levelsGained > 0 then
                        table.insert(levelChanges, { PreviousLevel = prevLevel, NewLevel = newLevel })
                    end
                    
                    -- Add XP gain step
                    table.insert(xpSteps, {
                        Type = "XP",
                        Creature = creatureName,
                        Amount = xpAmount,
                        IsShared = xpSpreadEnabled and creature ~= activeCreature,
                        IsPlayer = true,
                        XPProgress = creature.XPProgress or 0,
                        CurrentLevel = creature.Level,
                    })
                    
                    DBG:print("[XP]", creatureName, "gained", xpAmount, "XP")
                    
                    -- Add level up steps
                    if levelsGained and levelsGained > 0 then
                        local startLevel = creature.Level - levelsGained
                        for i = 1, levelsGained do
                            local xpProgress = (i == levelsGained) and (creature.XPProgress or 0) or nil
                            table.insert(xpSteps, {
                                Type = "LevelUp",
                                Creature = creatureName,
                                Level = startLevel + i,
                                IsPlayer = true,
                                XPProgress = xpProgress,
                            })
                            DBG:print("[XP]", creatureName, "reached level", startLevel + i)
                        end
                    end
                    
                    -- Learned moves from XP award
                    if type(creature._MovesLearnedRecently) == "table" then
                        local cur = creature.CurrentMoves or {}
                        local function hasMove(mv: string): boolean
                            for _, m in ipairs(cur) do
                                if m == mv then return true end
                            end
                            return false
                        end
                        for _, moveName in ipairs(creature._MovesLearnedRecently) do
                            if hasMove(moveName) or #cur < 4 then
                                table.insert(xpSteps, { Type = "MoveLearned", Creature = creatureName, Move = moveName, IsPlayer = true })
                            else
                                table.insert(xpSteps, {
                                    Type = "MoveReplacePrompt",
                                    Creature = creatureName,
                                    Move = moveName,
                                    CurrentMoves = table.clone(cur),
                                    SlotIndex = si,
                                    IsPlayer = true,
                                })
                            end
                        end
                    end
                end -- end else block
            end
        end
        
        -- Add XPSpread message if EXP Share is enabled and multiple Pokémon received XP
        if xpSpreadEnabled and participantCount > 1 then
            table.insert(xpSteps, {
                Type = "XPSpread",
                IsPlayer = true,
            })
        end
    end
    
    -- Force update client data
    if #xpSteps > 0 then
        ClientData:UpdateClientData(Player, PlayerData)
    end
    
    return xpSteps
end



-- Provide reference to active battles map for other modules
function ServerFunctions:GetActiveBattles()
    return ActiveBattles
end

-- Gracefully end a battle and notify the client
-- Gracefully end a battle and notify the client
function ServerFunctions:EndBattle(Player: Player, reason: string?)
	local battle = ActiveBattles[Player]
	if not battle then
		return
	end

	-- PvP: roll back all party HP/status to the pre-battle snapshot so players
	-- don't gain/lose HP or levels, and prevent blackout messaging due to 0 HP.
	if battle.Type == "PvP" and _restorePendingBattleSnapshot then
		_restorePendingBattleSnapshot(Player)
		local pd = ClientData:Get(Player)
		if pd then
			pd.InBattle = false
			ClientData:UpdateClientData(Player, pd)
		end
	end
	
	-- Clean up PvP turn buffer and resolving lock if this is a PvP battle
	if battle.Type == "PvP" and battle.OpponentPlayer then
		local opponent = battle.OpponentPlayer
		local key = _pvpKey(Player, opponent)
		if key then
			_pvpTurnBuffer[key] = nil
			_pvpResolving[key] = nil
			DBG:print("[PvP] Cleaned up turn buffer for battle:", key)
		end
	end
	
	local Events = game.ReplicatedStorage.Events
	if Events and Events.Communicate then
		Events.Communicate:FireClient(Player, "BattleOver", {
			Reason = reason or "Win",
			Rewards = {
				XP = 0,
				Studs = 0,
			}
		})
	end
	ServerFunctions:ClearBattleData(Player)
	
	-- Check and despawn any fainted creatures after battle ends
	pcall(function()
		CreatureSpawnService.CheckAndDespawnFaintedCreatures(Player)
	end)
end

-- ActiveBattles moved to top of file for global access

function ServerFunctions:AttemptEscape(Player)
	local PlayerData = ClientData:Get(Player)
	
	if not PlayerData then
		DBG:warn("No player data found for escape attempt")
		return false, "No player data"
	end

    local battle = ActiveBattles[Player]
    if battle and battle.Type == "PvP" then
        battle.PlayerAction = { Type = "Run", Actor = Player.DisplayName }
        return ServerFunctions:ProcessTurn(Player)
    end
	
	DBG:print("Player", Player.Name, "attempted to escape")
	
    -- Calculate escape chance server-side
    local canEscape = ServerFunctions:CalculateEscapeChance(Player, PlayerData)
    -- Run Away ability ensures escape in wild battles
    do
        local battle = ActiveBattles[Player]
        if battle and battle.Type == "Wild" then
            local pc = battle.PlayerCreature
            local Abilities = require(game:GetService("ReplicatedStorage").Shared.Abilities)
            if pc and Abilities.GuaranteesEscape(pc) then
                canEscape = true
                DBG:print("[Abilities] Run Away triggered: forced escape success")
            end
            
            -- Check for trapping abilities on foe (Elastic Trap)
            local foe = battle.FoeCreature
            if foe and Abilities.TrapsOpponent(foe) then
                -- Exception: Ghost types or Run Away users are immune to trapping (standard logic)
                -- Since Run Away is checked above, we can prioritize that.
                -- If Run Away is present, canEscape is true.
                -- If not, and foe has Elastic Trap, block escape.
                if not canEscape then -- i.e. Run Away didn't force it
                     -- Check if player is Ghost type (immune to trapping)
                     -- If not, block escape
                     -- canEscape = false
                     -- For now, just block if not already escaping
                     -- But wait, CalculateEscapeChance might have returned true.
                     -- If trapped, force false unless Run Away (which overrides trap in some Gens, or not? Run Away usually guarantees escape except from Block/Mean Look? No, Run Away guarantees escape from wild battle ALWAYS).
                     -- So if Run Away triggered, we are good.
                     -- If not, check trap.
                     if Abilities.TrapsOpponent(foe) then
                         -- Check for ghost type immunity
                         local isGhost = false
                         if pc.Type then
                             for _, t in ipairs(pc.Type) do if t == "Ghost" then isGhost = true break end end
                         end
                         if not isGhost then
                             canEscape = false
                             DBG:print("[Abilities] Foe's trapping ability prevented escape")
                         end
                     end
                end
            end
        end
    end
	
    if canEscape then
        -- Send escape success to client
        Events.Communicate:FireClient(Player, "EscapeSuccess")
        DBG:print("Player", Player.Name, "successfully escaped")
        
        -- Clear battle data on successful escape
        ServerFunctions:ClearBattleData(Player)
    else
        DBG:print("Player", Player.Name, "failed to escape - bundling response")

        -- Increment escape attempts for this active battle to make next attempt easier
        if ActiveBattles[Player] then
            ActiveBattles[Player].EscapeAttempts = (ActiveBattles[Player].EscapeAttempts or 0) + 1
            DBG:print("Escape attempts for player", Player.Name, "now", ActiveBattles[Player].EscapeAttempts)
        end

        -- Build enemy action and apply simple damage to player if it's a move
        local enemyAction = ServerFunctions:BuildEnemyAction(Player)
        local damageStep = nil
        if enemyAction and enemyAction.Move and ActiveBattles[Player] and ActiveBattles[Player].PlayerCreature and ActiveBattles[Player].PlayerCreature.Stats then
            local enemyDamage = 8
            local battle = ActiveBattles[Player]
            local currentHP = battle.PlayerCreature.Stats.HP or 0
            local newHP = math.max(0, currentHP - enemyDamage)
            battle.PlayerCreature.Stats.HP = newHP
            enemyAction.HPDelta = { Player = -enemyDamage }
            -- Include an explicit Damage step so the client applies damage at the correct time
            -- IsPlayer indicates which creature was damaged (defender), not attacker
            damageStep = { Type = "Damage", Effectiveness = "Normal", IsPlayer = true, NewHP = newHP }

            -- Mirror damage to persistent party data (Stats.HP and CurrentHP percent)
            local PlayerData = ClientData:Get(Player)
            if PlayerData and PlayerData.Party and battle.PlayerCreatureIndex then
                local slot = PlayerData.Party[battle.PlayerCreatureIndex]
                if slot then
                    slot.Stats = slot.Stats or {}
                    slot.Stats.HP = newHP
                    local maxHP = (battle.PlayerCreature.MaxStats and battle.PlayerCreature.MaxStats.HP) or slot.MaxStats and slot.MaxStats.HP
                    if maxHP and maxHP > 0 then
                        slot.CurrentHP = math.clamp(math.floor((newHP / maxHP) * 100 + 0.5), 0, 100)
                    end
                end
                if ClientData.UpdateClientData then
                    ClientData:UpdateClientData(Player, PlayerData)
                end
            end
        end

        -- Send bundled turn result with authoritative HP snapshot
        -- Advance TurnId
        local b = ActiveBattles[Player]
        if b then b.TurnId = (b.TurnId or 0) + 1 end
        local turnResult = {
            -- Structured message step so client shows proper escape failure text and sequencing
            Friendly = { { Type = "Message", Message = "You Coudn't get away!" } },
            Enemy = damageStep and { enemyAction, damageStep } or { enemyAction },
            HP = {
                Player = ActiveBattles[Player] and ActiveBattles[Player].PlayerCreature and ActiveBattles[Player].PlayerCreature.Stats and ActiveBattles[Player].PlayerCreature.Stats.HP or nil,
                PlayerMax = ActiveBattles[Player] and ActiveBattles[Player].PlayerCreature and ActiveBattles[Player].PlayerCreature.MaxStats and ActiveBattles[Player].PlayerCreature.MaxStats.HP or nil,
                Enemy = ActiveBattles[Player] and ActiveBattles[Player].FoeCreature and ActiveBattles[Player].FoeCreature.Stats and ActiveBattles[Player].FoeCreature.Stats.HP or nil,
                EnemyMax = ActiveBattles[Player] and ActiveBattles[Player].FoeCreature and ActiveBattles[Player].FoeCreature.MaxStats and ActiveBattles[Player].FoeCreature.MaxStats.HP or nil,
            },
            TurnId = b and b.TurnId or 0,
        }
        _logBattleMessages(Player.Name .. ":EscapeFail", turnResult)
        Events.Communicate:FireClient(Player, "TurnResult", turnResult)
    end
	
	return true
end

-- Store active battles for escape calculations
-- ActiveBattles declared above

-- Check all party creatures for evolution after battle
function ServerFunctions:CheckPartyEvolutions(Player)
	return CreatureSystem.CheckPartyEvolutions(Player)
end

-- Clear battle data when battle ends
function ServerFunctions:ClearBattleData(Player)
	return BattleSystem.ClearBattleData(Player)
end

-- Calculate escape chance using Pokemon formula (server-side)
function ServerFunctions:CalculateEscapeChance(Player, PlayerData)
	return BattleSystem.CalculateEscapeChance(Player, PlayerData)
end

-- Function to find the first alive creature in a party (delegates to CreatureSystem)
local function FindFirstAliveCreature(Party)
	return CreatureSystem.FindFirstAliveCreature(Party)
end

-- Helper: determine learned moves from LearnableMoves based on level thresholds (delegates to CreatureSystem)
local function GetMovesForLevel(LearnableMoves, level)
	return CreatureSystem.GetMovesForLevel(LearnableMoves, level)
end

-- Ensure all party creatures have an Ability assigned (delegates to CreatureSystem)
local function EnsurePartyAbilities(party)
	return CreatureSystem.EnsurePartyAbilities(party)
end

-- Ensure all party creatures have CurrentMoves derived from species Learnset (delegates to CreatureSystem)
local function EnsurePartyMoves(party)
	return CreatureSystem.EnsurePartyMoves(party)
end

-- Returns list of move names to learn at this level from a Learnset {[level]={moves}}
local function GetLearnsetMovesAtLevel(Learnset, level)
    local toLearn = {}
    if not Learnset then return toLearn end
    local movesAt = Learnset[level]
    if not movesAt then return toLearn end
    for _, moveName in ipairs(movesAt) do
        table.insert(toLearn, moveName)
    end
    return toLearn
end

-- Build starting moves (Pokémon-style) for a creature at a given level (delegates to CreatureSystem)
local function BuildStartingMovesFromLearnset(Learnset, level)
	return CreatureSystem.BuildStartingMovesFromLearnset(Learnset, level)
end

-- Damage + accuracy are handled by `Server/Battle/DamageCalculator.lua` (single source of truth).

-- Function to validate and start a battle
function ServerFunctions:StartBattle(Player, BattleType, BattleData)
	DBG:print("=== START BATTLE REQUEST ===")
	DBG:print("Player:", Player.Name)
	DBG:print("BattleType:", BattleType)
	DBG:print("BattleData:", BattleData)
	
	-- SECURITY: Prevent multiple battles for the same player
	if ActiveBattles[Player] then
		DBG:warn("Player", Player.Name, "already in battle, refusing new battle request")
		return false, "Player already in battle"
	end
	
	local StatCalc = require(game:GetService("ReplicatedStorage").Shared.StatCalc)
	-- Always use ClientData as the source of truth (returns debug data in debug mode or persisted data otherwise)
	local PlayerData = ClientData:Get(Player)
	DBG:print("Active PlayerData:", PlayerData)
	
	-- Check if PlayerData is still nil
	if not PlayerData then
		DBG:warn("Player", Player.Name, "has no player data available")
		return false, "No player data available"
	end
	
	-- Validate player has creatures in party
    if not PlayerData.Party or #PlayerData.Party == 0 then
		DBG:warn("Player", Player.Name, "tried to start battle with no creatures in party")
		return false, "No creatures in party"
	end
	
	-- Find first alive creature in player's party
    local PlayerCreature, PlayerCreatureIndex = FindFirstAliveCreature(PlayerData.Party)
	if not PlayerCreature then
		DBG:warn("Player", Player.Name, "tried to start battle with no alive creatures")
		return false, "No alive creatures in party"
	end
	
	-- Initialize XP data for all party creatures using XPManager
	for i, creature in ipairs(PlayerData.Party) do
		if creature then
			XPManager.InitializeCreatureXP(creature)
		end
	end
	
    -- Build battle creature from compact save (Name, Level, CurrentHP, Gender, Shiny, Nickname)
    -- Ensure all party members have moves and abilities before we start (helps debug data/old saves)
    EnsurePartyMoves(PlayerData.Party)
    EnsurePartyAbilities(PlayerData.Party)
    local Creatures = require(game:GetService("ReplicatedStorage").Shared.Creatures)
    -- YOffset deprecated; no longer used
	local function _applyStats(creature, forcedLevel: number?)
		local level = forcedLevel or creature.Level
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
		creature.Level = level
		creature.Stats = stats
		creature.Stats.HP = currentHPAbs
		creature.MaxStats = maxStats
		return maxStats, currentHPAbs, currentHPPercent
	end
	local forcedLevel = nil
	if BattleType == "PvP" then
		local lm = tostring(BattleData.LevelMode or "")
		if lm == "50" then forcedLevel = 50 elseif lm == "100" then forcedLevel = 100 end
	end
	local maxStats, currentHPAbs, currentHPPercent = _applyStats(PlayerCreature, forcedLevel)
	-- Apply held item stat modifiers for player creature
	HeldItemEffects.ApplyStatMods(PlayerCreature)

    -- Persist computed MaxStats into PlayerData party slot for consistent UI math
    if PlayerData.Party and PlayerData.Party[PlayerCreatureIndex] then
        PlayerData.Party[PlayerCreatureIndex].MaxStats = maxStats
        PlayerData.Party[PlayerCreatureIndex].Stats = PlayerData.Party[PlayerCreatureIndex].Stats or {}
        PlayerData.Party[PlayerCreatureIndex].Stats.HP = currentHPAbs
        PlayerData.Party[PlayerCreatureIndex].CurrentHP = currentHPPercent
		-- Mirror forced level for PvP so UI uses the battle level
		if forcedLevel then
			PlayerData.Party[PlayerCreatureIndex].Level = forcedLevel
		end
    end
    -- Ensure player creature has starting moves per learnset at current level
    local creatureDef = Creatures[PlayerCreature.Name]
    if creatureDef then
		-- Ensure Type exists on the battle creature instance (party saves often omit it).
		-- Used by weather effects like Sandstorm immunity.
		if (PlayerCreature.Type == nil or PlayerCreature.Type == "" or (type(PlayerCreature.Type) == "table" and #PlayerCreature.Type == 0))
			and creatureDef.Type ~= nil then
			PlayerCreature.Type = creatureDef.Type
		end
        PlayerCreature.CurrentMoves = PlayerCreature.CurrentMoves or {}
        PlayerCreature.LearnedMoves = PlayerCreature.LearnedMoves or {}
        if (not PlayerCreature.CurrentMoves or #PlayerCreature.CurrentMoves == 0) and creatureDef.Learnset then
            local startMoves, learned = BuildStartingMovesFromLearnset(creatureDef.Learnset, PlayerCreature.Level)
            PlayerCreature.CurrentMoves = startMoves
            PlayerCreature.LearnedMoves = learned
        end
    end
	
	local chunkNameForBattle = (BattleType == "PvP" and "PvP") or (PlayerData.Chunk or "Chunk1")

	local BattleInfo = {
		Type = BattleType, -- "Wild" or "Trainer"
		PlayerCreature = PlayerCreature,
		PlayerCreatureIndex = PlayerCreatureIndex,
		ChunkName = chunkNameForBattle,
		IsStatic = false, -- Set to true for legendary/boss encounters
		IsBoss = false, -- Set to true for boss battles
		EscapeAttempts = 0 -- Track escape attempts for wild battles
	}
	
	if BattleType == "Wild" then
		-- Validate wild encounter data
		if not BattleData or not BattleData.CreatureName or not BattleData.Level then
			DBG:warn("Invalid wild encounter data for player:", Player.Name)
			return false, "Invalid wild encounter data"
		end
		
		-- Get creature data
		local Creatures = require(game:GetService("ReplicatedStorage").Shared.Creatures)
		local CreatureData = Creatures[BattleData.CreatureName]
		if not CreatureData then
			DBG:warn("Unknown creature:", BattleData.CreatureName, "for player:", Player.Name)
			return false, "Unknown creature"
		end
		
		-- Create wild creature IVs (0-31) and compute stats
		local wildIVs = {
			HP = math.random(0, 31),
			Attack = math.random(0, 31),
			Defense = math.random(0, 31),
			Speed = math.random(0, 31),
		}
        local wildNature = Natures.GetRandomNature()
        local stats, maxStats = StatCalc.ComputeStats(BattleData.CreatureName, BattleData.Level, wildIVs, wildNature)
		
		-- Determine shiny status (use provided value or random roll)
		local isShiny = false
		if BattleData.Shiny == true then
			isShiny = true
		elseif BattleData.Shiny == false then
			isShiny = false
		else
			-- No explicit shiny flag, roll randomly (1 in SHINY_CHANCE)
			isShiny = math.random(1, GameData.Config.SHINY_CHANCE) == 1
		end
		
		-- Determine gender using species FemaleChance (0 = male, 1 = female)
		local fc = tonumber(CreatureData.FemaleChance) or 50
		local gender = (math.random(1, 100) <= fc) and 1 or 0
		
        local WildCreature = {
            Name = BattleData.CreatureName,
            Level = BattleData.Level,
            Stats = stats,
            MaxStats = maxStats,
			IVs = wildIVs,
            Type = CreatureData.Type,
			CurrentMoves = GetMovesForLevel(CreatureData.LearnableMoves, BattleData.Level),
            -- YOffset removed
            Gender = gender,
            Shiny = isShiny,
            Nature = wildNature,
            WeightKg = CreatureFactory.RollWeightKg(CreatureData.BaseWeightKg),
        }
        -- Assign a species ability for wild encounters
        do
            local Abilities = require(ReplicatedStorage.Shared.Abilities)
            WildCreature.Ability = Abilities.SelectAbility(WildCreature.Name, true)
            DBG:print("[Abilities] Wild", WildCreature.Name, "rolled ability:", WildCreature.Ability)
        end
		
		BattleInfo.FoeCreature = WildCreature
		BattleInfo.Message = "A wild " .. BattleData.CreatureName .. " has appeared!"
		
		-- Mark creature as seen
		PlayerData.SeenCreatures = PlayerData.SeenCreatures or {}
		PlayerData.SeenCreatures[BattleData.CreatureName] = true
		DBG:print("[Seen] Marked", BattleData.CreatureName, "as seen (wild encounter)")
		-- Update client data immediately so Dex can show the creature
		if ClientData.UpdateClientData then
			ClientData:UpdateClientData(Player, PlayerData)
		end
		
		-- Update challenge progress for discovering creatures
		pcall(function()
			ChallengesSystem.UpdateProgress(Player, "DiscoverCreatures", 0)
		end)
		
		-- Check for static/boss encounters
		if BattleData.IsStatic then
			BattleInfo.IsStatic = true
			BattleInfo.Message = BattleData.CreatureName .. " appeared!"
		end
		
		if BattleData.IsBoss then
			BattleInfo.IsBoss = true
			BattleInfo.Message = BattleData.CreatureName .. " appeared!"
		end
		
	elseif BattleType == "Trainer" then
		-- Validate trainer battle data
		if not BattleData or not BattleData.TrainerName or (not BattleData.TrainerParty and not BattleData.TrainerSpec) then
			DBG:warn("Invalid trainer battle data for player:", Player.Name)
			return false, "Invalid trainer battle data"
		end
		
		-- Build a full trainer party if a minimal spec was provided
		local trainerParty = BattleData.TrainerParty
		if not trainerParty and type(BattleData.TrainerSpec) == "table" then
			trainerParty = {}
			for _, spec in ipairs(BattleData.TrainerSpec) do
				if type(spec) == "table" and type(spec.Name) == "string" then
					local foe = {
						Name = spec.Name,
						Level = tonumber(spec.Level) or 1,
						CurrentMoves = spec.Moves,
						Shiny = spec.Shiny == true,
						Nature = spec.Nature,
						Gender = spec.Gender,
					}
					local instance = CreatureFactory.CreateFromFoe(foe)
					table.insert(trainerParty, instance)
				end
			end
		end
		
		-- Find first alive creature in trainer's party
		local TrainerCreature, TrainerCreatureIndex = FindFirstAliveCreature(trainerParty)
		if not TrainerCreature then
			DBG:warn("Trainer has no alive creatures for battle with player:", Player.Name)
			return false, "Trainer has no alive creatures"
		end
		
		BattleInfo.FoeCreature = TrainerCreature
		BattleInfo.FoeCreatureIndex = TrainerCreatureIndex
		BattleInfo.TrainerName = BattleData.TrainerName
		BattleInfo.TrainerParty = trainerParty
		BattleInfo.TrainerId = BattleData.TrainerId
		BattleInfo.TrainerDialogue = BattleData.TrainerDialogue -- Pass dialogue data for post-battle messages
		BattleInfo.Message = BattleData.TrainerName .. " would like to battle!"
		
		-- Mark trainer's first creature as seen
		if TrainerCreature and TrainerCreature.Name then
			PlayerData.SeenCreatures = PlayerData.SeenCreatures or {}
			PlayerData.SeenCreatures[TrainerCreature.Name] = true
			DBG:print("[Seen] Marked", TrainerCreature.Name, "as seen (trainer battle)")
			-- Update client data immediately so Dex can show the creature
			if ClientData.UpdateClientData then
				ClientData:UpdateClientData(Player, PlayerData)
			end
			
			-- Update challenge progress for discovering creatures
			pcall(function()
				ChallengesSystem.UpdateProgress(Player, "DiscoverCreatures", 0)
			end)
		end
		
	elseif BattleType == "PvP" then
		-- Validate PvP battle data: requires opponent creature
		if not BattleData or not BattleData.FoeCreature then
			DBG:warn("Invalid PvP battle data for player:", Player.Name)
			return false, "Invalid PvP battle data"
		end

		BattleInfo.Type = "PvP"
		BattleInfo.FoeCreature = BattleData.FoeCreature
		BattleInfo.FoeCreatureIndex = tonumber(BattleData.FoeCreatureIndex) or 1
		BattleInfo.OpponentName = BattleData.OpponentName or "Opponent"
		BattleInfo.OpponentUserId = BattleData.OpponentUserId
		BattleInfo.Message = (BattleData.OpponentName or "Opponent") .. " challenges you to a battle!"
		-- PvP battles should always use the dedicated PvP battle scene
		BattleInfo.ChunkName = "PvP"

		-- Mark foe as seen
		if BattleInfo.FoeCreature and BattleInfo.FoeCreature.Name then
			PlayerData.SeenCreatures = PlayerData.SeenCreatures or {}
			PlayerData.SeenCreatures[BattleInfo.FoeCreature.Name] = true
			if ClientData.UpdateClientData then
				ClientData:UpdateClientData(Player, PlayerData)
			end
		end

	else
		DBG:warn("Unknown battle type:", BattleType, "for player:", Player.Name)
		return false, "Unknown battle type"
	end
	
	-- Clone battle scene to player's PlayerGui
	ServerFunctions:SetupBattleScene(Player, BattleInfo.ChunkName)
	
    -- Initialize TurnId and store battle data for escape calculations
    BattleInfo.TurnId = 0
    ActiveBattles[Player] = BattleInfo
    if BattleType == "PvP" and BattleData.OpponentPlayer then
        BattleInfo.OpponentPlayer = BattleData.OpponentPlayer
    end
    
    -- Initialize stat stages for both creatures at battle start
    StatStages.EnsureCreatureHasStages(BattleInfo.PlayerCreature)
    StatStages.EnsureCreatureHasStages(BattleInfo.FoeCreature)
    
    DBG:print("Stored battle data for escape calculations")
    -- Mark in-battle to gate autosave in ProfileStore
    local pd = ClientData:Get(Player)
    if pd then
        pd.InBattle = true
        ClientData:UpdateClientData(Player, pd)
    end

    -- Take a pre-battle snapshot for rollback if the player leaves mid-battle
    local snapshot = {
        Party = {},
        Studs = PlayerData.Studs,
        Chunk = PlayerData.Chunk,
        LastChunk = PlayerData.LastChunk,
        LeaveData = PlayerData.LeaveData and table.clone(PlayerData.LeaveData) or nil,
        DefeatedTrainers = PlayerData.DefeatedTrainers and table.clone(PlayerData.DefeatedTrainers) or {},
    }
    if PlayerData.Party then
        for i, c in ipairs(PlayerData.Party) do
            snapshot.Party[i] = c and table.clone(c) or nil
        end
    end
    PlayerData.PendingBattle = snapshot
    -- For PvP, force current party HP to MaxStats (100%) at start; snapshot preserves original
    if BattleType == "PvP" and PlayerData.Party then
        for i, c in ipairs(PlayerData.Party) do
            if c and c.MaxStats and c.MaxStats.HP then
                c.Stats = c.Stats or {}
                c.Stats.HP = c.MaxStats.HP
                c.CurrentHP = 100
            end
        end
    end
    -- Preserve LeaveData during battle so Continue can restore exact position.
    -- Runtime code should avoid updating LeaveData while InBattle, but do not clear it here.
    ClientData:UpdateClientData(Player, PlayerData)

    -- Set weather from chunk (can be overridden by entry abilities)
    -- Only set weather for non-PvP battles and if not already set
    -- Only set weather for types that have battle effects (Sunlight, Rain, Sandstorm, Snow)
    if BattleType ~= "PvP" and not BattleInfo.Weather then
        local weatherData = WeatherService:GetCurrentWeather(BattleInfo.ChunkName)
        if weatherData then
            -- Map weather name to battle weather format
            -- Weather names: "Clear", "Harsh Sun", "Snowstorm", "Snow", "Fog", "Overcast", "Rain", "Thunderstorm", "Sandstorm"
            local weatherName = weatherData.Name
            -- Map to battle weather names (abilities use "Sunlight", so we'll use that format)
            -- Only set weather for types that have battle effects
            if weatherName == "Harsh Sun" then
                BattleInfo.Weather = "Sunlight"
                BattleInfo.WeatherId = weatherData.Id
                BattleInfo.WeatherName = weatherName
                DBG:print("[Weather] Set battle weather from chunk:", weatherName, "->", BattleInfo.Weather)
            elseif weatherName == "Rain" or weatherName == "Thunderstorm" then
                BattleInfo.Weather = "Rain"
                BattleInfo.WeatherId = weatherData.Id
                BattleInfo.WeatherName = weatherName
                DBG:print("[Weather] Set battle weather from chunk:", weatherName, "->", BattleInfo.Weather)
            elseif weatherName == "Sandstorm" then
                BattleInfo.Weather = "Sandstorm"
                BattleInfo.WeatherId = weatherData.Id
                BattleInfo.WeatherName = weatherName
                DBG:print("[Weather] Set battle weather from chunk:", weatherName, "->", BattleInfo.Weather)
            elseif weatherName == "Snow" or weatherName == "Snowstorm" then
                BattleInfo.Weather = "Snow"
                BattleInfo.WeatherId = weatherData.Id
                BattleInfo.WeatherName = weatherName
                DBG:print("[Weather] Set battle weather from chunk:", weatherName, "->", BattleInfo.Weather)
            else
                -- Clear, Fog, Overcast don't have battle effects - don't set weather
                BattleInfo.Weather = nil
                BattleInfo.WeatherId = weatherData.Id
                BattleInfo.WeatherName = weatherName
                DBG:print("[Weather] Weather", weatherName, "has no battle effects - not setting BattleInfo.Weather")
            end
        end
    end

    -- Trigger OnEntry abilities for initial active creatures BEFORE sending to client
    -- Apply stat changes and collect ability activation events for the client to display
    do
        local Abilities = require(game:GetService("ReplicatedStorage").Shared.Abilities)
        local entryAbilityEvents = {}
        
        -- Check player's creature entry ability
        local pAbility = Abilities.OnEntry(PlayerCreature)
        if pAbility and type(pAbility) == "table" then
            local playerCreatureName = PlayerCreature.Nickname or PlayerCreature.Name or "Your creature"
            local abilityName = pAbility.Ability or "Unknown"
            
            if pAbility.Effect == "Intimidate" and pAbility.StatChange then
                -- Lower foe attack using StatStages module
                local stat = pAbility.StatChange.Stat
                local stages = pAbility.StatChange.Stages
                local newStage, actualChange = StatStages.ModifyStage(BattleInfo.FoeCreature, stat, stages)
                
                local foeName = BattleInfo.FoeCreature.Nickname or BattleInfo.FoeCreature.Name or "Foe"
                local message = StatStages.GetChangeMessage(foeName, stat, stages, actualChange)
                
                table.insert(entryAbilityEvents, {
                    Type = "AbilityActivation",
                    Ability = abilityName,
                    Creature = playerCreatureName,
                    Message = message,
                    IsPlayer = true,
                    StatChange = { Stat = stat, Stages = actualChange },
                })
                DBG:print("[Abilities] Player's", abilityName, "lowered foe", stat, "to stage", newStage)
            elseif pAbility.Effect == "Sunlight" then
                BattleInfo.Weather = "Sunlight"
                BattleInfo.WeatherTurns = 5
                table.insert(entryAbilityEvents, {
                    Type = "AbilityActivation",
                    Ability = abilityName,
                    Creature = playerCreatureName,
                    Message = "The sunlight turned harsh!",
                    IsPlayer = true,
                })
                DBG:print("[Abilities] Player's", abilityName, "set Sunlight")
            end
        end
        
        -- Check foe's creature entry ability
        local fAbility = Abilities.OnEntry(BattleInfo.FoeCreature)
        if fAbility and type(fAbility) == "table" then
            local foeCreatureName = BattleInfo.FoeCreature.Nickname or BattleInfo.FoeCreature.Name or "Foe"
            local abilityName = fAbility.Ability or "Unknown"
            
            if fAbility.Effect == "Intimidate" and fAbility.StatChange then
                -- Lower player attack using StatStages module
                local stat = fAbility.StatChange.Stat
                local stages = fAbility.StatChange.Stages
                local newStage, actualChange = StatStages.ModifyStage(PlayerCreature, stat, stages)
                
                local playerName = PlayerCreature.Nickname or PlayerCreature.Name or "Your creature"
                local message = StatStages.GetChangeMessage(playerName, stat, stages, actualChange)
                
                table.insert(entryAbilityEvents, {
                    Type = "AbilityActivation",
                    Ability = abilityName,
                    Creature = foeCreatureName,
                    Message = message,
                    IsPlayer = false,
                    StatChange = { Stat = stat, Stages = actualChange },
                })
                DBG:print("[Abilities] Foe's", abilityName, "lowered player", stat, "to stage", newStage)
            elseif fAbility.Effect == "Sunlight" then
                BattleInfo.Weather = "Sunlight"
                BattleInfo.WeatherTurns = 5
                table.insert(entryAbilityEvents, {
                    Type = "AbilityActivation",
                    Ability = abilityName,
                    Creature = foeCreatureName,
                    Message = "The sunlight turned harsh!",
                    IsPlayer = false,
                })
                DBG:print("[Abilities] Foe's", abilityName, "set Sunlight")
            end
        end
        
        -- Add entry ability events to BattleInfo for client to process
        if #entryAbilityEvents > 0 then
            BattleInfo.EntryAbilityEvents = entryAbilityEvents
            DBG:print("[Abilities] Added", #entryAbilityEvents, "entry ability events to BattleInfo")
            for i, event in ipairs(entryAbilityEvents) do
                DBG:print("[Abilities] Event", i, ":", event.Ability, event.Creature, event.Message)
            end
        end
    end

	-- NOW notify client to start battle (after entry abilities are processed)
	DBG:print("Starting", BattleType, "battle for player:", Player.Name)
	DBG:print("[Abilities] BattleInfo.EntryAbilityEvents:", BattleInfo.EntryAbilityEvents ~= nil and #BattleInfo.EntryAbilityEvents or "nil")
	Events.Communicate:FireClient(Player, "StartBattle", BattleInfo)
	
	return true, BattleInfo
end

-- Function to setup battle scene for player
function ServerFunctions:SetupBattleScene(Player, ChunkName)
	DBG:print("Setting up battle scene for player:", Player.Name, "chunk:", ChunkName)
	
	local ServerStorage = game:GetService("ServerStorage")
	local BattleScenes = ServerStorage:WaitForChild("BattleScenes")
	
	-- Check if battle scene exists for this chunk
	local ChunkBattleScene = BattleScenes:FindFirstChild(ChunkName)
	if not ChunkBattleScene then
		DBG:warn("No battle scene found for chunk:", ChunkName, "using fallback")
		-- Try fallback to Chunk1 first
		ChunkBattleScene = BattleScenes:FindFirstChild("Chunk1")
		if not ChunkBattleScene then
			-- If Chunk1 doesn't exist, use the first available battle scene
			local firstScene = BattleScenes:GetChildren()[1]
			if firstScene then
				ChunkBattleScene = firstScene
				DBG:warn("Using first available battle scene:", firstScene.Name)
			else
				error("No battle scenes found in BattleScenes folder!")
			end
		else
			DBG:print("Using Chunk1 as fallback battle scene")
		end
	end
	
	-- Clone the battle scene to player's PlayerGui
	local BattleScene = ChunkBattleScene:Clone()
	BattleScene.Name = "BattleScene_" .. ChunkName
	BattleScene.Parent = Player:WaitForChild("PlayerGui")
	
	DBG:print("Battle scene cloned to PlayerGui:", BattleScene.Name)
end

-- Handle StartBattle remote event
Events.Communicate.OnServerEvent:Connect(function(Player, EventType, Data)
	if EventType == "StartBattle" then
		-- Send battle info to the specific client (don't force update client data with battle info)
		Events.Communicate:FireClient(Player, "StartBattle", Data)
		DBG:print("Sent battle info to client:", Player.Name)
	elseif EventType == "EvolutionComplete" then
		-- Client has finished showing evolution UI, now sync the data
		DBG:print("[Evolution] Client", Player.Name, "completed evolution UI - updating client data")
		local PlayerData = ClientData:Get(Player)
		if PlayerData then
			ClientData:UpdateClientData(Player, PlayerData)
			DBG:print("[Evolution] Client data updated after evolution UI")
		end
	end
end)

-- Pending Move Replace prompts keyed by player: { [slotIndex] = { Move = string, ExpiresAt = number } }
local _pendingMoveReplace: {[Player]: {[number]: {Move: string, ExpiresAt: number}}} = {}
local _pendingMLReplace: {[Player]: {[number]: {Move: string, ItemName: string, ExpiresAt: number}}} = {}

-- Install ProcessTurn into its own module (needs pending state above)
ProcessTurnModule.apply(ServerFunctions, {
	ActiveBattles = ActiveBattles,
	BattleSystem = BattleSystem,
	ClientData = ClientData,
	DBG = DBG,
	PvPTurnBuffer = _pvpTurnBuffer,
	PvPResolving = _pvpResolving,
	PvPKey = _pvpKey,
	PendingMoveReplace = _pendingMoveReplace,
	LogBattleMessages = _logBattleMessages,
	RestorePendingBattleSnapshot = _restorePendingBattleSnapshot,
	SaveNow = _saveNow,
	FindFirstAliveCreature = FindFirstAliveCreature,
	ChallengesSystem = ChallengesSystem,
})

-- Professional data access: non-blocking wait with bounded backoff (no kicks)
type DataWaitResult = any?
local function _waitForClientData(player: Player, timeoutSeconds: number?): DataWaitResult
	local deadline = os.clock() + (tonumber(timeoutSeconds) or 8)
	local delay = 0.05
	local data = ClientData:Get(player)
	while data == nil and os.clock() < deadline and player and player.Parent == Players do
		task.wait(delay)
		delay = math.min(delay * 1.5, 0.5)
		data = ClientData:Get(player)
	end
	return data
end

Events.Request.OnServerInvoke = function(Player: Player, Request: any)
	DBG:print("=== SERVER REQUEST RECEIVED ===")
	DBG:print("Player:", Player.Name)
	DBG:print("Request:", Request)
	DBG:print("Request[1]:", Request[1])

    -- Whitelist verbs and basic rate limit
    local verb = typeof(Request) == "table" and Request[1] or nil
    if not verb or not _ALLOWED_VERBS[verb] then
        DBG:warn("Blocked unknown verb from", Player.Name, verb)
        return false
    end
    if not _rateLimitOk(Player) then
        DBG:warn("Rate limit exceeded for", Player.Name, verb)
        return false
    end
	
	if Request[1] == "DataGet" then
		-- Wait briefly for data; never kick on timeout. Client will retry or rely on push updates.
		local data = _waitForClientData(Player, 8)
		if data == nil then
			DBG:warn("[DataGet] Timed out waiting for data for", Player.Name, "- returning nil (client should retry)")
		end
		return data
	end
	if Request[1] == "RequestChunk" then
		return ServerFunctions:LoadChunkPlayer(Player,Request[2])
	end
	if Request[1] == "FilterName" then
		return ServerFunctions:FilterName(Player, Request[2])
	end
	if Request[1] == "UpdateNickname" then
		return ServerFunctions:UpdateNickname(Player, Request[2])
	end
	if Request[1] == "SetEvent" then
		return ServerFunctions:SetEvent(Player, Request[2], Request[3])
	end
	if Request[1] == "RequestStarters" then
		return ServerFunctions:RequestStarters(Player)
	end
	if Request[1] == "PickStarter" then
		return ServerFunctions:PickStarter(Player, Request[2])
	end
	if Request[1] == "GetEncounterData" then
		return ServerFunctions:GetEncounterData(Player, Request[2])
	end
if Request[1] == "TryEncounterStep" then
    return ServerFunctions:TryEncounterStep(Player)
end
	if Request[1] == "GetChunkWeather" then
		-- Return weather data for a specific chunk
		local chunkName = Request[2]
		if not chunkName or typeof(chunkName) ~= "string" then
			return nil
		end
		local weatherData = ServerFunctions:GetCurrentWeather(chunkName)
		if weatherData then
			return {
				Id = weatherData.Id,
				Name = weatherData.Name,
				Description = weatherData.Description,
				Icon = weatherData.Icon,
				VisualEffects = weatherData.VisualEffects,
				AmbientSound = weatherData.AmbientSound,
			}
		end
		return nil
	end
	if Request[1] == "UpdateSettings" then
		return ServerFunctions:UpdateSettings(Player, Request[2], Request[3])
	end
	if Request[1] == "UpdateLastChunk" then
		return ServerFunctions:UpdateLastChunk(Player, Request[2])
    elseif Request[1] == "SetBlackoutReturnChunk" then
        return ServerFunctions:SetBlackoutReturnChunk(Player)
	elseif Request[1] == "HealParty" then
		-- Only allow healing when near authorized healer NPCs or inside safe chunks
		local PlayerData = ClientData:Get(Player)
		local CurrentChunk = PlayerData and PlayerData.Chunk
		-- Validation: only allow in approved healer chunks
        local AllowedHealerChunks = {
            ["Chunk1"] = true,
            ["Chunk2"] = true,
            ["CatchCare"] = true,
            ["Professor's Lab"] = true, -- allow healing in lab for Kyro intro flow
        }
		if not AllowedHealerChunks[CurrentChunk] then
			return false
		end
		-- Heal creatures: set HP to max, CurrentHP percent to 100, and clear status conditions
		local StatusModule = require(game:GetService("ReplicatedStorage").Shared.Status)
		if PlayerData and PlayerData.Party then
			for _, creature in ipairs(PlayerData.Party) do
				if creature then
					-- Support compact schema with CurrentHP percent
					creature.CurrentHP = 100
					-- If Stats/MaxStats present, sync scalar HP too
					if creature.MaxStats and creature.MaxStats.HP then
						creature.Stats = creature.Stats or {}
						creature.Stats.HP = creature.MaxStats.HP
					end
					-- Clear status conditions (burn, poison, paralysis, sleep, freeze)
					if StatusModule and StatusModule.Remove then
						StatusModule.Remove(creature)
					else
						creature.Status = nil
					end
					-- Clear volatile status conditions (confusion, infatuation, flinch)
					creature.VolatileStatus = nil
				end
			end
			-- Persist/update client-side cache
			if ClientData.UpdateClientData then
				ClientData:UpdateClientData(Player, PlayerData)
			end
			return true
		end
		return false
	end
	if Request[1] == "ClearLeaveDataCFrame" then
		return ServerFunctions:ClearLeaveDataCFrame(Player)
	end
    if Request[1] == "AttemptEscape" then
        return ServerFunctions:AttemptEscape(Player)
    end
    if Request[1] == "ManualSave" then
        -- Rate limit manual saves per player
        local now = os.clock()
        local last = _lastManualSaveAt[Player] or 0
        if (now - last) < MANUAL_SAVE_MIN_INTERVAL then
            return false, "RateLimited"
        end

        local PlayerDataModule = require(ServerScriptService.Server.ClientData.PlayerData)
        if PlayerDataModule and PlayerDataModule.ManualSave then
            local ok = PlayerDataModule.ManualSave(Player)
            if ok == true then
                _lastManualSaveAt[Player] = os.clock()
            end
            return ok == true
        end
        return false
    end
    if Request[1] == "NewGame" then
        -- Server-authoritative new game: deep reset persistent profile
        local ClientDataModule = require(ServerScriptService.Server.ClientData)
        local PlayerDataModule = require(ServerScriptService.Server.ClientData.PlayerData)
        local updated = PlayerDataModule.ResetData(Player)
        -- If profile-based reset didn't return data (e.g., in DebugData mode), build fresh defaults
        if not updated then
            local PlayerDataTemplate = require(game.ReplicatedStorage.Shared.PlayerData)
            local defaults = PlayerDataTemplate.DEFAULT_PLAYER_DATA
            local fresh = table.clone(defaults)
            fresh.Settings = table.clone(defaults.Settings)
            fresh.Events = table.clone(defaults.Events)
            fresh.Party = {}
            fresh.Boxes = {}
            
            -- Check Vault+ ownership for box count
            local VAULTPLUS_GAMEPASS_ID = 1656816296
            local success, ownsGamepass = pcall(function()
                return MarketplaceService:UserOwnsGamePassAsync(Player.UserId, VAULTPLUS_GAMEPASS_ID)
            end)
            local maxBoxes = (success and ownsGamepass) and 50 or 8
            
            for i = 1, maxBoxes do
                fresh.Boxes[i] = { Name = "Box " .. tostring(i), Creatures = {} }
            end
            fresh.Items = {}
            fresh.Creatures = {}
            fresh.Gamepasses = {}
            fresh.PickedUpItems = {}
            fresh.DefeatedTrainers = {}
            fresh.RedeemedCodes = {}
            fresh.SeenCreatures = {}
            fresh.SelectedStarter = nil
            fresh.Starters = nil
            fresh.PendingCapture = nil
            fresh.LastChunk = nil
            fresh.LastCF = nil
            fresh.LeaveData = nil
            fresh.Sequence = nil
            fresh.Chunk = nil
            fresh.DexNumber = 0
            updated = fresh
        end
        -- Update the server-side live cache (covers DebugData mode via ClientData:Set)
        if ClientDataModule.Set then
            ClientDataModule:Set(Player, updated)
        end
        -- Persist if applicable and update client cache
        if PlayerDataModule.ManualSave then
            PlayerDataModule.ManualSave(Player)
        end
        if ClientDataModule.UpdateClientData then
            ClientDataModule:UpdateClientData(Player, updated)
        end
        return true
    end
    if Request[1] == "MoveReplaceDecision" then
        -- Payload: { SlotIndex = number, NewMove = string, ReplaceIndex = number } ReplaceIndex 1..4, or 0 to decline
        local payload = Request[2]
        if typeof(payload) ~= "table" then return false end
        local slotIndex = tonumber(payload.SlotIndex)
        local replaceIndex = tonumber(payload.ReplaceIndex)
        local newMove = payload.NewMove
        if type(newMove) ~= "string" or not slotIndex or slotIndex < 1 then return false end
        -- Validate pending prompt
        local pendingForPlayer = _pendingMoveReplace[Player] and _pendingMoveReplace[Player][slotIndex]
        if not pendingForPlayer or pendingForPlayer.Move ~= newMove or (pendingForPlayer.ExpiresAt or 0) < os.clock() then
            DBG:warn("MoveReplaceDecision rejected - no valid pending prompt for", Player.Name)
            return false
        end
        -- Validate party and target creature
        local PlayerData = ClientData:Get(Player)
        if not PlayerData or not PlayerData.Party or not PlayerData.Party[slotIndex] then return false end
        local creature = PlayerData.Party[slotIndex]
        creature.CurrentMoves = creature.CurrentMoves or {}
        -- Decline learning
        if replaceIndex == 0 then
            _pendingMoveReplace[Player][slotIndex] = nil
            Events.Communicate:FireClient(Player, "BattleEvent", { Type = "MoveDeclined", Creature = creature.Nickname or creature.Name, Move = newMove, IsPlayer = true })
            return true
        end
        -- Replace existing move
        if replaceIndex and replaceIndex >= 1 and replaceIndex <= 4 and creature.CurrentMoves[replaceIndex] ~= nil then
            -- Security: ensure newMove exists in Learnset at or below current level
            local CreaturesModule = require(game.ReplicatedStorage.Shared.Creatures)
            local def = CreaturesModule[creature.Name]
            local allowed = false
            if def and def.Learnset then
                for lvl, list in pairs(def.Learnset) do
                    if lvl <= (creature.Level or 1) then
                        for _, mv in ipairs(list) do
                            if mv == newMove then allowed = true break end
                        end
                    end
                    if allowed then break end
                end
            end
            if not allowed then
                DBG:warn("MoveReplaceDecision rejected - move not in learnset for", Player.Name)
                return false
            end
            local oldMove = creature.CurrentMoves[replaceIndex]
            creature.CurrentMoves[replaceIndex] = newMove
            -- Persist and notify
            ClientData:UpdateClientData(Player, PlayerData)
            _pendingMoveReplace[Player][slotIndex] = nil
            Events.Communicate:FireClient(Player, "BattleEvent", {
                Type = "MoveReplaced",
                Creature = creature.Nickname or creature.Name,
                OldMove = oldMove,
                NewMove = newMove,
                IsPlayer = true,
            })
            return true
        end
        DBG:warn("MoveReplaceDecision rejected - invalid replace index from", Player.Name)
        return false
    end
    if Request[1] == "MLMoveReplaceDecision" then
        -- Payload: { SlotIndex = number, ReplaceIndex = number (1-4 or 0 to decline), MoveName = string }
        local payload = Request[2]
        if typeof(payload) ~= "table" then return false end
        local slotIndex = tonumber(payload.SlotIndex)
        local replaceIndex = tonumber(payload.ReplaceIndex)
        local moveName = payload.MoveName
        if type(moveName) ~= "string" or not slotIndex or slotIndex < 1 then return false end
        
        -- Validate pending ML replacement
        local pendingForPlayer = _pendingMLReplace[Player] and _pendingMLReplace[Player][slotIndex]
        if not pendingForPlayer or pendingForPlayer.Move ~= moveName or (pendingForPlayer.ExpiresAt or 0) < os.clock() then
            DBG:warn("MLMoveReplaceDecision rejected - no valid pending prompt for", Player.Name)
            return false
        end
        
        -- Validate party and target creature
        local PlayerData = ClientData:Get(Player)
        if not PlayerData or not PlayerData.Party or not PlayerData.Party[slotIndex] then return false end
        local creature = PlayerData.Party[slotIndex]
        creature.CurrentMoves = creature.CurrentMoves or {}
        
        -- Decline learning
        if replaceIndex == 0 then
            _pendingMLReplace[Player][slotIndex] = nil
            -- Fire client event to notify cancellation
            Events.Communicate:FireClient(Player, "MLMoveCancelled", {
                Creature = creature.Nickname or creature.Name,
                Move = moveName,
            })
            return true
        end
        
        -- Validate replaceIndex is a valid number
        if not replaceIndex or type(replaceIndex) ~= "number" then
            DBG:warn("MLMoveReplaceDecision rejected - invalid replaceIndex type from", Player.Name)
            return false
        end
        
        -- Replace existing move
        if replaceIndex >= 1 and replaceIndex <= 4 then
            -- Ensure CurrentMoves array is properly initialized
            if not creature.CurrentMoves[replaceIndex] or creature.CurrentMoves[replaceIndex] == "" then
                DBG:warn("MLMoveReplaceDecision rejected - move slot is empty at index", replaceIndex, "from", Player.Name)
                return false
            end
            local oldMove = creature.CurrentMoves[replaceIndex]
            creature.CurrentMoves[replaceIndex] = moveName
            
            -- Deduct item
            local itemName = pendingForPlayer.ItemName
            PlayerData.Items = PlayerData.Items or {}
            local itemCount = PlayerData.Items[itemName] or 0
            if itemCount > 0 then
                PlayerData.Items[itemName] = math.max(0, itemCount - 1)
            end
            
            -- Clear pending and persist
            _pendingMLReplace[Player][slotIndex] = nil
            if ClientData.UpdateClientData then ClientData:UpdateClientData(Player, PlayerData) end
            
            -- Fire success event
            Events.Communicate:FireClient(Player, "MLMoveReplaced", {
                Creature = creature.Nickname or creature.Name,
                OldMove = oldMove,
                NewMove = moveName,
            })
            return true
        end
        
        DBG:warn("MLMoveReplaceDecision rejected - invalid replace index from", Player.Name)
        return false
    end
    if Request[1] == "ExecuteMove" then
        if typeof(Request[2]) ~= "table" then return false end
        return ServerFunctions:ExecuteMove(Player, Request[2])
    end
    if Request[1] == "UseItem" then
        local payload = Request[2]
        if typeof(payload) ~= "table" or type(payload.Name) ~= "string" then return false end
        return ServerFunctions:UseItem(Player, payload)
    end
	if Request[1] == "BattleRequest" then
		local payload = Request[2]
		if typeof(payload) ~= "table" or type(payload.TargetUserId) ~= "number" then return "Cannot proceed." end
		return ServerFunctions:SendBattleRequest(Player, payload)
	end
	if Request[1] == "BattleRequestReply" then
		local payload = Request[2]
		if typeof(payload) ~= "table" then return false end
		return ServerFunctions:HandleBattleRequestReply(Player, payload)
	end
	if Request[1] == "TradeRequest" then
		local payload = Request[2]
		if typeof(payload) ~= "table" or type(payload.TargetUserId) ~= "number" then return "Cannot proceed." end
		return ServerFunctions:SendTradeRequest(Player, payload)
	end
	if Request[1] == "TradeRequestReply" then
		local payload = Request[2]
		if typeof(payload) ~= "table" then return false end
		return ServerFunctions:HandleTradeRequestReply(Player, payload)
	end
	if Request[1] == "TradeSendMessage" then
		local payload = Request[2]
		if typeof(payload) ~= "table" then return false end
		return ServerFunctions:TradeSendMessage(Player, payload)
	end
	if Request[1] == "TradeFetchBox" then
		local payload = Request[2]
		if typeof(payload) ~= "table" then return false end
		return ServerFunctions:TradeFetchBox(Player, payload)
	end
	if Request[1] == "TradeSetReady" then
		local payload = Request[2]
		if typeof(payload) ~= "table" then return false end
		return ServerFunctions:TradeSetReady(Player, payload)
	end
	if Request[1] == "TradeConfirm" then
		local payload = Request[2]
		if typeof(payload) ~= "table" then return false end
		return ServerFunctions:TradeConfirm(Player, payload)
	end
	if Request[1] == "TradeCancel" then
		local payload = Request[2]
		if payload ~= nil and typeof(payload) ~= "table" then return false end
		return ServerFunctions:TradeCancel(Player, payload)
	end
	if Request[1] == "TradeUpdateOffer" then
		local payload = Request[2]
		if typeof(payload) ~= "table" then return false end
		return ServerFunctions:TradeUpdateOffer(Player, payload)
	end
    if Request[1] == "RepelStepsDepleted" then
        -- Client notified that repel steps reached 0
        local PlayerData = ClientData:Get(Player)
        if PlayerData and PlayerData.RepelState then
            PlayerData.RepelState.ActiveSteps = 0
            PlayerData.RepelState.ItemName = nil
            DBG:print("[ServerFunctions] Repel steps depleted for", Player.Name)
            if ClientData.UpdateClientData then ClientData:UpdateClientData(Player, PlayerData) end
        end
        return true
    end
    if Request[1] == "UpdateRepelSteps" then
        -- Client syncing repel step count
        local steps = tonumber(Request[2])
        if steps and steps >= 0 then
            local PlayerData = ClientData:Get(Player)
            if PlayerData and PlayerData.RepelState then
                PlayerData.RepelState.ActiveSteps = steps
                -- Don't update client data on every sync to avoid spam
            end
        end
        return true
    end
    if Request[1] == "GiveItem" then
        local payload = Request[2]
        if typeof(payload) ~= "table" or type(payload.Name) ~= "string" then return false end
        return ServerFunctions:GiveItem(Player, payload)
    end
    if Request[1] == "GetUnstuck" then
        -- Server-side cooldown gate only; client handles the local reposition
        local now = os.clock()
        local untilTs = _unstuckCooldown[Player] or 0
        if untilTs > now then
            local remaining = math.max(0, math.floor(untilTs - now))
            return { Success = false, CooldownSeconds = remaining }
        end
        local COOLDOWN = 180
        _unstuckCooldown[Player] = now + COOLDOWN
        return { Success = true, CooldownSeconds = COOLDOWN }
    end
    if Request[1] == "PurchaseCatchCareItem" then
        return ServerFunctions:PurchaseCatchCareItem(Player, Request[2])
    end
    if Request[1] == "TakeHeldItem" then
        local payload = Request[2]
        if typeof(payload) ~= "table" or typeof(payload.Location) ~= "table" then return false end
        local loc = payload.Location
        local PlayerData = ClientData:Get(Player)
        if not PlayerData then DBG:print("[Server] TakeHeldItem: no PlayerData"); return false end
        
        -- Check if creature is locked in Mystery Trade
        local locationForCheck = { where = loc.Type, box = loc.BoxIndex, index = loc.SlotIndex }
        if MysteryTradeService:IsCreatureLocked(Player.UserId, locationForCheck) then
            return { Success = false, Message = "This creature is currently in a trade." }
        end
        
        local creature
        if loc.Type == "Party" then
            local idx = tonumber(loc.SlotIndex)
            if not idx or not PlayerData.Party or not PlayerData.Party[idx] then DBG:print("[Server] TakeHeldItem: invalid party slot"); return { Success = false } end
            creature = PlayerData.Party[idx]
        elseif loc.Type == "Box" then
            local bi = tonumber(loc.BoxIndex)
            local si = tonumber(loc.SlotIndex)
            if not bi or not si or not PlayerData.Boxes or not PlayerData.Boxes[bi] or not PlayerData.Boxes[bi].Creatures then DBG:print("[Server] TakeHeldItem: invalid box location"); return { Success = false } end
            local list = PlayerData.Boxes[bi].Creatures
            if not list[si] then DBG:print("[Server] TakeHeldItem: empty box slot"); return { Success = false } end
            creature = list[si]
        else
            DBG:print("[Server] TakeHeldItem: unknown location type", loc and loc.Type)
            return { Success = false }
        end
        local itemName = creature and creature.HeldItem
        if type(itemName) ~= "string" or itemName == "" then DBG:print("[Server] TakeHeldItem: no held item"); return { Success = false } end
        PlayerData.Items = PlayerData.Items or {}
        PlayerData.Items[itemName] = (PlayerData.Items[itemName] or 0) + 1
        creature.HeldItem = nil
        ClientData:UpdateClientData(Player, PlayerData)
        DBG:print("[Server] TakeHeldItem success - returned", itemName)
        return { Success = true, ItemName = itemName }
    end
    if Request[1] == "DesyncCreature" then
        local payload = Request[2]
        if typeof(payload) ~= "table" or typeof(payload.Location) ~= "table" then return false end
        local loc = payload.Location
        
        -- Check if creature is locked in Mystery Trade
        local locationForCheck = { where = loc.Type, box = loc.BoxIndex, index = loc.SlotIndex }
        if MysteryTradeService:IsCreatureLocked(Player.UserId, locationForCheck) then
            return false -- Cannot desync locked creature
        end
        
        local PlayerData = ClientData:Get(Player)
        if not PlayerData then return false end
        if loc.Type == "Party" then
            local idx = tonumber(loc.SlotIndex)
            if not idx or not PlayerData.Party or not PlayerData.Party[idx] then return false end
            table.remove(PlayerData.Party, idx)
        elseif loc.Type == "Box" then
            local bi = tonumber(loc.BoxIndex)
            local si = tonumber(loc.SlotIndex)
            if not bi or not si or not PlayerData.Boxes or not PlayerData.Boxes[bi] or not PlayerData.Boxes[bi].Creatures then return false end
            local list = PlayerData.Boxes[bi].Creatures
            if not list[si] then return false end
            table.remove(list, si)
        else
            return false
        end
        ClientData:UpdateClientData(Player, PlayerData)
        return true
    end
    if Request[1] == "RenameBox" then
        local payload = Request[2]
        if typeof(payload) ~= "table" then return false end
        local bi = tonumber(payload.BoxIndex)
        local name = payload.Name
        if not bi or type(name) ~= "string" then return false end
        local PlayerData = ClientData:Get(Player)
        if not PlayerData or not PlayerData.Boxes or not PlayerData.Boxes[bi] then return false end
        -- Filter incoming name for safety
        local filtered = ServerFunctions:FilterName(Player, name)
        if type(filtered) ~= "string" or filtered == "" then return false end
        -- Ensure new-schema box wrapper
        if typeof(PlayerData.Boxes[bi]) == "table" and PlayerData.Boxes[bi].Creatures == nil then
            PlayerData.Boxes[bi] = { Name = tostring(PlayerData.Boxes[bi].Name or ("Box " .. tostring(bi))), Creatures = PlayerData.Boxes[bi] }
        end
        PlayerData.Boxes[bi].Name = filtered
        ClientData:UpdateClientData(Player, PlayerData)
        return true
    end
    if Request[1] == "DesyncBox" then
        local payload = Request[2]
        if typeof(payload) ~= "table" then return false end
        local bi = tonumber(payload.BoxIndex)
        if not bi then return false end
        local PlayerData = ClientData:Get(Player)
        if not PlayerData or not PlayerData.Boxes or not PlayerData.Boxes[bi] then return false end
        -- Ensure new-schema box wrapper
        if typeof(PlayerData.Boxes[bi]) == "table" and PlayerData.Boxes[bi].Creatures == nil then
            PlayerData.Boxes[bi] = { Name = tostring(PlayerData.Boxes[bi].Name or ("Box " .. tostring(bi))), Creatures = PlayerData.Boxes[bi] }
        end
        PlayerData.Boxes[bi].Creatures = {}
        ClientData:UpdateClientData(Player, PlayerData)
        return true
    end
    if Request[1] == "UpdateVaultBoxes" then
        local payload = Request[2]
        if typeof(payload) ~= "table" then return false end
        local desiredBoxes = payload.Boxes -- array of { Name, Creatures }
        local desiredParty = payload.Party
        local PlayerData = ClientData:Get(Player)
        if not PlayerData then return false end
        PlayerData.Boxes = PlayerData.Boxes or {}
        PlayerData.Party = PlayerData.Party or {}
        
        -- Validate box count based on Vault+ ownership
        local VAULTPLUS_GAMEPASS_ID = 1656816296
        local success, ownsGamepass = pcall(function()
            return MarketplaceService:UserOwnsGamePassAsync(Player.UserId, VAULTPLUS_GAMEPASS_ID)
        end)
        local maxBoxes = (success and ownsGamepass) and 50 or 8
        
        -- Ensure player doesn't exceed their allowed box count
        if typeof(desiredBoxes) == "table" and #desiredBoxes > maxBoxes then
            DBG:warn("[UpdateVaultBoxes] Player", Player.Name, "attempted to use", #desiredBoxes, "boxes but only allowed", maxBoxes)
            -- Truncate to allowed count
            while #desiredBoxes > maxBoxes do
                table.remove(desiredBoxes)
            end
        end

        -- Build pool of current creatures keyed by a fingerprint
        local function fp(c)
            if typeof(c) ~= "table" then return "" end
            local caught = c.CatchData or {}
            local key = table.concat({ tostring(c.Name), tostring(c.Level), tostring(c.Gender), tostring(c.Shiny), tostring(c.Nickname or ""), tostring(c.OT or ""), tostring(caught.CaughtWhen or 0), tostring(caught.CaughtBy or "") }, "|")
            return key
        end
        local pool: {[string]: {any}} = {}
        local function addPool(c)
            local k = fp(c)
            pool[k] = pool[k] or {}
            table.insert(pool[k], c)
        end
        for _, c in ipairs(PlayerData.Party) do addPool(c) end
        for _, box in ipairs(PlayerData.Boxes) do
            if typeof(box) == "table" and typeof(box.Creatures) == "table" then
                for _, c in ipairs(box.Creatures) do addPool(c) end
            end
        end

        local function takeFromPool(k)
            local arr = pool[k]
            if not arr or #arr == 0 then return nil end
            return table.remove(arr, 1)
        end

        -- Helper to reconstruct list from desired list of creature tables by fingerprint
        local function buildListFromDesired(desiredList, cap)
            local out = {}
            local count = 0
            if typeof(desiredList) ~= "table" then return out end
            -- Use numeric for loop instead of ipairs to handle nil values properly
            -- For party, cap is 6; for boxes, cap is 30
            local maxIndex = cap or 6
            for i = 1, maxIndex do
                local c = desiredList[i]
                if c == nil then
                    -- Preserve nil slots (empty slots) - explicitly set to nil to maintain slot positions
                    out[i] = nil
                else
                    local k = fp(c)
                    local srv = takeFromPool(k)
                    if not srv then
                        return nil -- invalid payload (creature not in pool)
                    end
                    out[i] = srv
                    count += 1
                end
            end
            return out
        end

        -- Rebuild party and compact it (remove nil gaps, empty slots only at end)
        local newPartyRaw = buildListFromDesired(desiredParty, 6) or {}
        -- Compact party array: remove nil gaps so empty slots are only at the end
        local newParty = {}
        local count = 0
        for i = 1, 6 do
            if newPartyRaw[i] ~= nil then
                count += 1
                newParty[count] = newPartyRaw[i]
            end
        end
        -- Rebuild boxes
        local newBoxes = {}
        if typeof(desiredBoxes) == "table" then
            for i, box in ipairs(desiredBoxes) do
                if typeof(box) ~= "table" or typeof(box.Creatures) ~= "table" then
                    DBG:warn("[UpdateVaultBoxes] Invalid box entry from", Player.Name, "at", i)
                    return false
                end
                local built = buildListFromDesired(box.Creatures, 30)
                if not built then
                    DBG:warn("[UpdateVaultBoxes] Invalid box contents from", Player.Name, "at", i)
                    return false
                end
                -- Preserve existing Background if present server-side
                local existingBg = nil
                if PlayerData.Boxes and PlayerData.Boxes[i] and typeof(PlayerData.Boxes[i]) == "table" then
                    existingBg = PlayerData.Boxes[i].Background
                end
                newBoxes[i] = { Name = tostring(box.Name or ("Box " .. tostring(i))), Creatures = built, Background = existingBg }
            end
        else
            -- Keep as-is
            for i, box in ipairs(PlayerData.Boxes) do
                newBoxes[i] = { Name = tostring(box.Name or ("Box " .. tostring(i))), Creatures = box.Creatures or {}, Background = box.Background }
            end
        end

        -- If any pool entries remain, append them back into boxes to avoid loss
        for k, arr in pairs(pool) do
            for _, c in ipairs(arr) do
                -- Find first box with room
                local placed = false
                for i = 1, math.max(#newBoxes, 1) do
                    newBoxes[i] = newBoxes[i] or { Name = "Box " .. tostring(i), Creatures = {} }
                    if #newBoxes[i].Creatures < 30 then
                        table.insert(newBoxes[i].Creatures, c)
                        placed = true
                        break
                    end
                end
                if not placed then
                    table.insert(newBoxes, { Name = "Box " .. tostring(#newBoxes + 1), Creatures = { c } })
                end
            end
        end

        PlayerData.Party = newParty
        PlayerData.Boxes = newBoxes
        
        -- Ensure box count matches ownership (add empty boxes if needed)
        if #PlayerData.Boxes < maxBoxes then
            for i = #PlayerData.Boxes + 1, maxBoxes do
                PlayerData.Boxes[i] = { Name = "Box " .. tostring(i), Creatures = {} }
            end
        end
        
        ClientData:UpdateClientData(Player, PlayerData)
        return true
    end
    if Request[1] == "SetBoxBackground" then
        local payload = Request[2]
        if typeof(payload) ~= "table" then return false end
        local bi = tonumber(payload.BoxIndex)
        local bg = payload.Background
        if not bi or (type(bg) ~= "string" and type(bg) ~= "number") then return false end
        local PlayerData = ClientData:Get(Player)
        if not PlayerData or not PlayerData.Boxes or not PlayerData.Boxes[bi] then return false end
        -- Ensure new-schema wrapper
        if typeof(PlayerData.Boxes[bi]) == "table" and PlayerData.Boxes[bi].Creatures == nil then
            PlayerData.Boxes[bi] = { Name = tostring(PlayerData.Boxes[bi].Name or ("Box " .. tostring(bi))), Creatures = PlayerData.Boxes[bi] }
        end
        PlayerData.Boxes[bi].Background = tostring(bg)
        ClientData:UpdateClientData(Player, PlayerData)
        return true
    end
    if Request[1] == "OpenVault" then
        -- Port-A-Vault gamepass ID
        local PORTAVAULT_GAMEPASS_ID = 1656188952
        
        -- Validate gamepass ownership server-side
        local success, ownsGamepass = pcall(function()
            return MarketplaceService:UserOwnsGamePassAsync(Player.UserId, PORTAVAULT_GAMEPASS_ID)
        end)
        
        if success and ownsGamepass then
            return true
        else
            DBG:warn("[OpenVault] Player", Player.Name, "attempted to open vault without Port-A-Vault gamepass")
            return false
        end
    end
    if Request[1] == "MysteryTradeStart" then
        local canStartOk, canStart, reason = pcall(function()
            return MysteryTradeService:CanStartTrade(Player)
        end)
        if not canStartOk then
            DBG:warn("[MysteryTradeStart] Error in CanStartTrade:", canStart)
            return { Success = false, Message = "Unable to check trade status." }
        end
        if not canStart then
            DBG:print("[MysteryTradeStart] Cannot start trade:", reason)
            return { Success = false, Message = reason }
        end
        local searchOk, searchSuccess, searchReason = pcall(function()
            return MysteryTradeService:StartSearch(Player)
        end)
        if not searchOk then
            DBG:warn("[MysteryTradeStart] Error in StartSearch:", searchSuccess)
            return { Success = false, Message = "Unable to start search. Please try again." }
        end
        if not searchSuccess then
            DBG:warn("[MysteryTradeStart] StartSearch returned false:", searchReason)
            return { Success = false, Message = searchReason or "Unable to start search." }
        end
        DBG:print("[MysteryTradeStart] Successfully started search for", Player.Name)
        return { Success = true }
    end
    if Request[1] == "MysteryTradeCancel" then
        local payload = Request[2]
        local sessionId = payload and payload.SessionId
        if sessionId then
            MysteryTradeService:CancelSession(sessionId, "Cancelled by player.")
        else
            MysteryTradeService:CancelSearch(Player, "Cancelled by player.")
        end
        return { Success = true }
    end
    if Request[1] == "MysteryTradeSelectCreature" then
        local payload = Request[2]
        if typeof(payload) ~= "table" then
            return { Success = false, Message = "Invalid payload." }
        end
        local sessionId = payload.SessionId
        local creature = payload.Creature
        local location = payload.Location
        if not sessionId or not creature or not location then
            return { Success = false, Message = "Missing required fields." }
        end
        local ok, reason = MysteryTradeService:SelectCreature(Player, sessionId, creature, location)
        if not ok then
            return { Success = false, Message = reason or "Unable to select creature." }
        end
        return { Success = true }
    end
    if Request[1] == "MysteryTradeConfirm" then
        local payload = Request[2]
        if typeof(payload) ~= "table" then
            return { Success = false, Message = "Invalid payload." }
        end
        local sessionId = payload.SessionId
        if not sessionId then
            return { Success = false, Message = "Missing session ID." }
        end
        local ok, reason = MysteryTradeService:ConfirmTrade(Player, sessionId)
        if not ok then
            return { Success = false, Message = reason or "Unable to confirm trade." }
        end
        return { Success = true }
    end
    if Request[1] == "FinalizeCapture" then
        -- Payload: { Nickname = string?, Destination = "Party"|"Box", SwapIndex = number? }
        local payload = Request[2]
        if typeof(payload) ~= "table" then return false end
        local nickname = payload.Nickname
        local destination = payload.Destination
        local swapIndex = payload.SwapIndex
        local ClientData = require(ServerScriptService.Server.ClientData)
        local PlayerData = ClientData:Get(Player)
        if not PlayerData or not PlayerData.PendingCapture then
            return false
        end
        local captured = PlayerData.PendingCapture
        -- Optional nickname filtering
        if type(nickname) == "string" and nickname ~= "" then
            local filtered = ServerFunctions:FilterName(Player, nickname)
            if filtered and typeof(filtered) == "string" then
                captured.Nickname = filtered
            end
        end
        -- Place creature in party or box securely
        local placed = false
        if destination == "Party" then
            PlayerData.Party = PlayerData.Party or {}
            local partyLen = #PlayerData.Party
            if partyLen < 6 then
                table.insert(PlayerData.Party, captured)
                placed = true
            elseif typeof(swapIndex) == "number" and swapIndex >= 1 and swapIndex <= 6 and PlayerData.Party[swapIndex] ~= nil then
                PlayerData.Party[swapIndex] = captured
                placed = true
            end
        elseif destination == "Box" then
            PlayerData.Boxes = PlayerData.Boxes or {}
            -- Ensure at least 8 boxes exist (new schema only)
            if #PlayerData.Boxes < 8 then
                for i = #PlayerData.Boxes + 1, 8 do
                    PlayerData.Boxes[i] = { Name = "Box " .. tostring(i), Creatures = {} }
                end
            end
            -- If any legacy arrays slipped in, wrap them
            for i, b in ipairs(PlayerData.Boxes) do
                if type(b) == "table" and b.Creatures == nil then
                    -- b is legacy array; wrap into new schema
                    PlayerData.Boxes[i] = { Name = "Box " .. tostring(i), Creatures = b }
                end
            end
            -- Find first available slot
            for bi = 1, #PlayerData.Boxes do
                local box = PlayerData.Boxes[bi]
                local list = (type(box) == "table" and box.Creatures) or {}
                if #list < 30 then
                    table.insert(list, captured)
                    placed = true
                    break
                end
            end
        end
        if not placed then
            return false
        end
        
        -- Mark creature as seen (caught implies seen)
        if captured and captured.Name then
            PlayerData.SeenCreatures = PlayerData.SeenCreatures or {}
            if not PlayerData.SeenCreatures[captured.Name] then
                PlayerData.SeenCreatures[captured.Name] = true
                DBG:print("[Seen] Marked", captured.Name, "as seen (captured)")
            end
        end
        
        -- Clear pending capture and persist
        PlayerData.PendingCapture = nil
        if ClientData.UpdateClientData then
            ClientData:UpdateClientData(Player, PlayerData)
        end
        
        -- Update challenge progress for capture
        pcall(function()
            ChallengesSystem.UpdateProgress(Player, "CaptureCreatures", 1)
            ChallengesSystem.UpdateProgress(Player, "CaptureUniqueTypes", 0, {})
        end)
        
        -- Event-based save for successful capture finalization ONLY if AutoSave is enabled and not during cutscenes
        local allowAuto = (PlayerData.Settings and PlayerData.Settings.AutoSave) == true and (PlayerData.InCutscene ~= true)
        if allowAuto then
            _saveNow(Player)
        end
        return true
    end
	if Request[1] == "EndBattle" then
		-- Client requests to end battle after faint animation completes
		if ActiveBattles[Player] then
			-- Send battle over event to client
			Events.Communicate:FireClient(Player, "BattleOver", {
				Reason = "Win",
				Rewards = {
					XP = 0, -- XP was already processed
					Studs = 0
				}
			})
			
			-- Clear battle data
			ServerFunctions:ClearBattleData(Player)
			return true
		end
		return false
	end
    if Request[1] == "SwitchCreature" then
		DBG:print("=== SWITCH CREATURE REQUEST ===")
		DBG:print("Player:", Player.Name)
        local payload = Request[2]
        local creatureIndex = typeof(payload) == "table" and payload.Index or payload
        local isPreviewSwitch = typeof(payload) == "table" and payload.IsPreviewSwitch
        DBG:print("Request[2] (creatureIndex):", creatureIndex)
        DBG:print("Request[2] type:", typeof(payload))
        DBG:print("IsPreviewSwitch:", isPreviewSwitch)
		DBG:print("=== END SWITCH CREATURE REQUEST ===")
        
        -- Check if this is a preview switch
            local b = ActiveBattles[Player]
        if isPreviewSwitch then
            -- Validate that preview switch is allowed
            if not b or not b.AllowPreviewSwitch then
                DBG:warn("Preview switch not allowed for", Player.Name)
                return false
            end
            DBG:print("[SwitchPreview] Preview switch authorized - clearing flag")
            b.AllowPreviewSwitch = false -- Clear flag after use
            -- Mark that this SwitchCreature call is a reaction to a SwitchPreview
            b.PreviewSwitchInProgress = true
            return ServerFunctions:SwitchCreature(Player, creatureIndex)
        end
        
        -- Normal switch - check TurnId
        if typeof(payload) == "table" and type(payload.TurnId) == "number" then
            local current = b and (b.TurnId or 0) or 0
            local clientTurn = payload.TurnId
            if not b or current ~= clientTurn then
                DBG:warn("TurnId mismatch on SwitchCreature from", Player.Name, "client:", clientTurn, "server:", current)
                return false
            end
        end

        -- PvP: buffer switch as an action instead of executing immediately
        if b and b.Type == "PvP" then
            if type(creatureIndex) ~= "number" then
                DBG:warn("Invalid PvP switch payload from", Player.Name)
                return false
            end
            b.PlayerAction = { Type = "Switch", Slot = creatureIndex }
            return ServerFunctions:ProcessTurn(Player)
        end
        return ServerFunctions:SwitchCreature(Player, creatureIndex)
	end
	
	if Request[1] == "ProcessDeferredTrainerSendOut" then
		DBG:print("[ProcessDeferredTrainerSendOut] Request received from", Player.Name)
		return ServerFunctions:ProcessDeferredTrainerSendOut(Player)
	end

    if Request[1] == "ReorderParty" then
        local order = Request[2]
        if typeof(order) ~= "table" then return false end
        -- Block reordering while in battle
        if ActiveBattles[Player] then
            DBG:warn("Rejecting ReorderParty during active battle for", Player.Name)
            return false
        end
        local PlayerData = ClientData:Get(Player)
        if not PlayerData or not PlayerData.Party then return false end
        local party = PlayerData.Party
        local n = #party
        -- Validate order: length match, values 1..n unique
        local seen: {[number]: boolean} = {}
        local count = 0
        for i, idx in ipairs(order) do
            if type(idx) ~= "number" or idx < 1 or idx > n or seen[idx] then
                DBG:warn("Invalid reorder payload from", Player.Name)
                return false
            end
            seen[idx] = true
            count += 1
        end
        if count ~= n then return false end
        
        -- Track which slot was spawned before reorder
        local oldSpawnedSlot = CreatureSpawnService.GetSpawnedSlotIndex(Player)
        
        -- Apply reorder
        local newParty = {}
        for i = 1, n do
            newParty[i] = party[order[i]]
        end
        PlayerData.Party = newParty
        
        -- Check all party creatures for fainted status and despawn if needed
        -- This will handle the spawned creature if it's fainted
        CreatureSpawnService.CheckAndDespawnFaintedCreatures(Player)
        
        -- Persist and replicate
        if ClientData.UpdateClientData then
            ClientData:UpdateClientData(Player, PlayerData)
        end
        return true
    end
	if Request[1] == "SaveItemPickup" then
		return ServerFunctions:SaveItemPickup(Player, Request[2], Request[3])
	end
	if Request[1] == "GetPickedUpItems" then
		return ServerFunctions:GetPickedUpItems(Player)
	end
	if Request[1] == "GetTimeOfDay" then
		return ServerFunctions:GetTimeOfDay()
	end
	if Request[1] == "GetCurrentTimePeriod" then
		return ServerFunctions:GetCurrentTimePeriod()
	end
	if Request[1] == "GetFormattedTime" then
		return ServerFunctions:GetFormattedTime()
	end
    if Request[1] == "SetCutsceneActive" then
        local active = Request[2] == true
        local PlayerData = ClientData:Get(Player)
        PlayerData.InCutscene = active and true or nil
        if ClientData.UpdateClientData then
            ClientData:UpdateClientData(Player, PlayerData)
        end
        DBG:print("SetCutsceneActive:", active, "for", Player.Name)
        return true
    end
    if Request[1] == "SetSayActive" then
        local active = Request[2] == true
        local PlayerData = ClientData:Get(Player)
        PlayerData.InSayMessage = active and true or nil
        if ClientData.UpdateClientData then
            ClientData:UpdateClientData(Player, PlayerData)
        end
        DBG:print("SetSayActive:", active, "for", Player.Name)
        return true
    end
	if Request[1] == "GrantStuds" then
		return ServerFunctions:GrantStuds(Player, Request[2])
	end
	if Request[1] == "GrantItem" then
        DBG:warn("Rejected client GrantItem request from", Player.Name)
        return false
    end
	if Request[1] == "RedeemCode" then
		local code = Request[2]
		if type(code) ~= "string" then
			return { Success = false, Message = "Invalid code format." }
		end
		local success, message = CodeRedemption.RedeemCode(Player, code)
		return { Success = success, Message = message }
	end
	if Request[1] == "GetChallenges" then
		-- Return all challenges with their current progress
		return ChallengesSystem.GetAllChallengesForPlayer(Player)
	end
	if Request[1] == "ClaimChallengeReward" then
		local challengeId = Request[2]
		if type(challengeId) ~= "string" then
			return { Success = false, Message = "Invalid challenge ID." }
		end
		local success, result = ChallengesSystem.ClaimReward(Player, challengeId)
		return { Success = success, RewardText = result }
	end
	if Request[1] == "StartBattle" then
		DBG:print("Received StartBattle request from:", Player.Name)
		DBG:print("Request[2] (BattleType):", Request[2])
		DBG:print("Request[3] (BattleData):", Request[3])
		return ServerFunctions:StartBattle(Player, Request[2], Request[3])
	end
	if Request[1] == "HandleTrainerLoss" then
		-- Calculate studs penalty similar to Pokémon (Gen 3+): floor( (Level * 4) * (BaseRewardScaling) )
		-- We'll approximate: loss = floor((highestLevelInParty * 100))
		local PlayerData = ClientData:Get(Player)
		local highestLevel = 1
		if PlayerData and PlayerData.Party then
			for _, creature in ipairs(PlayerData.Party) do
				if creature and creature.Level and creature.Level > highestLevel then
					highestLevel = creature.Level
				end
			end
		end
		-- Use a scaling factor of 50 studs per level as a placeholder
		local studsLoss = math.floor(highestLevel * 50)
		-- Deduct from player's studs safely
		PlayerData.Studs = math.max(0, (PlayerData.Studs or 0) - studsLoss)
		ClientData:UpdateClientData(Player, PlayerData)
		
		-- Clear battle data when player is defeated
		ServerFunctions:ClearBattleData(Player)
		
		return studsLoss
	end
	-- Admin action handlers
	if Request[1] == "CheckAdminPermission" then
		local level = AdminService.GetPermissionLevel(Player)
		return { Success = true, Level = level }
	end
	if Request[1] == "AdminAction" then
		-- Upfront permission check: reject unauthorized users immediately
		local permissionLevel = AdminService.GetPermissionLevel(Player)
		if permissionLevel == "None" then
			return { Success = false, Message = "You do not have permission to perform admin actions." }
		end
		
		local actionType = Request[2]
		local targetUserId = Request[3]
		local params = Request[4] or {}
		
		if actionType == "RemoveCreature" then
			local slotIndex = params.SlotIndex
			local boxIndex = params.BoxIndex
			local success, message = ServerFunctions:RemoveCreature(Player, targetUserId, slotIndex, boxIndex)
			return { Success = success, Message = message }
		elseif actionType == "CreateCreature" then
			local creatureInfo = params.CreatureInfo
			local success, message = ServerFunctions:CreateCreature(Player, targetUserId, creatureInfo)
			return { Success = success, Message = message }
		elseif actionType == "KickPlayer" then
			local reason = params.Reason
			local success, message = ServerFunctions:KickPlayer(Player, targetUserId, reason)
			return { Success = success, Message = message }
		elseif actionType == "BanPlayer" then
			local duration = params.Duration -- in seconds
			local reason = params.Reason
			local success, message = ServerFunctions:BanPlayer(Player, targetUserId, duration, reason)
			return { Success = success, Message = message }
		elseif actionType == "UnbanPlayer" then
			local success, message = ServerFunctions:UnbanPlayer(Player, targetUserId)
			return { Success = success, Message = message }
		elseif actionType == "GiveItem" then
			local itemName = params.ItemName
			local quantity = params.Quantity or 1
			local success, message = ServerFunctions:GiveItemAdmin(Player, targetUserId, itemName, quantity)
			return { Success = success, Message = message }
		elseif actionType == "SetPlayerData" then
			local field = params.Field
			local value = params.Value
			local success, message = ServerFunctions:SetPlayerData(Player, targetUserId, field, value)
			return { Success = success, Message = message }
		elseif actionType == "StartEncounter" then
			local battleData = params.BattleData
			local chunkName = params.ChunkName
			local success, message = ServerFunctions:StartEncounterForPlayer(Player, targetUserId, battleData, chunkName)
			return { Success = success, Message = message }
		else
			return { Success = false, Message = "Unknown admin action: " .. tostring(actionType) }
		end
	end
	if Request[1] == "GetBannedPlayers" then
		local success, bans = ServerFunctions:GetBannedPlayers(Player)
		return { Success = success, Bans = bans }
	end
	if Request[1] == "ViewPlayerData" then
		local targetUserId = Request[2]
		local success, data = ServerFunctions:ViewPlayerData(Player, targetUserId)
		if success then
			return { Success = true, Data = data }
		else
			return { Success = false, Message = data }
		end
	end
	if Request[1] == "ToggleCreatureSpawn" then
		local slotIndex = Request[2]
		if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 6 then
			return false, "Invalid slot index"
		end
		
		local PlayerData = ClientData:Get(Player)
		if not PlayerData or not PlayerData.Party then
			return false, "No party data"
		end
		
		local creature = PlayerData.Party[slotIndex]
		if not creature then
			return false, "No creature in slot"
		end
		
		local success, err = CreatureSpawnService.ToggleCreatureSpawn(Player, slotIndex, creature)
		return success, err
	end
	
	if Request[1] == "UpdateCreatureAnimation" then
		return CreatureSpawnService.UpdateCreatureAnimation(Player, Request[2] == true)
	end
	
	if Request[1] == "ViewPlayerInfo" then
		local targetUserId = Request[2]
		if type(targetUserId) ~= "number" then
			return nil
		end
		return ServerFunctions:GetViewPlayerInfo(Player, targetUserId)
	end
	
	-- Catch-all for unhandled requests
	DBG:warn("Unhandled request type:", Request[1], "from player:", Player.Name)
	return false, "Unhandled request type: " .. tostring(Request[1])
end

-- Handle player leaving - clear server-side battle state only (position saved on CharacterRemoving)
Players.PlayerRemoving:Connect(function(Player: Player)
	DBG:print("Player leaving:", Player.Name, "- clearing battle state")
	ServerFunctions:ClearBattleData(Player)
	
	-- Clean up pending move replacement prompts to prevent memory leak
	if _pendingMoveReplace[Player] then
		_pendingMoveReplace[Player] = nil
		DBG:print("Cleared pending move replace prompts for player:", Player.Name)
	end
	
	-- Clean up spawned creature model and tracking
	CreatureSpawnService.CleanupPlayer(Player)
	-- End PvP for opponent if needed
	for p, battle in pairs(ActiveBattles) do
		if battle.Type == "PvP" and (battle.OpponentPlayer == Player or p == Player) then
			-- Determine who should receive the message (the opponent of the leaving player)
			local opponentToNotify
			local battleToUse = battle
			
			if battle.OpponentPlayer == Player then
				-- Leaving player is the opponent, so notify the battle owner
				opponentToNotify = p
			elseif p == Player then
				-- Leaving player is the battle owner, so notify the opponent
				opponentToNotify = battle.OpponentPlayer
			end
			
			local leavingPlayerName = Player.DisplayName or Player.Name
			
			-- Send battle message to opponent before ending
			local Events = game.ReplicatedStorage.Events
			if Events and Events.Communicate and opponentToNotify and opponentToNotify.Parent and battleToUse then
				local hpData = {
					Player = battleToUse.PlayerCreature and battleToUse.PlayerCreature.Stats and battleToUse.PlayerCreature.Stats.HP or 0,
					PlayerMax = battleToUse.PlayerCreature and battleToUse.PlayerCreature.MaxStats and battleToUse.PlayerCreature.MaxStats.HP or 0,
					Enemy = battleToUse.FoeCreature and battleToUse.FoeCreature.Stats and battleToUse.FoeCreature.Stats.HP or 0,
					EnemyMax = battleToUse.FoeCreature and battleToUse.FoeCreature.MaxStats and battleToUse.FoeCreature.MaxStats.HP or 0,
				}
				local turnResult = {
					Friendly = {
						{ Type = "Message", Message = leavingPlayerName .. " has left the match. The battle will now end.", IsPlayer = true }
					},
					Enemy = {},
					HP = hpData,
					PlayerCreature = battleToUse.PlayerCreature,
					FoeCreature = battleToUse.FoeCreature,
					TurnId = (battleToUse.TurnId or 0) + 1,
					BattleEnd = true,
				}
				DBG:print("[PvP] Sending opponent left message to", opponentToNotify.Name)
				Events.Communicate:FireClient(opponentToNotify, "TurnResult", turnResult)
				-- Wait a moment for message to display before ending battle
				task.wait(2)
			end
			ServerFunctions:EndBattle(p, "Win")
		end
	end
end)

-- Execute player move and process enemy turn
function ServerFunctions:ExecuteMove(Player, MoveData)
	local success = BattleSystem.ExecuteMove(Player, MoveData)
	if not success then
		return false
	end
	return ServerFunctions:ProcessTurn(Player)
end

-- Determine turn order based on speed and priority (Pokemon-style)
function ServerFunctions:DetermineTurnOrder(battle, playerAction, enemyAction)
    local playerCreature = battle.PlayerCreature
    local foeCreature = battle.FoeCreature
    
    -- Get move priorities
    local playerPriority = 0
    local enemyPriority = 0
    
    -- Item usage should act with high priority (player input resolves before enemy move)
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
    
    -- Apply stat stage modifiers to speed (must be done before status/ability modifiers)
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
    
    -- Sand Speed: 2x Speed in Sandstorm
    -- Swift Current: 2x Speed in Rain
    if pAbil then
        local a = string.lower(pAbil)
        if a == "sand speed" and battle.Weather == "Sandstorm" then playerSpeed *= 2 end
        if a == "swift current" and battle.Weather == "Rain" then playerSpeed *= 2 end
        if a == "steadspeed" then
             -- Prevent lowering (not relevant for calculation, but nice to know)
        end
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
            -- Same speed, random (Pokemon behavior)
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

-- Execute a single action and return the result
function ServerFunctions:ExecuteAction(Player, actionData, battle)
    local action = actionData.Action
    local isPlayer = actionData.IsPlayer
    
    if action.Type == "Move" then
        return BattleSystem.ExecuteMoveAction(Player, action, battle, isPlayer)
    elseif action.Type == "Switch" then
        return BattleSystem.ExecuteSwitchAction(Player, action, battle, isPlayer)
    elseif action.Type == "Capture" then
        -- Drive capture scan steps; server already computed outcome in UseItem
        local foe = battle.FoeCreature
        local foeName = foe and (foe.Nickname or foe.Name) or "Wild"
        -- Build three scan steps as Damage-like flashes on foe
        local steps = {}
        table.insert(steps, {Type = "Message", Message = "You used a capture cube." , IsPlayer = true})
        table.insert(steps, {Type = "Message", Message = string.format("It's attempting to scan the wild %s!", foeName), IsPlayer = true})
        local scans = action.Scans or {false,false,false}
        for i = 1, 3 do
            local okScan = scans[i] == true
            -- Include per-scan success so client can colorize (red on failure)
            table.insert(steps, {Type = "CaptureScan", Success = okScan, IsPlayer = true})
            if not okScan then
                -- Early fail: include the failed scan then stop
                break
            end
        end
        if battle.CaptureSuccess then
            -- Final capture success: show custom success message and despawn hologram (no faint text)
            table.insert(steps, {Type = "CaptureSuccess", Creature = foeName, IsPlayer = true})
            -- Mark capture complete so the server ends the battle cleanly after sending TurnResult
            battle.CaptureCompleted = true
        else
            -- Failure message; enemy will move as usual by turn flow
            local failVariants = {"Agh! Almost had it!", "Ah! It was so close!"}
            table.insert(steps, {Type = "Message", Message = failVariants[math.random(1, #failVariants)], IsPlayer = true})
        end
        -- Ensure messages drain before proceeding to enemy action
        table.insert(steps, {Type = "WaitDrain"})
        return steps
    elseif action.Type == "Item" then
        -- Items are already applied via UseItem; return a Heal step so the client can sequence and wait
        local amount = tonumber(action.Healed) or 0
        return {Type = "Heal", Amount = amount, IsPlayer = isPlayer}
    end
    
    -- Default fallback
    return {Type = "Message", Message = "Unknown action type"}
end

-- Execute a move action
function ServerFunctions:ExecuteMoveAction(Player, action, battle, isPlayer)
    local attacker = isPlayer and battle.PlayerCreature or battle.FoeCreature
    local defender = isPlayer and battle.FoeCreature or battle.PlayerCreature
    local moveName = action.Move
    local Abilities = require(game:GetService("ReplicatedStorage").Shared.Abilities)
    local StatusModule = require(game:GetService("ReplicatedStorage").Shared.Status)
    
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
    
    -- Check volatile status conditions (Confusion, Infatuation, Flinch)
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
    
    -- Self-heal moves: if move defines HealsPercent, apply heal instead of damage
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
        -- Queue move used + heal event
        return prependWakeUpMessage({
            { Type = "Move", Move = moveName, Actor = attacker.Name or "You", IsPlayer = isPlayer },
            { Type = "Heal", Amount = healed, IsPlayer = isPlayer, Message = string.format("%s perched and recovered HP!", attacker.Nickname or attacker.Name) }
        })
    end

    -- Check accuracy before dealing damage
    -- Get stat stages (default to 0 if not tracked)
    local accuracyStage = (attacker.StatStages and attacker.StatStages.Accuracy) or 0
    local evasionStage = (defender.StatStages and defender.StatStages.Evasion) or 0
    
    -- Pass attacker to CheckAccuracy for ability checks (e.g. Recon Flight)
    local hit = DamageCalculator.CheckAccuracy(moveName, accuracyStage, evasionStage, attacker)
    if not hit then
        -- Move missed - return miss step only (don't include Move step to prevent double execution)
        local missMessage = isPlayer and "The foe avoided the attack!" or "Your creature avoided the attack!"
        DBG:print("[MISS]", (attacker.Nickname or attacker.Name or (isPlayer and "Player" or "Enemy")), "used", moveName, "but it missed!")
        return prependWakeUpMessage({
            { Type = "Miss", Message = missMessage, Move = moveName, Actor = attacker.Name or (isPlayer and "Your creature" or "Foe"), IsPlayer = isPlayer }
        })
    end

    -- Calculate damage
    -- Roll for critical hit using DamageCalculator (handles crit stages)
    local isCrit = DamageCalculator and DamageCalculator.RollCriticalHit(attacker, moveDef.Flags and moveDef.Flags.highCrit) or (math.random(1, 16) == 1)
    
    -- Modify moveDef temporarily for calculation if type changed
    local effectiveMoveData = moveDef
    if modifiedType ~= moveDef.Type then
        effectiveMoveData = table.clone(moveDef)
        effectiveMoveData.Type = modifiedType
    end

    local dmgRes = DamageCalculator.CalculateDamage(attacker, defender, effectiveMoveData, isCrit, nil, nil, battle.Weather)
    local damage = dmgRes.damage
    -- Optional global damage tuning (Pokémon-faithful default is 1.0)
    if not isPlayer and Config and type(Config.ENEMY_DAMAGE_MULT) == "number" and Config.ENEMY_DAMAGE_MULT ~= 1.0 then
        damage = math.max(1, math.floor(damage * Config.ENEMY_DAMAGE_MULT))
    end
    -- Derive simplified effectiveness category for client-side SFX/VFX
    local effCat = "Normal"
    local effNum = (dmgRes and type(dmgRes.effectiveness) == "number") and dmgRes.effectiveness or 1
    if effNum == 0 then
        effCat = "Immune"
    elseif effNum >= 2 then
        effCat = "Super"
    elseif effNum <= 0.5 then
        effCat = "NotVery"
    end
    
    -- Apply damage (Focus Bandage check)
    local before = defender.Stats.HP or 0
    local after = math.max(0, before - damage)
    -- Focus Bandage: sometimes leaves the holder at 1 HP instead of fainting
    do
        local held = defender.HeldItem
        -- Sturdy / Hard Head logic could go here? No, Hard Head is recoil. Sturdy is OHKO protection.
        if held and string.lower(held) == string.lower("Focus Bandage") and after <= 0 and before > 0 then
            if math.random() < 0.1 then -- 10% chance
                after = 1
                DBG:print("[HeldItem] Focus Bandage saved", defender.Name, "at 1 HP")
            end
        end
    end
    defender.Stats.HP = after
    after = defender.Stats.HP or 0
    DBG:print("[DAMAGE]", (attacker.Nickname or attacker.Name or (isPlayer and "Player" or "Enemy")), "used", moveName, "on", (defender.Nickname or defender.Name or (isPlayer and "Enemy" or "Player")), "dmg:", damage, "HP:", before, "->", after)
    
    -- Apply Recoil (if any - need move flag or similar, assuming none for now unless specified)
    -- If move has recoil flag:
    -- if moveDef.Recoil and not Abilities.NegatesRecoil(attacker) then applyRecoil() end
    -- (Implementation pending move data having Recoil field)
    
    -- Contact effects (Needle Guard, Corrosive Skin, etc.)
    -- Assuming physical moves are contact.
    -- if moveDef.Category == "Physical" or (not moveDef.Category and moveDef.Type ~= "Special") then -- Simplified check
        -- local contactEffect = Abilities.CheckContactEffect(defender)
        -- if contactEffect == "Damage" then ... end
    -- end

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

    -- Get actor name for client message generation
    local actorName = attacker.Name or (isPlayer and "Your creature" or "Foe")
    
    local result = {
        Type = "Move",
        Move = moveName,
        Actor = actorName,
        HPDelta = isPlayer and {Enemy = -damage} or {Player = -damage},
        Critical = isCrit,
        Effectiveness = effCat,
    }
    
    -- Check for faint
    -- Prepare a Damage step to carry effectiveness/message semantics to client
    -- Include per-hit NewHP so the client can update the correct side at the correct time
    -- IsPlayer indicates which creature was damaged (defender), not attacker
    local damageStep = {
        Type = "Damage",
        Effectiveness = effCat,
        IsPlayer = not isPlayer, -- Defender is opposite of attacker
        NewHP = defender.Stats and defender.Stats.HP or nil,
    }

    -- Echo Bell: heal attacker slightly on successful damage
    local steps = {result, damageStep}
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
    
    -- Apply status effects from move (if move has status effect)
    if moveDef and moveDef.StatusEffect and damage > 0 then
        local statusType = moveDef.StatusEffect
        local statusChance = moveDef.StatusChance or 100
        
        -- Validate statusType is a string (status code)
        if type(statusType) ~= "string" then
            DBG:warn("[ServerFunctions] Invalid StatusEffect type - expected string, got:", type(statusType), "Value:", statusType, "Move:", moveName)
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
                DBG:print("[ServerFunctions] Status step created - Status:", statusType, "Message:", statusMessage)
            end
        end
    end
    
    -- Apply flinch if move causes flinch (apply when move hits, regardless of damage amount)
    -- Flinch should apply whenever the move successfully hits the target
    if moveDef and moveDef.CausesFlinch and hit then
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
    
    -- Apply confusion if move causes confusion
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
        
        -- XP is now processed at battle end, not here
        -- This prevents XP from being awarded mid-battle in trainer battles
        
        table.insert(steps, faintStep)
    end
    
    return prependWakeUpMessage(steps)
end

-- Execute a switch action (placeholder for now)
function ServerFunctions:ExecuteSwitchAction(Player, action, battle, isPlayer)
    -- This would handle switching logic
    return {Type = "Message", Message = "Switch action not yet implemented"}
end

-- Use an item (battle or overworld)
function ServerFunctions:UseItem(Player, payload)
    local itemName = payload.Name
    local context = payload.Context -- "Battle" | "Overworld"
    local PlayerData = ClientData:Get(Player)
    if not PlayerData then return false end
    local Items = GameData.Items
    local itemDef = Items[itemName]
    if not itemDef then return false end

    -- Validate inventory count
    PlayerData.Items = PlayerData.Items or {}
    local count = PlayerData.Items[itemName] or 0
    if count <= 0 then return false end

    -- Validate usability in context
    local inBattle = ActiveBattles[Player] ~= nil
    if context == "Battle" and not itemDef.UsableInBattle then return false end
    if context == "Overworld" and not itemDef.UsableInOverworld then return false end
    if context == "Battle" and not inBattle then return false end

    -- Apply effects
    local function getCurrentHP(creature)
        if not creature or not creature.MaxStats then return 0, 1 end
        local maxHP = creature.MaxStats.HP or 1
        local currentHP
        -- Prefer percentage field when present; Stats.HP may hold base or stale values
        if creature.CurrentHP ~= nil then
            local pct = math.clamp(tonumber(creature.CurrentHP) or 0, 0, 100)
            currentHP = math.floor(maxHP * (pct / 100) + 0.5)
        elseif creature.Stats and creature.Stats.HP ~= nil then
            currentHP = creature.Stats.HP
        else
            currentHP = maxHP -- fallback
        end
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

    if context == "Battle" then
        local battle = ActiveBattles[Player]
        if not battle or not battle.PlayerCreature then return false end
        -- Capture Cube special handling (wild only)
        if itemName == "Capture Cube" then
            -- Enforce wild-only on server
            if (battle.Type or "Wild") ~= "Wild" then
                return false
            end
            -- Deduct item now
            PlayerData.Items[itemName] = math.max(0, count - 1)
            -- Build capture outcome using Pokemon-like formula
            local foe = battle.FoeCreature
            if not foe or not foe.MaxStats or not foe.Stats then return false end
            local maxHP = foe.MaxStats.HP or 1
            local curHP = foe.Stats.HP or maxHP
            curHP = math.clamp(curHP, 1, maxHP)
            -- Pokemon-style catch rate: higher = easier to catch (1-255 range)
            -- 255 = very easy (common wild), 45 = moderate (starters), 3 = legendary
            local catchRate = 45 -- default if not defined
            do
                local def = foe and foe.Name and (CreaturesModule and CreaturesModule[foe.Name])
                if def and type(def.CatchRateScalar) == "number" then
                    -- Use Pokemon-style value directly, clamp to valid range
                    catchRate = math.clamp(math.floor(def.CatchRateScalar), 1, 255)
                end
            end
            -- Ball bonus (1.0 for Capture Cube), Status bonus (based on foe status if available)
            local ballBonus = 1.0
            local statusBonus = 1.0
            if foe and foe.Status then
                local s = tostring(foe.Status)
                if s == "Sleep" or s == "Freeze" then
                    statusBonus = 2.5
                elseif s == "Burn" or s == "Paralysis" or s == "Poison" then
                    statusBonus = 1.5
                end
            end
            -- Use catch rate directly as Pokemon-style base rate (higher = easier)
            local baseRate = catchRate
            -- Gen3/4 style 'a' value using baseRate in place of species catch rate
            local a = math.floor(((3 * maxHP - 2 * curHP) * baseRate * ballBonus * statusBonus) / (3 * maxHP))
            if a < 1 then a = 1 end
            -- Immediate capture if a >= 255
            local scanSuccess = {false, false, false}
            local success = false
            local function roll(bthreshold)
                -- Pokemon uses 0..65535 < threshold; we simulate similarly
                local r = math.random(0, 65535)
                return r < bthreshold
            end
            if a >= 255 then
                scanSuccess = {true, true, true}
                success = true
            else
                -- Compute 'b' threshold from 'a': b = floor(1048560 / sqrt(sqrt( (16711680 / a) )))
                local denom = (16711680 / a)
                if denom < 1 then denom = 1 end
                local root4 = math.sqrt(math.sqrt(denom))
                local b = math.floor(1048560 / root4)
                -- Perform three scan checks
                success = true
                for i = 1, 3 do
                    local okScan = roll(b)
                    scanSuccess[i] = okScan
                    if not okScan then
                        success = false
                        break
                    end
                end
            end
            -- Store player action and process as a turn (priority handled in DetermineTurnOrder)
            battle.PlayerAction = { Type = "Capture", Item = itemName, Scans = scanSuccess }
            -- Authoritative: if success, mark flag and build captured instance
            battle.CaptureSuccess = success
            if success then
                -- Build captured creature instance using factory (ensures IVs, Nature, moves valid)
                local captured = CreatureFactory.CreateFromFoe(foe)
                captured.OT = Player.UserId
                captured.CatchData = { CaughtWhen = os.time(), CaughtBy = tostring(Player.UserId) }
                battle.CapturedCreature = captured
                -- Persist pending capture to player profile for security until placement
                PlayerData.PendingCapture = captured
            end
            -- Advance turn processing
            local ok = ServerFunctions:ProcessTurn(Player)
            -- Replicate updated client data (inventory change, pending capture)
            if ClientData.UpdateClientData then ClientData:UpdateClientData(Player, PlayerData) end
            return ok == true
        end
        -- Default: healing/buff items path
        local healPct = itemDef.Stats and itemDef.Stats.HP or 0
        -- Compute creature HP state reliably
        do
            local stats, maxStats = StatCalc.ComputeStats(battle.PlayerCreature.Name, battle.PlayerCreature.Level or 1, battle.PlayerCreature.IVs or {}, battle.PlayerCreature.Nature)
            battle.PlayerCreature.Stats = stats
            battle.PlayerCreature.MaxStats = maxStats
        end
        local curHP, maxHP = getCurrentHP(battle.PlayerCreature)
        if healPct > 0 and curHP >= maxHP then
            return "It won't have any effect."
        end
        local healedAmount = applyHealPercent(battle.PlayerCreature, healPct)
        -- Deduct item
        PlayerData.Items[itemName] = math.max(0, count - 1)
        -- Fire battle messages to client
        local actorName = Player.Name
        local creatureName = battle.PlayerCreature.Nickname or battle.PlayerCreature.Name
        Events.Communicate:FireClient(Player, "BattleEvent", {Type = "ItemUse", Actor = actorName, Item = itemName, Target = creatureName})
        Events.Communicate:FireClient(Player, "BattleEvent", {Type = "Heal", Creature = creatureName, Amount = healedAmount})
        -- Store player action and process as a turn
        battle.PlayerAction = { Type = "Item", Item = itemName, Healed = healedAmount }
        -- Advance turn processing
        local ok = ServerFunctions:ProcessTurn(Player)
        -- Replicate updated client data
        if ClientData.UpdateClientData then ClientData:UpdateClientData(Player, PlayerData) end
        return ok == true
    else
        -- Overworld: handle repel items first (check by name since they're in "Items" category)
        if itemName == "Focus Spray" or itemName == "Super Focus Spray" or itemName == "Max Focus Spray" then
            -- Check if another repel is already active
            PlayerData.RepelState = PlayerData.RepelState or {}
            if PlayerData.RepelState.ActiveSteps and PlayerData.RepelState.ActiveSteps > 0 then
                return "A repel effect is already active."
            end
            
            -- Get step count for this repel
            local steps = REPEL_STEPS[itemName]
            if not steps or steps <= 0 then
                return "Invalid repel item."
            end
            
            -- Activate repel
            PlayerData.RepelState.ActiveSteps = steps
            PlayerData.RepelState.ItemName = itemName
            
            -- Deduct item
            PlayerData.Items[itemName] = math.max(0, count - 1)
            
            -- Fire event to client to activate repel
            Events.Communicate:FireClient(Player, "RepelActivated", {
                Steps = steps,
                ItemName = itemName
            })
            
            -- Update client data
            if ClientData.UpdateClientData then ClientData:UpdateClientData(Player, PlayerData) end
            
            DBG:print("[ServerFunctions] Activated", itemName, "for", steps, "steps for player", Player.Name)
            return true
        end
        
        -- Overworld: handle MoveLearners (ML items)
        if itemDef.Category == "MoveLearners" then
            local party = PlayerData.Party
            if not party or #party == 0 then return "No creatures in party." end
            
            local slotIndex = payload.SlotIndex or 1
            local targetCreature = party[slotIndex]
            
            if not targetCreature then
                return "Cannot use item."
            end
            
            -- Parse move name from item name (format: "ML - [MoveName]")
            local moveName = nil
            local parts = itemName:split(" - ")
            if #parts >= 2 then
                moveName = parts[2]
            end
            
            if not moveName or moveName == "" then
                return "Invalid ML item."
            end
            
            -- Validate move exists
            if not MovesModule[moveName] then
                return "Move not found."
            end
            
            -- Check if creature can learn this move via ML (compatibility check)
            local creatureName = targetCreature.Name
            if not MoveCompatibility.canCreatureLearnMove(creatureName, moveName) then
                return string.format("%s cannot learn %s!", targetCreature.Nickname or creatureName, moveName)
            end
            
            -- Ensure CurrentMoves exists
            targetCreature.CurrentMoves = targetCreature.CurrentMoves or {}
            
            -- Check if creature already knows this move
            for _, move in ipairs(targetCreature.CurrentMoves) do
                if move == moveName then
                    return string.format("%s already knows %s!", targetCreature.Nickname or targetCreature.Name, moveName)
                end
            end
            
            -- Count non-empty move slots
            local moveCount = 0
            for i = 1, 4 do
                if targetCreature.CurrentMoves[i] and targetCreature.CurrentMoves[i] ~= "" then
                    moveCount = moveCount + 1
                end
            end
            
            -- If creature has less than 4 moves, learn directly
            if moveCount < 4 then
                -- Find first empty slot
                local emptySlot = nil
                for i = 1, 4 do
                    if not targetCreature.CurrentMoves[i] or targetCreature.CurrentMoves[i] == "" then
                        emptySlot = i
                        break
                    end
                end
                
                if emptySlot then
                    targetCreature.CurrentMoves[emptySlot] = moveName
                    -- Deduct item
                    PlayerData.Items[itemName] = math.max(0, count - 1)
                    if ClientData.UpdateClientData then ClientData:UpdateClientData(Player, PlayerData) end
                    return string.format("%s learned %s!", targetCreature.Nickname or targetCreature.Name, moveName)
                end
            end
            
            -- Creature has 4 moves, need to replace one
            -- Store pending replacement
            if not _pendingMLReplace then
                _pendingMLReplace = {}
            end
            if not _pendingMLReplace[Player] then
                _pendingMLReplace[Player] = {}
            end
            _pendingMLReplace[Player][slotIndex] = {
                Move = moveName,
                ItemName = itemName,
                ExpiresAt = os.clock() + 300 -- 5 minute expiry
            }
            
            -- Fire event to client to show replacement UI
            Events.Communicate:FireClient(Player, "MLReplacePrompt", {
                Creature = targetCreature.Nickname or targetCreature.Name,
                Move = moveName,
                CurrentMoves = targetCreature.CurrentMoves,
                SlotIndex = slotIndex
            })
            
            -- Return special response indicating replacement needed
            return "REPLACE_NEEDED"
        end
        
        -- Overworld: use item on specified creature or first party creature
        local party = PlayerData.Party
        if not party or #party == 0 then return "No creatures in party." end
        
        -- Get target slot index (default to 1 if not specified)
        local slotIndex = payload.SlotIndex or 1
        local targetCreature = party[slotIndex]
        
        if not targetCreature then
            return "Cannot use item."
        end
        
        -- Ensure stats are computed before effect checks
        do
            local stats, maxStats = StatCalc.ComputeStats(targetCreature.Name, targetCreature.Level or 1, targetCreature.IVs or {}, targetCreature.Nature)
            targetCreature.Stats = stats
            targetCreature.MaxStats = maxStats
        end
        -- Check if item would have effect (after computing MaxStats)
        local healPct = itemDef.Stats and itemDef.Stats.HP or 0
        local currentHP, maxHP = getCurrentHP(targetCreature)
        
        -- For revive items (HP = 0 in stats), check if creature is fainted
        if healPct == 0 and itemName:find("Revive") then
            if currentHP > 0 then
                return "It won't have any effect."
            end
        -- For heal items, check if already at full HP
        elseif healPct > 0 then
            if currentHP >= maxHP then
                return "It won't have any effect."
            end
        end
        
        -- Stats already computed above
        
        -- Apply heal
        local healedAmount = applyHealPercent(targetCreature, healPct)
        
        -- Deduct item
        PlayerData.Items[itemName] = math.max(0, count - 1)
        if ClientData.UpdateClientData then ClientData:UpdateClientData(Player, PlayerData) end
        
        return true
    end
end

-- Process enemy turn with AI logic
function ServerFunctions:ProcessEnemyTurn(Player, PlayerData)
	DBG:print("Processing enemy turn for", Player.Name)

	local BattleType = "Wild" 
	
	if BattleType == "Wild" then
		ServerFunctions:ProcessWildEnemyTurn(Player)
	elseif BattleType == "Trainer" then
		ServerFunctions:ProcessTrainerEnemyTurn(Player)
	end
end

-- Optimized wild encounter enemy AI (uses real move data)
function ServerFunctions:ProcessWildEnemyTurn(Player)
	local battle = ActiveBattles[Player]
	if not battle or not battle.FoeCreature or not battle.FoeCreature.CurrentMoves then
		return
	end

	-- Select random move from creature's learned moves
	local learnedMoves = battle.FoeCreature.CurrentMoves
	local selectedMove = "Tackle" -- Default fallback

	if type(learnedMoves) == "table" and #learnedMoves > 0 then
		local randomIndex = math.random(1, #learnedMoves)
		local moveEntry = learnedMoves[randomIndex]

		-- Handle different move data formats
		if type(moveEntry) == "string" then
			selectedMove = moveEntry
		elseif type(moveEntry) == "table" and moveEntry.Name then
			selectedMove = moveEntry.Name
		elseif type(moveEntry) == "table" and moveEntry.Move then
			selectedMove = moveEntry.Move
	end
end

	-- Ensure we have a valid move name
	if not selectedMove or selectedMove == "" then
		selectedMove = "Tackle"
	end

	local foeName = battle.FoeCreature.Name or "Wild creature"

	-- Build enemy action data (don't fire to client yet - bundle in TurnResult)
	-- Client generates message from Actor + Move
	return {
		Type = "Move",
		Move = selectedMove,
		Actor = foeName
	}
end

-- Optimized trainer battle enemy AI (uses real move data)
function ServerFunctions:ProcessTrainerEnemyTurn(Player)
	local battle = ActiveBattles[Player]
	if not battle or not battle.FoeCreature or not battle.FoeCreature.CurrentMoves then
		return
	end

	-- Simple AI: Always use attacking moves for now
	local decision = 1 -- Force move selection

	if decision <= 100 then
	-- Use a move from creature's learned moves
	local learnedMoves = battle.FoeCreature.CurrentMoves
	local selectedMove = "Tackle" -- Default fallback

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

	-- Ensure we have a valid move name
	if not selectedMove or selectedMove == "" then
		selectedMove = "Tackle"
	end

	local foeName = battle.FoeCreature.Name or "Trainer's creature"
	local actorName = "Trainer's " .. foeName

		-- Client generates message from Actor + Move
		return {
			Type = "Move",
			Move = selectedMove,
			Actor = actorName
		}
	else
		-- Use an item (placeholder for future implementation)
		local item = "Potion" -- Placeholder
		local message = "Trainer used " .. item .. "!"

		return {
			Type = "Item",
			Item = item,
			Message = message
		}
	end
end

-- Optimized enemy action building (unified with ProcessEnemyTurn logic)
function ServerFunctions:BuildEnemyAction(Player)
	local battle = ActiveBattles[Player]
	if battle and battle.Type == "PvP" then
		return nil
	end
	return BattleSystem.BuildEnemyAction(Player)
end

--[[
	Handles creature switching during battle
	Delegates to BattleSystem for battle logic
	@param Player The player switching creatures
	@param newCreatureSlot The party slot index to switch to (1-6)
	@return boolean, string? Success status and optional error message
]]
function ServerFunctions:SwitchCreature(Player: Player, newCreatureSlot: number): (boolean, string?)
	return BattleSystem.SwitchCreature(Player, newCreatureSlot)
end

--[[
	Processes deferred trainer SendOut after SwitchPreview completes
	This is called from the client when the player selects Yes/No in response to SwitchPreview
	@param Player The player in the battle
	@return boolean Success status
]]
function ServerFunctions:ProcessDeferredTrainerSendOut(Player: Player): boolean
	local battle = ActiveBattles[Player]
	if not battle then
		DBG:warn("[ProcessDeferredTrainerSendOut] No active battle found for", Player.Name)
		return false
	end
	
	-- Only process if this is a trainer battle with pending send-out
	if battle.Type ~= "Trainer" or not battle.PendingTrainerSendOut or not battle.NextFoeCreature then
		DBG:print("[ProcessDeferredTrainerSendOut] No deferred send-out to process for", Player.Name)
		return false
	end
	
	-- Don't process if SendOutInline is true (should be handled in ProcessTurn)
	if battle.SendOutInline then
		DBG:print("[ProcessDeferredTrainerSendOut] SendOutInline is true - should be handled in ProcessTurn")
		return false
	end
	
	DBG:print("[ProcessDeferredTrainerSendOut] Processing deferred trainer SendOut for", Player.Name)
	
	-- Clear the pending flag and promote the next foe creature
	battle.PendingTrainerSendOut = false
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
			DBG:print("[Seen] Marked", battle.FoeCreature.Name, "as seen (deferred trainer send out)")
			ClientData:UpdateClientData(Player, PlayerData)
		end
	end
	
	-- Reset stat stages for the new trainer creature
	if StatStages then
		StatStages.ResetAll(battle.FoeCreature)
		StatStages.EnsureCreatureHasStages(battle.FoeCreature)
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
		DBG:print("[HAZARD] Checking FoeHazards for deferred trainer switch-in:", battle.FoeHazards)
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
			DBG:print("[HAZARD] Added hazard step for deferred trainer switch-in:", hazardStep.Type, hazardStep.HazardType)
		end
		
		-- Update the cloned creature data with post-hazard HP
		if #hazardSteps > 0 and battle.FoeCreature.Stats then
			creatureDataClone.Stats = creatureDataClone.Stats or {}
			creatureDataClone.Stats.HP = battle.FoeCreature.Stats.HP
			DBG:print("[HAZARD] Updated trainer creature HP after hazard damage (deferred):", battle.FoeCreature.Stats.HP)
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
		_logBattleMessages("DeferredTrainerSendOut:" .. Player.Name, turnResult)
		Events.Communicate:FireClient(Player, "TurnResult", turnResult)
	end
	
	return true
end

-- Day/Night Cycle access functions

--[[
	Admin Functions
]]

-- Remove creature from player's party or box
function ServerFunctions:RemoveCreature(admin: Player, targetUserId: number, slotIndex: number, boxIndex: number?)
	if not AdminService.CanPerformAction(admin, "RemoveCreature") then
		return false, "You do not have permission to remove creatures."
	end
	
	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer then
		return false, "Target player not found in game."
	end
	
	local targetData = ClientData:Get(targetPlayer)
	if not targetData then
		return false, "Target player data not found."
	end
	
	if boxIndex then
		-- Remove from box
		if not targetData.Boxes or not targetData.Boxes[boxIndex] then
			return false, "Invalid box index."
		end
		local box = targetData.Boxes[boxIndex]
		if type(box) == "table" and box.Creatures then
			if slotIndex < 1 or slotIndex > #box.Creatures then
				return false, "Invalid slot index."
			end
			table.remove(box.Creatures, slotIndex)
		else
			-- Legacy box format
			if slotIndex < 1 or slotIndex > #box then
				return false, "Invalid slot index."
			end
			table.remove(box, slotIndex)
		end
	else
		-- Remove from party
		if not targetData.Party or slotIndex < 1 or slotIndex > #targetData.Party then
			return false, "Invalid party slot index."
		end
		table.remove(targetData.Party, slotIndex)
	end
	
	ClientData:UpdateClientData(targetPlayer, targetData)
	_saveNow(targetPlayer)
	
	return true, "Creature removed successfully."
end

-- Create and give creature to player
function ServerFunctions:CreateCreature(admin: Player, targetUserId: number, creatureInfo: any)
	if not AdminService.CanPerformAction(admin, "CreateCreature") then
		return false, "You do not have permission to create creatures."
	end
	
	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer then
		return false, "Target player not found in game."
	end
	
	local targetData = ClientData:Get(targetPlayer)
	if not targetData then
		return false, "Target player data not found."
	end
	
	-- Set OT to target player's UserId if not specified
	if not creatureInfo.OT then
		creatureInfo.OT = targetPlayer.UserId
	end
	
	-- Create creature using CreatureFactory
	local creature = CreatureFactory.CreateFromInfo(creatureInfo)
	if type(creature) == "string" then
		return false, creature -- Error message from factory
	end
	
	-- Determine placement
	local placement = creatureInfo.Placement
	local destType = placement and placement.Type or "Auto"
	local slot = placement and placement.Slot
	local boxIdx = placement and placement.Box

	local message = "Creature created successfully."

	-- Helper: Place in party
	local function placeInParty(c, idx)
		if not targetData.Party then targetData.Party = {} end
		if idx and idx >= 1 and idx <= 6 then
			if targetData.Party[idx] then
				-- Swap: Move existing to box
				local old = targetData.Party[idx]
				-- Find box slot for old
				local placedOld = false
				if not targetData.Boxes then targetData.Boxes = {} end
				for i = 1, 8 do targetData.Boxes[i] = targetData.Boxes[i] or {Name="Box "..i, Creatures={}} end
				for _, b in ipairs(targetData.Boxes) do
					if #b.Creatures < 30 then
						table.insert(b.Creatures, old)
						placedOld = true
						break
					end
				end
				if not placedOld then return false, "No space in boxes for swapped creature." end
			end
			targetData.Party[idx] = c
			return true, "Placed in party slot " .. idx .. " (swapped if occupied)."
		else
			if #targetData.Party < 6 then
				table.insert(targetData.Party, c)
				return true, "Added to party."
			else
				return false, "Party full."
			end
		end
	end

	-- Helper: Place in box
	local function placeInBox(c, bIdx, sIdx)
		if not targetData.Boxes then targetData.Boxes = {} end
		for i = 1, 8 do targetData.Boxes[i] = targetData.Boxes[i] or {Name="Box "..i, Creatures={}} end
		
		if bIdx and targetData.Boxes[bIdx] then
			local box = targetData.Boxes[bIdx]
			if sIdx and sIdx >= 1 and sIdx <= 30 then
				-- Specific slot
				if box.Creatures[sIdx] then
					-- Swap / Overwrite? Let's just move old to next free slot for safety
					local old = box.Creatures[sIdx]
					-- try to find place for old
					local placedOld = false
					for _, b in ipairs(targetData.Boxes) do
						if #b.Creatures < 30 then
							table.insert(b.Creatures, old)
							placedOld = true
							break
						end
					end
					if not placedOld then return false, "No space for displaced creature." end
				end
				box.Creatures[sIdx] = c
				return true, "Placed in Box " .. bIdx .. " Slot " .. sIdx
			else
				-- Next free in specific box
				if #box.Creatures < 30 then
					table.insert(box.Creatures, c)
					return true, "Added to Box " .. bIdx
				else
					return false, "Box " .. bIdx .. " is full."
				end
			end
		else
			-- Find first free box
			for i, b in ipairs(targetData.Boxes) do
				if #b.Creatures < 30 then
					table.insert(b.Creatures, c)
					return true, "Added to Box " .. i
				end
			end
			return false, "All boxes full."
		end
	end

	local success = false
	local msg = ""

	if destType == "Party" then
		success, msg = placeInParty(creature, slot)
		if not success then
			-- Fallback to box
			success, msg = placeInBox(creature)
			if success then msg = "Party full/invalid, added to box." end
		end
	elseif destType == "Box" then
		success, msg = placeInBox(creature, boxIdx, slot)
	else -- Auto
		-- Try party first, then box
		local pSuccess, pMsg = placeInParty(creature)
		if pSuccess then
			success = true
			msg = pMsg
		else
			success, msg = placeInBox(creature)
		end
	end

	if not success then
		return false, msg or "Failed to place creature (storage full?)"
	end
	
	ClientData:UpdateClientData(targetPlayer, targetData)
	_saveNow(targetPlayer)
	
	return true, msg
end

-- Kick a player
function ServerFunctions:KickPlayer(admin: Player, targetUserId: number, reason: string?)
	if not AdminService.CanPerformAction(admin, "KickPlayer") then
		return false, "You do not have permission to kick players."
	end
	
	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer then
		return false, "Target player not found in game."
	end
	
	local kickMessage = "You have been kicked"
	if reason then
		kickMessage = kickMessage .. ". Reason: " .. reason
	end
	
	targetPlayer:Kick(kickMessage)
	return true, "Player kicked successfully."
end

-- Ban a player
function ServerFunctions:BanPlayer(admin: Player, targetUserId: number, duration: number?, reason: string?)
	if not AdminService.CanPerformAction(admin, "BanPlayer") then
		return false, "You do not have permission to ban players."
	end
	
	local success, message = AdminService.BanPlayer(admin, targetUserId, duration, reason)
	return success, message
end

-- Unban a player
function ServerFunctions:UnbanPlayer(admin: Player, targetUserId: number)
	if not AdminService.CanPerformAction(admin, "UnbanPlayer") then
		return false, "You do not have permission to unban players."
	end
	
	local success, message = AdminService.UnbanPlayer(admin, targetUserId)
	return success, message
end

-- View player data (read-only)
function ServerFunctions:ViewPlayerData(admin: Player, targetUserId: number)
	if not AdminService.CanPerformAction(admin, "ViewPlayerData") then
		return false, "You do not have permission to view player data."
	end
	
	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer then
		return false, "Target player not found in game."
	end
	
	local targetData = ClientData:Get(targetPlayer)
	if not targetData then
		return false, "Target player data not found."
	end
	
	-- Return a sanitized copy (remove sensitive data if needed)
	return true, table.clone(targetData)
end

-- Give item to player
function ServerFunctions:GiveItemAdmin(admin: Player, targetUserId: number, itemName: string, quantity: number)
	if not AdminService.CanPerformAction(admin, "GiveItem") then
		return false, "You do not have permission to give items."
	end
	
	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer then
		return false, "Target player not found in game."
	end
	
	quantity = quantity or 1
	
	-- GrantItem already handles the amount correctly, so call it once with the full quantity
	local success = ServerFunctions:GrantItem(targetPlayer, itemName, quantity)
	if not success then
		return false, "Failed to give item: " .. itemName
	end
	
	return true, "Item given successfully."
end

-- Start encounter for a target player (admin function)
function ServerFunctions:StartEncounterForPlayer(admin: Player, targetUserId: number, battleData: any, chunkName: string?)
	if not AdminService.CanPerformAction(admin, "CreateCreature") then
		return false, "You do not have permission to start encounters."
	end
	
	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer then
		return false, "Target player not found in game."
	end
	
	-- Temporarily set chunk if specified
	local originalChunk = nil
	if chunkName then
		local targetData = ClientData:Get(targetPlayer)
		if targetData then
			originalChunk = targetData.Chunk
			targetData.Chunk = chunkName
			ClientData:UpdateClientData(targetPlayer, targetData)
		end
	end
	
	-- Start battle for target player
	local success, message = ServerFunctions:StartBattle(targetPlayer, "Wild", battleData)
	
	-- Restore original chunk after a brief delay
	if originalChunk and chunkName and chunkName ~= originalChunk then
		task.spawn(function()
			task.wait(0.5)
			local targetData = ClientData:Get(targetPlayer)
			if targetData then
				targetData.Chunk = originalChunk
				ClientData:UpdateClientData(targetPlayer, targetData)
			end
		end)
	end
	
	return success, message or (success and "Encounter started successfully." or "Failed to start encounter.")
end

-- Set player data field
function ServerFunctions:SetPlayerData(admin: Player, targetUserId: number, field: string, value: any)
	if not AdminService.CanPerformAction(admin, "SetPlayerData") then
		return false, "You do not have permission to modify player data."
	end
	
	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer then
		return false, "Target player not found in game."
	end
	
	local targetData = ClientData:Get(targetPlayer)
	if not targetData then
		return false, "Target player data not found."
	end
	
	-- Validate field exists
	if targetData[field] == nil then
		return false, "Invalid field: " .. field
	end
	
	targetData[field] = value
	ClientData:UpdateClientData(targetPlayer, targetData)
	_saveNow(targetPlayer)
	
	return true, "Player data updated successfully."
end

-- Get banned players list
function ServerFunctions:GetBannedPlayers(admin: Player)
	if not AdminService.IsAdmin(admin) then
		return false, "You do not have permission to view bans."
	end
	
	-- Note: DataStore doesn't support listing all keys
	-- This would require a separate tracking system
	-- For now, return empty array
	return true, {}
end

-- Get player by UserId or name
function ServerFunctions:GetPlayerByNameOrId(identifier: string | number): Player?
	if type(identifier) == "number" then
		return Players:GetPlayerByUserId(identifier)
	else
		-- Search by name
		for _, player in ipairs(Players:GetPlayers()) do
			if string.lower(player.Name) == string.lower(identifier) then
				return player
			end
		end
	end
	return nil
end

return ServerFunctions
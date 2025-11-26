local ServerFunctions = {}

--// Services
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

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
local StatCalc = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StatCalc"))
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

--// Refactored System Modules
local BattleSystem = require(script.Parent.BattleSystem)
local ItemSystem = require(script.Parent.ItemSystem)
local CreatureSystem = require(script.Parent.CreatureSystem)
local WorldSystem = require(script.Parent.WorldSystem)
local CodeRedemption = require(script.Parent.CodeRedemption)

-- Unstuck cooldowns
local _unstuckCooldown: {[Player]: number} = {}

--// Instances
local Events = ReplicatedStorage:WaitForChild("Events")

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
		GameData = GameData,
		GameConfig = GameConfig,
		ChunkService = ChunkService,
		CatchCareShopConfig = CatchCareShopConfig,
		ReplicatedStorage = ReplicatedStorage,
	}
	
	BattleSystem.Initialize(dependencies)
	ItemSystem.Initialize(dependencies)
	CreatureSystem.Initialize(dependencies)
	WorldSystem.Initialize(dependencies)
	
	-- Initialize CodeRedemption with ServerFunctions reference
	dependencies.ServerFunctions = ServerFunctions
	CodeRedemption.Initialize(dependencies)
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

-- Give an item to a creature in the overworld (sets HeldItem)
function ServerFunctions:GiveItem(Player, payload)
	return ItemSystem.GiveItem(Player, payload)
end

function ServerFunctions:PurchaseCatchCareItem(Player: Player, payload: any)
	return ItemSystem.PurchaseCatchCareItem(Player, payload)
end

-- Manual save rate limiting (per-player)
local _lastManualSaveAt: {[Player]: number} = {}
local MANUAL_SAVE_MIN_INTERVAL = 15 -- seconds

-- Server-side request guard state for remotes
local _requestState: {[Player]: {lastTime: number, tokens: number}} = {}
local _ALLOWED_VERBS: {[string]: boolean} = {
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
    UpdateVaultBoxes = true,
    TakeHeldItem = true,
    DesyncCreature = true,
    RenameBox = true,
    DesyncBox = true,
    SetBoxBackground = true,
    SetBlackoutReturnChunk = true,
    GiveItem = true,
    GetUnstuck = true,
    PurchaseCatchCareItem = true,
    RedeemCode = true,
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
    
    -- Calculate XP using Pokémon formula
    local xpAmount = XPManager.CalculateXPYield(
        defeatedCreature,
        activeCreature,
        isTrainerBattle,
        1, -- participants
        false -- not shared
    )
    
    if xpAmount > 0 then
        local levelsGained = XPManager.AwardXP(activeCreature, xpAmount)
        local creatureName = activeCreature.Nickname or activeCreature.Name
        
        -- Add XP gain step
        table.insert(xpSteps, {
            Type = "XP",
            Creature = creatureName,
            Amount = xpAmount,
            IsShared = false,
            IsPlayer = true,
            XPProgress = activeCreature.XPProgress or 0,
            CurrentLevel = activeCreature.Level,
        })
        
        DBG:print("[XP]", creatureName, "gained", xpAmount, "XP")
        
        -- Add level up steps
        if levelsGained > 0 then
            local startLevel = activeCreature.Level - levelsGained
            for i = 1, levelsGained do
                -- Include XPProgress for the final level (after all level-ups)
                local xpProgress = (i == levelsGained) and (activeCreature.XPProgress or 0) or nil
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
    end
    
    -- Check XP Spread setting
    local xpSpreadEnabled = PlayerData.Settings and PlayerData.Settings.XPSpread or false
    local sharedCreatures = {}
    
    if xpSpreadEnabled then
        -- Participant earned xpAmount (full). Share 50% of that to every non-fainted non-participant
        local sharedAmount = math.floor(xpAmount * 0.5)
        if sharedAmount > 0 then
            for _, creature in ipairs(PlayerData.Party) do
                if creature ~= activeCreature and creature.Stats and creature.Stats.HP > 0 then
                    local shareLevels = XPManager.AwardXP(creature, sharedAmount)
                    local shareCreatureName = creature.Nickname or creature.Name
                    
                    table.insert(sharedCreatures, {
                        name = shareCreatureName,
                        levels = shareLevels,
                        level = creature.Level
                    })
                end
            end
        end
        
        -- Add "rest of party" message if anyone got shared XP
        if #sharedCreatures > 0 then
            table.insert(xpSteps, {
                Type = "XPSpread",
                IsPlayer = true,
            })
            
            -- Add individual level ups for shared creatures
            for _, data in ipairs(sharedCreatures) do
                if data.levels > 0 then
                    -- Find the creature in party to get its XPProgress
                    local shareCreature = nil
                    for _, creature in ipairs(PlayerData.Party) do
                        local nm = creature.Nickname or creature.Name
                        if nm == data.name then
                            shareCreature = creature
                            break
                        end
                    end
                    local startLevel = data.level - data.levels
                    for i = 1, data.levels do
                        -- Include XPProgress for the final level (after all level-ups)
                        local xpProgress = (i == data.levels) and shareCreature and (shareCreature.XPProgress or 0) or nil
                        table.insert(xpSteps, {
                            Type = "LevelUp",
                            Creature = data.name,
                            Level = startLevel + i,
                            IsPlayer = true,
                            XPProgress = xpProgress,
                        })
                        DBG:print("[XP]", data.name, "reached level", startLevel + i, "(shared)")
                    end
                end
            end
        end
    end
    
    -- Force update client data
    if #xpSteps > 0 then
        ClientData:UpdateClientData(Player, PlayerData)
    end
    
    return xpSteps
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

-- Session-scoped flags (cleared on player leave) for starter generation/refresh control
local SessionStarterGenerated: {[Player]: boolean} = {}

-- Cleanup session flags when players leave
do
    local PlayersService = game:GetService("Players")
    PlayersService.PlayerRemoving:Connect(function(p: Player)
        SessionStarterGenerated[p] = nil
    end)
end

function ServerFunctions:RequestStarters(Player)
	local PlayerData = ClientData:Get(Player)
	
    -- Per-session behavior:
    -- - First Request in a session:
    --   * If no starters exist yet -> generate new set and mark generated
    --   * If starters already exist (from previous session) and no selection -> REFRESH ONCE (generate new), then mark generated
    -- - Subsequent Requests in the same session (generated==true):
    --   * If no selection -> return existing without regenerating
    --   * If selection made -> return nil (no re-present)
    local generatedThisSession = SessionStarterGenerated[Player] == true
    if PlayerData.Starters then
        if PlayerData.SelectedStarter then
            DBG:print("[RequestStarters] Starter already selected for", Player.Name)
            return nil
        end
        if not generatedThisSession then
            DBG:print("[RequestStarters] Refreshing starters once for this session for", Player.Name)
            -- Fall through to (re)generation path below by clearing starters
            PlayerData.Starters = nil
        else
            -- Return existing set without regenerating
            local ForClient = {}
            for i, creature in ipairs(PlayerData.Starters) do
                ForClient[i] = { Name = creature.Name, Shiny = creature.Shiny }
            end
            DBG:print("[RequestStarters] Returning existing starters (session already generated) for", Player.Name)
            return ForClient
        end
    end
	
	-- Define the three starter creatures
    local starterInfo = {
        {Creature = "Frigo Camelo", Level = 5},
        {Creature = "Kitung", Level = 5},
        {Creature = "Twirlina", Level = 5},
    }

    -- Initialize starters array in player data
    PlayerData.Starters = {}

	-- Data to send to client
	local ForClient = {}

	-- Generate each starter creature
    for i, info in ipairs(starterInfo) do
        -- Tag Original Trainer (OT) and catcher name with player's chosen nickname if available
        info.OT = Player.UserId
        local caughtByName = (PlayerData and PlayerData.Nickname) or Player.Name
        info.CaughtBy = caughtByName
        -- Starter creatures are tradelocked by design
        info.TradeLocked = true
        local creature = CreatureFactory.CreateFromInfo(info)
		PlayerData.Starters[i] = creature

        ForClient[i] = {
            Name = creature.Name,
            Shiny = creature.Shiny,
        }
	end
	
    -- Update the client's data
    ClientData:UpdateClientData(Player, PlayerData)
    -- Mark generated for this session (prevents further refresh within the same join)
    SessionStarterGenerated[Player] = true
	
	DBG:print("Generated starters for player:", Player.Name)
	return ForClient
end

function ServerFunctions:PickStarter(Player, StarterName)
	local PlayerData = ClientData:Get(Player)
	
	-- Check if player has starters
	if not PlayerData.Starters then
		Player:Kick("No starters available!")
		return false
	end
	
	-- Check if player already picked a starter
	if PlayerData.SelectedStarter then
		Player:Kick("Already selected a starter!")
		return false
	end
	
	-- Find the selected starter
	local selectedStarter = nil
	for i, starter in ipairs(PlayerData.Starters) do
		if starter.Name == StarterName then
			selectedStarter = starter
			break
		end
	end
	
	if not selectedStarter then
		Player:Kick("Invalid starter selection!")
		return false
	end
	
	-- Add the selected starter to player's party
	if not PlayerData.Party then
		PlayerData.Party = {}
	end
	
	-- Ensure the starter has an assigned ability (backfill for pre-fix starters)
	if not selectedStarter.Ability or selectedStarter.Ability == "" then
		selectedStarter.Ability = AbilitiesModule.SelectAbility(selectedStarter.Name, false)
	end
	
	PlayerData.Party[1] = selectedStarter
	PlayerData.SelectedStarter = StarterName
	-- Mark FIRST_CREATURE acquired
	pcall(function()
		PlayerData.Events = PlayerData.Events or {}
		if PlayerData.Events.FIRST_CREATURE ~= true then
			PlayerData.Events.FIRST_CREATURE = true
		end
	end)
	
	-- Update the client's data
	ClientData:UpdateClientData(Player, PlayerData)
	
	DBG:print("Player", Player.Name, "selected starter:", StarterName)
	DBG:print("Starter added to party:", selectedStarter.Name, "Level:", selectedStarter.Level, "Shiny:", selectedStarter.Shiny)
	DBG:print("Player party now contains:", #PlayerData.Party, "creatures")
	return true
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
        local saved = _saveNow(Player)
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

-- Provide reference to active battles map for other modules
function ServerFunctions:GetActiveBattles()
    return ActiveBattles
end

-- ActiveBattles moved to top of file for global access

function ServerFunctions:AttemptEscape(Player)
	local PlayerData = ClientData:Get(Player)
	
	if not PlayerData then
		DBG:warn("No player data found for escape attempt")
		return false, "No player data"
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
            damageStep = { Type = "Damage", Effectiveness = "Normal", IsPlayer = false, NewHP = newHP }

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
        Events.Communicate:FireClient(Player, "TurnResult", {
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
        })
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
        _saveNow(Player)
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

-- Helper: get list of type names from a Type reference (string or array or type tables)
local function GetTypeNames(typeRef)
    local names = {}
    if type(typeRef) == "string" then
        table.insert(names, typeRef)
    elseif type(typeRef) == "table" then
        -- Could be array of strings or array of type tables
        for _, t in ipairs(typeRef) do
            if type(t) == "string" then
                table.insert(names, t)
            elseif type(t) == "table" then
                for typeName, data in pairs(TypesModule) do
                    if data == t then table.insert(names, typeName) break end
                end
            end
        end
    end
    return names
end

-- Helper: compute type effectiveness multiplier given move type and defender types
local function ComputeTypeModifier(moveTypeName, defenderTypeNames)
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
local function ComputeSTAB(moveTypeName, attacker)
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
local function CalculateDamage(attacker, defender, moveNameOrData, isCrit)
    if not attacker or not defender or not attacker.Stats or not defender.Stats then return 1 end

    local level = attacker.Level or 1
    local atk = attacker.Stats.Attack or 10
    local def = defender.Stats.Defense or 10

    -- Get move data (cached)
    local moveName, moveData, moveTypeName, power
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
            -- Cache type name lookups to avoid repeated table scans
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
	local abilityMultiplier = AbilitiesModule.DamageMultiplier(attacker, defender, moveTypeName)
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
    local stats, maxStats = StatCalc.ComputeStats(PlayerCreature.Name, PlayerCreature.Level, PlayerCreature.IVs, PlayerCreature.Nature)
    local currentHPPercent = PlayerCreature.CurrentHP
    local currentHPAbs: number
    if currentHPPercent == nil then
        currentHPPercent = 100
        currentHPAbs = maxStats.HP
        PlayerCreature.CurrentHP = currentHPPercent
    else
        currentHPPercent = math.clamp(currentHPPercent, 0, 100)
        currentHPAbs = math.floor(maxStats.HP * (currentHPPercent / 100) + 0.5)
    end
    PlayerCreature.Stats = stats
    PlayerCreature.Stats.HP = currentHPAbs
    PlayerCreature.MaxStats = maxStats
	-- Apply held item stat modifiers for player creature
	HeldItemEffects.ApplyStatMods(PlayerCreature)

    -- Persist computed MaxStats into PlayerData party slot for consistent UI math
    if PlayerData.Party and PlayerData.Party[PlayerCreatureIndex] then
        PlayerData.Party[PlayerCreatureIndex].MaxStats = maxStats
        PlayerData.Party[PlayerCreatureIndex].Stats = PlayerData.Party[PlayerCreatureIndex].Stats or {}
        PlayerData.Party[PlayerCreatureIndex].Stats.HP = currentHPAbs
        PlayerData.Party[PlayerCreatureIndex].CurrentHP = currentHPPercent
    end
    -- Ensure player creature has starting moves per learnset at current level
    local creatureDef = Creatures[PlayerCreature.Name]
    if creatureDef then
        PlayerCreature.CurrentMoves = PlayerCreature.CurrentMoves or {}
        PlayerCreature.LearnedMoves = PlayerCreature.LearnedMoves or {}
        if (not PlayerCreature.CurrentMoves or #PlayerCreature.CurrentMoves == 0) and creatureDef.Learnset then
            local startMoves, learned = BuildStartingMovesFromLearnset(creatureDef.Learnset, PlayerCreature.Level)
            PlayerCreature.CurrentMoves = startMoves
            PlayerCreature.LearnedMoves = learned
        end
    end
	
	local BattleInfo = {
		Type = BattleType, -- "Wild" or "Trainer"
		PlayerCreature = PlayerCreature,
		PlayerCreatureIndex = PlayerCreatureIndex,
		ChunkName = PlayerData.Chunk or "Chunk1",
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
		
		-- Determine shiny status (1 in SHINY_CHANCE)
		local isShiny = math.random(1, GameData.Config.SHINY_CHANCE) == 1
		
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
    -- Preserve LeaveData during battle so Continue can restore exact position.
    -- Runtime code should avoid updating LeaveData while InBattle, but do not clear it here.
    ClientData:UpdateClientData(Player, PlayerData)

	-- Immediately notify client to start battle (avoid extra client->server hop)
	Events.Communicate:FireClient(Player, "StartBattle", BattleInfo)

    -- Trigger OnEntry abilities for initial active creatures
    -- We do this silently on server state; client animations are handled via specific steps if generated during turns,
    -- but for start-of-battle we might need to queue immediate messages or just apply stats.
    -- For now, we'll just apply stat mods immediately if needed (e.g. Intimidate).
    -- Note: In a real turn structure, this would generate a "Message" step or "StatStage" step.
    -- Since StartBattle doesn't return steps, we might need to rely on client-side OnEntry or handle it in the first turn?
    -- Better: Apply stat changes to the BattleState creatures directly so damage calcs are correct from turn 1.
    -- Visuals might be missed unless we send a "BattleStartEvents" packet.
    do
        local Abilities = require(game:GetService("ReplicatedStorage").Shared.Abilities)
        local pAbility = Abilities.OnEntry(PlayerCreature)
        local fAbility = Abilities.OnEntry(BattleInfo.FoeCreature)

        if pAbility == "Intimidate" then
            -- Lower foe attack
            BattleInfo.FoeCreature.StatStages = BattleInfo.FoeCreature.StatStages or {}
            BattleInfo.FoeCreature.StatStages.Attack = (BattleInfo.FoeCreature.StatStages.Attack or 0) - 1
            DBG:print("[Abilities] Player's Intimidate lowered foe Attack")
        elseif pAbility == "Sunlight" then
            -- Set weather (needs BattleState weather support)
            -- BattleInfo.Weather = "Sunlight" -- TODO: Add weather to battle state
        end

        if fAbility == "Intimidate" then
            -- Lower player attack
            PlayerCreature.StatStages = PlayerCreature.StatStages or {}
            PlayerCreature.StatStages.Attack = (PlayerCreature.StatStages.Attack or 0) - 1
            DBG:print("[Abilities] Foe's Intimidate lowered player Attack")
        elseif fAbility == "Sunlight" then
            -- BattleInfo.Weather = "Sunlight"
        end
    end

	DBG:print("Starting", BattleType, "battle for player:", Player.Name)
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
		DBG:warn("No battle scene found for chunk:", ChunkName, "using Chunk1")
		-- Fallback to Chunk1
		ChunkBattleScene = BattleScenes:WaitForChild("Chunk1")
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
            for i = 1, 8 do
                fresh.Boxes[i] = { Name = "Box " .. tostring(i), Creatures = {} }
            end
            fresh.Items = {}
            fresh.Creatures = {}
            fresh.Gamepasses = {}
            fresh.PickedUpItems = {}
            fresh.DefeatedTrainers = {}
            fresh.RedeemedCodes = {}
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
    if Request[1] == "ExecuteMove" then
        if typeof(Request[2]) ~= "table" then return false end
        return ServerFunctions:ExecuteMove(Player, Request[2])
    end
    if Request[1] == "UseItem" then
        local payload = Request[2]
        if typeof(payload) ~= "table" or type(payload.Name) ~= "string" then return false end
        return ServerFunctions:UseItem(Player, payload)
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
            for _, c in ipairs(desiredList) do
                if cap and count >= cap then break end
                local k = fp(c)
                local srv = takeFromPool(k)
                if not srv then
                    return nil -- invalid payload (creature not in pool)
                end
                table.insert(out, srv)
                count += 1
            end
            return out
        end

        -- Rebuild party
        local newParty = buildListFromDesired(desiredParty, 6) or {}
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
        -- Clear pending capture and persist
        PlayerData.PendingCapture = nil
        if ClientData.UpdateClientData then
            ClientData:UpdateClientData(Player, PlayerData)
        end
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
        return ServerFunctions:SwitchCreature(Player, creatureIndex)
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
        -- Apply reorder
        local newParty = {}
        for i = 1, n do
            newParty[i] = party[order[i]]
        end
        PlayerData.Party = newParty
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
	
	-- Catch-all for unhandled requests
	DBG:warn("Unhandled request type:", Request[1], "from player:", Player.Name)
	return false, "Unhandled request type: " .. tostring(Request[1])
end

-- Handle player leaving - clear server-side battle state only (position saved on CharacterRemoving)
Players.PlayerRemoving:Connect(function(Player: Player)
	DBG:print("Player leaving:", Player.Name, "- clearing battle state")
	ServerFunctions:ClearBattleData(Player)
end)

-- Execute player move and process enemy turn
function ServerFunctions:ExecuteMove(Player, MoveData)
	-- Validate and store move action via BattleSystem
	local success = BattleSystem.ExecuteMove(Player, MoveData)
	if not success then
		return false
	end
	
	-- Process turn (handles battle end logic)
	return ServerFunctions:ProcessTurn(Player)
end

-- Process turn with proper speed-based order (Pokemon-style) - delegates to BattleSystem
function ServerFunctions:ProcessTurn(Player)
    local battle = ActiveBattles[Player]
    if not battle then
        DBG:warn("No active battle found for player:", Player.Name)
        return false
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
            local Events = game.ReplicatedStorage.Events
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
            IsPlayer = true
        }
        
        -- Add faint step to friendly actions (player fainted)
        local friendlyActions = {faintStep}
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
            Events.Communicate:FireClient(Player, "TurnResult", turnResult)
        end
        
        return true
    end
    
    -- Generate enemy action (skip if player performed a successful capture this turn,
    -- or if we're immediately after a SwitchPreview switch where the player opted to switch)
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
                -- Resolve actor side for this step (prefer explicit IsPlayer; only then attempt name match)
                local stepIsPlayer
                if singleResult.IsPlayer ~= nil then
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
                    if (singleResult.IsPlayer == true) then
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
            -- Prefer explicit IsPlayer; only then attempt name match
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
                    -- For ordering: attach FAINT to the same side as the triggering action
                    stepIsPlayer = action.IsPlayer
                    if (result.IsPlayer == true) then
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
                
                -- Add SwitchPreview step to ask player if they want to switch
                table.insert(enemyActions, {
                    Type = "SwitchPreview",
                    TrainerName = battle.TrainerName,
                    NextCreature = (nextCreature.Nickname or nextCreature.Name),
                    IsPlayer = false,
                })
                -- Set flag to allow switch during preview
                battle.AllowPreviewSwitch = true
                DBG:print("[KO/Switch] Added SwitchPreview step for", (nextCreature.Nickname or nextCreature.Name))
                DBG:print("[KO/Switch] Enabled AllowPreviewSwitch flag")
                
                -- Append a Switch SendOut step after the preview
                table.insert(enemyActions, {
                    Type = "Switch",
                    Action = "SendOut",
                    Creature = (nextCreature.Nickname or nextCreature.Name),
                    CreatureData = nextCreature,
                    IsPlayer = false,
                    TrainerName = battle.TrainerName,
                })
                -- Store next creature info but DON'T promote yet (TurnResult should show current state)
                battle.NextFoeCreature = nextCreature
                battle.NextFoeCreatureIndex = nextIndex
                battle.PendingTrainerSendOut = true
                DBG:print("[KO/Switch] Stored next creature for post-turn promotion")
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

	-- If foe fainted and battle continues (trainer has more), award XP now, before end-turn heals
	if foeFaintedThisTurn and not isFinalFoeFaint then
		local defeated = battle.FoeCreature
		if defeated then
			local xpSteps = ServerFunctions:AwardBattleXP(Player, defeated, battle)
			if type(xpSteps) == "table" and #xpSteps > 0 then
				for _, step in ipairs(xpSteps) do
					table.insert(friendlyActions, step)
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
            if not creature or not creature.Stats or creature.Stats.HP <= 0 then return end
            if not creature.Status then return end
            
            local statusDamage = StatusModule.ProcessEndOfTurn(creature)
            if not statusDamage or statusDamage <= 0 then return end
            
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
            
            DBG:print("[ServerFunctions][Status] applying:", creatureName, "before:", beforeHP, "-", statusDamage, "->", creature.Stats.HP, "Status:", statusType)
            
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
                        if ClientData.UpdateClientData then ClientData:UpdateClientData(Player, pd) end
                    end
                end
            else
                table.insert(enemyActions, step)
            end
        end
        
        -- Apply status damage to both creatures
        -- Note: Status damage affects the creature, so player damage goes to friendlyActions, foe damage goes to enemyActions
        applyStatusDamage(battle.PlayerCreature, true)
        applyStatusDamage(battle.FoeCreature, false)
        
        -- THEN process held item effects (like Crumbs healing) - healing happens after damage
        -- IMPORTANT: To get correct turn order (Player move -> Status -> Enemy move -> Crumbs -> Burn damage),
        -- we need to add player Crumbs to enemyActions so it appears after enemy moves.
        -- The client processes friendlyActions first, then enemyActions, so:
        -- - friendlyActions: [Player move]
        -- - enemyActions: [Status, Enemy move, Player Crumbs, Enemy Crumbs, Burn damage]
        -- This gives the correct order!
        local function processCrumbsForOrder(holder, isPlayerSide)
            local heldName = holder and holder.HeldItem and tostring(holder.HeldItem) or ""
            heldName = heldName:lower():gsub("^%s+"," "):gsub("%s+$"," ")
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
                    table.insert(enemyActions, step)
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
                                if ClientData.UpdateClientData then ClientData:UpdateClientData(Player, pd) end
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
            if not ability then return end
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
        if type(stepList) ~= "table" then return end
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

    -- Advance TurnId and send turn result to client
    battle.TurnId = (battle.TurnId or 0) + 1
    DBG:print("=== SENDING TURN RESULT TO CLIENT ===")
    DBG:print("Friendly actions count:", #friendlyActions)
    for i, action in ipairs(friendlyActions) do
        DBG:print("Friendly", i, "Type:", action.Type, "IsPlayer:", action.IsPlayer, "Creature:", action.Creature, "Move:", action.Move, "Message:", action.Message)
    end
    DBG:print("Enemy actions count:", #enemyActions)
    for i, action in ipairs(enemyActions) do
        DBG:print("Enemy", i, "Type:", action.Type, "IsPlayer:", action.IsPlayer, "Creature:", action.Creature, "Move:", action.Move, "Message:", action.Message)
    end
    DBG:print("=== END TURN RESULT ===")
    
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
        Events.Communicate:FireClient(Player, "TurnResult", {
            Friendly = friendlyActions,
            Enemy = enemyActions,
            HP = hpData,
            PlayerCreatureIndex = battle.PlayerCreatureIndex or 1,
            PlayerCreature = battle.PlayerCreature,
            FoeCreatureIndex = battle.FoeCreatureIndex or 1,
            FoeCreature = battle.FoeCreature,
            TurnId = battle.TurnId,
            -- Only signal Forced when it occurred this turn; otherwise omit to avoid stale client state
            SwitchMode = (playerFaintedThisTurn and "Forced") or nil,
            BattleEnd = willEnd,
        })
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
    if battle.PendingTrainerSendOut and battle.NextFoeCreature then
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
            for i, c in ipairs(battle.TrainerParty) do
                if c then
                    local hp = (c.CurrentHP or (c.Stats and c.Stats.HP) or 0)
                    local name = (c.Nickname or c.Name or "?")
                    local isCurrent = (c == battle.FoeCreature)
                    DBG:print("[BattleEnd] Party slot", i, ":", name, "HP:", hp, "IsCurrent:", isCurrent)
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
                    -- Wild battle - just the foe creature
                    if battle.FoeCreature then
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
            else
                DBG:warn("[BattleEnd] Could not mark trainer as defeated - PlayerData missing")
            end
        else
            DBG:print("[BattleEnd] Not marking trainer as defeated - conditions not met")
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
                local basePayout = {8, 16, 24, 36, 48, 60, 80, 100, 120}
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
            -- Finalize: clear pre-battle snapshot only now that battle ended
            local pd = ClientData:Get(Player)
            if pd then
                pd.PendingBattle = nil
                ClientData:UpdateClientData(Player, pd)
            end
            Events.Communicate:FireClient(Player, "BattleOver", battleOverData)
            -- Event-based save after battle completes ONLY if AutoSave is enabled and not during cutscenes
            local currentData = ClientData:Get(Player)
            local allowAuto = (currentData and currentData.Settings and currentData.Settings.AutoSave) == true and (currentData and currentData.InCutscene ~= true)
            if allowAuto then
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
    if not canAct then
        -- Attacker can't act due to status
        local steps = {
            { Type = "Move", Move = moveName, Actor = attacker.Name or (isPlayer and "Your creature" or "Foe"), IsPlayer = isPlayer },
            { Type = "Message", Message = statusMessage or "The creature can't move!", IsPlayer = isPlayer }
        }
        return steps
    end
    
    -- Check volatile status conditions (Confusion, Infatuation, Flinch)
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
        return {
            { Type = "Move", Move = moveName, Actor = attacker.Name or "You", IsPlayer = isPlayer },
            { Type = "Heal", Amount = healed, IsPlayer = isPlayer, Message = string.format("%s perched and recovered HP!", attacker.Nickname or attacker.Name) }
        }
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
        return {
            { Type = "Miss", Message = missMessage, Move = moveName, Actor = attacker.Name or (isPlayer and "Your creature" or "Foe"), IsPlayer = isPlayer }
        }
    end

    -- Calculate damage
    local critBonus = Abilities.GetCritStageBonus(attacker, not isPlayer) -- not isPlayer implies opponent used move last turn? No, param is just creature.
    -- Wait, GetCritStageBonus 2nd param is "opponentUsedMove". We don't track that easily here.
    -- For now, ignore Spy Lens conditional or assume false.
    
    local isCrit = (math.random(1, 16) == 1) -- Base crit. TODO: Use crit stages.
    
    -- Modify moveDef temporarily for calculation if type changed
    local effectiveMoveData = moveDef
    if modifiedType ~= moveDef.Type then
        effectiveMoveData = table.clone(moveDef)
        effectiveMoveData.Type = modifiedType
    end

    local damage, mods = CalculateDamage(attacker, defender, effectiveMoveData, isCrit)
    -- Global damage tuning: soften incoming damage to the player a bit for early routes
    if not isPlayer then
        damage = math.max(1, math.floor(damage * 0.7)) -- 30% reduction to enemy damage
    end
    -- Derive simplified effectiveness category for client-side SFX/VFX
    local effCat = "Normal"
    local effNum = (mods and type(mods.Effectiveness) == "number") and mods.Effectiveness or 1
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
    local damageStep = {
        Type = "Damage",
        Effectiveness = effCat,
        IsPlayer = isPlayer,
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
    
    return steps
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
            -- Base catch rate (default 45 if not defined)
            -- Base catch rate scalar from species (0 always catches, 100 impossible)
            local catchRate = 45
            do
                local def = foe and foe.Name and (CreaturesModule and CreaturesModule[foe.Name])
                if def and type(def.CatchRateScalar) == "number" then
                    catchRate = math.clamp(math.floor(def.CatchRateScalar), 0, 100)
                end
            end
            do
                local base = CreaturesModule and CreaturesModule[foe.Name]
                if base and type(base.CatchRate) == "number" then
                    catchRate = base.CatchRate
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
            -- Map 0..100 scalar to a 1..255-like base for 'a' computation
            -- 0 => auto-catch (simulate with very high a); 100 => near impossible (very low a)
            local baseRate
            if catchRate <= 0 then
                baseRate = 9999 -- force immediate success path
            elseif catchRate >= 100 then
                baseRate = 1
            else
                -- Invert: lower scalar => higher base
                baseRate = math.floor(255 * (1 - (catchRate / 100)))
                baseRate = math.clamp(baseRate, 1, 255)
            end
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
	return BattleSystem.BuildEnemyAction(Player)
end

function ServerFunctions:SwitchCreature(Player, newCreatureSlot)
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

    -- Allow switch during forced switch (this is exactly when we must switch)
	
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

	-- Determine if the CURRENT active creature has fainted -> forced swtch
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
            newBattleCreature.CurrentMoves = GetMovesForLevel(creatureData.LearnableMoves, newCreature.Level)
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
            playerData.Party[newCreatureSlot].CurrentMoves = GetMovesForLevel(creatureData.LearnableMoves, newCreature.Level)
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

	
    -- Send turn result to client with structured data (no message strings)
    local turnResult
	if battle.SwitchMode == "Forced" then
		-- Forced switch: do NOT show "come back"; only send-out and skip enemy action
		turnResult = {
			Friendly = {
				{ Type = "Switch", Action = "SendOut", Creature = newCreatureName, Variant = goVariant, IsPlayer = true }
			},
            Enemy = {},
			PlayerCreatureIndex = newCreatureSlot,
			PlayerCreature = battle.PlayerCreature,
			HP = nil,
			SwitchMode = battle.SwitchMode,
		}
	else
		-- Voluntary switch: show recall then send-out
		turnResult = {
			Friendly = {
				{ Type = "Switch", Action = "Recall", Creature = oldCreatureName, IsPlayer = true },
				{ Type = "Switch", Action = "SendOut", Creature = newCreatureName, Variant = goVariant, IsPlayer = true }
			},
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
        if (battleType ~= "Trainer" or not hasEnemySwitch) and not battle.PreviewSwitchInProgress then
			-- Normal switch behavior - foe gets a turn
			DBG:print("VOLUNTARY SWITCH: Enemy gets turn after switch to", battle.PlayerCreature.Name)
			
			-- REDUNDANT CHECK: Ensure the slot we're applying damage to is the ACTIVE creature's party slot:
			DBG:print("=== PRE DAMAGE SECTION CHECK ===")
			DBG:print("battle.PlayerCreatureIndex:", battle.PlayerCreatureIndex)
			DBG:print("battle.PlayerCreatureOriginalIndex:", battle.PlayerCreatureOriginalIndex)
			DBG:print("battle.PlayerCreature:", battle.PlayerCreature.Name)
			DBG:print("=== END PRE DAMAGE SECTION CHECK ===")

			-- Generate enemy action AFTER the switch is complete
			local enemyAction = ServerFunctions:BuildEnemyAction(Player)
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
                table.insert(enemySteps, {
                    Type = "Damage",
                    IsPlayer = false,
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

-- Day/Night Cycle access functions
function ServerFunctions:GetCurrentTimePeriod()
	return DayNightCycle:GetCurrentPeriod()
end

function ServerFunctions:GetTimeOfDay()
	return DayNightCycle:GetTimeOfDay()
end

function ServerFunctions:IsDay()
	return DayNightCycle:IsDay()
end

function ServerFunctions:IsDusk()
	return DayNightCycle:IsDusk()
end

function ServerFunctions:IsNight()
	return DayNightCycle:IsNight()
end

function ServerFunctions:GetFormattedTime()
	return DayNightCycle:GetFormattedTime()
end

function ServerFunctions:GetTimeUntilNextPeriod()
	return DayNightCycle:GetTimeUntilNextPeriod()
end

function ServerFunctions:GetDayNightCycle()
	return DayNightCycle
end

-- Initialize Day/Night Cycle system
DayNightCycle:Initialize()

return ServerFunctions
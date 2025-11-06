--!strict
--[[
	BattleSystemV2.lua
	Modern modular battle system using clean OOP architecture
	Coordinates all battle modules for a complete battle experience
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Import modules
local Battle = require(script.Parent.Parent.Battle)
local MessageQueue = Battle.MessageQueue
local AnimationController = Battle.AnimationController
local UIController = Battle.UIController
local ClientBattleState = Battle.StateManager
local CameraController = Battle.CameraController
local BattleSceneManager = Battle.SceneManager
local ActionHandler = Battle.ActionHandler
local BattleUIManager = Battle.UIManager
local CombatEffects = Battle.CombatEffects
local StepProcessor = Battle.StepProcessor
local PartyIntegration = Battle.PartyIntegration
local SwitchHandler = Battle.SwitchHandler
local PostBattleHandler = Battle.PostBattleHandler
local RelocationSignals = require(script.Parent.RelocationSignals)
local BattleOptionsManager = Battle.BattleOptionsManager
local BattleMessageGenerator = Battle.MessageGenerator

-- Import utilities
local CharacterFunctions = require(script.Parent.CharacterFunctions)
-- Lazy UI accessor to avoid startup require cycles
local function getUI()
	local ok, ui = pcall(function()
		return require(script.Parent.Parent.UI)
	end)
	if ok then return ui end
	return nil
end
local UIFunctions = require(script.Parent.Parent.UI.UIFunctions)
local MusicManager = require(script.Parent.MusicManager)
local EncounterZone = require(script.Parent.EncounterZone)
local TrainerIntroController = require(script.Parent.TrainerIntroController)
local ClientData = require(script.Parent.Parent.Plugins.ClientData)

-- Shared data
local MovesModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Moves"))
local TypesModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

-- Services
local Events = ReplicatedStorage:WaitForChild("Events")
local LocalPlayer = Players.LocalPlayer

-- Battle System V2
local BattleSystemV2 = {}
BattleSystemV2.__index = BattleSystemV2

export type BattleSystemV2Type = typeof(BattleSystemV2.new())

--[[
	Creates a new battle system instance
	@return BattleSystemV2
]]
function BattleSystemV2.new(): any
	local self = setmetatable({}, BattleSystemV2)
	
	-- Core modules (initialized on battle start)
	self._messageQueue = nil
	self._animationController = nil
	self._uiController = nil
	self._cameraController = nil
	self._sceneManager = nil
	self._battleState = nil
	self._actionHandler = nil
	self._battleUIManager = nil
	self._combatEffects = nil
	self._stepProcessor = nil
	self._partyIntegration = nil
	self._switchHandler = nil
	self._postBattleHandler = nil
    -- Move replace gating
    self._moveReplaceActive = false
    self._deferredEventsDuringMoveReplace = {}
	self._optionsManager = nil
	self._inTurnProcessing = false -- guards mid-turn UI from reappearing (e.g., after Bag close)
	self._pendingBattleOver = false -- defer server BattleOver until turn processing completes
	
	-- Battle data
	self._battleInfo = nil
	self._preBattlePartySnapshot = nil
    self._ending = false -- guard to prevent double end sequences
	self._deferredXPEvents = {} -- Store XP events to show after faint animation
	self._battleEndReason = nil -- Store the reason for battle end (Win, Loss, Capture, etc.)
	self._lossReason = false -- Flag for when player loses (all creatures faint)
	self._studsLost = 0 -- Amount of studs lost when player is defeated
	
	-- UI references (resolve lazily to avoid startup waits)
	local pg = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui")
	local gui = pg:FindFirstChild("GameUI") or pg:WaitForChild("GameUI")
	local battleGui = gui:FindFirstChild("BattleUI") or gui:WaitForChild("BattleUI")
	self._battleUI = battleGui
	self._battleOptions = battleGui:WaitForChild("BattleOptions")
	self._moveOptions = battleGui:WaitForChild("MoveOptions")
	self._battleNotification = battleGui:WaitForChild("BattleNotification")
	self._exclamationMark = gui:WaitForChild("ExclamationMark")
	
	-- Camera
	self._camera = workspace.CurrentCamera
	
	return self
end

--[[
	Initializes the battle system and sets up event listeners
]]
function BattleSystemV2:Initialize()
	-- Connect to server events
	Events.Communicate.OnClientEvent:Connect(function(eventType, data)
		if eventType == "StartBattle" then
			self:StartBattle(data)
		elseif eventType == "TurnResult" then
			self:ProcessTurnResult(data)
		elseif eventType == "EscapeSuccess" then
			self:HandleEscapeSuccess()
		elseif eventType == "EscapeFailure" then
			self:HandleEscapeFailure()
		elseif eventType == "BattleOver" then
		-- Store battle end reason and studs loss
		if type(data) == "table" and data.Reason then
			self._battleEndReason = data.Reason
			print("[BattleSystemV2] Battle ended with reason:", data.Reason)
			
			-- Store studs loss if player lost
			if data.Reason == "Loss" and data.StudsLost then
				self._studsLost = data.StudsLost
				print("[BattleSystemV2] Player lost", self._studsLost, "studs")
			end
		end
		
		-- Update client cache if trainer was defeated
		if type(data) == "table" and data.DefeatedTrainerId then
			local ClientData = require(script.Parent.Parent.Plugins.ClientData)
			local pd = ClientData:Get()
			if pd then
				if not pd.DefeatedTrainers then
					pd.DefeatedTrainers = {}
				end
				pd.DefeatedTrainers[data.DefeatedTrainerId] = true
				print("[BattleSystemV2] Updated client cache - marked trainer", data.DefeatedTrainerId, "as defeated")
			end
		end
		
		-- If we're in the middle of processing a turn (e.g., capture scans), defer the end
        if self._inTurnProcessing or self._moveReplaceActive then
			self._pendingBattleOver = true
			-- Preserve battle end reason even when deferring
			local reason = (type(data) == "table" and data.Reason) or nil
			if reason == "Capture" then
				self._caughtReason = true
			elseif reason == "Loss" then
				self._lossReason = true
			end
		else
			-- Defer end until all pending messages/animations (e.g., faint/capture success) are processed
			task.spawn(function()
                if self._messageQueue and self._messageQueue.WaitForDrain then
					self._messageQueue:WaitForDrain()
				end
				-- On capture, show Caught UI during blackout
				local reason = (type(data) == "table" and data.Reason) or nil
				if reason == "Capture" then
					self._caughtReason = true
				elseif reason == "Loss" then
					self._lossReason = true
				end
                -- Block battle end while move replacement flow is active
                if self._moveReplaceActive then
                    self._pendingBattleOver = true
                    return
                end
                self:EndBattle()
			end)
		end
		elseif eventType == "BattleEvent" then
			self:HandleBattleEvent(data)
		elseif eventType == "Evolution" then
			self:HandleEvolution(data)
		end
	end)
	
	print("[BattleSystemV2] Initialized")
end

--[[
	Starts a new battle
	@param battleInfo Battle information from server
]]
function BattleSystemV2:StartBattle(battleInfo: any)
	print("[BattleSystemV2] Starting battle:", battleInfo.Type)
    -- Reset end-state guard for new battle
    self._ending = false
	
	-- Store battle info
	self._battleInfo = battleInfo
	
	-- Initialize modules
	self._animationController = AnimationController.new()
	self._uiController = UIController.new()
	self._sceneManager = BattleSceneManager.new()
	self._messageQueue = MessageQueue.new(self._battleNotification)
	-- Utility: safe wait for message queue to drain with timeout to avoid deadlocks
	function self:_safeWaitForDrain(timeoutSeconds: number?)
		local q = self._messageQueue
		if not q then return end
		pcall(function()
			if q.ClearPersistent then q:ClearPersistent() end
		end)
		local done = false
		task.spawn(function()
			pcall(function()
				q:WaitForDrain()
			end)
			done = true
		end)
		local maxWait = (type(timeoutSeconds) == "number" and timeoutSeconds > 0) and timeoutSeconds or 3
		local start = os.clock()
		while not done and (os.clock() - start) < maxWait do
			task.wait(0.05)
		end
	end
	-- Hook message display for shiny burst when the sparkling message appears (wild only)
	self._messageQueue:SetOnDisplay(function(message: string)
		if type(message) ~= "string" then return end
		local lower = string.lower(message)
		if string.find(lower, "it's sparkling", 1, true) or string.find(lower, "its sparkling", 1, true) then
			if self._battleInfo and self._battleInfo.Type == "Wild" then
				local foeModel = self._sceneManager and self._sceneManager:GetFoeCreature()
				if foeModel and self._combatEffects and self._combatEffects.PlayShinyBurst then
					self._combatEffects:PlayShinyBurst(foeModel)
				end
			end
		end
	end)
	
	-- Initialize battle state first (needed by other modules)
	self._battleState = ClientBattleState.new(
		battleInfo.Type,
		battleInfo.PlayerCreature,
		battleInfo.FoeCreature
	)
	-- Initialize client TurnId from server-provided battleInfo and log for debugging
	self._battleState.TurnId = (type(battleInfo.TurnId) == "number") and battleInfo.TurnId or 0
	print("[BattleSystemV2] Initialized TurnId:", self._battleState.TurnId)
	
	-- Initialize action handler
	self._actionHandler = ActionHandler.new(self._battleState)
	
	-- Set up action handler callbacks
    self._actionHandler:OnSwitchRequested(function(creatureIndex)
		print("[BattleSystemV2] Switch requested for creature index:", creatureIndex)
        -- Hide battle options during switch
        if self._optionsManager then
            self._optionsManager:HideAll()
        end
	end)
	
	-- Set up can't run callback
	self._actionHandler:OnCantRun(function()
		print("[BattleSystemV2] Player can't run from trainer battle")
		-- Hide battle options first (like normal Run button behavior)
		if self._optionsManager then
			self._optionsManager:HideAll()
		end
		
		-- Show message and restore battle options
		if self._messageQueue then
			print("[BattleSystemV2] Enqueuing 'can't run' message")
			self._messageQueue:Enqueue("You can't run from a trainer battle!")
			-- Wait for message to drain, then show battle options
			self._messageQueue:OnDrained(function()
				print("[BattleSystemV2] 'Can't run' message drained, showing battle options")
				if self._optionsManager then
					self._optionsManager:ShowBattleOptions()
				end
			end)
		end
	end)
	
	-- Initialize party integration
	self._partyIntegration = PartyIntegration.new(self._battleState, self._actionHandler)
	
	-- Initialize UI manager with party integration
	self._battleUIManager = BattleUIManager.new(self._actionHandler, self._partyIntegration)
	
	-- Initialize combat effects
	self._combatEffects = CombatEffects.new(self._animationController)
	
	-- Initialize step processor
	self._stepProcessor = StepProcessor.new(
		self._battleState,
		self._messageQueue,
		self._uiController,
		self._sceneManager,
		self._combatEffects
	)
	
	-- Set battle system reference for callbacks
	self._stepProcessor:SetBattleSystem(self)
	
	-- Set callback for switch preview choice UI
	self._stepProcessor._showChoiceUI = function(onComplete)
		self:_showSwitchPreviewChoice(onComplete)
	end
	-- Provide animation controller so StepProcessor can play idle/adjust speeds
	if self._animationController and self._stepProcessor.SetAnimationController then
		self._stepProcessor:SetAnimationController(self._animationController)
	end
	
	-- Initialize switch handler
	self._switchHandler = SwitchHandler.new(
		self._battleState,
		self._sceneManager,
		self._animationController,
		self._messageQueue
	)
	
	-- Initialize post-battle handler
	self._postBattleHandler = PostBattleHandler.new(self._messageQueue, self._uiController)
	
	-- Initialize options manager
	self._optionsManager = BattleOptionsManager.new()
	
	-- Setup options manager callbacks
	self:_setupOptionsCallbacks()
	
	-- Initialize UI
	self._uiController:Initialize()

	-- Setup CreatureAmount indicators initially
	local pd = nil
	pcall(function()
		pd = ClientData:Get()
	end)
	local playerParty = (pd and pd.Party) or {}
	if self._uiController and self._uiController.ClearCreatureAmount then
		self._uiController:ClearCreatureAmount()
	end
	if self._uiController and self._uiController.RefreshCreatureAmount then
		self._uiController:RefreshCreatureAmount(self._battleInfo.Type, playerParty, self._battleInfo.TrainerParty)
	end
	
	-- Hide You UI initially (will be positioned off-screen when creature is sent out)
	local youUI = self._battleUI:FindFirstChild("You")
	if youUI then
		youUI.Visible = false
	end
	-- Hide Foe UI initially as well; it will be shown via SlideFoeUIIn on send-out
	local foeUI = self._battleUI:FindFirstChild("Foe")
	if foeUI then
		foeUI.Visible = false
	end
	
    -- Do not connect legacy UI buttons; interactions are managed by OptionsManager
	
	-- Setup party integration callbacks
	self:_setupPartyCallbacks()
	
	-- Set camera to battle mode
	self._camera.CameraType = Enum.CameraType.Scriptable
	self._camera.FieldOfView = 45
	
	-- Disable movement and hide TopBar
	CharacterFunctions:SetSuppressed(true)
	CharacterFunctions:CanMove(false)
	local UI = getUI()
	if UI and UI.TopBar then
		UI.TopBar:SetSuppressed(true)
		UI.TopBar:Hide()
	end
	
	-- Load battle scene
	local sceneLoaded = self._sceneManager:LoadScene(battleInfo.ChunkName)
	if not sceneLoaded then
		warn("[BattleSystemV2] Failed to load battle scene")
		self:EndBattle()
		return
	end
	
	-- Take pre-battle party snapshot for evolution detection
	local partyData = self:_getPartyData()
	if partyData and self._postBattleHandler then
		self._postBattleHandler:TakePreBattleSnapshot(partyData)
	end
	
	-- Play exclamation animation with explicit battle type to drive correct music
	-- Ensure cinematic bars are closed before running the exclamation mark
	pcall(function()
		local pg = game.Players.LocalPlayer.PlayerGui
		local gameUI = pg and pg:FindFirstChild("GameUI")
		local blackBars = gameUI and gameUI:FindFirstChild("BlackBars")
		if blackBars and blackBars:IsA("ImageLabel") then
			UIFunctions:BlackBars(false, blackBars)
		end
	end)
	UIFunctions:DoExclamationMark(self._exclamationMark, { BattleType = battleInfo.Type })
	task.wait(0.3) -- Let exclamation be visible
	
	-- Initialize camera controller AFTER exclamation (ensures all scene children are ready)
	local scene = self._sceneManager:GetScene()
	self._cameraController = CameraController.new(self._camera, scene)
	print("[BattleSystemV2] Camera controller initialized after exclamation")
	
	-- Spawn creatures
	self:_spawnInitialCreatures()
	
	-- Run battle intro sequence based on type
	if battleInfo.Type == "Wild" then
		self:_wildEncounterIntro()
	elseif battleInfo.Type == "Trainer" then
		self:_trainerBattleIntro()
	end
end

--[[
	Processes a turn result from the server
	@param data Turn result data
]]
function BattleSystemV2:ProcessTurnResult(data: any)
	print("[BattleSystemV2] Processing turn result")
	print("[BattleSystemV2] TurnResult data keys:", table.concat(self:_getTableKeys(data), ", "))

	-- Guard: we're now in a processing window; suppress mid-turn UI resurfacing
	self._inTurnProcessing = true
	-- Disable option interactions and hide any visible menus during turn processing
	if self._optionsManager then
		self._optionsManager:SetInteractionEnabled(false)
		self._optionsManager:HideAll()
	end
	
	-- Update TurnId for client requests (replay protection)
	if type(data.TurnId) == "number" and self._battleState then
		self._battleState.TurnId = data.TurnId
		-- Debug
		-- print("[BattleSystemV2] Updated TurnId to", data.TurnId)
	end
	
	-- Reset transient server flags unless explicitly set in this result
	if self._battleState and self._battleState.SetSwitchMode then
		self._battleState:SetSwitchMode(nil)
	end

	-- Update battle state from server
	if data.PlayerCreature then
		self._battleState:UpdatePlayerCreature(data.PlayerCreature, data.PlayerCreatureIndex or 1)
		-- Debug: Log player creature HP
		print("[BattleSystemV2] Player creature HP:", data.PlayerCreature.Stats and data.PlayerCreature.Stats.HP or "nil", "CurrentHP:", data.PlayerCreature.CurrentHP or "nil")
	end
	
	-- Only update FoeCreature on client when the server intends it (not just because HP snapshot changed).
	-- If the step list contains an enemy SendOut, defer UI update to that step's spawn.
	local hasEnemySendOut = false
	if data.Enemy and type(data.Enemy) == "table" then
		for _, s in ipairs(data.Enemy) do
			if type(s) == "table" and s.Type == "Switch" and s.Action == "SendOut" then
				hasEnemySendOut = true
				break
			end
		end
	end
	if data.FoeCreature and (not hasEnemySendOut) then
		self._battleState:UpdateFoeCreature(data.FoeCreature)
		-- Debug: Log foe creature HP
		print("[BattleSystemV2] Foe creature HP:", data.FoeCreature.Stats and data.FoeCreature.Stats.HP or "nil", "CurrentHP:", data.FoeCreature.CurrentHP or "nil")
	end
	
	-- Update cached creature names for message formatting
	if data.PlayerCreature and data.FoeCreature then
		BattleMessageGenerator.UpdateCreatureNames(data.PlayerCreature.Name, data.FoeCreature.Name)
	end
	
    -- Update switch mode
	if data.SwitchMode then
		self._battleState:SetSwitchMode(data.SwitchMode)
	end
	
	-- Lock actions during turn processing
	if self._actionHandler then
		self._actionHandler:Lock()
	end
	
    -- Hide battle UI during processing
    if self._optionsManager then
        self._optionsManager:HideAll()
    end
	
	-- Reset turn completion flag
	self._turnCompleted = false
	
	-- Store HP data for deferred UI updates (wait for Hit animation markers)
	-- This MUST happen before step processing so Hit markers can access the data
    if data.HP then
		-- Count how many move steps we have (each will trigger a Hit marker)
		local moveSteps = 0
		if data.Friendly then
			for _, step in ipairs(data.Friendly) do
                if type(step) == "table" and step.Type == "Move" then
                    -- Skip non-attacking/heal-only moves (no attack animation/hit marker)
                    local moveName = step.Move or step.MoveName
                    local def = moveName and MovesModule[moveName] or nil
                    local isHealOnly = def and type(def.HealsPercent) == "number" and def.HealsPercent > 0
                    if not isHealOnly then
                        moveSteps = moveSteps + 1
                    end
				end
			end
		end
		if data.Enemy then
			for _, step in ipairs(data.Enemy) do
                if type(step) == "table" and step.Type == "Move" then
                    -- Enemy heal-only moves also shouldn't count towards hit markers
                    local moveName = step.Move or step.MoveName
                    local def = moveName and MovesModule[moveName] or nil
                    local isHealOnly = def and type(def.HealsPercent) == "number" and def.HealsPercent > 0
                    if not isHealOnly then
                        moveSteps = moveSteps + 1
                    end
				end
			end
		end
		
		self._battleState:SetPendingHP(data.HP, moveSteps)
		print("[BattleSystemV2] Set pending HP data, expecting", moveSteps, "Hit markers")
	end

	-- Pre-compute incoming player damage from enemy steps for this turn.
	-- This allows heal-only moves (e.g., Perch) to display healed HP before enemy damage lands.
	local incomingPlayerDamageAbs = 0
	if data.Enemy then
		for _, step in ipairs(data.Enemy) do
			if type(step) == "table" and step.Type == "Move" and type(step.HPDelta) == "table" and type(step.HPDelta.Player) == "number" then
				local delta = step.HPDelta.Player
				if delta < 0 then incomingPlayerDamageAbs += (-delta) end
			end
		end
	end
	if self._stepProcessor and type(data.HP) == "table" then
		local finalHP = tonumber(data.HP.Player) or nil
		local finalMax = tonumber(data.HP.PlayerMax) or nil
		if finalHP and finalMax then
			self._stepProcessor:SetIncomingDamageContext({
				incomingPlayerDamageAbs = incomingPlayerDamageAbs,
				finalPlayerHP = finalHP,
				finalPlayerMaxHP = finalMax,
			})
		end
	end
	
	-- Fallback: ensure faint step exists if HP hits 0 and server omitted it (e.g., switch-damage path)
	local function ensureFaintIfMissing()
		if not data or not data.HP then return end
		local playerZero = (type(data.HP.Player) == "number") and (data.HP.Player <= 0)
		local foeZero = (type(data.HP.Enemy) == "number") and (data.HP.Enemy <= 0)
		local hasFaint = false
		local function scan(list)
			if type(list) ~= "table" then return end
			for _, s in ipairs(list) do
				if type(s) == "table" and s.Type == "Faint" then
					hasFaint = true
					break
				end
			end
		end
		scan(data.Friendly)
		scan(data.Enemy)
		if not hasFaint then
			if playerZero then
				data.Enemy = data.Enemy or {}
				table.insert(data.Enemy, { Type = "Faint", Creature = (data.PlayerCreature and (data.PlayerCreature.Nickname or data.PlayerCreature.Name)) or "Your creature", IsPlayer = true })
			elseif foeZero then
				data.Friendly = data.Friendly or {}
				table.insert(data.Friendly, { Type = "Faint", Creature = (data.FoeCreature and (data.FoeCreature.Nickname or data.FoeCreature.Name)) or "Foe", IsPlayer = false })
			end
		end
	end
	ensureFaintIfMissing()
	
	-- Determine if foe fainted in friendly steps (used to gate enemy steps until faint animation finishes)
	local foeFaintedInFriendly = false
	if data.Friendly and type(data.Friendly) == "table" then
		for _, step in ipairs(data.Friendly) do
			if step.Type == "Faint" then
				local foeCreatureName = (self._battleState.FoeCreature and (self._battleState.FoeCreature.Nickname or self._battleState.FoeCreature.Name)) or ""
				if step.IsPlayer == false or step.Creature == foeCreatureName then
					foeFaintedInFriendly = true
					print("[BattleSystemV2] Foe fainted in friendly steps - will defer enemy steps")
					break
				end
			end
		end
	end

	-- If foe fainted in friendly steps, defer enemy steps until faint animation completes
	if foeFaintedInFriendly then
		self._deferredEnemySteps = data.Enemy
		self._waitingForFoeFaintAnim = true
	else
		self._deferredEnemySteps = nil
		self._waitingForFoeFaintAnim = false
	end

    -- Reset per-turn enemy processing guard
    self._enemyProcessingActive = false

    -- Process friendly actions (player) sequentially and wait for each to complete
	if data.Friendly and type(data.Friendly) == "table" then
		print("[BattleSystemV2] Processing", #data.Friendly, "friendly steps")
		-- Debug: Log all friendly steps
		for i, step in ipairs(data.Friendly) do
			print("[BattleSystemV2] Friendly step", i, ":", step.Type or "nil", "Action:", step.Action or "nil", "Creature:", step.Creature or "nil")
		end

		-- Special ordering for preview voluntary switch: ensure opponent send-out happens before player's recall
		local function hasPlayerRecall(list)
			for _, s in ipairs(list) do
				if type(s) == "table" and s.Type == "Switch" and s.Action == "Recall" then return true end
			end
			return false
		end
		local function extractEnemySendOut(list)
			if type(list) ~= "table" then return nil end
			for idx, s in ipairs(list) do
				if type(s) == "table" and s.Type == "Switch" and s.Action == "SendOut" and s.IsPlayer == false then
					return table.remove(list, idx)
				end
			end
			return nil
		end

		local processFriendly = function()
			self:_processStepsSequentially(data.Friendly, true, function()
			print("[BattleSystemV2] All friendly steps completed")
			-- After friendly steps complete, either defer or process enemy steps immediately
			if self._waitingForFoeFaintAnim then
				print("[BattleSystemV2] Deferring enemy steps until foe faint animation completes")
			else
				-- Add slight pacing delay before enemy actions to improve readability
				local hasEnemy = (data.Enemy and type(data.Enemy) == "table" and #data.Enemy > 0)
				if hasEnemy then
					print("[BattleSystemV2] Adding 0.5s delay before enemy steps")
					task.delay(0.5, function()
						self:_processEnemySteps(data)
					end)
				else
					self:_processEnemySteps(data)
				end
			end
			end)
		end

		if hasPlayerRecall(data.Friendly) then
			local enemySendOutFirst = extractEnemySendOut(data.Enemy)
			if enemySendOutFirst then
				print("[BattleSystemV2] Preview switch ordering fix: processing enemy SendOut before player Recall")
				self._stepProcessor:ProcessStep(enemySendOutFirst, false, function()
					processFriendly()
				end)
			else
				processFriendly()
			end
		else
			processFriendly()
		end
	else
		-- No friendly steps, process enemy steps immediately
		print("[BattleSystemV2] No friendly steps to process")
		self:_processEnemySteps(data)
	end
	
	-- Wait for all messages to finish
	self._messageQueue:WaitForDrain()

	-- Safety: in rare edge cases where no branch re-shows options (due to
	-- server step composition or cancelled tweens), ensure the options are
	-- visible once turn processing is complete and no end/forced-switch is pending.
	if (not self._ending)
		and (not self._inTurnProcessing)
		and (not self._pendingBattleOver)
		and (self._battleState ~= nil)
		and (self._battleState.SwitchMode ~= "Forced")
		and self._optionsManager and self._optionsManager.GetState then
		local st = self._optionsManager:GetState()
		if st ~= "BattleOptions" then
			self._optionsManager:SetInteractionEnabled(true)
			self._optionsManager:ShowBattleOptions(true)
		end
	end
	
	-- Note: Turn end conditions are now handled by _checkTurnEndConditions after all steps complete
end

-- Called by StepProcessor after faint animation completes
function BattleSystemV2:OnFaintAnimationComplete(isPlayer: boolean)
    if (not isPlayer) and self._waitingForFoeFaintAnim then
        print("[NewTestLog] ResumeAfterFaint: foe faint animation complete, checking enemy steps")
        local deferred = self._deferredEnemySteps
        self._deferredEnemySteps = nil
        self._waitingForFoeFaintAnim = false
        
        -- Process any deferred XP events now that faint animation is complete
        if self._deferredXPEvents and #self._deferredXPEvents > 0 then
            print("[NewTestLog] ResumeAfterFaint: processing", #self._deferredXPEvents, "deferred XP events")
            for _, xpEvent in ipairs(self._deferredXPEvents) do
                self:HandleBattleEvent(xpEvent)
            end
            self._deferredXPEvents = {}
        end
        
        if deferred and #deferred > 0 then
            -- Check if enemy steps are still valid (foe might have been KO'd and is being replaced)
            -- Filter out invalid steps (e.g., heal/attack for a fainted creature being replaced)
            local validSteps = {}
            for _, step in ipairs(deferred) do
                -- Allow Switch steps (creature send-outs) even after faint
                -- Skip other action steps if they're for an action that can't happen now
                if step.Type == "Switch" then
                    table.insert(validSteps, step)
                    print("[NewTestLog] ResumeAfterFaint: keeping Switch step")
                elseif step.Type ~= "Move" and step.Type ~= "Heal" and step.Type ~= "Item" then
                    -- Keep non-action steps (messages, etc.)
                    table.insert(validSteps, step)
                    print("[NewTestLog] ResumeAfterFaint: keeping non-action step:", step.Type)
                else
                    print("[NewTestLog] ResumeAfterFaint: skipping invalid step after faint:", step.Type)
                end
            end
            
            if #validSteps > 0 then
                -- Build a synthetic data table to process only valid enemy steps now
                local d = { Enemy = validSteps }
                self:_processEnemySteps(d)
            else
                print("[NewTestLog] ResumeAfterFaint: no valid enemy steps to process")
                -- No valid steps - check if battle should end
                if self._pendingBattleOver then
                    if self._moveReplaceActive then
                        print("[NewTestLog] ResumeAfterFaint: MoveReplace active → deferring BattleOver")
                        return
                    end
                    print("[NewTestLog] ResumeAfterFaint: pending battle over detected, ending battle")
                    -- Clear processing flag and ensure all messages complete before ending
                    if self._messageQueue and self._messageQueue.WaitForDrain then
                        self._messageQueue:WaitForDrain()
                    end
                    self._inTurnProcessing = false
                    if self._optionsManager then self._optionsManager:SetInteractionEnabled(true) end
                    self._pendingBattleOver = false
                    self:EndBattle()
                else
                    print("[NewTestLog] ResumeAfterFaint: ending turn normally")
                    self:_checkTurnEndConditions({})
                end
            end
        else
            print("[NewTestLog] ResumeAfterFaint: no deferred enemy steps")
            -- No enemy steps at all - check if battle should end
            if self._pendingBattleOver then
                if self._moveReplaceActive then
                    print("[NewTestLog] ResumeAfterFaint: MoveReplace active → deferring BattleOver (no enemy steps)")
                    return
                end
                print("[NewTestLog] ResumeAfterFaint: pending battle over detected (no enemy steps), ending battle")
                -- Clear processing flag and ensure all messages complete before ending
                if self._messageQueue and self._messageQueue.WaitForDrain then
                    self._messageQueue:WaitForDrain()
                end
                self._inTurnProcessing = false
                if self._optionsManager then self._optionsManager:SetInteractionEnabled(true) end
                self._pendingBattleOver = false
                self:EndBattle()
            else
                print("[NewTestLog] ResumeAfterFaint: ending turn normally (no enemy steps)")
                self:_checkTurnEndConditions({})
            end
        end
    end
end

--[[
	Processes steps sequentially, waiting for each to complete
	@param steps Array of step data
	@param isPlayer Whether these are player steps
	@param onComplete Callback when all steps complete
]]
function BattleSystemV2:_processStepsSequentially(steps: {any}, isPlayer: boolean, onComplete: (() -> ())?)
	local currentIndex = 1
	
	local function processNextStep()
		if currentIndex > #steps then
			-- All steps completed
			if onComplete then
				onComplete()
			end
			return
		end
		
		local step = steps[currentIndex]
		print("[BattleSystemV2] Processing step", currentIndex, "of", #steps, "- Type:", step.Type or "nil", "IsPlayer:", isPlayer)
		
		if type(step) == "table" and step.Type then
			self._stepProcessor:ProcessStep(step, isPlayer, function()
				print("[BattleSystemV2] Step", currentIndex, "completed")
				currentIndex = currentIndex + 1
				processNextStep()
			end)
        else
            -- Handle legacy escape failure token for backward compatibility
            if step == "FailedRunAttempt" then
                self._messageQueue:Enqueue("You Coudn't get away!")
                self._messageQueue:OnDrained(function()
                    currentIndex = currentIndex + 1
                    processNextStep()
                end)
            else
                warn("[BattleSystemV2] Skipping invalid step:", step)
                currentIndex = currentIndex + 1
                processNextStep()
            end
        end
	end
	
	processNextStep()
end

--[[
	Processes enemy steps sequentially
	@param data Turn result data
]]
function BattleSystemV2:_processEnemySteps(data: any)
    -- Re-entrancy guard: prevent processing the same enemy steps twice
    if self._enemyProcessingActive then
        print("[BattleSystemV2] Enemy step processing already active - skipping duplicate call")
        return
    end
    self._enemyProcessingActive = true

    if data.Enemy and type(data.Enemy) == "table" then
        print("[BattleSystemV2] Processing", #data.Enemy, "enemy steps")
        self:_processStepsSequentially(data.Enemy, false, function()
            print("[BattleSystemV2] All enemy steps completed")
            self._enemyProcessingActive = false
            -- After all steps complete, check for turn end conditions
            self:_checkTurnEndConditions(data)
        end)
    else
        self._enemyProcessingActive = false
        -- No enemy steps, check turn end conditions immediately
        self:_checkTurnEndConditions(data)
    end
end

--[[
	Checks turn end conditions and starts next turn if appropriate
	@param data Turn result data
]]
function BattleSystemV2:_checkTurnEndConditions(data: any)
    -- Prevent duplicate turn completion
    if self._turnCompleted then
        -- Allow re-entry when in forced switch mode after player faint
        local allowReentry = (self._battleState and self._battleState.SwitchMode == "Forced")
        if not allowReentry then
            print("[BattleSystemV2] Turn already completed - ignoring duplicate call")
            return
        end
    end
	
	self._turnCompleted = true
	print("[BattleSystemV2] Processing turn end conditions")
	
    -- Check if foe fainted
    local foeFainted = false
    local enemySendOut = false
    if data.Enemy and type(data.Enemy) == "table" then
        for _, step in ipairs(data.Enemy) do
            if step.Type == "Faint" then
                foeFainted = true
            elseif step.Type == "Switch" and step.Action == "SendOut" then
                enemySendOut = true
            end
        end
        if foeFainted then
            print("[BattleSystemV2] Foe fainted")
        end
    end
	
	-- Check if there was a player switch (for "Go X!" message deferral)
	local playerSwitched = false
	if data.Friendly and type(data.Friendly) == "table" then
		for _, step in ipairs(data.Friendly) do
			if step.Type == "Switch" and step.Action == "SendOut" then
				playerSwitched = true
				print("[BattleSystemV2] Player switched - deferring Go message until spawn completes")
				break
			end
		end
	end
	
	-- Check for battle end
	-- If server flagged end in the result, or if a BattleOver event was deferred, end cleanly now
	if self._pendingBattleOver then
		-- Clear processing flag and ensure all messages/effects complete before ending
		self:_safeWaitForDrain(3)
        self._inTurnProcessing = false
        if self._optionsManager then self._optionsManager:SetInteractionEnabled(true) end
		self._pendingBattleOver = false
		self:EndBattle()
		return
	elseif data.BattleEnd then
		-- If server flagged end as part of this result, honor it only after friendly/enemy steps complete
		-- and after messages drain; if a BattleOver event also came early, we will reach here soon anyway.
		self._inTurnProcessing = false
		if self._optionsManager then self._optionsManager:SetInteractionEnabled(true) end
		self:_safeWaitForDrain(3)
		self:EndBattle()
    elseif foeFainted then
        if enemySendOut then
            -- Do not end; normal flow will finish, then StartNextTurn will be called
            print("[BattleSystemV2] Foe fainted - enemy will SendOut; continue flow")
        else
            -- No enemy send-out provided; treat as potential battle end (wild or trainer with no party)
            print("[BattleSystemV2] Foe fainted - waiting for battle end sequence")
        end
	elseif playerSwitched then
		-- Player switched - start next turn after all steps complete
		print("[BattleSystemV2] Player switched - starting next turn after all steps complete")
		-- Wait for message queue to drain before unlocking and starting next turn
		self:_safeWaitForDrain(3)
		if self._actionHandler then self._actionHandler:Unlock() end
        self._inTurnProcessing = false
        if self._optionsManager then self._optionsManager:SetInteractionEnabled(true) end
		self:StartNextTurn()
	elseif self._battleState and self._battleState.SwitchMode == "Forced" then
		-- Forced switch: if a BattleOver is pending (e.g., loss then forced switch), end immediately.
		if self._pendingBattleOver then
			if self._messageQueue and self._messageQueue.WaitForDrain then
				self._messageQueue:WaitForDrain()
			end
			self._inTurnProcessing = false
			if self._optionsManager then self._optionsManager:SetInteractionEnabled(true) end
			self._pendingBattleOver = false
			self:EndBattle()
			return
		end
		-- Otherwise, keep options hidden/disabled while waiting for Switch TurnResult
		print("[BattleSystemV2] Forced switch active - waiting for switch to complete")
		self._inTurnProcessing = false
		if self._optionsManager then self._optionsManager:SetInteractionEnabled(false) end
		return
	else
		-- Wait for message queue to drain before unlocking and starting next turn
		self:_safeWaitForDrain(3)
		if self._actionHandler then self._actionHandler:Unlock() end
        self._inTurnProcessing = false
        if self._optionsManager then self._optionsManager:SetInteractionEnabled(true) end
		self:StartNextTurn()
	end
end

--[[
	Starts the next turn (shows battle options)
]]
function BattleSystemV2:StartNextTurn()
	print("[BattleSystemV2] Starting next turn")
	
	-- Don't start next turn if battle has ended
	if not self._battleState or not self._battleInfo then
		print("[BattleSystemV2] Cannot start next turn - battle has ended")
		return
	end
	
	-- Clear any stale forced switch mode before starting a new player turn
	if self._battleState and self._battleState.SetSwitchMode then
		self._battleState:SetSwitchMode(nil)
	end
	
	self._battleState:IncrementTurn()
	
	-- Show battle options using the new options manager
	if self._optionsManager then
		print("[BattleSystemV2] Showing battle options via options manager")
		self._optionsManager:SetInteractionEnabled(true)
		self._optionsManager:ShowBattleOptions(true)
	else
		warn("[BattleSystemV2] Options manager not initialized")
	end
	
	-- Start camera cycle
	if self._cameraController then
		self._cameraController:StartCycle("Default", 3)
	end
end

--[[
	Handles escape success
]]
function BattleSystemV2:HandleEscapeSuccess()
	print("[BattleSystemV2] Escape success - starting run away sequence")
	-- Stop any active battle camera cycles/tweens immediately
	if self._cameraController then
		self._cameraController:StopCycle()
	end
	self._messageQueue:Enqueue("Got away safely!")
	self._messageQueue:OnDrained(function()
		self:_runAwaySequence()
	end)
end

--[[
	Handles escape failure
]]
function BattleSystemV2:HandleEscapeFailure()
	self._messageQueue:Enqueue("You Coudn't get away!")
	self._messageQueue:OnDrained(function()
		self:StartNextTurn()
	end)
end

--[[
	Ends the battle and cleans up
]]
function BattleSystemV2:EndBattle()
	print("[BattleSystemV2] Ending battle")
    if self._ending then
        -- Already ending; avoid double-running blackout/cleanup
        return
    end
    self._ending = true
	-- Start proper battle end sequence
	self:_runBattleEndSequence()
end

--[[
	Internal: Runs the proper battle end sequence
]]
function BattleSystemV2:_runBattleEndSequence()
	print("[BattleSystemV2] Starting battle end sequence")
	
	-- 1. Hide battle options immediately
	if self._optionsManager then
		self._optionsManager:HideAll()
	end
	
	-- 2. Wait for any pending messages to finish
	self._messageQueue:WaitForDrain()
	
    -- 3. Fade trainer back in for AfterSayInBattle (trainer-only win), then show dialogue
	if self._battleInfo and self._battleInfo.Type == "Trainer" and self._battleInfo.TrainerDialogue then
		-- Only show defeat dialogue if player won (not if player lost)
		local playerWon = self._battleEndReason == "Win" or (not self._battleEndReason and not self._lossReason)
		if playerWon then
            -- Bring trainer clone back and tween to spawn before dialogue
            local agent = TrainerIntroController:GetActive()
            local _, foeSpawn = self._sceneManager:GetSpawnPoints()
            if agent and foeSpawn then
                agent:PlaceAtSpawn(foeSpawn.CFrame) -- re-establish spawn/behind frames
                agent:FadeInAndTweenToSpawn(1.2,false)
				local animIdMap = {
					Clap = "74642253257972",
					Ashamed = "120749917990524",
					Sad = "122010512980716",
				}
				local dialogue = self._battleInfo.TrainerDialogue
				local animKey = dialogue and dialogue.AfterInBattle_Anim
				local toPlay = (type(animKey) == "string") and animIdMap[animKey] or nil
				if not toPlay then
					local pool = {animIdMap.Clap, animIdMap.Ashamed, animIdMap.Sad}
					toPlay = pool[math.random(1, #pool)]
				end
				pcall(function()
					agent:PlayAnimation(toPlay, 0.01, true)
				end)
            end
			local dialogue = self._battleInfo.TrainerDialogue
			if dialogue.AfterSayInBattle and type(dialogue.AfterSayInBattle) == "table" then
				print("[BattleSystemV2] Showing trainer defeat dialogue (player won)")
				-- Enqueue each line as a battle message
				for _, line in ipairs(dialogue.AfterSayInBattle) do
					local text = type(line) == "string" and line or (type(line) == "table" and line.Text) or ""
					if text ~= "" then
						self._messageQueue:Enqueue(text)
					end
				end
				-- Wait for dialogue to finish
				self._messageQueue:WaitForDrain()
			end
		else
			print("[BattleSystemV2] Player lost - not showing trainer defeat dialogue")
		end
	end
	
	-- 4. Small pause before blackout for readability
	task.wait(0.65)
	-- Despawn enemy with hologram effect and slide UI off screen (handled earlier during faint)

	self:_startBlackoutSequence()
end

--[[
	Internal: Despawns enemy with hologram effect and slides UI off screen
]]
function BattleSystemV2:_despawnEnemyAndSlideUI()
	print("[BattleSystemV2] Battle end sequence - UI already slid out during faint animation")
	
	-- Note: Both the foe model despawn and UI slide already happened during the faint animation
	-- This method is called as part of the battle end sequence but the work is already done
	print("[BattleSystemV2] Foe model and UI already handled by faint animation")
end

--[[
	Internal: Starts the blackout sequence
]]
function BattleSystemV2:_startBlackoutSequence()
	print("[BattleSystemV2] Starting blackout sequence")
	
	-- Get UI references
	local PlayerGui = game.Players.LocalPlayer.PlayerGui
	local GameUI = PlayerGui:WaitForChild("GameUI")
	local pg = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui")
	local gui = pg:FindFirstChild("GameUI") or pg:WaitForChild("GameUI")
	local Blackout = gui:WaitForChild("Blackout")
	local TopBar = GameUI:WaitForChild("TopBar")
	
	-- Hide battle UI
	self._battleUI.Visible = false
	
	-- Start blackout fade in
	Blackout.Visible = true
	Blackout.BackgroundTransparency = 1
	
	-- Fade to black
	local TweenService = game:GetService("TweenService")
	local FadeInTween = TweenService:Create(Blackout, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0
	})
	FadeInTween:Play()
	
	-- Wait for fade to complete
	FadeInTween.Completed:Wait()
	
	-- Wait 0.5 seconds as requested
	task.wait(0.5)
	
	-- Clean up battle scene during blackout, but keep ClientData intact (PendingCapture)
	self:_cleanupBattleScene()
	
	-- Reset camera during blackout
	self:_resetCamera()
	
	-- End encounter/trainer battle music and re-enable movement
	pcall(function()
		local MusicManager = require(script.Parent.MusicManager)
		if self._battleInfo and self._battleInfo.Type == "Trainer" then
			MusicManager:EndTrainerBattleMusic()
		else
			MusicManager:EndEncounterMusic()
		end
	end)
	self:_endEncounter()

	-- Hard-close Party Integration to ensure SendOut is hidden/inactive post-battle
	if self._partyIntegration and self._partyIntegration.Close then
		self._partyIntegration:Close()
	end
	
	-- Fade out blackout
	local FadeOutTween = TweenService:Create(Blackout, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1
	})
	
	-- If this end was due to a capture, display the Caught UI midway through blackout
	if self._caughtReason then
		self._caughtReason = false
		-- Fire Caught UI asynchronously so blackout fade-out isn't blocked by its flow
		task.spawn(function()
			pcall(function()
				local UI = require(script.Parent.Parent.UI)
				if UI and UI.Caught and UI.Caught.Show then
					local ClientData = require(script.Parent.Parent.Plugins.ClientData)
					local data = ClientData:Get()
					local captured = data and data.PendingCapture
					if captured then UI.Caught:Show(captured) end
				end
			end)
		end)
	elseif self._lossReason then
		-- Player lost - optionally customize defeat handling for specific trainers
		local handledCustomLoss = false
		if self._battleInfo and self._battleInfo.Type == "Trainer" and self._battleInfo.TrainerId == "Rival_Kyro_Intro" then
			-- Kyro intro battle: do NOT relocate/blackout to a heal station; just end and heal here
			print("[BattleSystemV2] Player defeated vs Kyro (Rival_Kyro_Intro) - skipping relocation and healing in place")
			self._lossReason = false
			handledCustomLoss = true
			-- Server-authoritative heal (Professor heals you up)
			pcall(function()
				Events.Request:InvokeServer({"HealParty"})
			end)
			-- Signal to listeners (e.g., cutscenes) that post-battle flow is complete without relocation
			pcall(function()
				local ChunkLoader = require(script.Parent:WaitForChild("ChunkLoader"))
				local chunkName = (ChunkLoader:GetCurrentChunk() and ChunkLoader:GetCurrentChunk().Model and ChunkLoader:GetCurrentChunk().Model.Name) or nil
				RelocationSignals.FirePostBattleRelocated({ Reason = "KyroIntro", Chunk = chunkName })
			end)
		end
		if not handledCustomLoss then
			self._lossReason = false
			print("[BattleSystemV2] Player defeated - all creatures fainted")
			-- Handle player defeat sequence (similar to legacy BlackoutToCatchCare)
			self:_handlePlayerDefeat()
		end
	else
		-- Show evolution UI while the screen is still black (non-capture flow)
		self:_showEvolutionUI()
	end
	
	FadeOutTween:Play()
	
	-- Show TopBar after fade out
	FadeOutTween.Completed:Connect(function()
		Blackout.Visible = false
		if TopBar then
			TopBar.Visible = true
		end
		-- Victory music is ended after Caught summary; do not resume chunk here
		
		-- Refresh Party UI with updated creature data (XP, levels, etc.)
		local success, UI = pcall(function()
			return require(script.Parent.Parent.UI)
		end)
		if success and UI and UI.Party and UI.Party.UpdatePartyDisplay then
			UI.Party:UpdatePartyDisplay()
			print("[BattleSystemV2] Refreshed Party UI after battle")
		else
			print("[BattleSystemV2] Could not refresh Party UI - script path issue or UI not available")
		end
		
		-- Clear battle state
		self:_clearBattleState()
		-- Allow future ends
		self._ending = false
			
			-- Fire a universal post-battle signal so cutscenes can resume (e.g., Kyro intro win path)
			pcall(function()
				local ChunkLoader = require(script.Parent:WaitForChild("ChunkLoader"))
				local chunkName = (ChunkLoader:GetCurrentChunk() and ChunkLoader:GetCurrentChunk().Model and ChunkLoader:GetCurrentChunk().Model.Name) or nil
				RelocationSignals.FirePostBattleRelocated({ Reason = "End", Chunk = chunkName })
			end)
		
		print("[BattleSystemV2] Battle end sequence completed")
	end)
end

--[[
	Internal: Cleans up battle scene and models
]]
function BattleSystemV2:_cleanupBattleScene()
	print("[BattleSystemV2] Cleaning up battle scene")
	
	-- Clean up scene manager (this will destroy the battle scene)
	if self._sceneManager then
		self._sceneManager:Cleanup()
	end

	-- Ensure trainer intro clone is destroyed during blackout cleanup
	pcall(function()
		local TrainerIntroControllerModule = require(script.Parent.TrainerIntroController)
		TrainerIntroControllerModule:DestroyActive()
	end)
	
	-- Cleanup other modules
	if self._animationController then
		self._animationController:Cleanup()
	end
	
	if self._uiController then
		self._uiController:ResetUIPositions()  -- Reset UI positions before cleanup
		self._uiController:Cleanup()
	end
	
	if self._cameraController then
		self._cameraController:Cleanup()
	end
	
	if self._battleUIManager then
		self._battleUIManager:Cleanup()
	end
	
	-- Cleanup party integration to remove battle-specific UI elements
	if self._partyIntegration then
		self._partyIntegration:Close()
		print("[BattleSystemV2] Closed party integration to clean up battle UI elements")
	end
	
	if self._combatEffects then
		self._combatEffects:Cleanup()
	end
	
	if self._partyIntegration then
		self._partyIntegration:Close()
	end
	
	if self._postBattleHandler then
		self._postBattleHandler:ClearSnapshot()
	end
	
	if self._optionsManager then
		self._optionsManager:Cleanup()
	end
end

--[[
	Internal: Resets camera to normal mode
]]
function BattleSystemV2:_resetCamera()
	print("[BattleSystemV2] Resetting camera")
	
	local Camera = workspace.CurrentCamera
	Camera.FieldOfView = 70
	Camera.CameraType = Enum.CameraType.Custom
	Camera.CameraSubject = game.Players.LocalPlayer.Character:WaitForChild("Humanoid")
end

--[[
	Internal: Ends encounter to re-enable movement
]]
function BattleSystemV2:_endEncounter()
	print("[BattleSystemV2] Ending encounter")
	
	-- End encounter to re-enable movement and reset exclamation mark
	local EncounterZone = require(script.Parent:WaitForChild("EncounterZone"))
	EncounterZone:EndEncounter()
	
	-- End encounter music and restore chunk music
	pcall(function()
		local MusicManager = require(script.Parent.MusicManager)
		-- Always end encounter music; MusicManager will handle resume rules
		MusicManager:EndEncounterMusic()
	end)
end

--[[
	Internal: Shows switch preview choice UI (Yes/No)
	@param onComplete Callback to invoke when choice is made or proceeding normally
]]
function BattleSystemV2:_showSwitchPreviewChoice(onComplete: (() -> ())?)
	print("[BattleSystemV2] Showing switch preview choice UI")
	
	-- Get UI references
	local PlayerGui = game.Players.LocalPlayer.PlayerGui
	local GameUI = PlayerGui:WaitForChild("GameUI")
	local BattleUI = GameUI:WaitForChild("BattleUI")
	local ChoiceFrame = BattleUI:WaitForChild("Choice")
	local YesButton = ChoiceFrame:WaitForChild("Yes")
	local NoButton = ChoiceFrame:WaitForChild("No")
	
	-- Show the choice UI
	ChoiceFrame.Visible = true
	
	-- Track if choice was made to prevent double-firing
	local choiceMade = false
	
    -- Handle No button
    local noConnection
    noConnection = NoButton.MouseButton1Down:Connect(function()
		if choiceMade then return end
		choiceMade = true
		
		print("[BattleSystemV2] Player chose NO - proceeding with enemy send-out")
		ChoiceFrame.Visible = false
		
		-- Disconnect both handlers
		if noConnection then noConnection:Disconnect() end
		if self._yesConnection then self._yesConnection:Disconnect() end
		
		-- Clear the persistent message and proceed normally
		self._messageQueue:ClearPersistent()
		if onComplete then
			onComplete()
		end
	end)
	
    -- Handle Yes button
    self._yesConnection = YesButton.MouseButton1Down:Connect(function()
		if choiceMade then return end
		choiceMade = true
		
		print("[BattleSystemV2] Player chose YES - showing party UI for switch")
		ChoiceFrame.Visible = false
		
		-- Disconnect both handlers
		if noConnection then noConnection:Disconnect() end
		if self._yesConnection then self._yesConnection:Disconnect() end
		
		-- Clear the persistent message and show party UI for switching
		self._messageQueue:ClearPersistent()
		self:_showPartySwitchForPreview(onComplete)
	end)
end

-- Generic Yes/No choice using BattleUI.Choice; keeps current battle message persistent
function BattleSystemV2:_showYesNoChoice(onYes: (() -> ())?, onNo: (() -> ())?)
	local PlayerGui = game.Players.LocalPlayer.PlayerGui
	local GameUI = PlayerGui:WaitForChild("GameUI")
	local BattleUI = GameUI:WaitForChild("BattleUI")
	local ChoiceFrame = BattleUI:WaitForChild("Choice")
	local YesButton = ChoiceFrame:WaitForChild("Yes")
	local NoButton = ChoiceFrame:WaitForChild("No")

	ChoiceFrame.Visible = true
	local choiceMade = false

	local noConn
	noConn = NoButton.MouseButton1Down:Connect(function()
		if choiceMade then return end
		choiceMade = true
		ChoiceFrame.Visible = false
		if noConn then noConn:Disconnect() end
		if self._yesConnection then self._yesConnection:Disconnect() end
		self._messageQueue:ClearPersistent()
		if onNo then onNo() end
	end)

	self._yesConnection = YesButton.MouseButton1Down:Connect(function()
		if choiceMade then return end
		choiceMade = true
		ChoiceFrame.Visible = false
		if noConn then noConn:Disconnect() end
		if self._yesConnection then self._yesConnection:Disconnect() end
		self._messageQueue:ClearPersistent()
		if onYes then onYes() end
	end)
end

-- Finalizes the move replace flow: drains current messages, flushes buffered events, and ends if needed
function BattleSystemV2:_finalizeMoveReplaceFlow()
	-- Drain any queued messages first
	if self._messageQueue and self._messageQueue.WaitForDrain then
		self._messageQueue:WaitForDrain()
	end
	self._moveReplaceActive = false
	-- Flush buffered events recorded during the flow
	if self._deferredEventsDuringMoveReplace and #self._deferredEventsDuringMoveReplace > 0 then
		local list = self._deferredEventsDuringMoveReplace
		self._deferredEventsDuringMoveReplace = {}
		for _, ev in ipairs(list) do
			self:HandleBattleEvent(ev)
		end
	end
	-- If end was pending, end now; otherwise release turn lock
	if self._pendingBattleOver then
		self._pendingBattleOver = false
		self:EndBattle()
	else
		self._inTurnProcessing = false
	end
end

-- Darken a Color3 by factor (0..1)
local function _darken(c: Color3, factor: number): Color3
	factor = math.clamp(factor or 0.7, 0, 1)
	return Color3.new(c.R * factor, c.G * factor, c.B * factor)
end

-- Resolve type name from Types module reference
local function _typeNameFromRef(ref): string
	for name, tbl in pairs(TypesModule) do
		if tbl == ref then return name end
	end
	return "Unknown"
end

-- Populates a move button with data and styles
local function _applyMoveToButton(btn: GuiObject, moveName: string)
	local move = MovesModule[moveName]
	if not move then return end
	local desc = btn:FindFirstChild("Description")
	local nameLbl = btn:FindFirstChild("MoveName")
	local stat = btn:FindFirstChild("Stat")
	local typeLbl = btn:FindFirstChild("Type")
	if typeof(nameLbl) == "Instance" then (nameLbl :: TextLabel).Text = moveName end
	if typeof(desc) == "Instance" then (desc :: TextLabel).Text = tostring(move.Description or "") end
	if typeof(stat) == "Instance" then (stat :: TextLabel).Text = string.format("Power: %d", tonumber(move.BasePower) or 0) end
	local typeName = _typeNameFromRef(move.Type)
	if typeof(typeLbl) == "Instance" then (typeLbl :: TextLabel).Text = string.format("Type: %s", typeName) end
	-- Color styling
	if btn:IsA("GuiObject") and move.Type and move.Type.uicolor then
		btn.BackgroundColor3 = move.Type.uicolor
		local stroke = btn:FindFirstChildOfClass("UIStroke")
		if stroke then
			(stroke :: UIStroke).Color = _darken(move.Type.uicolor, 0.6)
		end
	end
end

-- Opens ReplaceMove UI for selecting which move to replace
function BattleSystemV2:_openReplaceMoveModal(creatureName: string, newMove: string, currentMoves: {string}, slotIndex: number)
	local PlayerGui = game.Players.LocalPlayer.PlayerGui
	local GameUI = PlayerGui:FindFirstChild("GameUI")
	if not GameUI then
		warn("[ReplaceMove] GameUI not found")
		return
	end
	local ReplaceMove = GameUI:FindFirstChild("ReplaceMove")
	if not ReplaceMove then
		warn("[ReplaceMove] UI not found - falling back to decline")
		local Request = ReplicatedStorage.Events.Request
		Request:InvokeServer({"MoveReplaceDecision", { SlotIndex = slotIndex, ReplaceIndex = 0, NewMove = newMove }})
		return
	end

    self._moveReplaceActive = true
    self._inTurnProcessing = true
    ReplaceMove.Visible = true

	-- Populate buttons
	local buttons: {GuiButton} = {}
	for i = 1, 4 do
		local b = ReplaceMove:FindFirstChild("Move" .. i)
		if b and b:IsA("GuiButton") then
			_applyMoveToButton(b, tostring(currentMoves[i] or ""))
			buttons[i] = b
		end
	end
	local replacingBtn = ReplaceMove:FindFirstChild("ReplacingMove")
	if replacingBtn and replacingBtn:IsA("GuiButton") then
		_applyMoveToButton(replacingBtn, newMove)
	end

	-- Hook buttons via UIFunctions
    local function openConfirmReplace(index: number)
		ReplaceMove.Visible = false
		local oldMove = tostring(currentMoves[index])
		local prompt = string.format("Are you sure you want to replace %s with %s?", oldMove, newMove)
		self._messageQueue:Enqueue(prompt)
		self._messageQueue:SetPersistent(true)
		self._messageQueue:OnDrained(function()
			self:_showYesNoChoice(function()
				-- YES → send decision
				local Request = ReplicatedStorage.Events.Request
				local ok = Request:InvokeServer({"MoveReplaceDecision", { SlotIndex = slotIndex, ReplaceIndex = index, NewMove = newMove }})
				if not ok then
					warn("[ReplaceMove] Server rejected replace decision")
				end
                -- Finalization is driven by server MoveReplaced event
			end, function()
				-- NO → reopen
				ReplaceMove.Visible = true
			end)
		end)
	end

	for i, b in pairs(buttons) do
		UIFunctions:NewButton(b, {"Action"}, {Click = "One", HoverOn = "One", HoverOff = "One"}, 0.2, function()
			openConfirmReplace(i)
		end)
	end

    if replacingBtn and replacingBtn:IsA("GuiButton") then
		UIFunctions:NewButton(replacingBtn, {"Action"}, {Click = "One", HoverOn = "One", HoverOff = "One"}, 0.2, function()
			ReplaceMove.Visible = false
			local prompt = string.format("Are you sure you want to give up learning %s?", newMove)
			self._messageQueue:Enqueue(prompt)
			self._messageQueue:SetPersistent(true)
			self._messageQueue:OnDrained(function()
				self:_showYesNoChoice(function()
					local Request = ReplicatedStorage.Events.Request
					local ok = Request:InvokeServer({"MoveReplaceDecision", { SlotIndex = slotIndex, ReplaceIndex = 0, NewMove = newMove }})
                    if not ok then warn("[ReplaceMove] Server rejected give up decision") end
                    -- Finalization is driven by server MoveDeclined event
				end, function()
					-- NO → reopen
					ReplaceMove.Visible = true
				end)
			end)
		end)
	end
end

-- Handles MoveReplacePrompt battle event
function BattleSystemV2:_handleMoveReplacePrompt(eventData: any)
	local creature = tostring(eventData.Creature or "")
	local move = tostring(eventData.Move or "")
	local currentMoves = (type(eventData.CurrentMoves) == "table" and eventData.CurrentMoves) or {}
	local slotIndex = tonumber(eventData.SlotIndex) or 1
    -- Activate gating immediately so BattleOver does not end the battle before the choice is made
    self._moveReplaceActive = true
	local prompt = string.format("%s wants to learn %s, should a move be removed and replaced?", creature, move)
	self._messageQueue:Enqueue(prompt)
	self._messageQueue:SetPersistent(true)
	self._messageQueue:OnDrained(function()
		self:_showYesNoChoice(function()
			-- YES → open selection UI
			self:_openReplaceMoveModal(creature, move, currentMoves, slotIndex)
		end, function()
            -- NO → send decline to server (finalization will occur after MoveDeclined event drains)
			local Request = ReplicatedStorage.Events.Request
			Request:InvokeServer({"MoveReplaceDecision", { SlotIndex = slotIndex, ReplaceIndex = 0, NewMove = move }})
            -- Do not end yet; wait for MoveDeclined BattleEvent to display and drain
		end)
	end)
end

--[[
	Internal: Shows party UI for voluntary switch during preview
	@param onComplete Callback to invoke when switch completes or is cancelled
]]
function BattleSystemV2:_showPartySwitchForPreview(onComplete: (() -> ())?)
	print("[BattleSystemV2] Showing party UI for preview switch")
	
	-- Use party integration if available (same as Creatures button behavior)
	if self._battleUIManager and self._battleUIManager._partyIntegration then
		local integration = self._battleUIManager._partyIntegration
		
		-- Store original callbacks
		local oldCompleteCallback = integration._callbacks.onSwitchComplete
		local oldCancelCallback = integration._callbacks.onSwitchCancelled
		
		-- Set up switch complete callback
		integration:OnSwitchComplete(function(selectedSlot)
			print("[BattleSystemV2] Party switch completed - Selected slot:", selectedSlot)
			
			-- Restore original callbacks
			if oldCompleteCallback then
				integration._callbacks.onSwitchComplete = oldCompleteCallback
			end
			if oldCancelCallback then
				integration._callbacks.onSwitchCancelled = oldCancelCallback
			end
			
			-- Send preview switch request to server (server validates AllowPreviewSwitch flag)
			if selectedSlot then
				print("[BattleSystemV2] Sending preview switch request to server for slot:", selectedSlot)
				local Events = game:GetService("ReplicatedStorage"):WaitForChild("Events")
				local Request = Events:WaitForChild("Request")
				
				-- Send with IsPreviewSwitch flag - server will validate this is allowed
				local success = Request:InvokeServer({"SwitchCreature", {Index = selectedSlot, IsPreviewSwitch = true}})
				if success then
					print("[BattleSystemV2] Preview switch successful")
				else
					warn("[BattleSystemV2] Preview switch failed")
				end
			end
			
			-- Call onComplete
			if onComplete then
				onComplete()
			end
		end)
		
		-- Set up cancel callback
		integration:OnSwitchCancelled(function()
			print("[BattleSystemV2] Party switch cancelled")
			
			-- Restore original callbacks
			if oldCompleteCallback then
				integration._callbacks.onSwitchComplete = oldCompleteCallback
			end
			if oldCancelCallback then
				integration._callbacks.onSwitchCancelled = oldCancelCallback
			end
			
			-- Call onComplete to proceed normally
			if onComplete then
				onComplete()
			end
		end)
		
		-- Open party UI via integration (same as Creatures button)
		-- Pass true to indicate this is a preview switch
		integration:OpenForVoluntarySwitch(true)
	else
		-- Fallback: open party directly
		warn("[BattleSystemV2] PartyIntegration not available for preview switch")
		local success, Party = pcall(require, script.Parent.Parent.UI.Party)
		if success and Party and Party.Open then
			Party:Open(false)
		end
		-- Complete immediately as fallback
		if onComplete then
			onComplete()
		end
	end
end

--[[
	Internal: Shows evolution UI if needed
]]
function BattleSystemV2:_showEvolutionUI()
	print("[BattleSystemV2] Checking for evolutions")
	
	-- Check if we have pending evolutions from the server
	if self._pendingEvolutions and #self._pendingEvolutions > 0 then
		print("[BattleSystemV2] Found", #self._pendingEvolutions, "pending evolution(s)")
		
		local success, err = pcall(function()
			local EvolutionUI = require(script.Parent:WaitForChild("EvolutionUI"))
			if EvolutionUI and EvolutionUI.Show then
				-- Show each evolution in sequence
				for _, evolutionData in ipairs(self._pendingEvolutions) do
					print("[BattleSystemV2] Showing evolution:", evolutionData.OldSpecies, "->", evolutionData.NewSpecies)
					EvolutionUI:Show(
						evolutionData.OldSpecies,
						evolutionData.NewSpecies,
						evolutionData.Nickname
					)
				end
			else
				warn("[BattleSystemV2] EvolutionUI.Show not found")
			end
		end)
		
		if not success then
			warn("[BattleSystemV2] Error showing evolution UI:", err)
		end
		
		-- Clear pending evolutions
		self._pendingEvolutions = {}
	else
		print("[BattleSystemV2] No pending evolutions, checking snapshot")
		
		-- Fallback to snapshot-based evolution detection
		pcall(function()
			local EvolutionUI = require(script.Parent:WaitForChild("EvolutionUI"))
			local pre = self._postBattleHandler and self._postBattleHandler:GetPreBattleSnapshot()
			EvolutionUI:MaybeShowFromSnapshot(pre)
		end)
	end
end

--[[
	Internal: Clears all battle state
]]
function BattleSystemV2:_clearBattleState()
	-- Clear state
	self._battleState = nil
	self._battleInfo = nil
	self._actionHandler = nil
	self._battleUIManager = nil
	self._combatEffects = nil
	self._stepProcessor = nil
	self._partyIntegration = nil
	self._switchHandler = nil
	self._postBattleHandler = nil
	self._optionsManager = nil
	
	-- Re-enable movement
	CharacterFunctions:SetSuppressed(false)
	CharacterFunctions:CanMove(true)
	
	-- Restore TopBar
	local UI = getUI()
	if UI and UI.TopBar then
		UI.TopBar:SetSuppressed(false)
		UI.TopBar:Show()
	end
	
	-- End encounter
	EncounterZone:EndEncounter()
	
	-- Restore music (single path): End encounter track; chunk music resume is handled inside MusicManager or via explicit resume elsewhere
	MusicManager:EndEncounterMusic()
	
	-- Check for evolutions
	self:_checkForEvolutions()
	
	print("[BattleSystemV2] Battle ended")
end

--[[
	Internal: Spawns initial creatures for battle
]]
function BattleSystemV2:_spawnInitialCreatures()
	local playerSpawn, foeSpawn = self._sceneManager:GetSpawnPoints()
	
	if not playerSpawn or not foeSpawn then
		warn("[BattleSystemV2] Spawn points not found")
		return
	end
	
    -- Spawn foe creature: For Wild battles we spawn immediately; for Trainer battles, we spawn during the intro sequence after the message.
    if self._battleInfo.Type == "Wild" then
        local useHologramForFoe = false
        self._sceneManager:SpawnCreature(
            self._battleInfo.FoeCreature,
            foeSpawn,
            false,
            useHologramForFoe,
            function()
                -- Start idle animation
                local foeModel = self._sceneManager:GetFoeCreature()
                if foeModel then
                    self._animationController:PlayIdleAnimation(foeModel)
                end
                
                -- Slide in foe UI, then update with data
                if self._uiController and self._uiController.SlideFoeUIIn then
                    print("[NewTestLog] WildSpawn: foe spawning name=", (self._battleInfo.FoeCreature.Nickname or self._battleInfo.FoeCreature.Name))
                    self._uiController:SlideFoeUIIn(function()
                        self._uiController:UpdateCreatureUI(false, self._battleInfo.FoeCreature, false)
                        print("[NewTestLog] WildSpawn: foe spawn-complete name=", (self._battleInfo.FoeCreature.Nickname or self._battleInfo.FoeCreature.Name))
                        print("[BattleSystemV2] Updated foe UI after spawn (wild)")
                    end)
                else
                    self._uiController:UpdateCreatureUI(false, self._battleInfo.FoeCreature, false)
                    print("[BattleSystemV2] Updated foe UI after spawn (wild)")
                end
            end
        )
    end
	
	-- Player creature will be spawned in intro sequence
end

--[[
	Internal: Wild encounter intro sequence
]]
function BattleSystemV2:_wildEncounterIntro()
	print("[BattleSystemV2] Wild encounter intro")
	
	-- Stop any camera cycles
	if self._cameraController then
		self._cameraController:StopCycle()
	end
	
	-- Set camera to foe zoom out (if position exists)
	if self._cameraController then
		self._cameraController:SetPosition("FoeZoomOut", 1, true)
	end
	
	-- Show battle message then shiny callout if applicable
	local message = self._battleInfo.Message or "A wild creature appeared!"
	self._messageQueue:Enqueue(message)
	if self._battleInfo and self._battleInfo.FoeCreature and self._battleInfo.FoeCreature.Shiny then
		self._messageQueue:Enqueue("It's sparkling!")
	end
	
	-- Add highlight to foe
	local foeModel = self._sceneManager:GetFoeCreature()
	if foeModel then
		-- TODO: Add highlight effect
	end
	
	-- Fade out exclamation mark
	UIFunctions:FadeOutExclamationMark(self._exclamationMark)
	
	task.wait(1.5)
	
	-- Animate to default camera position (if available)
	if self._cameraController then
		self._cameraController:SetPosition("Default", 1, false)
	end
	
	task.wait(1.0)
	
	-- Spawn player creature
	local playerSpawn = self._sceneManager:GetSpawnPoints()
	if playerSpawn then
		local creatureName = self._battleInfo.PlayerCreature.Nickname or self._battleInfo.PlayerCreature.Name
		self._messageQueue:Enqueue("Go " .. creatureName .. "!")
		
		self._sceneManager:SpawnCreature(
			self._battleInfo.PlayerCreature,
			playerSpawn,
			true,
			true, -- Use hologram
			function()
				-- Start idle animation
				local playerModel = self._sceneManager:GetPlayerCreature()
				if playerModel then
					self._animationController:PlayIdleAnimation(playerModel)
				end
				
			-- Update player UI
			self._uiController:UpdateCreatureUI(true, self._battleInfo.PlayerCreature, false)
			print("[XP] Initial XP bar setup - Level:", self._battleInfo.PlayerCreature.Level, "Experience:", self._battleInfo.PlayerCreature.Experience or "nil", "XPProgress:", self._battleInfo.PlayerCreature.XPProgress or "nil", "%")
			self._uiController:UpdateLevelUI(self._battleInfo.PlayerCreature, false)
			print("[XP] Updated player UI after spawn")
				
				-- Slide in You UI when player creature is sent out
				self._uiController:SlideYouUIIn(function()
					print("[BattleSystemV2] You UI slide-in completed after creature sent out")
				end)
				
				-- Update cached creature names for message formatting
				if self._battleInfo.PlayerCreature and self._battleInfo.FoeCreature then
					BattleMessageGenerator.UpdateCreatureNames(
						self._battleInfo.PlayerCreature.Name, 
						self._battleInfo.FoeCreature.Name
					)
				end
			end
		)
	end
	
	-- Wait for messages and creature spawn
	self._messageQueue:WaitForDrain()
	
	-- Wait for player creature to exist
	local maxWait = 3
	local startTime = tick()
	while not self._sceneManager:GetPlayerCreature() and (tick() - startTime) < maxWait do
		task.wait(0.1)
	end
	
	task.wait(0.2) -- Ensure animations start
	
	-- Start the next turn (You UI will slide in when creature is sent out)
	self:StartNextTurn()
end

--[[
	Internal: Trainer battle intro sequence
]]
function BattleSystemV2:_trainerBattleIntro()
    print("[BattleSystemV2] Trainer battle intro")
    
    -- Stop any camera cycles
    if self._cameraController then
        self._cameraController:StopCycle()
    end
    
    -- Set camera to foe zoom out (same behavior as wild intro)
    if self._cameraController then
        self._cameraController:SetPosition("FoeZoomOut", 1, true)
    end

	    -- Prepare trainer clone agent and place at foe spawn for staging
		local _, foeSpawn = self._sceneManager:GetSpawnPoints()
		local agent = TrainerIntroController:ConsumePrepared()
		if agent and foeSpawn then
			agent:PlaceAtSpawn(foeSpawn.CFrame)
		end
	
    
    -- Small pacing delay to mirror wild intro timing
    task.wait(1.5)

	-- Fade out the exclamation mark like in wild intro
	UIFunctions:FadeOutExclamationMark(self._exclamationMark)

    -- Play intro pose/idle shortly after spawn
    local INTRO_ANIM = "78441710358556"
	task.delay(0.654, function()
		agent:PlayAnimation(INTRO_ANIM, 0.1, false)
	end)
    
    -- Show trainer wants-to-battle message first
    local trainerName = self._battleInfo.TrainerName or "Trainer"
    self._messageQueue:Enqueue(trainerName .. " wants to battle!")
    self._messageQueue:WaitForDrain()

    -- After message: tween trainer back 8 studs and fade out
    if agent then
        agent:TweenBackAndFade(10, 0.6, false)
        task.wait(0.2)
    end
    
    -- Then send out the foe creature and show the message
    local foe = self._battleInfo.FoeCreature
    if foe then
        local foeName = foe.Nickname or foe.Name or "their creature"
        self._messageQueue:Enqueue(trainerName .. " sent out " .. foeName .. "!")
        -- Spawn foe now
        local _, foeSpawn = self._sceneManager:GetSpawnPoints()
        if foeSpawn then
            self._sceneManager:SpawnCreature(
                foe,
                foeSpawn,
                false,
                true,
                function()
                    local foeModel = self._sceneManager:GetFoeCreature()
                    if foeModel then
                        self._animationController:PlayIdleAnimation(foeModel)
                    end
                    -- Update battle state with foe creature (ensure it's in sync)
                    if self._battleState then
                        self._battleState:UpdateFoeCreature(foe)
                        print("[BattleSystemV2] Updated battle state with initial foe in trainer intro")
                    end
                    
                    -- Slide in foe UI after spawn, then update
                    if self._uiController and self._uiController.SlideFoeUIIn then
                        self._uiController:SlideFoeUIIn(function()
                            print("[BattleSystemV2] Foe UI slide-in complete, updating UI with foe data")
                            print("[BattleSystemV2] Foe HP:", foe.Stats and foe.Stats.HP, "Max:", foe.MaxStats and foe.MaxStats.HP)
                            self._uiController:UpdateCreatureUI(false, foe, false)
                            print("[BattleSystemV2] Foe UI updated in trainer intro")
                        end)
                    else
                        self._uiController:UpdateCreatureUI(false, foe, false)
                    end
                end
            )
        end
    end
    self._messageQueue:WaitForDrain()
    
    -- Animate camera to default position (consistent with wild)
    if self._cameraController then
        self._cameraController:SetPosition("Default", 1, false)
    end
    
    -- Brief pause before sending out the player's creature (mirrors wild)
    task.wait(1.0)
    
    -- Finally, send out the player creature as usual
    local playerSpawn = self._sceneManager:GetSpawnPoints()
    if playerSpawn then
        local youName = self._battleInfo.PlayerCreature.Nickname or self._battleInfo.PlayerCreature.Name
        self._messageQueue:Enqueue("Go " .. youName .. "!")
        self._sceneManager:SpawnCreature(
            self._battleInfo.PlayerCreature,
            playerSpawn,
            true,
            true,
            function()
                local playerModel = self._sceneManager:GetPlayerCreature()
                if playerModel then
                    self._animationController:PlayIdleAnimation(playerModel)
                end
                self._uiController:UpdateCreatureUI(true, self._battleInfo.PlayerCreature, false)
                self._uiController:UpdateLevelUI(self._battleInfo.PlayerCreature, false)
                self._uiController:SlideYouUIIn(function() end)
                
                -- Update cached creature names for message formatting
                if self._battleInfo.PlayerCreature and self._battleInfo.FoeCreature then
                    BattleMessageGenerator.UpdateCreatureNames(
                        self._battleInfo.PlayerCreature.Name, 
                        self._battleInfo.FoeCreature.Name
                    )
                end
            end
        )
    end
    
    self._messageQueue:WaitForDrain()
    self:StartNextTurn()
end


--[[
	Internal: Gets party data from ClientData
	@return table? Party data
]]
function BattleSystemV2:_getPartyData(): {any}?
	-- Try to get ClientData module
	local ClientData = require(script.Parent.Parent.Plugins.ClientData)
	if ClientData and ClientData.Data and ClientData.Data.Party then
		return ClientData.Data.Party
	end
	return nil
end

--[[
	Internal: Checks for evolutions after battle
]]
function BattleSystemV2:_checkForEvolutions()
	if not self._postBattleHandler then
		return
	end
	
	-- Get current party data
	local partyData = self:_getPartyData()
	if not partyData then
		return
	end
	
	-- Check for evolutions
	local evolutions = self._postBattleHandler:CheckForEvolutions(partyData)
	
	if #evolutions > 0 then
		-- Queue evolutions
		for _, evolution in ipairs(evolutions) do
			self._postBattleHandler:QueueEvolution(evolution)
		end
		
		-- Process evolutions
		self._postBattleHandler:ProcessEvolutions()
	end
end

--[[
	Internal: Sets up party integration callbacks
]]
function BattleSystemV2:_setupPartyCallbacks()
	if not self._partyIntegration then
		return
	end
	
	-- Handle switch complete
	self._partyIntegration:OnSwitchComplete(function(selectedIndex: number)
		print("[BattleSystemV2] Party switch complete to index:", selectedIndex)
		-- Switch will be handled by server TurnResult
	end)
	
	-- Handle switch cancelled
	self._partyIntegration:OnSwitchCancelled(function()
		print("[BattleSystemV2] Party switch cancelled - callback received")
		-- Just show battle options again (don't start a new turn)
		print("[BattleSystemV2] Restoring battle options after cancel")
		if self._optionsManager then
			self._optionsManager:ShowBattleOptions(true) -- Force show to correct state
		else
			warn("[BattleSystemV2] Options manager not initialized")
		end
	end)
end

--[[
	Internal: Sets up options manager callbacks
]]
function BattleSystemV2:_setupOptionsCallbacks()
	if not self._optionsManager then
		return
	end
	
	self._optionsManager:SetCallbacks({
		-- Fight button: show move options
		onFight = function()
			print("[BattleSystemV2] Fight button pressed")
			if self._battleState and self._battleState.PlayerCreature then
				self._optionsManager:ShowMoveOptions(
					self._battleState.PlayerCreature,
					self._battleState.FoeCreature
				)
			end
		end,
		
		-- Run button: attempt to escape
		onRun = function()
			print("[BattleSystemV2] Run button pressed")
			if self._battleInfo.Type == "Trainer" then
				-- Use ActionHandler to handle trainer battle case (prevents duplicate message)
				if self._actionHandler then
					self._actionHandler:AttemptRun()
				end
				return
			end
			
			if self._battleInfo.IsStatic or self._battleInfo.IsBoss then
				self._messageQueue:Enqueue("You can't run away!")
				return
			end
			
			-- Hide options
			self._optionsManager:HideAll()
			
			-- Request escape from server
			Events.Request:InvokeServer({"AttemptEscape"})
		end,
		
		-- Creatures button: open party for voluntary switch
		onCreatures = function()
			print("[BattleSystemV2] Creatures button pressed")
			-- Hide options while party is open
			if self._optionsManager then
				self._optionsManager:HideAll()
			end
			-- Open party menu in battle context for a voluntary switch
			if self._partyIntegration and self._partyIntegration.OpenForVoluntarySwitch then
				self._partyIntegration:OpenForVoluntarySwitch(false)
			else
				warn("[BattleSystemV2] PartyIntegration not available for voluntary switch")
			end
		end,
		
		-- Bag button: open bag menu
			onBag = function()
			print("[BattleSystemV2] Bag button pressed")
				-- Hide options while bag is open
				self._optionsManager:HideAll()
			local UI = require(script.Parent.Parent.UI)
			if UI and UI.Bag and UI.Bag.Open then
				pcall(function()
						if UI.Bag.SetCallbacks then
							UI.Bag:SetCallbacks(nil, function()
								-- Defer restoring options until message queue drains to avoid mid-turn UI
								if self._messageQueue and self._messageQueue.WaitForDrain then
									self._messageQueue:WaitForDrain()
								end
								-- If we are still processing a turn (e.g., after using an item), do NOT show options yet
								if self._inTurnProcessing then
									return
								end
								if self._optionsManager then
									self._optionsManager:ShowBattleOptions(true)
								end
							end)
					end
				end)
				-- Pass battle type context to Bag to correctly gate capture items
				local isTrainer = (self._battleInfo and self._battleInfo.Type == "Trainer") == true
				UI.Bag:Open({ Context = "Battle", IsTrainer = isTrainer, BattleType = (self._battleInfo and self._battleInfo.Type) })
			else
				warn("[BattleSystemV2] UI.Bag not available")
			end
		end,
		
		-- Move selected: execute move
		onMoveSelected = function(moveIndex: number)
			print("[BattleSystemV2] Move", moveIndex, "selected")
			if self._actionHandler then
				self._actionHandler:ExecuteMove(moveIndex)
			end
			
			-- Hide options
			self._optionsManager:HideAll()
		end,
		
		-- Back button: return to battle options
		onBack = function()
			print("[BattleSystemV2] Back button pressed")
			self._optionsManager:ShowBattleOptions()
		end,
	})
	
	print("[BattleSystemV2] Options callbacks set up")
end

--[[
	Internal: Gets all keys from a table
	@param tbl The table to get keys from
	@return Array of key strings
]]
function BattleSystemV2:_getTableKeys(tbl: any): {string}
	local keys = {}
	if type(tbl) == "table" then
		for key, _ in pairs(tbl) do
			table.insert(keys, tostring(key))
		end
	end
	return keys
end

--[[
	Internal: Runs the escape sequence with blackout transition
]]
function BattleSystemV2:_runAwaySequence()
	print("[BattleSystemV2] Starting run away sequence with blackout")
	-- Ensure camera cycles are stopped before any fade/tween work
	if self._cameraController then
		self._cameraController:StopCycle()
	end
	
	-- Get Blackout frame
	local pg = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui")
	local gui = pg:FindFirstChild("GameUI") or pg:WaitForChild("GameUI")
	local Blackout = gui:WaitForChild("Blackout")
	
	-- Hide battle UI first
	self._battleUI.Visible = false
	
	-- Start blackout fade in
	Blackout.Visible = true
	Blackout.BackgroundTransparency = 1
	
	-- Fade to black
	local fadeInTween = TweenService:Create(
		Blackout,
		TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{BackgroundTransparency = 0}
	)
	fadeInTween:Play()
	
	-- Wait for fade to complete
	fadeInTween.Completed:Wait()
	
	-- Wait 0.5 seconds
	task.wait(0.5)
	
	-- Clean up battle during blackout
	if self._sceneManager then
		self._sceneManager:Cleanup()
	end
	
	-- Reset camera FOV during blackout (when screen is fully black)
	self._camera.FieldOfView = 70
	print("[BattleSystemV2] Camera FOV reset to 70 during blackout")
	
	-- Reset camera to normal mode
	self._camera.CameraType = Enum.CameraType.Custom
	self._camera.CameraSubject = LocalPlayer.Character and LocalPlayer.Character:WaitForChild("Humanoid")
	
	-- Clear battle data
	self._battleInfo = nil
	self._battleState = nil
	
	-- End encounter to re-enable movement
	EncounterZone:EndEncounter()
	
	-- End encounter music and restore chunk music
	MusicManager:EndEncounterMusic()
	task.delay(0.1, function()
		local ChunkLoader = require(script.Parent.ChunkLoader)
		local chunk = ChunkLoader:GetCurrentChunk()
		if chunk and chunk.Essentials then
			MusicManager:SetChunkMusic(chunk.Essentials)
		end
	end)
	
	-- Re-enable movement
	CharacterFunctions:CanMove(true)
	
	-- Restore TopBar
	local UI = getUI()
	if UI and UI.TopBar then
		UI.TopBar:SetSuppressed(false)
		UI.TopBar:Show()
	end
	
	-- Fade out blackout
	local fadeOutTween = TweenService:Create(
		Blackout,
		TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{BackgroundTransparency = 1}
	)
	fadeOutTween:Play()
	
	-- Wait for fade out to complete
	fadeOutTween.Completed:Wait()
	
	-- Hide blackout
	Blackout.Visible = false
	
	print("[BattleSystemV2] Run away sequence complete")
end

--[[
	Handles structured battle events from server (XP, level-ups, etc.)
	Generates messages client-side using MessageGenerator
]]
function BattleSystemV2:HandleBattleEvent(eventData: any)
	if not eventData or not eventData.Type then
		return
	end
	
	-- Don't process events if battle has ended
	if not self._battleState or not self._battleInfo then
		print("[BattleSystemV2] Ignoring battle event - battle has ended")
		return
	end
	
	-- Skip faint events - they're already handled by step processor
	if eventData.Type == "Faint" then
		print("[BattleSystemV2] Skipping faint event - already handled by step processor")
		return
	end
	
	-- Defer XP/LevelUp/MoveReplacePrompt while foe faint animation is running
	if (eventData.Type == "XP" or eventData.Type == "LevelUp" or eventData.Type == "XPSpread" or eventData.Type == "MoveReplacePrompt") and self._waitingForFoeFaintAnim then
		print("[BattleSystemV2] Deferring XP event until faint animation completes:", eventData.Type)
		table.insert(self._deferredXPEvents, eventData)
		return
	end

	-- If a move replace flow is active, buffer all other battle events until the flow completes
	if self._moveReplaceActive
		and eventData.Type ~= "MoveReplacePrompt"
		and eventData.Type ~= "MoveLearned"
		and eventData.Type ~= "MoveDeclined"
		and eventData.Type ~= "MoveReplaced" then
		print("[BattleSystemV2] Buffering event during MoveReplace flow:", eventData.Type)
		self._deferredEventsDuringMoveReplace = self._deferredEventsDuringMoveReplace or {}
		table.insert(self._deferredEventsDuringMoveReplace, eventData)
		return
	end

	-- Ensure MoveLearned message shows after LevelUp: buffer it for the same creature
	if eventData.Type == "MoveLearned" and eventData.Creature and eventData.Move then
		self._pendingMoveLearned = self._pendingMoveLearned or {}
		local list = self._pendingMoveLearned[eventData.Creature]
		if not list then list = {}; self._pendingMoveLearned[eventData.Creature] = list end
		table.insert(list, eventData)
		-- Do not enqueue the message yet
		return
	end
	
    -- Intercept client-interactive prompts first
	if eventData.Type == "MoveReplacePrompt" then
		self:_handleMoveReplacePrompt(eventData)
		return
	end

    -- Server confirmed a replacement: show "forgot" + "and learned" then finalize
    if eventData.Type == "MoveReplaced" then
        local creature = tostring(eventData.Creature or "")
        local oldMove = tostring(eventData.OldMove or "")
        local newMove = tostring(eventData.NewMove or "")
        self._messageQueue:Enqueue(string.format("%s forgot %s...", creature, oldMove))
        self._messageQueue:Enqueue(string.format("and learned %s!", newMove))
        self._messageQueue:OnDrained(function()
            self:_finalizeMoveReplaceFlow()
        end)
        return
    end

    -- Generate message from structured event data
	local message = Battle.MessageGenerator.FromEvent(eventData)
	
	if message then
		self._messageQueue:Enqueue(message)
        if eventData.Type == "MoveDeclined" and self._moveReplaceActive then
            self._messageQueue:OnDrained(function()
                self:_finalizeMoveReplaceFlow()
            end)
        end
	end
	
	-- Handle specific event types that need additional processing
	if eventData.Type == "XP" then
		-- Update XP bar for the active creature, tolerant to replication timing
		if self._battleInfo and self._battleInfo.PlayerCreature then
			local activeCreatureName = self._battleInfo.PlayerCreature.Nickname or self._battleInfo.PlayerCreature.Name
			if activeCreatureName == eventData.Creature then
				-- Resolve freshest creature snapshot for UI animation
				local function getBestCreatureData(): any
					local creatureData
					local ClientData = require(game.Players.LocalPlayer.PlayerScripts.Client.Plugins.ClientData)
					local playerData = ClientData:Get()
					if playerData and playerData.Party then
						for _, c in ipairs(playerData.Party) do
							local nm = c.Nickname or c.Name
							if nm == eventData.Creature then
								creatureData = c
								break
							end
						end
					end
					if not creatureData then
						creatureData = table.clone(self._battleInfo.PlayerCreature)
					end
					-- Prefer server-provided XP progress for immediate animation accuracy
					if type(eventData.XPProgress) == "number" then
						creatureData.XPProgress = eventData.XPProgress
					end
					return creatureData
				end
				local best = getBestCreatureData()
				self._uiController:UpdateLevelUI(best, true, false)
				print("[XP] Client: Updated XP bar for", activeCreatureName, "- Progress:", best.XPProgress or 0, "%")
			end
		end
    elseif eventData.Type == "LevelUp" then
		-- Animate level-up for the active creature (fill→snap→labels→tween)
		if self._battleInfo and self._battleInfo.PlayerCreature then
			local activeCreatureName = self._battleInfo.PlayerCreature.Nickname or self._battleInfo.PlayerCreature.Name
			if activeCreatureName == eventData.Creature then
				local function getBestCreatureData(): any
					local creatureData
					local ClientData = require(game.Players.LocalPlayer.PlayerScripts.Client.Plugins.ClientData)
					local playerData = ClientData:Get()
					if playerData and playerData.Party then
						for _, c in ipairs(playerData.Party) do
							local nm = c.Nickname or c.Name
							if nm == eventData.Creature then
								creatureData = c
								break
							end
						end
					end
					if not creatureData then
						creatureData = table.clone(self._battleInfo.PlayerCreature)
					end
					-- Prefer server-provided level to drive UI labels immediately
					if type(eventData.Level) == "number" then
						creatureData.Level = eventData.Level
					end
					if type(eventData.XPProgress) == "number" then
						creatureData.XPProgress = eventData.XPProgress
					end
					return creatureData
				end
				local best = getBestCreatureData()
				self._uiController:UpdateLevelUI(best, true, true)
				print("[XP] Client: Animated level-up for", activeCreatureName, "- Level:", best.Level, "Progress:", best.XPProgress or 0)
			end
		end

		-- Flush any pending MoveLearned messages for this creature so they appear immediately after level-up
		if self._pendingMoveLearned and eventData.Creature then
			local pending = self._pendingMoveLearned[eventData.Creature]
			if pending and #pending > 0 then
				for _, ev in ipairs(pending) do
					local msg2 = Battle.MessageGenerator.FromEvent(ev)
					if msg2 then
						self._messageQueue:Enqueue(msg2)
					end
				end
				self._pendingMoveLearned[eventData.Creature] = nil
			end
		end
    elseif eventData.Type == "MoveLearned" then
        -- Nothing extra to animate beyond message; message is enqueued above via MessageGenerator
	end
end

--[[
	Handles evolution events from server
	@param evolutionData Data about the evolution that occurred
]]
function BattleSystemV2:HandleEvolution(evolutionData: any)
	print("[BattleSystemV2] Received evolution event:", evolutionData.OldSpecies, "->", evolutionData.NewSpecies)
	
	-- Store the evolution data to be shown during the blackout sequence
	if not self._pendingEvolutions then
		self._pendingEvolutions = {}
	end
	table.insert(self._pendingEvolutions, evolutionData)
	print("[BattleSystemV2] Stored pending evolution - will show during blackout")
end

--[[
	Internal: Handles player defeat sequence (similar to legacy BlackoutToCatchCare)
]]
function BattleSystemV2:_handlePlayerDefeat()
	print("[BattleSystemV2] Handling player defeat sequence")
	
	-- Stop encounter music immediately
	pcall(function() 
		local MusicManager = require(script.Parent.MusicManager)
		MusicManager:EndEncounterMusic() 
	end)
	
	-- Show defeat messages
	local Say = require(script.Parent.Say)
	Say:Say("", true, {"You have no creatures left to fight!"})
	if self._studsLost > 0 then
		-- Context-aware studs loss message
		local studsMessage = ""
		if self._battleInfo and self._battleInfo.Type == "Trainer" then
			studsMessage = "You paid " .. self._studsLost .. " studs to the winner..."
		else
			studsMessage = "You dropped " .. self._studsLost .. " studs in panic..."
		end
		Say:Say("", true, {studsMessage})
	end
	
	-- Handle defeat sequence and wait for completion before fading out blackout
	self:_handleDefeatSequence()
end

--[[
	Internal: Handles the defeat sequence with proper timing
]]
function BattleSystemV2:_handleDefeatSequence()
	print("[BattleSystemV2] Starting defeat sequence")
	
	-- Prefer chunk-provided relocation target (ChunkEvents) if available
	local ChunkLoader = require(script.Parent:WaitForChild("ChunkLoader"))
	local currentChunk = ChunkLoader:GetCurrentChunk() and ChunkLoader:GetCurrentChunk().Model and ChunkLoader:GetCurrentChunk().Model.Name
	
	local relocate = nil
	local chunkObj = ChunkLoader:GetCurrentChunk()
	if chunkObj and chunkObj.BlackoutRelocate and chunkObj.BlackoutRelocate.Type == "HealerTom" then
		relocate = chunkObj.BlackoutRelocate
	end

	if relocate or currentChunk == "Chunk1" or currentChunk == "Chunk2" then
		print("[BattleSystemV2] Player defeated in", currentChunk, "- teleporting to Healer Tom in", currentChunk)
		
		local player = game.Players.LocalPlayer
		local character = player.Character or player.CharacterAdded:Wait()
		local hrp = character:WaitForChild("HumanoidRootPart")
		
		-- Find Healer Tom in the selected chunk (he's in the NPCs folder)
		local Chunk = ChunkLoader:GetCurrentChunk()
        if Chunk and Chunk.Model then
			local NPCs = Chunk.Model:FindFirstChild("NPCs")
			if NPCs then
				local healerName = (relocate and relocate.NPCTargetName) or "Healer Tom"
				local healerTom = NPCs:FindFirstChild(healerName)
				if healerTom and healerTom:FindFirstChild("HumanoidRootPart") then
					-- Teleport in front of Healer Tom, not on his head
					local healerPosition = healerTom.HumanoidRootPart.Position
					local healerCFrame = healerTom.HumanoidRootPart.CFrame
					local forwardDirection = healerCFrame.LookVector
					local teleportPosition = healerPosition + forwardDirection * 5 + Vector3.new(0, 0, 0)
					hrp.CFrame = CFrame.new(teleportPosition, healerPosition)
					print("[BattleSystemV2] Teleported in front of Healer Tom")
					
					-- Debug: Check model structure before calling Say
					print("[BattleSystemV2] Healer Tom model check:")
					print("  - Type:", typeof(healerTom))
					print("  - Children count:", #healerTom:GetChildren())
					print("  - Has HumanoidRootPart:", healerTom:FindFirstChild("HumanoidRootPart") ~= nil)
					print("  - Has Head:", healerTom:FindFirstChild("Head") ~= nil)
					print("  - Has Humanoid:", healerTom:FindFirstChildOfClass("Humanoid") ~= nil)
					
					self:_fadeOutBlackout()
					task.wait(0.5)
					-- Start healing dialogue with Healer Tom (using Say module directly)
					local Say = require(script.Parent.Say)
					Say:Say("Healer Tom", true, {"Oh! You need your creatures healed? Allow me!"}, healerTom)
					local success, healOk = pcall(function()
						return Events.Request:InvokeServer({"HealParty"})
					end)
					if success and healOk then
						Say:Say("Healer Tom", true, {"Done! Take care of them!"}, healerTom)
					else
						Say:Say("Healer Tom", true, {"Hmm, that didn't work. Come back when you're nearby."}, healerTom)
					end
						print("[BattleSystemV2] Started healing dialogue with Healer Tom")
						-- Signal that relocation after battle is complete (healer path)
						RelocationSignals.FirePostBattleRelocated({ Reason = "HealerTom", Chunk = currentChunk })
				end
			end
		end

		
	else
		-- Normal CatchCare loading for other chunks
		-- Ask server to compute and set the correct return chunk (nearest previous with CatchCare door)
		pcall(function()
			local Events = game:GetService("ReplicatedStorage"):WaitForChild("Events")
			if Events and Events.Request then
				Events.Request:InvokeServer({"SetBlackoutReturnChunk"})
			end
		end)
        local ok = ChunkLoader:ClientRequestChunk("CatchCare")
		print("[BattleSystemV2] Requested CatchCare chunk load:", ok and true or false)
		
		-- Wait for chunk to load
		task.wait(0.5)
		
		-- Position player at Essentials.ChunkSpawnFallBack
		local Chunk = ChunkLoader:GetCurrentChunk()
		if Chunk and Chunk.Essentials then
			local spawn = Chunk.Essentials:FindFirstChild("ChunkSpawnFallBack")
			local player = game.Players.LocalPlayer
			local character = player.Character or player.CharacterAdded:Wait()
			local hrp = character:WaitForChild("HumanoidRootPart")
            if spawn and hrp then
				hrp.CFrame = spawn.CFrame
				print("[BattleSystemV2] Positioned player at CatchCare spawn")
                -- Signal that relocation after battle is complete (CatchCare path)
                RelocationSignals.FirePostBattleRelocated({ Reason = "CatchCare", Chunk = "CatchCare" })
			end
		end
		
		-- Wait for position to be set, then start Miranda conversation
		task.wait(0.5)
		self:_fadeOutBlackout()
		
		-- Start Miranda conversation and heal
		local UI = require(script.Parent.Parent.UI)
		local Chunk2 = ChunkLoader:GetCurrentChunk()
		local npc = Chunk2 and Chunk2.Model and Chunk2.Model:FindFirstChild("NPCs") and Chunk2.Model.NPCs:FindFirstChild("Miranda")
		local Say = require(script.Parent.Say)
		Say:Say("Miranda", true, {"Oh hi! You need your creatures healed? Allow me!"}, npc)
		local success, healOk = pcall(function()
			return Events.Request:InvokeServer({"HealParty"})
		end)
		if success and healOk then
			Say:Say("Miranda", true, {"Done! Take care of them!"}, npc)
		else
			Say:Say("Miranda", true, {"Hmm, that didn't work. Come back when you're nearby."}, npc)
		end
	end
	
	-- Resume chunk music after blackout
	task.wait(0.5) -- Small delay to ensure everything is settled
	local currentChunk = ChunkLoader:GetCurrentChunk()
	if currentChunk and currentChunk.Essentials then
		pcall(function() 
			local MusicManager = require(script.Parent.MusicManager)
			MusicManager:SetChunkMusic(currentChunk.Essentials) 
		end)
	end
	
	print("[BattleSystemV2] Player defeat sequence completed")
end

--[[
	Internal: Fades out the blackout screen
]]
function BattleSystemV2:_fadeOutBlackout()
	print("[BattleSystemV2] Fading out blackout screen")
	
	local PlayerGui = game.Players.LocalPlayer.PlayerGui
	local GameUI = PlayerGui:WaitForChild("GameUI")
	local Blackout = GameUI:WaitForChild("Blackout")
	local TopBar = GameUI:WaitForChild("TopBar")
	
	-- Fade out blackout
	local TweenService = game:GetService("TweenService")
	local FadeOutTween = TweenService:Create(Blackout, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1
	})
	
	FadeOutTween:Play()
	
	-- Show TopBar after fade out
	FadeOutTween.Completed:Connect(function()
		Blackout.Visible = false
		TopBar.Visible = true
		print("[BattleSystemV2] Blackout fade out completed")
	end)
end

return BattleSystemV2

--!strict
--[[
	StepProcessor.lua
	Processes individual battle steps from server turn results
	Handles all step types with proper sequencing and callbacks
	
	Now uses BattleMessageGenerator for all message generation.
	Server sends only structured event data, no descriptive strings.
]]

local MessageGenerator = require(script.Parent.BattleMessageGenerator)
local ClientData = require(script.Parent.Parent.Plugins.ClientData)
local CaptureEffects = require(script.Parent.CaptureEffects)
local AgentAnimations = require(script.Parent.AgentAnimations)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MovesModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Moves"))

local StepProcessor = {}
StepProcessor.__index = StepProcessor

export type StepProcessorType = typeof(StepProcessor.new())
export type StepCallback = () -> ()

-- Step type annotations (partial; widened as needed during migration)
export type MessageStep = { Type: "Message", Message: string? }
export type MoveStep = { Type: "Move", Actor: string?, Move: string?, MoveName: string? }
export type DamageStep = { Type: "Damage", Effectiveness: string? }
export type HealStep = { Type: "Heal", Amount: number?, Message: string? }
export type CaptureScanStep = { Type: "CaptureScan", Success: boolean? }
export type CaptureSuccessStep = { Type: "CaptureSuccess", Creature: string? }
export type WaitDrainStep = { Type: "WaitDrain" }
export type FaintStep = { Type: "Faint", Creature: string? }
export type SwitchStep = { Type: "Switch", Action: string, Creature: string?, Variant: string? }
export type MissStep = { Type: "Miss", Message: string? }
export type CritStep = { Type: "Crit", Message: string? }
export type StatusStep = { Type: "Status", Status: string?, Message: string? }
export type StatStageStep = { Type: "StatStage", Stat: string?, Stages: number?, Message: string? }
export type XPStep = { Type: "XP", Creature: string, Amount: number, IsShared: boolean? }
export type XPSpreadStep = { Type: "XPSpread" }
export type LevelUpStep = { Type: "LevelUp", Creature: string, Level: number }
export type AbilityActivationStep = { Type: "AbilityActivation", Ability: string, Creature: string, Message: string?, IsPlayer: boolean?, StatChange: { Stat: string, Stages: number }? }
export type RecoilStep = { Type: "Recoil", Creature: string, IsPlayer: boolean, RecoilDamage: number?, NewHP: number?, MaxHP: number? }
export type EntryHazardStep = { Type: "EntryHazard", HazardType: string, Layers: number?, IsPlayer: boolean, Message: string? }
export type HazardDamageStep = { Type: "HazardDamage", HazardType: string, Creature: string, Damage: number?, NewHP: number?, MaxHP: number?, Status: string?, Absorbed: boolean?, IsPlayer: boolean, Message: string? }
export type GenericStep = { Type: string, [string]: any }
export type Step = MessageStep | MoveStep | DamageStep | HealStep | CaptureScanStep | WaitDrainStep | FaintStep | SwitchStep | MissStep | CritStep | StatusStep | StatStageStep | XPStep | XPSpreadStep | LevelUpStep | AbilityActivationStep | RecoilStep | EntryHazardStep | HazardDamageStep | GenericStep

--[[
	Creates a new step processor instance
	@param battleState The battle state reference
	@param messageQueue The message queue reference
	@param uiController The UI controller reference
	@param sceneManager The scene manager reference
	@param combatEffects The combat effects reference
	@return StepProcessor
]]
function StepProcessor.new(
    battleState: any,
    messageQueue: any,
    uiController: any,
    sceneManager: any,
    combatEffects: any
): StepProcessorType
	local self = setmetatable({}, StepProcessor)
	
	self._battleState = battleState
	self._messageQueue = messageQueue
	self._uiController = uiController
	self._sceneManager = sceneManager
	self._combatEffects = combatEffects
	self._battleSystem = nil  -- Will be set by BattleSystemV2

	-- Context for resolving correct heal-first-then-damage visuals in the same turn
	self._incomingContext = nil :: any

	-- Pending damage fallback (from Move.HPDelta) in case Damage.NewHP is missing
	self._pendingDamageDeltaPlayer = nil
	self._pendingDamageDeltaFoe = nil
	
	-- Track if effectiveness message has been shown for current move sequence
	-- Prevents duplicate "super effective" messages
	self._effectivenessMessageShown = false
	-- Track the current move's effectiveness to ensure damage steps use the correct value
	self._currentMoveEffectiveness = nil
	
	-- Track early HP updates at hit marker to avoid duplicate updates in Damage step
	-- nil = no early update, true = player updated early, false = foe updated early
	self._earlyHPUpdateTarget = nil :: boolean?
	
	-- Track starting HP for PvP execution order mode (to fix HP calculation at hit markers)
	-- These represent HP at the START of the turn, before any actions
	self._startingPlayerHP = nil :: number?
	self._startingFoeHP = nil :: number?
	-- Track current HP as we process steps (updated from starting HP + deltas)
	self._currentPlayerHP = nil :: number?
	self._currentFoeHP = nil :: number?
	
	-- Capture cinematic effects controller
	self._captureEffects = nil :: any
	self._captureScanIndex = 0 -- Tracks which scan we're on (1, 2, or 3)
	
	return self
end

--[[
	Sets the battle system reference for callbacks
	@param battleSystem The BattleSystemV2 reference
]]
function StepProcessor:SetBattleSystem(battleSystem: any)
	self._battleSystem = battleSystem
end

-- Supplies per-turn incoming damage context from BattleSystemV2
function StepProcessor:SetIncomingDamageContext(ctx: any)
	self._incomingContext = ctx
end

-- Sets starting HP for PvP execution order mode (HP at start of turn, before any actions)
function StepProcessor:SetStartingHP(playerHP: number?, foeHP: number?)
	self._startingPlayerHP = playerHP
	self._startingFoeHP = foeHP
	-- Initialize current HP tracking from starting HP
	self._currentPlayerHP = playerHP
	self._currentFoeHP = foeHP
	if playerHP ~= nil or foeHP ~= nil then
		print("[StepProcessor] Set starting HP - Player:", playerHP, "Foe:", foeHP)
	end
end

-- Optional: Provide animation controller reference for idle/damage speed adjustments
function StepProcessor:SetAnimationController(animationController: any)
	self._animationController = animationController
end

--[[]]
-- Internal: Resolves which side fainted for a Faint step.
-- Prefers explicit step.IsPlayer, then matches step.Creature against active
-- creature display names, and finally falls back to the defaultIsPlayer context.
function StepProcessor:_resolveFaintIsPlayer(step: any, defaultIsPlayer: boolean): boolean
	-- 1) Explicit flag wins
	if step and type(step.IsPlayer) == "boolean" then
		return step.IsPlayer
	end

	-- 2) Try to match creature name against active creatures
	local creatureStr = step and step.Creature
	if type(creatureStr) == "string" then
		local player = self._battleState and self._battleState.PlayerCreature
		local foe = self._battleState and self._battleState.FoeCreature
		local playerName = player and (player.Nickname or player.Name)
		local foeName = foe and (foe.Nickname or foe.Name)
		if playerName and creatureStr == playerName then
			return true
		end
		if foeName and creatureStr == foeName then
			return false
		end
	end

	-- 3) Fallback to context side provided by caller
	return defaultIsPlayer == true
end


--[[
	Internal: Updates UI with pending HP data when Hit marker is reached
	Only updates the target side for this hit to avoid premature HP changes on the attacker.
    @param targetIsPlayer boolean? When true, update player HP; when false, update foe HP
]]
function StepProcessor:_updateUIWithPendingHP(targetIsPlayer: boolean?)
	print("[StepProcessor] Hit marker reached - updating UI with pending HP data")
	local hpData = self._battleState:MarkHPUpdateProcessed()
	if not hpData then
		print("[StepProcessor] No pending HP data found or already processed")
		return
	end
	if not self._uiController then
		print("[StepProcessor] No UI controller found")
		return
	end
	print("[StepProcessor] HP data found:", hpData)

	-- Decide which side to update; default to player-only if ambiguous (defensive)
	local updatePlayer = (targetIsPlayer == true)
	local updateFoe = (targetIsPlayer == false)

	-- Update only the intended side for this hit
	if updatePlayer and hpData.Player and hpData.PlayerMax and self._battleState.PlayerCreature then
		local playerCreature = table.clone(self._battleState.PlayerCreature)
		playerCreature.Stats = playerCreature.Stats or {}
		playerCreature.Stats.HP = hpData.Player
		playerCreature.MaxStats = playerCreature.MaxStats or {}
		playerCreature.MaxStats.HP = hpData.PlayerMax
		self._uiController:UpdateCreatureUI(true, playerCreature, true)
		self._uiController:UpdateLevelUI(playerCreature, false)
		local playerModel = self._sceneManager:GetPlayerCreature()
		if playerModel and self._animationController then
			self._animationController:UpdateIdleSpeed(playerModel, hpData.Player, hpData.PlayerMax)
		end
	elseif updateFoe and hpData.Enemy and hpData.EnemyMax and self._battleState.FoeCreature then
		local foeCreature = table.clone(self._battleState.FoeCreature)
		foeCreature.Stats = foeCreature.Stats or {}
		foeCreature.Stats.HP = hpData.Enemy
		foeCreature.MaxStats = foeCreature.MaxStats or {}
		foeCreature.MaxStats.HP = hpData.EnemyMax
		self._uiController:UpdateCreatureUI(false, foeCreature, true)
		local foeModel = self._sceneManager:GetFoeCreature()
		if foeModel and self._animationController then
			self._animationController:UpdateIdleSpeed(foeModel, hpData.Enemy, hpData.EnemyMax)
		end
	end
end

--[[
	Internal: Triggers battle end sequence after foe faints
]]
function StepProcessor:_triggerBattleEndSequence()
	print("[StepProcessor] _triggerBattleEndSequence called")
end

--[[
	Processes a single battle step
	@param step The step data
	@param isPlayer Whether this is a player action
	@param onComplete Callback when step completes
]]
function StepProcessor:ProcessStep(step: Step, isPlayer: boolean, onComplete: StepCallback?)
    local stepType = step.Type
    -- Resolve actor side using structured flag when present
    local actorIsPlayer = (type((step :: any).IsPlayer) == "boolean") and (step :: any).IsPlayer or isPlayer
    print("[StepProcessor] Processing step - Type:", stepType, "IsPlayer:", actorIsPlayer)

    -- Dispatch table for clean, maintainable step handling
    local handlers: { [string]: () -> () } = {
        Message = function()
            -- If this is the first capture message during a capture action, play CaptureCube animation
            local msg = (step :: any).Message
            if type(msg) == "string" and (string.find(string.lower(msg), "you used a capture cube", 1, true) ~= nil) then
                -- Attempt to play cube animation at player's spawn within the active battle scene
                local scene = self._sceneManager and self._sceneManager:GetScene()
                if scene and self._combatEffects and self._combatEffects.PlayCaptureCubeUse then
                    self._combatEffects:PlayCaptureCubeUse(scene)
                end
                
                -- Initialize cinematic capture effects
                self._captureScanIndex = 0
                local camera = workspace.CurrentCamera
                local playerGui = game.Players.LocalPlayer:FindFirstChild("PlayerGui")
                local foeCreature = self._sceneManager and self._sceneManager:GetFoeCreature()
                if camera and playerGui then
                    self._captureEffects = CaptureEffects.new(camera, playerGui, foeCreature)
                    self._captureEffects:StartCaptureSequence()
                    print("[StepProcessor] Capture cinematic effects initialized")
                end
            end
            -- Messages should drain before continuing to preserve sequencing
            self:_processMessage(step :: MessageStep, true, onComplete)
        end,
        Move = function()
            -- Reset camera to default when any move is executed
            if self._battleSystem and self._battleSystem._cameraController then
                self._battleSystem._cameraController:ReturnToDefault()
            end
            
            -- Healing-only moves should not play attack animations; server will follow with a Heal step
            if step and step.Move and type(step.Move) == "string" then
                local Moves = require(game:GetService("ReplicatedStorage").Shared.Moves)
                local def = Moves[step.Move]
                if def and type(def.HealsPercent) == "number" and def.HealsPercent > 0 then
                    -- Only enqueue the move-used message and return
                    if step.Actor and step.Move then
                        local message = MessageGenerator.MoveUsed(step.Actor, step.Move, actorIsPlayer)
                        self._messageQueue:Enqueue(message)
                    end
                    if onComplete then onComplete() end
                    return
                end
            end
            -- Run move animation, then continue immediately so damage steps apply without waiting on message drain
            self:_processMove(step :: MoveStep, actorIsPlayer, onComplete)
        end,
        Damage = function()
            self:_processDamage(step :: DamageStep, actorIsPlayer, onComplete)
        end,
        Heal = function()
            -- Wait for the message queue to drain after heal-related messages
            self:_processHeal(step :: HealStep, actorIsPlayer, function()
                self:_afterDrain(onComplete)
            end)
        end,
        CaptureScan = function()
            -- Track scan index for cinematic effects
            self._captureScanIndex = (self._captureScanIndex or 0) + 1
            local scanIndex = self._captureScanIndex
            local scanSuccess = (step :: any).Success == true
            
            -- Process the visual scan flash on the creature FIRST
            self:_processCaptureScan(step :: CaptureScanStep, function()
                -- THEN process cinematic capture effects (FOV, shake, vignette, etc.) after scan animation
                if self._captureEffects then
                    self._captureEffects:ProcessScan(scanSuccess, scanIndex, function()
                        -- Only fade out the cube on failure
                        if not scanSuccess then
                            if self._combatEffects and self._combatEffects.FadeOutCaptureCube then
                                self._combatEffects:FadeOutCaptureCube()
                            end
                            -- Clean up capture effects on failure
                            if self._captureEffects then
                                self._captureEffects:EndCaptureSequence()
                                self._captureEffects = nil
                            end
                        end
                        if onComplete then onComplete() end
                    end)
                else
                    -- Fallback if no capture effects (shouldn't happen normally)
                    local s = (step :: any).Success
                    if s == false then
                        if self._combatEffects and self._combatEffects.FadeOutCaptureCube then
                            self._combatEffects:FadeOutCaptureCube()
                        end
                    end
                    if onComplete then onComplete() end
                end
            end)
        end,
        CaptureSuccess = function()
            -- Play cinematic capture celebration (FOV burst, flash, shake)
            if self._captureEffects then
                self._captureEffects:PlayCaptureSuccess(function()
                    -- Cleanup capture effects after celebration
                    if self._captureEffects then
                        self._captureEffects = nil
                    end
                    self._captureScanIndex = 0
                end)
            end
            
            -- On final success, fade out the cube before proceeding
            if self._combatEffects and self._combatEffects.FadeOutCaptureCube then
                self._combatEffects:FadeOutCaptureCube()
            end
            -- Hook victory music precisely when the success message is displayed
            local MusicManager
            pcall(function()
                MusicManager = require(script.Parent.Parent.Utilities.MusicManager)
            end)
            -- Temporarily wrap the message enqueue to play music at display time
            local originalEnqueue = self._messageQueue.Enqueue
            local triggered = false
            self._messageQueue.Enqueue = function(q, message: string)
                originalEnqueue(q, message)
                if (not triggered) and type(message) == "string" and string.find(string.lower(message), "was caught", 1, true) then
                    triggered = true
                    if MusicManager and MusicManager.PlayVictoryWild then
                        MusicManager:PlayVictoryWild()
                    end
                    -- Restore after triggering to avoid double plays
                    self._messageQueue.Enqueue = originalEnqueue
                end
            end
            self:_processCaptureSuccess(step :: CaptureSuccessStep, function()
                -- After capture success message and visuals, immediately display any queued XP/LevelUp steps
                self:_drainXPThen(onComplete)
            end)
        end,
        XP = function()
            self:_processXP(step :: any, onComplete)
        end,
        XPSpread = function()
            self:_processXPSpread(step :: any, onComplete)
        end,
        LevelUp = function()
            self:_processLevelUp(step :: any, onComplete)
        end,
        WaitDrain = function()
            self:_processWaitDrain(onComplete)
        end,
		Faint = function()
			print("[StepProcessor] Faint step detected - resolving faint side")
			local faintIsPlayer = self:_resolveFaintIsPlayer(step, actorIsPlayer)
			print("[StepProcessor] Faint resolved - IsPlayer:", faintIsPlayer, "(actorIsPlayer:", actorIsPlayer, ")")
			self:_processFaint(step :: FaintStep, faintIsPlayer, onComplete)
		end,
        Switch = function()
            -- Reset camera to default when any switch action occurs
            if self._battleSystem and self._battleSystem._cameraController then
                self._battleSystem._cameraController:ReturnToDefault()
            end
            
            self:_processSwitch(step :: SwitchStep, actorIsPlayer, onComplete)
        end,
        SwitchPreview = function()
            self:_processSwitchPreview(step :: any, onComplete)
        end,
        Miss = function()
            self:_processMiss(step :: MissStep, actorIsPlayer, onComplete)
        end,
        Crit = function()
            self:_processCrit(step :: CritStep, actorIsPlayer, onComplete)
        end,
        Status = function()
            self:_processStatus(step :: StatusStep, actorIsPlayer, onComplete)
        end,
        StatStage = function()
            self:_processStatStage(step :: StatStageStep, actorIsPlayer, onComplete)
        end,
        AbilityActivation = function()
            self:_processAbilityActivation(step :: AbilityActivationStep, actorIsPlayer, onComplete)
        end,
        MultiHitSummary = function()
            self:_processMultiHitSummary(step :: any, actorIsPlayer, onComplete)
        end,
        Recoil = function()
            self:_processRecoil(step :: any, actorIsPlayer, onComplete)
        end,
        EntryHazard = function()
            self:_processEntryHazard(step :: any, actorIsPlayer, onComplete)
        end,
        HazardDamage = function()
            self:_processHazardDamage(step :: any, actorIsPlayer, onComplete)
        end,
    }

    local handler = handlers[stepType]
    if handler then
        handler()
    else
        warn("[StepProcessor] Unknown step type:", stepType)
        if onComplete then onComplete() end
    end
end

--[[
	Internal: Process message step
]]
function StepProcessor:_processMessage(step: MessageStep, drain: boolean?, onComplete: StepCallback?)
    if step.Message then
        -- Check if message indicates a status application and play audio
        local message = tostring(step.Message):lower()
        if string.find(message, "became confused") or string.find(message, "is confused") then
            -- Play Confusion audio
            local model = self._sceneManager and (self._sceneManager:GetPlayerCreature() or self._sceneManager:GetFoeCreature())
            if model and self._combatEffects then
                self._combatEffects:PlayStatusEffect(model, "Confusion")
            end
        end
        
        self._messageQueue:Enqueue(step.Message)
    end
    if drain then
        self:_afterDrain(onComplete)
        return
    end
    if onComplete then onComplete() end
end

-- Utility: wait until the message queue drains, then call onComplete
function StepProcessor:_afterDrain(onComplete: StepCallback?)
    if not onComplete then return end
    if self._messageQueue and self._messageQueue.WaitForDrain then
        task.spawn(function()
            self._messageQueue:WaitForDrain()
            onComplete()
        end)
    else
        onComplete()
    end
end

-- Internal: Process capture scan step (visual glow/scan on creature)
function StepProcessor:_processCaptureScan(step: CaptureScanStep, onComplete: StepCallback?)
    local model = self._sceneManager:GetFoeCreature()
    local scanSuccess = (step.Success == nil) and true or (step.Success == true)
    
    if model and self._combatEffects then
        self._combatEffects:PlayScanFlash(model, scanSuccess)
    end
    
    -- Timing adjusted for dramatic effect:
    -- Success scans have a beat of anticipation before next
    -- Failure has a longer pause for the "oh no" moment
    local delay = scanSuccess and 0.6 or 1.0
    
    if onComplete then
        task.delay(delay, onComplete)
    end
end

-- Internal: Process capture success (custom message + hologram despawn)
function StepProcessor:_processCaptureSuccess(step: CaptureSuccessStep, onComplete: StepCallback?)
    local foeModel = self._sceneManager:GetFoeCreature()
    local creatureName = step.Creature or "creature"
    -- Choose a random celebratory message
    local variants = {
        "Gotcha! %s was caught!",
        "Perfect! %s was caught!",
        "Awesome! %s was caught!",
    }
    local msg = string.format(variants[math.random(1, #variants)], creatureName)
    -- Start victory music immediately (clean trigger)
    local ok, MusicManager = pcall(function() return require(script.Parent.Parent.Utilities.MusicManager) end)
    if ok and MusicManager and MusicManager.PlayVictoryWild then
        MusicManager:PlayVictoryWild()
    end
    if self._messageQueue then
        self._messageQueue:Enqueue(msg)
    end
    -- Slide out enemy UI similarly to faint path
    if self._uiController then
        self._uiController:SlideUIOut(false)
    end
    if foeModel and self._combatEffects then
        -- Use the same fade-out hologram used for recall (no faint semantics)
        self._combatEffects:PlayRecallAnimation(foeModel, function()
            if onComplete then onComplete() end
        end)
    else
        if onComplete then onComplete() end
    end
end

-- After capture success, drain any XP-related steps (XP, XPSpread, LevelUp) in order, then continue
function StepProcessor:_drainXPThen(onComplete: StepCallback?)
    if not self._battleSystem or not self._battleSystem._pendingXPEvents then
        if onComplete then onComplete() end
        return
    end
    -- Ensure XP events, if queued on battle system, are flushed as messages
    local events = self._battleSystem._pendingXPEvents
    self._battleSystem._pendingXPEvents = nil
    if type(events) == "table" and #events > 0 then
        for _, ev in ipairs(events) do
            local msg = require(script.Parent.BattleMessageGenerator).FromEvent(ev)
            if msg and self._messageQueue then
                self._messageQueue:Enqueue(msg)
            end
        end
        -- Wait for messages to finish before proceeding
        self:_afterDrain(onComplete)
    else
        if onComplete then onComplete() end
    end
end

function StepProcessor:_processXP(step: any, onComplete: StepCallback?)
    local msg = MessageGenerator.FromEvent({ Type = "XP", Creature = step.Creature, Amount = step.Amount, IsShared = step.IsShared })
    if msg then self._messageQueue:Enqueue(msg) end
    if onComplete then onComplete() end
end

function StepProcessor:_processXPSpread(step: any, onComplete: StepCallback?)
    local msg = MessageGenerator.FromEvent({ Type = "XPSpread" })
    if msg then self._messageQueue:Enqueue(msg) end
    if onComplete then onComplete() end
end

function StepProcessor:_processLevelUp(step: any, onComplete: StepCallback?)
    local msg = MessageGenerator.FromEvent({ Type = "LevelUp", Creature = step.Creature, Level = step.Level })
    if msg then self._messageQueue:Enqueue(msg) end
    if onComplete then onComplete() end
end

-- Internal: Process explicit wait-until-drain step
function StepProcessor:_processWaitDrain(onComplete: StepCallback?)
    self:_afterDrain(onComplete)
end

--[[
	Internal: Process move step
]]
function StepProcessor:_processMove(step: any, isPlayer: boolean, onComplete: StepCallback?)
	-- Reset effectiveness message flag for new move
	-- Store the current move's effectiveness so Damage step uses the correct value
	self._effectivenessMessageShown = false
	self._currentMoveEffectiveness = step.Effectiveness -- Track this move's effectiveness
	
	-- Clear early HP update flag for new move (prevents stale flags from previous moves)
	self._earlyHPUpdateTarget = nil
	
	local attackerModel = isPlayer 
		and self._sceneManager:GetPlayerCreature() 
		or self._sceneManager:GetFoeCreature()
	
	local defenderModel = isPlayer 
		and self._sceneManager:GetFoeCreature() 
		or self._sceneManager:GetPlayerCreature()
	
    -- Generate message from structured data
	if step.Actor and step.Move then
		local message = MessageGenerator.MoveUsed(step.Actor, step.Move, isPlayer)
		self._messageQueue:Enqueue(message)
	elseif step.Message then
		-- Fallback for legacy format (temporary during migration)
		self._messageQueue:Enqueue(step.Message)
	end
	
	-- Play agent action animation if agent is using a move in trainer battle
	if not isPlayer and self._battleState.Type == "Trainer" then
		AgentAnimations:PlayActionAnimation()
	end
	
	-- Enqueue effectiveness message immediately after move message (before faint/other messages)
	-- Use the Move step's own effectiveness value (not a cached/stale one)
	local moveEffectiveness = step.Effectiveness
	if type(moveEffectiveness) == "string" and not self._effectivenessMessageShown then
		local key: string?
		if moveEffectiveness == "Super" then
			key = "SuperEffective"
		elseif moveEffectiveness == "NotVery" then
			key = "NotVeryEffective"
		elseif moveEffectiveness == "Immune" then
			key = "NoEffect"
		end
		if key then
			local effectivenessMsg = MessageGenerator.Effectiveness(key)
			if effectivenessMsg and self._messageQueue then
				self._messageQueue:Enqueue(effectivenessMsg)
				self._effectivenessMessageShown = true -- Mark as shown to prevent duplicates
			end
		end
	end
	
	-- Play move animation
	if attackerModel and defenderModel then
        local hadPending = (self._battleState and self._battleState:GetPendingHP() ~= nil)
		-- Defer committing the pending HP snapshot until the hit marker.
		-- Do NOT update HP when the creature is sent out; only tween on hit.
		
		-- Check if move missed (no HPDelta means no damage, which indicates a miss)
		local hpDelta = (step and type(step.HPDelta) == "table") and step.HPDelta or nil
		
		-- Check if this is a multi-hit move - damage will be handled by individual Damage steps
		local isMultiHit = step.IsMultiHit == true
		
		-- Get effectiveness from Move step for hit impact effects
		local effectiveness = step.Effectiveness
		local targetIsPlayer = (not isPlayer) == true
		
		-- Check if move actually dealt damage to the target (more robust type-checked version)
		-- This is the authoritative check for whether hit effects should play
		-- For multi-hit moves, skip damage application here - Damage steps will handle it
		local hasDamage = false
		if not isMultiHit and hpDelta then
			if isPlayer and type(hpDelta.Enemy) == "number" and hpDelta.Enemy < 0 then
				hasDamage = true
			elseif not isPlayer and type(hpDelta.Player) == "number" and hpDelta.Player < 0 then
				hasDamage = true
			end
		end
		
		-- For animation purposes: determine if move missed (skip Damaged animation)
		-- A move missed if no damage was dealt (hasDamage is false)
		-- Exception: Multi-hit moves should NOT be treated as a miss - the Damage steps handle hits
		local willMiss = not hasDamage and not isMultiHit
		
		-- Debug: Log move step details
		print("[StepProcessor] _processMove - effectiveness:", effectiveness, "willMiss:", willMiss, "hasDamage:", hasDamage, "defenderModel:", defenderModel)
		
		-- Resolve move name for animation/handlers
		local moveNameForAnim = step.Move or step.MoveName or step.Name or "Unknown"
		print("[StepProcessor] Using move name for anim:", tostring(moveNameForAnim))

		-- Skip animation for multi-hit moves - individual Damage steps will handle animations via PlayMultiHitDamage
		if isMultiHit then
			print("[StepProcessor] Skipping PlayMoveAttack for multi-hit move - Damage steps will handle animations")
			-- Record pending damage delta for fallback if provided (do not apply here)
			if hpDelta then
				if isPlayer and type(hpDelta.Enemy) == "number" then
					self._pendingDamageDeltaFoe = hpDelta.Enemy -- negative value
				elseif (not isPlayer) and type(hpDelta.Player) == "number" then
					self._pendingDamageDeltaPlayer = hpDelta.Player -- negative value
				end
			end
			-- Complete immediately to proceed to Damage steps
			if onComplete then
				onComplete()
			end
		else
			-- Single-hit moves: play attack animation normally
			self._combatEffects:PlayMoveAttack(
				attackerModel,
				defenderModel,
				moveNameForAnim,
				function()
					-- Hit marker reached - trigger hit impact effects immediately
					-- ALWAYS trigger effects if move dealt damage (hasDamage is true)
					print("[StepProcessor] Hit marker reached - hasDamage:", hasDamage, "effectiveness:", effectiveness, "defenderModel:", defenderModel)
					if hasDamage and defenderModel then
						-- Determine effectiveness category for hit impact VFX
						local category: string? = nil
						if effectiveness == "Super" then
							category = "Super"
						elseif effectiveness == "NotVery" then
							category = "Weak"
						end
						-- Normal effectiveness (nil category) will use NormalHit in PlayHitImpact
						print("[StepProcessor] Triggering hit effects - category:", category or "Normal", "effectiveness:", effectiveness)
						-- Play hit impact effects on the defender at the hit marker
						self._combatEffects:PlayHitImpact(defenderModel, category)
						-- Play damage flash effect (includes effectiveness sound)
						self._combatEffects:PlayDamageFlash(defenderModel, effectiveness)

						-- Floating damage text (single-hit moves) at hit marker for tight sync
						if self._combatEffects and self._combatEffects.CreateFloatingText and hpDelta then
							local damageDelta = 0
							if targetIsPlayer and type(hpDelta.Player) == "number" then
								damageDelta = hpDelta.Player -- negative
							elseif (not targetIsPlayer) and type(hpDelta.Enemy) == "number" then
								damageDelta = hpDelta.Enemy -- negative
							end
							if damageDelta < 0 then
								local amt = math.abs(damageDelta)
								self._combatEffects:CreateFloatingText(defenderModel, "-" .. tostring(amt), Color3.fromRGB(255, 92, 92))
							end
						end
						
						-- Play agent damage reaction animation if player attacked agent's creature in trainer battle
						if isPlayer and not targetIsPlayer and self._battleState.Type == "Trainer" then
							if effectiveness == "Super" then
								AgentAnimations:PlaySuperEffectiveDamageReaction()
							else
								-- Normal or NotVery effective
								AgentAnimations:PlayNormalDamageReaction()
							end
						end
						
						-- Update HP immediately at hit marker for non-multi-hit moves to reduce delay
						-- Multi-hit moves have individual Damage steps per hit, so skip early update
						if not isMultiHit and hpDelta then
							local creature = targetIsPlayer and self._battleState.PlayerCreature or self._battleState.FoeCreature
							if creature and creature.Stats and creature.MaxStats then
								local maxHP = creature.MaxStats.HP or 1
								local statsHP = creature.Stats and creature.Stats.HP
								local currentHP = statsHP
								
								-- CRITICAL FIX: In PvP execution order mode, use tracked HP instead of creature.Stats.HP
								-- This fixes the issue where creature.Stats.HP has already been updated to final HP
								-- before we process steps in execution order
								if targetIsPlayer and self._currentPlayerHP ~= nil then
									currentHP = self._currentPlayerHP
									print("[StepProcessor] Hit marker - Using tracked Player HP:", currentHP, "(creature.Stats.HP was:", statsHP, ")")
								elseif not targetIsPlayer and self._currentFoeHP ~= nil then
									currentHP = self._currentFoeHP
									print("[StepProcessor] Hit marker - Using tracked Foe HP:", currentHP, "(creature.Stats.HP was:", statsHP, ")")
								else
									-- Fallback to existing logic for non-PvP or when tracking not initialized
									-- Prefer CurrentHP percentage when available, as it's authoritative from server
									-- If CurrentHP percentage suggests different HP than Stats.HP, trust the percentage
									-- This handles cases where Stats.HP is stale from previous turns
									if creature.CurrentHP and type(creature.CurrentHP) == "number" then
										local hpFromPercentage = math.floor((creature.CurrentHP / 100) * maxHP + 0.5)
										-- Use percentage if Stats.HP is nil/0, or if percentage suggests significantly different HP
										-- Threshold: if difference is >= 10% of max HP, prefer percentage (indicates stale Stats.HP)
										local hpDifference = math.abs((hpFromPercentage or 0) - (statsHP or 0))
										if statsHP == nil or statsHP == 0 or hpDifference >= (maxHP * 0.1) then
											currentHP = hpFromPercentage
											if statsHP ~= nil and statsHP ~= hpFromPercentage then
												print("[StepProcessor] Hit marker - Using CurrentHP percentage (Stats.HP appears stale):", creature.CurrentHP, "% -> ", currentHP, "HP (Stats.HP was:", statsHP, "diff:", hpDifference, ")")
											end
										end
									end
								end
								
								currentHP = currentHP or 0
								local damageAmount = 0
								
								-- Calculate damage from HPDelta (negative value)
								if targetIsPlayer and type(hpDelta.Player) == "number" then
									damageAmount = hpDelta.Player -- Already negative
								elseif not targetIsPlayer and type(hpDelta.Enemy) == "number" then
									damageAmount = hpDelta.Enemy -- Already negative
								end
								
								if damageAmount < 0 then
									print("[StepProcessor] Hit marker HP calculation - currentHP:", currentHP, "damageAmount:", damageAmount, "maxHP:", maxHP)
									local newHP = math.max(0, currentHP + damageAmount) -- damageAmount is negative, so this subtracts
									
									-- Update tracked HP for PvP execution order mode
									if targetIsPlayer and self._currentPlayerHP ~= nil then
										self._currentPlayerHP = newHP
									elseif not targetIsPlayer and self._currentFoeHP ~= nil then
										self._currentFoeHP = newHP
									end
									
									-- Update creature data with new HP
									local updatedCreature = table.clone(creature)
									updatedCreature.Stats = updatedCreature.Stats or {}
									updatedCreature.Stats.HP = newHP
									updatedCreature.MaxStats = updatedCreature.MaxStats or {}
									updatedCreature.MaxStats.HP = maxHP
									
									-- Update battle state with new HP
									if targetIsPlayer then
										self._battleState:UpdatePlayerCreature(updatedCreature, self._battleState.PlayerCreatureIndex or 1)
									else
										self._battleState:UpdateFoeCreature(updatedCreature)
									end
									
									-- Update UI immediately with tween
									if self._uiController then
										self._uiController:UpdateCreatureUI(targetIsPlayer, updatedCreature, true)
										self._uiController:UpdateLevelUI(updatedCreature, false)
									end
									
									-- Update animation speed based on HP
									local model = targetIsPlayer and self._sceneManager:GetPlayerCreature() or self._sceneManager:GetFoeCreature()
									if model and self._animationController then
										self._animationController:UpdateIdleSpeed(model, newHP, maxHP)
									end
									
									-- Mark that HP was updated early for this target
									self._earlyHPUpdateTarget = targetIsPlayer
									
									print("[StepProcessor] HP updated at hit marker - Target:", targetIsPlayer and "Player" or "Foe", "NewHP:", newHP, "MaxHP:", maxHP)
								end
							end
						end
					else
						print("[StepProcessor] Skipping hit effects - hasDamage:", hasDamage, "defenderModel:", defenderModel)
					end
				end,
				onComplete,
				willMiss  -- Skip Damaged animation if move missed
			)
			-- Record pending damage delta for fallback if provided (do not apply here)
			if hpDelta then
				if isPlayer and type(hpDelta.Enemy) == "number" then
					self._pendingDamageDeltaFoe = hpDelta.Enemy -- negative value
				elseif (not isPlayer) and type(hpDelta.Player) == "number" then
					self._pendingDamageDeltaPlayer = hpDelta.Player -- negative value
				end
			end
		end
	else
		if onComplete then
			onComplete()
		end
	end
end

--[[
	Internal: Process damage step
]]
function StepProcessor:_processDamage(step: any, isPlayer: boolean, onComplete: StepCallback?)
    -- Determine target side: use step.IsPlayer if available (indicates which creature was damaged)
    -- step.IsPlayer = true means player's creature was damaged, false means foe's creature was damaged
    local targetIsPlayer = nil
    if type(step.IsPlayer) == "boolean" then
        targetIsPlayer = step.IsPlayer
    else
        -- Fallback: if step came from friendlyActions (isPlayer=true), damage is typically to foe
        -- If step came from enemyActions (isPlayer=false), damage is typically to player
        -- But this is unreliable, so we should always have step.IsPlayer set
        targetIsPlayer = not isPlayer
    end
    
    print("[StepProcessor] _processDamage - step.IsPlayer:", step.IsPlayer, "isPlayer param:", isPlayer, "targetIsPlayer:", targetIsPlayer)
    print("[StepProcessor] _processDamage - step.Message:", step.Message, "step.NewHP:", step.NewHP, "step.EndOfTurn:", step.EndOfTurn)
    print("[StepProcessor] _processDamage - Full step:", step)

    -- Check if this is a status damage message and set up status effect callback
    local statusForEffect = nil
    if step.Message and type(step.Message) == "string" then
        local msgLower = step.Message:lower()
        if string.find(msgLower, "hurt by") then
            -- Extract status from damage message
            if string.find(msgLower, "burn") then
                statusForEffect = "BRN"
            elseif string.find(msgLower, "toxic") then
                statusForEffect = "TOX"
            elseif string.find(msgLower, "poison") then
                statusForEffect = "PSN"
            elseif string.find(msgLower, "paralyz") then
                statusForEffect = "PAR"
            end
        end
    end
    
    -- Set status effect callback if this is a status damage message
    if statusForEffect then
        local model = targetIsPlayer and self._sceneManager:GetPlayerCreature() or self._sceneManager:GetFoeCreature()
        if model and self._messageQueue and self._messageQueue.SetStatusEffectCallback then
            self._messageQueue:SetStatusEffectCallback(function()
                print("[StepProcessor] Status damage message displayed - playing status effect for:", statusForEffect)
                self._combatEffects:PlayStatusEffect(model, statusForEffect)
            end)
        end
    end

    -- Show message first if provided (for end-of-turn status damage like burn)
    if step.Message then
        self._messageQueue:Enqueue(step.Message)
    end

    -- Apply HP update from step.NewHP for ALL damage steps (not just end-of-turn)
    -- Since we process steps in execution order, each damage step should update HP incrementally
    -- HP updates are now non-blocking to minimize delay while keeping individual step processing
    -- Skip HP update if it was already done at the hit marker for this target
    local shouldSkipHPUpdate = (self._earlyHPUpdateTarget ~= nil) and (self._earlyHPUpdateTarget == targetIsPlayer)
    
    if step and type(step.NewHP) == "number" and not shouldSkipHPUpdate then
        local creature = targetIsPlayer and self._battleState.PlayerCreature or self._battleState.FoeCreature
        if creature and creature.Stats then
            local currentHP = creature.Stats.HP or 0
            local maxHP = creature.MaxStats and creature.MaxStats.HP or (step.MaxHP or 1)
            
            print("[StepProcessor] _processDamage - Processing damage step:", "Target:", targetIsPlayer and "Player" or "Foe", "CurrentHP:", currentHP, "step.NewHP:", step.NewHP, "step.MaxHP:", step.MaxHP, "CalculatedMaxHP:", maxHP)
            
            -- Warn if NewHP equals MaxHP during damage (suspicious - might indicate incorrect data)
            if type(step.MaxHP) == "number" and step.NewHP == step.MaxHP and step.NewHP > 0 then
                warn("[StepProcessor] SUSPICIOUS: step.NewHP equals step.MaxHP during damage step! NewHP:", step.NewHP, "MaxHP:", step.MaxHP, "Target:", targetIsPlayer and "Player" or "Foe", "This might indicate incorrect server data.")
            end
            
            -- Update the creature data with new HP immediately
            local updatedCreature = table.clone(creature)
            updatedCreature.Stats = updatedCreature.Stats or {}
            updatedCreature.Stats.HP = math.max(0, step.NewHP)
            if type(step.MaxHP) == "number" then
                updatedCreature.MaxStats = updatedCreature.MaxStats or {}
                updatedCreature.MaxStats.HP = step.MaxHP
            end
            
            print("[StepProcessor] _processDamage - Updated creature HP:", updatedCreature.Stats.HP, "/", (updatedCreature.MaxStats and updatedCreature.MaxStats.HP or "nil"), "before calling UpdateCreatureUI")
            
            -- Update tracked HP for PvP execution order mode
            if targetIsPlayer and self._currentPlayerHP ~= nil then
                self._currentPlayerHP = updatedCreature.Stats.HP
            elseif not targetIsPlayer and self._currentFoeHP ~= nil then
                self._currentFoeHP = updatedCreature.Stats.HP
            end
            
            -- Update battle state with new HP
            if targetIsPlayer then
                self._battleState:UpdatePlayerCreature(updatedCreature, self._battleState.PlayerCreatureIndex or 1)
            else
                self._battleState:UpdateFoeCreature(updatedCreature)
            end
            
            -- Validate that Stats.HP is set before updating UI
            if updatedCreature.Stats and updatedCreature.Stats.HP ~= nil then
                -- Update UI with tween (HP bar updates when damage step is processed)
                -- Non-blocking: tween happens in background, we don't wait for completion
                self._uiController:UpdateCreatureUI(targetIsPlayer, updatedCreature, true)
                self._uiController:UpdateLevelUI(updatedCreature, false)
            else
                warn("[StepProcessor] Skipping UI update - Stats.HP is nil for damage step. NewHP:", step.NewHP, "Target:", targetIsPlayer and "Player" or "Foe")
            end
            
            -- Update animation speed based on HP (non-blocking)
            local model = targetIsPlayer and self._sceneManager:GetPlayerCreature() or self._sceneManager:GetFoeCreature()
            if model and self._animationController then
                local maxHP = updatedCreature.MaxStats and updatedCreature.MaxStats.HP or creature.MaxStats and creature.MaxStats.HP or step.NewHP
                self._animationController:UpdateIdleSpeed(model, step.NewHP, maxHP)
            end
            
            print("[StepProcessor] Damage step HP applied - Target:", targetIsPlayer and "Player" or "Foe", "NewHP:", step.NewHP, "MaxHP:", step.MaxHP, "EndOfTurn:", step.EndOfTurn)

			-- Floating damage text for non-multi-hit damage steps (e.g., end-of-turn/status damage)
			-- Note: single-hit move damage is already shown at hit marker in _processMove.
			if self._combatEffects and self._combatEffects.CreateFloatingText and step.IsMultiHit ~= true then
				local delta = (currentHP or 0) - (updatedCreature.Stats.HP or 0)
				if delta > 0 and step.Message then
					local model = targetIsPlayer and self._sceneManager:GetPlayerCreature() or self._sceneManager:GetFoeCreature()
					if model then
						self._combatEffects:CreateFloatingText(model, "-" .. tostring(delta), Color3.fromRGB(255, 92, 92))
					end
				end
			end
        end
    elseif shouldSkipHPUpdate then
        print("[StepProcessor] Skipping HP update in Damage step - already updated at hit marker for", targetIsPlayer and "Player" or "Foe")
    else
        -- Damage step exists but NewHP is not a number or step is nil
        warn("[StepProcessor] Damage step processed but NewHP is not valid:", "step:", step and "exists" or "nil", "step.NewHP:", step and step.NewHP or "nil", "Target:", targetIsPlayer and "Player" or "Foe")
    end
    
    -- Clear early HP update flag after processing this Damage step
    if self._earlyHPUpdateTarget == targetIsPlayer then
        self._earlyHPUpdateTarget = nil
    end

    -- Only wait for message drain for end-of-turn damage with messages (like burn/poison)
    -- For move damage (no message), skip wait to minimize delay - HP updates happen immediately
    -- This keeps individual step processing while reducing perceived delay
    if step.Message and step.EndOfTurn and self._messageQueue and self._messageQueue.WaitForDrain then
        self._messageQueue:WaitForDrain()
    end

    -- Removed optional delay - HP updates happen immediately for better responsiveness
    -- Individual steps still process in order, but without artificial delays

    -- Play damage flash and hit impact effects
    -- Note: For normal move damage, effects are already triggered at the hit marker in _processMove
    -- End-of-turn damage effects are triggered immediately above when message appears
    -- Only trigger effects here for standalone damage steps (non-move, non-end-of-turn) that have a message
    -- This handles cases like confusion self-damage or other status damage that isn't end-of-turn
    if not step.EndOfTurn and step.Message then
        local model = targetIsPlayer and self._sceneManager:GetPlayerCreature() or self._sceneManager:GetFoeCreature()
        if model then
            print("[StepProcessor] Standalone damage step - triggering effects")
            self._combatEffects:PlayDamageFlash(model, step.Effectiveness)
            -- Also play the impact VFX based on effectiveness
            local category: string? = nil
            if step.Effectiveness == "Super" then
                category = "Super"
            elseif step.Effectiveness == "NotVery" then
                category = "Weak"
            end
            self._combatEffects:PlayHitImpact(model, category)
        end
    end

    -- Multi-hit damage step handling
    -- For multi-hit moves, play damage flash and HP update for each hit
    local isMultiHit = step.IsMultiHit == true
    local hitNumber = step.HitNumber or 1
    local totalHits = step.TotalHits or 1
    local isLastHit = (hitNumber >= totalHits)
    
    -- For multi-hit damage steps, play effects with animation and wait for completion
    if isMultiHit and not step.EndOfTurn and not step.Message then
        -- Get both attacker and defender models
        -- For multi-hit, the attacker is the one NOT being damaged (opposite of targetIsPlayer)
        local defenderModel = targetIsPlayer and self._sceneManager:GetPlayerCreature() or self._sceneManager:GetFoeCreature()
        local attackerModel = targetIsPlayer and self._sceneManager:GetFoeCreature() or self._sceneManager:GetPlayerCreature()
        
        -- Show crit message if this particular hit was a crit
        if step.IsCrit then
            local critMsg = MessageGenerator.CriticalHit()
            if critMsg and self._messageQueue then
                self._messageQueue:Enqueue(critMsg)
            end
			-- Subtle crit VFX on the defender (multi-hit crits don't always include a Crit step)
			if defenderModel and self._combatEffects then
				self._combatEffects:PlayCriticalHitEffect(defenderModel)
				self._combatEffects:CreateFloatingText(defenderModel, "CRIT", Color3.fromRGB(255, 214, 74))
			end
        end
        
        -- Update HP bar for this hit
        local creature = targetIsPlayer and self._battleState.PlayerCreature or self._battleState.FoeCreature
        if creature and step.NewHP ~= nil then
            local updatedCreature = table.clone(creature)
            updatedCreature.Stats = updatedCreature.Stats or {}
            updatedCreature.Stats.HP = math.max(0, step.NewHP)
            
            if targetIsPlayer then
                self._battleState:UpdatePlayerCreature(updatedCreature, self._battleState.PlayerCreatureIndex or 1)
            else
                self._battleState:UpdateFoeCreature(updatedCreature)
            end
            
            self._uiController:UpdateHPBar(targetIsPlayer, updatedCreature, true)
        end
        
        print("[StepProcessor] Multi-hit damage - Hit", hitNumber, "/", totalHits, "NewHP:", step.NewHP, "IsCrit:", step.IsCrit)

		-- Floating damage per hit (multi-hit)
		if defenderModel and self._combatEffects and self._combatEffects.CreateFloatingText then
			local dmgAmt = tonumber(step.DamageAmount) or tonumber(step.Damage) or nil
			if dmgAmt and dmgAmt > 0 then
				self._combatEffects:CreateFloatingText(defenderModel, "-" .. tostring(dmgAmt), Color3.fromRGB(255, 92, 92))
			end
		end
        
        -- Play multi-hit damage effects with attack + damaged animations, wait for completion
        if defenderModel then
            -- Capture references for the callback
            local capturedOnComplete = onComplete
            local capturedIsLastHit = isLastHit
            local capturedEffectiveness = step.Effectiveness
            
            self._combatEffects:PlayMultiHitDamage(attackerModel, defenderModel, step.Effectiveness, function()
                -- Animation completed - now show effectiveness message if this is the last hit
                if capturedIsLastHit then
                    local shouldShowEff = type(capturedEffectiveness) == "string" and not self._effectivenessMessageShown
                    if shouldShowEff then
                        local key: string? = nil
                        if capturedEffectiveness == "Super" then
                            key = "SuperEffective"
                        elseif capturedEffectiveness == "NotVery" then
                            key = "NotVeryEffective"
                        elseif capturedEffectiveness == "Immune" then
                            key = "NoEffect"
                        end
                        if key then
                            local msg = MessageGenerator.Effectiveness(key)
                            if msg and self._messageQueue then
                                self._messageQueue:Enqueue(msg)
                                self._effectivenessMessageShown = true
                            end
                        end
                    end
                end
                
                -- Call onComplete after animation finishes
                if capturedOnComplete then
                    capturedOnComplete()
                end
            end)
            
            -- Return early - the animation callback will handle onComplete
            return
        end
    end

    -- Enqueue effectiveness message when applicable (only once per move sequence)
    -- Use THIS step's effectiveness value, not a cached one from a previous move
    -- For multi-hit moves, only show effectiveness on the last hit (handled above for animated multi-hit)
    local damageEffectiveness = step.Effectiveness
    local isNoEffect = false
    
    -- Only show effectiveness message if:
    -- 1. This step has a valid effectiveness string
    -- 2. The message hasn't been shown yet for this move sequence
    -- 3. The effectiveness matches the current move's effectiveness (prevents stale messages)
    -- 4. For multi-hit moves, only show on the last hit
    local shouldShowEffectiveness = type(damageEffectiveness) == "string" 
        and not self._effectivenessMessageShown
        and (self._currentMoveEffectiveness == nil or damageEffectiveness == self._currentMoveEffectiveness)
        and (not isMultiHit or isLastHit) -- Only show on last hit for multi-hit moves
    
    if shouldShowEffectiveness then
        local key: string?
        if damageEffectiveness == "Super" then
            key = "SuperEffective"
        elseif damageEffectiveness == "NotVery" then
            key = "NotVeryEffective"
        elseif damageEffectiveness == "Immune" then
            key = "NoEffect"
            isNoEffect = true
        end
        if key then
            local msg = MessageGenerator.Effectiveness(key)
            if msg and self._messageQueue then
                self._messageQueue:Enqueue(msg)
                self._effectivenessMessageShown = true -- Mark as shown to prevent duplicates
            end
        end
    end

    if onComplete then
        if isNoEffect then
            -- Wait for "doesn't affect" message to drain before proceeding
            if self._messageQueue and self._messageQueue.WaitForDrain then
                self._messageQueue:WaitForDrain()
            end
            onComplete()
        elseif step.EndOfTurn == true then
            -- End-of-turn damage (like burn) - complete immediately after UI update
            onComplete()
        elseif step.NewHP ~= nil then
            -- Any damage step with HP update - complete immediately for tight timing
            -- HP updates happen at appropriate times (hit marker for moves, immediately for others)
            -- No delay - individual steps process quickly while maintaining correct order
            onComplete()
        elseif step.Message then
            -- Damage step with message but no HP update - wait briefly for message to show
            task.spawn(function()
                if self._messageQueue and self._messageQueue.WaitForDrain then
                    self._messageQueue:WaitForDrain()
                end
                onComplete()
            end)
        else
            -- No message, no HP - complete immediately
            onComplete()
        end
    end
end

--[[
	Internal: Process heal step
]]
function StepProcessor:_processHeal(step: any, isPlayer: boolean, onComplete: StepCallback?)
	-- Show message first so the audience reads it before the HP bar moves
	if step.Message then
		self._messageQueue:Enqueue(step.Message)
	end

	-- Optional delay (e.g., Crumbs) before visually applying the heal
	local delaySec = tonumber(step.DelaySeconds) or tonumber(step.Delay) or 0
	if delaySec and delaySec > 0 then
		task.wait(delaySec)
	end

	-- Use server-authoritative creature data already updated in battle state
	local serverCreature = isPlayer 
		and self._battleState.PlayerCreature 
		or self._battleState.FoeCreature

	if serverCreature then
		-- For player's heal: if we detect incoming enemy damage this turn, display the healed HP,
		-- not the end-of-turn HP. Compute pre-damage visual using incoming damage context.
		-- Skip this adjustment for end-of-turn heals (e.g., Crumbs) to avoid HP appearing to go down.
		local isEndOfTurnHeal = (step and (step.EndOfTurn == true or (tonumber(step.DelaySeconds) or 0) > 0)) or false
		if (not isEndOfTurnHeal) and isPlayer and self._incomingContext and type(self._incomingContext.incomingPlayerDamageAbs) == "number" then
			local dmgAbs = self._incomingContext.incomingPlayerDamageAbs
			local vis = table.clone(serverCreature)
			vis.Stats = vis.Stats or {}
			local healedHP = vis.Stats.HP or 0
			-- Only adjust if current HP equals final HP; display pre-damage value for the Heal step
			local finalHP = tonumber(self._incomingContext.finalPlayerHP)
			if type(finalHP) == "number" and healedHP == finalHP and dmgAbs > 0 then
				vis.Stats.HP = math.max(0, healedHP + dmgAbs)
			end
			self._uiController:UpdateCreatureUI(isPlayer, vis, true)
			self._uiController:UpdateLevelUI(vis, false)
		else
			-- Prefer an explicit target HP provided by server (e.g., Crumbs NewHP)
			if type(step.NewHP) == "number" then
				local vis = table.clone(serverCreature)
				vis.Stats = vis.Stats or {}
				vis.Stats.HP = math.max(0, step.NewHP)
				if type(step.MaxHP) == "number" then
					vis.MaxStats = vis.MaxStats or {}
					vis.MaxStats.HP = step.MaxHP
				end
				self._uiController:UpdateCreatureUI(isPlayer, vis, true)
				self._uiController:UpdateLevelUI(vis, false)
			else
				self._uiController:UpdateCreatureUI(isPlayer, serverCreature, true)
				self._uiController:UpdateLevelUI(serverCreature, false)
			end
		end
	end
	
	-- Play heal effect
	local model = isPlayer 
		and self._sceneManager:GetPlayerCreature() 
		or self._sceneManager:GetFoeCreature()
	
	if model and step.Amount then
		self._combatEffects:PlayHealEffect(model, step.Amount)
		if self._combatEffects and self._combatEffects.CreateFloatingText then
			self._combatEffects:CreateFloatingText(model, "+" .. tostring(step.Amount), Color3.fromRGB(72, 255, 140))
		end
	end
	
	if onComplete then
		task.delay(0.3, onComplete)
	end
end

--[[
	Internal: Process recoil step
	Handles recoil damage from high-power moves like Take Down, Double-Edge, Brave Bird
]]
function StepProcessor:_processRecoil(step: any, isPlayer: boolean, onComplete: StepCallback?)
	print("[StepProcessor] Processing recoil step - IsPlayer:", isPlayer, "Creature:", step.Creature, "RecoilDamage:", step.RecoilDamage)
	
	-- Generate and enqueue recoil message using the message generator
	if step.Creature then
		local message = MessageGenerator.Recoil(step.Creature)
		self._messageQueue:Enqueue(message)
	end
	
	-- Update HP bar for the creature that took recoil
	if type(step.NewHP) == "number" then
		local creature = isPlayer 
			and self._battleState.PlayerCreature 
			or self._battleState.FoeCreature
		
		if creature then
			local updatedCreature = table.clone(creature)
			updatedCreature.Stats = updatedCreature.Stats or {}
			updatedCreature.Stats.HP = math.max(0, step.NewHP)
			if type(step.MaxHP) == "number" then
				updatedCreature.MaxStats = updatedCreature.MaxStats or {}
				updatedCreature.MaxStats.HP = step.MaxHP
			end
			
			-- Update tracked HP for PvP execution order mode
			if isPlayer and self._currentPlayerHP ~= nil then
				self._currentPlayerHP = updatedCreature.Stats.HP
			elseif not isPlayer and self._currentFoeHP ~= nil then
				self._currentFoeHP = updatedCreature.Stats.HP
			end
			
			-- Update battle state
			if isPlayer then
				self._battleState:UpdatePlayerCreature(updatedCreature, self._battleState.PlayerCreatureIndex or 1)
			else
				self._battleState:UpdateFoeCreature(updatedCreature)
			end
			
			-- Update UI with tween
			self._uiController:UpdateCreatureUI(isPlayer, updatedCreature, true)
		end
	end
	
	-- Play damage flash on the creature that took recoil (same as getting hit)
	local model = isPlayer 
		and self._sceneManager:GetPlayerCreature() 
		or self._sceneManager:GetFoeCreature()
	
	if model then
		self._combatEffects:PlayDamageFlash(model, "Normal")
	end
	
	-- Wait for message to display before continuing
	if self._messageQueue and self._messageQueue.WaitForDrain then
		self._messageQueue:WaitForDrain()
	end
	
	if onComplete then
		task.delay(0.3, onComplete)
	end
end

--[[
	Internal: Process faint step
]]
function StepProcessor:_processFaint(step: any, isPlayer: boolean, onComplete: StepCallback?)
	print("[StepProcessor] Processing faint step - IsPlayer:", isPlayer)
    
    -- Server-authoritative: enqueue faint message exactly once per faint step
    if step and step.Creature then
        print("[FAINT][StepProcessor] enqueue for:", step.Creature, "isPlayer:", isPlayer)
        print("[NewTestLog] Faint: creature=", step.Creature, "isPlayer=", isPlayer)
        local message = MessageGenerator.Faint(step.Creature, isPlayer)
        self._messageQueue:Enqueue(message)
    elseif step and step.Message then
        self._messageQueue:Enqueue(step.Message)
    end

	-- Refresh CreatureAmount indicators on faint
	if self._uiController and self._battleSystem and self._battleSystem._battleInfo then
		-- If foe fainted in trainer battle, mark index by name (fallback when foe party HP isn't synced)
		if (not isPlayer) and self._battleSystem._battleInfo.Type == "Trainer" and type(step.Creature) == "string" then
			local party = self._battleSystem._battleInfo.TrainerParty
			if type(party) == "table" then
				for i, c in ipairs(party) do
					local nm = (c and (c.Nickname or c.Name))
					if nm == step.Creature then
						if self._uiController.MarkFoeFainted then
							self._uiController:MarkFoeFainted(i)
						end
						break
					end
				end
			end
		end
		local pd = nil
		pcall(function() pd = ClientData:Get() end)
		local playerParty = (pd and pd.Party) or {}
		self._uiController:RefreshCreatureAmount(self._battleSystem._battleInfo.Type, playerParty, self._battleSystem._battleInfo.TrainerParty)
	end
	
	-- Play faint animation
	local model = isPlayer 
		and self._sceneManager:GetPlayerCreature() 
		or self._sceneManager:GetFoeCreature()
	
	print("[StepProcessor] Faint - Model found:", model and model.Name or "nil", "IsPlayer:", isPlayer)
	
	if model then
		-- Store faint animation data for when the message is displayed
		print("[StepProcessor] Storing faint animation data - IsPlayer:", isPlayer)
		
		-- Track whether the faint message has been displayed and animation has completed
		local faintMessageDisplayed = false
		local animationCompleted = false
		
		local function tryCallOnComplete()
			-- Only call onComplete after both message is displayed AND animation completes
			if faintMessageDisplayed and animationCompleted then
				local wasWaitingForFoeFaint = self._battleSystem and self._battleSystem._waitingForFoeFaintAnim
				
				-- Notify battle system faint animation finished (to resume enemy steps)
				-- Only for foe faints - this will handle the deferred enemy steps
				if (not isPlayer) and wasWaitingForFoeFaint then
					if self._battleSystem and self._battleSystem.OnFaintAnimationComplete then
						self._battleSystem:OnFaintAnimationComplete(isPlayer)
					end
				end
				
				-- Only call onComplete for player faints or when not deferring enemy steps
				-- For foe faints with deferred steps, OnFaintAnimationComplete handles continuation
				-- This ensures XP steps only process after the full faint sequence: message -> animation
				if isPlayer or not wasWaitingForFoeFaint then
					if onComplete then onComplete() end
				end
			end
		end
		
		-- Store the faint animation callback in the message queue immediately
		-- The message queue will trigger the animation when the faint message starts sliding out
		-- CRITICAL FIX: We set this up immediately so it's ready when the message slides out
		if self._messageQueue then
			-- CRITICAL FIX: Wait for the faint message to finish displaying BEFORE allowing subsequent steps
			-- This ensures "X Fainted!" message appears and completes before XP messages are processed
			-- Use the new callback that fires when faint message finishes displaying (after typewriter + wait)
			self._messageQueue:SetFaintMessageDisplayedCallback(function()
				print("[StepProcessor] Faint message finished displaying - can now process XP steps")
				faintMessageDisplayed = true
				tryCallOnComplete()
			end)
			
			self._messageQueue:SetFaintAnimationCallback(function()
				print("[FAINT][StepProcessor] animation callback for:", step.Creature)
				print("[StepProcessor] Faint message sliding out - starting animation")
				
				-- Ensure camera is reset to a neutral/default before subsequent send-out
				if self._battleSystem and self._battleSystem._cameraController then
					self._battleSystem._cameraController:SetPosition("Default", 1, true)
				end
				
				-- Start hologram effect when faint message appears
				self._combatEffects:PlayFaintAnimation(model, isPlayer, function()
					print("[StepProcessor] Faint animation callback - IsPlayer:", isPlayer)
					print("[NewTestLog] Faint: animation-complete creature=", step.Creature, "isPlayer=", isPlayer)
					
					-- Slide UI out AFTER faint animation finishes so the HP tween to 0 can be seen
					if self._uiController then
						-- Use a small delay to ensure the HP tween (if any) has time to finish visually
						task.delay(0.05, function()
							self._uiController:SlideUIOut(not not isPlayer)
						end)
					end

					-- Trigger forced switch if player fainted (only if battle isn't ending)
					if isPlayer then
						-- Check if battle is ending before showing switch menu
						local battleEnding = self._battleSystem and self._battleSystem._pendingBattleOver
						
					-- Also check if this is the last creature by checking if there are any alive creatures
					local hasAliveCreatures = false
					local pd = nil
					pcall(function()
						pd = ClientData:Get()
					end)
					local party = pd and pd.Party or nil
					if party then
						for _, creature in ipairs(party) do
							local hp = (creature and ((creature.Stats and creature.Stats.HP) or creature.CurrentHP)) or 0
							if hp and hp > 0 then
								hasAliveCreatures = true
								break
							end
						end
					end
						
						if not battleEnding and hasAliveCreatures then
							self:_triggerForcedSwitch()
						else
							print("[StepProcessor] Player fainted but battle is ending or no alive creatures - not showing switch menu")
						end
					end
					
					-- Mark animation as completed and try to call onComplete
					animationCompleted = true
					tryCallOnComplete()
				end)
			end)
		end
	else
        -- No model; do nothing extra. Server will drive subsequent steps/events.
		-- Still wait for faint message to finish displaying before calling onComplete
		if self._messageQueue then
			self._messageQueue:SetFaintMessageDisplayedCallback(function()
				print("[StepProcessor] Faint message finished displaying (no model) - can now process XP steps")
				if onComplete then onComplete() end
			end)
		else
			if onComplete then
				onComplete()
			end
		end
	end
end

--[[
	Internal: Triggers forced switch after player faints
]]
function StepProcessor:_triggerForcedSwitch()
	print("[StepProcessor] Triggering forced switch sequence")
	
	-- Wait a moment for the faint animation to complete
	task.wait(0.5)
	
	-- Set forced switch mode on battle state BEFORE opening party menu
	-- This prevents BattleOptions from appearing during forced switch
	if self._battleSystem and self._battleSystem._battleState then
		if self._battleSystem._battleState.SetSwitchMode then
			self._battleSystem._battleState:SetSwitchMode("Forced")
			print("[StepProcessor] Set switch mode to Forced")
		end
	end
	
	-- Hide and disable battle options immediately to prevent them from showing
	if self._battleSystem and self._battleSystem._optionsManager then
		self._battleSystem._optionsManager:SetInteractionEnabled(false)
		self._battleSystem._optionsManager:HideAll()
		print("[StepProcessor] Hidden and disabled battle options for forced switch")
	end
	
	-- Ensure actions are unlocked so the player can select a new creature
	if self._battleSystem and self._battleSystem._actionHandler then
		self._battleSystem._actionHandler:Unlock()
	end
	
	-- Open party menu for forced switch
	if self._battleSystem and self._battleSystem._partyIntegration then
		print("[StepProcessor] Opening party menu for forced switch")
		self._battleSystem._partyIntegration:OpenForForcedSwitch()
	else
		warn("[StepProcessor] No party integration available for forced switch")
	end
end

--[[
	Internal: Process switch step
]]
function StepProcessor:_processSwitch(step: any, isPlayer: boolean, onComplete: StepCallback?)
	print("[StepProcessor] Processing switch step - Action:", step.Action, "Creature:", step.Creature, "IsPlayer:", isPlayer)
	
	if step.Action == "Recall" then
		self:_processRecall(step, isPlayer, onComplete)
	elseif step.Action == "SendOut" then
		self:_processSendOut(step, isPlayer, onComplete)
	else
		-- Fallback for legacy format or unknown action
		if step.Message then
			self._messageQueue:Enqueue(step.Message)
		end
		
		if onComplete then
			onComplete()
		end
	end
end

--[[
	Internal: Process switch preview (ask player if they want to switch)
	@param step The switch preview step containing trainer and next creature info
	@param onComplete Callback to invoke when processing completes
	
	IMPORTANT: This step must BLOCK until the user makes their Yes/No choice.
	The next step (SendOut) should only happen after the choice is made.
]]
function StepProcessor:_processSwitchPreview(step: any, onComplete: StepCallback?)
	print("[StepProcessor] Processing switch preview - TrainerName:", step.TrainerName, "NextCreature:", step.NextCreature)
	print("[StepProcessor] _showChoiceUI callback set:", self._showChoiceUI ~= nil)
	
	-- Generate and display the preview message
	local trainerName = step.TrainerName or "The opponent"
	local nextCreature = step.NextCreature or "another creature"
	local message = string.format("%s is about to send in %s. Switch your creature?", trainerName, nextCreature)
	
	-- CRITICAL: Wait for any existing messages to drain before setting persistent
	-- This ensures the persistent flag only applies to OUR message
	if self._messageQueue:IsProcessing() or self._messageQueue:GetLength() > 0 then
		print("[StepProcessor] Waiting for existing messages to drain before switch preview")
		self._messageQueue:WaitForDrain()
	end
	
	-- Set message to be persistent (won't auto-drain) - AFTER queue is empty
	self._messageQueue:SetPersistent(true)
	print("[StepProcessor] Set persistent flag to true")
	
	-- Display the message
	self._messageQueue:Enqueue(message)
	print("[StepProcessor] Enqueued persistent switch preview message")
	
	-- Wait for message queue to finish typing (synchronous wait)
	-- This ensures the message is fully displayed before showing buttons
	self._messageQueue:WaitForDrain()
	print("[StepProcessor] Message finished typing - now showing Choice UI")
	
	-- Show Choice UI via BattleSystem callback
	-- The callback will invoke onComplete when user makes their choice
	-- This function must NOT return until onComplete is called
	if self._showChoiceUI then
		-- _showChoiceUI is expected to call onComplete when user makes choice
		-- We don't return here - the callback chain handles continuation
		print("[StepProcessor] Calling _showChoiceUI to display Yes/No buttons")
		self._showChoiceUI(onComplete)
		print("[StepProcessor] _showChoiceUI returned - waiting for user choice")
	else
		warn("[StepProcessor] _showChoiceUI callback not set - this will break the flow!")
		-- Clear persistent message and proceed
		self._messageQueue:ClearPersistent()
		if onComplete then
			onComplete()
		end
	end
	-- NOTE: Do NOT call onComplete here! It's called by _showChoiceUI when user makes choice
end

--[[
	Internal: Process recall step (creature going back to ball)
]]
function StepProcessor:_processRecall(step: any, isPlayer: boolean, onComplete: StepCallback?)
	print("[StepProcessor] Processing recall - Creature:", step.Creature, "IsPlayer:", isPlayer)
	
	-- Generate recall message
	local message = MessageGenerator.Recall(step.Creature)
	if message then
		self._messageQueue:Enqueue(message)
	end
	
	-- Slide out You UI when player creature is recalled
	if isPlayer and self._uiController then
		self._uiController:SlideUIOut(true) -- true = player UI
		print("[StepProcessor] Sliding out You UI for recall")
	end
	
	-- Play recall animation and destroy model
	local model = isPlayer 
		and self._sceneManager:GetPlayerCreature() 
		or self._sceneManager:GetFoeCreature()
	
	if model then
		-- Fade out ice cube if creature is frozen
		if self._combatEffects then
			self._combatEffects:FadeOutIceCube(model)
		end
		
		-- Play recall animation using CombatEffects
		if self._combatEffects then
			self._combatEffects:PlayRecallAnimation(model, function()
				-- Destroy model after recall animation
				if model and model.Parent then
					model:Destroy()
					print("[StepProcessor] Destroyed recalled creature model:", model.Name)
				end
				
				-- Refresh counts after recall (active will change on send-out next)
				local pd = nil
				pcall(function() pd = ClientData:Get() end)
				local playerParty = (pd and pd.Party) or {}
				if self._uiController and self._battleSystem and self._battleSystem._battleInfo then
					self._uiController:RefreshCreatureAmount(self._battleSystem._battleInfo.Type, playerParty, self._battleSystem._battleInfo.TrainerParty)
				end
				if onComplete then
					onComplete()
				end
			end)
		else
			-- No combat effects, destroy immediately
			if model and model.Parent then
				model:Destroy()
				print("[StepProcessor] Destroyed recalled creature model (no animation):", model.Name)
			end
			
			if onComplete then
				onComplete()
			end
		end
	else
		print("[StepProcessor] No model found for recall")
		if onComplete then
			onComplete()
		end
	end
end

--[[
	Internal: Process send out step (new creature coming out)
]]
function StepProcessor:_processSendOut(step: any, isPlayer: boolean, onComplete: StepCallback?)
	print("[StepProcessor] Processing send out - Creature:", step.Creature, "IsPlayer:", isPlayer)
	
	-- Generate send out message with proper side (player vs foe)
	local message = MessageGenerator.SendOut(step.Creature, step.Variant, { 
		isPlayer = isPlayer,
		trainerName = step.TrainerName
	})
	
	-- Show send out message immediately for all creatures (including player)
	if message then
		print("[StepProcessor] Showing Go message immediately:", message)
		self._messageQueue:Enqueue(message)
	end
	
    -- Get creature data from step if provided (authoritative), otherwise from battle state
    local creatureData = step and step.CreatureData
    
    -- Debug logging to track creature data source
    if creatureData then
        print("[StepProcessor] Using CreatureData from step - Name:", creatureData.Name or creatureData.Nickname or "?", 
              "Stats.HP:", creatureData.Stats and creatureData.Stats.HP or "nil",
              "MaxStats.HP:", creatureData.MaxStats and creatureData.MaxStats.HP or "nil")
    else
        print("[StepProcessor] WARNING: step.CreatureData is nil, falling back to battle state")
        creatureData = isPlayer and self._battleState.PlayerCreature or self._battleState.FoeCreature
        if creatureData then
            print("[StepProcessor] Fallback creature - Name:", creatureData.Name or creatureData.Nickname or "?",
                  "Stats.HP:", creatureData.Stats and creatureData.Stats.HP or "nil",
                  "MaxStats.HP:", creatureData.MaxStats and creatureData.MaxStats.HP or "nil")
        end
    end
	
	if not creatureData then
		print("[StepProcessor] No creature data found for send out")
		if onComplete then
			onComplete()
		end
		return
	end
	
	-- Get spawn points
	local playerSpawn, foeSpawn = self._sceneManager:GetSpawnPoints()
	local spawnPoint = isPlayer and playerSpawn or foeSpawn
	
	if not spawnPoint then
		print("[StepProcessor] No spawn point found for", isPlayer and "player" or "foe")
		if onComplete then
			onComplete()
		end
		return
	end
	
	-- Determine if we should use hologram effect
	-- Use hologram for:
	-- 1. Player's creature always (sent out from capture device)
	-- 2. Trainer's creatures (sent out by trainer)
	-- 3. PvP opponent's creatures (sent out by opponent)
	-- Only skip hologram for wild creature initial spawns
    local useHologram = isPlayer or self._battleState.Type == "Trainer" or self._battleState.Type == "PvP"
	print("[StepProcessor] SendOut - useHologram:", useHologram, "isPlayer:", isPlayer, "BattleType:", self._battleState.Type)
	
    -- Spawn new creature model
        print("[NewTestLog] SendOut: spawning model name=", (creatureData and (creatureData.Nickname or creatureData.Name)) or "?", "isPlayer=", isPlayer, "useHologram=", useHologram)
        self._sceneManager:SpawnCreature(creatureData, spawnPoint, isPlayer, useHologram, function()
        print("[StepProcessor] Creature spawned successfully - IsPlayer:", isPlayer)
        local spawned = isPlayer and self._sceneManager:GetPlayerCreature() or self._sceneManager:GetFoeCreature()
        print("[NewTestLog] SendOut: spawn-complete name=", (creatureData and (creatureData.Nickname or creatureData.Name)) or "?", "isPlayer=", isPlayer, "model=", spawned and spawned.Name or "nil")
		
		-- Check if creature is frozen and reapply ice cube (for trainer battles where creature comes back)
		local spawnedModel = isPlayer and self._sceneManager:GetPlayerCreature() or self._sceneManager:GetFoeCreature()
		if spawnedModel and creatureData and creatureData.Status and creatureData.Status.Type == "FRZ" then
			print("[StepProcessor] Creature is frozen - reapplying ice cube")
			if self._combatEffects and self._combatEffects.PlayStatusEffect then
				-- Use a small delay to ensure model is fully spawned
				task.delay(0.1, function()
					if spawnedModel and spawnedModel.Parent then
						self._combatEffects:PlayStatusEffect(spawnedModel, "FRZ")
					end
				end)
			end
		end
		
		-- Note: Shiny burst effect is handled by BattleSceneManager for all creature spawns
		
		-- Reset camera to default position for ALL send outs (player and foe)
		if self._battleSystem and self._battleSystem._cameraController then
			print("[StepProcessor] Resetting camera to default position for send out")
			self._battleSystem._cameraController:ReturnToDefault()
		end
		
		-- If this is a player creature spawn, handle player-specific logic
		if isPlayer then
			-- Start idle animation for new creature
			local playerModel = self._sceneManager:GetPlayerCreature()
			if playerModel and self._animationController then
				self._animationController:PlayIdleAnimation(playerModel)
				print("[StepProcessor] Started idle animation for new player creature")
			end
			
			-- Update player UI with new creature data and slide in
			if self._uiController then
				-- Update UI with new creature data first
				self._uiController:UpdateCreatureUI(true, creatureData, false)
				self._uiController:UpdateLevelUI(creatureData, false)
					-- Ensure move buttons reflect the new creature's moves
					if self._battleSystem and self._battleSystem._battleUIManager then
						self._battleSystem._battleUIManager:UpdateMoveButtons(creatureData)
					end
				print("[StepProcessor] Updated player UI with new creature data")
				
				-- Slide in You UI when new player creature is sent out
				self._uiController:SlideYouUIIn(function()
					print("[StepProcessor] You UI slide-in completed for new creature")
				end)
			end
			
			-- Note: StartNextTurn will be called by the normal turn flow after enemy actions complete
			print("[StepProcessor] Player creature spawned - turn flow will handle StartNextTurn")
			-- Refresh player's CreatureAmount after switch
			if self._battleSystem and self._battleSystem._battleInfo then
				local pd = nil
				pcall(function() pd = ClientData:Get() end)
				local playerParty = (pd and pd.Party) or {}
				self._uiController:RefreshCreatureAmount(self._battleSystem._battleInfo.Type, playerParty, self._battleSystem._battleInfo.TrainerParty)
			end
		end
		
        -- Handle foe creature post-spawn
        if (not isPlayer) then
            -- Play agent send-out animation if this is a trainer battle
            if self._battleState.Type == "Trainer" then
                AgentAnimations:PlaySendOutAnimation()
            end
            
            -- Start idle animation for new foe creature
            local foeModel = self._sceneManager:GetFoeCreature()
            if foeModel and self._animationController then
                self._animationController:PlayIdleAnimation(foeModel)
                print("[StepProcessor] Started idle animation for new foe creature")
            end
            
            -- Update battle state with new foe creature
            if self._battleState and creatureData then
                self._battleState:UpdateFoeCreature(creatureData)
                print("[StepProcessor] Updated battle state with new foe creature:", creatureData.Name or creatureData.Nickname)
            end
            
            -- Update UI - update creature data BEFORE sliding in so HP shows correctly
            if self._uiController then
                -- Debug: log HP values being sent to UI
                print("[StepProcessor] Updating foe UI with HP:", 
                      creatureData.Stats and creatureData.Stats.HP or "nil", "/",
                      creatureData.MaxStats and creatureData.MaxStats.HP or "nil")
                
                -- Update creature UI first (while off-screen) so the new creature's HP is correct
                self._uiController:UpdateCreatureUI(false, creatureData, false)
                
                -- Then slide the UI in with the correct data already displayed
                if self._uiController.SlideFoeUIIn then
                    self._uiController:SlideFoeUIIn()
                end
            end

            -- Refresh CreatureAmount after foe send-out (trainer battles show foe count)
            if self._battleSystem and self._battleSystem._battleInfo then
                local pd = nil
                pcall(function() pd = ClientData:Get() end)
                local playerParty = (pd and pd.Party) or {}
                self._uiController:RefreshCreatureAmount(self._battleSystem._battleInfo.Type, playerParty, self._battleSystem._battleInfo.TrainerParty)
            end
        end

        if onComplete then
            onComplete()
        end
	end)
end

--[[
	Internal: Process miss step
]]
function StepProcessor:_processMiss(step: any, isPlayer: boolean, onComplete: StepCallback?)
	if step.Message then
		self._messageQueue:Enqueue(step.Message)
	end
	
	-- Play miss effect
	local model = isPlayer 
		and self._sceneManager:GetFoeCreature() 
		or self._sceneManager:GetPlayerCreature()
	
	if model then
		self._combatEffects:PlayMissEffect(model)
		if self._combatEffects and self._combatEffects.CreateFloatingText then
			self._combatEffects:CreateFloatingText(model, "MISS", Color3.fromRGB(230, 230, 230))
		end
	end
	
	-- Block until the miss message fully drains to avoid overlapping the opponent action
	if self._messageQueue and self._messageQueue.WaitForDrain then
		self._messageQueue:WaitForDrain()
	end
	if onComplete then
		onComplete()
	end
end

--[[
	Internal: Process critical hit step
]]
function StepProcessor:_processCrit(step: any, isPlayer: boolean, onComplete: StepCallback?)
	if step.Message then
		self._messageQueue:Enqueue(step.Message)
	end
	
	-- Play crit effect
	local model = isPlayer 
		and self._sceneManager:GetFoeCreature() 
		or self._sceneManager:GetPlayerCreature()
	
	if model then
		self._combatEffects:PlayCriticalHitEffect(model)
		if self._combatEffects and self._combatEffects.CreateFloatingText then
			self._combatEffects:CreateFloatingText(model, "CRIT", Color3.fromRGB(255, 214, 74))
		end
	end
	
	if onComplete then
		onComplete()
	end
end

--[[
	Internal: Process status step
]]
function StepProcessor:_processStatus(step: any, isPlayer: boolean, onComplete: StepCallback?)
	-- Debug: Log the entire step to see what we're receiving
	print("[StepProcessor] _processStatus - Full step:", step)
	print("[StepProcessor] step.Status:", step.Status, "type:", type(step.Status))
	print("[StepProcessor] step.IsPlayer:", step.IsPlayer, "isPlayer param:", isPlayer)
	
	-- Determine which creature was affected by checking step.IsPlayer (which indicates the affected creature)
	-- step.IsPlayer = true means player's creature was affected, false means foe's creature was affected
	local affectedIsPlayer = (type(step.IsPlayer) == "boolean") and step.IsPlayer or isPlayer
	
	-- Generate proper status message using BattleMessageGenerator
	local creatureName = nil
	local creatureData = nil
	
	if affectedIsPlayer then
		creatureData = self._battleState and self._battleState.PlayerCreature
		if creatureData then
			creatureName = creatureData.Nickname or creatureData.Name or "Your creature"
		end
	else
		creatureData = self._battleState and self._battleState.FoeCreature
		if creatureData then
			creatureName = creatureData.Nickname or creatureData.Name or "Foe"
		end
	end
	
	-- Extract status type from step - ensure it's a valid status code
	local statusType = nil
	if step.Status then
		local statusValue = step.Status
		-- Check if it's a valid status code (string like "BRN", "PSN", etc.)
		if type(statusValue) == "string" then
			local upperValue = statusValue:upper()
			if upperValue == "BRN" or upperValue == "PAR" or upperValue == "PSN" or upperValue == "TOX" or upperValue == "SLP" or upperValue == "FRZ" then
				statusType = upperValue
			else
				warn("[StepProcessor] Invalid status string:", statusValue)
			end
		elseif type(statusValue) == "number" then
			-- If it's a number (like 100), this is wrong - try to extract from message or creature data
			warn("[StepProcessor] Status step has numeric value:", statusValue, "- this should be a status code!")
			
			-- Try to extract status from the server message if available
			if step.Message and type(step.Message) == "string" then
				local msg = step.Message:lower()
				if string.find(msg, "burned") then
					statusType = "BRN"
				elseif string.find(msg, "paralyzed") then
					statusType = "PAR"
				elseif string.find(msg, "badly poisoned") then
					statusType = "TOX"
				elseif string.find(msg, "poisoned") then
					statusType = "PSN"
				elseif string.find(msg, "asleep") or string.find(msg, "sleep") then
					statusType = "SLP"
				elseif string.find(msg, "frozen") then
					statusType = "FRZ"
				end
				if statusType then
					print("[StepProcessor] Extracted status from message:", statusType)
				end
			end
			
			-- Fallback: try to get status from creature data if available
			if not statusType and creatureData and creatureData.Status and creatureData.Status.Type then
				local creatureStatus = creatureData.Status.Type
				if type(creatureStatus) == "string" then
					local upperStatus = creatureStatus:upper()
					if upperStatus == "BRN" or upperStatus == "PAR" or upperStatus == "PSN" or upperStatus == "TOX" or upperStatus == "SLP" or upperStatus == "FRZ" then
						statusType = upperStatus
						print("[StepProcessor] Using status from creature data:", statusType)
					end
				end
			end
		end
	end
	
	-- Get model and status for effect callback
	local model = affectedIsPlayer 
		and self._sceneManager:GetPlayerCreature() 
		or self._sceneManager:GetFoeCreature()
	
	-- Use statusType if available, otherwise fall back to step.Status
	local statusForEffect = statusType or step.Status
	
	-- Set status effect callback to play when message is displayed
	if model and statusForEffect and self._messageQueue and self._messageQueue.SetStatusEffectCallback then
		self._messageQueue:SetStatusEffectCallback(function()
			print("[StepProcessor] Status message displayed - playing status effect for:", statusForEffect)
			self._combatEffects:PlayStatusEffect(model, statusForEffect)
		end)
	end
	
	-- Generate message - prioritize server-provided message to avoid duplicates
	if step.Message then
		-- Use server message (prevents duplicate messages when server already sent a Message step)
		self._messageQueue:Enqueue(step.Message)
		print("[StepProcessor] Using server message for status:", step.Message)
		
		-- Try to extract status from message for UI update if not already set
		if not statusType and type(step.Message) == "string" then
			local msg = step.Message:lower()
			if string.find(msg, "burned") then
				statusType = "BRN"
			elseif string.find(msg, "paralyzed") then
				statusType = "PAR"
			elseif string.find(msg, "badly poisoned") then
				statusType = "TOX"
			elseif string.find(msg, "poisoned") then
				statusType = "PSN"
			elseif string.find(msg, "asleep") or string.find(msg, "sleep") then
				statusType = "SLP"
			elseif string.find(msg, "frozen") then
				statusType = "FRZ"
			end
			if statusType then
				print("[StepProcessor] Extracted status from server message:", statusType)
			end
		end
	elseif statusType and creatureName then
		-- No server message provided, generate one from status type
		local statusMessage = MessageGenerator.StatusApplied(creatureName, statusType)
		self._messageQueue:Enqueue(statusMessage)
		print("[StepProcessor] Status message generated:", statusMessage, "for status:", statusType)
	else
		warn("[StepProcessor] No status message available! step.Status:", step.Status, "step.Message:", step.Message)
	end
	
	-- Wait for the status message to be displayed and drained before continuing
	if self._messageQueue and self._messageQueue.WaitForDrain then
		self._messageQueue:WaitForDrain()
	end
	
	-- Wait for the status message to be displayed before updating UI
	if statusType and creatureData then
		-- Validate statusType is a valid status code before using it
		local validStatusCodes = {BRN = true, PAR = true, PSN = true, TOX = true, SLP = true, FRZ = true}
		if not validStatusCodes[statusType] then
			warn("[StepProcessor] Invalid status type:", statusType, "- skipping UI update")
			if onComplete then
				onComplete()
			end
			return
		end
		
		-- Update the creature data with the new status (ensure it's a string)
		if not creatureData.Status then
			creatureData.Status = {}
		end
		creatureData.Status.Type = statusType
		
		print("[StepProcessor] Updating status UI after message - Status:", statusType, "AffectedIsPlayer:", affectedIsPlayer, "Creature:", creatureName)
		
		-- Update battle state with status
		if affectedIsPlayer then
			self._battleState:UpdatePlayerCreature(creatureData, self._battleState.PlayerCreatureIndex or 1)
		else
			self._battleState:UpdateFoeCreature(creatureData)
		end
		
		-- Update UI display (this will show the status after message is displayed)
		if self._uiController then
			self._uiController:UpdateStatusDisplay(affectedIsPlayer, creatureData)
			-- Also call UpdateCreatureUI to ensure everything is refreshed
			self._uiController:UpdateCreatureUI(affectedIsPlayer, creatureData, false)
		end
	end
	
	-- Check if this is a thaw message and set up thaw callback
	if step.Message and type(step.Message) == "string" then
		local msgLower = step.Message:lower()
		if string.find(msgLower, "thawed out") then
			local model = affectedIsPlayer 
				and self._sceneManager:GetPlayerCreature() 
				or self._sceneManager:GetFoeCreature()
			
			if model and self._messageQueue and self._messageQueue.SetThawCallback then
				self._messageQueue:SetThawCallback(function()
					print("[StepProcessor] Thaw message displayed - thawing creature")
					if self._combatEffects and self._combatEffects.ThawCreature then
						self._combatEffects:ThawCreature(model)
					end
				end)
			end
		end
	end
	
	-- Complete after message has drained
	if onComplete then
		onComplete()
	end
end

--[[
	Internal: Process multi-hit summary step
	Displays "Hit X time(s)!" message after all hits of a multi-hit move are processed
]]
function StepProcessor:_processMultiHitSummary(step: any, isPlayer: boolean, onComplete: StepCallback?)
	local hitCount = step.HitCount or 1
	local moveName = step.MoveName or "The attack"
	
	-- Generate hit count message (Pokemon style: "Hit 3 time(s)!")
	local hitMessage
	if hitCount == 1 then
		hitMessage = "Hit 1 time!"
	else
		hitMessage = string.format("Hit %d times!", hitCount)
	end
	
	print("[StepProcessor] Multi-hit summary -", moveName, "hit", hitCount, "time(s)")
	
	-- Enqueue the hit count message
	self._messageQueue:Enqueue(hitMessage)
	
	-- Wait for message to drain before continuing
	if self._messageQueue and self._messageQueue.WaitForDrain then
		self._messageQueue:WaitForDrain()
	end
	
	if onComplete then
		onComplete()
	end
end

--[[
	Internal: Process stat stage step
]]
function StepProcessor:_processStatStage(step: any, isPlayer: boolean, onComplete: StepCallback?)
	-- Use IsPlayer from step if available (for stat changes on opponent)
	local targetIsPlayer = (type(step.IsPlayer) == "boolean") and step.IsPlayer or isPlayer
	
	-- Play stat change effect
	local model = targetIsPlayer 
		and self._sceneManager:GetPlayerCreature() 
		or self._sceneManager:GetFoeCreature()
	
	if model and step.Stat and step.Stages then
		self._combatEffects:PlayStatChangeEffect(model, step.Stat, step.Stages)
	end
	
	-- Enqueue message after starting visual effect
	if step.Message then
		self._messageQueue:Enqueue(step.Message)
	end
	
	-- Wait for the message to be displayed before completing
	-- This ensures multiple stat changes show one at a time
	if self._messageQueue and self._messageQueue.WaitForDrain then
		task.spawn(function()
			self._messageQueue:WaitForDrain()
			-- Small delay after message drains for visual clarity
			task.wait(0.3)
			if onComplete then
				onComplete()
			end
		end)
	else
		-- Fallback with delay if WaitForDrain not available
		if onComplete then
			task.delay(1.0, onComplete)
		end
	end
end

--[[
	Internal: Process ability activation step
	Shows ability notification and enqueues ability-related messages
]]
function StepProcessor:_processAbilityActivation(step: any, isPlayer: boolean, onComplete: StepCallback?)
	local abilityName = step.Ability or "Unknown Ability"
	local creatureName = step.Creature or "Creature"
	local isFriendly = (type(step.IsPlayer) == "boolean") and step.IsPlayer or isPlayer
	
	print("[StepProcessor] Processing ability activation -", abilityName, "for", creatureName, "isFriendly:", isFriendly)
	
	-- Show ability notification
	if self._uiController and self._uiController.ShowAbilityNotification then
		self._uiController:ShowAbilityNotification(abilityName, creatureName, isFriendly)
	end
	
	-- Enqueue the ability message
	if step.Message then
		self._messageQueue:Enqueue(step.Message)
	end
	
	-- Play stat change effect if there's a stat change
	if step.StatChange and step.StatChange.Stat and step.StatChange.Stages then
		local model = isFriendly 
			and self._sceneManager:GetPlayerCreature() 
			or self._sceneManager:GetFoeCreature()
		
		if model and self._combatEffects then
			self._combatEffects:PlayStatChangeEffect(model, step.StatChange.Stat, step.StatChange.Stages)
		end
	end
	
	-- Wait for the message to drain, then hide the notification
	if self._messageQueue and self._messageQueue.WaitForDrain then
		task.spawn(function()
			self._messageQueue:WaitForDrain()
			
			-- Hide the ability notification after message displays
			if self._uiController and self._uiController.HideAbilityNotification then
				self._uiController:HideAbilityNotification(function()
					if onComplete then onComplete() end
				end)
			else
				if onComplete then onComplete() end
			end
		end)
	else
		-- Fallback with delay
		task.delay(1.5, function()
			if self._uiController and self._uiController.HideAbilityNotification then
				self._uiController:HideAbilityNotification(function()
					if onComplete then onComplete() end
				end)
			else
				if onComplete then onComplete() end
			end
		end)
	end
end

--[[
	Internal: Process entry hazard set step
	Shows message for when hazards are placed on the field
]]
function StepProcessor:_processEntryHazard(step: any, isPlayer: boolean, onComplete: StepCallback?)
	print("[StepProcessor] Processing entry hazard set - HazardType:", step.HazardType, "IsPlayer:", isPlayer)
	
	-- Generate and enqueue the hazard set message
	if step.Message then
		self._messageQueue:Enqueue(step.Message)
	elseif step.HazardType then
		local message = MessageGenerator.HazardSet(step.HazardType, isPlayer, step.Layers)
		self._messageQueue:Enqueue(message)
	end
	
	-- Play visual effects for hazard placement
	if step.HazardType == "Spikes" then
		local battleScene = self._sceneManager and self._sceneManager:GetScene()
		if battleScene then
			-- Determine which side the spikes are on (opposite of who set them)
			-- If player set spikes, they appear on foe side (isPlayer=false)
			-- If foe set spikes, they appear on player side (isPlayer=true)
			local spikesOnPlayerSide = not isPlayer
			
			-- Get creature model that set the spikes for throw origin
			local creatureModel = isPlayer 
				and self._sceneManager:GetPlayerCreature() 
				or self._sceneManager:GetFoeCreature()
			
			-- Get layers from step (defaults to 1 if not specified)
			local layers = step.Layers or 1
			
			-- Play spikes effect
			if self._combatEffects and self._combatEffects.PlaySpikesEffect then
				self._combatEffects:PlaySpikesEffect(battleScene, spikesOnPlayerSide, layers, creatureModel)
			end
		end
	end
	
	-- Wait for message to drain before continuing (ensures "scattered around the battlefield" message finishes)
	-- This prevents the opponent from attacking until the message is done
	-- Use synchronous WaitForDrain to block until message queue is empty
	if self._messageQueue and self._messageQueue.WaitForDrain then
		self._messageQueue:WaitForDrain()
	end
	
	if onComplete then
		onComplete()
	end
end

--[[
	Internal: Process hazard damage step
	Shows message and applies damage when creature switches into hazards
]]
function StepProcessor:_processHazardDamage(step: any, isPlayer: boolean, onComplete: StepCallback?)
	print("[StepProcessor] Processing hazard damage - HazardType:", step.HazardType, "Creature:", step.Creature, "IsPlayer:", isPlayer)
	
	-- Delay before showing hazard damage (wait for spawn animation to complete)
	task.wait(0.45)
	
	-- Generate and enqueue the hazard damage message
	if step.Message then
		self._messageQueue:Enqueue(step.Message)
	elseif step.HazardType and step.Creature then
		local message = MessageGenerator.HazardDamage(step.Creature, step.HazardType, step.Status, step.Absorbed)
		self._messageQueue:Enqueue(message)
	end
	
	-- Get the affected creature model
	local model = isPlayer 
		and self._sceneManager:GetPlayerCreature() 
		or self._sceneManager:GetFoeCreature()
	
	-- Update HP bar if damage was dealt
	if step.Damage and step.NewHP ~= nil then
		-- Get MAX HP from the step (authoritative from server)
		local maxHP = step.MaxHP
		local newHP = math.max(0, step.NewHP)
		
		-- Get current creature from battle state
		local creature = isPlayer and self._battleState.PlayerCreature or self._battleState.FoeCreature
		if creature then
			-- Create updated creature with correct HP values
			local updatedCreature = table.clone(creature)
			updatedCreature.Stats = table.clone(creature.Stats or {})
			updatedCreature.Stats.HP = newHP
			
			if type(maxHP) == "number" then
				updatedCreature.MaxStats = table.clone(creature.MaxStats or {})
				updatedCreature.MaxStats.HP = maxHP
			end
			
			-- Update battle state with authoritative HP
			if isPlayer then
				self._battleState:UpdatePlayerCreature(updatedCreature, self._battleState.PlayerCreatureIndex or 1)
			else
				self._battleState:UpdateFoeCreature(updatedCreature)
			end
			
			-- Force update UI with tween (Pokemon-style: HP drops as message appears)
			-- Use the creature with updated HP values
			self._uiController:UpdateCreatureUI(isPlayer, updatedCreature, true)
			
			-- Play damage flash effect for hazard damage
			if model and self._combatEffects then
				self._combatEffects:PlayDamageFlash(model, "Normal")
			end
			
			print("[StepProcessor] Hazard damage applied - Creature:", step.Creature, "Damage:", step.Damage, "NewHP:", newHP, "MaxHP:", maxHP)
		end
	end
	
	-- Handle Toxic Spikes status application
	if step.Status and step.HazardType == "ToxicSpikes" then
		local creature = isPlayer and self._battleState.PlayerCreature or self._battleState.FoeCreature
		if creature then
			-- Update creature status in battle state
			creature.Status = creature.Status or {}
			creature.Status.Type = step.Status
			
			-- Update status display
			if self._uiController then
				self._uiController:UpdateStatusDisplay(isPlayer, creature)
			end
			
			-- Play poison status effect
			if model and self._combatEffects then
				self._combatEffects:PlayStatusEffect(model, step.Status)
			end
			
			print("[StepProcessor] Toxic Spikes applied status:", step.Status, "to", step.Creature)
		end
	end
	
	-- Wait for message to drain before continuing
	if self._messageQueue and self._messageQueue.WaitForDrain then
		self._messageQueue:WaitForDrain()
	end
	
	if onComplete then
		task.delay(0.3, onComplete) -- Small delay for visual feedback
	end
end

--[[
	Cleanup all resources
]]
function StepProcessor:Cleanup()
	-- Clean up capture effects if active
	if self._captureEffects then
		self._captureEffects:Cleanup()
		self._captureEffects = nil
	end
	self._captureScanIndex = 0
end

return StepProcessor

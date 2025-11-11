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
export type GenericStep = { Type: string, [string]: any }
export type Step = MessageStep | MoveStep | DamageStep | HealStep | CaptureScanStep | WaitDrainStep | FaintStep | SwitchStep | MissStep | CritStep | StatusStep | StatStageStep | XPStep | XPSpreadStep | LevelUpStep | GenericStep

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
            end
            -- Messages should drain before continuing to preserve sequencing
            self:_processMessage(step :: MessageStep, true, onComplete)
        end,
        Move = function()
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
            -- Only fade out the cube on failure (red). Do NOT fade for successful scans.
            self:_processCaptureScan(step :: CaptureScanStep, function()
                local s = (step :: any).Success
                if s == false then
                    if self._combatEffects and self._combatEffects.FadeOutCaptureCube then
                        self._combatEffects:FadeOutCaptureCube()
                    end
                end
                if onComplete then onComplete() end
            end)
        end,
        CaptureSuccess = function()
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

-- Internal: Process capture scan step (visual glow/scan)
function StepProcessor:_processCaptureScan(step: CaptureScanStep, onComplete: StepCallback?)
    local model = self._sceneManager:GetFoeCreature()
    if model and self._combatEffects then
        self._combatEffects:PlayScanFlash(model, (step.Success == nil) and true or (step.Success == true))
    end
    -- Longer inter-scan delay for readability
    if onComplete then
        task.delay(0.8, onComplete)
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
	
	-- Play move animation
	if attackerModel and defenderModel then
        local hadPending = (self._battleState and self._battleState:GetPendingHP() ~= nil)
		-- Defer committing the pending HP snapshot until the hit marker.
		-- Do NOT update HP when the creature is sent out; only tween on hit.
		
		-- Check if move missed (no HPDelta means no damage, which indicates a miss)
		local hpDelta = (step and type(step.HPDelta) == "table") and step.HPDelta or nil
		local willMiss = (hpDelta == nil) or (isPlayer and (not hpDelta.Enemy or hpDelta.Enemy == 0)) or (not isPlayer and (not hpDelta.Player or hpDelta.Player == 0))
		
		self._combatEffects:PlayMoveAttack(
			attackerModel,
			defenderModel,
			step.MoveName or "Unknown",
			function()
				-- Commit pending HP only for non-heal moves to avoid early HP updates on heal-only moves (e.g., Perch)
				local moveName = step.Move or step.MoveName
				local def = moveName and MovesModule[moveName] or nil
				local isHealOnly = def and type(def.HealsPercent) == "number" and def.HealsPercent > 0
				if not isHealOnly then
					-- Update only the defender for this move at the hit marker
					local targetIsPlayer = (not isPlayer) == true
					self:_updateUIWithPendingHP(targetIsPlayer)
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
    -- Determine target side (damage always applies to the defender of the move)
    local targetIsPlayer = not not (not isPlayer)

    -- If server provided per-hit NewHP, apply it to the target creature now (authoritative)
    if step and type(step.NewHP) == "number" then
        local creature = targetIsPlayer and self._battleState.PlayerCreature or self._battleState.FoeCreature
        if creature and creature.Stats then
            creature.Stats.HP = math.max(0, step.NewHP)
            -- Do not tween HP here; HP UI is updated strictly at the Hit marker in _processMove
        end
    else
        -- No NewHP provided; defer entirely to the Hit marker-driven update path
    end

    -- Play damage flash
    local model = targetIsPlayer and self._sceneManager:GetPlayerCreature() or self._sceneManager:GetFoeCreature()
    if model then
        print("[StepProcessor] Damage step effectiveness:", step.Effectiveness)
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

    -- Enqueue effectiveness message when applicable
    if type(step.Effectiveness) == "string" then
        local key: string?
        if step.Effectiveness == "Super" then
            key = "SuperEffective"
        elseif step.Effectiveness == "NotVery" then
            key = "NotVeryEffective"
        elseif step.Effectiveness == "Immune" then
            key = "NoEffect"
        end
        if key then
            local msg = MessageGenerator.Effectiveness(key)
            if msg and self._messageQueue then
                self._messageQueue:Enqueue(msg)
            end
        end
    end

    if onComplete then
        task.delay(0.3, onComplete)
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
			self._uiController:UpdateHPBar(isPlayer, vis, true)
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
				self._uiController:UpdateHPBar(isPlayer, vis, true)
			else
				self._uiController:UpdateCreatureUI(isPlayer, serverCreature, true)
				self._uiController:UpdateLevelUI(serverCreature, false)
				self._uiController:UpdateHPBar(isPlayer, serverCreature, true)
			end
		end
	end
	
	-- Play heal effect
	local model = isPlayer 
		and self._sceneManager:GetPlayerCreature() 
		or self._sceneManager:GetFoeCreature()
	
	if model and step.Amount then
		self._combatEffects:PlayHealEffect(model, step.Amount)
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
		
		-- Store the faint animation callback in the message queue
		-- The message queue will trigger the animation when the faint message is displayed
        if self._messageQueue then
            self._messageQueue:SetFaintAnimationCallback(function()
                print("[FAINT][StepProcessor] animation callback for:", step.Creature)
				print("[StepProcessor] Faint message displayed - starting animation")
				
                -- Slide UI out when faint message appears (no additional client decisions)
                self._uiController:SlideUIOut(not not isPlayer)
                -- Ensure camera is reset to a neutral/default before subsequent send-out
                if self._battleSystem and self._battleSystem._cameraController then
                    self._battleSystem._cameraController:SetPosition("Default", 1, true)
                end
				
				-- Start hologram effect when faint message appears
                self._combatEffects:PlayFaintAnimation(model, isPlayer, function()
                    print("[StepProcessor] Faint animation callback - IsPlayer:", isPlayer)
                    print("[NewTestLog] Faint: animation-complete creature=", step.Creature, "isPlayer=", isPlayer)
                    
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
                    
                    -- Check if we're deferring enemy steps BEFORE calling OnFaintAnimationComplete
                    -- (which will clear the flag)
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
                    if isPlayer or not wasWaitingForFoeFaint then
                        if onComplete then onComplete() end
                    end
                end)
			end)
		end
	else
        -- No model; do nothing extra. Server will drive subsequent steps/events.
		
		if onComplete then
			onComplete()
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
]]
function StepProcessor:_processSwitchPreview(step: any, onComplete: StepCallback?)
	print("[StepProcessor] Processing switch preview - TrainerName:", step.TrainerName, "NextCreature:", step.NextCreature)
	
	-- Generate and display the preview message
	local trainerName = step.TrainerName or "The opponent"
	local nextCreature = step.NextCreature or "another creature"
	local message = string.format("%s is about to send in %s. Switch your creature?", trainerName, nextCreature)
	
	-- Set message to be persistent (won't auto-drain)
	self._messageQueue:SetPersistent(true)
	
	-- Display the message
	self._messageQueue:Enqueue(message)
	print("[StepProcessor] Enqueued persistent switch preview message")
	
	-- Wait for message to finish typing, THEN show Choice UI
	-- The message will stay on screen until a choice is made
	self._messageQueue:OnDrained(function()
		print("[StepProcessor] Message finished typing - showing Choice UI")
		
		-- Show Choice UI via BattleSystem callback
		if self._showChoiceUI then
			self._showChoiceUI(onComplete)
		else
			warn("[StepProcessor] _showChoiceUI callback not set")
			-- Clear persistent message
			self._messageQueue:ClearPersistent()
			if onComplete then
				onComplete()
			end
		end
	end)
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
    if not creatureData then
        creatureData = isPlayer and self._battleState.PlayerCreature or self._battleState.FoeCreature
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
    local useHologram = isPlayer or (self._battleState.Type == "Trainer" and not isPlayer)
	print("[StepProcessor] SendOut - useHologram:", useHologram, "isPlayer:", isPlayer, "BattleType:", self._battleState.Type)
	
    -- Spawn new creature model
        print("[NewTestLog] SendOut: spawning model name=", (creatureData and (creatureData.Nickname or creatureData.Name)) or "?", "isPlayer=", isPlayer, "useHologram=", useHologram)
        self._sceneManager:SpawnCreature(creatureData, spawnPoint, isPlayer, useHologram, function()
        print("[StepProcessor] Creature spawned successfully - IsPlayer:", isPlayer)
        local spawned = isPlayer and self._sceneManager:GetPlayerCreature() or self._sceneManager:GetFoeCreature()
        print("[NewTestLog] SendOut: spawn-complete name=", (creatureData and (creatureData.Nickname or creatureData.Name)) or "?", "isPlayer=", isPlayer, "model=", spawned and spawned.Name or "nil")
		
		-- If this is a player creature spawn, move camera for clarity
		if isPlayer then
			-- Start idle animation for new creature
			local playerModel = self._sceneManager:GetPlayerCreature()
			if playerModel and self._animationController then
				self._animationController:PlayIdleAnimation(playerModel)
				print("[StepProcessor] Started idle animation for new player creature")
			end
			
			-- Move camera to default position for clarity during switch
			if self._battleSystem and self._battleSystem._cameraController then
				print("[StepProcessor] Moving camera to default position for switch")
				self._battleSystem._cameraController:SetPosition("Default", 1, true)  -- Instant move
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
            
            -- Update UI
            if self._uiController then
                if self._uiController.SlideFoeUIIn then
                    self._uiController:SlideFoeUIIn(function()
                        self._uiController:UpdateCreatureUI(false, creatureData, false)
                    end)
                else
                    self._uiController:UpdateCreatureUI(false, creatureData, false)
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
	end
	
	if onComplete then
		onComplete()
	end
end

--[[
	Internal: Process status step
]]
function StepProcessor:_processStatus(step: any, isPlayer: boolean, onComplete: StepCallback?)
	if step.Message then
		self._messageQueue:Enqueue(step.Message)
	end
	
	-- Play status effect
	local model = isPlayer 
		and self._sceneManager:GetPlayerCreature() 
		or self._sceneManager:GetFoeCreature()
	
	if model and step.Status then
		self._combatEffects:PlayStatusEffect(model, step.Status)
	end
	
	if onComplete then
		task.delay(0.5, onComplete)
	end
end

--[[
	Internal: Process stat stage step
]]
function StepProcessor:_processStatStage(step: any, isPlayer: boolean, onComplete: StepCallback?)
	if step.Message then
		self._messageQueue:Enqueue(step.Message)
	end
	
	-- Play stat change effect
	local model = isPlayer 
		and self._sceneManager:GetPlayerCreature() 
		or self._sceneManager:GetFoeCreature()
	
	if model and step.Stat and step.Stages then
		self._combatEffects:PlayStatChangeEffect(model, step.Stat, step.Stages)
	end
	
	if onComplete then
		task.delay(0.5, onComplete)
	end
end

return StepProcessor

--!strict
--[[
	CombatEffects.lua
	Handles combat visual effects, sounds, and animations
	Provides clean interface for all battle effect playback
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CombatEffects = {}
CombatEffects.__index = CombatEffects

export type CombatEffectsType = typeof(CombatEffects.new())

--[[
	Creates a new combat effects instance
	@param animationController The animation controller reference
	@return CombatEffects
]]
function CombatEffects.new(animationController: any): any
	local self = setmetatable({}, CombatEffects)
	
	self._animationController = animationController
	self._activeCaptureCube = nil :: Model?
	self._frozenIceCubes = {} :: {[Model]: MeshPart}  -- Track ice cubes for frozen creatures
	self._iceCubeConnections = {} :: {[Model]: RBXScriptConnection}  -- Track connections for ice cube alignment
	
	-- Cache common asset folders for effects
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	self._assets = assets
	self._effects = assets and assets:FindFirstChild("Effects")
	
	-- Try to find Audio in ReplicatedStorage (either in Assets or directly)
	local audio = ReplicatedStorage:FindFirstChild("Audio")
	if not audio then
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		if assets then
			audio = assets:FindFirstChild("Audio")
		end
	end
	
	self._audio = audio
	self._sfx = audio and audio:FindFirstChild("SFX")
	
	return self
end

-- Internal: find a reasonable anchor part for effects on a model
function CombatEffects:_getAnchorPart(model: Model): BasePart?
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	local primary = model.PrimaryPart
	if primary and primary:IsA("BasePart") then
		return primary
	end
	-- Fallback: any BasePart
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			return d
		end
	end
	return nil
end

-- Internal: subtle highlight pulse (code-only fallback for VFX)
function CombatEffects:_pulseHighlight(model: Model, fillColor: Color3, outlineColor: Color3?, duration: number?)
	local dur = (typeof(duration) == "number" and duration) or 0.35
	if dur <= 0 then dur = 0.35 end
	if not model or not model.Parent then return end

	-- Reuse existing highlight if present, otherwise create a temporary one
	local highlight = Instance.new("Highlight")
	highlight.Name = "CombatHighlightPulse"
	highlight.Adornee = model
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = fillColor
	highlight.OutlineColor = outlineColor or fillColor
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Parent = model

	local appear = TweenService:Create(highlight, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FillTransparency = 0.35,
		OutlineTransparency = 0.7,
	})
	local fade = TweenService:Create(highlight, TweenInfo.new(math.max(0.12, dur - 0.08), Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		FillTransparency = 1,
		OutlineTransparency = 1,
	})
	appear:Play()
	appear.Completed:Connect(function()
		if highlight.Parent then
			fade:Play()
		end
	end)
	fade.Completed:Connect(function()
		if highlight.Parent then
			highlight:Destroy()
		end
	end)
end

--[[]]
-- Internal utility: plays a one-shot particle emit from a template Part.
-- The template's ParticleEmitter children can specify Attributes:
--   EmitCount (number) and EmitDelay (number seconds)
-- Clones the part, forces Transparency=1, positions via cframe, emits, then destroys after 3s.
function CombatEffects:_emitFromTemplate(template: BasePart?, cframe: CFrame, parent: Instance?)
	if not template then
		print("[CombatEffects] _emitFromTemplate: no template provided")
		return
	end
	local clone = template:Clone()
	clone.Transparency = 1
	clone.CanCollide = false
	clone.Anchored = true
	clone.CFrame = cframe
	clone.Parent = parent or workspace
	print("[CombatEffects] _emitFromTemplate: cloned", template.Name, "parent:", (parent and parent:GetFullName()) or "workspace")

	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			local emitCountAttr = descendant:GetAttribute("EmitCount")
			local emitDelayAttr = descendant:GetAttribute("EmitDelay")
			local count = (typeof(emitCountAttr) == "number" and emitCountAttr) or 1
			local delaySec = (typeof(emitDelayAttr) == "number" and emitDelayAttr) or 0
			print("[CombatEffects] _emitFromTemplate: emitter", descendant.Name, "EmitCount=", count, "EmitDelay=", delaySec)
			if delaySec > 0 then
				task.delay(delaySec, function()
					if descendant.Parent then
						print("[CombatEffects] _emitFromTemplate: delayed emit for", descendant.Name, "count=", count)
						descendant:Emit(count)
					end
				end)
			else
				print("[CombatEffects] _emitFromTemplate: immediate emit for", descendant.Name, "count=", count)
				descendant:Emit(count)
			end
		end
	end

	-- Cleanup after 3 seconds
	task.delay(3, function()
		if clone and clone.Parent then
			print("[CombatEffects] _emitFromTemplate: destroying clone", clone.Name)
			pcall(function()
				clone:Destroy()
			end)
		end
	end)
end

--[[]]
-- Plays a hit impact particle at the defender's position. Category can be
-- "Super", "Weak"/"NotVery", or nil (defaults to Normal).
function CombatEffects:PlayHitImpact(defenderModel: Model, category: string?)
	if not defenderModel then 
		warn("[CombatEffects] PlayHitImpact - defenderModel is nil")
		return 
	end
	local hrp = defenderModel:FindFirstChild("HumanoidRootPart")
	local primary: BasePart? = (hrp and hrp:IsA("BasePart")) and hrp or defenderModel.PrimaryPart
	if not primary then 
		warn("[CombatEffects] PlayHitImpact - No primary part found for", defenderModel.Name)
		return 
	end

	local effects = self._effects
	if not effects then 
		warn("[CombatEffects] PlayHitImpact - effects folder not found")
		return 
	end
	local hitFolder = effects:FindFirstChild("HitFX")
	if not hitFolder then 
		warn("[CombatEffects] PlayHitImpact - HitFX folder not found in effects")
		return 
	end

	local name = "NormalHit"
	if category == "Super" then
		name = "SuperHit"
	elseif category == "Weak" or category == "NotVery" then
		name = "WeakHit"
	end

	local template = hitFolder:FindFirstChild(name)
	if template and template:IsA("BasePart") then
		print("[CombatEffects] Playing hit impact:", name, "at", primary.CFrame)
		self:_emitFromTemplate(template, primary.CFrame, workspace)
	else
		warn("[CombatEffects] PlayHitImpact - Template not found:", name, "in HitFX folder")
	end
end

--[[]]
-- Plays a shiny burst effect at the model's position using Assets.Effects.ShinyEffect
function CombatEffects:PlayShinyBurst(model: Model)
	print("[CombatEffects] PlayShinyBurst: called for model:", model and model.Name or "nil")
	if not model then
		print("[CombatEffects] PlayShinyBurst: no model")
		return
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local primary: BasePart? = (hrp and hrp:IsA("BasePart")) and hrp or model.PrimaryPart
	if not primary then
		print("[CombatEffects] PlayShinyBurst: no primary part")
		return
	end

	local effects = self._effects
	if not effects then
		print("[CombatEffects] PlayShinyBurst: Assets.Effects not found")
		return
	end

	-- Play Shiny SFX if available
	local sfx = self._sfx
	if sfx then
		local shinySound = sfx:FindFirstChild("Shiny")
		if shinySound and shinySound:IsA("Sound") then
			print("[CombatEffects] PlayShinyBurst: playing SFX 'Shiny'")
			shinySound:Play()
		else
			print("[CombatEffects] PlayShinyBurst: SFX 'Shiny' not found under", sfx:GetFullName())
		end
	else
		print("[CombatEffects] PlayShinyBurst: SFX container not available")
	end
	local shiny = effects:FindFirstChild("ShinyEffect")
	if shiny and shiny:IsA("BasePart") then
		print("[CombatEffects] PlayShinyBurst: found ShinyEffect template, emitting at", tostring(primary.CFrame.Position))
		self:_emitFromTemplate(shiny, primary.CFrame, workspace)
	else
		print("[CombatEffects] PlayShinyBurst: ShinyEffect template missing or wrong class")
	end
end

--[[
	Spawns and plays the Capture Cube use animation at the player's spawn.
	Clones ReplicatedStorage.Assets.Models.CaptureCube, loads Animation "BattleUse"
	from its AnimationController, positions at BattleScene.Essentials.PlayerCreatureSpawn.
	@param battleScene The active battle scene model
	@return Model? The spawned cube instance (nil on failure)
]]
function CombatEffects:PlayCaptureCubeUse(battleScene: Model): Model?
    if not battleScene then
        return nil
    end
    local assets = ReplicatedStorage:FindFirstChild("Assets")
    local models = assets and assets:FindFirstChild("Models")
    local cubeTemplate = models and models:FindFirstChild("CaptureCube")
    if not cubeTemplate or not cubeTemplate:IsA("Model") then
        return nil
    end
    local cube = cubeTemplate:Clone()
    cube.Name = "CaptureCubeRuntime"
    cube.Parent = battleScene
    -- Find spawn CFrame
    local essentials = battleScene:FindFirstChild("Essentials")
    local playerSpawn = essentials and essentials:FindFirstChild("PlayerCreatureSpawn")
    local spawnCFrame = playerSpawn and playerSpawn:IsA("BasePart") and playerSpawn.CFrame or nil
    -- Load and play animation
    -- Resolve the BattleUse Animation that is a descendant of the model (not the controller)
    local anim: Animation? = cube:FindFirstChild("BattleUse", true)
    local animController = cube:FindFirstChildOfClass("AnimationController")
    if anim and anim:IsA("Animation") and animController then
        local track = animController:LoadAnimation(anim)
        if track then
            track:Play()
            -- Wait until animation has actually started (TimePosition > 0)
            local deadline = os.clock() + 2.0
            while track.TimePosition <= 0 do
                if os.clock() > deadline then break end
                task.wait()
            end
			-- Position at spawn after we confirmed animation started (rotate 180° to face forward)
			if spawnCFrame and cube.PrimaryPart then
				cube:SetPrimaryPartCFrame(spawnCFrame * CFrame.Angles(0, math.pi, 0))
			end
        end
    end
    -- Track active cube for lifecycle management
    self._activeCaptureCube = cube
    return cube
end

--[[
	Fades out the active Capture Cube model's MeshPart (CaptureCube) and cleans up.
	@param onComplete Optional callback after removal
]]
function CombatEffects:FadeOutCaptureCube(onComplete: (() -> ())?)
    local cube = self._activeCaptureCube
    if not cube or not cube.Parent then
        self._activeCaptureCube = nil
        if onComplete then onComplete() end
        return
    end
    local mesh: MeshPart? = cube:FindFirstChild("CaptureCube") :: MeshPart?
    if not mesh then
        -- try descendant
        mesh = cube:FindFirstChild("CaptureCube", true) :: MeshPart?
    end
    if not mesh or not mesh:IsA("MeshPart") then
        -- Fallback: destroy cube immediately
        pcall(function() cube:Destroy() end)
        self._activeCaptureCube = nil
        if onComplete then onComplete() end
        return
    end
    -- Tween transparency to 1, then destroy model
    local tween = TweenService:Create(mesh, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
        Transparency = 1
    })
    tween.Completed:Connect(function()
        if cube and cube.Parent then
            pcall(function() cube:Destroy() end)
        end
        self._activeCaptureCube = nil
        if onComplete then onComplete() end
    end)
    tween:Play()
end

--[[
	Plays a status move hop animation (2 hops)
	@param attackerModel The attacker's model
	@param onHit Callback when hit marker is reached (called after first hop)
	@param onComplete Callback when animation completes
	@param skipDamaged If true, skip playing the Damaged animation on defender (for misses)
]]
function CombatEffects:PlayStatusMoveHop(
	attackerModel: Model,
	onHit: (() -> ())?,
	onComplete: (() -> ())?,
	skipDamaged: boolean?
)
	print("[CombatEffects] PlayStatusMoveHop called for model:", attackerModel and attackerModel.Name or "nil")
	
	if not attackerModel then
		print("[CombatEffects] PlayStatusMoveHop: No attackerModel provided")
		if onComplete then
			onComplete()
		end
		return
	end

	local hrp = attackerModel:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		print("[CombatEffects] PlayStatusMoveHop: No HumanoidRootPart found")
		if onComplete then
			onComplete()
		end
		return
	end

	-- Store original state
	local originalCFrame = hrp.CFrame
	local originalAnchored = hrp.Anchored
	print("[CombatEffects] PlayStatusMoveHop: Original CFrame:", originalCFrame, "Original Anchored:", originalAnchored)
	
	-- Anchor the HRP for the animation
	hrp.Anchored = true
	print("[CombatEffects] PlayStatusMoveHop: Anchored HRP for animation")
	
	local hopHeight = 2 -- studs
	local hopDuration = 0.2 -- seconds per direction (up or down)
	
	-- Function to perform a single hop (up then down)
	local function performHop(hopNumber: number, onHopComplete: (() -> ())?)
		print("[CombatEffects] PlayStatusMoveHop: Starting hop", hopNumber)
		
		-- Play hop sound
		local audio = ReplicatedStorage:FindFirstChild("Audio")
		local sfx = audio and audio:FindFirstChild("SFX")
		local hopSound = sfx and sfx:FindFirstChild("Hop")
		if hopSound and hopSound:IsA("Sound") then
			print("[CombatEffects] PlayStatusMoveHop: Playing Hop sound")
			hopSound:Play()
		else
			print("[CombatEffects] PlayStatusMoveHop: Hop sound not found")
		end
		
		-- Hop up
		local upCFrame = originalCFrame * CFrame.new(0, hopHeight, 0)
		print("[CombatEffects] PlayStatusMoveHop: Hop", hopNumber, "- Tweening up to:", upCFrame)
		
		local upTween = TweenService:Create(
			hrp,
			TweenInfo.new(hopDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{CFrame = upCFrame}
		)
		
		-- Hop down
		local downTween = TweenService:Create(
			hrp,
			TweenInfo.new(hopDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{CFrame = originalCFrame}
		)
		
		-- Chain the tweens
		upTween:Play()
		upTween.Completed:Connect(function()
			print("[CombatEffects] PlayStatusMoveHop: Hop", hopNumber, "- Up tween completed")
			downTween:Play()
			downTween.Completed:Connect(function()
				print("[CombatEffects] PlayStatusMoveHop: Hop", hopNumber, "- Down tween completed")
				if onHopComplete then
					onHopComplete()
				end
			end)
		end)
	end
	
	-- Perform first hop
	performHop(1, function()
		print("[CombatEffects] PlayStatusMoveHop: First hop completed")
		-- Call onHit after first hop completes
		if onHit then
			print("[CombatEffects] PlayStatusMoveHop: Calling onHit callback")
			onHit()
		end
		
		-- Perform second hop
		performHop(2, function()
			print("[CombatEffects] PlayStatusMoveHop: Second hop completed")
			-- Ensure we're back at original position
			hrp.CFrame = originalCFrame
			print("[CombatEffects] PlayStatusMoveHop: Reset HRP to original CFrame")
			
			-- Restore original anchored state
			hrp.Anchored = originalAnchored
			print("[CombatEffects] PlayStatusMoveHop: Restored original Anchored state:", originalAnchored)
			
			-- Return to idle animation
			if self._animationController then
				print("[CombatEffects] PlayStatusMoveHop: Returning to idle animation")
				self._animationController:PlayIdleAnimation(attackerModel)
			end
			
			-- Call completion callback
			if onComplete then
				print("[CombatEffects] PlayStatusMoveHop: Calling onComplete callback")
				onComplete()
			end
		end)
	end)
end

--[[
	Plays a move attack sequence
	@param attackerModel The attacker's model
	@param defenderModel The defender's model
	@param moveName The move name
	@param onHit Callback when hit marker is reached
	@param onComplete Callback when animation completes
	@param skipDamaged If true, skip playing the Damaged animation on defender (for misses)
]]
function CombatEffects:PlayMoveAttack(
	attackerModel: Model,
	defenderModel: Model,
	moveName: string,
	onHit: (() -> ())?,
	onComplete: (() -> ())?,
	skipDamaged: boolean?
)
	if not attackerModel or not defenderModel then
		if onComplete then
			onComplete()
		end
		return
	end

	-- Check if this is a status move (BasePower == 0)
	local Moves = require(ReplicatedStorage.Shared.Moves)
	local moveDef = Moves[moveName]
	-- Try case-insensitive lookup if direct lookup fails
	if not moveDef and type(moveName) == "string" then
		local moveNameLower = string.lower(moveName)
		for key, value in pairs(Moves) do
			if type(key) == "string" and string.lower(key) == moveNameLower then
				moveDef = value
				break
			end
		end
	end
	if moveDef and moveDef.BasePower == 0 then
		-- Status move: use hop animation instead of attack animation
		print("[CombatEffects] PlayMoveAttack: Detected status move:", moveName, "- Using hop animation")
		self:PlayStatusMoveHop(attackerModel, onHit, onComplete, skipDamaged)
		return
	end

	-- Custom move handlers (e.g., Crunch)
	local MoveFunctions = nil
	local okRequire, errRequire = pcall(function()
		MoveFunctions = MoveFunctions or require(script.Parent.MoveFunctions)
	end)
	if not okRequire then
		warn("[CombatEffects] MoveFunctions require failed:", errRequire)
	end
	-- Normalize name for lookup
	local key = moveName
	if type(moveName) == "string" then
		key = moveName
	end
	warn("[CombatEffects] PlayMoveAttack moveName=", tostring(moveName))
	if MoveFunctions and type(MoveFunctions[key]) ~= "function" and type(key) == "string" then
		key = string.lower(key)
	end
	if MoveFunctions and type(MoveFunctions[key]) == "function" then
		warn("[CombatEffects] PlayMoveAttack: calling MoveFunctions handler for", tostring(key))
		local handled = MoveFunctions[key]({
			attackerModel = attackerModel,
			defenderModel = defenderModel,
			onHit = onHit,
			onComplete = onComplete,
			skipDamaged = skipDamaged,
			animationController = self._animationController,
		})
		if handled then
			return
		else
			warn("[CombatEffects] MoveFunctions handler returned false for", tostring(key))
		end
	elseif MoveFunctions then
		warn("[CombatEffects] No MoveFunctions handler found for", tostring(key))
	end
	
	-- Check MoveAnimations module for custom animations
	local MoveAnimations = nil
	local okAnimRequire, errAnimRequire = pcall(function()
		MoveAnimations = MoveAnimations or require(script.Parent.MoveAnimations)
	end)
	if not okAnimRequire then
		warn("[CombatEffects] MoveAnimations require failed:", errAnimRequire)
	end
	
	if MoveAnimations then
		local animKey = moveName
		if type(moveName) == "string" then
			animKey = moveName
		end
		if type(MoveAnimations[animKey]) ~= "function" and type(animKey) == "string" then
			animKey = string.lower(animKey)
		end
		
		if type(MoveAnimations[animKey]) == "function" then
			warn("[CombatEffects] PlayMoveAttack: calling MoveAnimations handler for", tostring(animKey))
			local handled = MoveAnimations[animKey]({
				attackerModel = attackerModel,
				defenderModel = defenderModel,
				onHit = onHit,
				onComplete = onComplete,
				skipDamaged = skipDamaged,
				animationController = self._animationController,
			})
			if handled then
				return
			else
				warn("[CombatEffects] MoveAnimations handler returned false for", tostring(animKey))
			end
		end
	end
	
	-- Track if Damaged animation chain will handle completion
	local handledByDamagedChain = false
	
	-- Play attack animation on attacker with Hit marker support
	self._animationController:PlayAnimationWithHit(attackerModel, "Attack", function()
		-- Hit marker reached - trigger UI update and play damage animation
		if onHit then
			onHit()  -- Update UI with pending HP data and play hit effects
		end
		
		-- Play damage animation on defender only if the move hit
		if not skipDamaged then
			handledByDamagedChain = true
			self._animationController:PlayAnimation(defenderModel, "Damaged", function()
				-- Return attacker to idle after Damaged animation completes
				self._animationController:PlayIdleAnimation(attackerModel)
				
				if onComplete then
					onComplete()
				end
			end)
		else
			-- Move missed - just return attacker to idle without playing Damaged animation
			self._animationController:PlayIdleAnimation(attackerModel)
			
			if onComplete then
				onComplete()
			end
		end
	end, function()
		-- Attack animation track stopped
		-- Only handle completion if the Damaged animation chain isn't already handling it
		-- This prevents double onComplete calls and premature step progression
		if not handledByDamagedChain then
			self._animationController:PlayIdleAnimation(attackerModel)
			if onComplete then
				onComplete()
			end
		end
		-- If handledByDamagedChain is true, the Damaged animation callback handles idle and onComplete
	end)
end

--[[
	Plays damage flash effect on a model
	@param model The model to flash
	@param effectiveness Type effectiveness ("Super", "NotVery", "Normal", "Immune")
]]
function CombatEffects:PlayDamageFlash(model: Model, effectiveness: string?)
	if not model then
		return
	end
	
	-- Play effectiveness sound
	self:PlayEffectivenessSound(effectiveness or "Normal")
	
	-- Flash effect removed - no visual damage flash
end

--[[
	Plays a multi-hit damage effect - attack animation on attacker, then damage on defender
	Used for multi-hit moves like Double Kick, Bullet Seed, etc.
	Plays Attack animation, hit impact, damage flash, and Damaged animation, then calls onComplete
	@param attackerModel The attacker's model
	@param defenderModel The defender's model
	@param effectiveness Type effectiveness for the hit
	@param onComplete Callback when the hit animation completes
]]
function CombatEffects:PlayMultiHitDamage(attackerModel: Model?, defenderModel: Model, effectiveness: string?, onComplete: (() -> ())?)
	if not defenderModel then
		if onComplete then onComplete() end
		return
	end
	
	-- Determine effectiveness category for hit impact
	local category: string? = nil
	if effectiveness == "Super" then
		category = "Super"
	elseif effectiveness == "NotVery" or effectiveness == "Weak" then
		category = "Weak"
	end
	
	-- If we have an attacker model, play the attack animation with hit marker
	if attackerModel then
		self._animationController:PlayAnimationWithHit(attackerModel, "Attack", function()
			-- Hit marker reached - play impact effects on defender
			self:PlayHitImpact(defenderModel, category)
			self:PlayDamageFlash(defenderModel, effectiveness)
			
			-- Play Damaged animation on defender
			self._animationController:PlayAnimation(defenderModel, "Damaged", function()
				-- Return attacker to idle
				self._animationController:PlayIdleAnimation(attackerModel)
				
				-- Small delay after animation to let the visual register
				task.delay(0.1, function()
					if onComplete then
						onComplete()
					end
				end)
			end)
		end, function()
			-- Attack animation stopped callback (fallback if hit marker isn't reached)
			-- This is handled by the Damaged animation chain above
		end)
	else
		-- No attacker model - just play effects on defender
		self:PlayHitImpact(defenderModel, category)
		self:PlayDamageFlash(defenderModel, effectiveness)
		
		self._animationController:PlayAnimation(defenderModel, "Damaged", function()
			task.delay(0.1, function()
				if onComplete then
					onComplete()
				end
			end)
		end)
	end
end

-- Plays a dramatic scan flash with holographic effect: cyan/green on success, red on failure
function CombatEffects:PlayScanFlash(model: Model, success: boolean)
    if not model then
        return
    end
    
    -- Play scan audio
    local scanSound = Instance.new("Sound")
    if success then
        scanSound.SoundId = "rbxassetid://6895079853" -- Digital scan beep
        scanSound.PlaybackSpeed = 1.3
    else
        scanSound.SoundId = "rbxassetid://4590657391" -- Error buzz
        scanSound.PlaybackSpeed = 0.9
    end
    scanSound.Volume = 0.5
    scanSound.Parent = workspace
    scanSound:Play()
    scanSound.Ended:Connect(function()
        scanSound:Destroy()
    end)
    
    -- Create highlight for the creature
    local highlight = Instance.new("Highlight")
    highlight.Adornee = model
    highlight.DepthMode = Enum.HighlightDepthMode.Occluded
    highlight.FillTransparency = 1
    highlight.OutlineTransparency = 1
    highlight.Parent = model
    
    -- Colors: success = cyan/green (holographic feel), failure = red
    if success then
        highlight.FillColor = Color3.fromRGB(80, 255, 200) -- Cyan-green
        highlight.OutlineColor = Color3.fromRGB(100, 200, 255) -- Light blue
    else
        highlight.FillColor = Color3.fromRGB(255, 60, 60) -- Bright red
        highlight.OutlineColor = Color3.fromRGB(180, 40, 40) -- Dark red
    end
    
    local TweenService = game:GetService("TweenService")
    
    -- More dramatic timing for engagement
    local flashDuration = success and 0.12 or 0.08
    local holdDuration = success and 0.15 or 0.1
    local fadeDuration = success and 0.25 or 0.35
    
    -- Flash in quickly (more dramatic)
    local inTween = TweenService:Create(highlight, TweenInfo.new(flashDuration, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
        FillTransparency = success and 0.1 or 0.15, -- Brighter flash
        OutlineTransparency = 0,
    })
    
    -- Hold at peak brightness
    local holdTween = TweenService:Create(highlight, TweenInfo.new(holdDuration, Enum.EasingStyle.Linear), {
        FillTransparency = success and 0.15 or 0.2,
        OutlineTransparency = 0.1,
    })
    
    -- Fade out
    local outTween = TweenService:Create(highlight, TweenInfo.new(fadeDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
        FillTransparency = 1,
        OutlineTransparency = 1,
    })
    
    -- Add scanline effect for extra juice
    self:_playScanlineEffect(model, success)
    
    -- Chain tweens
    inTween:Play()
    inTween.Completed:Connect(function()
        holdTween:Play()
    end)
    holdTween.Completed:Connect(function()
        outTween:Play()
    end)
    outTween.Completed:Connect(function()
        highlight:Destroy()
    end)
end

-- Internal: Plays a scanning line effect over the creature
function CombatEffects:_playScanlineEffect(model: Model, success: boolean)
    local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    if not hrp then return end
    
    -- Create a simple scanline beam effect
    local scanline = Instance.new("Part")
    scanline.Name = "Scanline"
    scanline.Anchored = true
    scanline.CanCollide = false
    scanline.Size = Vector3.new(5, 0.08, 5)
    scanline.Material = Enum.Material.Neon
    scanline.Color = success and Color3.fromRGB(80, 255, 200) or Color3.fromRGB(255, 80, 80)
    scanline.Transparency = 0.3
    scanline.CastShadow = false
    
    -- Start below the creature
    local startY = hrp.Position.Y - 3
    local endY = hrp.Position.Y + 3
    scanline.CFrame = CFrame.new(hrp.Position.X, startY, hrp.Position.Z)
    scanline.Parent = workspace
    
    -- Animate scanline moving up
    local TweenService = game:GetService("TweenService")
    local moveTween = TweenService:Create(
        scanline,
        TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
        {CFrame = CFrame.new(hrp.Position.X, endY, hrp.Position.Z), Transparency = 0.8}
    )
    
    moveTween:Play()
    moveTween.Completed:Connect(function()
        scanline:Destroy()
    end)
end

--[[
	Plays recall animation sequence (creature going back to ball)
	@param model The model to recall
	@param onComplete Callback when animation completes
]]
function CombatEffects:PlayRecallAnimation(
	model: Model,
	onComplete: (() -> ())?
)
	print("[CombatEffects] PlayRecallAnimation called - Model:", model and model.Name or "nil")
	
	if not model then
		print("[CombatEffects] No model found - calling onComplete immediately")
		if onComplete then
			onComplete()
		end
		return
	end
	
	-- Play recall animation with hologram despawn effect
	if self._animationController then
		local track = self._animationController:PlayAnimation(model, "Recall", function()
			print("[CombatEffects] Recall animation completed - starting hologram despawn")
			self:_startRecallHologramEffect(model, onComplete)
		end)
		
		-- If no track returned (animation doesn't exist), skip animation and go directly to hologram
		if not track then
			print("[CombatEffects] Recall animation not found - skipping animation and going directly to hologram")
			self:_startRecallHologramEffect(model, onComplete)
		end
	else
		print("[CombatEffects] No animation controller - going directly to hologram")
		self:_startRecallHologramEffect(model, onComplete)
	end
end

--[[
	Internal: Starts the recall hologram effect
	@param model The model to despawn
	@param onComplete Callback when effect completes
]]
function CombatEffects:_startRecallHologramEffect(model: Model, onComplete: (() -> ())?)
	-- Use hologram spawn effect for recall (fade out)
	local HologramSpawnEffect = require(script.Parent.Parent.Utilities.HologramSpawnEffect)
	print("[CombatEffects] Calling HologramSpawnEffect:CreateFadeOut for recall")
	
	-- Create hologram effect with model destruction at peak visibility
	HologramSpawnEffect:CreateFadeOut(model, function()
		print("[CombatEffects] Recall hologram effect completed")
		
		-- Call the completion callback
		if onComplete then
			onComplete()
		else
			print("[CombatEffects] WARNING: onComplete callback is nil!")
		end
	end, function()
		print("[CombatEffects] Recall hologram at peak visibility - destroying model")
		
		-- Destroy the model when hologram reaches peak visibility
		if model and model.Parent then
			model:Destroy()
			print("[CombatEffects] Model destroyed:", model.Name)
		end
	end)
end

--[[
	Plays faint animation sequence
	@param model The model to faint
	@param isPlayer Whether this is the player's creature
	@param onComplete Callback when animation completes
]]
function CombatEffects:PlayFaintAnimation(
	model: Model,
	isPlayer: boolean,
	onComplete: (() -> ())?
)
	print("[CombatEffects] PlayFaintAnimation called - IsPlayer:", isPlayer, "Model:", model and model.Name or "nil")
	
	if not model then
		print("[CombatEffects] No model found - calling onComplete immediately")
		if onComplete then
			onComplete()
		end
		return
	end
	
	-- Fade out ice cube if creature is frozen
	self:FadeOutIceCube(model)
	
	-- Use hologram spawn effect for faint (fade out)
	print("[CombatEffects] Using hologram effect for faint - IsPlayer:", isPlayer)
	
	local HologramSpawnEffect = require(script.Parent.Parent.Utilities.HologramSpawnEffect)
	print("[CombatEffects] Calling HologramSpawnEffect:CreateFadeOut for model:", model.Name)
	
	-- Create hologram effect with model destruction at peak visibility
	HologramSpawnEffect:CreateFadeOut(model, function()
		print("[CombatEffects] Faint hologram effect completed")
		
		-- Call the completion callback
		if onComplete then
			onComplete()
		else
			print("[CombatEffects] WARNING: onComplete callback is nil!")
		end
	end, function()
		print("[CombatEffects] Faint hologram at peak visibility - destroying model")
		
		-- Destroy the model when hologram reaches peak visibility
		if model and model.Parent then
			model:Destroy()
			print("[CombatEffects] Model destroyed:", model.Name)
		end
	end)
end

--[[
	Plays critical hit effect
	@param model The defender's model
]]
function CombatEffects:PlayCriticalHitEffect(model: Model)
	if not model then
		return
	end
	
	-- Play crit sound
	if self._sfx then
		local critSound = self._sfx:FindFirstChild("CriticalHit")
		if critSound then
			critSound:Play()
		end
	end
	
	-- Subtle visual: quick golden highlight pulse (code-only fallback)
	self:_pulseHighlight(model, Color3.fromRGB(255, 214, 74), Color3.fromRGB(255, 248, 196), 0.35)
end

--[[
	Plays miss effect
	@param model The defender's model
]]
function CombatEffects:PlayMissEffect(model: Model)
	if not model then
		return
	end
	
	-- Play miss sound
	if self._sfx then
		local missSound = self._sfx:FindFirstChild("Miss")
		if missSound then
			missSound:Play()
		end
	end
	
	-- Subtle visual: quick cool/white pulse (reads as "whoosh"/avoid)
	self:_pulseHighlight(model, Color3.fromRGB(220, 220, 220), Color3.fromRGB(255, 255, 255), 0.28)
end

--[[
	Plays effectiveness sound
	@param effectiveness Type effectiveness ("Super", "NotVery", "Normal", "Immune")
]]
function CombatEffects:PlayEffectivenessSound(effectiveness: string)
	if not self._sfx then
		print("[CombatEffects] PlayEffectivenessSound: no SFX container")
		return
	end

	local soundName = "Normal"
	if effectiveness == "Super" then
		soundName = "SuperEffective"
	elseif effectiveness == "NotVery" then
		soundName = "NotVeryEffective"
	elseif effectiveness == "Immune" then
		-- Commonly not present; will fall back to Normal if missing
		soundName = "NoEffect"
	end

	-- Prefer SFX.Hits/<name>
	local hitsFolder = self._sfx:FindFirstChild("Hits")
	local sound: Sound? = nil
	if hitsFolder then
		sound = hitsFolder:FindFirstChild(soundName) :: Sound?
	end
	-- Fallback to SFX/<name>
	if not sound then
		sound = self._sfx:FindFirstChild(soundName) :: Sound?
	end
	-- Final fallback for Immune when NoEffect is missing
	if (not sound) and effectiveness == "Immune" and hitsFolder then
		sound = hitsFolder:FindFirstChild("Normal") :: Sound?
	end

	if sound then
		print("[CombatEffects] PlayEffectivenessSound: playing", sound.Name)
		sound:Play()
	else
		print("[CombatEffects] PlayEffectivenessSound: sound not found for effectiveness=", effectiveness, "(tried '", soundName, "')")
	end
end

--[[
	Plays stat change effect
	@param model The creature's model
	@param statName The stat name
	@param stages Number of stages changed (positive or negative)
]]
function CombatEffects:PlayStatChangeEffect(model: Model, statName: string, stages: number)
	if not model then
		return
	end
	
	-- Play stat change sound from ReplicatedStorage.Audio.SFX
	local soundName = stages > 0 and "StatUp" or "StatDown"
	local audio = ReplicatedStorage:FindFirstChild("Audio")
	local sfx = audio and audio:FindFirstChild("SFX")
	local sound = sfx and sfx:FindFirstChild(soundName)
	if sound and sound:IsA("Sound") then
		sound:Play()
		print("[CombatEffects] PlayStatChangeEffect: Playing sound", soundName)
	else
		print("[CombatEffects] PlayStatChangeEffect: Sound not found -", soundName)
	end
	
	-- Visual stat change effect using StatUp/StatDown models
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local primaryPart: BasePart? = (hrp and hrp:IsA("BasePart")) and hrp or model.PrimaryPart
	if not primaryPart then
		print("[CombatEffects] PlayStatChangeEffect: No primary part for visual effect")
		return
	end
	
	-- Get the StatUp or StatDown model from Assets.Models
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local models = assets and assets:FindFirstChild("Models")
	if not models then
		print("[CombatEffects] PlayStatChangeEffect: Assets.Models not found")
		return
	end
	
	local templateName = stages > 0 and "StatUp" or "StatDown"
	local template = models:FindFirstChild(templateName)
	if not template or not template:IsA("BasePart") then
		print("[CombatEffects] PlayStatChangeEffect: Template not found:", templateName)
		return
	end
	
	-- Clone and position the effect
	local effectPart = template:Clone()
	effectPart.Name = templateName .. "_Effect"
	effectPart.Anchored = true
	effectPart.CanCollide = false
	effectPart.Transparency = 1  -- Base part stays invisible
	effectPart.CFrame = primaryPart.CFrame
	effectPart.Parent = workspace
	
	-- Collect all animatable components for fade in/out
	local beams: {Beam} = {}
	local particles: {ParticleEmitter} = {}
	
	for _, descendant in ipairs(effectPart:GetDescendants()) do
		if descendant:IsA("Beam") then
			table.insert(beams, descendant)
		elseif descendant:IsA("ParticleEmitter") then
			table.insert(particles, descendant)
		end
	end
	
	-- Store original transparency values
	local originalBeamTransparencies: {[Beam]: NumberSequence} = {}
	local originalParticleTransparencies: {[ParticleEmitter]: NumberSequence} = {}
	
	-- Set all beams and particles to fully transparent initially
	for _, beam in ipairs(beams) do
		originalBeamTransparencies[beam] = beam.Transparency
		beam.Transparency = NumberSequence.new(1)  -- Fully transparent
	end
	
	for _, particle in ipairs(particles) do
		originalParticleTransparencies[particle] = particle.Transparency
		-- Enable particles so they start emitting
		particle.Enabled = true
	end
	
	-- Fade in beams over 0.3 seconds
	local fadeInDuration = 0.3
	local holdDuration = 1.0
	local fadeOutDuration = 0.4
	
	-- Animate beam fade in
	task.spawn(function()
		local startTime = os.clock()
		while os.clock() - startTime < fadeInDuration do
			local alpha = (os.clock() - startTime) / fadeInDuration
			for beam, originalTransparency in pairs(originalBeamTransparencies) do
				if beam and beam.Parent then
					-- Interpolate from fully transparent (1) to original transparency
					local keypoints = originalTransparency.Keypoints
					local newKeypoints = {}
					for _, keypoint in ipairs(keypoints) do
						local newValue = 1 - alpha * (1 - keypoint.Value)
						table.insert(newKeypoints, NumberSequenceKeypoint.new(keypoint.Time, newValue))
					end
					beam.Transparency = NumberSequence.new(newKeypoints)
				end
			end
			task.wait()
		end
		
		-- Set to original transparency after fade in completes
		for beam, originalTransparency in pairs(originalBeamTransparencies) do
			if beam and beam.Parent then
				beam.Transparency = originalTransparency
			end
		end
	end)
	
	-- Hold for duration, then fade out
	task.delay(fadeInDuration + holdDuration, function()
		-- Disable particle emission before fade out
		for _, particle in ipairs(particles) do
			if particle and particle.Parent then
				particle.Enabled = false
			end
		end
		
		-- Fade out beams
		local startTime = os.clock()
		while os.clock() - startTime < fadeOutDuration do
			local alpha = (os.clock() - startTime) / fadeOutDuration
			for beam, originalTransparency in pairs(originalBeamTransparencies) do
				if beam and beam.Parent then
					-- Interpolate from original transparency to fully transparent (1)
					local keypoints = originalTransparency.Keypoints
					local newKeypoints = {}
					for _, keypoint in ipairs(keypoints) do
						local newValue = keypoint.Value + alpha * (1 - keypoint.Value)
						table.insert(newKeypoints, NumberSequenceKeypoint.new(keypoint.Time, newValue))
					end
					beam.Transparency = NumberSequence.new(newKeypoints)
				end
			end
			task.wait()
		end
		
		-- Clean up: wait for remaining particles to dissipate, then destroy
		task.delay(2.0, function()
			if effectPart and effectPart.Parent then
				effectPart:Destroy()
			end
		end)
	end)
	
	print("[CombatEffects] PlayStatChangeEffect: Playing", templateName, "effect for", model.Name)
end

--[[
	Plays status condition effect
	@param model The creature's model
	@param status The status condition name
]]
function CombatEffects:PlayStatusEffect(model: Model, status: string)
	if not model then
		return
	end
	
	-- Status audio IDs mapping
	local statusAudioIds: {[string]: string} = {
		BRN = "rbxassetid://72777760410962",
		PAR = "rbxassetid://114020093372684",
		PSN = "rbxassetid://118711941569199",
		TOX = "rbxassetid://118711941569199", -- Use same as PSN for now
		SLP = "rbxassetid://106972850524292",
		FRZ = "rbxassetid://109691529279394",
		Confusion = "rbxassetid://80012622109613",
	}
	
	-- Normalize status to uppercase for lookup
	local statusUpper = status and string.upper(tostring(status)) or ""
	
	-- Get audio ID for this status
	local audioId = statusAudioIds[statusUpper]
	
	if audioId then
		-- Create and play sound
		local sound = Instance.new("Sound")
		sound.SoundId = audioId
		sound.Volume = 1.23
		sound.Parent = workspace
		sound:Play()
		
		-- Clean up sound after it finishes
		sound.Ended:Connect(function()
			sound:Destroy()
		end)
		
		print("[CombatEffects] PlayStatusEffect: Playing audio for status:", statusUpper, "AudioId:", audioId)
	else
		-- Fallback: try to find sound in SFX folder
		if self._sfx then
			local sound = self._sfx:FindFirstChild("Status" .. statusUpper)
			if sound then
				sound:Play()
				print("[CombatEffects] PlayStatusEffect: Using fallback SFX sound for:", statusUpper)
			else
				print("[CombatEffects] PlayStatusEffect: No audio found for status:", statusUpper)
			end
		end
	end
	
	-- Special handling for freeze status
	if statusUpper == "FRZ" then
		self:_applyFreezeEffect(model)
		return
	end
	
	-- Play particle effects for status conditions
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		-- Get status effects folder
		local effects = self._effects
		if effects then
			local statusFolder = effects:FindFirstChild("Status")
			if statusFolder then
				-- Map status codes to attachment names (handle Confusion vs confusion)
				local attachmentName = statusUpper
				if statusUpper == "CONFUSION" then
					attachmentName = "Confusion"
				else
					attachmentName = statusUpper  -- BRN, PAR, PSN, TOX, SLP
				end
				
				local statusAttachment = statusFolder:FindFirstChild(attachmentName)
				if statusAttachment and statusAttachment:IsA("Attachment") then
					-- Clone the attachment to the creature's HRP
					local clonedAttachment = statusAttachment:Clone()
					clonedAttachment.Parent = hrp
					print("[CombatEffects] PlayStatusEffect: Cloned status attachment:", attachmentName, "to HRP")
					
					-- Wait 0.85 seconds, then disable all particle emitters
					task.delay(0.85, function()
						if clonedAttachment and clonedAttachment.Parent then
							-- Find all ParticleEmitters in the attachment and disable them
							for _, descendant in ipairs(clonedAttachment:GetDescendants()) do
								if descendant:IsA("ParticleEmitter") then
									descendant.Enabled = false
									print("[CombatEffects] PlayStatusEffect: Disabled particle emitter:", descendant.Name)
								end
							end
							
							-- Wait 3 seconds, then destroy the attachment
							task.delay(3, function()
								if clonedAttachment and clonedAttachment.Parent then
									clonedAttachment:Destroy()
									print("[CombatEffects] PlayStatusEffect: Destroyed status attachment:", attachmentName)
								end
							end)
						end
					end)
				else
					print("[CombatEffects] PlayStatusEffect: Status attachment not found:", attachmentName)
				end
			else
				print("[CombatEffects] PlayStatusEffect: Status effects folder not found")
			end
		else
			print("[CombatEffects] PlayStatusEffect: Effects folder not found")
		end
	else
		print("[CombatEffects] PlayStatusEffect: No HumanoidRootPart found for particle effects")
	end
end

--[[
	Plays healing effect
	@param model The creature's model
	@param amount Amount healed
]]
function CombatEffects:PlayHealEffect(model: Model, amount: number)
	if not model then
		return
	end
	
	-- Play heal sound
	if self._sfx then
		local healSound = self._sfx:FindFirstChild("Heal")
		if healSound then
			healSound:Play()
		end
	end
	
	-- Subtle visual: green pulse
	self:_pulseHighlight(model, Color3.fromRGB(72, 255, 140), Color3.fromRGB(210, 255, 226), 0.4)
end

--[[
	Creates floating damage text
	@param model The creature's model
	@param text The text to display
	@param color The text color
]]
function CombatEffects:CreateFloatingText(model: Model, text: string, color: Color3?)
	if not model then
		return
	end

	local anchor = self:_getAnchorPart(model)
	if not anchor then return end
	if type(text) ~= "string" or text == "" then return end

	local gui = Instance.new("BillboardGui")
	gui.Name = "CombatFloatingText"
	gui.Adornee = anchor
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(160, 50)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 160
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Font.fromId(12187377099, Enum.FontWeight.Bold) 
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.45
	label.TextTransparency = 0
	label.Parent = gui

	-- Motion: slight drift + rise + fade out
	local driftX = (math.random() * 0.6) - 0.3
	local riseY = 1.4
	local duration = 0.8

	local tweenGui = TweenService:Create(gui, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = Vector3.new(driftX, 3.2 + riseY, 0),
	})
	local tweenLabel = TweenService:Create(label, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})

	tweenGui:Play()
	tweenLabel:Play()

	task.delay(duration + 0.15, function()
		if gui and gui.Parent then
			gui:Destroy()
		end
	end)
end

--[[
	Internal: Applies freeze effect to a creature
	@param model The creature model to freeze
]]
function CombatEffects:_applyFreezeEffect(model: Model)
	if not model then
		return
	end
	
	-- Freeze the animation
	if self._animationController and self._animationController.FreezeAnimation then
		self._animationController:FreezeAnimation(model)
	end
	
	-- Get HRP for ice cube positioning
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		print("[CombatEffects] _applyFreezeEffect: No HumanoidRootPart found")
		return
	end
	
	-- Check if already frozen (don't create duplicate ice cube)
	if self._frozenIceCubes[model] then
		print("[CombatEffects] _applyFreezeEffect: Creature already frozen, skipping ice cube creation")
		return
	end
	
	-- Get status effects folder
	local effects = self._effects
	if not effects then
		print("[CombatEffects] _applyFreezeEffect: Effects folder not found")
		return
	end
	
	local statusFolder = effects:FindFirstChild("Status")
	if not statusFolder then
		print("[CombatEffects] _applyFreezeEffect: Status effects folder not found")
		return
	end
	
	-- Play FRZ attachment particle effect (same as other status effects)
	local frzAttachment = statusFolder:FindFirstChild("FRZ")
	if frzAttachment and frzAttachment:IsA("Attachment") then
		-- Clone the attachment to the creature's HRP
		local clonedAttachment = frzAttachment:Clone()
		clonedAttachment.Parent = hrp
		print("[CombatEffects] _applyFreezeEffect: Cloned FRZ attachment to HRP")
		
		-- Wait 0.85 seconds, then disable all particle emitters
		task.delay(0.85, function()
			if clonedAttachment and clonedAttachment.Parent then
				-- Find all ParticleEmitters in the attachment and disable them
				for _, descendant in ipairs(clonedAttachment:GetDescendants()) do
					if descendant:IsA("ParticleEmitter") then
						descendant.Enabled = false
						print("[CombatEffects] _applyFreezeEffect: Disabled particle emitter:", descendant.Name)
					end
				end
				
				-- Wait 3 seconds, then destroy the attachment
				task.delay(3, function()
					if clonedAttachment and clonedAttachment.Parent then
						clonedAttachment:Destroy()
						print("[CombatEffects] _applyFreezeEffect: Destroyed FRZ attachment")
					end
				end)
			end
		end)
	else
		print("[CombatEffects] _applyFreezeEffect: FRZ attachment not found")
	end
	
	-- Find and clone the ice cube
	local iceCubeTemplate = statusFolder:FindFirstChild("FRZ_IceCube")
	if not iceCubeTemplate or not iceCubeTemplate:IsA("MeshPart") then
		print("[CombatEffects] _applyFreezeEffect: FRZ_IceCube not found or not a MeshPart")
		return
	end
	
	-- Clone the ice cube
	local iceCube = iceCubeTemplate:Clone()
	iceCube.Name = "FrozenIceCube"
	iceCube.Anchored = true
	iceCube.CanCollide = false
	iceCube.CFrame = hrp.CFrame
	iceCube.Parent = workspace
	
	-- Track the ice cube
	self._frozenIceCubes[model] = iceCube
	
	-- Keep ice cube aligned with HRP using a connection
	local connection
	connection = game:GetService("RunService").Heartbeat:Connect(function()
		if not model or not model.Parent or not hrp or not hrp.Parent then
			if connection then
				connection:Disconnect()
			end
			self._iceCubeConnections[model] = nil
			return
		end
		
		if iceCube and iceCube.Parent then
			iceCube.CFrame = hrp.CFrame
		else
			if connection then
				connection:Disconnect()
			end
			self._iceCubeConnections[model] = nil
		end
	end)
	
	-- Store connection for cleanup
	self._iceCubeConnections[model] = connection
	
	print("[CombatEffects] _applyFreezeEffect: Applied freeze effect to", model.Name)
end

--[[
	Internal: Fades out and destroys an ice cube
	@param iceCube The ice cube MeshPart to fade out
	@param onComplete Optional callback when fade completes
]]
function CombatEffects:_fadeOutIceCube(iceCube: MeshPart, onComplete: (() -> ())?)
	if not iceCube or not iceCube.Parent then
		if onComplete then
			onComplete()
		end
		return
	end
	
	-- Fade out transparency
	local tween = TweenService:Create(
		iceCube,
		TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
		{Transparency = 1}
	)
	
	tween.Completed:Connect(function()
		if iceCube and iceCube.Parent then
			iceCube:Destroy()
			print("[CombatEffects] _fadeOutIceCube: Destroyed ice cube after fade")
		end
		if onComplete then
			onComplete()
		end
	end)
	
	tween:Play()
end

--[[
	Thaws a frozen creature (removes freeze effect)
	@param model The creature model to thaw
]]
function CombatEffects:ThawCreature(model: Model)
	if not model then
		return
	end
	
	-- Unfreeze the animation
	if self._animationController and self._animationController.UnfreezeAnimation then
		self._animationController:UnfreezeAnimation(model)
	end
	
	-- Disconnect ice cube alignment connection
	local connection = self._iceCubeConnections[model]
	if connection then
		connection:Disconnect()
		self._iceCubeConnections[model] = nil
	end
	
	-- Fade out and destroy the ice cube
	local iceCube = self._frozenIceCubes[model]
	if iceCube and iceCube.Parent then
		self:_fadeOutIceCube(iceCube)
		print("[CombatEffects] ThawCreature: Fading out ice cube for", model.Name)
	end
	
	-- Clear tracking
	self._frozenIceCubes[model] = nil
	
	print("[CombatEffects] ThawCreature: Thawed", model.Name)
end

--[[
	Fades out ice cube for a creature (used when creature faints or is recalled)
	@param model The creature model
]]
function CombatEffects:FadeOutIceCube(model: Model)
	if not model then
		return
	end
	
	-- Disconnect ice cube alignment connection
	local connection = self._iceCubeConnections[model]
	if connection then
		connection:Disconnect()
		self._iceCubeConnections[model] = nil
	end
	
	-- Fade out and destroy the ice cube
	local iceCube = self._frozenIceCubes[model]
	if iceCube and iceCube.Parent then
		self:_fadeOutIceCube(iceCube)
		print("[CombatEffects] FadeOutIceCube: Fading out ice cube for", model.Name)
	end
	
	-- Clear tracking
	self._frozenIceCubes[model] = nil
end

--[[
	Plays spikes hazard visual effect
	Creates animated spikes falling from above onto the platform on the specified side
	@param battleScene The battle scene model
	@param isPlayerSide Whether spikes are on player side (true) or foe side (false)
	@param layers Number of spike layers (1-3). Determines how many spikes spawn.
	@param creatureModel Optional creature model (not used, kept for compatibility)
	@param color Optional color for spikes (defaults to 'Smoky grey')
]]
function CombatEffects:PlaySpikesEffect(battleScene: Model?, isPlayerSide: boolean, layers: number?, creatureModel: Model?, color: string?)
	if not battleScene then
		warn("[CombatEffects] PlaySpikesEffect: No battle scene provided")
		return
	end
	
	-- Get platform from Essentials folder
	local essentials = battleScene:FindFirstChild("Essentials")
	if not essentials then
		warn("[CombatEffects] PlaySpikesEffect: Essentials folder not found")
		return
	end
	
	local platformName = isPlayerSide and "PlayerCreatureSpawn" or "FoeCreatureSpawn"
	local platform = essentials:FindFirstChild(platformName)
	
	if not platform or not platform:IsA("BasePart") then
		warn("[CombatEffects] PlaySpikesEffect: Platform not found or invalid:", platformName)
		return
	end
	
	-- Determine spike count based on layers
	local layersCount = layers or 1
	layersCount = math.clamp(layersCount, 1, 3) -- Ensure between 1-3
	
	local totalSpikes = 9 -- Total spikes for max layer (3)
	local spikesPerLayer = 3 -- Each layer adds 3 spikes
	
	-- Calculate which positions to use for this layer
	-- Layer 1: positions 1-3, Layer 2: positions 4-6, Layer 3: positions 7-9
	local startIndex = ((layersCount - 1) * spikesPerLayer) + 1
	local endIndex = layersCount * spikesPerLayer
	local spikeCount = endIndex - startIndex + 1
	
	-- Create spike container
	local spikeContainer = Instance.new("Model")
	spikeContainer.Name = "Spikes" .. (isPlayerSide and "1" or "2")
	spikeContainer.Parent = battleScene
	
	-- Generate spike positions in a circular pattern around the platform
	local platformCFrame = platform.CFrame
	local platformSize = platform.Size
	local platformRadius = math.min(platformSize.X, platformSize.Z) * 0.4 -- Use 40% of platform size
	
	-- Generate all possible positions first (9 total positions)
	local allPositions: {CFrame} = {}
	for i = 1, totalSpikes do
		-- Use consistent base angle for each position to ensure they don't overlap
		local baseAngle = (i - 1) * (math.pi * 2 / totalSpikes)
		-- Add slight randomness per layer to make it look natural
		local angleVariation = math.random() * 0.2 - 0.1 -- -0.1 to 0.1 radians variation
		local angle = baseAngle + angleVariation
		
		-- Vary radius slightly but keep it consistent per position index
		local baseRadius = platformRadius * (0.7 + ((i % 3) * 0.1)) -- Vary by position
		local radius = baseRadius + (math.random() - 0.5) * 0.2 -- Small random variation
		
		local x = math.cos(angle) * radius
		local z = math.sin(angle) * radius
		local y = platformSize.Y / 2 + 0.25 -- Slightly above platform surface
		
		-- Random rotation for visual variety
		local randomRotation = CFrame.Angles(
			math.random() * math.pi * 0.3, -- Slight tilt
			math.random() * math.pi * 2, -- Full rotation
			math.random() * math.pi * 0.3 -- Slight tilt
		)
		
		local finalCFrame = platformCFrame * CFrame.new(x, y, z) * randomRotation
		table.insert(allPositions, finalCFrame)
	end
	
	-- Extract only the positions for this layer
	local spikePositions: {CFrame} = {}
	for i = startIndex, endIndex do
		table.insert(spikePositions, allPositions[i])
	end
	
	-- Spawn and animate each spike
	for i, landingCFrame in ipairs(spikePositions) do
		task.spawn(function()
			-- Stagger spawn times for cascading effect
			task.wait((i - 1) * 0.08)
			
			-- Create spike part
			local spike = Instance.new("Part")
			spike.Anchored = true
			spike.CanCollide = false
			spike.BrickColor = BrickColor.new(color or 'Smoky grey')
			spike.Reflectance = 0.1
			spike.Size = Vector3.new(1, 1, 1)
			spike.Transparency = 0
			
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.FileMesh
			mesh.MeshId = 'rbxassetid://109113400162452'
			mesh.Scale = Vector3.new(0.001,0.001,0.001)
			mesh.Parent = spike
			
			spike.Parent = spikeContainer
			
			-- Calculate start position (high above the landing position)
			local fallHeight = 12 + math.random() * 4 -- Random height between 12-16 studs
			local startPosition = landingCFrame.Position + Vector3.new(0, fallHeight, 0)
			
			-- Add slight horizontal offset for more natural fall
			local horizontalOffset = Vector3.new(
				(math.random() - 0.5) * 2,
				0,
				(math.random() - 0.5) * 2
			)
			startPosition = startPosition + horizontalOffset
			
			-- Set initial position
			local startCFrame = CFrame.new(startPosition) * (landingCFrame - landingCFrame.Position)
			spike.CFrame = startCFrame
			
			-- Animate falling with TweenService
			local fallDuration = 0.5 + math.random() * 0.2 -- Random duration between 0.5-0.7 seconds
			local tweenInfo = TweenInfo.new(
				fallDuration,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			)
			
			-- Create tween for position
			local positionTween = TweenService:Create(
				spike,
				tweenInfo,
				{CFrame = landingCFrame}
			)
			
			-- Add slight spin during fall
			local spinAmount = math.random(180, 360) -- Random spin between 180-360 degrees
			local endRotation = landingCFrame * CFrame.Angles(0, math.rad(spinAmount), 0)
			local spinTween = TweenService:Create(
				spike,
				tweenInfo,
				{CFrame = endRotation}
			)
			
			-- Play animation
			positionTween:Play()
			spinTween:Play()
			
			-- Wait for animation to complete
			positionTween.Completed:Wait()
		end)
	end
end

--[[
	Cleanup all active effects
]]
function CombatEffects:Cleanup()
	-- Stop any ongoing effects
	-- Clear any temporary effect instances
	
	-- Clean up all frozen ice cubes and connections
	for model, iceCube in pairs(self._frozenIceCubes) do
		-- Disconnect connection
		local connection = self._iceCubeConnections[model]
		if connection then
			connection:Disconnect()
		end
		
		-- Destroy ice cube
		if iceCube and iceCube.Parent then
			iceCube:Destroy()
		end
	end
	self._frozenIceCubes = {}
	self._iceCubeConnections = {}
	
	-- Clean up spikes from battle scene
	-- Find and destroy any spike containers in workspace (from active battle scenes)
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj:IsA("Model") and (obj.Name == "Spikes1" or obj.Name == "Spikes2") then
			-- Destroy all spikes in the container
			for _, child in ipairs(obj:GetChildren()) do
				if child:IsA("BasePart") then
					child:Destroy()
				end
			end
			obj:Destroy()
		end
	end
end

return CombatEffects

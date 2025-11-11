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
	if not defenderModel then return end
	local hrp = defenderModel:FindFirstChild("HumanoidRootPart")
	local primary: BasePart? = (hrp and hrp:IsA("BasePart")) and hrp or defenderModel.PrimaryPart
	if not primary then return end

	local effects = self._effects
	if not effects then return end
	local hitFolder = effects:FindFirstChild("HitFX")
	if not hitFolder then return end

	local name = "NormalHit"
	if category == "Super" then
		name = "SuperHit"
	elseif category == "Weak" or category == "NotVery" then
		name = "WeakHit"
	end

	local template = hitFolder:FindFirstChild(name)
	if template and template:IsA("BasePart") then
		self:_emitFromTemplate(template, primary.CFrame, workspace)
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
	
	-- Play attack animation on attacker with Hit marker support
	self._animationController:PlayAnimationWithHit(attackerModel, "Attack", function()
		-- Hit marker reached - trigger UI update and play damage animation
		if onHit then
			onHit()  -- Update UI with pending HP data
		end
		-- Note: Hit impact VFX is triggered in Damage step to respect effectiveness
		
		-- Play damage animation on defender only if the move hit
		if not skipDamaged then
			self._animationController:PlayAnimation(defenderModel, "Damaged", function()
				-- Return attacker to idle
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
		-- Attack animation completed (no hit marker)
		-- Return attacker to idle
		self._animationController:PlayIdleAnimation(attackerModel)
		
		if onComplete then
			onComplete()
		end
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

-- Plays a scan flash: green/blue on success, red on failure
function CombatEffects:PlayScanFlash(model: Model, success: boolean)
    if not model then
        return
    end
    -- Use a Highlight for smooth tweened flash instead of snapping part colors
    local highlight = Instance.new("Highlight")
    highlight.Adornee = model
    highlight.DepthMode = Enum.HighlightDepthMode.Occluded
    highlight.FillTransparency = 1
    highlight.OutlineTransparency = 1
    highlight.Parent = model
    -- Colors: success = blue, failure = red
    if success then
        highlight.FillColor = Color3.new(0.2, 0.6, 1)
        highlight.OutlineColor = Color3.new(0.1, 0.35, 0.8)
    else
        highlight.FillColor = Color3.new(1, 0.25, 0.25)
        highlight.OutlineColor = Color3.new(0.7, 0.1, 0.1)
    end
    local TweenService = game:GetService("TweenService")
    -- Fade in
    local inTween = TweenService:Create(highlight, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        FillTransparency = 0.2,
        OutlineTransparency = 0.2,
    })
    -- Fade out
    local outTween = TweenService:Create(highlight, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        FillTransparency = 1,
        OutlineTransparency = 1,
    })
    inTween:Play()
    inTween.Completed:Connect(function()
        outTween:Play()
    end)
    outTween.Completed:Connect(function()
        highlight:Destroy()
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
	
	-- TODO: Add visual crit effect (sparkles, flash, etc.)
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
	
	-- TODO: Add visual miss effect
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
	
	-- Play stat change sound
	if self._sfx then
		local soundName = stages > 0 and "StatUp" or "StatDown"
		local sound = self._sfx:FindFirstChild(soundName)
		if sound then
			sound:Play()
		end
	end
	
	-- TODO: Add visual stat change effect (arrows, particles, etc.)
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
	
	-- Play status sound
	if self._sfx then
		local sound = self._sfx:FindFirstChild("Status" .. status)
		if sound then
			sound:Play()
		end
	end
	
	-- TODO: Add visual status effect (icons, particles, etc.)
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
	
	-- TODO: Add visual heal effect (sparkles, glow, etc.)
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
	
	local primaryPart = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not primaryPart then
		return
	end
	
	-- TODO: Implement floating text billboard GUI
	-- This would create a BillboardGui above the creature showing damage/text
end

--[[
	Cleanup all active effects
]]
function CombatEffects:Cleanup()
	-- Stop any ongoing effects
	-- Clear any temporary effect instances
end

return CombatEffects

--!strict
-- Custom move effect handlers. Each handler should perform the full attack sequence
-- and MUST call onHit/onComplete following the same semantics as CombatEffects:PlayMoveAttack.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local MoveFunctions = {}

export type MoveContext = {
	attackerModel: Model,
	defenderModel: Model,
	onHit: (() -> ())?,
	onComplete: (() -> ())?,
	skipDamaged: boolean?,
	animationController: any, -- AnimationController module instance
}

-- Helper to play defender damaged + restore attacker idle, mirroring default behaviour
local function playDefenderDamagedAndIdle(ctx: MoveContext)
	if not ctx.animationController then
		if ctx.onComplete then ctx.onComplete() end
		return
	end

	if ctx.skipDamaged then
		-- Skip damaged animation on miss
		ctx.animationController:PlayIdleAnimation(ctx.attackerModel)
		if ctx.onComplete then ctx.onComplete() end
		return
	end

	ctx.animationController:PlayAnimation(ctx.defenderModel, "Damaged", function()
		ctx.animationController:PlayIdleAnimation(ctx.attackerModel)
		if ctx.onComplete then ctx.onComplete() end
	end)
end

-- Crunch: spawn move model, play its animation with Hit marker, align to defender, play SFX.
local function crunchHandler(ctx: MoveContext): boolean
	warn("[MoveFunctions][Crunch] handler start")
	if not ctx.attackerModel or not ctx.defenderModel then
		warn("[MoveFunctions][Crunch] Missing attacker/defender model")
		return false
	end

	local movesFolder = ReplicatedStorage:FindFirstChild("Assets")
	movesFolder = movesFolder and movesFolder:FindFirstChild("Models")
	movesFolder = movesFolder and movesFolder:FindFirstChild("Moves")
	if not movesFolder then
		warn("[MoveFunctions][Crunch] Moves folder not found at ReplicatedStorage.Assets.Models.Moves")
		return false
	end

	local crunchTemplate = movesFolder:FindFirstChild("Crunch")
	if not crunchTemplate or not crunchTemplate:IsA("Model") then
		warn("[MoveFunctions][Crunch] Crunch model not found under Moves")
		return false
	end

	local defenderRoot: BasePart? = ctx.defenderModel:FindFirstChild("HumanoidRootPart") or ctx.defenderModel.PrimaryPart
	if not defenderRoot then
		warn("[MoveFunctions][Crunch] Defender root not found")
		return false
	end

	-- Clone model and position it relative to defender
	local crunch = crunchTemplate:Clone()
	crunch.Parent = workspace
	if crunch.PrimaryPart then
		-- Place at defender, rotate 180° Y, then move back 5 studs
		local cf = defenderRoot.CFrame * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0, 5)
		crunch:SetPrimaryPartCFrame(cf)
	end

	-- Fade IN (non-root parts): set to 1 then tween to 0
	do
		local TweenService = game:GetService("TweenService")
		local tweenInfoIn = TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		for _, d in ipairs(crunch:GetDescendants()) do
			if d:IsA("BasePart") and d ~= crunch.PrimaryPart then
				d.Transparency = 1
				pcall(function()
					TweenService:Create(d, tweenInfoIn, { Transparency = 0 }):Play()
				end)
			end
		end
	end

	-- Ensure AnimationController & Animator exist
	local animController = crunch:FindFirstChildOfClass("AnimationController")
	if not animController then
		animController = Instance.new("AnimationController")
		animController.Parent = crunch
	end
	local animator = animController:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = animController
	end

	-- Find animation
	local anim = crunch:FindFirstChild("Animation", true)
	if not anim or not anim:IsA("Animation") then
		warn("[MoveFunctions][Crunch] Animation not found in Crunch model")
		crunch:Destroy()
		return false
	end

	-- Load and play animation
	local track = nil
	local ok, res = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok then track = res end
	if not track then
		warn("[MoveFunctions][Crunch] Failed to load animation")
		crunch:Destroy()
		return false
	end

	-- Play SFX at start
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://124298248035707"
	sound.Volume = 3.6
	sound.Parent = workspace
	sound:Play()

	-- Bind hit marker with fallback to ensure onHit always fires
	local hitFired = false
	local okHit, signal = pcall(function()
		return track:GetMarkerReachedSignal("Hit")
	end)
	if okHit and signal then
		signal:Connect(function()
			if not hitFired then
				hitFired = true
				warn("[MoveFunctions][Crunch] Hit marker reached, calling onHit")
				if ctx.onHit then ctx.onHit() end
			end
		end)
	end
	
	-- Fallback: trigger onHit after a delay if no marker was reached
	-- This ensures hit effects ALWAYS play even if the animation lacks a Hit marker
	task.delay(0.3, function()
		if not hitFired then
			hitFired = true
			warn("[MoveFunctions][Crunch] Fallback hit trigger (no marker), calling onHit")
			if ctx.onHit then ctx.onHit() end
		end
	end)

	-- Cleanup after animation
	track.Stopped:Connect(function()
		-- Tween all BaseParts to 0 transparency, then destroy
		local function fadeAndDestroy(model: Model)
			local parts = {}
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					table.insert(parts, d)
				end
			end
			if #parts == 0 then
				pcall(function() model:Destroy() end)
				return
			end
			local TweenService = game:GetService("TweenService")
			local tweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			for _, part in ipairs(parts) do
				local goal = { Transparency = 1 }
				pcall(function()
					local tween = TweenService:Create(part, tweenInfo, goal)
					tween:Play()
				end)
			end
			task.delay(tweenInfo.Time + 0.05, function()
				pcall(function() model:Destroy() end)
			end)
		end

		pcall(function()
			if crunch and crunch.Parent then
				fadeAndDestroy(crunch)
			end
		end)
		playDefenderDamagedAndIdle(ctx)
	end)

	track.Priority = Enum.AnimationPriority.Action4
	track:Play()

	warn("[MoveFunctions][Crunch] handler end (playing)")
	return true
end

-- Register handlers (case-insensitive)
MoveFunctions["Crunch"] = crunchHandler
MoveFunctions["crunch"] = crunchHandler

return MoveFunctions


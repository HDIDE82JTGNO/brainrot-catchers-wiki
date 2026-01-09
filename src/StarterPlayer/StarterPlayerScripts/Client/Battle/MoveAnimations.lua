--!strict
--[[
	MoveAnimations.lua
	Handles custom visual effects and animations for specific moves
	Creates programmatic effects to bring moves to life
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local MoveAnimations = {}

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

--[[
	Creates a slash effect (animated line that sweeps across)
	@param startCFrame Starting CFrame
	@param endCFrame Ending CFrame
	@param color Color3 for the slash
	@param duration Duration of animation
	@param width Width of the slash line
	@return Part The slash part (for cleanup)
]]
local function createSlashEffect(startCFrame: CFrame, endCFrame: CFrame, color: Color3, duration: number, width: number?): BasePart
	local slash = Instance.new("Part")
	slash.Name = "SlashEffect"
	slash.Anchored = true
	slash.CanCollide = false
	slash.Material = Enum.Material.Neon
	slash.Color = color
	slash.Transparency = 0.3
	
	local length = (endCFrame.Position - startCFrame.Position).Magnitude
	local w = width or 0.2
	slash.Size = Vector3.new(w, w, length)
	slash.CFrame = CFrame.lookAt(startCFrame.Position, endCFrame.Position) * CFrame.new(0, 0, -length/2)
	slash.Parent = workspace
	
	-- Animate: scale up, fade out, then destroy
	local startSize = Vector3.new(w, w, 0.1)
	local endSize = Vector3.new(w * 2, w * 2, length * 1.2)
	
	slash.Size = startSize
	slash.Transparency = 0.3
	
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local sizeTween = TweenService:Create(slash, tweenInfo, {
		Size = endSize,
		Transparency = 1
	})
	
	sizeTween:Play()
	sizeTween.Completed:Connect(function()
		if slash and slash.Parent then
			slash:Destroy()
		end
	end)
	
	return slash
end

--[[
	Creates a particle burst effect
	@param position Vector3 position
	@param color Color3 for particles
	@param count Number of particles
	@param duration Duration of effect
	@return Part The part containing the attachment (for cleanup)
]]
local function createParticleBurst(position: Vector3, color: Color3, count: number, duration: number): BasePart
	local part = Instance.new("Part")
	part.Name = "ParticleBurst"
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = CFrame.new(position)
	part.Parent = workspace
	
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	
	local emitter = Instance.new("ParticleEmitter")
	emitter.Parent = attachment
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0)
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1)
	})
	emitter.Speed = NumberRange.new(5, 10)
	emitter.Lifetime = NumberRange.new(0.3, 0.6)
	emitter.Rate = 0
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.SpreadAngle = Vector2.new(45, 45)
	
	emitter:Emit(count)
	
	task.delay(duration, function()
		if part and part.Parent then
			part:Destroy()
		end
	end)
	
	return part
end

--[[
	Creates a projectile effect
	@param startCFrame Starting CFrame
	@param endCFrame Ending CFrame
	@param color Color3
	@param speed Speed of projectile
	@param onReach Callback when projectile reaches target
	@return Part The projectile part
]]
local function createProjectile(startCFrame: CFrame, endCFrame: CFrame, color: Color3, speed: number, onReach: (() -> ())?): BasePart
	local projectile = Instance.new("Part")
	projectile.Name = "Projectile"
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.Material = Enum.Material.Neon
	projectile.Color = color
	projectile.Size = Vector3.new(0.5, 0.5, 0.5)
	projectile.Shape = Enum.PartType.Ball
	projectile.CFrame = startCFrame
	projectile.Parent = workspace
	
	-- Add glow
	local pointLight = Instance.new("PointLight")
	pointLight.Color = color
	pointLight.Brightness = 2
	pointLight.Range = 10
	pointLight.Parent = projectile
	
	local distance = (endCFrame.Position - startCFrame.Position).Magnitude
	local duration = distance / speed
	
	local tween = TweenService:Create(projectile, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		CFrame = endCFrame
	})
	
	tween:Play()
	tween.Completed:Connect(function()
		if onReach then
			onReach()
		end
		if projectile and projectile.Parent then
			projectile:Destroy()
		end
	end)
	
	return projectile
end

--[[
	Uppercut: Strong upward strike line effect
]]
local function uppercutHandler(ctx: MoveContext): boolean
	if not ctx.attackerModel or not ctx.defenderModel then
		return false
	end
	
	local attackerRoot = ctx.attackerModel:FindFirstChild("HumanoidRootPart") or ctx.attackerModel.PrimaryPart
	local defenderRoot = ctx.defenderModel:FindFirstChild("HumanoidRootPart") or ctx.defenderModel.PrimaryPart
	
	if not attackerRoot or not defenderRoot then
		return false
	end
	
	-- Play attack animation
	if ctx.animationController then
		ctx.animationController:PlayAnimationWithHit(ctx.attackerModel, "Attack", function()
			-- Hit marker reached - create uppercut effect
			local defenderPos = defenderRoot.Position
			local startPos = defenderPos + Vector3.new(0, -2, 0) -- Start low
			local endPos = defenderPos + Vector3.new(0, 3, 0) -- End high
			
			local startCFrame = CFrame.new(startPos) * CFrame.Angles(math.rad(-45), 0, 0)
			local endCFrame = CFrame.new(endPos) * CFrame.Angles(math.rad(-45), 0, 0)
			
			-- Create strong upward slash
			createSlashEffect(startCFrame, endCFrame, Color3.new(1, 0.8, 0.2), 0.3, 0.4)
			
			-- Add impact particles
			createParticleBurst(endPos, Color3.new(1, 0.9, 0.5), 15, 0.5)
			
			if ctx.onHit then
				ctx.onHit()
			end
			
			playDefenderDamagedAndIdle(ctx)
		end, function()
			-- Animation complete fallback
			if ctx.onComplete then
				ctx.onComplete()
			end
		end)
	else
		-- Fallback if no animation controller
		local defenderPos = defenderRoot.Position
		local startPos = defenderPos + Vector3.new(0, -2, 0)
		local endPos = defenderPos + Vector3.new(0, 3, 0)
		
		local startCFrame = CFrame.new(startPos) * CFrame.Angles(math.rad(-45), 0, 0)
		local endCFrame = CFrame.new(endPos) * CFrame.Angles(math.rad(-45), 0, 0)
		
		createSlashEffect(startCFrame, endCFrame, Color3.new(1, 0.8, 0.2), 0.3, 0.4)
		createParticleBurst(endPos, Color3.new(1, 0.9, 0.5), 15, 0.5)
		
		if ctx.onHit then
			task.delay(0.2, ctx.onHit)
		end
		
		playDefenderDamagedAndIdle(ctx)
	end
	
	return true
end

--[[
	Tackle: Forward charge movement
	IMPORTANT: Must anchor HRP when moving creatures
]]
local function tackleHandler(ctx: MoveContext): boolean
	if not ctx.attackerModel or not ctx.defenderModel then
		return false
	end
	
	local attackerRoot = ctx.attackerModel:FindFirstChild("HumanoidRootPart") or ctx.attackerModel.PrimaryPart
	local defenderRoot = ctx.defenderModel:FindFirstChild("HumanoidRootPart") or ctx.defenderModel.PrimaryPart
	
	if not attackerRoot or not defenderRoot then
		return false
	end
	
	-- Store original state
	local originalCFrame = attackerRoot.CFrame
	local originalAnchored = attackerRoot.Anchored
	
	-- Anchor the root part for movement
	attackerRoot.Anchored = true
	
	-- Use the creature's LookVector to move forward in the direction it's facing
	local chargeDistance = 4 -- Max charge distance
	local newPosition = originalCFrame.Position + originalCFrame.LookVector * chargeDistance
	
	-- Charge forward using LookVector
	local chargeTween = TweenService:Create(
		attackerRoot,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{CFrame = CFrame.new(newPosition, newPosition + originalCFrame.LookVector)}
	)
	
	chargeTween:Play()
	chargeTween.Completed:Connect(function()
		-- Impact effect
		if ctx.onHit then
			ctx.onHit()
		end
		
		-- Create impact particles
		local impactPos = attackerRoot.Position
		createParticleBurst(impactPos, Color3.new(0.9, 0.9, 0.9), 10, 0.4)
		
		-- Return to original position
		local returnTween = TweenService:Create(
			attackerRoot,
			TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{CFrame = originalCFrame}
		)
		
		returnTween:Play()
		returnTween.Completed:Connect(function()
			-- Restore original anchored state
			attackerRoot.Anchored = originalAnchored
			
			playDefenderDamagedAndIdle(ctx)
		end)
	end)
	
	return true
end

--[[
	Scratch: Quick slash effect
]]
local function scratchHandler(ctx: MoveContext): boolean
	if not ctx.attackerModel or not ctx.defenderModel then
		return false
	end
	
	local attackerRoot = ctx.attackerModel:FindFirstChild("HumanoidRootPart") or ctx.attackerModel.PrimaryPart
	local defenderRoot = ctx.defenderModel:FindFirstChild("HumanoidRootPart") or ctx.defenderModel.PrimaryPart
	
	if not attackerRoot or not defenderRoot then
		return false
	end
	
	if ctx.animationController then
		ctx.animationController:PlayAnimationWithHit(ctx.attackerModel, "Attack", function()
			-- Create slash effect
			local defenderPos = defenderRoot.Position
			local attackerPos = attackerRoot.Position
			local direction = (defenderPos - attackerPos).Unit
			
			local startCFrame = CFrame.new(defenderPos - direction * 1.5)
			local endCFrame = CFrame.new(defenderPos + direction * 1.5)
			
			createSlashEffect(startCFrame, endCFrame, Color3.new(1, 1, 1), 0.25, 0.2)
			createParticleBurst(defenderPos, Color3.new(0.9, 0.9, 0.9), 8, 0.3)
			
			if ctx.onHit then
				ctx.onHit()
			end
			
			playDefenderDamagedAndIdle(ctx)
		end)
	else
		-- Fallback
		local defenderPos = defenderRoot.Position
		local attackerPos = attackerRoot.Position
		local direction = (defenderPos - attackerPos).Unit
		
		local startCFrame = CFrame.new(defenderPos - direction * 1.5)
		local endCFrame = CFrame.new(defenderPos + direction * 1.5)
		
		createSlashEffect(startCFrame, endCFrame, Color3.new(1, 1, 1), 0.25, 0.2)
		createParticleBurst(defenderPos, Color3.new(0.9, 0.9, 0.9), 8, 0.3)
		
		if ctx.onHit then
			task.delay(0.15, ctx.onHit)
		end
		
		playDefenderDamagedAndIdle(ctx)
	end
	
	return true
end

--[[
	Fire move handler (Grease Jab, Searing Splat, Flare Blitz)
]]
local function fireMoveHandler(ctx: MoveContext, moveName: string): boolean
	if not ctx.attackerModel or not ctx.defenderModel then
		return false
	end
	
	local attackerRoot = ctx.attackerModel:FindFirstChild("HumanoidRootPart") or ctx.attackerModel.PrimaryPart
	local defenderRoot = ctx.defenderModel:FindFirstChild("HumanoidRootPart") or ctx.defenderModel.PrimaryPart
	
	if not attackerRoot or not defenderRoot then
		return false
	end
	
	local defenderPos = defenderRoot.Position
	
	if ctx.animationController then
		ctx.animationController:PlayAnimationWithHit(ctx.attackerModel, "Attack", function()
			-- Create fire particles
			local fireColor = Color3.new(1, 0.3, 0)
			createParticleBurst(defenderPos, fireColor, 20, 0.6)
			
			-- Create flame effect (multiple bursts)
			for i = 1, 3 do
				task.delay(i * 0.1, function()
					local offset = Vector3.new(
						(math.random() - 0.5) * 2,
						math.random() * 1.5,
						(math.random() - 0.5) * 2
					)
					createParticleBurst(defenderPos + offset, fireColor, 10, 0.4)
				end)
			end
			
			if ctx.onHit then
				ctx.onHit()
			end
			
			playDefenderDamagedAndIdle(ctx)
		end)
	else
		-- Fallback
		local fireColor = Color3.new(1, 0.3, 0)
		createParticleBurst(defenderPos, fireColor, 20, 0.6)
		
		for i = 1, 3 do
			task.delay(i * 0.1, function()
				local offset = Vector3.new(
					(math.random() - 0.5) * 2,
					math.random() * 1.5,
					(math.random() - 0.5) * 2
				)
				createParticleBurst(defenderPos + offset, fireColor, 10, 0.4)
			end)
		end
		
		if ctx.onHit then
			task.delay(0.2, ctx.onHit)
		end
		
		playDefenderDamagedAndIdle(ctx)
	end
	
	return true
end

--[[
	Electric move handler (Static Peck, Thunder Burst, Volt Tackle)
]]
local function electricMoveHandler(ctx: MoveContext, moveName: string): boolean
	if not ctx.attackerModel or not ctx.defenderModel then
		return false
	end
	
	local attackerRoot = ctx.attackerModel:FindFirstChild("HumanoidRootPart") or ctx.attackerModel.PrimaryPart
	local defenderRoot = ctx.defenderModel:FindFirstChild("HumanoidRootPart") or ctx.defenderModel.PrimaryPart
	
	if not attackerRoot or not defenderRoot then
		return false
	end
	
	local attackerPos = attackerRoot.Position
	local defenderPos = defenderRoot.Position
	
	if ctx.animationController then
		ctx.animationController:PlayAnimationWithHit(ctx.attackerModel, "Attack", function()
			-- Create lightning bolt effect (zigzag line)
			local electricColor = Color3.new(0.5, 0.8, 1)
			
			-- Create multiple lightning segments
			local segments = 5
			local segmentLength = (defenderPos - attackerPos).Magnitude / segments
			local direction = (defenderPos - attackerPos).Unit
			
			for i = 1, segments do
				local startSeg = attackerPos + direction * (i - 1) * segmentLength
				local endSeg = attackerPos + direction * i * segmentLength
				
				-- Add random offset for zigzag
				local offset = Vector3.new(
					(math.random() - 0.5) * 0.5,
					(math.random() - 0.5) * 0.5,
					(math.random() - 0.5) * 0.5
				)
				
				task.delay(i * 0.05, function()
					local startCFrame = CFrame.new(startSeg + offset)
					local endCFrame = CFrame.new(endSeg + offset)
					createSlashEffect(startCFrame, endCFrame, electricColor, 0.15, 0.15)
				end)
			end
			
			-- Electric burst at impact
			createParticleBurst(defenderPos, electricColor, 25, 0.5)
			
			if ctx.onHit then
				ctx.onHit()
			end
			
			playDefenderDamagedAndIdle(ctx)
		end)
	else
		-- Fallback
		local electricColor = Color3.new(0.5, 0.8, 1)
		local segments = 5
		local segmentLength = (defenderPos - attackerPos).Magnitude / segments
		local direction = (defenderPos - attackerPos).Unit
		
		for i = 1, segments do
			local startSeg = attackerPos + direction * (i - 1) * segmentLength
			local endSeg = attackerPos + direction * i * segmentLength
			local offset = Vector3.new(
				(math.random() - 0.5) * 0.5,
				(math.random() - 0.5) * 0.5,
				(math.random() - 0.5) * 0.5
			)
			
			task.delay(i * 0.05, function()
				local startCFrame = CFrame.new(startSeg + offset)
				local endCFrame = CFrame.new(endSeg + offset)
				createSlashEffect(startCFrame, endCFrame, electricColor, 0.15, 0.15)
			end)
		end
		
		createParticleBurst(defenderPos, electricColor, 25, 0.5)
		
		if ctx.onHit then
			task.delay(0.25, ctx.onHit)
		end
		
		playDefenderDamagedAndIdle(ctx)
	end
	
	return true
end

--[[
	Water move handler (Water Jet, Aqua Slash, Hydro Burst)
]]
local function waterMoveHandler(ctx: MoveContext, moveName: string): boolean
	if not ctx.attackerModel or not ctx.defenderModel then
		return false
	end
	
	local attackerRoot = ctx.attackerModel:FindFirstChild("HumanoidRootPart") or ctx.attackerModel.PrimaryPart
	local defenderRoot = ctx.defenderModel:FindFirstChild("HumanoidRootPart") or ctx.defenderModel.PrimaryPart
	
	if not attackerRoot or not defenderRoot then
		return false
	end
	
	local attackerPos = attackerRoot.Position
	local defenderPos = defenderRoot.Position
	local waterColor = Color3.new(0.2, 0.6, 1)
	
	if moveName == "Water Jet" or moveName == "water jet" then
		-- Jet stream effect
		if ctx.animationController then
			ctx.animationController:PlayAnimationWithHit(ctx.attackerModel, "Attack", function()
				local startCFrame = CFrame.new(attackerPos)
				local endCFrame = CFrame.new(defenderPos)
				createProjectile(startCFrame, endCFrame, waterColor, 30, function()
					createParticleBurst(defenderPos, waterColor, 15, 0.4)
					if ctx.onHit then
						ctx.onHit()
					end
					playDefenderDamagedAndIdle(ctx)
				end)
			end)
		else
			local startCFrame = CFrame.new(attackerPos)
			local endCFrame = CFrame.new(defenderPos)
			createProjectile(startCFrame, endCFrame, waterColor, 30, function()
				createParticleBurst(defenderPos, waterColor, 15, 0.4)
				if ctx.onHit then
					ctx.onHit()
				end
				playDefenderDamagedAndIdle(ctx)
			end)
		end
	else
		-- Slash or burst effect
		if ctx.animationController then
			ctx.animationController:PlayAnimationWithHit(ctx.attackerModel, "Attack", function()
				local direction = (defenderPos - attackerPos).Unit
				local startCFrame = CFrame.new(defenderPos - direction * 1.5)
				local endCFrame = CFrame.new(defenderPos + direction * 1.5)
				
				createSlashEffect(startCFrame, endCFrame, waterColor, 0.3, 0.3)
				createParticleBurst(defenderPos, waterColor, 20, 0.5)
				
				if ctx.onHit then
					ctx.onHit()
				end
				
				playDefenderDamagedAndIdle(ctx)
			end)
		else
			local direction = (defenderPos - attackerPos).Unit
			local startCFrame = CFrame.new(defenderPos - direction * 1.5)
			local endCFrame = CFrame.new(defenderPos + direction * 1.5)
			
			createSlashEffect(startCFrame, endCFrame, waterColor, 0.3, 0.3)
			createParticleBurst(defenderPos, waterColor, 20, 0.5)
			
			if ctx.onHit then
				task.delay(0.2, ctx.onHit)
			end
			
			playDefenderDamagedAndIdle(ctx)
		end
	end
	
	return true
end

--[[
	Ground move handler (Earthquake, Sand Storm)
]]
local function groundMoveHandler(ctx: MoveContext, moveName: string): boolean
	if not ctx.attackerModel or not ctx.defenderModel then
		return false
	end
	
	local defenderRoot = ctx.defenderModel:FindFirstChild("HumanoidRootPart") or ctx.defenderModel.PrimaryPart
	
	if not defenderRoot then
		return false
	end
	
	local defenderPos = defenderRoot.Position
	local groundColor = Color3.new(0.6, 0.4, 0.2)
	
	if ctx.animationController then
		ctx.animationController:PlayAnimationWithHit(ctx.attackerModel, "Attack", function()
			-- Create ground shake effect (particles from ground)
			for i = 1, 5 do
				task.delay(i * 0.1, function()
					local offset = Vector3.new(
						(math.random() - 0.5) * 3,
						0,
						(math.random() - 0.5) * 3
					)
					createParticleBurst(defenderPos + offset, groundColor, 12, 0.5)
				end)
			end
			
			if ctx.onHit then
				ctx.onHit()
			end
			
			playDefenderDamagedAndIdle(ctx)
		end)
	else
		-- Fallback
		for i = 1, 5 do
			task.delay(i * 0.1, function()
				local offset = Vector3.new(
					(math.random() - 0.5) * 3,
					0,
					(math.random() - 0.5) * 3
				)
				createParticleBurst(defenderPos + offset, groundColor, 12, 0.5)
			end)
		end
		
		if ctx.onHit then
			task.delay(0.3, ctx.onHit)
		end
		
		playDefenderDamagedAndIdle(ctx)
	end
	
	return true
end

-- Register move handlers
MoveAnimations["Uppercut"] = uppercutHandler
MoveAnimations["uppercut"] = uppercutHandler
MoveAnimations["Tackle"] = tackleHandler
MoveAnimations["tackle"] = tackleHandler
MoveAnimations["Scratch"] = scratchHandler
MoveAnimations["scratch"] = scratchHandler

-- Fire moves
MoveAnimations["Grease Jab"] = function(ctx) return fireMoveHandler(ctx, "Grease Jab") end
MoveAnimations["grease jab"] = function(ctx) return fireMoveHandler(ctx, "Grease Jab") end
MoveAnimations["Searing Splat"] = function(ctx) return fireMoveHandler(ctx, "Searing Splat") end
MoveAnimations["searing splat"] = function(ctx) return fireMoveHandler(ctx, "Searing Splat") end
MoveAnimations["Flare Blitz"] = function(ctx) return fireMoveHandler(ctx, "Flare Blitz") end
MoveAnimations["flare blitz"] = function(ctx) return fireMoveHandler(ctx, "Flare Blitz") end

-- Electric moves
MoveAnimations["Static Peck"] = function(ctx) return electricMoveHandler(ctx, "Static Peck") end
MoveAnimations["static peck"] = function(ctx) return electricMoveHandler(ctx, "Static Peck") end
MoveAnimations["Thunder Burst"] = function(ctx) return electricMoveHandler(ctx, "Thunder Burst") end
MoveAnimations["thunder burst"] = function(ctx) return electricMoveHandler(ctx, "Thunder Burst") end
MoveAnimations["Volt Tackle"] = function(ctx) return electricMoveHandler(ctx, "Volt Tackle") end
MoveAnimations["volt tackle"] = function(ctx) return electricMoveHandler(ctx, "Volt Tackle") end

-- Water moves
MoveAnimations["Water Jet"] = function(ctx) return waterMoveHandler(ctx, "Water Jet") end
MoveAnimations["water jet"] = function(ctx) return waterMoveHandler(ctx, "Water Jet") end
MoveAnimations["Aqua Slash"] = function(ctx) return waterMoveHandler(ctx, "Aqua Slash") end
MoveAnimations["aqua slash"] = function(ctx) return waterMoveHandler(ctx, "Aqua Slash") end
MoveAnimations["Hydro Burst"] = function(ctx) return waterMoveHandler(ctx, "Hydro Burst") end
MoveAnimations["hydro burst"] = function(ctx) return waterMoveHandler(ctx, "Hydro Burst") end

-- Ground moves
MoveAnimations["Earthquake"] = function(ctx) return groundMoveHandler(ctx, "Earthquake") end
MoveAnimations["earthquake"] = function(ctx) return groundMoveHandler(ctx, "Earthquake") end
MoveAnimations["Sand Storm"] = function(ctx) return groundMoveHandler(ctx, "Sand Storm") end
MoveAnimations["sand storm"] = function(ctx) return groundMoveHandler(ctx, "Sand Storm") end

--[[
	Grass move handler (Leaf Slash, Vine Whip)
]]
local function grassMoveHandler(ctx: MoveContext, moveName: string): boolean
	if not ctx.attackerModel or not ctx.defenderModel then
		return false
	end
	
	local attackerRoot = ctx.attackerModel:FindFirstChild("HumanoidRootPart") or ctx.attackerModel.PrimaryPart
	local defenderRoot = ctx.defenderModel:FindFirstChild("HumanoidRootPart") or ctx.defenderModel.PrimaryPart
	
	if not attackerRoot or not defenderRoot then
		return false
	end
	
	local defenderPos = defenderRoot.Position
	local attackerPos = attackerRoot.Position
	local grassColor = Color3.new(0.2, 0.8, 0.2)
	
	if ctx.animationController then
		ctx.animationController:PlayAnimationWithHit(ctx.attackerModel, "Attack", function()
			local direction = (defenderPos - attackerPos).Unit
			local startCFrame = CFrame.new(defenderPos - direction * 1.5)
			local endCFrame = CFrame.new(defenderPos + direction * 1.5)
			
			-- Create leaf slash effect
			createSlashEffect(startCFrame, endCFrame, grassColor, 0.3, 0.25)
			createParticleBurst(defenderPos, grassColor, 12, 0.4)
			
			if ctx.onHit then
				ctx.onHit()
			end
			
			playDefenderDamagedAndIdle(ctx)
		end)
	else
		local direction = (defenderPos - attackerPos).Unit
		local startCFrame = CFrame.new(defenderPos - direction * 1.5)
		local endCFrame = CFrame.new(defenderPos + direction * 1.5)
		
		createSlashEffect(startCFrame, endCFrame, grassColor, 0.3, 0.25)
		createParticleBurst(defenderPos, grassColor, 12, 0.4)
		
		if ctx.onHit then
			task.delay(0.2, ctx.onHit)
		end
		
		playDefenderDamagedAndIdle(ctx)
	end
	
	return true
end

--[[
	Dark move handler (Bite, Crunch)
]]
local function darkMoveHandler(ctx: MoveContext, moveName: string): boolean
	if not ctx.attackerModel or not ctx.defenderModel then
		return false
	end
	
	local attackerRoot = ctx.attackerModel:FindFirstChild("HumanoidRootPart") or ctx.attackerModel.PrimaryPart
	local defenderRoot = ctx.defenderModel:FindFirstChild("HumanoidRootPart") or ctx.defenderModel.PrimaryPart
	
	if not attackerRoot or not defenderRoot then
		return false
	end
	
	local defenderPos = defenderRoot.Position
	local darkColor = Color3.new(0.2, 0.1, 0.3)
	
	if ctx.animationController then
		ctx.animationController:PlayAnimationWithHit(ctx.attackerModel, "Attack", function()
			-- Dark energy burst
			createParticleBurst(defenderPos, darkColor, 18, 0.5)
			
			-- Add dark energy swirls
			for i = 1, 3 do
				task.delay(i * 0.1, function()
					local offset = Vector3.new(
						(math.random() - 0.5) * 1.5,
						(math.random() - 0.5) * 1.5,
						(math.random() - 0.5) * 1.5
					)
					createParticleBurst(defenderPos + offset, darkColor, 8, 0.3)
				end)
			end
			
			if ctx.onHit then
				ctx.onHit()
			end
			
			playDefenderDamagedAndIdle(ctx)
		end)
	else
		createParticleBurst(defenderPos, darkColor, 18, 0.5)
		
		for i = 1, 3 do
			task.delay(i * 0.1, function()
				local offset = Vector3.new(
					(math.random() - 0.5) * 1.5,
					(math.random() - 0.5) * 1.5,
					(math.random() - 0.5) * 1.5
				)
				createParticleBurst(defenderPos + offset, darkColor, 8, 0.3)
			end)
		end
		
		if ctx.onHit then
			task.delay(0.2, ctx.onHit)
		end
		
		playDefenderDamagedAndIdle(ctx)
	end
	
	return true
end

--[[
	Psychic move handler (Psychic Pulse, Mind Slam)
]]
local function psychicMoveHandler(ctx: MoveContext, moveName: string): boolean
	if not ctx.attackerModel or not ctx.defenderModel then
		return false
	end
	
	local attackerRoot = ctx.attackerModel:FindFirstChild("HumanoidRootPart") or ctx.attackerModel.PrimaryPart
	local defenderRoot = ctx.defenderModel:FindFirstChild("HumanoidRootPart") or ctx.defenderModel.PrimaryPart
	
	if not attackerRoot or not defenderRoot then
		return false
	end
	
	local attackerPos = attackerRoot.Position
	local defenderPos = defenderRoot.Position
	local psychicColor = Color3.new(0.8, 0.2, 0.9)
	
	if ctx.animationController then
		ctx.animationController:PlayAnimationWithHit(ctx.attackerModel, "Attack", function()
			-- Create psychic wave effect
			local startCFrame = CFrame.new(attackerPos)
			local endCFrame = CFrame.new(defenderPos)
			createProjectile(startCFrame, endCFrame, psychicColor, 25, function()
				createParticleBurst(defenderPos, psychicColor, 20, 0.5)
			end)
			
			if ctx.onHit then
				task.delay(0.2, ctx.onHit)
			end
			
			playDefenderDamagedAndIdle(ctx)
		end)
	else
		local startCFrame = CFrame.new(attackerPos)
		local endCFrame = CFrame.new(defenderPos)
		createProjectile(startCFrame, endCFrame, psychicColor, 25, function()
			createParticleBurst(defenderPos, psychicColor, 20, 0.5)
		end)
		
		if ctx.onHit then
			task.delay(0.3, ctx.onHit)
		end
		
		playDefenderDamagedAndIdle(ctx)
	end
	
	return true
end

--[[
	Fairy move handler (Dazzle Beam, Fairy Strike)
]]
local function fairyMoveHandler(ctx: MoveContext, moveName: string): boolean
	if not ctx.attackerModel or not ctx.defenderModel then
		return false
	end
	
	local attackerRoot = ctx.attackerModel:FindFirstChild("HumanoidRootPart") or ctx.attackerModel.PrimaryPart
	local defenderRoot = ctx.defenderModel:FindFirstChild("HumanoidRootPart") or ctx.defenderModel.PrimaryPart
	
	if not attackerRoot or not defenderRoot then
		return false
	end
	
	local attackerPos = attackerRoot.Position
	local defenderPos = defenderRoot.Position
	local fairyColor = Color3.new(1, 0.7, 0.9)
	
	if ctx.animationController then
		ctx.animationController:PlayAnimationWithHit(ctx.attackerModel, "Attack", function()
			if moveName == "Dazzle Beam" or moveName == "dazzle beam" then
				-- Beam effect
				local startCFrame = CFrame.new(attackerPos)
				local endCFrame = CFrame.new(defenderPos)
				createProjectile(startCFrame, endCFrame, fairyColor, 35, function()
					createParticleBurst(defenderPos, fairyColor, 25, 0.6)
				end)
			else
				-- Strike effect
				local direction = (defenderPos - attackerPos).Unit
				local startCFrame = CFrame.new(defenderPos - direction * 1.5)
				local endCFrame = CFrame.new(defenderPos + direction * 1.5)
				createSlashEffect(startCFrame, endCFrame, fairyColor, 0.3, 0.3)
				createParticleBurst(defenderPos, fairyColor, 15, 0.5)
			end
			
			if ctx.onHit then
				task.delay(0.2, ctx.onHit)
			end
			
			playDefenderDamagedAndIdle(ctx)
		end)
	else
		if moveName == "Dazzle Beam" or moveName == "dazzle beam" then
			local startCFrame = CFrame.new(attackerPos)
			local endCFrame = CFrame.new(defenderPos)
			createProjectile(startCFrame, endCFrame, fairyColor, 35, function()
				createParticleBurst(defenderPos, fairyColor, 25, 0.6)
			end)
		else
			local direction = (defenderPos - attackerPos).Unit
			local startCFrame = CFrame.new(defenderPos - direction * 1.5)
			local endCFrame = CFrame.new(defenderPos + direction * 1.5)
			createSlashEffect(startCFrame, endCFrame, fairyColor, 0.3, 0.3)
			createParticleBurst(defenderPos, fairyColor, 15, 0.5)
		end
		
		if ctx.onHit then
			task.delay(0.3, ctx.onHit)
		end
		
		playDefenderDamagedAndIdle(ctx)
	end
	
	return true
end

--[[
	Poison move handler (Ooze Shot, Sludge Puff, Toxic Wave, etc.)
]]
local function poisonMoveHandler(ctx: MoveContext, moveName: string): boolean
	if not ctx.attackerModel or not ctx.defenderModel then
		return false
	end
	
	local attackerRoot = ctx.attackerModel:FindFirstChild("HumanoidRootPart") or ctx.attackerModel.PrimaryPart
	local defenderRoot = ctx.defenderModel:FindFirstChild("HumanoidRootPart") or ctx.defenderModel.PrimaryPart
	
	if not attackerRoot or not defenderRoot then
		return false
	end
	
	local attackerPos = attackerRoot.Position
	local defenderPos = defenderRoot.Position
	local poisonColor = Color3.new(0.5, 0.2, 0.8)
	
	if ctx.animationController then
		ctx.animationController:PlayAnimationWithHit(ctx.attackerModel, "Attack", function()
			if moveName == "Ooze Shot" or moveName == "ooze shot" or moveName == "Toxic Wave" or moveName == "toxic wave" then
				-- Projectile effect
				local startCFrame = CFrame.new(attackerPos)
				local endCFrame = CFrame.new(defenderPos)
				createProjectile(startCFrame, endCFrame, poisonColor, 20, function()
					createParticleBurst(defenderPos, poisonColor, 18, 0.6)
				end)
			else
				-- Burst effect
				createParticleBurst(defenderPos, poisonColor, 20, 0.5)
				for i = 1, 3 do
					task.delay(i * 0.1, function()
						local offset = Vector3.new(
							(math.random() - 0.5) * 1.5,
							(math.random() - 0.5) * 0.5,
							(math.random() - 0.5) * 1.5
						)
						createParticleBurst(defenderPos + offset, poisonColor, 8, 0.4)
					end)
				end
			end
			
			if ctx.onHit then
				task.delay(0.2, ctx.onHit)
			end
			
			playDefenderDamagedAndIdle(ctx)
		end)
	else
		if moveName == "Ooze Shot" or moveName == "ooze shot" or moveName == "Toxic Wave" or moveName == "toxic wave" then
			local startCFrame = CFrame.new(attackerPos)
			local endCFrame = CFrame.new(defenderPos)
			createProjectile(startCFrame, endCFrame, poisonColor, 20, function()
				createParticleBurst(defenderPos, poisonColor, 18, 0.6)
			end)
		else
			createParticleBurst(defenderPos, poisonColor, 20, 0.5)
			for i = 1, 3 do
				task.delay(i * 0.1, function()
					local offset = Vector3.new(
						(math.random() - 0.5) * 1.5,
						(math.random() - 0.5) * 0.5,
						(math.random() - 0.5) * 1.5
					)
					createParticleBurst(defenderPos + offset, poisonColor, 8, 0.4)
				end)
			end
		end
		
		if ctx.onHit then
			task.delay(0.3, ctx.onHit)
		end
		
		playDefenderDamagedAndIdle(ctx)
	end
	
	return true
end

--[[
	Flying move handler (Peck, Dive Bomb, Brave Bird, etc.)
]]
local function flyingMoveHandler(ctx: MoveContext, moveName: string): boolean
	if not ctx.attackerModel or not ctx.defenderModel then
		return false
	end
	
	local attackerRoot = ctx.attackerModel:FindFirstChild("HumanoidRootPart") or ctx.attackerModel.PrimaryPart
	local defenderRoot = ctx.defenderModel:FindFirstChild("HumanoidRootPart") or ctx.defenderModel.PrimaryPart
	
	if not attackerRoot or not defenderRoot then
		return false
	end
	
	local attackerPos = attackerRoot.Position
	local defenderPos = defenderRoot.Position
	local flyingColor = Color3.new(0.7, 0.8, 1)
	
	-- Store original state for dive moves
	local originalCFrame = attackerRoot.CFrame
	local originalAnchored = attackerRoot.Anchored
	
	if moveName == "Dive Bomb" or moveName == "dive bomb" or moveName == "Brave Bird" or moveName == "brave bird" then
		-- Dive from above effect
		attackerRoot.Anchored = true
		
		if ctx.animationController then
			ctx.animationController:PlayAnimationWithHit(ctx.attackerModel, "Attack", function()
				-- Move up high, preserving LookVector
				local highPosition = originalCFrame.Position + Vector3.new(0, 5, 0)
				local highCFrame = CFrame.new(highPosition, highPosition + originalCFrame.LookVector)
				local diveTween = TweenService:Create(
					attackerRoot,
					TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{CFrame = highCFrame}
				)
				
				diveTween:Play()
				diveTween.Completed:Connect(function()
					-- Dive down towards defender, preserving LookVector
					local targetPosition = defenderPos + Vector3.new(0, 1, 0)
					local targetCFrame = CFrame.new(targetPosition, targetPosition + originalCFrame.LookVector)
					local downTween = TweenService:Create(
						attackerRoot,
						TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
						{CFrame = targetCFrame}
					)
					
					downTween:Play()
					downTween.Completed:Connect(function()
						createParticleBurst(defenderPos, flyingColor, 20, 0.5)
						
						if ctx.onHit then
							ctx.onHit()
						end
						
						-- Return to original position
						local returnTween = TweenService:Create(
							attackerRoot,
							TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
							{CFrame = originalCFrame}
						)
						
						returnTween:Play()
						returnTween.Completed:Connect(function()
							attackerRoot.Anchored = originalAnchored
							playDefenderDamagedAndIdle(ctx)
						end)
					end)
				end)
			end)
		else
			-- Fallback
			local highPosition = originalCFrame.Position + Vector3.new(0, 5, 0)
			local highCFrame = CFrame.new(highPosition, highPosition + originalCFrame.LookVector)
			local diveTween = TweenService:Create(
				attackerRoot,
				TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{CFrame = highCFrame}
			)
			
			diveTween:Play()
			diveTween.Completed:Connect(function()
				local targetPosition = defenderPos + Vector3.new(0, 1, 0)
				local targetCFrame = CFrame.new(targetPosition, targetPosition + originalCFrame.LookVector)
				local downTween = TweenService:Create(
					attackerRoot,
					TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{CFrame = targetCFrame}
				)
				
				downTween:Play()
				downTween.Completed:Connect(function()
					createParticleBurst(defenderPos, flyingColor, 20, 0.5)
					
					if ctx.onHit then
						ctx.onHit()
					end
					
					local returnTween = TweenService:Create(
						attackerRoot,
						TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{CFrame = originalCFrame}
					)
					
					returnTween:Play()
					returnTween.Completed:Connect(function()
						attackerRoot.Anchored = originalAnchored
						playDefenderDamagedAndIdle(ctx)
					end)
				end)
			end)
		end
	else
		-- Peck or other flying moves - simple strike
		if ctx.animationController then
			ctx.animationController:PlayAnimationWithHit(ctx.attackerModel, "Attack", function()
				local direction = (defenderPos - attackerPos).Unit
				local startCFrame = CFrame.new(defenderPos - direction * 1)
				local endCFrame = CFrame.new(defenderPos + direction * 1)
				createSlashEffect(startCFrame, endCFrame, flyingColor, 0.2, 0.2)
				createParticleBurst(defenderPos, flyingColor, 10, 0.3)
				
				if ctx.onHit then
					ctx.onHit()
				end
				
				playDefenderDamagedAndIdle(ctx)
			end)
		else
			local direction = (defenderPos - attackerPos).Unit
			local startCFrame = CFrame.new(defenderPos - direction * 1)
			local endCFrame = CFrame.new(defenderPos + direction * 1)
			createSlashEffect(startCFrame, endCFrame, flyingColor, 0.2, 0.2)
			createParticleBurst(defenderPos, flyingColor, 10, 0.3)
			
			if ctx.onHit then
				task.delay(0.15, ctx.onHit)
			end
			
			playDefenderDamagedAndIdle(ctx)
		end
	end
	
	return true
end

--[[
	Fighting move handler (Double Kick, Grand Slam, Knockout, Close Combat, etc.)
]]
local function fightingMoveHandler(ctx: MoveContext, moveName: string): boolean
	if not ctx.attackerModel or not ctx.defenderModel then
		return false
	end
	
	local attackerRoot = ctx.attackerModel:FindFirstChild("HumanoidRootPart") or ctx.attackerModel.PrimaryPart
	local defenderRoot = ctx.defenderModel:FindFirstChild("HumanoidRootPart") or ctx.defenderModel.PrimaryPart
	
	if not attackerRoot or not defenderRoot then
		return false
	end
	
	local defenderPos = defenderRoot.Position
	local attackerPos = attackerRoot.Position
	local fightingColor = Color3.new(0.9, 0.3, 0.2)
	
	if moveName == "Double Kick" or moveName == "double kick" or moveName == "Triple Kick" or moveName == "triple kick" then
		-- Multi-hit effect
		if ctx.animationController then
			ctx.animationController:PlayAnimationWithHit(ctx.attackerModel, "Attack", function()
				local hits = (moveName == "Triple Kick" or moveName == "triple kick") and 3 or 2
				for i = 1, hits do
					task.delay(i * 0.15, function()
						local direction = (defenderPos - attackerPos).Unit
						local offset = Vector3.new(
							(math.random() - 0.5) * 0.5,
							(math.random() - 0.5) * 0.5,
							(math.random() - 0.5) * 0.5
						)
						local startCFrame = CFrame.new(defenderPos - direction * 1.5 + offset)
						local endCFrame = CFrame.new(defenderPos + direction * 1.5 + offset)
						createSlashEffect(startCFrame, endCFrame, fightingColor, 0.2, 0.25)
						createParticleBurst(defenderPos + offset, fightingColor, 8, 0.3)
						
						if i == hits and ctx.onHit then
							ctx.onHit()
						end
					end)
				end
				
				task.delay(hits * 0.15 + 0.1, function()
					playDefenderDamagedAndIdle(ctx)
				end)
			end)
		else
			local hits = (moveName == "Triple Kick" or moveName == "triple kick") and 3 or 2
			for i = 1, hits do
				task.delay(i * 0.15, function()
					local direction = (defenderPos - attackerPos).Unit
					local offset = Vector3.new(
						(math.random() - 0.5) * 0.5,
						(math.random() - 0.5) * 0.5,
						(math.random() - 0.5) * 0.5
					)
					local startCFrame = CFrame.new(defenderPos - direction * 1.5 + offset)
					local endCFrame = CFrame.new(defenderPos + direction * 1.5 + offset)
					createSlashEffect(startCFrame, endCFrame, fightingColor, 0.2, 0.25)
					createParticleBurst(defenderPos + offset, fightingColor, 8, 0.3)
					
					if i == hits and ctx.onHit then
						ctx.onHit()
					end
				end)
			end
			
			task.delay(hits * 0.15 + 0.2, function()
				playDefenderDamagedAndIdle(ctx)
			end)
		end
	elseif moveName == "Grand Slam" or moveName == "grand slam" or moveName == "Knockout" or moveName == "knockout" or moveName == "Close Combat" or moveName == "close combat" then
		-- Powerful impact effect
		if ctx.animationController then
			ctx.animationController:PlayAnimationWithHit(ctx.attackerModel, "Attack", function()
				local direction = (defenderPos - attackerPos).Unit
				local startCFrame = CFrame.new(defenderPos - direction * 2)
				local endCFrame = CFrame.new(defenderPos + direction * 2)
				createSlashEffect(startCFrame, endCFrame, fightingColor, 0.4, 0.5)
				createParticleBurst(defenderPos, fightingColor, 30, 0.7)
				
				-- Additional impact bursts
				for i = 1, 3 do
					task.delay(i * 0.1, function()
						local offset = Vector3.new(
							(math.random() - 0.5) * 2,
							(math.random() - 0.5) * 1,
							(math.random() - 0.5) * 2
						)
						createParticleBurst(defenderPos + offset, fightingColor, 10, 0.4)
					end)
				end
				
				if ctx.onHit then
					ctx.onHit()
				end
				
				playDefenderDamagedAndIdle(ctx)
			end)
		else
			local direction = (defenderPos - attackerPos).Unit
			local startCFrame = CFrame.new(defenderPos - direction * 2)
			local endCFrame = CFrame.new(defenderPos + direction * 2)
			createSlashEffect(startCFrame, endCFrame, fightingColor, 0.4, 0.5)
			createParticleBurst(defenderPos, fightingColor, 30, 0.7)
			
			for i = 1, 3 do
				task.delay(i * 0.1, function()
					local offset = Vector3.new(
						(math.random() - 0.5) * 2,
						(math.random() - 0.5) * 1,
						(math.random() - 0.5) * 2
					)
					createParticleBurst(defenderPos + offset, fightingColor, 10, 0.4)
				end)
			end
			
			if ctx.onHit then
				task.delay(0.3, ctx.onHit)
			end
			
			playDefenderDamagedAndIdle(ctx)
		end
	else
		-- Other fighting moves - standard strike
		if ctx.animationController then
			ctx.animationController:PlayAnimationWithHit(ctx.attackerModel, "Attack", function()
				local direction = (defenderPos - attackerPos).Unit
				local startCFrame = CFrame.new(defenderPos - direction * 1.5)
				local endCFrame = CFrame.new(defenderPos + direction * 1.5)
				createSlashEffect(startCFrame, endCFrame, fightingColor, 0.3, 0.3)
				createParticleBurst(defenderPos, fightingColor, 15, 0.4)
				
				if ctx.onHit then
					ctx.onHit()
				end
				
				playDefenderDamagedAndIdle(ctx)
			end)
		else
			local direction = (defenderPos - attackerPos).Unit
			local startCFrame = CFrame.new(defenderPos - direction * 1.5)
			local endCFrame = CFrame.new(defenderPos + direction * 1.5)
			createSlashEffect(startCFrame, endCFrame, fightingColor, 0.3, 0.3)
			createParticleBurst(defenderPos, fightingColor, 15, 0.4)
			
			if ctx.onHit then
				task.delay(0.2, ctx.onHit)
			end
			
			playDefenderDamagedAndIdle(ctx)
		end
	end
	
	return true
end

--[[
	Steel move handler (Shield Bash, Gear Grind, Metal Claw, etc.)
]]
local function steelMoveHandler(ctx: MoveContext, moveName: string): boolean
	if not ctx.attackerModel or not ctx.defenderModel then
		return false
	end
	
	local attackerRoot = ctx.attackerModel:FindFirstChild("HumanoidRootPart") or ctx.attackerModel.PrimaryPart
	local defenderRoot = ctx.defenderModel:FindFirstChild("HumanoidRootPart") or ctx.defenderModel.PrimaryPart
	
	if not attackerRoot or not defenderRoot then
		return false
	end
	
	local defenderPos = defenderRoot.Position
	local attackerPos = attackerRoot.Position
	local steelColor = Color3.new(0.7, 0.7, 0.8)
	
	if moveName == "Gear Grind" or moveName == "gear grind" then
		-- Multi-hit effect
		if ctx.animationController then
			ctx.animationController:PlayAnimationWithHit(ctx.attackerModel, "Attack", function()
				for i = 1, 2 do
					task.delay(i * 0.2, function()
						local direction = (defenderPos - attackerPos).Unit
						local startCFrame = CFrame.new(defenderPos - direction * 1.5)
						local endCFrame = CFrame.new(defenderPos + direction * 1.5)
						createSlashEffect(startCFrame, endCFrame, steelColor, 0.25, 0.3)
						createParticleBurst(defenderPos, steelColor, 12, 0.4)
						
						if i == 2 and ctx.onHit then
							ctx.onHit()
						end
					end)
				end
				
				task.delay(0.5, function()
					playDefenderDamagedAndIdle(ctx)
				end)
			end)
		else
			for i = 1, 2 do
				task.delay(i * 0.2, function()
					local direction = (defenderPos - attackerPos).Unit
					local startCFrame = CFrame.new(defenderPos - direction * 1.5)
					local endCFrame = CFrame.new(defenderPos + direction * 1.5)
					createSlashEffect(startCFrame, endCFrame, steelColor, 0.25, 0.3)
					createParticleBurst(defenderPos, steelColor, 12, 0.4)
					
					if i == 2 and ctx.onHit then
						ctx.onHit()
					end
				end)
			end
			
			task.delay(0.6, function()
				playDefenderDamagedAndIdle(ctx)
			end)
		end
	else
		-- Standard steel move
		if ctx.animationController then
			ctx.animationController:PlayAnimationWithHit(ctx.attackerModel, "Attack", function()
				local direction = (defenderPos - attackerPos).Unit
				local startCFrame = CFrame.new(defenderPos - direction * 1.5)
				local endCFrame = CFrame.new(defenderPos + direction * 1.5)
				createSlashEffect(startCFrame, endCFrame, steelColor, 0.3, 0.3)
				createParticleBurst(defenderPos, steelColor, 15, 0.5)
				
				if ctx.onHit then
					ctx.onHit()
				end
				
				playDefenderDamagedAndIdle(ctx)
			end)
		else
			local direction = (defenderPos - attackerPos).Unit
			local startCFrame = CFrame.new(defenderPos - direction * 1.5)
			local endCFrame = CFrame.new(defenderPos + direction * 1.5)
			createSlashEffect(startCFrame, endCFrame, steelColor, 0.3, 0.3)
			createParticleBurst(defenderPos, steelColor, 15, 0.5)
			
			if ctx.onHit then
				task.delay(0.2, ctx.onHit)
			end
			
			playDefenderDamagedAndIdle(ctx)
		end
	end
	
	return true
end

--[[
	Recoil move handler (Take Down, Double-Edge, Head Smash, etc.)
]]
local function recoilMoveHandler(ctx: MoveContext, moveName: string): boolean
	if not ctx.attackerModel or not ctx.defenderModel then
		return false
	end
	
	local attackerRoot = ctx.attackerModel:FindFirstChild("HumanoidRootPart") or ctx.attackerModel.PrimaryPart
	local defenderRoot = ctx.defenderModel:FindFirstChild("HumanoidRootPart") or ctx.defenderModel.PrimaryPart
	
	if not attackerRoot or not defenderRoot then
		return false
	end
	
	-- Store original state
	local originalCFrame = attackerRoot.CFrame
	local originalAnchored = attackerRoot.Anchored
	attackerRoot.Anchored = true
	
	-- Use the creature's LookVector to move forward in the direction it's facing
	local chargeDistance = 5 -- Max charge distance
	local newPosition = originalCFrame.Position + originalCFrame.LookVector * chargeDistance
	
	local impactColor = Color3.new(0.9, 0.5, 0.3)
	local defenderPos = defenderRoot.Position
	
	if ctx.animationController then
		ctx.animationController:PlayAnimationWithHit(ctx.attackerModel, "Attack", function()
			-- Charge forward using LookVector
			local chargeTween = TweenService:Create(
				attackerRoot,
				TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{CFrame = CFrame.new(newPosition, newPosition + originalCFrame.LookVector)}
			)
			
			chargeTween:Play()
			chargeTween.Completed:Connect(function()
				createParticleBurst(defenderPos, impactColor, 25, 0.6)
				
				if ctx.onHit then
					ctx.onHit()
				end
				
				-- Return to original position
				local returnTween = TweenService:Create(
					attackerRoot,
					TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{CFrame = originalCFrame}
				)
				
				returnTween:Play()
				returnTween.Completed:Connect(function()
					attackerRoot.Anchored = originalAnchored
					playDefenderDamagedAndIdle(ctx)
				end)
			end)
		end)
	else
		-- Fallback
		local chargeTween = TweenService:Create(
			attackerRoot,
			TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{CFrame = CFrame.new(newPosition, newPosition + originalCFrame.LookVector)}
		)
		
		chargeTween:Play()
		chargeTween.Completed:Connect(function()
			createParticleBurst(defenderPos, impactColor, 25, 0.6)
			
			if ctx.onHit then
				ctx.onHit()
			end
			
			local returnTween = TweenService:Create(
				attackerRoot,
				TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{CFrame = originalCFrame}
			)
			
			returnTween:Play()
			returnTween.Completed:Connect(function()
				attackerRoot.Anchored = originalAnchored
				playDefenderDamagedAndIdle(ctx)
			end)
		end)
	end
	
	return true
end

--[[
	Multi-hit move handler (Tail Slap, Comet Punch, Bullet Seed, etc.)
]]
local function multiHitMoveHandler(ctx: MoveContext, moveName: string): boolean
	if not ctx.attackerModel or not ctx.defenderModel then
		return false
	end
	
	local attackerRoot = ctx.attackerModel:FindFirstChild("HumanoidRootPart") or ctx.attackerModel.PrimaryPart
	local defenderRoot = ctx.defenderModel:FindFirstChild("HumanoidRootPart") or ctx.defenderModel.PrimaryPart
	
	if not attackerRoot or not defenderRoot then
		return false
	end
	
	local defenderPos = defenderRoot.Position
	local attackerPos = attackerRoot.Position
	
	-- Determine hit count and color based on move
	local hits = 3 -- Default
	local moveColor = Color3.new(0.9, 0.9, 0.9)
	
	if moveName == "Tail Slap" or moveName == "tail slap" then
		hits = 3
		moveColor = Color3.new(0.8, 0.6, 0.4)
	elseif moveName == "Comet Punch" or moveName == "comet punch" or moveName == "Arm Thrust" or moveName == "arm thrust" then
		hits = 3
		moveColor = Color3.new(0.9, 0.7, 0.5)
	elseif moveName == "Bullet Seed" or moveName == "bullet seed" then
		hits = 4
		moveColor = Color3.new(0.3, 0.7, 0.2)
	elseif moveName == "Pin Missile" or moveName == "pin missile" or moveName == "Spike Cannon" or moveName == "spike cannon" then
		hits = 4
		moveColor = Color3.new(0.7, 0.7, 0.8)
	elseif moveName == "Water Shuriken" or moveName == "water shuriken" then
		hits = 3
		moveColor = Color3.new(0.2, 0.6, 1)
	end
	
	if ctx.animationController then
		ctx.animationController:PlayAnimationWithHit(ctx.attackerModel, "Attack", function()
			for i = 1, hits do
				task.delay(i * 0.1, function()
					local direction = (defenderPos - attackerPos).Unit
					local offset = Vector3.new(
						(math.random() - 0.5) * 1,
						(math.random() - 0.5) * 0.5,
						(math.random() - 0.5) * 1
					)
					
					if moveName == "Bullet Seed" or moveName == "bullet seed" or moveName == "Water Shuriken" or moveName == "water shuriken" or moveName == "Pin Missile" or moveName == "pin missile" then
						-- Projectile effect
						local startCFrame = CFrame.new(attackerPos + offset)
						local endCFrame = CFrame.new(defenderPos + offset)
						createProjectile(startCFrame, endCFrame, moveColor, 40, function()
							createParticleBurst(defenderPos + offset, moveColor, 5, 0.2)
						end)
					else
						-- Strike effect
						local startCFrame = CFrame.new(defenderPos - direction * 1 + offset)
						local endCFrame = CFrame.new(defenderPos + direction * 1 + offset)
						createSlashEffect(startCFrame, endCFrame, moveColor, 0.15, 0.2)
						createParticleBurst(defenderPos + offset, moveColor, 6, 0.25)
					end
					
					if i == hits and ctx.onHit then
						task.delay(0.1, ctx.onHit)
					end
				end)
			end
			
			task.delay(hits * 0.1 + 0.2, function()
				playDefenderDamagedAndIdle(ctx)
			end)
		end)
	else
		-- Fallback
		for i = 1, hits do
			task.delay(i * 0.1, function()
				local direction = (defenderPos - attackerPos).Unit
				local offset = Vector3.new(
					(math.random() - 0.5) * 1,
					(math.random() - 0.5) * 0.5,
					(math.random() - 0.5) * 1
				)
				
				if moveName == "Bullet Seed" or moveName == "bullet seed" or moveName == "Water Shuriken" or moveName == "water shuriken" or moveName == "Pin Missile" or moveName == "pin missile" then
					local startCFrame = CFrame.new(attackerPos + offset)
					local endCFrame = CFrame.new(defenderPos + offset)
					createProjectile(startCFrame, endCFrame, moveColor, 40, function()
						createParticleBurst(defenderPos + offset, moveColor, 5, 0.2)
					end)
				else
					local startCFrame = CFrame.new(defenderPos - direction * 1 + offset)
					local endCFrame = CFrame.new(defenderPos + direction * 1 + offset)
					createSlashEffect(startCFrame, endCFrame, moveColor, 0.15, 0.2)
					createParticleBurst(defenderPos + offset, moveColor, 6, 0.25)
				end
				
				if i == hits and ctx.onHit then
					task.delay(0.2, ctx.onHit)
				end
			end)
		end
		
		task.delay(hits * 0.1 + 0.3, function()
			playDefenderDamagedAndIdle(ctx)
		end)
	end
	
	return true
end

-- Grass moves
MoveAnimations["Leaf Slash"] = function(ctx) return grassMoveHandler(ctx, "Leaf Slash") end
MoveAnimations["leaf slash"] = function(ctx) return grassMoveHandler(ctx, "Leaf Slash") end
MoveAnimations["Vine Whip"] = function(ctx) return grassMoveHandler(ctx, "Vine Whip") end
MoveAnimations["vine whip"] = function(ctx) return grassMoveHandler(ctx, "Vine Whip") end
MoveAnimations["Seed Toss"] = function(ctx) return grassMoveHandler(ctx, "Seed Toss") end
MoveAnimations["seed toss"] = function(ctx) return grassMoveHandler(ctx, "Seed Toss") end
MoveAnimations["Bullet Seed"] = function(ctx) return multiHitMoveHandler(ctx, "Bullet Seed") end
MoveAnimations["bullet seed"] = function(ctx) return multiHitMoveHandler(ctx, "Bullet Seed") end
MoveAnimations["Thorn Barrage"] = function(ctx) return multiHitMoveHandler(ctx, "Bullet Seed") end
MoveAnimations["thorn barrage"] = function(ctx) return multiHitMoveHandler(ctx, "Bullet Seed") end

-- Dark moves
MoveAnimations["Bite"] = function(ctx) return darkMoveHandler(ctx, "Bite") end
MoveAnimations["bite"] = function(ctx) return darkMoveHandler(ctx, "Bite") end
MoveAnimations["Shadow Ball"] = function(ctx) return darkMoveHandler(ctx, "Shadow Ball") end
MoveAnimations["shadow ball"] = function(ctx) return darkMoveHandler(ctx, "Shadow Ball") end
MoveAnimations["Beat Up"] = function(ctx) return multiHitMoveHandler(ctx, "Tail Slap") end
MoveAnimations["beat up"] = function(ctx) return multiHitMoveHandler(ctx, "Tail Slap") end

-- Psychic moves
MoveAnimations["Psychic Pulse"] = function(ctx) return psychicMoveHandler(ctx, "Psychic Pulse") end
MoveAnimations["psychic pulse"] = function(ctx) return psychicMoveHandler(ctx, "Psychic Pulse") end
MoveAnimations["Mind Slam"] = function(ctx) return psychicMoveHandler(ctx, "Mind Slam") end
MoveAnimations["mind slam"] = function(ctx) return psychicMoveHandler(ctx, "Mind Slam") end
MoveAnimations["Psychic Blast"] = function(ctx) return psychicMoveHandler(ctx, "Psychic Blast") end
MoveAnimations["psychic blast"] = function(ctx) return psychicMoveHandler(ctx, "Psychic Blast") end

-- Fairy moves
MoveAnimations["Dazzle Beam"] = function(ctx) return fairyMoveHandler(ctx, "Dazzle Beam") end
MoveAnimations["dazzle beam"] = function(ctx) return fairyMoveHandler(ctx, "Dazzle Beam") end
MoveAnimations["Fairy Strike"] = function(ctx) return fairyMoveHandler(ctx, "Fairy Strike") end
MoveAnimations["fairy strike"] = function(ctx) return fairyMoveHandler(ctx, "Fairy Strike") end
MoveAnimations["Dance Strike"] = function(ctx) return fairyMoveHandler(ctx, "Dance Strike") end
MoveAnimations["dance strike"] = function(ctx) return fairyMoveHandler(ctx, "Dance Strike") end
MoveAnimations["Sunbeam"] = function(ctx) return fairyMoveHandler(ctx, "Dazzle Beam") end
MoveAnimations["sunbeam"] = function(ctx) return fairyMoveHandler(ctx, "Dazzle Beam") end

-- Poison moves
MoveAnimations["Ooze Shot"] = function(ctx) return poisonMoveHandler(ctx, "Ooze Shot") end
MoveAnimations["ooze shot"] = function(ctx) return poisonMoveHandler(ctx, "Ooze Shot") end
MoveAnimations["Sludge Puff"] = function(ctx) return poisonMoveHandler(ctx, "Sludge Puff") end
MoveAnimations["sludge puff"] = function(ctx) return poisonMoveHandler(ctx, "Sludge Puff") end
MoveAnimations["Toxic Wave"] = function(ctx) return poisonMoveHandler(ctx, "Toxic Wave") end
MoveAnimations["toxic wave"] = function(ctx) return poisonMoveHandler(ctx, "Toxic Wave") end
MoveAnimations["Corrosive Grasp"] = function(ctx) return poisonMoveHandler(ctx, "Corrosive Grasp") end
MoveAnimations["corrosive grasp"] = function(ctx) return poisonMoveHandler(ctx, "Corrosive Grasp") end
MoveAnimations["Acidic Deluge"] = function(ctx) return poisonMoveHandler(ctx, "Acidic Deluge") end
MoveAnimations["acidic deluge"] = function(ctx) return poisonMoveHandler(ctx, "Acidic Deluge") end

-- Flying moves
MoveAnimations["Peck"] = function(ctx) return flyingMoveHandler(ctx, "Peck") end
MoveAnimations["peck"] = function(ctx) return flyingMoveHandler(ctx, "Peck") end
MoveAnimations["Dive Bomb"] = function(ctx) return flyingMoveHandler(ctx, "Dive Bomb") end
MoveAnimations["dive bomb"] = function(ctx) return flyingMoveHandler(ctx, "Dive Bomb") end
MoveAnimations["Brave Bird"] = function(ctx) return flyingMoveHandler(ctx, "Brave Bird") end
MoveAnimations["brave bird"] = function(ctx) return flyingMoveHandler(ctx, "Brave Bird") end
MoveAnimations["Sky Crash"] = function(ctx) return flyingMoveHandler(ctx, "Dive Bomb") end
MoveAnimations["sky crash"] = function(ctx) return flyingMoveHandler(ctx, "Dive Bomb") end
MoveAnimations["Duststorm Dash"] = function(ctx) return flyingMoveHandler(ctx, "Peck") end
MoveAnimations["duststorm dash"] = function(ctx) return flyingMoveHandler(ctx, "Peck") end

-- Fighting moves
MoveAnimations["Double Kick"] = function(ctx) return fightingMoveHandler(ctx, "Double Kick") end
MoveAnimations["double kick"] = function(ctx) return fightingMoveHandler(ctx, "Double Kick") end
MoveAnimations["Triple Kick"] = function(ctx) return fightingMoveHandler(ctx, "Triple Kick") end
MoveAnimations["triple kick"] = function(ctx) return fightingMoveHandler(ctx, "Triple Kick") end
MoveAnimations["Grand Slam"] = function(ctx) return fightingMoveHandler(ctx, "Grand Slam") end
MoveAnimations["grand slam"] = function(ctx) return fightingMoveHandler(ctx, "Grand Slam") end
MoveAnimations["Knockout"] = function(ctx) return fightingMoveHandler(ctx, "Knockout") end
MoveAnimations["knockout"] = function(ctx) return fightingMoveHandler(ctx, "Knockout") end
MoveAnimations["Close Combat"] = function(ctx) return fightingMoveHandler(ctx, "Close Combat") end
MoveAnimations["close combat"] = function(ctx) return fightingMoveHandler(ctx, "Close Combat") end
MoveAnimations["Superpower"] = function(ctx) return fightingMoveHandler(ctx, "Grand Slam") end
MoveAnimations["superpower"] = function(ctx) return fightingMoveHandler(ctx, "Grand Slam") end
MoveAnimations["Rock Smash"] = function(ctx) return fightingMoveHandler(ctx, "Rock Smash") end
MoveAnimations["rock smash"] = function(ctx) return fightingMoveHandler(ctx, "Rock Smash") end
MoveAnimations["Power-Up Punch"] = function(ctx) return fightingMoveHandler(ctx, "Power-Up Punch") end
MoveAnimations["power-up punch"] = function(ctx) return fightingMoveHandler(ctx, "Power-Up Punch") end
MoveAnimations["Arm Thrust"] = function(ctx) return multiHitMoveHandler(ctx, "Arm Thrust") end
MoveAnimations["arm thrust"] = function(ctx) return multiHitMoveHandler(ctx, "Arm Thrust") end
MoveAnimations["Close Flurry"] = function(ctx) return fightingMoveHandler(ctx, "Double Kick") end
MoveAnimations["close flurry"] = function(ctx) return fightingMoveHandler(ctx, "Double Kick") end
MoveAnimations["Submission"] = function(ctx) return recoilMoveHandler(ctx, "Submission") end
MoveAnimations["submission"] = function(ctx) return recoilMoveHandler(ctx, "Submission") end

-- Steel moves
MoveAnimations["Shield Bash"] = function(ctx) return steelMoveHandler(ctx, "Shield Bash") end
MoveAnimations["shield bash"] = function(ctx) return steelMoveHandler(ctx, "Shield Bash") end
MoveAnimations["Gear Grind"] = function(ctx) return steelMoveHandler(ctx, "Gear Grind") end
MoveAnimations["gear grind"] = function(ctx) return steelMoveHandler(ctx, "Gear Grind") end
MoveAnimations["Spike Cannon"] = function(ctx) return multiHitMoveHandler(ctx, "Spike Cannon") end
MoveAnimations["spike cannon"] = function(ctx) return multiHitMoveHandler(ctx, "Spike Cannon") end
MoveAnimations["Metal Claw"] = function(ctx) return steelMoveHandler(ctx, "Metal Claw") end
MoveAnimations["metal claw"] = function(ctx) return steelMoveHandler(ctx, "Metal Claw") end

-- Normal moves
MoveAnimations["Fast Attack"] = function(ctx) return scratchHandler(ctx) end
MoveAnimations["fast attack"] = function(ctx) return scratchHandler(ctx) end
MoveAnimations["Tail Slap"] = function(ctx) return multiHitMoveHandler(ctx, "Tail Slap") end
MoveAnimations["tail slap"] = function(ctx) return multiHitMoveHandler(ctx, "Tail Slap") end
MoveAnimations["Comet Punch"] = function(ctx) return multiHitMoveHandler(ctx, "Comet Punch") end
MoveAnimations["comet punch"] = function(ctx) return multiHitMoveHandler(ctx, "Comet Punch") end
MoveAnimations["Barrage"] = function(ctx) return multiHitMoveHandler(ctx, "Comet Punch") end
MoveAnimations["barrage"] = function(ctx) return multiHitMoveHandler(ctx, "Comet Punch") end
MoveAnimations["Pin Missile"] = function(ctx) return multiHitMoveHandler(ctx, "Pin Missile") end
MoveAnimations["pin missile"] = function(ctx) return multiHitMoveHandler(ctx, "Pin Missile") end
MoveAnimations["Fury Swipes"] = function(ctx) return multiHitMoveHandler(ctx, "Tail Slap") end
MoveAnimations["fury swipes"] = function(ctx) return multiHitMoveHandler(ctx, "Tail Slap") end
MoveAnimations["Take Down"] = function(ctx) return recoilMoveHandler(ctx, "Take Down") end
MoveAnimations["take down"] = function(ctx) return recoilMoveHandler(ctx, "Take Down") end
MoveAnimations["Double-Edge"] = function(ctx) return recoilMoveHandler(ctx, "Double-Edge") end
MoveAnimations["double-edge"] = function(ctx) return recoilMoveHandler(ctx, "Double-Edge") end
MoveAnimations["Head Smash"] = function(ctx) return recoilMoveHandler(ctx, "Head Smash") end
MoveAnimations["head smash"] = function(ctx) return recoilMoveHandler(ctx, "Head Smash") end
MoveAnimations["Crush Claw"] = function(ctx) return scratchHandler(ctx) end
MoveAnimations["crush claw"] = function(ctx) return scratchHandler(ctx) end
MoveAnimations["Rapid Spin"] = function(ctx) return scratchHandler(ctx) end
MoveAnimations["rapid spin"] = function(ctx) return scratchHandler(ctx) end

-- Fire moves
MoveAnimations["Flame Charge"] = function(ctx) return fireMoveHandler(ctx, "Flame Charge") end
MoveAnimations["flame charge"] = function(ctx) return fireMoveHandler(ctx, "Flame Charge") end
MoveAnimations["Overheat"] = function(ctx) return fireMoveHandler(ctx, "Overheat") end
MoveAnimations["overheat"] = function(ctx) return fireMoveHandler(ctx, "Overheat") end

-- Electric moves
MoveAnimations["Wild Charge"] = function(ctx) return recoilMoveHandler(ctx, "Wild Charge") end
MoveAnimations["wild charge"] = function(ctx) return recoilMoveHandler(ctx, "Wild Charge") end

-- Water moves
MoveAnimations["Water Shuriken"] = function(ctx) return multiHitMoveHandler(ctx, "Water Shuriken") end
MoveAnimations["water shuriken"] = function(ctx) return multiHitMoveHandler(ctx, "Water Shuriken") end
MoveAnimations["Icy Wind"] = function(ctx) return waterMoveHandler(ctx, "Hydro Burst") end
MoveAnimations["icy wind"] = function(ctx) return waterMoveHandler(ctx, "Hydro Burst") end

-- Ground moves
MoveAnimations["Mud Slap"] = function(ctx) return groundMoveHandler(ctx, "Sand Storm") end
MoveAnimations["mud slap"] = function(ctx) return groundMoveHandler(ctx, "Sand Storm") end
MoveAnimations["Ancient Power"] = function(ctx) return groundMoveHandler(ctx, "Earthquake") end
MoveAnimations["ancient power"] = function(ctx) return groundMoveHandler(ctx, "Earthquake") end

return MoveAnimations


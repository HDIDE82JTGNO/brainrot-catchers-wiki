--!strict

-- Burst emitter for lightweight "stud" UI particles.
-- Spawns once, resolves simple 2D physics + circle collisions, then cleans itself up.

type StudGui = Frame | ImageLabel | ImageButton | TextLabel | TextButton
type StudBody = {
	instance: StudGui,
	position: Vector2,
	velocity: Vector2,
	angle: number,
	angularVelocity: number,
	radius: number,
}

export type EmitterConfig = {
	studCount: number,
	spawnYOffset: number,
	initialSpeedY: NumberRange,
	initialSpeedX: NumberRange,
	gravity: number,
	maxRespawnJitter: number,
	bottomCullPadding: number,
	initialAngularSpeed: NumberRange, -- deg/s
	angularDamping: number, -- per-second decay
	restitution: number,
	friction: number,
	collisionIterations: number,
	sizeXScaleRange: NumberRange, -- e.g., 0.027–0.042
	sizeYScaleRange: NumberRange, -- e.g., 0.046–0.07
	cornerSpawnFraction: number, -- 0–1 fraction to spawn from corners
	cornerSpawnMargin: number, -- pixels offscreen on X for corner spawns
	cornerTargetHeightRatio: number, -- 0–1 of screen height to aim toward
	cornerSpeed: NumberRange, -- magnitude for corner launch
}

type StudEmitterSelf = {
	rootGui: ScreenGui,
	template: StudGui,
	rng: Random,
	config: EmitterConfig,
	studs: { StudBody },
	connection: RBXScriptConnection?,
	finished: boolean,
}

local RunService = game:GetService("RunService")

local DEFAULT_CONFIG: EmitterConfig = table.freeze({
	studCount = 20,
	spawnYOffset = 80,
	initialSpeedY = NumberRange.new(-1600, -550),
	initialSpeedX = NumberRange.new(-120, 120),
	gravity = 1800,
	maxRespawnJitter = 30,
	bottomCullPadding = 80,
	initialAngularSpeed = NumberRange.new(-240, 240),
	angularDamping = 1.5,
	restitution = 0.4,
	friction = 0.4,
	collisionIterations = 2,
	sizeXScaleRange = NumberRange.new(0.027, 0.042),
	sizeYScaleRange = NumberRange.new(0.046, 0.07),
	cornerSpawnFraction = 0.4,
	cornerSpawnMargin = 60,
	cornerTargetHeightRatio = 0.35,
	cornerSpeed = NumberRange.new(650, 1300),
})

local StudEmitter = {}
StudEmitter.__index = StudEmitter

function StudEmitter.new(rootGui: ScreenGui, template: StudGui, config: EmitterConfig): StudEmitterSelf
	template.Visible = false

	local self: StudEmitterSelf = setmetatable({
		rootGui = rootGui,
		template = template,
		rng = Random.new(),
		config = config,
		studs = {} :: { StudBody },
		connection = nil,
		finished = false,
	}, StudEmitter)

	self:spawnStuds()
	self.connection = RunService.Heartbeat:Connect(function(dt: number)
		self:update(dt)
	end)

	return self
end

function StudEmitter:getViewportSize(): Vector2
	return self.rootGui.AbsoluteSize
end

function StudEmitter:computeRadius(guiObj: StudGui): number
	local size = guiObj.AbsoluteSize
	return 0.5 * math.max(size.X, size.Y)
end

function StudEmitter:randomVelocity(): Vector2
	local vx = self.rng:NextNumber(self.config.initialSpeedX.Min, self.config.initialSpeedX.Max)
	local vy = self.rng:NextNumber(self.config.initialSpeedY.Min, self.config.initialSpeedY.Max)
	return Vector2.new(vx, vy)
end

function StudEmitter:randomAngularVelocity(): number
	return self.rng:NextNumber(self.config.initialAngularSpeed.Min, self.config.initialAngularSpeed.Max)
end

function StudEmitter:randomSize(): UDim2
	local sx = self.rng:NextNumber(self.config.sizeXScaleRange.Min, self.config.sizeXScaleRange.Max)
	local sy = self.rng:NextNumber(self.config.sizeYScaleRange.Min, self.config.sizeYScaleRange.Max)
	return UDim2.new(sx, 0, sy, 0)
end

function StudEmitter:spawnStuds()
	local viewport = self:getViewportSize()
	local width = viewport.X
	local spacing = width / math.max(1, self.config.studCount - 1)

	for i = 1, self.config.studCount do
		local clone = self.template:Clone()
		clone.Visible = true
		clone.Size = self:randomSize()
		clone.Parent = self.rootGui

		local isCorner = self.rng:NextNumber(0, 1) < self.config.cornerSpawnFraction
		local x: number
		local y: number = viewport.Y + self.config.spawnYOffset
		local velocity: Vector2

		if isCorner then
			local fromLeft = self.rng:NextNumber(0, 1) < 0.5
			x = fromLeft and -self.config.cornerSpawnMargin or (viewport.X + self.config.cornerSpawnMargin)

			local target = Vector2.new(viewport.X * 0.5, viewport.Y * self.config.cornerTargetHeightRatio)
			local origin = Vector2.new(x, y)
			local dir = target - origin
			local mag = dir.Magnitude
			if mag < 1e-4 then
				dir = Vector2.new(0, -1)
			else
				dir = dir / mag
			end

			local speedMag = self.rng:NextNumber(self.config.cornerSpeed.Min, self.config.cornerSpeed.Max)
			velocity = dir * speedMag
		else
			x = (i - 1) * spacing + self.rng:NextNumber(-self.config.maxRespawnJitter, self.config.maxRespawnJitter)
			velocity = self:randomVelocity()
		end

		local body: StudBody = {
			instance = clone,
			position = Vector2.new(x, y),
			velocity = velocity,
			angle = self.rng:NextNumber(0, 360),
			angularVelocity = self:randomAngularVelocity(),
			radius = self:computeRadius(clone),
		}

		self:updateGuiTransform(body)
		table.insert(self.studs, body)
	end
end

function StudEmitter:updateGuiTransform(body: StudBody)
	local viewport = self:getViewportSize()
	local pos = body.position
	body.instance.Position = UDim2.new(
		pos.X / math.max(1, viewport.X),
		0,
		pos.Y / math.max(1, viewport.Y),
		0
	)
	body.instance.Rotation = body.angle % 360
end

function StudEmitter:resolveCollisions()
	local studs = self.studs
	local iterations = math.max(1, self.config.collisionIterations)
	for _ = 1, iterations do
		for i = 1, #studs - 1 do
			local a = studs[i]
			for j = i + 1, #studs do
				local b = studs[j]

				local delta = b.position - a.position
				local distSq = delta.X * delta.X + delta.Y * delta.Y
				local rSum = a.radius + b.radius

				if distSq < rSum * rSum then
					local dist = (distSq > 1e-6) and math.sqrt(distSq) or rSum
					local normal = (distSq > 1e-6) and (delta / dist) or Vector2.new(0, -1)
					local penetration = rSum - dist

					local correction = 0.5 * penetration
					a.position = a.position - normal * correction
					b.position = b.position + normal * correction

					local relVel = b.velocity - a.velocity
					local velAlongNormal = relVel:Dot(normal)
					if velAlongNormal < 0 then
						local e = self.config.restitution
						local j = -(1 + e) * velAlongNormal * 0.5
						local impulse = normal * j
						a.velocity = a.velocity - impulse
						b.velocity = b.velocity + impulse

						local tangent = relVel - (velAlongNormal * normal)
						local tMag = tangent.Magnitude
						if tMag > 1e-4 then
							tangent = tangent / tMag
							local jt = -relVel:Dot(tangent) * 0.5
							local mu = self.config.friction
							local frictionImpulse = tangent * math.clamp(jt, -j * mu, j * mu)
							a.velocity = a.velocity - frictionImpulse
							b.velocity = b.velocity + frictionImpulse
						end
					end
				end
			end
		end
	end
end

function StudEmitter:update(dt: number)
	if self.finished then
		return
	end

	local viewport = self:getViewportSize()
	local bottomLimit = viewport.Y + self.config.spawnYOffset + self.config.bottomCullPadding
	local activeCount = 0
	local angularDecay = math.exp(-self.config.angularDamping * dt)

	for _, body in ipairs(self.studs) do
		body.velocity = body.velocity + Vector2.new(0, self.config.gravity * dt)
		body.position = body.position + body.velocity * dt

		body.angularVelocity = body.angularVelocity * angularDecay
		body.angle = body.angle + body.angularVelocity * dt
	end

	self:resolveCollisions()

	for _, body in ipairs(self.studs) do
		if body.position.Y <= bottomLimit then
			activeCount = activeCount + 1
			self:updateGuiTransform(body)
		else
			body.instance.Visible = false
		end
	end

	if activeCount == 0 then
		self:Destroy()
	end
end

function StudEmitter:Destroy()
	if self.finished then
		return
	end
	self.finished = true
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	for _, body in ipairs(self.studs) do
		body.instance:Destroy()
	end
	table.clear(self.studs)
end

local StudBurstEmitter = {}

StudBurstEmitter.defaultConfig = DEFAULT_CONFIG

function StudBurstEmitter.playBurst(rootGui: ScreenGui?, studTemplate: StudGui?, config: EmitterConfig?): StudEmitterSelf?
	if not rootGui or not rootGui:IsA("ScreenGui") then
		warn("[StudBurstEmitter] rootGui missing or not a ScreenGui")
		return nil
	end

	local template: StudGui? = studTemplate or rootGui:FindFirstChild("Stud") :: StudGui?
	if not template or not template:IsA("GuiObject") then
		warn("[StudBurstEmitter] Could not find a valid stud template under", rootGui:GetFullName())
		return nil
	end

	local resolvedConfig: EmitterConfig = config or DEFAULT_CONFIG
	return StudEmitter.new(rootGui, template, resolvedConfig)
end

return StudBurstEmitter


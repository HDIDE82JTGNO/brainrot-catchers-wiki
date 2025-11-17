local RunService = game:GetService("RunService")

local IndoorCamera = {}
IndoorCamera.__index = IndoorCamera

local STEP_ID = "IndoorCameraStep"

local function degToOffset(angleDeg, distance)
	local a = math.rad(angleDeg)
	-- Forward tilt by angle, pulled back along -Z by distance, raised by sin(angle)*distance
	-- This matches a classic angled follow cam that looks down toward the target.
	return Vector3.new(0, math.sin(a) * distance, -math.cos(a) * distance)
end

function IndoorCamera.new()
	local self = setmetatable({}, IndoorCamera)
	self._enabled = false
	self._lastCameraType = nil
	self._target = nil -- BasePart the camera follows
	self._minX = -math.huge
	self._maxX = math.huge
	self._angleDeg = 40
	self._distance = 18
	self._angleOffset = degToOffset(self._angleDeg, self._distance)
	self._extraOffset = Vector3.new(0, 0, 0) -- optional user offset (e.g., per-room tweak)
	self._yOffset = 1.5 -- eye height over target
	self._overrideStack = {} -- for temporary scripted control
	self._bound = false
	return self
end

function IndoorCamera:setTarget(basePart)
	self._target = basePart
	return self
end

function IndoorCamera:setBounds(minX, maxX)
	self._minX = minX or -math.huge
	self._maxX = maxX or math.huge
	return self
end

function IndoorCamera:setAngleAndDistance(angleDeg, distance)
	self._angleDeg = angleDeg or self._angleDeg
	self._distance = distance or self._distance
	self._angleOffset = degToOffset(self._angleDeg, self._distance)
	return self
end

function IndoorCamera:setExtraOffset(offset)
	self._extraOffset = offset or Vector3.new()
	return self
end

function IndoorCamera:setYHeight(offsetY)
	self._yOffset = offsetY or self._yOffset
	return self
end

-- Returns the computed indoor camera CFrame (without applying it).
function IndoorCamera:getIndoorCFrame()
	local cam = workspace.CurrentCamera
	if not self._target or not self._target.Parent then
		return cam and cam.CFrame or CFrame.new()
	end

	local tp = self._target.CFrame.Position
	-- follow point p: clamp X, keep Y/Z from target
	local clampedX = math.max(self._minX, math.min(self._maxX, tp.X))
	local p = Vector3.new(clampedX, tp.Y + self._yOffset, tp.Z)
	local from = p + self._angleOffset + self._extraOffset
	return CFrame.new(from, p)
end

-- Push a per-frame override that can return a custom CFrame (or nil to skip and let default run).
-- The override receives (dt, state) where state contains current target, bounds, etc
function IndoorCamera:pushOverride(fn)
	if type(fn) ~= "function" then
		return self
	end
	table.insert(self._overrideStack, fn)
	return self
end

function IndoorCamera:popOverride()
	if #self._overrideStack > 0 then
		table.remove(self._overrideStack, #self._overrideStack)
	end
	return self
end

function IndoorCamera:_step(_, dt)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end

	-- If there is an active override, let it provide a CFrame.
	local overrideFn = self._overrideStack[#self._overrideStack]
	if overrideFn then
		local cf = overrideFn(dt, {
			target = self._target,
			minX = self._minX,
			maxX = self._maxX,
			angleDeg = self._angleDeg,
			distance = self._distance,
			extraOffset = self._extraOffset,
			yOffset = self._yOffset,
			getDefaultCFrame = function()
				return self:getIndoorCFrame()
			end,
		})
		if cf then
			cam.CFrame = cf
			return
		end
	end

	-- Default behavior: scriptable follow with clamp
	cam.CFrame = self:getIndoorCFrame()
end

function IndoorCamera:enable()
	if self._enabled then
		return self
	end
	self._enabled = true

	local cam = workspace.CurrentCamera
	if cam then
		self._lastCameraType = cam.CameraType
		cam.CameraType = Enum.CameraType.Scriptable
	end

	if not self._bound then
		RunService:BindToRenderStep(STEP_ID, Enum.RenderPriority.Camera.Value, function(dt)
			self:_step(nil, dt)
		end)
		self._bound = true
	end

	return self
end

function IndoorCamera:disable()
	if not self._enabled then
		return self
	end
	self._enabled = false

	if self._bound then
		RunService:UnbindFromRenderStep(STEP_ID)
		self._bound = false
	end

	local cam = workspace.CurrentCamera
	if cam and self._lastCameraType ~= nil then
		cam.CameraType = self._lastCameraType
	end
	self._lastCameraType = nil

	return self
end

return IndoorCamera



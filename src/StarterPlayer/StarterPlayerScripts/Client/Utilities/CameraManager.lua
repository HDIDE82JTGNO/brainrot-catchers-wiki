--!strict
--[[
	CameraManager.lua
	Comprehensive camera management system with cinematic presets
	Supports character-focused shots, scene-setting shots, and action/impact shots
]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local CameraManager = {}
CameraManager.__index = CameraManager

export type CameraManagerType = typeof(CameraManager.new())
export type CameraPreset = "CloseUp" | "MediumShot" | "FullBodyShot" | "OverTheShoulder" | "Tracking" | "Orbit" | "Establishing" | "WideShot" | "BirdEye" | "LowAngle" | "HighAngle" | "DynamicFollow" | "ZoomIn" | "CutIn" | "POV" | "SlowPan"

type PresetOptions = {
	duration: number?,
	offset: Vector3?,
	fov: number?,
	onComplete: (() -> ())?,
	subject: BasePart | Model?,
	lookAt: Vector3 | BasePart | Model?,
	fromBehind: boolean?, -- true = back view, false/nil = front view
	orbitRadius: number?,
	orbitSpeed: number?,
	followLag: number?,
	shakeIntensity: number?,
	panDirection: Vector3?,
	panSpeed: number?,
}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

--[[
	Creates a new camera manager instance
	@param cameraInstance Optional camera to control (defaults to workspace.CurrentCamera)
	@return CameraManager
]]
function CameraManager.new(cameraInstance: Camera?): CameraManagerType
	local self = setmetatable({}, CameraManager)
	
	self._camera = cameraInstance or workspace.CurrentCamera
	self._activeTween = nil
	self._activeConnection = nil
	self._originalCameraType = self._camera.CameraType
	self._originalFOV = self._camera.FieldOfView
	self._isActive = false
	
	return self
end

--[[
	Internal: Gets the character or target from options
]]
function CameraManager:_getTarget(options: PresetOptions?): Model?
	local target = options and options.subject
	if target then
		if target:IsA("Model") then
			return target
		elseif target:IsA("BasePart") then
			return target.Parent
		end
	end
	
	-- Default to player character
	if player and player.Character then
		return player.Character
	end
	
	return nil
end

--[[
	Internal: Gets the position to look at
]]
function CameraManager:_getLookAtPosition(options: PresetOptions?, character: Model?): Vector3
	local lookAt = options and options.lookAt
	if lookAt then
		if typeof(lookAt) == "Vector3" then
			return lookAt
		elseif typeof(lookAt) == "Instance" then
			if lookAt:IsA("BasePart") then
				return lookAt.Position
			elseif lookAt:IsA("Model") then
				local humanoidRootPart = lookAt:FindFirstChild("HumanoidRootPart") or lookAt:FindFirstChild("Torso") or lookAt:FindFirstChild("UpperTorso")
				if humanoidRootPart then
					return humanoidRootPart.Position
				end
			end
		end
	end
	
	-- Default to character head/upper body
	if character then
		local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
		if humanoidRootPart then
			return humanoidRootPart.Position + Vector3.new(0, 1, 0) -- Slightly above torso
		end
	end
	
	return Vector3.new(0, 0, 0)
end

--[[
	Internal: Gets character head position
]]
function CameraManager:_getHeadPosition(character: Model?): Vector3?
	if not character then return nil end
	
	local head = character:FindFirstChild("Head")
	if head then
		return head.Position
	end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
	if humanoidRootPart then
		return humanoidRootPart.Position + Vector3.new(0, 1.5, 0)
	end
	
	return nil
end

--[[
	Internal: Gets character torso/center position
]]
function CameraManager:_getTorsoPosition(character: Model?): Vector3?
	if not character then return nil end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
	if humanoidRootPart then
		return humanoidRootPart.Position
	end
	
	return nil
end

--[[
	Internal: Gets character facing direction
	@param character The character model
	@return Vector3 facing direction (or default forward if not found)
]]
function CameraManager:_getFacingDirection(character: Model?): Vector3
	if not character then return Vector3.new(0, 0, -1) end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
	if humanoidRootPart then
		return humanoidRootPart.CFrame.LookVector
	end
	
	return Vector3.new(0, 0, -1) -- Default forward
end

--[[
	Internal: Adjusts offset based on front/back option relative to character facing
	@param baseOffset Base offset (typically in world space with positive Z forward)
	@param character Character model
	@param fromBehind Whether camera should be behind character
	@return Adjusted offset Vector3 in world space
]]
function CameraManager:_adjustOffsetForFacing(baseOffset: Vector3, character: Model?, fromBehind: boolean?): Vector3
	if fromBehind == nil or not character then
		return baseOffset
	end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
	if not humanoidRootPart then
		return baseOffset
	end
	
	local characterCFrame = humanoidRootPart.CFrame
	local facing = characterCFrame.LookVector
	local right = characterCFrame.RightVector
	local up = characterCFrame.UpVector
	
	-- Convert base offset to character's local space
	-- Assume base offset is in world space where Z is typically forward
	local localRight = right:Dot(baseOffset)
	local localUp = up:Dot(baseOffset)
	local localForward = facing:Dot(baseOffset)
	
	-- Flip forward component if fromBehind is specified
	if fromBehind then
		-- Behind: camera should be in negative forward direction
		localForward = -math.abs(localForward)
	else
		-- Front: camera should be in positive forward direction
		localForward = math.abs(localForward)
	end
	
	-- Convert back to world space
	return (right * localRight) + (up * localUp) + (facing * localForward)
end

--[[
	Internal: Cancels active operations
]]
function CameraManager:_cancelActive()
	if self._activeTween then
		self._activeTween:Cancel()
		self._activeTween = nil
	end
	
	if self._activeConnection then
		self._activeConnection:Disconnect()
		self._activeConnection = nil
	end
	
	self._isActive = false
end

--[[
	Internal: Transitions camera to a CFrame
]]
function CameraManager:_transitionTo(targetCFrame: CFrame, duration: number, fov: number?, onComplete: (() -> ())?)
	self:_cancelActive()
	
	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.InOut
	)
	
	local properties = {CFrame = targetCFrame}
	if fov then
		properties.FieldOfView = fov
	end
	
	self._activeTween = TweenService:Create(self._camera, tweenInfo, properties)
	
	if onComplete then
		self._activeTween.Completed:Connect(function()
			onComplete()
		end)
	end
	
	self._activeTween:Play()
end

--[[
	Internal: Sets camera to scriptable mode
]]
function CameraManager:_setScriptableMode()
	if self._camera.CameraType ~= Enum.CameraType.Scriptable then
		self._camera.CameraType = Enum.CameraType.Scriptable
	end
end

-- ============================================
-- CHARACTER-FOCUSED SHOTS
-- ============================================

--[[
	Close-Up: Focuses on the player's face or upper body
	@param options PresetOptions with duration, fov, offset, fromBehind, etc.
]]
function CameraManager:CloseUp(options: PresetOptions?)
	local character = self:_getTarget(options)
	if not character then return end
	
	local headPos = self:_getHeadPosition(character)
	if not headPos then return end
	
	local lookAt = self:_getLookAtPosition(options, character)
	local duration = options and options.duration or 1
	local fov = options and options.fov or 35
	
	-- Get character's facing direction to position camera correctly
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
	local facing = Vector3.new(0, 0, -1) -- Default forward
	if humanoidRootPart then
		facing = humanoidRootPart.CFrame.LookVector
	end
	
	-- Calculate camera position based on front/back option
	local distance = 6.5 -- Default distance from head
	if options and options.offset then
		-- Use Z component of offset as distance
		distance = math.abs(options.offset.Z) or distance
	end
	
	local fromBehind = options and options.fromBehind
	local cameraDirection = facing
	if fromBehind then
		cameraDirection = -facing
	end
	local cameraPos = headPos + (cameraDirection * distance)
	
	-- Add slight vertical offset if specified
	if options and options.offset and options.offset.Y ~= 0 then
		cameraPos = cameraPos + Vector3.new(0, options.offset.Y, 0)
	end
	
	local cameraCFrame = CFrame.lookAt(cameraPos, lookAt)
	
	self:_setScriptableMode()
	self:_transitionTo(cameraCFrame, duration, fov, options and options.onComplete)
end

--[[
	Medium Shot: Shows the player from the waist up
	@param options PresetOptions with fromBehind option
]]
function CameraManager:MediumShot(options: PresetOptions?)
	local character = self:_getTarget(options)
	if not character then return end
	
	local torsoPos = self:_getTorsoPosition(character)
	if not torsoPos then return end
	
	local lookAt = self:_getLookAtPosition(options, character)
	local duration = options and options.duration or 1
	local fov = options and options.fov or 50
	
	-- Get character's facing direction to position camera correctly
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
	local facing = Vector3.new(0, 0, -1) -- Default forward
	if humanoidRootPart then
		facing = humanoidRootPart.CFrame.LookVector
	end
	
	-- Calculate camera position based on front/back option
	local distance = 4 -- Default distance from torso
	local verticalOffset = 0.5 -- Default vertical offset
	if options and options.offset then
		-- Use Z component of offset as distance
		distance = math.abs(options.offset.Z) or distance
		verticalOffset = options.offset.Y or verticalOffset
	end
	
	local fromBehind = options and options.fromBehind
	local cameraDirection = facing
	if fromBehind then
		cameraDirection = -facing
	end
	local cameraPos = torsoPos + (cameraDirection * distance) + Vector3.new(0, verticalOffset, 0)
	
	local cameraCFrame = CFrame.lookAt(cameraPos, lookAt)
	
	self:_setScriptableMode()
	self:_transitionTo(cameraCFrame, duration, fov, options and options.onComplete)
end

--[[
	Full Body Shot: Shows the entire player character
	@param options PresetOptions with fromBehind option
]]
function CameraManager:FullBodyShot(options: PresetOptions?)
	local character = self:_getTarget(options)
	if not character then return end
	
	local torsoPos = self:_getTorsoPosition(character)
	if not torsoPos then return end
	
	local lookAt = self:_getLookAtPosition(options, character)
	local baseOffset = options and options.offset or Vector3.new(0, 0, 6)
	local offset = self:_adjustOffsetForFacing(baseOffset, character, options and options.fromBehind)
	local duration = options and options.duration or 1
	local fov = options and options.fov or 60
	
	local cameraPos = torsoPos + offset
	local cameraCFrame = CFrame.lookAt(cameraPos, lookAt)
	
	self:_setScriptableMode()
	self:_transitionTo(cameraCFrame, duration, fov, options and options.onComplete)
end

--[[
	Over-the-Shoulder (OTS): Camera looks from behind the player's shoulder
	@param options PresetOptions with subject (player), lookAt (target), and fromBehind option
	Note: Default is fromBehind=true, but can be set to false for front-shoulder view
]]
function CameraManager:OverTheShoulder(options: PresetOptions?)
	local character = self:_getTarget(options)
	if not character then return end
	
	local torsoPos = self:_getTorsoPosition(character)
	if not torsoPos then return end
	
	local lookAt = self:_getLookAtPosition(options, character)
	local baseOffset = options and options.offset or Vector3.new(1, 0.5, -1)
	-- Default OTS is from behind, but allow override
	local fromBehind = options and options.fromBehind
	if fromBehind == nil then fromBehind = true end
	local offset = self:_adjustOffsetForFacing(baseOffset, character, fromBehind)
	local duration = options and options.duration or 1
	local fov = options and options.fov or 55
	
	local cameraPos = torsoPos + offset
	local cameraCFrame = CFrame.lookAt(cameraPos, lookAt)
	
	self:_setScriptableMode()
	self:_transitionTo(cameraCFrame, duration, fov, options and options.onComplete)
end

--[[
	Tracking/Dolly Shot: Camera follows the player as they move
	@param options PresetOptions with followLag (default 0.1) and fromBehind option
]]
function CameraManager:Tracking(options: PresetOptions?)
	local character = self:_getTarget(options)
	if not character then return end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
	if not humanoidRootPart then return end
	
	local baseOffset = options and options.offset or Vector3.new(0, 2, 5)
	local offset = self:_adjustOffsetForFacing(baseOffset, character, options and options.fromBehind)
	local followLag = options and options.followLag or 0.1
	local fov = options and options.fov or 60
	
	self:_cancelActive()
	self:_setScriptableMode()
	self._isActive = true
	
	local currentCameraPos = humanoidRootPart.Position + self:_adjustOffsetForFacing(baseOffset, character, options and options.fromBehind)
	
	self._activeConnection = RunService.Heartbeat:Connect(function()
		if not self._isActive or not character.Parent then
			self:_cancelActive()
			return
		end
		
		local currentPos = humanoidRootPart.Position
		local lookAt = self:_getLookAtPosition(options, character)
		
		-- Recalculate offset based on current facing (for dynamic tracking)
		local currentOffset = self:_adjustOffsetForFacing(baseOffset, character, options and options.fromBehind)
		local targetCameraPos = currentPos + currentOffset
		
		-- Smooth follow with lag
		currentCameraPos = currentCameraPos:Lerp(targetCameraPos, followLag)
		local cameraCFrame = CFrame.lookAt(currentCameraPos, lookAt)
		
		self._camera.CFrame = cameraCFrame
		if fov then
			self._camera.FieldOfView = fov
		end
	end)
end

--[[
	Orbit Shot: Camera circles around the player
	@param options PresetOptions with orbitRadius (default 8) and orbitSpeed (default 1)
]]
function CameraManager:Orbit(options: PresetOptions?)
	local character = self:_getTarget(options)
	if not character then return end
	
	local torsoPos = self:_getTorsoPosition(character)
	if not torsoPos then return end
	
	local orbitRadius = options and options.orbitRadius or 8
	local orbitSpeed = options and options.orbitSpeed or 1
	local fov = options and options.fov or 60
	
	self:_cancelActive()
	self:_setScriptableMode()
	self._isActive = true
	
	local angle = 0
	local lookAt = self:_getLookAtPosition(options, character)
	
	self._activeConnection = RunService.Heartbeat:Connect(function()
		if not self._isActive or not character.Parent then
			self:_cancelActive()
			if options and options.onComplete then
				options.onComplete()
			end
			return
		end
		
		angle = angle + (orbitSpeed * 0.01)
		
		local x = math.cos(angle) * orbitRadius
		local z = math.sin(angle) * orbitRadius
		local cameraPos = torsoPos + Vector3.new(x, orbitRadius * 0.5, z)
		local cameraCFrame = CFrame.lookAt(cameraPos, lookAt)
		
		self._camera.CFrame = cameraCFrame
		if fov then
			self._camera.FieldOfView = fov
		end
	end)
end

-- ============================================
-- SCENE-SETTING SHOTS
-- ============================================

--[[
	Establishing Shot: Wide or aerial view showing the environment
	@param options PresetOptions with lookAt position
]]
function CameraManager:Establishing(options: PresetOptions?)
	local character = self:_getTarget(options)
	local lookAt = self:_getLookAtPosition(options, character)
	
	local offset = options and options.offset or Vector3.new(0, 20, 15)
	local duration = options and options.duration or 2
	local fov = options and options.fov or 70
	
	local cameraPos = lookAt + offset
	local cameraCFrame = CFrame.lookAt(cameraPos, lookAt)
	
	self:_setScriptableMode()
	self:_transitionTo(cameraCFrame, duration, fov, options and options.onComplete)
end

--[[
	Wide Shot: Shows player and surroundings
	@param options PresetOptions with fromBehind option
]]
function CameraManager:WideShot(options: PresetOptions?)
	local character = self:_getTarget(options)
	if not character then return end
	
	local torsoPos = self:_getTorsoPosition(character)
	if not torsoPos then return end
	
	local lookAt = self:_getLookAtPosition(options, character)
	local baseOffset = options and options.offset or Vector3.new(0, 5, 12)
	local offset = self:_adjustOffsetForFacing(baseOffset, character, options and options.fromBehind)
	local duration = options and options.duration or 1
	local fov = options and options.fov or 75
	
	local cameraPos = torsoPos + offset
	local cameraCFrame = CFrame.lookAt(cameraPos, lookAt)
	
	self:_setScriptableMode()
	self:_transitionTo(cameraCFrame, duration, fov, options and options.onComplete)
end

--[[
	Bird's Eye / Top-Down: Looks down from above
	@param options PresetOptions
]]
function CameraManager:BirdEye(options: PresetOptions?)
	local character = self:_getTarget(options)
	if not character then return end
	
	local torsoPos = self:_getTorsoPosition(character)
	if not torsoPos then return end
	
	local lookAt = self:_getLookAtPosition(options, character)
	local offset = options and options.offset or Vector3.new(0, 15, 0)
	local duration = options and options.duration or 1
	local fov = options and options.fov or 60
	
	local cameraPos = torsoPos + offset
	local cameraCFrame = CFrame.lookAt(cameraPos, lookAt)
	
	self:_setScriptableMode()
	self:_transitionTo(cameraCFrame, duration, fov, options and options.onComplete)
end

--[[
	Low Angle: Camera looks up at the player
	@param options PresetOptions with fromBehind option
]]
function CameraManager:LowAngle(options: PresetOptions?)
	local character = self:_getTarget(options)
	if not character then return end
	
	local torsoPos = self:_getTorsoPosition(character)
	if not torsoPos then return end
	
	local lookAt = self:_getLookAtPosition(options, character)
	local baseOffset = options and options.offset or Vector3.new(0, -2, 4)
	local offset = self:_adjustOffsetForFacing(baseOffset, character, options and options.fromBehind)
	local duration = options and options.duration or 1
	local fov = options and options.fov or 55
	
	local cameraPos = torsoPos + offset
	local cameraCFrame = CFrame.lookAt(cameraPos, lookAt)
	
	self:_setScriptableMode()
	self:_transitionTo(cameraCFrame, duration, fov, options and options.onComplete)
end

--[[
	High Angle: Camera looks down on the player
	@param options PresetOptions with fromBehind option
]]
function CameraManager:HighAngle(options: PresetOptions?)
	local character = self:_getTarget(options)
	if not character then return end
	
	local torsoPos = self:_getTorsoPosition(character)
	if not torsoPos then return end
	
	local lookAt = self:_getLookAtPosition(options, character)
	local baseOffset = options and options.offset or Vector3.new(0, 5, 4)
	local offset = self:_adjustOffsetForFacing(baseOffset, character, options and options.fromBehind)
	local duration = options and options.duration or 1
	local fov = options and options.fov or 55
	
	local cameraPos = torsoPos + offset
	local cameraCFrame = CFrame.lookAt(cameraPos, lookAt)
	
	self:_setScriptableMode()
	self:_transitionTo(cameraCFrame, duration, fov, options and options.onComplete)
end

-- ============================================
-- ACTION/IMPACT SHOTS
-- ============================================

--[[
	Dynamic Follow Cam: Follows behind player with lag and shake
	@param options PresetOptions with followLag (default 0.15), shakeIntensity (default 0.1), and fromBehind option
]]
function CameraManager:DynamicFollow(options: PresetOptions?)
	local character = self:_getTarget(options)
	if not character then return end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso")
	if not humanoidRootPart then return end
	
	local baseOffset = options and options.offset or Vector3.new(0, 2, 5)
	local followLag = options and options.followLag or 0.15
	local shakeIntensity = options and options.shakeIntensity or 0.1
	local fov = options and options.fov or 65
	
	self:_cancelActive()
	self:_setScriptableMode()
	self._isActive = true
	
	local currentCameraPos = humanoidRootPart.Position + self:_adjustOffsetForFacing(baseOffset, character, options and options.fromBehind)
	
	self._activeConnection = RunService.Heartbeat:Connect(function()
		if not self._isActive or not character.Parent then
			self:_cancelActive()
			return
		end
		
		local currentPos = humanoidRootPart.Position
		local lookAt = self:_getLookAtPosition(options, character)
		
		-- Recalculate offset based on current facing
		local currentOffset = self:_adjustOffsetForFacing(baseOffset, character, options and options.fromBehind)
		local targetCameraPos = currentPos + currentOffset
		
		-- Smooth follow with lag
		currentCameraPos = currentCameraPos:Lerp(targetCameraPos, followLag)
		
		-- Camera shake
		local shakeOffset = Vector3.new(
			(math.random() - 0.5) * shakeIntensity,
			(math.random() - 0.5) * shakeIntensity,
			(math.random() - 0.5) * shakeIntensity
		)
		
		local cameraCFrame = CFrame.lookAt(currentCameraPos + shakeOffset, lookAt)
		
		self._camera.CFrame = cameraCFrame
		if fov then
			self._camera.FieldOfView = fov
		end
	end)
end

--[[
	Zoom-In / Punch-In: Quick zoom on the player or object
	@param options PresetOptions with fromBehind option
]]
function CameraManager:ZoomIn(options: PresetOptions?)
	local character = self:_getTarget(options)
	if not character then return end
	
	local headPos = self:_getHeadPosition(character)
	if not headPos then return end
	
	local lookAt = self:_getLookAtPosition(options, character)
	local baseOffset = options and options.offset or Vector3.new(0, 0, 1.5)
	local offset = self:_adjustOffsetForFacing(baseOffset, character, options and options.fromBehind)
	local duration = options and options.duration or 0.5
	local fov = options and options.fov or 25
	
	local cameraPos = headPos + offset
	local cameraCFrame = CFrame.lookAt(cameraPos, lookAt)
	
	self:_setScriptableMode()
	self:_transitionTo(cameraCFrame, duration, fov, options and options.onComplete)
end

--[[
	Cut-In Shot: Cuts to an object or specific body part
	@param options PresetOptions with subject (the part/object to focus on)
]]
function CameraManager:CutIn(options: PresetOptions?)
	if not options or not options.subject then
		warn("CutIn requires a subject option")
		return
	end
	
	local subject = options.subject
	local subjectPos: Vector3
	
	if subject:IsA("BasePart") then
		subjectPos = subject.Position
	elseif subject:IsA("Model") then
		local part = subject:FindFirstChild("HumanoidRootPart") or subject:FindFirstChild("Torso") or subject:FindFirstChildWhichIsA("BasePart")
		if part then
			subjectPos = part.Position
		else
			return
		end
	else
		return
	end
	
	local lookAt = self:_getLookAtPosition(options, subject:IsA("Model") and subject or nil)
	local offset = options and options.offset or Vector3.new(0, 0, 2)
	local duration = options and options.duration or 0.3
	local fov = options and options.fov or 40
	
	local cameraPos = subjectPos + offset
	local cameraCFrame = CFrame.lookAt(cameraPos, lookAt)
	
	self:_setScriptableMode()
	self:_transitionTo(cameraCFrame, duration, fov, options and options.onComplete)
end

--[[
	POV (Point of View): From the player's perspective
	@param options PresetOptions
]]
function CameraManager:POV(options: PresetOptions?)
	local character = self:_getTarget(options)
	if not character then return end
	
	local head = character:FindFirstChild("Head")
	if not head then return end
	
	local duration = options and options.duration or 0.5
	local fov = options and options.fov or 70
	
	self:_cancelActive()
	self:_setScriptableMode()
	
	-- Attach camera to head
	self._activeConnection = RunService.Heartbeat:Connect(function()
		if not character.Parent or not head.Parent then
			self:_cancelActive()
			return
		end
		
		-- Get head CFrame and look direction
		local headCFrame = head.CFrame
		local lookDirection = headCFrame.LookVector
		
		-- Position camera slightly forward from head
		local cameraPos = headCFrame.Position + (lookDirection * 0.5)
		self._camera.CFrame = CFrame.lookAt(cameraPos, cameraPos + lookDirection)
		
		if fov then
			self._camera.FieldOfView = fov
		end
	end)
	
	-- If duration is set, auto-stop after duration
	if duration and duration > 0 then
		task.spawn(function()
			task.wait(duration)
			if self._isActive then
				self:Stop()
				if options and options.onComplete then
					options.onComplete()
				end
			end
		end)
	end
end

--[[
	Slow Pan: Smoothly pans across the player or scene
	@param options PresetOptions with panDirection (Vector3) and panSpeed (default 1)
]]
function CameraManager:SlowPan(options: PresetOptions?)
	local character = self:_getTarget(options)
	local lookAt = self:_getLookAtPosition(options, character)
	
	local panDirection = options and options.panDirection or Vector3.new(1, 0, 0)
	local panSpeed = options and options.panSpeed or 1
	local startOffset = options and options.offset or Vector3.new(-5, 2, 5)
	local fov = options and options.fov or 60
	
	self:_cancelActive()
	self:_setScriptableMode()
	self._isActive = true
	
	local panDistance = 0
	
	self._activeConnection = RunService.Heartbeat:Connect(function()
		if not self._isActive then
			self:_cancelActive()
			return
		end
		
		panDistance = panDistance + (panSpeed * 0.01)
		local cameraPos = lookAt + startOffset + (panDirection * panDistance)
		local cameraCFrame = CFrame.lookAt(cameraPos, lookAt)
		
		self._camera.CFrame = cameraCFrame
		if fov then
			self._camera.FieldOfView = fov
		end
	end)
end

-- ============================================
-- UTILITY METHODS
-- ============================================

--[[
	Stops all active camera operations
]]
function CameraManager:Stop()
	self:_cancelActive()
end

--[[
	Resets camera to normal gameplay mode
]]
function CameraManager:ResetToGameplay()
	self:Stop()
	self._camera.CameraType = self._originalCameraType
	self._camera.FieldOfView = self._originalFOV
end

--[[
	Transitions camera to a custom CFrame
	@param targetCFrame Target CFrame
	@param duration Transition duration
	@param fov Optional FOV change
	@param onComplete Optional completion callback
]]
function CameraManager:TransitionTo(targetCFrame: CFrame, duration: number, fov: number?, onComplete: (() -> ())?)
	self:_setScriptableMode()
	self:_transitionTo(targetCFrame, duration, fov, onComplete)
end

--[[
	Sets camera to scriptable mode manually
]]
function CameraManager:SetScriptableMode()
	self:_setScriptableMode()
end

--[[
	Cleanup all camera operations
]]
function CameraManager:Cleanup()
	self:Stop()
	self:ResetToGameplay()
end

return CameraManager


--!strict
--[[
	CaptureEffects.lua
	Handles cinematic capture effects for an immersive creature catching experience
	
	Creates tension and engagement through:
	- Progressive FOV narrowing (tunnel vision)
	- Camera lookAt targeting the creature
	- Camera shake with varying intensity
	- Screen vignette darkening
	- Time dilation effects
	- Celebration effects on successful capture
]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CaptureEffects = {}
CaptureEffects.__index = CaptureEffects

export type CaptureEffectsType = typeof(CaptureEffects.new())

-- Configuration for cinematic effects
local CONFIG = {
	-- FOV settings (narrowing creates tension/focus)
	BaseFOV = 45,           -- Normal battle FOV
	FOVDecreasePerScan = 8, -- How much FOV decreases per successful scan
	MinFOV = 25,            -- Minimum FOV at max tension
	FOVTweenTime = 0.4,     -- Time to tween FOV
	
	-- Camera shake (rotational, in radians - very subtle)
	ShakeIntensitySuccess = 0.003,  -- Very subtle shake on success (about 0.17 degrees)
	ShakeIntensityFail = 0.025,     -- Noticeable shake on failure (about 1.4 degrees)
	ShakeDuration = 0.3,
	
	-- Vignette (screen edge darkening)
	VignetteMaxIntensity = 0.6,   -- How dark edges get (0-1)
	VignetteGrowthPerScan = 0.15, -- How much vignette increases per scan
	
	-- Time dilation (brief slow-mo)
	SlowMoScale = 0.4,            -- Time scale during slow-mo
	SlowMoDuration = 0.25,        -- Duration of slow-mo effect
	
	-- Success celebration
	SuccessFlashDuration = 0.3,
	SuccessFOVBurst = 55,         -- FOV snaps wide then settles
	SuccessShakeIntensity = 0.015, -- Subtle celebration shake
	
	-- Colors
	SuccessColor = Color3.fromRGB(80, 180, 255),   -- Blue success
	FailColor = Color3.fromRGB(255, 80, 80),        -- Red failure
	ScanPulseColor = Color3.fromRGB(80, 180, 255),  -- Blue scan pulse
}

--[[
	Creates a new capture effects instance
	@param camera The workspace camera
	@param playerGui The player's GUI
	@param targetCreature Optional target creature model for camera lookAt
	@return CaptureEffects
]]
function CaptureEffects.new(camera: Camera, playerGui: PlayerGui, targetCreature: Model?): CaptureEffectsType
	local self = setmetatable({}, CaptureEffects)
	
	self._camera = camera
	self._playerGui = playerGui
	self._originalFOV = camera.FieldOfView
	self._originalCFrame = camera.CFrame
	self._targetCreature = targetCreature
	
	-- State tracking
	self._successfulScans = 0
	self._isActive = false
	self._shakeConnection = nil
	
	-- UI elements for effects
	self._effectsGui = nil
	self._vignetteFrame = nil
	self._flashFrame = nil
	
	-- Audio
	self._scanSuccessSound = nil
	self._scanFailSound = nil
	self._captureSuccessSound = nil
	
	return self
end

--[[
	Initializes the capture sequence - call when capture cube is used
]]
function CaptureEffects:StartCaptureSequence()
	if self._isActive then
		return
	end
	
	self._isActive = true
	self._successfulScans = 0
	self._originalFOV = self._camera.FieldOfView
	self._originalCFrame = self._camera.CFrame
	
	-- Create effects UI overlay
	self:_createEffectsUI()
	
	-- Setup audio
	self:_setupAudio()
	
	-- Start ambient tension (subtle vignette)
	self:_updateVignette(0.1)
	
	print("[CaptureEffects] Capture sequence started")
end

--[[
	Sets the target creature for camera lookAt effects
	@param targetCreature The creature model to look at
]]
function CaptureEffects:SetTargetCreature(targetCreature: Model?)
	self._targetCreature = targetCreature
end

--[[
	Processes a scan result with full cinematic treatment
	@param success Whether the scan was successful
	@param scanIndex Which scan this is (1, 2, or 3)
	@param onComplete Callback when effects complete
]]
function CaptureEffects:ProcessScan(success: boolean, scanIndex: number, onComplete: (() -> ())?)
	if not self._isActive then
		if onComplete then onComplete() end
		return
	end
	
	print("[CaptureEffects] Processing scan", scanIndex, "success:", success)
	
	if success then
		self._successfulScans = self._successfulScans + 1
		self:_playSuccessScanEffects(scanIndex, onComplete)
	else
		self:_playFailScanEffects(onComplete)
	end
end

--[[
	Plays the final capture success celebration
	@param onComplete Callback when celebration completes
]]
function CaptureEffects:PlayCaptureSuccess(onComplete: (() -> ())?)
	if not self._isActive then
		if onComplete then onComplete() end
		return
	end
	
	print("[CaptureEffects] Playing capture success celebration!")
	
	-- Play success sound
	if self._captureSuccessSound then
		self._captureSuccessSound:Play()
	end
	
	-- Flash blue
	self:_flashScreen(CONFIG.SuccessColor, CONFIG.SuccessFlashDuration)
	
	-- FOV burst effect (snap wide, then settle back to original CFrame)
	local burstTween = TweenService:Create(
		self._camera,
		TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{FieldOfView = CONFIG.SuccessFOVBurst}
	)
	burstTween:Play()
	
	burstTween.Completed:Connect(function()
		-- Gentle settle to normal battle FOV and restore original CFrame
		local settleTween = TweenService:Create(
			self._camera,
			TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{FieldOfView = CONFIG.BaseFOV, CFrame = self._originalCFrame}
		)
		settleTween:Play()
	end)
	
	-- Shake with celebration intensity
	self:_shakeCamera(CONFIG.SuccessShakeIntensity, 0.4)
	
	-- Fade out vignette
	self:_tweenVignette(0, 0.5)
	
	-- Cleanup after effects
	task.delay(0.8, function()
		self:EndCaptureSequence()
		if onComplete then onComplete() end
	end)
end

--[[
	Ends the capture sequence and cleans up
]]
function CaptureEffects:EndCaptureSequence()
	if not self._isActive then
		return
	end
	
	print("[CaptureEffects] Ending capture sequence")
	
	self._isActive = false
	self._successfulScans = 0
	
	-- Stop effects
	self:_stopShake()
	
	-- Cleanup UI
	if self._effectsGui then
		self._effectsGui:Destroy()
		self._effectsGui = nil
	end
	
	-- Cleanup audio
	self:_cleanupAudio()
	
	-- Reset FOV and CFrame smoothly
	TweenService:Create(
		self._camera,
		TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{FieldOfView = CONFIG.BaseFOV, CFrame = self._originalCFrame}
	):Play()
end

--[[
	Internal: Creates the effects UI overlay
]]
function CaptureEffects:_createEffectsUI()
	-- Remove existing if any
	if self._effectsGui then
		self._effectsGui:Destroy()
	end
	
	-- Create ScreenGui for effects
	local gui = Instance.new("ScreenGui")
	gui.Name = "CaptureEffects"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100 -- Above most UI
	gui.ResetOnSpawn = false
	gui.Parent = self._playerGui
	
	-- Vignette frame (radial gradient for edge darkening)
	local vignette = Instance.new("ImageLabel")
	vignette.Name = "Vignette"
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.Position = UDim2.fromScale(0, 0)
	vignette.BackgroundTransparency = 1
	vignette.Image = "rbxassetid://1316045217" -- Standard vignette asset
	vignette.ImageColor3 = Color3.new(0, 0, 0)
	vignette.ImageTransparency = 1 -- Start invisible
	vignette.ScaleType = Enum.ScaleType.Stretch
	vignette.ZIndex = 1
	vignette.Parent = gui
	
	-- Flash frame for success/fail flashes
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.Position = UDim2.fromScale(0, 0)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1 -- Start invisible
	flash.BorderSizePixel = 0
	flash.ZIndex = 2
	flash.Parent = gui
	
	-- Pulse overlay for scan effects
	local pulse = Instance.new("Frame")
	pulse.Name = "ScanPulse"
	pulse.Size = UDim2.fromScale(1, 1)
	pulse.Position = UDim2.fromScale(0, 0)
	pulse.BackgroundColor3 = CONFIG.ScanPulseColor
	pulse.BackgroundTransparency = 1
	pulse.BorderSizePixel = 0
	pulse.ZIndex = 3
	pulse.Parent = gui
	
	self._effectsGui = gui
	self._vignetteFrame = vignette
	self._flashFrame = flash
	self._pulseFrame = pulse
end

--[[
	Internal: Setup audio for capture effects
]]
function CaptureEffects:_setupAudio()
	-- Create scan success sound
	local scanSuccess = Instance.new("Sound")
	scanSuccess.Name = "ScanSuccess"
	scanSuccess.SoundId = "rbxassetid://6895079853" -- Digital success beep
	scanSuccess.Volume = 0.6
	scanSuccess.PlaybackSpeed = 1.2
	scanSuccess.Parent = workspace
	self._scanSuccessSound = scanSuccess
	
	-- Create scan fail sound
	local scanFail = Instance.new("Sound")
	scanFail.Name = "ScanFail"
	scanFail.SoundId = "rbxassetid://4590657391" -- Error/fail buzz
	scanFail.Volume = 0.7
	scanFail.Parent = workspace
	self._scanFailSound = scanFail
	
	-- Create capture success fanfare
	local captureSuccess = Instance.new("Sound")
	captureSuccess.Name = "CaptureSuccess"
	captureSuccess.SoundId = "rbxassetid://5153734236" -- Victory chime
	captureSuccess.Volume = 0.8
	captureSuccess.Parent = workspace
	self._captureSuccessSound = captureSuccess
end

--[[
	Internal: Cleanup audio instances
]]
function CaptureEffects:_cleanupAudio()
	if self._scanSuccessSound then
		self._scanSuccessSound:Destroy()
		self._scanSuccessSound = nil
	end
	if self._scanFailSound then
		self._scanFailSound:Destroy()
		self._scanFailSound = nil
	end
	if self._captureSuccessSound then
		self._captureSuccessSound:Destroy()
		self._captureSuccessSound = nil
	end
end

--[[
	Internal: Plays success scan effects
]]
function CaptureEffects:_playSuccessScanEffects(scanIndex: number, onComplete: (() -> ())?)
	-- Play scan success sound
	if self._scanSuccessSound then
		-- Pitch up slightly with each scan for rising tension
		self._scanSuccessSound.PlaybackSpeed = 1.0 + (scanIndex * 0.15)
		self._scanSuccessSound:Play()
	end
	
	-- Decrease FOV (tunnel vision effect)
	local targetFOV = math.max(
		CONFIG.MinFOV,
		CONFIG.BaseFOV - (self._successfulScans * CONFIG.FOVDecreasePerScan)
	)
	
	-- Calculate lookAt CFrame if we have a target creature (rotation only, preserve position)
	local targetCFrame = self._camera.CFrame
	if self._targetCreature then
		local targetPart = self._targetCreature.PrimaryPart or self._targetCreature:FindFirstChildWhichIsA("BasePart")
		if targetPart then
			local cameraPos = self._camera.CFrame.Position
			local targetPos = targetPart.Position
			-- Get the lookAt CFrame but preserve original position
			local lookAtCFrame = CFrame.lookAt(cameraPos, targetPos)
			targetCFrame = CFrame.new(cameraPos) * lookAtCFrame.Rotation
		end
	end
	
	-- Tween camera rotation toward creature with FOV decrease (position unchanged)
	local cameraTween = TweenService:Create(
		self._camera,
		TweenInfo.new(CONFIG.FOVTweenTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{FieldOfView = targetFOV, CFrame = targetCFrame}
	)
	cameraTween:Play()
	
	-- Increase vignette intensity
	local vignetteIntensity = math.min(
		CONFIG.VignetteMaxIntensity,
		self._successfulScans * CONFIG.VignetteGrowthPerScan
	)
	self:_tweenVignette(vignetteIntensity, CONFIG.FOVTweenTime)
	
	-- Brief slow-motion effect
	self:_doSlowMotion()
	
	-- Flash screen with success color
	self:_flashScreen(CONFIG.SuccessColor, 0.2)
	
	-- Subtle camera shake (rotational only, doesn't interfere with tweens)
	self:_shakeCamera(CONFIG.ShakeIntensitySuccess, CONFIG.ShakeDuration)
	
	-- Pulse effect
	self:_doPulse(CONFIG.SuccessColor)
	
	-- Complete after effects settle
	if onComplete then
		task.delay(CONFIG.FOVTweenTime + 0.1, onComplete)
	end
end

--[[
	Internal: Plays failure scan effects
]]
function CaptureEffects:_playFailScanEffects(onComplete: (() -> ())?)
	-- Play fail sound
	if self._scanFailSound then
		self._scanFailSound:Play()
	end
	
	-- Flash red
	self:_flashScreen(CONFIG.FailColor, 0.3)
	
	-- Strong camera shake
	self:_shakeCamera(CONFIG.ShakeIntensityFail, CONFIG.ShakeDuration * 1.5)
	
	-- Snap FOV and CFrame back to original (jarring effect)
	local cameraTween = TweenService:Create(
		self._camera,
		TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{FieldOfView = CONFIG.BaseFOV, CFrame = self._originalCFrame}
	)
	cameraTween:Play()
	
	-- Fade vignette quickly
	self:_tweenVignette(0, 0.3)
	
	-- End sequence after shake
	if onComplete then
		task.delay(0.5, function()
			self:EndCaptureSequence()
			onComplete()
		end)
	end
end

--[[
	Internal: Updates vignette intensity instantly
]]
function CaptureEffects:_updateVignette(intensity: number)
	if self._vignetteFrame then
		self._vignetteFrame.ImageTransparency = 1 - intensity
	end
end

--[[
	Internal: Tweens vignette to target intensity
]]
function CaptureEffects:_tweenVignette(intensity: number, duration: number)
	if not self._vignetteFrame then
		return
	end
	
	TweenService:Create(
		self._vignetteFrame,
		TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ImageTransparency = 1 - intensity}
	):Play()
end

--[[
	Internal: Flashes the screen with a color
]]
function CaptureEffects:_flashScreen(color: Color3, duration: number)
	if not self._flashFrame then
		return
	end
	
	self._flashFrame.BackgroundColor3 = color
	self._flashFrame.BackgroundTransparency = 0.5
	
	-- Quick fade out
	TweenService:Create(
		self._flashFrame,
		TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{BackgroundTransparency = 1}
	):Play()
end

--[[
	Internal: Shakes the camera using rotational offsets (doesn't interfere with tweens)
	Uses rotation only so it can run simultaneously with CFrame/FOV tweens
]]
function CaptureEffects:_shakeCamera(intensity: number, duration: number)
	self:_stopShake()
	
	local startTime = os.clock()
	-- Store the last applied shake offset so we can remove it
	local lastShakeOffset = CFrame.new()
	
	self._shakeConnection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startTime
		if elapsed >= duration then
			-- Remove the last shake offset before stopping
			self._camera.CFrame = self._camera.CFrame * lastShakeOffset:Inverse()
			self:_stopShake()
			return
		end
		
		-- Remove previous frame's shake offset
		local baseCFrame = self._camera.CFrame * lastShakeOffset:Inverse()
		
		-- Decay intensity over time
		local progress = elapsed / duration
		local currentIntensity = intensity * (1 - progress)
		
		-- Random rotational shake (in radians)
		local shakeX = (math.random() - 0.5) * 2 * currentIntensity
		local shakeY = (math.random() - 0.5) * 2 * currentIntensity
		
		-- Create new shake offset (rotation only)
		lastShakeOffset = CFrame.Angles(shakeX, shakeY, 0)
		
		-- Apply shake on top of whatever the current camera position/rotation is
		self._camera.CFrame = baseCFrame * lastShakeOffset
	end)
end

--[[
	Internal: Stops camera shake
]]
function CaptureEffects:_stopShake()
	if self._shakeConnection then
		self._shakeConnection:Disconnect()
		self._shakeConnection = nil
	end
end

--[[
	Internal: Brief slow motion effect
]]
function CaptureEffects:_doSlowMotion()
	-- Note: Roblox doesn't have native time scale, so we simulate
	-- the feel through other effects. This is a placeholder for
	-- potential future implementation or can be used with custom
	-- animation playback speed adjustments.
	
	-- For now, we create a "freeze frame" feel with a brief pause
	-- in the vignette pulse
end

--[[
	Internal: Quick pulse effect overlay
]]
function CaptureEffects:_doPulse(color: Color3)
	if not self._pulseFrame then
		return
	end
	
	self._pulseFrame.BackgroundColor3 = color
	self._pulseFrame.BackgroundTransparency = 0.7
	
	TweenService:Create(
		self._pulseFrame,
		TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{BackgroundTransparency = 1}
	):Play()
end

--[[
	Cleanup all effects
]]
function CaptureEffects:Cleanup()
	self:EndCaptureSequence()
end

return CaptureEffects


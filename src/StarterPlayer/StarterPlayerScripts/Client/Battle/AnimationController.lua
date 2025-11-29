--!strict
--[[
	AnimationController.lua
	Manages battle animations and tweens
	Provides centralized animation control with proper cleanup
]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local AnimationController = {}
AnimationController.__index = AnimationController

export type TweenCallback = () -> ()

--[[
	Creates a new animation controller instance
	@return AnimationController
]]
function AnimationController.new(): any
	local self = setmetatable({}, AnimationController)
	
	self._activeTweens = {} :: {Tween}
	self._activeAnimations = {} :: {AnimationTrack}
	self._cameraVersion = 0
	self._cameraCycleRunning = false
	self._idleTracks = {} :: {[Model]: AnimationTrack}
	self._idleSpeed = {} :: {[Model]: number}
	self._frozenTracks = {} :: {[Model]: AnimationTrack}  -- Track frozen animation tracks
	self._frozenTimePositions = {} :: {[Model]: number}  -- Store time position when frozen
	self._frozenModels = {} :: {[Model]: boolean}  -- Track which models are frozen
	
	return self
end

--[[
	Plays an animation on a creature model
	@param model The creature model
	@param animationName The animation name
	@param onComplete Callback when animation completes (optional)
	@return AnimationTrack? The animation track
]]
function AnimationController:PlayAnimation(model: Model, animationName: string, onComplete: (() -> ())?): AnimationTrack?
	if not model or not animationName then
		return nil
	end
	
	-- Check if creature is frozen - prevent attack/damaged animations
	local nameLower = string.lower(animationName)
	local isActionAnimation = nameLower == "attack" or nameLower == "damaged" or nameLower == "damage"
	if isActionAnimation and self._frozenModels[model] then
		print("[AnimationController] PlayAnimation: Creature is frozen, blocking", animationName, "animation")
		-- Still call onComplete callback to prevent hanging
		if onComplete then
			task.spawn(onComplete)
		end
		return nil
	end
	
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	
	-- Find animation in model
	local animation = model:FindFirstChild(animationName, true)
	if not animation or not animation:IsA("Animation") then
		return nil
	end
	
    local track = animator:LoadAnimation(animation)
    -- Set priority based on animation type
    if nameLower == "idle" then
        track.Priority = Enum.AnimationPriority.Idle
        track.Looped = true
    elseif isActionAnimation then
        track.Priority = Enum.AnimationPriority.Action4
    end
	
	-- Handle animation completion if callback provided
	if onComplete then
		track.Stopped:Connect(function()
			-- Remove from active animations
			local index = table.find(self._activeAnimations, track)
			if index then
				table.remove(self._activeAnimations, index)
			end
			
			onComplete()
		end)
	end
	
	track:Play()
	table.insert(self._activeAnimations, track)
	
	return track
end

--[[
	Plays an animation with Hit marker support
	@param model The creature model
	@param animationName The animation name
	@param onHit Callback when Hit marker is reached (optional)
	@param onComplete Callback when animation completes (optional)
	@return AnimationTrack? The animation track
]]
function AnimationController:PlayAnimationWithHit(
	model: Model, 
	animationName: string, 
	onHit: (() -> ())?, 
	onComplete: (() -> ())?
): AnimationTrack?
	if not model or not animationName then
		if onComplete then
			onComplete()
		end
		return nil
	end
	
	-- Check if creature is frozen - prevent attack animations
	local nameLower = string.lower(animationName)
	if nameLower == "attack" and self._frozenModels[model] then
		print("[AnimationController] PlayAnimationWithHit: Creature is frozen, blocking attack animation")
		-- Still call callbacks to prevent hanging
		if onHit then
			task.spawn(onHit)
		end
		if onComplete then
			task.spawn(onComplete)
		end
		return nil
	end
	
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		if onComplete then
			onComplete()
		end
		return nil
	end
	
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		if onComplete then
			onComplete()
		end
		return nil
	end
	
	-- Find animation in model
	local animation = model:FindFirstChild(animationName, true)
	if not animation or not animation:IsA("Animation") then
		if onComplete then
			onComplete()
		end
		return nil
	end
	
    local track = animator:LoadAnimation(animation)
    -- Set priority based on animation type
    local nameLower = string.lower(animationName)
    if nameLower == "idle" then
        track.Priority = Enum.AnimationPriority.Idle
        track.Looped = true
    elseif nameLower == "attack" or nameLower == "damaged" or nameLower == "damage" then
        track.Priority = Enum.AnimationPriority.Action4
    end
	
	-- Bind to Hit marker if available
	local ok, signal = pcall(function() return track:GetMarkerReachedSignal("Hit") end)
	if ok and signal then
		signal:Connect(function()
			print("[AnimationController] Attack HIT marker reached:", model.Name)
			if onHit then
				onHit()
			end
		end)
	else
		-- Fallback: trigger onHit after a delay if no marker
		task.delay(0.25, function()
			print("[AnimationController] Attack fallback HIT (no marker):", model.Name)
			if onHit then
				onHit()
			end
		end)
	end
	
	-- Handle animation completion
	track.Stopped:Connect(function()
		-- Remove from active animations
		local index = table.find(self._activeAnimations, track)
		if index then
			table.remove(self._activeAnimations, index)
		end
		
		if onComplete then
			onComplete()
		end
	end)
	
	track:Play()
	table.insert(self._activeAnimations, track)
	
	return track
end

--[[
	Updates idle animation speed based on creature HP
	@param model The creature model
	@param currentHP Current HP value
	@param maxHP Maximum HP value
]]
function AnimationController:UpdateIdleSpeed(model: Model, currentHP: number, maxHP: number)
	if not model or not currentHP or not maxHP then
		return
	end
	
	local hpPercentage = currentHP / maxHP
	local speedMultiplier = 1.0
	
	-- If HP is very low (below 25%), slow down the idle animation
	if hpPercentage <= 0.25 then
		speedMultiplier = 0.5
	elseif hpPercentage <= 0.5 then
		speedMultiplier = 0.75
	end
	
	-- Persist desired speed for future idle restarts
	self._idleSpeed[model] = speedMultiplier
	
	-- Get existing idle track for this model
	local idleTrack = self._idleTracks[model]
	if idleTrack and idleTrack.IsPlaying then
		pcall(function() idleTrack:AdjustSpeed(speedMultiplier) end)
		print("[AnimationController] Updated idle speed for", model.Name, "to", speedMultiplier, "x (HP:", currentHP, "/", maxHP, ")")
	end
end

--[[
	Plays idle animation and stores track for speed updates
	@param model The creature model
	@return AnimationTrack? The idle animation track
]]
function AnimationController:PlayIdleAnimation(model: Model): AnimationTrack?
	if not model then
		return nil
	end
	
	-- Check if we already have a playing idle track for this model
	local existingTrack = self._idleTracks[model]
	if existingTrack and existingTrack.IsPlaying then
		-- Already playing idle, don't create a new one
		return existingTrack
	end
	
	-- Stop any existing idle-priority tracks to prevent double-idle
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator then
		-- Get all playing tracks and stop idle ones (check by priority AND by animation name)
		local playingTracks = animator:GetPlayingAnimationTracks()
		for _, t in ipairs(playingTracks) do
			-- Stop if it's idle priority OR if it's an idle animation (regardless of priority)
			local isIdle = t.Priority == Enum.AnimationPriority.Idle
			if not isIdle then
				-- Check if the animation itself is named "Idle"
				local anim = t.Animation
				if anim and string.lower(anim.Name) == "idle" then
					isIdle = true
				end
			end
			
			if isIdle then
				pcall(function() 
					t:Stop(0.1)
					-- Remove from active animations if it's there
					local index = table.find(self._activeAnimations, t)
					if index then
						table.remove(self._activeAnimations, index)
					end
				end)
			end
		end
	end
	
	-- Stop existing tracked idle (even if not playing)
	if existingTrack then
		pcall(function() existingTrack:Stop(0.1) end)
		-- Remove from active animations if it's there
		local index = table.find(self._activeAnimations, existingTrack)
		if index then
			table.remove(self._activeAnimations, index)
		end
	end
	
	-- Wait a frame to ensure stops have processed
	task.wait()
	
	-- Play new idle animation
	local track = self:PlayAnimation(model, "Idle")
	if track then
		self._idleTracks[model] = track
		-- Reapply last known idle speed if available
		local spd = self._idleSpeed[model]
		if type(spd) == "number" and spd > 0 then
			pcall(function() track:AdjustSpeed(spd) end)
		end
	end
	
	return track
end

--[[
	Stops an animation
	@param track The animation track to stop
]]
function AnimationController:StopAnimation(track: AnimationTrack?)
	if not track then
		return
	end
	
	track:Stop()
	
	-- Remove from active animations
	local index = table.find(self._activeAnimations, track)
	if index then
		table.remove(self._activeAnimations, index)
	end
end

--[[
	Freezes a creature's animation at the current frame
	@param model The creature model to freeze
]]
function AnimationController:FreezeAnimation(model: Model)
	if not model then
		return
	end
	
	-- Mark model as frozen
	self._frozenModels[model] = true
	
	-- Get the idle track for this model
	local idleTrack = self._idleTracks[model]
	if not idleTrack or not idleTrack.IsPlaying then
		-- If no idle track, try to get any playing animation
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local playingTracks = animator:GetPlayingAnimationTracks()
			for _, track in ipairs(playingTracks) do
				if track.IsPlaying then
					idleTrack = track
					break
				end
			end
		end
	end
	
	if idleTrack and idleTrack.IsPlaying then
		-- Store the current time position
		local timePos = idleTrack.TimePosition
		self._frozenTimePositions[model] = timePos
		self._frozenTracks[model] = idleTrack
		
		-- Stop the animation and set it to loop at the frozen frame
		idleTrack.Looped = false
		idleTrack:AdjustSpeed(0)  -- Set speed to 0 to freeze
		
		print("[AnimationController] Frozen animation for", model.Name, "at time position", timePos)
	else
		warn("[AnimationController] No playing animation found to freeze for", model.Name)
	end
end

--[[
	Unfreezes a creature's animation and resumes normal playback
	@param model The creature model to unfreeze
]]
function AnimationController:UnfreezeAnimation(model: Model)
	if not model then
		return
	end
	
	-- Clear frozen flag
	self._frozenModels[model] = nil
	
	local frozenTrack = self._frozenTracks[model]
	if frozenTrack then
		-- Restore normal speed
		frozenTrack:AdjustSpeed(1)
		frozenTrack.Looped = true
		
		-- Clear frozen state
		self._frozenTracks[model] = nil
		self._frozenTimePositions[model] = nil
		
		print("[AnimationController] Unfrozen animation for", model.Name)
	else
		-- If no frozen track, just ensure idle is playing normally
		self:PlayIdleAnimation(model)
	end
end

--[[
	Creates and plays a tween
	@param instance The instance to tween
	@param tweenInfo The tween info
	@param properties The properties to tween
	@param onComplete Optional callback when tween completes
	@return Tween The created tween
]]
function AnimationController:CreateTween(
	instance: Instance,
	tweenInfo: TweenInfo,
	properties: {[string]: any},
	onComplete: TweenCallback?
): Tween
	local tween = TweenService:Create(instance, tweenInfo, properties)
	
	table.insert(self._activeTweens, tween)
	
	if onComplete then
		tween.Completed:Connect(function()
			onComplete()
			self:_removeTween(tween)
		end)
	else
		tween.Completed:Connect(function()
			self:_removeTween(tween)
		end)
	end
	
	tween:Play()
	
	return tween
end

--[[
	Cancels a tween
	@param tween The tween to cancel
]]
function AnimationController:CancelTween(tween: Tween?)
	if not tween then
		return
	end
	
	tween:Cancel()
	self:_removeTween(tween)
end

--[[
	Tweens a model's scale
	@param model The model to scale
	@param startScale Starting scale
	@param endScale Ending scale
	@param duration Duration in seconds
	@param onComplete Optional callback
]]
function AnimationController:TweenModelScale(
	model: Model,
	startScale: number,
	endScale: number,
	duration: number,
	onComplete: TweenCallback?
)
	if not model or not model.PrimaryPart then
		if onComplete then
			onComplete()
		end
		return
	end
	
	local elapsed = 0
	local connection
	
	connection = RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime
		local alpha = math.min(elapsed / duration, 1)
		local currentScale = startScale + (endScale - startScale) * alpha
		
		model:ScaleTo(currentScale)
		
		if alpha >= 1 then
			if connection then
				connection:Disconnect()
			end
			if onComplete then
				onComplete()
			end
		end
	end)
end

--[[
	Slides a UI element out of view
	@param frame The UI frame
	@param direction "left" or "right"
	@param duration Duration in seconds
	@param onComplete Optional callback
]]
function AnimationController:SlideUIOut(
	frame: GuiObject,
	direction: string,
	duration: number?,
	onComplete: TweenCallback?
)
	if not frame then
		if onComplete then
			onComplete()
		end
		return
	end
	
	local tweenDuration = duration or 0.5
	local originalPosition = frame.Position
	local targetX = direction == "left" and -1000 or 1000
	
	self:CreateTween(
		frame,
		TweenInfo.new(tweenDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{Position = UDim2.new(0, targetX, originalPosition.Y.Scale, originalPosition.Y.Offset)},
		onComplete
	)
end

--[[
	Slides a UI element into view
	@param frame The UI frame
	@param targetPosition The target position
	@param duration Duration in seconds
	@param onComplete Optional callback
]]
function AnimationController:SlideUIIn(
	frame: GuiObject,
	targetPosition: UDim2,
	duration: number?,
	onComplete: TweenCallback?
)
	if not frame then
		if onComplete then
			onComplete()
		end
		return
	end
	
	local tweenDuration = duration or 0.5
	
	self:CreateTween(
		frame,
		TweenInfo.new(tweenDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{Position = targetPosition},
		onComplete
	)
end

--[[
	Starts a camera cycle animation
	@param camera The camera
	@param positions Array of CFrames to cycle through
	@param duration Duration for each transition
]]
function AnimationController:StartCameraCycle(
	camera: Camera,
	positions: {CFrame},
	duration: number
)
	self:StopCameraCycle()
	
	self._cameraCycleRunning = true
	self._cameraVersion += 1
	local currentVersion = self._cameraVersion
	
	task.spawn(function()
		local index = 1
		
		while self._cameraCycleRunning and currentVersion == self._cameraVersion do
			local targetCFrame = positions[index]
			
			if targetCFrame then
				local tween = self:CreateTween(
					camera,
					TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{CFrame = targetCFrame}
				)
				
				tween.Completed:Wait()
			end
			
			index = (index % #positions) + 1
			task.wait(0.1)
		end
	end)
end

--[[
	Stops the camera cycle animation
]]
function AnimationController:StopCameraCycle()
	self._cameraCycleRunning = false
	self._cameraVersion += 1
end

--[[
	Cleans up all active animations and tweens
]]
function AnimationController:Cleanup()
	-- Stop all animations
	for _, track in ipairs(self._activeAnimations) do
		if track then
			track:Stop()
		end
	end
	self._activeAnimations = {}
	
	-- Cancel all tweens
	for _, tween in ipairs(self._activeTweens) do
		if tween then
			tween:Cancel()
		end
	end
	self._activeTweens = {}
	
	-- Stop camera cycle
	self:StopCameraCycle()
end

--[[
	Internal: Removes a tween from active list
]]
function AnimationController:_removeTween(tween: Tween)
	local index = table.find(self._activeTweens, tween)
	if index then
		table.remove(self._activeTweens, index)
	end
end

return AnimationController

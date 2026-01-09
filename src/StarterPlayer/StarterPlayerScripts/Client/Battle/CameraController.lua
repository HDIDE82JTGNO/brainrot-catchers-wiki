--!strict
--[[
	CameraController.lua
	Manages battle camera positioning, transitions, and cycles
	Provides clean interface for all camera operations
]]

local TweenService = game:GetService("TweenService")

local CameraController = {}
CameraController.__index = CameraController

export type CameraControllerType = typeof(CameraController.new())

--[[
	Creates a new camera controller instance
	@param camera The workspace camera
	@param battleScene The battle scene model
	@return CameraController
]]
function CameraController.new(camera: Camera, battleScene: Model): any
	local self = setmetatable({}, CameraController)
	
	self._camera = camera
	self._battleScene = battleScene
	self._cameraPositions = {}
	self._activeTween = nil
	self._cycleRunning = false
	self._cycleVersion = 0
	self._isCleaningUp = false
	self._tweenConnections = {} -- Track all tween completion connections
	
	-- Cache camera positions from scene
	self:_cacheCameraPositions()
	
	return self
end

--[[
	Sets camera to a specific position
	@param positionName Name of the position (Default, FoeZoomOut, etc.)
	@param index Position index if multiple exist
	@param instant Whether to snap instantly or tween
]]
function CameraController:SetPosition(positionName: string, index: number?, instant: boolean?)
	local positions = self._cameraPositions[positionName]
	if not positions or #positions == 0 then
		warn("Camera position not found:", positionName)
		return
	end
	
	local targetIndex = index or 1
	local cameraPosition = positions[targetIndex]
	if not cameraPosition then
		warn("Camera position index not found:", positionName, targetIndex)
		return
	end
	
	if instant then
		self._camera.CFrame = cameraPosition.CFrame
	else
		self:TransitionTo(cameraPosition.CFrame, 0.5)
	end
end

--[[
	Transitions camera to a specific CFrame
	@param targetCFrame The target CFrame
	@param duration Duration in seconds
	@param onComplete Optional callback
]]
function CameraController:TransitionTo(targetCFrame: CFrame, duration: number, onComplete: (() -> ())?)
	-- Prevent new tweens during cleanup
	if self._isCleaningUp then
		return
	end
	
	if self._activeTween then
		self._activeTween:Cancel()
		self._activeTween = nil
	end
	
	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.InOut
	)
	
	self._activeTween = TweenService:Create(self._camera, tweenInfo, {CFrame = targetCFrame})
	
	if onComplete then
		self._activeTween.Completed:Connect(function()
			onComplete()
		end)
	end
	
	self._activeTween:Play()
end

--[[
	Starts camera cycle animation between positions
	@param positionName Name of the position set to cycle
	@param duration Duration for each transition
]]
function CameraController:StartCycle(positionName: string, duration: number)
	self:StopCycle()
	
	local positions = self._cameraPositions[positionName]
	if not positions or #positions == 0 then
		return
	end
	
	-- Reset cleanup flag when starting a new cycle
	self._isCleaningUp = false
	
	self._cycleRunning = true
	self._cycleVersion = self._cycleVersion + 1
	local currentVersion = self._cycleVersion
	
	task.spawn(function()
		local index = 1
		
		while self._cycleRunning and currentVersion == self._cycleVersion and not self._isCleaningUp do
			local cameraPosition = positions[index]
			if cameraPosition then
				-- Check cleanup flag before creating tween
				if self._isCleaningUp then
					break
				end
				
				if self._activeTween then
					self._activeTween:Cancel()
					self._activeTween = nil
				end
				
				-- Check cleanup flag again before creating new tween
				if self._isCleaningUp then
					break
				end
				
				local tweenInfo = TweenInfo.new(
					duration,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.InOut
				)
				
				self._activeTween = TweenService:Create(self._camera, tweenInfo, {CFrame = cameraPosition.CFrame})
				self._activeTween:Play()
				
				-- Wait for tween completion instead of using task.wait
				local tweenCompleted = false
				local connection
				connection = self._activeTween.Completed:Connect(function()
					tweenCompleted = true
					if connection then
						connection:Disconnect()
						-- Remove from tracked connections
						local idx = table.find(self._tweenConnections, connection)
						if idx then
							table.remove(self._tweenConnections, idx)
						end
					end
				end)
				
				-- Track this connection
				table.insert(self._tweenConnections, connection)
				
				-- Wait for completion or until cycle is stopped
				while not tweenCompleted and self._cycleRunning and currentVersion == self._cycleVersion and not self._isCleaningUp do
					task.wait(0.05)
				end
				
				if connection then
					connection:Disconnect()
					-- Remove from tracked connections
					local idx = table.find(self._tweenConnections, connection)
					if idx then
						table.remove(self._tweenConnections, idx)
					end
				end
				
				-- Small delay before next transition
				if self._cycleRunning and currentVersion == self._cycleVersion and not self._isCleaningUp then
					task.wait(0.1)
				end
			end
			
			-- Increment index for next position
			index = (index % #positions) + 1
		end
		
		-- Clear active tween reference when cycle exits
		if self._activeTween and currentVersion == self._cycleVersion then
			self._activeTween = nil
		end
	end)
end

--[[
	Stops camera cycle animation
]]
function CameraController:StopCycle()
	self._cycleRunning = false
	self._cycleVersion = self._cycleVersion + 1
	
	-- Cancel active tween immediately
	if self._activeTween then
		self._activeTween:Cancel()
		self._activeTween = nil
	end
	
	-- Disconnect all tracked tween connections
	for _, connection in ipairs(self._tweenConnections) do
		if connection then
			connection:Disconnect()
		end
	end
	self._tweenConnections = {}
end

--[[
	Starts cycling through all camera position sets (Pokemon Sword style)
	Cycles through: Default → FriendlyZoomOut → ToSide → ToSide2 → BirdsEye → FoeZoomOut → (repeat)
	@param duration Duration for each transition in seconds
]]
function CameraController:StartCycleAll(duration: number)
	self:StopCycle()
	
	-- Define the order of position sets to cycle through
	local positionOrder = {"Default", "FriendlyZoomOut", "ToSide", "ToSide2", "BirdsEye", "FoeZoomOut"}
	
	-- Filter to only include positions that exist
	local availablePositions = {}
	for _, positionName in ipairs(positionOrder) do
		if self._cameraPositions[positionName] and #self._cameraPositions[positionName] > 0 then
			table.insert(availablePositions, positionName)
		end
	end
	
	if #availablePositions == 0 then
		warn("[CameraController] No camera positions available for cycling")
		return
	end
	
	-- Reset cleanup flag when starting a new cycle
	self._isCleaningUp = false
	
	self._cycleRunning = true
	self._cycleVersion = self._cycleVersion + 1
	local currentVersion = self._cycleVersion
	
	task.spawn(function()
		local positionSetIndex = 1
		local previousPositionSetName = nil
		
		while self._cycleRunning and currentVersion == self._cycleVersion and not self._isCleaningUp do
			local positionSetName = availablePositions[positionSetIndex]
			local positions = self._cameraPositions[positionSetName]
			
			if positions and #positions > 0 then
				-- Cycle through all positions in this set
				for positionIndex = 1, #positions do
					if not (self._cycleRunning and currentVersion == self._cycleVersion and not self._isCleaningUp) then
						break
					end
					
					local cameraPosition = positions[positionIndex]
					if cameraPosition then
						-- Check if we're transitioning to a new position set (instant) or within same set (tween)
						local isNewPositionSet = (previousPositionSetName ~= positionSetName)
						local isFirstPositionInSet = (positionIndex == 1)
						local shouldTween = not (isNewPositionSet and isFirstPositionInSet)
						
						-- Check cleanup flag before creating tween
						if self._isCleaningUp then
							break
						end
						
						if self._activeTween then
							self._activeTween:Cancel()
							self._activeTween = nil
						end
						
						if shouldTween then
							-- Check cleanup flag again before creating new tween
							if self._isCleaningUp then
								break
							end
							
							-- Tween within the same position set (e.g., 1→2)
							local tweenInfo = TweenInfo.new(
								duration,
								Enum.EasingStyle.Quad,
								Enum.EasingDirection.InOut
							)
							
							self._activeTween = TweenService:Create(self._camera, tweenInfo, {CFrame = cameraPosition.CFrame})
							self._activeTween:Play()
							
							-- Wait for tween completion
							local tweenCompleted = false
							local connection
							connection = self._activeTween.Completed:Connect(function()
								tweenCompleted = true
								if connection then
									connection:Disconnect()
									-- Remove from tracked connections
									local idx = table.find(self._tweenConnections, connection)
									if idx then
										table.remove(self._tweenConnections, idx)
									end
								end
							end)
							
							-- Track this connection
							table.insert(self._tweenConnections, connection)
							
							-- Wait for completion or until cycle is stopped
							while not tweenCompleted and self._cycleRunning and currentVersion == self._cycleVersion and not self._isCleaningUp do
								task.wait(0.05)
							end
							
							if connection then
								connection:Disconnect()
								-- Remove from tracked connections
								local idx = table.find(self._tweenConnections, connection)
								if idx then
									table.remove(self._tweenConnections, idx)
								end
							end
							
							-- Small delay before next transition
							if self._cycleRunning and currentVersion == self._cycleVersion and not self._isCleaningUp then
								task.wait(0.1)
							end
						else
							-- Instant transition to first position of new set
							self._camera.CFrame = cameraPosition.CFrame
							-- Small delay before next transition
							if self._cycleRunning and currentVersion == self._cycleVersion and not self._isCleaningUp then
								task.wait(0.1)
							end
						end
						
						-- Update previous position set name after processing
						previousPositionSetName = positionSetName
					end
				end
			end
			
			-- Move to next position set
			positionSetIndex = (positionSetIndex % #availablePositions) + 1
		end
		
		-- Clear active tween reference when cycle exits
		if self._activeTween and currentVersion == self._cycleVersion then
			self._activeTween = nil
		end
	end)
end

--[[
	Stops cycle and returns camera to Default position
]]
function CameraController:ReturnToDefault()
	-- Set cleanup flag temporarily to prevent new tweens from starting
	self._isCleaningUp = true
	
	-- Stop cycle (non-blocking)
	self._cycleRunning = false
	self._cycleVersion = self._cycleVersion + 1
	
	-- Cancel active tween immediately
	if self._activeTween then
		self._activeTween:Cancel()
		self._activeTween = nil
	end
	
	-- Disconnect all tracked tween connections
	for _, connection in ipairs(self._tweenConnections) do
		if connection then
			connection:Disconnect()
		end
	end
	self._tweenConnections = {}
	
	-- Check if Default position exists
	local defaultPositions = self._cameraPositions["Default"]
	if defaultPositions and #defaultPositions > 0 then
		local defaultPosition = defaultPositions[1]
		if defaultPosition then
			-- Instantly snap to Default position
			self._camera.CFrame = defaultPosition.CFrame
		end
	else
		warn("[CameraController] Default position not found")
	end
	
	-- Reset cleanup flag so cycles can resume later if needed
	self._isCleaningUp = false
end

--[[
	Resets camera to normal gameplay mode
]]
function CameraController:ResetToGameplay()
	-- Set cleanup flag to prevent new tweens
	self._isCleaningUp = true
	
	-- Stop cycle and cancel any active tweens
	self._cycleRunning = false
	self._cycleVersion = self._cycleVersion + 1
	
	if self._activeTween then
		self._activeTween:Cancel()
		self._activeTween = nil
	end
	
	-- Disconnect all tracked tween connections
	for _, connection in ipairs(self._tweenConnections) do
		if connection then
			connection:Disconnect()
		end
	end
	self._tweenConnections = {}
	
	-- Set camera properties directly to prevent lingering tweens
	-- Store current CFrame to prevent camera from snapping
	local currentCFrame = self._camera.CFrame
	self._camera.CameraType = Enum.CameraType.Custom
	self._camera.FieldOfView = 70
	-- Restore CFrame to prevent visual glitch
	self._camera.CFrame = currentCFrame
end

--[[
	Sets camera to scriptable mode for battle
]]
function CameraController:SetBattleMode()
	self._camera.CameraType = Enum.CameraType.Scriptable
	self._camera.FieldOfView = 50
end

--[[
	Checks if a camera position exists
	@param positionName Name of the position
	@param index Position index (optional)
	@return boolean True if position exists
]]
function CameraController:HasPosition(positionName: string, index: number?): boolean
	local positions = self._cameraPositions[positionName]
	if not positions or #positions == 0 then
		return false
	end
	
	if index then
		return positions[index] ~= nil
	end
	
	return true
end

--[[
	Cleanup all camera operations
]]
function CameraController:Cleanup()
	-- Set cleanup flag first to prevent new tweens
	self._isCleaningUp = true
	
	-- Stop cycle
	self._cycleRunning = false
	self._cycleVersion = self._cycleVersion + 1
	
	-- Cancel active tween
	if self._activeTween then
		self._activeTween:Cancel()
		self._activeTween = nil
	end
	
	-- Disconnect all tracked tween connections
	for _, connection in ipairs(self._tweenConnections) do
		if connection then
			connection:Disconnect()
		end
	end
	self._tweenConnections = {}
	
	-- Reset to gameplay mode
	self:ResetToGameplay()
end

--[[
	Internal: Caches camera positions from battle scene
]]
function CameraController:_cacheCameraPositions()
	print("[CameraController] === CACHE CAMERA POSITIONS DEBUG START ===")
	
	if not self._battleScene then
		warn("[CameraController] No battle scene provided")
		return
	end
	
	print("[CameraController] Battle scene:", self._battleScene.Name)
	print("[CameraController] Battle scene parent:", self._battleScene.Parent)
	print("[CameraController] Battle scene children count:", #self._battleScene:GetChildren())
	
	-- List all children of battle scene
	print("[CameraController] Battle scene children:")
	for _, child in ipairs(self._battleScene:GetChildren()) do
		print("  -", child.Name, "(" .. child.ClassName .. ")")
	end
	
	-- Try to find CameraPoints folder (new structure)
	local cameraFolder = self._battleScene:FindFirstChild("CameraPoints")
	
	if cameraFolder then
		print("[CameraController] Found CameraPoints folder")
	else
		print("[CameraController] CameraPoints folder not found, trying Essentials/Camera")
		
		-- Fall back to old structure (Essentials/Camera)
		local essentials = self._battleScene:FindFirstChild("Essentials")
		if essentials then
			print("[CameraController] Found Essentials folder")
			cameraFolder = essentials:FindFirstChild("Camera")
			if cameraFolder then
				print("[CameraController] Found Camera folder in Essentials")
			else
				print("[CameraController] Camera folder not found in Essentials")
			end
		else
			print("[CameraController] Essentials folder not found")
		end
	end
	
	if not cameraFolder then
		warn("[CameraController] No camera folder found in battle scene (tried CameraPoints and Essentials/Camera)")
		print("[CameraController] === CACHE CAMERA POSITIONS DEBUG END (FAILED) ===")
		return
	end
	
	print("[CameraController] Found camera folder:", cameraFolder.Name)
	print("[CameraController] Camera folder children count:", #cameraFolder:GetChildren())
	
	-- List all children of camera folder
	print("[CameraController] Camera folder children:")
	for _, child in ipairs(cameraFolder:GetChildren()) do
		print("  -", child.Name, "(" .. child.ClassName .. ")", "IsBasePart:", child:IsA("BasePart"))
	end
	
	-- Cache all camera positions by name
	local count = 0
	for _, child in ipairs(cameraFolder:GetChildren()) do
		if child:IsA("BasePart") then
			-- Single part (like "Default")
			local positionName = child.Name
			
			if not self._cameraPositions[positionName] then
				self._cameraPositions[positionName] = {}
			end
			
			table.insert(self._cameraPositions[positionName], child)
			count = count + 1
			print("[CameraController] ✅ Cached single camera position:", positionName, "CFrame:", child.CFrame)
		elseif child:IsA("Folder") then
			-- Folder containing numbered parts (like "FoeZoomOut" with "1", "2")
			local positionName = child.Name
			
			if not self._cameraPositions[positionName] then
				self._cameraPositions[positionName] = {}
			end
			
			-- Cache all numbered parts within the folder
			local folderParts = child:GetChildren()
			table.sort(folderParts, function(a, b)
				return tonumber(a.Name) and tonumber(b.Name) and tonumber(a.Name) < tonumber(b.Name)
			end)
			
			for _, part in ipairs(folderParts) do
				if part:IsA("BasePart") then
					table.insert(self._cameraPositions[positionName], part)
					count = count + 1
					print("[CameraController] ✅ Cached folder camera position:", positionName .. "/" .. part.Name, "CFrame:", part.CFrame)
				end
			end
		else
			print("[CameraController] ⚠️ Skipped:", child.Name, "(" .. child.ClassName .. ")")
		end
	end
	
	print("[CameraController] Cached", count, "camera position(s)")
	print("[CameraController] Final _cameraPositions table:")
	for name, positions in pairs(self._cameraPositions) do
		print("  -", name, "→", #positions, "position(s)")
	end
	print("[CameraController] === CACHE CAMERA POSITIONS DEBUG END ===")
end

return CameraController

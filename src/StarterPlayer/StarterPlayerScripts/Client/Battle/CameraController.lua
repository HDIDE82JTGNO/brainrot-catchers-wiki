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
	if self._activeTween then
		self._activeTween:Cancel()
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
	
	self._cycleRunning = true
	self._cycleVersion = self._cycleVersion + 1
	local currentVersion = self._cycleVersion
	
	task.spawn(function()
		local index = 1
		
		while self._cycleRunning and currentVersion == self._cycleVersion do
			local cameraPosition = positions[index]
			if cameraPosition then
				self:TransitionTo(cameraPosition.CFrame, duration)
				task.wait(duration + 0.1)
			end
			
			index = (index % #positions) + 1
		end
	end)
end

--[[
	Stops camera cycle animation
]]
function CameraController:StopCycle()
	self._cycleRunning = false
	self._cycleVersion = self._cycleVersion + 1
	
	if self._activeTween then
		self._activeTween:Cancel()
		self._activeTween = nil
	end
end

--[[
	Resets camera to normal gameplay mode
]]
function CameraController:ResetToGameplay()
	self:StopCycle()
	self._camera.CameraType = Enum.CameraType.Custom
	self._camera.FieldOfView = 70
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
	self:StopCycle()
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

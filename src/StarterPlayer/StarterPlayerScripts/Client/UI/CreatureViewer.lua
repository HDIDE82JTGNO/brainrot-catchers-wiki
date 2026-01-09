local CreatureViewer = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Creatures = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Creatures"))

local OrbitConnections = setmetatable({}, { __mode = "k" })
local OVERLAY_NAME = "ViewerOverlay"

local function clearConnections(container: Instance?)
	if not container then return end
	local conns = OrbitConnections[container]
	if conns then
		for _, c in ipairs(conns) do
			if c and c.Connected then c:Disconnect() end
		end
	end
	OrbitConnections[container] = nil
end

local function ensureOverlay(container: GuiObject, opts)
	-- Overlay hints removed per latest UX request; only build if explicitly asked
	if not (opts and opts.ShowOverlay == true) then return nil end
	local overlay = container:FindFirstChild(OVERLAY_NAME)
	if overlay and overlay:IsA("Frame") then return overlay end
	overlay = Instance.new("Frame")
	overlay.Name = OVERLAY_NAME
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = 500
	overlay.Active = false
	overlay.Parent = container
	return overlay
end

local function applyShiny(model: Model, baseData: any?)
	if not (baseData and baseData.ShinyColors) then return end
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") or inst:IsA("MeshPart") then
			local newColor = baseData.ShinyColors[inst.Name]
			if newColor then
				pcall(function()
					inst.Color = newColor
				end)
			end
		elseif inst:IsA("Decal") or inst:IsA("Texture") then
			local newColor = baseData.ShinyColors[inst.Name]
			if newColor then
				pcall(function()
					inst.Color3 = newColor
				end)
			end
		end
	end
end

local function frameModel(cam: Camera, model: Model, viewportSize: Vector2, padding: number?)
	local cf, size = model:GetBoundingBox()
	local vFov = math.rad(cam.FieldOfView)
	local aspect = (viewportSize.Y > 0) and (viewportSize.X / viewportSize.Y) or 1
	local hFov = 2 * math.atan(math.tan(vFov * 0.5) * aspect)
	local halfHeight = math.max(0.5, size.Y * 0.5)
	local halfWidth = math.max(0.5, math.max(size.X, size.Z) * 0.5)
	local distV = halfHeight / math.tan(vFov * 0.5)
	local distH = halfWidth / math.tan(hFov * 0.5)
	local distance = math.max(distV, distH) * (padding or 1.25)

	local focus = Vector3.new(cf.Position.X, cf.Position.Y + (size.Y * 0.15), cf.Position.Z)
	-- Place camera on -Z to face the model's front (many rigs face +Z)
	local camPos = focus + Vector3.new(0, halfHeight * 0.15, -distance)

	cam.CFrame = CFrame.lookAt(camPos, focus)
	cam.Focus = CFrame.new(focus)
	return focus, distance
end

local function attachOrbit(container: GuiObject, worldModel: WorldModel, model: Model, opts: any?)
	clearConnections(container)
	
	-- Check if rotation is locked
	if opts and opts.LockRotation == true then
		return
	end
	
	local conns = {}
	OrbitConnections[container] = conns

	local yaw = 0
	local dragging = false
	local lastX: number? = nil
	local rotateSpeed = math.rad(0.4)

	local function applyRotation()
		local pivot = model:GetPivot()
		local pos = pivot.Position
		model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw, 0))
	end

	local function onInputBegan(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			lastX = input.Position.X
		end
	end

	local function onInputEnded(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
			lastX = nil
		end
	end

	local function onInputChanged(input: InputObject)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			if lastX then
				local dx = input.Position.X - lastX
				lastX = input.Position.X
				yaw += dx * rotateSpeed
				applyRotation()
			end
		end
	end

	table.insert(conns, container.InputBegan:Connect(onInputBegan))
	table.insert(conns, container.InputEnded:Connect(onInputEnded))
	table.insert(conns, UserInputService.InputChanged:Connect(onInputChanged))
end

function CreatureViewer:Load(container: GuiObject, data: any, opts: any?)
	if not container or not container:IsA("GuiObject") or not data then return end

	clearConnections(container)

	-- Clear dynamic children but keep decorative UI
	local existing = container:FindFirstChild("Viewport")
	if existing and existing:IsA("ViewportFrame") then
		existing:Destroy()
	end
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("ImageLabel") and (child.Name == "FallbackSprite") then
			child:Destroy()
		end
	end

	local overlay = ensureOverlay(container, opts or {})

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Viewport"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.Ambient = Color3.fromRGB(255, 255, 255)
	viewport.ZIndex = (overlay and overlay.ZIndex - 1) or 100
	viewport.Parent = container

	local worldModel = Instance.new("WorldModel")
	worldModel.Name = "WorldModel"
	worldModel.Parent = viewport

	local cam = Instance.new("Camera")
	cam.Name = "ViewportCamera"
	cam.Parent = viewport
	viewport.CurrentCamera = cam

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local modelsFolder = assets and assets:FindFirstChild("CreatureModels") or nil
	local speciesName = data.BaseName or data.Name
	local modelTemplate = modelsFolder and modelsFolder:FindFirstChild(tostring(speciesName)) or nil

	if modelTemplate and modelTemplate:IsA("Model") then
		local model = modelTemplate:Clone()
		model.Parent = worldModel
		local baseData = Creatures[speciesName]
		if data.Shiny == true then
			applyShiny(model, baseData)
		end

		model:PivotTo(CFrame.new())
		frameModel(cam, model, container.AbsoluteSize, opts and opts.Padding)

		-- Play idle if present
		local animator: Animator? = nil
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
		else
			local animController = model:FindFirstChildOfClass("AnimationController") or Instance.new("AnimationController", model)
			animator = animController:FindFirstChildOfClass("Animator") or Instance.new("Animator", animController)
		end
		local animFolder = model:FindFirstChild("Animations")
		local idle = animFolder and animFolder:FindFirstChild("Idle") or model:FindFirstChild("Idle")
		if idle and idle:IsA("Animation") and animator then
			local track = animator:LoadAnimation(idle)
			track.Priority = Enum.AnimationPriority.Idle
			track.Looped = true
			track:Play()
		end

		attachOrbit(container, worldModel, model, opts)
	else
		local base = Creatures[speciesName]
		local spriteId = base and ((data.Shiny and base.ShinySprite) or base.Sprite) or nil
		if spriteId then
			local img = Instance.new("ImageLabel")
			img.Name = "FallbackSprite"
			img.BackgroundTransparency = 1
			img.Size = UDim2.fromScale(1, 1)
			img.Image = spriteId
			img.ZIndex = (overlay and overlay.ZIndex) or 15
			img.Parent = container
			viewport:Destroy()
			clearConnections(container)
		else
			viewport:Destroy()
			clearConnections(container)
		end
	end
end

-- Expose camera framing helper for other modules (e.g., evolution swap)
function CreatureViewer:FrameModel(camera: Camera, model: Model, viewportSize: Vector2, padding: number?)
	return frameModel(camera, model, viewportSize, padding)
end

function CreatureViewer:AttachOrbit(container: GuiObject, model: Model, opts: any?)
	if not (container and container:IsA("GuiObject") and model) then return end
	local world = model.Parent
	if not world or not world:IsA("WorldModel") then return end
	attachOrbit(container, world, model, opts or {})
end

function CreatureViewer:Clear(container: GuiObject)
	clearConnections(container)
end

return CreatureViewer

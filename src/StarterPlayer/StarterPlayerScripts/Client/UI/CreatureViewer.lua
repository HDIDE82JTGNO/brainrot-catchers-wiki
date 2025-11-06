local CreatureViewer = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Creatures = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Creatures"))

-- Loads a 3D preview of a creature into the given container frame.
-- Expects a Frame that will receive a ViewportFrame child named "Viewport".
-- data should contain at least Name (species) and optional Shiny boolean.
function CreatureViewer:Load(container: Frame, data: any)
    if not container or not container:IsA("Frame") or not data then return end

    -- Clear existing viewport/image children but keep decorative UI
    local existing = container:FindFirstChild("Viewport")
    if existing and existing:IsA("ViewportFrame") then
        existing:Destroy()
    end
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("ImageLabel") and child.Name == "FallbackSprite" then
            child:Destroy()
        end
    end

    -- Create viewport
    local viewport = Instance.new("ViewportFrame")
    viewport.Name = "Viewport"
    viewport.Size = UDim2.fromScale(1, 1)
    viewport.BackgroundTransparency = 1
    viewport.LightColor = Color3.fromRGB(255, 255, 255)
    viewport.Ambient = Color3.fromRGB(255, 255, 255)
    viewport.Parent = container
    viewport.ZIndex = 100

    local worldModel = Instance.new("WorldModel")
    worldModel.Name = "WorldModel"
    worldModel.Parent = viewport

    local cam = Instance.new("Camera")
    cam.Name = "ViewportCamera"
    cam.Parent = viewport
    viewport.CurrentCamera = cam

    -- Locate model template by species name
    local assets = ReplicatedStorage:FindFirstChild("Assets")
    local modelsFolder = assets and assets:FindFirstChild("CreatureModels") or nil
    local speciesName = data.BaseName or data.Name
    local modelTemplate = modelsFolder and modelsFolder:FindFirstChild(tostring(speciesName)) or nil

    if modelTemplate and modelTemplate:IsA("Model") then
        local model = modelTemplate:Clone()
        model.Parent = worldModel

        -- Apply shiny recolor if needed
        if data.Shiny == true then
            local base = Creatures[speciesName]
            local shinyColors = base and base.ShinyColors
            if shinyColors then
                for _, d in ipairs(model:GetDescendants()) do
                    if d:IsA("BasePart") or d:IsA("MeshPart") then
                        local newColor = shinyColors[d.Name]
                        if newColor then
                            pcall(function()
                                d.Color = newColor
                            end)
                        end
                    end
                end
            end
        end

        -- Frame camera around model
        local hrp = model:FindFirstChild("HumanoidRootPart")
        local anchor: BasePart? = (hrp and hrp:IsA("BasePart") and hrp) or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
        if anchor and not model.PrimaryPart then model.PrimaryPart = anchor end
        if anchor then
            model:PivotTo(CFrame.new(0, 0, 0))
            local size = model:GetExtentsSize()
            local target = (model.PrimaryPart and model.PrimaryPart.Position) or Vector3.new(0, size.Y * 0.5, 0)
            local vFov = math.rad(cam.FieldOfView)
            local vp = container.AbsoluteSize
            local aspect = (vp.Y > 0) and (vp.X / vp.Y) or 1
            local hFov = 2 * math.atan(math.tan(vFov * 0.5) * aspect)
            local halfHeight = math.max(0.5, size.Y * 0.5)
            local halfWidth = math.max(0.5, math.max(size.X, size.Z) * 0.5)
            local distV = halfHeight / math.tan(vFov * 0.5)
            local distH = halfWidth / math.tan(hFov * 0.5)
            local padding = 1.2
            local distance = math.max(4, math.max(distV, distH) * padding * 1.2)
            local forward = Vector3.new(0, 0, -1)
            local camPos = -(target - (forward.Unit * distance))
            cam.CFrame = CFrame.new(camPos) * CFrame.Angles(0, math.rad(-180), 0)
            cam.Focus = CFrame.new(target)
        end

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
    else
        -- Fallback: use sprite if available
        local base = Creatures[speciesName]
        local spriteId = base and base.Sprite or nil
        if spriteId then
            local img = Instance.new("ImageLabel")
            img.Name = "FallbackSprite"
            img.BackgroundTransparency = 1
            img.Size = UDim2.fromScale(1, 1)
            img.Image = spriteId
            img.ZIndex = 15
            img.Parent = container
            viewport:Destroy()
        else
            viewport:Destroy()
        end
    end
end

return CreatureViewer



local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Creatures = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Creatures"))
local Say = require(script.Parent:WaitForChild("Say"))

local EvolutionUI = {}

local function tween(obj, info, props)
    local t = TweenService:Create(obj, info, props)
    t:Play()
    return t
end

local function setModelTransparency(model: Model, alpha: number)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
            d.Transparency = alpha
        end
    end
end

local function tryPlayIdle(model: Model)
    local humanoid: Humanoid? = model:FindFirstChildOfClass("Humanoid")
    local animator: Animator? = humanoid and humanoid:FindFirstChildOfClass("Animator")
    if not animator then return end
    -- Try find an Animation named "Idle" under model
    local animFolder = model:FindFirstChild("Animations")
    local idleAnim = animFolder and animFolder:FindFirstChild("Idle")
    if idleAnim and idleAnim:IsA("Animation") then
        local track = animator:LoadAnimation(idleAnim)
        track.Looped = true
        track:Play(0.2)
    end
end

local function buildViewport(container: Instance)
    local viewport: ViewportFrame = container:FindFirstChild("Viewport")
        or Instance.new("ViewportFrame")
    viewport.Name = "Viewport"
    viewport.BackgroundTransparency = 1
    viewport.BorderSizePixel = 0
    viewport.Size = UDim2.fromScale(1, 1)
    viewport.AnchorPoint = Vector2.new(0.5, 0.5)
    viewport.Position = UDim2.fromScale(0.5, 0.5)
    viewport.ZIndex = 504
    viewport.Parent = container

    local world: WorldModel = viewport:FindFirstChildOfClass("WorldModel") or Instance.new("WorldModel")
    world.Parent = viewport

    local cam: Camera = viewport:FindFirstChildOfClass("Camera") or Instance.new("Camera")
    cam.Parent = viewport
    viewport.CurrentCamera = cam

    return viewport, world, cam
end

local function centerCameraOnModel(cam: Camera, model: Model)
    local cf, size = model:GetBoundingBox()
    local radius = math.max(size.X, size.Y, size.Z) * 0.7
    local focus = cf.Position
    -- Position camera in front of the model (negative Z direction)
    local eye = focus + Vector3.new(0, size.Y * 0.25, -radius * 2)
    cam.CFrame = CFrame.lookAt(eye, focus)
end

-- Show evolution UI and animation from oldSpecies -> newSpecies (nickname optional)
function EvolutionUI:Show(oldSpecies: string, newSpecies: string, nickname: string?)
    local playerGui = game.Players.LocalPlayer:WaitForChild("PlayerGui")
    local gameUI = playerGui:WaitForChild("GameUI")
    local evolutionFrame: Frame = gameUI:WaitForChild("Evolution")
    local studsBg: ImageLabel? = evolutionFrame:FindFirstChild("Studs")
    local container: Frame = evolutionFrame:FindFirstChild("CreatureContainer") or evolutionFrame:FindFirstChild("creature container")
    if not container then return end

    -- Bring up evolution UI
    evolutionFrame.Visible = true
    if studsBg then studsBg.ImageTransparency = 1 end
    
    -- Fade out blackout when evolution UI appears
    local blackout = gameUI:FindFirstChild("Blackout")
    if blackout then
        local blackoutTween = tween(blackout, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
        blackoutTween:Play()
    end
    
    local studsTween
    if studsBg then
        studsTween = tween(studsBg, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { ImageTransparency = 0.8 })
    end

    -- Build viewport
    local viewport, world, cam = buildViewport(container)
    for _, child in ipairs(world:GetChildren()) do child:Destroy() end

    -- Load models
    local assets = ReplicatedStorage:WaitForChild("Assets")
    local models = assets:WaitForChild("CreatureModels")
    local oldModelTemplate = models:FindFirstChild(oldSpecies)
    local newModelTemplate = models:FindFirstChild(newSpecies)
    if not oldModelTemplate or not newModelTemplate then return end

    local oldModel = oldModelTemplate:Clone()
    local newModel = newModelTemplate:Clone()
    oldModel.Parent = world
    newModel.Parent = world
    newModel:PivotTo(CFrame.new(0, 0, 0))
    oldModel:PivotTo(CFrame.new(0, 0, 0))

    -- Start with only old visible
    setModelTransparency(newModel, 1)
    setModelTransparency(oldModel, 0)

    -- Camera framing
    centerCameraOnModel(cam, oldModel)

    -- Try play idle animations
    tryPlayIdle(oldModel)

    -- Dialogue 1
    local shownName = nickname or oldSpecies
Say:Say(" ", true, { { Text = "What? Something's happening to " .. shownName .. "!", Emotion = "Excited" } })

    -- Create simple hologram-style swap inside the WorldModel
    local _, size = oldModel:GetBoundingBox()
    local holo = Instance.new("Part")
    holo.Name = "Holo"
    holo.Size = size + Vector3.new(0.25, 0.25, 0.25)
    holo.Material = Enum.Material.Neon
    holo.Color = Color3.fromRGB(50, 180, 255)
    holo.Transparency = 1
    holo.Anchored = true
    holo.CanCollide = false
    holo.Parent = world
    local pivot = oldModel:GetPivot()
    holo.CFrame = pivot

    local inT = tween(holo, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Transparency = 0.2 })
    inT.Completed:Wait()

    -- Swap models at peak
    setModelTransparency(oldModel, 1)
    setModelTransparency(newModel, 0)
    tryPlayIdle(newModel)
    centerCameraOnModel(cam, newModel)
    
    -- Destroy old model now that we can see the new one
    oldModel:Destroy()

    -- Flash out the hologram
    tween(holo, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.In), { Transparency = 1 }).Completed:Wait()
    holo:Destroy()

    -- Dialogue 2
    local finalName = nickname or newSpecies
Say:Say(" ", true, { { Text = shownName .. " transformed into " .. newSpecies .. "!", Emotion = "Happy" } })

    -- Wait a moment before fading out
    task.wait(1.5)
    
    -- Destroy viewport instantly when fading out
    if viewport then viewport:Destroy() end
    if newModel then newModel:Destroy() end
    
    -- Fade out evolution UI
    local fadeOutTween = tween(evolutionFrame, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
    if studsBg then
        tween(studsBg, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { ImageTransparency = 1 })
    end
    
    fadeOutTween.Completed:Wait()
    
    -- Clean up everything
    evolutionFrame.Visible = false
    
    -- Notify server that evolution UI has completed
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Events = ReplicatedStorage:FindFirstChild("Events")
    if Events then
        local Communicate = Events:FindFirstChild("Communicate")
        if Communicate then
            Communicate:FireServer("EvolutionComplete")
            print("[EvolutionUI] Notified server that evolution UI completed")
        end
    end
end

-- Compare snapshot to current client data and show the first detected evolution
function EvolutionUI:MaybeShowFromSnapshot(preBattleSnapshot: {{Name: string, Level: number}}?)
    if not preBattleSnapshot then return end
    local ClientData = require(script.Parent.Parent:WaitForChild("Plugins"):WaitForChild("ClientData"))
    local now = ClientData:Get()
    if not now or not now.Party then return end

    for idx, prev in ipairs(preBattleSnapshot) do
        local curr = now.Party[idx]
        if prev and curr and prev.Name ~= curr.Name then
            -- Validate that prev evolves into curr
            local data = Creatures[prev.Name]
            if data and data.EvolvesInto == curr.Name then
                self:Show(prev.Name, curr.Name, curr.Nickname)
                return
            end
        end
    end
end

return EvolutionUI



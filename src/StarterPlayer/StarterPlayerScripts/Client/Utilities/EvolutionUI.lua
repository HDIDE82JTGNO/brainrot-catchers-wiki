local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local Creatures = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Creatures"))
local Say = require(script.Parent:WaitForChild("Say"))
local CreatureViewer = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("CreatureViewer"))

local EvolutionUI = {}

-- Sound effect IDs
local SOUND_IDS = {
	InitialFlash = 113453182535108,
	ParticleEffectsStart = 136428433939613,
	CameraZoomIn = 116764630643139,
	ModelPulse = 83702864315990,
	GlowActivation = 124725329972262,
	TransformationFlash = 125995505927633,
	ParticleBurst = 130921290732468,
	NewModelAppearance = 109246687809257,
	EvolutionComplete = 116672262716278,
}

-- Preloaded sound templates
local SoundTemplates = {}

--[[
	Preloads all evolution sound effects
]]
local function preloadSounds()
	local soundFolder = Instance.new("Folder")
	soundFolder.Name = "EvolutionSounds"
	soundFolder.Parent = ReplicatedStorage
	
	local soundsToPreload = {}
	
	for name, soundId in pairs(SOUND_IDS) do
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = "rbxassetid://" .. tostring(soundId)
		sound.Volume = 0.8
		sound:SetAttribute("SoundName", name)
		sound.Parent = soundFolder
		SoundTemplates[name] = sound
		table.insert(soundsToPreload, sound)
	end
	
	-- Preload all sounds using PreloadAsync
	ContentProvider:PreloadAsync(soundsToPreload)
end

--[[
	Plays a preloaded evolution sound effect
]]
local function playEvolutionSound(soundName: string, volume: number?): Sound?
	local template = SoundTemplates[soundName]
	if not template then return nil end
	
	local clonedSound = template:Clone()
	clonedSound.Volume = volume or 0.8
	clonedSound.Parent = workspace
	clonedSound:Play()
	clonedSound.Ended:Connect(function()
		clonedSound:Destroy()
	end)
	return clonedSound
end

-- Preload sounds on module initialization
preloadSounds()

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

local function centerCameraOnModel(cam: Camera, model: Model, viewportSize: Vector2, padding: number?)
    CreatureViewer:FrameModel(cam, model, viewportSize, padding or 1.25)
end

--[[
    Creates white flash overlay UI element
]]
local function createFlashOverlay(parent: Instance): Frame
    local flash = Instance.new("Frame")
    flash.Name = "EvolutionFlash"
    flash.Size = UDim2.fromScale(1, 1)
    flash.Position = UDim2.fromScale(0, 0)
    flash.BackgroundColor3 = Color3.new(1, 1, 1)
    flash.BackgroundTransparency = 1
    flash.BorderSizePixel = 0
    flash.ZIndex = 1000
    flash.Parent = parent
    return flash
end

--[[
    Plays a single white flash
]]
local function playFlash(flash: Frame, intensity: number, duration: number): Tween
    flash.BackgroundTransparency = 1 - intensity
    local fadeOut = tween(flash, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
        BackgroundTransparency = 1
    })
    return fadeOut
end

--[[
    Plays a sequence of multiple white flashes
]]
local function playFlashSequence(flash: Frame, count: number, baseDuration: number, intensity: number): {Tween}
    local tweens = {}
    for i = 1, count do
        local flashTween = playFlash(flash, intensity, baseDuration)
        table.insert(tweens, flashTween)
        if i < count then
            flashTween.Completed:Wait()
            task.wait(0.05) -- Small gap between flashes
        end
    end
    return tweens
end

--[[
    Creates particle effects around a model
]]
local function createParticleEffects(model: Model, world: WorldModel): {Instance}
    local effects = {}
    local pivot = model:GetPivot()
    
    -- Create sparkle particles
    local sparklePart = Instance.new("Part")
    sparklePart.Name = "SparkleParticles"
    sparklePart.Size = Vector3.new(1, 1, 1)
    sparklePart.Transparency = 1
    sparklePart.Anchored = true
    sparklePart.CanCollide = false
    sparklePart.CFrame = pivot
    sparklePart.Parent = world
    
    local sparkleAttachment = Instance.new("Attachment")
    sparkleAttachment.Parent = sparklePart
    
    local sparkleEmitter = Instance.new("ParticleEmitter")
    sparkleEmitter.Parent = sparkleAttachment
    sparkleEmitter.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(1, 1, 0.8)),
        ColorSequenceKeypoint.new(0.5, Color3.new(1, 0.9, 0.5)),
        ColorSequenceKeypoint.new(1, Color3.new(1, 0.7, 0.3))
    })
    sparkleEmitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(0.5, 0.5),
        NumberSequenceKeypoint.new(1, 0)
    })
    sparkleEmitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1)
    })
    sparkleEmitter.Speed = NumberRange.new(8, 15)
    sparkleEmitter.Lifetime = NumberRange.new(1.0, 2.0)
    sparkleEmitter.Rate = 40
    sparkleEmitter.SpreadAngle = Vector2.new(120, 120)
    sparkleEmitter.Texture = "rbxassetid://241650934" -- Star texture
    sparkleEmitter.LightEmission = 0.8
    sparkleEmitter.LightInfluence = 0
    
    table.insert(effects, sparklePart)
    
    -- Create energy swirl particles
    local energyPart = Instance.new("Part")
    energyPart.Name = "EnergyParticles"
    energyPart.Size = Vector3.new(1, 1, 1)
    energyPart.Transparency = 1
    energyPart.Anchored = true
    energyPart.CanCollide = false
    energyPart.CFrame = pivot
    energyPart.Parent = world
    
    local energyAttachment = Instance.new("Attachment")
    energyAttachment.Parent = energyPart
    
    local energyEmitter = Instance.new("ParticleEmitter")
    energyEmitter.Parent = energyAttachment
    energyEmitter.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(0.3, 0.7, 1)),
        ColorSequenceKeypoint.new(0.5, Color3.new(0.5, 0.9, 1)),
        ColorSequenceKeypoint.new(1, Color3.new(0.7, 1, 1))
    })
    energyEmitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(0.5, 0.4),
        NumberSequenceKeypoint.new(1, 0)
    })
    energyEmitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(1, 1)
    })
    energyEmitter.Speed = NumberRange.new(6, 12)
    energyEmitter.Lifetime = NumberRange.new(1.2, 2.2)
    energyEmitter.Rate = 30
    energyEmitter.SpreadAngle = Vector2.new(120, 120)
    energyEmitter.LightEmission = 0.9
    energyEmitter.LightInfluence = 0
    
    table.insert(effects, energyPart)
    
    return effects
end

--[[
    Shakes the viewport camera
]]
local function shakeCamera(cam: Camera, intensity: number, duration: number): RBXScriptConnection
    local startTime = os.clock()
    local lastShakeOffset = CFrame.new()
    local baseCFrame = cam.CFrame
    local isActive = true
    
    local connectionRef = {}
    connectionRef.connection = RunService.RenderStepped:Connect(function()
        if not isActive then
            return
        end
        
        local elapsed = os.clock() - startTime
        if elapsed >= duration then
            -- Remove the last shake offset
            cam.CFrame = cam.CFrame * lastShakeOffset:Inverse()
            isActive = false
            if connectionRef.connection then
                connectionRef.connection:Disconnect()
            end
            return
        end
        
        -- Remove previous frame's shake offset
        local currentBase = cam.CFrame * lastShakeOffset:Inverse()
        
        -- Decay intensity over time
        local progress = elapsed / duration
        local currentIntensity = intensity * (1 - progress)
        
        -- Random rotational shake (in radians)
        local shakeX = (math.random() - 0.5) * 2 * currentIntensity * 0.1
        local shakeY = (math.random() - 0.5) * 2 * currentIntensity * 0.1
        local shakeZ = (math.random() - 0.5) * 2 * currentIntensity * 0.05
        
        -- Create new shake offset
        lastShakeOffset = CFrame.Angles(shakeX, shakeY, shakeZ)
        
        -- Apply shake
        cam.CFrame = currentBase * lastShakeOffset
    end)
    
    return connectionRef.connection
end

--[[
    Zooms the viewport camera
]]
local function zoomCamera(cam: Camera, model: Model, viewportSize: Vector2, targetPadding: number, duration: number): Tween
    local startPadding = 1.25
    local startTime = os.clock()
    
    local connection
    connection = RunService.RenderStepped:Connect(function()
        local elapsed = os.clock() - startTime
        if elapsed >= duration then
            connection:Disconnect()
            return
        end
        
        local progress = elapsed / duration
        local currentPadding = startPadding + (targetPadding - startPadding) * progress
        centerCameraOnModel(cam, model, viewportSize, currentPadding)
    end)
    
    task.delay(duration, function()
        if connection then
            connection:Disconnect()
        end
    end)
    
    -- Return a dummy tween for compatibility
    local dummy = Instance.new("Frame")
    dummy.Parent = game:GetService("CoreGui")
    local tweenObj = tween(dummy, TweenInfo.new(duration), {})
    tweenObj.Completed:Connect(function()
        dummy:Destroy()
    end)
    return tweenObj
end


--[[
    Applies pulsing effect to model using CFrame scaling
]]
local function pulseModel(model: Model, intensity: number, duration: number): RBXScriptConnection
    local basePivot = model:GetPivot()
    local basePosition = basePivot.Position
    
    local startTime = os.clock()
    local connection
    connection = RunService.RenderStepped:Connect(function()
        local elapsed = os.clock() - startTime
        if elapsed >= duration then
            model:PivotTo(basePivot)
            connection:Disconnect()
            return
        end
        
        local progress = elapsed / duration
        local pulseValue = math.sin(progress * math.pi * 4) * intensity * (1 - progress)
        local currentScale = 1 + pulseValue
        
        -- Apply scale via CFrame
        local scaleCFrame = CFrame.new(basePosition) * CFrame.new(0, 0, 0):Lerp(CFrame.new(0, 0, 0) * CFrame.new(0, pulseValue * 0.5, 0), pulseValue)
        model:PivotTo(basePivot * CFrame.new(0, pulseValue * 0.2, 0))
    end)
    
    task.delay(duration, function()
        if connection then
            connection:Disconnect()
        end
        model:PivotTo(basePivot)
    end)
    
    return connection
end

--[[
    Creates glow effect around model
]]
local function createGlowEffect(model: Model, world: WorldModel): {Instance}
    local effects = {}
    local _, size = model:GetBoundingBox()
    local pivot = model:GetPivot()
    
    -- Create glow part
    local glow = Instance.new("Part")
    glow.Name = "EvolutionGlow"
    glow.Size = size + Vector3.new(1.5, 1.5, 1.5)
    glow.Material = Enum.Material.Neon
    glow.Color = Color3.fromRGB(100, 200, 255)
    glow.Transparency = 1
    glow.Anchored = true
    glow.CanCollide = false
    glow.Shape = Enum.PartType.Ball
    glow.CFrame = pivot
    glow.Parent = world
    
    -- Add point light
    local light = Instance.new("PointLight")
    light.Color = Color3.fromRGB(100, 200, 255)
    light.Brightness = 0
    light.Range = 40
    light.Parent = glow
    
    table.insert(effects, glow)
    
    return effects
end

--[[
    Creates vignette effect
]]
local function createVignette(parent: Instance): ImageLabel
    local vignette = Instance.new("ImageLabel")
    vignette.Name = "EvolutionVignette"
    vignette.Size = UDim2.fromScale(1, 1)
    vignette.Position = UDim2.fromScale(0, 0)
    vignette.BackgroundTransparency = 1
    vignette.Image = "rbxassetid://1316045217" -- Standard vignette
    vignette.ImageColor3 = Color3.new(0, 0, 0)
    vignette.ImageTransparency = 1
    vignette.ScaleType = Enum.ScaleType.Stretch
    vignette.ZIndex = 999
    vignette.Parent = parent
    return vignette
end

-- Show evolution UI and animation from oldSpecies -> newSpecies (nickname optional)
function EvolutionUI:Show(oldSpecies: string, newSpecies: string, nickname: string?)
    local playerGui = game.Players.LocalPlayer:WaitForChild("PlayerGui")
    local gameUI = playerGui:WaitForChild("GameUI")
    local evolutionFrame: Frame = gameUI:WaitForChild("Evolution")
    local studsBg: ImageLabel? = evolutionFrame:FindFirstChild("Studs")
    local container: Frame = evolutionFrame:FindFirstChild("CreatureContainer") or evolutionFrame:FindFirstChild("creature container")
    if not container then return end

    -- Cleanup tracking
    local cleanupItems: {Instance} = {}
    local connections: {RBXScriptConnection} = {}

    -- Bring up evolution UI
    evolutionFrame.Visible = true
    evolutionFrame.BackgroundTransparency = 0
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

    -- Create flash overlay
    local flashOverlay = createFlashOverlay(evolutionFrame)
    table.insert(cleanupItems, flashOverlay)
    
    -- Create vignette
    local vignette = createVignette(evolutionFrame)
    table.insert(cleanupItems, vignette)

    -- Build viewport
    local viewport, world, cam = buildViewport(container)
    table.insert(cleanupItems, viewport)
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

    -- Camera framing (larger padding = smaller model on screen)
    centerCameraOnModel(cam, oldModel, container.AbsoluteSize, 1.75)
    CreatureViewer:AttachOrbit(container, oldModel, { LockRotation = true })

    -- Try play idle animations
    tryPlayIdle(oldModel)

    -- ========== PHASE 1: INITIAL SETUP (0.5s) ==========
    -- Fade in vignette
    tween(vignette, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
        ImageTransparency = 0.3
    }):Play()
    
    task.wait(0.5)

    -- Dialogue 1
    -- Store original names to ensure they don't get overwritten
    -- For display name: use nickname if it exists and is not the new species name (to avoid using post-evolution nickname)
    local displayName = nickname and nickname ~= newSpecies and nickname or oldSpecies
    local originalOldSpecies = oldSpecies
    local originalNewSpecies = newSpecies
    Say:Say(" ", true, { { Text = "What? Something's happening to " .. displayName .. "!", Emotion = "Excited" } })

    -- ========== PHASE 2: BUILD-UP (1.5s) ==========
    -- First white flash
    playEvolutionSound("InitialFlash", 0.6)
    playFlash(flashOverlay, 0.4, 0.15)
    task.wait(0.2)
    
    -- Start particle effects
    playEvolutionSound("ParticleEffectsStart", 0.5)
    local particleEffects = createParticleEffects(oldModel, world)
    for _, effect in ipairs(particleEffects) do
        table.insert(cleanupItems, effect)
    end
    
    -- Camera zooms in (smaller padding = larger model, but we keep it reasonable)
    playEvolutionSound("CameraZoomIn", 0.3)
    zoomCamera(cam, oldModel, container.AbsoluteSize, 1.4, 0.8)
    
    -- Model begins pulsing
    playEvolutionSound("ModelPulse", 0.4)
    local pulseConnection = pulseModel(oldModel, 0.1, 1.5)
    table.insert(connections, pulseConnection)
    
    -- Create glow effect
    playEvolutionSound("GlowActivation", 0.5)
    local glowEffects = createGlowEffect(oldModel, world)
    for _, effect in ipairs(glowEffects) do
        table.insert(cleanupItems, effect)
    end
    
    -- Animate glow
    local glowPart = glowEffects[1]
    if glowPart then
        tween(glowPart, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
            Transparency = 0.3
        }):Play()
        local light = glowPart:FindFirstChildOfClass("PointLight")
        if light then
            tween(light, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
                Brightness = 2
            }):Play()
        end
    end
    
    task.wait(1.3)

    -- ========== PHASE 3: TRANSFORMATION (1.0s) ==========
    -- Multiple rapid white flashes
    playEvolutionSound("TransformationFlash", 0.9)
    playFlashSequence(flashOverlay, 4, 0.12, 0.7)
    
    -- Intense particle burst
    playEvolutionSound("ParticleBurst", 0.7)
    if #particleEffects > 0 then
        for _, effect in ipairs(particleEffects) do
            local emitter = effect:FindFirstChildOfClass("ParticleEmitter")
            if emitter then
                emitter.Rate = emitter.Rate * 3
                emitter:Emit(50)
            end
        end
    end
    
    -- Camera shake
    local shakeConnection = shakeCamera(cam, 0.3, 0.8)
    table.insert(connections, shakeConnection)
    
    -- Intensify glow
    if glowPart then
        tween(glowPart, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Transparency = 0.1,
            Size = glowPart.Size * 1.5
        }):Play()
        local light = glowPart:FindFirstChildOfClass("PointLight")
        if light then
            tween(light, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Brightness = 5,
                Range = 30
            }):Play()
        end
    end
    
    task.wait(0.5)
    
    -- Model swap with scale/rotation effects
    -- Rotate old model out
    local oldPivot = oldModel:GetPivot()
    local rotationTween = tween(oldModel, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {})
    -- Apply rotation via RenderStepped
    local rotationStart = os.clock()
    local rotationConnRef = {}
    rotationConnRef.connection = RunService.RenderStepped:Connect(function()
        local elapsed = os.clock() - rotationStart
        if elapsed >= 0.3 then
            if rotationConnRef.connection then
                rotationConnRef.connection:Disconnect()
            end
            return
        end
        local progress = elapsed / 0.3
        local rotation = progress * math.pi * 2
        oldModel:PivotTo(oldPivot * CFrame.Angles(0, rotation, 0))
    end)
    table.insert(connections, rotationConnRef.connection)
    
    -- Fade out old model
    setModelTransparency(oldModel, 1)
    
    task.wait(0.2)
    
    -- Show new model with scale-in effect
    playEvolutionSound("NewModelAppearance", 0.8)
    setModelTransparency(newModel, 0)
    tryPlayIdle(newModel)
    
    -- Scale in new model using transparency and slight position offset
    local newPivot = newModel:GetPivot()
    local scaleStartTime = os.clock()
    local scaleConnRef = {}
    scaleConnRef.connection = RunService.RenderStepped:Connect(function()
        local elapsed = os.clock() - scaleStartTime
        if elapsed >= 0.3 then
            newModel:PivotTo(newPivot)
            if scaleConnRef.connection then
                scaleConnRef.connection:Disconnect()
            end
            return
        end
        local progress = elapsed / 0.3
        local easeProgress = 1 - (1 - progress) ^ 2 -- Ease out
        -- Start slightly offset and scale in
        local offset = (1 - easeProgress) * 0.3
        newModel:PivotTo(newPivot * CFrame.new(0, -offset, 0))
    end)
    table.insert(connections, scaleConnRef.connection)
    
    -- Update camera to new model (larger padding = smaller model)
    centerCameraOnModel(cam, newModel, container.AbsoluteSize, 1.75)
    CreatureViewer:AttachOrbit(container, newModel, { LockRotation = true })
    
    -- Update glow to new model position
    if glowPart then
        local _, newSize = newModel:GetBoundingBox()
        local newPivot = newModel:GetPivot()
        glowPart.Size = newSize + Vector3.new(1.5, 1.5, 1.5)
        glowPart.CFrame = newPivot
    end
    
    -- Destroy old model
    oldModel:Destroy()
    
    task.wait(0.3)

    -- ========== PHASE 4: REVEAL (1.5s) ==========
    -- Final white flash
    playFlash(flashOverlay, 0.8, 0.2)
    
    -- Camera zooms out (back to normal size)
    zoomCamera(cam, newModel, container.AbsoluteSize, 1.75, 1.0)
    
    -- Particles fade out
    if #particleEffects > 0 then
        for _, effect in ipairs(particleEffects) do
            local emitter = effect:FindFirstChildOfClass("ParticleEmitter")
            if emitter then
                tween(emitter, TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
                    Rate = 0
                }):Play()
            end
        end
    end
    
    -- Glow fades out
    if glowPart then
        tween(glowPart, TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
            Transparency = 1
        }):Play()
        local light = glowPart:FindFirstChildOfClass("PointLight")
        if light then
            tween(light, TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
                Brightness = 0
            }):Play()
        end
    end
    
    -- Vignette fades out
    tween(vignette, TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
        ImageTransparency = 1
    }):Play()
    
    -- Dialogue 2 - Use original species names to ensure correct message (always use oldSpecies, not nickname)
    Say:Say(" ", true, { { Text = originalOldSpecies .. " evolved into " .. originalNewSpecies .. "!", Emotion = "Happy" } })
    
    playEvolutionSound("EvolutionComplete", 0.7)
    
    task.wait(1.5)

    -- ========== PHASE 5: COMPLETION (1.0s) ==========
    -- Fade out effects
    tween(flashOverlay, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
        BackgroundTransparency = 1
    }):Play()
    
    task.wait(1.0)
    
    -- Cleanup all connections
    for _, conn in ipairs(connections) do
        if conn then
            pcall(function()
                conn:Disconnect()
            end)
        end
    end
    
    -- Destroy all cleanup items
    for _, item in ipairs(cleanupItems) do
        if item and item.Parent then
            item:Destroy()
        end
    end
    
    -- Destroy viewport and models
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

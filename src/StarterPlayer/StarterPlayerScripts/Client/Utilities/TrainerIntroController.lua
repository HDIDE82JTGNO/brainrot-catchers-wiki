--!strict
--[[
    TrainerIntroController.lua
    Manages cloning, placement, tweening, and fading of the engaging Trainer model
    for the Trainer battle intro/outro presentation.

    API (singleton):
    - PrepareFromNPC(npcModel: Model)
        Clone and store the NPC model that initiated the battle.
    - ConsumePrepared(): TrainerIntroAgent?
        Returns an agent for the prepared clone and clears the prepared state.
    - GetActive(): TrainerIntroAgent?
        Returns the currently active agent, if any.

    Agent methods:
    - PlaceAtSpawn(spawnCFrame: CFrame)
    - TweenBackAndFade(distance: number, duration: number, fadeOut: boolean?)
    - FadeInAndTweenToSpawn(duration: number, fadeIn: boolean?)
    - Destroy()
]]

local TweenService = game:GetService("TweenService")

export type TrainerIntroAgent = {
    Model: Model,
    SpawnCFrame: CFrame?,
    BehindCFrame: CFrame?,
    _pivotValue: CFrameValue?,
    _pivotConn: RBXScriptConnection?,
    _animator: Animator?,
    _playingTracks: {AnimationTrack},
    PlaceAtSpawn: (self: TrainerIntroAgent, spawnCFrame: CFrame) -> (),
    TweenBackAndFade: (self: TrainerIntroAgent, distance: number, duration: number, fadeOut: boolean?) -> (),
    FadeInAndTweenToSpawn: (self: TrainerIntroAgent, duration: number, fadeIn: boolean?) -> (),
    PlayAnimation: (self: TrainerIntroAgent, assetId: string, fadeTime: number?, looped: boolean?) -> AnimationTrack?,
    StopAllAnimations: (self: TrainerIntroAgent) -> (),
    Destroy: (self: TrainerIntroAgent) -> (),
}

local TrainerIntroController = {}
TrainerIntroController.__index = TrainerIntroController

local preparedClone: Model? = nil
local activeAgent: TrainerIntroAgent? = nil

local function isFadePart(instance: Instance): boolean
    return instance:IsA("BasePart") or instance:IsA("MeshPart")
end

local function isFadeDecal(instance: Instance): boolean
    return instance:IsA("Decal") or instance:IsA("Texture")
end

local function setAnchoredAndNonPhysical(model: Model)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") or d:IsA("MeshPart") then
            d.Anchored = true
            d.CanCollide = false
            d.CanQuery = false
            d.CanTouch = false
            d.Massless = true
        end
    end
end

-- Early accessor: HRP or PrimaryPart
local function getHRP(model: Model): BasePart?
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") then return hrp end
    if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
        return model.PrimaryPart
    end
    return nil
end

local function setClonePhysics(model: Model)
    local hrp = getHRP(model)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") or d:IsA("MeshPart") then
            local isHRP = (hrp ~= nil and d == hrp)
            d.Anchored = isHRP
            d.CanCollide = false
            d.CanQuery = false
            d.CanTouch = false
            d.Massless = true
        end
    end
end

local function removeScripts(model: Model)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("Script") or d:IsA("LocalScript") then
            d:Destroy()
        end
    end
end

local function scaledOffset(cf: CFrame, scale: number): CFrame
    local p = cf.Position
    return (cf - p) + (p * scale)
end

local function stripAnimationSystems(model: Model)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("Animator") or d:IsA("AnimationController") then
            d:Destroy()
        elseif (d:IsA("Script") or d:IsA("LocalScript")) and d.Name == "Animate" then
            d:Destroy()
        end
    end
end

local function createR6Skeleton(): Model
    local m = Instance.new("Model")
    m.Name = "TrainerR6"
    local function part(name: string, size: Vector3, transparency: number): BasePart
        local p = Instance.new("Part")
        p.Name = name
        p.Size = size
        p.Anchored = true
        p.CanCollide = false
        p.CanQuery = false
        p.CanTouch = false
        p.Massless = true
        p.Transparency = transparency
        p.Parent = m
        return p
    end
    -- R6 default-like sizes
    local hrp = part("HumanoidRootPart", Vector3.new(2, 2, 1), 1)
    local torso = part("Torso", Vector3.new(2, 2, 1), 1)
    local head = part("Head", Vector3.new(2, 1, 1), 1)
    local ra = part("Right Arm", Vector3.new(1, 2, 1), 1)
    local la = part("Left Arm", Vector3.new(1, 2, 1), 1)
    local rl = part("Right Leg", Vector3.new(1, 2, 1), 1)
    local ll = part("Left Leg", Vector3.new(1, 2, 1), 1)

    -- Arrange in basic R6 formation relative to HRP at origin
    hrp.CFrame = CFrame.new(0, 3, 0)
    torso.CFrame = hrp.CFrame
    head.CFrame = torso.CFrame * CFrame.new(0, 1.5, 0)
    ra.CFrame = torso.CFrame * CFrame.new(1.5, 0.5, 0)
    la.CFrame = torso.CFrame * CFrame.new(-1.5, 0.5, 0)
    rl.CFrame = torso.CFrame * CFrame.new(0.5, -1.5, 0)
    ll.CFrame = torso.CFrame * CFrame.new(-0.5, -1.5, 0)

    m.PrimaryPart = hrp
    return m
end

local function cloneVisualPart(obj: BasePart, parent: Instance, scl: number)
    if obj:IsA("MeshPart") then
        local p = obj:Clone()
        -- Strip non-visual children
        for _, c in ipairs(p:GetChildren()) do
            if not (c:IsA("Attachment") or c:IsA("Decal") or c:IsA("Texture") or c:IsA("SpecialMesh") or c:IsA("DataModelMesh")) then
                c:Destroy()
            end
        end
        p.Size = obj.Size * scl
        p.Anchored = true
        p.CanCollide = false
        p.CanQuery = false
        p.CanTouch = false
        p.Massless = true
        p.CFrame = obj.CFrame
        p.Parent = parent
        return p
    else
        local p = Instance.new("Part")
        p.Name = obj.Name
        p.Size = obj.Size * scl
        p.Color = obj.Color
        p.Material = obj.Material
        p.Reflectance = obj.Reflectance
        p.Transparency = obj.Transparency
        p.CastShadow = obj.CastShadow
        p.Anchored = true
        p.CanCollide = false
        p.CanQuery = false
        p.CanTouch = false
        p.Massless = true
        for _, c in ipairs(obj:GetChildren()) do
            if c:IsA("Decal") or c:IsA("Texture") then
                local o = c:Clone(); o.Parent = p
            elseif c:IsA("SpecialMesh") or c:IsA("DataModelMesh") then
                local o = c:Clone(); if o:IsA("SpecialMesh") then o.Scale = o.Scale * scl end; o.Parent = p
            end
        end
        p.CFrame = obj.CFrame
        p.Parent = parent
        return p
    end
end

-- Build an R6 skeleton, then attach visual clones from the source model as independent parts.
local function buildR6RigFromCharacter(src: Model, scale: number?): Model?
    local scl = (type(scale) == "number" and scale > 0) and scale or 1
    local rig = createR6Skeleton()
    -- Determine initial placement from source HRP/head to preserve relative layout
    local function tryGetHRP(model: Model): BasePart?
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if hrp and hrp:IsA("BasePart") then return hrp end
        if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then return model.PrimaryPart end
        return nil
    end
    local srcRoot = tryGetHRP(src) or src:FindFirstChild("Head") or src:FindFirstChildOfClass("BasePart")
    if srcRoot and srcRoot:IsA("BasePart") then
        rig:SetPrimaryPartCFrame(srcRoot.CFrame)
    end
    -- Copy visual parts
    for _, d in ipairs(src:GetDescendants()) do
        if d:IsA("BasePart") and d.Archivable then
            cloneVisualPart(d, rig, scl)
        end
    end
    return rig
end

local function resetMotorTransforms(model: Model)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("Motor6D") then
            pcall(function()
                d.Transform = CFrame.new()
            end)
        elseif d.ClassName == "Bone" then
            pcall(function()
                (d :: any).Transform = CFrame.new()
            end)
        end
    end
end

-- Builds a clean, display-only clone of a character model with neutral pose.
local function buildDisplayCloneFromCharacter(src: Model, scale: number?): Model?
    local scl = (type(scale) == "number" and scale > 0) and scale or 1
    local dst = Instance.new("Model")
    dst.Name = tostring(src.Name) .. "_Display"

    -- First pass: copy visual parts
    local function copyVisualPart(obj: BasePart): BasePart
        local newPart: BasePart
        if obj:IsA("MeshPart") then
            newPart = obj:Clone()
            -- Clear non-visual children (keep attachments ok)
            for _, c in ipairs(newPart:GetChildren()) do
                if not (c:IsA("Attachment") or c:IsA("Decal") or c:IsA("Texture") or c:IsA("SpecialMesh") or c:IsA("DataModelMesh")) then
                    c:Destroy()
                end
            end
            newPart.Size = obj.Size * scl
        else
            local p = Instance.new("Part")
            p.Name = obj.Name
            p.Size = obj.Size * scl
            p.Color = obj.Color
            p.Material = obj.Material
            p.Reflectance = obj.Reflectance
            p.Transparency = obj.Transparency
            p.CastShadow = obj.CastShadow
            p.CanCollide = false
            p.CanQuery = false
            p.CanTouch = false
            -- copy visuals
            for _, c in ipairs(obj:GetChildren()) do
                if c:IsA("Decal") or c:IsA("Texture") then
                    local o = c:Clone(); o.Parent = p
                elseif c:IsA("SpecialMesh") or c:IsA("DataModelMesh") then
                    local o = c:Clone(); if o:IsA("SpecialMesh") then o.Scale = o.Scale * scl end; o.Parent = p
                end
            end
            newPart = p
        end
        newPart.Anchored = true
        newPart.CanCollide = false
        newPart.CanQuery = false
        newPart.CanTouch = false
        newPart.Massless = true
        newPart.Parent = dst
        return newPart
    end

    local srcPartsByName: {[string]: BasePart} = {}
    for _, obj in ipairs(src:GetChildren()) do
        if obj:IsA("BasePart") and obj.Archivable then
            srcPartsByName[obj.Name] = obj
            copyVisualPart(obj)
        end
    end

    -- Rebuild Motor6Ds as fixed joints with identity Transform
    for _, motor in ipairs(src:GetDescendants()) do
        if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
            local parent = motor.Parent
            local p0 = dst:FindFirstChild(motor.Part0.Name)
            local p1 = dst:FindFirstChild(motor.Part1.Name)
            local newParent = dst:FindFirstChild(parent.Name)
            if p0 and p1 and newParent and newParent:IsA("BasePart") then
                local m = Instance.new("Motor6D")
                m.Name = motor.Name
                m.Part0 = p0 :: BasePart
                m.Part1 = p1 :: BasePart
                m.C0 = scaledOffset(motor.C0, scl)
                m.C1 = scaledOffset(motor.C1, scl)
                m.Transform = CFrame.new()
                m.Parent = newParent
            end
        end
    end

    -- Accessories: build simple visual handles and weld to head using AccessoryWeld if exists
    local head = dst:FindFirstChild("Head")
    if head and head:IsA("BasePart") then
        for _, acc in ipairs(src:GetChildren()) do
            if acc:IsA("Accoutrement") then
                local handle = acc:FindFirstChild("Handle")
                if handle and handle:IsA("BasePart") then
                    local hPart = copyVisualPart(handle)
                    hPart.Name = handle.Name
                    -- Try new weld system
                    local ok = pcall(function()
                        local weld = handle:FindFirstChildOfClass("Weld")
                        local accessWeld = (handle :: any).AccessoryWeld
                        local hatWeld = accessWeld or weld
                        if hatWeld and hatWeld:IsA("Weld") then
                            local c0, c1 = hatWeld.C0, hatWeld.C1
                            local swapped = (hatWeld.Part0 == handle)
                            if swapped then c0, c1 = c1, c0 end
                            local part0Name = (hatWeld :: any)["Part" .. (swapped and "1" or "0")].Name
                            local target0 = dst:FindFirstChild(part0Name)
                            if target0 and target0:IsA("BasePart") then
                                local w = Instance.new("Weld")
                                w.Part0 = target0
                                w.Part1 = hPart
                                w.C0 = scaledOffset(c0, scl)
                                w.C1 = scaledOffset(c1, scl)
                                w.Parent = hPart
                            end
                        else
                            error("No accessory weld")
                        end
                    end)
                    if not ok then
                        local w = Instance.new("Weld")
                        w.Part0 = head
                        w.Part1 = hPart
                        w.C0 = CFrame.new()
                        w.C1 = CFrame.new()
                        w.Parent = head
                    end
                end
            end
        end
    end

    -- Ensure HRP exists and set transparency
    local hrp = dst:FindFirstChild("HumanoidRootPart")
    if not hrp or not hrp:IsA("BasePart") then
        dst:Destroy()
        return nil
    end
    pcall(function() (hrp :: BasePart).Transparency = 1 end)
    return dst
end

-- getHRP defined above

local function collectFadeTargets(model: Model): ({BasePart}, {Instance})
    local parts = {} :: {BasePart}
    local decals = {} :: {Instance}
    for _, d in ipairs(model:GetDescendants()) do
        if isFadePart(d) then
            table.insert(parts, d :: BasePart)
        elseif isFadeDecal(d) then
            table.insert(decals, d)
        end
    end
    return parts, decals
end

local function tweenProperty(instance: Instance, property: string, toValue: any, duration: number): Tween
    local tween = TweenService:Create(instance, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        [property] = toValue
    })
    tween:Play()
    return tween
end

local function ensureAnimator(model: Model): Animator?
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        local animator = humanoid:FindFirstChildOfClass("Animator")
        if not animator then
            animator = Instance.new("Animator")
            animator.Parent = humanoid
        end
        return animator
    else
        local ac = model:FindFirstChildOfClass("AnimationController")
        if not ac then
            ac = Instance.new("AnimationController")
            ac.Parent = model
        end
        local animator = ac:FindFirstChildOfClass("Animator")
        if not animator then
            animator = Instance.new("Animator")
            animator.Parent = ac
        end
        return animator
    end
end

local function setTransparencyImmediate(model: Model, transparency: number)
    local hrp = getHRP(model)
    local parts, decals = collectFadeTargets(model)
    for _, p in ipairs(parts) do
        if hrp and p == hrp then
            p.Transparency = 1
        else
            p.Transparency = transparency
        end
    end
    for _, d in ipairs(decals) do
        if d:IsA("Decal") or d:IsA("Texture") then
            d.Transparency = transparency
        end
    end
end

local function createAgent(model: Model): TrainerIntroAgent
    local agent = {} :: any
    agent.Model = model
    agent.SpawnCFrame = nil
    agent.BehindCFrame = nil
    agent._pivotValue = Instance.new("CFrameValue")
    agent._pivotValue.Value = CFrame.new()
    agent._pivotConn = nil
    agent._animator = nil
    agent._playingTracks = {}

    function agent:PlaceAtSpawn(spawnCFrame: CFrame)
        local spawnAbove = spawnCFrame + Vector3.new(0, 3.2, 0)
        self.SpawnCFrame = spawnAbove
        self.BehindCFrame = spawnAbove * CFrame.new(0, 0, 8)
        local hrp = getHRP(self.Model)
        if hrp then
            if self.Model.PrimaryPart ~= hrp then
                pcall(function()
                    self.Model.PrimaryPart = hrp
                end)
            end
        end
        setClonePhysics(self.Model)
        -- Drive movement via PivotTo to keep rig together
        if self._pivotConn then
            self._pivotConn:Disconnect()
            self._pivotConn = nil
        end
        self._pivotValue.Value = spawnAbove
        self._pivotConn = self._pivotValue:GetPropertyChangedSignal("Value"):Connect(function()
            if self.Model.PrimaryPart ~= hrp then
                pcall(function()
                    self.Model.PrimaryPart = hrp
                end)
            end
            self.Model:SetPrimaryPartCFrame(self._pivotValue.Value)
        end)
        if self.Model.PrimaryPart ~= hrp then
            pcall(function()
                self.Model.PrimaryPart = hrp
            end)
        end
        self.Model:SetPrimaryPartCFrame(spawnAbove)
        -- Ensure HRP is always invisible; rest visible
        if hrp then
            pcall(function()
                hrp.Transparency = 1
            end)
        end
        setTransparencyImmediate(self.Model, 0)
    end

    function agent:TweenBackAndFade(distance: number, duration: number, fadeOut: boolean?)
        if not self.SpawnCFrame then return end
        local current = self._pivotValue and self._pivotValue.Value or self.SpawnCFrame
        local target = current * CFrame.new(0, 0, math.max(0, distance))
        local tweens = {} :: {Tween}
        if self._pivotValue then
            table.insert(tweens, tweenProperty(self._pivotValue, "Value", target, duration))
        end

        if fadeOut == true then
            local hrp = getHRP(self.Model)
            local parts, decals = collectFadeTargets(self.Model)
            for _, p in ipairs(parts) do
                if not (hrp and p == hrp) then
                    table.insert(tweens, tweenProperty(p, "Transparency", 1, duration))
                else
                    p.Transparency = 1
                end
            end
            for _, d in ipairs(decals) do
                table.insert(tweens, tweenProperty(d, "Transparency", 1, duration))
            end
        end
        -- No explicit wait here; callers can yield on any tween if needed
    end

    function agent:FadeInAndTweenToSpawn(duration: number, fadeIn: boolean?)
        if not (self.SpawnCFrame and self.BehindCFrame) then return end
        -- Start from behind position fully invisible
        if self._pivotValue then
            self._pivotValue.Value = self.BehindCFrame
        end
        local hrp = getHRP(self.Model)
        if self.Model.PrimaryPart ~= hrp and hrp then
            pcall(function()
                self.Model.PrimaryPart = hrp
            end)
        end
        if hrp then
            self.Model:SetPrimaryPartCFrame(self.BehindCFrame)
        end
        -- If fadeIn is explicitly false, make the model visible immediately; otherwise start invisible
        if fadeIn == false then
            setTransparencyImmediate(self.Model, 0)
        else
            setTransparencyImmediate(self.Model, 1)
        end
        local hrp = getHRP(self.Model)
        if hrp then
            pcall(function()
                hrp.Transparency = 1
            end)
        end

        local tweens = {} :: {Tween}
        if self._pivotValue then
            table.insert(tweens, tweenProperty(self._pivotValue, "Value", self.SpawnCFrame, duration))
        end
        if fadeIn ~= false then
            local parts, decals = collectFadeTargets(self.Model)
            for _, p in ipairs(parts) do
                if not (hrp and p == hrp) then
                    table.insert(tweens, tweenProperty(p, "Transparency", 0, duration))
                else
                    p.Transparency = 1
                end
            end
            for _, d in ipairs(decals) do
                table.insert(tweens, tweenProperty(d, "Transparency", 0, duration))
            end
        end
    end

    function agent:PlayAnimation(assetId: string, fadeTime: number?, looped: boolean?): AnimationTrack?
        if type(assetId) ~= "string" or assetId == "" then return nil end
        local animator = self._animator or ensureAnimator(self.Model)
        if not animator then return nil end
        self._animator = animator
        local anim = Instance.new("Animation")
        if string.find(assetId, "rbxassetid://", 1, true) then
            anim.AnimationId = assetId
        else
            anim.AnimationId = "rbxassetid://" .. assetId
        end
        local ok, track = pcall(function()
            return animator:LoadAnimation(anim)
        end)
        if not ok or not track then return nil end
        track.Looped = looped == true
        pcall(function()
            track.Priority = Enum.AnimationPriority.Action
        end)
        local ft = (type(fadeTime) == "number" and fadeTime >= 0) and fadeTime or 0.1
        pcall(function()
            track:Play(ft)
        end)
        table.insert(self._playingTracks, track)
        return track
    end

    function agent:StopAllAnimations()
        for _, tr in ipairs(self._playingTracks) do
            pcall(function()
                tr:Stop(0.1)
            end)
        end
        self._playingTracks = {}
    end

    function agent:Destroy()
        if self._pivotConn then
            self._pivotConn:Disconnect()
            self._pivotConn = nil
        end
        if self._pivotValue then
            self._pivotValue:Destroy()
            self._pivotValue = nil
        end
        self:StopAllAnimations()
        if self.Model then
            self.Model:Destroy()
        end
        self.Model = nil :: any
        self.SpawnCFrame = nil
        self.BehindCFrame = nil
    end

    return agent :: TrainerIntroAgent
end

function TrainerIntroController:PrepareFromNPC(npcModel: Model)
    if not npcModel then return end
    -- 1) Capture and stop animations on the source NPC
    local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
    local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
    local captured = {} :: { { track: AnimationTrack, time: number } }
    if animator then
        local ok, tracks = pcall(function()
            return animator:GetPlayingAnimationTracks()
        end)
        if ok and type(tracks) == "table" then
            for _, track in ipairs(tracks) do
                local tp = 0
                pcall(function()
                    tp = track.TimePosition
                end)
                table.insert(captured, { track = track, time = tp })
                pcall(function()
                    track:Stop(0)
                end)
            end
        end
    end
    -- Give the rig a frame to settle back to neutral after stopping animations
    task.wait(.1)

    -- 2) Clone the NPC in a neutral pose
    local okClone, clone = pcall(function()
        return npcModel:Clone()
    end)
    if not okClone or not clone then
        -- Attempt to restore animations if cloning failed
        for _, info in ipairs(captured) do
            pcall(function()
                info.track:Play(0)
                info.track.TimePosition = info.time
            end)
        end
        return
    end
    clone.Name = ("%s_BattleIntroClone"):format(npcModel.Name)
    -- Prevent the clone from running scripts/animations
    stripAnimationSystems(clone)
    setClonePhysics(clone)
    -- Keep off-world until placed
    local hrp = getHRP(clone)
    if hrp then
        hrp.CFrame = CFrame.new(0, -5000, 0)
        pcall(function() clone.PrimaryPart = hrp end)
    end
    preparedClone = clone

    -- 3) Restore animations on the source NPC to their prior state
    for _, info in ipairs(captured) do
        pcall(function()
            info.track:Play(0)
            info.track.TimePosition = info.time
        end)
    end
end

function TrainerIntroController:ConsumePrepared(): TrainerIntroAgent?
    if not preparedClone then return nil end
    if activeAgent then
        -- Clean up any lingering active agent to avoid leaks
        pcall(function()
            activeAgent:Destroy()
        end)
        activeAgent = nil
    end
    preparedClone.Parent = workspace
    activeAgent = createAgent(preparedClone)
    preparedClone = nil
    return activeAgent
end

function TrainerIntroController:GetActive(): TrainerIntroAgent?
    return activeAgent
end

function TrainerIntroController:DestroyActive()
    if activeAgent then
        pcall(function()
            activeAgent:Destroy()
        end)
        activeAgent = nil
    end
end

return TrainerIntroController



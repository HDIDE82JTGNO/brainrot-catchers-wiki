--[[
	HologramSpawnEffect.lua
	Professional hologram spawn effect system with scanning and flash effects
	
	Features:
	- Animated hologram spawn with outlines
	- Scanning effect that sweeps through the hologram
	- Configurable flash effect for seamless model spawning
	- Proper error handling and cleanup
	- Modular design for reusability
]]

-- Services
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Constants
local HOLOGRAM_CONFIG = {
	SIZE = Vector3.new(4, 4, 4),
	MATERIAL = Enum.Material.ForceField,
	COLOR = BrickColor.new("Bright blue"),
	TRANSPARENCY = 0.3,
	SIZE_MARGIN = Vector3.new(2.55, 2.55, 2.55), -- 1.5 studs larger on each axis (1.05 + 1.5)
}

local OUTLINE_CONFIG = {
	PRIMARY = {
		COLOR = Color3.new(0, 0.8, 1),
		THICKNESS = 0.2,
		TRANSPARENCY = 0.3
	},
	SECONDARY = {
		COLOR = Color3.new(0, 0.5, 1),
		THICKNESS = 0.15,
		TRANSPARENCY = 0.5
	},
	TERTIARY = {
		COLOR = Color3.new(0, 0.3, 0.8),
		THICKNESS = 0.1,
		TRANSPARENCY = 0.7
	}
}

local ANIMATION_CONFIG = {
	IN_DURATION = 0.48, -- 0.4 * 1.2
	HOLD_DURATION = 0.24, -- 0.2 * 1.2
	OUT_DURATION = 0.48, -- 0.4 * 1.2
	SCAN_DURATION = 0.36, -- 0.3 * 1.2
	FLASH_DURATION = 0.8, -- Increased to better mask despawn/spawn
	FLASH_HOLD = 0.3 -- Longer hold time for better masking
}

-- Utility Functions
local function createPart(name, size, position, material, color, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Anchored = true
	part.CanCollide = false
	part.Material = material
	part.BrickColor = color
	part.Transparency = transparency
	part.Parent = workspace
	return part
end

local function createSelectionBox(adornee, color, thickness, transparency)
	local selectionBox = Instance.new("SelectionBox")
	selectionBox.Adornee = adornee
	selectionBox.Color3 = color
	selectionBox.LineThickness = thickness
	selectionBox.Transparency = transparency
	selectionBox.Parent = adornee
	return selectionBox
end

local function createTween(object, tweenInfo, properties)
	return TweenService:Create(object, tweenInfo, properties)
end

-- Flash Effect Module
local FlashEffect = {}

function FlashEffect:Create(duration, hologram)
	assert(type(duration) == "number" and duration > 0, "Duration must be a positive number")
	assert(hologram and hologram:IsA("BasePart"), "Hologram must be a valid BasePart")
	
	duration = duration or ANIMATION_CONFIG.FLASH_DURATION
	
    -- Create flash box that matches hologram bounds
    local flashBox = createPart(
		"FlashEffect",
		hologram.Size + Vector3.new(0.1, 0.1, 0.1), -- Slightly larger
		hologram.Position,
		Enum.Material.Neon,
		BrickColor.new("Bright blue"),
		1 -- Start invisible
	)
    -- Match orientation to the hologram so the box aligns properly
    flashBox.CFrame = hologram.CFrame
	
	-- Add lighting effect
	local light = Instance.new("PointLight")
	light.Color = Color3.new(0.447058, 0.623529, 1) -- User's specified color
	light.Brightness = 5
	light.Range = 15
	light.Parent = flashBox
	
	-- Create animation tweens
	local fadeInTween = createTween(
		flashBox,
		TweenInfo.new(
			duration / 2,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.Out
		),
		{ Transparency = 0 }
	)
	
	local fadeOutTween = createTween(
		flashBox,
		TweenInfo.new(
			duration / 2,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.In
		),
		{ Transparency = 1 }
	)
	
	-- Execute animation sequence
	fadeInTween:Play()
	
	fadeInTween.Completed:Connect(function()
		task.wait(ANIMATION_CONFIG.FLASH_HOLD)
		-- Fade out the flash light smoothly
		local flashLightFadeTween = createTween(
			light,
			TweenInfo.new(duration / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
			{ Brightness = 0 }
		)
		flashLightFadeTween:Play()
		fadeOutTween:Play()
	end)
	
	-- Cleanup
	fadeOutTween.Completed:Connect(function()
		flashBox:Destroy()
	end)
	
	return flashBox
end

-- Scanning Effect Module
local ScanningEffect = {}

function ScanningEffect:Create(hologram)
	assert(hologram and hologram:IsA("BasePart"), "Hologram must be a valid BasePart")
	
	-- Calculate scan bounds based on hologram
	local hologramTop = hologram.Position.Y + (hologram.Size.Y / 2)
	local hologramBottom = hologram.Position.Y - (hologram.Size.Y / 2)
	local scanSize = Vector3.new(hologram.Size.X, 0.2, hologram.Size.Z)
	
	-- Create scanning box
	local scanBox = createPart(
		"ScanBox",
		scanSize,
		Vector3.new(hologram.Position.X, hologramTop, hologram.Position.Z),
		Enum.Material.ForceField,
		BrickColor.new("Bright blue"),
		0.1
	)
	
	-- Add lighting effect
	local scanLight = Instance.new("PointLight")
	scanLight.Color = Color3.new(1, 1, 1)
	scanLight.Brightness = 3
	scanLight.Range = 8
	scanLight.Parent = scanBox
	
	-- Create scan animation
	local scanTween = createTween(
		scanBox,
		TweenInfo.new(
			ANIMATION_CONFIG.SCAN_DURATION,
			Enum.EasingStyle.Linear,
			Enum.EasingDirection.InOut
		),
		{ Position = Vector3.new(hologram.Position.X, hologramBottom, hologram.Position.Z) }
	)
	
	-- Create fade out effect
	local fadeTween = createTween(
		scanBox,
		TweenInfo.new(
			0.1,
			Enum.EasingStyle.Quart,
			Enum.EasingDirection.In,
			0,
			false,
			ANIMATION_CONFIG.SCAN_DURATION
		),
		{ Transparency = 1 }
	)
	
	-- Execute animation sequence
	scanTween:Play()
	scanTween.Completed:Connect(function()
		-- Fade out the scan light smoothly
		local scanLightFadeTween = createTween(
			scanLight,
			TweenInfo.new(0.1, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
			{ Brightness = 0 }
		)
		scanLightFadeTween:Play()
		fadeTween:Play()
	end)
	
	-- Cleanup
	Debris:AddItem(scanBox, 0.5)
	
	return scanBox
end

-- Main Hologram Spawn Effect Module
local HologramSpawnEffect = {}

-- Create hologram at position; optional sizeOverride to match model bounds
function HologramSpawnEffect:Create(position, onComplete, sizeOverride)
	assert(position and typeof(position) == "Vector3", "Position must be a valid Vector3")
	
	-- Create the hologram box
	local boxSize = sizeOverride or HOLOGRAM_CONFIG.SIZE
	print("=== HOLOGRAM CREATION DEBUG ===")
	print("Position:", position)
	print("Box size:", boxSize)
	
    local hologram = createPart(
		"Hologram",
		boxSize,
		position,
		HOLOGRAM_CONFIG.MATERIAL,
		HOLOGRAM_CONFIG.COLOR,
		1 -- Start invisible
	)
    -- Keep hologram oriented like the model if a model-sized call provided sizeOverride and we get called via CreateForModel
    -- Orientation now set in CreateForModel
	
	print("Hologram created at:", hologram.Position)
	print("Hologram size:", hologram.Size)
	
	-- Add a subtle glow effect
	local pointLight = Instance.new("PointLight")
	pointLight.Color = Color3.new(0, 0.5, 1)
	pointLight.Brightness = 2
	pointLight.Range = 10
	pointLight.Parent = hologram
	
	-- Create outline layers
	local outlines = {
		createSelectionBox(hologram, OUTLINE_CONFIG.PRIMARY.COLOR, OUTLINE_CONFIG.PRIMARY.THICKNESS, 1), -- Start invisible
		createSelectionBox(hologram, OUTLINE_CONFIG.SECONDARY.COLOR, OUTLINE_CONFIG.SECONDARY.THICKNESS, 1), -- Start invisible
		createSelectionBox(hologram, OUTLINE_CONFIG.TERTIARY.COLOR, OUTLINE_CONFIG.TERTIARY.THICKNESS, 1) -- Start invisible
	}
	
	-- Initialize animation state
	hologram.Transparency = 1
	
	-- Create IN animations (no size change, just transparency)
	local inTween = createTween(
		hologram,
		TweenInfo.new(ANIMATION_CONFIG.IN_DURATION, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{
			Transparency = HOLOGRAM_CONFIG.TRANSPARENCY
		}
	)
	
	local outlineInTweens = {}
	local outlineTargetTransparencies = {
		OUTLINE_CONFIG.PRIMARY.TRANSPARENCY,
		OUTLINE_CONFIG.SECONDARY.TRANSPARENCY,
		OUTLINE_CONFIG.TERTIARY.TRANSPARENCY
	}
	
	for i, outline in ipairs(outlines) do
		outlineInTweens[i] = createTween(
			outline,
			TweenInfo.new(
				ANIMATION_CONFIG.IN_DURATION,
				Enum.EasingStyle.Quart,
				Enum.EasingDirection.Out,
				0,
				false,
				i * 0.05 -- Staggered delays
			),
			{ Transparency = outlineTargetTransparencies[i] }
		)
	end
	
	-- Create OUT animations (no size change, just transparency)
	local outTween = createTween(
		hologram,
		TweenInfo.new(ANIMATION_CONFIG.OUT_DURATION, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
		{
			Transparency = 1
		}
	)
	
	local outlineOutTweens = {}
	for i, outline in ipairs(outlines) do
		outlineOutTweens[i] = createTween(
			outline,
			TweenInfo.new(
				ANIMATION_CONFIG.OUT_DURATION,
				Enum.EasingStyle.Quart,
				Enum.EasingDirection.In,
				0,
				false,
				i * 0.05 -- Staggered delays
			),
			{ Transparency = 1 }
		)
	end
	
    -- Resolve callbacks: function is onDone; table supports { onPeak = fn, onDone = fn }
    local onPeakCallback = nil
    local onDoneCallback = nil
    if type(onComplete) == "table" then
        onPeakCallback = onComplete.onPeak
        onDoneCallback = onComplete.onDone
    elseif type(onComplete) == "function" then
        onDoneCallback = onComplete
    end

	-- Play hologram spawn-in sound effect
	local audioFolder = ReplicatedStorage:FindFirstChild("Audio")
	local sfxFolder = audioFolder and audioFolder:FindFirstChild("SFX")
	local hologramInSound = sfxFolder and sfxFolder:FindFirstChild("HologramIn")
	
	print("=== HOLOGRAM SOUND DEBUG ===")
	print("Audio folder found:", audioFolder ~= nil)
	print("SFX folder found:", sfxFolder ~= nil)
	print("HologramIn sound found:", hologramInSound ~= nil)
	
	if hologramInSound then
		local sound = hologramInSound:Clone()
		sound.Parent = hologram
		sound:Play()
		print("Playing HologramIn sound")
		-- Clean up sound after it finishes
		sound.Ended:Connect(function()
			sound:Destroy()
		end)
	else
		print("HologramIn sound not found!")
	end
	
	-- Start all IN animations
	inTween:Play()
	for _, tween in ipairs(outlineInTweens) do
		tween:Play()
	end
    
    -- At peak visibility (after IN completes), invoke onPeak if provided; then proceed
    inTween.Completed:Connect(function()
        -- Start flash immediately to mask spawn/despawn
        FlashEffect:Create(ANIMATION_CONFIG.FLASH_DURATION, hologram)
        
        if type(onPeakCallback) == "function" then
            pcall(onPeakCallback)
        end
        ScanningEffect:Create(hologram)
        task.wait(0.1) -- Small delay after scan
        task.wait(ANIMATION_CONFIG.HOLD_DURATION) -- Hold time
        
        -- Fade out the point light smoothly
        local lightFadeTween = createTween(
            pointLight,
            TweenInfo.new(ANIMATION_CONFIG.OUT_DURATION, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
            { Brightness = 0 }
        )
        lightFadeTween:Play()
        
        outTween:Play()
        for _, tween in ipairs(outlineOutTweens) do
            tween:Play()
        end
    end)
    
    -- Call completion callback when effect finishes
    outTween.Completed:Connect(function()
        if type(onDoneCallback) == "function" then
            pcall(onDoneCallback)
        end
    end)
	
	-- Cleanup
	Debris:AddItem(hologram, ANIMATION_CONFIG.IN_DURATION + ANIMATION_CONFIG.HOLD_DURATION + ANIMATION_CONFIG.OUT_DURATION + 1)
	
	return hologram
end

-- Convenience: create a hologram sized to a model's bounding box
function HologramSpawnEffect:CreateForModel(model: Model, centerPosition: Vector3, onComplete)
	assert(model and model:IsA("Model"), "Model must be a valid Model")
	assert(centerPosition and typeof(centerPosition) == "Vector3", "centerPosition must be a Vector3")

	local size = model:GetExtentsSize()
	-- Add a small margin so the effect envelope looks clean
    local padded = size + HOLOGRAM_CONFIG.SIZE_MARGIN
    local hologram = self:Create(centerPosition, onComplete, padded)
    
    -- Set the hologram's orientation to match the model pivot (not off-screen bounding box)
    local pivot = model:GetPivot()
    local rx, ry, rz = pivot:ToOrientation()
    hologram.CFrame = CFrame.new(centerPosition) * CFrame.fromOrientation(rx, ry, rz)
	
	return hologram
end

-- Create a fade-out hologram effect for when creatures faint
function HologramSpawnEffect:CreateFadeOut(model: Model, onComplete, onPeak)
	assert(model and model:IsA("Model"), "Model must be a valid Model")
	
	local size = model:GetExtentsSize()
	local padded = size + HOLOGRAM_CONFIG.SIZE_MARGIN
    local boundingBox = model:GetBoundingBox()
    local centerPosition = boundingBox.Position
    local pivot = model:GetPivot()
    local rx, ry, rz = pivot:ToOrientation()
	
	-- Create the hologram box
    local hologram = createPart(
		"HologramFadeOut",
		padded,
		centerPosition,
		HOLOGRAM_CONFIG.MATERIAL,
		HOLOGRAM_CONFIG.COLOR,
		HOLOGRAM_CONFIG.TRANSPARENCY -- Start visible
	)
    
    -- Set the hologram's orientation to match the model pivot
    hologram.CFrame = CFrame.new(centerPosition) * CFrame.fromOrientation(rx, ry, rz)
    
    -- Improve visibility specifically for fade-out (box may be too faint otherwise)
    hologram.Material = Enum.Material.Neon
    hologram.Transparency = 0.2
	
	-- Add a subtle glow effect
	local pointLight = Instance.new("PointLight")
	pointLight.Color = Color3.new(0, 0.5, 1)
	pointLight.Brightness = 2
	pointLight.Range = 10
	pointLight.Parent = hologram
	
	-- Create outline layers
	local outlines = {
		createSelectionBox(hologram, OUTLINE_CONFIG.PRIMARY.COLOR, OUTLINE_CONFIG.PRIMARY.THICKNESS, OUTLINE_CONFIG.PRIMARY.TRANSPARENCY),
		createSelectionBox(hologram, OUTLINE_CONFIG.SECONDARY.COLOR, OUTLINE_CONFIG.SECONDARY.THICKNESS, OUTLINE_CONFIG.SECONDARY.TRANSPARENCY),
		createSelectionBox(hologram, OUTLINE_CONFIG.TERTIARY.COLOR, OUTLINE_CONFIG.TERTIARY.THICKNESS, OUTLINE_CONFIG.TERTIARY.TRANSPARENCY)
	}
	
	-- Create fade-out animation with size and transparency changes for smoother effect
	local fadeOutTween = createTween(
		hologram,
		TweenInfo.new(2.0, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), -- Smoother easing
		{ 
			Transparency = 1,
			Size = hologram.Size * 1.2  -- Slightly grow while fading
		}
	)
	
	-- Fade out outlines with smoother timing
	local outlineOutTweens = {}
	for i, outline in ipairs(outlines) do
		outlineOutTweens[i] = createTween(
			outline,
			TweenInfo.new(
				1.5, -- Longer duration for smoother fade
				Enum.EasingStyle.Quart, -- Smoother easing
				Enum.EasingDirection.Out,
				0,
				false,
				i * 0.1 -- Slightly longer staggered delays
			),
			{ Transparency = 1 }
		)
	end
	
	-- Fade out the point light smoothly
	local lightFadeTween = createTween(
		pointLight,
		TweenInfo.new(1.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), -- Match outline timing
		{ Brightness = 0 }
	)
	
	-- Play hologram fade-out sound effect
	local hologramOutSound = ReplicatedStorage:FindFirstChild("Audio") and ReplicatedStorage.Audio:FindFirstChild("SFX") and ReplicatedStorage.Audio.SFX:FindFirstChild("HologramOut")
	if hologramOutSound then
		local sound = hologramOutSound:Clone()
		sound.Parent = hologram
		sound:Play()
		-- Clean up sound after it finishes
		sound.Ended:Connect(function()
			sound:Destroy()
		end)
	end
	
	-- Wait 0.25 seconds before starting the fade-out effect
	task.wait(0.25)
	
	-- Call peak callback after delay (for fade-out, peak is at the beginning)
	if onPeak and type(onPeak) == "function" then
		pcall(onPeak)
	end
	
	-- Start all fade-out animations
	fadeOutTween:Play()
	lightFadeTween:Play()
	for _, tween in ipairs(outlineOutTweens) do
		tween:Play()
	end
	
	-- Call completion callback when effect finishes
	local completedFired = false
	fadeOutTween.Completed:Connect(function()
		completedFired = true
		if onComplete and type(onComplete) == "function" then
			pcall(onComplete)
		end
	end)
	-- Safety fallback: if the hologram is cleaned up early (e.g., via Debris), ensure onComplete still fires
	task.delay(ANIMATION_CONFIG.OUT_DURATION + 0.15, function()
		if not completedFired and onComplete and type(onComplete) == "function" then
			pcall(onComplete)
		end
	end)
	
	-- Cleanup
	-- Ensure hologram persists long enough for Completed to fire; then clean up with margin
	Debris:AddItem(hologram, ANIMATION_CONFIG.OUT_DURATION + 0.5)
	
	return hologram
end

return HologramSpawnEffect

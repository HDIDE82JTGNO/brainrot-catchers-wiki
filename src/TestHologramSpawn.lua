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

-- Constants
local HOLOGRAM_CONFIG = {
	SIZE = Vector3.new(4, 4, 4),
	POSITION = Vector3.new(0, 2, 0),
	MATERIAL = Enum.Material.ForceField,
	COLOR = BrickColor.new("Bright blue"),
	TRANSPARENCY = 0.3
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
	IN_DURATION = 0.4,
	HOLD_DURATION = 0.2,
	OUT_DURATION = 0.4,
	SCAN_DURATION = 0.3,
	FLASH_DURATION = 0.5,
	FLASH_HOLD = 0.02
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
	
	-- Add lighting effect
	local light = Instance.new("PointLight")
	light.Color = Color3.new(0, 0, 0.8)
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
		fadeTween:Play()
	end)
	
	-- Cleanup
	Debris:AddItem(scanBox, 0.5)
	
	return scanBox
end

-- Main Hologram Spawn Effect Module
local HologramSpawnEffect = {}

function HologramSpawnEffect:Create(config)
	config = config or {}
	
	-- Create hologram with configuration
	local hologram = createPart(
		config.name or "HologramSpawn",
		config.size or HOLOGRAM_CONFIG.SIZE,
		config.position or HOLOGRAM_CONFIG.POSITION,
		config.material or HOLOGRAM_CONFIG.MATERIAL,
		config.color or HOLOGRAM_CONFIG.COLOR,
		config.transparency or HOLOGRAM_CONFIG.TRANSPARENCY
	)
	
	-- Add lighting effect
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
	hologram.Size = Vector3.new(0.1, 0.1, 0.1)
	
	for _, outline in ipairs(outlines) do
		outline.Transparency = 1
	end
	
	-- Create IN animations
	local inTween = createTween(
		hologram,
		TweenInfo.new(
			ANIMATION_CONFIG.IN_DURATION,
			Enum.EasingStyle.Quart,
			Enum.EasingDirection.Out
		),
		{
			Transparency = HOLOGRAM_CONFIG.TRANSPARENCY,
			Size = HOLOGRAM_CONFIG.SIZE
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
	
	-- Create OUT animations
	local outTween = createTween(
		hologram,
		TweenInfo.new(
			ANIMATION_CONFIG.OUT_DURATION,
			Enum.EasingStyle.Quart,
			Enum.EasingDirection.In
		),
		{
			Transparency = 1,
			Size = Vector3.new(0.1, 0.1, 0.1)
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
	
	-- Execute IN animations
	inTween:Play()
	for _, tween in ipairs(outlineInTweens) do
		tween:Play()
	end
	
	-- Execute OUT animations after IN completes
	inTween.Completed:Connect(function()
		-- Create scanning effect
		ScanningEffect:Create(hologram)
		
		-- Create flash effect after scan
		task.wait(0.1)
		FlashEffect:Create(ANIMATION_CONFIG.FLASH_DURATION, hologram)
		
		-- Start OUT animations after hold
		task.wait(ANIMATION_CONFIG.HOLD_DURATION)
		outTween:Play()
		for _, tween in ipairs(outlineOutTweens) do
			tween:Play()
		end
	end)
	
	-- Cleanup
	Debris:AddItem(hologram, 2)
	
	return hologram
end

-- Test Functions
local function testHologramSpawn()
	print("Creating hologram spawn effect...")
	HologramSpawnEffect:Create()
end

local function testFlashEffect()
	print("Testing flash effect...")
	local testHologram = createPart(
		"TestHologram",
		HOLOGRAM_CONFIG.SIZE,
		HOLOGRAM_CONFIG.POSITION,
		HOLOGRAM_CONFIG.MATERIAL,
		HOLOGRAM_CONFIG.COLOR,
		0.3
	)
	
	FlashEffect:Create(0.5, testHologram)
	Debris:AddItem(testHologram, 1)
end

-- Execute main effect
testHologramSpawn()

-- Uncomment to test individual effects
-- testFlashEffect()
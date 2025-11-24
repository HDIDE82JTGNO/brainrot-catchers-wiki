--!strict
--[[
	BadgeAnimation.lua
	Displays a badge animation with blur effect, 3D model rotation, and fade in/out
]]

local BadgeAnimation = {}

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

--[[
	Plays a badge animation
	@param badgeName The name of the badge model (e.g., "Grass")
	@param duration Duration of the animation in seconds (default: 5)
	@return Promise that resolves when animation completes
]]
function BadgeAnimation:Play(badgeName: string, duration: number?): boolean
	duration = duration or 5
	
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local gameUI = playerGui:WaitForChild("GameUI")
	
	-- Get or create BadgeAnimation container in GameUI
	local badgeContainer = gameUI:FindFirstChild("BadgeAnimation")
	if not badgeContainer then
		badgeContainer = Instance.new("Frame")
		badgeContainer.Name = "BadgeAnimation"
		badgeContainer.Size = UDim2.fromScale(1, 1)
		badgeContainer.Position = UDim2.fromScale(0, 0)
		badgeContainer.BackgroundTransparency = 1
		badgeContainer.ZIndex = 1000
		badgeContainer.Visible = false
		badgeContainer.Parent = gameUI
	end
	
	-- Clear any existing viewport
	local existingViewport = badgeContainer:FindFirstChild("Viewport")
	if existingViewport then
		existingViewport:Destroy()
	end
	
	-- Create ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Viewport"
	viewport.Size = UDim2.fromScale(0.4, 0.4)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.ZIndex = 1001
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.Ambient = Color3.fromRGB(255, 255, 255)
	viewport.Parent = badgeContainer
	
	-- Create WorldModel for the viewport
	local worldModel = Instance.new("WorldModel")
	worldModel.Name = "WorldModel"
	worldModel.Parent = viewport
	
	-- Create Camera
	local cam = Instance.new("Camera")
	cam.Name = "ViewportCamera"
	cam.Parent = viewport
	viewport.CurrentCamera = cam
	
	-- Load badge model from ReplicatedStorage.Assets.Models.Badges.{badgeName}
	local assets = ReplicatedStorage:WaitForChild("Assets")
	local models = assets:WaitForChild("Models")
	local badges = models:WaitForChild("Badges")
	local badgeTemplate = badges:FindFirstChild(badgeName)
	
	if not badgeTemplate then
		warn("[BadgeAnimation] Badge model not found:", badgeName, "in", badges:GetFullName())
		warn("[BadgeAnimation] Available badges:")
		for _, child in ipairs(badges:GetChildren()) do
			warn("  -", child.Name, "(" .. child.ClassName .. ")")
		end
		viewport:Destroy()
		return false
	end
	
	-- Clone the badge (can be MeshPart or Model)
	local badgeClone = badgeTemplate:Clone()
	
	-- If it's a MeshPart, wrap it in a Model for easier handling
	local badgeModel
	if badgeClone:IsA("MeshPart") then
		badgeModel = Instance.new("Model")
		badgeModel.Name = badgeName
		badgeClone.Parent = badgeModel
		badgeModel.PrimaryPart = badgeClone
	elseif badgeClone:IsA("Model") then
		badgeModel = badgeClone
	else
		warn("[BadgeAnimation] Badge template is not a MeshPart or Model:", badgeName, "is", badgeClone.ClassName)
		viewport:Destroy()
		return false
	end
	
	badgeModel.Parent = worldModel
	
	-- Center the model at origin
	badgeModel:PivotTo(CFrame.new(0, 0, 0))
	
	-- Frame camera around the badge model
	local cf, size = badgeModel:GetBoundingBox()
	local focus = cf.Position
	local radius = math.max(size.X, size.Y, size.Z) * 0.7
	local eye = focus + Vector3.new(0, size.Y * 0.25, -radius * 2)
	cam.CFrame = CFrame.lookAt(eye, focus)
	
	-- Set initial transparency to 1 (fully transparent) for fade in
	for _, descendant in ipairs(badgeModel:GetDescendants()) do
		if descendant:IsA("BasePart") or descendant:IsA("MeshPart") then
			descendant.Transparency = 1
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = 1
		end
	end
	
	-- Create blur effect in Lighting
	local blurEffect = game.Lighting:FindFirstChildOfClass("BlurEffect")
	if not blurEffect then
		blurEffect = Instance.new("BlurEffect")
		blurEffect.Parent = game.Lighting
	end
	
	-- Store original blur size
	local originalBlurSize = blurEffect.Size or 0
	blurEffect.Size = 1
	
	-- Show the container
	badgeContainer.Visible = true
	
	-- Animation timeline
	local fadeInDuration = 0.5
	local fadeOutDuration = 0.5
	local rotationDuration = duration -- Full duration for rotation
	
	-- Blur animation (tween from 1 to 35, then back to 0 and destroy)
	local blurTweenIn = TweenService:Create(
		blurEffect,
		TweenInfo.new(fadeInDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = 35 }
	)
	
	local blurTweenOut = TweenService:Create(
		blurEffect,
		TweenInfo.new(fadeOutDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = 0 }
	)
	
	-- Start blur fade in
	blurTweenIn:Play()
	
	-- Start rotation animation (360 degrees on Y axis) - rotates continuously for full duration
	local rotationStartTime = tick()
	local rotationConnection
	
	rotationConnection = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - rotationStartTime
		if elapsed >= duration then
			rotationConnection:Disconnect()
			return
		end
		
		-- Rotate 360 degrees over the full duration
		local progress = elapsed / duration
		local currentRotation = 360 * progress
		badgeModel:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(currentRotation), 0))
	end)
	
	-- Fade in model parts (transparency goes from 1 to 0)
	local fadeInStartTime = tick()
	while tick() - fadeInStartTime < fadeInDuration do
		local elapsed = tick() - fadeInStartTime
		local alpha = math.min(elapsed / fadeInDuration, 1)
		for _, descendant in ipairs(badgeModel:GetDescendants()) do
			if descendant:IsA("BasePart") or descendant:IsA("MeshPart") then
				descendant.Transparency = 1 - alpha  -- 1 -> 0
			elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
				descendant.Transparency = 1 - alpha  -- 1 -> 0
			end
		end
		task.wait()
	end
	
	-- Ensure model is fully visible (transparency = 0)
	for _, descendant in ipairs(badgeModel:GetDescendants()) do
		if descendant:IsA("BasePart") or descendant:IsA("MeshPart") then
			descendant.Transparency = 0
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = 0
		end
	end
	
	-- Wait for main rotation duration (after fade in, before fade out)
	local mainDuration = duration - fadeInDuration - fadeOutDuration
	task.wait(mainDuration)
	
	-- Fade out model parts (transparency goes from 0 to 1)
	local fadeOutStartTime = tick()
	while tick() - fadeOutStartTime < fadeOutDuration do
		local elapsed = tick() - fadeOutStartTime
		local alpha = math.min(elapsed / fadeOutDuration, 1)
		for _, descendant in ipairs(badgeModel:GetDescendants()) do
			if descendant:IsA("BasePart") or descendant:IsA("MeshPart") then
				descendant.Transparency = alpha  -- 0 -> 1
			elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
				descendant.Transparency = alpha  -- 0 -> 1
			end
		end
		task.wait()
	end
	
	-- Start blur fade out
	blurTweenOut:Play()
	blurTweenOut.Completed:Wait()
	
	-- Cleanup
	if rotationConnection then
		rotationConnection:Disconnect()
	end
	
	-- Destroy blur effect after fade out completes
	if blurEffect then
		blurEffect:Destroy()
	end
	
	badgeContainer.Visible = false
	viewport:Destroy()
	
	return true
end

return BadgeAnimation
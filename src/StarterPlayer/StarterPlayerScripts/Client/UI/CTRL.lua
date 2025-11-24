--!nocheck
local CTRLModule = {}
local isOpen = false

--// Services
local TweenService: TweenService = game:GetService("TweenService")

local Audio = script.Parent.Parent.Assets:WaitForChild("Audio")

--// Animation Constants
local OPEN_SIZE: UDim2 = UDim2.new(0.563, 0, 0.632, 0)
local CLOSED_SIZE: UDim2 = UDim2.fromScale(0, 0)

--// CTRL Open
function CTRLModule:Open(All)
	if isOpen then return end -- Already open, don't open again
	
	isOpen = true
	local CTRL: ScreenGui & {
		Shadow: { Image: ImageLabel },
		Topbar: {
			Size: UDim2,
			Icon: ImageLabel,
			IconShadow: ImageLabel,
			Title: TextLabel,
		},
		Darken: Frame,
	} = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("CTRL")
	
	Audio.SFX.Open:Play()

	CTRL.Visible = true
	CTRL.Size = CLOSED_SIZE

	-- Main Frame
	TweenService:Create(CTRL, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Size = OPEN_SIZE,
	}):Play()
	
	CTRL.Position = UDim2.new(0.5, 0, 0.5, 0)

	-- Shadow
	if CTRL:FindFirstChild("Shadow") and CTRL.Shadow:FindFirstChild("Image") then
		CTRL.Shadow.Image.ImageTransparency = 1
		TweenService:Create(CTRL.Shadow.Image, TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			ImageTransparency = 0.5,
		}):Play()
	end

	-- Topbar
	if CTRL:FindFirstChild("Topbar") then
		CTRL.Topbar.Size = UDim2.fromScale(1, 0.165)
		TweenService:Create(CTRL.Topbar, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(1, 0.107),
		}):Play()

		-- Icon + Shadow
		if CTRL.Topbar:FindFirstChild("Icon") then
			CTRL.Topbar.Icon.Rotation = 25
			CTRL.Topbar.Icon.Position = UDim2.new(0.05, 0, 0.341, 0)
			TweenService:Create(CTRL.Topbar.Icon, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Rotation = 0,
				Position = UDim2.new(0.041, 0, 0.185, 0),
			}):Play()
		end
		
		if CTRL.Topbar:FindFirstChild("IconShadow") then
			CTRL.Topbar.IconShadow.Position = UDim2.new(0.084, 0, 0.682, 0)
			TweenService:Create(CTRL.Topbar.IconShadow, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.066, 0, 0.526, 0),
			}):Play()
		end

		-- Title
		if CTRL.Topbar:FindFirstChild("Title") then
			CTRL.Topbar.Title.MaxVisibleGraphemes = 0
			TweenService:Create(CTRL.Topbar.Title, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				MaxVisibleGraphemes = 11,
			}):Play()
		end
	end

	-- Darken
	if CTRL:FindFirstChild("Darken") then
		CTRL.Darken.Size = CLOSED_SIZE
		TweenService:Create(CTRL.Darken, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
			Size = UDim2.new(4.0125*1.2, 0,6.0945*1.2, 0),	
		}):Play()
	end
end

--// CTRL Close
function CTRLModule:Close(All)
	All = All or {} -- Make All parameter optional
	if not isOpen then return end -- Not open, don't close
	
	isOpen = false
	local CTRL: ScreenGui & {
		Shadow: { Image: ImageLabel },
		Topbar: {
			Size: UDim2,
			Icon: ImageLabel,
			IconShadow: ImageLabel,
			Title: TextLabel,
		},
		Darken: Frame,
	} = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("CTRL")

	Audio.SFX.Close:Play()
	
	task.delay(0.1, function()
		TweenService:Create(CTRL, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Size = CLOSED_SIZE,
		}):Play()
	end)

	if CTRL:FindFirstChild("Shadow") and CTRL.Shadow:FindFirstChild("Image") then
		TweenService:Create(CTRL.Shadow.Image, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			ImageTransparency = 1,
		}):Play()
	end

	if CTRL:FindFirstChild("Topbar") then
		TweenService:Create(CTRL.Topbar, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(1, 0.1),
		}):Play()

		if CTRL.Topbar:FindFirstChild("Icon") then
			TweenService:Create(CTRL.Topbar.Icon, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Rotation = 25,
				Position = UDim2.new(0.05, 0, 0.341, 0),
			}):Play()
		end
		
		if CTRL.Topbar:FindFirstChild("IconShadow") then
			TweenService:Create(CTRL.Topbar.IconShadow, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.084, 0, 0.682, 0),
			}):Play()
		end

		if CTRL.Topbar:FindFirstChild("Title") then
			TweenService:Create(CTRL.Topbar.Title, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				MaxVisibleGraphemes = 0,
			}):Play()
		end
	end

	if CTRL:FindFirstChild("Darken") then
		TweenService:Create(CTRL.Darken, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Size = CLOSED_SIZE,
		}):Play()
	end

	task.delay(0.4, function()
		CTRL.Visible = false
	end)
end

return CTRLModule


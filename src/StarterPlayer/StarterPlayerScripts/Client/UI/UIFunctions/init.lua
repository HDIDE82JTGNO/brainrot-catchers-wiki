local UIFunctions = {}

local TweenService = game:GetService("TweenService")
local PlayerGui = game.Players.LocalPlayer.PlayerGui

local ButtonClass = require(script:WaitForChild("Button"))

-- Simple signal for when CircularTransition finishes hiding
local _circularHiddenEvent = Instance.new("BindableEvent")
UIFunctions.OnCircularTransitionHidden = _circularHiddenEvent.Event

function UIFunctions:NewButton(...)
	return ButtonClass.new(...)
end

function UIFunctions:AddSpacesToCaps(str)
    -- Special-case: return early to avoid re-spacing "XP Spread" into "X P Spread"
    if str == "XPSpread" then
        return "XP Spread"
    end
    -- Generic fallback: insert spaces before capitals
    return str:gsub("(%u)", " %1"):gsub("^ ", "")
end

function UIFunctions:RemoveSpaces(str)
	return str:gsub("%s+", "")
end

function UIFunctions:ClearConnection(Inst)
	if Inst:IsA("GUIButton") then
		return ButtonClass:ClearConnection(Inst)
	end
end

local SpinningTask = nil

local Sizings = {
	OffScreen = UDim2.fromScale(1.599, 2.159),
	BeforeClose = UDim2.fromScale(0.686, 0.927),
	Closed = UDim2.fromScale(0.01,0.01)
}

function UIFunctions:CircularTransition(Circle,Bool)
	task.spawn(function()
		local Camera = workspace.CurrentCamera
		local OriginalFOV = 70 -- Static FOV value
		
		if Bool then 
			-- Start transition (screen goes black)
			Circle.Visible = true
			Circle.Size = Sizings.OffScreen
			Circle.BackgroundTransparency = 1 -- Fill is transparent when not closed
			
			-- FOV starts at normal, zooms in as circle shrinks
			Camera.FieldOfView = OriginalFOV
			local FOVTween1 = TweenService:Create(Camera, TweenInfo.new(0.33, Enum.EasingStyle.Back), {
				FieldOfView = 55
			})
			
			local Tween1 = TweenService:Create(Circle, TweenInfo.new(0.33, Enum.EasingStyle.Back), {Size = Sizings.BeforeClose})
			Tween1:Play()
			FOVTween1:Play()
			Tween1.Completed:Wait()
			
			task.wait(0.15) -- Small buffer
			
			-- Continue zooming in as circle closes completely
			local FOVTween2 = TweenService:Create(Camera, TweenInfo.new(0.52, Enum.EasingStyle.Back,Enum.EasingDirection.In), {
				FieldOfView = 40
			})
			
			local Tween2 = TweenService:Create(Circle, TweenInfo.new(0.52, Enum.EasingStyle.Back,Enum.EasingDirection.In), {Size = Sizings.Closed})
			Tween2:Play()
			FOVTween2:Play()
			Tween2.Completed:Wait()
			
			-- When circle reaches closed state, make fill visible
			Circle.BackgroundTransparency = 0
		else
			-- End transition (screen comes back)
			Circle.Size = Sizings.Closed
			Circle.BackgroundTransparency = 0 -- Fill is visible when in closed state
			
			-- Immediately reset FOV to 70
			Camera.FieldOfView = OriginalFOV
			
			-- Make fill transparent when circle starts getting bigger
			Circle.BackgroundTransparency = 1
			
			local Tween1 = TweenService:Create(Circle, TweenInfo.new(0.33, Enum.EasingStyle.Back), {Size = Sizings.BeforeClose})
			Tween1:Play()
			Tween1.Completed:Wait()
			
			task.wait(0.15) -- Small buffer
			
			local Tween2 = TweenService:Create(Circle, TweenInfo.new(0.52, Enum.EasingStyle.Back,Enum.EasingDirection.In), {Size = Sizings.OffScreen})
			Tween2:Play()
			Tween2.Completed:Wait()
			Circle.Visible = false
			-- Notify listeners that the circular transition has fully hidden
			pcall(function()
				_circularHiddenEvent:Fire()
			end)
		end
	end)
	return true
end


function UIFunctions:Transition(Active:boolean, Yeild:any)

	warn("Attempting to transition to: " .. tostring(Active))
	local TargetTransparency = Active and 0 or 1

	TweenService:Create(PlayerGui.GameUI.Blackout, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		BackgroundTransparency = TargetTransparency
	}):Play()
	TweenService:Create(PlayerGui.GameUI.Blackout.Loading, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		ImageTransparency = TargetTransparency
	}):Play()

	if Active then
		if SpinningTask then
			task.cancel(SpinningTask)
			SpinningTask = nil
		end

		SpinningTask = task.spawn(function()
			while true do
				task.wait()
				PlayerGui.GameUI.Blackout.Loading.Rotation += 0.2
			end
		end)
	else
		if SpinningTask then
			task.delay(0.5, function()
				if SpinningTask then
					task.cancel(SpinningTask)
					SpinningTask = nil
				end
			end)
		end
	end
end

function UIFunctions:SaveNotificationSuccess(SaveNotificationFrame)
	-- Reset states
	SaveNotificationFrame.BackgroundTransparency = 1
	SaveNotificationFrame.Arrow.ImageTransparency = 1
	SaveNotificationFrame.Arrow.Size = UDim2.fromScale(.55,.536)
	SaveNotificationFrame.Line.ImageTransparency = 1
	SaveNotificationFrame.Line.Size = UDim2.fromScale(.55,.536)
	SaveNotificationFrame.Check.Rotation = -270
	SaveNotificationFrame.Check.ImageTransparency = 1
	SaveNotificationFrame.Check.Size = UDim2.fromScale(.7,.7)
	SaveNotificationFrame.AutoSave.ImageTransparency = 1

	-- Fade in background & line
	TweenService:Create(SaveNotificationFrame, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.5,
	}):Play()

	TweenService:Create(SaveNotificationFrame.Line, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		ImageTransparency = 0,
	}):Play()

	-- Arrow in
	SaveNotificationFrame.Arrow.Position = UDim2.fromScale(0.5, -0.1)
	TweenService:Create(SaveNotificationFrame.Arrow, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		ImageTransparency = 0,
		Position = UDim2.fromScale(.5,.4)
	}):Play()
	task.wait(1)

	-- Arrow & line shrink out
	TweenService:Create(SaveNotificationFrame.Arrow, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
		Size = UDim2.fromScale(0,0),
		ImageTransparency = 1
	}):Play()

	TweenService:Create(SaveNotificationFrame.Line, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
		Size = UDim2.fromScale(0,0),
		ImageTransparency = 1
	}):Play()

	-- Tick comes last
	task.wait(0.3)
	TweenService:Create(SaveNotificationFrame.Check, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		ImageTransparency = 0,
		Rotation = 0,
		Size = UDim2.fromScale(0.75,0.75)
	}):Play()

	task.wait(1.25)

	-- Fade everything out
	TweenService:Create(SaveNotificationFrame.Check, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		ImageTransparency = 1,
	}):Play()

	TweenService:Create(SaveNotificationFrame, TweenInfo.new(0.65, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
end

function UIFunctions:DoExclamationMark(ExclamationMark, opts)
	print("starting exclamation mark")
	
	-- Start intro music deterministically at the very beginning
	print("=== ATTEMPTING TO START EXCL INTRO MUSIC ===")
	local MusicManager
	local success, error = pcall(function()
		print("Requiring MusicManager...")
		MusicManager = require(script.Parent.Parent.Utilities.MusicManager)
		print("MusicManager required successfully")
		-- Prefer explicit battle type when provided by caller
		local battleType = nil
		if type(opts) == "table" then
			battleType = opts.BattleType or opts.Type
		end
		if battleType == "Trainer" then
			print("[Exclamation] Trainer battle intro → TrainerBattle BGM")
			MusicManager:StartTrainerBattleMusic()
		else
			print("[Exclamation] Wild/unknown intro → Encounter music")
			MusicManager:StartEncounterMusic()
		end
	end)
	
	if not success then
		print("ERROR starting exclamation intro:", error)
	else
		print("Exclamation intro started successfully")
	end
	
	-- Reset all properties to ensure clean animation
	ExclamationMark.Visible = true
	ExclamationMark.ImageTransparency = 0
	ExclamationMark.BackgroundTransparency = 1
	workspace.CurrentCamera.FieldOfView = 70
	ExclamationMark.Size = UDim2.fromScale(0,0)
	
	local FirstTimer:number = 0.5
	TweenService:Create(ExclamationMark, TweenInfo.new(FirstTimer,Enum.EasingStyle.Back,Enum.EasingDirection.Out), {Size = UDim2.fromScale(0.209,0.734)}):Play()
	TweenService:Create(workspace.CurrentCamera, TweenInfo.new(FirstTimer,Enum.EasingStyle.Back,Enum.EasingDirection.Out), {FieldOfView = 75}):Play()
	task.wait(FirstTimer)
	TweenService:Create(workspace.CurrentCamera, TweenInfo.new(FirstTimer,Enum.EasingStyle.Back,Enum.EasingDirection.Out), {FieldOfView = 70}):Play()
	task.wait(FirstTimer)
	local SecondTimer:number = 0.4
	TweenService:Create(ExclamationMark, TweenInfo.new(SecondTimer,Enum.EasingStyle.Back,Enum.EasingDirection.InOut), {Size = UDim2.fromScale(3.142,11.026)}):Play()
	task.wait(SecondTimer/3)
	TweenService:Create(workspace.CurrentCamera, TweenInfo.new(SecondTimer*1.5,Enum.EasingStyle.Back,Enum.EasingDirection.Out), {FieldOfView = 10}):Play()
	
	-- Wait for the camera zoom to complete
	task.wait(SecondTimer*1.5)
	
	print("exclamation mark grow animation completed")
end

function UIFunctions:FadeOutExclamationMark(ExclamationMark)
	print("fading out exclamation mark")
	
	-- Force FOV to 50 immediately when starting fade out
	workspace.CurrentCamera.FieldOfView = 45
	
	-- Fade out the exclamation mark
	local FadeOutInfo = TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local FadeOutTween = TweenService:Create(ExclamationMark, FadeOutInfo, {ImageTransparency = 1})
	FadeOutTween:Play()
	
	-- Show battle UI (we need to get it from the battle system)
	local PlayerGui = game.Players.LocalPlayer.PlayerGui
	local GameUI = PlayerGui:FindFirstChild("GameUI")
	if GameUI then
		local BattleUI = GameUI:FindFirstChild("BattleUI")
		if BattleUI then
			BattleUI.Visible = true
		end
	end

	-- Wait for fade to complete to guarantee sequencing, then hide mark
	FadeOutTween.Completed:Wait()
	ExclamationMark.Visible = false
	
	print("exclamation mark fade out completed")
end

function UIFunctions:BlackBars(Active: boolean, Blackbars: ImageLabel)
	if not Blackbars or not Blackbars:IsA("ImageLabel") then return end
	task.spawn(function()
		if Active == true then
			Blackbars.Visible = true
			Blackbars.Size = UDim2.fromScale(1, 15)
			TweenService:Create(Blackbars, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 10.5) }):Play()
		else
			Blackbars.Size = UDim2.fromScale(1, 10.5)
			TweenService:Create(Blackbars, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 15) }):Play()
			task.wait(0.35)
			Blackbars.Visible = false
		end
	end)
end

-- Show the location name with a type-in and blink animation
function UIFunctions:ShowLocationName(UI: GuiObject, LocationName: string)
	if not UI then return end
	task.spawn(function()
		local Which = UI:FindFirstChild("Which")
		if not Which or not Which:IsA("TextLabel") then return end

		Which.Text = LocationName
		Which.MaxVisibleGraphemes = 0
		local l = #LocationName
		for count = 1, l do
			task.wait(0.03)
			Which.MaxVisibleGraphemes = count
		end
		task.wait(1.25)
		for count = l, 0, -1 do
			task.wait(0.02)
			Which.MaxVisibleGraphemes = count
		end
	end)
end

return UIFunctions

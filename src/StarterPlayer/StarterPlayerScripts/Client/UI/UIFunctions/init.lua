local UIFunctions = {}

local TweenService = game:GetService("TweenService")
local PlayerGui = game.Players.LocalPlayer.PlayerGui

local ButtonClass = require(script:WaitForChild("Button"))
local StudBurstEmitter = require(script.Parent:WaitForChild("Effects"):WaitForChild("StudBurstEmitter"))

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
	-- Resolve UI references safely
	local pg = PlayerGui or (game.Players.LocalPlayer and game.Players.LocalPlayer:FindFirstChild("PlayerGui"))
	if not pg then
		warn("[UIFunctions.Transition] PlayerGui not available")
		return false
	end
	local gameUI = pg:FindFirstChild("GameUI")
	if not gameUI then
		warn("[UIFunctions.Transition] GameUI not found in PlayerGui")
		return false
	end
	local blackout = gameUI:FindFirstChild("Blackout")
	if not blackout then
		warn("[UIFunctions.Transition] Blackout frame not found")
		return false
	end
	local loading = blackout:FindFirstChild("Loading")
	if not loading then
		warn("[UIFunctions.Transition] Blackout.Loading not found")
		return false
	end

	local TargetTransparency = Active and 0 or 1

	-- Ensure visibility state so tween actually shows/hides
	if Active then
		blackout.Visible = true
		loading.Visible = true
	end

	TweenService:Create(blackout, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		BackgroundTransparency = TargetTransparency
	}):Play()
	TweenService:Create(loading, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
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
				loading.Rotation += 0.2
			end
		end)
	else
		-- When hiding, schedule visibility off after fade
		task.delay(0.55, function()
			blackout.Visible = false
			loading.Visible = false
		end)
		if SpinningTask then
			task.delay(0.5, function()
				if SpinningTask then
					task.cancel(SpinningTask)
					SpinningTask = nil
				end
			end)
		end
	end
	return true
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

function UIFunctions:DoExclamationMark(_, opts)
	print("starting question mark intro")
	
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

	-- Resolve UI
	local pg = PlayerGui or (game.Players.LocalPlayer and game.Players.LocalPlayer:FindFirstChild("PlayerGui"))
	local gameUI = pg and pg:FindFirstChild("GameUI")
	if not gameUI then
		warn("[UIFunctions.DoExclamationMark] GameUI not found; cannot play question mark UI")
		return false
	end

	local BlackBars = gameUI:FindFirstChild("BlackBars")
	local QuestionMark = gameUI:FindFirstChild("QuestionMark")
	local Flashing = gameUI:FindFirstChild("Flashing")
	if not (BlackBars and QuestionMark and Flashing) then
		warn("[UIFunctions.DoExclamationMark] Missing QuestionMark UI parts (BlackBars/QuestionMark/Flashing)")
		return false
	end

	-- Fire stud burst alongside the intro if the template exists
	task.spawn(function()
		StudBurstEmitter.playBurst(gameUI :: ScreenGui)
	end)

	-- Hide legacy exclamation mark instance if one was passed
	if _ and typeof(_) == "Instance" then
		pcall(function()
			_.Visible = false
		end)
	end

	-- Reset all properties to ensure clean animation
	BlackBars.Visible = true
	BlackBars.Size = UDim2.fromScale(1, 15)

	QuestionMark.Visible = true
	QuestionMark.Rotation = 0
	QuestionMark.Position = UDim2.fromScale(0.5,0.5)
	QuestionMark.Size = UDim2.fromScale(0, 0)

	Flashing.BackgroundTransparency = 1
	Flashing.Visible = true

	TweenService:Create(BlackBars, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 10.5) }):Play()
	TweenService:Create(QuestionMark, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(0.045,0.112) }):Play()

	task.wait(0.65)

	TweenService:Create(QuestionMark, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(0.22,0.467) }):Play()
	TweenService:Create(QuestionMark, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = -3 }):Play()
	TweenService:Create(Flashing, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { BackgroundTransparency = 0 }):Play()
	TweenService:Create(BlackBars, TweenInfo.new(2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 15) }):Play()

	print("question mark animation queued")
	return true
end

function UIFunctions:FadeOutExclamationMark(_)
	print("fading out question mark")
	
	-- Let the question mark linger a bit before fading out
	task.wait(0.8)
	
	local pg = PlayerGui or (game.Players.LocalPlayer and game.Players.LocalPlayer:FindFirstChild("PlayerGui"))
	local gameUI = pg and pg:FindFirstChild("GameUI")
	if not gameUI then
		warn("[UIFunctions.FadeOutExclamationMark] GameUI not found; cannot fade question mark")
		return false
	end

	local QuestionMark = gameUI:FindFirstChild("QuestionMark")
	local Flashing = gameUI:FindFirstChild("Flashing")
	local BlackBars = gameUI:FindFirstChild("BlackBars")

	-- Hide legacy exclamation mark instance if one was passed
	if _ and typeof(_) == "Instance" then
		pcall(function()
			_.Visible = false
		end)
	end
	
	-- Fade out the question mark UI
	if QuestionMark then
		QuestionMark.Visible = false
		-- Reset to baseline so next run starts from a known state
		pcall(function()
			QuestionMark.Size = UDim2.fromScale(0, 0)
			QuestionMark.Rotation = 0
			QuestionMark.Position = UDim2.fromScale(0.5, 0.5)
		end)
	end

	local FlashTween
	if Flashing then
		FlashTween = TweenService:Create(Flashing, TweenInfo.new(0.63, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { BackgroundTransparency = 1 })
		FlashTween:Play()
	end
	
	-- Show battle UI (we need to get it from the battle system)
	local BattleUI = gameUI:FindFirstChild("BattleUI")
	if BattleUI then
		BattleUI.Visible = true
	end

	-- Wait for fade to complete to guarantee sequencing
	if FlashTween then
		FlashTween.Completed:Wait()
	end

	if Flashing then
		Flashing.Visible = false
		pcall(function()
			Flashing.BackgroundTransparency = 1
		end)
	end

	task.delay(2, function()
		if BlackBars then
			BlackBars.Visible = false
			pcall(function()
				BlackBars.Size = UDim2.fromScale(1, 15)
			end)
		end
	end)
	
	print("question mark fade out completed")
	return true
end

function UIFunctions:BlackBars(Active: boolean, Blackbars: ImageLabel, Timer : number?)
	if not Blackbars or not Blackbars:IsA("ImageLabel") then return end
	local timer = Timer or 0.35
	task.spawn(function()
		if Active == true then
			Blackbars.Visible = true
			Blackbars.Size = UDim2.fromScale(1, 15)
			TweenService:Create(Blackbars, TweenInfo.new(timer, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 10.5) }):Play()
		else
			Blackbars.Size = UDim2.fromScale(1, 10.5)
			TweenService:Create(Blackbars, TweenInfo.new(timer, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 15) }):Play()
			task.wait(timer)
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

--[[ 
	Staggered Fade-In Animation Helper
	Use this for populating scrolling frames with subtle cascade animations.
	
	@param element - The GuiObject to animate
	@param index - The element's position in the list (1-based)
	@param options - Optional table with:
		- staggerDelay: number (default 0.03) - delay between items
		- fadeTime: number (default 0.15) - duration of fade-in
		- includeChildren: boolean (default true) - animate child elements too
]]
function UIFunctions:AnimateListItem(element: GuiObject, index: number, options: any?)
	if not element or not element:IsA("GuiObject") then return end
	
	local opts = options or {}
	local staggerDelay = opts.staggerDelay or 0.03
	local fadeTime = opts.fadeTime or 0.15
	local includeChildren = opts.includeChildren ~= false
	
	-- Start transparent
	element.BackgroundTransparency = 1
	
	-- Make text and images transparent if including children
	if includeChildren then
		for _, child in ipairs(element:GetDescendants()) do
			if child:IsA("TextLabel") or child:IsA("TextButton") then
				child.TextTransparency = 1
			elseif child:IsA("ImageLabel") or child:IsA("ImageButton") then
				child.ImageTransparency = 1
			end
		end
	end
	
	-- Staggered animation
	task.delay(index * staggerDelay, function()
		if not element or not element.Parent then return end
		
		-- Fade in background
		TweenService:Create(element, TweenInfo.new(fadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 0
		}):Play()
		
		if includeChildren then
			for _, child in ipairs(element:GetDescendants()) do
				if child:IsA("TextLabel") or child:IsA("TextButton") then
					TweenService:Create(child, TweenInfo.new(fadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						TextTransparency = 0
					}):Play()
				elseif child:IsA("ImageLabel") or child:IsA("ImageButton") then
					TweenService:Create(child, TweenInfo.new(fadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						ImageTransparency = 0
					}):Play()
				end
			end
		end
	end)
end

--[[
	Pulse Animation for selection feedback
	Creates a subtle scale pulse effect on an element
	
	@param element - The GuiObject to pulse
	@param options - Optional table with:
		- scale: number (default 1.03) - how much to scale up
		- duration: number (default 0.2) - total pulse duration
]]
function UIFunctions:PulseElement(element: GuiObject, options: any?)
	if not element or not element:IsA("GuiObject") then return end
	if element:GetAttribute("IsPulsing") then return end
	
	element:SetAttribute("IsPulsing", true)
	
	local opts = options or {}
	local scale = opts.scale or 1.03
	local duration = opts.duration or 0.2
	
	local originalSize = element:GetAttribute("OriginalPulseSize") or element.Size
	element:SetAttribute("OriginalPulseSize", originalSize)
	
	local scaledSize = UDim2.new(
		originalSize.X.Scale * scale, originalSize.X.Offset,
		originalSize.Y.Scale * scale, originalSize.Y.Offset
	)
	
	local upTime = duration * 0.4
	local downTime = duration * 0.6
	
	local pulseUp = TweenService:Create(element, TweenInfo.new(upTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = scaledSize
	})
	local pulseDown = TweenService:Create(element, TweenInfo.new(downTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = originalSize
	})
	
	pulseUp:Play()
	pulseUp.Completed:Connect(function()
		pulseDown:Play()
		pulseDown.Completed:Connect(function()
			element:SetAttribute("IsPulsing", false)
		end)
	end)
end

return UIFunctions

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Say = {}
local NPCAnimations = require(script.Parent:WaitForChild("NPCAnimations"))

local Player = game.Players.LocalPlayer
local function getCharacterHRP()
	local character = Player.Character or Player.CharacterAdded:Wait()
	return character:WaitForChild("HumanoidRootPart")
end

-- Robust function to get a valid part from an instance for positioning
local function getModelPart(target: Instance): BasePart?
    if not target then
        return nil
    end

    -- If a BasePart is provided directly, use it
    if target:IsA("BasePart") then
        return target
    end
    
    -- If a Humanoid is provided, use its parent model
    if target:IsA("Humanoid") and target.Parent and target.Parent:IsA("Model") then
        target = target.Parent
    end
    
    -- If child instance, try to resolve to parent model
    if not target:IsA("Model") and target.Parent and target.Parent:IsA("Model") then
        target = target.Parent
    end
    
    if not target:IsA("Model") then
        return nil
    end
    local model = target :: Model
    
	-- Try 1: PrimaryPart
    if model.PrimaryPart then
        return model.PrimaryPart
    end
    
    -- Try 2: HumanoidRootPart
	local hrp = model:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") then
        return hrp
    end
    
    -- Try 3: Head
	local head = model:FindFirstChild("Head")
    if head and head:IsA("BasePart") then
        return head
    end
    
    -- Try 4: First BasePart in model
    for _, child in ipairs(model:GetDescendants()) do
        if child:IsA("BasePart") then
            return child
        end
    end
    return nil
end

local Audio = script.Parent.Parent:WaitForChild("Assets"):WaitForChild("Audio")

local CharacterFunctions = require(script.Parent:WaitForChild("CharacterFunctions"))
-- Lazy UI accessor to avoid startup circular waits
local function getUI()
	local ok, ui = pcall(function()
		return require(script.Parent.Parent:WaitForChild("UI"))
	end)
	if ok then return ui end
	return nil
end
local UIFunctions = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("UIFunctions"))
local ClientData = require(script.Parent.Parent:WaitForChild("Plugins"):WaitForChild("ClientData"))
local CutsceneRegistry = require(script.Parent:WaitForChild("CutsceneRegistry"))

local TweenService = game:GetService("TweenService")
local Sounds = game.ReplicatedStorage:WaitForChild("Audio"):WaitForChild("SFX")
local NPCAnimations = require(script.Parent:WaitForChild("NPCAnimations"))

-- Arrow UI manager (points from Say UI to the world talker)
type ArrowState = {
	root: ImageLabel?,
	head: ImageLabel?,
	updateConn: RBXScriptConnection?,
	target: BasePart?,
	anchorGetter: (() -> Vector2)?,
	anchorFixed: Vector2?,
}

local Arrow: ArrowState = { root = nil, head = nil, updateConn = nil, target = nil, anchorGetter = nil, anchorFixed = nil }

local function ensureArrowUi(parentGui: Instance)
    -- Parent the arrow under Say's parent (GameUI), not under Say itself
    local container: Instance = parentGui.Parent or parentGui
    -- Reuse existing arrow in GameUI if present
    local existing = container:FindFirstChild("SayArrowLine")
    if existing and existing:IsA("ImageLabel") then
        Arrow.root = existing
        return
    end
    -- If we already created one earlier, ensure it's reparented to GameUI
    if Arrow.root and Arrow.root.Parent then
        if Arrow.root.Parent ~= container then
            Arrow.root.Parent = container
        end
        return
    end
    -- Create one if not found
    local line = Instance.new("ImageLabel")
    line.Name = "SayArrowLine"
    line.BackgroundTransparency = 1
    line.Image = "rbxassetid://86390524642807"
    line.ImageColor3 = Color3.fromRGB(202, 202, 202)
    line.ScaleType = Enum.ScaleType.Slice
    line.SliceCenter = Rect.new(2, 2, 2, 2)
    line.ZIndex = 1000
    line.Visible = false
    line.Parent = container

    Arrow.root = line
end

local function hideArrow()
	if Arrow.updateConn then Arrow.updateConn:Disconnect() Arrow.updateConn = nil end
	if Arrow.root then Arrow.root.Visible = false end
	Arrow.target = nil
	Arrow.anchorGetter = nil
	Arrow.anchorFixed = nil
end

local function startArrow(target: BasePart, anchorGetter: () -> Vector2, parentGui: Instance)
	ensureArrowUi(parentGui)
	Arrow.target = target
	Arrow.anchorGetter = anchorGetter
	Arrow.anchorFixed = anchorGetter()

    local cam = workspace.CurrentCamera
	if Arrow.updateConn then Arrow.updateConn:Disconnect() end
    -- Use a single solid bar only; no head
    Arrow.root.Image = "rbxassetid://86390524642807"
    Arrow.root.ScaleType = Enum.ScaleType.Slice
    Arrow.root.SliceCenter = Rect.new(2, 2, 2, 2)

    Arrow.updateConn = RunService.RenderStepped:Connect(function(dt)
        if not Arrow.root or not Arrow.target or not Arrow.anchorGetter then return end
        local anchor = Arrow.anchorFixed or Arrow.anchorGetter()
        local tv, onScreen = cam:WorldToViewportPoint(Arrow.target.Position)
		if not onScreen then
			Arrow.root.Visible = false
			return
		end
        local tip = Vector2.new(tv.X, tv.Y)
        local from = anchor
        local to = tip
        local delta = to - from
        local dist = delta.Magnitude
		if dist < 6 then
			Arrow.root.Visible = false
			return
		end
        local offset = delta
        local dist = offset.Magnitude
        local angleDeg = math.deg(math.atan2(offset.Y, offset.X))

        Arrow.root.Visible = true
    
        local container = (Arrow.root and Arrow.root.Parent) and Arrow.root.Parent or parentGui
        local baseH = (container and (container :: any).AbsoluteSize and (container :: any).AbsoluteSize.Y) or 400
        local shaftWidth = math.clamp(math.floor(baseH * 0.12), 10, 30)
        Arrow.root.Size = UDim2.fromOffset(shaftWidth, dist)
        Arrow.root.Rotation = angleDeg - 90
 
        local mid = from + offset*0.5
        Arrow.root.Position = UDim2.fromOffset(mid.X - Arrow.root.AbsoluteSize.X/2, mid.Y - Arrow.root.AbsoluteSize.Y/2)
        Arrow.root.ImageTransparency = 0
	end)
end

local function getSayUI()
	local pg = Player:WaitForChild("PlayerGui")
	local gameUi = pg:WaitForChild("GameUI")
	return gameUi:WaitForChild("Say")
end
local Saying = false --are we saying anything?
local CanProceed = false--can we click to go to the next thing?
local Proceeded = false
local AllowProceed = true
local WasAbleToMove
local HadTopBarOpen = nil

-- Extended Say supports optional emotion tags per line.
-- tbl may contain strings or { Text = string, Emotion = string } tables.
function Say:Say(talkerstr,allowproceed,tbl,talker,hearer)
	if Saying == true then return end
	local SayUI = getSayUI()
	repeat task.wait() until SayUI:FindFirstChild("Talker")
	Saying = true
	AllowProceed = allowproceed
	
	--[[
	if _G.OverrideTopBar == false then
		_G.Plugins.TopBar:Hide()
	end
	]]
	
	WasAbleToMove = CharacterFunctions:CheckCanMove()

	--If we have the topbar showing
	local UI = getUI()
	if UI and UI.TopBar then
		HadTopBarOpen = UI.TopBar:GetState()
	else
		HadTopBarOpen = false
	end
	
	-- Safety fix: Force close any open TopBar menus if NPC interaction somehow happens
	if UI and UI.TopBar and UI.TopBar.IsMenuOpen and UI.TopBar:IsMenuOpen() then
		UI.TopBar:Hide() -- Force close any open menus
		HadTopBarOpen = false -- Don't try to restore TopBar since we forced it closed
	end
	
	if HadTopBarOpen == true and UI and UI.TopBar then
		UI.TopBar:Hide() -- if the topbar is active/open, hide it while talking
	end
	
	CharacterFunctions:CanMove(false)

	-- If provided text list is blank (only empty/whitespace strings), do not show UI; just wait for proceed input
	local function isBlankList(list)
		if type(list) ~= "table" then return false end
		local sawAny = false
		for _, v in ipairs(list) do
			if type(v) ~= "string" then return false end
			sawAny = true
			if v:match("%S") then
				return false
			end
		end
		return sawAny
	end

	if isBlankList(tbl) then
		-- Hide Say UI and simply wait for a proceed action
		SayUI.Visible = false
		Proceeded = false
		CanProceed = true
		if AllowProceed == true then
			repeat task.wait() until Proceeded == true
			CanProceed = false
			-- Cleanup like end-of-say
			Saying = false
			if WasAbleToMove == true then
				CharacterFunctions:CanMove(true)
			end
		end
		return
	end
	
	if talker then
		-- Debug: Check what we're actually getting
		local talkerName = (typeof(talker) == "Instance" and talker.Name) or ""
		
		-- Use robust fallback to get a valid part (PrimaryPart -> HRP -> Head -> First BasePart)
		local Model1 = getModelPart(talker)
		
		if not Model1 then
			warn("[Say] Talker model has no valid parts:", talkerName)
		else
			if hearer then
				local Model2 = getModelPart(hearer)
				
				if not Model2 then
					warn("[Say] Hearer model has no valid parts:", hearer:GetFullName())
				else
					-- talker looks at hearer
					local dir1 = (Model2.Position - Model1.Position).Unit
					local look1 = CFrame.new(Model1.Position, Model1.Position + Vector3.new(dir1.X, 0, dir1.Z))
					TweenService:Create(Model1, TweenInfo.new(0.5), {CFrame = look1}):Play()

					-- hearer looks at talker
					local dir2 = (Model1.Position - Model2.Position).Unit
					local look2 = CFrame.new(Model2.Position, Model2.Position + Vector3.new(dir2.X, 0, dir2.Z))
					TweenService:Create(Model2, TweenInfo.new(0.5), {CFrame = look2}):Play()

					-- player looks at talker
					local success, HRP = pcall(getCharacterHRP)
					if success and HRP then
						local dir3 = (Model1.Position - HRP.Position).Unit
						local look3 = CFrame.new(HRP.Position, HRP.Position + Vector3.new(dir3.X, 0, dir3.Z))
						TweenService:Create(HRP, TweenInfo.new(0.5), {CFrame = look3}):Play()
					end
				end
			else
				-- talker and player look at each other
				local success, HRP = pcall(getCharacterHRP)
				if success and HRP then
					local dir1 = (HRP.Position - Model1.Position).Unit
					local look1 = CFrame.new(Model1.Position, Model1.Position + Vector3.new(dir1.X, 0, dir1.Z))
					TweenService:Create(Model1, TweenInfo.new(0.5), {CFrame = look1}):Play()

					local dir2 = (Model1.Position - HRP.Position).Unit
					local look2 = CFrame.new(HRP.Position, HRP.Position + Vector3.new(dir2.X, 0, dir2.Z))
					TweenService:Create(HRP, TweenInfo.new(0.5), {CFrame = look2}):Play()
				end
			end
		end
	end


	
	SayUI.Visible = true
	SayUI:WaitForChild("Talker").Text = talkerstr
	-- Adjust SayText position depending on whether there is a Talker label
	if talkerstr == "" then
		SayUI.SayText.Position = UDim2.new(0.483, 0, 0.493, 0)
	else
		SayUI.SayText.Position = UDim2.new(0.483, 0, 0.643, 0)
	end
		for i,v in pairs(tbl) do
		local textStr: string
			local emotion: string?
			local emotionsMap: any
		if type(v) == "table" then
			textStr = tostring(v.Text or "")
				emotion = (type(v.Emotion) == "string" and v.Emotion) or nil
				emotionsMap = (type(v.Emotions) == "table" and v.Emotions) or nil
		else
			textStr = tostring(v)
			emotion = nil
		end
			-- Apply NPC emotion animations for multiple actors per line when provided
			local function resolveModelFromInstance(inst: Instance?): Model?
				if not inst then return nil end
				if inst:IsA("Model") then return inst end
				if inst.Parent and inst.Parent:IsA("Model") then return inst.Parent end
				return nil
			end
			local function playEmotionFor(model: Model?, em: string?)
				if model and type(em) == "string" and em ~= "" then
					NPCAnimations:PlayEmotionLoop(model, em)
				end
			end
			-- Backwards-compatible: if a single Emotion string is provided, apply to talker
			if emotion and talker and typeof(talker) == "Instance" then
				playEmotionFor(resolveModelFromInstance(talker), emotion)
			end
			-- Extended: support per-actor emotions via Emotions table and/or explicit HearerEmotion
			local hearerEmotion = nil
			if type(v) == "table" then
				if type(v.HearerEmotion) == "string" then
					hearerEmotion = v.HearerEmotion
				elseif emotionsMap and type(emotionsMap.Hearer) == "string" then
					hearerEmotion = emotionsMap.Hearer
				end
				if emotionsMap and type(emotionsMap.Talker) == "string" and talker then
					playEmotionFor(resolveModelFromInstance(talker), emotionsMap.Talker)
				end
			end
			if hearer and typeof(hearer) == "Instance" and type(hearerEmotion) == "string" then
				playEmotionFor(resolveModelFromInstance(hearer), hearerEmotion)
			end
		SayUI.SayText.Text = textStr
		Proceeded = false

		-- Start/update arrow pointing to talker for this line
		do
			local targetPart: BasePart? = nil
			if typeof(talker) == "Instance" then
				if talker:IsA("Model") then
					local head = talker:FindFirstChild("Head")
					if head and head:IsA("BasePart") then
						targetPart = head
					else
						targetPart = getModelPart(talker)
					end
				else
					targetPart = getModelPart(talker)
				end
			end
			if targetPart then
                local function anchorGetter(): Vector2
                    -- Prefer anchoring to the bottom-middle of the visible SayText content,
                    -- shifted left by ~1/7 of the screen width as requested.
                    local cam = workspace.CurrentCamera
                    local screenW = (cam and cam.ViewportSize.X) or SayUI.AbsoluteSize.X
                    local sayText: TextLabel? = SayUI:FindFirstChild("SayText") :: TextLabel?
                    if sayText then
                        local tpos = sayText.AbsolutePosition
                        local tsz = sayText.AbsoluteSize
                        local textH = (sayText.TextBounds and sayText.TextBounds.Y) or tsz.Y
                        local y = math.min(tsz.Y, textH)
                        local centerX = tpos.X + tsz.X * 0.5
                        return Vector2.new(centerX , tpos.Y + y)
                    end
                    -- Fallback: bottom-middle of full Say UI
                    local pos = SayUI.AbsolutePosition
                    local size = SayUI.AbsoluteSize
                    local centerX = pos.X + size.X * 0.5
                    return Vector2.new(centerX , pos.Y + size.Y * 0.99)
                end
				startArrow(targetPart, anchorGetter, SayUI)
			else
				hideArrow()
			end
		end
		
		-- Get FastText setting (guard against nil data during title/new game flows)
		local fastTextEnabled = false
		pcall(function()
			local pd = ClientData:Get()
			if type(pd) == "table" and type(pd.Settings) == "table" and type(pd.Settings.FastText) == "boolean" then
				fastTextEnabled = pd.Settings.FastText
			end
		end)
		local textSpeed = fastTextEnabled and 0.02 / 1.5 or 0.02 -- 1.5x faster when enabled
		
		local Length = #textStr
		for count = 1,Length do
			SayUI.SayText.MaxVisibleGraphemes = count
			task.wait(textSpeed)
		end
		
		CanProceed = true
		
		if AllowProceed == true then
			SayUI.Proceed.Visible = true
			
			repeat
				task.wait()
			until Proceeded == true
			
			SayUI.Proceed.Visible = false
			Sounds.Next:Play()
		end

	end
	
		if AllowProceed == true then
		SayUI.Visible = false
		Saying = false
		if WasAbleToMove == true then
			CharacterFunctions:CanMove(true)
		end
		hideArrow()
			-- Stop emotion animations for involved actors when dialogue ends (unless flagged custom)
			local function resolveModelFromInstance(inst: Instance?): Model?
				if not inst then return nil end
				if inst:IsA("Model") then return inst end
				if inst.Parent and inst.Parent:IsA("Model") then return inst.Parent end
				return nil
			end
			local function maybeStop(model: Model?)
				if model and model:GetAttribute("HasCustomDialogueAnim") ~= true then
					NPCAnimations:StopEmotion(model)
				end
			end
			maybeStop(resolveModelFromInstance(talker))
			maybeStop(resolveModelFromInstance(hearer))
		-- Do not auto-show TopBar here; the caller/cutscene controls it
			--[[
	if _G.OverrideTopBar == false then
		_G.Plugins.TopBar:Show()
	end
	]]
	end

end

function Say:Proceed()
	if Saying == false then return end
	CanProceed = false
	Proceeded = true
end

function Say:Exit()
	if Saying == false then return end
	Proceeded = true
	local SayUI = getSayUI()
	SayUI.Visible = false
	Saying = false
	hideArrow()
	if WasAbleToMove == true then
		CharacterFunctions:CanMove(true)
	end
	-- Do not auto-show TopBar here; the caller/cutscene controls it
	--[[
	if _G.OverrideTopBar == false then
		_G.Plugins.TopBar:Show()
	end
	]]
end


-- Returns true while dialogue is actively showing or waiting for proceed
function Say:IsActive()
    return Saying == true
end

function Say:IsAnyCutsceneActive()
    return CutsceneRegistry:IsAnyActive()
end

function Say:YieldChoice()

	local SayUI = getSayUI()
	-- Ensure choice buttons are visible and interactive
	local YesBtn = SayUI.Choice:FindFirstChild("Yes")
	local NoBtn = SayUI.Choice:FindFirstChild("No")
	if YesBtn then YesBtn.Visible = true YesBtn.Active = true end
	if NoBtn then NoBtn.Visible = true NoBtn.Active = true end
	SayUI.Choice.Visible = true
	local Chose = nil
	UIFunctions:NewButton(SayUI.Choice.Yes, {"Action"}, {Click = "One", HoverOn = "One", HoverOff = "One"}, 0.25, function()
		Audio.SFX.Click:Play()
		Chose = true
	end)
	UIFunctions:NewButton(SayUI.Choice.No, {"Action"}, {Click = "One", HoverOn = "One", HoverOff = "One"}, 0.25, function()
		Audio.SFX.Click:Play()
		Chose = false
	end)

	repeat task.wait() until Chose ~= nil

	UIFunctions:ClearConnection(SayUI.Choice.Yes)
	UIFunctions:ClearConnection(SayUI.Choice.No)
	SayUI.Choice.Visible = false

	return Chose
end

UserInputService.InputBegan:connect(function(inputObject)
	if inputObject.KeyCode == Enum.KeyCode.ButtonA or inputObject.KeyCode == Enum.KeyCode.ButtonX or ((inputObject.UserInputType == Enum.UserInputType.MouseButton1 or inputObject.UserInputType == Enum.UserInputType.Touch) and inputObject.UserInputState == Enum.UserInputState.Begin) then
		if Saying == true and CanProceed == true and AllowProceed == true then
			Say:Proceed()
		end
	end
end)

return Say

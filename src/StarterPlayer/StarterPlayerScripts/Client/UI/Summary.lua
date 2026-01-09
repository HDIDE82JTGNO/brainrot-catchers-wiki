local Summary = {}

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local TypesModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local MovesModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Moves"))
local Creatures = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Creatures"))
local CreatureViewer = require(script.Parent:WaitForChild("CreatureViewer"))
local StatCalc = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StatCalc"))
local UIFunctions = require(script.Parent:WaitForChild("UIFunctions"))
local Audio = script.Parent.Parent:WaitForChild("Assets"):WaitForChild("Audio")

local MOVE_ANIMATION_TIME = 0.2
local STAT_ANIMATION_TIME = 0.5
local COLOR_ANIMATION_TIME = 0.3
local TWEEN_STYLE = Enum.EasingStyle.Quart
local TWEEN_DIRECTION = Enum.EasingDirection.Out

local MoveHoverConnections = setmetatable({}, { __mode = "k" })

-- Module state
local _summaryFrame: Frame? = nil
local _navigationCallbacks = {
	onNext = nil,
	onPrevious = nil,
	onClose = nil,
}
local _buttonsConnected = false

local function DarkenColor3(c: Color3, factor: number)
	local f = math.clamp(factor or 1, 0, 1)
	return Color3.new(c.R * f, c.G * f, c.B * f)
end

local function setTypeFrame(frame: Frame?, typeName: string?)
	if not frame or not typeName then return end
	local typeText = frame:FindFirstChild("TypeText")
	if TypesModule[typeName] then
		local c = TypesModule[typeName].uicolor
		frame.BackgroundColor3 = c
		local darker = DarkenColor3(c, 0.6)
		local stroke = frame:FindFirstChild("UIStroke")
		if stroke then stroke.Color = darker end
		if typeText and typeText:IsA("TextLabel") then
			local txtStroke = typeText:FindFirstChild("UIStroke")
			if txtStroke then txtStroke.Color = darker end
		end
	end
	if typeText and typeText:IsA("TextLabel") then
		typeText.Text = typeName or "Unknown"
	end
end

local function setup3DPreview(SummaryFrame: Frame, creatureData: any)
	local container = SummaryFrame:FindFirstChild("3DPreview")
	if not container or not container:IsA("GuiObject") then return end

	CreatureViewer:Load(container, {
		Name = creatureData.Name,
		BaseName = creatureData.BaseName or creatureData.Name,
		Shiny = creatureData.Shiny,
	})
end

local function SetIVFrame(SummaryFrame: Frame, frameName: string, value: number?, baseColor: Color3)
	local frame = SummaryFrame:FindFirstChild(frameName)
	if not frame then return end
	local iv = typeof(value) == "number" and math.clamp(value, 0, 31) or 0
	local StatLabel = frame:FindFirstChild("Stat")
	if StatLabel and StatLabel:IsA("TextLabel") then
		StatLabel.Text = tostring(iv)
	end
	local ratio = iv / 31
	local shade = 0.35 + (0.65 * ratio)
	local color = DarkenColor3(baseColor, shade)
	frame.BackgroundColor3 = color
	local stroke = frame:FindFirstChild("UIStroke")
	if stroke then
		local darker = DarkenColor3(color, 0.6)
		stroke.Color = darker
	end
end

local function fillMoves(SummaryFrame: Frame, creatureData: any)
	local MoveInfo = SummaryFrame:FindFirstChild("MoveInfo")
	local uis = game:GetService("UserInputService")
	if MoveInfo and not MoveInfo:GetAttribute("HoverFollowConnected") then
		MoveInfo.Visible = false
		MoveInfo:SetAttribute("HoverFollowConnected", true)
		uis.InputChanged:Connect(function(input)
			if MoveInfo.Visible and input.UserInputType == Enum.UserInputType.MouseMovement then
				local pos = input.Position
				local padX, padY = 220, 145
				local parent: any = MoveInfo.Parent
				local parentSize = parent and parent.AbsoluteSize or Vector2.new(1920, 1080)
				local px = math.max(1, parentSize.X)
				local py = math.max(1, parentSize.Y)
				local xScale = math.clamp((pos.X - padX) / px, 0, 1)
				local yScale = math.clamp((pos.Y - padY) / py, 0, 1)
				MoveInfo.Position = UDim2.new(xScale, 0, yScale, 0)
			end
		end)
	end
	if MoveInfo then MoveInfo.Visible = false end

	if MoveHoverConnections[SummaryFrame] and MoveHoverConnections[SummaryFrame].PerMove then
		for _, c in ipairs(MoveHoverConnections[SummaryFrame].PerMove) do
			if c and c.Connected then c:Disconnect() end
		end
		MoveHoverConnections[SummaryFrame].PerMove = {}
	end
	-- Clear old hover flags and attributes to avoid stale data
	for i = 1, 4 do
		local mf = SummaryFrame:FindFirstChild("Move" .. i)
		if mf then
			mf:SetAttribute("HoverBound", nil)
			mf:SetAttribute("MoveName", nil)
			mf:SetAttribute("MovePower", nil)
			mf:SetAttribute("MoveDescription", nil)
			mf:SetAttribute("TypeColorR", nil)
			mf:SetAttribute("TypeColorG", nil)
			mf:SetAttribute("TypeColorB", nil)
		end
	end
	for i = 1, 4 do
		local MoveFrame = SummaryFrame:FindFirstChild("Move" .. i)
		if MoveFrame then
			local MoveName = MoveFrame:FindFirstChild("MoveName")
			local MoveStat = MoveFrame:FindFirstChild("Stat")
			local entry = creatureData.CurrentMoves and creatureData.CurrentMoves[i]
			local resolvedName: string? = nil
			local moveDef: any = nil
			if typeof(entry) == "string" then
				resolvedName = entry
				moveDef = MovesModule[resolvedName]
			elseif typeof(entry) == "table" then
				for k, v in pairs(MovesModule) do
					if v == entry then
						resolvedName = k
						moveDef = v
						break
					end
				end
			end
			if resolvedName and moveDef and MoveName and MoveName:IsA("TextLabel") and MoveStat and MoveStat:IsA("TextLabel") then
				MoveName.Text = resolvedName
				MoveStat.Text = "Power: " .. tostring(moveDef.BasePower)
				local typeColor = moveDef.Type and moveDef.Type.uicolor or Color3.new(0.5, 0.5, 0.5)
				MoveFrame.BackgroundTransparency = 1
				MoveFrame.Visible = true
				TweenService:Create(MoveFrame, TweenInfo.new(MOVE_ANIMATION_TIME, TWEEN_STYLE, TWEEN_DIRECTION), { BackgroundTransparency = 0 }):Play()
				TweenService:Create(MoveFrame, TweenInfo.new(COLOR_ANIMATION_TIME, TWEEN_STYLE, TWEEN_DIRECTION), { BackgroundColor3 = typeColor }):Play()
				local stroke = MoveFrame:FindFirstChild("UIStroke")
				if stroke then
					local darker = DarkenColor3(typeColor, 0.6)
					TweenService:Create(stroke, TweenInfo.new(COLOR_ANIMATION_TIME, TWEEN_STYLE, TWEEN_DIRECTION), { Color = darker }):Play()
				end
				if MoveInfo then
					MoveFrame:SetAttribute("MoveName", resolvedName)
					MoveFrame:SetAttribute("MovePower", moveDef.BasePower or 0)
					MoveFrame:SetAttribute("MoveDescription", tostring(moveDef.Description or ""))
					MoveFrame:SetAttribute("TypeColorR", typeColor.R)
					MoveFrame:SetAttribute("TypeColorG", typeColor.G)
					MoveFrame:SetAttribute("TypeColorB", typeColor.B)
					local function show()
						MoveInfo.Visible = true
						local r = MoveFrame:GetAttribute("TypeColorR") or typeColor.R
						local g = MoveFrame:GetAttribute("TypeColorG") or typeColor.G
						local b = MoveFrame:GetAttribute("TypeColorB") or typeColor.B
						local currentTypeColor = Color3.new(r, g, b)
						MoveInfo.BackgroundColor3 = currentTypeColor
						local infoStroke = MoveInfo:FindFirstChild("UIStroke")
						if infoStroke then infoStroke.Color = DarkenColor3(currentTypeColor, 0.6) end
						local nameLabel = MoveInfo:FindFirstChild("MoveName")
						local statLabel = MoveInfo:FindFirstChild("Stat")
						local descLabel = MoveInfo:FindFirstChild("Description")
						local n = MoveFrame:GetAttribute("MoveName") or resolvedName
						local p = MoveFrame:GetAttribute("MovePower") or moveDef.BasePower
						local d = MoveFrame:GetAttribute("MoveDescription") or (moveDef.Description or "")
						if nameLabel and nameLabel:IsA("TextLabel") then nameLabel.Text = tostring(n) end
						if statLabel and statLabel:IsA("TextLabel") then statLabel.Text = "Power: " .. tostring(p) end
						if descLabel and descLabel:IsA("TextLabel") then descLabel.Text = tostring(d) end
						for _, obj in ipairs(MoveInfo:GetDescendants()) do
							if obj:IsA("UIStroke") and obj.Parent and obj.Parent:IsA("TextLabel") then
								obj.Color = DarkenColor3(currentTypeColor, 0.6)
							end
						end
					end
					local function hide()
						MoveInfo.Visible = false
					end
					MoveHoverConnections[SummaryFrame] = MoveHoverConnections[SummaryFrame] or { PerMove = {} }
					local c1 = MoveFrame.MouseEnter:Connect(show)
					local c2 = MoveFrame.MouseLeave:Connect(hide)
					table.insert(MoveHoverConnections[SummaryFrame].PerMove, c1)
					table.insert(MoveHoverConnections[SummaryFrame].PerMove, c2)
					MoveFrame:SetAttribute("HoverBound", true)
				end
			else
				MoveFrame.Visible = false
				MoveFrame:SetAttribute("HoverBound", nil)
				MoveFrame:SetAttribute("MoveName", nil)
				MoveFrame:SetAttribute("MovePower", nil)
				MoveFrame:SetAttribute("MoveDescription", nil)
				MoveFrame:SetAttribute("TypeColorR", nil)
				MoveFrame:SetAttribute("TypeColorG", nil)
				MoveFrame:SetAttribute("TypeColorB", nil)
			end
		end
	end
end

function Summary:Render(SummaryFrame: Frame, creatureData: any)
	if not SummaryFrame or not creatureData then return end

	-- Basic text fields
	local displayName = creatureData.Nickname or creatureData.Name or "---"
	local CreatureName = SummaryFrame:FindFirstChild("CreatureName")
	if CreatureName and CreatureName:IsA("TextLabel") then
		CreatureName.Text = displayName
	end
	local Level = SummaryFrame:FindFirstChild("Level")
	if Level and Level:IsA("TextLabel") then
		Level.Text = "Lv." .. tostring(creatureData.Level or "--")
	end
	local NatureFrame = SummaryFrame:FindFirstChild("Nature")
	local NatureText = NatureFrame and NatureFrame:FindFirstChild("NatureText")
	if NatureText and NatureText:IsA("TextLabel") then
		NatureText.Text = tostring(creatureData.Nature or "Unknown")
	end

	-- Types
	local typesList = {}
	local baseTypes = creatureData.BaseType or (Creatures[creatureData.Name] and Creatures[creatureData.Name].Type)
	if typeof(baseTypes) == "table" then
		for i, t in ipairs(baseTypes) do typesList[i] = typeof(t) == "string" and t or nil end
	elseif typeof(baseTypes) == "string" then
		typesList[1] = baseTypes
	end
	local FirstType = SummaryFrame:FindFirstChild("FirstType")
	local SecondType = SummaryFrame:FindFirstChild("SecondType")
	if FirstType or SecondType then
		setTypeFrame(FirstType, typesList[1])
		if SecondType then
			if typesList[2] then
				SecondType.Visible = true
				setTypeFrame(SecondType, typesList[2])
			else
				SecondType.Visible = false
			end
		end
	else
		local TypeFrame = SummaryFrame:FindFirstChild("Type")
		if TypeFrame and TypeFrame:IsA("Frame") then
			setTypeFrame(TypeFrame, typesList[1])
		end
	end

	-- Weight and size
	local SizeFrame = SummaryFrame:FindFirstChild("SizeFrame")
	if SizeFrame and SizeFrame:IsA("Frame") then
		local SizeClassObj = SizeFrame:FindFirstChild("SizeClass")
		local ActualWeightLabel = SizeFrame:FindFirstChild("ActualWeight", true)
		local baseData = Creatures[creatureData.Name]
		local baseWeight = baseData and baseData.BaseWeightKg or nil
		local weight = creatureData.WeightKg or baseWeight
		local function getClass(actual:number?, base:number?): string
			if type(actual) ~= "number" or type(base) ~= "number" or base <= 0 then return "?" end
			local delta = (actual - base) / base
			if delta <= -0.3 then return "XS" end
			if delta <= -0.1 then return "S" end
			if delta < 0.1 then return "M" end
			if delta < 0.3 then return "L" end
			return "XL"
		end
		local class = getClass(weight, baseWeight)
		if SizeClassObj and SizeClassObj:IsA("TextLabel") then
			SizeClassObj.Text = class
		end
		if ActualWeightLabel and ActualWeightLabel:IsA("TextLabel") then
			if type(weight) == "number" then
				ActualWeightLabel.Text = tostring(weight) .. "KG"
			else
				ActualWeightLabel.Text = "--"
			end
		end
	end

	-- Gender, shiny, tradelocked in AdditionalInfo
	local AdditionalInfo = SummaryFrame:FindFirstChild("AdditionalInfo")
	if AdditionalInfo then
		local GenderIcon = AdditionalInfo:FindFirstChild("GenderIcon")
		if GenderIcon and GenderIcon:IsA("ImageLabel") then
			if creatureData.Gender == 0 then
				GenderIcon.ImageRectOffset = Vector2.new(510, 75)
			else
				GenderIcon.ImageRectOffset = Vector2.new(0, 75)
			end
		end
		local Shiny = AdditionalInfo:FindFirstChild("Shiny")
		if Shiny and Shiny:IsA("GuiObject") then Shiny.Visible = creatureData.Shiny == true end
		local TradeLockedBadge = AdditionalInfo:FindFirstChild("TradeLocked")
		if TradeLockedBadge and TradeLockedBadge:IsA("ImageLabel") then
			TradeLockedBadge.Visible = creatureData.TradeLocked == true
		end
	end

	-- OT label
	local OTLabel = SummaryFrame:FindFirstChild("OT")
	if OTLabel and OTLabel:IsA("TextLabel") then
		local userId = creatureData.OT
		if typeof(userId) == "number" and userId > 0 then
			local success, nameOrErr = pcall(function()
				return Players:GetNameFromUserIdAsync(userId)
			end)
			if success and typeof(nameOrErr) == "string" then
				OTLabel.Text = "OT: " .. nameOrErr
			else
				OTLabel.Text = "OT: Unknown"
			end
		else
			OTLabel.Text = "OT: Unknown"
		end
	end

	-- HP and stats
	local HP = SummaryFrame:FindFirstChild("HP")
	local HPMax = HP and HP:FindFirstChild("Max")
	local HPCurrent = HP and HP:FindFirstChild("Current")
	local CreatureHP = SummaryFrame:FindFirstChild("CreatureHP")
	local percent = creatureData.CurrentHP
	if percent == nil then percent = 100 end
	percent = math.clamp(percent, 0, 100)
	local _, maxStatsFallback = StatCalc.ComputeStats(creatureData.Name, creatureData.Level, creatureData.IVs, creatureData.Nature)
	local maxHP = (creatureData.MaxStats and creatureData.MaxStats.HP)
		or (maxStatsFallback and maxStatsFallback.HP)
		or (creatureData.Stats and creatureData.Stats.HP)
		or 1
	local currentScalar = math.floor(maxHP * (percent / 100) + 0.5)
	if HPMax and HPMax:IsA("TextLabel") then
		HPMax.Text = tostring(maxHP)
	end
	if CreatureHP and CreatureHP:IsA("TextLabel") then
		CreatureHP.Text = "HP: " .. tostring(currentScalar) .. "/" .. tostring(maxHP)
	end
	if HPCurrent and HPCurrent:IsA("Frame") then
		local hpPercent = math.clamp(currentScalar / math.max(1, maxHP), 0, 1)
		local fullXScale = 0.456
		local fullYScale = 0.049
		HPCurrent.Size = UDim2.new(fullXScale * hpPercent, 0, fullYScale, 0)
	end

	-- Compute stats for display
	local stats, maxStats = StatCalc.ComputeStats(creatureData.Name, creatureData.Level, creatureData.IVs, creatureData.Nature)
	local displayStats = creatureData.MaxStats or maxStats or maxStatsFallback or {}

	local Attack = SummaryFrame:FindFirstChild("Attack")
	local AttackStat = Attack and Attack:FindFirstChild("Stat")
	local AttackCurrent = Attack and Attack:FindFirstChild("Current")
	if AttackStat and AttackStat:IsA("TextLabel") then
		AttackStat.Text = tostring(displayStats.Attack or 0)
	end
	if AttackCurrent then
		AttackCurrent.Size = UDim2.new(0, 0, 1, 0)
		TweenService:Create(AttackCurrent, TweenInfo.new(STAT_ANIMATION_TIME, TWEEN_STYLE, TWEEN_DIRECTION), { Size = UDim2.new(1, 0, 1, 0) }):Play()
	end
	local Defense = SummaryFrame:FindFirstChild("Defense")
	local DefenseStat = Defense and Defense:FindFirstChild("Stat")
	local DefenseCurrent = Defense and Defense:FindFirstChild("Current")
	if DefenseStat and DefenseStat:IsA("TextLabel") then
		DefenseStat.Text = tostring(displayStats.Defense or 0)
	end
	if DefenseCurrent then
		DefenseCurrent.Size = UDim2.new(0, 0, 1, 0)
		TweenService:Create(DefenseCurrent, TweenInfo.new(STAT_ANIMATION_TIME, TWEEN_STYLE, TWEEN_DIRECTION), { Size = UDim2.new(1, 0, 1, 0) }):Play()
	end
	local Speed = SummaryFrame:FindFirstChild("Speed")
	local SpeedStat = Speed and Speed:FindFirstChild("Stat")
	local SpeedCurrent = Speed and Speed:FindFirstChild("Current")
	if SpeedStat and SpeedStat:IsA("TextLabel") then
		SpeedStat.Text = tostring(displayStats.Speed or 0)
	end
	if SpeedCurrent then
		SpeedCurrent.Size = UDim2.new(0, 0, 1, 0)
		TweenService:Create(SpeedCurrent, TweenInfo.new(STAT_ANIMATION_TIME, TWEEN_STYLE, TWEEN_DIRECTION), { Size = UDim2.new(1, 0, 1, 0) }):Play()
	end
	local SpecialAttack = SummaryFrame:FindFirstChild("SpecialAttack")
	local SpecialAttackStat = SpecialAttack and SpecialAttack:FindFirstChild("Stat")
	local SpecialAttackCurrent = SpecialAttack and SpecialAttack:FindFirstChild("Current")
	if SpecialAttackStat and SpecialAttackStat:IsA("TextLabel") then
		SpecialAttackStat.Text = tostring(displayStats.SpecialAttack or 0)
	end
	if SpecialAttackCurrent then
		SpecialAttackCurrent.Size = UDim2.new(0, 0, 1, 0)
		TweenService:Create(SpecialAttackCurrent, TweenInfo.new(STAT_ANIMATION_TIME, TWEEN_STYLE, TWEEN_DIRECTION), { Size = UDim2.new(1, 0, 1, 0) }):Play()
	end
	local SpecialDefense = SummaryFrame:FindFirstChild("SpecialDefense")
	local SpecialDefenseStat = SpecialDefense and SpecialDefense:FindFirstChild("Stat")
	local SpecialDefenseCurrent = SpecialDefense and SpecialDefense:FindFirstChild("Current")
	if SpecialDefenseStat and SpecialDefenseStat:IsA("TextLabel") then
		SpecialDefenseStat.Text = tostring(displayStats.SpecialDefense or 0)
	end
	if SpecialDefenseCurrent then
		SpecialDefenseCurrent.Size = UDim2.new(0, 0, 1, 0)
		TweenService:Create(SpecialDefenseCurrent, TweenInfo.new(STAT_ANIMATION_TIME, TWEEN_STYLE, TWEEN_DIRECTION), { Size = UDim2.new(1, 0, 1, 0) }):Play()
	end

	-- IVs
	if creatureData.IVs then
		SetIVFrame(SummaryFrame, "HPIV", creatureData.IVs.HP, Color3.fromRGB(38, 255, 0))
		SetIVFrame(SummaryFrame, "AttackIV", creatureData.IVs.Attack, Color3.fromRGB(255, 78, 47))
		SetIVFrame(SummaryFrame, "DefenseIV", creatureData.IVs.Defense, Color3.fromRGB(47, 158, 255))
		SetIVFrame(SummaryFrame, "SpecialAttackIV", creatureData.IVs.SpecialAttack, Color3.fromRGB(200, 100, 255))
		SetIVFrame(SummaryFrame, "SpecialDefenseIV", creatureData.IVs.SpecialDefense, Color3.fromRGB(100, 200, 255))
		SetIVFrame(SummaryFrame, "SPDIV", creatureData.IVs.Speed, Color3.fromRGB(250, 189, 45))
	end

	-- Moves
	if not creatureData.CurrentMoves then
		-- Fallback: compute recent learnable moves (latest 4 under or at level)
		local base = Creatures[creatureData.Name]
		local learned = {}
		if base and base.Learnset then
			local flat = {}
			for lvl, movesAt in pairs(base.Learnset) do
				for _, mv in ipairs(movesAt) do
					table.insert(flat, { lvl = lvl, move = mv })
				end
			end
			table.sort(flat, function(a, b)
				if a.lvl == b.lvl then return tostring(a.move) < tostring(b.move) end
				return a.lvl < b.lvl
			end)
			local recent = {}
			for i = #flat, 1, -1 do
				local e = flat[i]
				if e.lvl <= (creatureData.Level or 1) and not table.find(recent, e.move) and MovesModule[e.move] then
					table.insert(recent, e.move)
					if #recent == 4 then break end
				end
			end
			creatureData.CurrentMoves = {}
			for i = #recent, 1, -1 do table.insert(creatureData.CurrentMoves, recent[i]) end
		end
	end
	fillMoves(SummaryFrame, creatureData)

	-- 3D preview
	setup3DPreview(SummaryFrame, creatureData)
end

-- Get GameUI.Summary frame
local function getSummaryFrame(): Frame?
	if _summaryFrame and _summaryFrame.Parent then
		return _summaryFrame
	end
	
	local player = Players.LocalPlayer
	if not player then return nil end
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return nil end
	local gameUi = playerGui:FindFirstChild("GameUI")
	if not gameUi then return nil end
	
	_summaryFrame = gameUi:FindFirstChild("Summary")
	return _summaryFrame
end

-- Connect navigation buttons once
local function connectButtons()
	if _buttonsConnected then return end
	
	local frame = getSummaryFrame()
	if not frame then return end
	
	-- Connect SummaryClose button
	local closeBtn = frame:FindFirstChild("SummaryClose")
	if closeBtn and (closeBtn:IsA("TextButton") or closeBtn:IsA("ImageButton")) then
		UIFunctions:NewButton(
			closeBtn,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.3,
			function()
				Audio.SFX.Click:Play()
				if _navigationCallbacks.onClose then
					_navigationCallbacks.onClose()
				else
					Summary:Hide()
				end
			end
		)
	end
	
	-- Connect Next button
	local nextBtn = frame:FindFirstChild("Next")
	if nextBtn and (nextBtn:IsA("TextButton") or nextBtn:IsA("ImageButton")) then
		UIFunctions:NewButton(
			nextBtn,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.3,
			function()
				Audio.SFX.Click:Play()
				if _navigationCallbacks.onNext then
					_navigationCallbacks.onNext()
				end
			end
		)
	end
	
	-- Connect Previous button
	local prevBtn = frame:FindFirstChild("Previous")
	if prevBtn and (prevBtn:IsA("TextButton") or prevBtn:IsA("ImageButton")) then
		UIFunctions:NewButton(
			prevBtn,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.3,
			function()
				Audio.SFX.Click:Play()
				if _navigationCallbacks.onPrevious then
					_navigationCallbacks.onPrevious()
				end
			end
		)
	end
	
	_buttonsConnected = true
end

-- Show summary with creature data and context
function Summary:Show(creatureData: any, context: string?)
	local frame = getSummaryFrame()
	if not frame then
		warn("[Summary] GameUI.Summary frame not found")
		return
	end
	
	-- Render the creature data
	Summary:Render(frame, creatureData)
	
	-- Show the frame
	frame.Visible = true
	
	-- Ensure buttons are connected
	connectButtons()
end

-- Hide summary
function Summary:Hide()
	local frame = getSummaryFrame()
	if not frame then return end
	
	frame.Visible = false
	
	-- Hide move info tooltip
	local moveInfo = frame:FindFirstChild("MoveInfo")
	if moveInfo then moveInfo.Visible = false end
	
	-- Clear 3D preview content to free resources
	local container = frame:FindFirstChild("3DPreview")
	if container then
		for _, child in ipairs(container:GetChildren()) do
			child:Destroy()
		end
	end
end

-- Set navigation callbacks
function Summary:SetNavigationCallbacks(onNext: (()->())?, onPrevious: (()->())?, onClose: (()->())?)
	_navigationCallbacks.onNext = onNext
	_navigationCallbacks.onPrevious = onPrevious
	_navigationCallbacks.onClose = onClose
end

-- Update navigation button visibility
function Summary:UpdateNavigationVisibility(showNext: boolean, showPrevious: boolean)
	local frame = getSummaryFrame()
	if not frame then return end
	
	local nextBtn = frame:FindFirstChild("Next")
	if nextBtn and nextBtn:IsA("GuiObject") then
		nextBtn.Visible = showNext == true
	end
	
	local prevBtn = frame:FindFirstChild("Previous")
	if prevBtn and prevBtn:IsA("GuiObject") then
		prevBtn.Visible = showPrevious == true
	end
end

return Summary



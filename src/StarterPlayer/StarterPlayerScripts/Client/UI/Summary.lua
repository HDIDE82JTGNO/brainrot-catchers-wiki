local Summary = {}

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local TypesModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local MovesModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Moves"))
local Creatures = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Creatures"))
local StatCalc = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StatCalc"))

local MOVE_ANIMATION_TIME = 0.2
local STAT_ANIMATION_TIME = 0.5
local COLOR_ANIMATION_TIME = 0.3
local TWEEN_STYLE = Enum.EasingStyle.Quart
local TWEEN_DIRECTION = Enum.EasingDirection.Out

local MoveHoverConnections = setmetatable({}, { __mode = "k" })
local OrbitConnections = setmetatable({}, { __mode = "k" })

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
    -- Accept any GuiObject (Frame, ImageLabel, etc.) as the preview container
    if not container or not container:IsA("GuiObject") then return end

	-- Clear dynamic children
	local previous = container:FindFirstChild("Viewport")
	if previous and previous:IsA("ViewportFrame") then
		previous:Destroy()
	end
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("ImageLabel") and child.Name == "SpriteFallback" then
			child:Destroy()
		end
	end
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Viewport"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.ZIndex = 15
	viewport.BackgroundTransparency = 1
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.Ambient = Color3.fromRGB(255, 255, 255)
	viewport.Parent = container

	local worldModel = Instance.new("WorldModel")
	worldModel.Name = "WorldModel"
	worldModel.Parent = viewport

	local cam = Instance.new("Camera")
	cam.Name = "ViewportCamera"
	cam.Parent = viewport
	viewport.CurrentCamera = cam

	local modelsFolder = ReplicatedStorage:FindFirstChild("Assets")
	modelsFolder = modelsFolder and modelsFolder:FindFirstChild("CreatureModels") or nil
	local modelTemplate: Instance? = modelsFolder and modelsFolder:FindFirstChild(tostring(creatureData.BaseName or creatureData.Name)) or nil
	if modelTemplate and modelTemplate:IsA("Model") then
		local model = modelTemplate:Clone()
		model.Parent = worldModel
		-- Apply shiny recolor if flagged and shiny palette exists on base creature
		local base = Creatures[creatureData.BaseName or creatureData.Name]
		local shinyMap = (creatureData.Shiny == true) and base and base.ShinyColors or nil
		if shinyMap and typeof(shinyMap) == "table" then
			for partName, color in pairs(shinyMap) do
				local inst = model:FindFirstChild(partName, true)
				if inst then
					if inst:IsA("BasePart") then
						(inst :: BasePart).Color = color
					elseif inst:IsA("Decal") then
						(inst :: Decal).Color3 = color
					end
				end
			end
		end
		local anchor: BasePart? = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart")
		if anchor and not model.PrimaryPart then model.PrimaryPart = anchor end
		model:PivotTo(CFrame.new(0,0,0))

		local size = model:GetExtentsSize()
		local vFov = math.rad(cam.FieldOfView)
		local vp = container.AbsoluteSize
		local aspect = (vp.Y > 0) and (vp.X / vp.Y) or 1
		local hFov = 2 * math.atan(math.tan(vFov * 0.5) * aspect)
		local halfHeight = math.max(0.5, size.Y * 0.5)
		local halfWidth = math.max(0.5, math.max(size.X, size.Z) * 0.5)
		local distV = halfHeight / math.tan(vFov * 0.5)
		local distH = halfWidth / math.tan(hFov * 0.5)
		local distance = math.max(4, math.max(distV, distH) * 1.2)
		local anchorPos = (model.PrimaryPart and model.PrimaryPart.Position) or Vector3.new(0,0,0)
		local target = anchorPos
		if math.abs(anchorPos.X) < 1e-3 and math.abs(anchorPos.Y) < 1e-3 and math.abs(anchorPos.Z) < 1e-3 then
			target = Vector3.new(0, halfHeight, 0)
		end
		-- Match Party camera placement and orientation EXACTLY
		local forward = Vector3.new(0, 0, -1)
		local camPos = -(target - (forward.Unit * distance))
		if camPos.Magnitude < 1e-3 then
			camPos = Vector3.new(0, 0, -distance)
		end
		cam.CFrame = CFrame.new(camPos) * CFrame.Angles(0, math.rad(-180), 0)
		cam.Focus = CFrame.new(target)

		-- Attempt to play idle if present (Humanoid or AnimationController)
		local animator: Animator? = nil
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			animator = humanoid:FindFirstChildOfClass("Animator")
			if not animator then
				animator = Instance.new("Animator")
				animator.Parent = humanoid
			end
		else
			local animController = model:FindFirstChildOfClass("AnimationController")
			if not animController then
				animController = Instance.new("AnimationController")
				animController.Parent = model
			end
			animator = animController:FindFirstChildOfClass("Animator")
			if not animator then
				animator = Instance.new("Animator")
				animator.Parent = animController
			end
		end
		local animFolder = model:FindFirstChild("Animations")
		local idle = animFolder and animFolder:FindFirstChild("Idle") or model:FindFirstChild("Idle")
		if idle and idle:IsA("Animation") and animator then
			local track = animator:LoadAnimation(idle)
			track.Priority = Enum.AnimationPriority.Idle
			track.Looped = true
			track:Play()
		end
	else
		-- Fallback to sprite image if no model (prefer shiny sprite when flagged)
		local base = Creatures[creatureData.BaseName or creatureData.Name]
		local useShiny = (creatureData.Shiny == true)
		local spriteId = nil
		if base then
			spriteId = (useShiny and base.ShinySprite) or base.Sprite
		end
		if spriteId then
			viewport:Destroy()
			local img = Instance.new("ImageLabel")
			img.Name = "SpriteFallback"
			img.BackgroundTransparency = 1
			img.Image = spriteId
			img.Size = UDim2.fromScale(1, 1)
			img.ZIndex = 15
			img.Parent = container
		else
			viewport:Destroy()
		end
	end

	-- Bind orbit drag to rotate model around Y (and slight pitch) like Party
	if OrbitConnections[container] then
		for _, conn in ipairs(OrbitConnections[container]) do
			if conn and conn.Connected then conn:Disconnect() end
		end
		OrbitConnections[container] = nil
	end
	local conns = {}
	OrbitConnections[container] = conns
	local dragging = false
	local lastX: number? = nil
	local lastY: number? = nil
	local rotateSpeed = math.rad(0.35)
	local yawAccum = 0
	local pitchAccum = 0

	local function onInputBegan(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			lastX = input.Position.X
			lastY = input.Position.Y
		end
	end
	local function onInputEnded(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
			lastX = nil
		end
	end
	local function onInputChanged(input: InputObject)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			if lastX and lastY then
				local dx = input.Position.X - lastX
				local dy = input.Position.Y - lastY
				lastX = input.Position.X
				lastY = input.Position.Y
				yawAccum += (dx * rotateSpeed)
				pitchAccum += (dy * rotateSpeed)
				local maxPitch = math.rad(80)
				if pitchAccum > maxPitch then pitchAccum = maxPitch end
				if pitchAccum < -maxPitch then pitchAccum = -maxPitch end
				if worldModel and #worldModel:GetChildren() > 0 then
					local m = worldModel:GetChildren()[1]
					if m and m:IsA("Model") then
						local hrp = m:FindFirstChild("HumanoidRootPart")
						if hrp and hrp:IsA("BasePart") then
							m.PrimaryPart = hrp
							local pos = hrp.Position
							local newRoot = CFrame.new(pos) * CFrame.Angles(pitchAccum, yawAccum, 0)
							m:PivotTo(newRoot)
						else
							local cf = m:GetPivot()
							local newPivot = cf * CFrame.Angles(-dy * rotateSpeed, dx * rotateSpeed, 0)
							m:PivotTo(newPivot)
						end
					end
				end
			end
		end
	end
	local c1 = container.InputBegan:Connect(onInputBegan)
	local c2 = container.InputEnded:Connect(onInputEnded)
	local c3 = game:GetService("UserInputService").InputChanged:Connect(onInputChanged)
	table.insert(conns, c1)
	table.insert(conns, c2)
	table.insert(conns, c3)
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

	local Attack = SummaryFrame:FindFirstChild("Attack")
	local AttackCurrent = Attack and Attack:FindFirstChild("Current")
	if AttackCurrent then
		AttackCurrent.Size = UDim2.new(0, 0, 1, 0)
		TweenService:Create(AttackCurrent, TweenInfo.new(STAT_ANIMATION_TIME, TWEEN_STYLE, TWEEN_DIRECTION), { Size = UDim2.new(1, 0, 1, 0) }):Play()
	end
	local Defense = SummaryFrame:FindFirstChild("Defense")
	local DefenseCurrent = Defense and Defense:FindFirstChild("Current")
	if DefenseCurrent then
		DefenseCurrent.Size = UDim2.new(0, 0, 1, 0)
		TweenService:Create(DefenseCurrent, TweenInfo.new(STAT_ANIMATION_TIME, TWEEN_STYLE, TWEEN_DIRECTION), { Size = UDim2.new(1, 0, 1, 0) }):Play()
	end
	local Speed = SummaryFrame:FindFirstChild("Speed")
	local SpeedCurrent = Speed and Speed:FindFirstChild("Current")
	if SpeedCurrent then
		SpeedCurrent.Size = UDim2.new(0, 0, 1, 0)
		TweenService:Create(SpeedCurrent, TweenInfo.new(STAT_ANIMATION_TIME, TWEEN_STYLE, TWEEN_DIRECTION), { Size = UDim2.new(1, 0, 1, 0) }):Play()
	end

	-- IVs
	if creatureData.IVs then
		SetIVFrame(SummaryFrame, "HPIV", creatureData.IVs.HP, Color3.fromRGB(38, 255, 0))
		SetIVFrame(SummaryFrame, "AttackIV", creatureData.IVs.Attack, Color3.fromRGB(255, 78, 47))
		SetIVFrame(SummaryFrame, "DefenseIV", creatureData.IVs.Defense, Color3.fromRGB(47, 158, 255))
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

return Summary



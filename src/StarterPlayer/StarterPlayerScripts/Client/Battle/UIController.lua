--!strict
--[[
	UIController.lua
	Manages battle UI state and updates
	Provides clean interface for UI manipulation
]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local GameUI = PlayerGui:WaitForChild("GameUI")
local BattleUI = GameUI:WaitForChild("BattleUI")

-- Load shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Creatures = require(Shared:WaitForChild("Creatures"))

local UIController = {}
UIController.__index = UIController

export type UICallback = () -> ()

--[[
	Creates a new UI controller instance
	@return UIController
]]
function UIController.new(): any
	local self = setmetatable({}, UIController)
	
	self._battleUI = BattleUI
	self._battleOptions = BattleUI:WaitForChild("BattleOptions")
	self._moveOptions = BattleUI:WaitForChild("MoveOptions")
	self._youUI = BattleUI:WaitForChild("You")
	self._foeUI = BattleUI:WaitForChild("Foe")
	self._battleNotification = BattleUI:WaitForChild("BattleNotification")
	
	self._activeTweens = {} :: {Tween}
	self._youUIPosition = nil
	self._foeUIPosition = nil
	self._foeFaintedByIndex = {} :: {[number]: boolean}
	self._previousStatus = {} :: {[boolean]: string?}  -- Track previous status for each side
	self._combatEffects = nil  -- Will be set by BattleSystem
	
	return self
end

--[[
	Sets the combat effects reference for thaw detection
	@param combatEffects The CombatEffects instance
]]
function UIController:SetCombatEffects(combatEffects: any)
	self._combatEffects = combatEffects
end

--[[
	Initializes UI positions
]]
function UIController:Initialize()
	self._youUIPosition = self._youUI.Position
	self._foeUIPosition = self._foeUI.Position
end

--[[
	Clears existing CreatureAmount clones for both sides
]]
function UIController:ClearCreatureAmount()
	local function clear(container: Instance?)
		if not container then return end
		for _, child in ipairs(container:GetChildren()) do
			if child.Name ~= "Template" and not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
	end

	local you = self._youUI and self._youUI:FindFirstChild("CreatureAmount")
	local foe = self._foeUI and self._foeUI:FindFirstChild("CreatureAmount")
	clear(you)
	clear(foe)
end

--[[
	Marks a foe party slot as fainted (used when server may not update trainer party HP on client)
	@param index number Index in foe party
]]
function UIController:MarkFoeFainted(index: number)
	if type(index) == "number" and index > 0 then
		self._foeFaintedByIndex[index] = true
	end
end

--[[
	Refreshes CreatureAmount indicators
	@param battleType string "Wild" or "Trainer"
	@param playerParty {any} Player party array
	@param foeParty {any}? Trainer foe party array (only for Trainer battles)
]]
function UIController:RefreshCreatureAmount(battleType: string, playerParty: {any}, foeParty: {any}?)
	local function render(containerParent: Instance?, party: {any}, isFoe: boolean)
		if not containerParent or not party then return end
		local container = containerParent:FindFirstChild("CreatureAmount")
		if not container then return end
		local template = container:FindFirstChild("Template")
		if not (template and template:IsA("GuiObject")) then return end

		-- Cleanup existing non-template children
		for _, child in ipairs(container:GetChildren()) do
			if child ~= template and not child:IsA("UIListLayout") then child:Destroy() end
		end

		-- Helper to set image transparency on clone
		local function setTransparencyOnClone(clone: Instance, alpha: number)
			local applied = false
			if clone:IsA("ImageLabel") or clone:IsA("ImageButton") then
				(clone :: any).ImageTransparency = alpha
				applied = true
			end
			if not applied then
				for _, d in ipairs(clone:GetDescendants()) do
					if d:IsA("ImageLabel") or d:IsA("ImageButton") then
						(d :: any).ImageTransparency = alpha
						applied = true
						break
					end
				end
			end
			if not applied and clone:IsA("GuiObject") then
				(clone :: GuiObject).BackgroundTransparency = alpha
			end
		end

		for i, creature in ipairs(party) do
			local clone = (template :: GuiObject):Clone()
			clone.Visible = true
			clone.Name = string.format("Slot%d", i)
			clone.LayoutOrder = i
			clone.Parent = container

			-- Determine fainted
			local fainted = false
			local hp = nil
			if creature then
				local stats = (creature :: any).Stats
				if stats and type(stats.HP) == "number" then
					hp = stats.HP
				elseif (creature :: any).CurrentHP ~= nil then
					hp = tonumber((creature :: any).CurrentHP)
				end
			end
			if hp ~= nil then
				fainted = (hp <= 0)
			elseif isFoe and self._foeFaintedByIndex[i] then
				fainted = true
			end

			setTransparencyOnClone(clone, fainted and 0.65 or 0)
		end
	end

	-- Always render player's indicators
	if self._youUI then
		self._youUI.Visible = self._youUI.Visible ~= false
		render(self._youUI, playerParty or {}, false)
	end

	-- Foe indicators: only for Trainer battles
	local foeContainer = self._foeUI and self._foeUI:FindFirstChild("CreatureAmount")
	if foeContainer then
		if battleType == "Trainer" then
			foeContainer.Visible = true
			render(self._foeUI, foeParty or {}, true)
		else
			-- Wild battle: hide foe count
			for _, child in ipairs(foeContainer:GetChildren()) do
				if child.Name ~= "Template" and not child:IsA("UIListLayout") then child:Destroy() end
			end
			foeContainer.Visible = false
		end
	end
end

--[[
	Shows battle options
]]
function UIController:ShowBattleOptions()
	self:_toggleOptions(self._battleOptions, true)
end

--[[
	Hides battle options
]]
function UIController:HideBattleOptions()
	self:_toggleOptions(self._battleOptions, false)
end

--[[
	Shows move options
]]
function UIController:ShowMoveOptions()
	self:_toggleOptions(self._moveOptions, true)
end

--[[
	Hides move options
]]
function UIController:HideMoveOptions()
	self:_toggleOptions(self._moveOptions, false)
end

--[[
	Updates creature UI display
	@param isPlayer Whether this is the player's creature
	@param creatureData The creature data
	@param shouldTween Whether to tween HP changes
]]
function UIController:UpdateCreatureUI(
	isPlayer: boolean,
	creatureData: any,
	shouldTween: boolean?
)
	local ui = isPlayer and self._youUI or self._foeUI
	if not ui then
		warn("[UIController] UI frame not found for", isPlayer and "player" or "foe")
		return
	end
	
	print("[UIController] Updating creature UI for:", creatureData.Name, "IsPlayer:", isPlayer)
	
	-- Update creature name (use nickname if available)
	local creatureName = ui:FindFirstChild("CreatureName") or ui:FindFirstChild("Name")
	if creatureName and creatureName:IsA("TextLabel") then
		local displayName = creatureData.Nickname or creatureData.Name or "Unknown"
		creatureName.Text = displayName
		print("[UIController] Updated name to:", displayName)
	end
	
	-- Update level
	local levelLabel = ui:FindFirstChild("Level")
	if levelLabel and levelLabel:IsA("TextLabel") then
		levelLabel.Text = "Lv." .. tostring(creatureData.Level or 1)
		print("[UIController] Updated level to:", creatureData.Level or 1)
	end
	
	-- Update gender icon
	self:_updateGenderIcon(ui, creatureData)
	
	-- Update type display
	self:_updateTypeDisplay(ui, creatureData)
	
	-- Update status condition display
	self:UpdateStatusDisplay(isPlayer, creatureData)
	
	-- Update HP
	self:UpdateHPBar(isPlayer, creatureData, shouldTween)
end

--[[
	Updates HP bar display
	@param isPlayer Whether this is the player's creature
	@param creatureData The creature data
	@param shouldTween Whether to tween the change
]]
function UIController:UpdateHPBar(
	isPlayer: boolean,
	creatureData: any,
	shouldTween: boolean?
)
	local ui = isPlayer and self._youUI or self._foeUI
	if not ui then
		return
	end
	
	-- Legacy system updates HPAmount (Frame), not HPBar!
	-- Bar frame to size/color: You/Foe.HPAmount (Frame)
	-- Label for text: You/Foe.HPBar.HPAmount (TextLabel or TextLabel.Text)
	local barFrame = ui:FindFirstChild("HPAmount")
	local hpBar = ui:FindFirstChild("HPBar")
	local label = hpBar and hpBar:FindFirstChild("HPAmount")
	
	if not barFrame or not barFrame:IsA("Frame") then
		warn("[UIController] HPAmount frame not found in UI")
		return
	end
	
	local currentHP = creatureData.Stats and creatureData.Stats.HP or 0
	local maxHP = creatureData.MaxStats and creatureData.MaxStats.HP or 1
	local hpPercentage = math.clamp(currentHP / maxHP, 0, 1)
	
	print("[UIController] Updating HP bar - Current:", currentHP, "Max:", maxHP, "Percentage:", hpPercentage)
	
	-- Update HP text label with gradual animation
	if label then
		local amountLabel = label:FindFirstChild("Text")
		local textLabel = amountLabel and amountLabel:IsA("TextLabel") and amountLabel or (label:IsA("TextLabel") and label or nil)
		
		if textLabel then
			-- Get current HP from text if available, otherwise use the new value
			local currentText = textLabel.Text
			local currentHPFromText = 0
			if currentText and string.find(currentText, "HP:") then
				local hpMatch = string.match(currentText, "HP: (%d+)/")
				if hpMatch then
					currentHPFromText = tonumber(hpMatch) or 0
				end
			end
			
			-- Animate HP text if we're tweening and the HP changed
			if shouldTween and currentHPFromText ~= currentHP then
				self:_animateHPText(textLabel, currentHPFromText, currentHP, maxHP)
			else
				textLabel.Text = "HP: " .. tostring(currentHP) .. "/" .. tostring(maxHP)
			end
			textLabel.Visible = true
		end
		print("[UIController] Updated HP label:", currentHP .. "/" .. maxHP)
	end
	
	-- Cache original full size once (used as 100% baseline)
	if barFrame:GetAttribute("FullXScale") == nil then
		barFrame:SetAttribute("FullXScale", barFrame.Size.X.Scale)
		barFrame:SetAttribute("FullXOffset", barFrame.Size.X.Offset)
		barFrame:SetAttribute("FullYScale", barFrame.Size.Y.Scale)
		barFrame:SetAttribute("FullYOffset", barFrame.Size.Y.Offset)
	end
	
	local fullXScale = barFrame:GetAttribute("FullXScale") or barFrame.Size.X.Scale
	local fullXOffset = barFrame:GetAttribute("FullXOffset") or barFrame.Size.X.Offset
	local fullYScale = barFrame:GetAttribute("FullYScale") or barFrame.Size.Y.Scale
	local fullYOffset = barFrame:GetAttribute("FullYOffset") or barFrame.Size.Y.Offset
	
	-- Respect original sizing mode: scale or offset
	local targetSize
	if fullXScale and fullXScale > 0 then
		targetSize = UDim2.new(fullXScale * hpPercentage, fullXOffset, fullYScale, fullYOffset)
	else
		targetSize = UDim2.new(0, math.floor((fullXOffset) * hpPercentage + 0.5), fullYScale, fullYOffset)
	end
	
	-- Update HP bar size with tween
	if shouldTween then
		local hpBarTweenInfo = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local sizeTween = TweenService:Create(barFrame, hpBarTweenInfo, {Size = targetSize})
		table.insert(self._activeTweens, sizeTween)
		sizeTween:Play()
		print("[UIController] HP bar tween started")
	else
		barFrame.Size = targetSize
		print("[UIController] HP bar updated instantly")
	end
	
	-- Color transition from green (full) to red (empty)
	local green = Color3.fromRGB(5, 255, 68)
	local red = Color3.fromRGB(255, 3, 3)
	local color = self:_lerpColor3(red, green, hpPercentage)
	
	local colorTween = TweenService:Create(
		barFrame,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundColor3 = color}
	)
	table.insert(self._activeTweens, colorTween)
	colorTween:Play()
	
	print("[UIController] HP bar updated to", math.floor(hpPercentage * 100 + 0.5), "%")
end

--[[
	Updates level UI display
	@param creatureData The creature data
	@param shouldTween Whether to tween XP bar
]]
--[[
	Updates the XP/Level UI for the player's creature
	@param creatureData The creature data containing Level and XPProgress
	@param shouldTween Whether to animate the XP bar
	@param isLevelUp Whether this is a level-up (triggers special animation)
]]
function UIController:UpdateLevelUI(creatureData: any, shouldTween: boolean?, isLevelUp: boolean?)
	if not self._youUI then
		return
	end
	
	local lvProgress = self._youUI:FindFirstChild("LvProgress")
	if not lvProgress then
		return
	end
	
	local xpProgress = (creatureData.XPProgress or 0) / 100
	local targetSize = UDim2.new(xpProgress, 0, lvProgress.Size.Y.Scale, lvProgress.Size.Y.Offset)
	
	print("[XP] UI: UpdateLevelUI called - XPProgress:", creatureData.XPProgress or "nil", "Progress:", xpProgress, "shouldTween:", shouldTween, "isLevelUp:", isLevelUp)
	
	if shouldTween and isLevelUp then
		-- Level-up animation: Fill to max → snap to 0 → update level → tween to new progress
		print("[XP] UI: Animating level-up sequence - fill to max → snap to 0 → update level → tween to", xpProgress)
		
		-- Step 1: Tween to max (100%)
		local fillTween = TweenService:Create(
			lvProgress,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Size = UDim2.new(1, 0, lvProgress.Size.Y.Scale, lvProgress.Size.Y.Offset)}
		)
		table.insert(self._activeTweens, fillTween)
		fillTween:Play()
		
		-- Step 2: After fill completes, snap to 0 and update level labels
		fillTween.Completed:Connect(function()
			-- Snap to 0
			lvProgress.Size = UDim2.new(0, 0, lvProgress.Size.Y.Scale, lvProgress.Size.Y.Offset)
			
			-- Update level labels immediately
			local currentLevelLabel = self._youUI:FindFirstChild("CurrentLevelLabel")
			if currentLevelLabel and currentLevelLabel:IsA("TextLabel") then
				currentLevelLabel.Text = "Lv. " .. tostring(creatureData.Level or 1)
			end
			
			local nextLevelLabel = self._youUI:FindFirstChild("NextLevelLabel")
			if nextLevelLabel and nextLevelLabel:IsA("TextLabel") then
				nextLevelLabel.Text = "Lv. " .. tostring((creatureData.Level or 1) + 1)
			end

			-- Fallback: some UI uses LvBackdrop.CurrentLevel and LvBackdrop.NextLevel
			local lvBackdrop = self._youUI:FindFirstChild("LvBackdrop")
			if lvBackdrop and lvBackdrop:IsA("Frame") then
				local curr = lvBackdrop:FindFirstChild("CurrentLevel")
				if curr and curr:IsA("TextLabel") then
					curr.Text = "Lv. " .. tostring(creatureData.Level or 1)
				end
				local next = lvBackdrop:FindFirstChild("NextLevel")
				if next and next:IsA("TextLabel") then
					next.Text = "Lv. " .. tostring((creatureData.Level or 1) + 1)
				end
			end
			
			-- Also update the compact level label (You.Level) used by some UIs
			local compactLevel = self._youUI:FindFirstChild("Level")
			if compactLevel and compactLevel:IsA("TextLabel") then
				compactLevel.Text = "Lv." .. tostring(creatureData.Level or 1)
			end

			-- Small pause
			task.wait(0.1)
			
			-- Step 3: Tween to new progress
			local progressTween = TweenService:Create(
				lvProgress,
				TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{Size = targetSize}
			)
			table.insert(self._activeTweens, progressTween)
			progressTween:Play()
		end)
	elseif shouldTween then
		-- Normal XP gain animation (no level-up)
		local tween = TweenService:Create(
			lvProgress,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Size = targetSize}
		)
		table.insert(self._activeTweens, tween)
		tween:Play()
		
		-- Update level labels immediately for non-level-up tweens
		local currentLevelLabel = self._youUI:FindFirstChild("CurrentLevelLabel")
		if currentLevelLabel and currentLevelLabel:IsA("TextLabel") then
			currentLevelLabel.Text = "Lv. " .. tostring(creatureData.Level or 1)
		end
		
		local nextLevelLabel = self._youUI:FindFirstChild("NextLevelLabel")
		if nextLevelLabel and nextLevelLabel:IsA("TextLabel") then
			nextLevelLabel.Text = "Lv. " .. tostring((creatureData.Level or 1) + 1)
		end

		-- Fallback
		local lvBackdrop = self._youUI:FindFirstChild("LvBackdrop")
		if lvBackdrop and lvBackdrop:IsA("Frame") then
			local curr = lvBackdrop:FindFirstChild("CurrentLevel")
			if curr and curr:IsA("TextLabel") then
				curr.Text = "Lv. " .. tostring(creatureData.Level or 1)
			end
			local next = lvBackdrop:FindFirstChild("NextLevel")
			if next and next:IsA("TextLabel") then
				next.Text = "Lv. " .. tostring((creatureData.Level or 1) + 1)
			end
		end

		-- Also update the compact level label (You.Level) used by some UIs
		local compactLevel = self._youUI:FindFirstChild("Level")
		if compactLevel and compactLevel:IsA("TextLabel") then
			compactLevel.Text = "Lv." .. tostring(creatureData.Level or 1)
		end
	else
		-- Instant update (no animation)
		lvProgress.Size = targetSize
		
		-- Update level labels
		local currentLevelLabel = self._youUI:FindFirstChild("CurrentLevelLabel")
		if currentLevelLabel and currentLevelLabel:IsA("TextLabel") then
			currentLevelLabel.Text = "Lv. " .. tostring(creatureData.Level or 1)
		end
		
		local nextLevelLabel = self._youUI:FindFirstChild("NextLevelLabel")
		if nextLevelLabel and nextLevelLabel:IsA("TextLabel") then
			nextLevelLabel.Text = "Lv. " .. tostring((creatureData.Level or 1) + 1)
		end

		-- Fallback
		local lvBackdrop = self._youUI:FindFirstChild("LvBackdrop")
		if lvBackdrop and lvBackdrop:IsA("Frame") then
			local curr = lvBackdrop:FindFirstChild("CurrentLevel")
			if curr and curr:IsA("TextLabel") then
				curr.Text = "Lv. " .. tostring(creatureData.Level or 1)
			end
			local next = lvBackdrop:FindFirstChild("NextLevel")
			if next and next:IsA("TextLabel") then
				next.Text = "Lv. " .. tostring((creatureData.Level or 1) + 1)
			end
		end

		-- Also update the compact level label (You.Level) used by some UIs
		local compactLevel = self._youUI:FindFirstChild("Level")
		if compactLevel and compactLevel:IsA("TextLabel") then
			compactLevel.Text = "Lv." .. tostring(creatureData.Level or 1)
		end
	end
end

--[[
	Shows a battle message
	@param message The message to display
	@param duration Duration to show (optional)
]]
function UIController:ShowMessage(message: string, duration: number?)
	if not self._battleNotification then
		return
	end
	
	local textLabel = self._battleNotification:FindFirstChild("Text")
	if textLabel and textLabel:IsA("TextLabel") then
		textLabel.Text = message
	end
	
	self._battleNotification.Visible = true
	
	task.wait(duration or 0.55)
	
	self._battleNotification.Visible = false
end

--[[
	Gets the You UI position
	@return UDim2? The position
]]
function UIController:GetYouUIPosition(): UDim2?
	return self._youUIPosition
end

--[[
	Gets the Foe UI position
	@return UDim2? The position
]]
function UIController:GetFoeUIPosition(): UDim2?
	return self._foeUIPosition
end

--[[
	Gets the You UI frame
	@return Frame? The frame
]]
function UIController:GetYouUI(): Frame?
	return self._youUI
end

--[[
	Gets the Foe UI frame
	@return Frame? The frame
]]
function UIController:GetFoeUI(): Frame?
	return self._foeUI
end

--[[
	Slides UI off screen (for battle end sequence)
	@param isPlayer boolean True for player UI, false for foe UI
]]
function UIController:SlideUIOut(isPlayer: boolean)
	local ui = isPlayer and self._youUI or self._foeUI
	if not ui then
		return
	end
	
	local TweenService = game:GetService("TweenService")
	local targetPosition
	
	if isPlayer then
		-- Slide player UI to the left (matching slide-in off-screen position)
		targetPosition = UDim2.new(-0.15, 0, -0.55, 0)
	else
		-- Slide foe UI to the right (position {1.25, 0},{-0.802, 0})
		targetPosition = UDim2.new(1.25, 0, -0.802, 0)
	end
	
	local slideTween = TweenService:Create(ui, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = targetPosition
	})
	
	table.insert(self._activeTweens, slideTween)
	slideTween:Play()
	
	print("[UIController] Sliding", isPlayer and "player" or "foe", "UI off screen")
end

--[[
	Slides You UI in from off-screen (for battle start sequence)
	@param callback Optional callback when animation completes
]]
function UIController:SlideYouUIIn(callback: (() -> ())?)
	if not self._youUI or not self._youUIPosition then
		warn("[UIController] You UI or position not available for slide-in")
		return
	end
	
	local TweenService = game:GetService("TweenService")
	
	-- Set initial position off-screen (slide from left)
	local offScreenPosition = UDim2.new(-0.15, 0, -0.55, 0)
	self._youUI.Position = offScreenPosition
	self._youUI.Visible = true
	
	-- Create slide-in tween to original position (matching foe slideout timing)
	local slideTween = TweenService:Create(
		self._youUI,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Position = self._youUIPosition}
	)
	
	-- Connect completion callback
	if callback then
		slideTween.Completed:Connect(callback)
	end
	
	-- Store tween for cleanup
	table.insert(self._activeTweens, slideTween)
	slideTween:Play()
	
	print("[UIController] Sliding You UI in from off-screen")
end

--[[
    Slides Foe UI in from off-screen (for foe send-out)
    @param callback Optional callback when animation completes
]]
function UIController:SlideFoeUIIn(callback: (() -> ())?)
    if not self._foeUI or not self._foeUIPosition then
        warn("[UIController] Foe UI or position not available for slide-in")
        return
    end
    
    local TweenService = game:GetService("TweenService")
    
    -- Set initial position off-screen (slide from right)
    local offScreenPosition = UDim2.new(1.25, 0, -0.802, 0)
    self._foeUI.Position = offScreenPosition
    self._foeUI.Visible = true
    
    local slideTween = TweenService:Create(
        self._foeUI,
        TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Position = self._foeUIPosition}
    )
    
    if callback then
        slideTween.Completed:Connect(callback)
    end
    
    table.insert(self._activeTweens, slideTween)
    slideTween:Play()
    
    print("[UIController] Sliding Foe UI in from off-screen")
end

--[[
	Updates status condition display
	@param isPlayer Whether this is the player's creature
	@param creatureData The creature data
]]
function UIController:UpdateStatusDisplay(isPlayer: boolean, creatureData: any)
	local ui = isPlayer and self._youUI or self._foeUI
	if not ui then
		return
	end
	
	local statusFrame = ui:FindFirstChild("Status")
	if not statusFrame or not statusFrame:IsA("Frame") then
		-- Status frame doesn't exist, skip
		return
	end
	
	local statusText = statusFrame:FindFirstChild("StatusText")
	if not statusText or not statusText:IsA("TextLabel") then
		return
	end
	
	local StatusModule = require(ReplicatedStorage.Shared.Status)
	
	-- Check if status was cleared (was FRZ, now nil)
	local previousStatus = self._previousStatus[isPlayer]
	local currentStatus = creatureData.Status and creatureData.Status.Type and tostring(creatureData.Status.Type):upper() or nil
	
	-- If creature was frozen and is now thawed, trigger thaw effect
	if previousStatus == "FRZ" and currentStatus ~= "FRZ" then
		print("[UIController] Status changed from FRZ to", currentStatus or "nil", "- triggering thaw")
		-- Get the creature model and thaw it
		if self._combatEffects and self._combatEffects.ThawCreature then
			-- We need to get the model from somewhere - this will be handled by StepProcessor via message callback
			-- But we can also check here if we have access to scene manager
		end
	end
	
	-- Update previous status
	self._previousStatus[isPlayer] = currentStatus
	
	-- Check if creature has a status condition
	if creatureData.Status and creatureData.Status.Type then
		local statusType = tostring(creatureData.Status.Type):upper()
		local statusDef = StatusModule.GetDefinition(statusType)
		
		print("[UIController] UpdateStatusDisplay - StatusType:", statusType, "StatusDef:", statusDef and "found" or "nil", "IsPlayer:", isPlayer)
		
		if statusDef then
			-- Map status codes to display names
			local displayNames = {
				BRN = "Burned",
				PAR = "Paralyzed",
				PSN = "Poisoned",
				TOX = "Badly Poisoned",
				SLP = "Asleep",
				FRZ = "Frozen",
			}
			
			local displayName = displayNames[statusType] or statusDef.Name
			
			statusFrame.Visible = true
			statusText.Text = displayName
			-- Keep text color white (don't change to status color)
			statusText.TextColor3 = Color3.fromRGB(255, 255, 255)
			
			-- Update frame background color
			if statusFrame:IsA("Frame") then
				statusFrame.BackgroundColor3 = statusDef.Color
			end
			
			-- Update stroke color
			local stroke = statusText:FindFirstChild("UIStroke")
			if stroke and stroke:IsA("UIStroke") then
				stroke.Color = statusDef.StrokeColor
			end
			
			-- Update frame stroke if it exists
			local frameStroke = statusFrame:FindFirstChild("UIStroke")
			if frameStroke and frameStroke:IsA("UIStroke") then
				frameStroke.Color = statusDef.StrokeColor
			end
			
			print("[UIController] Status UI updated - Visible:", statusFrame.Visible, "Text:", displayName, "Color:", statusDef.Color)
		else
			warn("[UIController] Status definition not found for:", statusType)
			statusFrame.Visible = false
		end
	else
		-- No status condition
		print("[UIController] No status condition found")
		statusFrame.Visible = false
	end
end

--[[
	Resets UI positions to their original state
]]
function UIController:ResetUIPositions()
	if self._youUI and self._youUIPosition then
		self._youUI.Position = self._youUIPosition
		print("[UIController] Reset player UI position")
	end
	
	if self._foeUI and self._foeUIPosition then
		self._foeUI.Position = self._foeUIPosition
		print("[UIController] Reset foe UI position")
	end
end

--[[
	Cleans up all active tweens
]]
function UIController:Cleanup()
	for _, tween in ipairs(self._activeTweens) do
		if tween then
			tween:Cancel()
		end
	end
	self._activeTweens = {}
end

--[[
	Internal: Toggles UI options visibility
]]
function UIController:_toggleOptions(frame: Frame, visible: boolean)
	if not frame then
		return
	end
	
	frame.Visible = visible
	
	-- Enable/disable buttons
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("TextButton") or child:IsA("ImageButton") then
			child.Active = visible
			child.Visible = visible
		end
	end
end

--[[
	Internal: Lerps between two Color3 values
]]
function UIController:_lerpColor3(c1: Color3, c2: Color3, alpha: number): Color3
	return Color3.new(
		c1.R + (c2.R - c1.R) * alpha,
		c1.G + (c2.G - c1.G) * alpha,
		c1.B + (c2.B - c1.B) * alpha
	)
end

--[[
	Animates HP text from current value to target value
	@param textLabel The text label to animate
	@param fromHP Starting HP value
	@param toHP Target HP value
	@param maxHP Maximum HP value
]]
function UIController:_animateHPText(textLabel: TextLabel, fromHP: number, toHP: number, maxHP: number)
	local duration = 0.6  -- Match HP bar tween duration
	local steps = math.max(1, math.abs(toHP - fromHP))  -- One step per HP point
	local stepDuration = duration / steps
	
	local currentHP = fromHP
	local stepDirection = toHP > fromHP and 1 or -1
	
	local function updateText()
		if currentHP == toHP then
			textLabel.Text = "HP: " .. tostring(toHP) .. "/" .. tostring(maxHP)
			return
		end
		
		currentHP = currentHP + stepDirection
		textLabel.Text = "HP: " .. tostring(currentHP) .. "/" .. tostring(maxHP)
		
		task.wait(stepDuration)
		updateText()
	end
	
	task.spawn(updateText)
end

--[[
	Internal: Updates gender icon display
]]
function UIController:_updateGenderIcon(ui: Frame, creatureData: any)
	local genderIcon = ui:FindFirstChild("Gender") or ui:FindFirstChild("GenderIcon")
	
	if genderIcon and creatureData.Gender ~= nil then
		-- Set gender icon using ImageRectOffset (same as Party UI)
		if creatureData.Gender == 0 then
			-- Male icon
			genderIcon.ImageRectOffset = Vector2.new(510, 75)
			genderIcon.Visible = true
			print("[UIController] Set male gender icon")
		elseif creatureData.Gender == 1 then
			-- Female icon
			genderIcon.ImageRectOffset = Vector2.new(0, 75)
			genderIcon.Visible = true
			print("[UIController] Set female gender icon")
		else
			genderIcon.Visible = false
		end
	elseif genderIcon then
		genderIcon.Visible = false
		print("[UIController] No gender data, hiding icon")
	end
end

--[[
	Internal: Updates type display
]]
function UIController:_updateTypeDisplay(ui: Frame, creatureData: any)
    -- Determine type names (support both string and array forms)
    local function getTypeNames()
        local out = {}
        local typeRef = creatureData.Type or (creatureData.Name and Creatures[creatureData.Name] and Creatures[creatureData.Name].Type)
        if not typeRef then return out end
        if typeof(typeRef) == "string" then
            out[1] = typeRef
        elseif type(typeRef) == "table" then
            for i, t in ipairs(typeRef) do
                if typeof(t) == "string" then out[#out+1] = t end
            end
        end
        return out
    end

    local names = getTypeNames()

    -- Primary type frame (existing)
    local typeFrame = ui:FindFirstChild("CreatureType")
    local typeText = typeFrame and typeFrame:FindFirstChild("TypeText")
    if typeFrame and typeText and typeText:IsA("TextLabel") and names[1] and Types[names[1]] then
        local color = Types[names[1]].uicolor
        typeFrame.BackgroundColor3 = color
        typeText.Text = names[1]
        local stroke = typeFrame:FindFirstChild("UIStroke")
        if stroke then
            stroke.Color = Color3.new(math.max(0, color.R * 0.6), math.max(0, color.G * 0.6), math.max(0, color.B * 0.6))
        end
    end

    -- Optional second type frame
    local second = ui:FindFirstChild("SecondCreatureType")
    if second and second:IsA("Frame") then
        local label = second:FindFirstChild("TypeText")
        if names[2] and Types[names[2]] then
            second.Visible = true
            second.BackgroundColor3 = Types[names[2]].uicolor
            if label and label:IsA("TextLabel") then
                label.Text = names[2]
            end
            local stroke = second:FindFirstChild("UIStroke")
            if stroke then
                local c = Types[names[2]].uicolor
                stroke.Color = Color3.new(math.max(0, c.R * 0.6), math.max(0, c.G * 0.6), math.max(0, c.B * 0.6))
            end
        else
            second.Visible = false
        end
    end
end

return UIController

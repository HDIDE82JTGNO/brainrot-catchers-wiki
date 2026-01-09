--[[
	BattleOptionsManager.lua
	
	Manages the consolidated BattleUI.Controller (replaces BattleOptions/MoveOptions)
	with clean state management, smooth animations, and event-driven design.
	
	Features:
	- Slide-in/out animations for both option menus
	- State tracking to prevent overlapping transitions
	- Cross-fade between menus (hide one, show another)
	- Move button updates with type effectiveness indicators
	- Clean callback system for button interactions
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local GameUI = PlayerGui:WaitForChild("GameUI")
local BattleUI = GameUI:WaitForChild("BattleUI")
local Controller = BattleUI:WaitForChild("Controller")

-- Import modules
local Types = require(ReplicatedStorage.Shared.Types)
local Moves = require(ReplicatedStorage.Shared.Moves)

-- Layout + animation constants for the consolidated Controller frame
local POSITIONS = {
	BattleOptions = {
		Fight = UDim2.fromScale(0.5, 0.101),
		Bag = UDim2.fromScale(0.03, 0.5),
		Creatures = UDim2.fromScale(0.952, 0.5),
		Run = UDim2.fromScale(0.5, 0.918),
		Move1 = UDim2.fromScale(0.5, -3),
		Move2 = UDim2.fromScale(-7, 0.5),
		Move3 = UDim2.fromScale(2.5, 0.5),
		Move4 = UDim2.fromScale(0.5, 2.5),
		Back = UDim2.fromScale(-3.5, -3.282),
	},
	MoveOptions = {
		Fight = UDim2.fromScale(0.5, -3),
		Bag = UDim2.fromScale(-7, 0.5),
		Creatures = UDim2.fromScale(2.5, 0.5),
		Run = UDim2.fromScale(0.5, 2.5),
		Move1 = UDim2.fromScale(0.5, 0.101),
		Move2 = UDim2.fromScale(0.03, 0.5),
		Move3 = UDim2.fromScale(0.952, 0.5),
		Move4 = UDim2.fromScale(0.5, 0.918),
		Back = UDim2.fromScale(-0.223, -0.174),
	},
}

local TWEEN = {
	Position = TweenInfo.new(0.35, Enum.EasingStyle.Circular, Enum.EasingDirection.InOut),
	SizeFast = TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
	SizeSlow = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
}

local SIZE = {
	Expanded = UDim2.fromScale(0.173, 0.67),
	Compact = UDim2.fromScale(0.157, 0.611),
}

local FADE_IN = TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

local TEXT_OBJECT_CLASSES = {
	TextLabel = true,
	TextButton = true,
	TextBox = true,
}

local function findTextObject(root: Instance?, names: {string}): TextLabel | TextButton | TextBox | nil
	if not root then
		return nil
	end

	for _, name in ipairs(names) do
		local inst = root:FindFirstChild(name, true)
		if inst and TEXT_OBJECT_CLASSES[inst.ClassName] then
			return inst
		end
	end

	return nil
end

local function setTextOnFirst(root: Instance?, names: {string}, text: string): ()
	local label = findTextObject(root, names)
	if label then
		label.Text = text
	end
end

local function setImageTransparency(obj: Instance?, transparency: number)
	if not obj then
		return
	end
	if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
		obj.ImageTransparency = transparency
	end
end

local function applyPositions(root: Frame, state: "BattleOptions" | "MoveOptions")
	local pos = POSITIONS[state]
	if not root or not pos then
		return
	end

	for name, value in pairs(pos) do
		local child = root:FindFirstChild(name)
		if child and child:IsA("GuiObject") then
			child.Position = value
		end
	end
end

local function tweenPositions(root: Frame, targets: {[string]: UDim2}, info: TweenInfo, store: {Tween})
	for name, value in pairs(targets) do
		local child = root and root:FindFirstChild(name)
		if child and child:IsA("GuiObject") then
			local tween = TweenService:Create(child, info, { Position = value })
			tween:Play()
			table.insert(store, tween)
		end
	end
end

local function tweenSize(root: Frame, info: TweenInfo, size: UDim2, store: {Tween})
	if not root then
		return
	end
	local tween = TweenService:Create(root, info, { Size = size })
	tween:Play()
	table.insert(store, tween)
end

-- Type definitions
export type OptionsState = "Hidden" | "BattleOptions" | "MoveOptions" | "Transitioning"

export type BattleOptionsManager = {
	_state: OptionsState,
	_activeTweens: {Tween},
	_callbacks: {
		onFight: (() -> ())?,
		onRun: (() -> ())?,
		onCreatures: (() -> ())?,
		onBag: (() -> ())?,
		onMoveSelected: ((moveIndex: number) -> ())?,
		onBack: (() -> ())?,
	},
	
	-- Public methods
	ShowBattleOptions: (self: BattleOptionsManager) -> (),
	ShowMoveOptions: (self: BattleOptionsManager, creatureData: any, foeCreature: any?) -> (),
	HideAll: (self: BattleOptionsManager) -> (),
	UpdateMoveButtons: (self: BattleOptionsManager, creatureData: any, foeCreature: any?) -> (),
	SetCallbacks: (self: BattleOptionsManager, callbacks: any) -> (),
	GetState: (self: BattleOptionsManager) -> OptionsState,
	IsTransitioning: (self: BattleOptionsManager) -> boolean,
	Cleanup: (self: BattleOptionsManager) -> (),
}

local BattleOptionsManager = {}
BattleOptionsManager.__index = BattleOptionsManager

--[[
	Creates a new BattleOptionsManager instance
]]
function BattleOptionsManager.new(): BattleOptionsManager
	local self = setmetatable({}, BattleOptionsManager)
	
	self._state = "Hidden"
	self._activeTweens = {}
	self._callbacks = {}
	self._interactionEnabled = true
	self._lastClickTime = 0
	self._root = Controller
	self._transitionId = 0
	self._buttons = {
		Fight = Controller:FindFirstChild("Fight"),
		Run = Controller:FindFirstChild("Run"),
		Creatures = Controller:FindFirstChild("Creatures"),
		Bag = Controller:FindFirstChild("Bag"),
		Back = Controller:FindFirstChild("Back"),
		Move1 = Controller:FindFirstChild("Move1"),
		Move2 = Controller:FindFirstChild("Move2"),
		Move3 = Controller:FindFirstChild("Move3"),
		Move4 = Controller:FindFirstChild("Move4"),
	}

	-- Default layout: battle options compact and hidden until requested
	applyPositions(self._root, "BattleOptions")
	self._root.Size = SIZE.Compact
	self._root.Visible = false
	
	-- Connect battle option buttons
	self:_connectBattleOptionButtons()
	
	-- Connect move option buttons
	self:_connectMoveOptionButtons()
	
	print("[BattleOptionsManager] Initialized")
	
	return self
end

--[[
	Shows the battle options menu with slide-in animation
	@param forceShow Whether to force show even if already visible (for state correction)
	@param skipReturnAnim When true, skips the new offscreen→onscreen fade-in (used by Back)
]]
function BattleOptionsManager:ShowBattleOptions(forceShow: boolean?, skipReturnAnim: boolean?)
	if self._state == "Transitioning" and not forceShow then
		warn("[BattleOptionsManager] Cannot show BattleOptions during transition")
		return
	end

	if self._state == "BattleOptions" and not forceShow then
		return
	end

	self._state = "Transitioning"
	self._root.Visible = true
	self:_cancelActiveTweens()
	
	if skipReturnAnim then
		self:_transitionToBattleOptions()
	else
		self:_playBattleOptionsReturnAnim()
	end
end

--[[
	Shows the move options menu with slide-in animation
	@param creatureData The player's active creature
	@param foeCreature The opponent's creature (for effectiveness calculation)
]]
function BattleOptionsManager:ShowMoveOptions(creatureData: any, foeCreature: any?)
	if self._state == "Transitioning" then
		warn("[BattleOptionsManager] Cannot show MoveOptions during transition - queuing show")
		return
	end
	
	if self._state == "MoveOptions" then
		print("[BattleOptionsManager] MoveOptions already visible")
		return
	end
	
	print("[BattleOptionsManager] Showing MoveOptions")

	self._state = "Transitioning"
	self._root.Visible = true
	self:_cancelActiveTweens()
	
	-- Update move buttons before showing
	self:UpdateMoveButtons(creatureData, foeCreature)
	self:_transitionToMoveOptions()
end

--[[
	Hides all option menus
]]
function BattleOptionsManager:HideAll()
	if self._state == "Hidden" then
		return
	end
	
	print("[BattleOptionsManager] Hiding all options")
	
	-- Cancel any active tween first
	self:_cancelActiveTweens()

	self._state = "Hidden"
	if self._root then
		self._root.Visible = false
	end
end

--[[
	Updates move buttons with current creature's moves and type effectiveness
	@param creatureData The player's active creature
	@param foeCreature The opponent's creature (for effectiveness calculation)
]]
function BattleOptionsManager:UpdateMoveButtons(creatureData: any, foeCreature: any?)
    if not creatureData then
        warn("[BattleOptionsManager] No creature data to update")
        return
    end
    
    local moves = creatureData.CurrentMoves or creatureData.Moves or {}
	local foeTypes = {}
	
	-- Get foe types for effectiveness calculation
	if foeCreature and foeCreature.Type then
		foeTypes = self:_getTypeNames(foeCreature.Type)
	end
	
	print("[BattleOptionsManager] Updating move buttons - Moves:", #moves, "Foe types:", #foeTypes)
	
	-- Update each move button (1-4)
	for i = 1, 4 do
		local moveButton = self._buttons["Move" .. i]
		if moveButton then
			local currentMove = moves[i]
			
			if currentMove then
				moveButton.Visible = true
				
				-- CurrentMove is now a string (move name) from server
				local moveName = "Unknown Move"
				local moveType = nil
				local moveData = nil
				
				if type(currentMove) == "string" then
					-- Server sends move name as string
					moveName = currentMove
					moveData = Moves[moveName]
					if moveData then
						moveType = moveData.Type
					else
						warn("[BattleOptionsManager] Move not found in Moves module:", moveName)
					end
				else
					-- Legacy: Match move by properties (fallback for old data)
					warn("[BattleOptionsManager] Received move as table instead of string, using legacy matching")
					for moveKey, data in pairs(Moves) do
						if self:_movesMatch(data, currentMove) then
							moveName = moveKey
							moveType = data.Type
							moveData = data
							break
						end
					end
				end
				
				-- Update move name
				setTextOnFirst(moveButton, {"MoveName"}, moveName)
				
				-- Update move type
				local resolvedTypeName = "Normal"
				local typeData = nil
				if moveType then
					local typeName = self:_getTypeName(moveType)
					if typeName then
						resolvedTypeName = typeName
						typeData = Types[typeName]
					end
				end

				setTextOnFirst(moveButton, {"TypeName", "MoveType", "Type"}, resolvedTypeName)
				
				-- Color move button background and stroke
				if typeData and typeData.uicolor then
					if moveButton:IsA("GuiObject") then
						moveButton.BackgroundColor3 = typeData.uicolor
					end
					if moveButton:IsA("ImageButton") or moveButton:IsA("ImageLabel") then
						moveButton.ImageColor3 = typeData.uicolor
					end

					-- Darken stroke color
					local stroke = moveButton:FindFirstChild("UIStroke")
					if stroke then
						local c = typeData.uicolor
						stroke.Color = Color3.new(
							math.max(0, c.R * 0.6),
							math.max(0, c.G * 0.6),
							math.max(0, c.B * 0.6)
						)
					end
				end
				
				-- Update PP (if implemented)
				local ppLabel = moveButton:FindFirstChild("PP")
				if ppLabel and ppLabel:IsA("TextLabel") then
					-- For now, just hide PP until it's implemented
					ppLabel.Visible = false
				end
				
				-- Update effectiveness indicators
				if moveData then
					self:_updateEffectivenessIndicators(moveButton, moveData, foeTypes)
				end
			else
				-- No move in this slot
				moveButton.Visible = false
			end
		end
	end
end

--[[
	Sets callback functions for button interactions
	@param callbacks Table of callback functions
]]
function BattleOptionsManager:SetCallbacks(callbacks: any)
	self._callbacks = callbacks or {}
	print("[BattleOptionsManager] Callbacks set")
end

--[[
	Gets the current state
	@return Current OptionsState
]]
function BattleOptionsManager:GetState(): OptionsState
	return self._state
end

--[[
	Checks if currently transitioning
	@return True if transitioning
]]
function BattleOptionsManager:IsTransitioning(): boolean
	return self._state == "Transitioning"
end

--[[
	Cleans up the manager
]]
function BattleOptionsManager:Cleanup()
	self:_cancelActiveTweens()
	self:HideAll()
	self._callbacks = {}
	print("[BattleOptionsManager] Cleaned up")
end

--[[]]
-- Enables or disables user interaction with the options UI
-- @param enabled Whether interaction should be enabled
function BattleOptionsManager:SetInteractionEnabled(enabled: boolean)
	self._interactionEnabled = enabled and true or false
end

-- ============================================================================
-- INTERNAL METHODS
-- ============================================================================

--[[
	Internal: Plays the animation from battle options → move options
]]
function BattleOptionsManager:_transitionToMoveOptions()
	self._transitionId += 1
	local token = self._transitionId
	local tweens = self._activeTweens

	applyPositions(self._root, "BattleOptions")
	tweenPositions(self._root, {
		Fight = POSITIONS.MoveOptions.Fight,
		Bag = POSITIONS.MoveOptions.Bag,
		Creatures = POSITIONS.MoveOptions.Creatures,
		Run = POSITIONS.MoveOptions.Run,
	}, TWEEN.Position, tweens)
	tweenSize(self._root, TWEEN.SizeFast, SIZE.Expanded, tweens)

	task.delay(0.15, function()
		if self._transitionId ~= token then return end
		tweenPositions(self._root, {
			Move1 = POSITIONS.MoveOptions.Move1,
			Move2 = POSITIONS.MoveOptions.Move2,
			Move3 = POSITIONS.MoveOptions.Move3,
			Move4 = POSITIONS.MoveOptions.Move4,
			Back = POSITIONS.MoveOptions.Back,
		}, TWEEN.Position, tweens)
		tweenSize(self._root, TWEEN.SizeFast, SIZE.Expanded, tweens)
	end)

	task.delay(0.35, function()
		if self._transitionId ~= token then return end
		tweenSize(self._root, TWEEN.SizeSlow, SIZE.Compact, tweens)
		self._state = "MoveOptions"
	end)
end

--[[
	Internal: Plays the animation from move options → battle options
]]
function BattleOptionsManager:_transitionToBattleOptions()
	self._transitionId += 1
	local token = self._transitionId
	local tweens = self._activeTweens

	applyPositions(self._root, "MoveOptions")
	tweenPositions(self._root, {
		Move1 = POSITIONS.BattleOptions.Move1,
		Move2 = POSITIONS.BattleOptions.Move2,
		Move3 = POSITIONS.BattleOptions.Move3,
		Move4 = POSITIONS.BattleOptions.Move4,
	}, TWEEN.Position, tweens)
	local back = self._buttons.Back
	if back then
		local tween = TweenService:Create(back, TWEEN.Position, { Position = POSITIONS.BattleOptions.Back })
		tween:Play()
		table.insert(tweens, tween)
	end
	tweenSize(self._root, TWEEN.SizeFast, SIZE.Expanded, tweens)

	task.delay(0.35, function()
		if self._transitionId ~= token then return end
		tweenSize(self._root, TWEEN.SizeSlow, SIZE.Compact, tweens)
		tweenPositions(self._root, {
			Fight = POSITIONS.BattleOptions.Fight,
			Bag = POSITIONS.BattleOptions.Bag,
			Creatures = POSITIONS.BattleOptions.Creatures,
			Run = POSITIONS.BattleOptions.Run,
		}, TWEEN.Position, tweens)
		tweenSize(self._root, TWEEN.SizeFast, SIZE.Compact, tweens)
		self._state = "BattleOptions"
	end)
end

--[[
	Internal: Resets all buttons offscreen, fades in controller, and slides battle options on
]]
function BattleOptionsManager:_playBattleOptionsReturnAnim()
	self._transitionId += 1
	local token = self._transitionId
	local tweens = self._activeTweens
	local root = self._root
	if not root then
		return
	end

	-- Force everything offscreen first
	root.Size = SIZE.Compact
	setImageTransparency(root, 1)

	local startPositions = {
		Fight = POSITIONS.MoveOptions.Fight,
		Bag = POSITIONS.MoveOptions.Bag,
		Creatures = POSITIONS.MoveOptions.Creatures,
		Run = POSITIONS.MoveOptions.Run,
		Move1 = POSITIONS.BattleOptions.Move1,
		Move2 = POSITIONS.BattleOptions.Move2,
		Move3 = POSITIONS.BattleOptions.Move3,
		Move4 = POSITIONS.BattleOptions.Move4,
		Back = POSITIONS.BattleOptions.Back,
	}

	for name, pos in pairs(startPositions) do
		local child = root:FindFirstChild(name)
		if child and child:IsA("GuiObject") then
			child.Position = pos
		end
	end

	-- Fade in the controller
	local fadeTween = TweenService:Create(root, FADE_IN, { ImageTransparency = 0 })
	fadeTween:Play()
	table.insert(tweens, fadeTween)

	-- Slide battle options into place
	tweenPositions(root, {
		Fight = POSITIONS.BattleOptions.Fight,
		Bag = POSITIONS.BattleOptions.Bag,
		Creatures = POSITIONS.BattleOptions.Creatures,
		Run = POSITIONS.BattleOptions.Run,
	}, TWEEN.Position, tweens)

	task.delay(FADE_IN.Time, function()
		if self._transitionId ~= token then return end
		self._state = "BattleOptions"
	end)
end

--[[
	Internal: Cancels any active tweens
]]
function BattleOptionsManager:_cancelActiveTweens()
	for _, tween in ipairs(self._activeTweens) do
		if tween then
			pcall(function()
				tween:Cancel()
			end)
		end
	end
	self._activeTweens = {}
end

--[[
	Internal: Connects battle option buttons
]]
function BattleOptionsManager:_connectBattleOptionButtons()
	-- Get UIFunctions for button setup
	local UIFunctions = require(script.Parent.Parent.UI.UIFunctions)
	
	local fightButton = self._buttons.Fight
	local runButton = self._buttons.Run
	local creaturesButton = self._buttons.Creatures
	local bagButton = self._buttons.Bag
	
	-- Fight button
	if fightButton then
		fightButton:SetAttribute("OGSize", fightButton.Size)
		UIFunctions:NewButton(
			fightButton,
			{"Action"},
			{Click = "One", HoverOn = "One", HoverOff = "One"},
			0.7,
			function()
				if not self._interactionEnabled then return end
				if self._state ~= "BattleOptions" then return end
				local now = os.clock()
				if now - (self._lastClickTime or 0) < 0.08 then return end
				self._lastClickTime = now
				print("[BattleOptionsManager] Fight button clicked")
				if self._callbacks.onFight then
					self._callbacks.onFight()
				end
			end
		)
	end
	
	-- Run button
	if runButton then
		runButton:SetAttribute("OGSize", runButton.Size)
		UIFunctions:NewButton(
			runButton,
			{"Action"},
			{Click = "One", HoverOn = "One", HoverOff = "One"},
			0.7,
			function()
				if not self._interactionEnabled then return end
				if self._state ~= "BattleOptions" then return end
				local now = os.clock()
				if now - (self._lastClickTime or 0) < 0.08 then return end
				self._lastClickTime = now
				print("[BattleOptionsManager] Run button clicked")
				if self._callbacks.onRun then
					self._callbacks.onRun()
				end
			end
		)
	end
	
	-- Creatures button
	if creaturesButton then
		creaturesButton:SetAttribute("OGSize", creaturesButton.Size)
		UIFunctions:NewButton(
			creaturesButton,
			{"Action"},
			{Click = "One", HoverOn = "One", HoverOff = "One"},
			0.7,
			function()
				if not self._interactionEnabled then return end
				if self._state ~= "BattleOptions" then return end
				local now = os.clock()
				if now - (self._lastClickTime or 0) < 0.08 then return end
				self._lastClickTime = now
				print("[BattleOptionsManager] Creatures button clicked")
				if self._callbacks.onCreatures then
					self._callbacks.onCreatures()
				end
			end
		)
	end
	
	-- Bag button
	if bagButton then
		bagButton:SetAttribute("OGSize", bagButton.Size)
		UIFunctions:NewButton(
			bagButton,
			{"Action"},
			{Click = "One", HoverOn = "One", HoverOff = "One"},
			0.7,
			function()
				if not self._interactionEnabled then return end
				if self._state ~= "BattleOptions" then return end
				local now = os.clock()
				if now - (self._lastClickTime or 0) < 0.08 then return end
				self._lastClickTime = now
				print("[BattleOptionsManager] Bag button clicked")
				if self._callbacks.onBag then
					self._callbacks.onBag()
				end
			end
		)
	end
	
	print("[BattleOptionsManager] Battle option buttons connected")
end

--[[
	Internal: Connects move option buttons
]]
function BattleOptionsManager:_connectMoveOptionButtons()
	-- Get UIFunctions for button setup
	local UIFunctions = require(script.Parent.Parent.UI.UIFunctions)
	
	-- Connect each move button (1-4)
	for i = 1, 4 do
		local moveButton = self._buttons["Move" .. i]
		if moveButton then
			moveButton:SetAttribute("OGSize", moveButton.Size)
			UIFunctions:NewButton(
				moveButton,
				{"Action"},
				{Click = "One", HoverOn = "One", HoverOff = "One"},
				0.7,
				function()
					if not self._interactionEnabled then return end
					if self._state ~= "MoveOptions" then return end
					local now = os.clock()
					if now - (self._lastClickTime or 0) < 0.15 then return end
					self._lastClickTime = now
					print("[BattleOptionsManager] Move " .. i .. " button clicked")
					if self._callbacks.onMoveSelected then
						self._callbacks.onMoveSelected(i)
					end
				end
			)
		end
	end
	
	-- Connect back button
	local backButton = self._buttons.Back
	if backButton then
		backButton:SetAttribute("OGSize", backButton.Size)
		UIFunctions:NewButton(
			backButton,
			{"Action"},
			{Click = "One", HoverOn = "One", HoverOff = "One"},
			0.7,
			function()
				if not self._interactionEnabled then return end
				local now = os.clock()
				if now - (self._lastClickTime or 0) < 0.08 then return end
				self._lastClickTime = now
				print("[BattleOptionsManager] Back button clicked")
				if self._callbacks.onBack then
					self._callbacks.onBack()
				else
					-- Default: return to battle options
					self:ShowBattleOptions(true, true)
				end
			end
		)
	end
	
	print("[BattleOptionsManager] Move option buttons connected")
end

--[[
	Internal: Updates effectiveness indicators on a move button
	@param moveButton The move button to update
	@param moveData The move data from Moves module
	@param foeTypes Array of foe type tables
]]
function BattleOptionsManager:_updateEffectivenessIndicators(
	moveButton: Frame,
	moveData: any,
	foeTypes: {any}
)
	local seIcon = moveButton:FindFirstChild("SuperEffective")
	local nveIcon = moveButton:FindFirstChild("NotVeryEffective")
	
	-- Hide both by default
	if seIcon then
		seIcon.Visible = false
	end
	if nveIcon then
		nveIcon.Visible = false
	end
	
	-- If no foe types or no move type, can't calculate effectiveness
	if not moveData.Type or #foeTypes == 0 then
		return
	end
	
	local moveType = moveData.Type
	
	-- Find move type name
	local moveTypeName = self:_getTypeName(moveType)
	if not moveTypeName then
		return
	end
	
	-- Get move type data from Types module
	local moveTypeData = Types[moveTypeName]
	if not moveTypeData then
		return
	end
	
	-- Calculate effectiveness
	local result = "neutral"
	for _, foeType in ipairs(foeTypes) do
		local foeTypeName = self:_getTypeName(foeType)
		if foeTypeName then
			-- Check super effective
			if table.find(moveTypeData.strongTo, foeTypeName) then
				result = "se"
				break
			end
			
			-- Check not very effective or immune
			if table.find(moveTypeData.resist, foeTypeName) or table.find(moveTypeData.immuneTo, foeTypeName) then
				if result ~= "se" then
					result = "nve"
				end
			end
		end
	end
	
	-- Show appropriate icon
	if result == "se" and seIcon then
		seIcon.Visible = true
	elseif result == "nve" and nveIcon then
		nveIcon.Visible = true
	end
end

--[[
	Internal: Gets the type name from a type table reference
	@param typeRef The type table reference
	@return Type name string or nil
]]
function BattleOptionsManager:_getTypeName(typeRef: any): string?
	if not typeRef then
		return nil
	end
	
	-- Iterate through Types module to find matching reference
	for typeName, typeData in pairs(Types) do
		if typeData == typeRef then
			return typeName
		end
	end
	
	return nil
end

--[[
	Internal: Gets type names from an array of type references
	@param typeRefs Array of type table references
	@return Array of type name strings
]]
function BattleOptionsManager:_getTypeNames(typeRefs: any): {string}
	local names = {}
	
	if type(typeRefs) ~= "table" then
		return names
	end
	
	for _, typeRef in ipairs(typeRefs) do
		if type(typeRef) == "string" then
			table.insert(names, typeRef)
		elseif type(typeRef) == "table" then
			local typeName = self:_getTypeName(typeRef)
			if typeName then
				table.insert(names, typeName)
			end
		end
	end
	
	return names
end

--[[
	Internal: Checks if two moves match by comparing their properties
	@param move1 First move data
	@param move2 Second move data
	@return True if moves match
]]
function BattleOptionsManager:_movesMatch(move1: any, move2: any): boolean
	if not move1 or not move2 then
		return false
	end
	
	-- Compare BasePower
	local powerMatch = move1.BasePower == move2.BasePower
	
	-- Compare Accuracy
	local accuracyMatch = move1.Accuracy == move2.Accuracy
	
	-- Compare Priority
	local priorityMatch = move1.Priority == move2.Priority
	
	-- Compare Type (by uicolor since they're table references)
	local typeMatch = false
	if move1.Type and move2.Type then
		if move1.Type.uicolor and move2.Type.uicolor then
			typeMatch = move1.Type.uicolor == move2.Type.uicolor
		end
	elseif not move1.Type and not move2.Type then
		typeMatch = true
	end
	
	return powerMatch and accuracyMatch and priorityMatch and typeMatch
end

return BattleOptionsManager

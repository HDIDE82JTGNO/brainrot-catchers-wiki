--[[
	BattleOptionsManager.lua
	
	Manages battle option menus (BattleOptions and MoveOptions) with clean state management,
	smooth animations, and event-driven design.
	
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

-- Import modules
local Types = require(ReplicatedStorage.Shared.Types)
local Moves = require(ReplicatedStorage.Shared.Moves)

-- UI References
local BattleOptions = BattleUI:WaitForChild("BattleOptions")
local MoveOptions = BattleUI:WaitForChild("MoveOptions")

-- Type definitions
export type OptionsState = "Hidden" | "BattleOptions" | "MoveOptions" | "Transitioning"

export type BattleOptionsManager = {
	_state: OptionsState,
	_activeTween: Tween?,
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
	self._activeTween = nil
	self._callbacks = {}
	self._interactionEnabled = true
	self._lastClickTime = 0
	
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
]]
function BattleOptionsManager:ShowBattleOptions(forceShow: boolean?)
	if self._state == "Transitioning" then
		warn("[BattleOptionsManager] Cannot show BattleOptions during transition - queuing show")
		local active = self._activeTween
		if active then
			local conn
			conn = active.Completed:Connect(function()
				if conn then conn:Disconnect() end
				self:ShowBattleOptions(true)
			end)
		else
			task.defer(function()
				self:ShowBattleOptions(true)
			end)
		end
		return
	end
	
	if self._state == "BattleOptions" and not forceShow then
		print("[BattleOptionsManager] BattleOptions already visible")
		-- Check if UI is actually visible, if not, force show
		if not BattleOptions.Visible then
			print("[BattleOptionsManager] State says visible but UI is hidden - forcing show")
			forceShow = true
		else
			return
		end
	end
	
	print("[BattleOptionsManager] Showing BattleOptions")
	
	-- Hide move options first if visible
	if self._state == "MoveOptions" then
		self:_hideMoveOptions(true) -- Skip cross-fade
	end
	
	self._state = "Transitioning"
	self:_cancelActiveTween()
	
	-- Set initial position (off-screen right)
	BattleOptions.Visible = true
	BattleOptions.Position = UDim2.new(1.3, 0, 0.165, 0)
	
	-- Slide in
	local slideInInfo = TweenInfo.new(0.35, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
	self._activeTween = TweenService:Create(
		BattleOptions,
		slideInInfo,
		{Position = UDim2.new(0.778, 0, 0.165, 0)}
	)
	
	self._activeTween.Completed:Connect(function()
		self._activeTween = nil
		self._state = "BattleOptions"
		print("[BattleOptionsManager] BattleOptions visible")
	end)
	
	self._activeTween:Play()
end

--[[
	Shows the move options menu with slide-in animation
	@param creatureData The player's active creature
	@param foeCreature The opponent's creature (for effectiveness calculation)
]]
function BattleOptionsManager:ShowMoveOptions(creatureData: any, foeCreature: any?)
	if self._state == "Transitioning" then
		warn("[BattleOptionsManager] Cannot show MoveOptions during transition - queuing show")
		local active = self._activeTween
		if active then
			local conn
			conn = active.Completed:Connect(function()
				if conn then conn:Disconnect() end
				self:ShowMoveOptions(creatureData, foeCreature)
			end)
		else
			task.defer(function()
				self:ShowMoveOptions(creatureData, foeCreature)
			end)
		end
		return
	end
	
	if self._state == "MoveOptions" then
		print("[BattleOptionsManager] MoveOptions already visible")
		return
	end
	
	print("[BattleOptionsManager] Showing MoveOptions")
	
	-- Hide battle options first if visible
	if self._state == "BattleOptions" then
		self:_hideBattleOptions(true) -- Skip cross-fade
	end
	
	self._state = "Transitioning"
	self:_cancelActiveTween()
	
	-- Update move buttons before showing
	self:UpdateMoveButtons(creatureData, foeCreature)
	
	-- Set initial position (off-screen right)
	MoveOptions.Visible = true
	MoveOptions.Position = UDim2.new(1.3, 0, 0.165, 0)
	
	-- Slide in
	local slideInInfo = TweenInfo.new(0.35, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
	self._activeTween = TweenService:Create(
		MoveOptions,
		slideInInfo,
		{Position = UDim2.new(0.778, 0, 0.165, 0)}
	)
	
	self._activeTween.Completed:Connect(function()
		self._activeTween = nil
		self._state = "MoveOptions"
		print("[BattleOptionsManager] MoveOptions visible")
	end)
	
	self._activeTween:Play()
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
	self:_cancelActiveTween()
	
	if self._state == "BattleOptions" then
		self:_hideBattleOptions(false)
	elseif self._state == "MoveOptions" then
		self:_hideMoveOptions(false)
	else
		-- If in transitioning state or unknown state, force hide and reset
		print("[BattleOptionsManager] Force hiding and resetting state")
		BattleOptions.Visible = false
		MoveOptions.Visible = false
		self._state = "Hidden"
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
		local moveButton = MoveOptions:FindFirstChild("Move" .. i)
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
				local nameLabel = moveButton:FindFirstChild("MoveName")
				if nameLabel and nameLabel:IsA("TextLabel") then
					nameLabel.Text = moveName
				end
				
				-- Update move type
				local typeLabel = moveButton:FindFirstChild("MoveType")
				if typeLabel and typeLabel:IsA("TextLabel") then
					if moveType then
						-- Find type name
						local typeName = self:_getTypeName(moveType)
						typeLabel.Text = typeName or "Normal"
					else
						typeLabel.Text = "Normal"
					end
				end
				
				-- Color move button background and stroke
				if moveType then
					local typeName = self:_getTypeName(moveType)
					local typeData = typeName and Types[typeName]
					if typeData and typeData.uicolor then
						moveButton.BackgroundColor3 = typeData.uicolor
						
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
	self:_cancelActiveTween()
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
	Internal: Hides battle options with slide-out animation
	@param skipCrossFade Whether to skip cross-fade logic
]]
function BattleOptionsManager:_hideBattleOptions(skipCrossFade: boolean)
	if not skipCrossFade then
		self._state = "Transitioning"
	end
	
	self:_cancelActiveTween()
	
	-- Slide out
	local slideOutInfo = TweenInfo.new(0.35, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
	self._activeTween = TweenService:Create(
		BattleOptions,
		slideOutInfo,
		{Position = UDim2.new(1.3, 0, 0.165, 0)}
	)
	
	self._activeTween.Completed:Connect(function()
		BattleOptions.Visible = false
		self._activeTween = nil
		if not skipCrossFade then
			self._state = "Hidden"
			print("[BattleOptionsManager] BattleOptions hidden")
		end
	end)
	
	self._activeTween:Play()
end

--[[
	Internal: Hides move options with slide-out animation
	@param skipCrossFade Whether to skip cross-fade logic
]]
function BattleOptionsManager:_hideMoveOptions(skipCrossFade: boolean)
	if not skipCrossFade then
		self._state = "Transitioning"
	end
	
	self:_cancelActiveTween()
	
	-- Slide out
	local slideOutInfo = TweenInfo.new(0.35, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
	self._activeTween = TweenService:Create(
		MoveOptions,
		slideOutInfo,
		{Position = UDim2.new(1.3, 0, 0.165, 0)}
	)
	
	self._activeTween.Completed:Connect(function()
		MoveOptions.Visible = false
		self._activeTween = nil
		if not skipCrossFade then
			self._state = "Hidden"
			print("[BattleOptionsManager] MoveOptions hidden")
		end
	end)
	
	self._activeTween:Play()
end

--[[
	Internal: Cancels the active tween if any
]]
function BattleOptionsManager:_cancelActiveTween()
	if self._activeTween then
		pcall(function()
			self._activeTween:Cancel()
		end)
		self._activeTween = nil
	end
end

--[[
	Internal: Connects battle option buttons
]]
function BattleOptionsManager:_connectBattleOptionButtons()
	-- Get UIFunctions for button setup
	local UIFunctions = require(script.Parent.Parent.UI.UIFunctions)
	
	local fightButton = BattleOptions:FindFirstChild("Fight")
	local runButton = BattleOptions:FindFirstChild("Run")
	local creaturesButton = BattleOptions:FindFirstChild("Creatures")
	local bagButton = BattleOptions:FindFirstChild("Bag")
	
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
		local moveButton = MoveOptions:FindFirstChild("Move" .. i)
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
	local backButton = MoveOptions:FindFirstChild("Back")
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
					self:ShowBattleOptions(true)
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

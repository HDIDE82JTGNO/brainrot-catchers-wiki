--!strict
--[[
	PartyIntegration.lua
	Handles party menu integration for battle creature switching
	Manages both voluntary and forced switches with proper UI flow
	
	Professional OOP implementation with:
	- Proper metatable-based inheritance
	- Complete Luau type annotations
	- Event-driven architecture
	- No global variables or _G usage
	- Clean separation of concerns
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local GameUI = PlayerGui:WaitForChild("GameUI")

-- Require Party module from the codebase
local Party = require(script.Parent.Parent.UI.Party)

-- Type definitions
export type CreatureData = {
	Name: string,
	Nickname: string?,
	CurrentHP: number?,
	Stats: {
		HP: number
	}?
}

export type BattleState = {
	PlayerCreatureIndex: number
}

export type ActionHandler = {
	RequestSwitch: (number) -> ()
}

export type PartyModule = {
	Open: (() -> ())?,
	Close: (() -> ())?,
	SetSelectionChangedCallback: ((CreatureData?, number?) -> ())?
}

export type SwitchCallback = (number) -> ()
export type CancellationCallback = () -> ()

export type PartyIntegrationType = {
	-- Public methods
	OnSwitchComplete: (self: PartyIntegrationType, callback: SwitchCallback) -> (),
	OnSwitchCancelled: (self: PartyIntegrationType, callback: CancellationCallback) -> (),
	OpenForVoluntarySwitch: (self: PartyIntegrationType) -> (),
	OpenForForcedSwitch: (self: PartyIntegrationType) -> (),
	Close: (self: PartyIntegrationType) -> (),
	IsOpen: (self: PartyIntegrationType) -> boolean,
	GetSwitchMode: (self: PartyIntegrationType) -> string?,
	HandleCancellation: (self: PartyIntegrationType) -> (),
	
	-- Private methods
	_setupSelectionCallback: (self: PartyIntegrationType) -> (),
	_onCreatureSelected: (self: PartyIntegrationType, creatureData: CreatureData?, slotIndex: number?) -> (),
	_updateSendOutButton: (self: PartyIntegrationType, creatureData: CreatureData, slotIndex: number) -> (),
	_onSendOutClicked: (self: PartyIntegrationType) -> (),
	_onCancelClicked: (self: PartyIntegrationType) -> (),
	_validateSelection: (self: PartyIntegrationType, creatureData: CreatureData, slotIndex: number) -> boolean,
	_initializeUI: (self: PartyIntegrationType) -> (),
	_setupButtonHandlers: (self: PartyIntegrationType) -> (),
	_cleanupButtonHandlers: (self: PartyIntegrationType) -> (),
	_setButtonVisibility: (self: PartyIntegrationType, visible: boolean) -> (),
	
	-- Private fields
	_battleState: BattleState,
	_actionHandler: ActionHandler,
	_partyModule: PartyModule,
	_isOpen: boolean,
	_switchMode: string?,
	_selectedCreatureData: CreatureData?,
	_selectedSlotIndex: number?,
	_callbacks: {
		onSwitchComplete: SwitchCallback?,
		onSwitchCancelled: CancellationCallback?
	},
	_uiElements: {
		sendOutButton: TextButton?,
		cancelButton: TextButton?,
		sendOutCreatureText: TextLabel?,
		sendOutCreatureIcon: ImageLabel?,
		sendOutUIStroke: UIStroke?
	},
	_connections: {
		sendOutConnection: boolean?,
		cancelConnection: boolean?
	}
}

local PartyIntegration = {}
PartyIntegration.__index = PartyIntegration

--[[
	Creates a new party integration instance
	@param battleState The battle state reference
	@param actionHandler The action handler reference
	@return PartyIntegrationType
]]
function PartyIntegration.new(battleState: BattleState, actionHandler: ActionHandler): PartyIntegrationType
	local self = setmetatable({}, PartyIntegration) :: PartyIntegrationType
	
	-- Initialize core references
	self._battleState = battleState
	self._actionHandler = actionHandler
	self._partyModule = Party :: PartyModule
	
	-- Initialize state
	self._isOpen = false
	self._switchMode = nil
	self._selectedCreatureData = nil
	self._selectedSlotIndex = nil
	
	-- Initialize callbacks
	self._callbacks = {
		onSwitchComplete = nil,
		onSwitchCancelled = nil
	}
	
	-- Initialize UI elements
	self._uiElements = {
		sendOutButton = nil,
		cancelButton = nil,
		sendOutCreatureText = nil,
		sendOutCreatureIcon = nil,
		sendOutUIStroke = nil
	}
	
	-- Initialize connections
	self._connections = {
		sendOutConnection = nil,
		cancelConnection = nil
	}
	
	-- Initialize UI elements
	self:_initializeUI()
	
	return self
end

--[[
	Sets the switch complete callback
	@param callback Function to call when switch completes
]]
function PartyIntegration:OnSwitchComplete(callback: SwitchCallback)
	self._callbacks.onSwitchComplete = callback
end

--[[
	Sets the switch cancelled callback
	@param callback Function to call when switch is cancelled
]]
function PartyIntegration:OnSwitchCancelled(callback: CancellationCallback)
	self._callbacks.onSwitchCancelled = callback
end

--[[
	Opens party menu for voluntary switch
]]
function PartyIntegration:OpenForVoluntarySwitch(isPreviewSwitch: boolean?)
	if not self._partyModule then
		warn("[PartyIntegration] Party module not found")
		return
	end
	
	if self._isOpen then
		warn("[PartyIntegration] Party already open")
		return
	end
	
	print("[PartyIntegration] Opening party for voluntary switch - Preview:", isPreviewSwitch or false)
	
	self._switchMode = "Voluntary"
	self._isPreviewSwitch = isPreviewSwitch or false
	self._isOpen = true

	-- Refresh UI references in case Party UI wasn't ready at construction time
	self:_initializeUI()
	
	-- Set up UI and button handlers
	self:_setButtonVisibility(true)
	self:_setupButtonHandlers()
	self:_setupSelectionCallback()
	
	-- Open party menu
	if self._partyModule.Open then
		self._partyModule:Open("Battle")
		-- Re-acquire UI elements after opening to ensure references are valid, then (idempotently) wire handlers
		self:_initializeUI()
		self:_setButtonVisibility(true)
		self:_setupButtonHandlers()
	end
end

--[[
	Opens party menu for forced switch (after fainting)
]]
function PartyIntegration:OpenForForcedSwitch()
	if not self._partyModule then
		warn("[PartyIntegration] Party module not found")
		return
	end
	
	if self._isOpen then
		warn("[PartyIntegration] Party already open")
		return
	end
	
	print("[PartyIntegration] Opening party for forced switch")
	
	self._switchMode = "Forced"
	self._isOpen = true

	-- Refresh UI references in case Party UI wasn't ready at construction time
	self:_initializeUI()
	
	-- Set up UI and button handlers
	self:_setButtonVisibility(true)
	self:_setupButtonHandlers()
	self:_setupSelectionCallback()
	
	-- Open party menu
	if self._partyModule.Open then
		self._partyModule:Open("Battle")
		-- Re-acquire UI elements after opening to ensure references are valid, then (idempotently) wire handlers
		self:_initializeUI()
		self:_setButtonVisibility(true)
		self:_setupButtonHandlers()
	end
end

--[[
	Closes the party menu
]]
function PartyIntegration:Close()
	if not self._partyModule then
		return
	end
	
	print("[PartyIntegration] Closing party menu")
	
	-- Reset state
	self._isOpen = false
	self._switchMode = nil
	self._selectedCreatureData = nil
	self._selectedSlotIndex = nil
	
	-- Clean up UI and connections
	self:_cleanupButtonHandlers()
	self:_setButtonVisibility(false)

	-- Defensive: ensure SendOut button is hidden and inactive regardless of Party state
	if self._uiElements and self._uiElements.sendOutButton then
		self._uiElements.sendOutButton.Visible = false
		self._uiElements.sendOutButton.Active = false
		self._uiElements.sendOutButton.BackgroundTransparency = 1
	end
	
	-- Close party menu
	if self._partyModule.Close then
		self._partyModule:Close()
	end

	-- Detach selection callback to prevent overworld Party from invoking battle-only handlers
	if self._partyModule and self._partyModule.SetSelectionChangedCallback then
		pcall(function()
			self._partyModule:SetSelectionChangedCallback(function() end)
		end)
	end
end

--[[
	Checks if party menu is open
	@return boolean True if open
]]
function PartyIntegration:IsOpen(): boolean
	return self._isOpen
end

--[[
	Gets the current switch mode
	@return string? The switch mode
]]
function PartyIntegration:GetSwitchMode(): string?
	return self._switchMode
end

--[[
	Handles cancellation of switch
]]
function PartyIntegration:HandleCancellation()
	print("[PartyIntegration] Switch cancelled")
	
	self:Close()
	
	-- Trigger callback
	if self._callbacks.onSwitchCancelled then
		print("[PartyIntegration] Triggering onSwitchCancelled callback")
		self._callbacks.onSwitchCancelled()
	else
		warn("[PartyIntegration] No onSwitchCancelled callback set!")
	end
end

--[[
	Internal: Initializes UI element references
]]
function PartyIntegration:_initializeUI()
    local PartyUI = GameUI:FindFirstChild("Party")
    if not PartyUI then
        warn("[PartyIntegration] Party UI not found in GameUI")
        return
    end
    
    -- Find battle buttons (search recursively to tolerate layout differences)
    local function deepFind(root: Instance, name: string): Instance?
        return root:FindFirstChild(name, true)
    end
    self._uiElements.sendOutButton = (deepFind(PartyUI, "SendOut") :: TextButton?)
    self._uiElements.cancelButton = (deepFind(PartyUI, "Cancel") :: TextButton?)
    
    -- Find SendOut button sub-elements
    if self._uiElements.sendOutButton then
        self._uiElements.sendOutCreatureText = (self._uiElements.sendOutButton:FindFirstChild("SendOutCreatureText") or deepFind(self._uiElements.sendOutButton, "SendOutCreatureText")) :: TextLabel?
        self._uiElements.sendOutCreatureIcon = (self._uiElements.sendOutButton:FindFirstChild("CreatureIcon") or deepFind(self._uiElements.sendOutButton, "CreatureIcon")) :: ImageLabel?
        self._uiElements.sendOutUIStroke = self._uiElements.sendOutButton:FindFirstChildOfClass("UIStroke") :: UIStroke?
    end
    
    print("[PartyIntegration] UI initialized - SendOut:", self._uiElements.sendOutButton ~= nil, "Cancel:", self._uiElements.cancelButton ~= nil)
end

--[[
	Internal: Sets up button click handlers using UIFunctions
]]
function PartyIntegration:_setupButtonHandlers()
	-- Get UIFunctions for proper button setup
	local UIFunctions = require(script.Parent.Parent.UI.UIFunctions)
	
	-- Set up SendOut button handler
	if self._uiElements.sendOutButton and not self._connections.sendOutConnection then
		-- Set up button with UIFunctions
		UIFunctions:NewButton(
			self._uiElements.sendOutButton,
			{"Action"},
			{Click = "One", HoverOn = "One", HoverOff = "One"},
			0.7,
			function()
				self:_onSendOutClicked()
			end
		)
		
		-- Mark as connected to prevent duplicate setup
		self._connections.sendOutConnection = true
		print("[PartyIntegration] SendOut button handler connected via UIFunctions")
	end
	
	-- Set up Cancel button handler
	if self._uiElements.cancelButton and not self._connections.cancelConnection then
		-- Set up button with UIFunctions
		UIFunctions:NewButton(
			self._uiElements.cancelButton,
			{"Action"},
			{Click = "One", HoverOn = "One", HoverOff = "One"},
			0.7,
			function()
				self:_onCancelClicked()
			end
		)
		
		-- Mark as connected to prevent duplicate setup
		self._connections.cancelConnection = true
		print("[PartyIntegration] Cancel button handler connected via UIFunctions")
	end
end

--[[
	Internal: Cleans up button click handlers
]]
function PartyIntegration:_cleanupButtonHandlers()
	-- Get UIFunctions for proper cleanup
	local UIFunctions = require(script.Parent.Parent.UI.UIFunctions)
	
	-- Clean up SendOut button
	if self._uiElements.sendOutButton and self._connections.sendOutConnection then
		UIFunctions:ClearConnection(self._uiElements.sendOutButton)
		self._connections.sendOutConnection = nil
		print("[PartyIntegration] SendOut button connection cleared")
	end
	
	-- Clean up Cancel button
	if self._uiElements.cancelButton and self._connections.cancelConnection then
		UIFunctions:ClearConnection(self._uiElements.cancelButton)
		self._connections.cancelConnection = nil
		print("[PartyIntegration] Cancel button connection cleared")
	end
end

--[[
	Internal: Sets button visibility and state
	@param visible Whether buttons should be visible
]]
function PartyIntegration:_setButtonVisibility(visible: boolean)
	-- SendOut button starts hidden, only shown when creature selected
	if self._uiElements.sendOutButton then
		self._uiElements.sendOutButton.Visible = false
		self._uiElements.sendOutButton.Active = false
		self._uiElements.sendOutButton.BackgroundTransparency = 1
	end
	
	-- Cancel button visibility depends on switch mode
	if self._uiElements.cancelButton then
		local cancelVisible = visible and self._switchMode == "Voluntary"
		self._uiElements.cancelButton.Visible = cancelVisible
		self._uiElements.cancelButton.Active = cancelVisible
		self._uiElements.cancelButton.BackgroundTransparency = cancelVisible and 0 or 1
	end
end

--[[
	Internal: Sets up the party selection callback
]]
function PartyIntegration:_setupSelectionCallback()
	if not self._partyModule then
		return
	end
	
	-- Create callback function
	local callback = function(creatureData: CreatureData?, slotIndex: number?)
		self:_onCreatureSelected(creatureData, slotIndex)
	end
	
	-- Set callback in party module
	if self._partyModule.SetSelectionChangedCallback then
		self._partyModule:SetSelectionChangedCallback(callback)
	end
end

--[[
	Internal: Handles creature selection from party
	@param creatureData The selected creature data
	@param slotIndex The selected party index
]]
function PartyIntegration:_onCreatureSelected(creatureData: CreatureData, slotIndex: number)
	-- Ignore selections when PartyIntegration is not actively open for a battle switch
	if self._isOpen ~= true or self._switchMode == nil then
		return
	end
	
	-- Handle nil values for clearing selection (when summary is closed via BACK button)
	if creatureData == nil or slotIndex == nil then
		print("[PartyIntegration] Clearing selection (summary closed)")
		self._selectedCreatureData = nil
		self._selectedSlotIndex = nil
		
		-- Hide SendOut button when selection is cleared
		if self._uiElements.sendOutButton then
			self._uiElements.sendOutButton.Visible = false
			self._uiElements.sendOutButton.Active = false
			self._uiElements.sendOutButton.BackgroundTransparency = 1
			print("[PartyIntegration] SendOut button hidden (selection cleared)")
		end
		return
	end
	
	print("[PartyIntegration] Creature selected:", creatureData and creatureData.Name or "nil", "Slot:", slotIndex)
	print("[PartyIntegration] Previous selection - Creature:", self._selectedCreatureData and self._selectedCreatureData.Name or "nil", "Slot:", self._selectedSlotIndex)
	
	-- Store the selected creature for SendOut button (always store, even if invalid)
	self._selectedCreatureData = creatureData
	self._selectedSlotIndex = slotIndex
	
	print("[PartyIntegration] New selection stored - Creature:", self._selectedCreatureData and self._selectedCreatureData.Name or "nil", "Slot:", self._selectedSlotIndex)
	
	-- Show SendOut button now that a creature is selected (always show, even for invalid selections)
	if self._uiElements.sendOutButton then
		self._uiElements.sendOutButton.Visible = true
		self._uiElements.sendOutButton.Active = true
		self._uiElements.sendOutButton.BackgroundTransparency = 0
		print("[PartyIntegration] SendOut button made visible")
	end
	
	-- Update SendOut button appearance with creature data (always update, shows validity state)
	self:_updateSendOutButton(creatureData, slotIndex)
	
	-- Log validation result for debugging
	local isValid = self:_validateSelection(creatureData, slotIndex)
	print("[PartyIntegration] Selection valid:", isValid)
end

--[[
	Internal: Updates SendOut button appearance with creature data
	@param creatureData The selected creature data
	@param slotIndex The selected slot index
]]
function PartyIntegration:_updateSendOutButton(creatureData: CreatureData, slotIndex: number)
	if not self._uiElements.sendOutButton or not self._uiElements.sendOutCreatureText then
		return
	end
	
	-- Determine button text and validity based on legacy logic
	local buttonText: string
	local isValid: boolean = false
	
	-- Check if creature is alive (using same logic as legacy)
	local hpPercent = creatureData.CurrentHP
	local hpLegacy = creatureData.Stats and creatureData.Stats.HP
	local isAlive = (hpPercent == nil and (hpLegacy == nil or hpLegacy > 0)) or (type(hpPercent) == "number" and hpPercent > 0)
	
	if creatureData and isAlive then
		-- Check if it's not the current creature (compare slot indices)
		if self._battleState and self._battleState.PlayerCreatureIndex and slotIndex ~= self._battleState.PlayerCreatureIndex then
			-- Valid switch - not current creature
			isValid = true
			local displayName = creatureData.Nickname or creatureData.Name
			buttonText = "Send out " .. displayName
		else
			-- Already out - current creature
			buttonText = "Already out!"
		end
	else
		-- Fainted creature
		buttonText = "Fainted"
	end
	
	-- Update button text
	self._uiElements.sendOutCreatureText.Text = buttonText
	
	-- Update button colors based on validity (legacy colors)
	if self._uiElements.sendOutUIStroke then
		if isValid then
			-- Valid blue colors
			self._uiElements.sendOutButton.BackgroundColor3 = Color3.fromRGB(64, 224, 255)
			self._uiElements.sendOutUIStroke.Color = Color3.fromRGB(17, 60, 68)
		else
			-- Invalid red colors
			self._uiElements.sendOutButton.BackgroundColor3 = Color3.fromRGB(255, 61, 61)
			self._uiElements.sendOutUIStroke.Color = Color3.fromRGB(79, 19, 19)
		end
	end
	
	-- Update text stroke color
	local textStroke = self._uiElements.sendOutCreatureText:FindFirstChildOfClass("UIStroke")
	if textStroke then
		textStroke.Color = isValid and Color3.fromRGB(17, 60, 68) or Color3.fromRGB(79, 19, 19)
	end
	
	-- Update creature icon (always show, regardless of validity)
	if self._uiElements.sendOutCreatureIcon and creatureData then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local Creatures = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Creatures"))
		local baseCreature = Creatures[creatureData.Name]
		if baseCreature and baseCreature.Sprite then
			self._uiElements.sendOutCreatureIcon.Image = baseCreature.Sprite
		else
			warn("[PartyIntegration] No sprite found for creature:", creatureData.Name)
			self._uiElements.sendOutCreatureIcon.Image = ""
		end
	end
	
	print("[PartyIntegration] SendOut button updated - Text:", buttonText, "Valid:", isValid)
end

--[[
	Internal: Handles SendOut button click
]]
function PartyIntegration:_onSendOutClicked()
	print("[PartyIntegration] SendOut button clicked - Selected creature:", self._selectedCreatureData and self._selectedCreatureData.Name or "nil", "Slot:", self._selectedSlotIndex)
	
	if not self._selectedCreatureData or not self._selectedSlotIndex then
		warn("[PartyIntegration] No creature selected for SendOut")
		return
	end
	
	-- Validate selection before proceeding
	if not self:_validateSelection(self._selectedCreatureData, self._selectedSlotIndex) then
		print("[PartyIntegration] SendOut button clicked but selection is invalid - ignoring")
		return
	end
	
	print("[PartyIntegration] SendOut button clicked - Switching to:", self._selectedCreatureData.Name, "Slot:", self._selectedSlotIndex)
	
	-- Store selection before closing (since Close() clears it)
	local selectedSlotIndex = self._selectedSlotIndex
	
	-- Close party menu (this will clear the selection)
	self:Close()
	
	-- For preview switches, skip ActionHandler and let callback handle the request
	if not self._isPreviewSwitch then
		-- Request switch via action handler using stored selection
		if self._actionHandler then
			print("[PartyIntegration] Calling ActionHandler:RequestSwitch with slot:", selectedSlotIndex)
			self._actionHandler:RequestSwitch(selectedSlotIndex)
		else
			warn("[PartyIntegration] No action handler available")
		end
	else
		print("[PartyIntegration] Preview switch - skipping ActionHandler, will be handled by callback")
	end
	
	-- Trigger callback
	if self._callbacks.onSwitchComplete then
		self._callbacks.onSwitchComplete(selectedSlotIndex)
	end
	
	-- Clear preview switch flag
	self._isPreviewSwitch = false
end

--[[
	Internal: Handles Cancel button click
]]
function PartyIntegration:_onCancelClicked()
	print("[PartyIntegration] Cancel button clicked")
	print("[PartyIntegration] Callbacks available:", self._callbacks.onSwitchCancelled ~= nil)
	self:HandleCancellation()
end

--[[
	Internal: Validates creature selection
	@param creatureData The selected creature data
	@param slotIndex The selected party index
	@return boolean True if valid
]]
function PartyIntegration:_validateSelection(creatureData: CreatureData, slotIndex: number): boolean
	if not self._battleState or not creatureData or not slotIndex then
		return false
	end
	
	-- Can't select current creature (unless forced switch)
	if slotIndex == self._battleState.PlayerCreatureIndex and self._switchMode ~= "Forced" then
		warn("[PartyIntegration] Cannot switch to current creature")
		return false
	end
	
	-- Check if creature is fainted
	local hpPercent = creatureData.CurrentHP
	local hpLegacy = creatureData.Stats and creatureData.Stats.HP
	local isFainted = (hpPercent ~= nil and hpPercent <= 0) or (hpLegacy ~= nil and hpLegacy <= 0)
	
	if isFainted then
		warn("[PartyIntegration] Cannot switch to fainted creature")
		return false
	end
	
	return true
end

return PartyIntegration
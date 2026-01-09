--!nocheck
local MysteryTrade = {}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Events = ReplicatedStorage:WaitForChild("Events")
local Request = Events:WaitForChild("Request")
local Communicate = Events:WaitForChild("Communicate")

-- Modules
local Say = require(script.Parent.Parent.Utilities:WaitForChild("Say"))
local ClientData = require(script.Parent.Parent:WaitForChild("Plugins"):WaitForChild("ClientData"))
local CharacterFunctions = require(script.Parent.Parent.Utilities:WaitForChild("CharacterFunctions"))

-- State machine states
local STATE_IDLE = "Idle"
local STATE_SEARCHING = "Searching"
local STATE_SELECTING = "Selecting"
local STATE_CONFIRMING = "Confirming"
local STATE_WAITING = "Waiting"
local STATE_COOLDOWN = "Cooldown"

-- State tracking
local _state = STATE_IDLE
local _selectedCreature = nil
local _selectedLocation = nil
local _sessionId = nil
local _partnerName = nil
local _cooldownEnd = 0
local _isConfirming = false -- Prevent double-clicks on confirm

-- Get UI reference
local function getUI()
	local ok, UI = pcall(function()
		return require(script.Parent.Parent.UI)
	end)
	return ok and UI or nil
end

-- Get current state
function MysteryTrade:GetState(): string
	return _state
end

-- Set state
function MysteryTrade:SetState(newState: string)
	_state = newState
end

-- Check if can start trade
function MysteryTrade:CanStartTrade(): boolean
	return _state == STATE_IDLE
end

-- Start Mystery Trade
function MysteryTrade:StartTrade()
	if not self:CanStartTrade() then
		return
	end
	
	-- Show explanation
	Say:Say("System", true, {"Mystery Trade allows you to send one creature and receive a random one from another player."})
	
	-- Ask for confirmation
	Say:Say("System", false, {"Start searching for a trade?"})
	local choice = Say:YieldChoice()
	Say:Exit()
	
	if choice ~= true then
		local UI = getUI()
		if UI and UI.TopBar then
			UI.TopBar:Show()
		end
		CharacterFunctions:CanMove(true)
		return
	end
	
	-- Suppress TopBar and disable movement for the duration of the trade
	local UI = getUI()
	if UI and UI.TopBar then
		UI.TopBar:SetSuppressed(true)
	end
	CharacterFunctions:CanMove(false)
	
	-- Start search
	self:SetState(STATE_SEARCHING)
	
	-- Show searching message (non-dismissible)
	Say:Say("System", false, {"Searching for another player to trade with..."})
	
	-- Request server to start search
	local ok, result = pcall(function()
		return Request:InvokeServer({"MysteryTradeStart"})
	end)
	
	if not ok or not result then
		self:HandleAbort("Unable to start search. Please try again.")
		return
	end
	
	if type(result) == "table" and result.Success == false then
		self:HandleAbort(result.Message or "Unable to start search.")
		return
	end
	
	-- Safety timeout: if we don't receive a response within 15 seconds, auto-cancel
	-- This prevents the state from getting stuck if the server doesn't send an event
	task.delay(15, function()
		if self:GetState() == STATE_SEARCHING then
			self:HandleAbort("Search timed out. Please try again.")
		end
	end)
	
	-- Wait for search result (will be handled by event handler)
	-- The server will send either MysteryTradeFound or MysteryTradeCancelled
end

-- Handle search result
function MysteryTrade:HandleSearchResult(success: boolean, message: string?)
	Say:Exit() -- Close searching message
	
	if not success then
		self:HandleAbort(message or "Unable to find a trade partner.")
		return
	end
end

-- Handle partner found
function MysteryTrade:HandlePartnerFound(sessionId: string, partnerName: string, partnerUserId: number)
	-- Only handle if we're still searching
	if self:GetState() ~= STATE_SEARCHING then
		return
	end
	
	_sessionId = sessionId
	_partnerName = partnerName
	
	self:SetState(STATE_SELECTING)
	
	-- Close searching message
	Say:Exit()
	
	-- Show message (dismissible)
	Say:Say("System", true, {"Trade found! Please select a creature to trade."})
	
	-- Only open vault if still in selecting state
	if self:GetState() == STATE_SELECTING then
		local UI = getUI()
		if UI and UI.Vault then
			UI.Vault:Open({
				selectionMode = true,
				onSelect = function(creatureData, locationInfo)
					self:OnCreatureSelected(creatureData, locationInfo)
				end
			})
		else
			self:HandleAbort("Unable to open vault.")
		end
	end
end

-- Handle creature selection
function MysteryTrade:OnCreatureSelected(creatureData: any, locationInfo: any)
	_selectedCreature = creatureData
	_selectedLocation = locationInfo
	
	-- Show confirmation
	local creatureName = creatureData.Nickname or creatureData.Name or "this creature"
	Say:Say("System", false, {string.format("Are you sure you want to trade %s? This action cannot be undone.", creatureName)})
	local choice = Say:YieldChoice()
	
	if choice ~= true then
		-- User said no, just hide the Say dialog and clear selection
		-- Don't close vault or do anything else that might interfere
		Say:Exit()
		_selectedCreature = nil
		_selectedLocation = nil
		return
	end
	
	-- User said yes, exit Say and proceed with submission
	Say:Exit()
	
	-- Hide Close button in vault to prevent closing after confirmation
	local UI = getUI()
	if UI and UI.Vault then
		local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
		local GameUI = PlayerGui:FindFirstChild("GameUI")
		if GameUI then
			local vaultGui = GameUI:FindFirstChild("Vault")
			if vaultGui then
				local closeBtn = vaultGui:FindFirstChild("Close")
				if closeBtn and (closeBtn:IsA("TextButton") or closeBtn:IsA("ImageButton")) then
					closeBtn.Visible = false
				end
			end
		end
	end
	
	-- Submit selection (this will handle server communication)
	-- The vault will remain open until the selection is confirmed by the server
	-- It will be closed when the trade progresses to the next state
	self:SubmitSelection()
end

-- Submit creature selection
function MysteryTrade:SubmitSelection()
	if not _sessionId or not _selectedCreature or not _selectedLocation then
		self:HandleAbort("Invalid selection.")
		return
	end
	
	-- SECURITY: Client-side validation (defense in depth)
	-- Validate session ID
	if type(_sessionId) ~= "string" or _sessionId == "" then
		self:HandleAbort("Invalid session ID.")
		return
	end
	
	-- Validate creature data structure
	if not _selectedCreature or type(_selectedCreature) ~= "table" then
		self:HandleAbort("Invalid creature data.")
		return
	end
	
	if not _selectedCreature.Name or type(_selectedCreature.Name) ~= "string" then
		self:HandleAbort("Invalid creature name.")
		return
	end
	
	if not _selectedCreature.Level or type(_selectedCreature.Level) ~= "number" or _selectedCreature.Level < 1 or _selectedCreature.Level > 100 then
		self:HandleAbort("Invalid creature level.")
		return
	end
	
	-- Validate location data structure
	if not _selectedLocation or type(_selectedLocation) ~= "table" then
		self:HandleAbort("Invalid location data.")
		return
	end
	
	if _selectedLocation.where ~= "Party" and _selectedLocation.where ~= "Box" then
		self:HandleAbort("Invalid location type.")
		return
	end
	
	if not _selectedLocation.index or type(_selectedLocation.index) ~= "number" then
		self:HandleAbort("Invalid location index.")
		return
	end
	
	if _selectedLocation.where == "Party" then
		if _selectedLocation.index < 1 or _selectedLocation.index > 6 then
			self:HandleAbort("Invalid party slot.")
			return
		end
	elseif _selectedLocation.where == "Box" then
		if not _selectedLocation.box or type(_selectedLocation.box) ~= "number" then
			self:HandleAbort("Invalid box index.")
			return
		end
		if _selectedLocation.box < 1 or _selectedLocation.box > 8 then
			self:HandleAbort("Invalid box index.")
			return
		end
		if _selectedLocation.index < 1 or _selectedLocation.index > 30 then
			self:HandleAbort("Invalid box slot.")
			return
		end
	end
	
	local ok, result = pcall(function()
		return Request:InvokeServer({"MysteryTradeSelectCreature", {
			SessionId = _sessionId,
			Creature = _selectedCreature,
			Location = _selectedLocation,
		}})
	end)
	
	if not ok or not result then
		self:HandleAbort("Unable to submit selection.")
		return
	end
	
	if type(result) == "table" and result.Success == false then
		self:HandleAbort(result.Message or "Unable to submit selection.")
		return
	end
	
	self:SetState(STATE_CONFIRMING)
	
	-- Close vault after successful submission
	local UI = getUI()
	if UI and UI.Vault and UI.Vault.Close then
		-- Check if vault is actually open before closing
		local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
		local GameUI = PlayerGui:FindFirstChild("GameUI")
		if GameUI then
			local vaultGui = GameUI:FindFirstChild("Vault")
			if vaultGui and vaultGui.Visible then
				UI.Vault:Close()
			end
		end
	end
	
	-- Show waiting message (non-dismissible)
	Say:Say("System", false, {string.format("Waiting for %s to confirm their choice...", _partnerName or "partner")})
	
	-- Wait for confirmation (will be handled by event handler)
end

-- Handle partner selected
function MysteryTrade:HandlePartnerSelected()
	-- Partner has selected their creature, check if we're waiting for them
	if self:GetState() == STATE_CONFIRMING then
		-- Both players have now selected, wait 1-2 seconds before showing confirmation prompt
		task.wait(1.5)
		-- Double-check state hasn't changed during the delay
		if self:GetState() == STATE_CONFIRMING then
			self:HandleConfirmRequired()
		end
	end
end

-- Handle confirmation required
function MysteryTrade:HandleConfirmRequired()
	-- Both players have selected, now need to confirm
	Say:Exit() -- Close waiting message
	
	Say:Say("System", false, {"Both players have selected. Confirm trade?"})
	local choice = Say:YieldChoice()
	Say:Exit()
	
	if choice == true then
		self:ConfirmTrade()
	else
		self:HandleAbort("Trade cancelled.")
	end
end

-- Confirm trade
function MysteryTrade:ConfirmTrade()
	-- Prevent double-clicks - if already confirming, ignore
	if _isConfirming then
		return
	end
	
	-- Prevent confirming if already waiting
	if self:GetState() == STATE_WAITING then
		return
	end
	
	if not _sessionId then
		return
	end
	
	-- SECURITY: Client-side validation (defense in depth)
	if type(_sessionId) ~= "string" or _sessionId == "" then
		self:HandleAbort("Invalid session ID.")
		return
	end
	
	-- Set confirming flag immediately to prevent rapid clicks
	_isConfirming = true
	
	local ok, result = pcall(function()
		return Request:InvokeServer({"MysteryTradeConfirm", {
			SessionId = _sessionId,
		}})
	end)
	
	if not ok or not result then
		_isConfirming = false -- Reset flag on error
		self:HandleAbort("Unable to confirm trade.")
		return
	end
	
	if type(result) == "table" and result.Success == false then
		_isConfirming = false -- Reset flag on error
		-- Check if it's a rate limit error - don't abort trade, just show message
		local errorMsg = result.Message or "Unable to confirm trade."
		local isRateLimit = string.find(errorMsg:lower(), "wait") or string.find(errorMsg:lower(), "rate") or string.find(errorMsg:lower(), "moment")
		
		if isRateLimit then
			-- Rate limit error - show message but don't abort trade
			-- Keep state as CONFIRMING so user can try again
			Say:Say("System", true, {errorMsg})
			-- Re-show the confirmation prompt after a short delay so they can try again
			task.delay(1, function()
				if self:GetState() == STATE_CONFIRMING then
					Say:Exit()
					Say:Say("System", false, {"Both players have selected. Confirm trade?"})
					local choice = Say:YieldChoice()
					Say:Exit()
					if choice == true then
						self:ConfirmTrade()
					else
						self:HandleAbort("Trade cancelled.")
					end
				end
			end)
			return
		end
		-- Other errors - abort trade
		self:HandleAbort(errorMsg)
		return
	end
	
	-- Success - keep _isConfirming true until trade completes or aborts
	self:SetState(STATE_WAITING)
	
	-- Show waiting message
	Say:Say("System", false, {"Waiting for trade to complete..."})
	
	-- Safety timeout: if we don't receive finalization event within 15 seconds, auto-clear
	-- This prevents the message from getting stuck if the event doesn't arrive
	-- Store session ID to check if it's still valid
	local timeoutSessionId = _sessionId
	task.delay(15, function()
		-- Check if we're still waiting and session hasn't changed
		if self:GetState() == STATE_WAITING and _sessionId == timeoutSessionId then
			-- Trade should have completed by now, clear the message and reset
			warn("[MysteryTrade] Trade completion timeout - clearing stuck state. SessionId:", timeoutSessionId)
			-- Force clear Say dialog if it's still showing
			if Say:IsActive() then
				Say:Exit()
			end
			self:Reset()
			local UI = getUI()
			if UI and UI.TopBar then
				UI.TopBar:SetSuppressed(false)
				UI.TopBar:Show()
			end
			CharacterFunctions:CanMove(true)
		end
	end)
end

-- Handle trade finalized
function MysteryTrade:HandleTradeFinalized(payload: any)
	-- Validate payload
	if not payload then
		warn("[MysteryTrade] HandleTradeFinalized called with nil payload")
		return
	end
	
	-- Only handle if we're actually waiting for trade completion
	-- But also handle if we're in confirming state (in case event arrives early)
	local currentState = self:GetState()
	if currentState ~= STATE_WAITING and currentState ~= STATE_CONFIRMING then
		warn("[MysteryTrade] HandleTradeFinalized called but state is", currentState, "not Waiting or Confirming")
		return
	end
	
	-- Validate session ID matches
	if payload.SessionId and _sessionId and payload.SessionId ~= _sessionId then
		warn("[MysteryTrade] HandleTradeFinalized session mismatch:", payload.SessionId, "vs", _sessionId)
		return
	end
	
	-- Force close Say dialog - ensure it's cleared before showing animation
	-- Call Exit multiple times to ensure it's cleared (Say might need multiple calls in some edge cases)
	Say:Exit()
	if Say:IsActive() then
		Say:Exit()
	end
	-- Use spawn to ensure Say clearing happens even if there's a delay
	-- This handles cases where Say might be in the middle of animating text
	task.spawn(function()
		task.wait(0.1)
		if Say:IsActive() then
			warn("[MysteryTrade] Say dialog still active after Exit, forcing close")
			Say:Exit()
		end
	end)
	
	-- Close vault if it's open (check before closing to avoid unnecessary animation)
	local UI = getUI()
	if UI and UI.Vault and UI.Vault.Close then
		-- Check if vault is actually open before closing
		local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
		local GameUI = PlayerGui:FindFirstChild("GameUI")
		if GameUI then
			local vaultGui = GameUI:FindFirstChild("Vault")
			if vaultGui and vaultGui.Visible then
				UI.Vault:Close()
			end
		end
	end
	
	-- Use existing trade animation from Trade module
	if UI and UI.Trade then
		-- Call the Trade UI's HandleEvent to trigger the animation
		-- Use MysteryTradeFinalized event type (not TradeFinalized) since MysteryTrade doesn't use TradeUI state
		UI.Trade:HandleEvent("MysteryTradeFinalized", payload)
	end
	
	-- Restore UI (only when trade fully finalizes)
	if UI and UI.TopBar then
		UI.TopBar:SetSuppressed(false)
		UI.TopBar:Show()
	end
	CharacterFunctions:CanMove(true)
	
	-- Reset state immediately (animation will play independently)
	self:Reset()
end

-- Handle abort
function MysteryTrade:HandleAbort(reason: string?)
	-- Prevent multiple calls from causing issues
	if _state == STATE_IDLE then
		return
	end
	
	Say:Exit() -- Close any open messages
	
	if reason then
		Say:Say("System", true, {reason})
	end
	
	-- Cancel on server if we have a session or are searching
	if _sessionId then
		pcall(function()
			Request:InvokeServer({"MysteryTradeCancel", {
				SessionId = _sessionId,
			}})
		end)
	elseif _state == STATE_SEARCHING then
		-- Cancel search if we're still searching (no session yet)
		pcall(function()
			Request:InvokeServer({"MysteryTradeCancel", {}})
		end)
	end

	-- Show Close button again if vault is still open
	local UI = getUI()
	if UI then
		local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
		local GameUI = PlayerGui:FindFirstChild("GameUI")
		if GameUI then
			local vaultGui = GameUI:FindFirstChild("Vault")
			if vaultGui and vaultGui.Visible then
				local closeBtn = vaultGui:FindFirstChild("Close")
				if closeBtn and (closeBtn:IsA("TextButton") or closeBtn:IsA("ImageButton")) then
					closeBtn.Visible = true
				end
			end
		end
	end

	-- Close vault if it's open (check before closing to avoid unnecessary animation)
	if UI and UI.Vault and UI.Vault.Close then
		-- Check if vault is actually open before closing
		local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
		local GameUI = PlayerGui:FindFirstChild("GameUI")
		if GameUI then
			local vaultGui = GameUI:FindFirstChild("Vault")
			if vaultGui and vaultGui.Visible then
				UI.Vault:Close()
			end
		end
	end
	
	-- Restore UI (only when trade cancels)
	if UI and UI.TopBar then
		UI.TopBar:SetSuppressed(false)
		UI.TopBar:Show()
	end
	CharacterFunctions:CanMove(true)
	
	-- Reset state immediately
	self:Reset()
end

-- Reset state
function MysteryTrade:Reset()
	_state = STATE_IDLE
	_selectedCreature = nil
	_selectedLocation = nil
	_sessionId = nil
	_partnerName = nil
	_isConfirming = false -- Reset confirming flag
end

-- Initialize event handlers
function MysteryTrade:Init()
	Communicate.OnClientEvent:Connect(function(eventType, data)
		if eventType == "MysteryTradeFound" then
			if data and data.SessionId then
				self:HandlePartnerFound(data.SessionId, data.PartnerName or "Player", data.PartnerUserId or 0)
			end
		elseif eventType == "MysteryTradeCancelled" then
			if data and data.Reason then
				self:HandleAbort(data.Reason)
			else
				self:HandleAbort("Trade cancelled.")
			end
		elseif eventType == "MysteryTradeFinalized" then
			if data then
				self:HandleTradeFinalized(data)
			else
				warn("[MysteryTrade] MysteryTradeFinalized event received but data is nil")
			end
		elseif eventType == "MysteryTradePartnerSelected" then
			self:HandlePartnerSelected()
		end
	end)
end

-- Initialize on require
MysteryTrade:Init()

return MysteryTrade


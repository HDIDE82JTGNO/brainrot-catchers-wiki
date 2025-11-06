--!strict
--[[
	ActionHandler.lua
	Handles player battle actions (moves, switches, items, run)
	Provides clean interface for all player input processing
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Events = ReplicatedStorage:WaitForChild("Events")

local ActionHandler = {}
ActionHandler.__index = ActionHandler

export type ActionHandlerType = typeof(ActionHandler.new())
export type ActionCallback = (any) -> ()

--[[
	Creates a new action handler instance
	@param battleState The battle state reference
	@return ActionHandler
]]
function ActionHandler.new(battleState: any): any
	local self = setmetatable({}, ActionHandler)
	
	self._battleState = battleState
	self._actionLocked = false
    self._lastTurnId = 0
	self._callbacks = {
		onMoveSelected = nil,
		onSwitchRequested = nil,
		onRunRequested = nil,
		onBagOpened = nil,
		onCantRun = nil,
	}
	
	return self
end

--[[
	Sets the move selected callback
	@param callback Function to call when move is selected
]]
function ActionHandler:OnMoveSelected(callback: ActionCallback)
	self._callbacks.onMoveSelected = callback
end

--[[
	Sets the switch requested callback
	@param callback Function to call when switch is requested
]]
function ActionHandler:OnSwitchRequested(callback: ActionCallback)
	self._callbacks.onSwitchRequested = callback
end

--[[
	Sets the run requested callback
	@param callback Function to call when run is requested
]]
function ActionHandler:OnRunRequested(callback: ActionCallback)
	self._callbacks.onRunRequested = callback
end

--[[
	Sets the bag opened callback
	@param callback Function to call when bag is opened
]]
function ActionHandler:OnBagOpened(callback: ActionCallback)
	self._callbacks.onBagOpened = callback
end

--[[
	Sets the can't run callback
	@param callback Function to call when player can't run
]]
function ActionHandler:OnCantRun(callback: ActionCallback)
	self._callbacks.onCantRun = callback
end

--[[
	Executes a move
	@param moveIndex The move index (1-4)
]]
function ActionHandler:ExecuteMove(moveIndex: number)
	if self._actionLocked then
		warn("[ActionHandler] Action locked, cannot execute move")
		return
	end
	
	if not self._battleState or not self._battleState.PlayerCreature then
		warn("[ActionHandler] No active battle or creature")
		return
	end
	
	local creature = self._battleState.PlayerCreature
	local moves = creature.CurrentMoves or creature.Moves
	
	if not moves or not moves[moveIndex] then
		warn("[ActionHandler] Invalid move index:", moveIndex)
		return
	end
	
	local move = moves[moveIndex]
	
	-- Lock actions
	self._actionLocked = true
	self._battleState.PlayerTurnUsed = true
	
	-- Get move name (move is now a string from server)
	local moveName = "Unknown"
	if type(move) == "string" then
		moveName = move
	elseif type(move) == "table" and move.Name then
		moveName = move.Name
	elseif type(move) == "table" then
		-- Legacy: try to find move name by properties
		local Moves = require(game.ReplicatedStorage.Shared.Moves)
		for moveKey, moveData in pairs(Moves) do
			if moveData == move then
				moveName = moveKey
				break
			end
		end
	end
	
	-- Send to server with TurnId for replay protection
	local success, err = pcall(function()
		Events.Request:InvokeServer({"ExecuteMove", {
			MoveIndex = moveIndex,
			MoveName = moveName,
            TurnId = self._battleState.TurnId,
		}})
	end)
	
	if not success then
		warn("[ActionHandler] Failed to execute move:", err)
		self._actionLocked = false
		self._battleState.PlayerTurnUsed = false
	end
	
	-- Trigger callback
	if self._callbacks.onMoveSelected then
		self._callbacks.onMoveSelected(move)
	end
end

--[[
	Requests a creature switch
	@param creatureIndex The party index to switch to
]]
function ActionHandler:RequestSwitch(creatureIndex: number)
	print("[ActionHandler] RequestSwitch called with creatureIndex:", creatureIndex)
	
	if self._actionLocked then
		warn("[ActionHandler] Action locked, cannot switch")
		return
	end
	
	if not self._battleState then
		warn("[ActionHandler] No active battle")
		return
	end
	
	-- Lock actions
	self._actionLocked = true
	self._battleState.PlayerTurnUsed = true
	
	-- Send to server with TurnId for replay protection
	print("[ActionHandler] Sending SwitchCreature request to server with index:", creatureIndex)
	local success, err = pcall(function()
		Events.Request:InvokeServer({"SwitchCreature", {
			Index = creatureIndex,
			TurnId = self._battleState.TurnId,
		}})
	end)
	
	if not success then
		warn("[ActionHandler] Failed to switch creature:", err)
		self._actionLocked = false
		self._battleState.PlayerTurnUsed = false
	else
		print("[ActionHandler] SwitchCreature request sent successfully")
	end
	
	-- Trigger callback
	if self._callbacks.onSwitchRequested then
		self._callbacks.onSwitchRequested(creatureIndex)
	end
end

--[[
	Attempts to run from battle
]]
function ActionHandler:AttemptRun()
	if self._actionLocked then
		warn("[ActionHandler] Action locked, cannot run")
		return
	end
	
	if not self._battleState then
		warn("[ActionHandler] No active battle")
		return
	end
	
	-- Can't run from trainer battles
	if self._battleState.Type == "Trainer" then
		warn("[ActionHandler] Cannot run from trainer battles")
		
		-- Trigger callback to handle the "can't run" case
		if self._callbacks.onCantRun then
			self._callbacks.onCantRun()
		end
		return
	end
	
	-- Lock actions
	self._actionLocked = true
	self._battleState.PlayerTurnUsed = true
	
	-- Increment escape attempts
	self._battleState:IncrementEscapeAttempts()
	
	-- Send to server
	local success, err = pcall(function()
		Events.Request:InvokeServer({"AttemptRun"})
	end)
	
	if not success then
		warn("[ActionHandler] Failed to run:", err)
		self._actionLocked = false
		self._battleState.PlayerTurnUsed = false
	end
	
	-- Trigger callback
	if self._callbacks.onRunRequested then
		self._callbacks.onRunRequested()
	end
end

--[[
	Opens the bag menu
]]
function ActionHandler:OpenBag()
	if self._actionLocked then
		warn("[ActionHandler] Action locked, cannot open bag")
		return
	end
	
	-- Trigger callback
	if self._callbacks.onBagOpened then
		self._callbacks.onBagOpened()
	end
end

--[[
	Locks player actions (during animations, etc.)
]]
function ActionHandler:Lock()
	self._actionLocked = true
end

--[[
	Unlocks player actions
]]
function ActionHandler:Unlock()
	self._actionLocked = false
end

--[[
	Checks if actions are locked
	@return boolean True if locked
]]
function ActionHandler:IsLocked(): boolean
	return self._actionLocked
end

--[[
	Resets the action handler for a new turn
]]
function ActionHandler:Reset()
	self._actionLocked = false
end

return ActionHandler

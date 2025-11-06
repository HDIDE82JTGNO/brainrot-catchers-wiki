--!strict
--[[
	ClientBattleState.lua
	Client-side battle state manager using OOP patterns
	Manages local battle state with proper encapsulation
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BattleTypes = require(ReplicatedStorage.Shared.BattleTypes)

type Creature = BattleTypes.Creature
type BattleMode = BattleTypes.BattleMode
type SwitchMode = BattleTypes.SwitchMode

local ClientBattleState = {}
ClientBattleState.__index = ClientBattleState

--[[
	Creates a new client battle state instance
	@param battleType The type of battle
	@param playerCreature The player's active creature
	@param foeCreature The opponent's creature
	@return ClientBattleState
]]
function ClientBattleState.new(
	battleType: BattleMode,
	playerCreature: Creature,
	foeCreature: Creature
): any
	local self = setmetatable({}, ClientBattleState)
	
	self.Type = battleType
	self.TurnNumber = 0
	self.PlayerCreatureIndex = 1
	self.PlayerCreature = playerCreature
	self.FoeCreature = foeCreature
	self.SwitchMode = nil
	self.PlayerTurnUsed = false
	self.EnemyTurnUsed = false
	self.EscapeAttempts = 0
	self.SwitchSpawnPending = false
	self.PendingGoMessage = nil
	
	-- Faint tracking
	self._faintedSlots = {} :: {[number]: boolean}
	self._playerFainted = false
	self._foeFainted = false
	
	-- HP update tracking (for animation timing)
	self._pendingHP = nil
	self._hpUpdateCount = 0
	self._expectedHpUpdates = 0
	
	return self
end

--[[
	Updates the player's active creature
	@param creature The new creature
	@param index The party index
]]
function ClientBattleState:UpdatePlayerCreature(creature: Creature, index: number)
	self.PlayerCreature = creature
	self.PlayerCreatureIndex = index
end

--[[
	Updates the foe's active creature
	@param creature The new creature
]]
function ClientBattleState:UpdateFoeCreature(creature: Creature)
	self.FoeCreature = creature
end

--[[
	Increments the turn number
]]
function ClientBattleState:IncrementTurn()
	self.TurnNumber += 1
	self.PlayerTurnUsed = false
	self.EnemyTurnUsed = false
end

--[[
	Sets the switch mode
	@param mode The switch mode
]]
function ClientBattleState:SetSwitchMode(mode: SwitchMode?)
	self.SwitchMode = mode
end

--[[
	Marks a party slot as fainted
	@param slotIndex The slot index
]]
function ClientBattleState:MarkSlotFainted(slotIndex: number)
	self._faintedSlots[slotIndex] = true
end

--[[
	Checks if a party slot is fainted
	@param slotIndex The slot index
	@return boolean True if fainted
]]
function ClientBattleState:IsSlotFainted(slotIndex: number): boolean
	return self._faintedSlots[slotIndex] == true
end

--[[
	Clears fainted slot tracking
]]
function ClientBattleState:ClearFaintedSlots()
	self._faintedSlots = {}
end

--[[
	Sets the player fainted flag
	@param fainted Whether the player's creature fainted
]]
function ClientBattleState:SetPlayerFainted(fainted: boolean)
	self._playerFainted = fainted
end

--[[
	Gets the player fainted flag
	@return boolean True if fainted
]]
function ClientBattleState:IsPlayerFainted(): boolean
	return self._playerFainted
end

--[[
	Sets the foe fainted flag
	@param fainted Whether the foe's creature fainted
]]
function ClientBattleState:SetFoeFainted(fainted: boolean)
	self._foeFainted = fainted
end

--[[
	Gets the foe fainted flag
	@return boolean True if fainted
]]
function ClientBattleState:IsFoeFainted(): boolean
	return self._foeFainted
end

--[[
	Sets the switch spawn pending flag
	@param pending Whether a switch spawn is pending
]]
function ClientBattleState:SetSwitchSpawnPending(pending: boolean)
	self.SwitchSpawnPending = pending
end

--[[
	Gets the switch spawn pending flag
	@return boolean True if pending
]]
function ClientBattleState:IsSwitchSpawnPending(): boolean
	return self.SwitchSpawnPending == true
end

--[[
	Sets the pending "Go!" message
	@param message The message
]]
function ClientBattleState:SetPendingGoMessage(message: string?)
	self.PendingGoMessage = message
end

--[[
	Gets and clears the pending "Go!" message
	@return string? The message
]]
function ClientBattleState:ConsumePendingGoMessage(): string?
	local message = self.PendingGoMessage
	self.PendingGoMessage = nil
	return message
end

--[[
	Increments escape attempts
]]
function ClientBattleState:IncrementEscapeAttempts()
	self.EscapeAttempts += 1
end

--[[
	Resets the battle state for a new battle
]]
function ClientBattleState:Reset()
	self.TurnNumber = 0
	self.PlayerTurnUsed = false
	self.EnemyTurnUsed = false
	self.EscapeAttempts = 0
	self.SwitchSpawnPending = false
	self.PendingGoMessage = nil
	self.SwitchMode = nil
	self._faintedSlots = {}
	self._playerFainted = false
	self._foeFainted = false
end

--[[
	Sets pending HP data for deferred UI updates
	@param hpData The HP data from server
	@param expectedUpdates Number of Hit markers expected (usually 2 for player + foe)
]]
function ClientBattleState:SetPendingHP(hpData: any, expectedUpdates: number?)
	self._pendingHP = hpData
	self._hpUpdateCount = 0
	self._expectedHpUpdates = expectedUpdates or 2 -- Default to 2 (player + foe)
end

--[[
	Gets pending HP data (doesn't clear it)
	@return table|nil The pending HP data
]]
function ClientBattleState:GetPendingHP(): any?
	return self._pendingHP
end

--[[
	Marks an HP update as processed and clears data when all expected updates are done
	@return table|nil The pending HP data (only on first call)
]]
function ClientBattleState:MarkHPUpdateProcessed(): any?
	if not self._pendingHP then
		return nil
	end
	
	self._hpUpdateCount = self._hpUpdateCount + 1
	
    -- Return HP data on every call until all expected updates are processed;
    -- clear when we reach the expected count
    local hpSnapshot = self._pendingHP
    if self._hpUpdateCount >= self._expectedHpUpdates then
		-- All expected updates processed, clear the data
		self._pendingHP = nil
		self._hpUpdateCount = 0
		self._expectedHpUpdates = 0
	end
    return hpSnapshot
end

--[[
	Gets a snapshot of the current state
	@return table State snapshot
]]
function ClientBattleState:GetSnapshot(): {[string]: any}
	return {
		Type = self.Type,
		TurnNumber = self.TurnNumber,
		PlayerCreatureIndex = self.PlayerCreatureIndex,
		PlayerCreature = self.PlayerCreature,
		FoeCreature = self.FoeCreature,
		SwitchMode = self.SwitchMode,
		EscapeAttempts = self.EscapeAttempts,
	}
end

return ClientBattleState

--!strict
--[[
	BattleStateManager.lua
	Manages battle state using OOP patterns with metatables
	Provides a clean interface for battle state manipulation
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local BattleTypes = require(ReplicatedStorage.Shared.BattleTypes)

type BattleState = BattleTypes.BattleState
type BattleMode = BattleTypes.BattleMode
type Creature = BattleTypes.Creature

local BattleStateManager = {}
BattleStateManager.__index = BattleStateManager

-- Active battles storage
local ActiveBattles: {[string]: BattleState} = {}

--[[
	Creates a new battle state instance
	@param player The player in the battle
	@param battleType The type of battle (Wild, Trainer, PvP)
	@param playerCreature The player's active creature
	@param foeCreature The opponent's creature
	@param chunk The current chunk name
	@return BattleState The new battle state
]]
function BattleStateManager.new(
	player: Player,
	battleType: BattleMode,
	playerCreature: Creature,
	foeCreature: Creature,
	chunk: string
): BattleState
	local self = setmetatable({}, BattleStateManager) :: any
	
	self.id = HttpService:GenerateGUID(false)
	self.Player = player
	self.Type = battleType
	self.Turn = 0
	self.PlayerCreatureIndex = 1
	self.PlayerCreature = playerCreature
	self.FoeCreature = foeCreature
	self.EscapeAttempts = 0
	self.Chunk = chunk
	self.SwitchMode = nil
	
	-- Store in active battles
	ActiveBattles[self.id] = self
	
	return self :: BattleState
end

--[[
	Gets an active battle by ID
	@param battleId The battle ID
	@return BattleState? The battle state if found
]]
function BattleStateManager.GetBattle(battleId: string): BattleState?
	return ActiveBattles[battleId]
end

--[[
	Gets an active battle by player
	@param player The player
	@return BattleState? The battle state if found
]]
function BattleStateManager.GetBattleByPlayer(player: Player): BattleState?
	for _, battle in pairs(ActiveBattles) do
		if battle.Player == player then
			return battle
		end
	end
	return nil
end

--[[
	Ends a battle and cleans up state
	@param battleId The battle ID
]]
function BattleStateManager.EndBattle(battleId: string)
	local battle = ActiveBattles[battleId]
	if battle then
		-- Clean up any battle-specific data
		ActiveBattles[battleId] = nil
	end
end

--[[
	Increments the turn counter
]]
function BattleStateManager:IncrementTurn()
	self.Turn += 1
end

--[[
	Updates the player's active creature
	@param newCreature The new creature
	@param newIndex The new index in the party
]]
function BattleStateManager:UpdatePlayerCreature(newCreature: Creature, newIndex: number)
	self.PlayerCreature = newCreature
	self.PlayerCreatureIndex = newIndex
end

--[[
	Updates the foe's active creature
	@param newCreature The new creature
	@param newIndex The new index (optional for wild battles)
]]
function BattleStateManager:UpdateFoeCreature(newCreature: Creature, newIndex: number?)
	self.FoeCreature = newCreature
	if newIndex then
		self.FoeCreatureIndex = newIndex
	end
end

--[[
	Sets the switch mode (Forced or Voluntary)
	@param mode The switch mode
]]
function BattleStateManager:SetSwitchMode(mode: BattleTypes.SwitchMode?)
	self.SwitchMode = mode
end

--[[
	Increments escape attempts
]]
function BattleStateManager:IncrementEscapeAttempts()
	self.EscapeAttempts += 1
end

--[[
	Checks if the player's creature has fainted
	@return boolean True if fainted
]]
function BattleStateManager:IsPlayerCreatureFainted(): boolean
	return self.PlayerCreature and self.PlayerCreature.Stats and self.PlayerCreature.Stats.HP <= 0
end

--[[
	Checks if the foe's creature has fainted
	@return boolean True if fainted
]]
function BattleStateManager:IsFoeCreatureFainted(): boolean
	return self.FoeCreature and self.FoeCreature.Stats and self.FoeCreature.Stats.HP <= 0
end

--[[
	Gets a snapshot of the current battle state for client transmission
	@return table A sanitized snapshot
]]
function BattleStateManager:GetSnapshot(): {[string]: any}
	return {
		id = self.id,
		Type = self.Type,
		Turn = self.Turn,
		PlayerCreatureIndex = self.PlayerCreatureIndex,
		PlayerCreature = self.PlayerCreature,
		FoeCreature = self.FoeCreature,
		SwitchMode = self.SwitchMode,
		EscapeAttempts = self.EscapeAttempts,
		Chunk = self.Chunk,
	}
end

--[[
	Gets all active battles (for debugging)
	@return table All active battles
]]
function BattleStateManager.GetAllBattles(): {[string]: BattleState}
	return ActiveBattles
end

--[[
	Cleans up all battles for a player (on disconnect)
	@param player The player
]]
function BattleStateManager.CleanupPlayerBattles(player: Player)
	for battleId, battle in pairs(ActiveBattles) do
		if battle.Player == player then
			BattleStateManager.EndBattle(battleId)
		end
	end
end

return BattleStateManager

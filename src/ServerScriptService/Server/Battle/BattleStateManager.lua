--!strict
--[[
	BattleStateManager.lua
	Manages battle state using OOP patterns with metatables
	Provides a clean interface for battle state manipulation
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local BattleTypes = require(ReplicatedStorage.Shared.BattleTypes)
local StatStages = require(ReplicatedStorage.Shared.StatStages)

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
	
	-- Initialize stat stages for both creatures
	StatStages.EnsureCreatureHasStages(playerCreature)
	StatStages.EnsureCreatureHasStages(foeCreature)
	
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
	Updates the player's active creature (resets stat stages)
	@param newCreature The new creature
	@param newIndex The new index in the party
]]
function BattleStateManager:UpdatePlayerCreature(newCreature: Creature, newIndex: number)
	self.PlayerCreature = newCreature
	self.PlayerCreatureIndex = newIndex
	-- Reset stat stages for the new creature
	StatStages.ResetAll(newCreature)
	StatStages.EnsureCreatureHasStages(newCreature)
end

--[[
	Updates the foe's active creature (resets stat stages)
	@param newCreature The new creature
	@param newIndex The new index (optional for wild battles)
]]
function BattleStateManager:UpdateFoeCreature(newCreature: Creature, newIndex: number?)
	self.FoeCreature = newCreature
	if newIndex then
		self.FoeCreatureIndex = newIndex
	end
	-- Reset stat stages for the new creature
	StatStages.ResetAll(newCreature)
	StatStages.EnsureCreatureHasStages(newCreature)
end

--[[
	Resets stat stages for the player's creature
]]
function BattleStateManager:ResetPlayerStatStages()
	if self.PlayerCreature then
		StatStages.ResetAll(self.PlayerCreature)
	end
end

--[[
	Resets stat stages for the foe's creature
]]
function BattleStateManager:ResetFoeStatStages()
	if self.FoeCreature then
		StatStages.ResetAll(self.FoeCreature)
	end
end

--[[
	Gets the stat stages for display
	@param isPlayer Whether to get player or foe stages
	@return table The stat stages
]]
function BattleStateManager:GetStatStages(isPlayer: boolean): any
	local creature = isPlayer and self.PlayerCreature or self.FoeCreature
	return StatStages.GetAllStages(creature)
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
		-- Include stat stages for client display
		PlayerStatStages = self.PlayerCreature and self.PlayerCreature.StatStages or nil,
		FoeStatStages = self.FoeCreature and self.FoeCreature.StatStages or nil,
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

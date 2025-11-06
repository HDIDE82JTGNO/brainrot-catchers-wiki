--!strict
--[[
	AIController.lua
	Handles enemy AI decision making for battles
	Provides different AI strategies for wild and trainer battles
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BattleTypes = require(ReplicatedStorage.Shared.BattleTypes)
local MovesModule = require(ReplicatedStorage.Shared.Moves)
local DamageCalculator = require(script.Parent.DamageCalculator)

type Creature = BattleTypes.Creature
type Move = BattleTypes.Move

local AIController = {}

-- AI difficulty levels
export type AIDifficulty = "Random" | "Smart" | "Expert"

--[[
	Selects a random move from available moves
	@param moves The available moves
	@return string? The selected move name
]]
local function selectRandomMove(moves: {string}?): string?
	if not moves or #moves == 0 then
		return "Tackle" -- Fallback move
	end
	
	return moves[math.random(1, #moves)]
end

--[[
	Evaluates move effectiveness and damage potential
	@param foeCreature The attacking creature
	@param playerCreature The defending creature
	@param moveName The move to evaluate
	@return number Score for the move (higher is better)
]]
local function evaluateMove(
	foeCreature: Creature,
	playerCreature: Creature,
	moveName: string
): number
	local moveData = MovesModule[moveName]
	if not moveData then
		return 0
	end
	
	local score = 0
	
	-- Base score from move power
	if moveData.BasePower then
		score += moveData.BasePower
	end
	
	-- Bonus for type effectiveness
	if moveData.Type and playerCreature.Type then
		local effectiveness = DamageCalculator.GetEffectivenessString(moveData.Type, playerCreature.Type)
		if effectiveness == "SuperEffective" then
			score += 50
		elseif effectiveness == "NotVeryEffective" then
			score -= 25
		elseif effectiveness == "Immune" then
			score = 0
		end
	end
	
	-- Bonus for STAB
	if moveData.Type and foeCreature.Type then
		for _, creatureType in ipairs(foeCreature.Type) do
			if creatureType == moveData.Type then
				score += 20
				break
			end
		end
	end
	
	-- Bonus for high accuracy
	if moveData.Accuracy and moveData.Accuracy >= 90 then
		score += 10
	end
	
	-- Bonus for priority moves
	if moveData.Priority and moveData.Priority > 0 then
		score += 15
	end
	
	return score
end

--[[
	Selects the best move based on current battle state
	@param foeCreature The attacking creature
	@param playerCreature The defending creature
	@param moves The available moves
	@return string? The selected move name
]]
local function selectSmartMove(
	foeCreature: Creature,
	playerCreature: Creature,
	moves: {string}?
): string?
	if not moves or #moves == 0 then
		return "Tackle"
	end
	
	local bestMove = nil
	local bestScore = -1
	
	for _, moveName in ipairs(moves) do
		local score = evaluateMove(foeCreature, playerCreature, moveName)
		
		if score > bestScore then
			bestScore = score
			bestMove = moveName
		end
	end
	
	return bestMove or moves[1] or "Tackle"
end

--[[
	Selects a move for a wild creature (random strategy)
	@param foeCreature The wild creature
	@param playerCreature The player's creature
	@return string The selected move name
]]
function AIController.SelectWildMove(
	foeCreature: Creature,
	playerCreature: Creature
): string
	if not foeCreature or not foeCreature.CurrentMoves then
		return "Tackle"
	end
	
	local selectedMove = selectRandomMove(foeCreature.CurrentMoves)
	return selectedMove or "Tackle"
end

--[[
	Selects a move for a trainer's creature (smart strategy)
	@param foeCreature The trainer's creature
	@param playerCreature The player's creature
	@param difficulty The AI difficulty level
	@return string The selected move name
]]
function AIController.SelectTrainerMove(
	foeCreature: Creature,
	playerCreature: Creature,
	difficulty: AIDifficulty?
): string
	if not foeCreature or not foeCreature.CurrentMoves then
		return "Tackle"
	end
	
	local aiDifficulty = difficulty or "Smart"
	
	if aiDifficulty == "Random" then
		local selectedMove = selectRandomMove(foeCreature.CurrentMoves)
		return selectedMove or "Tackle"
	elseif aiDifficulty == "Smart" or aiDifficulty == "Expert" then
		local selectedMove = selectSmartMove(foeCreature, playerCreature, foeCreature.CurrentMoves)
		return selectedMove or "Tackle"
	end
	
	return "Tackle"
end

--[[
	Determines if the AI should switch creatures (for trainer battles)
	@param foeCreature The current creature
	@param playerCreature The player's creature
	@param availableCreatures Other creatures in the trainer's party
	@return shouldSwitch: boolean, switchToIndex: number?
]]
function AIController.ShouldSwitch(
	foeCreature: Creature,
	playerCreature: Creature,
	availableCreatures: {Creature}?
): (boolean, number?)
	-- Simple AI: don't switch for now
	-- This can be expanded to check type matchups and HP thresholds
	return false, nil
end

--[[
	Calculates escape chance for wild battles
	@param playerCreature The player's creature
	@param foeCreature The wild creature
	@param escapeAttempts Number of previous escape attempts
	@return boolean Whether escape succeeds
]]
function AIController.CalculateEscapeChance(
	playerCreature: Creature,
	foeCreature: Creature,
	escapeAttempts: number
): boolean
	if not playerCreature or not foeCreature then
		return false
	end
	
	-- Pokémon escape formula
	local playerSpeed = playerCreature.Stats.Speed or 1
	local foeSpeed = foeCreature.Stats.Speed or 1
	
	local speedRatio = (playerSpeed * 128) / foeSpeed
	local escapeValue = math.floor(speedRatio) + (30 * escapeAttempts)
	
	-- Cap at 255 (guaranteed escape)
	if escapeValue >= 255 then
		return true
	end
	
	-- Roll for escape
	return math.random(0, 255) < escapeValue
end

return AIController

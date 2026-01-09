local CreatureSystem = require(script.Parent.Parent:WaitForChild("CreatureSystem"))

local BattleSystemHelpers = {}

function BattleSystemHelpers.FindFirstAliveCreature(Party)
	return CreatureSystem.FindFirstAliveCreature(Party)
end

function BattleSystemHelpers.GetMovesForLevel(LearnableMoves, level)
	return CreatureSystem.GetMovesForLevel(LearnableMoves, level)
end

function BattleSystemHelpers.EnsurePartyAbilities(party)
	return CreatureSystem.EnsurePartyAbilities(party)
end

function BattleSystemHelpers.EnsurePartyMoves(party)
	return CreatureSystem.EnsurePartyMoves(party)
end

function BattleSystemHelpers.BuildStartingMovesFromLearnset(Learnset, level)
	return CreatureSystem.BuildStartingMovesFromLearnset(Learnset, level)
end

return BattleSystemHelpers


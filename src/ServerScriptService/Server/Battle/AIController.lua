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
local TypeChart = require(ReplicatedStorage.Shared.TypeChart)
local Status = require(ReplicatedStorage.Shared.Status)
local StatStages = require(ReplicatedStorage.Shared.StatStages)

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
local function extractMoveName(moveEntry: any): string?
	if type(moveEntry) == "string" then
		return moveEntry
	end
	if type(moveEntry) == "table" then
		if type(moveEntry.Name) == "string" then
			return moveEntry.Name
		end
		if type(moveEntry.Move) == "string" then
			return moveEntry.Move
		end
	end
	return nil
end

local function toMoveNameList(moves: {any}?): {string}
	local result: {string} = {}
	if type(moves) ~= "table" then
		return result
	end
	for _, entry in ipairs(moves) do
		local name = extractMoveName(entry)
		if name and MovesModule[name] then
			table.insert(result, name)
		end
	end
	return result
end

local function selectRandomMove(moves: {any}?): string?
	local moveNames = toMoveNameList(moves)
	if #moveNames == 0 then
		return "Tackle" -- Fallback move
	end
	return moveNames[math.random(1, #moveNames)]
end

local function getHPPercent(creature: Creature?): number
	if not creature or not creature.Stats then
		return 1
	end
	local currentHP = tonumber(creature.Stats.HP) or 0
	local maxHP = tonumber((creature.MaxStats and creature.MaxStats.HP) or creature.Stats.HP) or 1
	if maxHP <= 0 then
		return 0
	end
	return math.clamp(currentHP / maxHP, 0, 1)
end

local function getAccuracyMultiplier(moveData: Move): number
	-- Convention: Accuracy == 0 means always hit in this codebase (see DamageCalculator.CheckAccuracy).
	local acc = moveData.Accuracy
	if acc == nil or acc == 0 then
		return 1
	end
	return math.clamp((tonumber(acc) or 0) / 100, 0, 1)
end

local function getExpectedMultiHitCount(moveData: Move): number
	local mh = (moveData :: any).MultiHit
	if type(mh) ~= "table" then
		return 1
	end
	if mh.Fixed == true then
		return tonumber(mh.MinHits) or 1
	end
	local minHits = tonumber(mh.MinHits) or 1
	local maxHits = tonumber(mh.MaxHits) or minHits
	-- Standard 2-5 distribution used elsewhere: 2:35%, 3:35%, 4:15%, 5:15%
	if minHits == 2 and maxHits == 5 then
		return 3.1
	end
	-- Fallback: uniform expectation
	return (minHits + maxHits) / 2
end

local function getCritChanceForEstimate(attacker: Creature?, moveData: Move): number
	local critStage = 0
	if attacker then
		critStage = StatStages.GetStage(attacker, "CritStage") or 0
	end
	local highCrit = false
	if (moveData :: any).Flags and type((moveData :: any).Flags) == "table" then
		highCrit = ((moveData :: any).Flags :: any).highCrit == true
	end
	if highCrit then
		critStage += 1
	end
	critStage = math.clamp(critStage, 0, 3)
	-- Match DamageCalculator stages (Gen 8–9-ish):
	local byStage = {
		[0] = 1 / 24,
		[1] = 1 / 8,
		[2] = 1 / 2,
		[3] = 1,
	}
	return byStage[critStage] or (1 / 24)
end

local function estimateDamageNoRng(attacker: Creature, defender: Creature, moveData: Move, difficulty: AIDifficulty?): number
	-- IMPORTANT: Never use math.random here; AI evaluation must not consume RNG that impacts battle.
	if not attacker or not defender or not attacker.Stats or not defender.Stats then
		return 0
	end

	local category = (moveData.Category :: any) or "Physical"
	if category == "Status" or (moveData.BasePower or 0) <= 0 then
		return 0
	end

	local attackerLevel = attacker.Level or 1
	local levelFactor = math.floor((2 * attackerLevel) / 5) + 2

	local atkBase: number
	local defBase: number
	if category == "Special" then
		atkBase = tonumber((attacker.Stats :: any).SpecialAttack) or tonumber(attacker.Stats.Attack) or 1
		defBase = tonumber((defender.Stats :: any).SpecialDefense) or tonumber(defender.Stats.Defense) or 1
	else
		atkBase = tonumber(attacker.Stats.Attack) or 1
		defBase = tonumber(defender.Stats.Defense) or 1
	end
	defBase = math.max(1, defBase)

	-- Apply stage modifiers (approximate; no crit stage ignoring in estimate)
	local atkStage = StatStages.GetStage(attacker, category == "Special" and "SpecialAttack" or "Attack") or 0
	local defStage = StatStages.GetStage(defender, category == "Special" and "SpecialDefense" or "Defense") or 0
	local atk = StatStages.ApplyStage(atkBase, atkStage, false)
	local def = math.max(1, StatStages.ApplyStage(defBase, defStage, false))

	-- Burn halves Attack for physical damage in this codebase
	if category ~= "Special" then
		atk = math.floor(atk * Status.GetAttackMultiplier(attacker))
	end

	local basePower = tonumber(moveData.BasePower) or 0
	if basePower <= 0 then
		return 0
	end

	local baseDamage = math.floor((levelFactor * basePower * (atk / def)) / 50) + 2

	-- Type effectiveness and STAB (both deterministic)
	local moveType = (moveData :: any).Type
	local effectiveness = 1
	if moveType ~= nil and defender.Type then
		effectiveness = TypeChart.GetMultiplier(moveType, defender.Type :: any)
	end
	if effectiveness <= 0 then
		return 0
	end

	local stab = 1
	if moveType ~= nil and attacker.Type then
		for _, t in ipairs(attacker.Type :: any) do
			if t == moveType then
				stab = 1.5
				break
			end
		end
	end

	-- Expert considers expected crit value; Smart ignores for stability.
	local critMultiplier = 1
	if difficulty == "Expert" then
		local critChance = getCritChanceForEstimate(attacker, moveData)
		critMultiplier = 1 + (critChance * (1.5 - 1))
	end

	-- Accuracy as expectation
	local accuracyMult = getAccuracyMultiplier(moveData)

	-- Multi-hit expectation (score proxy)
	local hitCount = getExpectedMultiHitCount(moveData)

	local estimated = baseDamage * stab * effectiveness * critMultiplier * accuracyMult * hitCount
	return math.max(0, math.floor(estimated))
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
	moveName: string,
	difficulty: AIDifficulty?
): number
	local moveData = MovesModule[moveName]
	if not moveData then
		return 0
	end
	
	local score = 0

	local aiDifficulty = difficulty or "Smart"

	local isStatusMove = (moveData.Category == "Status") or ((moveData.BasePower or 0) <= 0)

	-- Priority bonus (helps finishers and tempo)
	if moveData.Priority and moveData.Priority > 0 then
		score += 15 + (moveData.Priority * 5)
	end

	-- Healing moves
	local healsPercent = tonumber((moveData :: any).HealsPercent)
	if healsPercent and healsPercent > 0 then
		local hpPct = getHPPercent(foeCreature)
		local missing = 1 - hpPct
		local healFrac = math.clamp(healsPercent / 100, 0, 1)
		local effectiveHeal = math.min(missing, healFrac)
		-- Strongly prefer healing when low; weaker preference when near full.
		score += effectiveHeal * 220
		if hpPct <= 0.5 then
			score += 40
		end
		if hpPct <= 0.25 then
			score += 70
		end
	end

	-- Stat stage changes (buffs/debuffs)
	local statChanges = (moveData :: any).StatChanges
	if type(statChanges) == "table" then
		for _, sc in ipairs(statChanges) do
			if type(sc) == "table" and type(sc.Stat) == "string" and type(sc.Stages) == "number" then
				local chance = math.clamp((tonumber(sc.Chance) or 100) / 100, 0, 1)
				local target = sc.Target
				if type(target) ~= "string" then
					target = (sc.Stages > 0) and "Self" or "Opponent"
				end
				local statWeight = 10
				if sc.Stat == "Attack" then
					statWeight = 25
				elseif sc.Stat == "Defense" then
					statWeight = 20
				elseif sc.Stat == "Speed" then
					statWeight = 22
				end

				if target == "Self" then
					score += (sc.Stages * statWeight) * chance
				elseif target == "Opponent" then
					-- Lowering opponent stats is good (negative stages => positive score).
					score += (-sc.Stages * statWeight) * chance
				end
			end
		end
	end

	-- Status infliction moves
	local statusEffect = (moveData :: any).StatusEffect
	if type(statusEffect) == "string" then
		local chance = math.clamp((tonumber((moveData :: any).StatusChance) or 100) / 100, 0, 1)
		local canInflict = Status.CanBeInflicted(playerCreature, statusEffect :: any)
		if canInflict then
			local value = 25
			if statusEffect == "SLP" then
				value = 60
			elseif statusEffect == "FRZ" then
				value = 50
			elseif statusEffect == "PAR" then
				value = 40
			elseif statusEffect == "BRN" then
				value = 35
			elseif statusEffect == "TOX" then
				value = 35
			elseif statusEffect == "PSN" then
				value = 30
			end
			score += value * chance
		end
	end

	-- Damaging move evaluation (deterministic estimate)
	if not isStatusMove and (moveData.BasePower or 0) > 0 then
		local estimatedDamage = estimateDamageNoRng(foeCreature, playerCreature, moveData, aiDifficulty)
		score += estimatedDamage

		-- Prefer KOs (especially on Expert)
		local defenderHP = tonumber((playerCreature.Stats and playerCreature.Stats.HP) or 0) or 0
		if defenderHP > 0 and estimatedDamage >= defenderHP then
			score += (aiDifficulty == "Expert") and 260 or 180
		end

		-- Type effectiveness tuning (using existing helper string for readability)
		if moveData.Type and playerCreature.Type then
			local eff = DamageCalculator.GetEffectivenessString(moveData.Type :: any, playerCreature.Type :: any)
			if eff == "SuperEffective" then
				score += 40
			elseif eff == "NotVeryEffective" then
				score -= 20
			elseif eff == "Immune" then
				return 0
			end
		end

		-- Recoil penalty (avoid suiciding)
		local recoilPercent = tonumber((moveData :: any).RecoilPercent)
		if recoilPercent and recoilPercent > 0 then
			local expectedRecoil = estimatedDamage * (recoilPercent / 100)
			local hpPct = getHPPercent(foeCreature)
			local penaltyScale = (hpPct <= 0.35) and 1.2 or 0.7
			score -= expectedRecoil * penaltyScale
		end
	end

	-- Slight preference for reliable moves
	local accMult = getAccuracyMultiplier(moveData)
	if accMult >= 0.9 then
		score += 8
	elseif accMult <= 0.7 then
		score -= 8
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
	moves: {any}?,
	difficulty: AIDifficulty?
): string?
	local moveNames = toMoveNameList(moves)
	if #moveNames == 0 then
		return "Tackle"
	end
	
	local bestMove = nil
	local bestScore = -1
	
	for _, moveName in ipairs(moveNames) do
		local score = evaluateMove(foeCreature, playerCreature, moveName, difficulty)
		
		if score > bestScore then
			bestScore = score
			bestMove = moveName
		end
	end
	
	return bestMove or moveNames[1] or "Tackle"
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
		local selectedMove = selectSmartMove(foeCreature, playerCreature, foeCreature.CurrentMoves, aiDifficulty)
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
	availableCreatures: {Creature}?,
	difficulty: AIDifficulty?
): (boolean, number?)
	local aiDifficulty = difficulty or "Smart"
	if type(availableCreatures) ~= "table" or #availableCreatures == 0 then
		return false, nil
	end
	if not foeCreature or not foeCreature.Stats or foeCreature.Stats.HP <= 0 then
		return false, nil
	end
	if not playerCreature or not playerCreature.Stats or playerCreature.Stats.HP <= 0 then
		return false, nil
	end

	local hpPct = getHPPercent(foeCreature)
	local switchThreshold = (aiDifficulty == "Expert") and 0.35 or 0.25

	-- If we can likely KO this turn, do not switch.
	local bestStayMove = selectSmartMove(foeCreature, playerCreature, foeCreature.CurrentMoves, aiDifficulty)
	if bestStayMove and MovesModule[bestStayMove] then
		local est = estimateDamageNoRng(foeCreature, playerCreature, MovesModule[bestStayMove], aiDifficulty)
		local defenderHP = tonumber((playerCreature.Stats and playerCreature.Stats.HP) or 0) or 0
		if defenderHP > 0 and est >= defenderHP then
			return false, nil
		end
	end

	-- Determine if current matchup is bad: all damaging moves are resisted/immune.
	local hasGoodDamageOption = false
	local moveNames = toMoveNameList(foeCreature.CurrentMoves)
	for _, moveName in ipairs(moveNames) do
		local md = MovesModule[moveName]
		if md and (md.BasePower or 0) > 0 and md.Category ~= "Status" then
			local eff = 1
			if (md :: any).Type ~= nil and playerCreature.Type then
				eff = TypeChart.GetMultiplier((md :: any).Type, playerCreature.Type :: any)
			end
			if eff >= 1 then
				hasGoodDamageOption = true
				break
			end
		end
	end

	local inBadMatchup = not hasGoodDamageOption
	if hpPct > switchThreshold and not inBadMatchup then
		return false, nil
	end

	-- Find best alternative creature to switch into (based on best move score vs the player).
	local bestIndex: number? = nil
	local bestScore = -math.huge

	for i, c in ipairs(availableCreatures) do
		if c and c ~= foeCreature then
			local cHP = (c.Stats and c.Stats.HP) or 0
			if type(cHP) == "number" and cHP > 0 then
				local bestMove = selectSmartMove(c, playerCreature, c.CurrentMoves, aiDifficulty)
				local score = -math.huge
				if bestMove and MovesModule[bestMove] then
					score = evaluateMove(c, playerCreature, bestMove, aiDifficulty)
				end
				-- Prefer healthier switch-ins when very low.
				score += getHPPercent(c) * 25
				if score > bestScore then
					bestScore = score
					bestIndex = i
				end
			end
		end
	end

	if not bestIndex then
		return false, nil
	end

	-- Only switch if we are low HP or in a clearly bad matchup.
	return true, bestIndex
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

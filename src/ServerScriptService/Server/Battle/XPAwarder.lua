--!strict
-- XPAwarder.lua
-- Responsible for awarding XP and producing client step payloads (XP, LevelUp, MoveLearned/ReplacePrompt)
-- Extracted from ServerFunctions to a dedicated, testable module

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DBG = require(ReplicatedStorage.Shared.DBG)
local CreaturesModule = require(ReplicatedStorage.Shared.Creatures)
local ClientData = require(ServerScriptService.Server.ClientData)

local Battle = require(ServerScriptService.Server.Battle)
local XPManager = Battle.XPManager

local XPAwarder = {}

-- Awards XP for defeating multiple creatures, returns steps for client to display
function XPAwarder.AwardBattleXPForAll(Player: Player, defeatedCreatures: {any}, battle: any): {any}
	local xpSteps: {any} = {}
	if not defeatedCreatures or #defeatedCreatures == 0 or not battle then return xpSteps end

	local PlayerData = ClientData:Get(Player)
	if not PlayerData or not PlayerData.Party then return xpSteps end

	local isTrainerBattle = (battle.Type == "Trainer")
	local activeCreature = battle.PlayerCreature
	if not activeCreature or not activeCreature.Stats or activeCreature.Stats.HP <= 0 then
		return xpSteps
	end

	-- Accumulate XP across all defeated creatures
	local totalXP = 0
	for _, defeatedCreature in ipairs(defeatedCreatures) do
		local xpAmount = XPManager.CalculateXPYield(defeatedCreature, activeCreature, isTrainerBattle, 1, false)
		totalXP += xpAmount
	end

	if totalXP > 0 then
		DBG:print("[XP] Before awarding - Level:", activeCreature.Level, "Experience:", activeCreature.Experience or 0, "XPProgress:", activeCreature.XPProgress or 0)
		local levelsGained = XPManager.AwardXP(activeCreature, totalXP)
		local creatureName = activeCreature.Nickname or activeCreature.Name
		DBG:print("[XP] After awarding - Level:", activeCreature.Level, "Experience:", activeCreature.Experience or 0, "XPProgress:", activeCreature.XPProgress or 0, "LevelsGained:", levelsGained)

		-- Persist active creature to party slot
		do
			local pd = ClientData:Get(Player)
			local slotIndex = battle.PlayerCreatureIndex
			if pd and pd.Party and slotIndex and pd.Party[slotIndex] then
				local slot = pd.Party[slotIndex]
				slot.Level = activeCreature.Level
				slot.Experience = activeCreature.Experience
				slot.XPProgress = activeCreature.XPProgress
				slot.Stats = activeCreature.Stats
				slot.MaxStats = activeCreature.MaxStats
				slot.CurrentMoves = activeCreature.CurrentMoves or slot.CurrentMoves
				slot.LearnedMoves = activeCreature.LearnedMoves or slot.LearnedMoves
			end
			if pd then
				ClientData:UpdateClientData(Player, pd)
			end
		end

		table.insert(xpSteps, {
			Type = "XP",
			Creature = creatureName,
			Amount = totalXP,
			IsShared = false,
			IsPlayer = true,
			XPProgress = activeCreature.XPProgress or 0,
			CurrentLevel = activeCreature.Level,
		})

		if levelsGained and levelsGained > 0 then
			local startLevel = activeCreature.Level - levelsGained
			for i = 1, levelsGained do
				local level = startLevel + i
				table.insert(xpSteps, { Type = "LevelUp", Creature = creatureName, Level = level, IsPlayer = true })
				-- Learned moves at this level
				local species = CreaturesModule[activeCreature.Name]
				local learnset = species and species.Learnset
				local movesAtLevel = learnset and learnset[level]
				if type(movesAtLevel) == "table" then
					local cur = activeCreature.CurrentMoves or {}
					local function hasMove(mv: string): boolean
						for _, m in ipairs(cur) do
							if m == mv then return true end
						end
						return false
					end
					for _, moveName in ipairs(movesAtLevel) do
						if hasMove(moveName) or #cur < 4 then
							table.insert(xpSteps, { Type = "MoveLearned", Creature = creatureName, Move = moveName, IsPlayer = true })
						else
							table.insert(xpSteps, {
								Type = "MoveReplacePrompt",
								Creature = creatureName,
								Move = moveName,
								CurrentMoves = table.clone(cur),
								SlotIndex = battle.PlayerCreatureIndex,
								IsPlayer = true,
							})
						end
					end
				end
			end
		end
	end

	-- XP Spread
	local xpSpreadEnabled = (PlayerData.Settings and PlayerData.Settings.XPSpread) or false
	if xpSpreadEnabled and totalXP > 0 then
		local sharedAmount = math.floor(totalXP * 0.5)
		if sharedAmount > 0 then
			for si, creature in ipairs(PlayerData.Party) do
				if creature ~= activeCreature and creature.Stats and creature.Stats.HP > 0 then
					local shareLevels = XPManager.AwardXP(creature, sharedAmount)
					local shareCreatureName = creature.Nickname or creature.Name
					-- Learned moves (auto) on spread
					if type(creature._MovesLearnedRecently) == "table" then
						local cur = creature.CurrentMoves or {}
						local function hasMove(mv: string): boolean
							for _, m in ipairs(cur) do
								if m == mv then return true end
							end
							return false
						end
						for _, moveName in ipairs(creature._MovesLearnedRecently) do
							if hasMove(moveName) or #cur < 4 then
								table.insert(xpSteps, { Type = "MoveLearned", Creature = shareCreatureName, Move = moveName, IsPlayer = true })
							else
								table.insert(xpSteps, {
									Type = "MoveReplacePrompt",
									Creature = shareCreatureName,
									Move = moveName,
									CurrentMoves = table.clone(cur),
									SlotIndex = si,
									IsPlayer = true,
								})
							end
						end
					end
				end
			end
		end
	end

	if #xpSteps > 0 then
		ClientData:UpdateClientData(Player, PlayerData)
	end

	return xpSteps
end

-- Awards XP for defeating a single creature (legacy compatibility)
function XPAwarder.AwardBattleXP(Player: Player, defeatedCreature: any, battle: any): {any}
	local xpSteps: {any} = {}
	if not defeatedCreature or not battle then return xpSteps end

	local PlayerData = ClientData:Get(Player)
	if not PlayerData or not PlayerData.Party then return xpSteps end

	local isTrainerBattle = (battle.Type == "Trainer")
	local activeCreature = battle.PlayerCreature
	if not activeCreature or not activeCreature.Stats or activeCreature.Stats.HP <= 0 then
		return xpSteps
	end

	local xpAmount = XPManager.CalculateXPYield(defeatedCreature, activeCreature, isTrainerBattle, 1, false)
	if xpAmount > 0 then
		local levelsGained = XPManager.AwardXP(activeCreature, xpAmount)
		local creatureName = activeCreature.Nickname or activeCreature.Name

		table.insert(xpSteps, { Type = "XP", Creature = creatureName, Amount = xpAmount, IsPlayer = true })

		if levelsGained and levelsGained > 0 then
			local startLevel = activeCreature.Level - levelsGained
			for i = 1, levelsGained do
				local level = startLevel + i
				table.insert(xpSteps, { Type = "LevelUp", Creature = creatureName, Level = level, IsPlayer = true })
				-- Moves at this level (same behavior as AwardForAll)
				local species = CreaturesModule[activeCreature.Name]
				local learnset = species and species.Learnset
				local movesAtLevel = learnset and learnset[level]
				if type(movesAtLevel) == "table" then
					local cur = activeCreature.CurrentMoves or {}
					local function hasMove(mv: string): boolean
						for _, m in ipairs(cur) do
							if m == mv then return true end
						end
						return false
					end
					for _, moveName in ipairs(movesAtLevel) do
						if hasMove(moveName) or #cur < 4 then
							table.insert(xpSteps, { Type = "MoveLearned", Creature = creatureName, Move = moveName, IsPlayer = true })
						else
							table.insert(xpSteps, {
								Type = "MoveReplacePrompt",
								Creature = creatureName,
								Move = moveName,
								CurrentMoves = table.clone(cur),
								SlotIndex = battle.PlayerCreatureIndex,
								IsPlayer = true,
							})
						end
					end
				end
			end
		end
	end

	-- XP spread (same rule)
	local xpSpreadEnabled = (PlayerData.Settings and PlayerData.Settings.XPSpread) or false
	if xpSpreadEnabled and xpAmount and xpAmount > 0 then
		local sharedAmount = math.floor(xpAmount * 0.5)
		if sharedAmount > 0 then
			for si, creature in ipairs(PlayerData.Party) do
				if creature ~= activeCreature and creature.Stats and creature.Stats.HP > 0 then
					XPManager.AwardXP(creature, sharedAmount)
					local shareCreatureName = creature.Nickname or creature.Name
					if type(creature._MovesLearnedRecently) == "table" then
						local cur = creature.CurrentMoves or {}
						local function hasMove(mv: string): boolean
							for _, m in ipairs(cur) do
								if m == mv then return true end
							end
							return false
						end
						for _, moveName in ipairs(creature._MovesLearnedRecently) do
							if hasMove(moveName) or #cur < 4 then
								table.insert(xpSteps, { Type = "MoveLearned", Creature = shareCreatureName, Move = moveName, IsPlayer = true })
							else
								table.insert(xpSteps, {
									Type = "MoveReplacePrompt",
									Creature = shareCreatureName,
									Move = moveName,
									CurrentMoves = table.clone(cur),
									SlotIndex = si,
									IsPlayer = true,
								})
							end
						end
					end
				end
			end
		end
	end

	if #xpSteps > 0 then
		ClientData:UpdateClientData(Player, PlayerData)
	end

	return xpSteps
end

return XPAwarder



--!strict
-- XPAwarder.lua
-- Responsible for awarding XP and producing client step payloads (XP, LevelUp, MoveLearned/ReplacePrompt)
-- Extracted from ServerFunctions to a dedicated, testable module

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local MarketplaceService = game:GetService("MarketplaceService")

local DBG = require(ReplicatedStorage.Shared.DBG)
local CreaturesModule = require(ReplicatedStorage.Shared.Creatures)
local ClientData = require(ServerScriptService.Server.ClientData)

local Battle = require(ServerScriptService.Server.Battle)
local XPManager = Battle.XPManager

-- Lazy require to avoid circular dependency
local ChallengesSystem = nil
local function GetChallengesSystem()
	if not ChallengesSystem then
		pcall(function()
			ChallengesSystem = require(ServerScriptService.Server.ChallengesSystem)
		end)
	end
	return ChallengesSystem
end

local XPAwarder = {}

-- EXP Share+ gamepass ID
local EXPSHAREPLUS_GAMEPASS_ID = 1656774306

--[[
	Checks if player owns EXP Share+ gamepass
	@param player The player to check
	@return boolean True if player owns EXP Share+ gamepass
]]
local function hasEXPSharePlus(player: Player): boolean
	local success, ownsGamepass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, EXPSHAREPLUS_GAMEPASS_ID)
	end)
	return success and ownsGamepass == true
end

--[[
	Counts the number of non-fainted Creatures in the party
	@param party The player's party array
	@return number Count of non-fainted Creatures
]]
local function countNonFaintedPartyMembers(party: {any}): number
	local count = 0
	for _, creature in ipairs(party) do
		local hp = creature.Stats and creature.Stats.HP
		if type(hp) == "number" and hp > 0 then
			count = count + 1
		end
	end
	return count
end

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

	local xpSpreadEnabled = (PlayerData.Settings and PlayerData.Settings.XPSpread) or false
	
	-- Determine participant count based on EXP Share setting
	local participantCount = 1
	if xpSpreadEnabled then
		participantCount = countNonFaintedPartyMembers(PlayerData.Party)
	end

	-- Accumulate XP across all defeated creatures using correct participant count
	local totalXP = 0
	for _, defeatedCreature in ipairs(defeatedCreatures) do
		local xpAmount = XPManager.CalculateXPYield(defeatedCreature, activeCreature, isTrainerBattle, participantCount, false)
		totalXP += xpAmount
	end

	-- Apply EXP Share+ bonus (+30%) if EXP Share is enabled and player owns the gamepass
	if xpSpreadEnabled and hasEXPSharePlus(Player) then
		totalXP = math.floor(totalXP * 1.3)
	end

	-- Track level changes for challenge progress
	local levelChanges = {}

	-- Award XP to all eligible Pokémon
	if totalXP > 0 then
		local activeSlotIndex = battle.PlayerCreatureIndex
		-- Award XP to all non-fainted Pokémon (including battler when EXP Share is on)
		for si, creature in ipairs(PlayerData.Party) do
			local hp = creature.Stats and creature.Stats.HP
			if type(hp) == "number" and hp > 0 then
				-- When EXP Share is off, only award to the active creature (by slot index)
				if not xpSpreadEnabled and si ~= activeSlotIndex then
					-- Skip non-active creatures when EXP Share is off
				else
					local prevLevel = creature.Level
				local levelsGained = XPManager.AwardXP(creature, totalXP)
				local creatureName = creature.Nickname or creature.Name
				local newLevel = creature.Level

				-- Track level change for challenge progress
				if levelsGained and levelsGained > 0 then
					table.insert(levelChanges, { PreviousLevel = prevLevel, NewLevel = newLevel })
				end

				-- Add XP step
				table.insert(xpSteps, {
					Type = "XP",
					Creature = creatureName,
					Amount = totalXP,
					IsShared = xpSpreadEnabled and creature ~= activeCreature,
					IsPlayer = true,
					XPProgress = creature.XPProgress or 0,
					CurrentLevel = creature.Level,
				})

				-- Add level up steps
				if levelsGained and levelsGained > 0 then
					local startLevel = creature.Level - levelsGained
					for i = 1, levelsGained do
						local level = startLevel + i
						local xpProgress = (i == levelsGained) and (creature.XPProgress or 0) or nil
						table.insert(xpSteps, { 
							Type = "LevelUp", 
							Creature = creatureName, 
							Level = level, 
							IsPlayer = true,
							XPProgress = xpProgress,
						})

						-- Learned moves at this level
						local species = CreaturesModule[creature.Name]
						local learnset = species and species.Learnset
						local movesAtLevel = learnset and learnset[level]
						if type(movesAtLevel) == "table" then
							local cur = creature.CurrentMoves or {}
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
										SlotIndex = si,
										IsPlayer = true,
									})
								end
							end
						end
					end
				end

				-- Learned moves from XP award (for non-level-up moves)
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
							table.insert(xpSteps, { Type = "MoveLearned", Creature = creatureName, Move = moveName, IsPlayer = true })
						else
							table.insert(xpSteps, {
								Type = "MoveReplacePrompt",
								Creature = creatureName,
								Move = moveName,
								CurrentMoves = table.clone(cur),
								SlotIndex = si,
								IsPlayer = true,
							})
						end
					end
				end
				end -- end else block
			end
		end

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

		-- Add XPSpread message if EXP Share is enabled and multiple Pokémon received XP
		if xpSpreadEnabled and participantCount > 1 then
			table.insert(xpSteps, {
				Type = "XPSpread",
				IsPlayer = true,
			})
		end
	end

	if #xpSteps > 0 then
		ClientData:UpdateClientData(Player, PlayerData)
		
		-- Update challenge progress for ReachLevel (for all creatures that leveled up)
		if #levelChanges > 0 then
			pcall(function()
				local challenges = GetChallengesSystem()
				if challenges then
					-- Check each creature that leveled up to see if any crossed a challenge threshold
					for _, change in ipairs(levelChanges) do
						challenges.UpdateProgress(Player, "ReachLevel", 0, {
							PreviousLevel = change.PreviousLevel,
							NewLevel = change.NewLevel,
						})
					end
				end
			end)
		end
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

	local xpSpreadEnabled = (PlayerData.Settings and PlayerData.Settings.XPSpread) or false
	
	-- Determine participant count based on EXP Share setting
	local participantCount = 1
	if xpSpreadEnabled then
		participantCount = countNonFaintedPartyMembers(PlayerData.Party)
	end

	-- Calculate XP using correct participant count
	local xpAmount = XPManager.CalculateXPYield(defeatedCreature, activeCreature, isTrainerBattle, participantCount, false)
	
	-- Apply EXP Share+ bonus (+30%) if EXP Share is enabled and player owns the gamepass
	if xpSpreadEnabled and hasEXPSharePlus(Player) then
		xpAmount = math.floor(xpAmount * 1.3)
	end
	
	-- Track level changes for challenge progress
	local levelChanges = {}

	-- Award XP to all eligible Pokémon
	if xpAmount > 0 then
		local activeSlotIndex = battle.PlayerCreatureIndex
		-- Award XP to all non-fainted Pokémon (including battler when EXP Share is on)
		for si, creature in ipairs(PlayerData.Party) do
			local hp = creature.Stats and creature.Stats.HP
			if type(hp) == "number" and hp > 0 then
				-- When EXP Share is off, only award to the active creature (by slot index)
				if not xpSpreadEnabled and si ~= activeSlotIndex then
					-- Skip non-active creatures when EXP Share is off
				else
					local prevLevel = creature.Level
					local levelsGained = XPManager.AwardXP(creature, xpAmount)
					local creatureName = creature.Nickname or creature.Name
					local newLevel = creature.Level

					-- Track level change for challenge progress
					if levelsGained and levelsGained > 0 then
						table.insert(levelChanges, { PreviousLevel = prevLevel, NewLevel = newLevel })
					end

					-- Add XP step
					table.insert(xpSteps, {
						Type = "XP",
						Creature = creatureName,
						Amount = xpAmount,
						IsShared = xpSpreadEnabled and creature ~= activeCreature,
						IsPlayer = true,
						XPProgress = creature.XPProgress or 0,
						CurrentLevel = creature.Level,
					})

					-- Add level up steps
					if levelsGained and levelsGained > 0 then
						local startLevel = creature.Level - levelsGained
						for i = 1, levelsGained do
							local level = startLevel + i
							local xpProgress = (i == levelsGained) and (creature.XPProgress or 0) or nil
							table.insert(xpSteps, { 
								Type = "LevelUp", 
								Creature = creatureName, 
								Level = level, 
								IsPlayer = true,
								XPProgress = xpProgress,
							})

							-- Learned moves at this level
							local species = CreaturesModule[creature.Name]
							local learnset = species and species.Learnset
							local movesAtLevel = learnset and learnset[level]
							if type(movesAtLevel) == "table" then
								local cur = creature.CurrentMoves or {}
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
											SlotIndex = si,
											IsPlayer = true,
										})
									end
								end
							end
						end
					end

					-- Learned moves from XP award (for non-level-up moves)
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
								table.insert(xpSteps, { Type = "MoveLearned", Creature = creatureName, Move = moveName, IsPlayer = true })
							else
								table.insert(xpSteps, {
									Type = "MoveReplacePrompt",
									Creature = creatureName,
									Move = moveName,
									CurrentMoves = table.clone(cur),
									SlotIndex = si,
									IsPlayer = true,
								})
							end
						end
					end
				end -- end else block
			end
		end

		-- Add XPSpread message if EXP Share is enabled and multiple Pokémon received XP
		if xpSpreadEnabled and participantCount > 1 then
			table.insert(xpSteps, {
				Type = "XPSpread",
				IsPlayer = true,
			})
		end
	end

	if #xpSteps > 0 then
		ClientData:UpdateClientData(Player, PlayerData)
		
		-- Update challenge progress for ReachLevel (for all creatures that leveled up)
		if #levelChanges > 0 then
			pcall(function()
				local challenges = GetChallengesSystem()
				if challenges then
					for _, change in ipairs(levelChanges) do
						challenges.UpdateProgress(Player, "ReachLevel", 0, {
							PreviousLevel = change.PreviousLevel,
							NewLevel = change.NewLevel,
						})
					end
				end
			end)
		end
	end

	return xpSteps
end

return XPAwarder



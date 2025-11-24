--!strict
--[[
	CreatureSystem.lua
	Handles creature/party management: switching, evolutions, helper functions
	Separated from ServerFunctions for better organization
]]

local CreatureSystem = {}

-- Dependencies (will be injected)
local ClientData: any = nil
local DBG: any = nil
local Events: any = nil
local CreaturesModule: any = nil
local MovesModule: any = nil
local AbilitiesModule: any = nil
local StatCalc: any = nil
local XPManager: any = nil
local ReplicatedStorage: any = nil

--[[
	Initialize CreatureSystem with dependencies
]]
function CreatureSystem.Initialize(dependencies: {[string]: any})
	ClientData = dependencies.ClientData
	DBG = dependencies.DBG
	Events = dependencies.Events
	CreaturesModule = dependencies.CreaturesModule
	MovesModule = dependencies.MovesModule
	AbilitiesModule = dependencies.AbilitiesModule
	StatCalc = dependencies.StatCalc
	XPManager = dependencies.XPManager
	ReplicatedStorage = dependencies.ReplicatedStorage
end

--[[
	Find the first alive creature in a party
	@param Party The party array
	@return Creature?, number? The creature and its index, or nil
]]
function CreatureSystem.FindFirstAliveCreature(Party: {any}?): (any?, number?)
	if not Party or #Party == 0 then
		return nil, nil
	end
	
	for i = 1, #Party do
		local creature = Party[i]
		local hp = (creature.CurrentHP ~= nil) and creature.CurrentHP or (creature.Stats and creature.Stats.HP)
		if creature and hp and hp > 0 then
			return creature, i
		end
	end
	
	return nil, nil
end

--[[
	Get moves for a creature at a given level from LearnableMoves
	@param LearnableMoves The learnable moves table
	@param level The creature level
	@return {string} Array of move names
]]
function CreatureSystem.GetMovesForLevel(LearnableMoves: any, level: number): {string}
	local moves: {string} = {}
	if not LearnableMoves then return moves end
	
	-- Convert move table references to move names
	local function getMoveNameFromTable(moveTable: any): string?
		if not moveTable then return nil end
		for moveName, moveData in pairs(MovesModule) do
			if moveData == moveTable then
				return moveName
			end
		end
		return nil
	end
	
	if LearnableMoves[1] then 
		local moveName = getMoveNameFromTable(LearnableMoves[1])
		if moveName then moves[1] = moveName end
	end
	if level >= 10 and LearnableMoves[2] then 
		local moveName = getMoveNameFromTable(LearnableMoves[2])
		if moveName then moves[2] = moveName end
	end
	if level >= 25 and LearnableMoves[3] then 
		local moveName = getMoveNameFromTable(LearnableMoves[3])
		if moveName then moves[3] = moveName end
	end
	if level >= 45 and LearnableMoves[4] then 
		local moveName = getMoveNameFromTable(LearnableMoves[4])
		if moveName then moves[4] = moveName end
	end
	return moves
end

--[[
	Ensure all party creatures have an Ability assigned
	@param party The party array
]]
function CreatureSystem.EnsurePartyAbilities(party: {any}?)
	if not party then
		return
	end

	for _, creature in ipairs(party) do
		if creature and (creature.Ability == nil or creature.Ability == "") and type(creature.Name) == "string" then
			local ability = AbilitiesModule.SelectAbility(creature.Name, false)
			if ability ~= nil then
				creature.Ability = ability
			end
		end
	end
end

--[[
	Ensure all party creatures have CurrentMoves derived from species Learnset
	@param party The party array
]]
function CreatureSystem.EnsurePartyMoves(party: {any}?)
	if not party then
		return
	end

	local Creatures = CreaturesModule
	for _, creature in ipairs(party) do
		if creature and (creature.CurrentMoves == nil or #creature.CurrentMoves == 0) then
			local def = creature.Name and Creatures[creature.Name]
			if def and def.Learnset then
				local level = creature.Level or 1
				local all = {}
				for lvl, moveList in pairs(def.Learnset) do
					for _, mv in ipairs(moveList) do
						table.insert(all, { lvl = lvl, move = mv })
					end
				end
				table.sort(all, function(a, b)
					if a.lvl == b.lvl then
						return a.move < b.move
					end
					return a.lvl < b.lvl
				end)
				local current, learned = {}, {}
				local recent = {}
				for i = #all, 1, -1 do
					local entry = all[i]
					if entry.lvl <= level and not table.find(recent, entry.move) then
						table.insert(recent, entry.move)
						if #recent == 4 then
							break
						end
					end
				end
				for i = #recent, 1, -1 do
					table.insert(current, recent[i])
					learned[recent[i]] = true
				end
				if #current < 4 then
					for _, entry in ipairs(all) do
						if entry.lvl <= level and not learned[entry.move] then
							table.insert(current, entry.move)
							learned[entry.move] = true
							if #current == 4 then
								break
							end
						end
					end
				end
				creature.CurrentMoves = current
				creature.LearnedMoves = learned
			end
		end
	end
end

--[[
	Build starting moves (Pokémon-style) for a creature at a given level
	@param Learnset The learnset table
	@param level The creature level
	@return {string}, {[string]: boolean} Current moves and learned moves map
]]
function CreatureSystem.BuildStartingMovesFromLearnset(Learnset: any, level: number): ({string}, {[string]: boolean})
	local currentMoves: {string} = {}
	local learned: {[string]: boolean} = {}
	if not Learnset or not level then return currentMoves, learned end

	local all = {}
	for lvl, moveList in pairs(Learnset) do
		for _, mv in ipairs(moveList) do
			table.insert(all, { lvl = lvl, move = mv })
		end
	end
	table.sort(all, function(a, b)
		if a.lvl == b.lvl then return a.move < b.move end
		return a.lvl < b.lvl
	end)

	local recent = {}
	for i = #all, 1, -1 do
		local entry = all[i]
		if entry.lvl <= level and not table.find(recent, entry.move) then
			table.insert(recent, entry.move)
			if #recent == 4 then break end
		end
	end
	-- assign oldest->newest for consistency
	for i = #recent, 1, -1 do
		table.insert(currentMoves, recent[i])
		learned[recent[i]] = true
	end

	if #currentMoves < 4 then
		for _, entry in ipairs(all) do
			if entry.lvl <= level and not learned[entry.move] then
				table.insert(currentMoves, entry.move)
				learned[entry.move] = true
				if #currentMoves == 4 then break end
			end
		end
	end

	return currentMoves, learned
end

--[[
	Check all party creatures for evolution after battle
	@param Player The player
]]
function CreatureSystem.CheckPartyEvolutions(Player: Player)
	local PlayerData = ClientData:Get(Player)
	if not PlayerData or not PlayerData.Party then
		return
	end
	
	DBG:print("=== CHECKING PARTY EVOLUTIONS ===")
	DBG:print("Player:", Player.Name)
	DBG:print("Party size:", PlayerData.Party and #PlayerData.Party or "nil")
	
	local evolvedCreatures = {}
	
	-- Check each creature in the party
	for i, creature in ipairs(PlayerData.Party) do
		if creature and creature.Stats and creature.Stats.HP > 0 then
			DBG:print("[Evolution] Checking creature", i, ":", creature.Name, "Level:", creature.Level, "HP:", creature.Stats.HP)
			local shouldEvolve, evolvedName = XPManager.CheckEvolution(creature)
			DBG:print("[Evolution] Creature", i, "evolution check result - shouldEvolve:", shouldEvolve, "evolvedName:", evolvedName)
			if shouldEvolve then
				DBG:print("Creature", i, "can evolve:", creature.Name, "Level:", creature.Level)
				
				local oldName = creature.Nickname or creature.Name
				local oldSpecies = creature.Name
				
				local creatureData = CreaturesModule[creature.Name]
				local newSpecies = creatureData and creatureData.EvolvesInto
				
				local success, newName = XPManager.EvolveCreature(creature)
				if success and newSpecies then
					table.insert(evolvedCreatures, {
						oldName = oldName,
						oldSpecies = oldSpecies,
						newSpecies = newSpecies,
						nickname = creature.Nickname
					})
					DBG:print("Successfully evolved creature", i, "from", oldSpecies, "to", newSpecies)
				else
					DBG:warn("Failed to evolve creature", i, ":", creature.Name)
				end
			end
		end
	end
	
	-- If any creatures evolved, notify client
	if #evolvedCreatures > 0 then
		DBG:print("=== EVOLUTION SUMMARY ===")
		DBG:print("Total evolutions:", #evolvedCreatures)
		for i, evolution in ipairs(evolvedCreatures) do
			DBG:print("Evolution", i, ":", evolution.oldSpecies, "->", evolution.newSpecies)
		end
		
		if Events and Events.Communicate then
			for _, evolution in ipairs(evolvedCreatures) do
				Events.Communicate:FireClient(Player, "Evolution", {
					OldName = evolution.oldName,
					OldSpecies = evolution.oldSpecies,
					NewSpecies = evolution.newSpecies,
					Nickname = evolution.nickname
				})
				DBG:print("[Evolution] Sent evolution event to client:", evolution.oldSpecies, "->", evolution.newSpecies)
			end
		end
	else
		DBG:print("No evolutions occurred")
	end
end

return CreatureSystem


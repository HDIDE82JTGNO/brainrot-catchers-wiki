local ClientData = {}

local UseDebugData = true :: boolean -- Debug data does NOT save.

local DBG = require(game:GetService("ReplicatedStorage").Shared.DBG)
local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local Moves = require(game:GetService("ReplicatedStorage").Shared.Moves)
local Abilities = require(game:GetService("ReplicatedStorage").Shared.Abilities)

-- Forward declaration so helper functions capture the same reference
local DebugData

--[[
LastChunk = "Chunk1",
LeaveData = {
		Position = {
			X = 24.1,
			Y = -0.115,
			Z = -147.36
		},
		Rotation = {
			X = 0,
			Y = 0,
			Z = 0,
			W = 1
		}
	},



LastChunk = "Chunk2",
LeaveData = {
		Position = {
			X = 20.56,
			Y = 1.546,
			Z = -694.21
		},
		Rotation = {
			X = 0,
			Y = 0,
			Z = 0,
			W = 1
		}
	},
]]

--[[
-1171.74, 2.821, -827.953
]]

--[[
Outside 1st gym

LastChunk = "Chunk5", 
	LeaveData = {
		Position = { 
			X = -84,
			Y = 2040, 
			Z = 1851
		},
		Rotation = {
			X = 0,
			Y = 0,
			Z = 0,
			W = 1
		}
	},
]]

-- Per-player debug clones so test data isn't shared across players
local DebugDataPerPlayer: {[Player]: any} = {}

local function deepCopy(value: any)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = deepCopy(v)
	end
	return out
end

local function makeDebugCopy()
	local copy = deepCopy(DebugData)
	copy.__DebugData = true
	return copy
end

DebugData = {
	Studs = 1000,
	Badges = 1,
	LastPlayed = 0,
	Nickname = "DEBUG",
	Sequence = nil,
	Chunk = nil,
	DexNumber = 0, -- Will be calculated from unique creatures
	SeenCreatures = {
		["Frulli Frulla"] = true,
		["Sir Tung"] = true,
		["Tim Cheese"] = true,
		["Kitung"] = true,
		["Magi-Tung"] = true,
		["Duckaroo"] = true,
		["Frigo Camelo"] = true,
		["Refricamel"] = true,
		["Glacimel"] = true,
		["Timmy Cheddar"] = true,
		["Abrazard"] = true,
		["Twirlina"] = true,
		["Burbaloni Lulliloli"] = true,
		["Doggolino"] = true,
	},
	LastChunk = "Chunk6",
LeaveData = {
		Position = {
			X = -1252,
			Y = 229,
			Z = -477
		},
		Rotation = {
			X = 0,
			Y = 0,
			Z = 0,
			W = 1
		}
	},
	Party = {
		[1] = { Name = "Doggolino", Level = 23, Gender = 0, Shiny = true, Nickname = nil, CurrentHP = 200, XPProgress = 0, IVs = {HP = 15, Attack = 18, Defense = 12, SpecialAttack = 14, SpecialDefense = 13, Speed = 16}, OT = 1048500292, TradeLocked = false, Nature = "Adamant", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, WeightKg = 12, CurrentMoves = {"Bulk Up","Spikes","Bullet Seed","Double-Edge"}, Ability = "Menace" },
		[2] = { Name = "Sir Tung", Level = 18, Gender = 0, Shiny = false, CurrentHP = 62, XPProgress = 0, IVs = {HP = 14, Attack = 14, Defense = 12, SpecialAttack = 11, SpecialDefense = 10, Speed = 10}, Nature = "Adamant", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Fast Attack","Double Kick","Uppercut"} },
		[3] = { Name = "Tim Cheese", Level = 22, Gender = 1, Shiny = true, CurrentHP = 70, XPProgress = 0, IVs = {HP = 14, Attack = 15, Defense = 12, SpecialAttack = 16, SpecialDefense = 14, Speed = 12}, Nature = "Modest", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Scratch","Tackle","Bite","Crunch"}, HeldItem = "Capture Cube" },
		[4] = { Name = "Kitung", Level = 15, Gender = 1, Shiny = false, CurrentHP = 100, XPProgress = 98, IVs = {HP = 12, Attack = 11, Defense = 10, SpecialAttack = 9, SpecialDefense = 8, Speed = 13}, Nature = "Hardy", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Scratch","Fast Attack","Uppercut"} },
		[5] = { Name = "Magi-Tung", Level = 32, Gender = 1, Shiny = false, CurrentHP = 90, XPProgress = 0, IVs = {HP = 20, Attack = 18, Defense = 16, SpecialAttack = 15, SpecialDefense = 14, Speed = 17}, Nature = "Jolly", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Double Kick","Uppercut","Grand Slam"}, HeldItem = "Metal Fist" },
		[6] = { Name = "Duckaroo", Level = 16, Gender = 1, Shiny = false, CurrentHP = 55, XPProgress = 0, IVs = {HP = 13, Attack = 16, Defense = 11, SpecialAttack = 10, SpecialDefense = 9, Speed = 14}, Nature = "Brave", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Peck","Fast Attack","Sand Storm"} },
	},

	-- Debug Vault boxes (supports new named-box format; Vault will also handle legacy)
	Boxes = {
		{ Name = "Box 1", Creatures = {
			{ Name = "Kitung", Level = 5, Gender = 1, Shiny = false, CurrentHP = 28, XPProgress = 0, IVs = {HP = 12, Attack = 11, Defense = 10, SpecialAttack = 9, SpecialDefense = 8, Speed = 13}, Nature = "Hardy", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Scratch","Fast Attack"} },
			{ Name = "Sir Tung", Level = 18, Gender = 0, Shiny = false, CurrentHP = 62, XPProgress = 0, IVs = {HP = 14, Attack = 14, Defense = 12, SpecialAttack = 11, SpecialDefense = 10, Speed = 10}, Nature = "Adamant", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Fast Attack","Double Kick","Uppercut"}, HeldItem = "Capture Cube" },
			{ Name = "Magi-Tung", Level = 32, Gender = 1, Shiny = true, CurrentHP = 90, XPProgress = 0, IVs = {HP = 20, Attack = 18, Defense = 16, SpecialAttack = 15, SpecialDefense = 14, Speed = 17}, Nature = "Jolly", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Double Kick","Uppercut","Grand Slam"} },
			{ Name = "Frigo Camelo", Level = 11, Gender = 1, Shiny = false, CurrentHP = 40, XPProgress = 0, IVs = {HP = 10, Attack = 9, Defense = 10, SpecialAttack = 8, SpecialDefense = 9, Speed = 12}, Nature = "Calm", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Fast Attack","Scratch","Sand Storm"} },
			{ Name = "Refricamel", Level = 24, Gender = 1, Shiny = false, CurrentHP = 80, XPProgress = 0, IVs = {HP = 14, Attack = 14, Defense = 12, SpecialAttack = 13, SpecialDefense = 11, Speed = 12}, Nature = "Bold", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Sand Storm","Bite","Crunch"} },
			{ Name = "Glacimel", Level = 41, Gender = 0, Shiny = false, CurrentHP = 120, XPProgress = 0, IVs = {HP = 20, Attack = 15, Defense = 18, SpecialAttack = 14, SpecialDefense = 17, Speed = 11}, Nature = "Gentle", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Fast Attack","Sand Storm","Crunch","Earthquake"} },
			{ Name = "Timmy Cheddar", Level = 9, Gender = 1, Shiny = false, CurrentHP = 33, XPProgress = 0, IVs = {HP = 9, Attack = 9, Defense = 8, SpecialAttack = 7, SpecialDefense = 7, Speed = 10}, Nature = "Quirky", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Scratch","Tackle","Fast Attack"} },
			{ Name = "Tim Cheese", Level = 22, Gender = 1, Shiny = true, CurrentHP = 70, XPProgress = 0, IVs = {HP = 14, Attack = 15, Defense = 12, SpecialAttack = 16, SpecialDefense = 14, Speed = 12}, Nature = "Modest", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Scratch","Tackle","Bite","Crunch"}, HeldItem = "Apple" },
			{ Name = "Duckaroo", Level = 16, Gender = 1, Shiny = false, CurrentHP = 55, XPProgress = 0, IVs = {HP = 13, Attack = 16, Defense = 11, SpecialAttack = 10, SpecialDefense = 9, Speed = 14}, Nature = "Brave", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Peck","Fast Attack","Sand Storm"} },
			{ Name = "Abrazard", Level = 7, Gender = 1, Shiny = false, CurrentHP = 29, XPProgress = 0, IVs = {HP = 10, Attack = 9, Defense = 9, SpecialAttack = 8, SpecialDefense = 8, Speed = 11}, Nature = "Docile", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Scratch","Fast Attack"} },
			{ Name = "Twirlina", Level = 13, Gender = 0, Shiny = false, CurrentHP = 44, XPProgress = 0, IVs = {HP = 11, Attack = 8, Defense = 9, SpecialAttack = 10, SpecialDefense = 9, Speed = 13}, Nature = "Hasty", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Dance Strike","Dazzle Beam"} },
			{ Name = "Burbaloni Lulliloli", Level = 20, Gender = 1, Shiny = true, CurrentHP = 68, XPProgress = 0, IVs = {HP = 15, Attack = 11, Defense = 12, SpecialAttack = 10, SpecialDefense = 11, Speed = 10}, Nature = "Lax", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Tackle","Scratch","Fast Attack"} },
		}},
		{ Name = "Shinies", Creatures = {
			{ Name = "Kitung", Level = 5, Gender = 1, Shiny = true, CurrentHP = 28, XPProgress = 0, IVs = {HP = 12, Attack = 11, Defense = 10, SpecialAttack = 9, SpecialDefense = 8, Speed = 13}, Nature = "Hardy", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Scratch","Fast Attack"}, HeldItem = "Capture Cube" },
			{ Name = "Sir Tung", Level = 26, Gender = 0, Shiny = true, CurrentHP = 70, XPProgress = 0, IVs = {HP = 16, Attack = 15, Defense = 14, SpecialAttack = 13, SpecialDefense = 12, Speed = 12}, Nature = "Jolly", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Double Kick","Uppercut","Grand Slam"} },
		}},
		{ Name = "Empty Box", Creatures = {} },
	},
	-- Debug inventory
	Items = {
		Apple = 5,
		Potion = 3,
		["Epic Potion"] = 2,
		["Maximum Potion"] = 1,
		Revive = 2,
		["Maximum Revive"] = 1,
		["Toxic Candy"] = 3,
		["Golden Apple"] = 1,
		["Capture Cube"] = 10,
		["Rot Cube"] = 5,
		["Glitch Cube"] = 5,
		["Metal Fist"] = 5,
		["Fairy Dust"] = 5,
		["Static Chip"] = 5,
		["Spike Band"] = 5,
		["Rage Core"] = 5,
		Crumbs = 5,
		["Echo Bell"] = 5,
		["Focus Bandage"] = 5,
		["Stone Armor"] = 5,
		["Sleep Mask"] = 5,
		["Bright Core"] = 5,
		["Inferno Seed"] = 5,
		["Tore Stone"] = 5,
		["Focus Spray"] = 5,
		["Super Focus Spray"] = 5,
		["Max Focus Spray"] = 5,
		["ML - Tackle"] = 5,
		["ML - Scratch"] = 5,
		["ML - Bite"] = 5,
		["ML - Crunch"] = 5,
		["ML - Earthquake"] = 5,
		["ML - Fast Attack"] = 5,
		["ML - Double-Edge"] = 5,
		["ML - Flare Blitz"] = 5,
	},
	Creatures = {},
	Gamepasses = {},
	PickedUpItems = {},

	Settings = {
		AutoSave = false,
		MuteMusic = false,
		FastText = true,
		XPSpread = true,
	},

	Events = {
		GAME_INTRO = true,
		MET_PROFESSOR = true,
		FIRST_CREATURE = true,
		FIRST_BATTLE = true,
		MET_KYRO_ROUTE_1 = true,
		AYLA_ROUTE2_DONE = true,

		MET_KYRO_ROUTE_3 = true, --These two are sorta gated, happen in the same chunk but different cutscenes
		MET_MAN_ROUTE_3 = true,
		ASSASSIN_ROUTE_3_INTRO = true,
		ASSASSIN_ROUTE_3 = true,

		MET_FREINDS_ROUTE_4 = true, --Set after we meet our friends in route 4
		MET_FREINDS_ASTERDEN = false, --Set after we meet our friends in Asterden
		MET_FRIENDS_AFTER_GYM = false, --Set after we meet our friends again after beating the gym
	},

	DefeatedTrainers = {
		["TrainerCecil01"] = true,
		["TrainerNicole01"] = true,
		["TrainerAiden01"] = true,
		["TrainerGiselle01"] = true,
		["TrainerHope01"] = true,
		["TrainerJames01"] = true,
		["TrainerLucian01"] = true,
	},
}

-- Ensure every debug creature instance has an assigned ability
local function ensureInstanceAbility(instance)
	if type(instance) ~= "table" then
		return
	end

	if (instance.Ability == nil or instance.Ability == "") and type(instance.Name) == "string" then
		local ability = Abilities.SelectAbility(instance.Name, false)
		if ability ~= nil then
			instance.Ability = ability
		end
	end
end

local function ensureDebugAbilities(data)
	-- Party creatures
	local party = data and data.Party
	if type(party) == "table" then
		for _, creature in pairs(party) do
			ensureInstanceAbility(creature)
		end
	end

	-- Box creatures
	local boxes = data and data.Boxes
	if type(boxes) == "table" then
		for _, box in ipairs(boxes) do
			if box and type(box.Creatures) == "table" then
				for _, creature in ipairs(box.Creatures) do
					ensureInstanceAbility(creature)
				end
			end
		end
	end
end

local Events = game:GetService("ReplicatedStorage").Events
local PlayerData = require(script.PlayerData)

--We force update the clients data on their end
function ClientData:UpdateClientData(Player:Player,Data:any)
	local payload = Data

	if UseDebugData then
		-- Always keep an isolated per-player copy seeded from DebugData
		local current = DebugDataPerPlayer[Player]
		DBG:print("[UpdateClientData] Debug mode - current exists:", current ~= nil, "Data exists:", Data ~= nil)
		if current then
			DBG:print("[UpdateClientData] current.Chunk:", current.Chunk, "Data.Chunk:", Data and Data.Chunk)
			DBG:print("[UpdateClientData] Data == current:", Data == current, "Data.__DebugData:", Data and Data.__DebugData)
		end
		
		if not current then
			current = makeDebugCopy()
			ensureDebugAbilities(current)
			DBG:print("[UpdateClientData] Created new debug copy with Chunk:", current.Chunk)
			-- First-time seed ignores live profile data to keep testing consistent
		elseif Data ~= nil and (Data == current or Data.__DebugData == true) then
			-- Only accept updates that originate from the debug copy itself
			current = Data
			DBG:print("[UpdateClientData] Accepted Data update, Chunk:", current.Chunk)
		else
			DBG:warn("[UpdateClientData] REJECTED update - Data is not the debug copy! current.Chunk:", current.Chunk, "Data.Chunk:", Data and Data.Chunk)
		end
		DebugDataPerPlayer[Player] = current
		payload = current
	end

	-- Check if spawned creature is fainted or moved to box, and despawn if needed
	local success, err = pcall(function()
		local CreatureSpawnService = require(script.Parent:WaitForChild("CreatureSpawnService"))
		if CreatureSpawnService and CreatureSpawnService.CheckAndDespawnFaintedCreatures then
			local spawnedSlot = CreatureSpawnService.GetSpawnedSlotIndex and CreatureSpawnService.GetSpawnedSlotIndex(Player)
			if spawnedSlot then
				local party = payload and payload.Party
				DBG:print("[ClientData] Checking spawned creature for", Player.Name, "- spawnedSlot:", spawnedSlot, "party length:", party and #party or 0)
				-- Check if the spawned creature still exists in the party (handles party compaction)
				-- This will update the slot index if the creature moved to a different slot due to compaction
				if CreatureSpawnService.IsSpawnedCreatureStillInSlot and not CreatureSpawnService.IsSpawnedCreatureStillInSlot(Player, party) then
					DBG:print("[ClientData] Spawned creature not found in party for", Player.Name, "- despawning")
					-- Creature was moved out of party (to box), despawn it
					-- Get the slot before despawning (DespawnPlayerCreature clears it)
					local currentSlot = CreatureSpawnService.GetSpawnedSlotIndex and CreatureSpawnService.GetSpawnedSlotIndex(Player)
					if currentSlot then
						-- Use CheckAndDespawnSlot which handles both despawning and event firing
						-- But first, we need to ensure it will work even if slot doesn't match
						-- Actually, since we know the creature isn't in party, we can directly despawn
						CreatureSpawnService.DespawnPlayerCreature(Player)
						-- Fire the despawn event manually since DespawnPlayerCreature doesn't do it
						local ReplicatedStorage = game:GetService("ReplicatedStorage")
						local events = ReplicatedStorage:WaitForChild("Events")
						local communicate = events:WaitForChild("Communicate")
						communicate:FireClient(Player, "CreatureDespawned", currentSlot)
						DBG:print("[ClientData] Despawned and fired CreatureDespawned event for slot", currentSlot, "for", Player.Name)
					else
						-- Fallback: just despawn without event (shouldn't happen)
						CreatureSpawnService.DespawnPlayerCreature(Player)
						DBG:warn("[ClientData] Despawned without slot info for", Player.Name)
					end
				else
					DBG:print("[ClientData] Spawned creature still in party for", Player.Name)
				end
			else
				DBG:print("[ClientData] No spawned creature for", Player.Name)
			end
			-- Check for fainted creatures
			CreatureSpawnService.CheckAndDespawnFaintedCreatures(Player)
		end
	end)
	if not success then
		DBG:warn("[ClientData] Error checking spawned creature for", Player.Name, ":", err)
	end

	DBG:print("SERVER: Force updating client data for", Player.Name)
	DBG:print("Data being sent:", payload)
	Events.Communicate:FireClient(Player,"ClientData",payload)
end

function ClientData:Get(Player)
	if UseDebugData then
		-- Provide an isolated copy per player so trades/mutations don't bleed across players
		local current = DebugDataPerPlayer[Player]
		local wasNew = false
		if not current then
			current = makeDebugCopy()
			wasNew = true
			DBG:print("[ClientData:Get] Created NEW debug copy for", Player.Name, "Chunk:", current.Chunk)
		end
		-- Backfill abilities on every fetch to keep debug instances valid
		ensureDebugAbilities(current)
		-- Apply ability backfill to the per-player copy
		if DebugDataPerPlayer[Player] ~= current then
			DebugDataPerPlayer[Player] = current
		end
		if not wasNew then
			--DBG:print("[ClientData:Get] Returning EXISTING debug copy for", Player.Name, "Chunk:", current.Chunk)
		end
		return current
	end

	return PlayerData.GetData(Player)
end

-- Set the player's live data (bypassing persistence layer for immediate reset)
function ClientData:Set(Player: Player, data: any)
    if UseDebugData then
        -- Overwrite per-player debug copy in memory
		if not DebugDataPerPlayer[Player] then
			DebugDataPerPlayer[Player] = makeDebugCopy()
		end
		-- Only replace with debug-tagged data; ignore live profile tables
		if data and (data.__DebugData == true or data == DebugDataPerPlayer[Player]) then
			DebugDataPerPlayer[Player] = data
		end
        return true
    else
        if PlayerData and PlayerData.SetData then
            return PlayerData.SetData(Player, data)
        end
    end
    return false
end

return ClientData

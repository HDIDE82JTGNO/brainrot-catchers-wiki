local ClientData = {}

local UseDebugData = true :: boolean -- Debug data does NOT save.

local DBG = require(game:GetService("ReplicatedStorage").Shared.DBG)
local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local Moves = require(game:GetService("ReplicatedStorage").Shared.Moves)

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

local DebugData = {
	Studs = 9999,
	Badges = 0,
	LastPlayed = 0,
	Nickname = "DEBUG",
	Sequence = nil,
	Chunk = nil,
	LastChunk = "Chunk1", 
	LeaveData = {
		Position = {
			X = 216.209,
			Y = 10,
			Z = -263.683
		},
		Rotation = {
			X = 0,
			Y = 0,
			Z = 0,
			W = 1
		}
	},
	Party = {
		--[1] = { Name = "Duckaroo", Level = 3, Gender = 1, Shiny = false, Nickname = nil, CurrentHP = 11, XPProgress = 0, IVs = {HP = 20, Attack = 20, Defense = 20, Speed = 20}, OT = 4788714726, TradeLocked = false, Nature = "Calm", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, WeightKg = 40, CurrentMoves = {"Peck","Perch","Fast Attack","Bite"} },
		--[2] = { Name = "Primarina Ballerina", Level = 47, Gender = 1, Shiny = false, Nickname = nil, CurrentHP = 100, XPProgress = 99.5, IVs = {HP = 20, Attack = 20, Defense = 20, Speed = 20}, OT = 4788714726, TradeLocked = false, Nature = "Modest", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, WeightKg = 40, CurrentMoves = {"Dance Strike","Dazzle Beam","Fairy Strike","Shield Bash"} },
		--[3] = { Name = "Magi-Tung", Level = 38, Gender = 1, Shiny = false, Nickname = nil, CurrentHP = 100, XPProgress = 0, IVs = {HP = 20, Attack = 20, Defense = 20, Speed = 20}, OT = 4788714726, TradeLocked = false, Nature = "Jolly", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, WeightKg = 40, CurrentMoves = {"Scratch","Fast Attack","Double Kick","Uppercut"} },
		--[4] = { Name = "Sir Tung", Level = 26, Gender = 0, Shiny = false, Nickname = nil, CurrentHP = 100, XPProgress = 0, IVs = {HP = 20, Attack = 20, Defense = 20, Speed = 20}, OT = 4788714726, TradeLocked = false, Nature = "Adamant", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, WeightKg = 55, CurrentMoves = {"Fast Attack","Double Kick","Uppercut","Grand Slam"} },
		[1] = { Name = "Frulli Frulla", Level = 8, Gender = 1, Shiny = true, Nickname = nil, CurrentHP = 100, XPProgress = 0, IVs = {HP = 18, Attack = 16, Defense = 14, Speed = 17}, OT = 4788714726, TradeLocked = false, Nature = "Timid", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, WeightKg = 6, CurrentMoves = {"Peck","Perch","Fast Attack","Bite"}, HeldItem = "Apple" },
	},

	-- Debug Vault boxes (supports new named-box format; Vault will also handle legacy)
	Boxes = {
		{ Name = "Box 1", Creatures = {
			{ Name = "Kitung", Level = 5, Gender = 1, Shiny = false, CurrentHP = 28, XPProgress = 0, IVs = {HP = 12, Attack = 11, Defense = 10, Speed = 13}, Nature = "Hardy", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Scratch","Fast Attack"} },
			{ Name = "Sir Tung", Level = 18, Gender = 0, Shiny = false, CurrentHP = 62, XPProgress = 0, IVs = {HP = 14, Attack = 14, Defense = 12, Speed = 10}, Nature = "Adamant", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Fast Attack","Double Kick","Uppercut"}, HeldItem = "Capture Cube" },
			{ Name = "Magi-Tung", Level = 32, Gender = 1, Shiny = true, CurrentHP = 90, XPProgress = 0, IVs = {HP = 20, Attack = 18, Defense = 16, Speed = 17}, Nature = "Jolly", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Double Kick","Uppercut","Grand Slam"} },
			{ Name = "Frigo Camelo", Level = 11, Gender = 1, Shiny = false, CurrentHP = 40, XPProgress = 0, IVs = {HP = 10, Attack = 9, Defense = 10, Speed = 12}, Nature = "Calm", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Fast Attack","Scratch","Sand Storm"} },
			{ Name = "Refricamel", Level = 24, Gender = 1, Shiny = false, CurrentHP = 80, XPProgress = 0, IVs = {HP = 14, Attack = 14, Defense = 12, Speed = 12}, Nature = "Bold", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Sand Storm","Bite","Crunch"} },
			{ Name = "Glacimel", Level = 41, Gender = 0, Shiny = false, CurrentHP = 120, XPProgress = 0, IVs = {HP = 20, Attack = 15, Defense = 18, Speed = 11}, Nature = "Gentle", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Fast Attack","Sand Storm","Crunch","Earthquake"} },
			{ Name = "Timmy Cheddar", Level = 9, Gender = 1, Shiny = false, CurrentHP = 33, XPProgress = 0, IVs = {HP = 9, Attack = 9, Defense = 8, Speed = 10}, Nature = "Quirky", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Scratch","Tackle","Fast Attack"} },
			{ Name = "Tim Cheese", Level = 22, Gender = 1, Shiny = true, CurrentHP = 70, XPProgress = 0, IVs = {HP = 14, Attack = 15, Defense = 12, Speed = 12}, Nature = "Modest", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Scratch","Tackle","Bite","Crunch"}, HeldItem = "Apple" },
			{ Name = "Duckaroo", Level = 16, Gender = 1, Shiny = false, CurrentHP = 55, XPProgress = 0, IVs = {HP = 13, Attack = 16, Defense = 11, Speed = 14}, Nature = "Brave", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Peck","Fast Attack","Sand Storm"} },
			{ Name = "Abrazard", Level = 7, Gender = 1, Shiny = false, CurrentHP = 29, XPProgress = 0, IVs = {HP = 10, Attack = 9, Defense = 9, Speed = 11}, Nature = "Docile", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Scratch","Fast Attack"} },
			{ Name = "Twirlina", Level = 13, Gender = 0, Shiny = false, CurrentHP = 44, XPProgress = 0, IVs = {HP = 11, Attack = 8, Defense = 9, Speed = 13}, Nature = "Hasty", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Dance Strike","Dazzle Beam"} },
			{ Name = "Burbaloni Lulliloli", Level = 20, Gender = 1, Shiny = true, CurrentHP = 68, XPProgress = 0, IVs = {HP = 15, Attack = 11, Defense = 12, Speed = 10}, Nature = "Lax", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Tackle","Scratch","Fast Attack"} },
		}},
		{ Name = "Shinies", Creatures = {
			{ Name = "Kitung", Level = 5, Gender = 1, Shiny = true, CurrentHP = 28, XPProgress = 0, IVs = {HP = 12, Attack = 11, Defense = 10, Speed = 13}, Nature = "Hardy", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Scratch","Fast Attack"}, HeldItem = "Capture Cube" },
			{ Name = "Sir Tung", Level = 26, Gender = 0, Shiny = true, CurrentHP = 70, XPProgress = 0, IVs = {HP = 16, Attack = 15, Defense = 14, Speed = 12}, Nature = "Jolly", CatchData = { CaughtWhen = os.time(), CaughtBy = 4788714726 }, CurrentMoves = {"Double Kick","Uppercut","Grand Slam"} },
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
		MET_KYRO_ROUTE_1 = false,
	},

	DefeatedTrainers = {
		["TrainerCecil01"] = true,
		["TrainerNicole01"] = true,
	},
}

local Events = game:GetService("ReplicatedStorage").Events
local PlayerData = require(script.PlayerData)

--We force update the clients data on their end
function ClientData:UpdateClientData(Player:Player,Data:any)
	DBG:print("SERVER: Force updating client data for", Player.Name)
	DBG:print("Data being sent:", Data)
	Events.Communicate:FireClient(Player,"ClientData",Data)
end

function ClientData:Get(Player)
	return UseDebugData and DebugData or PlayerData.GetData(Player)
end

-- Set the player's live data (bypassing persistence layer for immediate reset)
function ClientData:Set(Player: Player, data: any)
    if UseDebugData then
        -- Overwrite debug table in memory
        for k in pairs(DebugData) do DebugData[k] = nil end
        for k, v in pairs(data) do DebugData[k] = v end
        return true
    else
        if PlayerData and PlayerData.SetData then
            return PlayerData.SetData(Player, data)
        end
    end
    return false
end

return ClientData

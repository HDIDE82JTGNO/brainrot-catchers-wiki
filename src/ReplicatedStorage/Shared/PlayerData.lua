local Shared = {}

Shared.DEFAULT_PLAYER_DATA = {

	Settings = {
		AutoSave = true, -- Saves on EXIT if true. If false, it will only save the players progress when they ask.
		MuteMusic = false, -- Self explanitory
		FastText = false, -- Makes text appear 1.5x faster in dialogue
		XPSpread = true, -- When true, other party members gain XP when defeating opponents
	},
	
	Studs = 0,
	Badges = 0,
	LastPlayed = 0,
	Nickname = nil,
	Sequence = nil,
	Chunk = nil,
	LastChunk = nil,
	LastCF = nil,
	DexNumber = 0, -- Number of unique creatures caught
	SeenCreatures = {}, -- map of CreatureName -> true (tracks which creatures player has seen in battle)
	Party = {},
	-- Vault boxes (new schema only): array of { Name = string, Creatures = { up to 30 creatures } }
	Boxes = {},
	Items = {},
	Creatures = {},
	Gamepasses = {},
	PickedUpItems = {},
	DefeatedTrainers = {}, -- map of TrainerId -> true
	RedeemedCodes = {}, -- map of Code -> true (tracks which codes player has redeemed)
	
	-- Pending battle snapshot for crash/leave rollback; cleared on BattleOver
	PendingBattle = nil,
	
	Events = {
		GAME_INTRO = false, --Set after we wake up from our bed, intro cutscene
		MET_PROFESSOR = false, --Set after the end of the professor cutscene, once we are done talking to mom
		FIRST_CREATURE = false, --Set after we get our first creature
		FIRST_BATTLE = false, --Set after completing the first battle against kyro
		FINISHED_TUTORIAL = false, --Set after completing the tutorial (Give player 5 capture cubes when setting to true)
		MET_KYRO_ROUTE_1 = false, --Set after we meet kyro in route 1, 
		AYLA_ROUTE2_DONE = false,
		MET_KYRO_ROUTE_3 = false, --Set after we meet kyro in route 2,
		MET_MAN_ROUTE_3 = false, --Set after we have the cutscene with the old maaayyne
		ASSASSIN_ROUTE_3_INTRO = false, --Set after Assassin first blocks the Route 3 gate
		ASSASSIN_ROUTE_3 = false, --Set after we meet the assassin and its owner in route 3
		MET_FREINDS_ROUTE_4 = false, --Set after we meet our friends in route 4
		MET_FREINDS_ASTERDEN = false, --Set after we meet our friends in Asterden
		MET_FRIENDS_AFTER_GYM = false, --Set after we meet our friends again after beating the gym
	},
}

export type PlayerData = typeof(Shared.DEFAULT_PLAYER_DATA)

return Shared
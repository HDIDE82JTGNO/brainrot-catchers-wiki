-- Move Compatibility System for ML Items
-- Uses creature-centric storage (Creature -> Moves as sets) like Pokémon's TM/HM system

-- Primary data: Creature -> Moves (as sets with boolean values)
-- O(1) lookup: COMPATIBILITY[creature][move] == true
local COMPATIBILITY: { [string]: { [string]: boolean } } = {
	--============================================================================
	-- STARTER LINE 1: Kitung (Fighting -> Fighting/Psychic)
	--============================================================================
	["Kitung"] = {
		Tackle = true,
		Scratch = true,
		["Fast Attack"] = true,
		["Double Kick"] = true,
		Uppercut = true,
	},
	["Sir Tung"] = {
		Tackle = true,
		Scratch = true,
		["Fast Attack"] = true,
		["Double Kick"] = true,
		Uppercut = true,
		["Grand Slam"] = true,
		["Shield Bash"] = true,
	},
	["Magi-Tung"] = {
		Tackle = true,
		Scratch = true,
		["Fast Attack"] = true,
		["Double Kick"] = true,
		Uppercut = true,
		["Grand Slam"] = true,
		["Shield Bash"] = true,
		["Mind Slam"] = true,
		Knockout = true,
	},

	--============================================================================
	-- STARTER LINE 2: Frigo Camelo (Ground -> Ground/Ice)
	--============================================================================
	["Frigo Camelo"] = {
		Tackle = true,
		Scratch = true,
		Bite = true,
		["Sand Storm"] = true,
		["Fast Attack"] = true,
	},
	["Refricamel"] = {
		Tackle = true,
		Scratch = true,
		Bite = true,
		Crunch = true,
		["Sand Storm"] = true,
		["Fast Attack"] = true,
		Earthquake = true,
	},
	["Glacimel"] = {
		Tackle = true,
		Scratch = true,
		Bite = true,
		Crunch = true,
		["Sand Storm"] = true,
		["Fast Attack"] = true,
		Earthquake = true,
		["Dive Bomb"] = true,
	},

	--============================================================================
	-- STARTER LINE 3: Twirlina (Fairy -> Fairy/Steel)
	--============================================================================
	["Twirlina"] = {
		Tackle = true,
		["Dance Strike"] = true,
		["Fast Attack"] = true,
		["Dazzle Beam"] = true,
		["Fairy Strike"] = true,
	},
	["Ballerina Cappuccina"] = {
		Tackle = true,
		["Dance Strike"] = true,
		["Fast Attack"] = true,
		["Dazzle Beam"] = true,
		["Fairy Strike"] = true,
		Sunbeam = true,
		["Mind Slam"] = true,
	},
	["Primarina Ballerina"] = {
		Tackle = true,
		["Dance Strike"] = true,
		["Fast Attack"] = true,
		["Dazzle Beam"] = true,
		["Fairy Strike"] = true,
		Sunbeam = true,
		["Shield Bash"] = true,
		["Mind Slam"] = true,
		["Grand Slam"] = true,
	},

	--============================================================================
	-- WILD CREATURES: Early-game commons and uncommons
	--============================================================================
	["Frulli Frulla"] = {
		Tackle = true,
		Peck = true,
		["Fast Attack"] = true,
		Perch = true,
		["Static Peck"] = true,
		Bite = true,
	},
	["Frulilala"] = {
		Tackle = true,
		Peck = true,
		["Fast Attack"] = true,
		Perch = true,
		["Static Peck"] = true,
		Bite = true,
		["Duststorm Dash"] = true,
		["Dive Bomb"] = true,
		["Thunder Burst"] = true,
		Crunch = true,
	},
	["Frulli Fruletro"] = {
		Tackle = true,
		Peck = true,
		["Fast Attack"] = true,
		Perch = true,
		["Static Peck"] = true,
		["Duststorm Dash"] = true,
		["Dive Bomb"] = true,
		["Thunder Burst"] = true,
		["Shield Bash"] = true,
		["Grand Slam"] = true,
		Crunch = true,
	},

	--============================================================================
	-- Tim Line (Normal type 2-stage)
	--============================================================================
	["Timmy Cheddar"] = {
		Scratch = true,
		Tackle = true,
		["Fast Attack"] = true,
		Bite = true,
		Crunch = true,
	},
	["Tim Cheese"] = {
		Scratch = true,
		Tackle = true,
		["Fast Attack"] = true,
		Bite = true,
		Crunch = true,
		["Double Kick"] = true,
		["Grand Slam"] = true,
	},

	--============================================================================
	-- Burbaloni Lulliloli (Single-stage rare)
	--============================================================================
	["Burbaloni Lulliloli"] = {
		Tackle = true,
		Scratch = true,
		["Sand Storm"] = true,
		Bite = true,
		["Fast Attack"] = true,
		Earthquake = true,
		Crunch = true,
	},

	--============================================================================
	-- Jungle Chimps (Grass type 2-stage line)
	--============================================================================
	["Chimpanini"] = {
		Scratch = true,
		Tackle = true,
		["Vine Whip"] = true,
		["Fast Attack"] = true,
		["Seed Toss"] = true,
	},
	["Chimpanzini Bananini"] = {
		Scratch = true,
		Tackle = true,
		["Vine Whip"] = true,
		["Fast Attack"] = true,
		["Seed Toss"] = true,
		["Leaf Slash"] = true,
		["Grand Slam"] = true,
	},

	--============================================================================
	-- Duckaroo (Single-stage rare - Flying/Ground)
	--============================================================================
	["Duckaroo"] = {
		Peck = true,
		Tackle = true,
		["Fast Attack"] = true,
		["Sand Storm"] = true,
		Bite = true,
		["Duststorm Dash"] = true,
		Earthquake = true,
		["Dive Bomb"] = true,
		Crunch = true,
	},

	--============================================================================
	-- Doggolino (Single-stage Fire type - uncommon)
	--============================================================================
	["Doggolino"] = {
		Tackle = true,
		Scratch = true,
		["Fast Attack"] = true,
		Bite = true,
		Crunch = true,
		["Grand Slam"] = true,
		["Flare Blitz"] = true,
	},

	--============================================================================
	-- Tadbalabu Line (Grass 3-stage)
	--============================================================================
	["Tadbalabu"] = {
		Tackle = true,
		Scratch = true,
		["Vine Whip"] = true,
		["Fast Attack"] = true,
		["Seed Toss"] = true,
	},
	["Boneca Ambalabu"] = {
		Tackle = true,
		Scratch = true,
		["Vine Whip"] = true,
		["Fast Attack"] = true,
		["Seed Toss"] = true,
		["Leaf Slash"] = true,
		["Double Kick"] = true,
	},
	["Ambalabu Ton-Ton"] = {
		Tackle = true,
		Scratch = true,
		["Vine Whip"] = true,
		["Seed Toss"] = true,
		["Leaf Slash"] = true,
		["Double Kick"] = true,
		["Grand Slam"] = true,
		Earthquake = true,
	},

	--============================================================================
	-- Abrazard (Single-stage Psychic - uncommon)
	--============================================================================
	["Abrazard"] = {
		Scratch = true,
		Tackle = true,
		["Fast Attack"] = true,
		["Mind Slam"] = true,
		["Dazzle Beam"] = true,
		Sunbeam = true,
	},

	--============================================================================
	-- Bolasaeg Selluaim (Single-stage Poison - tanky uncommon)
	--============================================================================
	["Bolasaeg Selluaim"] = {
		Tackle = true,
		["Ooze Shot"] = true,
		Scratch = true,
		["Sludge Puff"] = true,
		["Toxic Wave"] = true,
		["Corrosive Grasp"] = true,
		["Acidic Deluge"] = true,
	},

	--============================================================================
	-- Trippi Troppi (Water/Normal - tanky water type)
	--============================================================================
	["Trippi Troppi"] = {
		Tackle = true,
		["Water Jet"] = true,
		Bite = true,
		["Fast Attack"] = true,
		["Aqua Slash"] = true,
		Crunch = true,
		["Hydro Burst"] = true,
	},

	--============================================================================
	-- Il Cacto Hipopotamo (Grass/Ground - defensive rare)
	--============================================================================
	["Il Cacto Hipopotamo"] = {
		Tackle = true,
		Scratch = true,
		["Vine Whip"] = true,
		["Sand Storm"] = true,
		["Seed Toss"] = true,
		["Leaf Slash"] = true,
		Earthquake = true,
	},

	--============================================================================
	-- Chicleteira (Steel - defensive uncommon)
	--============================================================================
	["Chicleteira"] = {
		Tackle = true,
		Scratch = true,
		["Fast Attack"] = true,
		["Shield Bash"] = true,
		Bite = true,
		["Grand Slam"] = true,
	},

	--============================================================================
	-- Špijuniro Golubiro (Flying/Steel - speedy rare spy pigeon)
	--============================================================================
	["Špijuniro Golubiro"] = {
		Peck = true,
		Tackle = true,
		["Fast Attack"] = true,
		["Dive Bomb"] = true,
		["Shield Bash"] = true,
		["Duststorm Dash"] = true,
		["Grand Slam"] = true,
	},

	--============================================================================
	-- Avocadini Guffo (Grass - tanky uncommon owl)
	--============================================================================
	["Avocadini Guffo"] = {
		Tackle = true,
		Peck = true,
		["Vine Whip"] = true,
		["Seed Toss"] = true,
		Perch = true,
		["Leaf Slash"] = true,
	},

	--============================================================================
	-- Bombombini Gusini (Flying/Steel - fast and powerful rare)
	--============================================================================
	["Bombombini Gusini"] = {
		Peck = true,
		Tackle = true,
		["Fast Attack"] = true,
		["Shield Bash"] = true,
		["Dive Bomb"] = true,
		["Duststorm Dash"] = true,
		["Grand Slam"] = true,
		Earthquake = true,
	},

	--============================================================================
	-- Brr Brr Patapim (Grass - tanky defensive common)
	--============================================================================
	["Brr Brr Patapim"] = {
		Tackle = true,
		Scratch = true,
		["Vine Whip"] = true,
		["Seed Toss"] = true,
		["Leaf Slash"] = true,
		["Grand Slam"] = true,
	},

	--============================================================================
	-- Frycito (Fire/Fighting - rare single-stage)
	--============================================================================
	["Frycito"] = {
		Scratch = true,
		["Grease Jab"] = true,
		["Double Kick"] = true,
		["Fast Attack"] = true,
		Uppercut = true,
		["Searing Splat"] = true,
		["Grand Slam"] = true,
		["Flare Blitz"] = true,
	},

	--============================================================================
	-- Yoyoi Shaur Line (Normal/Psychic - 2-stage spinner)
	--============================================================================
	["Yoyoi Shaur"] = {
		Tackle = true,
		["Fast Attack"] = true,
		Scratch = true,
		["Psychic Pulse"] = true,
		["Mind Slam"] = true,
		["Grand Slam"] = true,
	},
	["Yoyoya Shaur"] = {
		Tackle = true,
		["Fast Attack"] = true,
		Scratch = true,
		["Psychic Pulse"] = true,
		["Mind Slam"] = true,
		["Dazzle Beam"] = true,
		["Grand Slam"] = true,
		Knockout = true,
	},

	--============================================================================
	-- LEGENDARY/SPECIAL: Tralalero Tralala
	--============================================================================
	["Tralalero Tralala"] = {
		["Water Jet"] = true,
		Tackle = true,
		["Fast Attack"] = true,
		Bite = true,
		["Aqua Slash"] = true,
		Crunch = true,
		["Hydro Burst"] = true,
		["Grand Slam"] = true,
	},
}

-- Reverse index: Move -> Creatures (as set)
-- Built automatically on module load for efficient move->creatures queries
local REVERSE_INDEX: { [string]: { [string]: boolean } } = {}

-- Build reverse index on module initialization
do
	for creatureName, moves in pairs(COMPATIBILITY) do
		for moveName, _ in pairs(moves) do
			if not REVERSE_INDEX[moveName] then
				REVERSE_INDEX[moveName] = {}
			end
			REVERSE_INDEX[moveName][creatureName] = true
		end
	end
end

-- Helper function: Check if a creature can learn a move via ML
-- O(1) lookup: creature lookup + boolean check
local function canCreatureLearnMove(creatureName: string, moveName: string): boolean
	local creatureMoves = COMPATIBILITY[creatureName]
	if not creatureMoves then
		return false
	end
	return creatureMoves[moveName] == true
end

-- Helper function: Get all moves a creature can learn via ML
-- Returns array of move names
local function getMovesForCreature(creatureName: string): {string}?
	local creatureMoves = COMPATIBILITY[creatureName]
	if not creatureMoves then
		return nil
	end
	
	local moves = {}
	for moveName, _ in pairs(creatureMoves) do
		table.insert(moves, moveName)
	end
	return moves
end

-- Helper function: Get all creatures that can learn a move via ML
-- Returns array of creature names
local function getCreaturesForMove(moveName: string): {string}?
	local creatures = REVERSE_INDEX[moveName]
	if not creatures then
		return nil
	end
	
	local creatureList = {}
	for creatureName, _ in pairs(creatures) do
		table.insert(creatureList, creatureName)
	end
	return creatureList
end

return {
	canCreatureLearnMove = canCreatureLearnMove,
	getMovesForCreature = getMovesForCreature,
	getCreaturesForMove = getCreaturesForMove,
}


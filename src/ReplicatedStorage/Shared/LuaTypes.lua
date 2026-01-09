export type StatBlock = {
	HP: number,
	Attack: number,
	Defense: number,
	SpecialAttack: number,
	SpecialDefense: number,
	Speed: number,
}

export type CreatureClass = "Basic" | "Advanced" | "Rare" | "Legendary" | "Transcendent"

-- Stat Stage Change Info (for moves that modify stats)
export type StatStageEffect = {
	Stat: string,       -- "Attack" | "Defense" | "Speed" | "Accuracy" | "Evasion"
	Stages: number,     -- Number of stages to change (-6 to +6)
	Target: string?,    -- "Self" | "Opponent" (defaults to "Opponent" for lowering, "Self" for raising)
	Chance: number?,    -- Optional: chance to apply (0-100, defaults to 100)
}

-- Multi-Hit configuration for moves that hit multiple times
export type MultiHitConfig = {
	MinHits: number, -- Minimum number of hits (e.g., 2 for Double Kick, 2 for Bullet Seed)
	MaxHits: number, -- Maximum number of hits (e.g., 2 for Double Kick, 5 for Bullet Seed)
	Fixed: boolean?, -- If true, always hits exactly MinHits times (for moves like Double Kick)
}

export type Move = {
	BasePower: number, --Base power
	Accuracy: number, --Accuracy from 0-100
	Priority: number, --Higher number goes first
	Type: {any}, --Type.Any
    Category: "Physical" | "Special" | "Status", -- Physical, Special, or Status
    Description: string?,
    HealsPercent: number?, -- Optional: percent of max HP to heal (self-heal moves)
    StatusEffect: string?, -- Optional: status condition to inflict ("BRN", "PAR", "PSN", "TOX", "SLP", "FRZ")
    StatusChance: number?, -- Optional: chance to inflict status (0-100)
    CausesFlinch: boolean?, -- Optional: causes flinch on hit
    CausesConfusion: boolean?, -- Optional: causes confusion
    -- Stat Stage Effects
    StatChanges: {StatStageEffect}?, -- Optional: list of stat stage changes this move causes
    -- Multi-Hit Moves
    MultiHit: MultiHitConfig?, -- Optional: configuration for multi-hit moves (e.g., Double Kick, Bullet Seed)
    -- Recoil Moves
    RecoilPercent: number?, -- Optional: percentage of damage dealt that the attacker takes as recoil (e.g., 25 for Take Down, 33 for Double-Edge)
    -- Entry Hazard Moves
    IsHazard: boolean?, -- Optional: true if this move sets entry hazards
    HazardType: string?, -- Optional: "StealthRock" | "Spikes" | "ToxicSpikes"
    MaxLayers: number?, -- Optional: max stack layers for Spikes (3) / Toxic Spikes (2)
    -- Hazard Removal
    RemovesHazards: boolean?, -- Optional: true if move removes hazards (Rapid Spin, Defog)
    RemovesAllHazards: boolean?, -- Optional: true if removes hazards from BOTH sides (Defog)
}

export type StatBoostInfo = {
	Stats: StatBlock,
	Amount: number,
}

export type Item = {
	Stats: StatBlock,
	Description: string,
	Category: string, -- "CaptureCubes" | "Heals" | "Items" | "MoveLearners"
    ContextType: string?, -- "Battle" | "Overworld" 
    UsableInBattle: boolean?,
    UsableInOverworld: boolean?,
	Image: string?, -- Asset ID for item image
}

export type Creature = {
	-- Identity
	DexNumber: number,
	Name: string,
	Sprite: string,
	ShinySprite: string?,

	-- Flavor
	Description: string,
	Type: {any},
	Class: CreatureClass?,

	-- Gameplay data
	BaseStats: StatBlock,
	Learnset: {[number]: {string}}?,
	EvolutionLevel: number?,
	EvolvesInto: string?,
	BaseWeightKg: number?,
	CatchRateScalar: number?, -- 0..100 (0 always catches, 100 impossible)
	FemaleChance: number?, -- 0..100 (% chance of female; default 50)

	-- Visual customization
	ShinyColors: {[string]: Color3}?,
}


-- Catch data for individual creature instances
export type CatchData = {
    CaughtWhen: number, -- Unix timestamp when caught/created
    CaughtBy: string, -- Username of the catcher/creator
}

-- Individual creature instance in party/save (compact schema)
export type CreatureInstance = {
    Name: string,
    Nickname: string?,
    Level: number,
    XP: number?,
    XPProgress: number?,
    Gender: number, -- 0 male, 1 female
    Stats: StatBlock?,
    MaxStats: StatBlock?,
    CurrentMoves: {any}?,
    CurrentHP: number?, -- 0..100 percent representation
    Shiny: boolean?,
    Nature: string?,
    IVs: {[string]: number}?,
    OT: number?,
    TradeLocked: boolean?,
    CatchData: CatchData?,
    WeightKg: number?,
    LearnedMoves: {[string]: boolean}?,
    Ability: string?,
}


local Types = {}
return Types
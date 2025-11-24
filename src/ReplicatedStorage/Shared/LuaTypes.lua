export type StatBlock = {
	HP: number,
	Attack: number,
	Defense: number,
	Speed: number,
}

export type CreatureClass = "Basic" | "Advanced" | "Rare" | "Legendary" | "Transcendent"

export type Move = {
	BasePower: number, --Base power
	Accuracy: number, --Accuracy from 0-100
	Priority: number, --Higher number goes first
	Type: {any}, --Type.Any
    Description: string?,
    HealsPercent: number?, -- Optional: percent of max HP to heal (self-heal moves)
    StatusEffect: string?, -- Optional: status condition to inflict ("BRN", "PAR", "PSN", "TOX", "SLP", "FRZ")
    StatusChance: number?, -- Optional: chance to inflict status (0-100)
    CausesFlinch: boolean?, -- Optional: causes flinch on hit
    CausesConfusion: boolean?, -- Optional: causes confusion
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
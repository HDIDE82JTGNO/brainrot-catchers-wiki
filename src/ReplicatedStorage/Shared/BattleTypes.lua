--!strict
--[[
	BattleTypes.lua
	Comprehensive type definitions for the battle system
	Provides type safety and documentation for all battle-related data structures
]]

local LuaTypes = require(script.Parent.LuaTypes)

export type StatBlock = LuaTypes.StatBlock
export type Move = LuaTypes.Move
export type Creature = LuaTypes.Creature

-- Battle Mode
export type BattleMode = "Wild" | "Trainer" | "PvP"

-- Switch Mode
export type SwitchMode = "Forced" | "Voluntary"

-- Battle Step Types
export type StepType = "Switch" | "Message" | "Move" | "Damage" | "Heal" | "Status" | "StatStage" | "Faint" | "Miss" | "Crit" | "Flinch" | "EntryHazard" | "HazardDamage"

-- Entry Hazard Types
export type HazardType = "StealthRock" | "Spikes" | "ToxicSpikes"

-- Entry Hazards per side of field
export type EntryHazards = {
	StealthRock: boolean?,  -- true = active
	Spikes: number?,        -- 0-3 layers
	ToxicSpikes: number?,   -- 0-2 layers
}

-- Stat Stage Change Info
export type StatStageChange = {
	Stat: string,       -- "Attack" | "Defense" | "Speed" | "Accuracy" | "Evasion"
	Stages: number,     -- Number of stages to change (-6 to +6)
	Target: string?,    -- "Self" | "Opponent" (defaults to "Opponent")
}

-- Battle Step
export type BattleStep = {
	Type: StepType,
	Message: string?,
	Damage: number?,
	NewHP: number?,
	Critical: boolean?,
	Effectiveness: string?,
	FlinchTarget: string?,
	-- Stat stage step fields
	Stat: string?,
	Stages: number?,
	IsPlayer: boolean?,
	-- Additional fields as needed
}

-- Turn Result
export type TurnResult = {
	Turn: number?,
	SwitchMode: SwitchMode?,
	Friendly: {BattleStep},
	Enemy: {BattleStep},
	PlayerCreatureIndex: number?,
	PlayerCreature: Creature?,
	FoeCreatureIndex: number?,
	FoeCreature: Creature?,
	Rewards: any?,
	BattleEnd: boolean?,
	HP: number?,
	MaxHP: number?,
}

-- Battle State (Server-side)
export type BattleState = {
	id: string,
	Player: Player,
	Type: BattleMode,
	Turn: number,
	PlayerCreatureIndex: number,
	PlayerCreatureOriginalIndex: number?,
	PlayerCreature: Creature,
	PlayerCreatureOriginalData: Creature?,
	FoeCreature: Creature,
	FoeCreatureIndex: number?,
	SwitchMode: SwitchMode?,
	EscapeAttempts: number,
	Chunk: string,
	TrainerName: string?,
	TrainerTeam: {Creature}?,
	-- Entry Hazards
	PlayerHazards: EntryHazards?, -- Hazards on the player's side (damage player's switch-ins)
	FoeHazards: EntryHazards?,    -- Hazards on the foe's side (damage foe's switch-ins)
	-- Add other fields as needed
}

-- Client Battle State
export type ClientBattleState = {
	Type: BattleMode,
	TurnNumber: number,
	PlayerCreatureIndex: number,
	PlayerCreature: Creature,
	FoeCreature: Creature,
	SwitchMode: SwitchMode?,
	PlayerTurnUsed: boolean,
	EnemyTurnUsed: boolean,
	EscapeAttempts: number,
	SwitchSpawnPending: boolean?,
	PendingGoMessage: string?,
}

-- Damage Calculation Result
export type DamageResult = {
	damage: number,
	isCrit: boolean,
	effectiveness: number | string,
	stab: number,
}

-- Action Request (Client → Server)
export type ActionRequest = {
	kind: "Move" | "Switch" | "Run" | "Forfeit",
	slot: number?,
	partyIndex: number?,
}

return {}

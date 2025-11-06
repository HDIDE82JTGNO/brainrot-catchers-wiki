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
export type StepType = "Switch" | "Message" | "Move" | "Damage" | "Heal" | "Status" | "StatStage" | "Faint" | "Miss" | "Crit" | "Flinch"

-- Battle Step
export type BattleStep = {
	Type: StepType,
	Message: string?,
	Damage: number?,
	NewHP: number?,
	Critical: boolean?,
	Effectiveness: string?,
	FlinchTarget: string?,
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

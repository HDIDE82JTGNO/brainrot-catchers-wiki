/**
 * Damage calculation utilities
 * Based on Pokémon-style damage formula adapted for Brainrot Catchers
 */

import { getTypeEffectiveness } from './typeEffectiveness';
import { Creature, Move } from '@/types';

export interface DamageCalculationParams {
  attacker: Creature;
  defender: Creature;
  move: Move;
  attackerLevel?: number;
  defenderLevel?: number;
  attackerAttackStage?: number;
  defenderDefenseStage?: number;
  isCritical?: boolean;
}

export interface DamageResult {
  min: number;
  max: number;
  average: number;
  minCrit: number;
  maxCrit: number;
  averageCrit: number;
  effectiveness: number;
  effectivenessLabel: string;
  stab: number;
  koChance: number; // Percentage chance to KO (assuming max damage)
}

/**
 * Get STAB (Same Type Attack Bonus) multiplier
 */
function getSTAB(moveType: string, attackerTypes: string[]): number {
  if (!moveType || !attackerTypes) return 1;
  
  // Check if move type matches any of attacker's types
  const moveTypeLower = moveType.toLowerCase();
  for (const attackerType of attackerTypes) {
    if (attackerType.toLowerCase() === moveTypeLower) {
      return 1.5;
    }
  }
  
  return 1;
}

/**
 * Get stat stage multiplier
 * Stages range from -6 to +6
 */
function getStatStageMultiplier(stage: number): number {
  if (stage === 0) return 1;
  if (stage > 0) {
    return (2 + stage) / 2;
  } else {
    return 2 / (2 - stage);
  }
}

/**
 * Calculate damage using Pokémon-style formula
 */
export function calculateDamage(params: DamageCalculationParams): DamageResult {
  const {
    attacker,
    defender,
    move,
    attackerLevel = 50,
    defenderLevel = 50,
    attackerAttackStage = 0,
    defenderDefenseStage = 0,
    isCritical = false,
  } = params;

  // Get base stats
  const attackStat = move.Category === 'Physical' 
    ? attacker.BaseStats.Attack 
    : attacker.BaseStats.SpecialAttack;
  const defenseStat = move.Category === 'Physical'
    ? defender.BaseStats.Defense
    : defender.BaseStats.SpecialDefense;

  // Apply stat stages (crits ignore negative stat stages)
  let finalAttack = attackStat;
  let finalDefense = defenseStat;

  if (isCritical) {
    // Crits ignore defender's positive stat stages and attacker's negative stat stages
    if (attackerAttackStage < 0) {
      finalAttack = attackStat; // Ignore negative stages
    } else {
      finalAttack = Math.floor(attackStat * getStatStageMultiplier(attackerAttackStage));
    }
    if (defenderDefenseStage > 0) {
      finalDefense = defenseStat; // Ignore positive stages
    } else {
      finalDefense = Math.floor(defenseStat * getStatStageMultiplier(defenderDefenseStage));
    }
  } else {
    finalAttack = Math.floor(attackStat * getStatStageMultiplier(attackerAttackStage));
    finalDefense = Math.floor(defenseStat * getStatStageMultiplier(defenderDefenseStage));
  }

  // Ensure minimum values
  finalAttack = Math.max(1, finalAttack);
  finalDefense = Math.max(1, finalDefense);

  // Base damage calculation (Pokémon formula)
  const levelFactor = Math.floor((2 * attackerLevel) / 5) + 2;
  const basePower = move.BasePower || 0;
  const baseDamage = Math.floor((levelFactor * basePower * (finalAttack / finalDefense)) / 50) + 2;

  // Calculate modifiers
  const stab = getSTAB(move.Type, attacker.Types || []);
  const effectiveness = getTypeEffectiveness(move.Type, defender.Types || []);
  const critMultiplier = isCritical ? 1.5 : 1;

  // Random factor (0.85 to 1.0)
  const minRandom = 0.85;
  const maxRandom = 1.0;

  // Calculate damage ranges
  const baseWithModifiers = Math.floor(baseDamage * stab * effectiveness * critMultiplier);
  const min = Math.max(1, Math.floor(baseWithModifiers * minRandom));
  const max = Math.max(1, Math.floor(baseWithModifiers * maxRandom));
  const average = Math.floor((min + max) / 2);

  // Critical hit damage
  const critBase = Math.floor(baseDamage * stab * effectiveness * 1.5);
  const minCrit = Math.max(1, Math.floor(critBase * minRandom));
  const maxCrit = Math.max(1, Math.floor(critBase * maxRandom));
  const averageCrit = Math.floor((minCrit + maxCrit) / 2);

  // Effectiveness label
  let effectivenessLabel = 'Normal';
  if (effectiveness === 0) effectivenessLabel = 'Immune';
  else if (effectiveness >= 4) effectivenessLabel = '4× Super Effective';
  else if (effectiveness >= 2) effectivenessLabel = 'Super Effective';
  else if (effectiveness <= 0.25) effectivenessLabel = '2× Not Very Effective';
  else if (effectiveness <= 0.5) effectivenessLabel = 'Not Very Effective';

  // KO chance (assuming defender has full HP)
  const defenderHP = defender.BaseStats.HP;
  const koChance = defenderHP > 0 ? Math.min(100, Math.round((max / defenderHP) * 100)) : 0;

  return {
    min,
    max,
    average,
    minCrit,
    maxCrit,
    averageCrit,
    effectiveness,
    effectivenessLabel,
    stab,
    koChance,
  };
}

/**
 * Calculate damage for multiple scenarios
 */
export function calculateDamageScenarios(
  attacker: Creature,
  defender: Creature,
  move: Move,
  options?: {
    attackerLevel?: number;
    defenderLevel?: number;
    includeCrit?: boolean;
  }
) {
  const scenarios = [];
  
  // Normal hit
  scenarios.push({
    label: 'Normal Hit',
    ...calculateDamage({
      attacker,
      defender,
      move,
      attackerLevel: options?.attackerLevel,
      defenderLevel: options?.defenderLevel,
      isCritical: false,
    }),
  });

  // Critical hit
  if (options?.includeCrit !== false) {
    scenarios.push({
      label: 'Critical Hit',
      ...calculateDamage({
        attacker,
        defender,
        move,
        attackerLevel: options?.attackerLevel,
        defenderLevel: options?.defenderLevel,
        isCritical: true,
      }),
    });
  }

  return scenarios;
}


/**
 * Type effectiveness calculations
 * Handles type multipliers and dual-type combinations
 */

import typeChartData from '../data/types.json';

export type TypeName = keyof typeof typeChartData;

/**
 * Calculate type effectiveness multiplier for a move type against defender types
 * @param attackType The type of the attacking move
 * @param defenderTypes Array of defender types (1 or 2 types)
 * @returns Effectiveness multiplier (0, 0.25, 0.5, 1, 2, or 4)
 */
export function getTypeEffectiveness(
  attackType: string,
  defenderTypes: string[]
): number {
  const chart = typeChartData as Record<string, Record<string, number>>;
  const attackRow = chart[attackType];
  
  if (!attackRow || !defenderTypes || defenderTypes.length === 0) {
    return 1;
  }

  // For dual types, multiply the multipliers
  let multiplier = 1;
  for (const defenderType of defenderTypes) {
    const typeMult = attackRow[defenderType] ?? 1;
    multiplier *= typeMult;
  }

  return multiplier;
}

/**
 * Get effectiveness description
 */
export function getEffectivenessLabel(multiplier: number): string {
  if (multiplier === 0) return 'Immune';
  if (multiplier >= 4) return '4× Super Effective';
  if (multiplier >= 2) return 'Super Effective';
  if (multiplier >= 1) return 'Normal';
  if (multiplier >= 0.5) return 'Not Very Effective';
  if (multiplier >= 0.25) return '2× Not Very Effective';
  return 'Immune';
}

/**
 * Get effectiveness color class
 */
export function getEffectivenessColor(multiplier: number): string {
  if (multiplier === 0) return 'bg-gray-200 text-gray-600';
  if (multiplier >= 4) return 'bg-green-600 text-white';
  if (multiplier >= 2) return 'bg-green-500 text-white';
  if (multiplier >= 1) return 'bg-slate-200 text-slate-700';
  if (multiplier >= 0.5) return 'bg-orange-300 text-orange-800';
  if (multiplier >= 0.25) return 'bg-red-300 text-red-800';
  return 'bg-gray-200 text-gray-600';
}

/**
 * Get all types
 */
export function getAllTypes(): string[] {
  return Object.keys(typeChartData).sort();
}

/**
 * Calculate defensive effectiveness (what types are effective against this creature)
 */
export function getDefensiveEffectiveness(defenderTypes: string[]): Record<string, number> {
  const allTypes = getAllTypes();
  const effectiveness: Record<string, number> = {};
  
  for (const attackType of allTypes) {
    effectiveness[attackType] = getTypeEffectiveness(attackType, defenderTypes);
  }
  
  return effectiveness;
}

/**
 * Get weaknesses (types that deal 2x or more damage)
 */
export function getWeaknesses(defenderTypes: string[]): string[] {
  const effectiveness = getDefensiveEffectiveness(defenderTypes);
  return Object.entries(effectiveness)
    .filter(([_, mult]) => mult >= 2)
    .map(([type]) => type);
}

/**
 * Get resistances (types that deal 0.5x or less damage)
 */
export function getResistances(defenderTypes: string[]): string[] {
  const effectiveness = getDefensiveEffectiveness(defenderTypes);
  return Object.entries(effectiveness)
    .filter(([_, mult]) => mult <= 0.5 && mult > 0)
    .map(([type]) => type);
}

/**
 * Get immunities (types that deal 0x damage)
 */
export function getImmunities(defenderTypes: string[]): string[] {
  const effectiveness = getDefensiveEffectiveness(defenderTypes);
  return Object.entries(effectiveness)
    .filter(([_, mult]) => mult === 0)
    .map(([type]) => type);
}


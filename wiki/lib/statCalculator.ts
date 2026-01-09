import { StatBlock } from './teamTypes';

/**
 * Calculate HP stat using Pokemon formula
 * HP: floor(((2*Base + IV + floor(EV/4)) * Level) / 100) + Level + 10
 */
export function calculateHP(baseHP: number, level: number, iv: number, ev: number): number {
  return Math.floor(((2 * baseHP + iv + Math.floor(ev / 4)) * level) / 100) + level + 10;
}

/**
 * Calculate other stats using Pokemon formula
 * Others: floor(((2*Base + IV + floor(EV/4)) * Level) / 100) + 5
 */
export function calculateStat(baseStat: number, level: number, iv: number, ev: number): number {
  return Math.floor(((2 * baseStat + iv + Math.floor(ev / 4)) * level) / 100) + 5;
}

/**
 * Calculate all stats for a team member
 */
export function calculateStats(
  baseStats: StatBlock,
  level: number,
  ivs: StatBlock,
  evs: StatBlock
): StatBlock {
  return {
    HP: calculateHP(baseStats.HP, level, ivs.HP, evs.HP),
    Attack: calculateStat(baseStats.Attack, level, ivs.Attack, evs.Attack),
    Defense: calculateStat(baseStats.Defense, level, ivs.Defense, evs.Defense),
    SpecialAttack: calculateStat(baseStats.SpecialAttack, level, ivs.SpecialAttack, evs.SpecialAttack),
    SpecialDefense: calculateStat(baseStats.SpecialDefense, level, ivs.SpecialDefense, evs.SpecialDefense),
    Speed: calculateStat(baseStats.Speed, level, ivs.Speed, evs.Speed),
  };
}

/**
 * Calculate total EVs
 */
export function getTotalEVs(evs: StatBlock): number {
  return evs.HP + evs.Attack + evs.Defense + evs.SpecialAttack + evs.SpecialDefense + evs.Speed;
}

/**
 * Validate IVs (0-31)
 */
export function validateIVs(ivs: StatBlock): boolean {
  const stats = Object.values(ivs) as number[];
  return stats.every(iv => iv >= 0 && iv <= 31);
}

/**
 * Validate EVs (0-252 per stat, 510 total max)
 */
export function validateEVs(evs: StatBlock): boolean {
  const stats = Object.values(evs) as number[];
  const allValid = stats.every(ev => ev >= 0 && ev <= 252);
  const totalValid = getTotalEVs(evs) <= 510;
  return allValid && totalValid;
}


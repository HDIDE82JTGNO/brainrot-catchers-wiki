export interface CaptureCalculationResult {
  a: number;
  b: number;
  scanChance: number; // 0-1
  finalChance: number; // 0-1
  isGuaranteed: boolean;
}

export type StatusType = 'None' | 'Sleep' | 'Freeze' | 'Burn' | 'Paralysis' | 'Poison';
export type CubeType = 'Capture Cube' | 'Premium Cube' | 'Excellence Cube' | 'Rot Cube' | 'Rapid Cube' | 'Glitch Cube';

export const CUBE_BONUSES: Record<CubeType, number> = {
  'Capture Cube': 1.0,
  'Premium Cube': 1.5,
  'Excellence Cube': 2.0,
  'Rot Cube': 3.0,
  'Rapid Cube': 1.5, // Note: Should handle "First Turn" logic in UI or assume condition met
  'Glitch Cube': 1.0, // Special handling needed?
};

export const STATUS_BONUSES: Record<StatusType, number> = {
  'None': 1.0,
  'Sleep': 2.5,
  'Freeze': 2.5,
  'Burn': 1.5,
  'Paralysis': 1.5,
  'Poison': 1.5,
};

export function calculateCaptureChance(
  catchRate: number,
  maxHP: number,
  currentHP: number,
  cubeBonus: number = 1.0,
  statusBonus: number = 1.0
): CaptureCalculationResult {
  // Ensure valid inputs
  maxHP = Math.max(1, Math.floor(maxHP));
  currentHP = Math.max(1, Math.min(maxHP, Math.floor(currentHP)));
  catchRate = Math.max(1, Math.min(255, Math.floor(catchRate)));

  // a = floor(((3 * maxHP - 2 * curHP) * catchRate * ballBonus * statusBonus) / (3 * maxHP))
  let a = Math.floor(
    ((3 * maxHP - 2 * currentHP) * catchRate * cubeBonus * statusBonus) / (3 * maxHP)
  );

  if (a < 1) a = 1;

  if (a >= 255) {
    return {
      a,
      b: 65536,
      scanChance: 1,
      finalChance: 1,
      isGuaranteed: true,
    };
  }

  // b = floor(1048560 / sqrt(sqrt( (16711680 / a) )))
  let denom = 16711680 / a;
  if (denom < 1) denom = 1;
  
  const root4 = Math.sqrt(Math.sqrt(denom));
  const b = Math.floor(1048560 / root4);

  const scanChance = Math.min(1, b / 65536);
  // Three checks must pass
  const finalChance = Math.pow(scanChance, 3);

  return {
    a,
    b,
    scanChance,
    finalChance,
    isGuaranteed: false,
  };
}


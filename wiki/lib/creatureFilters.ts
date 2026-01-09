import { Creature } from '@/types';

export interface StatRange {
  min: number;
  max: number;
}

export interface CreatureFilters {
  types: string[];
  moves: string[];
  abilities: string[];
  hp: StatRange;
  attack: StatRange;
  defense: StatRange;
  specialAttack: StatRange;
  specialDefense: StatRange;
  speed: StatRange;
  catchRate: StatRange;
  weight: StatRange;
  evolutionStatus: 'all' | 'can_evolve' | 'final';
  dexNumber: StatRange;
}

export const INITIAL_FILTERS: CreatureFilters = {
  types: [],
  moves: [],
  abilities: [],
  hp: { min: 0, max: 255 },
  attack: { min: 0, max: 255 },
  defense: { min: 0, max: 255 },
  specialAttack: { min: 0, max: 255 },
  specialDefense: { min: 0, max: 255 },
  speed: { min: 0, max: 255 },
  catchRate: { min: 0, max: 255 },
  weight: { min: 0, max: 1000 },
  evolutionStatus: 'all',
  dexNumber: { min: 1, max: 999 },
};

export function applyFilters(creatures: Creature[], filters: CreatureFilters): Creature[] {
  return creatures.filter(creature => {
    // 1. Types (AND logic - must have ALL selected types)
    if (filters.types.length > 0) {
      if (!creature.Types) return false;
      const hasAllTypes = filters.types.every(t => creature.Types.includes(t));
      if (!hasAllTypes) return false;
    }

    // 2. Moves (OR logic - must have at least ONE selected move)
    if (filters.moves.length > 0) {
        if (!creature.Learnset) return false;
        
        // Flatten learnset moves into a single set
        const learnableMoves = new Set<string>();
        Object.values(creature.Learnset).forEach(moves => {
            if (Array.isArray(moves)) {
                moves.forEach(m => learnableMoves.add(m));
            }
        });

        const hasAnyMove = filters.moves.some(m => learnableMoves.has(m));
        if (!hasAnyMove) return false;
    }

    // 2.5. Abilities (OR logic - must have at least ONE selected ability)
    if (filters.abilities.length > 0) {
        if (!creature.Abilities || creature.Abilities.length === 0) return false;
        const creatureAbilities = creature.Abilities.map(a => a.Name);
        const hasAnyAbility = filters.abilities.some(a => creatureAbilities.includes(a));
        if (!hasAnyAbility) return false;
    }

    // 3. Stats
    if (creature.BaseStats) {
      if (creature.BaseStats.HP < filters.hp.min || creature.BaseStats.HP > filters.hp.max) return false;
      if (creature.BaseStats.Attack < filters.attack.min || creature.BaseStats.Attack > filters.attack.max) return false;
      if (creature.BaseStats.Defense < filters.defense.min || creature.BaseStats.Defense > filters.defense.max) return false;
      if (creature.BaseStats.SpecialAttack < filters.specialAttack.min || creature.BaseStats.SpecialAttack > filters.specialAttack.max) return false;
      if (creature.BaseStats.SpecialDefense < filters.specialDefense.min || creature.BaseStats.SpecialDefense > filters.specialDefense.max) return false;
      if (creature.BaseStats.Speed < filters.speed.min || creature.BaseStats.Speed > filters.speed.max) return false;
    }

    // 4. Catch Rate
    const catchRate = creature.CatchRateScalar || 0;
    if (catchRate < filters.catchRate.min || catchRate > filters.catchRate.max) return false;

    // 5. Weight
    const weight = creature.BaseWeightKg || 0;
    if (weight < filters.weight.min || weight > filters.weight.max) return false;

    // 6. Evolution Status
    if (filters.evolutionStatus !== 'all') {
      if (filters.evolutionStatus === 'can_evolve') {
        if (!creature.EvolvesInto) return false;
      } else if (filters.evolutionStatus === 'final') {
        if (creature.EvolvesInto) return false;
      }
    }

    // 7. Dex Number
    const dexNum = creature.DexNumber || 0;
    if (dexNum < filters.dexNumber.min || dexNum > filters.dexNumber.max) return false;

    return true;
  });
}


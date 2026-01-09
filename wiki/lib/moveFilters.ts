import { Move } from '@/types';

export interface StatRange {
  min: number;
  max: number;
}

export interface MoveFilters {
  search: string;
  types: string[];
  categories: string[];
  power: StatRange;
  accuracy: StatRange;
  priority: StatRange;
  effects: {
    hasStatus: boolean;
    hasMultiHit: boolean;
    hasRecoil: boolean;
    hasPriority: boolean;
    hasHealing: boolean;
    hasStatChanges: boolean;
    hasFlinch: boolean;
    hasConfusion: boolean;
  };
}

export const INITIAL_FILTERS: MoveFilters = {
  search: '',
  types: [],
  categories: [],
  power: { min: 0, max: 200 },
  accuracy: { min: 0, max: 100 },
  priority: { min: -5, max: 5 },
  effects: {
    hasStatus: false,
    hasMultiHit: false,
    hasRecoil: false,
    hasPriority: false,
    hasHealing: false,
    hasStatChanges: false,
    hasFlinch: false,
    hasConfusion: false,
  },
};

export function hasMultiHit(move: Move): boolean {
  if (move.MultiHit) return true;
  if ((move as any).MinHits && (move as any).MaxHits) return true;
  return false;
}

export function hasPriority(move: Move): boolean {
  return move.Priority !== 0;
}

export function applyFilters(moves: Move[], filters: MoveFilters): Move[] {
  return moves.filter(move => {
    // 1. Search (name or description)
    if (filters.search) {
      const searchLower = filters.search.toLowerCase();
      const matchesName = move.Name.toLowerCase().includes(searchLower);
      const matchesDescription = move.Description?.toLowerCase().includes(searchLower);
      if (!matchesName && !matchesDescription) return false;
    }

    // 2. Types
    if (filters.types.length > 0) {
      if (!filters.types.includes(move.Type)) return false;
    }

    // 3. Categories
    if (filters.categories.length > 0) {
      if (!filters.categories.includes(move.Category)) return false;
    }

    // 4. Power range
    const power = move.BasePower || 0;
    if (power < filters.power.min || power > filters.power.max) return false;

    // 5. Accuracy range
    const accuracy = move.Accuracy || 0;
    if (accuracy < filters.accuracy.min || accuracy > filters.accuracy.max) return false;

    // 6. Priority range
    const priority = move.Priority || 0;
    if (priority < filters.priority.min || priority > filters.priority.max) return false;

    // 7. Effect filters
    if (filters.effects.hasStatus && !move.StatusEffect) return false;
    if (filters.effects.hasMultiHit && !hasMultiHit(move)) return false;
    if (filters.effects.hasRecoil && !move.RecoilPercent) return false;
    if (filters.effects.hasPriority && !hasPriority(move)) return false;
    if (filters.effects.hasHealing && (!move.HealsPercent || move.HealsPercent <= 0)) return false;
    if (filters.effects.hasStatChanges && (!move.StatChanges || (Array.isArray(move.StatChanges) && move.StatChanges.length === 0))) return false;
    if (filters.effects.hasFlinch && !move.CausesFlinch) return false;
    if (filters.effects.hasConfusion && !move.CausesConfusion) return false;

    return true;
  });
}

export function getActiveFilterCount(filters: MoveFilters): number {
  let count = 0;
  if (filters.search) count++;
  if (filters.types.length > 0) count++;
  if (filters.categories.length > 0) count++;
  if (filters.power.min > 0 || filters.power.max < 200) count++;
  if (filters.accuracy.min > 0 || filters.accuracy.max < 100) count++;
  if (filters.priority.min > -5 || filters.priority.max < 5) count++;
  if (filters.effects.hasStatus) count++;
  if (filters.effects.hasMultiHit) count++;
  if (filters.effects.hasRecoil) count++;
  if (filters.effects.hasPriority) count++;
  if (filters.effects.hasHealing) count++;
  if (filters.effects.hasStatChanges) count++;
  if (filters.effects.hasFlinch) count++;
  if (filters.effects.hasConfusion) count++;
  return count;
}


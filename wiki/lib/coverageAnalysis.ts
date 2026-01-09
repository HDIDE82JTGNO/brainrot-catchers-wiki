/**
 * Move coverage analysis utilities
 * Analyzes which types can be hit effectively by a set of moves
 */

import { getAllTypes, getTypeEffectiveness } from './typeEffectiveness';
import { Move } from '@/types';

export interface CoverageResult {
  type: string;
  effectiveness: number;
  bestMove: Move | null;
  canHit: boolean;
}

export interface CoverageAnalysis {
  superEffective: CoverageResult[];
  normal: CoverageResult[];
  notVeryEffective: CoverageResult[];
  immune: CoverageResult[];
  coveragePercentage: number;
  gaps: string[];
}

/**
 * Analyze move coverage for a set of moves
 */
export function analyzeMoveCoverage(moves: Move[]): CoverageAnalysis {
  const allTypes = getAllTypes();
  const coverage: CoverageResult[] = [];

  // For each defender type, find the best move effectiveness
  for (const defenderType of allTypes) {
    let bestEffectiveness = 0;
    let bestMove: Move | null = null;

    for (const move of moves) {
      const effectiveness = getTypeEffectiveness(move.Type, [defenderType]);
      if (effectiveness > bestEffectiveness) {
        bestEffectiveness = effectiveness;
        bestMove = move;
      }
    }

    coverage.push({
      type: defenderType,
      effectiveness: bestEffectiveness,
      bestMove,
      canHit: bestEffectiveness > 0,
    });
  }

  // Categorize results
  const superEffective = coverage.filter(c => c.effectiveness >= 2);
  const normal = coverage.filter(c => c.effectiveness === 1);
  const notVeryEffective = coverage.filter(c => c.effectiveness > 0 && c.effectiveness < 1);
  const immune = coverage.filter(c => c.effectiveness === 0);

  // Calculate coverage percentage (types that can be hit super effectively or normally)
  const coveredTypes = coverage.filter(c => c.effectiveness >= 1).length;
  const coveragePercentage = (coveredTypes / allTypes.length) * 100;

  // Find coverage gaps (types that can't be hit effectively)
  const gaps = coverage
    .filter(c => c.effectiveness < 1)
    .map(c => c.type);

  return {
    superEffective,
    normal,
    notVeryEffective,
    immune,
    coveragePercentage,
    gaps,
  };
}

/**
 * Get recommended moves to improve coverage
 */
export function getRecommendedMoves(
  currentMoves: Move[],
  allMoves: Move[],
  targetTypes?: string[]
): Move[] {
  const currentCoverage = analyzeMoveCoverage(currentMoves);
  const gaps = targetTypes || currentCoverage.gaps;

  if (gaps.length === 0) return [];

  // Find moves that can hit the gap types super effectively
  const recommendations: Move[] = [];
  const currentMoveNames = new Set(currentMoves.map(m => m.Name));

  for (const gapType of gaps) {
    for (const move of allMoves) {
      if (currentMoveNames.has(move.Name)) continue;

      const effectiveness = getTypeEffectiveness(move.Type, [gapType]);
      if (effectiveness >= 2) {
        // Check if this move is already recommended
        if (!recommendations.some(m => m.Name === move.Name)) {
          recommendations.push(move);
        }
      }
    }
  }

  // Sort by base power (prefer stronger moves)
  return recommendations.sort((a, b) => (b.BasePower || 0) - (a.BasePower || 0)).slice(0, 10);
}

/**
 * Analyze team coverage (combines moves from multiple creatures)
 */
export function analyzeTeamCoverage(creatureMovesets: Move[][]): CoverageAnalysis {
  // Combine all moves from all creatures
  const allMoves: Move[] = [];
  const seenMoveNames = new Set<string>();

  for (const moveset of creatureMovesets) {
    for (const move of moveset) {
      if (!seenMoveNames.has(move.Name)) {
        allMoves.push(move);
        seenMoveNames.add(move.Name);
      }
    }
  }

  return analyzeMoveCoverage(allMoves);
}


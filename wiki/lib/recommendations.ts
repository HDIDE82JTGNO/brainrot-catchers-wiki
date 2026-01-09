/**
 * Recommendations engine
 * Provides suggestions for similar creatures, moves, etc.
 */

import { Creature, Move } from '@/types';
import { getTypeEffectiveness } from './typeEffectiveness';

/**
 * Find similar creatures based on types and stats
 */
export function findSimilarCreatures(
  creature: Creature,
  allCreatures: Creature[],
  limit: number = 5
): Creature[] {
  const scores = allCreatures
    .filter(c => c.Id !== creature.Id)
    .map(other => {
      let score = 0;

      // Type similarity
      const creatureTypes = new Set(creature.Types || []);
      const otherTypes = new Set(other.Types || []);
      const commonTypes = [...creatureTypes].filter(t => otherTypes.has(t));
      score += commonTypes.length * 10;

      // Stat similarity (using total BST)
      const creatureBST = Object.values(creature.BaseStats).reduce((a, b) => a + b, 0);
      const otherBST = Object.values(other.BaseStats).reduce((a, b) => a + b, 0);
      const bstDiff = Math.abs(creatureBST - otherBST);
      score += Math.max(0, 100 - bstDiff / 10);

      // Stat distribution similarity
      const statKeys: (keyof typeof creature.BaseStats)[] = ['HP', 'Attack', 'Defense', 'SpecialAttack', 'SpecialDefense', 'Speed'];
      let statSimilarity = 0;
      for (const key of statKeys) {
        const diff = Math.abs(creature.BaseStats[key] - other.BaseStats[key]);
        statSimilarity += Math.max(0, 50 - diff);
      }
      score += statSimilarity / statKeys.length;

      return { creature: other, score };
    })
    .sort((a, b) => b.score - a.score)
    .slice(0, limit)
    .map(item => item.creature);

  return scores;
}

/**
 * Recommend moves for a creature based on type coverage
 */
export function recommendMoves(
  creature: Creature,
  allMoves: Move[],
  limit: number = 10
): Move[] {
  const creatureTypes = creature.Types || [];
  const creatureMoveNames = new Set<string>();
  
  if (creature.Learnset) {
    Object.values(creature.Learnset).forEach(moveList => {
      if (Array.isArray(moveList)) {
        moveList.forEach(name => creatureMoveNames.add(name));
      }
    });
  }

  // Get moves the creature can learn
  const learnableMoves = allMoves.filter(m => creatureMoveNames.has(m.Name));

  // Score moves based on:
  // 1. STAB (Same Type Attack Bonus)
  // 2. Base Power
  // 3. Coverage (hitting types the creature's types don't cover well)
  const scoredMoves = learnableMoves.map(move => {
    let score = 0;

    // STAB bonus
    const hasSTAB = creatureTypes.some(t => t === move.Type);
    if (hasSTAB) score += 50;

    // Base power
    score += (move.BasePower || 0) * 0.5;

    // Priority moves are valuable
    if (move.Priority && move.Priority > 0) score += 20;

    // Status moves with effects
    if (move.Category === 'Status') {
      if (move.StatusEffect) score += 15;
      if (move.StatChanges) score += 10;
    }

    return { move, score };
  });

  return scoredMoves
    .sort((a, b) => b.score - a.score)
    .slice(0, limit)
    .map(item => item.move);
}

/**
 * Find creatures that learn a specific move
 */
export function findCreaturesWithMove(
  moveName: string,
  allCreatures: Creature[]
): Creature[] {
  return allCreatures.filter(creature => {
    if (!creature.Learnset) return false;
    
    for (const moveList of Object.values(creature.Learnset)) {
      if (Array.isArray(moveList) && moveList.includes(moveName)) {
        return true;
      }
    }
    
    return false;
  });
}

/**
 * Recommend team members based on coverage gaps
 */
export function recommendTeamMembers(
  currentTeam: Creature[],
  allCreatures: Creature[],
  limit: number = 5
): Creature[] {
  // Get all types covered by current team
  const coveredTypes = new Set<string>();
  currentTeam.forEach(creature => {
    creature.Types?.forEach(type => coveredTypes.add(type));
  });

  // Find creatures that add new type coverage
  const scores = allCreatures
    .filter(c => !currentTeam.some(t => t.Id === c.Id))
    .map(creature => {
      let score = 0;
      const creatureTypes = new Set(creature.Types || []);

      // Bonus for new types
      creatureTypes.forEach(type => {
        if (!coveredTypes.has(type)) {
          score += 20;
        }
      });

      // Bonus for high BST
      const bst = Object.values(creature.BaseStats).reduce((a, b) => a + b, 0);
      score += bst / 10;

      return { creature, score };
    })
    .sort((a, b) => b.score - a.score)
    .slice(0, limit)
    .map(item => item.creature);

  return scores;
}


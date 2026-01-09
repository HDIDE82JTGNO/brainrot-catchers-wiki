import { Creature } from '@/types';

/**
 * Builds the complete evolution chain for a given creature
 * @param creatureName - The name of the creature to build the chain for
 * @param allCreatures - Array of all creatures
 * @returns Ordered array of creatures in the evolution chain: [pre-evo1, pre-evo2, ..., current, post-evo1, post-evo2, ...]
 */
export function buildEvolutionChain(creatureName: string, allCreatures: Creature[]): Creature[] {
  // Find the current creature
  const currentCreature = allCreatures.find(c => c.Name === creatureName);
  if (!currentCreature) {
    return [];
  }

  const chain: Creature[] = [];
  
  // Build pre-evolution chain (find all creatures that evolve into the current one)
  const preEvolutions: Creature[] = [];
  let searchName = creatureName;
  
  // Keep searching backwards until we find the base form
  while (true) {
    const preEvo = allCreatures.find(c => c.EvolvesInto === searchName);
    if (!preEvo) {
      break;
    }
    preEvolutions.unshift(preEvo); // Add to beginning to maintain order
    searchName = preEvo.Name;
  }
  
  // Add pre-evolutions to chain
  chain.push(...preEvolutions);
  
  // Add current creature
  chain.push(currentCreature);
  
  // Build post-evolution chain (follow EvolvesInto chain)
  const postEvolutions: Creature[] = [];
  let nextName: string | undefined = currentCreature.EvolvesInto;

  while (nextName) {
    const nextEvo = allCreatures.find(c => c.Name === nextName);
    if (!nextEvo) {
      break;
    }
    postEvolutions.push(nextEvo);
    nextName = nextEvo.EvolvesInto;
  }
  
  // Add post-evolutions to chain
  chain.push(...postEvolutions);
  
  // Return chain (if only one creature, return empty array as there's no evolution line to show)
  return chain.length > 1 ? chain : [];
}


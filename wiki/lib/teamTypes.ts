import { Creature } from '@/types';

export interface StatBlock {
  HP: number;
  Attack: number;
  Defense: number;
  SpecialAttack: number;
  SpecialDefense: number;
  Speed: number;
}

export interface TeamMember extends Creature {
  ivs: StatBlock;
  evs: StatBlock;
  moves: string[];
  level: number;
  heldItem?: string;
}

export function createDefaultTeamMember(creature: Creature): TeamMember {
  return {
    ...creature,
    ivs: {
      HP: 0,
      Attack: 0,
      Defense: 0,
      SpecialAttack: 0,
      SpecialDefense: 0,
      Speed: 0,
    },
    evs: {
      HP: 0,
      Attack: 0,
      Defense: 0,
      SpecialAttack: 0,
      SpecialDefense: 0,
      Speed: 0,
    },
    moves: [],
    level: 50,
    heldItem: undefined,
  };
}


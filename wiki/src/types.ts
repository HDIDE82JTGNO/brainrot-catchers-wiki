export interface Creature {
  Id: string;
  DexNumber: number;
  Name: string;
  Sprite: string;
  ShinySprite: string;
  Description: string;
  Types: string[];
  BaseStats: {
    HP: number;
    Attack: number;
    Defense: number;
    SpecialAttack: number;
    SpecialDefense: number;
    Speed: number;
  };
  Learnset: { [level: string]: string[] } | null;
  EvolutionLevel?: number;
  EvolvesInto?: string;
  BaseWeightKg?: number;
  ShinyColors?: any;
  Class?: string;
  CatchRateScalar?: number;
  FemaleChance?: number;
}

export interface Item {
  Name: string;
  Stats: { HP: number; Attack: number; Defense: number; Speed: number };
  Description: string;
  Category: string;
  UsableInBattle: boolean;
  UsableInOverworld: boolean;
  Image: string;
}

export interface Move {
  Name: string;
  BasePower: number;
  Accuracy: number;
  Priority: number;
  Type: string;
  Category: string;
  Description: string;
  HealsPercent?: number;
  StatusEffect?: string;
  StatusChance?: number;
  CausesFlinch?: boolean;
  CausesConfusion?: boolean;
  StatChanges?: any;
  MultiHit?: any;
  RecoilPercent?: number;
}

export interface Location {
  Id: string;
  Name: string;
  Encounters: Encounter[];
  Parent?: string;
}

export type Encounter = [string, number, number, number];

export type TypeChart = { [attacker: string]: { [defender: string]: number } };


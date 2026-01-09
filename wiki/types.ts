export interface Creature {
  Id: string;
  Slug: string;
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
  Abilities?: AbilityEntry[];
}

export interface AbilityEntry {
  Name: string;
  Chance: number;
}

export interface Ability {
  Id: string;
  Name: string;
  Description: string;
  TriggerType: string;
  [key: string]: any; // For additional ability properties
}

export interface Item {
  Id: string;
  Slug: string;
  Name: string;
  Stats: { HP: number; Attack: number; Defense: number; Speed: number };
  Description: string;
  Category: string;
  UsableInBattle: boolean;
  UsableInOverworld: boolean;
  Image: string;
}

export interface Move {
  Id: string;
  Slug: string;
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
  Slug: string;
  Name: string;
  Encounters: Encounter[];
  Parent?: string;
  Description?: string;
}

export interface Encounter {
  Creature: string;
  MinLevel: number;
  MaxLevel: number;
  Chance: number;
}

export type TypeChart = { [attacker: string]: { [defender: string]: number } };

"use client";

import { GlobalSearch } from './GlobalSearch';
import creaturesData from '../data/creatures.json';
import movesData from '../data/moves.json';
import itemsData from '../data/items.json';
import locationsData from '../data/locations.json';
import { Creature, Move, Item, Location } from '@/types';

const creatures = creaturesData as unknown as Creature[];
const moves = movesData as unknown as Move[];
const items = itemsData as unknown as Item[];
const locations = locationsData as unknown as Location[];

export function GlobalSearchWrapper() {
  return (
    <GlobalSearch
      creatures={creatures}
      moves={moves}
      items={items}
      locations={locations}
    />
  );
}


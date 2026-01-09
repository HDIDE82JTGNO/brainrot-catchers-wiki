import { Item } from '@/types';

// Constants for ML sprite handling
const ML_SPRITE_SIZE = 149;
const ML_SPRITE_PATH = '/items/ML.webp';

// Type offset mapping from Bag.lua
const TYPE_OFFSETS: Record<string, [number, number]> = {
  'Normal': [0, 0],
  'Fire': [147, 0],
  'Ice': [293, 0],
  'Electric': [586, 0],
  'Grass': [730, 0],
  'Fighting': [0, 135],
  'Poison': [147, 135],
  'Ground': [438, 135],
  'Psychic': [585, 135],
  'Bug': [729, 135],
  'Rock': [0, 269],
  'Ghost': [294, 269],
  'Dragon': [440, 269],
  'Dark': [585, 269],
  'Steel': [730, 269],
  'Fairy': [880, 269],
};

interface ItemImageInfo {
  src: string;
  isSprite: boolean;
  style?: React.CSSProperties;
}

export function getItemImageInfo(item: Item, moves: any[]): ItemImageInfo {
  // Check if it's an ML item
  if (item.Name.startsWith('ML - ')) {
    return {
      src: ML_SPRITE_PATH,
      isSprite: true
    };
  }

  // Regular item
  return {
    src: `/items/${item.Name}.webp`,
    isSprite: false
  };
}

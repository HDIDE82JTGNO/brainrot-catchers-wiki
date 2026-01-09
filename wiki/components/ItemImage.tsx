"use client";

import React, { useEffect, useState } from 'react';
import { Item } from '@/types';
import { getItemImageInfo } from '../lib/itemImageUtils';

interface ItemImageProps {
  item: Item;
  moves: any[];
  className?: string;
  size?: number;
}

export function ItemImage({ item, moves, className = '', size = 64 }: ItemImageProps) {
  const { src, isSprite } = getItemImageInfo(item, moves);
  const [spriteLoaded, setSpriteLoaded] = useState(false);

  if (isSprite) {
    const ML_SPRITE_PATH = '/items/ML.webp';
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

    let offset = [0, 0];
    if (item.Name.startsWith('ML - ')) {
        const moveName = item.Name.replace('ML - ', '');
        const move = moves.find(m => m.Name === moveName);
        if (move) {
            let typeName = 'Normal';
            if (Array.isArray(move.Type)) {
                if (move.Type.length > 0) typeName = move.Type[0];
            } else if (move.Type) {
                typeName = move.Type;
            }
            offset = TYPE_OFFSETS[typeName] || [0, 0];
        }
    }

    // IMPORTANT: The sprite sheet dimensions. 
    // Based on the max offset X (880) + width (149) = 1029.
    // The closest power of 2 is 1024, but 1029 is larger.
    // However, looking at the layout:
    // Row 1: 0, 147, 293, 440 (missing?), 586, 730
    // The gaps are: 147, 146, 147, ...
    // It seems roughly 147px per icon horizontally? But Bag.lua says 149x149.
    // If the image is loaded naturally, we can use background-position with pixel values.
    // To scale it down, we use background-size.
    
    // We'll use a hardcoded estimation of the sheet width based on the last column (880) + icon width (149) = 1029.
    // It's likely the sheet is exactly 1029px wide or slightly larger (e.g. 1030). 
    // Let's assume 1029px for calculation purposes as that covers the content.
    const SHEET_WIDTH = 1029; 
    const ICON_SIZE = 149;
    
    // Scaling factor: how much to scale the background image
    // If we want the icon (149px) to fit in `size` (e.g. 48px), we scale by size/149.
    // The background-size should be SHEET_WIDTH * scale.
    const scale = size / ICON_SIZE;
    const bgWidth = SHEET_WIDTH * scale;
    
    const bgPosX = -offset[0] * scale;
    const bgPosY = -offset[1] * scale;

    return (
      <div 
        className={`relative overflow-hidden ${className}`}
        style={{ width: size, height: size }}
        title={item.Name}
      >
        {/* Debug info on hover 
        <div className="hidden absolute z-10 bg-black text-white text-[8px] p-1 top-0 left-0">
            {offset[0]},{offset[1]}
        </div>
        */}
        <div
            style={{
                width: '100%',
                height: '100%',
                backgroundImage: `url(${ML_SPRITE_PATH})`,
                backgroundPosition: `${bgPosX}px ${bgPosY}px`,
                backgroundSize: `${bgWidth}px auto`,
                backgroundRepeat: 'no-repeat',
                imageRendering: 'pixelated' // Optional, for crisp edges
            }}
        />
      </div>
    );
  }

  // Regular item
  return (
    <div className={`flex items-center justify-center bg-transparent ${className}`} style={{ width: size, height: size }}>
      <img 
        src={src} 
        alt={item.Name} 
        className="w-full h-full object-contain"
        style={{ imageRendering: 'pixelated' }}
        onError={(e) => {
            (e.target as HTMLImageElement).style.display = 'none';
            // Show fallback emoji if image fails
            const span = document.createElement('span');
            span.innerText = '🎒';
            span.className = 'text-2xl';
            (e.target as HTMLImageElement).parentElement?.appendChild(span);
        }}
      />
    </div>
  );
}

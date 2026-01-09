import React, { useMemo } from 'react';
import { Encounter, Creature } from '../types';
import Link from 'next/link';
import { TypeBadge } from './TypeBadge';
import { getSpritePath } from '../lib/spriteUtils';
import creaturesData from '../data/creatures.json';

interface EncounterListProps {
  encounters: any[]; // Using any to match the new object structure from updated extractor
}

const creatures = creaturesData as unknown as Creature[];

export function EncounterList({ encounters }: EncounterListProps) {
  // Create a lookup map for creatures by name
  const creaturesByName = useMemo(() => {
    const map = new Map<string, Creature>();
    creatures.forEach(creature => {
      map.set(creature.Name, creature);
    });
    return map;
  }, []);

  if (!encounters || encounters.length === 0) {
    return <div className="text-slate-400 italic text-sm">No encounters listed.</div>;
  }

  return (
    <ul className="divide-y divide-slate-100 bg-white rounded-lg border border-slate-200 overflow-hidden">
      {encounters.map((enc, idx) => {
        // Handle both old array format and new object format just in case
        const name = enc.Creature || enc[0];
        const minLvl = enc.MinLevel || enc[1];
        const maxLvl = enc.MaxLevel || enc[2];
        const chance = enc.Chance || enc[3];
        
        // Look up creature data
        const creature = creaturesByName.get(name);
        const spritePath = creature ? getSpritePath(name, false) : null;
        const types = creature?.Types || [];
        const femaleChance = creature?.FemaleChance ?? 50;

        return (
          <li key={idx} className="flex items-center gap-4 p-3 hover:bg-slate-50 transition-colors">
            {/* Sprite Image */}
            {spritePath && (
              <div className="flex-shrink-0 w-16 h-16 bg-gradient-to-br from-slate-50 to-slate-100 rounded-lg flex items-center justify-center border border-slate-200 overflow-hidden">
                <img 
                  src={spritePath} 
                  alt={name}
                  className="w-full h-full object-contain p-1"
                  style={{ imageRendering: 'pixelated' }}
                  onError={(e) => {
                    (e.target as HTMLImageElement).style.display = 'none';
                  }}
                />
              </div>
            )}
            
            {/* Center: Name, Types, Gender */}
            <div className="flex-1 min-w-0">
              <Link href={`/creatures/${encodeURIComponent(name)}`} className="text-blue-600 hover:underline font-medium text-sm block mb-1">
                {name}
              </Link>
              <div className="flex flex-wrap items-center gap-2 mb-1">
                {types.length > 0 ? (
                  types.map((type, typeIdx) => (
                    <TypeBadge key={typeIdx} type={type} className="scale-90" />
                  ))
                ) : (
                  <span className="text-xs text-slate-400 italic">Unknown type</span>
                )}
              </div>
              <div className="text-xs text-slate-500">
                <span className="font-medium">Gender:</span> ♂ {(100 - femaleChance)}% / ♀ {femaleChance}%
              </div>
            </div>
            
            {/* Right: Level and Chance */}
            <div className="flex flex-col items-end gap-1 text-xs flex-shrink-0">
              <span className="text-slate-500">Lvl {minLvl}-{maxLvl}</span>
              <span className="font-bold text-slate-700 bg-slate-100 px-2 py-1 rounded min-w-[3rem] text-center">
                {chance}%
              </span>
            </div>
          </li>
        );
      })}
    </ul>
  );
}

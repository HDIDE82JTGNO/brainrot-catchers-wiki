import React from 'react';
import { Encounter } from '../types';
import Link from 'next/link';

interface EncounterListProps {
  encounters: Encounter[];
}

export function EncounterList({ encounters }: EncounterListProps) {
  if (!encounters || encounters.length === 0) {
    return <div className="text-gray-500 italic">No encounters listed.</div>;
  }

  return (
    <ul className="divide-y divide-gray-200 bg-white rounded shadow-sm">
      {encounters.map((enc, idx) => {
        const [name, minLvl, maxLvl, chance] = enc;
        return (
          <li key={idx} className="flex justify-between items-center p-3">
            <Link href={`/creatures/${name}`} className="text-blue-600 hover:underline font-medium">
              {name}
            </Link>
            <div className="text-sm text-gray-600">
              <span className="mr-4">Lvl {minLvl}-{maxLvl}</span>
              <span className="font-bold">{chance}%</span>
            </div>
          </li>
        );
      })}
    </ul>
  );
}


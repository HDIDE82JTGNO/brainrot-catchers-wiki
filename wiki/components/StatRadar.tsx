import React from 'react';
import { Creature } from '../types';

interface StatBarProps {
  label: string;
  value: number;
  max?: number;
}

function StatBar({ label, value, max = 255 }: StatBarProps) {
  const percentage = Math.min((value / max) * 100, 100);
  
  // Color based on value (approximate tiers)
  let color = 'bg-red-500';
  if (value >= 60) color = 'bg-yellow-500';
  if (value >= 90) color = 'bg-green-500';
  if (value >= 120) color = 'bg-blue-500';

  return (
    <div className="flex items-center text-sm mb-1">
      <span className="w-24 font-bold text-gray-700">{label}</span>
      <span className="w-8 text-right mr-2 text-gray-600">{value}</span>
      <div className="flex-1 h-3 bg-gray-200 rounded-full overflow-hidden">
        <div 
          className={`h-full ${color}`} 
          style={{ width: `${percentage}%` }}
        />
      </div>
    </div>
  );
}

interface StatRadarProps {
  stats: Creature['BaseStats'];
}

export function StatRadar({ stats }: StatRadarProps) {
  const total = Object.values(stats).reduce((a, b) => a + b, 0);

  return (
    <div className="bg-white p-4 rounded shadow-sm">
      <h3 className="text-lg font-bold mb-2">Base Stats</h3>
      <StatBar label="HP" value={stats.HP} />
      <StatBar label="Attack" value={stats.Attack} />
      <StatBar label="Defense" value={stats.Defense} />
      <StatBar label="Sp. Atk" value={stats.SpecialAttack} />
      <StatBar label="Sp. Def" value={stats.SpecialDefense} />
      <StatBar label="Speed" value={stats.Speed} />
      <div className="mt-2 text-right text-sm font-bold text-gray-500">
        Total: {total}
      </div>
    </div>
  );
}


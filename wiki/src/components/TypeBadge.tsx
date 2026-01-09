import React from 'react';

const TYPE_COLORS: { [key: string]: string } = {
  Normal: 'bg-gray-400',
  Fire: 'bg-red-500',
  Water: 'bg-blue-500',
  Electric: 'bg-yellow-400',
  Grass: 'bg-green-500',
  Ice: 'bg-cyan-300',
  Fighting: 'bg-red-700',
  Poison: 'bg-purple-500',
  Ground: 'bg-yellow-600',
  Flying: 'bg-indigo-300',
  Psychic: 'bg-pink-500',
  Bug: 'bg-lime-500',
  Rock: 'bg-yellow-800',
  Ghost: 'bg-purple-800',
  Dragon: 'bg-indigo-600',
  Steel: 'bg-gray-500',
  Dark: 'bg-gray-800',
  Fairy: 'bg-pink-300',
};

interface TypeBadgeProps {
  type: string;
  className?: string;
}

export function TypeBadge({ type, className = '' }: TypeBadgeProps) {
  const colorClass = TYPE_COLORS[type] || 'bg-gray-500';
  
  return (
    <span className={`px-2 py-1 rounded text-white text-xs font-bold uppercase ${colorClass} ${className}`}>
      {type}
    </span>
  );
}


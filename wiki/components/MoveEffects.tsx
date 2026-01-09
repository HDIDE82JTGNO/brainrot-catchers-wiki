import React from 'react';
import { Move } from '../types';

interface MoveEffectsProps {
  move: Move;
  className?: string;
}

const STATUS_COLORS: { [key: string]: string } = {
  BRN: 'bg-red-600',
  PAR: 'bg-yellow-500',
  PSN: 'bg-purple-600',
  TOX: 'bg-purple-700',
  SLP: 'bg-blue-500',
  FRZ: 'bg-cyan-400',
};

const STATUS_LABELS: { [key: string]: string } = {
  BRN: 'Burn',
  PAR: 'Paralyze',
  PSN: 'Poison',
  TOX: 'Toxic',
  SLP: 'Sleep',
  FRZ: 'Freeze',
};

export function MoveEffects({ move, className = '' }: MoveEffectsProps) {
  const effects: React.ReactNode[] = [];

  // Status Effect
  if (move.StatusEffect) {
    const statusColor = STATUS_COLORS[move.StatusEffect] || 'bg-gray-500';
    const statusLabel = STATUS_LABELS[move.StatusEffect] || move.StatusEffect;
    const chance = move.StatusChance ? `${move.StatusChance}%` : '';
    effects.push(
      <span
        key="status"
        className={`px-2 py-1 rounded text-white text-xs font-bold ${statusColor} ${className}`}
        title={`${statusLabel}${chance ? ` (${chance} chance)` : ''}`}
      >
        {statusLabel}{chance && ` ${chance}`}
      </span>
    );
  }

  // Multi-hit
  if (move.MultiHit) {
    const minHits = move.MultiHit.MinHits || (move as any).MinHits;
    const maxHits = move.MultiHit.MaxHits || (move as any).MaxHits;
    if (minHits && maxHits) {
      effects.push(
        <span
          key="multihit"
          className={`px-2 py-1 rounded text-xs font-bold bg-indigo-100 text-indigo-700 border border-indigo-300 ${className}`}
          title={`Hits ${minHits}-${maxHits} times`}
        >
          {minHits}-{maxHits} hits
        </span>
      );
    }
  } else if ((move as any).MinHits && (move as any).MaxHits) {
    // Handle MinHits/MaxHits at root level
    const minHits = (move as any).MinHits;
    const maxHits = (move as any).MaxHits;
    effects.push(
      <span
        key="multihit"
        className={`px-2 py-1 rounded text-xs font-bold bg-indigo-100 text-indigo-700 border border-indigo-300 ${className}`}
        title={`Hits ${minHits}-${maxHits} times`}
      >
        {minHits}-{maxHits} hits
      </span>
    );
  }

  // Recoil
  if (move.RecoilPercent) {
    effects.push(
      <span
        key="recoil"
        className={`px-2 py-1 rounded text-xs font-bold bg-orange-100 text-orange-700 border border-orange-300 ${className}`}
        title={`User takes ${move.RecoilPercent}% recoil damage`}
      >
        {move.RecoilPercent}% recoil
      </span>
    );
  }

  // Priority
  if (move.Priority !== 0) {
    const priorityText = move.Priority > 0 ? `+${move.Priority}` : `${move.Priority}`;
    effects.push(
      <span
        key="priority"
        className={`px-2 py-1 rounded text-xs font-bold bg-green-100 text-green-700 border border-green-300 ${className}`}
        title={`Priority ${priorityText}`}
      >
        Priority {priorityText}
      </span>
    );
  }

  // Healing
  if (move.HealsPercent && move.HealsPercent > 0) {
    effects.push(
      <span
        key="heal"
        className={`px-2 py-1 rounded text-xs font-bold bg-emerald-100 text-emerald-700 border border-emerald-300 ${className}`}
        title={`Heals ${move.HealsPercent}% of max HP`}
      >
        Heals {move.HealsPercent}%
      </span>
    );
  }

  // Flinch
  if (move.CausesFlinch) {
    effects.push(
      <span
        key="flinch"
        className={`px-2 py-1 rounded text-xs font-bold bg-pink-100 text-pink-700 border border-pink-300 ${className}`}
        title="May cause flinch"
      >
        Flinch
      </span>
    );
  }

  // Confusion
  if (move.CausesConfusion) {
    effects.push(
      <span
        key="confusion"
        className={`px-2 py-1 rounded text-xs font-bold bg-purple-100 text-purple-700 border border-purple-300 ${className}`}
        title="May cause confusion"
      >
        Confusion
      </span>
    );
  }

  // Stat Changes
  if (move.StatChanges && Array.isArray(move.StatChanges) && move.StatChanges.length > 0) {
    const statChanges = move.StatChanges.map((change: any) => {
      const stat = change.Stat || change.stat;
      const amount = change.Stages || change.stages || 0;
      const sign = amount > 0 ? '+' : '';
      return `${sign}${amount} ${stat}`;
    }).join(', ');
    
    effects.push(
      <span
        key="stat"
        className={`px-2 py-1 rounded text-xs font-bold bg-blue-100 text-blue-700 border border-blue-300 ${className}`}
        title={`Stat changes: ${statChanges}`}
      >
        {statChanges}
      </span>
    );
  }

  if (effects.length === 0) {
    return null;
  }

  return (
    <div className="flex flex-wrap gap-1.5">
      {effects}
    </div>
  );
}


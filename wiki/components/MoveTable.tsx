"use client";

import React, { useState } from 'react';
import Link from 'next/link';
import { useTransition, animated, useSpring } from '@react-spring/web';
import { Move, Creature } from '../types';
import { TypeBadge } from './TypeBadge';
import { MoveEffects } from './MoveEffects';
import { getSpringConfig } from '@/lib/springConfigs';

// Type assertion for react-spring animated components with React 19
const AnimatedTr = animated.tr as any;

interface MoveTableProps {
  moves: Move[];
  showPriority?: boolean;
  compact?: boolean;
  moveLearnsetMap?: Map<string, Creature[]>;
}

const CATEGORY_COLORS: { [key: string]: string } = {
  Physical: 'bg-red-100 text-red-700 border-red-300',
  Special: 'bg-blue-100 text-blue-700 border-blue-300',
  Status: 'bg-gray-100 text-gray-700 border-gray-300',
};

export function MoveTable({ moves, showPriority = true, compact = false, moveLearnsetMap }: MoveTableProps) {
  const [expandedRow, setExpandedRow] = useState<number | null>(null);

  // Animate table rows
  const transitions = useTransition(moves, {
    keys: (move) => move.Id || move.Name,
    from: { opacity: 0, transform: 'translateX(-10px)' },
    enter: { opacity: 1, transform: 'translateX(0px)' },
    leave: { opacity: 0, transform: 'translateX(10px)' },
    config: getSpringConfig('gentle'),
    trail: 20,
  });

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full bg-white">
        <thead className="bg-gradient-to-r from-slate-50 to-slate-100 border-b-2 border-slate-200">
          <tr>
            <th className="px-4 py-3 text-left text-xs font-bold text-slate-700 uppercase tracking-wider">Name</th>
            <th className="px-4 py-3 text-left text-xs font-bold text-slate-700 uppercase tracking-wider">Type</th>
            <th className="px-4 py-3 text-left text-xs font-bold text-slate-700 uppercase tracking-wider">Category</th>
            <th className="px-4 py-3 text-left text-xs font-bold text-slate-700 uppercase tracking-wider">Power</th>
            <th className="px-4 py-3 text-left text-xs font-bold text-slate-700 uppercase tracking-wider">Acc</th>
            {showPriority && (
              <th className="px-4 py-3 text-left text-xs font-bold text-slate-700 uppercase tracking-wider">Priority</th>
            )}
            <th className="px-4 py-3 text-left text-xs font-bold text-slate-700 uppercase tracking-wider">Effects</th>
            {!compact && (
              <th className="px-4 py-3 text-left text-xs font-bold text-slate-700 uppercase tracking-wider">Description</th>
            )}
          </tr>
        </thead>
        <tbody className="divide-y divide-slate-200">
          {moves.length === 0 ? (
            <tr>
              <td colSpan={compact ? 7 : 8} className="px-4 py-8 text-center text-slate-500">
                No moves found matching your filters.
              </td>
            </tr>
          ) : (
            transitions((style, move, _, idx) => {
              const isExpanded = expandedRow === idx;
              const categoryColor = CATEGORY_COLORS[move.Category] || 'bg-gray-100 text-gray-700 border-gray-300';
              
                return (
                  <React.Fragment key={move.Id || move.Name || idx}>
                    <AnimatedTr
                      style={style}
                      className={`hover:bg-slate-50 transition-colors cursor-pointer ${isExpanded ? 'bg-blue-50' : ''}`}
                      onClick={() => setExpandedRow(isExpanded ? null : idx)}
                    >
                    <td className="px-4 py-3 font-semibold text-slate-900">{move.Name}</td>
                    <td className="px-4 py-3">
                      <TypeBadge type={move.Type} />
                    </td>
                    <td className="px-4 py-3">
                      <span className={`px-2 py-1 rounded text-xs font-bold border ${categoryColor}`}>
                        {move.Category}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-sm text-slate-700 font-medium">
                      {move.BasePower || move.Category === 'Status' ? (move.BasePower || '-') : '-'}
                    </td>
                    <td className="px-4 py-3 text-sm text-slate-700 font-medium">
                      {move.Accuracy || '-'}
                    </td>
                    {showPriority && (
                      <td className="px-4 py-3 text-sm text-slate-700">
                        {move.Priority !== 0 ? (
                          <span className={`font-medium ${move.Priority > 0 ? 'text-green-600' : 'text-red-600'}`}>
                            {move.Priority > 0 ? '+' : ''}{move.Priority}
                          </span>
                        ) : (
                          <span className="text-slate-400">0</span>
                        )}
                      </td>
                    )}
                    <td className="px-4 py-3">
                      <MoveEffects move={move} />
                    </td>
                    {!compact && (
                      <td className="px-4 py-3 text-sm text-slate-600 max-w-md">
                        <span className={isExpanded ? '' : 'truncate block'} title={move.Description}>
                          {move.Description}
                        </span>
                      </td>
                    )}
                  </AnimatedTr>
                  {isExpanded && !compact && (
                    <AnimatedTr 
                      className="bg-blue-50 border-b border-blue-100"
                      style={style}
                    >
                      <td colSpan={compact ? 7 : 8} className="px-4 py-3">
                        <div className="space-y-3">
                          <div className="text-sm text-slate-700">
                            <span className="font-semibold">Description:</span> {move.Description}
                          </div>
                          <MoveEffects move={move} />
                          {moveLearnsetMap && moveLearnsetMap.has(move.Name) && (
                            <div className="text-sm text-slate-700 pt-2 border-t border-blue-200">
                              <span className="font-semibold">Learned by {moveLearnsetMap.get(move.Name)!.length} creature(s):</span>
                              <div className="flex flex-wrap gap-2 mt-2">
                                {moveLearnsetMap.get(move.Name)!.slice(0, 10).map(creature => (
                                  <Link
                                    key={creature.Id}
                                    href={`/creatures/${encodeURIComponent(creature.Name)}`}
                                    className="px-2 py-1 bg-white rounded text-xs font-medium text-blue-600 hover:text-blue-800 hover:bg-blue-100 border border-blue-200 transition-colors"
                                    onClick={(e) => e.stopPropagation()}
                                  >
                                    {creature.Name}
                                  </Link>
                                ))}
                                {moveLearnsetMap.get(move.Name)!.length > 10 && (
                                  <span className="px-2 py-1 text-xs text-slate-500">
                                    +{moveLearnsetMap.get(move.Name)!.length - 10} more
                                  </span>
                                )}
                              </div>
                            </div>
                          )}
                        </div>
                      </td>
                    </AnimatedTr>
                  )}
                </React.Fragment>
              );
            })
          )}
        </tbody>
      </table>
    </div>
  );
}


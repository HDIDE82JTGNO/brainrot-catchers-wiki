import React from 'react';
import { Move } from '../types';
import { TypeBadge } from './TypeBadge';

interface MoveTableProps {
  moves: Move[];
}

export function MoveTable({ moves }: MoveTableProps) {
  return (
    <div className="overflow-x-auto">
      <table className="min-w-full bg-white border border-gray-200">
        <thead className="bg-gray-50">
          <tr>
            <th className="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Name</th>
            <th className="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Type</th>
            <th className="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Category</th>
            <th className="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Power</th>
            <th className="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Acc</th>
            <th className="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Effect</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-200">
          {moves.map((move) => (
            <tr key={move.Name}>
              <td className="px-4 py-2 font-medium text-gray-900">{move.Name}</td>
              <td className="px-4 py-2">
                <TypeBadge type={move.Type} />
              </td>
              <td className="px-4 py-2 text-sm text-gray-500">{move.Category}</td>
              <td className="px-4 py-2 text-sm text-gray-500">{move.BasePower || '-'}</td>
              <td className="px-4 py-2 text-sm text-gray-500">{move.Accuracy || '-'}</td>
              <td className="px-4 py-2 text-sm text-gray-500 max-w-xs truncate" title={move.Description}>
                {move.Description}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}


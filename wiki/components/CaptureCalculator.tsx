"use client";

import { useState, useMemo } from 'react';
import { 
  calculateCaptureChance, 
  CUBE_BONUSES, 
  STATUS_BONUSES, 
  CubeType, 
  StatusType 
} from '../lib/captureCalculator';

interface CaptureCalculatorProps {
  catchRate: number;
  className?: string;
}

export function CaptureCalculator({ catchRate, className = '' }: CaptureCalculatorProps) {
  const [hpPercent, setHpPercent] = useState<number>(100);
  const [status, setStatus] = useState<StatusType>('None');
  const [cube, setCube] = useState<CubeType>('Capture Cube');
  const [isRapidFirstTurn, setIsRapidFirstTurn] = useState<boolean>(true);

  const result = useMemo(() => {
    // We use 100 as base MaxHP to simulate percentage
    const maxHP = 100;
    const currentHP = Math.max(1, Math.round((hpPercent / 100) * maxHP));
    
    // Handle specific cube logic
    let cubeBonus = CUBE_BONUSES[cube];
    if (cube === 'Rapid Cube' && !isRapidFirstTurn) {
        cubeBonus = 1.0;
    }

    return calculateCaptureChance(catchRate, maxHP, currentHP, cubeBonus, STATUS_BONUSES[status]);
  }, [catchRate, hpPercent, status, cube, isRapidFirstTurn]);

  // Color helper for probability
  const getChanceColor = (chance: number) => {
    if (chance >= 1) return 'text-green-600';
    if (chance >= 0.7) return 'text-green-500';
    if (chance >= 0.3) return 'text-yellow-500';
    if (chance >= 0.1) return 'text-orange-500';
    return 'text-red-500';
  };

  return (
    <div className={`bg-white rounded-xl border border-slate-200 p-6 shadow-sm ${className}`}>
      <h3 className="text-lg font-bold text-slate-800 mb-4 flex items-center gap-2">
        <span className="text-xl">🧮</span> Capture Calculator
      </h3>

      <div className="space-y-6">
        {/* HP Slider */}
        <div>
          <div className="flex justify-between mb-2">
            <label className="text-sm font-medium text-slate-700">HP Remaining</label>
            <span className="text-sm font-bold text-slate-900">{hpPercent}%</span>
          </div>
          <input
            type="range"
            min="1"
            max="100"
            value={hpPercent}
            onChange={(e) => setHpPercent(Number(e.target.value))}
            className="w-full h-2 bg-slate-200 rounded-lg appearance-none cursor-pointer accent-blue-600"
          />
          <div className="flex justify-between text-xs text-slate-400 mt-1">
            <span>1% (Red)</span>
            <span>100% (Full)</span>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {/* Cube Selector */}
          <div>
            <label className="block text-sm font-medium text-slate-700 mb-2">Capture Cube</label>
            <select
              value={cube}
              onChange={(e) => setCube(e.target.value as CubeType)}
              className="w-full p-2 border border-slate-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
            >
              {(Object.keys(CUBE_BONUSES) as CubeType[]).map((c) => (
                <option key={c} value={c}>
                  {c} (x{CUBE_BONUSES[c]})
                </option>
              ))}
            </select>
            {cube === 'Rapid Cube' && (
              <div className="mt-2 flex items-center gap-2">
                 <input 
                    type="checkbox" 
                    id="rapidFirstTurn"
                    checked={isRapidFirstTurn}
                    onChange={(e) => setIsRapidFirstTurn(e.target.checked)}
                    className="rounded border-slate-300 text-blue-600 focus:ring-blue-500"
                 />
                 <label htmlFor="rapidFirstTurn" className="text-xs text-slate-600">First Turn?</label>
              </div>
            )}
          </div>

          {/* Status Selector */}
          <div>
            <label className="block text-sm font-medium text-slate-700 mb-2">Status Condition</label>
            <select
              value={status}
              onChange={(e) => setStatus(e.target.value as StatusType)}
              className="w-full p-2 border border-slate-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
            >
              {(Object.keys(STATUS_BONUSES) as StatusType[]).map((s) => (
                <option key={s} value={s}>
                  {s} (x{STATUS_BONUSES[s]})
                </option>
              ))}
            </select>
          </div>
        </div>

        {/* Results */}
        <div className="bg-slate-50 rounded-lg p-4 border border-slate-200">
          <div className="flex flex-col items-center justify-center text-center">
            <div className="text-sm text-slate-500 font-medium uppercase tracking-wider mb-1">Capture Chance</div>
            <div className={`text-4xl font-black ${getChanceColor(result.finalChance)} transition-colors duration-300`}>
              {(result.finalChance * 100).toFixed(1)}%
            </div>
            {result.isGuaranteed && (
              <span className="inline-block mt-2 px-2 py-0.5 bg-green-100 text-green-700 text-xs font-bold rounded-full">
                Guaranteed Catch
              </span>
            )}
          </div>

          <div className="mt-4 pt-4 border-t border-slate-200 grid grid-cols-2 gap-4 text-xs text-slate-500">
            <div>
                <span className="block font-medium text-slate-700">Base Rate</span>
                {catchRate}
            </div>
            <div>
                <span className="block font-medium text-slate-700">Modified 'a'</span>
                {result.a}
            </div>
            <div>
                <span className="block font-medium text-slate-700">Shake Probability</span>
                {(result.scanChance * 100).toFixed(1)}%
            </div>
             <div>
                <span className="block font-medium text-slate-700">Shake Checks</span>
                3
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}


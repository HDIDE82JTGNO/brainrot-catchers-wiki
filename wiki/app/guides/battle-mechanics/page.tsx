"use client";

import React from 'react';
import { useSpring, animated } from '@react-spring/web';
import { getSpringConfig } from '@/lib/springConfigs';
import Link from 'next/link';

const AnimatedDiv = animated.div as any;

export default function BattleMechanicsPage() {
  const fadeIn = useSpring({
    to: { opacity: 1, transform: 'translateY(0px)' },
    config: getSpringConfig('gentle'),
  });

  return (
    <div className="space-y-6">
      <div className="text-center">
        <h1 className="text-4xl md:text-5xl font-extrabold text-white mb-3" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)', WebkitTextFillColor: 'white', color: 'white', background: 'none', WebkitBackgroundClip: 'unset', backgroundClip: 'unset' }}>
          Battle Mechanics Guide
        </h1>
        <p className="text-lg text-white max-w-2xl mx-auto" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)' }}>
          Learn how battles work, including turn order, stat stages, status effects, and more.
        </p>
      </div>

      <AnimatedDiv style={fadeIn} className="space-y-6">
        <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6 space-y-6">
          <section>
            <h2 className="text-2xl font-bold text-slate-900 mb-4">Turn Order & Priority</h2>
            <p className="text-slate-600 mb-4">
              Turn order is determined by Speed stat, with higher Speed going first. Moves with Priority values 
              can change turn order - positive Priority moves go before normal moves, negative Priority moves go after.
            </p>
            <ul className="list-disc list-inside space-y-2 text-slate-600 ml-4">
              <li>Priority +1 moves always go before Priority 0 moves</li>
              <li>Speed determines order within the same Priority bracket</li>
              <li>Some abilities can grant Priority bonuses to specific move types</li>
            </ul>
          </section>

          <section>
            <h2 className="text-2xl font-bold text-slate-900 mb-4">Stat Stages</h2>
            <p className="text-slate-600 mb-4">
              Stat stages modify stats during battle. Stages range from -6 to +6, with each stage providing a multiplier.
            </p>
            <div className="bg-slate-50 rounded-lg p-4">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-slate-200">
                    <th className="text-left py-2">Stage</th>
                    <th className="text-right py-2">Multiplier</th>
                  </tr>
                </thead>
                <tbody>
                  {[-6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6].map(stage => {
                    const mult = stage === 0 ? '1.0×' : stage > 0 
                      ? `${(2 + stage) / 2}×` 
                      : `${2 / (2 - stage)}×`;
                    return (
                      <tr key={stage} className={stage === 0 ? 'bg-blue-50 font-bold' : ''}>
                        <td className="py-1">{stage > 0 ? '+' : ''}{stage}</td>
                        <td className="text-right py-1">{mult}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </section>

          <section>
            <h2 className="text-2xl font-bold text-slate-900 mb-4">Status Effects</h2>
            <p className="text-slate-600 mb-4">
              Status effects can be inflicted by moves or abilities. See the <Link href="/status-effects" className="text-blue-600 hover:underline">Status Effects</Link> page for details.
            </p>
            <ul className="list-disc list-inside space-y-2 text-slate-600 ml-4">
              <li><strong>Burn (BRN):</strong> Reduces Attack and deals damage each turn</li>
              <li><strong>Paralysis (PAR):</strong> Reduces Speed and may prevent movement</li>
              <li><strong>Poison (PSN):</strong> Deals damage each turn</li>
              <li><strong>Badly Poisoned (TOX):</strong> Deals increasing damage each turn</li>
              <li><strong>Sleep (SLP):</strong> Prevents action for 1-3 turns</li>
              <li><strong>Freeze (FRZ):</strong> Prevents action until thawed</li>
            </ul>
          </section>

          <section>
            <h2 className="text-2xl font-bold text-slate-900 mb-4">Weather Effects</h2>
            <p className="text-slate-600 mb-4">
              Weather conditions affect spawn rates and battle mechanics. See the <Link href="/weather" className="text-blue-600 hover:underline">Weather</Link> page for details.
            </p>
            <ul className="list-disc list-inside space-y-2 text-slate-600 ml-4">
              <li>Weather changes once per day at 00:00 UTC</li>
              <li>Weather can modify type effectiveness and spawn rates</li>
              <li>Some abilities interact with specific weather conditions</li>
            </ul>
          </section>

          <section>
            <h2 className="text-2xl font-bold text-slate-900 mb-4">Abilities</h2>
            <p className="text-slate-600 mb-4">
              Abilities provide passive effects in battle. See the <Link href="/abilities" className="text-blue-600 hover:underline">Abilities</Link> page for a complete list.
            </p>
            <ul className="list-disc list-inside space-y-2 text-slate-600 ml-4">
              <li>Abilities can modify damage, stats, status immunity, and more</li>
              <li>Each creature has possible abilities with different probabilities</li>
              <li>Abilities activate automatically when conditions are met</li>
            </ul>
          </section>

          <section>
            <h2 className="text-2xl font-bold text-slate-900 mb-4">Type Effectiveness</h2>
            <p className="text-slate-600 mb-4">
              Type matchups determine damage multipliers. See the <Link href="/tools" className="text-blue-600 hover:underline">Type Chart</Link> tool for details.
            </p>
            <ul className="list-disc list-inside space-y-2 text-slate-600 ml-4">
              <li>Super effective: 2× damage</li>
              <li>Not very effective: 0.5× damage</li>
              <li>No effect: 0× damage (immune)</li>
              <li>Dual-type creatures combine both type matchups</li>
            </ul>
          </section>
        </div>
      </AnimatedDiv>
    </div>
  );
}


"use client";

import React, { useState, useRef, useEffect } from 'react';
import { copyCreatureData, copyMoveData, copyTeamData } from '@/lib/shareUtils';
import { Creature, Move } from '@/types';
import { TeamMember } from '@/lib/teamTypes';
import { useSpring, animated } from '@react-spring/web';
import { getSpringConfig } from '@/lib/springConfigs';
import { IconCopy, IconCheck, IconChevronDown } from '@tabler/icons-react';

const AnimatedDiv = animated.div as any;

interface CopyCreatureButtonProps {
  creature: Creature;
  className?: string;
}

interface CopyMoveButtonProps {
  move: Move;
  className?: string;
}

interface CopyTeamButtonProps {
  team: TeamMember[];
  className?: string;
}

export function CopyCreatureButton({ creature, className = '' }: CopyCreatureButtonProps) {
  const [copied, setCopied] = useState(false);
  const [showFormatMenu, setShowFormatMenu] = useState(false);
  const [format, setFormat] = useState<'json' | 'text'>('text');
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
        setShowFormatMenu(false);
      }
    };

    if (showFormatMenu) {
      document.addEventListener('mousedown', handleClickOutside);
      return () => document.removeEventListener('mousedown', handleClickOutside);
    }
  }, [showFormatMenu]);

  const handleCopy = async (selectedFormat: 'json' | 'text') => {
    const success = await copyCreatureData(creature, selectedFormat);
    if (success) {
      setCopied(true);
      setShowFormatMenu(false);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  const spring = useSpring({
    scale: copied ? 1.1 : 1,
    config: getSpringConfig('snappy'),
  });

  return (
    <div className="relative" ref={menuRef}>
      <AnimatedDiv style={spring}>
        <button
          onClick={() => setShowFormatMenu(!showFormatMenu)}
          className={`px-3 py-2 rounded-lg font-medium transition-all flex items-center gap-2 ${
            copied
              ? 'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300 border-2 border-green-300 dark:border-green-700'
              : 'bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300 border-2 border-slate-300 dark:border-slate-600 hover:border-blue-300 dark:hover:border-blue-500 hover:text-blue-600 dark:hover:text-blue-400'
          } ${className}`}
          title="Copy creature data"
        >
          {copied ? (
            <>
              <IconCheck className="w-4 h-4" />
              Copied!
            </>
          ) : (
            <>
              <IconCopy className="w-4 h-4" />
              Copy Data
              <IconChevronDown className="w-3 h-3" />
            </>
          )}
        </button>
      </AnimatedDiv>

      {showFormatMenu && !copied && (
        <div className="absolute top-full mt-2 right-0 bg-white dark:bg-slate-800 border-2 border-slate-200 dark:border-slate-700 rounded-lg shadow-xl overflow-hidden z-50 min-w-[120px]">
          <button
            onClick={() => handleCopy('text')}
            className="w-full px-4 py-2 text-left text-sm text-slate-700 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors"
          >
            Copy as Text
          </button>
          <button
            onClick={() => handleCopy('json')}
            className="w-full px-4 py-2 text-left text-sm text-slate-700 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors border-t border-slate-200 dark:border-slate-700"
          >
            Copy as JSON
          </button>
        </div>
      )}
    </div>
  );
}

export function CopyMoveButton({ move, className = '' }: CopyMoveButtonProps) {
  const [copied, setCopied] = useState(false);
  const [showFormatMenu, setShowFormatMenu] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
        setShowFormatMenu(false);
      }
    };

    if (showFormatMenu) {
      document.addEventListener('mousedown', handleClickOutside);
      return () => document.removeEventListener('mousedown', handleClickOutside);
    }
  }, [showFormatMenu]);

  const handleCopy = async (format: 'json' | 'text') => {
    const success = await copyMoveData(move, format);
    if (success) {
      setCopied(true);
      setShowFormatMenu(false);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  const spring = useSpring({
    scale: copied ? 1.1 : 1,
    config: getSpringConfig('snappy'),
  });

  return (
    <div className="relative" ref={menuRef}>
      <AnimatedDiv style={spring}>
        <button
          onClick={() => setShowFormatMenu(!showFormatMenu)}
          className={`px-3 py-2 rounded-lg font-medium transition-all flex items-center gap-2 ${
            copied
              ? 'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300 border-2 border-green-300 dark:border-green-700'
              : 'bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300 border-2 border-slate-300 dark:border-slate-600 hover:border-blue-300 dark:hover:border-blue-500 hover:text-blue-600 dark:hover:text-blue-400'
          } ${className}`}
          title="Copy move data"
        >
          {copied ? (
            <>
              <IconCheck className="w-4 h-4" />
              Copied!
            </>
          ) : (
            <>
              <IconCopy className="w-4 h-4" />
              Copy Data
              <IconChevronDown className="w-3 h-3" />
            </>
          )}
        </button>
      </AnimatedDiv>

      {showFormatMenu && !copied && (
        <div className="absolute top-full mt-2 right-0 bg-white dark:bg-slate-800 border-2 border-slate-200 dark:border-slate-700 rounded-lg shadow-xl overflow-hidden z-50 min-w-[120px]">
          <button
            onClick={() => handleCopy('text')}
            className="w-full px-4 py-2 text-left text-sm text-slate-700 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors"
          >
            Copy as Text
          </button>
          <button
            onClick={() => handleCopy('json')}
            className="w-full px-4 py-2 text-left text-sm text-slate-700 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors border-t border-slate-200 dark:border-slate-700"
          >
            Copy as JSON
          </button>
        </div>
      )}
    </div>
  );
}

export function CopyTeamButton({ team, className = '' }: CopyTeamButtonProps) {
  const [copied, setCopied] = useState(false);
  const [showFormatMenu, setShowFormatMenu] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
        setShowFormatMenu(false);
      }
    };

    if (showFormatMenu) {
      document.addEventListener('mousedown', handleClickOutside);
      return () => document.removeEventListener('mousedown', handleClickOutside);
    }
  }, [showFormatMenu]);

  const handleCopy = async (format: 'json' | 'text') => {
    const success = await copyTeamData(team, format);
    if (success) {
      setCopied(true);
      setShowFormatMenu(false);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  const spring = useSpring({
    scale: copied ? 1.1 : 1,
    config: getSpringConfig('snappy'),
  });

  return (
    <div className="relative" ref={menuRef}>
      <AnimatedDiv style={spring}>
        <button
          onClick={() => setShowFormatMenu(!showFormatMenu)}
          className={`px-3 py-2 rounded-lg font-medium transition-all flex items-center gap-2 ${
            copied
              ? 'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300 border-2 border-green-300 dark:border-green-700'
              : 'bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300 border-2 border-slate-300 dark:border-slate-600 hover:border-blue-300 dark:hover:border-blue-500 hover:text-blue-600 dark:hover:text-blue-400'
          } ${className}`}
          title="Copy team data"
        >
          {copied ? (
            <>
              <IconCheck className="w-4 h-4" />
              Copied!
            </>
          ) : (
            <>
              <IconCopy className="w-4 h-4" />
              Copy Team
              <IconChevronDown className="w-3 h-3" />
            </>
          )}
        </button>
      </AnimatedDiv>

      {showFormatMenu && !copied && (
        <div className="absolute top-full mt-2 right-0 bg-white dark:bg-slate-800 border-2 border-slate-200 dark:border-slate-700 rounded-lg shadow-xl overflow-hidden z-50 min-w-[120px]">
          <button
            onClick={() => handleCopy('text')}
            className="w-full px-4 py-2 text-left text-sm text-slate-700 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors"
          >
            Copy as Text
          </button>
          <button
            onClick={() => handleCopy('json')}
            className="w-full px-4 py-2 text-left text-sm text-slate-700 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors border-t border-slate-200 dark:border-slate-700"
          >
            Copy as JSON
          </button>
        </div>
      )}
    </div>
  );
}


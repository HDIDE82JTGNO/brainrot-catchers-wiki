"use client";

import React, { useState, useRef, useEffect } from 'react';
import { useTheme } from '@/lib/theme';
import { IconSun, IconMoon, IconDeviceDesktop } from '@tabler/icons-react';
import { useSpring, animated } from '@react-spring/web';
import { getSpringConfig } from '@/lib/springConfigs';

const AnimatedDiv = animated.div as any;

export function ThemeToggle() {
  const { theme, setTheme } = useTheme();
  const [isOpen, setIsOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  const spring = useSpring({
    opacity: isOpen ? 1 : 0,
    scale: isOpen ? 1 : 0.95,
    config: getSpringConfig('gentle'),
  });

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };

    if (isOpen) {
      document.addEventListener('mousedown', handleClickOutside);
      return () => document.removeEventListener('mousedown', handleClickOutside);
    }
  }, [isOpen]);

  const options: Array<{ value: 'light' | 'dark' | 'system'; label: string; icon: React.ReactNode }> = [
    { value: 'light', label: 'Light', icon: <IconSun className="w-4 h-4" /> },
    { value: 'dark', label: 'Dark', icon: <IconMoon className="w-4 h-4" /> },
    { value: 'system', label: 'System', icon: <IconDeviceDesktop className="w-4 h-4" /> },
  ];

  const currentOption = options.find(opt => opt.value === theme) || options[2];

  return (
    <div className="relative" ref={dropdownRef}>
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="p-2 rounded-lg bg-white dark:bg-slate-800 border-2 border-slate-200 dark:border-slate-700 hover:border-blue-400 dark:hover:border-blue-500 transition-all flex items-center gap-2 text-slate-700 dark:text-slate-200"
        aria-label="Toggle theme"
      >
        {currentOption.icon}
        <span className="hidden md:inline text-sm font-medium">{currentOption.label}</span>
      </button>

      {isOpen && (
        <AnimatedDiv
          style={spring}
          className="absolute top-full mt-2 right-0 bg-white dark:bg-slate-800 border-2 border-slate-200 dark:border-slate-700 rounded-lg shadow-xl overflow-hidden z-50 min-w-[140px]"
        >
          {options.map((option) => (
            <button
              key={option.value}
              onClick={() => {
                setTheme(option.value);
                setIsOpen(false);
              }}
              className={`w-full px-4 py-2 flex items-center gap-2 text-left transition-colors ${
                theme === option.value
                  ? 'bg-blue-50 dark:bg-blue-900/30 text-blue-600 dark:text-blue-400 font-medium'
                  : 'text-slate-700 dark:text-slate-200 hover:bg-slate-50 dark:hover:bg-slate-700'
              }`}
            >
              {option.icon}
              <span className="text-sm">{option.label}</span>
            </button>
          ))}
        </AnimatedDiv>
      )}
    </div>
  );
}


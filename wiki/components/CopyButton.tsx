"use client";

import React, { useState } from 'react';
import { copyToClipboard } from '@/lib/shareUtils';
import { useSpring, animated } from '@react-spring/web';
import { getSpringConfig } from '@/lib/springConfigs';
import { IconCopy, IconCheck } from '@tabler/icons-react';

const AnimatedDiv = animated.div as any;

interface CopyButtonProps {
  text: string;
  label?: string;
  className?: string;
  showLabel?: boolean;
}

export function CopyButton({ text, label = 'Copy', className = '', showLabel = true }: CopyButtonProps) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    const success = await copyToClipboard(text);
    if (success) {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  const spring = useSpring({
    scale: copied ? 1.1 : 1,
    config: getSpringConfig('snappy'),
  });

  return (
    <AnimatedDiv style={spring}>
      <button
        onClick={handleCopy}
        className={`px-3 py-2 rounded-lg font-medium transition-all flex items-center gap-2 ${
          copied
            ? 'bg-green-100 text-green-700 border-2 border-green-300'
            : 'bg-slate-100 text-slate-600 border-2 border-slate-300 hover:border-blue-300 hover:text-blue-600'
        } ${className}`}
        title={copied ? 'Copied!' : label}
      >
        {copied ? (
          <>
            <IconCheck className="w-4 h-4" />
            {showLabel && 'Copied!'}
          </>
        ) : (
          <>
            <IconCopy className="w-4 h-4" />
            {showLabel && label}
          </>
        )}
      </button>
    </AnimatedDiv>
  );
}


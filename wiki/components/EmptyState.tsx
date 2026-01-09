"use client";

import { animated, useSpring } from '@react-spring/web';
import { getSpringConfig } from '@/lib/springConfigs';

// Type assertion for react-spring animated components with React 19
const AnimatedDiv = animated.div as any;

interface EmptyStateProps {
  message: string;
  icon?: string;
}

export function EmptyState({ message, icon = '🔍' }: EmptyStateProps) {
  const spring = useSpring({
    from: { opacity: 0, transform: 'translateY(20px)' },
    to: { opacity: 1, transform: 'translateY(0px)' },
    config: getSpringConfig('gentle'),
  });

  return (
    <AnimatedDiv 
      className="text-center py-12 text-slate-500"
      style={spring}
    >
      <div className="text-4xl mb-4">{icon}</div>
      <p className="text-lg">{message}      </p>
    </AnimatedDiv>
  );
}


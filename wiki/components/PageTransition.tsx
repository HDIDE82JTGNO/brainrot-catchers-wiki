"use client";

import React, { useEffect, useState, useRef } from 'react';
import { usePathname } from 'next/navigation';
import { useSpring, animated } from '@react-spring/web';
import { getSpringConfig } from '@/lib/springConfigs';

// Type assertion for react-spring animated components with React 19
const AnimatedDiv = animated.div as any;

interface AnimatedContentProps {
  children: React.ReactNode;
  opacity: number;
  fadeInFromBelow: boolean;
}

function AnimatedContent({ children, opacity, fadeInFromBelow }: AnimatedContentProps) {
  const [animationKey, setAnimationKey] = React.useState(0);
  
  // Force animation reset when starting fade-in
  React.useEffect(() => {
    if (fadeInFromBelow && opacity === 1) {
      setAnimationKey(prev => prev + 1);
    }
  }, [fadeInFromBelow]);

  const spring = useSpring({
    from: fadeInFromBelow ? { opacity: 0, transform: 'translateY(10px)' } : { opacity: 0, transform: 'translateY(0px)' },
    to: { 
      opacity, 
      transform: opacity === 1 ? 'translateY(0px)' : 'translateY(-10px)' 
    },
    config: getSpringConfig('snappy'),
  });

  return (
    <AnimatedDiv
      key={animationKey} // Remount to restart animation
      style={{
        ...spring,
        width: '100%',
      }}
    >
      {children}
    </AnimatedDiv>
  );
}

interface PageTransitionProps {
  children: React.ReactNode;
}

export function PageTransition({ children }: PageTransitionProps) {
  const pathname = usePathname();
  const [displayChildren, setDisplayChildren] = useState(children);
  const [opacity, setOpacity] = useState(1);
  const [fadeInFromBelow, setFadeInFromBelow] = useState(false);
  const prevPathnameRef = useRef(pathname);
  const timeoutRef = useRef<NodeJS.Timeout | null>(null);
  const newChildrenRef = useRef<React.ReactNode>(null);

  useEffect(() => {
    // Check if pathname actually changed
    if (prevPathnameRef.current !== pathname) {
      // Store new children but don't display yet
      newChildrenRef.current = children;
      
      // Fade out first
      setOpacity(0);
      setFadeInFromBelow(false);
      
      // Clear any existing timeout
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
      
      // After fade out, update children and fade in
      timeoutRef.current = setTimeout(() => {
        setDisplayChildren(newChildrenRef.current);
        setFadeInFromBelow(true);
        setOpacity(1);
        prevPathnameRef.current = pathname;
        newChildrenRef.current = null;
      }, 150);
    } else {
      // Same pathname, just update children directly
      setDisplayChildren(children);
      setOpacity(1);
      setFadeInFromBelow(false);
    }

    return () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
    };
  }, [pathname, children]);

  return (
    <AnimatedContent 
      opacity={opacity} 
      fadeInFromBelow={fadeInFromBelow}
    >
      {displayChildren}
    </AnimatedContent>
  );
}


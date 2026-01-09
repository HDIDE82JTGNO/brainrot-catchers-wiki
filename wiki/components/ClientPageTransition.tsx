"use client";

import { PageTransition } from './PageTransition';

export function ClientPageTransition({ children }: { children: React.ReactNode }) {
  return <PageTransition>{children}</PageTransition>;
}


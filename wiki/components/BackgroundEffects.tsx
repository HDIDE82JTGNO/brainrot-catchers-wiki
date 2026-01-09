"use client";

import dynamic from "next/dynamic";

// Dynamically import heavy components with no SSR
const DotGrid = dynamic(() => import("@/components/DotGrid").then(mod => ({ default: mod.DotGrid })), {
  ssr: false,
  loading: () => null
});

const DomeGalleryWrapper = dynamic(() => import("@/components/DomeGalleryWrapper").then(mod => ({ default: mod.DomeGalleryWrapper })), {
  ssr: false,
  loading: () => null
});

export function BackgroundEffects() {
  return (
    <>
      <div className="fixed inset-0 pointer-events-none" style={{ zIndex: 0 }}>
        <DotGrid
          dotSize={10}
          baseColor="#EDEDED"
          activeColor="#DBDBDB"
          className="w-full h-full"
        />
      </div>
      <DomeGalleryWrapper />
      <div 
        className="fixed inset-0 pointer-events-none" 
        style={{ 
          zIndex: 15,
          backgroundColor: 'rgba(0, 0, 0, 0.2)'
        }}
      />
    </>
  );
}


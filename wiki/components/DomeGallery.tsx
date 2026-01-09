"use client";

import { useEffect, useMemo, useRef, useCallback, useState } from 'react';
import { useGesture } from '@use-gesture/react';

type ImageItem = string | { src: string; alt?: string };

type DomeGalleryProps = {
  images?: ImageItem[];
  fit?: number;
  fitBasis?: 'auto' | 'min' | 'max' | 'width' | 'height';
  minRadius?: number;
  maxRadius?: number;
  padFactor?: number;
  overlayBlurColor?: string;
  maxVerticalRotationDeg?: number;
  dragSensitivity?: number;
  enlargeTransitionMs?: number;
  segments?: number;
  dragDampening?: number;
  openedImageWidth?: string;
  openedImageHeight?: string;
  imageBorderRadius?: string;
  openedImageBorderRadius?: string;
  grayscale?: boolean;
  className?: string;
  isFalling?: boolean;
  resetKey?: number;
  fallDuration?: number; // Duration in seconds for fall animation
  isReverseReset?: boolean; // Use reverse reset animation (same as coming in, but reversed)
};

type ItemDef = {
  src: string;
  alt: string;
  x: number;
  y: number;
  sizeX: number;
  sizeY: number;
};

const DEFAULTS = {
  maxVerticalRotationDeg: 5,
  dragSensitivity: 20,
  enlargeTransitionMs: 300,
  segments: 35
};

const clamp = (v: number, min: number, max: number) => Math.min(Math.max(v, min), max);
const normalizeAngle = (d: number) => ((d % 360) + 360) % 360;
const wrapAngleSigned = (deg: number) => {
  const a = (((deg + 180) % 360) + 360) % 360;
  return a - 180;
};
const getDataNumber = (el: HTMLElement, name: string, fallback: number) => {
  const attr = el.dataset[name] ?? el.getAttribute(`data-${name}`);
  const n = attr == null ? NaN : parseFloat(attr);
  return Number.isFinite(n) ? n : fallback;
};

function buildItems(pool: ImageItem[], seg: number): ItemDef[] {
  const xCols = Array.from({ length: seg }, (_, i) => -37 + i * 2);
  const evenYs = [-4, -2, 0, 2, 4];
  const oddYs = [-3, -1, 1, 3, 5];

  const coords = xCols.flatMap((x, c) => {
    const ys = c % 2 === 0 ? evenYs : oddYs;
    return ys.map(y => ({ x, y, sizeX: 1.5, sizeY: 1.5 })); // Smaller sprite sizes
  });

  const totalSlots = coords.length;
  if (pool.length === 0) {
    return coords.map(c => ({ ...c, src: '', alt: '' }));
  }
  if (pool.length > totalSlots) {
    console.warn(
      `[DomeGallery] Provided image count (${pool.length}) exceeds available tiles (${totalSlots}). Some images will not be shown.`
    );
  }

  const normalizedImages = pool.map(image => {
    if (typeof image === 'string') {
      return { src: image, alt: '' };
    }
    return { src: image.src || '', alt: image.alt || '' };
  });

  const usedImages = Array.from({ length: totalSlots }, (_, i) => normalizedImages[i % normalizedImages.length]);

  for (let i = 1; i < usedImages.length; i++) {
    if (usedImages[i].src === usedImages[i - 1].src) {
      for (let j = i + 1; j < usedImages.length; j++) {
        if (usedImages[j].src !== usedImages[i].src) {
          const tmp = usedImages[i];
          usedImages[i] = usedImages[j];
          usedImages[j] = tmp;
          break;
        }
      }
    }
  }

  return coords.map((c, i) => ({
    ...c,
    src: usedImages[i].src,
    alt: usedImages[i].alt
  }));
}

function computeItemBaseRotation(offsetX: number, offsetY: number, sizeX: number, sizeY: number, segments: number) {
  const unit = 360 / segments / 2;
  const rotateY = unit * (offsetX + (sizeX - 1) / 2);
  const rotateX = unit * (offsetY - (sizeY - 1) / 2);
  return { rotateX, rotateY };
}

// Lazy-loaded image component with IntersectionObserver
function DomeGalleryImage({
  src,
  alt,
  imageBorderRadius,
  grayscale,
  onOpen
}: {
  src: string;
  alt: string;
  imageBorderRadius: string;
  grayscale: boolean;
  onOpen: (e: React.MouseEvent<HTMLElement>) => void;
}) {
  const [isLoaded, setIsLoaded] = useState(false);
  const [shouldLoad, setShouldLoad] = useState(false);
  const imgRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const element = imgRef.current;
    if (!element) return;

    // Use IntersectionObserver to lazy load images
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            setShouldLoad(true);
            observer.disconnect();
          }
        });
      },
      { rootMargin: '50px' } // Start loading 50px before visible
    );

    observer.observe(element);

    return () => {
      observer.disconnect();
    };
  }, []);

  // Check if this is an item image (starts with /items/)
  const isItemImage = src.startsWith('/items/');

  return (
    <div
      ref={imgRef}
      className="item__image absolute block overflow-hidden cursor-pointer bg-gray-200 transition-transform duration-300"
      role="button"
      tabIndex={0}
      aria-label={alt || 'Open image'}
      onClick={onOpen}
      onPointerUp={(e) => {
        if ((e.nativeEvent as PointerEvent).pointerType !== 'touch') return;
        onOpen(e as any);
      }}
      style={{
        inset: '8px',
        borderRadius: `var(--tile-radius, ${imageBorderRadius})`,
        backfaceVisibility: 'hidden',
        willChange: 'transform'
      }}
    >
      {shouldLoad ? (
        <img
          src={src}
          draggable={false}
          alt={alt}
          className="w-full h-full object-contain pointer-events-none"
          loading="lazy"
          onLoad={() => setIsLoaded(true)}
          style={{
            backfaceVisibility: 'hidden',
            filter: `var(--image-filter, ${grayscale ? 'grayscale(1)' : 'none'})`,
            opacity: isLoaded ? 1 : 0,
            transition: 'opacity 0.2s',
            imageRendering: 'pixelated',
            transform: isItemImage ? 'scale(0.6)' : 'none',
            transformOrigin: 'center center'
          }}
        />
      ) : (
        <div className="w-full h-full bg-gray-300 animate-pulse" />
      )}
    </div>
  );
}

// Available sprite names (without -NS/-S suffix)
const spriteNames = [
  "AmbalabuTonTon",
  "BallerinaCappuccina",
  "BolasaegSelluaim",
  "BonecaAmbalabu",
  "BurbaloniLulliloli",
  "Doggolino",
  "FrigoCamelo",
  "Frulilala",
  "FrulliFrulla",
  "Glacimel",
  "Kitung",
  "MagiTung",
  "PrimarinaBallerina",
  "Refricamel",
  "SirTung",
  "Tadbalabu",
  "TimCheese",
  "TimmyCheddar",
  "Twirlina",
];

export function DomeGallery({
  images,
  fit = 0.2,
  fitBasis = 'max',
  minRadius = 1300,
  maxRadius = Infinity,
  padFactor = 0.05,
  overlayBlurColor = '#060010',
  maxVerticalRotationDeg = DEFAULTS.maxVerticalRotationDeg,
  dragSensitivity = DEFAULTS.dragSensitivity,
  enlargeTransitionMs = DEFAULTS.enlargeTransitionMs,
  segments = DEFAULTS.segments,
  dragDampening = 2,
  openedImageWidth,
  openedImageHeight,
  imageBorderRadius = '30px',
  openedImageBorderRadius = '30px',
  grayscale = false,
  className = "",
  isFalling = false,
  resetKey = 0,
  fallDuration = 1.5, // Default 1.5 seconds
  isReverseReset = false
}: DomeGalleryProps) {
  // Generate random sprites if no images provided - use all sprites multiple times
  const defaultImages = useMemo(() => {
    if (images && images.length > 0) return images;
    const selected: ImageItem[] = [];
    // Use all sprites multiple times to fill the dome
    const totalNeeded = segments * 5; // segments * average items per column
    for (let i = 0; i < totalNeeded; i++) {
      const spriteIndex = i % spriteNames.length;
      const sprite = spriteNames[spriteIndex];
      const isShiny = Math.random() > 0.5;
      selected.push(`/sprites/${sprite}${isShiny ? '-S' : '-NS'}.webp`);
    }
    return selected;
  }, [images, segments]);

  const rootRef = useRef<HTMLDivElement>(null);
  const mainRef = useRef<HTMLDivElement>(null);
  const sphereRef = useRef<HTMLDivElement>(null);
  const frameRef = useRef<HTMLDivElement>(null);
  const viewerRef = useRef<HTMLDivElement>(null);
  const scrimRef = useRef<HTMLDivElement>(null);
  const focusedElRef = useRef<HTMLElement | null>(null);
  const originalTilePositionRef = useRef<{
    left: number;
    top: number;
    width: number;
    height: number;
  } | null>(null);

  const rotationRef = useRef({ x: 0, y: 0 });
  const startRotRef = useRef({ x: 0, y: 0 });
  const startPosRef = useRef<{ x: number; y: number } | null>(null);
  const draggingRef = useRef(false);
  const cancelTapRef = useRef(false);
  const cancelTapTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const movedRef = useRef(false);
  const inertiaRAF = useRef<number | null>(null);
  const autoRotateRef = useRef<number | null>(null);
  const pointerTypeRef = useRef<'mouse' | 'pen' | 'touch'>('mouse');
  const tapTargetRef = useRef<HTMLElement | null>(null);
  const openingRef = useRef(false);
  const openStartedAtRef = useRef(0);
  const lastDragEndAt = useRef(0);
  
  // Mount tracking and timeout management
  const isMountedRef = useRef(true);
  const generationRef = useRef(0);
  const timeoutRefs = useRef<Set<ReturnType<typeof setTimeout>>>(new Set());
  const clearAllTimeouts = useCallback(() => {
    timeoutRefs.current.forEach(id => clearTimeout(id));
    timeoutRefs.current.clear();
  }, []);
  const safeTimeout = useCallback((fn: () => void, delayMs: number) => {
    const gen = generationRef.current;
    const id = setTimeout(() => {
      if (!isMountedRef.current) return;
      if (generationRef.current !== gen) return;
      fn();
    }, delayMs);
    timeoutRefs.current.add(id);
    return id;
  }, []);

  // StrictMode-safe lifecycle: in dev, React may run effects+cleanups twice.
  // This must NOT leave `isMountedRef` stuck at false.
  useEffect(() => {
    isMountedRef.current = true;
    const genAtStart = generationRef.current;

    return () => {
      // Invalidate any pending async work from the previous run.
      if (generationRef.current === genAtStart) {
        generationRef.current += 1;
      }

      isMountedRef.current = false;
      clearAllTimeouts();

      if (autoRotateRef.current) {
        cancelAnimationFrame(autoRotateRef.current);
        autoRotateRef.current = null;
      }
      if (inertiaRAF.current) {
        cancelAnimationFrame(inertiaRAF.current);
        inertiaRAF.current = null;
      }

      if (cancelTapTimeoutRef.current) {
        clearTimeout(cancelTapTimeoutRef.current);
        cancelTapTimeoutRef.current = null;
      }

      document.body.classList.remove('dg-scroll-lock');
    };
  }, [clearAllTimeouts]);

  const scrollLockedRef = useRef(false);
  const lockScroll = useCallback(() => {
    if (scrollLockedRef.current) return;
    scrollLockedRef.current = true;
    document.body.classList.add('dg-scroll-lock');
  }, []);
  const unlockScroll = useCallback(() => {
    if (!scrollLockedRef.current) return;
    if (rootRef.current?.getAttribute('data-enlarging') === 'true') return;
    scrollLockedRef.current = false;
    document.body.classList.remove('dg-scroll-lock');
  }, []);

  const items = useMemo(() => buildItems(defaultImages, segments), [defaultImages, segments]);

  const applyTransform = (xDeg: number, yDeg: number) => {
    const el = sphereRef.current;
    if (el) {
      el.style.transform = `translateZ(calc(var(--radius) * -1)) rotateX(${xDeg}deg) rotateY(${yDeg}deg)`;
    }
  };

  const lockedRadiusRef = useRef<number | null>(null);

  useEffect(() => {
    const root = rootRef.current;
    if (!root) return;
    const ro = new ResizeObserver(entries => {
      const cr = entries[0].contentRect;
      const w = Math.max(1, cr.width),
        h = Math.max(1, cr.height);
      const minDim = Math.min(w, h),
        maxDim = Math.max(w, h),
        aspect = w / h;
      let basis: number;
      switch (fitBasis) {
        case 'min':
          basis = minDim;
          break;
        case 'max':
          basis = maxDim;
          break;
        case 'width':
          basis = w;
          break;
        case 'height':
          basis = h;
          break;
        default:
          basis = aspect >= 1.3 ? w : minDim;
      }
      let radius = basis * fit;
      // Remove height guard to allow full screen fill
      radius = clamp(radius, minRadius, maxRadius);
      lockedRadiusRef.current = Math.round(radius);

      const viewerPad = Math.max(8, Math.round(minDim * padFactor));
      root.style.setProperty('--radius', `${lockedRadiusRef.current}px`);
      root.style.setProperty('--viewer-pad', `${viewerPad}px`);
      root.style.setProperty('--overlay-blur-color', overlayBlurColor);
      root.style.setProperty('--tile-radius', imageBorderRadius);
      root.style.setProperty('--enlarge-radius', openedImageBorderRadius);
      root.style.setProperty('--image-filter', grayscale ? 'grayscale(1)' : 'none');
      root.style.setProperty('opacity', '0.75'); // Set overall opacity to 0.75
      applyTransform(rotationRef.current.x, rotationRef.current.y);

      const enlargedOverlay = viewerRef.current?.querySelector('.enlarge') as HTMLElement;
      if (enlargedOverlay && frameRef.current && mainRef.current) {
        const frameR = frameRef.current.getBoundingClientRect();
        const mainR = mainRef.current.getBoundingClientRect();

        const hasCustomSize = openedImageWidth && openedImageHeight;
        if (hasCustomSize) {
          const tempDiv = document.createElement('div');
          tempDiv.style.cssText = `position: absolute; width: ${openedImageWidth}; height: ${openedImageHeight}; visibility: hidden;`;
          document.body.appendChild(tempDiv);
          const tempRect = tempDiv.getBoundingClientRect();
          document.body.removeChild(tempDiv);

          const centeredLeft = frameR.left - mainR.left + (frameR.width - tempRect.width) / 2;
          const centeredTop = frameR.top - mainR.top + (frameR.height - tempRect.height) / 2;

          enlargedOverlay.style.left = `${centeredLeft}px`;
          enlargedOverlay.style.top = `${centeredTop}px`;
        } else {
          enlargedOverlay.style.left = `${frameR.left - mainR.left}px`;
          enlargedOverlay.style.top = `${frameR.top - mainR.top}px`;
          enlargedOverlay.style.width = `${frameR.width}px`;
          enlargedOverlay.style.height = `${frameR.height}px`;
        }
      }
    });
    ro.observe(root);
    return () => ro.disconnect();
  }, [
    fit,
    fitBasis,
    minRadius,
    maxRadius,
    padFactor,
    overlayBlurColor,
    grayscale,
    imageBorderRadius,
    openedImageBorderRadius,
    openedImageWidth,
    openedImageHeight
  ]);

  // Infinite auto-rotation animation with throttling and visibility check
  const isVisibleRef = useRef(true); // Start as visible, will be updated by IntersectionObserver
  const lastFrameTime = useRef(0);
  const targetFPS = 30; // Reduced from 60fps to 30fps
  const frameInterval = 1000 / targetFPS;
  const isFallingRef = useRef(isFalling);
  
  // IntersectionObserver to pause animations when off-screen
  useEffect(() => {
    const root = rootRef.current;
    if (!root) return;

    // Initialize as visible (will be updated by observer)
    isVisibleRef.current = true;

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          isVisibleRef.current = entry.isIntersecting;
        });
      },
      { threshold: 0.1 }
    );

    observer.observe(root);

    // Also check page visibility
    const handleVisibilityChange = () => {
      isVisibleRef.current = !document.hidden && root.getBoundingClientRect().top < window.innerHeight;
    };
    document.addEventListener('visibilitychange', handleVisibilityChange);

    return () => {
      observer.disconnect();
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, []);
  
  // Update isFalling ref when prop changes
  useEffect(() => {
    isFallingRef.current = isFalling;
  }, [isFalling]);

  useEffect(() => {
    if (!isMountedRef.current) return;
    
    // Stop auto-rotation completely when falling - don't set up animation loop
    if (isFallingRef.current) {
      if (autoRotateRef.current) {
        cancelAnimationFrame(autoRotateRef.current);
        autoRotateRef.current = null;
      }
      return;
    }
    
    applyTransform(rotationRef.current.x, rotationRef.current.y);
    
    const animate = (currentTime: number) => {
      // Check mount state - exit if unmounted
      if (!isMountedRef.current) {
        autoRotateRef.current = null;
        return;
      }
      
      // Stop completely if falling
      if (isFallingRef.current) {
        autoRotateRef.current = null;
        return;
      }
      
      // Pause rotation (but keep loop running) if dragging, opening, or not visible
      // Note: Don't check resetAnimationActiveRef here - let it run during resets
      // The reset animation will handle its own timing
      if (!isVisibleRef.current || draggingRef.current || openingRef.current) {
        autoRotateRef.current = requestAnimationFrame(animate);
        return;
      }

      const elapsed = currentTime - lastFrameTime.current;
      
      if (elapsed >= frameInterval) {
        rotationRef.current.y += 0.02; // Reduced from 0.04 for slower rotation
        applyTransform(rotationRef.current.x, rotationRef.current.y);
        lastFrameTime.current = currentTime;
      }
      
      autoRotateRef.current = requestAnimationFrame(animate);
    };
    
    lastFrameTime.current = performance.now();
    autoRotateRef.current = requestAnimationFrame(animate);
    
    return () => {
      if (autoRotateRef.current) {
        cancelAnimationFrame(autoRotateRef.current);
        autoRotateRef.current = null;
      }
    };
  }, [isFalling, frameInterval]);

  const prevIsFallingRef = useRef(isFalling);
  const prevIsReverseResetRef = useRef(isReverseReset);
  const needsResetRef = useRef(false);
  const resetAnimationActiveRef = useRef(false);
  const reverseResetTimeoutRefs = useRef<Set<ReturnType<typeof setTimeout>>>(new Set());

  // Initialize animation flags on mount
  useEffect(() => {
    // Ensure flags start in correct state
    resetAnimationActiveRef.current = false;
    needsResetRef.current = false;
    resetTriggeredRef.current = false;
  }, []);

  // Animation timing constants
  const REVERSE_RESET_FADE_DURATION = 250; // ms
  const REVERSE_RESET_STAGGER_DELAY = 8; // ms per item
  const RESET_ANIMATION_DURATION = 1500; // ms
  const RESET_STAGGER_DELAY = 8; // ms per item

  // Reverse reset animation effect (same as reset but reversed - for creature/item swapping)
  useEffect(() => {
    if (!isMountedRef.current) return;
    
    // Clear previous timeouts
    reverseResetTimeoutRefs.current.forEach(id => clearTimeout(id));
    reverseResetTimeoutRefs.current.clear();
    
    if (!isReverseReset || !sphereRef.current) {
      prevIsReverseResetRef.current = isReverseReset;
      resetAnimationActiveRef.current = false;
      return;
    }

    resetAnimationActiveRef.current = true;
    const gen = generationRef.current;
    const sphereItems = sphereRef.current.querySelectorAll('.sphere-item');
    const itemCount = sphereItems.length;
    
    // Calculate dynamic timeout based on actual item count
    const lastItemDelay = itemCount * REVERSE_RESET_STAGGER_DELAY;
    const totalDuration = REVERSE_RESET_FADE_DURATION + lastItemDelay;
    
    // Mark that we'll need a reset when new images come in
    needsResetRef.current = true;
    
    // IMPORTANT: do not force sphere/items visible here.
    // Forcing opacity back to 1 can cause a perceptible "snap/refresh" right before the fade-out.

    // Animate items out - just fade them out (no movement)
    sphereItems.forEach((item, index) => {
      if (!isMountedRef.current) return;
      
      const element = item as HTMLElement;
      const delay = index * REVERSE_RESET_STAGGER_DELAY;
      
      // Start from normal position (remove any falling state)
      // Set transition to none first to set initial state instantly
      element.style.transition = 'none';
      element.removeAttribute('data-falling');
      element.style.removeProperty('--fall-distance');
      element.style.removeProperty('--fall-rotation');
      element.style.removeProperty('--fall-drift');
      // Do not force opacity to 1; preserve the current visual state to avoid flicker.
      
      // Force a reflow to apply the initial state
      void element.offsetHeight;
      
      const timeoutId = safeTimeout(() => {
        if (!sphereRef.current) return;

        // Set transition BEFORE changing opacity
        element.style.transition = `opacity ${REVERSE_RESET_FADE_DURATION}ms ease-in`;

        // Use requestAnimationFrame to ensure transition is applied before opacity change
        requestAnimationFrame(() => {
          if (!isMountedRef.current) return;
          if (generationRef.current !== gen) return;
          // Just fade out - no transform changes
          element.style.opacity = '0';
        });
      }, delay);
      
      reverseResetTimeoutRefs.current.add(timeoutId);
    });

    // Hide the entire sphere after animation completes
    // Add extra buffer to ensure animation completes
    const hideTimeoutId = safeTimeout(() => {
      resetAnimationActiveRef.current = false;
      if (sphereRef.current) {
        sphereRef.current.style.opacity = '0';
        sphereRef.current.style.pointerEvents = 'none';
      }
    }, totalDuration + 100); // Add 100ms buffer
    
    reverseResetTimeoutRefs.current.add(hideTimeoutId);
    
    // Safety fallback: ensure flag resets even if something goes wrong
    const fallbackTimeoutId = safeTimeout(() => {
      if (resetAnimationActiveRef.current) {
        resetAnimationActiveRef.current = false;
      }
    }, totalDuration + 2000); // 2 second fallback
    
    reverseResetTimeoutRefs.current.add(fallbackTimeoutId);

    prevIsReverseResetRef.current = isReverseReset;
    
    return () => {
      reverseResetTimeoutRefs.current.forEach(id => clearTimeout(id));
      reverseResetTimeoutRefs.current.clear();
      // Reset flag on cleanup
      resetAnimationActiveRef.current = false;
    };
  }, [isReverseReset, safeTimeout]);

  const fallingTimeoutRefs = useRef<Set<ReturnType<typeof setTimeout>>>(new Set());

  // Falling animation effect (for route changes to falling routes)
  useEffect(() => {
    if (!isMountedRef.current) return;
    
    // Clear previous timeouts
    fallingTimeoutRefs.current.forEach(id => clearTimeout(id));
    fallingTimeoutRefs.current.clear();
    
    // Skip if reverse reset is active (but allow falling during normal reset)
    if (isReverseReset) {
      return;
    }

    if (!isFalling || !sphereRef.current) {
      prevIsFallingRef.current = isFalling;
      return;
    }

    const sphereItems = sphereRef.current.querySelectorAll('.sphere-item');
    const screenHeight = window.innerHeight;
    const durationMs = fallDuration * 1000; // Convert to milliseconds
    
    // Mark that we'll need a reset when falling stops
    needsResetRef.current = true;
    
    sphereItems.forEach((item, index) => {
      if (!isMountedRef.current) return;
      
      const element = item as HTMLElement;
      const delay = 0; // No delay - animation starts immediately
      const fallDistance = screenHeight + 1000; // Fall off screen
      const rotation = (Math.random() - 0.5) * 720; // Random rotation between -360 and 360
      const horizontalDrift = (Math.random() - 0.5) * 200; // Random horizontal movement
      
      const gen = generationRef.current;
      const timeoutId = safeTimeout(() => {
        if (!sphereRef.current) return;
        
        // Ensure transition is set before changing attributes
        element.style.transition = `transform ${fallDuration}s cubic-bezier(0.55, 0.055, 0.675, 0.19), opacity ${fallDuration}s ease-out`;
        
        // Use requestAnimationFrame to ensure transition is applied
        requestAnimationFrame(() => {
          if (!isMountedRef.current || !sphereRef.current) return;
          if (generationRef.current !== gen) return;
          
          // Add falling class and set CSS custom properties for animation
          element.setAttribute('data-falling', 'true');
          element.style.setProperty('--fall-distance', `${fallDistance}px`);
          element.style.setProperty('--fall-rotation', `${rotation}deg`);
          element.style.setProperty('--fall-drift', `${horizontalDrift}px`);
          element.style.opacity = '0';
        });
      }, delay);
      
      fallingTimeoutRefs.current.add(timeoutId);
    });

    // Hide the entire sphere after animation completes
    const hideTimeoutId = safeTimeout(() => {
      if (sphereRef.current) {
        sphereRef.current.style.opacity = '0';
        sphereRef.current.style.pointerEvents = 'none';
      }
    }, durationMs);
    
    fallingTimeoutRefs.current.add(hideTimeoutId);

    prevIsFallingRef.current = isFalling;
    
    return () => {
      fallingTimeoutRefs.current.forEach(id => clearTimeout(id));
      fallingTimeoutRefs.current.clear();
    };
  }, [isFalling, fallDuration, isReverseReset, safeTimeout]);

  const prevImagesRef = useRef(defaultImages);
  const prevImagesPropRef = useRef(images);
  const prevResetKeyRef = useRef(resetKey);
  const resetTriggeredRef = useRef(false);
  const resetTimeoutRefs = useRef<Set<ReturnType<typeof setTimeout>>>(new Set());
  
  // Reset falling animation and animate back into place when isFalling becomes false
  useEffect(() => {
    if (!isMountedRef.current) return;
    
    // Clear previous reset timeouts
    resetTimeoutRefs.current.forEach(id => clearTimeout(id));
    resetTimeoutRefs.current.clear();
    
    const imagesPropChanged = prevImagesPropRef.current !== images;
    const resetKeyChanged = prevResetKeyRef.current !== resetKey;
    prevImagesPropRef.current = images;
    prevResetKeyRef.current = resetKey;
    
    // Trigger reset if we need to reset and we're not falling or reverse resetting
    // Reset should happen when:
    // 1. needsResetRef is true (items were falling or reverse resetting)
    // 2. isFalling is false (not currently falling)
    // 3. isReverseReset is false (not currently reverse resetting)
    // 4. We have items to reset (defaultImages has items)
    // 5. We haven't already triggered reset
    // 6. resetKey changed (navigated back from falling route) OR images prop changed
    const shouldReset = needsResetRef.current && !isFalling && !isReverseReset && !resetAnimationActiveRef.current && defaultImages.length > 0 && !resetTriggeredRef.current && (resetKeyChanged || imagesPropChanged);
    
    if (shouldReset && sphereRef.current && isMountedRef.current) {
      resetTriggeredRef.current = true;
      resetAnimationActiveRef.current = true;
      
      // Wait for items to be rendered (in case images just changed)
      // Use a retry mechanism to ensure items exist
      let retries = 0;
      const maxRetries = 20; // Try for up to 2 seconds
      
      const tryReset = () => {
        if (!isMountedRef.current || !sphereRef.current) {
          resetTriggeredRef.current = false;
          resetAnimationActiveRef.current = false;
          return;
        }
        
        const sphereItems = sphereRef.current.querySelectorAll('.sphere-item');
        if (!sphereItems || sphereItems.length === 0) {
          retries++;
          if (retries < maxRetries) {
            const retryTimeoutId = safeTimeout(tryReset, 100);
            resetTimeoutRefs.current.add(retryTimeoutId);
            return;
          } else {
            resetTriggeredRef.current = false;
            resetAnimationActiveRef.current = false;
            return;
          }
        }
        
        // Items found, proceed with reset
        const initTimeoutId = safeTimeout(() => {
          if (!isMountedRef.current || !sphereRef.current) {
            resetTriggeredRef.current = false;
            resetAnimationActiveRef.current = false;
            return;
          }

          const gen = generationRef.current;
          
          // Reset sphere visibility and pointer events
          sphereRef.current.style.opacity = '1';
          sphereRef.current.style.pointerEvents = 'auto';

          const itemCount = sphereItems.length;
          const lastItemDelay = itemCount * RESET_STAGGER_DELAY;
          const totalDuration = RESET_ANIMATION_DURATION + lastItemDelay;

          // Reset all items and animate them back into place
          // Start from their "fallen" state (off-screen) and animate back
          sphereItems.forEach((item, index) => {
            if (!isMountedRef.current) return;
            
            const element = item as HTMLElement;
            const delay = index * RESET_STAGGER_DELAY;
            
            // Set initial fallen state (they should start off-screen)
            // First, set transition to none to set initial state instantly
            element.style.transition = 'none';
            element.setAttribute('data-falling', 'true');
            const screenHeight = window.innerHeight;
            element.style.setProperty('--fall-distance', `${screenHeight + 1000}px`);
            element.style.setProperty('--fall-rotation', '0deg');
            element.style.setProperty('--fall-drift', '0px');
            element.style.opacity = '0';
            
            // Force a reflow to apply the initial state
            void element.offsetHeight;
            
            const itemTimeoutId = safeTimeout(() => {
              if (!isMountedRef.current) return;
              
              // Set transition BEFORE removing attributes
              element.style.transition = `transform ${RESET_ANIMATION_DURATION}ms cubic-bezier(0.19, 1, 0.22, 1), opacity ${RESET_ANIMATION_DURATION}ms ease-in`;
              
              // Use requestAnimationFrame to ensure transition is applied
              requestAnimationFrame(() => {
                if (!isMountedRef.current) return;
                if (generationRef.current !== gen) return;
                
                // Remove falling attributes and reset styles to animate back
                element.removeAttribute('data-falling');
                element.style.removeProperty('--fall-distance');
                element.style.removeProperty('--fall-rotation');
                element.style.removeProperty('--fall-drift');
                element.style.opacity = '1';
              });
            }, delay);
            
            resetTimeoutRefs.current.add(itemTimeoutId);
          });

          // Reset rotation to start fresh
          rotationRef.current = { x: 0, y: 0 };
          applyTransform(0, 0);
          
          // Clear the reset flag after animation completes (use dynamic duration)
          // Add extra buffer to ensure animation completes
          const cleanupTimeoutId = safeTimeout(() => {
            needsResetRef.current = false;
            resetTriggeredRef.current = false;
            resetAnimationActiveRef.current = false;
          }, totalDuration + 100); // Add 100ms buffer
          
          resetTimeoutRefs.current.add(cleanupTimeoutId);
          
          // Safety fallback: ensure flag resets even if something goes wrong
          const fallbackTimeoutId = safeTimeout(() => {
            if (resetAnimationActiveRef.current) {
              resetAnimationActiveRef.current = false;
            }
          }, totalDuration + 2000); // 2 second fallback
          
          resetTimeoutRefs.current.add(fallbackTimeoutId);
        }, 50); // Small delay to ensure DOM is ready
        
        resetTimeoutRefs.current.add(initTimeoutId);
      };
      
      // Start trying to reset
      const startTimeoutId = safeTimeout(tryReset, 100);
      resetTimeoutRefs.current.add(startTimeoutId);
    }

    // Reset the trigger flag when falling starts again
    if (isFalling) {
      resetTriggeredRef.current = false;
      resetAnimationActiveRef.current = false;
    }

    prevIsFallingRef.current = isFalling;
    
    return () => {
      resetTimeoutRefs.current.forEach(id => clearTimeout(id));
      resetTimeoutRefs.current.clear();
      // Reset flags on cleanup
      resetAnimationActiveRef.current = false;
      resetTriggeredRef.current = false;
    };
  }, [isFalling, isReverseReset, defaultImages, images, resetKey, safeTimeout]);

  const stopInertia = useCallback(() => {
    if (inertiaRAF.current) {
      cancelAnimationFrame(inertiaRAF.current);
      inertiaRAF.current = null;
    }
  }, []);

  const startInertia = useCallback(
    (vx: number, vy: number) => {
      const MAX_V = 1.4;
      let vX = clamp(vx, -MAX_V, MAX_V) * 80;
      let vY = clamp(vy, -MAX_V, MAX_V) * 80;
      let frames = 0;
      const d = clamp(dragDampening ?? 0.6, 0, 1);
      const frictionMul = 0.94 + 0.055 * d;
      const stopThreshold = 0.015 - 0.01 * d;
      const maxFrames = Math.round(90 + 270 * d);
      const step = () => {
        vX *= frictionMul;
        vY *= frictionMul;
        if (Math.abs(vX) < stopThreshold && Math.abs(vY) < stopThreshold) {
          inertiaRAF.current = null;
          return;
        }
        if (++frames > maxFrames) {
          inertiaRAF.current = null;
          return;
        }
        const nextX = clamp(rotationRef.current.x - vY / 200, -maxVerticalRotationDeg, maxVerticalRotationDeg);
        const nextY = wrapAngleSigned(rotationRef.current.y + vX / 200);
        rotationRef.current = { x: nextX, y: nextY };
        applyTransform(nextX, nextY);
        inertiaRAF.current = requestAnimationFrame(step);
      };
      stopInertia();
      inertiaRAF.current = requestAnimationFrame(step);
    },
    [dragDampening, maxVerticalRotationDeg, stopInertia]
  );

  const openItemFromElement = (el: HTMLElement) => {
    if (!isMountedRef.current) return;
    if (openingRef.current) return;
    openingRef.current = true;
    openStartedAtRef.current = performance.now();
    lockScroll();
    const parent = el.parentElement as HTMLElement;
    if (!parent) {
      openingRef.current = false;
      unlockScroll();
      return;
    }
    focusedElRef.current = el;
    el.setAttribute('data-focused', 'true');
    const offsetX = getDataNumber(parent, 'offsetX', 0);
    const offsetY = getDataNumber(parent, 'offsetY', 0);
    const sizeX = getDataNumber(parent, 'sizeX', 2);
    const sizeY = getDataNumber(parent, 'sizeY', 2);
    const parentRot = computeItemBaseRotation(offsetX, offsetY, sizeX, sizeY, segments);
    const parentY = normalizeAngle(parentRot.rotateY);
    const globalY = normalizeAngle(rotationRef.current.y);
    let rotY = -(parentY + globalY) % 360;
    if (rotY < -180) rotY += 360;
    const rotX = -parentRot.rotateX - rotationRef.current.x;
    parent.style.setProperty('--rot-y-delta', `${rotY}deg`);
    parent.style.setProperty('--rot-x-delta', `${rotX}deg`);
    const refDiv = document.createElement('div');
    refDiv.className = 'item__image item__image--reference opacity-0';
    refDiv.style.transform = `rotateX(${-parentRot.rotateX}deg) rotateY(${-parentRot.rotateY}deg)`;
    parent.appendChild(refDiv);

    void refDiv.offsetHeight;

    const tileR = refDiv.getBoundingClientRect();
    const mainR = mainRef.current?.getBoundingClientRect();
    const frameR = frameRef.current?.getBoundingClientRect();

    if (!isMountedRef.current || !mainR || !frameR || tileR.width <= 0 || tileR.height <= 0) {
      openingRef.current = false;
      focusedElRef.current = null;
      if (parent.contains(refDiv)) {
        parent.removeChild(refDiv);
      }
      unlockScroll();
      return;
    }

    originalTilePositionRef.current = {
      left: tileR.left,
      top: tileR.top,
      width: tileR.width,
      height: tileR.height
    };
    el.style.visibility = 'hidden';
    (el.style as any).zIndex = 0;
    const overlay = document.createElement('div');
    overlay.className = 'enlarge';
    overlay.style.cssText = `position:absolute; left:${frameR.left - mainR.left}px; top:${frameR.top - mainR.top}px; width:${frameR.width}px; height:${frameR.height}px; opacity:0; z-index:30; will-change:transform,opacity; transform-origin:top left; transition:transform ${enlargeTransitionMs}ms ease, opacity ${enlargeTransitionMs}ms ease; border-radius:${openedImageBorderRadius}; overflow:hidden; box-shadow:0 10px 30px rgba(0,0,0,.35);`;
    const rawSrc = parent.dataset.src || (el.querySelector('img') as HTMLImageElement)?.src || '';
    const rawAlt = parent.dataset.alt || (el.querySelector('img') as HTMLImageElement)?.alt || '';
    const img = document.createElement('img');
    img.src = rawSrc;
    img.alt = rawAlt;
    img.style.cssText = `width:100%; height:100%; object-fit:contain; filter:${grayscale ? 'grayscale(1)' : 'none'}; image-rendering: pixelated;`;
    overlay.appendChild(img);
    if (!viewerRef.current || !isMountedRef.current) {
      openingRef.current = false;
      focusedElRef.current = null;
      if (parent.contains(refDiv)) {
        parent.removeChild(refDiv);
      }
      unlockScroll();
      return;
    }
    viewerRef.current.appendChild(overlay);
    const tx0 = tileR.left - frameR.left;
    const ty0 = tileR.top - frameR.top;
    const sx0 = tileR.width / frameR.width;
    const sy0 = tileR.height / frameR.height;

    const validSx0 = isFinite(sx0) && sx0 > 0 ? sx0 : 1;
    const validSy0 = isFinite(sy0) && sy0 > 0 ? sy0 : 1;

    overlay.style.transform = `translate(${tx0}px, ${ty0}px) scale(${validSx0}, ${validSy0})`;
    const openTimeoutId = safeTimeout(() => {
      if (!overlay.parentElement) return;
      overlay.style.opacity = '1';
      overlay.style.transform = 'translate(0px, 0px) scale(1, 1)';
      rootRef.current?.setAttribute('data-enlarging', 'true');
    }, 16);
  };

  useGesture(
    {
      onDragStart: ({ event }) => {
        if (focusedElRef.current) return;
        stopInertia();

        const evt = event as PointerEvent;
        pointerTypeRef.current = (evt.pointerType as any) || 'mouse';
        if (pointerTypeRef.current === 'touch') evt.preventDefault();
        if (pointerTypeRef.current === 'touch') lockScroll();
        draggingRef.current = true;
        cancelTapRef.current = false;
        movedRef.current = false;
        startRotRef.current = { ...rotationRef.current };
        startPosRef.current = { x: evt.clientX, y: evt.clientY };
        const potential = (evt.target as Element).closest?.('.item__image') as HTMLElement | null;
        tapTargetRef.current = potential || null;
      },
      onDrag: ({ event, last, velocity: velArr = [0, 0], direction: dirArr = [0, 0], movement }) => {
        if (focusedElRef.current || !draggingRef.current || !startPosRef.current) return;

        const evt = event as PointerEvent;
        if (pointerTypeRef.current === 'touch') evt.preventDefault();

        const dxTotal = evt.clientX - startPosRef.current.x;
        const dyTotal = evt.clientY - startPosRef.current.y;

        if (!movedRef.current) {
          const dist2 = dxTotal * dxTotal + dyTotal * dyTotal;
          if (dist2 > 16) movedRef.current = true;
        }

        const nextX = clamp(
          startRotRef.current.x - dyTotal / dragSensitivity,
          -maxVerticalRotationDeg,
          maxVerticalRotationDeg
        );
        const nextY = startRotRef.current.y + dxTotal / dragSensitivity;

        const cur = rotationRef.current;
        if (cur.x !== nextX || cur.y !== nextY) {
          rotationRef.current = { x: nextX, y: nextY };
          applyTransform(nextX, nextY);
        }

        if (last) {
          draggingRef.current = false;
          let isTap = false;

          if (startPosRef.current) {
            const dx = evt.clientX - startPosRef.current.x;
            const dy = evt.clientY - startPosRef.current.y;
            const dist2 = dx * dx + dy * dy;
            const TAP_THRESH_PX = pointerTypeRef.current === 'touch' ? 10 : 6;
            if (dist2 <= TAP_THRESH_PX * TAP_THRESH_PX) {
              isTap = true;
            }
          }

          let [vMagX, vMagY] = velArr;
          const [dirX, dirY] = dirArr;
          let vx = vMagX * dirX;
          let vy = vMagY * dirY;

          if (!isTap && Math.abs(vx) < 0.001 && Math.abs(vy) < 0.001 && Array.isArray(movement)) {
            const [mx, my] = movement;
            vx = (mx / dragSensitivity) * 0.02;
            vy = (my / dragSensitivity) * 0.02;
          }

          if (!isTap && (Math.abs(vx) > 0.005 || Math.abs(vy) > 0.005)) {
            startInertia(vx, vy);
          }
          startPosRef.current = null;
          cancelTapRef.current = !isTap;

          if (isTap && tapTargetRef.current && !focusedElRef.current) {
            openItemFromElement(tapTargetRef.current);
          }
          tapTargetRef.current = null;

          if (cancelTapRef.current) {
            if (cancelTapTimeoutRef.current) {
              clearTimeout(cancelTapTimeoutRef.current);
            }
            cancelTapTimeoutRef.current = safeTimeout(() => {
              cancelTapRef.current = false;
            }, 120);
          }
          if (pointerTypeRef.current === 'touch') unlockScroll();
          if (movedRef.current) lastDragEndAt.current = performance.now();
          movedRef.current = false;
        }
      }
    },
    { target: mainRef, eventOptions: { passive: false } }
  );

  useEffect(() => {
    const scrim = scrimRef.current;
    if (!scrim) return;

    const close = () => {
      if (!isMountedRef.current) return;
      if (performance.now() - openStartedAtRef.current < 250) return;
      const el = focusedElRef.current;
      if (!el) return;
      const parent = el.parentElement as HTMLElement;
      const overlay = viewerRef.current?.querySelector('.enlarge') as HTMLElement | null;
      if (!overlay) return;

      const refDiv = parent.querySelector('.item__image--reference') as HTMLElement | null;

      const originalPos = originalTilePositionRef.current;
      if (!originalPos) {
        overlay.remove();
        if (refDiv) refDiv.remove();
        parent.style.setProperty('--rot-y-delta', `0deg`);
        parent.style.setProperty('--rot-x-delta', `0deg`);
        el.style.visibility = '';
        (el.style as any).zIndex = 0;
        focusedElRef.current = null;
        rootRef.current?.removeAttribute('data-enlarging');
        openingRef.current = false;
        return;
      }

      const currentRect = overlay.getBoundingClientRect();
      const rootRect = rootRef.current?.getBoundingClientRect();
      if (!rootRect) return;

      const originalPosRelativeToRoot = {
        left: originalPos.left - rootRect.left,
        top: originalPos.top - rootRect.top,
        width: originalPos.width,
        height: originalPos.height
      };

      const overlayRelativeToRoot = {
        left: currentRect.left - rootRect.left,
        top: currentRect.top - rootRect.top,
        width: currentRect.width,
        height: currentRect.height
      };

      const animatingOverlay = document.createElement('div');
      animatingOverlay.className = 'enlarge-closing';
      animatingOverlay.style.cssText = `
        position: absolute;
        left: ${overlayRelativeToRoot.left}px;
        top: ${overlayRelativeToRoot.top}px;
        width: ${overlayRelativeToRoot.width}px;
        height: ${overlayRelativeToRoot.height}px;
        z-index: 9999;
        border-radius: ${openedImageBorderRadius};
        overflow: hidden;
        box-shadow: 0 10px 30px rgba(0,0,0,.35);
        transition: all ${enlargeTransitionMs}ms ease-out;
        pointer-events: none;
        margin: 0;
        transform: none;
        filter: ${grayscale ? 'grayscale(1)' : 'none'};
      `;

      const originalImg = overlay.querySelector('img');
      if (originalImg) {
        const img = originalImg.cloneNode() as HTMLImageElement;
        img.style.cssText = 'width: 100%; height: 100%; object-fit: contain; image-rendering: pixelated;';
        animatingOverlay.appendChild(img);
      }

      overlay.remove();
      if (!rootRef.current) return;
      rootRef.current.appendChild(animatingOverlay);

      void animatingOverlay.getBoundingClientRect();

      requestAnimationFrame(() => {
        if (!isMountedRef.current) return;
        animatingOverlay.style.left = originalPosRelativeToRoot.left + 'px';
        animatingOverlay.style.top = originalPosRelativeToRoot.top + 'px';
        animatingOverlay.style.width = originalPosRelativeToRoot.width + 'px';
        animatingOverlay.style.height = originalPosRelativeToRoot.height + 'px';
        animatingOverlay.style.opacity = '0';
      });

      const cleanup = () => {
        if (!isMountedRef.current) return;
        
        animatingOverlay.remove();
        originalTilePositionRef.current = null;

        if (refDiv) refDiv.remove();
        parent.style.transition = 'none';
        el.style.transition = 'none';

        parent.style.setProperty('--rot-y-delta', `0deg`);
        parent.style.setProperty('--rot-x-delta', `0deg`);

        requestAnimationFrame(() => {
          if (!isMountedRef.current) return;
          el.style.visibility = '';
          el.style.opacity = '0';
          (el.style as any).zIndex = 0;
          focusedElRef.current = null;
          rootRef.current?.removeAttribute('data-enlarging');

          requestAnimationFrame(() => {
            if (!isMountedRef.current) return;
            el.style.transition = 'opacity 300ms ease-out';

            requestAnimationFrame(() => {
              if (!isMountedRef.current) return;
              el.style.opacity = '1';
              const finalTimeoutId = safeTimeout(() => {
                el.style.transition = '';
                el.style.opacity = '';
                openingRef.current = false;
                if (!draggingRef.current && rootRef.current?.getAttribute('data-enlarging') !== 'true') {
                  document.body.classList.remove('dg-scroll-lock');
                }
              }, 300);
            });
          });
        });
      };

      animatingOverlay.addEventListener('transitionend', cleanup, {
        once: true
      });
    };

    scrim.addEventListener('click', close);
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') close();
    };
    window.addEventListener('keydown', onKey);

    return () => {
      scrim.removeEventListener('click', close);
      window.removeEventListener('keydown', onKey);
    };
  }, [enlargeTransitionMs, openedImageBorderRadius, grayscale, safeTimeout]);

  const cssStyles = `
    .sphere-root {
      --radius: 520px;
      --viewer-pad: 72px;
      --circ: calc(var(--radius) * 3.14);
      --rot-y: calc((360deg / var(--segments-x)) / 2);
      --rot-x: calc((360deg / var(--segments-y)) / 2);
      --item-width: calc(var(--circ) / var(--segments-x));
      --item-height: calc(var(--circ) / var(--segments-y));
    }
    
    .sphere-root * { box-sizing: border-box; }
    .sphere, .sphere-item, .item__image { transform-style: preserve-3d; }
    
    .stage {
      width: 100%;
      height: 100%;
      display: grid;
      place-items: center;
      position: absolute;
      inset: 0;
      margin: auto;
      perspective: calc(var(--radius) * 6);
      perspective-origin: 50% 50%;
    }
    
    .sphere {
      transform: translateZ(calc(var(--radius) * -1));
      will-change: transform;
      position: absolute;
    }
    
    .sphere-item {
      width: calc(var(--item-width) * var(--item-size-x));
      height: calc(var(--item-height) * var(--item-size-y));
      position: absolute;
      top: -999px;
      bottom: -999px;
      left: -999px;
      right: -999px;
      margin: auto;
      transform-origin: 50% 50%;
      backface-visibility: hidden;
      transition: transform 300ms;
      transform: rotateY(calc(var(--rot-y) * (var(--offset-x) + ((var(--item-size-x) - 1) / 2)) + var(--rot-y-delta, 0deg))) 
                 rotateX(calc(var(--rot-x) * (var(--offset-y) - ((var(--item-size-y) - 1) / 2)) + var(--rot-x-delta, 0deg))) 
                 translateZ(var(--radius));
    }
    
    .sphere-item[data-falling="true"] {
      transform: rotateY(calc(var(--rot-y) * (var(--offset-x) + ((var(--item-size-x) - 1) / 2)) + var(--rot-y-delta, 0deg))) 
                 rotateX(calc(var(--rot-x) * (var(--offset-y) - ((var(--item-size-y) - 1) / 2)) + var(--rot-x-delta, 0deg))) 
                 translateZ(var(--radius))
                 translateY(var(--fall-distance, 1000px))
                 translateX(var(--fall-drift, 0px))
                 rotateZ(var(--fall-rotation, 0deg));
      transition: transform 1.5s cubic-bezier(0.55, 0.055, 0.675, 0.19), opacity 1.5s ease-out;
    }
    
    .sphere-root[data-enlarging="true"] .scrim {
      opacity: 1 !important;
      pointer-events: all !important;
    }
    
    @media (max-aspect-ratio: 1/1) {
      .viewer-frame {
        height: auto !important;
        width: 100% !important;
      }
    }
    .item__image {
      position: absolute;
      inset: 8px;
      border-radius: var(--tile-radius, 12px);
      overflow: hidden;
      cursor: pointer;
      backface-visibility: hidden;
      -webkit-backface-visibility: hidden;
      transition: transform 300ms;
      pointer-events: auto;
      -webkit-transform: translateZ(0);
      transform: translateZ(0);
    }
    .item__image--reference {
      position: absolute;
      inset: 10px;
      pointer-events: none;
    }
  `;

  return (
    <>
      <style dangerouslySetInnerHTML={{ __html: cssStyles }} />
      <div
        ref={rootRef}
        className={`sphere-root fixed inset-0 w-full h-full ${className}`}
        style={
          {
            ['--segments-x' as any]: segments,
            ['--segments-y' as any]: segments,
            ['--overlay-blur-color' as any]: overlayBlurColor,
            ['--tile-radius' as any]: imageBorderRadius,
            ['--enlarge-radius' as any]: openedImageBorderRadius,
            ['--image-filter' as any]: grayscale ? 'grayscale(1)' : 'none',
            opacity: '0.7',
            zIndex: 10,
            pointerEvents: 'none'
          } as React.CSSProperties
        }
      >
        <main
          ref={mainRef}
          className="absolute inset-0 grid place-items-center overflow-hidden select-none bg-transparent"
          style={{
            touchAction: 'none',
            WebkitUserSelect: 'none'
          }}
        >
          <div className="stage">
            <div ref={sphereRef} className="sphere">
              {items.map((it, i) => (
                <div
                  key={`${it.x},${it.y},${i}`}
                  className="sphere-item absolute m-auto"
                  data-src={it.src}
                  data-alt={it.alt}
                  data-offset-x={it.x}
                  data-offset-y={it.y}
                  data-size-x={it.sizeX}
                  data-size-y={it.sizeY}
                  style={
                    {
                      ['--offset-x' as any]: it.x,
                      ['--offset-y' as any]: it.y,
                      ['--item-size-x' as any]: it.sizeX,
                      ['--item-size-y' as any]: it.sizeY,
                      top: '-999px',
                      bottom: '-999px',
                      left: '-999px',
                      right: '-999px'
                    } as React.CSSProperties
                  }
                >
                  <DomeGalleryImage
                    src={it.src}
                    alt={it.alt}
                    imageBorderRadius={imageBorderRadius}
                    grayscale={grayscale}
                    onOpen={(e) => {
                      if (draggingRef.current) return;
                      if (movedRef.current) return;
                      if (performance.now() - lastDragEndAt.current < 80) return;
                      if (openingRef.current) return;
                      openItemFromElement(e.currentTarget as HTMLElement);
                    }}
                  />
                </div>
              ))}
            </div>
          </div>


          <div
            ref={viewerRef}
            className="absolute inset-0 z-20 pointer-events-none flex items-center justify-center"
            style={{ padding: 'var(--viewer-pad)' }}
          >
            <div
              ref={scrimRef}
              className="scrim absolute inset-0 z-10 pointer-events-none opacity-0 transition-opacity duration-500"
              style={{
                background: 'rgba(0, 0, 0, 0.4)',
                backdropFilter: 'blur(3px)'
              }}
            />
            <div
              ref={frameRef}
              className="viewer-frame h-full aspect-square flex"
              style={{
                borderRadius: `var(--enlarge-radius, ${openedImageBorderRadius})`
              }}
            />
          </div>
        </main>
      </div>
    </>
  );
}

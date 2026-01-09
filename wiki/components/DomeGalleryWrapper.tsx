"use client";

import { useEffect, useState, useRef } from 'react';
import { DomeGallery } from './DomeGallery';
import { getSpritePath } from '@/lib/spriteUtils';
import creaturesData from '@/data/creatures.json';

// Cache for validated images to avoid re-validation
const imageValidationCache = new Map<string, boolean>();

// Function to validate if an image exists (with caching)
function validateImage(src: string): Promise<boolean> {
  // Check cache first
  if (imageValidationCache.has(src)) {
    return Promise.resolve(imageValidationCache.get(src)!);
  }

  return new Promise((resolve) => {
    const img = new Image();
    const timeout = setTimeout(() => {
      imageValidationCache.set(src, false);
      resolve(false);
    }, 1500); // Reduced timeout for faster failure
    
    img.onload = () => {
      clearTimeout(timeout);
      imageValidationCache.set(src, true);
      resolve(true);
    };
    
    img.onerror = () => {
      clearTimeout(timeout);
      imageValidationCache.set(src, false);
      resolve(false);
    };
    
    img.src = src;
  });
}

// Function to validate multiple images in parallel batches (non-blocking)
async function validateImagesBatch(imagePaths: string[]): Promise<string[]> {
  const batchSize = 5; // Reduced batch size for less blocking
  const validatedImages: string[] = [];
  
  // Process batches with small delays to avoid blocking
  for (let i = 0; i < imagePaths.length; i += batchSize) {
    const batch = imagePaths.slice(i, i + batchSize);
    
    // Use requestIdleCallback if available, otherwise setTimeout
    if (typeof window !== 'undefined' && 'requestIdleCallback' in window) {
      await new Promise<void>((resolve) => {
        requestIdleCallback(() => {
          Promise.all(batch.map(path => validateImage(path))).then(results => {
            results.forEach((isValid, index) => {
              if (isValid) {
                validatedImages.push(batch[index]);
              }
            });
            resolve();
          });
        }, { timeout: 100 });
      });
    } else {
      const results = await Promise.all(batch.map(path => validateImage(path)));
      results.forEach((isValid, index) => {
        if (isValid) {
          validatedImages.push(batch[index]);
        }
      });
      
      // Small delay between batches to avoid blocking
      if (i + batchSize < imagePaths.length) {
        await new Promise(resolve => setTimeout(resolve, 10));
      }
    }
  }
  
  return validatedImages;
}

// Function to validate and replace invalid images (optimized)
async function validateAndReplaceImages(
  imagePaths: string[],
  allAvailablePaths: string[],
  targetCount: number
): Promise<string[]> {
  // First, validate the initial set of images
  const validatedImages = await validateImagesBatch(imagePaths);
  
  // If we have enough valid images, return them
  if (validatedImages.length >= targetCount) {
    return validatedImages.slice(0, targetCount);
  }
  
  // Need more images - validate from the pool
  const remainingNeeded = targetCount - validatedImages.length;
  const poolPaths = allAvailablePaths.filter(path => !validatedImages.includes(path));
  
  // Shuffle pool for variety
  const shuffledPool = [...poolPaths].sort(() => Math.random() - 0.5);
  
  // Only validate what we need
  const poolToValidate = shuffledPool.slice(0, remainingNeeded * 2); // Validate extra for buffer
  const poolValidated = await validateImagesBatch(poolToValidate);
  
  // Combine validated images
  const combined = [...validatedImages, ...poolValidated];
  
  // Return up to target count, removing duplicates
  const unique = Array.from(new Set(combined));
  return unique.slice(0, targetCount);
}

export function DomeGalleryWrapper() {
  const [images, setImages] = useState<string[]>([]);
  const loadSeqRef = useRef(0);

  // Always load creature sprites - never change to item images
  useEffect(() => {
    const seq = ++loadSeqRef.current;
    
    // Only load images if we don't have any yet
    if (images.length === 0) {
      setImages([]); // Clear first to show loading state
      
      // Load creature sprites
      const creatures = creaturesData as any[];
      const targetCount = 175; // segments * 5 = 35 * 5 = 175
      
      // Generate all possible creature sprite paths
      const allCreaturePaths: string[] = [];
      creatures.forEach(creature => {
        allCreaturePaths.push(getSpritePath(creature.Name, false));
        allCreaturePaths.push(getSpritePath(creature.Name, true));
      });
      
      // Shuffle and select initial set
      const shuffled = [...allCreaturePaths].sort(() => Math.random() - 0.5);
      const selected = shuffled.slice(0, targetCount);
      
      // Validate and replace invalid images
      validateAndReplaceImages(selected, allCreaturePaths, targetCount).then(validatedImages => {
        if (loadSeqRef.current !== seq) return;
        setImages(validatedImages);
      });
    }
  }, [images.length]);

  return (
    <div
      style={{
        width: '100%',
        height: '100%',
      }}
    >
      <DomeGallery 
        images={images}
      />
    </div>
  );
}


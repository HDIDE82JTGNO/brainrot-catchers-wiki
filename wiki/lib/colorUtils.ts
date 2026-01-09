/**
 * Utility functions for extracting and manipulating colors from images
 */

export interface ColorTheme {
  primary: string;      // Hex color (#RRGGBB)
  primaryRgb: string;  // RGB string (r, g, b)
  light: string;       // Light variant for backgrounds
  dark: string;        // Dark variant for borders/text
  gradient: string;    // Gradient string for CSS
}

/**
 * Extracts the average color from an image by analyzing its pixels
 * @param imageSrc - The source URL/path of the image
 * @returns Promise resolving to a ColorTheme object
 */
export async function extractAverageColor(imageSrc: string): Promise<ColorTheme> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.crossOrigin = 'anonymous'; // Handle CORS
    
    img.onload = () => {
      try {
        // Create canvas and draw image
        const canvas = document.createElement('canvas');
        const ctx = canvas.getContext('2d');
        
        if (!ctx) {
          reject(new Error('Could not get canvas context'));
          return;
        }
        
        canvas.width = img.width;
        canvas.height = img.height;
        ctx.drawImage(img, 0, 0);
        
        // Get image data
        const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
        const data = imageData.data;
        
        // Calculate average RGB values
        let r = 0, g = 0, b = 0;
        let pixelCount = 0;
        
        // Sample pixels (every 4th pixel for performance, or all if small image)
        const step = canvas.width * canvas.height > 10000 ? 4 : 1;
        
        for (let i = 0; i < data.length; i += 4 * step) {
          // Skip fully transparent pixels (alpha < 128)
          if (data[i + 3] < 128) continue;
          
          r += data[i];
          g += data[i + 1];
          b += data[i + 2];
          pixelCount++;
        }
        
        if (pixelCount === 0) {
          // Fallback to default color if no opaque pixels found
          resolve(getDefaultTheme());
          return;
        }
        
        // Calculate averages
        r = Math.round(r / pixelCount);
        g = Math.round(g / pixelCount);
        b = Math.round(b / pixelCount);
        
        // Generate theme variants
        const theme = generateThemeFromRgb(r, g, b);
        resolve(theme);
      } catch (error) {
        reject(error);
      }
    };
    
    img.onerror = () => {
      // Fallback to default theme on error
      resolve(getDefaultTheme());
    };
    
    img.src = imageSrc;
  });
}

/**
 * Generates a color theme from RGB values
 */
function generateThemeFromRgb(r: number, g: number, b: number): ColorTheme {
  // Convert to hex
  const primary = `#${[r, g, b].map(x => {
    const hex = x.toString(16);
    return hex.length === 1 ? '0' + hex : hex;
  }).join('')}`;
  
  const primaryRgb = `${r}, ${g}, ${b}`;
  
  // Generate light variant (mix with white - 85% white, 15% color)
  const lightR = Math.round(r * 0.15 + 255 * 0.85);
  const lightG = Math.round(g * 0.15 + 255 * 0.85);
  const lightB = Math.round(b * 0.15 + 255 * 0.85);
  const light = `#${[lightR, lightG, lightB].map(x => {
    const hex = x.toString(16);
    return hex.length === 1 ? '0' + hex : hex;
  }).join('')}`;
  
  // Generate dark variant (reduce brightness by 30%)
  const darkR = Math.max(0, Math.round(r * 0.7));
  const darkG = Math.max(0, Math.round(g * 0.7));
  const darkB = Math.max(0, Math.round(b * 0.7));
  const dark = `#${[darkR, darkG, darkB].map(x => {
    const hex = x.toString(16);
    return hex.length === 1 ? '0' + hex : hex;
  }).join('')}`;
  
  // Generate gradient (from light to primary)
  const gradient = `linear-gradient(135deg, ${light} 0%, ${primary} 100%)`;
  
  return {
    primary,
    primaryRgb,
    light,
    dark,
    gradient
  };
}

/**
 * Returns a default theme (slate colors) as fallback
 */
export function getDefaultTheme(): ColorTheme {
  return {
    primary: '#64748b',
    primaryRgb: '100, 116, 139',
    light: '#f1f5f9',
    dark: '#475569',
    gradient: 'linear-gradient(135deg, #f1f5f9 0%, #64748b 100%)'
  };
}


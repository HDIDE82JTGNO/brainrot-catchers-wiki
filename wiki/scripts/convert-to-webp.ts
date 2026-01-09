import sharp from 'sharp';
import { readdir, stat, unlink } from 'fs/promises';
import { join, extname, basename } from 'path';
import { existsSync } from 'fs';

async function convertImageToWebP(inputPath: string, outputPath: string): Promise<void> {
  try {
    await sharp(inputPath)
      .webp({ quality: 90, effort: 6 })
      .toFile(outputPath);
    console.log(`✓ Converted: ${basename(inputPath)} -> ${basename(outputPath)}`);
  } catch (error) {
    console.error(`✗ Failed to convert ${inputPath}:`, error);
    throw error;
  }
}

async function processDirectory(dirPath: string): Promise<void> {
  const files = await readdir(dirPath);
  const pngFiles = files.filter(file => extname(file).toLowerCase() === '.png');
  
  for (const file of pngFiles) {
    const inputPath = join(dirPath, file);
    const outputPath = join(dirPath, file.replace(/\.png$/i, '.webp'));
    
    // Skip if webp already exists
    if (existsSync(outputPath)) {
      console.log(`⊘ Skipping ${file} (webp already exists)`);
      continue;
    }
    
    await convertImageToWebP(inputPath, outputPath);
  }
}

async function main() {
  const publicDir = join(process.cwd(), 'public');
  const spritesDir = join(publicDir, 'sprites');
  const itemsDir = join(publicDir, 'items');
  
  console.log('Starting PNG to WebP conversion...\n');
  
  try {
    // Convert sprites
    if (existsSync(spritesDir)) {
      console.log('Converting sprites...');
      await processDirectory(spritesDir);
      console.log('');
    }
    
    // Convert items
    if (existsSync(itemsDir)) {
      console.log('Converting items...');
      await processDirectory(itemsDir);
      console.log('');
    }
    
    // Convert root level PNG files
    console.log('Converting root level images...');
    await processDirectory(publicDir);
    console.log('');
    
    console.log('✓ Conversion complete!');
    console.log('\nNote: Original PNG files are still present. You may want to delete them after verifying the WebP files work correctly.');
  } catch (error) {
    console.error('Error during conversion:', error);
    process.exit(1);
  }
}

main();


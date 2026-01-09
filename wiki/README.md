# Brainrot Catchers Wiki

A comprehensive wiki for the Brainrot Catchers game, built with Next.js and deployed on Vercel.

## Features

- Complete creature database with stats, moves, and abilities
- Item catalog and descriptions
- Move database with type effectiveness
- Ability descriptions and effects
- Location guides and encounter information
- Team builder and comparison tools
- Damage calculator
- Type chart and weakness calculator
- And much more!

## Tech Stack

- **Framework**: Next.js 16.1.1
- **React**: 19.2.3
- **Styling**: Tailwind CSS 4
- **Animations**: Framer Motion, React Spring
- **Icons**: Tabler Icons
- **Deployment**: Vercel

## Getting Started

### Prerequisites

- Node.js 18+ 
- npm, yarn, pnpm, or bun

### Installation

1. Clone the repository:
```bash
git clone <your-repo-url>
cd wiki
```

2. Install dependencies:
```bash
npm install
```

3. Run the development server:
```bash
npm run dev
```

4. Open [http://localhost:3000](http://localhost:3000) in your browser

## Available Scripts

- `npm run dev` - Start development server
- `npm run build` - Build for production (includes data extraction)
- `npm run start` - Start production server
- `npm run lint` - Run ESLint
- `npm run extract` - Extract game data from Lua files
- `npm run sync-game-data` - Sync Lua game data files

## Project Structure

```
wiki/
├── app/              # Next.js app router pages
├── components/       # React components
├── lib/              # Utility functions
├── data/             # JSON data files (generated)
├── public/           # Static assets (images, sprites)
├── scripts/          # Build scripts
└── game-data/        # Source Lua game data files
```

## Deployment

### Deploying to Vercel

1. **Push to GitHub**:
   ```bash
   git add .
   git commit -m "Initial commit"
   git push origin main
   ```

2. **Connect to Vercel**:
   - Go to [vercel.com](https://vercel.com)
   - Click "New Project"
   - Import your GitHub repository
   - Vercel will auto-detect Next.js settings
   - Click "Deploy"

3. **Build Settings** (should auto-detect):
   - Framework Preset: Next.js
   - Build Command: `npm run build`
   - Output Directory: `.next`
   - Install Command: `npm install`

### Environment Variables

No environment variables are required for basic deployment. If you need to add any, configure them in the Vercel dashboard under Project Settings → Environment Variables.

## Data Updates

The wiki uses game data extracted from Lua files. To update the data:

1. Update the Lua files in `game-data/`
2. Run `npm run sync-game-data` to sync from parent directory (if applicable)
3. Run `npm run extract` to generate JSON data files
4. Commit and push the updated `data/` folder

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is private and proprietary.

## Support

For issues or questions, please open an issue on GitHub.

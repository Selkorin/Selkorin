// Script to create white smiley icon as PNG
// Uses sharp or canvas if available, otherwise creates SVG
const fs = require('fs');
const path = require('path');

// Create SVG icon - white smiley face
const svg = `<?xml version="1.0" encoding="UTF-8"?>
<svg width="512" height="512" viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg">
  <!-- Background circle - white -->
  <circle cx="256" cy="256" r="240" fill="white" opacity="0.95"/>
  <!-- Left eye -->
  <ellipse cx="185" cy="200" rx="35" ry="42" fill="#1a1a2e"/>
  <!-- Right eye -->
  <ellipse cx="327" cy="200" rx="35" ry="42" fill="#1a1a2e"/>
  <!-- Eye shine left -->
  <ellipse cx="175" cy="188" rx="12" ry="14" fill="white" opacity="0.6"/>
  <!-- Eye shine right -->
  <ellipse cx="317" cy="188" rx="12" ry="14" fill="white" opacity="0.6"/>
  <!-- Smile -->
  <path d="M 165 310 Q 256 390 347 310" stroke="#1a1a2e" stroke-width="20" fill="none" stroke-linecap="round"/>
</svg>`;

fs.writeFileSync(path.join(__dirname, 'assets', 'icon.svg'), svg);
console.log('SVG icon created at assets/icon.svg');

// Also create a simple base64 PNG by embedding SVG
// For Electron on Linux, PNG is preferred
const { execSync } = require('child_process');
try {
  // Try converting SVG to PNG using rsvg-convert or inkscape
  execSync('rsvg-convert -w 512 -h 512 assets/icon.svg -o assets/icon.png', { cwd: __dirname });
  console.log('PNG icon created via rsvg-convert');
} catch(e) {
  try {
    execSync('convert -background none assets/icon.svg assets/icon.png', { cwd: __dirname });
    console.log('PNG icon created via ImageMagick');
  } catch(e2) {
    try {
      execSync('inkscape --export-png=assets/icon.png --export-width=512 --export-height=512 assets/icon.svg', { cwd: __dirname });
      console.log('PNG icon created via Inkscape');
    } catch(e3) {
      // Fallback: copy SVG as PNG (some tools handle this)
      fs.copyFileSync('assets/icon.svg', 'assets/icon.png');
      console.log('Warning: using SVG as PNG fallback');
    }
  }
}

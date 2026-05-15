// Run once: node generate-icons.mjs
// Generates simple orange square PNG icons for the PWA manifest
import { createCanvas } from 'canvas';
import { writeFileSync } from 'fs';

function makeIcon(size) {
  const c = createCanvas(size, size);
  const ctx = c.getContext('2d');
  const r = size * 0.16;

  // Dark background with rounded corners
  ctx.fillStyle = '#111827';
  ctx.beginPath();
  ctx.moveTo(r, 0); ctx.lineTo(size - r, 0);
  ctx.quadraticCurveTo(size, 0, size, r);
  ctx.lineTo(size, size - r);
  ctx.quadraticCurveTo(size, size, size - r, size);
  ctx.lineTo(r, size); ctx.quadraticCurveTo(0, size, 0, size - r);
  ctx.lineTo(0, r); ctx.quadraticCurveTo(0, 0, r, 0);
  ctx.fill();

  // Orange "P" lettermark
  ctx.fillStyle = '#ea580c';
  ctx.font = `bold ${size * 0.52}px system-ui, sans-serif`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText('P', size / 2, size / 2 + size * 0.04);

  return c.toBuffer('image/png');
}

try {
  writeFileSync('public/icon-192.png', makeIcon(192));
  writeFileSync('public/icon-512.png', makeIcon(512));
  console.log('Icons generated.');
} catch {
  console.log('canvas not available — skipping icon generation (icons are optional)');
}

// Run once: node generate-icons.mjs
// Generates PNG app icons for the PWA manifest and iOS apple-touch-icon.
// Zero external dependencies — uses only Node's built-in zlib to encode PNGs.
// Renders the ProLine lettermark: dark rounded square with an orange "P".
import { deflateSync } from 'node:zlib';
import { writeFileSync } from 'node:fs';

const BG = [0x11, 0x18, 0x27];      // #111827 dark
const FG = [0xea, 0x58, 0x0c];      // #ea580c orange

// CRC32 (for PNG chunks)
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}
function encodePNG(size, rgba) {
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0); ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8;   // bit depth
  ihdr[9] = 6;   // colour type RGBA
  const stride = size * 4;
  const raw = Buffer.alloc((stride + 1) * size);
  for (let y = 0; y < size; y++) {
    raw[y * (stride + 1)] = 0; // filter type: none
    rgba.copy(raw, y * (stride + 1) + 1, y * stride, y * stride + stride);
  }
  const idat = deflateSync(raw, { level: 9 });
  return Buffer.concat([
    sig,
    chunk('IHDR', ihdr),
    chunk('IDAT', idat),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

const clamp01 = (v) => Math.max(0, Math.min(1, v));

// Renders the lettermark. `pad` insets the artwork so maskable icons keep the
// mark inside iOS/Android safe zones.
function makeIcon(size, { padded = false } = {}) {
  const buf = Buffer.alloc(size * size * 4);
  const cr = size * 0.156;                       // rounded-square corner radius

  // "P" geometry, proportional to size (matches the SVG lettermark)
  const inset = padded ? size * 0.10 : 0;
  const s = size - inset * 2;
  const ox = inset, oy = inset;
  const stem = { x0: ox + s * 0.34, x1: ox + s * 0.44, y0: oy + s * 0.24, y1: oy + s * 0.76 };
  const bowlCx = ox + s * 0.44, bowlCy = oy + s * 0.365, bowlRo = s * 0.155, bowlRi = s * 0.072;

  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const i = (y * size + x) * 4;

      // Rounded-square alpha mask for the whole tile
      const dx = Math.max(cr - x, x - (size - cr), 0);
      const dy = Math.max(cr - y, y - (size - cr), 0);
      const tileA = clamp01(cr - Math.hypot(dx, dy) + 0.5);

      // Letter "P" coverage
      let letter = 0;
      if (x >= stem.x0 - 1 && x <= stem.x1 + 1 && y >= stem.y0 - 1 && y <= stem.y1 + 1) {
        const ex = Math.max(stem.x0 - x, x - stem.x1, 0);
        const ey = Math.max(stem.y0 - y, y - stem.y1, 0);
        letter = Math.max(letter, clamp01(2 - Math.hypot(ex, ey)));
      }
      if (x >= bowlCx - 2) {
        const bd = Math.hypot(x - bowlCx, y - bowlCy);
        letter = Math.max(letter, Math.min(clamp01(bowlRo - bd + 0.75), clamp01(bd - bowlRi + 0.75)));
      }
      letter = Math.min(letter, 1);

      buf[i]     = FG[0] * letter + BG[0] * (1 - letter);
      buf[i + 1] = FG[1] * letter + BG[1] * (1 - letter);
      buf[i + 2] = FG[2] * letter + BG[2] * (1 - letter);
      buf[i + 3] = Math.round(tileA * 255);
    }
  }
  return encodePNG(size, buf);
}

// apple-touch-icon should be a full-bleed square (iOS rounds the corners itself),
// so render those without the transparent rounded mask.
function makeAppleIcon(size) {
  const buf = Buffer.alloc(size * size * 4);
  const stem = { x0: size * 0.34, x1: size * 0.44, y0: size * 0.24, y1: size * 0.76 };
  const bowlCx = size * 0.44, bowlCy = size * 0.365, bowlRo = size * 0.155, bowlRi = size * 0.072;
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const i = (y * size + x) * 4;
      let letter = 0;
      if (x >= stem.x0 - 1 && x <= stem.x1 + 1 && y >= stem.y0 - 1 && y <= stem.y1 + 1) {
        const ex = Math.max(stem.x0 - x, x - stem.x1, 0);
        const ey = Math.max(stem.y0 - y, y - stem.y1, 0);
        letter = Math.max(letter, clamp01(2 - Math.hypot(ex, ey)));
      }
      if (x >= bowlCx - 2) {
        const bd = Math.hypot(x - bowlCx, y - bowlCy);
        letter = Math.max(letter, Math.min(clamp01(bowlRo - bd + 0.75), clamp01(bd - bowlRi + 0.75)));
      }
      letter = Math.min(letter, 1);
      buf[i]     = FG[0] * letter + BG[0] * (1 - letter);
      buf[i + 1] = FG[1] * letter + BG[1] * (1 - letter);
      buf[i + 2] = FG[2] * letter + BG[2] * (1 - letter);
      buf[i + 3] = 255;
    }
  }
  return encodePNG(size, buf);
}

writeFileSync('public/icon-192.png', makeIcon(192, { padded: true }));
writeFileSync('public/icon-512.png', makeIcon(512, { padded: true }));
writeFileSync('public/apple-touch-icon.png', makeAppleIcon(180));
console.log('Wrote public/icon-192.png, public/icon-512.png, public/apple-touch-icon.png');

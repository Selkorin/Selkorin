'use strict';
// Упаковывает PNG-иконки (build/icons/icon_<size>.png) в build/icon.icns.
// Чистый Node, без нативных зависимостей — работает и на macOS при сборке.
const fs = require('fs');
const path = require('path');

const dir = path.join(__dirname, 'icons');
// OSType → размер (PNG-иконки, поддерживаются macOS 10.7+)
const MAP = [
  ['icp4', 16], ['icp5', 32], ['icp6', 64],
  ['ic07', 128], ['ic08', 256], ['ic09', 512], ['ic10', 1024],
  ['ic11', 32], ['ic12', 64], ['ic13', 256], ['ic14', 512],
];

const chunks = [];
for (const [type, size] of MAP) {
  const p = path.join(dir, `icon_${size}.png`);
  if (!fs.existsSync(p)) { console.warn('пропускаю (нет файла):', p); continue; }
  const png = fs.readFileSync(p);
  const header = Buffer.alloc(8);
  header.write(type, 0, 'ascii');
  header.writeUInt32BE(png.length + 8, 4); // длина = данные + 8-байтный заголовок
  chunks.push(header, png);
}

const body = Buffer.concat(chunks);
const fileHeader = Buffer.alloc(8);
fileHeader.write('icns', 0, 'ascii');
fileHeader.writeUInt32BE(body.length + 8, 4);
const icns = Buffer.concat([fileHeader, body]);

const out = path.join(__dirname, 'icon.icns');
fs.writeFileSync(out, icns);
console.log(`✓ ${out} — ${(icns.length / 1024).toFixed(1)} KB, элементов: ${chunks.length / 2}`);

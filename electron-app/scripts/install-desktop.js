#!/usr/bin/env node
// Installs Алакея as a desktop app on Linux (creates .desktop file)
const fs = require('fs');
const path = require('path');
const os = require('os');

const appDir = path.resolve(__dirname, '..');
const electronBin = path.join(appDir, 'node_modules', '.bin', 'electron');
const iconPath = path.join(appDir, 'assets', 'icon.png');

const desktopEntry = `[Desktop Entry]
Version=1.0
Type=Application
Name=Алакея
Comment=Умный голосовой ассистент
Exec=${electronBin} ${appDir} --no-sandbox --disable-gpu
Icon=${iconPath}
Terminal=false
Categories=Utility;AI;
StartupNotify=true
StartupWMClass=alakeia
`;

const homeDir = os.homedir();
const desktopDir = path.join(homeDir, '.local', 'share', 'applications');
const desktopFile = path.join(desktopDir, 'alakeia.desktop');

// Create directory if needed
fs.mkdirSync(desktopDir, { recursive: true });
fs.writeFileSync(desktopFile, desktopEntry);
fs.chmodSync(desktopFile, '755');

console.log(`✓ Desktop entry created: ${desktopFile}`);

// Also create a launch script in /usr/local/bin
const launchScript = `#!/bin/bash
cd "${appDir}"
exec "${electronBin}" . --no-sandbox --disable-gpu "$@"
`;

try {
  const binPath = '/usr/local/bin/alakeia';
  fs.writeFileSync(binPath, launchScript);
  fs.chmodSync(binPath, '755');
  console.log(`✓ Launch script created: ${binPath}`);
  console.log('  You can now run: alakeia');
} catch(e) {
  const localBin = path.join(homeDir, '.local', 'bin');
  fs.mkdirSync(localBin, { recursive: true });
  const binPath = path.join(localBin, 'alakeia');
  fs.writeFileSync(binPath, launchScript);
  fs.chmodSync(binPath, '755');
  console.log(`✓ Launch script created: ${binPath}`);
}

console.log('\n✓ Алакея установлена! Запустите: alakeia');

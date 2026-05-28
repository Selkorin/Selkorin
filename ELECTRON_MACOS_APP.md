# 🎬 Creating a Native macOS App with Electron (Optional)

Если вы хотите запустить приложение как полноценное нативное macOS приложение с иконкой в Dock, вы можете создать Electron оборочку.

## 📋 Требования для Electron версии

- Node.js 20.x
- npm 10.x
- macOS 10.15+
- 500 MB свободного места (для build)

## 🚀 Установка Electron версии

### Способ 1: Быстрая установка (Рекомендуется)

```bash
# 1. Установите Electron dependencies
npm install electron electron-builder --save-dev --workspace=apps/server

# 2. Создайте Electron главное окно
mkdir -p apps/electron
```

### Способ 2: Шаг за шагом

```bash
# В корневой директории проекта
npm install electron electron-builder --save-dev

# Создайте структуру
mkdir -p apps/electron/src
mkdir -p apps/electron/assets
```

## 📝 Создайте основной Electron файл

**`apps/electron/src/main.ts`**

```typescript
import { app, BrowserWindow, Menu } from 'electron';
import path from 'path';
import { spawn } from 'child_process';

let mainWindow: BrowserWindow | null = null;
let serverProcess: any = null;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1400,
    height: 900,
    minWidth: 1000,
    minHeight: 600,
    webPreferences: {
      preload: path.join(__dirname, 'preload.ts'),
      nodeIntegration: false,
      contextIsolation: true,
    },
    icon: path.join(__dirname, '../assets/icon.png'),
  });

  // Open DevTools in development
  if (process.env.NODE_ENV === 'development') {
    mainWindow.webContents.openDevTools();
  }

  // Load app
  const isDev = process.env.NODE_ENV === 'development';
  const url = isDev 
    ? 'http://localhost:5173' 
    : `file://${path.join(__dirname, '../dist/index.html')}`;

  mainWindow.loadURL(url);

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

function startBackendServer() {
  const serverPath = path.join(__dirname, '../../apps/server/dist/index.js');
  serverProcess = spawn('node', [serverPath], {
    stdio: 'inherit',
    cwd: path.join(__dirname, '../../apps/server'),
  });

  serverProcess.on('error', (err) => {
    console.error('Failed to start backend:', err);
  });
}

app.on('ready', () => {
  startBackendServer();
  
  // Wait for server to start
  setTimeout(() => {
    createWindow();
  }, 2000);
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('activate', () => {
  if (mainWindow === null) {
    createWindow();
  }
});

app.on('quit', () => {
  if (serverProcess) {
    serverProcess.kill();
  }
});

// Create menu
function createMenu() {
  const menu = [
    {
      label: 'Remote Support',
      submenu: [
        { role: 'about' },
        { type: 'separator' },
        { role: 'quit' },
      ],
    },
    {
      label: 'View',
      submenu: [
        { role: 'reload' },
        { role: 'forceReload' },
        { role: 'toggleDevTools' },
      ],
    },
  ];

  Menu.setApplicationMenu(Menu.buildFromTemplate(menu as any));
}

if (app.isReady()) {
  createMenu();
} else {
  app.on('ready', createMenu);
}
```

## ⚙️ Конфигурация для сборки

**`apps/electron/electron-builder.json`**

```json
{
  "appId": "com.remotesupport.app",
  "productName": "Remote Support",
  "directories": {
    "buildResources": "assets",
    "output": "dist"
  },
  "files": [
    "dist/**/*",
    "node_modules/**/*"
  ],
  "mac": {
    "target": [
      "dmg",
      "zip"
    ],
    "category": "public.app-category.utilities",
    "icon": "assets/icon.icns",
    "hardenedRuntime": true,
    "gatekeeperAssess": false
  },
  "dmg": {
    "contents": [
      {
        "x": 130,
        "y": 220,
        "type": "file"
      },
      {
        "x": 410,
        "y": 220,
        "type": "link",
        "path": "/Applications"
      }
    ]
  }
}
```

## 🎨 Создайте иконку приложения

1. Создайте иконку 1024x1024 px в Figma или используйте существующую
2. Сохраните как `apps/electron/assets/icon.png`
3. Для macOS нужен ICNS формат, создайте его:

```bash
# Используя ImageMagick
convert apps/electron/assets/icon.png apps/electron/assets/icon.icns

# Или используйте онлайн конвертер
```

## 📦 Сборка приложения

### Сборка для разработки

```bash
# Compile backend
npm run build --workspace=apps/server

# Compile frontend
npm run build --workspace=apps/web

# Build Electron app
electron-builder --mac --publish never
```

### Сборка для продакшена

```bash
# Full build
npm run build

# Package as DMG for distribution
electron-builder --mac -p always
```

## 🚀 Запуск Electron версии

```bash
# Режим разработки (с hot reload)
npm run electron:dev

# Production версия
npm run electron:start
```

## 📝 Добавьте скрипты в package.json

**`package.json`**

```json
{
  "scripts": {
    "electron:dev": "electron apps/electron/dist/main.js",
    "electron:build": "tsc --project apps/electron/tsconfig.json && npm run build --workspaces",
    "electron:start": "electron-builder --mac --publish never"
  }
}
```

## 📂 Результирующая структура

```
apps/electron/
├── src/
│   ├── main.ts
│   ├── preload.ts
│   └── tsconfig.json
├── assets/
│   ├── icon.png
│   └── icon.icns
├── dist/
│   └── main.js (скомпилировано)
├── electron-builder.json
└── package.json
```

## ✅ Результат

После сборки вы получите:
- `dist/Remote\ Support-1.0.0.dmg` - инсталлятор для распространения
- `dist/Remote Support.app` - приложение для macOS

Пользователи просто откроют DMG файл и перетащат приложение в Applications.

## 🎯 Улучшения для production

```typescript
// Коды подписи и нотариации для macOS
{
  "mac": {
    "certificateFile": "path/to/certificate.p12",
    "certificatePassword": "password",
    "notarize": {
      "teamId": "ABC1234567"
    }
  }
}
```

## 📚 Полезные ссылки

- [Electron Documentation](https://www.electronjs.org/docs)
- [Electron Builder](https://www.electron.build/)
- [macOS App Distribution](https://developer.apple.com/macos/distribution/)

## 💡 Советы

- Убедитесь что бэкенд скомпилирован перед сборкой
- Используйте electron-builder для автоматической сборки
- Тестируйте DMG файл перед распространением
- Добавьте обновления через electron-updater

## 🔧 Troubleshooting Electron

### "Cannot find module"
```bash
# Пересоздайте node_modules
rm -rf node_modules
npm install --legacy-peer-deps
```

### Приложение не запускается
```bash
# Запустите с логами
electron apps/electron/dist/main.js --debug
```

### DMG не создается
```bash
# Убедитесь что иконка существует
ls -la apps/electron/assets/icon.icns

# Пересоздайте иконку если нужно
```

---

**На этом этапе у вас есть полноценное нативное macOS приложение!** 🎉

Для основного использования просто следуйте инструкциям в [START_HERE_MACOS.md](./START_HERE_MACOS.md).

Electron версия - это опциональное улучшение для более полированного пользовательского опыта.

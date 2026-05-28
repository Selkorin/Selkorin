import { app, BrowserWindow, Menu, ipcMain, dialog } from 'electron'
import path from 'path'
import { spawn, ChildProcess } from 'child_process'
import * as fs from 'fs'

let mainWindow: BrowserWindow | null = null
let serverProcess: ChildProcess | null = null
const isDev = process.env.NODE_ENV === 'development'

// Запуск backend сервера
function startBackendServer(): Promise<void> {
  return new Promise((resolve, reject) => {
    const backendPath = path.join(app.getAppPath(), 'resources', 'backend')
    const indexPath = path.join(backendPath, 'dist', 'index.js')

    // Dev режим - запускаем из исходной директории
    let execPath = isDev
      ? path.join(__dirname, '../apps/server/dist/index.js')
      : indexPath

    console.log('Starting backend from:', execPath)

    // Убедитесь что файл существует
    if (!fs.existsSync(execPath)) {
      console.error('Backend file not found:', execPath)
      reject(new Error('Backend not found'))
      return
    }

    serverProcess = spawn('node', [execPath], {
      cwd: isDev
        ? path.join(__dirname, '../apps/server')
        : path.join(app.getAppPath(), 'resources', 'backend'),
      stdio: isDev ? 'inherit' : 'pipe',
      env: {
        ...process.env,
        NODE_ENV: isDev ? 'development' : 'production',
        PORT: '3000',
        DATABASE_URL: 'file:./dev.db'
      }
    })

    serverProcess.on('error', (err) => {
      console.error('Backend error:', err)
      reject(err)
    })

    // Даем серверу время на запуск
    setTimeout(() => {
      resolve()
    }, 2000)
  })
}

// Создание главного окна
function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1400,
    height: 900,
    minWidth: 1000,
    minHeight: 600,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: path.join(__dirname, 'preload.js')
    },
    icon: isDev
      ? undefined
      : path.join(__dirname, '../assets/icon.png')
  })

  const startUrl = isDev
    ? 'http://localhost:5173'
    : `file://${path.join(__dirname, '../dist/index.html')}`

  mainWindow.loadURL(startUrl)

  if (isDev) {
    mainWindow.webContents.openDevTools()
  }

  mainWindow.on('closed', () => {
    mainWindow = null
  })

  // Обработка ошибок загрузки
  mainWindow.webContents.on('did-fail-load', () => {
    setTimeout(() => {
      if (mainWindow) {
        mainWindow.reload()
      }
    }, 1000)
  })
}

// Создание меню
function createMenu() {
  const template: any = [
    {
      label: 'Remote Support',
      submenu: [
        {
          label: 'About Remote Support',
          click: () => {
            dialog.showMessageBox(mainWindow!, {
              type: 'info',
              title: 'About Remote Support',
              message: 'Remote Support Application',
              detail: 'A secure remote support tool for macOS\n\nVersion 1.0.0\n\n© 2024'
            })
          }
        },
        { type: 'separator' },
        { role: 'quit', label: 'Quit' }
      ]
    },
    {
      label: 'Edit',
      submenu: [
        { role: 'undo' },
        { role: 'redo' },
        { type: 'separator' },
        { role: 'cut' },
        { role: 'copy' },
        { role: 'paste' }
      ]
    },
    {
      label: 'View',
      submenu: [
        { role: 'reload' },
        { role: 'forceReload' },
        { role: 'toggleDevTools' },
        { type: 'separator' },
        { role: 'resetZoom' },
        { role: 'zoomIn' },
        { role: 'zoomOut' }
      ]
    }
  ]

  Menu.setApplicationMenu(Menu.buildFromTemplate(template))
}

// Обработка запуска приложения
app.on('ready', async () => {
  try {
    await startBackendServer()
    createWindow()
    createMenu()
  } catch (error) {
    console.error('Failed to start application:', error)
    dialog.showErrorBox('Error', 'Failed to start application')
    app.quit()
  }
})

// Закрытие всех окон -> выход
app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit()
  }
})

// Re-create window при активации (macOS)
app.on('activate', () => {
  if (mainWindow === null) {
    createWindow()
  }
})

// Завершение работы
app.on('quit', () => {
  if (serverProcess) {
    serverProcess.kill()
  }
})

// IPC обработчики (если нужны)
ipcMain.handle('get-app-version', () => app.getVersion())
ipcMain.handle('get-app-path', () => app.getAppPath())

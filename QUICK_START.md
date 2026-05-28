# 🚀 Remote Support Application - Quick Start

## ⚡ Get Running in 2 Minutes

### 1️⃣ Setup
```bash
./setup-macos.sh
```

### 2️⃣ Run
```bash
./start-macos.sh
```

**Done!** App opens at http://localhost:5173

---

## 📖 What is This?

A secure web app for remote device support. Designed with explicit user consent:

✅ **For Operator (on Mac)**
- Create QR code
- See connected devices
- View device info (model, OS, browser)
- Stream device screen
- Send guidance to user

✅ **For User (on Phone)**
- Scan QR to connect
- See "Active Session" banner
- Can disconnect anytime
- Control what operator sees

✅ **Security**
- No hidden access
- No fingerprint spoofing
- Explicit confirmations
- Full audit trail

---

## 📁 Choose Your Path

### 🌐 Web Version (Recommended for Most)
- **File**: [START_HERE_MACOS.md](./START_HERE_MACOS.md)
- **Run**: `./start-macos.sh`
- **Port**: http://localhost:5173
- **Pro**: No installation needed

### 🎬 Native macOS App (Optional)
- **File**: [ELECTRON_MACOS_APP.md](./ELECTRON_MACOS_APP.md)
- **Creates**: Native .app & .dmg installer
- **Pro**: Looks like native macOS app in Dock
- **Con**: More setup steps

---

## 🎯 How It Works (30 seconds)

```
Mac                          Phone
 │                            │
 ├─ Click "Create QR"        │
 │    ↓                        │
 │  [Shows QR Code] ──────→  Camera scans
 │                            ↓
 │                        [Confirmation modal]
 │                            ↓
 │    ← Device connects ──────┤
 │    (WebRTC stream)         │
 │                            │
 ├─ Click "Start Screen"     │
 │                            ├─ [Permission prompt]
 │                            │
 │    ← Stream video ─────────┤
 │    │                       │
 └─ See screen               └─ Active session visible
```

---

## 📋 System Requirements

- **macOS** 10.15+
- **Node.js** 20.x ([Install](https://nodejs.org/) or `brew install node@20`)
- **npm** 10.x (comes with Node.js)

Check if installed:
```bash
node --version    # should be v20.x.x
npm --version     # should be 10.x.x
```

---

## 🚀 Installation

### Automatic Setup
```bash
./setup-macos.sh
```

This:
- ✅ Checks Node.js
- ✅ Installs packages
- ✅ Creates database
- ✅ Asks to start app

### Manual Setup (if script fails)
```bash
npm install --legacy-peer-deps
npm run db:push --workspace=apps/server
./start-macos.sh
```

---

## 💬 Usage

### Create Connection
1. Click **"Создать QR"** button (top right)
2. QR code appears
3. Share instructions with phone user

### Connect Device
1. **Phone**: Scan QR with camera app
2. **Phone**: Click notification/link
3. **Phone**: Tap **"Разрешить"** (Allow)
4. **Mac**: Device appears in list

### View Device
1. Click device card
2. See info: model, OS, browser, resolution
3. Click **"Запустить экран"** (Start Screen)
4. Phone confirms
5. Live stream appears!

---

## 🔗 URLs

| Service | URL |
|---------|-----|
| **App** | http://localhost:5173 |
| **API** | http://localhost:3000 |
| **Database** | ./apps/server/dev.db |

---

## 🛑 Troubleshooting

### "Port already in use"
```bash
./start-macos.sh  # Auto-cleans ports
```

### "Module not found"
```bash
rm -rf node_modules
npm install --legacy-peer-deps
./start-macos.sh
```

### "Database error"
```bash
rm -f apps/server/dev.db
npm run db:push --workspace=apps/server
./start-macos.sh
```

### App won't open in browser
Manually visit: http://localhost:5173

### More help?
See: [START_HERE_MACOS.md](./START_HERE_MACOS.md) (Troubleshooting section)

---

## 📚 Documentation

| Document | Purpose |
|----------|---------|
| [START_HERE_MACOS.md](./START_HERE_MACOS.md) | Complete macOS guide (recommended) |
| [MACOS_SETUP.md](./MACOS_SETUP.md) | Detailed setup & configuration |
| [ELECTRON_MACOS_APP.md](./ELECTRON_MACOS_APP.md) | Native app with Electron |
| [README_REMOTE_SUPPORT.md](./README_REMOTE_SUPPORT.md) | Full technical docs |

---

## 🎯 Next Steps

**Right Now:**
```bash
./setup-macos.sh
```

**Then:**
```bash
./start-macos.sh
```

**Enjoy!** 🎉

---

## ❓ FAQ

**Q: Can I use this on iPhone/Android?**
A: Yes! Phone must be on same Wi-Fi. Scan QR from any camera.

**Q: Is it secure?**
A: Yes! Explicit permission model. Phone sees banner "Active Session". Can disconnect anytime.

**Q: Do I need internet?**
A: No! Works entirely on local Wi-Fi. No cloud needed.

**Q: Can I use on multiple phones?**
A: Yes! Create multiple QR codes, connect many devices.

**Q: Can I share screen to friends?**
A: No, designed for operator support only. Would need separate instance for sharing.

**Q: How do I uninstall?**
A: Just delete the folder. Everything is local.

**Q: Can I build a native app?**
A: Yes! See [ELECTRON_MACOS_APP.md](./ELECTRON_MACOS_APP.md)

---

## 💡 Pro Tips

- **Local IP**: For testing on real phones, use your Mac's local IP instead of localhost
  ```bash
  ifconfig | grep "inet " | grep -v 127
  ```

- **Database Viewer**: 
  ```bash
  npm run db:studio --workspace=apps/server
  ```

- **Dev Tools**: Press F12 in app to see console

- **Restart Fast**: Just Ctrl+C then `./start-macos.sh` again

---

## 🎓 Architecture

**Backend** (Node.js + Express)
- Manages connections
- WebRTC signaling
- Audit logging
- SQLite database

**Frontend** (React + Vite)
- Beautiful dashboard
- QR code generation
- Device management
- Live streaming

**Mobile** (Web + WebRTC)
- Permission prompts
- Active session banner
- Video streaming
- Disconnect button

---

## 🔐 Security Features

✅ Explicit QR-based consent  
✅ Visible active session on device  
✅ Phone controls permissions  
✅ No recording without approval  
✅ All actions logged  
✅ Works only on local Wi-Fi  
✅ One-time pairing tokens  
✅ 5-minute token expiry  

---

**Ready? Let's go!**

```bash
./setup-macos.sh && ./start-macos.sh
```

Have questions? See [START_HERE_MACOS.md](./START_HERE_MACOS.md) 📖

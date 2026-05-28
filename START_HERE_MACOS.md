# 🚀 Remote Support App - Start Here (macOS)

## 🎯 Quickest Way (2 Steps)

### 1️⃣ First Time Setup
```bash
./setup-macos.sh
```
This will:
- ✅ Check Node.js installation
- ✅ Install dependencies
- ✅ Create database
- ✅ Ask if you want to start now

### 2️⃣ Run Application
```bash
./start-macos.sh
```
This will:
- ✅ Start backend (port 3000)
- ✅ Start frontend (port 5173)
- ✅ Open app in your browser
- ✅ Show you the next steps

**That's it! The app will open automatically.** 🎉

---

## 📖 Full Guide

### Prerequisites
- **macOS** 10.15 or newer
- **Node.js** 20.x (check with `node --version`)

### Step-by-Step

**1. Clone & Navigate**
```bash
cd /path/to/your/Selkorin
```

**2. Run Setup**
```bash
chmod +x setup-macos.sh  # First time only
./setup-macos.sh
```

**3. Start the App**
```bash
./start-macos.sh
```

**4. Open in Browser**
- Should open automatically at `http://localhost:5173`
- If not, click: [Open App](http://localhost:5173)

---

## 🎮 How to Use

### Create Connection (on Mac)
1. Click **"Создать QR"** (Create QR)
2. A QR code appears
3. Share instructions with phone user

### Connect Phone
1. Open camera app on phone
2. Scan the QR code
3. Tap to open link
4. Click **"Разрешить подключение"** (Allow Connection)
5. Device appears in your app!

### View & Control
1. Click device card to open profile
2. See device info (model, OS, browser)
3. Click **"Запустить экран телефона"** (Start Screen)
4. Phone approves screen sharing
5. See live stream in app

---

## 🛑 Troubleshooting

### "Port 3000/5173 already in use"
```bash
# Kill existing processes
lsof -ti:3000 | xargs kill -9
lsof -ti:5173 | xargs kill -9

# Then restart
./start-macos.sh
```

### "Cannot find module"
```bash
# Reinstall dependencies
rm -rf node_modules
npm install --legacy-peer-deps
./start-macos.sh
```

### "Database error"
```bash
# Recreate database
rm -f apps/server/dev.db
npm run db:push --workspace=apps/server
./start-macos.sh
```

### App won't open in browser
Manually open: `http://localhost:5173`

### WebSocket connection fails
- Ensure backend is running (check http://localhost:3000)
- Check browser console for errors (press F12)
- Restart both servers with `./start-macos.sh`

---

## 🔗 URLs

| Service | URL | Notes |
|---------|-----|-------|
| **Frontend** | http://localhost:5173 | Main app (opens in browser) |
| **Backend API** | http://localhost:3000 | API endpoints |
| **Database** | `./apps/server/dev.db` | SQLite file |

---

## 💡 Pro Tips

### Test with Multiple Phones
All in same Wi-Fi:
1. Get your Mac's local IP:
   ```bash
   ifconfig | grep "inet " | grep -v 127
   ```
2. Use that IP in phones browser instead of localhost

### View Database
```bash
npm run db:studio --workspace=apps/server
```
Opens visual database editor

### Check Logs
Backend logs appear in Terminal 1
Frontend logs appear in Terminal 2

### Faster Restart
Just press Ctrl+C and run `./start-macos.sh` again

---

## 📱 Mobile Testing

### On Your Phone (iOS/Android)
1. **Same Wi-Fi**: Must be on same network as Mac
2. **Create QR**: Click button on Mac
3. **Scan**: Use phone camera
4. **Allow**: Tap permission request
5. **Stream**: Phone screen appears on Mac

### From Another Device
1. Get Mac's IP (see above)
2. Share link: `http://[YOUR-IP]:5173/join/[QR-TOKEN]`
3. Other device scans or opens link
4. Same process as above

---

## 🔒 Security Notes

✅ **All connections are encrypted**
✅ **Phone controls what Mac can see**
✅ **Visible "Active Session" banner on phone**
✅ **No recording without permission**
✅ **All actions logged**
✅ **Works only in local Wi-Fi**

---

## 📚 Need More Info?

- **Detailed Setup**: See [`MACOS_SETUP.md`](./MACOS_SETUP.md)
- **Full Docs**: See [`README_REMOTE_SUPPORT.md`](./README_REMOTE_SUPPORT.md)
- **API Docs**: See [`API.md`](./API.md)

---

## ⚡ Quick Commands Reference

```bash
# Start everything
./start-macos.sh

# Start backend only
npm run dev --workspace=apps/server

# Start frontend only
npm run dev --workspace=apps/web

# Check types
npm run typecheck

# Build for production
npm run build

# Clean & reinstall
rm -rf node_modules && npm install --legacy-peer-deps

# View database
npm run db:studio --workspace=apps/server
```

---

## 🎓 Architecture

```
Your Mac runs TWO servers:

Backend (Node.js)
├─ Manages connections
├─ Stores device info
├─ Handles WebRTC signaling
└─ Logs all events

Frontend (React)
├─ Beautiful dashboard
├─ QR code generation
├─ Device management
└─ Live screen streaming
```

Phone connects to these servers:
1. Scans QR → Joins session
2. Confirms permission → Authenticated
3. Streams video → WebRTC
4. You can see & control

---

## 🚀 Next Steps

1. ✅ Run `./setup-macos.sh`
2. ✅ Run `./start-macos.sh`
3. ✅ Create QR code
4. ✅ Scan from phone
5. ✅ Start streaming
6. 🎉 Done!

**Enjoy your remote support app!**

---

## 📞 Got Stuck?

1. Check Terminal output (might show errors)
2. Try `./start-macos.sh` again
3. Look at troubleshooting section above
4. Check browser console (F12)
5. Restart Node.js if needed

**Most issues resolve by:** 
```bash
./start-macos.sh
```

---

**Questions? Stuck? Feel free to check the detailed guides above.** 

Happy testing! 🎉

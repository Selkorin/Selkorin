# SelkorinCam

A macOS lab/test app for:

1. **Receiving and recording your phone's camera** on your Mac (live view +
   recording to H.264 MOV or a JPEG sequence).
2. **Inventorying IP cameras on a network you own or are authorized to test**
   (ONVIF WS-Discovery, Bonjour/mDNS, and a bounded TCP port probe of your local
   /24).
3. **Passively summarizing camera-related traffic** on that network (read-only
   flow metadata via `tcpdump`).

> ⚠️ **Read [`Docs/AUTHORIZED_USE.md`](Docs/AUTHORIZED_USE.md) first.** The
> discovery and analysis features touch other devices. Use them only on
> networks and cameras you own, or have **explicit written authorization** to
> test. The app gates those features behind an on-screen acknowledgement and
> keeps an activity log so an authorized engagement has an audit trail.

## What it deliberately does not do

To keep this a defensive / authorized-testing tool rather than an attack tool,
the following are intentionally **not** implemented: WiFi deauth/DoS, WPA
handshake capture or cracking, camera password brute-forcing / default-credential
spraying, firmware CVE exploitation, and any covert / anti-detection behavior.
See `Docs/AUTHORIZED_USE.md` for the responsible camera-audit checklist and
which established tools to use for deeper authorized testing.

## Requirements

- macOS 13+
- Xcode 15+ (or a Swift 5.9 toolchain) to build
- For traffic analysis: `tcpdump` (ships with macOS) and BPF access
  (run with sufficient privileges, same as Wireshark)

## Build & run

```bash
cd macos-remote-camera
swift build -c release
swift run SelkorinCam
```

Or open `Package.swift` in Xcode and run the **SelkorinCam** scheme.

For the camera preview to appear you must grant the app the usual macOS
permissions the first time (Camera is not needed on the Mac side — the phone
is the camera; the Mac only receives frames over the network).

## Streaming your phone → Mac

There are two paths. Pick based on what's easiest for your phone.

### A. MJPEG pull (most reliable, recommended)

1. Install any "IP webcam" style app on the phone that exposes an **MJPEG**
   endpoint (e.g. `http://<phone-ip>:8080/video`). These apps access the camera
   natively and handle the secure-context issue for you.
2. In SelkorinCam → **Live Camera** → *Mac pulls MJPEG*, paste the URL and
   **Connect**.
3. **Start recording** to save an H.264 MOV or JPEG frames.

### B. Browser push (no app install)

1. In SelkorinCam → **Live Camera** → *Phone pushes to Mac*, note the shown
   address, e.g. `http://192.168.1.10:8099`, and **Start server**.
2. Open `PhoneClient/index.html` on the phone, set the target to that address,
   and **Start streaming**.

> **Secure-context caveat:** mobile browsers only allow camera access
> (`getUserMedia`) from a **secure context** — HTTPS or `localhost`. Loading the
> page over plain `http://<phone-ip>` will block the camera. To use browser
> push you need to serve `PhoneClient/index.html` over HTTPS (e.g. a local
> HTTPS dev server or a tunnel). If that's inconvenient, use **path A**.

### About "phone screen off, camera still streaming"

- **Browser (path B):** the OS pauses camera capture when the screen fully
  locks. A wake-lock keeps it going with the screen *dimmed*, but not fully off.
- **Native app (path A):** on **Android**, an IP-webcam app running a foreground
  service can keep the camera on with the screen off. On **iOS**, third-party
  apps cannot keep the camera running in the background — Apple restricts it.

So "screen fully off + camera streaming" is achievable on Android with a native
foreground-service app, not in a browser and not on iOS. This project focuses on
the Mac receiver + recorder and works with whichever phone-side method your
device supports.

## Camera discovery (authorized networks only)

**Discovery** tab → acknowledge the notice → confirm/adjust the subnet
(defaults to your Mac's own /24) → **Scan**. It merges:

- **ONVIF WS-Discovery** — multicast SOAP probe; conformant cameras reply with
  service URLs and scopes.
- **Bonjour/mDNS** — browses `_rtsp`, `_onvif`, `_http`, etc.
- **TCP port probe** — normal connect scan of common camera ports on your /24.

Select a device to see its open ports, vendor guess, and advertised service
URLs. To view a stream, use its RTSP/ONVIF URL with credentials **you** already
have (e.g. in VLC). The tool never guesses or brute-forces credentials.

## Traffic analysis (authorized networks only)

**Traffic Analysis** tab → acknowledge → set interface (e.g. `en0`) and BPF
filter → **Start**. It runs `tcpdump` in quiet mode with a tiny snap length and
rolls packets up into per-flow summaries (endpoints, ports, protocol, packet/
byte counts). Payloads are never decoded or stored. Needs BPF privileges.

## Layout

```
macos-remote-camera/
├── Package.swift
├── Sources/SelkorinCam/
│   ├── SelkorinCamApp.swift        app entry + shared state
│   ├── Models/                     data types
│   ├── Streaming/                  push server, MJPEG client, recorder, session
│   ├── Discovery/                  ONVIF, Bonjour, port scan, coordinator
│   ├── Analysis/                   passive tcpdump flow summarizer
│   ├── Views/                      SwiftUI tabs
│   └── Util/                       logging, local-network helpers
├── PhoneClient/index.html          browser camera → Mac streamer
└── Docs/                           authorized-use guidance, architecture
```

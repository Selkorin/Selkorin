# Architecture

SelkorinCam is a single SwiftUI app (SPM executable target) split into four
concerns, each behind a tab.

## Data flow: phone camera → Mac

```
                 path A (pull)                       path B (push)
 phone IP-webcam app  ──MJPEG──►  MJPEGClient   browser getUserMedia ──HTTP POST──►  StreamServer
                                       │                                                  │
                                       └──────────► CameraSession.ingest(jpeg) ◄──────────┘
                                                          │
                                    ┌─────────────────────┼─────────────────────┐
                                    ▼                                            ▼
                            latestImage (NSImage)                         FrameRecorder
                            → LiveCameraView preview                      → H.264 MOV / JPEG seq
```

- **`StreamServer`** (`Streaming/StreamServer.swift`) — minimal HTTP/1.1 server
  on `NWListener`. Accepts `POST /frame` (JPEG body) and a health check. CORS is
  open so the browser client can post cross-origin. Keep-alive connections are
  parsed by a small per-connection buffer that handles Content-Length bodies and
  pipelined requests.
- **`MJPEGClient`** (`Streaming/MJPEGClient.swift`) — `URLSession` streaming
  delegate that splits a `multipart/x-mixed-replace` body into frames by
  scanning for JPEG SOI (`FFD8`)/EOI (`FFD9`) markers. Supports HTTP Basic auth
  for cameras the user has credentials for.
- **`FrameRecorder`** (`Streaming/FrameRecorder.swift`) — decodes each JPEG to a
  `CGImage`, renders into a BGRA `CVPixelBuffer`, and appends to an
  `AVAssetWriter` H.264 movie with wall-clock-derived timestamps (frames arrive
  with network jitter, so timing is not assumed fixed). Alternatively writes a
  numbered JPEG sequence.
- **`CameraSession`** (`Streaming/CameraSession.swift`) — `@MainActor` view
  model wiring a source to the preview and recorder, and measuring FPS.

## Discovery

`DiscoveryCoordinator` runs three backends in parallel and merges results by IP:

- **`OnvifDiscovery`** — sends the standard WS-Discovery `Probe` SOAP message to
  `239.255.255.250:3702` over UDP and parses `ProbeMatch` replies (XAddrs,
  Scopes). This is the same mechanism ONVIF Device Manager uses.
- **`BonjourBrowser`** — `NetServiceBrowser` over camera-related service types,
  resolving each to an IPv4 address.
- **`PortScanner`** — bounded async TCP *connect* scan (normal handshakes, no
  raw/SYN tricks) of the local /24 for camera-ish ports, with a short optional
  banner read (metadata only).

`CameraFingerprint` holds the port/banner knowledge used to label devices and
rank likely cameras first. Scope is intentionally the local /24
(`LocalNetwork.hostsIn(cidr:)` only expands /24) to keep sweeps small and local.

## Passive analysis

`PacketAnalyzer` shells out to `/usr/sbin/tcpdump` with `-q` (quiet, headers
only) and `-s 96` (tiny snap length), plus a camera-port BPF filter. It parses
quiet-mode lines into per-flow rollups (`TrafficFlow`). It never parses,
decodes, stores, or displays payload — only endpoints, ports, protocol, and
packet/byte counts. Requires BPF privileges, like Wireshark.

## Safety model

- Network features are gated behind `AuthorizationGateView`, backed by an
  `authorized` flag on each coordinator; scans/captures refuse to run until the
  operator acknowledges ownership/authorization.
- `AppLog` keeps an in-app, timestamped activity log so an authorized engagement
  has an audit trail of exactly what ran.
- No credential attacks, exploits, DoS, or covert behavior exist anywhere in the
  codebase — see `AUTHORIZED_USE.md`.

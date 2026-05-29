# Jellyswarrm

> A modern, native Apple client for [Jellyfin](https://jellyfin.org) — built with SwiftUI, designed for iOS, iPadOS, tvOS, and macOS.

[![CI](https://github.com/jellyswarrm/Jellyswarrm/actions/workflows/ci.yml/badge.svg)](https://github.com/jellyswarrm/Jellyswarrm/actions/workflows/ci.yml)
[![License: LGPL v2.1](https://img.shields.io/badge/License-LGPLv2.1-blue.svg)](LICENSE)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2017%20%7C%20iPadOS%2017%20%7C%20tvOS%2017%20%7C%20macOS%2014-lightgrey.svg)](#requirements)

---

## ⚠️ Branch Information

- **`v2-clean-architecture`** (default) — Active development. UIKit shell on tvOS, VLCKit integration via CocoaPods, clean rebuild.
- **`abandoned/v1`** — Previous SwiftUI-only approach. Abandoned due to tvOS `NavigationStack` limitations causing persistent ghost-title and double-dismiss bugs. Preserved for reference only.

## Setup

1. Clone the repo and check out `v2-clean-architecture`:
   ```bash
   git clone https://github.com/khaos-adv-llc/Jellyswarrm.git
   cd Jellyswarrm
   git checkout v2-clean-architecture
   ```
2. Install CocoaPods if you don't have it:
   ```bash
   sudo gem install cocoapods
   ```
3. Run `pod install` in the repo root — this fetches **MobileVLCKit** (iOS), **TVVLCKit** (tvOS), and **VLCKit** (macOS):
   ```bash
   pod install
   ```
4. Open **`Jellyswarm.xcworkspace`** — **NOT** `Jellyswarm.xcodeproj`. Only the workspace includes the VLC pods.
5. Select your target platform and build.

> ⚠️ Pre-`pod install`, the VLC engine is unavailable: `PlaybackEngine.vlcAvailable` returns `false` and `PlaybackEngineResolver` falls back to AVFoundation. The project still builds and runs without VLC, but HDR10/HLG/DV-Profile-7 routing and exotic-container playback all require the pods.

---

## Overview

Jellyswarrm is a full-featured, open-source media client for Jellyfin servers. It is designed from the ground up with modern Swift — no Flutter, no Electron, no cross-platform compromises. Every platform gets a native experience that feels at home on the device.

**Key goals:**

- **Modern design** — fluid animations, adaptive layouts, dark-first UI that doesn't look like a port
- **Full tvOS multi-user support** — each Apple TV profile gets its own isolated session; Quick Connect removes the need for a keyboard
- **Jellyseerr / Overseerr integration** — a dedicated Discover tab lets users browse trending content, see what's on the server, and request missing titles
- **Security-first** — credentials stored in the system Keychain with proper per-user isolation on tvOS; no plaintext, no third-party analytics

---

## Screenshots

<!-- TODO: Add screenshots once UI polish phase is complete -->
*Screenshots coming soon.*

---

## Features

### Media Playback
- Direct play and HLS transcoding via Jellyfin's adaptive bitrate API
- Full playback reporting (start, progress, stop) for resume and watched state sync
- Per-user watch history and "Continue Watching"
- Subtitle and audio track selection

### Library
- Browse all Jellyfin libraries (Movies, TV Shows, Music, etc.)
- Search across the entire server
- "Next Up" for in-progress TV series

### Discover (Jellyseerr / Overseerr)
- Browse trending movies and TV shows — both on-server and off-server content
- Request missing titles directly from the app
- View request status (pending, approved, available)
- Supports all three Seerr auth modes: API key, Jellyfin credentials, local account

### tvOS Multi-User
- Detects Apple TV profile switches automatically
- Shows a server selection screen for new profiles with existing server configs
- **Quick Connect** as the primary login path — displays a short code, no keyboard needed
- Password login as fallback
- Per-user Keychain isolation — tokens and session cookies are never shared between profiles
- Automatic Seerr re-authentication after profile switch (Jellyfin creds mode auto-carries; local account prompts once)

### Platforms
| Platform | Min Version | Notes |
|----------|------------|-------|
| iPhone (iOS) | 17.0 | Full feature set |
| iPad (iPadOS) | 17.0 | Adaptive split-view layout |
| Apple TV (tvOS) | 17.0 | Focus engine UI, multi-user |
| Mac (macOS) | 14.0 Sonoma | Native window, menu bar |

---

## Requirements

- **Xcode** 16.0 or later
- **Swift** 6.0 or later
- **macOS** 14.0+ to build
- **Apple Developer Account** (free works for simulator; paid required for device and tvOS)
- A running **Jellyfin** server (10.8+)
- Optionally: **Jellyseerr** or **Overseerr** for the Discover tab

---

## Getting Started

### 1. Clone

```bash
git clone https://github.com/jellyswarrm/Jellyswarrm.git
cd Jellyswarrm
```

### 2. Open in Xcode

```bash
open project/Package.swift
```

Xcode will resolve the Swift Package and index the project automatically.

### 3. Select a scheme and destination

Choose the scheme for your target platform from the toolbar (iOS, tvOS, macOS) and select a simulator or connected device.

### 4. Build and run

`⌘R` — that's it. No CocoaPods, no Carthage, no third-party setup.

### tvOS — Additional Xcode capabilities

The tvOS target requires two capabilities that must be added manually in **Xcode → Signing & Capabilities** for the tvOS target:

1. **User Management** → check "Runs as Current User"  
   *(enables per-tvOS-profile Keychain isolation)*
2. **App Groups** → add `group.com.jellyswarrm.shared`  
   *(enables shared server config discovery across profiles)*

These are bound to your provisioning profile and are not committed to source control.

---

## Architecture

Jellyswarrm is a Swift Package with two library targets:

```
project/
├── Sources/
│   ├── JellyswarrmCore/          # Platform-agnostic logic
│   │   ├── Models/               # Jellyfin + Seerr data models
│   │   ├── Networking/           # API clients (actor-isolated)
│   │   │   ├── JellyfinAPIClient.swift
│   │   │   ├── SeerrAPIClient.swift
│   │   │   └── KeychainManager.swift
│   │   ├── State/                # @Observable view models
│   │   └── Extensions/
│   └── JellyswarrmUI/            # SwiftUI views (all platforms)
│       ├── JellyswarrmApp.swift  # App entry point + RootView routing
│       ├── Views/
│       │   ├── Home/
│       │   ├── Library/
│       │   ├── Discover/         # Seerr integration
│       │   ├── Search/
│       │   ├── Player/
│       │   ├── Settings/
│       │   └── Login/            # Includes tvOS-specific views
│       └── Components/
└── Tests/
    └── JellyswarrmCoreTests/
```

### Key design decisions

| Decision | Rationale |
|----------|-----------|
| Full SwiftUI (no Flutter) | Flutter has no tvOS App Store support; SwiftUI is native on all 4 platforms |
| `actor` for API clients | Thread-safe without locks; composable with `async/await` |
| `@Observable` (not `ObservableObject`) | Swift 5.9 Observation — more efficient, no `@Published` boilerplate |
| Shared vs per-user Keychain | tvOS multi-user requirement: server configs shared, tokens isolated |
| Zero third-party dependencies | Smaller attack surface; no supply chain risk; pure SPM |
| LGPL v2.1 | Compatible with VLCKit and other LGPL libraries while permitting linking from App Store binaries |

---

## Seerr Integration

Jellyswarrm supports three Seerr authentication modes:

| Mode | Behavior |
|------|----------|
| **API Key** | Device-wide; stored in shared Keychain; no per-user action needed |
| **Jellyfin Credentials** | Per-user; auto-carried when logging in with username+password; prompts once if Quick Connect was used |
| **Local Account** | Per-user; prompts for Seerr email + password once per tvOS profile |

Session cookies are stored in the per-user Keychain partition and are isolated between tvOS profiles.

---

## Contributing

Contributions are welcome and appreciated. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a PR.

**Quick start:**

1. [Fork](https://github.com/jellyswarrm/Jellyswarrm/fork) the repo
2. Create a branch: `git checkout -b feat/your-feature`
3. Make your changes and `swift test`
4. Open a Pull Request

For bugs, use the [Bug Report template](../../issues/new?template=bug_report.md).  
For features, use the [Feature Request template](../../issues/new?template=feature_request.md).  
For questions, use [Discussions](../../discussions).

---

## Security

Please **do not** open public issues for security vulnerabilities. See [SECURITY.md](SECURITY.md) for the responsible disclosure process.

---

## License

Jellyswarrm is licensed under the **GNU Lesser General Public License v2.1 (or later)**.

LGPL v2.1 keeps the source open while remaining compatible with VLCKit and the other LGPL components Jellyswarrm links against.

See [LICENSE](LICENSE) for the full text.

---

## Acknowledgements

- [Jellyfin](https://jellyfin.org) — the open-source media server this app is built for
- [Jellyseerr](https://github.com/Fallenbagel/jellyseerr) / [Overseerr](https://overseerr.dev) — request management integration
- [Fladder](https://github.com/DonutWare/Fladder) — the Flutter Jellyfin client that inspired this project (GPL v3)

---

## Disclaimer

Jellyswarrm is an independent, community-developed application. It is not affiliated with or endorsed by the Jellyfin project, Jellyseerr, or Overseerr.

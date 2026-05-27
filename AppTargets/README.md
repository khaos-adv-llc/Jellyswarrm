# AppTargets

Per-platform scaffold for the three Jellyswarrm app targets. The Swift package in this repo (`JellyswarrmCore` + `JellyswarrmUI`) is shared across all of them; each target only provides its `@main` entry point, `Info.plist`, entitlements, and an `xcconfig`.

The Xcode project (`Jellyswarm.xcodeproj`) lives **outside** this repo as a sibling folder. This directory only holds source assets you wire into Xcode targets — it is not itself an Xcode project.

## Layout

```
AppTargets/
├── iOS/
│   ├── JellyswarmApp_iOS.swift     # @main entry point
│   ├── Info-iOS.plist
│   ├── Jellyswarrm-iOS.entitlements
│   └── Config-iOS.xcconfig
├── tvOS/
│   ├── JellyswarmApp_tvOS.swift
│   ├── Info-tvOS.plist
│   ├── Jellyswarrm-tvOS.entitlements
│   └── Config-tvOS.xcconfig
└── macOS/
    ├── JellyswarmApp_macOS.swift
    ├── Info-macOS.plist
    ├── Jellyswarrm-macOS.entitlements
    └── Config-macOS.xcconfig
```

## Minimum OS versions

- iOS / iPadOS 26
- tvOS 26
- macOS 26 (native, not Catalyst)

## Bundle IDs

- iOS: `com.jellyswarrm.ios`
- tvOS: `com.jellyswarrm.tvos`
- macOS: `com.jellyswarrm.macos`

All three share the App Group `group.com.jellyswarrm.shared`.

## Adding the targets in Xcode 26

Do this once per platform. The steps are the same for iOS, tvOS, and macOS — just pick the matching template and files.

### 1. Add the Swift package

In `Jellyswarm.xcodeproj`:

1. **File → Add Package Dependencies… → Add Local…**
2. Pick this repo directory (the one containing `Package.swift`).
3. Add both library products: `JellyswarrmCore` and `JellyswarrmUI`.

### 2. Create the iOS target

1. **File → New → Target…**
2. Choose **iOS → App**. Name it `Jellyswarrm-iOS`, interface **SwiftUI**, language **Swift**. Uncheck tests/Core Data.
3. Delete the auto-generated `App.swift`, `ContentView.swift`, and `Info.plist` Xcode created.
4. Drag `AppTargets/iOS/JellyswarmApp_iOS.swift` into the target. **Do not copy** — uncheck "Copy items if needed" so it stays referenced from the repo.
5. Drag `Info-iOS.plist` and `Jellyswarrm-iOS.entitlements` into the target the same way.
6. In **Project → Configurations**, set the iOS target's Debug and Release configs to use `Config-iOS.xcconfig` (Based on Configuration File).
7. In the target's **General** tab, link `JellyswarrmCore` and `JellyswarrmUI` under **Frameworks, Libraries, and Embedded Content**.
8. In **Build Settings**, set:
   - `INFOPLIST_FILE` → `$(SRCROOT)/Jellyswarrm/AppTargets/iOS/Info-iOS.plist` (adjust path to wherever the repo sits relative to the `.xcodeproj`)
   - `CODE_SIGN_ENTITLEMENTS` → `$(SRCROOT)/Jellyswarrm/AppTargets/iOS/Jellyswarrm-iOS.entitlements`
9. **Signing & Capabilities**: fill in your Development Team. Add the **App Groups** capability and check `group.com.jellyswarrm.shared`. Add **Associated Domains** if you want universal links.

### 3. Create the tvOS target

Same steps as iOS, but pick **tvOS → App** in the template picker. Use the files under `AppTargets/tvOS/`. The tvOS entitlement `com.apple.developer.user-management.runs-as-current-user` is added automatically — leave it.

### 4. Create the macOS target

Same steps as iOS, but pick **macOS → App** and use the files under `AppTargets/macOS/`. Make sure **App Sandbox** stays on (the entitlements file already sets it). Add the **App Groups** capability and check `group.com.jellyswarrm.shared`.

### 5. Schemes

Xcode creates a scheme for each new target. Rename them to `Jellyswarrm-iOS`, `Jellyswarrm-tvOS`, `Jellyswarrm-macOS` so the scheme picker stays readable.

### 6. Build & run

- iOS: pick "Khaos iPhone" (or any iOS 26 device/simulator) and Run.
- tvOS: pick an Apple TV simulator running tvOS 26.
- macOS: pick "My Mac" — it should build natively, not via Catalyst.

## Notes

- The three `@main` structs are intentionally named the same (`JellyswarmApp`). Each lives in its own target, so there is no symbol clash — but only add **one** of these files per target.
- `RootView`, `SettingsView`, and `AppState` come from `JellyswarrmUI` / `JellyswarrmCore`. If a symbol like `SettingsView` or `checkTVOSUserOnboarding` doesn't exist yet, add it to the package — don't inline it into the app target.
- Keep `Package.swift` as the source of truth for platform minimums. The xcconfig deployment targets here must stay in sync with it.

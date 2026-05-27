# Contributing to Jellyswarrm

Thank you for your interest in contributing! Jellyswarrm is a community-driven project and all contributions — code, documentation, bug reports, and design — are welcome.

---

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [How to Contribute](#how-to-contribute)
  - [Reporting Bugs](#reporting-bugs)
  - [Suggesting Features](#suggesting-features)
  - [Submitting Pull Requests](#submitting-pull-requests)
- [Code Style](#code-style)
- [Commit Messages](#commit-messages)
- [Branch Naming](#branch-naming)
- [Testing](#testing)
- [License](#license)

---

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating you agree to uphold it.

---

## Getting Started

### Prerequisites

| Tool | Version |
|------|---------|
| Xcode | 16.0+ |
| Swift | 6.0+ |
| macOS | 14.0+ (Sonoma) |
| Apple Developer Account | Required for device/tvOS testing |

### Development Setup

```bash
# 1. Fork the repo on GitHub, then clone your fork
git clone https://github.com/YOUR_USERNAME/Jellyswarrm.git
cd Jellyswarrm

# 2. Open in Xcode
open project/Package.swift

# 3. Select the scheme for your target platform (iOS, tvOS, macOS)
# 4. Build and run on simulator or device
```

#### tvOS-Specific Setup

The tvOS target requires two capabilities added in Xcode → Signing & Capabilities (tvOS target only):

1. **User Management** → enable "Runs as Current User"
2. **App Groups** → add `group.com.jellyswarrm.shared`

These are not committed to source control (they live in `.entitlements` files bound to your provisioning profile).

---

## How to Contribute

### Reporting Bugs

1. Search [existing issues](../../issues) to avoid duplicates.
2. Open a [Bug Report](../../issues/new?template=bug_report.md).
3. Include:
   - Platform and OS version (e.g. tvOS 18.2, iPhone iOS 18.1)
   - Xcode version
   - Steps to reproduce
   - Expected vs actual behavior
   - Logs or screenshots if relevant

### Suggesting Features

1. Search [existing issues](../../issues) and [discussions](../../discussions) first.
2. Open a [Feature Request](../../issues/new?template=feature_request.md).
3. Describe the problem you're solving, not just the solution.
4. Mention which platform(s) are affected.

### Submitting Pull Requests

1. **Open an issue first** for anything beyond a small bug fix or typo — this avoids duplicate work.
2. Fork and create a branch from `main` (see [Branch Naming](#branch-naming)).
3. Make your changes, following the [Code Style](#code-style) guidelines.
4. Add or update tests where applicable.
5. Ensure `swift test` passes locally.
6. Open a PR against `main` using the [PR template](.github/PULL_REQUEST_TEMPLATE.md).
7. Link the related issue in the PR description (e.g. `Closes #42`).
8. A maintainer will review within a few days. Be responsive to feedback.

---

## Code Style

Jellyswarrm uses **SwiftUI** and **Swift Concurrency** throughout. Please follow these conventions:

### General

- Follow [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- Prefer `async/await` over callbacks or Combine.
- Use `actor` for mutable shared state (e.g. API clients).
- Use `@Observable` (Swift 5.9 Observation framework) for view-facing state — not `ObservableObject`.
- No third-party dependencies — keep it pure SPM with Apple frameworks only.

### SwiftUI

- Keep views small and composable. Extract subviews into private structs or `@ViewBuilder` helpers.
- Use `#if os(tvOS)` / `#if os(macOS)` guards rather than runtime checks wherever possible.
- Prefer `@FocusState` for tvOS focus engine interactions.
- All new views must compile on all four platforms (iOS, iPadOS, tvOS, macOS) unless wrapped in a platform guard.

### Formatting

- 4-space indentation (no tabs).
- Opening braces on the same line.
- `// MARK: - Section Name` for logical sections within a file.
- Keep lines under ~120 characters.

A `.editorconfig` and SwiftFormat config are included — run `swiftformat .` before committing if you have [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) installed (not required but appreciated).

---

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short description>

[optional body]

[optional footer(s)]
```

**Types:** `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `ci`

**Scopes:** `tvos`, `ios`, `macos`, `auth`, `seerr`, `player`, `discover`, `keychain`, `ci`, `docs`

**Examples:**

```
feat(tvos): add Quick Connect polling with 10-minute expiry
fix(keychain): correct shared vs per-user item accessibility flags
docs(contributing): add tvOS entitlements setup instructions
test(auth): add QuickConnectState decoding test
```

---

## Branch Naming

```
<type>/<short-description>
```

**Examples:**
- `feat/tvos-quick-connect`
- `fix/seerr-session-cookie-parsing`
- `docs/update-readme-setup`
- `chore/update-package-swift`

---

## Testing

Tests live in `Tests/JellyswarrmCoreTests/`. Run them with:

```bash
cd project
swift test
```

When adding new networking or model code, add corresponding unit tests. UI tests are not required but welcome.

If your change touches the Keychain or tvOS multi-user flow, note that those paths require a real device or specific simulator configuration — document any limitations in your PR.

---

## License

By contributing you agree that your contributions will be licensed under the [GNU General Public License v3.0 with App Store Exception](LICENSE) that covers this project.

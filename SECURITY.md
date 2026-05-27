# Security Policy

## Supported Versions

Only the latest release of Jellyswarrm receives security fixes. We do not backport patches to older versions.

| Version | Supported |
|---------|-----------|
| Latest (`main`) | ✅ |
| Older tags | ❌ |

## Reporting a Vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

Instead, report them privately via one of these channels:

1. **GitHub Private Security Advisory** *(preferred)*: [Report a vulnerability](../../security/advisories/new)
2. **Email**: perplexity@alias.valdeze.de — use the subject line `[SECURITY] Jellyswarrm <brief description>`

### What to include

- A clear description of the vulnerability
- Steps to reproduce or a proof-of-concept
- The potential impact (data exposure, authentication bypass, etc.)
- Which platforms are affected (iOS, tvOS, macOS, iPadOS)
- Any suggested mitigations if you have them

### Response timeline

| Stage | Target |
|-------|--------|
| Acknowledgement | Within 3 business days |
| Initial assessment | Within 7 business days |
| Fix / mitigation | Depends on severity (critical: ASAP, high: 2 weeks, medium/low: next release) |
| Public disclosure | Coordinated with reporter after fix is released |

We will credit researchers in the release notes unless they prefer to remain anonymous.

## Security Design Notes

Jellyswarrm handles sensitive credentials. Here is how they are protected:

### Keychain architecture

| Data | Storage | tvOS scope |
|------|---------|-----------|
| Server URL + name | Shared Keychain (App Group) | All profiles |
| Seerr server config | Shared Keychain (App Group) | All profiles |
| Seerr API keys | Shared Keychain (`kSecAttrAccessibleAlwaysThisDeviceOnly`) | All profiles |
| Jellyfin auth tokens | Per-user Keychain | Current profile only |
| Seerr session cookies | Per-user Keychain | Current profile only |
| Stable device ID | Shared Keychain | All profiles |

### tvOS multi-user isolation

Jellyfin tokens and Seerr session cookies are stored in the per-user Keychain partition, which is isolated per tvOS system profile. One user's credentials cannot be read by another user's profile.

### What Jellyswarrm does NOT do

- Does not transmit credentials to any third-party service
- Does not log tokens, passwords, or cookies to the console or disk
- Does not store plaintext passwords anywhere — only tokens and session cookies obtained from the server after authentication
- Quick Connect secrets are held only in memory during the polling loop and are never persisted

### Dependency scope

Jellyswarrm has **zero third-party Swift dependencies**. The attack surface is limited to Apple's own frameworks (Foundation, SwiftUI, AVFoundation, Security).

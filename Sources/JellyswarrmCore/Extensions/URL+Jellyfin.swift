// MARK: - URL+Jellyfin.swift

// Jellyswarrm — GPL v3 with App Store exception

import Foundation

public extension URL {
    /// Normalize a user-entered server URL (trim slashes, ensure scheme)
    static func normalizeJellyfinURL(_ input: String) -> URL? {
        var cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if !cleaned.lowercased().hasPrefix("http://"), !cleaned.lowercased().hasPrefix("https://") {
            cleaned = "https://\(cleaned)"
        }

        return URL(string: cleaned)
    }

    /// Append Jellyfin API path components safely
    func jellyfinPath(_ components: String...) -> URL {
        var result = self
        for component in components {
            result = result.appendingPathComponent(component)
        }
        return result
    }
}

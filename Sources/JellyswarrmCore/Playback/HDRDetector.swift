// MARK: - HDRDetector.swift

// Jellyswarrm — GPL v3 with App Store exception

import AVFoundation
import CoreMedia
import Foundation

public enum HDRFormat: Sendable, Equatable {
    case dolbyVision   // Profile 5/8 — AVFoundation handles natively
    case hdr10         // PQ transfer function — Metal renderer needed
    case hlg           // HLG transfer function — Metal renderer needed
    case sdr           // Standard dynamic range
}

public actor HDRDetector {
    public static func detect(asset: AVAsset) async -> HDRFormat {
        guard let hdrTracks = try? await asset.loadTracks(withMediaCharacteristic: .containsHDRVideo),
              !hdrTracks.isEmpty else {
            return .sdr
        }

        for track in hdrTracks {
            guard let formatDescriptions = try? await track.load(.formatDescriptions) else { continue }
            for desc in formatDescriptions {
                let extensions = CMFormatDescriptionGetExtensions(desc) as? [String: Any] ?? [:]
                let transferFunction = extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String
                let colorPrimaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String

                // Dolby Vision — DOVIConfigurationBox present in format extensions
                // signals dvhe / dvav variants that AVFoundation decodes natively.
                if extensions["DOVIConfigurationBox" as String] != nil {
                    return .dolbyVision
                }

                if transferFunction == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String) {
                    return .hdr10
                }

                if transferFunction == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String) {
                    return .hlg
                }

                // BT.2020 primaries without explicit PQ/HLG — treat as HDR10.
                if colorPrimaries == (kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String) {
                    return .hdr10
                }
            }
        }
        return .hlg
    }
}

// MARK: - HDRPlayerView.swift

// Jellyswarrm — GPL v3 with App Store exception

#if canImport(MetalKit)
import AVFoundation
import JellyswarrmCore
import MetalKit
import SwiftUI

/// SwiftUI wrapper for the Metal HDR renderer. Used instead of the
/// AVFoundation player when `hdrFormat` is `.hdr10` or `.hlg`. Dolby Vision and
/// SDR stay on the AVFoundation path — VideoToolbox handles DV natively.
struct HDRPlayerView: View {
    let player: AVPlayer
    let hdrFormat: HDRFormat
    @State private var renderer: HDRMetalRenderer?

    var body: some View {
        Group {
            if let renderer {
                MetalViewRepresentable(mtkView: renderer.mtkView)
                    .ignoresSafeArea()
            } else {
                Color.black
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            if renderer == nil {
                renderer = HDRMetalRenderer(player: player, hdrFormat: hdrFormat)
            }
        }
        .onDisappear {
            renderer?.tearDown()
            renderer = nil
        }
    }
}

#if os(macOS)
struct MetalViewRepresentable: NSViewRepresentable {
    let mtkView: MTKView
    func makeNSView(context: Context) -> MTKView { mtkView }
    func updateNSView(_ nsView: MTKView, context: Context) {}
}
#else
struct MetalViewRepresentable: UIViewRepresentable {
    let mtkView: MTKView
    func makeUIView(context: Context) -> MTKView { mtkView }
    func updateUIView(_ uiView: MTKView, context: Context) {}
}
#endif
#endif

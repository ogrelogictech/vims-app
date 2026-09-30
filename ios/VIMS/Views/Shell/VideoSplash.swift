import SwiftUI
import AVFoundation
import UIKit

/// Cold-launch splash (shared/media/vims-splash.mp4): muted, aspect-FIT (the whole 9:16 frame, including
/// the tagline, is always visible), plays once, tap to skip. The letterbox bands above and below use the
/// video's own top/bottom edge colors (sampled from a frame) so the frame blends in seamlessly.
/// With Reduce Motion on, the last frame is shown for ~1 s instead.
struct VideoSplashView: View {
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastFrame: UIImage?
    @State private var finished = false
    /// Edge colors of the video frame (defaults measured from vims-splash.mp4; re-sampled at launch
    /// so a replacement video still blends).
    @State private var topEdge = Color(red: 0xD9 / 255, green: 0xDB / 255, blue: 0xE1 / 255)
    @State private var bottomEdge = Color(red: 0xC4 / 255, green: 0xC9 / 255, blue: 0xCF / 255)

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topEdge.frame(maxHeight: .infinity)
                bottomEdge.frame(maxHeight: .infinity)
            }
            .ignoresSafeArea()
            if reduceMotion {
                if let lastFrame {
                    Image(uiImage: lastFrame).resizable().scaledToFit().ignoresSafeArea()
                }
            } else if let url = Self.videoURL {
                SplashPlayerView(url: url) { finish() }
                    .ignoresSafeArea()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement()
        .accessibilityLabel("VIMS — Vision Inspection Management Solutions")
        .accessibilityHint("Double-tap to skip")
        .accessibilityAddTraits(.isButton)
        .task {
            guard let url = Self.videoURL else { finish(); return }
            if let edges = await Self.edgeColors(of: url) { topEdge = edges.top; bottomEdge = edges.bottom }
            if reduceMotion {
                lastFrame = await Self.lastFrame(of: url)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                finish()
            } else {
                // Safety net in case playback never reports the end.
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                finish()
            }
        }
    }

    static var videoURL: URL? { Bundle.main.url(forResource: "vims-splash", withExtension: "mp4") }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }

    /// Average color of the top and bottom pixel rows of a frame ~40% into the video.
    static func edgeColors(of url: URL) async -> (top: Color, bottom: Color)? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 180, height: 320)
        guard let d = try? await asset.load(.duration),
              let (img, _) = try? await gen.image(at: CMTimeMultiplyByFloat64(d, multiplier: 0.4)) else { return nil }
        let w = img.width, h = img.height
        guard w > 0, h > 4 else { return nil }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        func row(_ y: Int) -> Color {
            var r = 0, g = 0, b = 0
            for x in 0..<w { let i = (y * w + x) * 4; r += Int(px[i]); g += Int(px[i + 1]); b += Int(px[i + 2]) }
            let n = Double(w) * 255
            return Color(red: Double(r) / n, green: Double(g) / n, blue: Double(b) / n)
        }
        return (row(1), row(h - 2))
    }

    static func lastFrame(of url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceAfter = .zero
        guard let d = try? await asset.load(.duration) else { return nil }
        let t = CMTimeSubtract(d, CMTime(value: 1, timescale: 30))
        guard let (img, _) = try? await gen.image(at: t) else { return nil }
        return UIImage(cgImage: img)
    }
}

/// AVPlayerLayer host (aspect-fit, muted, no controls, transparent around the video).
struct SplashPlayerView: UIViewRepresentable {
    let url: URL
    let onEnd: () -> Void

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    final class Coordinator {
        var observer: NSObjectProtocol?
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerView {
        // Don't interrupt the user's music.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        let v = PlayerView()
        v.backgroundColor = .clear
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .pause
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        v.playerLayer.backgroundColor = UIColor.clear.cgColor
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in onEnd() }
        player.play()
        return v
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        uiView.playerLayer.player?.pause()
    }
}

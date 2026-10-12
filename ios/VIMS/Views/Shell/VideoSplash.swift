import SwiftUI
import AVFoundation
import UIKit

/// Cold-launch splash (shared/media/vims-splash.mp4): muted, aspect-FIT (the whole 9:16 frame, including
/// the tagline, is always visible), plays once to its end, tap to skip. The bands around the frame use the video's
/// own edge colors (sampled from a frame) so it blends in: above / below it on a tall screen (iPhone), and beside it
/// on a wider one (iPad, either orientation), where each side band runs from that edge's top color to its bottom one.
/// With Reduce Motion on, the last frame is shown for ~1 s instead.
struct VideoSplashView: View {
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastFrame: UIImage?
    @State private var finished = false
    /// Edge colors of the video frame (defaults measured from the Oct 12 vims-splash.mp4, the same through the
    /// whole video; re-sampled at launch so a replacement video still blends).
    @State private var edges = Edges()

    /// Band colors: the top / bottom rows, and the top / bottom ends of the left and right columns.
    struct Edges {
        var top = Color(red: 0xD5 / 255, green: 0xDD / 255, blue: 0xE5 / 255)
        var bottom = Color(red: 0xC6 / 255, green: 0xD0 / 255, blue: 0xDA / 255)
        var left: (Color, Color)? = nil
        var right: (Color, Color)? = nil
    }
    /// 720 × 1280.
    static let videoAspect: CGFloat = 9.0 / 16.0

    var body: some View {
        ZStack {
            GeometryReader { g in
                if g.size.height > 0, g.size.width / g.size.height > Self.videoAspect {
                    // Wider than the video (iPad): bands left and right.
                    HStack(spacing: 0) {
                        LinearGradient(colors: [edges.left?.0 ?? edges.top, edges.left?.1 ?? edges.bottom], startPoint: .top, endPoint: .bottom)
                        // 1 pt under each side of the video, so no hairline of the screen below shows at its edges.
                        Color.clear.frame(width: max(g.size.height * Self.videoAspect - 2, 0))
                        LinearGradient(colors: [edges.right?.0 ?? edges.top, edges.right?.1 ?? edges.bottom], startPoint: .top, endPoint: .bottom)
                    }
                } else {
                    VStack(spacing: 0) {
                        edges.top.frame(maxHeight: .infinity)
                        edges.bottom.frame(maxHeight: .infinity)
                    }
                }
            }
            .background(edges.bottom)
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
            if let sampled = await Self.edgeColors(of: url) { edges = sampled }
            if reduceMotion {
                lastFrame = await Self.lastFrame(of: url)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                finish()
            } else {
                // Safety net in case playback never reports the end: the video's own length plus 3 s, so a longer
                // video (the Oct 12 one is 6.6 s) always plays to its end — the end-of-video notification finishes.
                let loaded = (try? await AVURLAsset(url: url).load(.duration)).map(CMTimeGetSeconds) ?? 8
                let length = loaded.isFinite ? min(max(loaded, 1), 30) : 8
                try? await Task.sleep(nanoseconds: UInt64((length + 3) * 1_000_000_000))
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

    /// Edge colors of a frame ~40% into the video: the average of the top and bottom pixel rows, and of the top and
    /// bottom 15% of the left and right pixel columns.
    static func edgeColors(of url: URL) async -> Edges? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 180, height: 320)
        guard let d = try? await asset.load(.duration),
              let (img, _) = try? await gen.image(at: CMTimeMultiplyByFloat64(d, multiplier: 0.4)) else { return nil }
        let w = img.width, h = img.height
        guard w > 4, h > 8 else { return nil }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        func average(_ points: [(Int, Int)]) -> Color {
            var r = 0, g = 0, b = 0
            for (x, y) in points { let i = (y * w + x) * 4; r += Int(px[i]); g += Int(px[i + 1]); b += Int(px[i + 2]) }
            let n = Double(max(points.count, 1)) * 255
            return Color(red: Double(r) / n, green: Double(g) / n, blue: Double(b) / n)
        }
        func row(_ y: Int) -> Color { average((0..<w).map { ($0, y) }) }
        let band = max(h * 15 / 100, 1)
        func column(_ x: Int) -> (Color, Color) { (average((0..<band).map { (x, $0) }), average(((h - band)..<h).map { (x, $0) })) }
        return Edges(top: row(1), bottom: row(h - 2), left: column(1), right: column(w - 2))
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
        #if DEBUG
        let start = Date()
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
            print("SPLASHTEST ended after \(String(format: "%.2f", Date().timeIntervalSince(start))) s, at \(String(format: "%.2f", CMTimeGetSeconds(item.currentTime()))) of \(String(format: "%.2f", CMTimeGetSeconds(item.duration))) s")
        }
        #endif
        player.play()
        return v
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        uiView.playerLayer.player?.pause()
    }
}

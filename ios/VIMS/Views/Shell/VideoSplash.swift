import SwiftUI
import AVFoundation
import UIKit

/// Cold-launch splash (shared/media/vims-splash.mp4): full-screen, muted, aspect-fill, plays once,
/// tap to skip. With Reduce Motion on, the last frame is shown for ~1 s instead.
/// The launch screen color (LaunchBackground) matches the first frame, so there is no white flash.
struct VideoSplashView: View {
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastFrame: UIImage?
    @State private var finished = false

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            if reduceMotion {
                if let lastFrame {
                    Image(uiImage: lastFrame).resizable().scaledToFill().ignoresSafeArea()
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

/// AVPlayerLayer host (aspect-fill, muted, no controls).
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
        v.backgroundColor = UIColor(named: "LaunchBackground")
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .pause
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspectFill
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

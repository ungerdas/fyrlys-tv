#if !os(tvOS)
import AVFoundation
import FyrlysCore
import MediaPlayer
import SwiftUI

/// Filmer og episoder som spilles med VLC i kontrollsenteret og på låseskjermen (iPhone, iPad), og med mediatastene,
/// AirPods og «Spilles nå» i menylinja (Mac): tittelen, bildet, hvor langt den har kommet, pause og spoling. Apples
/// avspiller gjør det selv; VLC gjør det ikke.
@MainActor
final class VLCNowPlaying {
    static let shared = VLCNowPlaying()

    private weak var engine: VLCEngine?
    private var info: [String: Any] = [:]
    private var targets: [(MPRemoteCommand, Any)] = []
    private var pushed: (time: Double, playing: Bool, length: Double) = (-10, false, 0)

    func begin(_ engine: VLCEngine, title: String, subtitle: String, image: String?) {
        end()
        self.engine = engine
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        info = [MPMediaItemPropertyTitle: title,
                MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue]
        if !subtitle.isEmpty { info[MPMediaItemPropertyArtist] = subtitle }
        let center = MPRemoteCommandCenter.shared()
        func on(_ command: MPRemoteCommand, _ action: @escaping @MainActor (MPRemoteCommandEvent) -> Bool) {
            command.isEnabled = true
            let token = command.addTarget { event in
                MainActor.assumeIsolated { action(event) ? .success : .commandFailed }
            }
            targets.append((command, token))
        }
        on(center.playCommand) { [weak self] _ in self?.set(playing: true) ?? false }
        on(center.pauseCommand) { [weak self] _ in self?.set(playing: false) ?? false }
        on(center.togglePlayPauseCommand) { [weak self] _ in
            guard let engine = self?.engine else { return false }
            engine.togglePause()
            self?.update(force: true)
            return true
        }
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
        on(center.skipForwardCommand) { [weak self] _ in self?.jump(10) ?? false }
        on(center.skipBackwardCommand) { [weak self] _ in self?.jump(-10) ?? false }
        on(center.changePlaybackPositionCommand) { [weak self] event in
            guard let engine = self?.engine, let event = event as? MPChangePlaybackPositionCommandEvent else {
                return false
            }
            engine.seek(to: event.positionTime)
            self?.update(force: true)
            return true
        }
        update(force: true)
        if let image, let url = URL(string: image) { loadArtwork(url, for: engine) }
    }

    /// Hvor langt den har kommet, og om den spiller (hvert femte sekund, og med en gang når noe er endret).
    func update(force: Bool = false) {
        guard let engine else { return }
        let changed = engine.isPlaying != pushed.playing || engine.length != pushed.length
            || abs(engine.time - pushed.time) >= 5
        guard force || changed else { return }
        pushed = (engine.time, engine.isPlaying, engine.length)
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = engine.time
        info[MPNowPlayingInfoPropertyPlaybackRate] = engine.isPlaying ? 1.0 : 0.0
        if engine.length > 0 { info[MPMediaItemPropertyPlaybackDuration] = engine.length }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = engine.isPlaying ? .playing : .paused
        #endif
    }

    /// Slutt (spilleren er lukket); bare når det er [engine] som vises (en ny episode har tatt over ellers).
    func end(_ engine: VLCEngine? = nil) {
        if let engine, engine !== self.engine { return }
        for (command, token) in targets { command.removeTarget(token) }
        targets = []
        self.engine = nil
        info = [:]
        pushed = (-10, false, 0)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        #endif
    }

    private func set(playing: Bool) -> Bool {
        guard let engine else { return false }
        if engine.isPlaying != playing { engine.togglePause() }
        update(force: true)
        return true
    }

    private func jump(_ seconds: Double) -> Bool {
        guard let engine else { return false }
        engine.seek(to: engine.time + seconds)
        update(force: true)
        return true
    }

    private func loadArtwork(_ url: URL, for engine: VLCEngine) {
        Task {
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.setValue(ProviderAgent.current, forHTTPHeaderField: "User-Agent")
            guard let (data, _) = try? await URLSession.shared.data(for: request), let image = UIImage(data: data),
                  self.engine === engine else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }
}
#endif

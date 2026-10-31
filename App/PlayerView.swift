import AVFoundation
import AVKit
import FyrlysCore
import SwiftUI

/// Avspillingen av én kanal om gangen med AVPlayer (HLS rett fra leverandøren). Nye forsøk ved brudd, tre i minuttet;
/// så en forklaring (alle tilkoblingene i bruk, HTTP-koden fra leverandøren, eller det AVPlayer sa).
@MainActor
@Observable
final class PlayerModel {
    let player = AVPlayer()
    private(set) var channel: Channel
    let list: [Channel]
    private(set) var error: String?

    private let app: AppModel
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var notes: [NSObjectProtocol] = []
    @ObservationIgnored private var failures: [Date] = []
    @ObservationIgnored private var generation = 0

    static let triesPerMinute = 3

    init(app: AppModel, channel: Channel, list: [Channel]) {
        self.app = app
        self.channel = channel
        self.list = list
    }

    var isFavorite: Bool { app.isFavorite(channel) }

    func open(_ channel: Channel) {
        guard let client = app.client else { return }
        self.channel = channel
        error = nil
        generation += 1
        let gen = generation
        let asset = AVURLAsset(url: client.liveURL(channel), options: [AVURLAssetHTTPUserAgentKey: xtreamUserAgent])
        let item = AVPlayerItem(asset: asset)
        item.externalMetadata = metadata()
        stopObserving()
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed, let self else { return }
            let message = item.error?.localizedDescription
            Task { @MainActor in self.failed(gen, message) }
        }
        let center = NotificationCenter.default
        notes = [
            center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item,
                               queue: .main) { [weak self] note in
                guard let self else { return }
                let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                    .localizedDescription
                Task { @MainActor in self.failed(gen, message) }
            },
            // en direktesending skal ikke ta slutt: da åpnes den igjen
            center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item,
                               queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.failed(gen, nil) }
            },
        ]
        player.replaceCurrentItem(with: item)
        player.play()
        app.played(channel)
        app.programs.want(channel)
    }

    /// Prøv igjen (knappen etter en feil).
    func retry() {
        failures = []
        open(channel)
    }

    /// Neste (1) eller forrige (-1) kanal i lista.
    func step(_ delta: Int) {
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.id == channel.id } ?? 0
        let next = list[((index + delta) % list.count + list.count) % list.count]
        failures = []
        open(next)
    }

    func toggleFavorite() { app.toggleFavorite(channel) }

    func stop() {
        generation += 1
        stopObserving()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func stopObserving() {
        statusObservation?.invalidate()
        statusObservation = nil
        for note in notes { NotificationCenter.default.removeObserver(note) }
        notes = []
    }

    private func failed(_ gen: Int, _ message: String?) {
        guard gen == generation, error == nil else { return }
        let now = Date()
        failures = failures.filter { now.timeIntervalSince($0) < 60 } + [now]
        generation += 1
        let next = generation
        if failures.count <= Self.triesPerMinute {
            Task {
                try? await Task.sleep(for: .seconds(2))
                guard next == self.generation else { return }
                self.open(self.channel)
            }
        } else {
            player.pause()
            Task { await explain(next, message) }
        }
    }

    private func explain(_ gen: Int, _ message: String?) async {
        guard let client = app.client else { return }
        var text = L("Kanalen kunne ikke spilles ({message}).", ["message": client.redact(message ?? "?")])
        if let account = try? await client.account(), account.maxConnections > 0,
           account.activeConnections >= account.maxConnections {
            text = L("Alle tilkoblingene i abonnementet er i bruk akkurat nå. Ser noen på en annen enhet?")
        } else if let code = await streamStatus(client.liveURL(channel)), code >= 400 {
            text = L("Kanalen kunne ikke spilles ({message}).",
                     ["message": L("IPTV-serveren svarte HTTP {code}", ["code": code])])
        }
        guard gen == generation else { return }
        error = text
    }

    /// Bare svaret fra leverandøren (HTTP-koden), ikke selve strømmen.
    private func streamStatus(_ url: URL) async -> Int? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(xtreamUserAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            bytes.task.cancel()
            return (response as? HTTPURLResponse)?.statusCode
        } catch {
            return nil
        }
    }

    /// Kanalen og programmet som går nå, i infoen til spilleren.
    func metadata() -> [AVMetadataItem] {
        var items = [Self.meta(.commonIdentifierTitle, nameParts(channel.name).main)]
        if let now = nowAndNext(app.programs.programs(for: channel), at: Date()).now {
            items.append(Self.meta(.iTunesMetadataTrackSubTitle, "\(hhmm(now.start))–\(hhmm(now.stop))  \(now.title)"))
            if !now.description.isEmpty {
                items.append(Self.meta(.commonIdentifierDescription, now.description))
            }
        }
        return items
    }

    func refreshMetadata() {
        player.currentItem?.externalMetadata = metadata()
    }

    private static func meta(_ id: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = id
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item
    }
}

/// Spilleren i fullskjerm. Menyknappen på fjernkontrollen lukker den.
struct PlayerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: PlayerModel?
    let request: PlayRequest

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                if let error = model.error {
                    PlayerError(model: model, message: error) { dismiss() }
                } else {
                    PlayerController(model: model, channelId: model.channel.id, favorite: model.isFavorite)
                        .ignoresSafeArea()
                }
            }
        }
        .onAppear {
            guard model == nil else { return }
            let player = PlayerModel(app: app, channel: request.channel, list: request.list)
            model = player
            player.open(request.channel)
        }
        .onDisappear { model?.stop() }
        .onChange(of: programs) { model?.refreshMetadata() }
    }

    private var programs: [Program] {
        guard let model else { return [] }
        return app.programs.programs(for: model.channel)
    }
}

/// Når kanalen ikke kan spilles.
private struct PlayerError: View {
    let model: PlayerModel
    let message: String
    let close: () -> Void

    var body: some View {
        VStack(spacing: 34) {
            FyrlysMark()
                .frame(width: 120)
            Text(nameParts(model.channel.name).main)
                .font(.system(size: 40, weight: .bold))
            Text(L("Kanalen kunne ikke spilles"))
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.live)
            Text(message)
                .font(.system(size: 28))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 1200)
            HStack(spacing: 40) {
                Button(L("Prøv igjen")) { model.retry() }
                Button(L("Neste kanal")) { model.step(1) }
                Button(L("Lukk"), action: close)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spiller-feil")
    }
}

/// AVPlayerViewController med neste/forrige kanal og favoritt i kontrollene, og kanallista som et eget felt når man
/// sveiper ned.
struct PlayerController: UIViewControllerRepresentable {
    let model: PlayerModel
    /// (bare så SwiftUI oppdaterer knappene når kanalen eller favoritten endres)
    let channelId: String
    let favorite: Bool

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = model.player
        controller.customInfoViewControllers = [context.coordinator.channels]
        updateButtons(controller)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        updateButtons(controller)
    }

    private func updateButtons(_ controller: AVPlayerViewController) {
        let model = model
        let favorite = favorite
        controller.transportBarCustomMenuItems = [
            UIAction(title: L("Forrige kanal"), image: UIImage(systemName: "chevron.down")) { _ in
                MainActor.assumeIsolated { model.step(-1) }
            },
            UIAction(title: L("Neste kanal"), image: UIImage(systemName: "chevron.up")) { _ in
                MainActor.assumeIsolated { model.step(1) }
            },
            UIAction(title: favorite ? L("Fjern fra favoritter") : L("Legg til i favoritter"),
                     image: UIImage(systemName: favorite ? "star.fill" : "star")) { _ in
                MainActor.assumeIsolated { model.toggleFavorite() }
            },
        ]
    }

    @MainActor
    final class Coordinator {
        let channels: UIHostingController<ChannelStrip>

        init(model: PlayerModel) {
            channels = UIHostingController(rootView: ChannelStrip(model: model))
            channels.title = L("Kanaler")
            channels.preferredContentSize = CGSize(width: 1920, height: 330)
        }
    }
}

/// Kanalene i lista bortover (feltet «Kanaler» i spilleren).
struct ChannelStrip: View {
    let model: PlayerModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 36) {
                    ForEach(model.list) { channel in
                        Button {
                            model.open(channel)
                        } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                ChannelTile(channel: channel, compact: true)
                                    .frame(width: 280, height: 158)
                                Text(nameParts(channel.name).main)
                                    .font(.system(size: 22, weight: channel.id == model.channel.id ? .bold : .regular))
                                    .foregroundStyle(channel.id == model.channel.id ? Theme.signal : Theme.ink)
                                    .lineLimit(1)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .frame(width: 280, alignment: .leading)
                            }
                            .background(Theme.surface)
                        }
                        .buttonStyle(.card)
                        .id(channel.id)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 30)
            }
            .onAppear { proxy.scrollTo(model.channel.id, anchor: .center) }
        }
    }
}

import FyrlysCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Det store kanalkortet, som på Fyrlys-nettsiden (iPhone og Apple TV): stor logo på logoens egen farge, en strek for
/// hvor langt programmet har kommet, det som går nå (eller kampen) og kanalnavnet under. På iPhone legger stjernen
/// oppe til høyre kanalen til i favorittene; på Apple TV er hele kortet én knapp som får fokus, og stjernen viser bare
/// at kanalen er favoritt. Hold inne for å legge til eller fjerne.
struct BigChannelCard: View {
    @Environment(AppModel.self) private var model
    let channel: Channel
    let action: () -> Void
    /// Apple TV: kortet fikk fokus (den øverste raden ruller da siden helt opp, så fanelinja kommer helt fram)
    var onFocus: (() -> Void)?
    #if os(tvOS)
    @FocusState private var focused: Bool
    #endif

    var body: some View {
        let favorite = model.isFavorite(channel)
        card(favorite)
            .contextMenu {
                Button {
                    model.toggleFavorite(channel)
                } label: {
                    Label(favorite ? L("Fjern fra favoritter") : L("Legg til i favoritter"),
                          systemImage: favorite ? "star.slash" : "star")
                }
                if channel.archiveDays > 0 {
                    Button {
                        model.archiveChannel = channel
                    } label: {
                        Label(L("TV-arkiv"), systemImage: "clock.arrow.circlepath")
                    }
                }
                if model.multiviewAvailable {
                    Button {
                        model.multiview = MultiviewRequest(channel: channel)
                    } label: {
                        Label(L("Multiview"), systemImage: "rectangle.split.2x2")
                    }
                }
            }
            #if !os(tvOS)
            // ett element med de to knappene i, så «kanal-…» ikke skriver over id-en til stjerneknappen
            .accessibilityElement(children: .contain)
            #endif
            .accessibilityIdentifier("kanal-\(channel.id)")
            .onAppear { model.programs.want(channel) }
            .onDisappear { model.programs.forget(channel) }
    }

    /// Logoen øverst og teksten under.
    private var face: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(16 / 8.5, contentMode: .fit)
                .overlay { LogoArea(channel: channel) }
                .clipped()
            CardInfo(channel: channel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    #if os(tvOS)
    private func card(_ favorite: Bool) -> some View {
        Button(action: action) {
            face
                .overlay(alignment: .topTrailing) {
                    if favorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: Metrics.bigStar, weight: .semibold))
                            .foregroundStyle(Theme.gold)
                            .frame(width: Metrics.bigStarBox, height: Metrics.bigStarBox)
                            .background(Circle().fill(Color.black.opacity(0.4)))
                            .padding(10)
                            .accessibilityIdentifier("favoritt-\(channel.id)")
                    }
                }
        }
        .buttonStyle(BigCardStyle())
        .focused($focused)
        .onChange(of: focused) { _, now in
            if now { onFocus?() }
        }
        // over naboene, så skyggen og kanten ikke havner under dem
        .zIndex(focused ? 1 : 0)
    }
    #else
    private func card(_ favorite: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.bigRadius, style: .continuous)
        return Button(action: action) {
            face
                .background(Theme.surface)
                .clipShape(shape)
                .contentShape(shape)
        }
        .buttonStyle(PressStyle())
        .overlay(alignment: .topTrailing) {
            Button {
                model.toggleFavorite(channel)
            } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .font(.system(size: Metrics.bigStar, weight: .semibold))
                    .foregroundStyle(favorite ? Theme.gold : Color.white)
                    .frame(width: Metrics.bigStarBox, height: Metrics.bigStarBox)
                    .background(Circle().fill(Color.black.opacity(0.4)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(6)
            .accessibilityIdentifier("stjerne-kanal-\(channel.id)")
            .accessibilityLabel(favorite ? L("Fjern fra favoritter") : L("Legg til i favoritter"))
        }
    }
    #endif
}

#if os(tvOS)
/// De store kortene på Apple TV: med fokus lyseblå kant, litt større, lysere flate og skygge (som de smale kortene).
struct BigCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BigCardBody(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct BigCardBody<Label: View>: View {
    let label: Label
    let pressed: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.bigRadius, style: .continuous)
        label
            .background(focused ? Theme.surface2 : Theme.surface)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.focus, lineWidth: 4).opacity(focused ? 1 : 0))
            .scaleEffect(focused ? (pressed ? 1.0 : 1.06) : 1)
            .shadow(color: .black.opacity(focused ? 0.55 : 0), radius: focused ? 20 : 0, y: focused ? 12 : 0)
            .animation(.easeOut(duration: 0.16), value: focused)
    }
}
#endif

/// Streken, det som går nå og navnet. Eventkanaler: kampen står i navnet (klokkeslettet i gult), og konkurransen
/// øverst. Kanaler uten programinfo: bare navnet, større.
private struct CardInfo: View {
    @Environment(AppModel.self) private var model
    let channel: Channel

    private var pad: CGFloat { Metrics.bigPad }

    var body: some View {
        let parts = nameParts(channel.name)
        Group {
            if !parts.sub.isEmpty {
                lines(top: Text(verbatim: parts.sub), parts: parts)
            } else if channel.wantsEpg {
                TimelineView(.everyMinute) { context in
                    if let now = nowAndNext(model.programs.programs(for: channel), at: context.date).now {
                        VStack(alignment: .leading, spacing: 0) {
                            ProgressLine(value: now.progress(at: context.date))
                            lines(top: Text(now.title), parts: parts)
                        }
                    } else if !model.programs.isLoaded(channel) {
                        // henter: en grå strek der programmet kommer
                        VStack(alignment: .leading, spacing: 2) {
                            Capsule()
                                .fill(Theme.surface2)
                                .frame(width: Metrics.bigTitle * 6, height: Metrics.bigTitle * 0.6)
                                .padding(.top, pad * 1.25)
                                .padding(.bottom, pad * 0.4)
                            name(parts, big: false)
                        }
                        .padding(.horizontal, pad)
                    } else {
                        name(parts, big: true)
                    }
                }
            } else {
                name(parts, big: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Metrics.bigInfoMin, alignment: .topLeading)
    }

    private func lines(top: Text, parts: NameParts) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            top
                .font(.system(size: Metrics.bigTitle, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .padding(.top, pad * 0.85)
            name(parts, big: false)
        }
        .padding(.horizontal, pad)
    }

    /// Navnet: lite og dempet under programmet, eller stort når det står alene.
    @ViewBuilder
    private func name(_ parts: NameParts, big: Bool) -> some View {
        HStack(spacing: 6) {
            if !parts.time.isEmpty {
                Text(verbatim: parts.time)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.signal)
                    .fixedSize()
            }
            Text(verbatim: parts.main)
                .fontWeight(big ? .bold : .medium)
                .foregroundStyle(big ? Theme.ink : Theme.muted)
                .lineLimit(big ? 2 : 1)
        }
        .font(.system(size: big ? Metrics.bigTitle : Metrics.bigSub))
        .padding(.top, big ? pad : 0)
        .padding(.bottom, pad * 1.1)
        .padding(.horizontal, big ? pad : 0)
    }
}

/// Streken under logoen for hvor langt programmet har kommet (hele bredden).
private struct ProgressLine: View {
    let value: Double

    var body: some View {
        let clamped = min(1, max(0, value))
        Rectangle()
            .fill(Theme.ink.opacity(0.16))
            .frame(height: Metrics.bigBar)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Theme.signal)
                    .scaleEffect(x: max(clamped, 0.001), y: 1, anchor: .leading)
            }
    }
}

/// Logoen på logoens egen farge (regnet ut fra bildet, som på nettsiden), eller de tre første tegnene på en farge
/// fra navnet når kanalen ikke har logo.
struct LogoArea: View {
    let channel: Channel
    @State private var image: UIImage?
    @State private var tint: Color?

    private var url: URL? { channel.logo.flatMap { URL(string: $0) } }

    init(channel: Channel) {
        self.channel = channel
        let url = channel.logo.flatMap { URL(string: $0) }
        _image = State(initialValue: url.flatMap { Images.shared.cached($0) })
        _tint = State(initialValue: url.flatMap { Images.shared.tint(for: $0) })
    }

    var body: some View {
        ZStack {
            surfaceColor
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(0.69)
            } else {
                Text(verbatim: logoText(channel.name))
                    .font(.system(size: Metrics.bigLogoText, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, Metrics.bigPad)
            }
        }
        .task(id: url) {
            guard let url, image == nil else { return }
            if let loaded = await Images.shared.load(url) {
                tint = Images.shared.tint(for: url)
                image = loaded
            }
        }
    }

    private var surfaceColor: Color {
        if url == nil { return Color(hue: Double(nameHue(channel.name)), saturation: 0.32, lightness: 0.24) }
        return tint ?? Theme.cardLogoBg
    }
}

/// Fargetonen (0–359) for et navn, som `hue()` på nettsiden, så kanaler uten logo får samme farge der og her.
func nameHue(_ text: String) -> Int {
    var h = 0
    for scalar in text.unicodeScalars {
        h = (h * 31 + Int(scalar.utf16.first ?? 0)) % 360
    }
    return h
}

/// Bakgrunnen bak en logo, som på nettsiden: logoens egen bakgrunn (hjørnene er dekkende), ellers en mørk utgave av
/// fargen i logoen, ellers lyst bak mørke logoer; nil gir standardflaten.
func logoTint(_ image: UIImage) -> Color? {
    guard let cg = image.cgImage else { return nil }
    let n = 24
    guard let context = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.interpolationQuality = .medium
    context.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
    guard let raw = context.data else { return nil }
    let d = raw.bindMemory(to: UInt8.self, capacity: n * n * 4)
    /// rød, grønn, blå (0–255, uten forhåndsmultiplisert alfa) og alfa for punktet nr. i
    func pixel(_ i: Int) -> (r: Double, g: Double, b: Double, a: Double) {
        let a = Double(d[i * 4 + 3])
        guard a > 0 else { return (0, 0, 0, 0) }
        let k = 255 / a
        return (min(255, Double(d[i * 4]) * k), min(255, Double(d[i * 4 + 1]) * k), min(255, Double(d[i * 4 + 2]) * k), a)
    }
    let corners = [0, n - 1, n * (n - 1), n * n - 1].map(pixel)
    if corners.allSatisfy({ $0.a > 200 }) {
        let r = corners.map(\.r).reduce(0, +) / 4, g = corners.map(\.g).reduce(0, +) / 4
        let b = corners.map(\.b).reduce(0, +) / 4
        return Color(red: r / 255, green: g / 255, blue: b / 255)
    }
    var count = 0.0, luminance = 0.0, saturated = 0.0, sr = 0.0, sg = 0.0, sb = 0.0
    for i in 0..<(n * n) {
        let p = pixel(i)
        guard p.a >= 128 else { continue }
        count += 1
        luminance += (0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b) / 255
        if max(p.r, p.g, p.b) - min(p.r, p.g, p.b) > 60 {
            saturated += 1
            sr += p.r
            sg += p.g
            sb += p.b
        }
    }
    if count > 0 && saturated > count * 0.15 {
        let r = sr / saturated / 255, g = sg / saturated / 255, b = sb / saturated / 255
        let hi = max(r, g, b), lo = min(r, g, b)
        var hue = 0.0
        if hi != lo {
            if hi == r {
                hue = 60 * ((g - b) / (hi - lo)).truncatingRemainder(dividingBy: 6)
            } else if hi == g {
                hue = 60 * ((b - r) / (hi - lo) + 2)
            } else {
                hue = 60 * ((r - g) / (hi - lo) + 4)
            }
        }
        return Color(hue: (hue + 360).truncatingRemainder(dividingBy: 360).rounded(), saturation: 0.45, lightness: 0.26)
    }
    if count > 0 && luminance / count < 0.35 { return Color(hex: 0xDFE4E8) }
    return nil
}

/// Litt mindre mens du trykker.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

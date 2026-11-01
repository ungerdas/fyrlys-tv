import FyrlysCore
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Fargene fra Fyrlys. Mørk «Fyrlys om natta» (havblått og fyrlys-ravgult) på Apple TV; på iPhone og iPad også lys
/// «Nordisk lys» (papirhvitt og fjordblått, med en tynn ravgul strek), som på nettsiden. Fargene følger da modusen.
enum Theme {
    static let bg = tone(0x07121C, light: 0xF5F3EE)
    static let surface = tone(0x0C1B29, light: 0xFFFFFF)
    static let surface2 = tone(0x12263A, light: 0xE9EEF2)
    static let line = tone(0x1D3449, light: 0xD8DFE5)
    static let ink = tone(0xEDF1F4, light: 0x0F1F2D)
    static let ink2 = tone(0xB3C1CD, light: 0x33485B)
    static let muted = tone(0x8597A8, light: 0x566A7C)
    /// gult lys i mørk modus, fjordblått i lys (som nettsiden)
    static let signal = tone(0xF2B544, light: 0x1F5F8B)
    /// tekst på `signal`
    static let signalInk = tone(0x1B1305, light: 0xFFFFFF)
    /// lyset fra fyret i logoen
    static let beam = tone(0xF2B544, light: 0xE0A33A)
    /// stjernen over logoen på de store kortene: alltid gul (den står på en mørk flate)
    static let gold = Color(hex: 0xF2B544)
    static let live = Color(hex: 0xFF5A4F)
    /// flaten bak logoene: mørk i begge moduser
    static let logoBg = Color(hex: 0x1B2C3B)
    /// flaten bak logoen på de store kortene når logoen ikke har en farge
    static let cardLogoBg = tone(0x050D15, light: 0x1B2C3B)
    /// forkortelsen når logoen mangler (på den mørke logoflaten)
    static let logoInk = Color(hex: 0xEDF1F4)
    /// kanten rundt kortet som har fokus (som i Fyrlys på Windows)
    static let focus = tone(0x8CC8FF, light: 0x1F5F8B)
    /// luft mot sidene av TV-en: sidene går forbi den trygge sonen til Apple TV (80 pt), som ga for mye luft
    static let edge: CGFloat = 40
    /// luft nederst når et kort med fokus rulles fram (innholdet går ellers helt ned)
    static let bottomFocus: CGFloat = 30

    /// [dark] i mørk modus og [light] i lys (bare på iPhone og iPad; Apple TV er alltid mørk).
    private static func tone(_ dark: UInt32, light: UInt32) -> Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .light ? light : dark)
        })
        #else
        Color(hex: dark)
        #endif
    }
}

#if os(iOS)
/// Lys eller mørk modus på iPhone og iPad: «light», «dark», eller tom for å følge enheten (som nettsiden).
enum Appearance {
    static let key = "tema"

    static func scheme(_ stored: String) -> ColorScheme? {
        switch stored {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#endif

/// Målene på TV-siden: skalert opp for TV (rundt 1,4 ganger pikslene i Fyrlys på Windows), og som Windows-appen på
/// iPhone og iPad.
enum Metrics {
    #if os(tvOS)
    static let sidebarWidth: CGFloat = 340
    static let sidebarFont: CGFloat = 23
    static let sidebarRow: CGFloat = 54
    static let sidebarIcon: CGFloat = 21
    static let sectionFont: CGFloat = 16
    static let smallFont: CGFloat = 17
    static let cardHeight: CGFloat = 96
    static let cardTitle: CGFloat = 21
    static let cardSub: CGFloat = 17
    static let logo = CGSize(width: 84, height: 63)
    static let logoText: CGFloat = 20
    static let gridMin: CGFloat = 320
    static let gridSpacing: CGFloat = 18
    static let pageTitle: CGFloat = 34
    static let pageCount: CGFloat = 22
    static let pagePadding: CGFloat = 22
    // de store kortene (som på iPhone, men seks i bredden ved siden av sidemenyen, så mange kanaler får plass)
    static let bigColumns = 6
    static let bigTitle: CGFloat = 19
    static let bigSub: CGFloat = 16
    static let bigLogoText: CGFloat = 28
    static let bigRadius: CGFloat = 16
    static let bigPad: CGFloat = 12
    static let bigBar: CGFloat = 3
    static let bigInfoMin: CGFloat = 70
    static let bigStar: CGFloat = 20
    static let bigStarBox: CGFloat = 38
    static let bigGridMin: CGFloat = 230
    static let bigGap: CGFloat = 20
    static let rowTitle: CGFloat = 28
    static let rowClock: CGFloat = 22
    #else
    static let sidebarWidth: CGFloat = 280
    static let sidebarFont: CGFloat = 16
    static let sidebarRow: CGFloat = 42
    static let sidebarIcon: CGFloat = 17
    static let sectionFont: CGFloat = 12
    static let smallFont: CGFloat = 13
    static let cardHeight: CGFloat = 76
    static let cardTitle: CGFloat = 16
    static let cardSub: CGFloat = 13
    static let logo = CGSize(width: 64, height: 48)
    static let logoText: CGFloat = 15
    static let gridMin: CGFloat = 300
    static let gridSpacing: CGFloat = 12
    static let pageTitle: CGFloat = 24
    static let pageCount: CGFloat = 15
    static let pagePadding: CGFloat = 16
    // de store kortene på iPhone (som på Fyrlys-nettsiden)
    static let bigColumns = 2
    static let bigTitle: CGFloat = 15
    static let bigSub: CGFloat = 13
    static let bigLogoText: CGFloat = 24
    static let bigRadius: CGFloat = 18
    static let bigPad: CGFloat = 12
    static let bigBar: CGFloat = 3
    static let bigInfoMin: CGFloat = 64
    static let bigStar: CGFloat = 17
    static let bigStarBox: CGFloat = 36
    static let bigGridMin: CGFloat = 150
    static let bigGap: CGFloat = 12
    static let rowTitle: CGFloat = 21
    static let rowClock: CGFloat = 16
    #endif
}

/// Antall med mellomrom mellom tusenene på norsk («24 224»), komma på engelsk.
enum CountText {
    static func of(_ n: Int) -> String {
        let format = NumberFormatter()
        format.numberStyle = .decimal
        format.locale = Locale(identifier: appLanguage == "no" ? "nb_NO" : "en_GB")
        return format.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

extension View {
    /// Fokusseksjon på Apple TV (finnes ikke på iOS).
    @ViewBuilder
    func tvFocusSection() -> some View {
        #if os(tvOS)
        focusSection()
        #else
        self
        #endif
    }

    /// Nærmere sidene og helt ned på Apple TV (den trygge sonen ga for mye luft); på iPhone og iPad gjelder den
    /// trygge sonen (hakket og hjem-streken).
    @ViewBuilder
    func tvEdges(bottom: Bool = true) -> some View {
        #if os(tvOS)
        padding(.horizontal, Theme.edge)
            .ignoresSafeArea(.container, edges: bottom ? [.horizontal, .bottom] : .horizontal)
        #else
        self
        #endif
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// Fra HSL (fargetone 0–360, metning og lyshet 0–1), som i CSS.
    init(hue: Double, saturation: Double, lightness: Double) {
        let c = (1 - abs(2 * lightness - 1)) * saturation
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        var r = 0.0, g = 0.0, b = 0.0
        switch h {
        case ..<1: (r, g, b) = (c, x, 0)
        case ..<2: (r, g, b) = (x, c, 0)
        case ..<3: (r, g, b) = (0, c, x)
        case ..<4: (r, g, b) = (0, x, c)
        case ..<5: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        let m = lightness - c / 2
        self.init(red: r + m, green: g + m, blue: b + m)
    }
}

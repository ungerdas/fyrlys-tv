import SwiftUI

/// Fargene fra Fyrlys («Fyrlys om natta»): mørk blå bakgrunn, lys tekst og gult lys.
enum Theme {
    static let bg = Color(hex: 0x07121C)
    static let surface = Color(hex: 0x0C1B29)
    static let surface2 = Color(hex: 0x12263A)
    static let line = Color(hex: 0x1D3449)
    static let ink = Color(hex: 0xEDF1F4)
    static let muted = Color(hex: 0x8597A8)
    static let signal = Color(hex: 0xF2B544)
    static let live = Color(hex: 0xFF5A4F)
    static let logoBg = Color(hex: 0x1B2C3B)
    /// kanten rundt kortet som har fokus (som i Fyrlys på Windows)
    static let focus = Color(hex: 0x8CC8FF)
    /// luft mot sidene av TV-en: sidene går forbi den trygge sonen til Apple TV (80 pt), som ga for mye luft
    static let edge: CGFloat = 40
    /// luft nederst når et kort med fokus rulles fram (innholdet går ellers helt ned)
    static let bottomFocus: CGFloat = 30
}

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
    #endif
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
}

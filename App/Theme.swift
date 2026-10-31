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

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

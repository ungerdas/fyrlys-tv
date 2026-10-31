import Foundation

/// TV-guiden: seks timer fra halvtimen før denne halvtimen (som i Fyrlys på Windows).
public enum GuideTime {
    public static let hours = 6
    public static var totalMinutes: Double { Double(hours * 60) }

    /// 20:47 → 20:00, 20:12 → 19:30 (i hele halvtimer, så det stemmer i alle tidssoner med hele og halve timer)
    public static func start(_ now: Date) -> Date {
        let half: TimeInterval = 1800
        let floored = (now.timeIntervalSince1970 / half).rounded(.down) * half
        return Date(timeIntervalSince1970: floored - half)
    }

    public static func end(_ start: Date) -> Date { start.addingTimeInterval(totalMinutes * 60) }

    /// Minutter fra [start] til [date].
    public static func minutes(from start: Date, to date: Date) -> Double {
        date.timeIntervalSince(start) / 60
    }

    /// Hvor programmet står i guiden, i minutter fra starten: (fra, lengde), kuttet til guiden. Nil når det ikke vises.
    public static func span(of program: Program, start: Date) -> (from: Double, length: Double)? {
        let end = end(start)
        guard program.stop > start, program.start < end else { return nil }
        let from = max(0, minutes(from: start, to: program.start))
        let to = min(totalMinutes, minutes(from: start, to: program.stop))
        return to > from ? (from, to - from) : nil
    }

    /// Tidene for merkene over guiden (hver halvtime).
    public static func marks(_ start: Date) -> [Date] {
        (0..<(hours * 2)).map { start.addingTimeInterval(Double($0) * 1800) }
    }
}

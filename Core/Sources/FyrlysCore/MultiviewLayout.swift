import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Hvordan bildene i multiview står: like store, ett stort med de andre i en kolonne ved siden av, eller ett stort
/// øverst med de andre på en rad under. Det store er det første bildet (hovedbildet).
public enum MultiviewLayout: String, CaseIterable, Sendable {
    case grid = "like"
    case side = "side"
    case top = "topp"
}

/// Rammene til [count] bilder i [size], i samme rekkefølge som bildene. Bildene i «side» og «topp» er 16:9 (det store
/// og de små), midtstilt; i «like» deler de skjermen. Står skjermen (høyere enn den er bred), blir «side» som «topp».
public func multiviewFrames(_ layout: MultiviewLayout, count: Int, in size: CGSize, gap: CGFloat = 4) -> [CGRect] {
    guard count > 0, size.width > 0, size.height > 0 else { return [] }
    let full = CGRect(origin: .zero, size: size)
    if count == 1 { return [full] }
    let portrait = size.height > size.width
    switch layout {
    case .grid:
        return gridFrames(count, size, gap, portrait)
    case .side where !portrait:
        return sideFrames(count, size, gap)
    case .side, .top:
        return portrait ? topFramesPortrait(count, size, gap) : topFrames(count, size, gap)
    }
}

private let ratio: CGFloat = 9.0 / 16.0

/// To ved siden av hverandre (over hverandre når skjermen står), tre eller fire i to rader.
private func gridFrames(_ count: Int, _ size: CGSize, _ gap: CGFloat, _ portrait: Bool) -> [CGRect] {
    if count == 2 {
        if portrait {
            let h = (size.height - gap) / 2
            return (0..<2).map { CGRect(x: 0, y: CGFloat($0) * (h + gap), width: size.width, height: h) }
        }
        let w = (size.width - gap) / 2
        return (0..<2).map { CGRect(x: CGFloat($0) * (w + gap), y: 0, width: w, height: size.height) }
    }
    let w = (size.width - gap) / 2, h = (size.height - gap) / 2
    return (0..<count).map { CGRect(x: CGFloat($0 % 2) * (w + gap), y: CGFloat($0 / 2) * (h + gap), width: w, height: h) }
}

/// Det store til venstre, de små over hverandre til høyre (en tredjedel av bredden), begge midtstilt i høyden.
private func sideFrames(_ count: Int, _ size: CGSize, _ gap: CGFloat) -> [CGRect] {
    let small = count - 1
    var smallWidth = (size.width * 0.3).rounded(.down)
    var smallHeight = smallWidth * ratio
    let column = CGFloat(small) * smallHeight + CGFloat(small - 1) * gap
    if column > size.height {
        smallHeight = (size.height - CGFloat(small - 1) * gap) / CGFloat(small)
        smallWidth = smallHeight / ratio
    }
    let mainWidth = size.width - smallWidth - gap
    let mainHeight = min(size.height, mainWidth * ratio)
    var frames = [CGRect(x: 0, y: (size.height - mainHeight) / 2, width: mainWidth, height: mainHeight)]
    let total = CGFloat(small) * smallHeight + CGFloat(small - 1) * gap
    let top = (size.height - total) / 2
    for i in 0..<small {
        frames.append(CGRect(x: mainWidth + gap, y: top + CGFloat(i) * (smallHeight + gap),
                             width: smallWidth, height: smallHeight))
    }
    return frames
}

/// Det store øverst (to tredjedeler av høyden), de små på en rad under, midtstilt.
private func topFrames(_ count: Int, _ size: CGSize, _ gap: CGFloat) -> [CGRect] {
    let small = count - 1
    let fitting = (size.width - CGFloat(small - 1) * gap) / CGFloat(small) * ratio
    let rowHeight = min((size.height / 3).rounded(.down), fitting)
    let mainHeight = size.height - rowHeight - gap
    let mainWidth = min(size.width, mainHeight / ratio)
    var frames = [CGRect(x: (size.width - mainWidth) / 2, y: 0, width: mainWidth, height: mainHeight)]
    let smallWidth = rowHeight / ratio
    let row = CGFloat(small) * smallWidth + CGFloat(small - 1) * gap
    let left = (size.width - row) / 2
    for i in 0..<small {
        frames.append(CGRect(x: left + CGFloat(i) * (smallWidth + gap), y: mainHeight + gap,
                             width: smallWidth, height: rowHeight))
    }
    return frames
}

/// Skjermen står: det store over hele bredden øverst, de små to og to under (halvparten så brede).
private func topFramesPortrait(_ count: Int, _ size: CGSize, _ gap: CGFloat) -> [CGRect] {
    let mainHeight = min(size.width * ratio, size.height / 2)
    var frames = [CGRect(x: 0, y: 0, width: size.width, height: mainHeight)]
    let small = count - 1
    let smallWidth = (size.width - gap) / 2
    let smallHeight = smallWidth * ratio
    for i in 0..<small {
        let row = i / 2
        let inRow = min(2, small - row * 2)
        let rowWidth = CGFloat(inRow) * smallWidth + CGFloat(inRow - 1) * gap
        let left = (size.width - rowWidth) / 2
        frames.append(CGRect(x: left + CGFloat(i % 2) * (smallWidth + gap),
                             y: mainHeight + gap + CGFloat(row) * (smallHeight + gap),
                             width: smallWidth, height: smallHeight))
    }
    return frames
}

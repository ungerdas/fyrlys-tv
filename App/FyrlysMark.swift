import SwiftUI

/// Fyret fra Fyrlys-ikonet (tegnet etter fyrlys.svg, 64 × 64), med eller uten den mørke flaten bak.
struct FyrlysMark: View {
    var background = true

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 64
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            if background {
                context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 64 * s, height: 64 * s), cornerRadius: 14 * s),
                             with: .color(Theme.bg))
            }
            var right = Path()
            right.move(to: p(32, 22))
            right.addLine(to: p(62, 8))
            right.addLine(to: p(62, 36))
            right.closeSubpath()
            context.fill(right, with: .color(Theme.beam.opacity(0.28)))
            var left = Path()
            left.move(to: p(32, 22))
            left.addLine(to: p(2, 8))
            left.addLine(to: p(2, 36))
            left.closeSubpath()
            context.fill(left, with: .color(Theme.beam.opacity(0.15)))
            context.fill(Path(ellipseIn: CGRect(x: 27 * s, y: 17 * s, width: 10 * s, height: 10 * s)),
                         with: .color(Theme.beam))
            var tower = Path()
            tower.move(to: p(28, 28))
            tower.addLine(to: p(36, 28))
            tower.addLine(to: p(41, 58))
            tower.addLine(to: p(23, 58))
            tower.closeSubpath()
            context.fill(tower, with: .color(Theme.ink2))
            var stripes = Path()
            stripes.move(to: p(26.5, 38))
            stripes.addLine(to: p(37.5, 38))
            stripes.move(to: p(25, 48))
            stripes.addLine(to: p(39, 48))
            context.stroke(stripes, with: .color(Theme.bg), lineWidth: 2.4 * s)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

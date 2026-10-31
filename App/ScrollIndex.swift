import SwiftUI
import UIKit

extension View {
    /// Legges på innholdet i en ScrollView: skrur av hurtigrullingen til Apple TV (prikker langs kanten og et lite felt
    /// som kan få fokus). I sidemenyen la den seg oppå tallene og tok fokus når man trykket til høyre. (Ingenting på
    /// iPhone og iPad.)
    @ViewBuilder
    func hidesScrollIndex() -> some View {
        #if os(tvOS)
        background(ScrollIndexHider().allowsHitTesting(false).accessibilityHidden(true))
        #else
        self
        #endif
    }
}

#if os(tvOS)
/// Finner UIScrollView-en rundt seg og skrur av hurtigrullingen og rullefeltet.
private struct ScrollIndexHider: UIViewRepresentable {
    func makeUIView(context: Context) -> HiderView { HiderView() }

    func updateUIView(_ view: HiderView, context: Context) { view.apply() }

    final class HiderView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        func apply() {
            var view = superview
            while let current = view {
                if let scroll = current as? UIScrollView {
                    scroll.indexDisplayMode = .alwaysHidden
                    scroll.showsVerticalScrollIndicator = false
                    return
                }
                view = current.superview
            }
        }
    }
}
#endif

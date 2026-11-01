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

    #if os(tvOS)
    /// Legges på innholdet i rullelista med kortene ved siden av sidemenyen: fanelinja følger den lista, så den glir
    /// bort når kortene rulles nedover og kommer tilbake øverst. Med to rullelister ved siden av hverandre fulgte Apple
    /// TV ingen av dem, og fanelinja ble stående over kortene (en liste alene på siden, som i 0.1.7, følges av seg selv).
    func movesTabBar() -> some View {
        background(TabBarLink().allowsHitTesting(false).accessibilityHidden(true))
    }
    #endif
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

/// Gir fanen (barnet av UITabBarController) UIScrollView-en rundt seg som `tabBarObservedScrollView`: da flytter UIKit
/// fanelinja i takt med den lista. Finnes ikke en UITabBarController over, gjøres ingenting.
private struct TabBarLink: UIViewRepresentable {
    func makeUIView(context: Context) -> LinkView { LinkView() }

    func updateUIView(_ view: LinkView, context: Context) { view.link() }

    final class LinkView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            link()
        }

        func link() {
            guard window != nil else { return }
            var view = superview
            while let current = view, !(current is UIScrollView) {
                view = current.superview
            }
            guard let scroll = view as? UIScrollView else { return }
            var responder = next
            while let current = responder, !(current is UIViewController) {
                responder = current.next
            }
            var controller = responder as? UIViewController
            while let current = controller, !(current.parent is UITabBarController) {
                controller = current.parent
            }
            guard let tab = controller, tab.tabBarObservedScrollView !== scroll else { return }
            tab.tabBarObservedScrollView = scroll
        }
    }
}
#endif

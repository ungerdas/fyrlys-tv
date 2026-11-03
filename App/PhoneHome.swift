#if os(iOS)
import FyrlysCore
import SwiftUI
import UIKit

/// iPhone (og iPad i et smalt vindu), som Fyrlys-nettsiden på en telefon: topplinja med fyret, «Fyrlys», lys/mørk og
/// Konto, og fanene TV, TV-guide, Filmer og Serier nederst.
struct PhoneHome: View {
    @Environment(AppModel.self) private var model
    @Binding var tab: HomeView.Tab
    @Binding var path: [Shelf]
    @Binding var query: String
    let play: (Channel, [Channel]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            PhoneTopBar()
            TabView(selection: $tab) {
                PhoneTV(path: $path, query: $query, play: play)
                    .tabItem {
                        Label {
                            Text(L("TV"))
                        } icon: {
                            Image(uiImage: TabIcons.tv)
                        }
                    }
                    .tag(HomeView.Tab.tv)
                GuideView(play: play)
                    .tabItem {
                        Label {
                            Text(L("TV-guide"))
                        } icon: {
                            Image(uiImage: TabIcons.guide)
                        }
                    }
                    .tag(HomeView.Tab.guide)
                VODTab(kind: .movies)
                    .tabItem { Label(L("Filmer"), systemImage: "film") }
                    .tag(HomeView.Tab.movies)
                VODTab(kind: .series)
                    .tabItem { Label(L("Serier"), systemImage: "play.rectangle.on.rectangle") }
                    .tag(HomeView.Tab.series)
            }
            .tint(Theme.signal)
        }
        .background(Theme.bg)
        .onAppear {
            // søket og kontoen står på TV-siden og i topplinja her
            if tab == .search || tab == .settings { tab = .tv }
        }
    }
}

/// Topplinja: fyret og «Fyrlys», sola eller månen (bytter mellom lys og mørk modus) og Konto.
private struct PhoneTopBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Appearance.key, store: TestSupport.defaults) private var stored = ""
    @State private var account = TestSupport.screen == "settings"
    @State private var plex = TestSupport.screen == "plex-link"
    @State private var streams = TestSupport.screen == "strommer"

    var body: some View {
        HStack(spacing: 10) {
            FyrlysMark(background: false)
                .frame(width: 34, height: 34)
            Text(verbatim: "Fyrlys")
                .font(.system(size: 21, weight: .bold))
                .tracking(-0.42)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            Button {
                stored = scheme == .light ? "dark" : "light"
            } label: {
                Image(systemName: scheme == .light ? "moon" : "sun.max")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.signal)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tema")
            .accessibilityLabel(L("Bytt mellom lys og mørk modus"))
            Button {
                account = true
            } label: {
                Text(L("Konto"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Capsule().fill(Theme.surface))
                    .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("konto")
            .popover(isPresented: $account, arrowEdge: .top) {
                AccountMenu {
                    account = false
                } openPlex: {
                    account = false
                    // arket vises når menyen har lukket seg
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        plex = true
                    }
                } openStreams: {
                    account = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        streams = true
                    }
                }
                .environment(model)
                .presentationCompactAdaptation(.popover)
                .presentationBackground(Theme.surface)
            }
            .sheet(isPresented: $plex) {
                PlexSheet()
                    .environment(model)
            }
            .sheet(isPresented: $streams) {
                StreamSheet()
                    .environment(model)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(Theme.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.line)
                .frame(height: 1)
        }
    }
}

/// Kontoen, som menyen under Konto på nettsiden: hvem og hvor, når abonnementet går ut, tilkoblingene, hent listene
/// på nytt og logg ut.
private struct AccountMenu: View {
    @Environment(AppModel.self) private var model
    @State private var confirmSignOut = false
    let done: () -> Void
    let openPlex: () -> Void
    let openStreams: () -> Void

    var body: some View {
        // på tvers på iPhone er det ikke alltid plass til alt; da kan menyen rulles
        ViewThatFits(in: .vertical) {
            menu
            ScrollView { menu }
                .scrollIndicators(.visible)
        }
        .alert(L("Logg ut av {name}?", ["name": model.login?.label ?? ""]), isPresented: $confirmSignOut) {
            Button(L("Logg ut"), role: .destructive) {
                done()
                model.signOut()
            }
            Button(L("Avbryt"), role: .cancel) {}
        }
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let login = model.login {
                Text(login.label)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
            if let account = model.account {
                if let expires = account.expires {
                    Text(L("Utløper {date}", ["date": longDate(expires)]))
                }
                if account.maxConnections > 0 {
                    Text(L("{active} av {max} tilkoblinger i bruk",
                           ["active": account.activeConnections, "max": account.maxConnections]))
                }
                if !account.status.isEmpty && account.status.lowercased() != "active" {
                    Text(L("Kontoen har status «{status}» hos leverandøren.", ["status": account.status]))
                        .font(.system(size: 13.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.signal.opacity(0.16)))
                }
            }
            Text(L("{n} kanaler i {c} kategorier", ["n": model.channels.count, "c": model.categories.count]))
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.muted)
            HStack(spacing: 8) {
                Button {
                    Task { await model.reload() }
                    done()
                } label: {
                    menuButton(L("Hent listene nå"))
                }
                .buttonStyle(PressStyle())
                .disabled(model.loading)
                Button {
                    confirmSignOut = true
                } label: {
                    menuButton(L("Logg ut"))
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("logg-ut")
            }
            .padding(.top, 8)
            ForEach(model.logins.filter { $0.id != model.login?.id }, id: \.id) { other in
                Button {
                    model.switchTo(other)
                    done()
                } label: {
                    menuButton(L("Bytt til {name}", ["name": other.label]))
                }
                .buttonStyle(PressStyle())
            }
            Button {
                model.addingLogin = true
                done()
            } label: {
                menuButton(L("Legg til innlogging"))
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("legg-til-innlogging")
            Button(action: openPlex) {
                menuButton(model.plex.client != nil
                           ? L("Plex: {server}", ["server": model.plex.server?.name ?? ""]) : L("Plex …"))
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("plex-innstillinger")
            Button(action: openStreams) {
                menuButton(model.streamLines.isEmpty ? L("Egne strømmer …")
                           : L("Egne strømmer ({n})", ["n": model.streamOverrides.count]))
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("egne-strommer")
            Text(L("Fyrlys {version}", ["version": appVersion]))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)
                .padding(.top, 8)
        }
        .font(.system(size: 14))
        .foregroundStyle(Theme.ink2)
        .padding(14)
        .frame(width: 290, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("innstillinger")
    }

    private func menuButton(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.bg))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// Ikonene i fanelinja, tegnet etter ikonene på nettsiden (24 × 24, strek 1,8).
enum TabIcons {
    static let tv = draw { path in
        path.append(UIBezierPath(roundedRect: CGRect(x: 3, y: 6.5, width: 18, height: 12.5), cornerRadius: 2.5))
        let antenna = UIBezierPath()
        antenna.move(to: CGPoint(x: 8.5, y: 2.5))
        antenna.addLine(to: CGPoint(x: 12, y: 6.5))
        antenna.addLine(to: CGPoint(x: 15.5, y: 2.5))
        path.append(antenna)
    }

    static let guide = draw { path in
        path.append(UIBezierPath(roundedRect: CGRect(x: 3, y: 4, width: 18, height: 16), cornerRadius: 2.5))
        let lines = UIBezierPath()
        for (from, to) in [((3.0, 9.0), (21.0, 9.0)), ((8, 13), (11, 13)), ((13, 13), (18, 13)), ((8, 16.5), (14, 16.5))] {
            lines.move(to: CGPoint(x: from.0, y: from.1))
            lines.addLine(to: CGPoint(x: to.0, y: to.1))
        }
        path.append(lines)
    }

    private static func draw(_ build: (UIBezierPath) -> Void) -> UIImage {
        let path = UIBezierPath()
        build(path)
        path.lineWidth = 1.8
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { _ in
            UIColor.black.setStroke()
            path.stroke()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}

/// Sveip fra venstre kant for å gå tilbake, også når navigasjonslinja er skjult (sidene har sin egen tilbake-knapp,
/// som nettsiden).
struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            enable()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enable()
        }

        private func enable() {
            guard let navigation = navigationController, let pop = navigation.interactivePopGestureRecognizer else {
                return
            }
            SwipeBack.shared.navigation = navigation
            pop.delegate = SwipeBack.shared
            pop.isEnabled = true
        }
    }
}

/// Lar sveipet begynne bare når det er en side å gå tilbake til, og ikke mens en side er på vei inn eller ut (et sveip
/// midt i en overgang kan låse navigasjonen).
final class SwipeBack: NSObject, UIGestureRecognizerDelegate {
    static let shared = SwipeBack()
    weak var navigation: UINavigationController?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // navigasjonen sveipet hører til (det er én per fane), ellers den som sist slo det på
        guard let navigation = (gestureRecognizer.view?.next as? UINavigationController) ?? self.navigation else {
            return false
        }
        return navigation.viewControllers.count > 1 && navigation.transitionCoordinator == nil
    }
}
#endif

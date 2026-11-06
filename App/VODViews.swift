import AVKit
import FyrlysCore
import SwiftUI

// ── fanen ──

/// Fanen Filmer eller Serier (fra IPTV-leverandøren), eller Plex-fanen (filmene og seriene fra Plex sammen): «Hjem» og
/// kategoriene eller bibliotekene (sidemeny på Apple TV og iPad; på iPhone en meny øverst, og i Plex-fanen knapper på
/// en rad), søket (øverst i sidemenyen på Apple TV, over plakatene på iPhone og iPad) og plakatene. En film eller serie
/// åpnes som egen side (Menu eller tilbake går tilbake).
struct VODTab: View {
    @Environment(AppModel.self) private var app
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// søket i filmene eller seriene
    @State private var query = ""
    #endif
    /// filmer eller serier fra IPTV-leverandøren; nil: Plex-fanen
    let kind: VODKind?
    @State private var path = NavigationPath()
    /// Plex: valget av bibliotekene som vises
    @State private var libraries = false
    /// Plex Home: «Hvem ser på?»
    @State private var chooseUser = false

    private var model: VODModel {
        switch kind {
        case .movies?: return app.movies
        case .series?: return app.series
        case nil: return app.plexVOD
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                #if os(iOS)
                // på iPad ellers systemets bakgrunn (svart eller hvit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                #endif
                .navigationDestination(for: VODItem.self) { item in
                    VODDetailView(item: item)
                }
                // «Se alle» for en rad fra Plex
                .navigationDestination(for: VODRow.self) { row in
                    VODRowPage(model: model, row: row)
                }
                #if os(tvOS)
                .navigationDestination(for: VODSearchRoute.self) { _ in
                    VODSearchPage(model: model)
                }
                #endif
        }
        // på nytt når kilden byttes (en annen innlogging, eller Plex)
        .task(id: model.version) { await model.loadCategories() }
        .sheet(isPresented: $libraries) {
            PlexLibrariesSheet()
                .environment(app)
        }
        .sheet(isPresented: $chooseUser) {
            PlexUserSheet()
                .environment(app)
        }
    }

    /// Plex Home: knappen «Hvem ser på?» med navnet på den som ser på (bare når kontoen har flere brukere).
    private var hasHomeUsers: Bool { model.mixed && !app.plex.users.isEmpty }

    /// Plex: «Velg biblioteker» når alle er skjult (ellers holder du inne på et bibliotek, eller går til Innstillinger).
    private var librariesButton: some View {
        Button {
            libraries = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "books.vertical")
                Text(L("Velg biblioteker"))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .accessibilityIdentifier("velg-biblioteker")
    }

    @ViewBuilder
    private var content: some View {
        if !model.loaded {
            if let error = model.error {
                VODMessage(text: error) { Task { await model.loadCategories(force: true) } }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if model.categories.isEmpty {
            if model.isPlex, model.hiddenAll {
                VStack(spacing: 24) {
                    Text(L("Alle bibliotekene er skjult."))
                        .font(.system(size: Metrics.pageCount + 6))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                    librariesButton
                        .fixedSize()
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.isPlex {
                VODMessage(text: L("Ingen biblioteker med filmer eller serier."))
            } else {
                VODMessage(text: kind == .movies ? L("Ingen filmer hos leverandøren.")
                           : L("Ingen serier hos leverandøren."))
            }
        } else {
            #if os(iOS)
            if usesPhoneLayout(sizeClass) { phone } else { split }
            #else
            split
            #endif
        }
    }

    /// Plex-fanen: ikonet foran Hjem og bibliotekene (filmer eller serier).
    private func libraryIcon(_ id: String) -> String {
        if id == VODModel.home { return "house" }
        return model.kind(of: id) == .movies ? "film" : "tv"
    }

    /// Et bibliotek i Plex-fanen (ikke Hjem): hold inne for å flytte eller skjule det.
    private func isLibrary(_ category: ChannelCategory) -> Bool {
        model.mixed && category.id != VODModel.home
    }

    /// Hold inne på et bibliotek: flytt det opp eller ned (til venstre eller høyre i raden på iPhone, [across]), eller
    /// skjul det (det vises igjen under Plex i innstillingene, «Biblioteker»).
    @ViewBuilder
    private func libraryActions(_ id: String, across: Bool) -> some View {
        let libraries = model.categories.map(\.id).filter { $0 != VODModel.home }
        let index = libraries.firstIndex(of: id) ?? 0
        if index > 0 {
            Button {
                app.moveLibrary(id, by: -1, among: libraries)
            } label: {
                Label(across ? L("Flytt til venstre") : L("Flytt opp"), systemImage: across ? "arrow.left" : "arrow.up")
            }
        }
        if index < libraries.count - 1 {
            Button {
                app.moveLibrary(id, by: 1, among: libraries)
            } label: {
                Label(across ? L("Flytt til høyre") : L("Flytt ned"), systemImage: across ? "arrow.right" : "arrow.down")
            }
        }
        Button {
            app.setHidden(id, true)
        } label: {
            Label(L("Skjul"), systemImage: "eye.slash")
        }
    }

    /// En linje i sidemenyen (i Plex-fanen med ikon).
    private func sidebarRow(_ category: ChannelCategory) -> some View {
        let selected = model.chosen == category.id
        return Button {
            model.chosen = category.id
        } label: {
            HStack(spacing: model.mixed ? Metrics.sidebarIcon * 0.65 : 8) {
                if model.mixed {
                    SidebarIcon(name: libraryIcon(category.id), selected: selected)
                }
                Text(category.name)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(SidebarStyle(selected: selected))
        // id-en før hurtigmenyen (etter den ble id-en borte av og til på iPhone og iPad)
        .accessibilityIdentifier("vodkat-\(category.id)")
    }

    /// Apple TV og iPad: kategoriene (i Plex-fanen bibliotekene, med ikon) til venstre, plakatene til høyre.
    private var split: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    #if os(tvOS)
                    // søket i filmene eller seriene (egen side med tastaturet til Apple TV)
                    Button {
                        path.append(VODSearchRoute())
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                            Text(L("Søk"))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(SidebarStyle(selected: false))
                    .accessibilityIdentifier("vod-sok")
                    #endif
                    if hasHomeUsers {
                        Button {
                            chooseUser = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "person.crop.circle")
                                Text(app.plex.user?.name ?? L("Hvem ser på?"))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(SidebarStyle(selected: false))
                        .accessibilityIdentifier("plex-bruker")
                    }
                    ForEach(model.categories) { category in
                        if isLibrary(category) {
                            sidebarRow(category)
                                .contextMenu { libraryActions(category.id, across: false) }
                        } else {
                            sidebarRow(category)
                        }
                    }
                }
                .padding(.vertical, 6)
                .hidesScrollIndex()
            }
            .scrollIndicators(.never)
            .frame(width: Metrics.sidebarWidth)
            .clipped()
            .tvFocusSection()
            Rectangle()
                .fill(Theme.line)
                .frame(width: 1)
                .padding(.vertical, 12)
            #if os(iOS)
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, Metrics.pagePadding)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                pageOrResults(showsTitle: true)
            }
            #else
            page(showsTitle: true)
                .tvFocusSection()
            #endif
        }
        #if os(tvOS)
        .padding(.horizontal, Theme.edge)
        .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
        #else
        .clipped()
        #endif
    }

    #if os(iOS)
    /// iPhone: kategorien i en meny øverst (i Plex-fanen Hjem og bibliotekene som knapper på en rad), plakatene under.
    private var phone: some View {
        VStack(spacing: 0) {
            if model.mixed {
                libraryRow
            } else {
                categoryMenu
            }
            searchField
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            pageOrResults(showsTitle: false)
        }
    }

    private var categoryMenu: some View {
        Menu {
            ForEach(model.categories) { category in
                Button(category.name) { model.chosen = category.id }
            }
        } label: {
            HStack(spacing: 10) {
                Text(model.name(model.chosen))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 18)
            .frame(height: 46)
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        }
        .accessibilityIdentifier("vod-kategori")
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// Plex-fanen på iPhone: Hjem og bibliotekene som knapper på en rad (den kan dras til siden når det er mange); hold
    /// inne på et bibliotek for å flytte eller skjule det.
    private var libraryRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if hasHomeUsers {
                    Button {
                        chooseUser = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.ink2)
                            .frame(width: 44, height: 38)
                            .background(Capsule().fill(Theme.surface))
                            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(app.plex.user?.name ?? L("Hvem ser på?"))
                    .accessibilityIdentifier("plex-bruker")
                }
                ForEach(model.categories) { category in
                    if isLibrary(category) {
                        chip(category)
                            .contextMenu { libraryActions(category.id, across: true) }
                    } else {
                        chip(category)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.never)
        .padding(.top, 8)
    }

    /// Hjem eller et bibliotek på raden øverst på iPhone.
    private func chip(_ category: ChannelCategory) -> some View {
        let selected = model.chosen == category.id
        return Button {
            model.chosen = category.id
        } label: {
            HStack(spacing: 6) {
                Image(systemName: libraryIcon(category.id))
                    .font(.system(size: 13, weight: .semibold))
                Text(category.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Theme.signalInk : Theme.ink2)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Capsule().fill(selected ? Theme.signal : Theme.surface))
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Theme.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vodkat-\(category.id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Søket i filmene eller seriene (en annen kategori tømmer det).
    private var searchField: some View {
        SearchField(text: $query, prompt: searchPrompt(model), id: "vod-sok")
            .onChange(of: model.chosen) { query = "" }
    }

    @ViewBuilder
    private func pageOrResults(showsTitle: Bool) -> some View {
        if searching {
            VODSearchResults(model: model, query: query.trimmingCharacters(in: .whitespaces))
        } else {
            page(showsTitle: showsTitle)
        }
    }
    #endif

    /// Plakatene i kategorien, eller «Hjem» med «Fortsett å se», favorittene og radene.
    @ViewBuilder
    private func page(showsTitle: Bool) -> some View {
        if model.chosen == VODModel.home {
            VODHomeView(model: model) { path.append($0) }
        } else {
            PosterGrid(model: model, category: model.chosen, showsTitle: showsTitle)
        }
    }
}

/// «Søk i filmer», «Søk i serier» eller «Søk i Plex».
@MainActor
func searchPrompt(_ model: VODModel) -> String {
    model.mixed ? L("Søk i Plex") : (model.kind == .movies ? L("Søk i filmer") : L("Søk i serier"))
}

/// Plakatene i en kategori (hentes når kategorien velges); «Fortsett å se» og favorittene står på Hjem.
private struct PosterGrid: View {
    let model: VODModel
    let category: String?
    var showsTitle = true

    /// toppen av lista (den øverste raden ruller dit, så fanelinja på Apple TV kommer helt fram)
    static let top = "toppen"

    /// Apple TV: et fast antall kolonner (det samme som det var plass til), så den øverste raden er kjent; ellers så
    /// mange det er plass til
    private var columns: [GridItem] {
        #if os(tvOS)
        Array(repeating: GridItem(.flexible(), spacing: Metrics.posterGap, alignment: .top),
              count: Metrics.posterColumns)
        #else
        [GridItem(.adaptive(minimum: Metrics.posterMin), spacing: Metrics.posterGap, alignment: .top)]
        #endif
    }

    var body: some View {
        ScrollViewReader { proxy in
            grid {
                withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(Self.top, anchor: .top) }
            }
        }
        .task(id: category) {
            guard let category else { return }
            await model.load(category)
        }
        // IPTV: sortert i rekkefølgen som er valgt (utenfor hovedtråden)
        .task(id: "\(model.sort.rawValue)-\(category.flatMap { model.items[$0]?.count } ?? -1)") {
            if let category { await model.prepareSorted(category) }
        }
        .id(category)
    }

    /// Tittelen (Apple TV og iPad), rekkefølgen og hvor mange.
    private func header(_ items: [VODItem]?) -> some View {
        HStack(alignment: .center, spacing: 20) {
            if showsTitle {
                Text(model.name(category))
                    .font(.system(size: Metrics.pageTitle, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let category {
                VODSortMenu(model: model, category: category)
            }
            if let count = category.flatMap({ model.totals[$0] }) ?? items?.count {
                Text(verbatim: CountText.of(count))
                    .font(.system(size: Metrics.pageCount))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
        // Apple TV: opp fra hvilken som helst plakat i den øverste raden går til menyene (de står til høyre)
        .tvFocusSection()
    }

    private func grid(_ toTop: @escaping () -> Void) -> some View {
        let items = category.flatMap { model.shown($0) }
        #if os(tvOS)
        let firstRow = Set((items ?? []).prefix(Metrics.posterColumns).map(\.id))
        #else
        let firstRow = Set<String>()
        #endif
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(items)
                if let items {
                    if items.isEmpty {
                        Text(L("Ingen her."))
                            .font(.system(size: Metrics.pageCount + 4))
                            .foregroundStyle(Theme.muted)
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: Metrics.posterGap + 8) {
                            ForEach(items) { item in
                                VODPosterLink(item: item, id: "vod-\(item.id)",
                                              onFocus: firstRow.contains(item.id) ? toTop : nil)
                            }
                        }
                        // Apple TV: ned fra menyene til høyre går til plakatene, også når ingen står rett under
                        // (en kategori med to eller tre filmer)
                        .tvFocusSection()
                        // Plex: neste side når de nederste vises
                        if let category, model.hasMore(category) {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .onAppear { Task { await model.loadMore(category) } }
                        }
                    }
                } else if model.error != nil, let category {
                    VODMessage(text: model.error ?? "") { Task { await model.load(category) } }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                }
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 6)
            .padding(.bottom, 24)
            #if os(tvOS)
            .hidesScrollIndex()
            .movesTabBar()
            #endif
            .id(Self.top)
        }
        .scrollIndicators(.never)
        #if os(tvOS)
        .safeAreaPadding(.bottom, Theme.bottomFocus)
        #endif
    }
}

/// Rekkefølgen i en kategori («Leverandørens rekkefølge», «Nyeste først», «A–Å»), og hos Plex rekkefølgen i
/// biblioteket («Nylig lagt til», «A–Å», «Nyeste utgivelser», «Best vurdert», «Sist sett»).
private struct VODSortMenu: View {
    let model: VODModel
    let category: String

    var body: some View {
        HStack(spacing: Metrics.posterGap * 0.5) {
            if model.isPlex {
                ChoiceMenu(title: L("Sortering"),
                           options: PlexSort.allCases.map { MenuOption(value: $0, name: $0.title) },
                           selected: model.plexSort(category), icon: "arrow.up.arrow.down", id: "vod-sortering") {
                    model.setPlexSort($0, for: category)
                }
            } else {
                ChoiceMenu(title: L("Sortering"), options: VODSort.allCases.map { MenuOption(value: $0, name: $0.title) },
                           selected: model.sort, icon: "arrow.up.arrow.down", id: "vod-sortering") {
                    model.setSort($0)
                }
            }
        }
    }
}

/// Et valg i en meny.
private struct MenuOption<Value: Hashable>: Hashable {
    let value: Value
    let name: String
}

/// En meny over plakatene med det som er valgt på knappen. Apple TV: en knapp per valg, med hake ved det som er valgt,
/// så valgene står rett i menyen; iPhone og iPad: en Picker (hakene er systemets).
private struct ChoiceMenu<Value: Hashable>: View {
    let title: String
    let options: [MenuOption<Value>]
    let selected: Value
    let icon: String
    let id: String
    let choose: (Value) -> Void

    var body: some View {
        Menu {
            #if os(tvOS)
            ForEach(options, id: \.value) { option in
                Button {
                    choose(option.value)
                } label: {
                    if option.value == selected {
                        Label(option.name, systemImage: "checkmark")
                    } else {
                        Text(verbatim: option.name)
                    }
                }
            }
            #else
            Picker(title, selection: Binding(get: { selected }, set: { choose($0) })) {
                ForEach(options, id: \.value) { option in
                    Text(verbatim: option.name).tag(option.value)
                }
            }
            #endif
        } label: {
            SortLabel(title: options.first { $0.value == selected }?.name ?? options.first?.name ?? "", icon: icon)
        }
        .accessibilityIdentifier(id)
    }
}

private struct SortLabel: View {
    let title: String
    let icon: String

    var body: some View {
        #if os(tvOS)
        Label(title, systemImage: icon)
            .font(.system(size: 22, weight: .semibold))
            .lineLimit(1)
        #else
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.ink2)
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        #endif
    }
}

extension VODSort {
    var title: String {
        switch self {
        case .provider: return L("Leverandørens rekkefølge")
        case .newest: return L("Nyeste først")
        case .name: return L("A–Å")
        }
    }
}

extension PlexSort {
    var title: String {
        switch self {
        case .added: return L("Nylig lagt til")
        case .title: return L("A–Å")
        case .released: return L("Nyeste utgivelser")
        case .rating: return L("Best vurdert")
        case .viewed: return L("Sist sett")
        }
    }
}

/// Merker som brytes over flere linjer når det ikke er plass (alder, land, «4K», «5.1» …).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            // litt slakk: bredden som gis tilbake, er summen av de samme tallene (ellers kunne det siste merket havne på
            // en ny linje som det ikke var satt av plass til, oppå teksten under)
            if x > 0, x + size.width > width + 1 {
                x = 0
                y += row + spacing
                row = 0
            }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX + 1 {
                x = bounds.minX
                y += row + spacing
                row = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

/// Et merke på siden for en film eller serie; merkene fra navnet («PRE») er gule.
struct InfoBadge: View {
    let text: String
    var accent = false

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: Metrics.badge, weight: .semibold))
            .foregroundStyle(accent ? Theme.signalInk : Theme.ink2)
            .lineLimit(1)
            .padding(.horizontal, Metrics.badge * 0.6)
            .padding(.vertical, Metrics.badge * 0.25)
            .background(accent ? Theme.signal : Theme.surface2,
                        in: RoundedRectangle(cornerRadius: Metrics.badge * 0.35, style: .continuous))
            .accessibilityIdentifier("merke-\(text)")
    }
}

/// Plakaten med tittel, år og terningkast; for en episode (radene fra Plex) seriens plakat med serien, episoden og
/// sesong og nummer. På iPhone og iPad står teksten under bildet (som i Plex og IPTV-appene), på Apple TV i kortet.
struct PosterCard: View {
    let item: VODItem
    var episode: Episode?

    var body: some View {
        #if os(tvOS)
        VStack(alignment: .leading, spacing: 0) {
            image
            text
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        #else
        VStack(alignment: .leading, spacing: 7) {
            image
                .clipShape(RoundedRectangle(cornerRadius: Metrics.posterRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Metrics.posterRadius, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 0.5))
            text
        }
        .contentShape(Rectangle())
        #endif
    }

    private var image: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                RemoteImage(url: item.poster.flatMap { URL(string: $0) }, fill: true) {
                    ZStack {
                        LinearGradient(colors: [Theme.surface2, Theme.logoBg], startPoint: .top, endPoint: .bottom)
                        Text(item.name)
                            .font(.system(size: Metrics.posterTitle + 2, weight: .bold))
                            .foregroundStyle(Theme.ink2)
                            .multilineTextAlignment(.center)
                            .padding(10)
                    }
                }
            }
            .clipped()
            .overlay(alignment: .topLeading) {
                // merkene fra navnet hos leverandøren («PRE»), høyst to
                if episode == nil, let tags = item.tags, !tags.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(tags.prefix(2)), id: \.self) { tag in
                            Text(verbatim: tag.uppercased())
                                .font(.system(size: Metrics.posterTag, weight: .bold))
                                .foregroundStyle(Theme.signalInk)
                                .lineLimit(1)
                                .padding(.horizontal, Metrics.posterTag * 0.45)
                                .padding(.vertical, Metrics.posterTag * 0.15)
                                .background(Theme.signal, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                    }
                    .padding(Metrics.posterTag * 0.6)
                }
            }
            .overlay(alignment: .topTrailing) {
                if episode?.watched ?? (item.watched == true) {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .font(.system(size: Metrics.posterTitle + 6, weight: .semibold))
                        .foregroundStyle(Theme.signalInk, Theme.signal)
                        .padding(8)
                        .accessibilityLabel(L("Sett"))
                }
            }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.name)
                .font(.system(size: Metrics.posterTitle, weight: .semibold))
                .foregroundStyle(Theme.ink)
                // på Apple TV like høye kort (plass til to linjer); på iPhone og iPad året rett under tittelen
                #if os(tvOS)
                .lineLimit(episode == nil ? 2 : 1, reservesSpace: true)
                #else
                .lineLimit(episode == nil ? 2 : 1)
                #endif
                .multilineTextAlignment(.leading)
            if let episode {
                Text(episode.title)
                    .font(.system(size: Metrics.posterTitle - 2))
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
            }
            Text(verbatim: meta)
                .font(.system(size: Metrics.posterTitle - 3))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
    }

    private var meta: String {
        if let episode { return "S\(episode.season) · E\(episode.number)" }
        return [item.year, item.rating.map(ratingText)].compactMap { $0 }.joined(separator: "  ")
    }
}

extension View {
    /// Plakatene som knapp: løftes når de har fokus på Apple TV, vanlige på iPhone og iPad.
    @ViewBuilder
    func posterButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(.card)
        #else
        buttonStyle(.plain)
        #endif
    }
}

/// En melding midt på (ingen filmer, feil), eventuelt med «Prøv igjen».
private struct VODMessage: View {
    let text: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            Text(text)
                .font(.system(size: Metrics.pageCount + 6))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            if let retry {
                Button(L("Prøv igjen"), action: retry)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ── en medvirkende ──

/// Bildet i en sirkel (ellers forbokstavene på en rolig flate), navnet og rollen under.
struct PersonCard: View {
    let person: VODPerson

    var body: some View {
        VStack(spacing: 8) {
            RemoteImage(url: person.image.flatMap { URL(string: $0) }, fill: true) {
                ZStack {
                    Theme.surface2
                    Text(initials(person.name))
                        .font(.system(size: Metrics.person * 0.34, weight: .semibold))
                        .foregroundStyle(Theme.ink2)
                }
            }
            .frame(width: Metrics.person, height: Metrics.person)
            .clipShape(Circle())
            Text(person.name)
                .font(.system(size: Metrics.detailText - 4, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if let role = person.role {
                Text(role)
                    .font(.system(size: Metrics.detailText - 6))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: Metrics.personWidth)
        .accessibilityElement(children: .combine)
    }
}

// ── siden for en film eller serie ──

/// Plakaten, tittelen, år, sjanger, lengde og terningkast, handlingen og «Spill av» (filmer, med «Fortsett» når du
/// har sett noe), eller sesongene og episodene (serier).
struct VODDetailView: View {
    @Environment(AppModel.self) private var app
    let item: VODItem
    @State private var details: VODDetails?
    @State private var error: String?
    @State private var season: Int?
    @State private var playing: VODPlay?
    /// telles opp når spilleren lukkes, så «Fortsett» viser hvor langt du kom
    @State private var watched = 0
    /// «Mer som dette» (Plex) eller «Mer fra <kategori>» (leverandøren)
    @State private var related: [VODItem] = []
    @State private var relatedTitle = ""
    /// merker som sett eller ikke sett
    @State private var busy = false
    /// en feil som vises en liten stund (Plex svarte ikke da noe skulle merkes som sett)
    @State private var notice: String?

    private var model: VODModel { app.vod(for: item) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                header
                peopleRow
                if item.kind == .series {
                    episodes
                }
                relatedRow
            }
            .padding(.horizontal, Metrics.detailPadding)
            .padding(.vertical, Metrics.detailPadding * 0.6)
            // til venstre (en smal side ble ellers lagt midt i rullelista)
            .frame(maxWidth: .infinity, alignment: .leading)
            #if os(tvOS)
            .hidesScrollIndex()
            #endif
        }
        .scrollIndicators(.never)
        .background(backdropLayer)
        .task { await load() }
        #if os(tvOS)
        .fullScreenCover(item: $playing, onDismiss: closed) { play in
            VODPlayerView(play: play)
                .environment(app)
        }
        #else
        .sheet(item: $playing, onDismiss: closed) { play in
            VODPlayerView(play: play)
                .environment(app)
                .preferredColorScheme(.dark)
                .presentationDragIndicator(.visible)
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        // stjernen oppe til høyre (ved siden av «Spill av» var det ikke plass på iPhone)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if details != nil {
                    Menu {
                        watchedButton
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(L("Mer"))
                    .accessibilityIdentifier("vod-mer")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                favoriteButton
            }
        }
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vod-side")
    }

    /// Favoritt eller ikke (filmen eller serien står da under «Favoritter» på Hjem).
    private var favoriteButton: some View {
        let favorite = app.isVODFavorite(item)
        return Button {
            app.toggleVODFavorite(item)
        } label: {
            #if os(tvOS)
            Label(favorite ? L("Favoritt") : L("Legg til i favoritter"), systemImage: favorite ? "star.fill" : "star")
            #else
            Image(systemName: favorite ? "star.fill" : "star")
                .foregroundStyle(favorite ? Theme.signal : Theme.ink)
            #endif
        }
        .accessibilityLabel(favorite ? L("Fjern fra favoritter") : L("Legg til i favoritter"))
        .accessibilityValue(favorite ? L("Favoritt") : "")
        .accessibilityIdentifier("vod-favoritt")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Metrics.detailPadding * 0.8) {
            RemoteImage(url: (details?.poster ?? item.poster).flatMap { URL(string: $0) }, fill: true) {
                LinearGradient(colors: [Theme.surface2, Theme.logoBg], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: Metrics.detailPoster, height: Metrics.detailPoster * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 14) {
                titleView
                if let tagline = details?.tagline {
                    Text(tagline)
                        .font(.system(size: Metrics.detailText, weight: .medium).italic())
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(2)
                }
                let badges = badgeList
                if !badges.isEmpty {
                    FlowLayout(spacing: Metrics.badge * 0.5) {
                        ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                            InfoBadge(text: badge.text, accent: badge.accent)
                        }
                    }
                }
                if let details {
                    if !details.plot.isEmpty {
                        Text(details.plot)
                            .font(.system(size: Metrics.detailText))
                            .foregroundStyle(Theme.ink2)
                            .lineLimit(8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // de medvirkende står i raden under når de finnes, ellers som en linje
                    if details.people.isEmpty, !details.cast.isEmpty {
                        Text(L("Med: {cast}", ["cast": details.cast]))
                            .font(.system(size: Metrics.detailText - 3))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(2)
                    }
                    if !details.director.isEmpty {
                        Text(L("Regi: {name}", ["name": details.director]))
                            .font(.system(size: Metrics.detailText - 3))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                } else if let error {
                    Text(error)
                        .font(.system(size: Metrics.detailText))
                        .foregroundStyle(Theme.muted)
                } else {
                    ProgressView()
                }
                #if os(tvOS)
                HStack(spacing: 24) {
                    if item.kind == .movies {
                        movieButtons
                    } else if let details, let next = nextEpisode(details) {
                        seriesButton(next)
                    }
                    favoriteButton
                    watchedButton
                }
                .padding(.top, 10)
                #else
                if item.kind == .movies {
                    movieButtons
                        .padding(.top, 10)
                } else if let details, let next = nextEpisode(details) {
                    seriesButton(next)
                        .padding(.top, 10)
                }
                #endif
                noticeText
            }
        }
    }

    /// Tittelen: logoen til filmen eller serien når Plex har den (ellers, og til den er lastet, navnet som tekst).
    @ViewBuilder
    private var titleView: some View {
        if let logo = details?.logo.flatMap({ URL(string: $0) }) {
            RemoteImage(url: logo) {
                titleText
            }
            .frame(maxWidth: Metrics.detailLogo, maxHeight: Metrics.detailLogo * 0.38, alignment: .leading)
            .accessibilityLabel(item.name)
            .accessibilityIdentifier("vod-logo")
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(item.name)
            .font(.system(size: Metrics.detailTitle, weight: .bold))
            .foregroundStyle(Theme.ink)
            .lineLimit(3)
    }

    /// Bakgrunnsbildet til filmen eller serien øverst, tonet over i bakgrunnen nedover og mot venstre, så teksten
    /// og plakaten står på noe rolig. Står fast mens siden rulles.
    private var backdropLayer: some View {
        ZStack(alignment: .top) {
            Theme.bg
            if let url = details?.backdrop.flatMap({ URL(string: $0) }) {
                RemoteImage(url: url, fill: true) {
                    Color.clear
                }
                .frame(height: Metrics.detailBackdrop)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(LinearGradient(colors: [Theme.bg.opacity(0.35), Theme.bg.opacity(0.75), Theme.bg],
                                        startPoint: .top, endPoint: .bottom))
                .overlay(LinearGradient(colors: [Theme.bg.opacity(0.8), Theme.bg.opacity(0.2), .clear],
                                        startPoint: .leading, endPoint: .trailing))
                .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
    }

    /// «Medvirkende»: rollene med bilde (Plex) eller bare navnene (leverandøren). På Apple TV de første som får
    /// plass på én linje, på iPhone og iPad en rad som kan rulles.
    @ViewBuilder
    private var peopleRow: some View {
        if let details, !details.people.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.shelfTitleGap) {
                Text(L("Medvirkende"))
                    .font(.system(size: Metrics.shelfTitle, weight: .semibold))
                    .foregroundStyle(Theme.ink2)
                #if os(tvOS)
                HStack(alignment: .top, spacing: Metrics.personGap) {
                    ForEach(details.people.prefix(Metrics.personCount)) { person in
                        PersonCard(person: person)
                    }
                }
                #else
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: Metrics.personGap) {
                        ForEach(details.people) { person in
                            PersonCard(person: person)
                        }
                    }
                }
                .scrollIndicators(.never)
                #endif
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("medvirkende")
        }
    }

    /// En feil en liten stund under knappene.
    @ViewBuilder
    private var noticeText: some View {
        if let notice {
            Text(notice)
                .font(.system(size: Metrics.detailText - 3))
                .foregroundStyle(Theme.muted)
                .task(id: notice) {
                    try? await Task.sleep(for: .seconds(4))
                    self.notice = nil
                }
        }
    }

    /// «Merk som sett» eller «Merk som ikke sett»: filmen, eller hele serien (Plex på serveren, ellers på enheten).
    @ViewBuilder
    private var watchedButton: some View {
        if let details {
            let seen = isWatched(details)
            Button {
                Task { await markWatched(!seen, details) }
            } label: {
                Label(seen ? L("Merk som ikke sett") : L("Merk som sett"),
                      systemImage: seen ? "eye.slash" : "checkmark.circle")
            }
            .disabled(busy)
            .accessibilityIdentifier("merk-sett")
        }
    }

    /// Filmen er sett (og ikke begynt på igjen), eller alle episodene i serien (uten spesialene).
    private func isWatched(_ details: VODDetails) -> Bool {
        let _ = watched
        if item.kind == .movies {
            let started = app.progress(item.progressKey) > 0
            return item.isPlex ? details.watched && details.resume == 0 && !started
                : app.isFinished(item.progressKey) && !started
        }
        let regular = details.seasons.filter { $0.number != 0 }.flatMap(\.episodes)
        let all = regular.isEmpty ? details.seasons.flatMap(\.episodes) : regular
        return !all.isEmpty && all.allSatisfy(finished)
    }

    private func markWatched(_ seen: Bool, _ details: VODDetails) async {
        busy = true
        defer { busy = false }
        let keys = item.kind == .movies ? [item.progressKey] : details.seasons.flatMap(\.episodes).map(\.progressKey)
        if item.isPlex {
            do {
                try await model.setWatched(item.id, seen)
            } catch {
                notice = error.localizedDescription
                return
            }
        }
        for key in keys {
            if !item.isPlex { app.setFinished(key, seen) }
            app.setProgress(key, nil)
            if seen { model.finishedHere.insert(key) } else { model.finishedHere.remove(key) }
        }
        if !item.isPlex { app.forgetContinue(item) }
        watched += 1
        if item.isPlex { await reloadPlex() }
    }

    /// En episode som sett eller ikke sett (hold inne på den).
    private func markEpisode(_ episode: Episode, _ seen: Bool) {
        Task {
            let plex = episode.source == "plex"
            if plex {
                do {
                    try await model.setWatched(episode.id, seen)
                } catch {
                    notice = error.localizedDescription
                    return
                }
            } else {
                app.setFinished(episode.progressKey, seen)
            }
            app.setProgress(episode.progressKey, nil)
            if seen {
                model.finishedHere.insert(episode.progressKey)
            } else {
                model.finishedHere.remove(episode.progressKey)
            }
            watched += 1
            if plex { await reloadPlex() }
        }
    }

    /// «Mer som dette» (Plex: filmer og serier som ligner) eller «Mer fra <kategori>» (leverandøren) under.
    @ViewBuilder
    private var relatedRow: some View {
        if !related.isEmpty {
            VODShelf(title: relatedTitle) {
                ForEach(related) { other in
                    VODPosterLink(item: other, id: "lik-\(other.id)")
                        .frame(width: Metrics.rowPoster)
                }
            }
        }
    }

    /// Merkene under tittelen: merkene fra navnet («PRE»), året, sjangeren, lengden (serier: sesonger og episoder),
    /// terningkastet, aldersgrensen, landet og kvaliteten (bildet og lyden).
    private var badgeList: [(text: String, accent: Bool)] {
        let d = details
        var list: [(text: String, accent: Bool)] = (item.tags ?? []).map { (text: $0.uppercased(), accent: true) }
        var plain: [String?] = [d?.year ?? item.year, d.map(\.genre).flatMap { $0.isEmpty ? nil : $0 }]
        if item.kind == .series, let d {
            let seasons = d.seasons.filter { $0.number != 0 }.count
            let episodes = d.seasons.reduce(0) { $0 + $1.episodes.count }
            if seasons > 1 { plain.append(L("{n} sesonger", ["n": seasons])) }
            if episodes > 0 { plain.append(episodes == 1 ? L("1 episode") : L("{n} episoder", ["n": episodes])) }
        } else {
            plain.append(d.map(\.duration).flatMap { $0.isEmpty ? nil : $0 })
        }
        plain += [(d?.rating ?? item.rating).map(ratingText), d?.age, d?.country, d?.studio]
        list += plain.compactMap { $0 }.map { (text: $0, accent: false) }
        list += (d?.quality ?? []).map { (text: $0, accent: false) }
        return list
    }

    private var meta: String {
        let d = details
        let parts: [String?] = [
            d?.year ?? item.year,
            d.map(\.genre).flatMap { $0.isEmpty ? nil : $0 },
            d.map(\.duration).flatMap { $0.isEmpty ? nil : $0 },
            (d?.rating ?? item.rating).map { String(format: "★ %.1f", $0) },
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private var movieButtons: some View {
        let _ = watched
        let saved = app.progress(item.progressKey)
        return HStack(spacing: 24) {
            Button {
                startMovie(at: saved)
            } label: {
                Label(saved > 0 ? L("Fortsett ({time})", ["time": playTime(saved)]) : L("Spill av"),
                      systemImage: "play.fill")
            }
            .vodPrimary()
            // Plex: fila står på siden, som hentes først (før gjorde knappen ingenting til da)
            .disabled(item.isPlex && details == nil)
            .accessibilityIdentifier("spill-av")
            if saved > 0 {
                Button {
                    startMovie(at: 0)
                } label: {
                    Label(L("Fra start"), systemImage: "arrow.counterclockwise")
                }
                .accessibilityIdentifier("fra-start")
            }
        }
    }

    /// Episoden du skal se: den du er midt i (når den kommer etter den siste du har sett ferdig), ellers den etter den
    /// siste du har sett, ellers den første. Spesialene (sesong 0) teller ikke med.
    private func nextEpisode(_ details: VODDetails) -> (episode: Episode, seen: Double, after: Bool)? {
        let _ = watched
        let regular = details.seasons.filter { $0.number != 0 }.flatMap(\.episodes)
        let all = regular.isEmpty ? details.seasons.flatMap(\.episodes) : regular
        guard let first = all.first else { return nil }
        let lastSeen = all.lastIndex(where: finished)
        // en gammel, avbrutt episode før den siste du har sett ferdig, er ikke den du skal se
        if let current = all.lastIndex(where: { app.progress($0.progressKey) > 0 }),
           lastSeen.map({ current > $0 }) ?? true {
            return (all[current], app.progress(all[current].progressKey), false)
        }
        if let lastSeen {
            return lastSeen + 1 < all.count ? (all[lastSeen + 1], 0, true) : (first, 0, false)
        }
        return (first, 0, false)
    }

    /// Sett ferdig: Plex vet det selv (og der kan noe merkes som usett igjen); ellers det enheten husker.
    private func finished(_ episode: Episode) -> Bool {
        episode.source == "plex" ? episode.watched : (episode.watched || app.isFinished(episode.progressKey))
    }

    /// «Fortsett S1 E3 (4:45)», «Neste: S1 E4» eller «Spill av S1 E1»: rett til episoden du skal se.
    private func seriesButton(_ next: (episode: Episode, seen: Double, after: Bool)) -> some View {
        let code = "S\(next.episode.season) E\(next.episode.number)"
        let title = next.seen > 0 ? L("Fortsett {episode} ({time})", ["episode": code, "time": playTime(next.seen)])
            : next.after ? L("Neste: {episode}", ["episode": code]) : L("Spill av {episode}", ["episode": code])
        return Button {
            play(next.episode)
        } label: {
            Label(title, systemImage: "play.fill")
        }
        .vodPrimary()
        .accessibilityIdentifier("fortsett-serie")
    }

    @ViewBuilder
    private var episodes: some View {
        if let details {
            if details.seasons.isEmpty {
                Text(L("Ingen episoder."))
                    .font(.system(size: Metrics.detailText))
                    .foregroundStyle(Theme.muted)
            } else {
                let current = season ?? details.seasons[0].number
                VStack(alignment: .leading, spacing: 20) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 16) {
                            ForEach(details.seasons) { s in
                                Button {
                                    season = s.number
                                } label: {
                                    Text(L("Sesong {n}", ["n": s.number]))
                                        .fontWeight(s.number == current ? .bold : .regular)
                                }
                                .vodSeason(selected: s.number == current)
                                .accessibilityIdentifier("sesong-\(s.number)")
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    .scrollIndicators(.never)
                    #if os(tvOS)
                    .scrollClipDisabled()
                    .focusSection()
                    #endif
                    LazyVStack(alignment: .leading, spacing: 14) {
                        let _ = watched
                        ForEach(details.seasons.first { $0.number == current }?.episodes ?? []) { episode in
                            Button {
                                play(episode)
                            } label: {
                                EpisodeRow(episode: episode, seen: app.progress(episode.progressKey),
                                           finished: finished(episode))
                            }
                            .posterButtonStyle()
                            // id-en før hurtigmenyen (etter den ble id-en borte av og til på iPhone og iPad)
                            .accessibilityIdentifier("episode-\(episode.id)")
                            .contextMenu {
                                let done = finished(episode)
                                if !done {
                                    Button {
                                        markEpisode(episode, true)
                                    } label: {
                                        Label(L("Merk som sett"), systemImage: "checkmark.circle")
                                    }
                                }
                                if done || app.progress(episode.progressKey) > 0 {
                                    Button {
                                        markEpisode(episode, false)
                                    } label: {
                                        Label(L("Merk som ikke sett"), systemImage: "eye.slash")
                                    }
                                }
                            }
                        }
                    }
                    #if os(tvOS)
                    .focusSection()
                    #endif
                }
            }
        }
    }

    private func load() async {
        guard details == nil else { return }
        do {
            let found = try await model.details(item)
            if item.isPlex { syncProgress(found) }
            details = found
            error = nil
            // sesongen med episoden du skal se
            if season == nil, let next = nextEpisode(found) { season = next.episode.season }
        } catch {
            self.error = error.localizedDescription
            return
        }
        if item.isPlex {
            related = await model.related(item)
            relatedTitle = L("Mer som dette")
        } else {
            let more = await model.moreFrom(item)
            related = more.items
            relatedTitle = more.title
        }
    }

    /// Plex: hvor langt du har sett, slik Plex har det (også fra de andre Plex-appene).
    private func syncProgress(_ found: VODDetails) {
        if item.kind == .movies {
            // også når filmen er sett før og ses på nytt (da har Plex både «sett» og hvor langt du er kommet)
            app.setProgress(item.progressKey, found.resume > 0 ? found.resume : nil)
        }
        for episode in found.seasons.flatMap(\.episodes) {
            app.setProgress(episode.progressKey, episode.resume > 0 ? episode.resume : nil)
        }
    }

    /// Spilleren er lukket: «Fortsett» og episodene viser hvor langt du kom, og med Plex hentes siden og «Fortsett å
    /// se» på nytt (litt etter, så Plex har fått med seg det siste).
    private func closed() {
        watched += 1
        guard item.isPlex else { return }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await reloadPlex()
        }
    }

    /// Plex: siden på nytt (hva som er sett, og hvor langt) og «Fortsett å se».
    private func reloadPlex() async {
        if let found = try? await model.details(item) {
            syncProgress(found)
            details = found
            watched += 1
        }
        await model.refreshContinue()
    }

    private func startMovie(at seconds: Double) {
        let urls = model.movieURLs(item, details)
        guard !urls.isEmpty else { return }
        playing = VODPlay(id: item.progressKey, urls: urls, title: item.name, subtitle: meta,
                          progressKey: item.progressKey, start: seconds, item: item,
                          plex: item.isPlex ? item.id : nil, image: details?.backdrop)
    }

    /// En episode der du slapp; spilleren har hele serien (forrige og neste episode).
    private func play(_ episode: Episode) {
        Task {
            if let play = await model.play(episode, show: item, app: app, image: details?.backdrop ?? episode.image,
                                            seasons: details?.seasons) {
                playing = play
            }
        }
    }
}

/// En episode: nummeret, tittelen, handlingen og lengden, og hvor langt du har sett.
private struct EpisodeRow: View {
    let episode: Episode
    let seen: Double
    var finished = false

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Text(verbatim: "\(episode.number)")
                .font(.system(size: Metrics.detailText + 4, weight: .bold))
                .foregroundStyle(Theme.signal)
                .frame(width: Metrics.detailText * 2.2, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text(episode.title)
                    .font(.system(size: Metrics.detailText, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if !episode.plot.isEmpty {
                    Text(episode.plot)
                        .font(.system(size: Metrics.detailText - 4))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if seen > 0 {
                    Text(L("Sett til {time}", ["time": playTime(seen)]))
                        .font(.system(size: Metrics.detailText - 5, weight: .medium))
                        .foregroundStyle(Theme.signal)
                } else if finished {
                    Label(L("Sett"), systemImage: "checkmark")
                        .font(.system(size: Metrics.detailText - 5, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
            if !episode.duration.isEmpty {
                Text(verbatim: episode.duration)
                    .font(.system(size: Metrics.detailText - 4))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension View {
    /// «Spill av»: gul på iPhone og iPad (fokus gjør jobben på Apple TV).
    @ViewBuilder
    func vodPrimary() -> some View {
        #if os(iOS)
        buttonStyle(.borderedProminent)
            .tint(Theme.signal)
            .foregroundStyle(Theme.signalInk)
        #else
        self
        #endif
    }

    /// Sesong- og dagknappene: den valgte er gul (på Apple TV mørk tekst på lys flate når den har fokus).
    @ViewBuilder
    func vodSeason(selected: Bool) -> some View {
        #if os(iOS)
        buttonStyle(.bordered)
            .tint(selected ? Theme.signal : Theme.muted)
        #else
        buttonStyle(PillStyle(selected: selected))
        #endif
    }
}

#if os(tvOS)
/// En pille på Apple TV: lys med mørk tekst i fokus, ellers gul tekst på en litt lysere flate når den er valgt.
struct PillStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        PillLabel(label: configuration.label, selected: selected, pressed: configuration.isPressed)
    }
}

private struct PillLabel<Label: View>: View {
    let label: Label
    let selected: Bool
    let pressed: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        label
            .font(.system(size: 26, weight: selected ? .bold : .medium))
            .foregroundStyle(focused ? Theme.bg : (selected ? Theme.signal : Theme.ink))
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(Capsule().fill(focused ? Theme.ink : (selected ? Theme.surface2 : Theme.surface)))
            .scaleEffect(focused ? (pressed ? 1.0 : 1.06) : 1)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}
#endif

/// «★ 7,5» (på engelsk «★ 7.5»); hele tall uten desimaler.
func ratingText(_ rating: Double) -> String {
    let rounded = (rating * 10).rounded() / 10
    let number = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    return "★ " + (appLanguage == "no" ? number.replacingOccurrences(of: ".", with: ",") : number)
}

#if os(tvOS)
/// Søket i filmene, seriene eller Plex på Apple TV (fra sidemenyen; fanen vet hvor det søkes).
struct VODSearchRoute: Hashable {}

/// Apple TV: søket i filmene eller seriene, med tastaturet til Apple TV øverst og treffene under.
struct VODSearchPage: View {
    let model: VODModel
    @State private var query = ""

    var body: some View {
        VODSearchResults(model: model, query: query.trimmingCharacters(in: .whitespaces))
            .searchable(text: $query, prompt: searchPrompt(model))
            .background(Theme.bg.ignoresSafeArea())
    }
}
#endif

/// 1:02:03 eller 12:34.
func playTime(_ seconds: Double) -> String {
    let s = max(0, Int(seconds))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
        : String(format: "%d:%02d", s / 60, s % 60)
}

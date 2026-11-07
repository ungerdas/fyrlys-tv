import FyrlysCore
import SwiftUI

/// TV-arkivet for en kanal: dagene øverst (i dag, i går …) og programmene den dagen, det nyeste først. Et program
/// spilles fra start i spilleren for filmer (med spoling), også det som går nå («se fra start»).
struct ArchiveView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let channel: Channel
    @State private var items: [ArchiveItem]?
    @State private var error: String?
    @State private var day: Date?
    @State private var playing: VODPlay?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text(L("TV-arkiv: {channel}", ["channel": nameParts(channel.name).main]))
                    .font(.system(size: Metrics.detailTitle, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                #if !os(tvOS)
                Button(L("Lukk")) { dismiss() }
                    .accessibilityIdentifier("lukk-arkiv")
                #endif
            }
            if let items {
                let days = Self.days(items)
                if days.isEmpty {
                    Text(L("Ingenting i arkivet de siste dagene."))
                        .font(.system(size: Metrics.detailText))
                        .foregroundStyle(Theme.muted)
                } else {
                    let current = day ?? days[0].day
                    ScrollView(.horizontal) {
                        HStack(spacing: 16) {
                            ForEach(days, id: \.day) { d in
                                Button(Self.name(d.day)) { day = d.day }
                                    .vodSeason(selected: d.day == current)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .scrollIndicators(.never)
                    #if os(tvOS)
                    .scrollClipDisabled()
                    .focusSection()
                    #endif
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(days.first { $0.day == current }?.items ?? []) { item in
                                Button {
                                    play(item)
                                } label: {
                                    ArchiveRow(item: item)
                                }
                                .posterButtonStyle()
                                .disabled(!item.available)
                                .accessibilityIdentifier("arkiv-\(Int(item.program.start.timeIntervalSince1970))")
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    .scrollIndicators(.never)
                    #if os(tvOS)
                    .focusSection()
                    #endif
                }
            } else if let error {
                Text(error)
                    .font(.system(size: Metrics.detailText))
                    .foregroundStyle(Theme.muted)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
        }
        .padding(Metrics.detailPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg.ignoresSafeArea())
        .task { await load() }
        #if os(tvOS)
        .fullScreenCover(item: $playing) { play in
            VODPlayerView(play: play)
                .environment(app)
        }
        #else
        .sheet(item: $playing) { play in
            VODPlayerView(play: play)
                .environment(app)
                .preferredColorScheme(.dark)
                .presentationDragIndicator(.visible)
        }
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("arkiv")
    }

    private func load() async {
        guard items == nil, let client = app.client else { return }
        do {
            items = try await client.archive(channel)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func play(_ item: ArchiveItem) {
        guard let client = app.client else { return }
        Task {
            let clock = await app.serverClock()
            playing = VODPlay.archive(channel, item.program, client: client, clock: clock)
        }
    }

    /// Programmene dag for dag, den nyeste dagen og det nyeste programmet først.
    static func days(_ items: [ArchiveItem]) -> [(day: Date, items: [ArchiveItem])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: items) { calendar.startOfDay(for: $0.program.start) }
        return groups.keys.sorted(by: >).map { day in
            (day, (groups[day] ?? []).sorted { a, b in a.program.start > b.program.start })
        }
    }

    /// «I dag», «I går», ellers ukedagen og datoen.
    static func name(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return L("I dag") }
        if calendar.isDateInYesterday(day) { return L("I går") }
        let format = DateFormatter()
        format.locale = Locale(identifier: appLanguage == "no" ? "nb_NO" : "en_GB")
        format.setLocalizedDateFormatFromTemplate("EEEEdMMM")
        return format.string(from: day)
    }
}

/// Et program i arkivet: tiden, tittelen og handlingen, og om det går nå eller ikke er i arkivet.
private struct ArchiveRow: View {
    let item: ArchiveItem

    var body: some View {
        let p = item.program
        let live = p.stop > Date()
        HStack(alignment: .top, spacing: 18) {
            Text(verbatim: "\(hhmm(p.start))–\(hhmm(p.stop))")
                .font(.system(size: Metrics.detailText - 2, weight: .semibold).monospacedDigit())
                .foregroundStyle(item.available ? Theme.signal : Theme.muted)
                .frame(width: Metrics.detailText * 5.4, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Text(p.title)
                    .font(.system(size: Metrics.detailText, weight: .semibold))
                    .foregroundStyle(item.available ? Theme.ink : Theme.muted)
                    .lineLimit(1)
                if !p.description.isEmpty {
                    Text(p.description)
                        .font(.system(size: Metrics.detailText - 4))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
            if live {
                Text(L("Går nå"))
                    .font(.system(size: Metrics.detailText - 5, weight: .bold))
                    .foregroundStyle(Theme.live)
            } else if !item.available {
                Text(L("Ikke i arkivet"))
                    .font(.system(size: Metrics.detailText - 5))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

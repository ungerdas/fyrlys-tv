import FyrlysCore
import Foundation
import Observation

/// Filmene eller seriene: kategoriene (hentes første gang fanen vises), kategorien som er valgt, og lista for hver
/// kategori (hentes når den velges, og huskes til innloggingen byttes).
@MainActor
@Observable
final class VODModel {
    let kind: VODKind
    private(set) var categories: [ChannelCategory] = []
    private(set) var items: [String: [VODItem]] = [:]
    private(set) var loadingCategories = false
    private(set) var loadingItems: Set<String> = []
    /// kategoriene er hentet (tom liste = leverandøren har ingen)
    private(set) var loaded = false
    private(set) var error: String?
    /// kategorien som vises
    var chosen: String?

    @ObservationIgnored private var client: XtreamClient?
    @ObservationIgnored private var generation = 0

    init(kind: VODKind) {
        self.kind = kind
    }

    func reset(client: XtreamClient?) {
        generation += 1
        self.client = client
        categories = []
        items = [:]
        loadingCategories = false
        loadingItems = []
        loaded = false
        error = nil
        chosen = nil
    }

    func loadCategories(force: Bool = false) async {
        guard let client, !loadingCategories, force || !loaded else { return }
        let gen = generation
        loadingCategories = true
        do {
            let found = try await client.vodCategories(kind)
            guard gen == generation else { return }
            categories = found
            loaded = true
            error = nil
            if chosen == nil || !found.contains(where: { $0.id == chosen }) { chosen = found.first?.id }
        } catch {
            guard gen == generation else { return }
            self.error = error.localizedDescription
        }
        loadingCategories = false
    }

    func load(_ category: String) async {
        guard let client, items[category] == nil, !loadingItems.contains(category) else { return }
        let gen = generation
        loadingItems.insert(category)
        do {
            let found = try await client.vodItems(kind, category: category)
            guard gen == generation else { return }
            items[category] = found
            error = nil
        } catch {
            guard gen == generation else { return }
            self.error = error.localizedDescription
        }
        loadingItems.remove(category)
    }

    func details(_ item: VODItem) async throws -> VODDetails {
        guard let client else { throw SourceError(L("Ikke logget inn")) }
        return try await client.vodDetails(item)
    }

    func name(_ category: String?) -> String {
        categories.first { $0.id == category }?.name ?? ""
    }
}

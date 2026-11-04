import Foundation
import FyrlysCore
import Network

// Pause og tilbakespoling i direktesending: appen henter HLS-strømmen selv, legger bitene på disken (opptil en
// halvtime, `ShiftBuffer` i kjernen) og gir Apple sin avspiller en spilleliste med alt den har, fra en liten tjener på
// enheten (127.0.0.1, ikke synlig for andre på nettet). Avspilleren ser da en direktesending med en halvtime bak seg,
// så pause, spoling og «direkte» virker som i Apples egne apper. Strømmer som ikke kan bufferes (lyden i en egen
// spilleliste, deler av filer, ikke HLS), spilles som før, rett fra leverandøren.

/// Én direktesending som hentes og legges på disken.
actor LiveShiftSession {
    nonisolated let id = UUID().uuidString
    nonisolated let source: URL
    private let dir: URL
    private var buffer: ShiftBuffer
    private var mediaURL: URL?
    private var loop: Task<Void, Never>?
    private(set) var alive = true

    /// så mange biter hentes før avspilleren får lista (resten kommer mens den begynner)
    static let ready = 2

    init(source: URL) {
        self.source = source
        dir = LiveShift.folder.appendingPathComponent(id, isDirectory: true)
        #if os(tvOS)
        buffer = ShiftBuffer(maxDuration: 1800, maxBytes: 1_500_000_000)
        #else
        buffer = ShiftBuffer(maxDuration: 1800, maxBytes: 800_000_000)
        #endif
    }

    /// Finner medielista (velger varianten i en hovedliste) og henter de første bitene. false: strømmen kan ikke
    /// bufferes, eller det kom ingenting (den spilles da rett fra leverandøren).
    func start() async -> Bool {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            guard let (url, media) = try await resolve(source) else {
                AppLog.shared.add("Tilbakespoling: strømmen kan ikke bufferes, spilles direkte")
                return false
            }
            mediaURL = url
            let first = buffer.newSegments(in: media)
            try await download(Array(first.prefix(Self.ready)), target: media.targetDuration)
            guard !buffer.entries.isEmpty else { return false }
        } catch {
            AppLog.shared.add("Tilbakespoling: kom ikke i gang (\(error.localizedDescription))")
            return false
        }
        loop = Task { await self.run() }
        return true
    }

    func stop() {
        alive = false
        loop?.cancel()
        loop = nil
        try? FileManager.default.removeItem(at: dir)
    }

    /// Spillelista til avspilleren.
    func playlist() -> Data { Data(buffer.playlist().utf8) }

    /// En bit fra disken (bare de som er i bufferet).
    func file(_ name: String) -> Data? {
        guard buffer.entries.contains(where: { $0.file == name }) else { return nil }
        return try? Data(contentsOf: dir.appendingPathComponent(name))
    }

    /// Hvor mye som er tatt vare på (sekunder).
    var duration: TimeInterval { buffer.duration }

    // ── hentingen ──

    /// Medielista bak [url] (en hovedliste: den beste varianten med lyden i seg), og adressen den kom fra. nil: ikke
    /// noe som kan bufferes (et opptak med slutt, deler av filer, lyden for seg, ikke HLS).
    private func resolve(_ url: URL, depth: Int = 0) async throws -> (URL, HLSMedia)? {
        let (data, final) = try await get(url, timeout: 15)
        guard let playlist = parseHLS(String(decoding: data, as: UTF8.self), base: final) else { return nil }
        switch playlist {
        case .master(let variants):
            guard depth == 0, let variant = chooseVariant(variants) else { return nil }
            return try await resolve(variant.url, depth: 1)
        case .media(let media):
            guard !media.ended, !media.byteRanges, !media.segments.isEmpty else { return nil }
            return (final, media)
        }
    }

    /// Henter lista på nytt (omtrent hver halve bitlengde) og bitene som er nye. Feiler det, prøves det igjen; hver
    /// tredje gang fra begynnelsen (adressen bak kan ha fått en ny nøkkel), og etter mange feil på rad slutter den.
    private func run() async {
        var failures = 0
        while !Task.isCancelled {
            do {
                guard let url = mediaURL else { break }
                let (data, final) = try await get(url, timeout: 15)
                guard case .media(let media)? = parseHLS(String(decoding: data, as: UTF8.self), base: final) else {
                    throw URLError(.cannotParseResponse)
                }
                mediaURL = final
                if media.ended { break }
                try await download(buffer.newSegments(in: media), target: media.targetDuration)
                failures = 0
                try await Task.sleep(for: .seconds(max(1, Double(media.targetDuration) / 2)))
            } catch {
                if Task.isCancelled { break }
                failures += 1
                if failures % 3 == 0, let again = try? await resolve(source) { mediaURL = again.0 }
                if failures > 30 {
                    AppLog.shared.add("Tilbakespoling: strømmen svarer ikke lenger")
                    alive = false
                    break
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func download(_ segments: [HLSSegment], target: Int) async throws {
        for segment in segments {
            guard !Task.isCancelled, alive else { return }
            let (data, _) = try await get(segment.url, timeout: 30)
            let name = buffer.nextName(for: segment)
            try data.write(to: dir.appendingPathComponent(name))
            for old in buffer.add(segment, file: name, bytes: data.count, targetDuration: target) {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(old))
            }
        }
    }

    private nonisolated func get(_ url: URL, timeout: TimeInterval) async throws -> (Data, URL) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(xtreamUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return (data, response.url ?? url)
    }
}

/// Den ene direktesendingen som bufferes (den du ser på), og adressen avspilleren får.
@MainActor
final class LiveShift {
    static let shared = LiveShift()
    private var session: LiveShiftSession?

    /// Bitene ligger her (i Caches, så enheten kan rydde selv), og mappen tømmes når appen starter.
    nonisolated static var folder: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("tilbakespoling", isDirectory: true)
    }

    /// Rester fra sist (appen ble avsluttet midt i en sending).
    static func cleanUp() {
        Task.detached(priority: .background) { try? FileManager.default.removeItem(at: folder) }
    }

    /// Bare HLS (.m3u8) kan bufferes.
    static func applies(to url: URL) -> Bool { url.pathExtension.lowercased() == "m3u8" }

    /// Adressen på enheten avspilleren skal bruke for [url]: den samme sendingen fortsetter (etter et brudd eller et
    /// nytt forsøk), ellers begynner en ny. nil: kan ikke bufferes, spill [url] direkte.
    func prepare(_ url: URL) async -> URL? {
        if let current = session, current.source == url, await current.alive {
            return await ShiftServer.shared.address(for: current)
        }
        await stop()
        let next = LiveShiftSession(source: url)
        session = next
        guard await next.start(), session === next, let address = await ShiftServer.shared.address(for: next) else {
            if session === next { session = nil }
            await next.stop()
            return nil
        }
        return address
    }

    /// Avspilleren er lukket (eller en annen kanal begynner): sendingen stoppes, og bitene slettes.
    func stop() async {
        guard let current = session else { return }
        session = nil
        ShiftServer.shared.remove(current.id)
        await current.stop()
    }
}

/// Tjeneren på enheten: /shift/<sending>/index.m3u8 og bitene. Lytter bare på 127.0.0.1.
final class ShiftServer: @unchecked Sendable {
    static let shared = ShiftServer()
    private let queue = DispatchQueue(label: "no.fyrlys.tilbakespoling")
    private var listener: NWListener?
    private var port: UInt16?
    private var waiting: [CheckedContinuation<UInt16?, Never>] = []
    private var sessions: [String: LiveShiftSession] = [:]

    /// Adressen til spillelista for [session] (tjeneren startes første gang).
    func address(for session: LiveShiftSession) async -> URL? {
        guard let port = await start() else { return nil }
        queue.sync { sessions[session.id] = session }
        return URL(string: "http://127.0.0.1:\(port)/shift/\(session.id)/index.m3u8")
    }

    func remove(_ id: String) {
        queue.async { self.sessions[id] = nil }
    }

    private func start() async -> UInt16? {
        await withCheckedContinuation { continuation in
            queue.async {
                if let port = self.port {
                    continuation.resume(returning: port)
                    return
                }
                self.waiting.append(continuation)
                guard self.listener == nil else { return }
                do {
                    let parameters = NWParameters.tcp
                    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
                    let listener = try NWListener(using: parameters)
                    listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                    listener.stateUpdateHandler = { [weak self] state in self?.changed(state) }
                    self.listener = listener
                    listener.start(queue: self.queue)
                } catch {
                    AppLog.shared.add("Tilbakespoling: tjeneren kom ikke i gang (\(error.localizedDescription))")
                    self.finish(nil)
                }
            }
        }
    }

    private func changed(_ state: NWListener.State) {
        switch state {
        case .ready:
            port = listener?.port?.rawValue
            finish(port)
        case .failed, .cancelled:
            listener?.cancel()
            listener = nil
            port = nil
            finish(nil)
        default:
            break
        }
    }

    private func finish(_ port: UInt16?) {
        let all = waiting
        waiting = []
        for continuation in all { continuation.resume(returning: port) }
    }

    // ── HTTP, så enkelt som avspilleren trenger: GET og HEAD, ett svar per tilkobling ──

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, Data())
    }

    private func receive(_ connection: NWConnection, _ received: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var all = received
            if let data { all.append(data) }
            if let end = all.range(of: Data("\r\n\r\n".utf8)) {
                self.respond(connection, String(decoding: all[..<end.lowerBound], as: UTF8.self))
            } else if complete || error != nil || all.count > 65_536 {
                connection.cancel()
            } else {
                self.receive(connection, all)
            }
        }
    }

    private func respond(_ connection: NWConnection, _ head: String) {
        let words = head.split(separator: "\r\n").first?.split(separator: " ") ?? []
        guard words.count >= 2 else {
            send(connection, nil, type: "text/plain", head: false)
            return
        }
        let isHead = words[0] == "HEAD"
        let path = words[1].split(separator: "?").first ?? ""
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 3, parts[0] == "shift", let session = sessions[parts[1]] else {
            send(connection, nil, type: "text/plain", head: isHead)
            return
        }
        let name = parts[2]
        Task {
            let body: Data?
            let type: String
            if name == "index.m3u8" {
                body = await session.playlist()
                type = "application/vnd.apple.mpegurl"
            } else {
                body = await session.file(name)
                type = Self.contentType(name)
            }
            self.queue.async { self.send(connection, body, type: type, head: isHead) }
        }
    }

    private func send(_ connection: NWConnection, _ body: Data?, type: String, head: Bool) {
        let status = body == nil ? "404 Not Found" : "200 OK"
        let length = body?.count ?? 0
        var reply = Data(("HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(length)\r\n"
            + "Cache-Control: no-cache\r\nConnection: close\r\n\r\n").utf8)
        if !head, let body { reply.append(body) }
        connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func contentType(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "aac": return "audio/aac"
        case "m4s", "mp4": return "video/mp4"
        default: return "video/mp2t"
        }
    }
}

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Hva slags feil det var, så innloggingen vet om det er verdt å prøve igjen som en annen klient (som Fyrlys for
/// Windows 2.1.46).
public enum SourceFailure: String, Sendable {
    /// ikke noe svar fra adressen (navnet finnes ikke, porten er stengt, tidsavbrudd, https som ikke virker): å prøve
    /// den samme adressen på en annen måte hjelper ikke
    case unreachable
    /// serveren svarte, men avviste forespørselen (HTTP 401/403), svarte tomt eller lukket forbindelsen
    case rejected
    /// serveren svarte, men ikke som en Xtream-server (en nettside, HTTP 404, ikke JSON)
    case notXtream
    /// leverandøren sa at brukernavnet eller passordet er feil
    case wrongLogin
    case other
}

/// Klientene innloggingen prøver etter tur når serveren ikke vil svare VLC (avvist, tomt, en nettside eller en
/// forbindelse som lukkes): noen leverandører stenger VLC ute, andre alt annet enn kjente apper. Den som virker,
/// huskes for innloggingen (`Login.userAgent`) og brukes også for strømmene.
public let loginUserAgents = [xtreamUserAgent, "okhttp/4.12.0", "Fyrlys"]

/// Hvorfor serveren ikke ga noe svar, som en setning brukeren kan gjøre noe med. Uten adressen, så teksten kan stå i
/// loggen og feilrapporten.
public func connectionProblem(_ error: Error) -> SourceError {
    if let source = error as? SourceError { return source }
    guard let url = error as? URLError else {
        return SourceError(L("Får ikke kontakt med IPTV-serveren"), failure: .unreachable)
    }
    switch url.code {
    case .cannotFindHost, .dnsLookupFailed:
        return SourceError(L("Fant ikke serveren. Sjekk at adressen er skrevet riktig."), failure: .unreachable)
    case .cannotConnectToHost:
        return SourceError(L("Serveren tar ikke imot tilkoblinger på porten i adressen. Sjekk porten (tallet etter kolon)."),
                           failure: .unreachable)
    case .timedOut:
        return SourceError(L("Serveren svarer ikke. Sjekk adressen og porten, eller prøv igjen senere."),
                           failure: .unreachable)
    case .notConnectedToInternet:
        return SourceError(L("Får ikke kontakt med serveren. Sjekk nettforbindelsen."), failure: .unreachable)
    case .networkConnectionLost, .badServerResponse, .zeroByteResource, .cannotParseResponse:
        // noen servere lukker forbindelsen uten svar for klienter de stenger ute (nginx sin «444»)
        return SourceError(L("Serveren brøt forbindelsen. Prøv igjen om litt."), failure: .rejected)
    case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
         .serverCertificateHasUnknownRoot, .clientCertificateRejected:
        return SourceError(L("Sertifikatet til serveren godtas ikke, så den sikre tilkoblingen (https) ble stoppet. Har du fått en adresse med http:// fra leverandøren, bruk den."),
                           failure: .unreachable)
    case .secureConnectionFailed:
        return SourceError(L("Serveren svarer ikke på https på denne porten. Prøv adressen med http:// foran."),
                           failure: .unreachable)
    default:
        return SourceError(L("Får ikke kontakt med IPTV-serveren"), failure: .unreachable)
    }
}

/// Hva slags feil det var, til loggen: koden, aldri adressen (den har brukernavn og passord).
public func errorKind(_ error: Error) -> String {
    if let url = error as? URLError { return "URLError \(url.code.rawValue)" }
    if let source = error as? SourceError { return "SourceError \(source.failure.rawValue)" }
    return String(describing: type(of: error))
}

/// En side fra Cloudflare som vil se en nettleser (eller har stengt ute klienten), ikke svaret fra serveren.
func cloudflareCheck(_ lower: String) -> Bool {
    lower.contains("cdn-cgi/challenge-platform") || lower.contains("cf-chl")
        || (lower.contains("cloudflare")
            && (lower.contains("just a moment") || lower.contains("attention required") || lower.contains("been blocked")))
}

private func head(_ data: Data) -> String {
    let prefix = data.prefix(8000)
    let text = String(decoding: prefix, as: UTF8.self)
    return text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

/// Hva som er galt med svaret fra player_api.php ([status] og [data]), eller nil når det kan tolkes.
public func xtreamResponseProblem(_ status: Int, _ data: Data) -> SourceError? {
    let lower = head(data)
    if status == 400 && lower.contains("plain http request was sent to https port") {
        return SourceError(L("Serveren vil ha https på denne porten. Skriv https:// foran adressen."),
                           failure: .unreachable)
    }
    if status >= 400 && cloudflareCheck(lower) {
        return SourceError(L("Adressen er bak en nettleserkontroll (Cloudflare) som stopper IPTV-apper. Spør leverandøren om en serveradresse for apper."),
                           failure: .rejected)
    }
    if status == 401 || status == 403 {
        return SourceError(L("Serveren avviste innloggingen (HTTP {code}). Sjekk at abonnementet er aktivt.",
                             ["code": status]), failure: .rejected)
    }
    if status == 404 {
        return SourceError(L("Fant ikke Xtream Codes på adressen (HTTP 404). Sjekk serveradressen."),
                           failure: .notXtream)
    }
    if status >= 400 { return SourceError(L("IPTV-serveren svarte HTTP {code}", ["code": status])) }
    if lower.isEmpty {
        return SourceError(L("Serveren svarte tomt. Sjekk brukernavn og passord, og at abonnementet er aktivert."),
                           failure: .rejected)
    }
    return nil
}

/// Svaret var ikke JSON: en nettside (eller en kontroll fra Cloudflare) eller noe helt annet.
public func xtreamNotJSON(_ data: Data) -> SourceError {
    let lower = head(data)
    if cloudflareCheck(lower) {
        return SourceError(L("Adressen er bak en nettleserkontroll (Cloudflare) som stopper IPTV-apper. Spør leverandøren om en serveradresse for apper."),
                           failure: .rejected)
    }
    if lower.hasPrefix("<") {
        return SourceError(L("Adressen svarte med en nettside, ikke som en IPTV-server. Bruk serveradressen for Xtream Codes fra leverandøren, ikke adressen til nettsiden deres."),
                           failure: .notXtream)
    }
    return SourceError(L("Serveren svarte ikke som en Xtream-server"), failure: .notXtream)
}

/// JSON fra player_api.php, også når serveren har skrevet noe foran (et BOM-tegn eller advarsler fra PHP).
public func decodeJSONLenient(_ data: Data) -> Any? {
    if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) { return json }
    var bytes = data
    // BOM
    if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
        bytes = bytes.dropFirst(3)
        if let json = try? JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed]) { return json }
    }
    // «Warning: … in /var/www/…» foran: fra den første { eller [
    let starts = [bytes.firstIndex(of: UInt8(ascii: "{")), bytes.firstIndex(of: UInt8(ascii: "["))]
        .compactMap { $0 }.sorted()
    for start in starts where start > bytes.startIndex {
        if let json = try? JSONSerialization.jsonObject(with: bytes[start...], options: []) { return json }
    }
    return nil
}

/// `auth` i user_info: 1 hos de fleste, men noen svarer true eller «1»; mangler den, avgjør `status`.
public func xtreamAuthorized(_ info: [String: Any]) -> Bool {
    guard let auth = info["auth"], !(auth is NSNull) else {
        return text(info["status"]).lowercased() == "active"
    }
    // true/false, og på Apple også 1/0 som NSNumber
    if let flag = auth as? Bool { return flag }
    if let number = int(auth) { return number == 1 }
    return text(auth).lowercased() == "true"
}

/// Hvorfor en kanal ikke gir bilde, fra HTTP-koden strømmen svarte med ([provider]: leverandørens strøm, ikke en egen).
public func channelStatusProblem(_ status: Int, provider: Bool) -> String? {
    guard status >= 400 else { return nil }
    guard provider else { return L("Strømmen svarte HTTP {code}", ["code": status]) + "." }
    switch status {
    case 401, 403:
        return L("Leverandøren avviste kanalen (HTTP {code}). Den er kanskje ikke med i abonnementet, eller den er stengt der du er.",
                 ["code": status])
    case 404, 410:
        return L("Fant ikke kanalen hos leverandøren (HTTP {code}). Den kan være flyttet; hent kanallista på nytt.",
                 ["code": status])
    case 429, 458, 509:
        // koder mange Xtream-servere bruker for «for mange tilkoblinger»
        return L("Leverandøren sier at alle tilkoblingene er i bruk (HTTP {code}). Ser noen på en annen enhet?",
                 ["code": status])
    case 500...599:
        return L("Leverandøren har problemer med kanalen akkurat nå (HTTP {code}). Prøv igjen om litt.",
                 ["code": status])
    default:
        return L("IPTV-serveren svarte HTTP {code}", ["code": status]) + "."
    }
}

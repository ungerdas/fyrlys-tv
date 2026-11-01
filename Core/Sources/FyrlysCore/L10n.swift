import Foundation

// Tekstene i appen. Norsken står i koden og er også nøkkelen til engelsken: L("Logg ut") gir «Sign out» på engelsk.
// {navn} byttes med verdiene: L("Byttet til {name}", ["name": navn]). Det som mangler i `english`, vises på norsk
// (testen L10nTests sier fra om det).

/// "no" eller "en". Settes av appen fra språket på Apple TV-en (norsk for nb, nn og no, ellers engelsk).
nonisolated(unsafe) public var appLanguage = "no"

/// Språket for en språkkode fra systemet.
public func language(ofPreferred codes: [String]) -> String {
    guard let first = codes.first?.lowercased() else { return "en" }
    return ["nb", "nn", "no"].contains(where: { first.hasPrefix($0) }) ? "no" : "en"
}

/// [no] på språket appen vises på, med {navn} byttet med verdiene i [args].
public func L(_ no: String, _ args: [String: Any] = [:]) -> String {
    var text = appLanguage == "en" ? (english[no] ?? no) : no
    for (key, value) in args {
        text = text.replacingOccurrences(of: "{\(key)}", with: "\(value)")
    }
    return text
}

/// Norsk → engelsk.
public let english: [String: String] = [
    // innlogging
    "{user} på {host}": "{user} on {host}",
    "Logg inn": "Sign in",
    "Logger inn …": "Signing in…",
    "Server": "Server",
    "Brukernavn": "Username",
    "Passord": "Password",
    "Innloggingen fra IPTV-leverandøren din (Xtream Codes). Den lagres kryptert på Apple TV-en.":
        "The login from your IPTV provider (Xtream Codes). It is stored encrypted on the Apple TV.",
    "Fyll inn server, brukernavn og passord.": "Fill in server, username and password.",
    // feil fra leverandøren
    "Får ikke kontakt med IPTV-serveren": "Can't reach the IPTV server",
    "Serveren avviste innloggingen": "The server rejected the login",
    "IPTV-serveren svarte HTTP {code}": "The IPTV server responded HTTP {code}",
    "Serveren svarte ikke som en Xtream-server": "The server didn't respond like an Xtream server",
    "Abonnementet er ikke aktivt ({status})": "The subscription isn't active ({status})",
    // TV
    "TV": "TV",
    "TV-guide": "TV guide",
    "Innstillinger": "Settings",
    "Favoritter": "Favorites",
    "Sist sett": "Recently watched",
    "Alle kanaler": "All channels",
    "Kategorier": "Categories",
    "Dine kategorier": "Your categories",
    "Alle kategorier": "All categories",
    "Hold inne på en kategori for å legge den øverst.": "Press and hold a category to pin it to the top.",
    "Legg øverst": "Pin to top",
    "Fjern fra toppen": "Unpin from top",
    "Flytt opp": "Move up",
    "Flytt ned": "Move down",
    // iPhone og iPad
    "Innloggingen fra IPTV-leverandøren din (Xtream Codes). Den lagres kryptert på denne enheten.":
        "The login from your IPTV provider (Xtream Codes). It is stored encrypted on this device.",
    "Søk i kategoriene": "Search categories",
    "Ferdig": "Done",
    "Trykk på stjernen for å legge en kategori øverst.": "Tap the star to pin a category to the top.",
    "Se kanalen": "Watch channel",
    "Forrige": "Previous",
    "Neste": "Next",
    "Favoritt": "Favorite",
    "Henter kanalene …": "Loading channels…",
    "Ingen kanaler her.": "No channels here.",
    "Ingen favoritter ennå. Hold inne på en kanal for å legge den til.":
        "No favorites yet. Press and hold a channel to add it.",
    "Du har ikke sett noen kanaler ennå.": "You haven't watched any channels yet.",
    "Legg til i favoritter": "Add to favorites",
    "Fjern fra favoritter": "Remove from favorites",
    "Nå: {title}": "Now: {title}",
    "Etterpå {time}: {title}": "Next {time}: {title}",
    "Ingen programinfo": "No program information",
    "Prøv igjen": "Try again",
    "Søk": "Search",
    "Søk etter kanal": "Search for a channel",
    "Ingen treff.": "No results.",
    // iPhone som Fyrlys-nettsiden
    "Bytt mellom lys og mørk modus": "Switch between light and dark mode",
    "Konto": "Account",
    "Utløper {date}": "Expires {date}",
    "{active} av {max} tilkoblinger i bruk": "{active} of {max} connections in use",
    "Kontoen har status «{status}» hos leverandøren.": "The account has the status “{status}” at the provider.",
    "Hent listene nå": "Reload lists now",
    "Fyrlys {version}": "Fyrlys {version}",
    "Treff": "Results",
    "Nå på favorittene": "Now on your favorites",
    "Ingen favoritter ennå. Trykk på stjernen på en kanal for å legge den til her.":
        "No favorites yet. Tap the star on a channel to add it here.",
    "Tilbake": "Back",
    "Tøm søket": "Clear search",
    "**Samle favorittene dine her.** Trykk på stjernen på kanalene du ser mest, så ligger de øverst med det som går nå. I TV-guiden ser du hva som kommer senere.":
        "**Gather your favorites here.** Tap the star on the channels you watch most, and they'll be at the top with what's on now. The TV guide shows what's coming up later.",
    "Utseende": "Appearance",
    "Som enheten": "Same as device",
    "Mørk": "Dark",
    "Lys": "Light",
    "Til nå": "Jump to now",
    "Vis flere kanaler ({n} av {total})": "Show more channels ({n} of {total})",
    "Ingen favoritter ennå. Trykk på stjernen på en kanal under TV, eller velg en kategori over.":
        "No favorites yet. Tap the star on a channel under TV, or choose a category above.",
    "Starter {time}": "Starts {time}",
    // Apple TV som iPhone
    "**Samle favorittene dine her.** Hold inne på en kanal og velg «Legg til i favoritter», så ligger den øverst med det som går nå. I TV-guiden ser du hva som kommer senere.":
        "**Gather your favorites here.** Press and hold a channel and choose “Add to favorites”, and it'll be at the top with what's on now. The TV guide shows what's coming up later.",
    // spilleren
    "Neste kanal": "Next channel",
    "Forrige kanal": "Previous channel",
    "Kanalen kunne ikke spilles": "The channel couldn't be played",
    "Kanalen kunne ikke spilles ({message}).": "The channel couldn't be played ({message}).",
    "Alle tilkoblingene i abonnementet er i bruk akkurat nå. Ser noen på en annen enhet?":
        "All connections in the subscription are in use right now. Is someone watching on another device?",
    "Lukk": "Close",
    "Kanaler": "Channels",
    "Episode {n}": "Episode {n}",
    // se fra start, fortsett, VLC
    "Se fra start": "Watch from the start",
    "Fortsett å se": "Continue watching",
    // flere innlogginger
    "Innlogginger": "Logins",
    "Bytt til {name}": "Switch to {name}",
    "Fjern {name}": "Remove {name}",
    "Fjern": "Remove",
    "Legg til innlogging": "Add login",
    // TV-arkivet
    "TV-arkiv": "TV archive",
    "TV-arkiv: {channel}": "TV archive: {channel}",
    "Ingenting i arkivet de siste dagene.": "Nothing in the archive for the last few days.",
    "I dag": "Today",
    "I går": "Yesterday",
    "Går nå": "On now",
    "Ikke i arkivet": "Not in the archive",
    // filmer og serier
    "Filmer": "Movies",
    "Serier": "Series",
    "Ingen filmer hos leverandøren.": "Your provider has no movies.",
    "Ingen serier hos leverandøren.": "Your provider has no series.",
    "Ingen her.": "Nothing here.",
    "Ikke logget inn": "Not signed in",
    "Med: {cast}": "With: {cast}",
    "Fortsett ({time})": "Continue ({time})",
    "Fra start": "From the start",
    "Ingen episoder.": "No episodes.",
    "Sesong {n}": "Season {n}",
    "Sesong {s}, episode {e}": "Season {s}, episode {e}",
    "Sett til {time}": "Watched to {time}",
    "Kunne ikke spilles: leverandøren svarte ikke med filen, eller alle tilkoblingene dine er i bruk.":
        "Couldn't be played: your provider didn't send the file, or all your connections are in use.",
    // Plex
    "Plex avviste innloggingen. Koble til Plex på nytt.": "Plex rejected the sign-in. Connect to Plex again.",
    "Plex svarte HTTP {code}": "Plex answered HTTP {code}",
    "Får ikke kontakt med Plex": "Can't reach Plex",
    "Får ikke kontakt med Plex-serveren": "Can't reach the Plex server",
    "Plex svarte ikke som ventet": "Plex didn't answer as expected",
    "{n} min": "{n} min",
    "Ingen filmbiblioteker på Plex-serveren.": "No movie libraries on the Plex server.",
    "Ingen seriebiblioteker på Plex-serveren.": "No TV show libraries on the Plex server.",
    "Sett": "Watched",
    "Koden gikk ut. Prøv igjen.": "The code expired. Try again.",
    "Fant ingen Plex-server på kontoen.": "Found no Plex server on the account.",
    "Får ikke kontakt med {name}.": "Can't reach {name}.",
    "Se filmene og seriene dine fra Plex i fanene Filmer og Serier, i stedet for dem fra IPTV-leverandøren.":
        "Watch your movies and TV shows from Plex in the Movies and Series tabs, instead of those from your IPTV provider.",
    "Koble til Plex": "Connect to Plex",
    "Gå til plex.tv/link på telefonen eller PC-en, logg inn og skriv inn koden:":
        "Go to plex.tv/link on your phone or computer, sign in and enter the code:",
    "Kobler til Plex …": "Connecting to Plex …",
    "Velg Plex-serveren:": "Choose the Plex server:",
    "Koble fra Plex": "Disconnect Plex",
    "Koblet til {server}": "Connected to {server}",
    "Filmer og serier fra: Plex": "Movies and series from: Plex",
    "Filmer og serier fra: IPTV-leverandøren": "Movies and series from: IPTV provider",
    "Filmer og serier fra": "Movies and series from",
    "IPTV-leverandøren": "IPTV provider",
    "Bytt server": "Switch server",
    "Plex: {server}": "Plex: {server}",
    "Plex …": "Plex …",
    // VLC-spilleren
    "Av": "Off",
    "Spor {n}": "Track {n}",
    "Lyd": "Audio",
    "Undertekster": "Subtitles",
    "◀ ▶ spol  ·  ned: lyd og undertekster": "◀ ▶ skip  ·  down: audio and subtitles",
    "◀ ▶ spol": "◀ ▶ skip",
    "10 sekunder tilbake": "Back 10 seconds",
    "10 sekunder fram": "Forward 10 seconds",
    "Pause": "Pause",
    // guiden
    "Velg hva guiden viser oppe til høyre: favorittene, alle kanaler eller en kategori.":
        "Choose what the guide shows at the top right: your favorites, all channels or a category.",
    "Spill av": "Play",
    // innstillinger
    "Abonnement": "Subscription",
    "Aktiv til {date}": "Active until {date}",
    "1 tilkobling": "1 connection",
    "{n} tilkoblinger": "{n} connections",
    "Innlogget som {user}": "Signed in as {user}",
    "Hent listene på nytt": "Reload lists",
    "Logg ut": "Sign out",
    "Logg ut av {name}?": "Sign out of {name}?",
    "Avbryt": "Cancel",
    "Versjon {version}": "Version {version}",
    "{n} kanaler i {c} kategorier": "{n} channels in {c} categories",
]

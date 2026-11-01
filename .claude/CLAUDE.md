# Fyrlys for Apple TV, iPhone og iPad – arbeidsnotater for Claude

Egen app for Apple TV (tvOS 17+) og iPhone/iPad (iOS 17+), Swift/SwiftUI med AVPlayer, i tillegg til Fyrlys for Windows
(eget repo). Apple TV, iPhone og iPad er **én app** i App Store Connect og TestFlight (samme bundle-id, eierens valg
31.10). Logger inn med Xtream Codes og henter alt rett fra leverandøren. Repoet er **offentlig**: hold appen, koden, testene,
commit-meldingene og disse notatene fri for navn, hjemmenett, maskinnavn, leverandør, brukernavn, hemmeligheter og
e-postadresser (eksempeladresser som iptv.example.com og 192.168.1.10 er greit; unntaket er NRK-adressene i
`Core/Sources/FyrlysCore/Streams.swift`, bygget inn etter eierens ønske 1.11.2026). Testene bruker bare den falske
leverandøren i `tools/fake_xtream.py`, med oppdiktede kanaler. `README.md` er forsiden på GitHub, skrevet for brukere.

## Arbeidsmåte
- Svar alltid på **norsk**. Commit-meldinger på norsk med prefikset `Fyrlys:`. Push rett til `main`.
- **Xcode kan ikke kjøres i Claude-økta** (ingen Mac). Kjernen (`Core/`, bare Foundation) testes her med Swift for
  Linux: `swift test --package-path Core` (Swift 6.2 ligger i scratchpad-mappen til økta, `swift/usr/bin`, og må
  lastes ned på nytt i en ny økt: swift.org-tarball for Ubuntu 24.04; kjør `swift` fra en mappe som finnes: er
  arbeidsmappen slettet, krasjer swift-driveren med «Illegal instruction»). Appen bygges og testes av GitHub Actions på
  macOS: `gh run list --repo ungerdas/fyrlys-tv`, `gh run watch <id> --repo ungerdas/fyrlys-tv`. Loggene og
  artefaktene kan ikke lastes ned herfra; ved feil legger workflowen feilene og slutten av loggen som merknad:
  `gh api repos/ungerdas/fyrlys-tv/check-runs/<jobb-id>/annotations` (jobb-id fra `gh run view <id> --json jobs`).
- **Skjermbilder**: UI-testene (`UITests/FyrlysUITests.swift`) tar bilder i simulatoren, og workflowen legger dem i
  grenen `skjermbilder` (overskrives hver gang); iPhone og iPad (`UITestsMobil/FyrlysMobilUITests.swift`, «NN-iphone-…»
  og «NN-ipad-…») i grenen `skjermbilder-mobil`. Den grunne klonen trenger en refspec:
  `git fetch --depth 1 origin skjermbilder:refs/remotes/origin/skjermbilder`. Hent med `git fetch origin skjermbilder` og
  `git show origin/skjermbilder:02-tv.png > …`, og se på dem med Read. Bilder XCTest tok ved feil heter `feil-*.png`.
- Appen i testmodus: miljøvariablene `FYRLYS_TEST_SERVER` (falsk leverandør, test/test, ingen nøkkelring, egne
  innstillinger og kanalliste som tømmes, unntatt med `FYRLYS_TEST_KEEP`), `FYRLYS_TEST_SCREEN` (login, tv, guide,
  search, settings, player, player-error = kanal 90 som svarer 404; på iPhone også all = «Alle kanaler» og category =
  Sport åpnet), `FYRLYS_TEST_LANG` og `FYRLYS_TEST_THEME` (light/dark; UI-testene for iPhone/iPad bruker dark, ellers
  ville simulatoren gitt lys modus) (`App/TestSupport.swift`).
  Elementene testene finner, har `accessibilityIdentifier` (`kanal-<id>`, `hylle-…`, `favoritt-<id>`, `seksjon-dine`/
  `-alle`/`-kategorier`, `seksjon-favoritter`/`-sist` (radene øverst), `lagt-overst`, `spiller` (spilleren står
  framme; kortene bak den finnes i elementtreet også da), `spiller-feil` (på Apple TV samme beholder som `spiller`, id-en
  byttes: en beholder med id inne i en annen med id ble borte), `guide`, `innstillinger`). `focus(app, mål)`
  i UI-testene flytter fokus dit uansett hvor det står (fanelinja, sidemenyen, kortene). På iPhone/iPad også
  `kategori-velger`, `stjerne-<kategori>`, `stjerne-kanal-<id>`, `lukk-spiller`, `neste-kanal`, `guide-velger`,
  `til-naa`; bare iPhone: `sok`, `tema`, `konto`, `tilbake`, `kategori-stjerne`, flisene `hylle-…`. Testen av farten (`test11StorListe`) bruker en stor falsk leverandør
  (`fake_xtream.py --kanaler 25000 --kategorier 450` på port 8898, `FYRLYS_TEST_SERVER_STOR`); tidene står som merknad
  «ytelse» på bygget (simulatoren på en Mac er raskere enn en Apple TV).
- **Utseendet følger Fyrlys på Windows** (eieren 31.10: «så lik som mulig windows appen»), men **fanelinja til Apple TV
  beholdes** (eieren: «jeg liker fanelinja til apple! så behold den»). Fasit for mål og farger er Windows-repoet
  (`ungerdas/fyrlys`, offentlig, kan klones for lesing: `lib/ui/channel_card.dart`, `home_page.dart` (`_sidebar`,
  `_categoryTile`), `theme.dart`), skalert opp for TV (rundt 1,4 ganger pikslene der). Ingen endringer i det repoet
  herfra. **iPhone følger nettversjonen** (Docker-versjonen av Fyrlys på telefon; eieren 31.10 med et bilde av den:
  «Ønsker iPhone appen i denne UI!»): fasit er `app/web/fyrlys.css` (reglene under `@media (max-width: 860px)`,
  `.chan`, `.ctile`, `.mhead`, `.tabs`, `.top`, `.gwrap`) og `js/list.js`/`guide.js`/`core.js` (`tintLogo`) i eierens
  private repo for den; det kan legges til økta for lesing. Ingenting derfra (adresser, navn) skal hit.
- Swift 5-modus i appen (`SWIFT_VERSION 5.0`); kjernen er swift-tools 5.9. Unngå navn som `Category` (finnes i
  ObjC-kjøretiden) og frie funksjoner med samme navn som View-metoder (`tint`): inne i en View vinner metoden.
- Tekster: `L("norsk tekst", ["navn": verdi])` (`Core/Sources/FyrlysCore/L10n.swift`); norsken er nøkkelen i
  `english`. `L10nTests.testEverythingIsTranslated` finner alle `L("…")` i `Core/Sources` og `App` og krever engelsk
  med de samme `{navnene}`. Tekst som ikke skal oversettes: `Text(verbatim:)`. `appLanguage` settes ved start fra
  språket på Apple TV-en (nb/nn/no = norsk, ellers engelsk).
- **Versjoner**: `MARKETING_VERSION` i `project.yml` (0.1.0 til å begynne med), byggnummeret er `github.run_number`.
  Øk patch-versjonen før hver push som legges ut (når TestFlight er satt opp), og skriv avsnittet i `CHANGELOG.md`.
- Ikonene lages av `tools/make_icons.py` (cairosvg) fra fyret i Fyrlys-ikonet: tre lag (fyret, strålene, bakgrunnen)
  for parallakse, App Store-ikonet 1280×768 og Top Shelf-bildene. Bakgrunnslaget og Top Shelf må være uten
  gjennomsiktighet.

## Arkitektur
- `project.yml` (XcodeGen; prosjektet og Info.plist lages i bygget og ligger ikke i repoet): målene `Fyrlys` (tvOS) og
  `FyrlysMobil` (iPhone og iPad, `TARGETED_DEVICE_FAMILY` 1,2), begge med bundle-id `no.fyrlys.tv` og produktnavn
  Fyrlys, http tillatt fordi leverandørene bruker det, `ITSAppUsesNonExemptEncryption` false; iOS i tillegg alle
  retninger på iPad (kreves for delt skjerm), `UIBackgroundModes` audio (bilde-i-bilde) og ikonet i
  `App/Mobil.xcassets` (1024 × 1024 uten alfa, `tools/make_icons.py --ios`; tvOS bruker `Assets.xcassets`, og hvert
  mål utelater det andres). `FyrlysUITests` og `FyrlysMobilUITests`, ett skjema per plattform.
- **Felles kode med `#if os(tvOS)`/`#if os(iOS)`**: begge målene tar med hele `App/`. Bare tvOS: `GuideView.swift`,
  `SettingsView.swift`, `PlayerView.swift` (AVPlayerViewController med `transportBarCustomMenuItems`/
  `customInfoViewControllers`), hurtigrullingen i `ScrollIndex.swift`. Bare iOS: `GuideViewMobil.swift` (som nettsiden:
  valg av favoritter/alle/kategori lagret som `guide`, «Til nå» via `scrollPosition(id:)` på halvtimene, tidslinja
  øverst flyttes etter sporene via en preference og `GuideScroll`, sporene har fast bredde (rammen minus
  kanalkolonnen), og tidslinja `frame(minWidth: 0, maxWidth: .infinity)`: med bare `maxWidth` blir en ramme aldri
  smalere enn innholdet (seks timer), så hele guiden ble bredere enn skjermen og radene havnet utenfor i 0.1.6;
  kanalkolonnen er lat og henter programinfoen,
  info-ark med «Se kanalen»), `SettingsViewMobil.swift` (Form, bare iPad; med lys/mørk), `PlayerViewMobil.swift` (bildet
  øverst med bilde-i-bilde, panel og kanalliste under; liggende iPhone bare bildet; iPad på tvers lista ved siden av;
  alltid mørk; dra bildet ned for å lukke: en `UIPanGestureRecognizer` (`DragDown`) på AVPlayerViewController-visningen
  som bare begynner nedover og virker sammen med AVKit, `offset` på hele spilleren og `presentationBackground(.clear)`
  på `fullScreenCover`, så TV-siden synes under). iPhone (smal bredde, `HomeView` velger på `horizontalSizeClass`): `PhoneHome.swift` (topplinja med
  fyret, sol/måne og Konto som popover, `TabView` med TV og TV-guide og ikonene tegnet etter nettsiden, `SwipeBackEnabler`
  så sveip tilbake virker med skjult navigasjonslinje), `PhoneTV.swift` (`NavigationStack` med stien i HomeView:
  forsiden med søk, «Nå på favorittene», «Sist sett», flisene; `PhoneShelfPage` med tilbake, pille som åpner
  `CategoryPicker` og stjerne), `BigCard.swift` (de store kortene, `logoTint` = `tintLogo` fra nettsiden, regnet ut i
  `Images.load` og husket per adresse). Lys og mørk: fargene i `Theme` er dynamiske på iOS (`tone`), valget i
  innstillingene som `tema` (tom = som enheten). Felles:
  `PlayerModel.swift`, `AppModel`, kortene og TV-siden, med mål i `Metrics` (`Theme.swift`; tvOS ≈ 1,4 × Windows,
  iOS som Windows) og `tvFocusSection()`. `focusSection`, `indexDisplayMode` og AVKits tvOS-kontroller finnes ikke på
  iOS.
- `Core/Sources/FyrlysCore/`: `Models.swift` (`ChannelCategory`, `Channel`, `Program`, `Account`, `Login` med
  `normalize`, `id` = `stableHash(server|bruker)` uten passordet, `nowAndNext`, `cleanPrograms`; `Channel.hasEpg` fra
  `epg_channel_id` (egen `init(from:)`, så lister lagret uten den leses), `wantsEpg` = har EPG og er ikke eventkanal),
  `Xtream.swift` (`XtreamClient`: player_api.php, `liveURL` = `/live/<bruker>/<passord>/<id>.m3u8`, `redact`, løse
  typer fra leverandøren, EPG i base64; `Fetch` byttes ut i testene), `ChannelIndex.swift` (oppslagene for en liste:
  `byId`, `byCategory`, kategoriene med kanaler, `channels(favoring:)` = favorittkategoriene først, `search(_:favoring:
  limit:)` med navnene i små bokstaver ferdig, `hasSameLists`; lages i bakgrunnen, 25 000 kanaler ≈ 50 ms på Linux),
  `Store.swift` (`Library`: favoritter, favorittkategorier (`moveFavoriteCategory` bytter med naboen som vises, som i
  Windows-appen) og sist sett per innlogging, i minnet og skrevet til lagringen ved endring, `reload()`; `mergeIds`;
  `search`),
  `ListCache.swift` (kategoriene og kanalene på disk), `Guide.swift` (`GuideTime`: seks timer fra halvtimen før denne),
  `Names.swift` (`nameParts` (regex bare når navnet begynner med et siffer), `logoText` = tre første tegn som i
  Windows-appen, `initials`, `hhmm`), `L10n.swift`.
- `App/`: `AppModel` (@Observable: innlogging i nøkkelringen (`Keychain.swift`), `index` (`ChannelIndex`; lista fra
  disk leses i bakgrunnen før `phase = .ready`, den hentede byttes bare inn når den er endret), `allChannels`
  (favorittkategoriene først), `generation` så svar for en tidligere innlogging ikke brukes, favoritter,
  favorittkategorier og sist sett via `libraryVersion`) og `ProgramStore` (ikke observerbar selv: én `ChannelPrograms`
  per kanal, så bare kortet for kanalen tegnes på nytt; 150 ms før henting, høyst fire om gangen, nyeste først, fem
  minutter, tomt svar huskes, feil prøves igjen; ikke for `!wantsEpg`). `RootView` → `LoginView` eller `HomeView`
  (TabView: TV, TV-guide, Søk, Innstillinger; valgt hylle og søket står i HomeView; spilleren som `fullScreenCover`).
  `ChannelsView` (sidemeny 340 pt: Alle kanaler, Favoritter, Sist sett med ikoner, så «Dine kategorier» og «Alle
  kategorier», eller «Kategorier» med et hint når ingen er lagt øverst; hold inne på en kategori = «Legg øverst» /
  «Flytt opp» / «Flytt ned» / «Fjern fra toppen»; valg ved trykk, ikke ved fokus; på Apple TV klippes rullelistene
  ikke under fanelinja (fra 0.1.8, se under), på iPad `.clipped()`; `hidesScrollIndex()` i `ScrollIndex.swift` skrur av
  hurtigrullingen (`indexDisplayMode`, via UIScrollView-en rundt), som la seg over tallene og tok fokus),
  `ChannelGrid` (bare iPad; adaptiv, minst 320 pt: fire kolonner ved siden av sidemenyen) med
  `ChannelCard` (96 pt høyt som Windows-kortet: `ChannelLogo`, klokkeslett i gult, navnet, kampen eller det som går nå
  (`NowPlaying`, `.everyMinute`), nummeret og stjernen; `CardStyle` med lyseblå kant `Theme.focus` og 1,05 i fokus;
  hold inne = favoritt), `GuideView` (6 timer, 4,2 pt/min, navn 300 pt, rader 66 pt, så det får plass uten vannrett rulling;
  fra 0.1.11 valget oppe til høyre (`Menu` `guide-velger`: favoritter, sist sett, alle, «Dine kategorier», undermeny
  «Alle kategorier»; lagret som `guide` som på iPhone; fokus
  settes i `GuideSelection`, som bare `GuideHeader` leser, så guiden ikke tegnes på nytt ved hvert steg; egen
  `GuideCellStyle` med `@Environment(\.isFocused)`), `SearchView` (`.searchable`, favorittkategoriene først),
  `SettingsView`, `PlayerView` (`PlayerModel` med AVPlayer, User-Agent som VLC, nye forsøk tre i
  minuttet, så forklaring: alle tilkoblinger i bruk, HTTP-koden fra leverandøren eller AVPlayers melding;
  `AVPlayerViewController` med neste/forrige/favoritt i `transportBarCustomMenuItems` og kanallista i
  `customInfoViewControllers`; programinfo i `externalMetadata`; fra 0.1.11 kanalbytte med opp/ned via AVKits
  `skipToNextChannel`/`skipToPreviousChannel` i `AVPlayerViewControllerDelegate` (koordinatoren) med `ChannelPreview`
  som `next/previousChannelInterstitialViewController`). `Images.swift` (logoer med eget mellomlager,
  `ChannelTile`), `FyrlysMark.swift` (fyret tegnet i Canvas), `Theme.swift` («Fyrlys om natta»).
- **Apple TV fra 0.1.8: sidemenyen og de store kortene** (eieren 1.11 om 0.1.7: «rart med den toppen», «uoversiktlig»;
  valgte sidemeny + mindre kort): `ChannelsView` med sidemenyen som før og `TVChannelPanel` (`TVHome.swift`) til
  høyre: i «Alle kanaler» (standard på Apple TV) «Nå på favorittene» og «Sist sett» som rader (`TVStrip`,
  `scrollClipDisabled` + `StripClip`: kortet med fokus kuttes ikke, men kortene rulles ikke inn over sidemenyen), eller
  tipset når begge er tomme, så tittel, antall og `BigCardGrid` med `Metrics.bigColumns` like brede kolonner (fire fra
  0.1.10; eieren syntes seks (0.1.8) og fem (0.1.9) var for små; `.flexible()`; kortene i radene har
  `containerRelativeFrame(count:)` med samme antall, så de er like brede); søket bruker `BigCardGrid(columns: nil)` (adaptiv, minst `bigGridMin`). Ingen `GeometryReader` rundt rullelista (den skal nå toppen av den trygge sonen). Toppen: TV-siden
  begynner under fanelinja, men kortene klippes ikke der (0.1.2–0.1.7 hadde `.clipped()`, og når fanelinja gled
  bort, ble det en tom stripe med kortene kuttet under). Over sidemenyen står Fyrlys-merket (`TVBrand`: `FyrlysMark`
  og «Fyrlys», som topplinja på iPhone; eieren 1.11: «Savner Fyrlys logo») som `overlay` med
  `alignmentGuide(.top)`, så bunnen står `Metrics.brandGap` over sidemenyen, på linje med fanelinja i simulatoren;
  sidemenyen er `.clipped()` under det. Fanelinja følger en rulleliste alene på siden av seg selv
  (0.1.7), men ingen av to ved siden av hverandre: i bygg 21 sto den fast over kortene (`18-…-rullet`). Derfor
  `movesTabBar()` i `ScrollIndex.swift`: UIScrollView-en rundt kortene blir `tabBarObservedScrollView` for fanen
  (barnet av UITabBarController, funnet via responder-kjeden), så UIKit flytter fanelinja i takt med kortene. `BigCard.swift` er felles: på Apple TV er hele kortet én
  knapp (`BigCardStyle`, lyseblå kant og 1,06 i fokus), stjernen bare et merke (`favoritt-<id>`). Målene i `Metrics`
  (`bigColumns`, `big…`, `row…`). 0.1.7 hadde en forside med fliser og egne sider per kategori (`TVChannels`,
  `TVTiles`, `TVShelfPage`); de er tatt bort. UI-testene for Apple TV flytter fokus mot målet med rammene (`focus`);
  `test11StorListe` måler kortene og sidemenyen og tar bilder av toppen (`17-…-sidemeny`, `18-…-rullet`,
  `19-…-fanelinja` etter Menu).
- **iCloud fra 0.1.12**: `CloudStore` (`App/CloudStore.swift`) er lagringen til `Library` utenom testene: favorittene
  og favorittkategoriene (nøklene `favorites@…`/`favoriteCategories@…`, per innlogging) i `NSUbiquitousKeyValueStore`
  og UserDefaults, «sist sett» bare lokalt. Første gang per nøkkel og ved `InitialSyncChange` flettes det enheten hadde
  inn (`mergeIds`, merket `icloud-flettet@…`), ellers vinner iCloud; endringer fra andre enheter → `Library.reload()` i
  `AppModel.libraryChangedElsewhere`. `asc.py check` slår på ICLOUD for app-id-en (`ensure_capability`,
  `POST /v1/bundleIdCapabilities`) og setter `ICLOUD_KVS=1` i `GITHUB_ENV`; da tar `adhoc_sign.sh` med
  `com.apple.developer.ubiquity-kvstore-identifier` = `<team>.no.fyrlys.tv` (samme for tvOS og iOS, så de deler).
- **Filmer og serier fra 0.1.12**: `Core/.../VOD.swift` (`VODKind`, `VODItem`, `Episode`, `Season`, `VODDetails`,
  `vodCategories`/`vodItems` (per kategori)/`vodDetails`, `movieURL`/`episodeURL` (`/movie|series/<bruker>/<passord>/
  <id>.<ext>`), `playableExtensions`: filtypen leverandøren oppgir, eller mp4 og m3u8 når den mangler; fra 0.1.15
  `playAttempts` (se VLC under)). `App/VODModel.swift` (`AppModel.movies`/`.series`, kategoriene første gang
  fanen vises, lista per kategori når den velges). `App/VODViews.swift`: `VODTab` (fanene Filmer og Serier; sidemeny
  med `vodkat-<id>` på Apple TV og iPad, meny `vod-kategori` på iPhone; `NavigationStack` med `VODDetailView`),
  plakater `vod-<id>` (`.card` på Apple TV), siden `vod-side` med `spill-av`/`fra-start` eller `sesong-<n>` og
  `episode-<id>`, `VODPlayerView` (`vod-spiller`/`vod-feil`; fullskjerm på Apple TV, ark på iPhone/iPad) med
  `VODPlayerModel`: prøver adressene etter tur, begynner der du slapp, lagrer hvor langt (`AppModel.progress`, nøkkel
  `sett@<innlogging>@<film|episode>`, hvert 10. s og ved lukking; glemmes nær slutten). Falsk leverandør: filmene
  501–503 (502 er mkv: `tools/testdata/stormnatt.mkv`, oppdiktet, 30 s, to lydspor og norske undertekster, med Range)
  og serien 9001; testskjermene `movies`, `series`, `mkv` (502 i VLC) og `mkv-feil` (504.avi, som svarer 404).
- **TV-arkiv fra 0.1.12** (som Fyrlys for Windows, `lib/core/xtream_source.dart`): `Core/.../Archive.swift`
  (`parseArchive` fra `get_simple_data_table` med `has_archive`, de siste `archiveDays` dagene; `serverClockOffset`
  fra `server_info` (`time_now` mot `timestamp_now`, rundet til kvarter); `archiveOffset` (enhetens sone med
  sommertid når serveren går likt, ellers serverens); `xtreamTime` «YYYY-MM-DD:HH-MM»; `archiveURLs` =
  `/timeshift/<bruker>/<passord>/<minutter>/<start>/<id>.m3u8` (+ `.ts`), på minuttet). `App/ArchiveView.swift`:
  dagene og programmene (nyeste først), spilles i `VODPlayerView`; åpnes med «TV-arkiv» i hurtigmenyen på kortene
  (`AppModel.archiveChannel`, vist i `HomeView`; testskjermen `archive` = kanal 1). `AppModel.serverClock()` spør én
  gang per innlogging.
- **Flere innlogginger fra 0.1.12**: `Keychain.saveAll/loadAll` (kontoen `logins`, en JSON-liste med den som er i bruk
  først; den gamle `login` flyttes over), `AppModel.logins`, `switchTo`, `remove`, `addingLogin` (RootView viser
  `LoginView` med `avbryt-innlogging`), `signOut` går til den neste. Innstillinger (Apple TV, iPad) og Konto (iPhone):
  «Bytt til …», «Legg til innlogging» (`legg-til-innlogging`), fjern med hurtigmeny/sveip.
- **Top Shelf fra 0.1.13**: målet `FyrlysTopShelf` (tvOS-utvidelse `com.apple.tv-top-shelf`, app-id
  `no.fyrlys.tv.topshelf`, `TopShelf/ContentProvider.swift`) viser favorittene (`TVTopShelfSectionedContent`, logo,
  navn; trykk = `fyrlys://kanal/<id>` → `AppModel.pendingPlay` → `HomeView` spiller). Favorittene deles i en felles
  nøkkelring-gruppe `<team>.no.fyrlys.tv.shared` (`TopShelf/SharedFavorites.swift`, også i app-målet; prefikset
  finnes fra et element lagret i standardgruppen), skrevet av `AppModel.shareFavorites()` ved endringer.
  `adhoc_sign.sh` signerer utvidelsen først (egen app-id og gruppen) og gir appen `keychain-access-groups` (egen
  gruppe først, så innloggingene blir der de var); `asc.py prepare` registrerer app-id-en og lager en profil til for
  utvidelsen (`EXTENSIONS`), og `ExportOptions-tvOS.plist` har begge.
- **0.1.14**: «Se fra start»: `AppModel.archivePlay(channel, program)` → `VODPlay.archive`; `AppModel.replay` vises av
  `HomeView` (fullskjerm/ark). Fra spilleren for direktesendingen (`PlayerModel.startOver`, `canStartOver`; Apple TV i
  `transportBarCustomMenuItems`, iPhone/iPad `fra-start-live`) og fra infoarket i iPhone-guiden (`se-fra-start`) går
  den via `pendingReplay`: direktesendingen stoppes og lukkes (`closeRequested`), og `showPendingReplay()` i
  `onDismiss` viser den (én tilkobling om gangen). Apple TV-guiden: hurtigmeny på programmer (se fra start) og på
  kanalen (TV-arkiv). «Fortsett å se»: `AppModel.continueItems/rememberContinue/forgetContinue` (JSON i
  `fortsett@<innlogging>`, satt av `VODPlayerModel.save`), raden øverst i `PosterGrid` (`fortsett-<id>`). («Åpne i
  VLC» på iOS fra 0.1.14 er tatt bort i 0.1.15.)
- **VLC fra 0.1.15** (eieren: «andre klienter klarer jo å spille av filmer og serier»): VLCKit 3.7.2 (LGPL 2.1, de
  ferdige rammeverkene fra VideoLAN, dynamiske) hentes av `tools/vlckit.sh` til `Vendor/` (ikke i repoet; sjekksum,
  armv7/i386 tatt bort med lipo, nytt xcframework uten dSYM) og ligger som `framework`-avhengighet med embed i
  `project.yml` (`TVVLCKit` for `Fyrlys`, `MobileVLCKit` for `FyrlysMobil`); i bygget med `actions/cache` (nøkkel =
  hashen av skriptet) og `build/vlckit.log` i feilmerknadene. MPVKit ble valgt bort (forfatteren skriver at den ikke
  er for produksjon; Metal bare som lapp), KSPlayer er GPL. `playAttempts` (Core): Apples avspiller for
  mp4/m4v/mov/m3u8, ellers VLC; er ingen av adressene for VLC, prøves den første med VLC til slutt (TV-arkivet:
  m3u8 med AVPlayer, så .ts med VLC). `App/VLCPlayer.swift`: `VLCEngine` (@Observable; `VLCMediaPlayer` med
  `drawable` = `surface` (`VLCSurfaceView`: VLC sin visning inni får alltid samme ramme), hendelsene via
  `VLCEvents` til hovedtråden; valg per media: `:http-user-agent`,
  `:network-caching=3000`, `:start-time`, `:sub-language=nor,…` når appen er på norsk; fra 0.1.17
  `VLCMediaPlayer(options: subtitleStyle())`: undertekstene i Apple sin stil fra MediaAccessibility
  (`MACaptionAppearance…`: skrift (systemskriften → «Helvetica Neue»), relativ størrelse → `--freetype-rel-fontsize`
  18/størrelse, farge/bakgrunn/opasitet → `--freetype-color`/`-background-color`/`-background-opacity`, kant →
  `--freetype-outline-thickness`/`-shadow-opacity`; eieren: «vil ha teksten i orginal Apple stil»); feil = `.error`, eller
  `.ended`/`.stopped` før tiden har gått, eller ingen tid etter 45 s; skrur av skjermsparer/lås mens den spiller) og
  `VLCPlayerScreen` (egne kontroller: Apple TV en usynlig knapp over hele skjermen med fokus, venstre/høyre spoler 10
  s (30/60 ved flere trykk på rad, hoppet etter 0,7 s), ned = menyene `vod-lyd`/`vod-tekst`, Menu skjuler og så
  lukker; iOS trykk for kontrollene, `lukk-vod`, ±10 s, `vod-pause`, Slider; tiden `vod-tid`; kontrollene skjules
  ikke i testene). `VODPlayerModel.vlc` velger visningen i `VODPlayerView`; `finished` lukker når VLC er ferdig.
  Testene `test15Mkv`/`test16MkvFeil` (Apple TV) og `test17Mkv` (iPhone og iPad). Ikke prøvd på ekte enheter ennå.
- **Plex fra 0.1.16** (eieren: «en Plex fane eller noe, som erstattet Filmer/Serier hvis man ville å koble til Plex.
  Gjerne litt som Plezy», så «Gjør noe med det»; Plezy er GPL/Flutter, bare inspirasjon): `Core/.../Plex.swift`
  (`PlexDevice` = X-Plex-hodene med en fast `clientId` per installasjon (`plex-klient` i innstillingene);
  `PlexAccountClient` mot plex.tv: `POST /api/v2/pins?strong=false` (fire tegn til plex.tv/link), `GET
  /api/v2/pins/<id>` til `authToken` kommer, `GET /api/v2/resources?includeHttps=1&includeRelay=1` (bare
  `provides` server, de du eier først); `PlexClient` mot serveren med `X-Plex-Token` i hodet: `reachable` prøver
  tilkoblingene samtidig og tar den beste som svarer på `/identity` (lokale, så utenfra, så relé), `libraries`
  (`/library/sections`, movie/show), `items` (`/library/sections/<n>/all?sort=addedAt:desc`), `details`
  (`/library/metadata/<id>`, serier + `/allLeaves`), `continueWatching` (`/hubs/continueWatching/items`, ellers
  `/library/onDeck`; episodene blir serien sin), `imageURL` (`/photo/:/transcode`, nøkkelen i adressen), `fileURL`
  (`/library/parts/…/file.<ext>?X-Plex-Token=`, spilles direkte; VLC for mkv), `timeline` (playing/paused/stopped,
  ms) og `scrobble`). `VODItem.source`/`Episode.source` = "plex" (nøklene for hvor langt: `plex:<ratingKey>`), og
  `fileKey`/`resume`/`watched`. `App/PlexModel.swift` (`AppModel.plex`: `Phase` off/linking(kode)/choosing/
  connecting/connected/failed, nøkkelen og serveren i nøkkelringen (`Keychain.savePlex`, konto `plex`) med adressen
  som svarte sist, `useForVOD` (`plex-filmer`, satt første gang det kobles til), `report` → timeline/scrobble).
  `VODModel` har en `VODBackend` (xtream, plex, waiting mens Plex kobler til, unavailable(feil)); `AppModel.
  refreshVOD()` ved innlogging og når Plex endres (`onChange`), `VODTab` henter på nytt med `.task(id:
  model.version)`. Plex: «Fortsett å se» fra Plex (`continueRow`), hvor langt du har sett hentes ned fra Plex når
  siden åpnes (`syncProgress`) og sendes opp av `VODPlayerModel.save` (hvert 10. s, `stopped` ved lukking, `scrobble`
  én gang nær slutten); siden og raden hentes på nytt 1,5 s etter at spilleren er lukket. `App/PlexSettings.swift`:
  seksjonen i Innstillinger (Apple TV i en rulleliste nå, iPad i Form) og `PlexSheet` fra Konto på iPhone
  (`plex-innstillinger`); id-ene `koble-til-plex`, `plex-kode`, `plex-tilkoblet`, `vod-kilde`, `koble-fra-plex`.
  Falsk Plex: `tools/fake_plex.py` (port 8897, `FYRLYS_TEST_PLEX`; koden FYRL gir nøkkelen tredje gang, serveren
  «Hjemmekino» med en lokal tilkobling som ikke svarer og en som gjør det, filmene 1001–1003, serien 2001), og
  testskjermene `plex`/`plex-series` (koblet til fra før) og `plex-link`; testene `test17Plex`/`test18PlexKobling`
  (Apple TV) og `test18Plex`/`test19PlexKobling` (iPhone og iPad). Ikke prøvd mot en ekte Plex-server ennå.
- `.github/workflows/build.yml`: kjernen på Linux (`ubuntu-24.04`, som har Swift; `ubuntu-latest` ble Ubuntu 26 uten
  Swift 1.11.2026, og jobben feilet med 127); UI-testene kjøres med `-retry-tests-on-failure -test-iterations 2` (en
  test som feiler, kjøres én gang til: «Timed out while requesting launch progress» og trykk som ikke tas, skjer av og
  til i simulatoren); appen på `macos-15` med høyeste Xcode, XcodeGen, simulator fra
  `tools/simulator.py` (`[plattform] [slag] [variabel]`, f.eks. `iOS iPad IPAD_ID`; laster ned plattformen om den
  mangler), falsk leverandør, `xcodebuild test`, skjermbildene ut med `tools/screenshots.py` (`xcresulttool export
  attachments`) og inn i grenen `skjermbilder`. Jobben `ios` bygger én gang (`build-for-testing`) og tester på iPhone
  og så iPad (`test-without-building`, se Status) og legger bildene i `skjermbilder-mobil`.
- **TestFlight** (jobbene `oppsett` og `testflight`, bare på main og når hemmelighetene `ASC_KEY_ID`, `ASC_ISSUER_ID`,
  `ASC_KEY_P8` og `APPLE_TEAM_ID` finnes; Admin-nøkkel laget av eieren): `tools/asc.py check` (nøkkelen, app-id-en
  `no.fyrlys.tv`, appen i App Store Connect; `ensure_platform` legger IOS til appen med `POST /v1/appStoreVersions`
  første gang), arkiv uten signering for begge plattformene (`CODE_SIGNING_ALLOWED=NO`: å signere for en
  Apple TV krever en utviklerprofil, og den krever en registrert enhet), `tools/adhoc_sign.sh` (ad hoc med
  application-identifier og team), `asc.py prepare` (distribusjonssertifikat og en profil per plattform; med
  hemmeligheten `DIST_KEY` (privat RSA-nøkkel, PKCS#1 eller #8, `DIST_KEY_PATH` i jobben) finnes sertifikatet med
  samme offentlige nøkkel igjen hos Apple (`find_certificate`, sammenligner modulus; går det ut innen to uker, trekkes
  det tilbake og et nytt lages) eller lages første gang, og beholdes; uten den ett per kjøring som `cleanup` trekker
  tilbake,
  `TVOS_APP_STORE` og `IOS_APP_STORE`, med `ExportOptions-tvOS.plist`/`-iOS.plist`, for kjøringen gjennom REST-API-et, JWT med openssl, bare standardbiblioteket; egen nøkkelring), `xcodebuild
  -exportArchive` med `destination upload` og API-nøkkelen per plattform (laster opp selv), `asc.py wait <byggnummer>`
  (venter på bygget for både TV_OS og IOS; feiler hvis ett ikke dukker opp i App Store Connect, eller blir INVALID), og `asc.py cleanup` (sletter profilene og
  trekker tilbake sertifikatet hvis det ble laget for kjøringen; da får eieren en e-post «Your Certificate Has Been
  Revoked» for hvert bygg). Hemmelighetene kan ikke leses eller settes herfra (proxyen stenger `actions/secrets`). Prøvd og forlatt 31.10: Apples skysignering
  (`-allowProvisioningUpdates` med API-nøkkelen) eksporterte uten feil, men App Store Connect avviste bygget
  («Invalid Signature … Fyrlys.app/Fyrlys»); med `altool --upload-app` forsvant byggene stille (bygg 3 og 4).
  `.github/workflows/status.yml` (startes for hånd: `gh api -X POST
  repos/ungerdas/fyrlys-tv/actions/workflows/status.yml/dispatches -f ref=main`) viser de siste byggene og
  testgruppene som merknad (`asc.py builds`). `gh workflow run` virker ikke herfra (GraphQL er stengt).
  Offentlig repo: loggene og artefaktene er synlige for alle, så ingenting hemmelig skrives ut.

## Status
- 31.10.2026: v0.1.0 (TV, guide, søk, innstillinger, spiller), alle UI-testene grønne i simulatoren, lastet opp til
  TestFlight (eieren registrerte `no.fyrlys.tv`, laget appen i App Store Connect, la inn hemmelighetene og laget den
  interne testgruppen). 0.1.1 (bygg 5) er den første som kom fram (VALID, IN_BETA_TESTING); 0.1.1 rettet at
  TV-siden hoppet til Favoritter ved første favoritt. Ikke prøvd på ekte Apple TV ennå, heller ikke ekte strømmer
  fra leverandøren hans (simulatoren spiller Apples eksempelstrøm).
- 31.10.2026: 0.1.1 installert fra TestFlight på hans Apple TV 4K (virker), med leverandøren hans: 25 153 kanaler.
  Treg start og hakking, og han syntes den var «så zoomet inn» og ville ha den så lik Windows-appen som mulig, med
  favorittkategorier («land») han velger rekkefølgen på; bilder viste sidemenyen rulle inn under fanelinja og
  hurtigrullingen oppå tallene. 0.1.2 (bygg 6, VALID i TestFlight 31.10) retter det (se CHANGELOG); i simulatoren
  med 25 000 kanaler kom første kort etter 6,6 s uten lista fra sist og 4,7 s med (med oppstarten). En topplinje som i
  Windows-appen ble skrevet, men forkastet: han vil beholde fanelinja til Apple TV.
- 31.10.2026: 0.1.3: eieren syntes det var «for mye luft mellom enden av tven og appen». TV-siden, guiden, søket og
  innstillingene ignorerer den trygge sonen til Apple TV på sidene (og nederst, unntatt innstillingene) og bruker
  `Theme.edge` = 40 pt; `safeAreaPadding(.bottom, Theme.bottomFocus)` holder kortet med fokus litt over bunnen. Toppen
  står under fanelinja som før.
- Åpent (31.10): 0.1.2 er ikke prøvd på Apple TV-en hans ennå (fart med 25 000 kanaler, de nye kortene, «Dine
  kategorier», at ingenting går inn under fanelinja). «Hjem» (startsiden i Windows-appen) finnes ikke i Apple TV-appen.
  Han får en e-post «Your Certificate Has Been Revoked» for hvert bygg (fra `asc.py cleanup`; 1.11 spurte han hvordan
  han fikser det). Løst 1.11: han la inn hemmeligheten `DIST_KEY` (se TestFlight under); bygg 24 laget sertifikatet
  som beholdes (utløper 1.11.2027, da lages et nytt: én e-post i året), og oppryddingen sletter bare profilene.
  Merknadene `sertifikat` og `opprydding` på TestFlight-jobben viser det. Et bygg kan startes uten endring med
  `gh api -X POST repos/ungerdas/fyrlys-tv/actions/workflows/build.yml/dispatches -f ref=main`.
- 31.10.2026: eieren laget en ekstern TestFlight-gruppe med offentlig lenke; 0.1.3 (bygg 7) ble sendt til Apples
  beta-gjennomgang (Waiting for Review). Nye versjoner kommer ikke av seg selv til den eksterne gruppa (må legges til
  og gjennomgås); tilbudt å automatisere det i bygget, og en demo-innlogging hvis gjennomgangen stopper på innloggingen.
- 31.10.2026: eieren ville ha en iPhone-app også; valgte samme app som Apple TV og iPhone + iPad. 0.1.4 (bygg 10) er
  den første med iOS: VALID for både TV_OS og IOS i App Store Connect (iOS lagt til appen av `asc.py check`). Alle
  UI-testene grønne (iPhone 10, iPad 6, Apple TV). iPhone/iPad er bare prøvd i simulatoren.
- iOS-jobben i CI: første forsøk (begge simulatorene i samme `xcodebuild test`) gikk ut på tid etter 75 min uten
  merknader (sannsynligvis to iOS-simulatorer samtidig på en maskin med 7 GB). Nå: `build-for-testing` én gang, så
  `test-without-building` på iPhone (alle testene) og iPad (et utvalg, `-only-testing`) etter hverandre, tidsgrense per
  test, en vakthund (`limited <min> <logg> …`) som stopper xcodebuild før jobben går ut på tid, merknaden «tester
  iphone/ipad» med hver test og tiden, og utdrag av loggene (`*-utdrag.txt`, `tider.txt`) i `skjermbilder-mobil`.
  Tilgjengelighet på iOS: et kort med to knapper må ha `.accessibilityElement(children: .contain)`, ellers skriver
  «kanal-…» på kortet over id-ene til knappene.
- 31.10.2026: 0.1.5: på iPhone rullet kortene opp under klokka og Dynamic Island (bilde fra eieren). En ScrollView som
  når toppen av skjermen uten navigasjonslinje tegner det som rulles forbi under statuslinja. Nå står kategorivalget
  fast øverst med lista under (ScrollView-en begynner under det); på iPad (og innloggingen) `.clipped()`, som på Apple
  TV. Under fanelinja nederst ruller innholdet fortsatt, som i Apples egne apper (glass).
- 31.10.2026: 0.1.6: eieren ville ha iPhone-appen lik Fyrlys-nettsiden på telefon (bilde): topplinje, «Sist sett»,
  kategorifliser, store kort med logofarge, fanene nederst. Laget som over (se Arkitektur), også lys modus. Nettsiden
  har Filmer og Serier i fanelinja; de finnes ikke i Apple-appen ennå (avtalt senere). Samme kveld (bilde fra hans
  iPhone med ekte strømmer, spilleren virket): «dra med video vinduet for å lukke» – laget i 0.1.6.
- 0.1.7: guiden på iPhone var tom i 0.1.6 (se Arkitektur; det første forsøket traff feil sted, og det bygget feilet
  også på at et trykk på en flis ikke tok i simulatoren, så testene trykker nå én gang til). `UIUserInterfaceStyle:
  Dark` er tatt ut av iOS-målet, så appen følger enheten til man velger lys eller mørk (Apple TV har den fortsatt).
  Apple TV fikk forsiden og de store kortene (se Arkitektur). 0.1.7 (bygg 20) er i TestFlight for både TV_OS og IOS
  (1.11). Ikke prøvd på ekte Apple TV eller iPhone ennå. Fartstesten: flisene etter 14,7 s uten lista fra sist (før:
  første kort etter 6,2–6,5 s) og 5,4 s med (før 4,1–4,3 s); verdt å se på om oppstarten med 25 000 kanaler er blitt
  tregere. `test06Player` på Apple TV trykket ikke Menu i 0.1.7 («kanal-1» fantes bak spilleren); fra 0.1.8 venter
  den på at `spiller` er borte.
- 1.11.2026: 0.1.8: eieren syntes Apple TV-versjonen 0.1.7 var «rart med den toppen» (bilde: den øverste raden kuttet
  under en tom stripe der fanelinja hadde vært) og «uoversiktlig» (fem store kort i bredden). Valgte «Sidemeny + mindre
  kort»: sidemenyen tilbake, radene øverst i «Alle kanaler», seks kort i bredden, ingen klipping under fanelinja, og
  fanelinja følger kortene (`movesTabBar`, se Arkitektur). 0.1.8 (bygg 22) er i TestFlight, VALID for både TV_OS og IOS
  (1.11); alle UI-testene grønne. Fartstesten: første kort etter 6,7 s uten lista fra sist og 4,4 s med (bygg 21: 4,9
  og 4,0), 24 steg i kortene 5,5 s, 20 steg i sidemenyen 4,3 s. Ikke prøvd på ekte Apple TV ennå.
- 1.11.2026: 0.1.9: eieren hadde 0.1.8 på Apple TV-en og ville ha 4–5 kort i bredden i stedet for seks («større
  brikker»); valgt fem (`Metrics.bigColumns`, med litt større tekst og logo). 0.1.9 (bygg 24) er i TestFlight, VALID for
  TV_OS og IOS; fartstesten 5,5 s uten lista fra sist og 4,2 s med. Samme natt (bilde av «Norway» på iPhone):
  «Liker godt UI på iPhone, så gjerne før over noe av det samme på AppleTV»; spurt hva (større kort/fire i bredden,
  kategoritoppen med stjerne, stjerne på alle kort, forsiden fra iPhone), han ville prøve 0.1.9 først.
- 1.11.2026: 0.1.10: etter å ha prøvd 0.1.9: «Syntes flisene kan være bittelitt større. Savner Fyrlys logo osv» →
  fire kort i bredden og Fyrlys-merket øverst til venstre (se Arkitektur). «osv» ikke avklart (topplinja på iPhone har
  også sol/måne og Konto; Apple TV er alltid mørk og har Innstillinger i fanelinja). 0.1.10 (bygg 25) er i
  TestFlight, VALID for TV_OS og IOS; sertifikatet fra bygg 24 ble brukt igjen (merknaden «Bruker
  distribusjonssertifikatet fra før»), så `DIST_KEY` virker. Fartstesten 5,8 s uten lista fra sist og 4,4 s med.
  Eieren prøvde 0.1.10 på Apple TV-en samme natt: «Syntes dette var konge jeg!» Sidemenyen, fire kort i bredden,
  radene øverst og merket er altså godkjent; ikke endre uten at han ber om det.
- 1.11.2026 kl. 05: eieren spurte «Hva mer kan forbedres?», fikk lista (kanalbytte med fjernkontrollen, valg i guiden
  på Apple TV, felles favoritter via iCloud, Top Shelf, filmer og serier, TV-arkiv, flere innlogginger) og svarte
  «Kjør alt.» 0.1.11 = kanalbytte + guidevalg; 0.1.12 = filmer og serier, TV-arkiv, flere innlogginger og felles
  favoritter via iCloud; Top Shelf til slutt (krever en egen utvidelse med egen app-id og profil i signeringen).
  0.1.11 (bygg 26) og 0.1.12 (bygg 27) er i TestFlight, VALID for TV_OS og IOS; `asc.py check` slo på ICLOUD for
  app-id-en, og eksporten med iCloud-rettigheten gikk. 0.1.12 ble bygget med `workflow_dispatch` etter at koden var
  pushet med [skip ci] (en push under en opplasting avbryter den). Første bygg av 0.1.13 (Top Shelf) ble avvist av
  App Store Connect: utvidelsen må ha `UIRequiredDeviceCapabilities: [arm64]` i Info.plist (signeringen og profilene
  for `no.fyrlys.tv.topshelf` virket). Med det er 0.1.13 (bygg 29) i TestFlight, VALID for TV_OS og IOS: hele lista
  fra «Kjør alt.» er ute. Ikke prøvd på hans enheter ennå: filmer/serier mot leverandøren hans (mkv?), TV-arkivet,
  iCloud-delingen mellom iPhone og Apple TV, Top Shelf (vises logoene over http?), kanalbytte med opp/ned.
- 1.11.2026: eieren spurte «kan du forbedre det du kan?» → 0.1.14 (bygg 30, VALID for TV_OS og IOS): se fra start,
  «Fortsett å se», «Åpne i VLC». Så: «hvorfor kan den ikke spille av MKV? andre klienter klarer jo å spille av filmer
  og serier uten problem» → forklart (AVPlayer kan ikke mkv), foreslått en innebygd avspiller, han svarte «Ja». 0.1.15
  = VLC (se Arkitektur). Samme dag ønsket han Plex i stedet for Filmer/Serier («Gjør noe med det når du har
  mulighet») → 0.1.16. 0.1.15 (bygg 31) er i TestFlight, VALID for TV_OS og IOS; VLC spilte testfilmen riktig i
  simulatorene. (NB: testfilmen `testsrc` har en svart stripe til venstre, som lett ser ut som at bildet er
  forskjøvet; det var det ikke. Sammenlign med en ramme fra ffmpeg før du «retter» noe.) 0.1.16 (bygg 32, Plex) er i
  TestFlight, VALID for TV_OS og IOS; alle UI-testene grønne. Ikke prøvd mot hans Plex-server ennå (tilkoblingen
  utenfra/hjemmenettet, store bibliotek, hvor langt du har sett tilbake til Plex/Tautulli). Eieren prøvde 0.1.16
  samme dag: «Funker fint» (Tautulli viste Fyrlys på Apple TV med Direct Play av HEVC Main 10, EAC3 og norsk SRT),
  «men vil ha teksten i orginal Apple stil» → 0.1.17. Så (bilde av radene i Plex: «Nytt fra TV 2», «Nytt fra
  TVNorge / HBO Max / discovery+», «Nytt fra NRK»): «Ønsker også de radene slik som på plex.» → 0.1.18: «Hjem»
  (`VODModel.home` = "hjem", først i sidemenyen når det finnes rader eller «Fortsett å se») med `PlexHomeView`
  (`App/PlexHome.swift`): «Fortsett å se» (`fortsett-<id>`) og radene (`rad-<id>`, episoder `rad-e<id>`) fra
  `PlexClient.rows` (`/hubs/promoted?contentDirectoryID=<bibliotekene>&pinnedContentDirectoryID=…&count=20&
  excludeContinueWatching=1`, ellers `/hubs/sections/<n>`; `parseHubs`: filmer i Filmer, serier/sesonger/episoder i
  Serier, uten «Fortsett å se» og rader med noe annet). Episodene spilles med en gang (`withFile` henter fila om den
  mangler), hold inne = «Gå til serien». Testene `test17Plex`/`test19PlexSerier` (Apple TV), `test18Plex`/
  `test20PlexSerier` (iPhone og iPad). Ikke sjekket mot hans server: om samlingene hans står i `/hubs/promoted`.
  0.1.17 (bygg 33) og 0.1.18 (bygg 34) er i TestFlight, VALID for TV_OS og IOS. Eieren om 0.1.17 på iPhone (bilde av Mayday): «Teksten er
  ikke Apple stil» (grå tekst uten boks: «Undertekster og teksting» har gjennomsiktig bakgrunn som standard, og
  skyggen bak kontrollene la seg over), «når jeg forsøker å få liggende visning fra stående, så funker ikke det», og
  «ønsker også en fortsett å se knapp på serier som går rett til den episoden jeg skal se» → 0.1.19: fast stil
  (`subtitleStyle`: «Helvetica Neue Medium», hvit, boks svart 150, uten kant/skygge, `--no-video-title-show`; bare
  størrelsen fra MediaAccessibility), `Landscape` (`App/VLCPlayer.swift`: `requestGeometryUpdate` til liggende når
  `VODPlayerView` åpnes på iPhone, tilbake til stående ved lukking hvis den sto slik; knappen `snu-skjermen` i
  VLC-kontrollene), og `fortsett-serie` på seriesiden (`nextEpisode`: den du er midt i, ellers den etter den siste
  sett ferdig (`watched` fra Plex eller `AppModel.isFinished`, satt av `VODPlayerModel.save` nær slutten), ellers den
  første; sesongen velges). Skjermbildene må hete `NN-…` (`tools/screenshots.py`), ikke `26b-…`.
  Samme dag: «Fyrlys skal kun bruke disse m3u8 fra NRK. Det er direkte.» (fire adresser fra et CDN for NRK1, NRK2,
  NRK3 og NRK Super). Adressene skal IKKE inn i repoet eller appen (offentlig repo og offentlig TestFlight-lenke);
  laget i stedet «Egne strømmer» (0.1.19): `Core/.../Streams.swift` (`channelKey(navn)`: små bokstaver og tall uten
  landskode foran og kvalitet bak, «NO: NRK1 HD» → nrk1; `channelKey(of: url)`: filnavnet, eller mappen over når
  filnavnet er generelt (muxed, index, playlist …); `parseStreamOverrides`: «adresse» eller «Kanalnavn = adresse»),
  `AppModel.streamLines`/`setStreams`/`streamURL(channel)` (brukt av `PlayerModel` i stedet for `liveURL`), lagret i
  iCloud-nøkkelen `egne-strommer` (`CloudStore.shared`), `App/StreamSettings.swift` (TextEditor på iPhone/iPad, på
  Apple TV lista og ett felt for én linje), `StreamSheet` fra Konto (`egne-strommer`), id-ene `egen-strom-<nøkkel>`.
  Testskjermen `strommer`, `FYRLYS_TEST_STREAMS`; testene `test20EgneStrommer` (Apple TV, også at spilleren bruker
  adressen) og `test21EgneStrommer` (iPhone og iPad). Eieren svarte så «Bygg inn for alle.» → `builtInStreams` i
  Streams.swift (de fire NRK-adressene), brukt for alle (`AppModel.useBuiltInStreams`, «NRK direkte» av/på i
  innstillingene, lagret som `innebygde-strommer-av`; egne strømmer for samme kanal går foran).
  Første bygg av 0.1.19 (bygg 35): iPad feilet i `test20PlexSerier` (id-en «rad-e…» på en knapp med `.contextMenu`
  ble borte; nå settes id-en før hurtigmenyen) og `test21EgneStrommer` (Form på iPad er lat: testen ruller fram);
  `Landscape.set(true)` i `onAppear` ble avvist mens arket kom inn (knappen virket senere), nå 0,6 s etter.
  0.1.19 (bygg 36) er i TestFlight, VALID for TV_OS og IOS; alle UI-testene grønne (undertekstene i boks på Apple
  TV og iPhone, iPhone åpner spilleren liggende). Ikke prøvd på hans enheter ennå, heller ikke NRK-adressene. Fortsatt bare for
  kanaler leverandøren har (navnet må bli nrk1/nrk2/nrk3/nrksuper), så programinfo, logo og favoritter er som før.
  0.1.20: «Burde vi slå sammen da, NRK er en, NRK 2 er en …» → `ChannelIndex(lists, merging: keys)` (`mergeKeys` =
  nøklene til de egne og innebygde strømmene, `AppModel.remerge()` når de endres): kanaler med samme `channelKey`
  blir én (den med EPG og logo, i alle kategoriene til de andre; `byId` for de andre id-ene peker dit, `ids(of:)`,
  `merged`; søket på alle navnene). Favoritt/ikke favoritt gjelder alle id-ene (`AppModel.isFavorite`/
  `toggleFavorite`), og `channels(_:in:)` tar hver kanal én gang. Falsk leverandør: 91 «Fjordkanalen HD» (i Test),
  slås sammen med 1 i `test20EgneStrommer`/`test21EgneStrommer` («Alle kanaler» 19).
  Bygg 37 feilte bare på iPad i `test01Login` (to ganger; samme kode gikk i bygg 38, så simulatoren). Steget «Merknad
  ved feil» stoppet før merknadene for testene (grep uten treff med pipefail), nå med `set +e`, og
  `test-*-utdrag.txt` begynner med alle «error:»-linjene. 0.1.20 (bygg 38) er i TestFlight, VALID for TV_OS og IOS.
  Fartstesten i bygg 38: 37,2 s uten lista fra sist (bygg 37 med samme kode: 5,6 s), 5,0 s med; trolig en treg
  runner, men se etter om det skjer igjen.
  Eieren sendte samme dag et bilde fra iPhone (0.1.20, kategorien Norway): leverandøren har landskoden bak («NRK 1 HD
  NO», «NRK 1 FHD NO», «NRK 2 Lydtekst HD NO», «NRK 3/SUPER NO», «NRK 3/SUPER HD NO»), så ingenting ble slått sammen.
  0.1.21: `channelKey` tar bort landskoden bak (`trailingCountryCodes`, når det er flere ord) og «lydtekst»/«tegnspråk»;
  `channelAlternatives`/`matchingStreamKeys`: «a/b» i navnet er to kanaler; `ChannelIndex` deler en slik i to når
  begge har en strøm (den første beholder id-en og får navnet «NRK 3 NO», den andre er `Channel.split`: id
  `<id>~<nøkkel>`, `source` = leverandørens id, uten logo; `Channel.streamId` brukes for adressen, EPG og arkivet).
  Delte kanaler taper mot ekte når de slås sammen (poeng 4). Testen `testMergingWithCountryLast`.

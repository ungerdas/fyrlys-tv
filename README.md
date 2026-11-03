# Fyrlys for Apple TV, iPhone og iPad

![Fyrlys](docs/ikon.png)

En enkel IPTV-spiller for Apple TV, iPhone og iPad: logg inn med Xtream Codes fra IPTV-leverandøren din og se TV.

- **TV**: favoritter, sist sett, alle kanaler og kategoriene, med det som går nå på hvert kanalkort. Legg kategoriene
  du bruker mest i «Dine kategorier», i den rekkefølgen du vil. Hold inne på en kanal for å gjøre den til favoritt (på
  iPhone og iPad kan du også trykke på stjernen).
- **TV-guide** for de neste seks timene.
- **Søk** i kanalene.
- **Spilleren** er Apples egen (AVPlayer). På Apple TV kan du pause og spole tilbake, bytte til neste eller forrige
  kanal i kontrollene, og sveipe ned for kanallista. På iPhone og iPad står kanallista under bildet, med bilde-i-bilde
  og AirPlay.
- **Filmer og serier** med «Hjem» først: «Fortsett å se» (med episoden og hvor langt du har kommet), favorittene og
  kategoriene som rader med «Se alle». Søk, en side for hver film og serie, episodene sesong for sesong. Filtyper
  Apples avspiller ikke kan (mkv, avi …), spilles med VLC, med valg av lydspor og undertekster.
- **TV-arkiv** for kanaler som har det hos leverandøren, og «se fra start» på det som går nå.
- **Plex**: koble til Plex-serveren din (med en kode på plex.tv/link), og fanene Filmer og Serier viser bibliotekene
  derfra. Hvor langt du har sett, og hva du har sett, holdes i takt med Plex.
- **iPhone**: som Fyrlys på nettet på en telefon, med favorittene og det du har sett sist øverst, kategoriene som
  fliser, store kanalkort med logoens egen farge, og lys eller mørk modus.
- Norsk og engelsk, etter språket på enheten.

Innloggingen lagres kryptert i nøkkelringen på enheten og sendes bare til leverandøren din. Appen har ingen kanaler
selv og samler ingenting inn.

Fyrlys trenger tvOS 17 eller iOS/iPadOS 17 eller nyere. Kanalene spilles som HLS (`.m3u8`), og det støtter de fleste
Xtream-leverandører.

## Status

Under utvikling, og kommer via TestFlight. Skjermbilder fra testene ligger i grenene
[`skjermbilder`](../../tree/skjermbilder) (Apple TV) og [`skjermbilder-mobil`](../../tree/skjermbilder-mobil) (iPhone og
iPad), og de er tatt mot en falsk leverandør med oppdiktede kanaler.

## Bygge selv

Prosjektet lages med [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
tools/vlckit.sh   # VLCKit fra VideoLAN til Vendor/
xcodegen generate
open Fyrlys.xcodeproj
```

- Kjernen (`Core/`: Xtream, programinfo, favoritter, tekstene) er en Swift-pakke. Den kan testes på macOS og Linux med
  `swift test --package-path Core`.
- Appen selv (`App/`) er SwiftUI, med to mål: `Fyrlys` (Apple TV) og `FyrlysMobil` (iPhone og iPad).
- Testene i simulatorene (`UITests/` og `UITestsMobil/`) bruker `tools/fake_xtream.py` og `tools/fake_plex.py`.

## Lisenser

Filmer og serier i andre filtyper enn Apples spilles med [VLCKit](https://code.videolan.org/videolan/VLCKit) fra
VideoLAN (LGPL 2.1), som et eget rammeverk inni appen. `tools/vlckit.sh` henter de ferdige rammeverkene VideoLAN legger
ut.

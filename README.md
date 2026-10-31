# Fyrlys for Apple TV

![Fyrlys](docs/ikon.png)

En enkel IPTV-spiller for Apple TV: logg inn med Xtream Codes fra IPTV-leverandøren din og se TV.

- **TV**: favoritter, sist sett, alle kanaler og kategoriene, med det som går nå på hvert kanalkort.
  Hold inne på en kanal for å gjøre den til favoritt.
- **TV-guide** for de neste seks timene.
- **Søk** i kanalene.
- **Spilleren** er Apple TV sin egen (AVPlayer). Du kan pause og spole tilbake, bytte til neste eller forrige kanal i
  kontrollene, og sveipe ned for kanallista.
- Norsk og engelsk, etter språket på Apple TV-en.

Innloggingen lagres kryptert i nøkkelringen på Apple TV-en og sendes bare til leverandøren din. Appen har ingen
kanaler selv og samler ingenting inn.

Fyrlys trenger tvOS 17 eller nyere. Kanalene spilles som HLS (`.m3u8`), og det støtter de fleste Xtream-leverandører.

## Status

Under utvikling. Den første versjonen kommer via TestFlight. Skjermbilder fra testene i Apple TV-simulatoren ligger i
grenen [`skjermbilder`](../../tree/skjermbilder), og de er tatt mot en falsk leverandør med oppdiktede kanaler.

## Bygge selv

Prosjektet lages med [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open Fyrlys.xcodeproj
```

- Kjernen (`Core/`: Xtream, programinfo, favoritter, tekstene) er en Swift-pakke. Den kan testes på macOS og Linux med
  `swift test --package-path Core`.
- Appen selv (`App/`) er SwiftUI.
- Testene i simulatoren (`UITests/`) bruker `tools/fake_xtream.py`.

# Endringer

## v0.1.2

- Raskere med store kanallister (titusenvis av kanaler): lista fra sist pakkes ut i bakgrunnen når appen starter, og en
  ny liste gjøres klar i bakgrunnen og byttes bare inn når noe er endret.
- Mindre hakking når du blar: et kort tegnes bare på nytt når programinfoen for den kanalen kommer, ikke alle kortene
  hver gang. Programinfo hentes først når et kort har vært framme litt, og ikke for eventkanaler eller kanaler
  leverandøren ikke har programinfo for.
- TV-guiden tegnes ikke lenger på nytt for hvert steg du flytter, og er mindre, så flere kanaler får plass.
- TV-siden som i Fyrlys på Windows: kompakte kanalkort med logo, klokkeslett, kanalnummer og stjerne, og sidemenyen
  med «Dine kategorier» og «Alle kategorier».
- «Dine kategorier»: hold inne på en kategori i sidemenyen for å legge den øverst, flytte den opp eller ned, eller ta
  den bort fra toppen. Kanalene derfra kommer også først i «Alle kanaler», i søket og i guiden.
- Sidemenyen og kortene ruller ikke lenger inn under fanelinja, og prikkene for hurtigrulling (som la seg oppå tallene
  og kunne ta fokus) er borte.

## v0.1.1

- TV: siden hopper ikke lenger til Favoritter når du legger til den første favoritten.

## v0.1.0

Første versjon for Apple TV:

- Innlogging med Xtream Codes (server, brukernavn og passord), lagret kryptert i nøkkelringen på Apple TV-en.
- TV: favoritter, sist sett, alle kanaler og kategoriene, med kanalkort som viser det som går nå. Hold inne på en
  kanal for å legge den til i favorittene.
- TV-guide for de neste seks timene.
- Søk i kanalene.
- Spilleren til Apple TV (AVPlayer), med neste og forrige kanal, favoritt og kanallista når du sveiper ned.
- Norsk og engelsk, etter språket på Apple TV-en.

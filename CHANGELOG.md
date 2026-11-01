# Endringer

## v0.1.11

Apple TV:

- Bytt kanal med opp og ned på fjernkontrollen mens du ser på, som på vanlig TV. Mens du bytter, ser du kanalen og
  programmet som går nå.
- TV-guiden: velg hva den viser oppe til høyre – favorittene, sist sett, alle kanaler, «Dine kategorier» eller en
  annen kategori. Valget huskes.

## v0.1.10

- Apple TV: kanalkortene er litt større, fire i bredden.
- Fyrlys-merket og navnet står øverst til venstre, på linje med fanelinja, som på iPhone. Sidemenyen ruller under det.

## v0.1.9

- Apple TV: større kanalkort, fem i bredden i stedet for seks (også i radene øverst og litt større i søket).

## v0.1.8

Apple TV, mer oversiktlig:

- Sidemenyen er tilbake til venstre: Alle kanaler, Favoritter, Sist sett, «Dine kategorier» og resten av kategoriene.
  Hold inne på en kategori for å legge den øverst eller flytte den.
- «Alle kanaler» åpner med «Nå på favorittene» og «Sist sett» som rader øverst, og så kanalene.
- Mindre kanalkort, seks i bredden, med logoen på logoens egen farge og det som går nå.
- Toppen: fanelinja glir bort når du blar nedover i kortene, og kortene ruller helt opp. Før ble de kuttet under en tom
  stripe der fanelinja hadde vært.

## v0.1.7

Apple TV som iPhone:

- TV-fanen åpner med «Nå på favorittene» og «Sist sett» som rader med store kort, og kategoriene som fliser
  (Favoritter, Alle kanaler, «Dine kategorier» i gult og resten). En kategori åpnes som egen side; Menu-knappen går
  tilbake. Fanelinja øverst er som før.
- Store kanalkort, også i søket: logoen på logoens egen farge, en strek for hvor langt programmet har kommet, det som
  går nå og kanalnavnet. Hold inne på en kanal for å gjøre den til favoritt, og på en kategori for å legge den øverst
  eller flytte den.

iPhone og iPad:

- TV-guiden på iPhone viste ingen kanaler (radene havnet utenfor skjermen), og på iPad sto de for langt til høyre.
- Appen følger lys eller mørk modus på enheten til du velger selv (0.1.6 var alltid mørk til du trykket på sola).

## v0.1.6

iPhone som Fyrlys på nettet:

- Topplinje med fyret og «Fyrlys», sola eller månen for lys og mørk modus, og Konto (abonnementet, hent listene på
  nytt og logg ut). Fanene TV og TV-guide nederst.
- TV-siden: søk øverst, «Nå på favorittene» og «Sist sett» med det som går nå, og kategoriene som fliser (Favoritter,
  Alle kanaler, «Dine kategorier» i gult og resten).
- En kategori åpnes som egen side: tilbake, kategorien (trykk for å velge en annen) og stjernen som legger den øverst.
  Sveip fra venstre kant for å gå tilbake.
- Store kanalkort: logoen på logoens egen farge, en strek for hvor langt programmet har kommet, det som går nå og
  kanalnavnet. Stjernen oppe til høyre gjør kanalen til favoritt.
- TV-guiden (også på iPad): velg favorittene, alle kanaler eller en kategori, «Til nå», og tidene og kanalene står fast
  når du ruller. Trykk på det som går nå for å spille.
- Lys modus («Nordisk lys») på iPhone og iPad. Den følger telefonen til du velger selv; på iPad under Innstillinger.
  Spilleren er alltid mørk.
- Spilleren på iPhone og iPad: dra bildet ned for å lukke den (slipper du tidlig, spretter den tilbake).

## v0.1.5

- iPhone: kanalkortene ruller ikke lenger opp under klokka og Dynamic Island. Kategorien står fast øverst, og lista
  ruller under den.
- iPad: sidemenyen og kortene ruller ikke inn under linja øverst.

## v0.1.4

Fyrlys for iPhone og iPad, i samme app som Apple TV (samme TestFlight-lenke):

- iPhone: faner nederst. På TV-siden åpner tittelen kategoriene, med stjerner for «Dine kategorier», som du kan dra i
  den rekkefølgen du vil. Kanalkortene står i en liste med stjerne du kan trykke på. Dra ned for å hente listene på
  nytt.
- iPad: sidemenyen og rutenettet som på Apple TV, med stjerner du kan trykke på.
- TV-guiden ruller sidelengs. Trykk på kanalen eller det som går nå for å spille, eller på et annet program for info.
- Spilleren: bildet øverst med bilde-i-bilde og AirPlay, kanalen og programmet, forrige, neste og favoritt, og
  kanallista under. Liggende iPhone viser bare bildet, og på en iPad på tvers står lista ved siden av.

## v0.1.3

- Mindre luft mot kantene av TV-en: TV-siden, guiden, søket og innstillingene går nærmere sidene (40 pt i stedet for
  Apple TV sin trygge sone på 80) og helt ned til bunnen. Guiden er litt bredere.

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

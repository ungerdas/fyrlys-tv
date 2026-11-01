# Endringer

## v0.1.21

- NRK-kanalene slås sammen også når leverandøren har landskoden bak navnet («NRK 1 HD NO», «NRK 1 FHD NO»), og
  utgavene med lydtekst og tegnspråk regnes som samme kanal («NRK 2 Lydtekst HD NO» er NRK2). Med NRK direkte spilles
  de fra NRK med vanlig lyd.
- «NRK 3/SUPER» blir to kanaler, NRK3 og NRK Super, som spilles fra hver sin strøm hos NRK. Programinfoen og
  TV-arkivet er leverandørens for den delte kanalen. NRK Super har ingen egen logo der, så kortet viser navnet.

## v0.1.20

- NRK1, NRK2, NRK3 og NRK Super står én gang hver. Leverandøren har ofte flere utgaver av samme kanal («NRK1 HD»,
  «NRK1 FHD», «NRK 1»), men med NRK direkte spilles de fra samme strøm, så de er slått sammen: den med programinfo og
  logo beholdes og står i alle kategoriene de andre sto i. Det samme gjelder kanaler du har lagt inn en egen strøm
  for. Favoritter og «Sist sett» fra de andre utgavene peker til den som er igjen, og søket finner den på alle
  navnene. Slås NRK direkte av, er de der hver for seg igjen.

## v0.1.19

- Undertekstene i filmer og serier som spilles med VLC er hvit tekst på en halvgjennomsiktig mørk boks, som hos
  Apple. I 0.1.17 ble boksen borte, og teksten ble grå når kontrollene var framme. Tittelen VLC viste øverst i
  starten, er borte.
- iPhone: filmer og serier spilles liggende, som i Apple TV-appen, også når skjermretningen er låst. Knappen oppe til
  høyre snur mellom liggende og stående, og når du lukker, er telefonen tilbake slik den sto.
- Seriesiden har en knapp rett til episoden du skal se: «Fortsett S1 E3 (4:45)» når du er midt i en, ellers «Neste:
  S1 E4» etter den siste du har sett, eller «Spill av S1 E1». Sesongen med episoden er valgt når siden åpnes.
  Episoder du har sett ferdig, er merket «Sett» (også fra IPTV-leverandøren).
- NRK direkte: NRK1, NRK2, NRK3 og NRK Super spilles direkte fra NRK i stedet for fra leverandøren (innebygd, kan
  slås av under Innstillinger).
- Egne strømmer: lim inn adresser (m3u8) under Innstillinger (Konto på iPhone), én per linje, så spilles de i stedet
  for leverandørens for kanalene de gjelder. Kanalen finnes ut fra navnet i adressen («…/nrk1/muxed.m3u8» er NRK1),
  eller skriv «Kanalnavn = adresse». Adressene deles med iCloud, så det holder å lime dem inn på iPhonen; Apple TV-en
  viser hvilke kanaler de gjelder.

## v0.1.18

- Plex: «Hjem» øverst i Filmer og Serier, med radene fra Hjem i Plex («Nytt fra …», «Nylig lagt til» og samlingene du
  har lagt der) og «Fortsett å se». Filmer og serier åpnes som egen side; en episode i en rad spilles med en gang, der
  du slapp. Hold inne på en episode for å gå til serien.

## v0.1.17

- Undertekstene i filmer og serier som spilles med VLC (mkv og Plex) ser ut som Apple sine: hvit tekst på en
  halvgjennomsiktig mørk bakgrunn, i stedet for VLC sin tykke svarte kant. De følger «Undertekster og teksting» i
  innstillingene på Apple TV-en, iPhonen eller iPaden (skrift, størrelse, farger og bakgrunn), som Apples egen
  avspiller.

## v0.1.16

- Plex: koble til under Innstillinger (Konto på iPhone). Apple TV-en viser en kode du skriver inn på plex.tv/link, og
  har kontoen flere servere, velger du én. Fyrlys finner selv adressen som svarer (hjemmenettet først).
- Med Plex viser fanene Filmer og Serier bibliotekene dine fra Plex, sist lagt til først, med plakatene, siden for hver
  film og serie og episodene sesong for sesong. Du kan bytte tilbake til filmene og seriene fra IPTV-leverandøren i
  innstillingene.
- Filene spilles rett fra Plex-serveren (mkv med VLC). Hvor langt du har sett, sendes til Plex, ferdige filmer og
  episoder merkes som sett, og «Fortsett å se» kommer fra Plex, så det stemmer med de andre Plex-appene.

## v0.1.15

- Filmer og serier i mkv, avi og andre filtyper Apple-enhetene ikke spiller selv, spilles nå i Fyrlys, med VLC bygget
  inn. Du kan velge lydspor og undertekster (norske undertekster velges av seg selv når filmen har dem), pause og spole
  (på Apple TV med venstre og høyre, raskere når du trykker flere ganger), og den begynner der du slapp.
- Filmer i mp4 og HLS spilles som før med Apples avspiller; får den ikke til en fil, prøves VLC.
- TV-arkivet: virker ikke HLS-adressen, spilles programmet som MPEG-TS med VLC.
- «Åpne i VLC» på iPhone og iPad er borte (det trengs ikke lenger).

## v0.1.14

- Se fra start: i spilleren («Se fra start» i kontrollene på Apple TV, «Fra start» på iPhone og iPad) og i TV-guiden
  (hold inne på et program på Apple TV, eller trykk på det på iPhone), for kanaler med TV-arkiv. Direktesendingen
  stoppes først, så det går også med bare én tilkobling.
- I TV-guiden på Apple TV: hold inne på en kanal for TV-arkivet.
- Filmer og Serier: «Fortsett å se» øverst, med det du har begynt på.
- iPhone og iPad: kan en film ikke spilles (som mkv), kan du åpne den i VLC.

## v0.1.13

- Apple TV: favorittene dine står på hjemskjermen (Top Shelf) når Fyrlys har fokus. Trykk på en kanal for å se den
  med en gang.
- Apple TV: siden for en film står til venstre som de andre sidene, og sesongen eller dagen som er valgt i serier og
  TV-arkivet, er lett å lese også når den har fokus.

## v0.1.12

- Filmer og serier: egne faner på Apple TV, iPhone og iPad, med kategoriene, plakatene, en side for hver film og
  serie (handling, år, sjanger, lengde og terningkast) og episodene sesong for sesong. «Fortsett» begynner der du
  slapp. Filmer i formater Apple-enhetene ikke kan spille (som mkv), prøves først som strøm fra leverandøren; går det
  ikke, står det hvorfor.
- TV-arkiv: hold inne på en kanal som har arkiv hos leverandøren og velg «TV-arkiv». Velg dag og program, og se det
  fra start – også det som går nå. Du kan spole i programmet.
- Flere innlogginger: legg til en innlogging under Innstillinger (Konto på iPhone), og bytt mellom dem der. Logger du
  ut av én, brukes den neste.
- Favorittene og «Dine kategorier» er de samme på iPhone, iPad og Apple TV med samme Apple-ID (iCloud). Legger du til
  en favoritt på telefonen, er den på TV-en også. Første gang flettes det hver enhet hadde fra før, så ingenting
  forsvinner. «Sist sett» er fortsatt per enhet.

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

# Endringer

## v0.2.4

- Mac: tastene i spilleren: mellomrom (pause), ← og → (10 sekunder), ↑ og ↓ (forrige og neste kanal), F
  (fullskjerm), M (lyd av) og I (minispiller). ⌘F går til søket, ⌘1–5 til TV, TV-guide, Filmer, Serier og Plex. Den
  nye menyen «Avspilling» har det samme.
- Mac: minispiller. Direktesendingen i et lite vindu som ligger over alt, også andre apper, mens du blar i Fyrlys
  eller gjør noe annet. Knappen «Minispiller» i spilleren (eller I); dobbeltklikk eller «Tilbake i vinduet» tar den
  tilbake uten at sendingen starter på nytt.
- Mac: vinduet åpner der det var, like stort, og i fullskjerm hvis det var det sist.
- Kanalkortene på Mac og iPad: nummeret står over stjerna, så navnet får mer plass, og kanaler uten program under
  (som eventkanalene med kampen i navnet) får navnet på to linjer. På Mac viser musa over kortet hele navnet.
- Plex Home: slå på «Spør hvem som ser på» (Innstillinger → Plex), så kommer «Hvem ser på?» første gang Plex-fanen
  åpnes etter at appen har startet. «Bytt bruker» står der også.
- iPhone, iPad og Mac: Siri og Snarveier. Si «Spill NRK1 i Fyrlys» (eller «Se …»); Siri kjenner favorittene og
  kanalene du har sett sist.
- iPhone, iPad og Mac: «Minn meg på» på programmer som ikke har begynt i TV-guiden. Varselet kommer to minutter før,
  og et trykk på det spiller kanalen.
- iPhone og iPad: widget med favorittkanalene på hjemskjermen (liten, middels og stor). Trykk på en kanal for å se
  den.
- Apple TV: Top Shelf viser «Fortsett å se» (fra Plex og leverandøren) med hvor langt du har kommet, over
  favorittene. Et trykk åpner siden for filmen eller serien.
- iPad på høykant: Innstillinger og Søk er ikoner i fanelinja, så alle fanene får plass (før sto Innstillinger bak
  en pil).
- Nye versjoner sendes til de eksterne testerne i TestFlight av seg selv (etter Apples gjennomgang).

## v0.2.3

- Mac: film- og seriesiden ser ut som i Fyrlys for Windows: stort bakgrunnsbilde, plakaten, logoen, merkene,
  knappene («Spill av», «Fra start», «Merk som sett», favoritt), handlingen med «Skuespillere» og «Regi», sesongene
  som valg (med hake når alt er sett) og episodene i et rutenett med bilde, nummer og ⋮-meny.
- Mac: filmer og episoder spilles over hele vinduet (før i et lite ark), med lukkeknapp og Esc. VLC-spilleren har en
  fullskjermknapp, og lyd og undertekster er valg nede til høyre som viser sporet som er valgt.
- Mac: «Hvem ser på?» i Plex og de andre arkene (bibliotekene, TV-arkivet, feilrapporten, kanalvalget i multiview)
  var nesten tomme; nå får de plass. Bibliotekene i Plex har «…» (og høyreklikk) for å flytte og skjule dem.
- Kortere navn på lydspor og undertekster: «Norsk», «Engelsk (SDH)» i stedet for «Norsk - [Norwegian]» og
  «Track 1 - [English]».
- Plex: en episode i radene på Hjem («Nylig utgitte episoder» o.l.) og i «Fortsett å se» åpner serien, der knappen
  fortsetter der du slapp. Hold inne (Mac: høyreklikk) og velg «Spill av episoden» for å spille den direkte.

## v0.2.2

- **Fyrlys for Mac** (macOS 14 Sonoma eller nyere, Intel og Apple Silicon), som en del av den samme appen i
  TestFlight. Den ser ut som Fyrlys for Windows: merket, seksjonene (TV, TV-guide, Filmer, Serier, Plex), søket, lys
  eller mørk og innstillingene øverst i vinduet; sidemenyen og kanalkortene; TV-guiden; filmer og serier med VLC for
  mkv og andre filtyper; Plex; multiview; spilleren med kanallista ved siden av bildet og Macens egne kontroller
  (fullskjerm, bilde-i-bilde, AirPlay). Esc lukker spilleren, ⌘, åpner innstillingene.

## v0.2.1

- Apple TV: sidemenyen i Filmer, Serier og Plex er smalere (220 i stedet for 340 punkter), så plakatene får mer
  plass. TV-siden er som før.
- «Fortsett å se» i Serier: når en episode er sett ferdig, står den neste episoden på kortet og spilles med en gang
  (før åpnet kortet seriesiden). Etter den siste episoden åpnes seriesiden som før.
- Episodelista på seriesiden viser bildet fra hver episode (uten bilde nummeret), med nummeret foran tittelen.

## v0.1.37

- Plakatene, bakgrunnsbildene og logoene var uskarpe: appen krympet alle bilder til 360 piksler (ment for
  kanallogoene) og ba Plex om små bilder. Nå hentes hvert bilde så stort som det vises på skjermen (Apple TV 4K og
  iPhone tegner med 2–3 piksler per punkt), og Plex spørres om plakater i 720 × 1080, bakgrunner i 1920 × 1080 og
  logoer i full størrelse.

## v0.1.36

- Siden for en film eller serie er fylt ut: bakgrunnsbildet øverst (tonet over i bakgrunnen), logoen til filmen eller
  serien fra Plex i stedet for tittelen når Plex har den, slagordet, studioet blant merkene, «Regi:» og raden
  «Medvirkende» med bilde og rolle (fra Plex; hos IPTV-leverandøren bare navnene).

## v0.1.35

- Plex Home: byttet til en annen bruker ga «Plex svarte HTTP 404» (plex.tv vil ha brukerens uuid i adressen, ikke
  nummeret). Rettet.

## v0.1.34

- Plex Home: «Hvem ser på?» øverst i sidemenyen i Plex-fanen (på iPhone den første knappen på raden) når kontoen har
  flere brukere. Velg en bruker (med PIN for dem som har det), så får «Fortsett å se», sett/ikke sett og bibliotekene
  den brukerens. Valget huskes på hver enhet for seg.

## v0.1.33

- Radene på Hjem i Plex-fanen følger rekkefølgen på bibliotekene også når Plex ikke sier hvilket bibliotek det som står
  i raden, kommer fra (da hører raden til det første biblioteket med serier eller filmer). I 0.1.32 havnet en slik rad
  til slutt.

## v0.1.32

- Plex-fanen: hold inne på et bibliotek for å flytte det opp eller ned (på iPhone til venstre eller høyre) eller skjule
  det. «Velg biblioteker» står ikke lenger i sidemenyen og raden; de skjulte bibliotekene vises igjen under Plex i
  innstillingene (på iPhone Konto, Plex), «Biblioteker».
- Rekkefølgen du velger, gjelder også radene på Hjem (som i Plex), og den deles mellom Apple TV, iPhone og iPad.

## v0.1.31

- Plex har fått sin egen fane, Plex, etter Filmer og Serier i fanelinja, og Filmer og Serier viser alltid det som
  kommer fra IPTV-leverandøren. Valget «Filmer og serier fra» under Plex i innstillingene er tatt bort.
- Hjem i Plex-fanen samler filmene og seriene, som Hjem i Plex: «Fortsett å se» (sist sett først), favorittene og
  radene fra Plex med filmer og serier sammen.
- Bibliotekene står i sidemenyen på Apple TV og iPad (med «Søk» øverst på Apple TV og «Velg biblioteker» nederst),
  og som knapper på en rad øverst på iPhone. Søket i Plex-fanen finner både filmer og serier.
- Valget av sjanger over plakatene i Plex er tatt bort; rekkefølgen står igjen. På Apple TV står valgene i menyen for
  rekkefølge rett i menyen, og ned fra menyen går til plakatene også når det bare er noen få.

## v0.1.30

- Pause og spol tilbake i direktesending (som i Fyrlys for Windows): Fyrlys tar vare på den siste halvtimen av
  kanalen du ser på, så du kan pause og spole tilbake med Apples vanlige kontroller, og «direkte» tar deg tilbake.
  Kan slås av under «Direktesending» i innstillingene (på iPhone under Konto, Egne strømmer) hvis en kanal ikke vil
  spille. Kanaler som ikke kan tas vare på (lyden for seg, ikke HLS), spilles som før.
- Bildeformat per kanal: «Original», «Fyll skjermen», «Strekk», 16:9 og 4:3 (for kanaler som sender feil format). I
  kontrollene på Apple TV, og under «Mer» (…) i spilleren på iPhone og iPad. Huskes for hver kanal.
- Strøminfo: oppløsningen, kodekene, bilder i sekundet, bitraten og tapte bilder. På Apple TV ved siden av «Kanaler»
  når du sveiper ned i spilleren, på iPhone og iPad under «Mer».
- Det siste merket på siden for en film (for eksempel «★ 6,9») kunne havne på en egen linje oppå teksten under.
- Apple TV: opp fra plakatene går til valget av rekkefølge og sjanger, uansett hvilken plakat du står på.

## v0.1.29

- Multiview: opptil fire kanaler samtidig (som i Fyrlys for Windows), én tilkobling per bilde. Med to innlogginger
  (eller et abonnement med flere tilkoblinger) står «Multiview» i hurtigmenyen på kanalkortene (hold inne) og i
  spilleren. Lyden kommer fra det valgte bildet: på Apple TV det som har fokus, på iPhone og iPad det du trykker på.
  Trykk (dobbelttrykk på iPhone og iPad) for stort bilde, hold inne for å bytte kanal, og Menu eller krysset lukker.
  Et bilde som stopper, startes igjen av seg selv.

## v0.1.28

- Logg inn med en M3U-lenke (som i Fyrlys for Windows): velg «M3U-lenke» på innloggingssiden. Kanalene kommer i
  gruppene fra lista (kanaler uten gruppe under «Uten kategori»), og filmer og episoder i lista hoppes over.
- TV-guiden for en M3U-liste kommer fra XMLTV: lenken som står i lista, eller en du oppgir selv («EPG-lenke», også
  .xml.gz). Den hentes når den trengs og så hver sjette time.
- Er M3U-lenken en Xtream-lenke (get.php med brukernavn og passord), logges du inn med Xtream Codes, og da får du også
  filmer, serier og TV-arkivet.
- En M3U-liste har ikke filmer og serier, så de fanene vises ikke (med Plex kommer de derfra). En .ts-strøm fra en
  Xtream-server i lista prøves som HLS først, siden det er det Apples avspiller kan spille.

## v0.1.27

- Innloggingene kan få egne navn («Gi nytt navn»: «Hjemme», «Sport»). Under Innstillinger på Apple TV og iPad, og
  under Konto på iPhone; hold inne på en annen innlogging for å gi den et navn. Tomt gir «bruker på server» igjen.
- Feilrapport (Innstillinger, eller Konto på iPhone): versjonen, enheten, innstillingene og det siste appen har gjort,
  uten passord, brukernavn, adresser og navnet på leverandøren. «Kopier» og «Del» på iPhone og iPad; på Apple TV vises
  den på skjermen, og «Send til iPhone» legger den i iCloud, så den kan deles derfra.

## v0.1.26

- Serier: når en episode er ferdig, begynner den neste av seg selv («Neste: S1 E3 · …»), også i neste sesong. I
  spilleren er det knapper for forrige og neste episode (på Apple TV under streken: trykk ned).
- Plex: «Hopp over introen» og «Hopp over rulleteksten» der Plex har merket dem. I rulleteksten til slutt står
  «Neste episode» i stedet.
- Plex: undertekstfiler som ligger ved siden av filmen eller episoden (for eksempel en .no.srt), kan velges i
  spilleren, og den norske vises av seg selv når fila ikke har norske undertekster inni seg.
- «Merk som sett» og «Merk som ikke sett» på siden for en film eller serie (på iPhone og iPad i menyen oppe til høyre),
  og på hver episode (hold inne). Med Plex merkes det på serveren, så det stemmer i de andre Plex-appene.
- Plex: «Mer som dette» nederst på siden for en film eller serie.
- Plex: stopper ruteren adressene som slutter på plex.direct (de peker inn i hjemmenettet), kobles det til serveren
  rett på hjemmenettet i stedet.
- Plex: biblioteker kan skjules («Velg biblioteker» nederst i sidemenyen, i menyen på iPhone og under Plex i
  innstillingene). Det som er skjult, er borte fra sidemenyen, Hjem, «Fortsett å se» og søket, på alle enhetene dine.
- Plex: overskriftene Plex lager selv, bes om på norsk (når serveren har dem på norsk).
- Spilles en film med Apples egen avspiller, lukkes spilleren når filmen er ferdig (som med VLC).
- Filmer og serier hos IPTV-leverandøren: «Nylig lagt til» på Hjem, «Alle filmer» og «Alle serier», og rekkefølgen i
  kategoriene kan velges («Leverandørens rekkefølge», «Nyeste først», «A–Å»).
- Plex: bibliotekene har sjanger og rekkefølge («Nylig lagt til», «A–Å», «Nyeste utgivelser», «Best vurdert», «Sist
  sett»), og store bibliotek hentes 100 om gangen.
- Merker: «[PRE]» og lignende i navnet blir et merke på plakaten, og «[2026]» blir året (navnet står uten dem). Siden
  for en film viser kvaliteten (4K, HDR, H.265, 5.1, Dolby …), aldersgrensen og landet når leverandøren eller Plex sier
  det, og antall sesonger og episoder for en serie.
- «Mer fra <kategori>» nederst på siden for en film eller serie fra leverandøren.
- Episodene heter bare det de heter, uten serien og «S01E03» foran.
- Søk i filmer og serier på Apple TV (øverst i sidemenyen).

## v0.1.25

- Apple TV: fanelinja øverst kommer helt fram igjen når du går tilbake til den øverste raden. Før ble lista stående
  litt nede, så fanelinja sto halvveis ute over kanten av skjermen. Det gjelder TV, Filmer og Serier; ellers ser
  TV-siden ut som før.

## v0.1.24

- Filmer og Serier har fått en ny «Hjem» øverst, i stilen fra IPTV-appene:
  - «Fortsett å se» med store bredbilder, hvor langt du har kommet (streken nederst) og hvilken episode du er på
    («S1 E3»). Trykk på en episode, så spilles den der du slapp; hold inne for serien.
  - «Favoritter»: stjernen på siden for en film eller serie (oppe til høyre på iPhone og iPad), eller hold inne på en
    plakat. Favorittene deles mellom iPhone, iPad og Apple TV med iCloud.
  - Under det radene fra Plex (med «Se alle» når det er flere), eller kategoriene hos IPTV-leverandøren som rader med
    «Se alle».
- Søk i filmer og serier på iPhone og iPad (feltet under menyen øverst).
- På iPhone og iPad står tittelen under plakatene, og plakatene i radene er større.
- Feilmeldingen i spilleren sier ikke lenger «Kanalen kunne ikke spilles» to ganger.
- iPhone og iPad: krysset på «Koble fra Plex» er rødt som teksten.

## v0.1.23

En gjennomgang av hele appen: feil som er rettet, og ting som tåler mer.

- TV: står bildet fast uten at det kommer noen feil (leverandøren slutter bare å sende), åpnes kanalen på nytt etter
  25 sekunder; før sto det fast til du byttet kanal. Nye forsøk kommer etter 2, 5 og 10 sekunder, og feilmeldingen
  vises med en gang, med forklaringen etter (alle tilkoblingene i bruk, eller hva serveren svarte).
- NRK direkte og egne strømmer: virker ikke strømmen (nede, eller stengt der du er), spilles kanalen fra
  leverandøren i stedet.
- Kanalbytte (opp/ned på Apple TV og kanallista i spilleren): kanalen du går fra, stoppes med en gang, og trykker du
  flere ganger på rad, åpnes bare den siste. Med én tilkobling hos leverandøren ga rask blaing ellers «alle
  tilkoblingene i bruk». Velger du kanalen som allerede spilles, begynner den ikke på nytt.
- Programmet i spilleren byttes når et nytt program begynner (før sto programmet fra da kanalen ble åpnet).
  Programinfoen på kortene og i guiden hentes på nytt når den er gammel, når den feilet, og når appen kommer fram
  igjen.
- Filmer og serier: brytes forbindelsen midt i, fortsetter filmen der den slapp (to ganger), så kommer «Prøv igjen».
  Før lukket VLC-spilleren seg som om filmen var sett ferdig, og hvor langt du hadde kommet, kunne bli skrevet over.
- VLC tar pause når du går ut av appen eller låser skjermen, i stedet for å spille lyden videre uten bilde.
- iPhone og iPad: fullskjermknappen i spilleren stoppet avspillingen; nå spilles det videre.
- Plex: når appen kommer fram igjen, brukes adressen som svarer nå (hjemme eller ute), så Filmer og Serier virker
  også etter at du har dratt hjemmefra. «Pause» og «stoppet» kommer fram til Plex i riktig rekkefølge, så økta ikke
  blir hengende i Plex og Tautulli. En film du har sett ferdig og ser på nytt, fortsetter der du er. «Spill av»
  venter til siden er hentet. Fant ikke appen serveren, eller må du velge en, står det i fanene i stedet for at de
  laster i det uendelige.
- Serier: «Fortsett» velger ikke en gammel, avbrutt episode når du har sett nyere ferdig, og spesialene (sesong 0)
  står til slutt.
- Lengden på filmer og episoder står som «1 t 32 min».
- Kanallista: sender leverandøren en tom liste, står lista fra sist. Lista hentes på nytt når appen kommer fram
  etter noen timer (eventkanalene har kampene i navnet).
- Innlogging: mellomrom i serveradressen og «+» i brukernavnet eller passordet virker, og avviser leverandøren
  innloggingen, står det.
- Kanaler med kvalitet eller land foran navnet («4K | Kinokanalen») får riktig navn og programinfo.
- En egen strøm uten land gjelder den norske kanalen («TV 2 = …» er ikke «TV 2 HD DK»).
- Bytter du innlogging, begynner TV-siden på nytt, og etter utlogging viser ikke Top Shelf favorittene lenger.
- Apple TV: «Logg ut», «Fjern alle egne strømmer» og «Koble fra Plex» var vanskelige å lese når de var valgt (rød
  tekst på rødt); nå er teksten rød. Guiden viser hele den siste halvtimen, og kampen på eventkanalene.
- iPhone: TV-guiden åpner på det som går nå, og «Til nå» ruller dit også når du bare har rullet litt. «Se kanalen» i
  programinfoen virker hver gang. Liggende står flere fliser og kort i bredden, og Konto-menyen kan rulles. Sveip
  tilbake begynner ikke midt i en overgang.
- iPad: TV, Søk, Filmer og Serier har bakgrunnen til Fyrlys (var svart eller hvit).
- Logoer som ikke kom fordi nettet var borte, prøves igjen etter et halvt minutt (før etter ti).

## v0.1.22

- iPhone: filmer og serier spilles igjen. På de store iPhonene (Pro Max, Plus og Air) byttet hele appen til
  iPad-oppsettet når telefonen la seg ned, så filmen ble lukket med en gang den snudde seg, og telefonen reiste seg
  igjen. Nå beholder iPhonen sitt eget oppsett også på tvers, både når filmen legger seg ned av seg selv og når du
  snur telefonen.
- Filmer og Serier: hentingen av kategoriene (og «Fortsett å se» og radene fra Plex) fortsetter selv om fanen tegnes
  på nytt imens, i stedet for å bli stående tom eller med «Får ikke kontakt».

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

# Ændringer

## iPhone-app 0.7.0 (2026-11-09)

- **ASCII-opstart**: opstartsskærmen er nu en ASCII-animation. Ikonet bygges op af tegn: firkanten fyldes ud fra midten, V'et afkodes langs stregen, plusset popper ind, og ringe af tegn bølger ud mens skemaet hentes. Status skrives som i en terminal med blinkende markør. Følger det valgte app-ikon og mørk tilstand, og står stille hvis Reducer bevægelse er slået til.

## iPhone-app 0.6.0 (2026-11-09)

- **Ny opstartsskærm**: ikonet tegner sig selv, plusset popper ind, og en blød glorie pulserer mens skemaet hentes. Derefter zoomer appen ind med alt klar, i stedet for grå pladsholdere.
- **Vælg app-ikon** under Indstillinger: Viggo, Midnat, Solnedgang, Mint, Lilla, Lys, Neon og Guld. Opstartsskærmen følger det ikon du har valgt.

## iPhone-app 0.5.0 (2026-11-09)

- **Beskeder som iMessage**: fastgør samtaler øverst med et langt tryk eller ved at swipe, korte tider ("2 t", "I går"), beskeder samlet per afsender med tidsstempel, og en svarlinje hvor send-knappen først dukker op når du skriver.
- **Opslagstavlen i appen**: tryk på et opslag for at læse hele teksten med billeder og afsender, i stedet for at blive sendt videre til Viggo. Billeder kan zoomes.
- **I morgen kan foldes ud**: tryk på I morgen-kortet for at se hele morgendagens skema.
- **Uge viser hele dagen**: aftensmad, stilletime, fællessamling, på værelse og godnat, ligesom på Viggo.
- **Nyt login**: kortet sidder nederst på skærmen, tastaturet lukker af sig selv, og telefonen vibrerer ved hvert trin og når du er logget ind.
- Haptisk feedback og små animationer rundt omkring: faner, dagvælger, lektier, lektionsvinduet og beskeder.

## 1.6.1 og iPhone-app 0.4.1 (2026-11-09)

- **Farve per fag overalt**: uge-oversigten, panelet, Nu-kortet og lektionsvinduet bruger nu samme faste farve per fag som iPhone-appen, i stedet for at alle timer er blå. Egne farver vinder stadig.
- Rød nu-linje i uge-oversigten flytter sig hvert minut, og i dag åbner ved det nuværende klokkeslæt i stedet for kl. 8.
- iPhone: dagvælgeren i Uge glider med til den valgte dag, en prik viser i dag, og skemaet glider ind fra den side du skifter til.
- iPhone: I dag viser grå pladsholdere mens skemaet hentes, i stedet for "Fri resten af dagen" og nuller.

## 1.6.0 (2026-11-09)

- **Beskeder på Mac**: et Beskeder-vindue som Mail, med indbakke og søgning til venstre og tråden som chat til højre. Svar direkte (⌘↩ sender), vælg Svar alle eller kun afsender i gruppebeskeder, og skriv nye beskeder med søgning på elever, lærere og grupper.
- Ny knap i panelet med antal ulæste, og beskeder i panelet åbner nu i vinduet i stedet for på Viggo.

## iPhone-app 0.4.0 (2026-11-09)

- **Lektie-widget** til hjemmeskærmen (lille, mellem og stor). Tryk på cirklen for at markere en lektie som færdig på Viggo, direkte fra widgetten.

## iPhone-app 0.3.0 (2026-11-09)

- **Beskeder i appen**: indbakke med søgning og ulæst-tæller, tråde som chat, svar alle eller kun afsender, og nye beskeder med søgning på navn og gruppe.
- Beskeder på I dag åbner nu i appen i stedet for på Viggo.

## iPhone-app 0.2.0 (2026-11-09)

- **Ny I dag-skærm** med stort Nu-kort, tal for dagen, farve per fag, mad i dag og fri sammen med venner.
- **Siri og Genveje**: spørg hvad du har nu, hvornår du har fri, om lektier og om i morgen.
- **Kontrolcenter-knap** der viser hvad du har nu.
- **Stor widget** med hele dagen og lektier.

## iPhone-app 0.1.0 (2026-11-09)

- **Ny iPhone-app** med samme kode som Mac-appen: I dag, Uge, Venner og Indstillinger.
- **Widget** til hjemmeskærmen og låseskærmen med det du har nu, nedtælling og hvad der kommer bagefter.
- **Notifikationer**: påmindelse før hver time, morgen- og aften-brief og fødselsdage lægges klar en uge frem. Flyttede timer, nye lektier, beskeder og opslag kommer fra en baggrundsopdatering.
- **Live Activity** i skoletiden på låseskærmen og i Dynamic Island.
- Installeres med `iOS/install.sh` (se README). Med en gratis Apple-konto skal den installeres igen hver 7. dag.

## 1.5.1 (2026-11-09)

- **Dagens mad**: retten fra køkkenets madplan på opslagstavlen ("Madplan uge 45") står nu under Middag i panelet, og aftenens mad (fx kold buffet) under Aftensmad. Kan slås fra under Indstillinger › Panel.
- **Genvejstasten virker nu**: ⌥V åbner og lukker panelet. Menubar-punktet og panelet er nu Viggo+'s egne, så appen selv kan åbne dem. Panelet lukker når du klikker udenfor, trykker Esc eller skifter app.
- Når lærerens info eller dagens mad folder ud, vokser panelet nu blødt med, og teksten toner ind når der er plads, i stedet for at ligge oven i rækkerne under og hoppe i størrelse.
- Når du åbner Indstillinger, Detaljer eller uge-overblikket fra panelet, lukker panelet, og vinduet åbner lige ved siden af hvor panelet sad, i stedet for midt på skærmen oven i det.

## 1.5.0 (2026-11-09)

- **Middag og værelsestjek mellem timerne**: middagen og det der kommer lige efter (Tjek af værelser, Hovedrengøring af værelser, Formiddagspause) står nu i panelet mellem timerne og i menubaren, ligesom på Viggo. Kan slås fra under Indstillinger › Panel.
- **Pauser mellem timerne**: pauserne mellem klassens timer står i panelet og uge-overblikket (ikke ved valgfag og linjefag). Kan slås fra under Indstillinger › Panel. Under Indstillinger › Menubar kan du også få pausen vist i menubaren, fx "Pause → 09:55".
- **Uge-overblikket** viser også middag og pauser (grå) og dine egne punkter (grønne).
- **Egne punkter**: tilføj frokost, træning, lektier og andet under Indstillinger › Egne punkter, med tidspunkt og hvilke dage. De står i panelet med en grøn streg og i menubaren, fx "Frokost 12:00".
- **Læs lærerens info direkte i panelet**: tryk på en time med info, så folder den ud med hele beskeden og links, i stedet for at åbne et nyt vindue. "Detaljer" åbner stadig vinduet med lærere og hold.
- **Mere kompakt panel**: dig og dine venner sidder nu som små billeder oppe i toppen ved siden af navnet, Nu-kortet er strammet op, og aftenens faste punkter står lidt mindre, så timerne træder frem. Panelet fylder ca. en sjettedel mindre.
- **Små animationer**: lektier hopper når du krydser af, minutterne ruller på Nu-kortet, ringen glider hen til den ven du vælger, og dagen tones ind. Synk-pilen drejer mens den henter, og knapperne giver lidt efter når du trykker.
- I indstillingerne glider markeringen i siden med, og siderne tones ind.
- **Login-kort**: når Viggo+ logger dig eller en ven ind, viser et kort hvor langt login er nået (Viggo, UNI-Login, SkoleIT), med en lås der bliver til et grønt skjold når det lykkes.
- Rettet: profilen i toppen af indstillingerne kunne blive blank.
- Rettet: automatisk login kunne fejle med "UNI-Login-knappen findes ikke", hvis det blev kørt to gange lige efter hinanden.

## 1.4.0 (2026-11-08)

- **Automatisk login for venner**: tilføj en ven med vennens SkoleIT-login under Indstillinger › Venner, eller tryk på nøglen ved en ven du allerede har. Når vennens session udløber, logger Viggo+ selv vennen ind igen i et privat vindue, som aldrig ser din egen session.
- Koderne gemmes nu i en fil på din Mac, som kun din bruger kan læse, i stedet for nøgleringen. Så spørger macOS ikke længere efter nøglering-koden. Har du gemt et login i 1.3.0, skal du skrive det igen én gang.
- En vens kode slettes, når vennen fjernes.
- Enklere Konto- og Venner-side: login-felterne står direkte på siden.

## 1.3.0 (2026-11-08)

- **Automatisk login med SkoleIT**: gem dit SkoleIT-login under Indstillinger › Konto, så logger Viggo+ selv ind i baggrunden når sessionen udløber (UNI-Login, Lokalt login, SkoleIT). Skriver du kun dit brugernavn, fx `otto1161`, sætter Viggo+ selv `@cloud.skoleit.dk` på. Du får kun en notifikation hvis det fejler, fx ved forkert kode.
- Adgangskoden ligger i Mac'ens nøglering. Log ud og Fjern sletter den.

## 1.2.0 (2026-11-08)

- **Info fra læreren**: klik på en time, så ser du hvad I skal, hvad du skal læse eller have med, og lærerens links (videoer, Drev-filer). Timer med info har et lille ikon.
- **Nu-kortet** viser starten af lærerens info til den time du har nu eller skal have.
- Info og links kan også ses fra uge-overblikket.

## 1.1.2 (2026-11-08)

- **Weekenden vises altid** i uge-overblikket: lørdag og søndag står med, også når der ikke er noget på dem.

## 1.1.1 (2026-11-06)

- **Uge-overblikket er et rigtigt skema**: timerne står efter klokken, og hver time er så høj som den varer, ligesom på Viggo. Timer der overlapper står ved siden af hinanden, og en rød streg viser hvad klokken er.
- **Lange navne kan læses**: begivenheder med lange navne bliver ikke længere skåret af i panelet, men fortsætter på næste linje.

## 1.1.0 (2026-11-06)

- **Uge-overblik** med hele ugens timer i kolonner, også for dine venner. Åbnes fra kalender-ikonet i panelet.
- **Venner nu** i panelet: hvem har fri, og hvem har time.
- **Fødselsdage** i panelet og som notifikation om morgenen.
- **Opslagstavlen**: notifikation om nye opslag, og opslagene kan vises i panelet.
- **Egne navne og farver** til timer under Indstillinger › Timer.
- **Genvejstast** der åbner panelet (⌥ V, kan ændres).
- **Opdaterer sig selv**: en lille besked når der er en ny version, og ét klik opdaterer appen.
- Log ud rydder nu hele login-kæden, så den næste der logger ind kan være en anden.

## 1.0.0 (2026-11-06)

Første udgivelse.

- Menubar-app til Viggo. Menubaren viser den time du har nu eller den næste, og efter skoletid hverdagen (aftensmad, stilletime, godnat).
- Panel med et "Nu"-kort, resten af dagen som én tidslinje, i morgen, lektier, beskeder og aftenvagt. Hver sektion kan slås til og fra, og der er stor tekst.
- Log ind på Viggos egen side (UNI-Login, SkoleIT eller adgangskode). Ingen adgangskoder bliver gemt. Sessionen holdes i live, og når den udløber, får du én notifikation og logger ind igen med ét klik.
- Venner: en ven logger ind på sin egen konto i et privat vindue, og du ser vennens dag i samme layout, plus hvornår I begge har fri.
- Import til Apple Kalender i separate kalendere (skema, lektier, begivenheder, hverdag), som holdes opdateret og kan fjernes igen.
- Notifikationer om flyttede eller aflyste timer, nye lektier og nye beskeder, og en brief morgen og aften.
- Sæt lektier som færdige fra panelet.
- Ulæste beskeder og spørgeskemaer vises i menubaren.
- Fokus i timerne via to genveje, hvis du vil.
- Start når Mac'en starter.

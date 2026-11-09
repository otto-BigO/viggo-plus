<p align="center">
  <img src="docs/banner.png" alt="Viggo+" width="800">
</p>

<h4 align="center">En menubar-app til Viggo på macOS. Dit skema, dine lektier og beskeder, uden at åbne hjemmesiden.</h4>

<p align="center">
  <img src="docs/screens/panel.png" alt="Panelet i menubaren" width="320">
  &nbsp;&nbsp;
  <img src="docs/screens/panel-friend.png" alt="En vens dag" width="320">
</p>

## Info fra læreren

Klik på en time i panelet eller uge-overblikket, så ser du hvad læreren har skrevet til timen: hvad I skal, hvad du skal læse eller have med, og links til videoer og filer.

<p align="center">
  <img src="docs/screens/lesson.png" alt="Info fra læreren" width="420">
</p>

## Uge-overblik

<p align="center">
  <img src="docs/screens/week.png" alt="Uge-overblik" width="800">
</p>

## Opdateringer

<p align="center">
  <img src="docs/screens/update.png" alt="Ny version" width="380">
</p>

Viggo+ tjekker GitHub for nye versioner. Er der en, viser den kort hvad der er nyt, med et link til hele listen her på GitHub. **Opdater** henter den nye version og skifter den ind, uden at du skal hente en DMG. Det kan slås fra under Generelt.

## Indstillinger

Klik på en side for at se den.

<details>
<summary><b>Konto</b>: Log ind og ud, og din profil.</summary>
<br>
<p align="center"><img src="docs/screens/settings-konto.png" alt="Konto" width="680"></p>
</details>

<details>
<summary><b>Generelt</b>: Opdateringer, start ved login, genvejstast, tal i menubaren og fokus i timerne.</summary>
<br>
<p align="center"><img src="docs/screens/settings-generelt.png" alt="Generelt" width="680"></p>
</details>

<details>
<summary><b>Panel</b>: Hvad panelet viser, skjul det overståede og stor tekst.</summary>
<br>
<p align="center"><img src="docs/screens/settings-panel.png" alt="Panel" width="680"></p>
</details>

<details>
<summary><b>Menubar</b>: Hverdag efter skoletid, og hvilke punkter der vises.</summary>
<br>
<p align="center"><img src="docs/screens/settings-menubar.png" alt="Menubar" width="680"></p>
</details>

<details>
<summary><b>Timer</b>: Egne navne og farver til dine timer.</summary>
<br>
<p align="center"><img src="docs/screens/settings-timer.png" alt="Timer" width="680"></p>
</details>

<details>
<summary><b>Egne punkter</b>: Frokost, træning, lektier og andet du selv vil have med.</summary>
<br>
<p align="center"><img src="docs/screens/settings-egne-punkter.png" alt="Egne punkter" width="680"></p>
</details>

<details>
<summary><b>Kalender</b>: Import til Apple Kalender og påmindelser.</summary>
<br>
<p align="center"><img src="docs/screens/settings-kalender.png" alt="Kalender" width="680"></p>
</details>

<details>
<summary><b>Notifikationer</b>: Hvad du får besked om, og den daglige brief.</summary>
<br>
<p align="center"><img src="docs/screens/settings-notifikationer.png" alt="Notifikationer" width="680"></p>
</details>

<details>
<summary><b>Venner</b>: Dine venner, fri samtidig og tilføj ven.</summary>
<br>
<p align="center"><img src="docs/screens/settings-venner.png" alt="Venner" width="680"></p>
</details>

<sub>Billederne bruger opdigtede navne og et opdigtet skema. De laves med `./build.sh && build/Viggo+.app/Contents/MacOS/ViggoPlus --render-docs docs/screens`.</sub>

## Hvad den gør

- Menubaren viser hvad du har lige nu, fx `Dansk → 14:15`, og hvad der er næste gang når du har fri. Efter skoletid skifter den til hverdagen: aftensmad, stilletime, godnat.
- Klik på den for panelet: et "Nu"-kort med tid tilbage, resten af dagen som én tidslinje, i morgen, lektier, beskeder og aftenvagt. Hver del kan slås til og fra, og der er en indstilling med stor tekst.
- Klik på en time for at se lærerens info: hvad I skal, hvad du skal have med, og links til videoer og filer.
- Sæt lektier som færdige direkte i panelet. Det bliver gemt i Viggo.
- Ulæste beskeder og spørgeskemaer vises som et tal i menubaren.
- Notifikationer når en time bliver flyttet, aflyst eller skifter lokale, når der kommer nye lektier eller en ny besked, og en brief morgen og aften.
- Import til Apple Kalender som separate kalendere (skema, lektier, begivenheder, hverdag), som holdes opdateret. Én kontakt fjerner dem igen.
- Venner: en ven logger ind på sin egen konto i et privat vindue. Du ser vennens dag i samme layout, og hvornår I begge har fri. Gemmer du vennens SkoleIT-login, logger Viggo+ også vennen ind igen af sig selv.
- Fokus i timerne, hvis du vil, via to genveje.
- Uge-overblik med hele ugens timer i kolonner, også for dine venner.
- "Venner nu": hvem af dine venner der har fri, og hvem der har time.
- Fødselsdage i panelet og som notifikation om morgenen.
- Notifikation når der kommer et nyt opslag på opslagstavlen.
- Giv timer dine egne navne og farver.
- Genvejstast (⌥ V) der åbner panelet.
- Opdaterer sig selv: når der er en ny version, får du en lille besked med det nye, og ét klik opdaterer appen.
- Kan starte når Mac'en starter.

## Login

Du logger ind på Viggos egen login-side inde i appen, med UNI-Login, SkoleIT eller adgangskode, præcis som på hjemmesiden.

**Automatisk login med SkoleIT** (valgfrit, under Indstillinger › Konto): gem dit SkoleIT-brugernavn (fx `otto1161`, `@cloud.skoleit.dk` sættes selv på) og din adgangskode, så logger Viggo+ selv ind når sessionen udløber. Den går de samme trin igennem som du ville: UNI-Login, Lokalt login, SkoleIT, brugernavn og kode, og tilbage til Viggo. Det sker i baggrunden uden et vindue. Adgangskoden ligger kun på din Mac, i en fil som kun din bruger kan læse, og **Log ud** eller **Fjern** sletter den. Det samme gælder dine venners koder under Indstillinger › Venner. Slår du det ikke til, gemmer Viggo+ aldrig din adgangskode, kun sessionen. Den pinger Viggo med få minutters mellemrum, så sessionen holder så længe som muligt. Udløber den alligevel, får du én notifikation og logger ind igen med ét klik.

## Krav

En Mac med Apple Silicon og macOS 14 eller nyere, og en Viggo-konto.

Skolen står i `Sources/Util.swift` (`Config.baseURL`, lige nu `broeruphus.viggo.dk`). Skift den til din egen skoles Viggo-adresse og byg appen.

## Installation

1. Hent DMG-filen under [Releases](https://github.com/otto-BigO/viggo-plus/releases).
2. Åbn den og træk Viggo+ over i Programmer.
3. Appen er ikke notariseret af Apple, så macOS blokerer den første gang. Åbn **Systemindstillinger > Anonymitet og sikkerhed** og klik **Åbn alligevel**.
4. Tillad Kalender og Notifikationer når macOS spørger, og log ind fra indstillingsvinduet.

## Byg selv

Kræver Xcode Command Line Tools (`xcode-select --install`).

- `./install.sh` bygger appen, kopierer den til `/Applications` og starter den.
- `./build.sh` bygger den kun, til `build/Viggo+.app`.
- `./make_dmg.sh` bygger DMG-filen i `dist/`.
- `./release.sh` bygger DMG og zip og udgiver versionen fra `Resources/Info.plist` på GitHub med noterne fra `CHANGELOG.md`. Zip-filen er den som appen selv henter når den opdaterer.
- `swift Tools/makeicon.swift <mappe>.iconset` og `iconutil` laver ikonet igen.

## Godt at vide

- Viggo har ingen offentlig API. Viggo+ læser de samme sider og den samme JSON som hjemmesiden bruger mens du er logget ind, så en ændring hos Viggo kan få den til at gå i stykker.
- Alt bliver på din Mac: sessionen ligger i `~/Library/Application Support/ViggoPlus` (kun læsbar for dig), og kalenderne er din egen Apple Kalender.
- Viggo+ er et personligt projekt og er ikke lavet af eller tilknyttet Viggo eller KOMiT.

## Licens

MIT. Se [LICENSE](LICENSE).

<p align="center">
  <img src="docs/banner.png" alt="Viggo+" width="800">
</p>

<h4 align="center">En menubar-app til Viggo på macOS. Dit skema, dine lektier og beskeder, uden at åbne hjemmesiden.</h4>

<p align="center">
  <img src="docs/screens/panel.png" alt="Panelet i menubaren" width="320">
  &nbsp;&nbsp;
  <img src="docs/screens/panel-friend.png" alt="En vens dag" width="320">
</p>

## Indstillinger

<p align="center">
  <img src="docs/screens/settings-panel.png" alt="Panel" width="420">
  &nbsp;
  <img src="docs/screens/settings-kalender.png" alt="Kalender" width="420">
</p>
<p align="center">
  <img src="docs/screens/settings-venner.png" alt="Venner" width="420">
  &nbsp;
  <img src="docs/screens/settings-generelt.png" alt="Generelt" width="420">
</p>
<p align="center">
  <img src="docs/screens/settings-menubar.png" alt="Menubar" width="420">
  &nbsp;
  <img src="docs/screens/settings-notifikationer.png" alt="Notifikationer" width="420">
</p>

<sub>Billederne bruger opdigtede navne og et opdigtet skema. De laves med `./build.sh && build/Viggo+.app/Contents/MacOS/ViggoPlus --render-docs docs/screens`.</sub>

## Hvad den gør

- Menubaren viser hvad du har lige nu, fx `Dansk → 14:15`, og hvad der er næste gang når du har fri. Efter skoletid skifter den til hverdagen: aftensmad, stilletime, godnat.
- Klik på den for panelet: et "Nu"-kort med tid tilbage, resten af dagen som én tidslinje, i morgen, lektier, beskeder og aftenvagt. Hver del kan slås til og fra, og der er en indstilling med stor tekst.
- Sæt lektier som færdige direkte i panelet. Det bliver gemt i Viggo.
- Ulæste beskeder og spørgeskemaer vises som et tal i menubaren.
- Notifikationer når en time bliver flyttet, aflyst eller skifter lokale, når der kommer nye lektier eller en ny besked, og en brief morgen og aften.
- Import til Apple Kalender som separate kalendere (skema, lektier, begivenheder, hverdag), som holdes opdateret. Én kontakt fjerner dem igen.
- Venner: en ven logger ind på sin egen konto i et privat vindue. Du ser vennens dag i samme layout, og hvornår I begge har fri.
- Fokus i timerne, hvis du vil, via to genveje.
- Kan starte når Mac'en starter.

## Login

Du logger ind på Viggos egen login-side inde i appen, med UNI-Login, SkoleIT eller adgangskode, præcis som på hjemmesiden. Viggo+ ser og gemmer aldrig din adgangskode, kun sessionen. Den pinger Viggo med få minutters mellemrum, så sessionen holder så længe som muligt. Udløber den alligevel, får du én notifikation og logger ind igen med ét klik.

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
- `swift Tools/makeicon.swift <mappe>.iconset` og `iconutil` laver ikonet igen.

## Godt at vide

- Viggo har ingen offentlig API. Viggo+ læser de samme sider og den samme JSON som hjemmesiden bruger mens du er logget ind, så en ændring hos Viggo kan få den til at gå i stykker.
- Alt bliver på din Mac: sessionen ligger i `~/Library/Application Support/ViggoPlus` (kun læsbar for dig), og kalenderne er din egen Apple Kalender.
- Viggo+ er et personligt projekt og er ikke lavet af eller tilknyttet Viggo eller KOMiT.

## Licens

MIT. Se [LICENSE](LICENSE).

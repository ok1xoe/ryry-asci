# RYRY TUI – konzolová verze s ASCII art rozhraním

Tiket: ASCI-1 (YouTrack, projekt ASCI). Stav: **návrh ke schválení**. Autor zadání: OK1XOE.

## Záměr a proč

RYRY je nativní macOS aplikace pro RTTY (SwiftUI). Cílem je **konzolová aplikace**, která se ovládá co nejvíc stejně
jako původní okno, ale celá žije v terminálu a využívá ASCII/Unicode art (waterfall, spektrum, měřiče). Je to
„proof of fun“: má to být zábavné a zároveň plně použitelné u rádia připojeného k témuž Macu.

## Cíle

1. Nový spustitelný cíl `ryry-tui` ve stávajícím Swift balíčku, který **znovu používá stávající jádro** beze změn:
   `Engine`, `RTTYModem`/`MMTTYCore`, `AudioIO`, `Keying`, `RigControl`, `QSOLog`, `MacroEngine`, `Spots`, `DXCC`,
   `AppCore`, `Settings`, `APIServer`, `Localization`.
2. **Věrnost originálu** hlavního okna: horní lišta (TX/RX, Tune, Stop, stav, demodulátor, HAM, profil, frekvence,
   měřič signálu, Baud, Shift, LTRS/FIGS, filtry, přepínače XY / 2. dekodér / AFC / NET / REV / ATC), spektrum,
   waterfall, příjmové okno, volitelný panel 2. dekodéru, vysílací okno, 16 maker (F1–F12, ⇧F1–⇧F4), stavový řádek
   (rychlost závodu, skóre, stav API) a pravý QSO panel (značka, jméno, RST, závodní výměna, DXCC, azimut a vzdálenost,
   předchozí spojení, QTC).
3. Okna jako celoobrazovkové panely nebo překryvy: **Log, Spoty, Band mapa, Skóre, Multiplikátory** (s funkcemi
   originálu: hledání, editace, mazání, import ADIF, export Cabrillo, filtry spotů).
4. **Myš v příjmovém okně** stejně jako v originále: klik na slovo = dosadí ho do QSO podle typu (značka / jméno /
   RST / číslo). Myš navíc na spektru a waterfallu (klik = naladění značky, pravé tlačítko = notch) a na tlačítkách
   maker a lišty.
5. **Jednoduché menu nastavení** v terminálu (audio zařízení, rig a PTT/FSK, vlastní značka a lokátor, kontest a
   předvolba, makra, jazyk). Vše ostatní zůstává v `settings.json`, který čte i GUI aplikace.
6. Nastavení, log a data jsou **kompatibilní s GUI RYRY** (stejné soubory a formáty), aby šlo oba front-endy střídat.

## Non-cíle

- Žádné vzdálené ovládání zvuku (SSH jen jako způsob, jak spustit TUI na Macu s rádiem; zvuk vždy lokálně).
- Žádný Linux/Windows (CoreAudio backend zůstává; přenositelnost je až další etapa).
- Žádná plná kopie všech stránek `SettingsView` (≈1 200 řádků).
- Žádná změna modemu, protokolů ani API.

## Anti-cíle (selhání, i kdyby to technicky fungovalo)

- Zpoždění nebo ztráty zvuku/dekódování kvůli vykreslování (UI nesmí blokovat engine; kreslení v samostatné úloze,
  omezená frekvence překreslení).
- Rozbitý terminál po pádu nebo Ctrl-C (musí se vždy obnovit režim terminálu, kurzor, myš, alternativní obrazovka).
- Zkopírované jádro nebo kopie logiky z `AppModel` (jádro se sdílí, nepřepisuje).
- Ovládání, které se odchyluje od originálu bez důvodu.

## Rozhodnutí uživatele (v konverzaci)

- Aplikace je **konzolová**, používá se na Macu s připojeným rádiem; SSH ovládání není pro v1 potřeba.
- Nastavení v jednoduchém menu; ostatní co nejvěrněji; podpora myši v příjmovém okně.

## Moje volby (označeno jako návrh, uživatel je může změnit)

- **Jazyk a stack:** Swift, protože jádro už v něm je. Nový cíl `ryry-tui` + knihovna `TUIKit` (vlastní tenká vrstva
  nad ANSI/termios, bez externí závislosti). UI logika oddělená od vykreslování, aby šla testovat.
- **Znovupoužití stavu:** UI se napojí na existující `AppModel`/`AppController` z `AppUI`. Pokud `AppModel` brání
  použití bez GUI (import SwiftUI/AppKit), buduje se tenká společná část; rozhodne se v plánu po průzkumu.
- **Vykreslování:** pevná mřížka buněk (znak + barva popředí/pozadí), diferenční překreslení, raw režim, alternativní
  obrazovka, SGR myš (1006), bracketed paste. Barvy true color s degradací na 256.
- **Waterfall/spektrum:** půlblok `▀`/`▄` = 2 svislé pixely na buňku, barevná paleta jako v originále; záložní
  varianta ASCII rampa ` .:-=+*#%@` pro terminály bez barev.
- **Rozložení:** hlavní sloupec vlevo, QSO panel vpravo (jako HSplitView originálu); minimální velikost návrhem
  100×32, při menším okně hláška. Při změně velikosti (SIGWINCH) se přepočítá layout.
- **Fokus:** `Tab`/`⇧Tab` cyklí mezi vysílacím oknem, příjmovým oknem a poli QSO panelu.
- **Klávesy (návrh, finální mapování v plánu):** F1–F12 makra; ⇧F1–⇧F4 podle toho, co terminál posílá, záložně
  Alt+1–4; ⌘ → Ctrl (Ctrl+T TX/RX, Ctrl+L zalogovat); Esc = okamžitě RX (rozlišení od escape sekvencí časovým
  limitem); okna Alt+L/S/B/C/M (Log/Spoty/Band mapa/Skóre/Multiplikátory) a Ctrl+O = nabídka oken; Ctrl+P nastavení; Ctrl+G nápověda; Ctrl+Q konec (Ctrl+, a Ctrl+číslice terminál nedoručí).
  Klávesové zkratky z `settings.json` (`KeyBinding`) se mapují, kde to jde; nenamapovatelné ⌘ kombinace mají náhradu.
- **Testy:** čistý parser vstupu (bajty → události), čistý renderer (stav → buffer buněk) se snapshot testy,
  mapování kláves, hit-testing myši v příjmovém okně; jádro má 830 stávajících testů, které se nesmí rozbít.

## Doplněno po kontrole staviteli (moje volby)

- **TUI a GUI najednou:** nepodporuje se. `ryry-tui` při startu zjistí, že zvuková karta, port rigu nebo port API je
  obsazen (např. běží GUI), a srozumitelně skončí s hláškou. Nastavení a log se zapisují atomicky a po jednom
  front-endu. API server v TUI běží ve výchozím stavu stejně jako v `rtty-tool live` (jde vypnout `--no-api`).
- **Nastavení:** menu zapisuje zpět do `settings.json` a **zachová pole, která nezná** (round-trip přes `Tolerant`),
  což pokrývá test. Makra: ve v1 výběr sady a úprava názvu a textu jednoho makra jednořádkovým editorem; barvy a
  opakování se upravují v souboru.
- **Terminály (rozhodnutí uživatele: aplikace nesmí záviset na konkrétním terminálu):** žádný terminál není
  referenční. Aplikace se přizpůsobí schopnostem: barvy true color → 256 → 16 → monochromaticky (ASCII rampa),
  Unicode půlbloky → čisté ASCII, myš je vždy volitelná (vše jde i klávesnicí), každá akce má klávesu, která
  funguje i tam, kde ⇧F-klávesy a modifikátory nedorazí (Alt+1–4 nebo prefix Ctrl+A pro ⇧F1–⇧F4). Schopnosti se
  zjistí z `COLORTERM`/`TERM`/locale a dotazem na terminál, jdou ručně přepsat parametry. Testuje se na
  Terminal.app, iTerm2 a Ghostty (a přes SSH); základem je, že fungují všechny stejně, jen s různou ozdobou.
- **Věrnost při 100×32:** vejde se hlavní sloupec, QSO panel a makra ve 2 řádcích; panel 2. dekodéru se při malé
  výšce skryje. Na větší obrazovce se přidá výška spektra a waterfallu. Okna Log/Spoty/Band mapa/Skóre/Multiplikátory
  mají ve v1 funkční parity s GUI s výjimkou souborových dialogů: import ADIF a export Cabrillo se zadávají cestou
  v textovém poli s doplňováním.
- **Použití `AppModel`:** ve v1 se bere `AppUI` tak, jak je (`AppModel` importuje jen Foundation a AVFoundation,
  AppKit mají jen `SystemAlertSink` a pár dalších souborů). Hlavní smyčka přes `RunLoop`/`dispatchMain`. Oprávnění
  k mikrofonu se u příkazového nástroje přiřadí terminálu, což je akceptováno. Případný refaktoring jen pokud
  průzkum ukáže skutečnou překážku.
- **Distribuce:** ve v1 jen cíl v balíčku, sekce v README a stránka v manuálu; bez podpisu a bez App Storu. Testy
  musí být deterministické (CI běží sériově na 3 jádrech), tzn. bez závislosti na čase a skutečném terminálu.

## Co je na staviteli

- Přesná velikost a pořadí panelů, paleta waterfallu, přesné náhradní klávesy, způsob propojení s `AppModel`.
- Rozdělení do etap (doporučení: 1. kostra + hlavní okno bez myši, 2. makra/QSO/log, 3. myš, 4. okna, 5. nastavení).

## Otevřené / ke kontrole uživatelem

- Souhlas s mapováním ⌘ → Ctrl a s náhradními klávesami pro ⇧F1–⇧F4.
- Minimální velikost terminálu (100×32).

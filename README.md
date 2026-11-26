# FR Standing Start

Start z miejsca po okrążeniu formującym dla serwerów Assetto Corsa (skrypt online CSP).
*Standing start after a formation lap for Assetto Corsa servers (CSP online script) – English summary at the bottom.*

Kierowcy nie instalują nic. Serwer podaje skrypt każdemu, kto wchodzi na serwer. Potrzebny jest tylko Custom Shaders Patch.

## Jak to działa

1. **Start z gry rozpoczyna okrążenie formujące.** Skrypt zapisuje pole startowe każdego auta, czyli miejsce, w którym stało na starcie (kolejność z kwalifikacji).
2. **Okrążenie formujące.** Obowiązuje limit prędkości (domyślnie 80 km/h). Na ekranie widać numer Twojego pola.
3. **Dojazd do pola.** Od 300 m przed polem skrypt odlicza metry. Pole jest narysowane na asfalcie:
   - zielone: stoisz dobrze,
   - żółte: blisko albo trochę za daleko,
   - czerwone: przestrzelone.

   Biała linia pokazuje, gdzie ma być przód auta. Czerwona linia to granica, za którą jest kara.
4. **Światła.** Admin klika „Zapal światła” albo światła zapalają się same, gdy wszyscy stoją (opcja `AUTO_LIGHTS`). Zapala się 5 czerwonych świateł, potem jest losowa przerwa i światła gasną. Każdy komputer liczy światła od chwili, gdy komenda dotarła do serwera (z poprawką na ping), więc u wszystkich gasną jednocześnie.
5. **Falstart i przestrzelenie pola.** Kara jest nakładana w chwili zgaszenia świateł i ogłaszana na czacie. Każdy dostaje też swój czas reakcji.

### Zasady

| Sytuacja | Co się dzieje (domyślnie) |
|---|---|
| Stoisz do 0,5 m przed/za linią pola | OK |
| Za daleko o 0,5–10 m | ostrzeżenie, bez kary |
| Za daleko o ponad 10 m | **drive-through** (3 okrążenia na odbycie) |
| Obok pola (w lewo/prawo) o ponad 0,5 m | komunikat ze strzałką „← w lewo / w prawo →” i żółta strzałka na asfalcie |
| Obok pola o ponad 2 m przy zapaleniu świateł | **drive-through** |
| Cofnięcie po przestrzeleniu do 10 m | można poprawić ustawienie |
| Cofnięcie po przestrzeleniu ponad 10 m | kara zostaje (liczy się najdalszy punkt) |
| Ruch ponad 0,5 m przed zgaszeniem świateł | **falstart → drive-through** |
| Start z alei serwisowej | wyjazd z alei przed zgaszeniem świateł = falstart |
| Wjazd do alei w trakcie formującego | start z alei |
| Jechałeś, gdy zapaliło się pierwsze światło | wpis „spóźniony” na czacie, decyzja admina |
| Dołączenie po starcie | brak pola, start z alei |

Gdy kierowca ma dwie kary (np. przestrzelenie i falstart), dostaje jedną, surowszą. Na czacie są opisane obie.

## Instalacja na serwerze (ACSM)

1. W wyścigu (Custom Race / Championship) w polu **Extra Options** (opcje CSP) dopisz na końcu:

```ini
[SCRIPT_...]
SCRIPT = "https://raw.githubusercontent.com/zepansrpl-creator/fr-standing-start/v0.1.7/fr_standing_start.lua"

[FR_STANDING_START]
LANGUAGE = PL
FORMATION_SPEED_KMH = 80
GRID_TOLERANCE_M = 0.5
GRID_WARNING_M = 10.0
OVERSHOOT_PENALTY = DRIVE_THROUGH
JUMP_START_PENALTY = DRIVE_THROUGH
PENALTY_LAPS = 3
AUTO_LIGHTS = 0
```

   Sekcję `[SCRIPT_...]` wpisz dokładnie tak, z trzema kropkami – CSP sam nada jej numer (np. SCRIPT_3). Adres zawiera numer wersji (`v0.1.7`), więc zmiany w repo nie podmienią skryptu w trakcie wyścigu. Nową wersję włączasz, zmieniając numer w adresie.

2. **Start Rule** ustaw na **„Car is Locked Until Start”**, żeby nikt nie dostał kary gry za ruszenie na okrążenie formujące.
3. **Wymagana wersja CSP:** zostaw swoją (3749) albo co najmniej 0.2.x.
4. **Real Penalty** wyłącz w tym wyścigu albo wyłącz w nim obsługę startu, żeby kary się nie dublowały.
5. **Liczba okrążeń:** okrążenie formujące najpewniej doliczy się do 1. okrążenia. Sprawdzimy to w teście, wtedy wyścig trzeba będzie ustawić na +1 okrążenie.

### Wszystkie ustawienia `[FR_STANDING_START]`

| Klucz | Domyślnie | Opis |
|---|---|---|
| `LANGUAGE` | `PL` | `PL` albo `EN`. Kierowca może przełączyć u siebie. |
| `FORMATION_SPEED_KMH` | `80` | limit na formującym (0 = brak limitu) |
| `APPROACH_ZONE_M` | `300` | od jakiej odległości pokazujemy pole |
| `GRID_TOLERANCE_M` | `0.5` | tolerancja ustawienia |
| `GRID_WARNING_M` | `10.0` | powyżej tego przestrzelenie = kara |
| `LATERAL_TOLERANCE_M` | `0.5` | tyle można stać obok środka pola |
| `LATERAL_PENALTY_M` | `2.0` | stanie dalej obok pola przy zapaleniu świateł = kara |
| `ALLOW_REVERSE` | `0` | `1` = cofnięcie poprawia ustawienie |
| `OVERSHOOT_PENALTY` | `DRIVE_THROUGH` | `DRIVE_THROUGH` / `TELEPORT` / `WARNING` |
| `JUMP_START_PENALTY` | `DRIVE_THROUGH` | jak wyżej |
| `PENALTY_LAPS` | `3` | okrążenia na odbycie drive-through |
| `TELEPORT_SECONDS` | `10` | blokada w boksie przy karze `TELEPORT` |
| `JUMP_START_M` | `0.5` | ruch, od którego liczy się falstart |
| `LIGHTS_COUNT` | `5` | liczba świateł (1–10) |
| `LIGHTS_INTERVAL_MS` | `1000` | odstęp między światłami |
| `LIGHTS_LEAD_MS` | `3000` | czas od kliknięcia do pierwszego światła |
| `HOLD_MIN_MS` / `HOLD_MAX_MS` | `200` / `3000` | losowa przerwa przed zgaszeniem |
| `AUTO_LIGHTS` | `0` | `1` = klient admina sam zapala światła |
| `AUTO_DELAY_S` | `5` | tyle sekund wszyscy muszą stać |
| `AUTO_TIMEOUT_S` | `60` | po tylu sekundach od pierwszego auta na polu światła ruszą i tak |
| `REPORT_REACTION` | `1` | czas reakcji na czacie (każdy widzi tylko swój) |
| `CHAT_PREFIX` | `FRSS>` | początek wpisów na czacie, przyda się później do logu |

## Panel admina

1. Zaloguj się jako admin: wpisz na czacie `/admin hasło_admina` (serwer odpowie „You are now Admin”) albo zaloguj się jako admin w nowej aplikacji czatu CSP.
2. Otwórz nową aplikację czatu CSP, kliknij ikonę dodatków online (żarówka) i wybierz **„FR Standing Start – admin”**.
3. Panel zostaje na ekranie. Masz w nim:
   - **Zapal światła**: działa w trakcie okrążenia formującego,
   - **Przerwij start (dodatkowe formujące)**: gasi światła, wszyscy jadą jeszcze jedno okrążenie, kary za przestrzelenie przepadają,
   - **Pomiń formujące (test)**: wszyscy są traktowani tak, jakby już zrobili formujące. Przydaje się do testów w pojedynkę,
   - **listę aut** z polem, stanem i przesunięciem w metrach oraz przyciskiem **Anuluj karę** (działa przed zgaszeniem świateł).

Po starcie w panelu admina pojawia się **lista czasów reakcji wszystkich kierowców** (od najszybszego; falstarty, start z alei i spóźnieni na końcu) i przycisk **„Kopiuj czasy reakcji (Discord)”** – lista trafia do schowka gotowa do wklejenia (Ctrl+V). Lista zostaje do następnego startu, także po zakończeniu wyścigu.

Komendy na czacie (działają tylko dla admina, nie są widoczne dla innych):

| Komenda | Działanie |
|---|---|
| `!frss swiatla` | zapal światła |
| `!frss przerwij` | przerwij start (dodatkowe formujące) |
| `!frss pomin` | pomiń formujące (test) |
| `!frss reakcje` | skopiuj listę czasów reakcji do schowka |

Każdy kierowca ma w tym samym menu okno **„FR Standing Start – ustawienia”**:
- zmiana języka PL/EN,
- przesuwanie napisów z odległością (suwaki albo przeciągnięcie podglądu myszką) i ich wielkość; zapamiętywane na komputerze kierowcy.

Po karze drive-through kierowca widzi na ekranie, ile okrążeń zostało na jej odbycie; odbycie (przejazd przez aleję **bez zatrzymania**) jest potwierdzane na ekranie i na czacie; pitstop w boksie kary nie odbywa.

## Testy

### Testy automatyczne (bez gry)

```sh
./run_tests.sh
```

Testy sprawdzają:
- logikę: odległość od pola, światła, falstart, kary, ustawienia, teksty PL/EN,
- symulację wyścigu na atrapie API gry: czysty start, przestrzelenie, ostrzeżenie, falstart, anulowanie kary, przerwany start, start z alei, automat świateł, późne wczytanie.

### Test 1 – sam na serwerze

- [ ] Po wejściu na serwer w **Lua Debug** CSP jest nowy „Server Script: SCRIPT_…” z wpisami `FRSS …` (w każdej sesji), czyli skrypt się wczytał.
- [ ] Przed startem stan to `1`. Po starcie z gry faza zmienia się na `2` i pojawia się napis „OKRĄŻENIE FORMUJĄCE”.
- [ ] Jazda powyżej 80 km/h: gaz jest odcinany.
- [ ] Ok. 300 m przed polem pojawia się odliczanie, a na asfalcie widać pole.
- [ ] Zatrzymanie na polu daje „STOP – STOISZ NA POLU” i zielone pole.
- [ ] „Zapal światła” w panelu: 5 świateł, zgaszenie, czas reakcji na czacie.
- [ ] Drugi wyścig: celowe przestrzelenie o ponad 10 m daje drive-through po zgaszeniu świateł.
- [ ] Trzeci wyścig: ruszenie przy zapalonych światłach daje falstart i karę.
- [ ] Skrót do testów: „Pomiń formujące (test)” od razu po starcie z gry, potem „Zapal światła”.

Jeśli coś nie działa, przyślij plik `Dokumenty\Assetto Corsa\logs\custom_shaders_patch.log` (wpisy `[FRSS]`) i zrzut ekranu.

### Test 2 – z 2–3 osobami

- [ ] Światła gasną u wszystkich jednocześnie: porównujemy czasy reakcji na czacie albo nagrania.
- [ ] Każdy widzi swoje właściwe pole (P1, P2, …).
- [ ] Panel admina pokazuje stan wszystkich aut.
- [ ] Kierowca z wyższym pingiem nie dostaje fałszywego falstartu.
- [ ] Kierowca, który dołączył po starcie, ma komunikat „brak pola”.

### Test 3 – sytuacje graniczne

- [ ] Ktoś stoi w boksie w chwili startu, czyli start z alei.
- [ ] Ktoś obraca się na formującym.
- [ ] Ktoś się rozłącza w trakcie.
- [ ] „Przerwij start” przy zapalonych światłach.
- [ ] Liczba okrążeń w wynikach ACSM (czy trzeba +1).
- [ ] Wyścig na czas.

### Test 4 – próbny wyścig ligowy z pełną stawką

## Do sprawdzenia w pierwszych testach

Te rzeczy działają w testach na atrapie, ale ich zachowanie w grze trzeba potwierdzić:
- moment startu z gry (`timeToSessionStart` / `currentSessionTime`),
- dostarczanie komend admina do wszystkich aut,
- wysyłanie wpisów na czat ze skryptu online,
- działanie limitu prędkości przy `LIMIT_LOCK_CONTROLS_TIME = 1` w `[EXTRA_RULES]`.

---

## English summary

FR Standing Start is a CSP online script that adds a standing start after a formation lap. It records each car's grid slot at the game's race start (which begins the formation lap), enforces a speed limit, shows a distance countdown and a marked grid box on the tarmac, penalises overshooting the slot, runs synchronised start lights (admin button or automatic when everyone is stopped) and detects jump starts. Messages are available in Polish and English (`LANGUAGE = EN`, drivers can switch locally). Configure it with the `[FR_STANDING_START]` section shown above.

## Licencja

MIT – patrz plik [LICENSE](LICENSE). Możesz używać i przerabiać, zachowując informację o autorze.

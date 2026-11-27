# Zmiany

## 0.2.4

### Poprawki
- Automat świateł skraca czekanie do 5 s dopiero, gdy wszyscy stoją poprawnie na swoich polach albo w alei. Kto stoi przed polem, obok pola albo trochę za daleko, ma jeszcze czas do końca limitu (60 s) na poprawienie ustawienia.

## 0.2.3

### Poprawki
- Automat świateł nie zapala świateł, dopóki przynajmniej jedno auto nie przejedzie formującego i nie stanie na polu; limit czasu liczy się dopiero od tej chwili.
- Stan „nie ruszył na formujące” dopiero wtedy, gdy inne auta już stoją na polach po formującym (wcześniej kierowcy zwlekający na starcie formującego byli liczeni jako gotowi).
- Komunikat „5s do świateł” bez odliczania.

## 0.2.2

### Nowe funkcje
- Odliczanie „5 s do świateł” dla wszystkich przed zapaleniem pierwszego światła.
- Startujący z boksu, zanim ruszy, widzi: „Możesz ruszyć do okrążenia formującego, ale startujesz do wyścigu z pitlane”.
- Panel admina pokazuje stan automatu świateł (ile aut czeka, za ile sekund światła).

### Poprawki
- Kierowca, który dołączył później i startuje z boksu, dostaje zielone razem z innymi startującymi z boksu (dystans stawki liczony z położenia aut przy zgaszeniu świateł).
- Automat świateł mniej wrażliwy na zakłócenia prędkości aut innych kierowców.

## 0.2.1

### Poprawki
- Automat świateł czeka na auta, które jadą po torze – meldunek „gotowy” liczy się tylko, gdy auto naprawdę stoi na polu albo jest w alei.
- Kierowca dołączający w trakcie formującego dostaje informację o starcie z boksu także bez admina na serwerze (z meldunków innych aut); admin dodatkowo co 10 s przypomina fazę startu.
- Startujący z boksu nie widzą świateł startowych, tylko swoje światło wyjazdu z alei; wyjazd przed zielonym = drive-through (`PIT_EXIT_PENALTY`).
- Zielone dla startujących z boksu, gdy cała stawka przejedzie 500 m od startu (było 300 m).

## 0.2.0

### Nowe funkcje
- Start z boksu: komunikat dla kierowcy, możliwość przejechania formującego z obowiązkiem powrotu do alei przed światłami, własne światło wyjazdu z alei – zielone, gdy cała stawka minie T1 (300 m za polem P1) albo po 30 s.
- Kara stop & go (postój 10 s w swoim boksie, z odliczaniem) dla kierowcy, który przy zapaleniu świateł był ponad 20 m od pola; bliżej – drive-through.
- Kierowca dołączający w trakcie procedury startu dostaje informację, że startuje z boksu.

### Poprawki
- Ramka pola 3 razy cieńsza.
- Numer pola liczony z ustawienia aut na polach, a nie z wyników – auto przeniesione do boksu nie zabiera lidera pola P1.
- Wyjazd z boksu na formujące nie daje już pola na końcu stawki (zastąpione startem z boksu).

## 0.1.9

### Nowe funkcje
- Kierowca, który rusza na okrążenie formujące z boksu, dostaje pole na końcu stawki (oznaczone tak jak inne pola).
- Kara drive-through dla kierowcy, który nie zdążył na swoje pole przed zapaleniem świateł (ustawienie `LATE_PENALTY`).

## 0.1.8

### Poprawki
- Brama nad polem obniżona do 1,5 m.
- Po przerwaniu startu automat świateł nie liczy już starych meldunków „stoję na polu” – światła nie ruszą w trakcie dodatkowego okrążenia formującego.
- Auto przeniesione do boksu w trakcie formującego od razu startuje z alei i nie blokuje świateł.
- Auto, które nie ruszyło na formujące, jest traktowane jako gotowe do startu (komunikat dla kierowcy i stan „nie ruszył” w panelu).

## 0.1.7

### Nowe funkcje
- Lista czasów reakcji wszystkich kierowców w panelu admina, z przyciskiem kopiowania gotowej listy na Discord (także komenda `!frss reakcje`).

## 0.1.6

### Nowe funkcje
- Pole jaśniejsze i świecące; z daleka pulsuje.
- Brama nad przodem pola (słupki 3,2 m i poprzeczka) z numerem pola – widać z daleka, gdzie stanąć.

## 0.1.5

### Nowe funkcje
- Strzałki w komunikatach: ↑ podjedź, ↓ za daleko, ← w lewo / w prawo →.

### Poprawki
- Kara za przestrzelenie pola dopiero od 10 m.
- Tolerancja ustawienia w bok: 0,5 m (było 1 m).
- Drive-through zalicza tylko przejazd przez aleję bez zatrzymania; pitstop w boksie nie odbywa kary.

## 0.1.4

### Poprawki
- Światła startowe zapalają się i gasną u wszystkich w tym samym momencie (wcześniej u niektórych kierowców startowały kilka sekund wcześniej).

## 0.1.3

### Poprawki
- Po cofnięciu z małego przestrzelenia (do 5 m) napis „za daleko” znika, a pole robi się zielone; przestrzelenie ponad 5 m dalej oznacza karę.

## 0.1.2

### Nowe funkcje
- Wyraźniejsze pole na asfalcie: mocniejsze kolory, gruba obwódka, biała linia przodu, słupki i numer pola.
- Wykrywanie stania obok pola (w lewo/prawo): komunikat, strzałka do środka pola, kara powyżej 2 m.
- Informacja o karze drive-through: ile okrążeń zostało, potwierdzenie odbycia albo jego braku.
- Okno ustawień kierowcy: język oraz przesuwanie i wielkość napisów z odległością.

### Poprawki
- Kara za przestrzelenie pola dopiero od 5 m.
- Czas reakcji na czacie widzi tylko jego autor.

## 0.1.1

### Nowe funkcje
- Komendy admina na czacie: `!frss swiatla`, `!frss przerwij`, `!frss pomin`.
- Wpisy FRSS w Lua Debug widoczne w każdej sesji (łatwo sprawdzić, czy skrypt się wczytał).

### Poprawki
- Panel admina pojawia się także po zalogowaniu komendą `/admin`.
- Instrukcja: sekcja skryptu to `[SCRIPT_...]` (poprzednia nazwa nie była wczytywana przez CSP).

## 0.1.0

### Nowe funkcje
- Start z gry rozpoczyna okrążenie formujące, a pola startowe są zapisywane z ustawienia po kwalifikacjach.
- Limit prędkości na okrążeniu formującym.
- Odliczanie metrów do pola i pole narysowane na asfalcie (zielone / żółte / czerwone).
- Kara za przestrzelenie pola, a do 2 m tylko ostrzeżenie.
- Panel admina: zapalanie świateł, przerwanie startu, pominięcie formującego (test), lista aut, anulowanie kary.
- Światła startowe zsynchronizowane czasem sesji, z losową przerwą przed zgaszeniem.
- Wykrywanie falstartu, także przy starcie z alei serwisowej.
- Czasy reakcji i kary ogłaszane na czacie.
- Opcjonalny automat świateł, gdy wszyscy stoją.
- Teksty po polsku i angielsku, z przełącznikiem u kierowcy.

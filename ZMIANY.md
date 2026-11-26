# Zmiany

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

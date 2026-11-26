# Zmiany

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

-- FR Standing Start
-- Start z miejsca po okrążeniu formującym dla serwerów Assetto Corsa (skrypt online CSP).
-- Standing start after a formation lap for Assetto Corsa servers (CSP online script).
--
-- Licencja MIT (c) 2026 Maciej Szczepaniak – github.com/zepansrpl-creator/fr-standing-start
-- Konfiguracja: patrz README.md (sekcja [FR_STANDING_START] w CSP Extra Options serwera).

local VERSION = '0.2.0'

-------------------------------------------------------------------------------
-- 1. Czysta logika (bez API gry) – testowana w tests/test_logic.lua
-------------------------------------------------------------------------------

local L = {}

L.VERSION = VERSION

-- Domyślne ustawienia. Każde można nadpisać w sekcji [FR_STANDING_START].
L.DEFAULTS = {
  LANGUAGE = 'PL',             -- PL albo EN (kierowca może przełączyć u siebie)
  FORMATION_SPEED_KMH = 80,    -- limit prędkości na okrążeniu formującym (0 = brak)
  APPROACH_ZONE_M = 300,       -- od jakiej odległości pokazujemy pole i odliczanie metrów
  GRID_TOLERANCE_M = 0.5,      -- tyle można stanąć przed/za linią pola bez uwag
  GRID_WARNING_M = 10.0,       -- przestrzelenie do tej wartości = tylko ostrzeżenie, dalej kara
  LATERAL_TOLERANCE_M = 0.5,   -- tyle można stać obok środka pola (w lewo/prawo) bez uwag
  LATERAL_PENALTY_M = 2.0,     -- stoi dalej obok pola przy zapaleniu świateł = kara jak za przestrzelenie
  ALLOW_REVERSE = 0,           -- 0: liczy się najdalszy punkt (cofanie nie kasuje przestrzelenia)
  OVERSHOOT_PENALTY = 'DRIVE_THROUGH', -- DRIVE_THROUGH / TELEPORT / WARNING
  JUMP_START_PENALTY = 'DRIVE_THROUGH',
  LATE_PENALTY = 'DRIVE_THROUGH', -- nie dojechał na pole przed zapaleniem świateł
  LATE_FAR_M = 20,             -- ...a był dalej niż tyle od pola
  LATE_FAR_PENALTY = 'STOP_GO',
  STOP_GO_SECONDS = 10,        -- czas postoju w boksie przy karze stop & go
  PIT_RELEASE_M = 300,         -- start z boksu: wyjazd dopiero, gdy cała stawka minie punkt tyle metrów za polem P1 (≈ T1)
  PIT_RELEASE_MAX_S = 30,      -- ...albo po tylu sekundach od zgaszenia świateł
  PENALTY_LAPS = 3,            -- ile okrążeń na odbycie drive-through
  TELEPORT_SECONDS = 10,       -- blokada w boksie przy karze TELEPORT
  JUMP_START_M = 0.5,          -- ruch większy niż tyle przed zgaszeniem świateł = falstart
  LIGHTS_COUNT = 5,
  LIGHTS_INTERVAL_MS = 1000,   -- co ile zapala się kolejne światło
  LIGHTS_LEAD_MS = 3000,       -- czas od kliknięcia admina do zapalenia pierwszego światła
  HOLD_MIN_MS = 200,           -- losowa przerwa po zapaleniu wszystkich świateł
  HOLD_MAX_MS = 3000,
  AUTO_LIGHTS = 0,             -- 1: klient admina sam zapala światła, gdy wszyscy stoją
  AUTO_DELAY_S = 5,            -- ile sekund wszyscy muszą stać, zanim ruszą światła
  AUTO_TIMEOUT_S = 60,         -- po tylu sekundach od pierwszego auta na polu światła ruszą i tak
  REPORT_REACTION = 1,         -- 1: czas reakcji każdego kierowcy na czacie
  CHAT_PREFIX = 'FRSS>',
}

-- Stany auta (wysyłane w zdarzeniu statusu, więc liczby muszą być stałe).
L.S = {
  NONE = 0,        -- skrypt nieaktywny / poza wyścigiem
  GRID = 1,        -- stoi na polu przed startem z gry
  FORMATION = 2,   -- jedzie okrążenie formujące
  APPROACH = 3,    -- dojeżdża do swojego pola
  IN_SLOT = 4,     -- stoi na polu (w tolerancji)
  SHORT = 5,       -- stoi przed polem (za krótko)
  OVERSHOOT = 6,   -- przestrzelił, ostrzeżenie
  OVERSHOOT_PEN = 7, -- przestrzelił, kara
  PIT_START = 8,   -- startuje z alei serwisowej
  NO_SLOT = 9,     -- brak pola (dołączył po starcie)
  RACING = 10,     -- po zgaszeniu świateł
  LATE = 11,       -- jechał, gdy zapaliły się światła
  WRONG_LANE = 12, -- stoi obok pola (w lewo/prawo)
  DNS = 13,        -- nie ruszył na okrążenie formujące (stoi na polu)
  PIT_OUT = 14,    -- startuje z boksu, jedzie okrążenie formujące (musi wrócić do alei)
}

-- Fazy wyścigu (wspólne dla wszystkich, sterowane startem z gry i komendami admina).
L.P = { IDLE = 0, GRID = 1, FORMATION = 2, LIGHTS = 3, RACING = 4 }

-- Komendy admina.
L.CMD = { LIGHTS = 1, ABORT = 2, PARDON = 3, SKIP_FORMATION = 4, PIT_RELEASE = 5 }

function L.clamp(x, a, b) if x < a then return a elseif x > b then return b else return x end end

-- Różnica pozycji na splajnie a - b w zakresie [-0.5, 0.5).
function L.splineDelta(a, b)
  local d = (a - b) % 1
  if d >= 0.5 then d = d - 1 end
  return d
end

-- Przesunięcie auta względem pola: wzdłużne (+ = przed linią pola, czyli przestrzelenie)
-- i poprzeczne. Działa na tablicach {x,y,z} i na vec3 z CSP.
function L.slotOffset(carPos, slotPos, slotLook, slotSide)
  local dx, dy, dz = carPos.x - slotPos.x, carPos.y - slotPos.y, carPos.z - slotPos.z
  local long = dx * slotLook.x + dy * slotLook.y + dz * slotLook.z
  local lat = dx * slotSide.x + dy * slotSide.y + dz * slotSide.z
  return long, lat
end

-- Odległość do pola w metrach (ujemna = pole jeszcze przed autem, dodatnia = auto za daleko).
-- Blisko pola używa dokładnej geometrii 3D, dalej – pozycji na splajnie.
function L.signedSlotDistance(carSpline, slotSpline, trackLen, long3D)
  local d = L.splineDelta(carSpline, slotSpline) * trackLen
  if long3D ~= nil and math.abs(d) < 60 then return long3D end
  return d
end

-- Przyrost przejechanej drogi między dwiema klatkami (pomija skoki np. przy teleporcie).
function L.travelDelta(prevSpline, newSpline, trackLen)
  local d = L.splineDelta(newSpline, prevSpline)
  if math.abs(d) > 0.1 then return 0 end
  return d * trackLen
end

-- Czy auto zrobiło już większość okrążenia i jest w strefie dojazdu do pola.
function L.isApproaching(traveled, trackLen, signedDist, cfg, minTravel)
  return traveled > (minTravel or trackLen * 0.5) and signedDist > -cfg.APPROACH_ZONE_M and signedDist < 60
end


-- Ocena stojącego (lub dojeżdżającego) auta względem pola.
-- long – bieżące przesunięcie, maxLong – najdalsze przesunięcie osiągnięte w strefie pola.
function L.classifySlot(long, maxLong, speedKmh, cfg, lat)
  -- kara za przestrzelenie zostaje mimo cofnięcia (chyba że ALLOW_REVERSE = 1);
  -- małe przestrzelenie (ostrzeżenie) można poprawić cofając
  local worst = cfg.ALLOW_REVERSE == 1 and long or math.max(long, maxLong)
  if worst > cfg.GRID_WARNING_M then return L.S.OVERSHOOT_PEN, worst end
  local stopped = speedKmh < 0.5
  if not stopped then return L.S.APPROACH, long end
  if lat and math.abs(lat) > cfg.LATERAL_TOLERANCE_M and math.abs(long) < 10 then return L.S.WRONG_LANE, lat end
  if long > cfg.GRID_TOLERANCE_M then return L.S.OVERSHOOT, long end
  if long < -cfg.GRID_TOLERANCE_M then return L.S.SHORT, long end
  return L.S.IN_SLOT, long
end

-- Kara dla auta, które nie stało na polu przy zapaleniu świateł (dist – odległość od pola w m).
function L.latePenalty(dist, cfg)
  if dist and math.abs(dist) > cfg.LATE_FAR_M then return L.parsePenalty(cfg.LATE_FAR_PENALTY, cfg) end
  return L.parsePenalty(cfg.LATE_PENALTY, cfg)
end

-- Kolejność pól: auta posortowane po położeniu na torze (najbliżej linii startu = P1).
-- splines: lista pozycji na splajnie; zwraca listę indeksów od P1.
function L.gridOrder(splines)
  local idx = {}
  for i in ipairs(splines) do idx[#idx + 1] = i end
  if #idx == 0 then return idx end
  local ref = splines[1]
  table.sort(idx, function(a, b) return L.splineDelta(splines[a], ref) > L.splineDelta(splines[b], ref) end)
  return idx
end

-- Czy auto minęło punkt toru (np. T1) – dodatnia różnica na splajnie (do pół okrążenia).
function L.passedPoint(carSpline, pointSpline)
  return L.splineDelta(carSpline, pointSpline) >= 0
end

-- Czy stanie obok pola zasługuje na karę (sprawdzane przy zapaleniu świateł).
function L.isLanePenalty(state, lat, cfg)
  return state == L.S.WRONG_LANE and math.abs(lat or 0) > cfg.LATERAL_PENALTY_M
end

-- Stan kary drive-through: ile okrążeń zostało na odbycie.
function L.dtLapsLeft(laps, startLap, lapCount)
  return laps - (lapCount - startLap)
end

-- Czy stan oznacza, że auto czeka na start (stoi).
function L.isReadyState(s)
  return s == L.S.IN_SLOT or s == L.S.SHORT or s == L.S.OVERSHOOT or s == L.S.OVERSHOOT_PEN
    or s == L.S.PIT_START or s == L.S.NO_SLOT or s == L.S.WRONG_LANE or s == L.S.DNS
end

-- Stan świateł w chwili `now` (ms czasu sesji).
-- Zwraca: liczbę zapalonych świateł, czy zgasły, czas zgaszenia.
function L.lightsState(now, t0, count, intervalMs, holdMs)
  local outAt = t0 + (count - 1) * intervalMs + holdMs
  if now >= outAt then return 0, true, outAt end
  if now < t0 then return 0, false, outAt end
  local lit = math.floor((now - t0) / intervalMs) + 1
  return math.min(lit, count), false, outAt
end

-- Czy ruch przed zgaszeniem świateł to falstart.
function L.isJumpStart(movedM, cfg)
  return movedM > cfg.JUMP_START_M
end

-- Zamiana nazwy kary z konfiguracji na opis.
function L.parsePenalty(name, cfg)
  name = string.upper(tostring(name or ''))
  if name == 'DRIVE_THROUGH' or name == 'DT' then return { kind = 'dt', param = cfg.PENALTY_LAPS } end
  if name == 'TELEPORT' or name == 'TELEPORT_TO_PITS' then return { kind = 'teleport', param = cfg.TELEPORT_SECONDS } end
  if name == 'STOP_GO' or name == 'SG' or name == 'STOP_AND_GO' then return { kind = 'sg', param = cfg.STOP_GO_SECONDS } end
  return { kind = 'warning', param = 0 }
end

-- Która z dwóch kar jest surowsza (gdy kierowca dostał obie, wykonujemy jedną).
local severity = { warning = 0, dt = 1, sg = 2, teleport = 3 }
function L.stronger(a, b)
  if not a then return b end
  if not b then return a end
  return severity[b.kind] > severity[a.kind] and b or a
end

-- Czy klient admina powinien sam zapalić światła.
-- statuses: lista stanów aut; readySince: od kiedy wszyscy stoją (s);
-- firstReadyAt: kiedy pierwsze auto stanęło na polu (s).
function L.autoLightsDue(statuses, now, readySince, firstReadyAt, cfg)
  if #statuses == 0 then return false end
  local allReady = true
  for _, s in ipairs(statuses) do
    if not L.isReadyState(s) then allReady = false break end
  end
  if allReady and readySince and now - readySince >= cfg.AUTO_DELAY_S then return true end
  if firstReadyAt and now - firstReadyAt >= cfg.AUTO_TIMEOUT_S then return true end
  return false
end

-- Wczytanie ustawień: getter(key, default) zwraca wartość z konfiguracji serwera.
function L.readConfig(getter)
  local cfg = {}
  for k, v in pairs(L.DEFAULTS) do
    local val = getter and getter(k, v)
    if val == nil then val = v end
    if type(v) == 'number' then val = tonumber(val) or v end
    if type(v) == 'string' then val = tostring(val) end
    cfg[k] = val
  end
  cfg.LANGUAGE = string.upper(cfg.LANGUAGE) == 'EN' and 'EN' or 'PL'
  cfg.LIGHTS_COUNT = L.clamp(math.floor(cfg.LIGHTS_COUNT), 1, 10)
  if cfg.HOLD_MAX_MS < cfg.HOLD_MIN_MS then cfg.HOLD_MAX_MS = cfg.HOLD_MIN_MS end
  if cfg.GRID_WARNING_M < cfg.GRID_TOLERANCE_M then cfg.GRID_WARNING_M = cfg.GRID_TOLERANCE_M end
  if cfg.LATERAL_PENALTY_M < cfg.LATERAL_TOLERANCE_M then cfg.LATERAL_PENALTY_M = cfg.LATERAL_TOLERANCE_M end
  return cfg
end

-- Teksty PL/EN.
L.TEXT = {
  PL = {
    formation = 'OKRĄŻENIE FORMUJĄCE',
    formationLimit = 'OKRĄŻENIE FORMUJĄCE · max %d km/h',
    yourSlot = 'Twoje pole: P%d',
    pitStart = 'START Z BOKSU – wyjedź dopiero na zielone światło wyjazdu z alei',
    noSlot = 'Brak pola startowego (dołączyłeś po starcie) – startuj z alei',
    toGo = 'P%d · ↑ %d m',
    toGoNear = 'P%d · ↑ %.1f m',
    stop = 'STOP – STOISZ NA POLU',
    short = '↑ Podjedź jeszcze %.1f m',
    overshoot = '↓ Za daleko o %.1f m',
    overshootPen = 'PRZESTRZELONE POLE o %.1f m – KARA',
    waitLights = 'Czekaj na światła',
    lights = 'START',
    late = 'Nie stałeś na polu przy zapaleniu świateł',
    aborted = 'START PRZERWANY – dodatkowe okrążenie formujące',
    reaction = 'Reakcja: %d ms',
    jump = 'FALSTART (%d ms przed zgaszeniem)',
    penDT = 'Kara: drive-through (%d okr.)',
    penTP = 'Kara: teleport do boksów (%d s)',
    penWarn = 'Ostrzeżenie (bez kary)',
    pardoned = 'Admin anulował Twoją karę',
    chatJump = '%s P%d %s: falstart %d ms → %s',
    chatOver = '%s P%d %s: przestrzelone pole o %.1f m → %s',
    chatReaction = '%s P%d %s: reakcja %d ms',
    chatLate = '%s P%d %s: nie stał na polu przy zapaleniu świateł → %s',
    chatPit = '%s %s: wyjazd z alei przed zielonym światłem → %s',
    penNameDT = 'drive-through', penNameTP = 'teleport do boksów', penNameWarn = 'ostrzeżenie',
    -- panel admina
    adminTitle = 'FR Standing Start – admin',
    langToggle = 'FR Standing Start: język PL/EN',
    phase = 'Faza: %s',
    phaseNames = { [0] = 'poza wyścigiem', 'przed startem', 'okrążenie formujące', 'światła', 'wyścig' },
    btnLights = 'Zapal światła',
    btnAbort = 'Przerwij start (dodatkowe formujące)',
    btnSkip = 'Pomiń formujące (test)',
    btnPardon = 'Anuluj karę',
    ready = 'Gotowych: %d / %d',
    auto = 'Automat świateł: %s',
    on = 'włączony', off = 'wyłączony',
    stateNames = {
      [0] = '–', 'na polu (przed startem)', 'formujące', 'dojeżdża', 'na polu', 'przed polem',
      'za daleko', 'PRZESTRZELIŁ (kara)', 'start z boksu', 'brak pola', 'wyścig', 'spóźniony', 'obok pola',
      'nie ruszył na formujące', 'z boksu na formującym',
    },
    pending = 'kara czeka',
    dns = 'Nie ruszyłeś na okrążenie formujące – czekaj na światła',
    pitStartMsg = 'Startujesz z boksu',
    pitOut = 'START Z BOKSU – po okrążeniu formującym zjedź do alei serwisowej',
    pitWait = 'WYJAZD Z ALEI: CZEKAJ',
    pitGo = 'WYJAZD Z ALEI: JEDŹ',
    pitEarly = 'Wyjazd z alei przed zielonym światłem',
    penSG = 'Kara: stop & go %d s (%d okr.)',
    penNameSG = 'stop & go %d s',
    sgInfo = 'STOP & GO %d s: zjedź do boksu – zostało okrążeń: %d',
    sgLast = 'STOP & GO: OSTATNIE OKRĄŻENIE na odbycie kary!',
    sgCount = 'STOP & GO: %d s',
    sgGo = 'STOP & GO odbyty – JEDŹ',
    sgNotServed = 'Stop & go nie zaliczony – zatrzymaj się w swoim boksie na %d s',
    chatSGServed = '%s %s: stop & go odbyty',
    listTitle = 'Czasy reakcji – %s – %s',
    listJump = 'FALSTART (%d ms za wcześnie)',
    listLate = 'nie stał na polu',
    listPit = 'start z alei',
    listNone = 'brak pomiaru',
    btnCopy = 'Kopiuj czasy reakcji (Discord)',
    copied = 'Skopiowano – wklej na Discordzie (Ctrl+V)',
    reactHeader = 'Czasy reakcji (%d):',
    wrongLane = 'STAŃ NA ŚRODKU POLA – jesteś obok o %.1f m',
    moveLeft = '← W LEWO o %.1f m',
    moveRight = 'W PRAWO o %.1f m →',
    penStopInvalid = 'Postój w boksie nie zalicza drive-through – przejedź aleję bez zatrzymania',
    chatStopInvalid = '%s %s: postój w boksie nie zaliczył drive-through',
    chatLane = '%s P%d %s: stał obok pola (%.1f m) → %s',
    penDTInfo = 'DRIVE-THROUGH: przejedź przez aleję serwisową – zostało okrążeń: %d',
    penDTLast = 'DRIVE-THROUGH: OSTATNIE OKRĄŻENIE na odbycie kary!',
    penServed = 'Kara drive-through odbyta',
    penMissed = 'Nie odbyłeś drive-through w wyznaczonym czasie',
    chatServed = '%s %s: drive-through odbyty',
    chatMissed = '%s %s: drive-through NIE odbyty',
    settingsTitle = 'FR Standing Start – ustawienia',
    setLang = 'Język: %s (kliknij, aby zmienić)',
    setPosX = 'Poziomo',
    setPosY = 'Pionowo',
    setScale = 'Wielkość',
    setHint = 'Możesz też przeciągnąć podgląd myszką.',
    setReset = 'Przywróć domyślne',
    preview = 'P1 · 12.3 m (podgląd)',
    chatHelp = 'Czat: !frss swiatla / !frss przerwij / !frss pomin',
    noData = 'brak danych',
  },
  EN = {
    formation = 'FORMATION LAP',
    formationLimit = 'FORMATION LAP · max %d km/h',
    yourSlot = 'Your grid slot: P%d',
    pitStart = 'PIT START – leave only on the green pit exit light',
    noSlot = 'No grid slot (joined after the start) – start from the pit lane',
    toGo = 'P%d · ↑ %d m',
    toGoNear = 'P%d · ↑ %.1f m',
    stop = 'STOP – YOU ARE IN YOUR SLOT',
    short = '↑ Move up %.1f m',
    overshoot = '↓ Too far by %.1f m',
    overshootPen = 'GRID SLOT OVERSHOT by %.1f m – PENALTY',
    waitLights = 'Wait for the lights',
    lights = 'START',
    late = 'You were not in your slot when the lights came on',
    aborted = 'START ABORTED – extra formation lap',
    reaction = 'Reaction: %d ms',
    jump = 'JUMP START (%d ms before lights out)',
    penDT = 'Penalty: drive-through (%d laps)',
    penTP = 'Penalty: teleport to pits (%d s)',
    penWarn = 'Warning (no penalty)',
    pardoned = 'Admin cancelled your penalty',
    chatJump = '%s P%d %s: jump start %d ms → %s',
    chatOver = '%s P%d %s: grid slot overshot by %.1f m → %s',
    chatReaction = '%s P%d %s: reaction %d ms',
    chatLate = '%s P%d %s: not in slot when the lights came on → %s',
    chatPit = '%s %s: left the pit lane before the green light → %s',
    penNameDT = 'drive-through', penNameTP = 'teleport to pits', penNameWarn = 'warning',
    adminTitle = 'FR Standing Start – admin',
    langToggle = 'FR Standing Start: language PL/EN',
    phase = 'Phase: %s',
    phaseNames = { [0] = 'not a race', 'before start', 'formation lap', 'lights', 'race' },
    btnLights = 'Start lights',
    btnAbort = 'Abort start (extra formation lap)',
    btnSkip = 'Skip formation (test)',
    btnPardon = 'Cancel penalty',
    ready = 'Ready: %d / %d',
    auto = 'Auto lights: %s',
    on = 'on', off = 'off',
    stateNames = {
      [0] = '–', 'on grid (before start)', 'formation', 'approaching', 'in slot', 'short of slot',
      'too far', 'OVERSHOT (penalty)', 'pit start', 'no slot', 'race', 'late', 'beside slot', 'did not start formation',
      'pit starter on formation',
    },
    pending = 'penalty pending',
    dns = 'You did not start the formation lap – wait for the lights',
    pitStartMsg = 'You start from the pits',
    pitOut = 'PIT START – after the formation lap, enter the pit lane',
    pitWait = 'PIT EXIT: WAIT',
    pitGo = 'PIT EXIT: GO',
    pitEarly = 'Left the pit lane before the green light',
    penSG = 'Penalty: stop & go %d s (%d laps)',
    penNameSG = 'stop & go %d s',
    sgInfo = 'STOP & GO %d s: enter your pit box – laps left: %d',
    sgLast = 'STOP & GO: LAST LAP to serve the penalty!',
    sgCount = 'STOP & GO: %d s',
    sgGo = 'STOP & GO served – GO',
    sgNotServed = 'Stop & go not served – stop in your pit box for %d s',
    chatSGServed = '%s %s: stop & go served',
    listTitle = 'Reaction times – %s – %s',
    listJump = 'JUMP START (%d ms early)',
    listLate = 'not in slot',
    listPit = 'pit lane start',
    listNone = 'no measurement',
    btnCopy = 'Copy reaction times (Discord)',
    copied = 'Copied – paste it on Discord (Ctrl+V)',
    reactHeader = 'Reaction times (%d):',
    wrongLane = 'MOVE TO THE CENTRE OF THE SLOT – you are %.1f m off',
    moveLeft = '← LEFT by %.1f m',
    moveRight = 'RIGHT by %.1f m →',
    penStopInvalid = 'A pit stop does not serve a drive-through – drive through the pit lane without stopping',
    chatStopInvalid = '%s %s: pit stop did not serve the drive-through',
    chatLane = '%s P%d %s: stopped beside the slot (%.1f m) → %s',
    penDTInfo = 'DRIVE-THROUGH: drive through the pit lane – laps left: %d',
    penDTLast = 'DRIVE-THROUGH: LAST LAP to serve the penalty!',
    penServed = 'Drive-through served',
    penMissed = 'Drive-through not served in time',
    chatServed = '%s %s: drive-through served',
    chatMissed = '%s %s: drive-through NOT served',
    settingsTitle = 'FR Standing Start – settings',
    setLang = 'Language: %s (click to change)',
    setPosX = 'Horizontal',
    setPosY = 'Vertical',
    setScale = 'Size',
    setHint = 'You can also drag the preview with the mouse.',
    setReset = 'Reset to defaults',
    preview = 'P1 · 12.3 m (preview)',
    chatHelp = 'Chat: !frss lights / !frss abort / !frss skip',
    noData = 'no data',
  },
}

function L.text(lang, key)
  local t = L.TEXT[lang] or L.TEXT.PL
  return t[key] or L.TEXT.PL[key] or key
end

-- Lista czasów reakcji do wklejenia na Discord.
-- entries: { name, slot, ms (nil gdy brak), jump (bool), jumpMs, pit (bool), late (bool) }
function L.formatReactions(lang, entries, title)
  local ok, rest = {}, {}
  for _, e in ipairs(entries) do
    if e.ms and not e.jump and not e.late then ok[#ok + 1] = e else rest[#rest + 1] = e end
  end
  table.sort(ok, function(a, b) return a.ms < b.ms end)
  table.sort(rest, function(a, b) return (a.slot or 99) < (b.slot or 99) end)
  local lines = { '**' .. title .. '**' }
  for i, e in ipairs(ok) do
    lines[#lines + 1] = string.format('%d. %s (P%d) – %.3f s', i, e.name, e.slot or 0, e.ms / 1000)
  end
  for _, e in ipairs(rest) do
    local why
    if e.jump then why = string.format(L.text(lang, 'listJump'), e.jumpMs or 0)
    elseif e.late then why = L.text(lang, 'listLate')
    elseif e.pit then why = L.text(lang, 'listPit')
    else why = L.text(lang, 'listNone') end
    lines[#lines + 1] = string.format('– %s (P%d) – %s', e.name, e.slot or 0, why)
  end
  return table.concat(lines, '\n')
end

function L.penaltyName(lang, pen)
  if pen.kind == 'dt' then return L.text(lang, 'penNameDT') end
  if pen.kind == 'sg' then return string.format(L.text(lang, 'penNameSG'), pen.param) end
  if pen.kind == 'teleport' then return L.text(lang, 'penNameTP') end
  return L.text(lang, 'penNameWarn')
end

-- W testach (poza grą) kończymy tutaj i zwracamy logikę.
if FRSS_TEST then return L end

-------------------------------------------------------------------------------
-- 2. Część działająca w grze (CSP)
-------------------------------------------------------------------------------

local sim = ac.getSim()
local myCar = ac.getCar(0)
local cfg = L.readConfig(nil)
local lang = cfg.LANGUAGE

local function T(key, ...)
  local s = L.text(lang, key)
  if select('#', ...) > 0 then return string.format(s, ...) end
  return s
end

local function chat(msg)
  pcall(ac.sendChatMessage, msg)
end

local function log(msg)
  ac.log('[FRSS] ' .. msg)
end

-- Stan globalny (per klient)
local phase = L.P.IDLE
local slots = {}          -- [carIndex] = {pos, look, side, spline, gridPos, groundY, pit}
local lightsT0, lightsHold, lightsOutAt = nil, nil, nil
local lightsDoneAt = nil   -- czas gry (s), kiedy zgasły światła
local sessionIndex = -1

-- Stan własnego auta
local me = {}
local function resetMe()
  me = {
    state = L.S.NONE,
    traveled = 0,
    prevSpline = nil,
    long = 0, lat = 0, maxLong = -1e9,
    dist = nil,
    pending = nil,        -- kara czekająca do zgaszenia świateł
    jumpMs = nil,
    late = false,
    lightsStartPos = nil, -- pozycja przy zapaleniu pierwszego światła
    wasStopped = false,
    reactionMs = nil, outPos = nil,
    pitStart = false,
    pardoned = false,
    notice = nil, noticeUntil = 0, noticeColor = rgbm.colors.white,
    lastSentState = -1, lastSentAt = -100, lastSentOffset = 0,
  }
end
resetMe()

-- Statusy innych aut (zbierane przez wszystkich, używane w panelu admina)
local statuses = {}  -- [carIndex] = {state, offsetCm, pending, at}

-- Automat świateł (tylko klient admina)
local auto = { readySince = nil, firstReadyAt = nil, since = 0 }

-- Lokalny zegar tego komputera (ms). Światła liczymy od chwili otrzymania komendy,
-- bo czas sesji potrafi się różnić między komputerami o kilka sekund.
local function clockMs() return sim.time end
local lightsSentAt = nil
local function gameS() return sim.gameTime end

local function notify(text, seconds, color)
  me.notice = text
  me.noticeUntil = gameS() + (seconds or 5)
  me.noticeColor = color or rgbm.colors.white
end

local function myName()
  return ac.getDriverName(0) or '?'
end

local function mySlotNumber()
  local s = slots[0]
  return s and s.gridPos or 0
end

-- CSP ustawia sim.isAdmin tylko po zalogowaniu w nowej aplikacji czatu.
-- Dlatego rozpoznajemy też odpowiedź serwera na komendę /admin.
local adminByChat = false
local function isAdmin() return sim.isAdmin or adminByChat end

-- Zdarzenia sieciowe ----------------------------------------------------------

local sendStatus = ac.OnlineEvent({
  key = ac.StructItem.key('frss_status_v1'),
  state = ac.StructItem.byte(),
  offsetCm = ac.StructItem.int16(),
  pending = ac.StructItem.byte(),
}, function(sender, data)
  if not sender then return end
  statuses[sender.index] = { state = data.state, offsetCm = data.offsetCm, pending = data.pending, at = gameS() }
end, ac.SharedNamespace.ServerScript)

-- Czasy reakcji wszystkich kierowców (zbiera każdy klient, lista w panelu admina)
local reactions = {} -- [carIndex] = { name, slot, ms, jump, jumpMs, pit, late }

local sendReaction = ac.OnlineEvent({
  key = ac.StructItem.key('frss_react_v1'),
  ms = ac.StructItem.int32(),
  slot = ac.StructItem.int16(),
  flags = ac.StructItem.byte(),
}, function(sender, data)
  if not sender then return end
  local f = data.flags
  reactions[sender.index] = {
    name = ac.getDriverName(sender.index) or '?',
    slot = data.slot,
    ms = (f == 0) and data.ms or nil,
    jump = f % 2 == 1, jumpMs = data.ms,
    pit = math.floor(f / 2) % 2 == 1,
    late = math.floor(f / 4) % 2 == 1,
  }
end, ac.SharedNamespace.ServerScript)

local function reportReaction(ms, jump, pit, late)
  local flags = (jump and 1 or 0) + (pit and 2 or 0) + (late and 4 or 0)
  sendReaction({ ms = math.floor(ms or 0), slot = mySlotNumber(), flags = flags })
end

local onPhase -- zdefiniowane niżej
local sendPhase = ac.OnlineEvent({
  key = ac.StructItem.key('frss_phase_v1'),
  phase = ac.StructItem.byte(),
  released = ac.StructItem.byte(),
}, function(sender, data)
  if onPhase then onPhase(sender, data) end
end, ac.SharedNamespace.ServerScript)

local pitReleased = false
local function broadcastPhase()
  -- klient admina ogłasza fazę (powtarzaną dla kierowców, którzy dołączą później)
  if isAdmin() then pcall(sendPhase, { phase = phase, released = pitReleased and 1 or 0 }, true) end
end

local onCommand -- zdefiniowane niżej

local sendCommand = ac.OnlineEvent({
  key = ac.StructItem.key('frss_cmd_v1'),
  cmd = ac.StructItem.byte(),
  t0 = ac.StructItem.double(),
  hold = ac.StructItem.int32(),
  target = ac.StructItem.int32(),
}, function(sender, data)
  if onCommand then onCommand(sender, data) end
end, ac.SharedNamespace.ServerScript)

local function pushStatus(force)
  local offsetCm = math.floor(L.clamp(me.long or 0, -300, 300) * 100 + 0.5)
  local pend = me.pending and (me.pending.kind == 'teleport' and 2 or me.pending.kind == 'dt' and 1 or 3) or 0
  local t = gameS()
  local changed = me.state ~= me.lastSentState or math.abs(offsetCm - me.lastSentOffset) >= 20
  if (changed and t - me.lastSentAt >= 1) or force then
    if sendStatus({ state = me.state, offsetCm = offsetCm, pending = pend }) then
      me.lastSentState, me.lastSentAt, me.lastSentOffset = me.state, t, offsetCm
    end
  end
end

-- Pola startowe ---------------------------------------------------------------

local function groundY(pos)
  local up = vec3(0, 1, 0)
  local d = physics.raycastTrack(pos + up * 2, vec3(0, -1, 0), 5)
  if d and d >= 0 then return pos.y + 2 - d end
  return pos.y
end

local function recordSlots()
  for i = 0, sim.carsCount - 1 do
    local c = ac.getCar(i)
    if c and c.isConnected then
      slots[i] = {
        pos = c.position:clone(),
        look = c.look:clone(),
        side = c.side:clone(),
        spline = c.splinePosition,
        gridPos = c.racePosition,
        pit = c.isInPitlane or c.isInPit,
        sessionID = c.sessionID,
        size = c.aabbSize and c.aabbSize:clone() or vec3(2, 1.3, 4.6),
      }
    end
  end
end

local function freezeSlots()
  -- numeracja pól z położenia aut na torze (najbliżej linii = P1), nie z wyników:
  -- auto przeniesione do boksu nie zabiera pola P1
  local list = {}
  for _, sl in pairs(slots) do if not sl.pit then list[#list + 1] = sl end end
  local splines = {}
  for i, sl in ipairs(list) do splines[i] = sl.spline end
  for rank, i in ipairs(L.gridOrder(splines)) do list[i].gridPos = rank end
  for _, sl in pairs(slots) do
    if sl.pit then sl.gridPos = 0 end
    sl.groundY = groundY(sl.pos)
  end
  local s = slots[0]
  if s then
    log(string.format('pole P%d zapisane, spline %.4f', s.gridPos, s.spline))
  end
end

-- Kary ------------------------------------------------------------------------

local function applyPenalty(pen)
  if not pen or pen.kind == 'warning' then return end
  if pen.kind == 'dt' then
    physics.setCarPenalty(ac.PenaltyType.MandatoryPits, pen.param)
    notify(T('penDT', pen.param), 8, rgbm.colors.red)
    me.dt = { laps = pen.param, startLap = myCar.lapCount, inPit = myCar.isInPitlane, done = false }
  elseif pen.kind == 'sg' then
    physics.setCarPenalty(ac.PenaltyType.MandatoryPits, cfg.PENALTY_LAPS)
    notify(T('penSG', pen.param, cfg.PENALTY_LAPS), 8, rgbm.colors.red)
    me.sg = { laps = cfg.PENALTY_LAPS, startLap = myCar.lapCount, secs = pen.param, stopTime = 0, done = false }
  elseif pen.kind == 'teleport' then
    physics.setCarPenalty(ac.PenaltyType.TeleportToPits, pen.param)
    notify(T('penTP', pen.param), 8, rgbm.colors.red)
  end
end

local function penaltyText(pen)
  return L.penaltyName(lang, pen)
end

-- Fazy ------------------------------------------------------------------------

local function startFormation(extraLap)
  phase = L.P.FORMATION
  lightsT0, lightsHold, lightsOutAt, lightsDoneAt = nil, nil, nil, nil
  me.traveled = 0
  me.prevSpline = myCar.splinePosition
  me.maxLong = -1e9
  me.late = false
  me.jumpMs = nil
  me.lightsStartPos = nil
  pitReleased = false
  if me.pitStart then me.state = (myCar.isInPitlane or myCar.isInPit) and L.S.PIT_START or L.S.PIT_OUT
  elseif slots[0] then me.state = L.S.FORMATION
  else me.state = L.S.NO_SLOT end
  auto.readySince, auto.firstReadyAt, auto.since = nil, nil, gameS()
  me.formationStartAt = gameS()
  pushStatus(true) -- wszyscy od razu meldują nowy stan (stare statusy przestają się liczyć)
  if extraLap then
    notify(T('aborted'), 8, rgbm.colors.yellow)
    -- kara za przestrzelenie z przerwanego startu przepada, falstart też
    me.pending = nil
    me.pardoned = false
  end
  broadcastPhase()
  log('faza: formujące' .. (extraLap and ' (dodatkowe)' or ''))
end

local function startLights(t0, hold)
  if phase ~= L.P.FORMATION then return end
  phase = L.P.LIGHTS
  reactions = {}
  lightsT0, lightsHold = t0, hold
  local _, _, outAt = L.lightsState(clockMs(), t0, cfg.LIGHTS_COUNT, cfg.LIGHTS_INTERVAL_MS, hold)
  lightsOutAt = outAt
  broadcastPhase()
  log(string.format('światła: start %.0f, zgaszenie %.0f', t0, outAt))
end

local function finishStart()
  phase = L.P.RACING
  lightsDoneAt = gameS()
  me.outPos = myCar.position:clone()
  local n = mySlotNumber()
  local name = myName()
  local pen = nil

  if me.jumpMs then
    local p = L.parsePenalty(cfg.JUMP_START_PENALTY, cfg)
    pen = L.stronger(pen, p)
    if me.pitStart then
      chat(string.format(T('chatPit'), cfg.CHAT_PREFIX, name, penaltyText(p)))
    else
      chat(string.format(T('chatJump'), cfg.CHAT_PREFIX, n, name, me.jumpMs, penaltyText(p)))
    end
    notify(T('jump', me.jumpMs), 8, rgbm.colors.red)
  end
  if me.pending then
    pen = L.stronger(pen, me.pending)
    if me.maxLong > cfg.GRID_WARNING_M then
      chat(string.format(T('chatOver'), cfg.CHAT_PREFIX, n, name, me.maxLong, penaltyText(me.pending)))
    end
    if me.lanePenalty then
      chat(string.format(T('chatLane'), cfg.CHAT_PREFIX, n, name, me.lanePenalty, penaltyText(me.pending)))
    end
  end
  if me.late then
    chat(string.format(T('chatLate'), cfg.CHAT_PREFIX, n, name, penaltyText(me.latePen or L.parsePenalty(cfg.LATE_PENALTY, cfg))))
  end
  if me.jumpMs then reportReaction(me.jumpMs, true, me.pitStart, false)
  elseif me.late then reportReaction(0, false, false, true)
  elseif me.pitStart or not slots[0] then reportReaction(0, false, true, false) end
  applyPenalty(pen)
  me.pending = nil
  me.pitWait = me.pitStart and not me.late and not me.jumpMs
  me.state = me.pitWait and L.S.PIT_START or L.S.RACING
  pushStatus(true)
  broadcastPhase()
  log('faza: wyścig')
end

onCommand = function(sender, data)
  if data.cmd == L.CMD.LIGHTS then
    -- wspólny moment startu = chwila, gdy komenda dotarła do serwera, + LIGHTS_LEAD_MS;
    -- odejmujemy połowę pingu (czas drogi serwer → ten komputer)
    local ping = (myCar.ping and myCar.ping > 0) and myCar.ping or 0
    local t0
    if sender and sender.index == 0 and lightsSentAt and clockMs() - lightsSentAt < 5000 then
      t0 = lightsSentAt + ping / 2 + cfg.LIGHTS_LEAD_MS
    else
      t0 = clockMs() - ping / 2 + cfg.LIGHTS_LEAD_MS
    end
    lightsSentAt = nil
    startLights(t0, data.hold)
  elseif data.cmd == L.CMD.ABORT then
    if phase == L.P.LIGHTS or phase == L.P.FORMATION then startFormation(true) end
  elseif data.cmd == L.CMD.PARDON then
    if data.target == myCar.sessionID and phase ~= L.P.RACING then
      me.pending = nil
      me.jumpMs = nil
      me.lanePenalty = nil
      me.pardoned = true
      notify(T('pardoned'), 6, rgbm.colors.green)
      pushStatus(true)
    end
  elseif data.cmd == L.CMD.PIT_RELEASE then
    pitReleased = true
  elseif data.cmd == L.CMD.SKIP_FORMATION then
    if phase == L.P.FORMATION then me.traveled = sim.trackLengthM end
  end
end

-- Kierowca dołączył w trakcie procedury startu: dowiaduje się o fazie od admina.
onPhase = function(sender, data)
  if sender and sender.index == 0 then return end
  if data.released == 1 then pitReleased = true end
  if sim.raceSessionType ~= ac.SessionType.Race or slots[0] then return end
  -- tylko kierowca bez pola (dołączył po starcie z gry), gdy procedura startu jeszcze trwa
  if me.state == L.S.NO_SLOT and not (data.phase == L.P.RACING and data.released == 1) then
    me.pitStart = true
    if data.phase == L.P.FORMATION then
      phase = L.P.FORMATION
      me.state = (myCar.isInPitlane or myCar.isInPit) and L.S.PIT_START or L.S.PIT_OUT
    else
      phase = L.P.RACING
      me.pitWait = not pitReleased
      me.state = L.S.PIT_START
    end
    notify(T('pitStartMsg'), 8, rgbm.colors.yellow)
    log('dołączenie w trakcie startu: start z boksu')
  end
end

local function adminSend(cmd, target)
  local t0, hold = 0, 0
  if cmd == L.CMD.LIGHTS then
    math.randomseed(os.time() + math.floor(clockMs()))
    lightsSentAt = clockMs()
    hold = math.random(cfg.HOLD_MIN_MS, cfg.HOLD_MAX_MS)
  end
  sendCommand({ cmd = cmd, t0 = t0, hold = hold, target = target or -1 })
end

-- Konfiguracja z serwera --------------------------------------------------------

ac.onOnlineWelcome(function(message, config)
  cfg = L.readConfig(function(k, v) return config:get('FR_STANDING_START', k, v) end)
  lang = cfg.LANGUAGE
  log('v' .. VERSION .. ' wczytany, język ' .. lang)
end)

ac.onSessionStart(function(index, restarted)
  phase = L.P.IDLE
  slots, statuses = {}, {}
  resetMe()
  sessionIndex = index
end)

-- Admin i komendy na czacie ----------------------------------------------------

-- CSP ustawia sim.isAdmin tylko po zalogowaniu w nowej aplikacji czatu.
-- Dlatego rozpoznajemy też odpowiedź serwera na komendę /admin.

local copyReactions -- zdefiniowane niżej (panel admina)

L.CHAT_COMMANDS = {
  swiatla = L.CMD.LIGHTS, ['światła'] = L.CMD.LIGHTS, lights = L.CMD.LIGHTS,
  przerwij = L.CMD.ABORT, abort = L.CMD.ABORT,
  pomin = L.CMD.SKIP_FORMATION, ['pomiń'] = L.CMD.SKIP_FORMATION, skip = L.CMD.SKIP_FORMATION,
  reakcje = 'copy', reactions = 'copy',
}

ac.onChatMessage(function(message, senderCarIndex)
  local msg = tostring(message or '')
  if senderCarIndex == -1 and msg:lower():find('you are now admin', 1, true) then
    adminByChat = true
    pcall(ac.checkAdminPrivileges)
    log('rozpoznano admina po komendzie /admin')
    return false
  end
  -- czas reakcji widzi tylko jego autor
  if msg:sub(1, #cfg.CHAT_PREFIX + 1) == cfg.CHAT_PREFIX .. 'R' and senderCarIndex ~= 0 then
    return true
  end
  local cmd = msg:match('^!frss%s+(%S+)')
  if cmd then
    if senderCarIndex == 0 and isAdmin() then
      local c = L.CHAT_COMMANDS[cmd:lower()]
      if c == 'copy' then copyReactions()
      elseif c then adminSend(c) end
    end
    return true -- ukryj komendę na czacie u wszystkich
  end
  return false
end)

pcall(ac.checkAdminPrivileges)

-- Pętla główna ----------------------------------------------------------------

local function updateGrid()
  -- przed startem z gry: auta stoją na polach z kwalifikacji
  phase = L.P.GRID
  recordSlots()
  me.pitStart = myCar.isInPitlane or myCar.isInPit
  me.state = me.pitStart and L.S.PIT_START or L.S.GRID
end

local function updateFormation(dt)
  -- limit prędkości (poza aleją, gdzie działa ogranicznik gry)
  if cfg.FORMATION_SPEED_KMH > 0 and not myCar.isInPitlane then
    local v = myCar.speedKmh
    if v > cfg.FORMATION_SPEED_KMH then
      physics.forceUserThrottleFor(0.1, 0)
      if v > cfg.FORMATION_SPEED_KMH + 15 then physics.forceUserBrakesFor(0.1, 0.3) end
    end
  end

  -- start z boksu: może przejechać formujące, ale musi wrócić do alei
  if me.pitStart then
    if myCar.isInPitlane or myCar.isInPit then
      me.state = L.S.PIT_START
    else
      if me.state == L.S.PIT_START then notify(T('pitOut'), 8, rgbm.colors.yellow) end
      me.state = L.S.PIT_OUT
    end
    return
  end
  if not slots[0] then
    me.state = L.S.NO_SLOT
    return
  end
  -- auto w alei lub w boksie (wjazd albo przeniesienie do boksu) = start z boksu
  if myCar.isInPitlane or myCar.isInPit then
    me.pitStart = true
    me.state = L.S.PIT_START
    notify(T('pitStartMsg'), 8, rgbm.colors.yellow)
    return
  end

  local s = slots[0]
  local trackLen = sim.trackLengthM > 0 and sim.trackLengthM or 4000
  if me.prevSpline then
    me.traveled = me.traveled + L.travelDelta(me.prevSpline, myCar.splinePosition, trackLen)
  end
  me.prevSpline = myCar.splinePosition

  local long, lat = L.slotOffset(myCar.position, s.pos, s.look, s.side)
  local dist = L.signedSlotDistance(myCar.splinePosition, s.spline, trackLen, long)
  me.dist = dist

  -- nie ruszył na formujące: stoi na swoim polu od ponad 20 s
  if me.traveled < 30 and myCar.speedKmh < 1 and gameS() - (me.formationStartAt or gameS()) > 20 then
    me.state = L.S.DNS
    me.long, me.lat = dist, lat
    return
  end

  if L.isApproaching(me.traveled, trackLen, dist, cfg) then
    me.long, me.lat = dist, lat
    -- w którą stronę do środka pola: oś „w prawo” z pozycji kół (przednie prawe − przednie lewe)
    local wh = myCar.wheels
    if wh and wh[0] and wh[1] then
      local rx, rz = wh[1].position.x - wh[0].position.x, wh[1].position.z - wh[0].position.z
      local len = math.sqrt(rx * rx + rz * rz)
      if len > 0.1 then
        me.toSlotRight = ((s.pos.x - myCar.position.x) * rx + (s.pos.z - myCar.position.z) * rz) / len
      end
    end
    if math.abs(dist) < 60 then me.maxLong = math.max(me.maxLong, dist) end
    local st = L.classifySlot(dist, me.maxLong, myCar.speedKmh, cfg, lat)
    me.state = st
    if st == L.S.OVERSHOOT_PEN and not me.pardoned then
      me.pending = L.parsePenalty(cfg.OVERSHOOT_PENALTY, cfg)
    end
  else
    me.state = L.S.FORMATION
  end
end

local function updateLights()
  local lit, out = L.lightsState(clockMs(), lightsT0, cfg.LIGHTS_COUNT, cfg.LIGHTS_INTERVAL_MS, lightsHold)
  -- pierwsze światło: zapamiętaj pozycję i czy auto stało
  if lit >= 1 and not me.lightsStartPos then
    me.lightsStartPos = myCar.position:clone()
    me.wasStopped = myCar.speedKmh < 1
    if L.isLanePenalty(me.state, me.lat, cfg) and not me.pardoned then
      me.lanePenalty = math.abs(me.lat)
      me.pending = L.stronger(me.pending, L.parsePenalty(cfg.OVERSHOOT_PENALTY, cfg))
    end
    local notThere = me.state == L.S.FORMATION or me.state == L.S.APPROACH or me.state == L.S.LATE
      or me.state == L.S.PIT_OUT
    if (not me.pitStart and slots[0] and (notThere or not me.wasStopped)) or me.state == L.S.PIT_OUT then
      me.late = true
      me.state = L.S.LATE
      me.wasStopped = false -- spóźniony: ruch w trakcie świateł nie jest liczony jako falstart
      -- daleko od pola (ponad LATE_FAR_M) = stop & go, bliżej = drive-through
      me.latePen = me.pitStart and L.parsePenalty(cfg.LATE_PENALTY, cfg) or L.latePenalty(me.dist, cfg)
      if not me.pardoned then
        me.pending = L.stronger(me.pending, me.latePen)
      end
      notify(T('late'), 6, rgbm.colors.red)
    end
  end
  -- falstart
  if me.lightsStartPos and not me.jumpMs and not me.late and (me.wasStopped or me.pitStart) then
    local moved
    if me.pitStart then
      moved = (not myCar.isInPitlane and not myCar.isInPit) and 99 or 0
    else
      moved = L.slotOffset(myCar.position, me.lightsStartPos, myCar.look, myCar.side)
    end
    if L.isJumpStart(moved, cfg) then
      me.jumpMs = math.max(0, math.floor(lightsOutAt - clockMs()))
      log('falstart ' .. me.jumpMs .. ' ms')
    end
  end
  if out then finishStart() end
end

local function updateDriveThrough(frameDt)
  local dt = me.dt
  if not dt or dt.done then return end
  dt.frame = frameDt or 0
  if myCar.isInPitlane then
    dt.inPit = true
    -- zatrzymanie w boksie (pitstop) nie zalicza drive-through
    if myCar.isInPit or myCar.speedKmh < 1 then
      dt.stopTime = (dt.stopTime or 0) + (dt.frame or 0)
      if myCar.isInPit or dt.stopTime > 1 then dt.stopped = true end
    end
  elseif dt.inPit and dt.stopped then
    dt.inPit, dt.stopped, dt.stopTime = false, false, 0
    local left = math.max(1, L.dtLapsLeft(dt.laps, dt.startLap, myCar.lapCount))
    physics.setCarPenalty(ac.PenaltyType.MandatoryPits, left)
    notify(T('penStopInvalid'), 8, rgbm.colors.red)
    chat(string.format(T('chatStopInvalid'), cfg.CHAT_PREFIX, myName()))
  elseif dt.inPit then
    dt.done = true
    notify(T('penServed'), 6, rgbm.colors.green)
    chat(string.format(T('chatServed'), cfg.CHAT_PREFIX, myName()))
    return
  end
  if L.dtLapsLeft(dt.laps, dt.startLap, myCar.lapCount) <= 0 and not dt.inPit then
    dt.done = true
    dt.missed = true
    notify(T('penMissed'), 8, rgbm.colors.red)
    chat(string.format(T('chatMissed'), cfg.CHAT_PREFIX, myName()))
  end
end

local function updateStopGo(frameDt)
  local sg = me.sg
  if not sg or sg.done then return end
  if myCar.isInPitlane or myCar.isInPit then
    sg.inPit = true
    if myCar.isInPit and myCar.speedKmh < 1 then
      sg.stopTime = sg.stopTime + (frameDt or 0)
      if sg.stopTime < sg.secs then
        physics.forceUserBrakesFor(0.2, 1) -- trzyma auto w miejscu do końca kary
      elseif not sg.go then
        sg.go = true
        notify(T('sgGo'), 6, rgbm.colors.green)
        chat(string.format(T('chatSGServed'), cfg.CHAT_PREFIX, myName()))
      end
    end
  elseif sg.inPit then
    sg.inPit = false
    if sg.go then
      sg.done = true
      return
    end
    -- wyjechał bez pełnego postoju
    sg.stopTime = 0
    local left = math.max(1, L.dtLapsLeft(sg.laps, sg.startLap, myCar.lapCount))
    physics.setCarPenalty(ac.PenaltyType.MandatoryPits, left)
    notify(T('sgNotServed', sg.secs), 8, rgbm.colors.red)
    chat(string.format(T('chatStopInvalid'), cfg.CHAT_PREFIX, myName()))
  end
  if L.dtLapsLeft(sg.laps, sg.startLap, myCar.lapCount) <= 0 and not sg.inPit then
    sg.done = true
    sg.missed = true
    notify(T('penMissed'), 8, rgbm.colors.red)
    chat(string.format(T('chatMissed'), cfg.CHAT_PREFIX, myName()))
  end
end

-- Zielone światło wyjazdu z alei dla startujących z boksu:
-- cała stawka minęła punkt PIT_RELEASE_M za polem P1 (≈ T1) albo minął limit czasu.
local function pitReleaseDue()
  if pitReleased then return true end
  if not lightsDoneAt then return false end
  if gameS() - lightsDoneAt >= cfg.PIT_RELEASE_MAX_S then return true end
  local p1
  for _, sl in pairs(slots) do if sl.gridPos == 1 then p1 = sl end end
  if not p1 then return false end
  local trackLen = sim.trackLengthM > 0 and sim.trackLengthM or 4000
  local t1 = (p1.spline + cfg.PIT_RELEASE_M / trackLen) % 1
  for i, sl in pairs(slots) do
    local c = ac.getCar(i)
    if c and c.isConnected and not sl.pit and not c.isInPitlane and not c.isInPit then
      if not L.passedPoint(c.splinePosition, t1) then return false end
    end
  end
  return true
end

local function updatePitRelease()
  if not pitReleased and pitReleaseDue() then
    pitReleased = true
    if isAdmin() then adminSend(L.CMD.PIT_RELEASE) end
    broadcastPhase()
  end
  if not me.pitWait then return end
  if pitReleased then
    me.pitWait = false
    me.state = L.S.RACING
    me.pitGoAt = gameS()
    notify(T('pitGo'), 5, rgbm.colors.green)
    return
  end
  -- wyjazd z alei przed zielonym światłem
  if not myCar.isInPitlane and not myCar.isInPit then
    me.pitWait = false
    me.state = L.S.RACING
    local p = L.parsePenalty(cfg.JUMP_START_PENALTY, cfg)
    chat(string.format(T('chatPit'), cfg.CHAT_PREFIX, myName(), penaltyText(p)))
    notify(T('pitEarly'), 8, rgbm.colors.red)
    applyPenalty(p)
  end
end

local function updateRacing(frameDt)
  updatePitRelease()
  updateDriveThrough(frameDt)
  updateStopGo(frameDt)
  -- czas reakcji w pierwszych 5 s po zgaszeniu świateł
  if me.reactionMs or me.jumpMs or me.late or not me.outPos or not lightsDoneAt then return end
  if gameS() - lightsDoneAt > 5 then return end
  local moved = L.slotOffset(myCar.position, me.outPos, myCar.look, myCar.side)
  if moved > 0.3 then
    me.reactionMs = math.floor(clockMs() - lightsOutAt)
    notify(T('reaction', me.reactionMs), 5, rgbm.colors.green)
    if not me.pitStart then reportReaction(me.reactionMs, false, false, false) end
    if cfg.REPORT_REACTION == 1 and not me.pitStart then
      chat(string.format(T('chatReaction'), cfg.CHAT_PREFIX .. 'R', mySlotNumber(), myName(), me.reactionMs))
    end
  end
end

local function updateAutoLights()
  if cfg.AUTO_LIGHTS ~= 1 or not isAdmin() or phase ~= L.P.FORMATION then return end
  local list, anyReady = {}, false
  for i = 0, sim.carsCount - 1 do
    local c = ac.getCar(i)
    if c and c.isConnected then
      local st
      if i == 0 then st = me.state
      elseif statuses[i] then
        -- status sprzed rozpoczęcia tego okrążenia formującego (np. sprzed przerwania startu) jest nieaktualny
        st = statuses[i].at >= auto.since and statuses[i].state or L.S.FORMATION
      end
      if st then
        list[#list + 1] = st
        if L.isReadyState(st) and st ~= L.S.PIT_START and st ~= L.S.NO_SLOT then anyReady = true end
      end
    end
  end
  local t = gameS()
  if anyReady and not auto.firstReadyAt then auto.firstReadyAt = t end
  local allReady = #list > 0
  for _, st in ipairs(list) do if not L.isReadyState(st) then allReady = false break end end
  if allReady then auto.readySince = auto.readySince or t else auto.readySince = nil end
  if L.autoLightsDue(list, t, auto.readySince, auto.firstReadyAt, cfg) then
    auto.firstReadyAt, auto.readySince = nil, nil
    adminSend(L.CMD.LIGHTS)
  end
end

local function debugValues()
  -- podgląd w aplikacji „Lua Debug” CSP (pomaga przy testach)
  ac.debug('FRSS wersja', VERSION)
  ac.debug('FRSS admin', isAdmin())
  ac.debug('FRSS faza', phase)
  ac.debug('FRSS stan', me.state)
  ac.debug('FRSS przejechane m', math.floor(me.traveled or 0))
  ac.debug('FRSS do pola m', me.dist and string.format('%.2f', me.dist) or '-')
  ac.debug('FRSS pole P', mySlotNumber())
end

function script.update(dt)
  debugValues()
  if sim.raceSessionType ~= ac.SessionType.Race then
    if phase ~= L.P.IDLE then phase = L.P.IDLE; me.state = L.S.NONE end
    return
  end
  if sim.currentSessionIndex ~= sessionIndex and sessionIndex ~= -1 then
    -- nowa sesja bez wywołania onSessionStart
    slots, statuses = {}, {}
    resetMe()
    phase = L.P.IDLE
  end
  sessionIndex = sim.currentSessionIndex

  local preStart = (sim.timeToSessionStart and sim.timeToSessionStart > 0) or sim.currentSessionTime < 0
  if preStart then
    updateGrid()
  elseif phase == L.P.GRID then
    freezeSlots()
    startFormation(false)
  elseif phase == L.P.IDLE then
    -- skrypt wczytany po starcie wyścigu: brak pól
    phase = L.P.RACING
    me.state = L.S.NO_SLOT
  elseif phase == L.P.FORMATION then
    updateFormation(dt)
    updateAutoLights()
  elseif phase == L.P.LIGHTS then
    updateLights()
  elseif phase == L.P.RACING then
    updateRacing(dt)
  end

  pushStatus(false)
end

-- Rysowanie pola na torze -------------------------------------------------------

-- kolory świecące (wartości > 1 = jaśniej niż biel, widać z daleka i w deszczu)
local COL_OK = rgbm(0.2, 3, 0.4, 0.8)
local COL_NEAR = rgbm(3, 2.2, 0.1, 0.8)
local COL_BAD = rgbm(3, 0.2, 0.1, 0.85)
local COL_IDLE = rgbm(0.3, 1.6, 3.5, 0.8)

local function slotColor()
  local st = me.state
  if st == L.S.IN_SLOT then return COL_OK end
  if st == L.S.OVERSHOOT_PEN or st == L.S.LATE then return COL_BAD end
  if st == L.S.OVERSHOOT or st == L.S.SHORT or st == L.S.WRONG_LANE then return COL_NEAR end
  if st == L.S.APPROACH and me.dist and math.abs(me.dist) < 15 then return COL_NEAR end
  return COL_IDLE
end

-- prostokątny pasek na asfalcie od punktu a do b o szerokości w
local function band(a, b, dirSide, w, col)
  local h = dirSide * (w / 2)
  render.quad(a - h, a + h, b + h, b - h, col)
end

local function bright(col, k)
  return rgbm(math.min(col.r * k, 8), math.min(col.g * k, 8), math.min(col.b * k, 8), 1)
end

function script.draw3D()
  if phase ~= L.P.FORMATION and phase ~= L.P.LIGHTS then return end
  local s = slots[0]
  if not s or me.pitStart then return end
  if phase == L.P.FORMATION and me.state == L.S.FORMATION then return end
  local y = (s.groundY or s.pos.y) + 0.05
  local base = vec3(s.pos.x, y, s.pos.z)
  local look = vec3(s.look.x, 0, s.look.z):normalize()
  local side = vec3(s.side.x, 0, s.side.z):normalize()
  local halfL = (s.size.z or 4.6) / 2
  local halfW = math.min((s.size.x or 2) / 2, 1.1) + 0.1
  local f, b, l, r = look * halfL, look * -halfL, side * -halfW, side * halfW
  render.setBlendMode(render.BlendMode.AlphaBlend)
  render.setDepthMode(render.DepthMode.ReadOnlyLessEqual)
  render.setCullMode(render.CullMode.None)
  local col = slotColor()
  -- z daleka pole pulsuje, żeby łatwiej je było wypatrzyć
  local far = me.dist and me.dist < -25
  if far then
    local k = 0.65 + 0.35 * math.sin(sim.gameTime * 6)
    col = rgbm(col.r * k, col.g * k, col.b * k, col.mult)
  end
  local edge = bright(col, 2)
  -- wypełnienie pola
  render.quad(base + b + l, base + b + r, base + f + r, base + f + l, col)
  -- gruba obwódka (25 cm)
  local t = 0.08
  band(base + b + l, base + f + l, side, t, edge)
  band(base + b + r, base + f + r, side, t, edge)
  band(base + b + l, base + b + r, look, t, edge)
  -- linia przodu pola: tu ma być przód auta (biała, gruba)
  band(base + f + l, base + f + r, look, 0.12, rgbm(4, 4, 4, 1))
  -- brama nad przodem pola: dwa wysokie słupki i poprzeczka, widoczne z daleka
  local up = vec3(0, 1.5, 0)
  for _, corner in ipairs({ base + f + l, base + f + r }) do
    band(corner, corner + up, look, 0.06, edge)
    band(corner, corner + up, side, 0.06, edge)
  end
  band(base + f + l + up, base + f + r + up, look, 0.08, edge)
  band(base + f + l + up, base + f + r + up, vec3(0, 1, 0), 0.08, edge)
  -- granica kary za przestrzelenie (czerwona)
  local w = look * (halfL + cfg.GRID_WARNING_M)
  band(base + w + l, base + w + r, look, 0.1, rgbm(4, 0.2, 0.1, 1))
  -- strzałka do środka pola, gdy auto stoi obok
  if me.state == L.S.WRONG_LANE then
    local from = vec3(myCar.position.x, y, myCar.position.z)
    local to = base + look * L.clamp(me.long or 0, -halfL, halfL)
    band(from, to, look, 0.1, rgbm(4, 3, 0.2, 1))
  end
  pcall(render.debugText, base + look * halfL + vec3(0, 2.0, 0), 'P' .. tostring(s.gridPos), rgbm(4, 4, 4, 1), 3.5)
  render.setCullMode(render.CullMode.Back)
  render.setDepthMode(render.DepthMode.Normal)
  render.setBlendMode(render.BlendMode.Opaque)
end

-- HUD -----------------------------------------------------------------------------

-- Pozycja i wielkość napisów (kierowca może je przesunąć, zapamiętywane na jego komputerze).
local HUD_DEFAULT = { x = 0.5, y = 0.14, scale = 1.0 }
local hud
do
  local ok, st = pcall(ac.storage, { x = 0.5, y = 0.14, scale = 1.0 }, 'frss_hud_')
  if ok and st then hud = st else hud = { x = 0.5, y = 0.14, scale = 1.0 } end
end
local settingsSeenAt = -100
local dragging = false

local function screen()
  local scale = ac.getUI().uiScale or 1
  return sim.windowWidth / scale, sim.windowHeight / scale
end

-- napis wyśrodkowany w punkcie HUD (dy – przesunięcie w dół)
local function banner(text, dy, size, color, bg)
  local w, h = screen()
  local k = hud.scale or 1
  size = size * k
  local cx, y = w * hud.x, h * hud.y + dy * k
  local ts = ui.measureDWriteText(text, size)
  local pad = vec2(18 * k, 8 * k)
  local p1 = vec2(cx - ts.x / 2 - pad.x, y - pad.y)
  local p2 = vec2(cx + ts.x / 2 + pad.x, y + ts.y + pad.y)
  ui.drawRectFilled(p1, p2, bg or rgbm(0, 0, 0, 0.6), 6)
  ui.dwriteDrawText(text, size, vec2(cx - ts.x / 2, y), color or rgbm.colors.white)
  return p1, p2
end

local function drawLights()
  local lit, out = L.lightsState(clockMs(), lightsT0, cfg.LIGHTS_COUNT, cfg.LIGHTS_INTERVAL_MS, lightsHold)
  if out then return end
  local w = screen()
  local n = cfg.LIGHTS_COUNT
  local r, gap = 26, 18
  local total = n * (2 * r) + (n - 1) * gap
  local x0, y = w / 2 - total / 2 + r, 90
  ui.drawRectFilled(vec2(x0 - r - 14, y - r - 14), vec2(x0 + total - r + 14, y + r + 14), rgbm(0, 0, 0, 0.75), 10)
  for i = 1, n do
    local c = vec2(x0 + (i - 1) * (2 * r + gap), y)
    local on = i <= lit
    ui.drawCircleFilled(c, r, on and rgbm(1, 0.05, 0.03, 1) or rgbm(0.18, 0.18, 0.18, 1), 32)
  end
end

local function drawPreview()
  local p1, p2 = banner(T('preview'), 0, 34, rgbm.colors.yellow, rgbm(0, 0, 0, 0.8))
  -- przeciąganie myszką
  local m = ui.mousePos()
  local inside = m.x >= p1.x and m.x <= p2.x and m.y >= p1.y and m.y <= p2.y
  if ui.mouseDown(0) then
    if inside or dragging then
      dragging = true
      local w, h = screen()
      local d = ui.mouseDelta()
      hud.x = L.clamp(hud.x + d.x / w, 0.05, 0.95)
      hud.y = L.clamp(hud.y + d.y / h, 0.02, 0.95)
    end
  else
    dragging = false
  end
end

-- światło wyjazdu z alei dla startujących z boksu
local function drawPitLight()
  local green = not me.pitWait and me.pitGoAt and gameS() - me.pitGoAt < 8
  if not me.pitWait and not green then return end
  local w = screen()
  local r, y = 30, 90
  ui.drawRectFilled(vec2(w / 2 - r - 14, y - r - 14), vec2(w / 2 + r + 14, y + r + 14), rgbm(0, 0, 0, 0.75), 10)
  ui.drawCircleFilled(vec2(w / 2, y), r, green and rgbm(0.1, 1, 0.2, 1) or rgbm(1, 0.05, 0.03, 1), 32)
  banner(T(green and 'pitGo' or 'pitWait'), 0, 26, green and rgbm(0.2, 1, 0.3, 1) or rgbm.colors.white)
end

local function drawDriveThroughInfo()
  local sg = me.sg
  if sg and not sg.done and not sg.go then
    if myCar.isInPit and myCar.speedKmh < 1 then
      banner(T('sgCount', math.max(0, math.ceil(sg.secs - sg.stopTime))), 0, 40, rgbm.colors.white, rgbm(0.75, 0, 0, 0.85))
    else
      local leftSg = L.dtLapsLeft(sg.laps, sg.startLap, myCar.lapCount)
      if leftSg <= 1 then banner(T('sgLast'), 0, 22, rgbm.colors.white, rgbm(0.75, 0, 0, 0.85))
      else banner(T('sgInfo', sg.secs, leftSg), 0, 20, rgbm.colors.white, rgbm(0.6, 0, 0, 0.7)) end
    end
    return
  end
  local dt = me.dt
  if not dt or dt.done then return end
  local left = L.dtLapsLeft(dt.laps, dt.startLap, myCar.lapCount)
  if left <= 1 then
    banner(T('penDTLast'), 0, 22, rgbm.colors.white, rgbm(0.75, 0, 0, 0.85))
  else
    banner(T('penDTInfo', left), 0, 20, rgbm.colors.white, rgbm(0.6, 0, 0, 0.7))
  end
end

function script.drawUI()
  local previewOn = gameS() - settingsSeenAt < 0.3
  if (phase == L.P.IDLE or phase == L.P.GRID) and not previewOn then return end
  pcall(ui.pushDWriteFont, 'Segoe UI;Weight=Bold')

  if previewOn then
    drawPreview()
  else
    if phase == L.P.LIGHTS then drawLights() end

    if phase == L.P.FORMATION or phase == L.P.LIGHTS then
      local st = me.state
      if st == L.S.PIT_START then
        banner(T('pitStart'), 0, 20, rgbm.colors.yellow)
      elseif st == L.S.PIT_OUT then
        banner(T('pitOut'), 0, 22, rgbm.colors.yellow)
      elseif st == L.S.NO_SLOT then
        banner(T('noSlot'), 0, 20, rgbm.colors.yellow)
      elseif st == L.S.FORMATION then
        local head = cfg.FORMATION_SPEED_KMH > 0 and T('formationLimit', cfg.FORMATION_SPEED_KMH) or T('formation')
        banner(head .. '   ·   ' .. T('yourSlot', mySlotNumber()), 0, 20)
      elseif st == L.S.APPROACH then
        local d = -(me.dist or 0)
        if d > 20 then banner(T('toGo', mySlotNumber(), math.floor(d + 0.5)), 0, 34)
        elseif d > 0 then banner(T('toGoNear', mySlotNumber(), d), 0, 40, rgbm.colors.yellow)
        else banner(T('overshoot', -d), 0, 34, rgbm.colors.yellow) end
      elseif st == L.S.IN_SLOT then
        banner(T('stop'), 0, 34, rgbm(0.2, 1, 0.3, 1))
      elseif st == L.S.SHORT then
        banner(T('short', -me.long), 0, 30, rgbm.colors.yellow)
      elseif st == L.S.WRONG_LANE then
        local off = math.abs(me.lat or 0)
        if me.toSlotRight then
          banner(T(me.toSlotRight > 0 and 'moveRight' or 'moveLeft', off), 0, 34, rgbm.colors.yellow)
        else
          banner(T('wrongLane', off), 0, 30, rgbm.colors.yellow)
        end
      elseif st == L.S.OVERSHOOT then
        banner(T('overshoot', me.long), 0, 30, rgbm.colors.yellow)
      elseif st == L.S.OVERSHOOT_PEN then
        banner(T('overshootPen', me.maxLong), 0, 30, rgbm.colors.white, rgbm(0.7, 0, 0, 0.8))
      elseif st == L.S.LATE then
        banner(T('late'), 0, 24, rgbm.colors.yellow)
      elseif st == L.S.DNS then
        banner(T('dns'), 0, 24, rgbm.colors.yellow)
      end
      if phase == L.P.LIGHTS and st ~= L.S.LATE then
        banner(T('waitLights'), 60, 18)
      end
    elseif phase == L.P.RACING then
      drawPitLight()
      drawDriveThroughInfo()
    end

    if me.notice and gameS() < me.noticeUntil then
      banner(me.notice, 110, 24, me.noticeColor)
    end
  end
  pcall(ui.popDWriteFont)
end

-- Panel admina i przełącznik języka ----------------------------------------------

local function reactionText()
  local list = {}
  for _, e in pairs(reactions) do list[#list + 1] = e end
  local track = (pcall(ac.getTrackName) and ac.getTrackName()) or ''
  local title = string.format(L.text(lang, 'listTitle'), track, os.date('%d.%m.%Y %H:%M'))
  return L.formatReactions(lang, list, title), #list
end

copyReactions = function()
  local text = reactionText()
  if not pcall(ac.setClipboardText, text) then pcall(ui.setClipboardText, text) end
  pcall(ui.toast, ui.Icons.Copy or ui.Icons.Settings, T('copied'))
end

local function stateName(st)
  local names = L.text(lang, 'stateNames')
  return names[st] or tostring(st)
end

local function adminUI()
  ui.text('v' .. VERSION)
  ui.text(T('phase', L.text(lang, 'phaseNames')[phase] or '?'))
  ui.text(T('auto', cfg.AUTO_LIGHTS == 1 and T('on') or T('off')))
  ui.separator()
  if ui.button(T('btnLights')) and phase == L.P.FORMATION then adminSend(L.CMD.LIGHTS) end
  if ui.button(T('btnAbort')) then adminSend(L.CMD.ABORT) end
  if ui.button(T('btnSkip')) then adminSend(L.CMD.SKIP_FORMATION) end
  ui.separator()

  local total, ready = 0, 0
  for i = 0, sim.carsCount - 1 do
    local c = ac.getCar(i)
    if c and c.isConnected then
      total = total + 1
      local st, off, pend
      if i == 0 then
        st, off, pend = me.state, (me.long or 0), me.pending and 1 or 0
      elseif statuses[i] then
        st, off, pend = statuses[i].state, statuses[i].offsetCm / 100, statuses[i].pending
      end
      if st and L.isReadyState(st) then ready = ready + 1 end
      local slot = slots[i] and ('P' .. slots[i].gridPos) or '--'
      local line = string.format('%s  %s  ', slot, ac.getDriverName(i) or '?')
      if st then
        line = line .. stateName(st)
        if st >= L.S.APPROACH and st <= L.S.OVERSHOOT_PEN then line = line .. string.format(' (%+.1f m)', off) end
        if pend and pend > 0 then line = line .. ' · ' .. T('pending') end
      else
        line = line .. T('noData')
      end
      ui.text(line)
      if pend and pend > 0 and phase ~= L.P.RACING then
        ui.sameLine()
        if ui.button(T('btnPardon') .. '##p' .. i) then adminSend(L.CMD.PARDON, c.sessionID) end
      end
    end
  end
  ui.separator()
  ui.text(T('ready', ready, total))
  ui.text(T('chatHelp'))
  local _, count = reactionText()
  if count > 0 then
    ui.separator()
    ui.text(T('reactHeader', count))
    local text = reactionText()
    for line in text:gmatch('[^\n]+') do ui.text(line) end
    if ui.button(T('btnCopy')) then copyReactions() end
  end
  return false
end

ui.registerOnlineExtra(ui.Icons.TrafficLight, L.text('PL', 'adminTitle'),
  function() return isAdmin() end, adminUI, nil,
  ui.OnlineExtraFlags.Tool, ui.WindowFlags.None, vec2(420, 540))

local function settingsUI()
  settingsSeenAt = gameS()
  if ui.button(T('setLang', lang)) then lang = lang == 'PL' and 'EN' or 'PL' end
  ui.separator()
  local v
  v = ui.slider('##x', hud.x * 100, 5, 95, T('setPosX') .. ': %.0f%%')
  if v ~= hud.x * 100 then hud.x = v / 100 end
  v = ui.slider('##y', hud.y * 100, 2, 95, T('setPosY') .. ': %.0f%%')
  if v ~= hud.y * 100 then hud.y = v / 100 end
  v = ui.slider('##s', hud.scale * 100, 50, 200, T('setScale') .. ': %.0f%%')
  if v ~= hud.scale * 100 then hud.scale = v / 100 end
  ui.text(T('setHint'))
  if ui.button(T('setReset')) then
    hud.x, hud.y, hud.scale = HUD_DEFAULT.x, HUD_DEFAULT.y, HUD_DEFAULT.scale
  end
  return false
end

ui.registerOnlineExtra(ui.Icons.Settings, L.text('PL', 'settingsTitle'),
  function() return true end, settingsUI, nil,
  ui.OnlineExtraFlags.Tool, ui.WindowFlags.None, vec2(360, 220))

log('v' .. VERSION .. ' start')

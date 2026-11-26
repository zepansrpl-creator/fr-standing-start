-- FR Standing Start
-- Start z miejsca po okrążeniu formującym dla serwerów Assetto Corsa (skrypt online CSP).
-- Standing start after a formation lap for Assetto Corsa servers (CSP online script).
--
-- Licencja MIT (c) 2026 Maciej Szczepaniak – github.com/zepansrpl-creator/fr-standing-start
-- Konfiguracja: patrz README.md (sekcja [FR_STANDING_START] w CSP Extra Options serwera).

local VERSION = '0.1.4'

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
  GRID_WARNING_M = 5.0,        -- przestrzelenie do tej wartości = tylko ostrzeżenie, dalej kara
  LATERAL_TOLERANCE_M = 1.0,   -- tyle można stać obok środka pola (w lewo/prawo) bez uwag
  LATERAL_PENALTY_M = 2.0,     -- stoi dalej obok pola przy zapaleniu świateł = kara jak za przestrzelenie
  ALLOW_REVERSE = 0,           -- 0: liczy się najdalszy punkt (cofanie nie kasuje przestrzelenia)
  OVERSHOOT_PENALTY = 'DRIVE_THROUGH', -- DRIVE_THROUGH / TELEPORT / WARNING
  JUMP_START_PENALTY = 'DRIVE_THROUGH',
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
}

-- Fazy wyścigu (wspólne dla wszystkich, sterowane startem z gry i komendami admina).
L.P = { IDLE = 0, GRID = 1, FORMATION = 2, LIGHTS = 3, RACING = 4 }

-- Komendy admina.
L.CMD = { LIGHTS = 1, ABORT = 2, PARDON = 3, SKIP_FORMATION = 4 }

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
function L.isApproaching(traveled, trackLen, signedDist, cfg)
  return traveled > trackLen * 0.5 and signedDist > -cfg.APPROACH_ZONE_M and signedDist < 60
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
    or s == L.S.PIT_START or s == L.S.NO_SLOT or s == L.S.WRONG_LANE
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
  return { kind = 'warning', param = 0 }
end

-- Która z dwóch kar jest surowsza (gdy kierowca dostał obie, wykonujemy jedną).
local severity = { warning = 0, dt = 1, teleport = 2 }
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
    pitStart = 'START Z ALEI SERWISOWEJ – wyjedź dopiero po zgaszeniu świateł',
    noSlot = 'Brak pola startowego (dołączyłeś po starcie) – startuj z alei',
    toGo = 'P%d · %d m',
    toGoNear = 'P%d · %.1f m',
    stop = 'STOP – STOISZ NA POLU',
    short = 'Podjedź jeszcze %.1f m',
    overshoot = 'Za daleko o %.1f m',
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
    chatLate = '%s P%d %s: nie stał na polu przy zapaleniu świateł',
    chatPit = '%s %s: wyjazd z alei przed zgaszeniem świateł → %s',
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
      'za daleko', 'PRZESTRZELIŁ (kara)', 'aleja serwisowa', 'brak pola', 'wyścig', 'spóźniony', 'obok pola',
    },
    pending = 'kara czeka',
    wrongLane = 'STAŃ NA ŚRODKU POLA – jesteś obok o %.1f m',
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
    pitStart = 'PIT LANE START – leave only after the lights go out',
    noSlot = 'No grid slot (joined after the start) – start from the pit lane',
    toGo = 'P%d · %d m',
    toGoNear = 'P%d · %.1f m',
    stop = 'STOP – YOU ARE IN YOUR SLOT',
    short = 'Move up %.1f m',
    overshoot = 'Too far by %.1f m',
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
    chatLate = '%s P%d %s: not in slot when the lights came on',
    chatPit = '%s %s: left the pit lane before lights out → %s',
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
      'too far', 'OVERSHOT (penalty)', 'pit lane', 'no slot', 'race', 'late', 'beside slot',
    },
    pending = 'penalty pending',
    wrongLane = 'MOVE TO THE CENTRE OF THE SLOT – you are %.1f m off',
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

function L.penaltyName(lang, pen)
  if pen.kind == 'dt' then return L.text(lang, 'penNameDT') end
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
local auto = { readySince = nil, firstReadyAt = nil }

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
        pit = c.isInPitlane,
        size = c.aabbSize and c.aabbSize:clone() or vec3(2, 1.3, 4.6),
      }
    end
  end
end

local function freezeSlots()
  for _, s in pairs(slots) do s.groundY = groundY(s.pos) end
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
  if me.pitStart then me.state = L.S.PIT_START
  elseif slots[0] then me.state = L.S.FORMATION
  else me.state = L.S.NO_SLOT end
  auto.readySince, auto.firstReadyAt = nil, nil
  if extraLap then
    notify(T('aborted'), 8, rgbm.colors.yellow)
    -- kara za przestrzelenie z przerwanego startu przepada, falstart też
    me.pending = nil
    me.pardoned = false
  end
  log('faza: formujące' .. (extraLap and ' (dodatkowe)' or ''))
end

local function startLights(t0, hold)
  if phase ~= L.P.FORMATION then return end
  phase = L.P.LIGHTS
  lightsT0, lightsHold = t0, hold
  local _, _, outAt = L.lightsState(clockMs(), t0, cfg.LIGHTS_COUNT, cfg.LIGHTS_INTERVAL_MS, hold)
  lightsOutAt = outAt
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
    chat(string.format(T('chatLate'), cfg.CHAT_PREFIX, n, name))
  end
  applyPenalty(pen)
  me.pending = nil
  me.state = L.S.RACING
  pushStatus(true)
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
  elseif data.cmd == L.CMD.SKIP_FORMATION then
    if phase == L.P.FORMATION then me.traveled = sim.trackLengthM end
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
local adminByChat = false
local function isAdmin() return sim.isAdmin or adminByChat end

L.CHAT_COMMANDS = {
  swiatla = L.CMD.LIGHTS, ['światła'] = L.CMD.LIGHTS, lights = L.CMD.LIGHTS,
  przerwij = L.CMD.ABORT, abort = L.CMD.ABORT,
  pomin = L.CMD.SKIP_FORMATION, ['pomiń'] = L.CMD.SKIP_FORMATION, skip = L.CMD.SKIP_FORMATION,
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
      if c then adminSend(c) end
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
  me.pitStart = myCar.isInPitlane
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

  if me.pitStart or not slots[0] then
    me.state = me.pitStart and L.S.PIT_START or L.S.NO_SLOT
    return
  end
  -- wjazd do alei w trakcie formującego = start z alei
  if myCar.isInPitlane and me.traveled > 200 then
    me.pitStart = true
    me.state = L.S.PIT_START
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

  if L.isApproaching(me.traveled, trackLen, dist, cfg) then
    me.long, me.lat = dist, lat
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
    if not me.wasStopped and not me.pitStart and slots[0] then
      me.late = true
      me.state = L.S.LATE
      notify(T('late'), 6, rgbm.colors.yellow)
    end
  end
  -- falstart
  if me.lightsStartPos and not me.jumpMs and (me.wasStopped or me.pitStart) then
    local moved
    if me.pitStart then
      moved = (not myCar.isInPitlane) and 99 or 0
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

local function updateDriveThrough()
  local dt = me.dt
  if not dt or dt.done then return end
  if myCar.isInPitlane then
    dt.inPit = true
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

local function updateRacing()
  updateDriveThrough()
  -- czas reakcji w pierwszych 5 s po zgaszeniu świateł
  if me.reactionMs or me.jumpMs or me.late or not me.outPos or not lightsDoneAt then return end
  if gameS() - lightsDoneAt > 5 then return end
  local moved = L.slotOffset(myCar.position, me.outPos, myCar.look, myCar.side)
  if moved > 0.3 then
    me.reactionMs = math.floor(clockMs() - lightsOutAt)
    notify(T('reaction', me.reactionMs), 5, rgbm.colors.green)
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
      local st = i == 0 and me.state or (statuses[i] and statuses[i].state)
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
    updateRacing()
  end

  pushStatus(false)
end

-- Rysowanie pola na torze -------------------------------------------------------

local COL_OK = rgbm(0.1, 1, 0.25, 0.55)
local COL_NEAR = rgbm(1, 0.8, 0.05, 0.55)
local COL_BAD = rgbm(1, 0.1, 0.05, 0.6)
local COL_IDLE = rgbm(0.2, 0.6, 1, 0.45)

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
  return rgbm(math.min(col.r * k, 4), math.min(col.g * k, 4), math.min(col.b * k, 4), 1)
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
  local edge = bright(col, 2.5)
  -- wypełnienie pola
  render.quad(base + b + l, base + b + r, base + f + r, base + f + l, col)
  -- gruba obwódka (25 cm)
  local t = 0.25
  band(base + b + l, base + f + l, side, t, edge)
  band(base + b + r, base + f + r, side, t, edge)
  band(base + b + l, base + b + r, look, t, edge)
  -- linia przodu pola: tu ma być przód auta (biała, gruba)
  band(base + f + l, base + f + r, look, 0.35, rgbm(4, 4, 4, 1))
  -- słupki na przednich narożnikach, widoczne z daleka
  local up = vec3(0, 1.2, 0)
  for _, corner in ipairs({ base + f + l, base + f + r }) do
    band(corner, corner + up, look, 0.12, rgbm(4, 4, 4, 1))
  end
  -- granica kary za przestrzelenie (czerwona)
  local w = look * (halfL + cfg.GRID_WARNING_M)
  band(base + w + l, base + w + r, look, 0.3, rgbm(4, 0.2, 0.1, 1))
  -- strzałka do środka pola, gdy auto stoi obok
  if me.state == L.S.WRONG_LANE then
    local from = vec3(myCar.position.x, y, myCar.position.z)
    local to = base + look * L.clamp(me.long or 0, -halfL, halfL)
    band(from, to, look, 0.3, rgbm(4, 3, 0.2, 1))
  end
  pcall(render.debugText, base + look * halfL + vec3(0, 1.6, 0), 'P' .. tostring(s.gridPos), rgbm(1, 1, 1, 1), 2.5)
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

local function drawDriveThroughInfo()
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
        banner(T('wrongLane', math.abs(me.lat or 0)), 0, 30, rgbm.colors.yellow)
      elseif st == L.S.OVERSHOOT then
        banner(T('overshoot', me.long), 0, 30, rgbm.colors.yellow)
      elseif st == L.S.OVERSHOOT_PEN then
        banner(T('overshootPen', me.maxLong), 0, 30, rgbm.colors.white, rgbm(0.7, 0, 0, 0.8))
      elseif st == L.S.LATE then
        banner(T('late'), 0, 24, rgbm.colors.yellow)
      end
      if phase == L.P.LIGHTS and st ~= L.S.LATE then
        banner(T('waitLights'), 60, 18)
      end
    elseif phase == L.P.RACING then
      drawDriveThroughInfo()
    end

    if me.notice and gameS() < me.noticeUntil then
      banner(me.notice, 110, 24, me.noticeColor)
    end
  end
  pcall(ui.popDWriteFont)
end

-- Panel admina i przełącznik języka ----------------------------------------------

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

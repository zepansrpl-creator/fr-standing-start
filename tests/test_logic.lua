-- Testy czystej logiki FR Standing Start. Uruchom: luajit tests/test_logic.lua
FRSS_TEST = true
local L = dofile('fr_standing_start.lua')

local pass, fail = 0, 0
local function check(name, cond)
  if cond then pass = pass + 1 else fail = fail + 1; print('FAIL: ' .. name) end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

local cfg = L.readConfig(nil)

-- splineDelta
check('splineDelta prosty', near(L.splineDelta(0.3, 0.1), 0.2))
check('splineDelta przez linię mety (przód)', near(L.splineDelta(0.02, 0.98), 0.04))
check('splineDelta przez linię mety (tył)', near(L.splineDelta(0.98, 0.02), -0.04))

-- travelDelta
check('travelDelta normalny', near(L.travelDelta(0.10, 0.11, 4000), 40))
check('travelDelta przez metę', near(L.travelDelta(0.995, 0.005, 4000), 40))
check('travelDelta ignoruje teleport', L.travelDelta(0.1, 0.6, 4000) == 0)

-- slotOffset: pole skierowane wzdłuż +z
local slot, look, side = { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 1 }, { x = 1, y = 0, z = 0 }
local long, lat = L.slotOffset({ x = 0.3, y = 0, z = 1.5 }, slot, look, side)
check('slotOffset wzdłużne', near(long, 1.5))
check('slotOffset poprzeczne', near(lat, 0.3))
long = L.slotOffset({ x = 0, y = 0, z = -12 }, slot, look, side)
check('slotOffset przed polem ujemne', near(long, -12))

-- signedSlotDistance: blisko → 3D, daleko → splajn
check('dystans blisko z 3D', near(L.signedSlotDistance(0.990, 0.991, 4000, -3.9), -3.9))
check('dystans daleko ze splajnu', near(L.signedSlotDistance(0.90, 0.99, 4000, -999), -360, 1e-6))

-- isApproaching
check('nie dojazd na początku formującego', not L.isApproaching(10, 4000, -3990, cfg))
check('dojazd 250 m przed polem', L.isApproaching(3750, 4000, -250, cfg))
check('nie dojazd 400 m przed polem', not L.isApproaching(3600, 4000, -400, cfg))
check('dojazd po przestrzeleniu', L.isApproaching(4003, 4000, 3, cfg))

-- classifySlot
local S = L.S
check('jedzie → dojazd', L.classifySlot(-5, -5, 20, cfg) == S.APPROACH)
check('stoi w tolerancji → na polu', L.classifySlot(0.3, 0.3, 0, cfg) == S.IN_SLOT)
check('stoi za krótko', L.classifySlot(-1.2, -1.2, 0, cfg) == S.SHORT)
check('stoi 1.5 m za daleko → ostrzeżenie', L.classifySlot(1.5, 1.5, 0, cfg) == S.OVERSHOOT)
check('stoi 9.5 m za daleko → ostrzeżenie', L.classifySlot(9.5, 9.5, 0, cfg) == S.OVERSHOOT)
check('10.5 m za daleko → kara nawet w ruchu', L.classifySlot(10.5, 10.5, 3, cfg) == S.OVERSHOOT_PEN)
check('cofnięcie poprawia małe przestrzelenie', L.classifySlot(0.1, 0.6, 0, cfg) == S.IN_SLOT)
check('cofnięcie z 3 m do 1 m = ostrzeżenie 1 m', L.classifySlot(1.0, 3.0, 0, cfg) == S.OVERSHOOT)
check('cofnięcie nie kasuje przestrzelenia ponad 10 m', L.classifySlot(0.0, 10.6, 0, cfg) == S.OVERSHOOT_PEN)
local cfgRev = L.readConfig(function(k, v) if k == 'ALLOW_REVERSE' then return 1 end end)
check('ALLOW_REVERSE=1: cofnięcie poprawia', L.classifySlot(0.0, 10.6, 0, cfgRev) == S.IN_SLOT)
check('stoi obok pola 1.5 m', L.classifySlot(0.1, 0.1, 0, cfg, 1.5) == S.WRONG_LANE)
check('stoi obok pola z drugiej strony', L.classifySlot(0.1, 0.1, 0, cfg, -1.5) == S.WRONG_LANE)
check('0.4 m obok = na polu', L.classifySlot(0.1, 0.1, 0, cfg, 0.4) == S.IN_SLOT)
check('0.7 m obok = obok pola', L.classifySlot(0.1, 0.1, 0, cfg, 0.7) == S.WRONG_LANE)
check('obok pola w ruchu = dojazd', L.classifySlot(-3, -3, 10, cfg, 2.5) == S.APPROACH)
check('kara za stanie obok > 2 m', L.isLanePenalty(S.WRONG_LANE, -2.4, cfg))
check('bez kary 1.5 m obok', not L.isLanePenalty(S.WRONG_LANE, 1.5, cfg))
check('obok pola liczy się jako gotowy', L.isReadyState(S.WRONG_LANE))
check('DT: 3 okrążenia na start', L.dtLapsLeft(3, 0, 0) == 3)
check('DT: po 2 okrążeniach zostało 1', L.dtLapsLeft(3, 1, 3) == 1)
check('domyślnie kara od 10 m', cfg.GRID_WARNING_M == 10)
check('tolerancja w bok 0.5 m', cfg.LATERAL_TOLERANCE_M == 0.5)

-- lightsState: 5 świateł co 1000 ms, przerwa 1500 ms, start t0=10000
local lit, out, outAt = L.lightsState(9000, 10000, 5, 1000, 1500)
check('przed światłami 0', lit == 0 and not out)
check('czas zgaszenia', outAt == 10000 + 4000 + 1500)
lit = L.lightsState(10000, 10000, 5, 1000, 1500); check('pierwsze światło', lit == 1)
lit = L.lightsState(12500, 10000, 5, 1000, 1500); check('trzy światła', lit == 3)
lit, out = L.lightsState(15200, 10000, 5, 1000, 1500); check('wszystkie przed zgaszeniem', lit == 5 and not out)
lit, out = L.lightsState(15500, 10000, 5, 1000, 1500); check('zgaszone', out)

-- falstart
check('mały ruch to nie falstart', not L.isJumpStart(0.3, cfg))
check('ruch 0.6 m to falstart', L.isJumpStart(0.6, cfg))

-- kary
check('domyślna kara drive-through', L.parsePenalty(cfg.OVERSHOOT_PENALTY, cfg).kind == 'dt')
check('drive-through 3 okrążenia', L.parsePenalty('DRIVE_THROUGH', cfg).param == 3)
check('teleport', L.parsePenalty('teleport', cfg).kind == 'teleport')
check('nieznana = ostrzeżenie', L.parsePenalty('cokolwiek', cfg).kind == 'warning')
local dt, tp = L.parsePenalty('DT', cfg), L.parsePenalty('TELEPORT', cfg)
check('surowsza kara', L.stronger(dt, tp) == tp and L.stronger(tp, dt) == tp and L.stronger(nil, dt) == dt)

-- automat świateł
local cfgA = L.readConfig(function(k) if k == 'AUTO_LIGHTS' then return 1 end end)
check('automat: nie wszyscy gotowi', not L.autoLightsDue({ S.IN_SLOT, S.APPROACH }, 100, nil, 99, cfgA))
check('automat: wszyscy, za krótko', not L.autoLightsDue({ S.IN_SLOT, S.PIT_START }, 100, 98, 90, cfgA))
check('automat: wszyscy 5 s', L.autoLightsDue({ S.IN_SLOT, S.OVERSHOOT }, 100, 95, 90, cfgA))
check('automat: limit czasu', L.autoLightsDue({ S.IN_SLOT, S.APPROACH }, 200, nil, 100, cfgA))

-- konfiguracja
local c2 = L.readConfig(function(k, v)
  if k == 'LANGUAGE' then return 'en' end
  if k == 'FORMATION_SPEED_KMH' then return '100' end
  if k == 'HOLD_MAX_MS' then return 10 end
  if k == 'LIGHTS_COUNT' then return 50 end
end)
check('język EN', c2.LANGUAGE == 'EN')
check('liczba z tekstu', c2.FORMATION_SPEED_KMH == 100)
check('HOLD_MAX >= HOLD_MIN', c2.HOLD_MAX_MS >= c2.HOLD_MIN_MS)
check('max 10 świateł', c2.LIGHTS_COUNT == 10)

-- teksty: każdy klucz PL ma odpowiednik EN i formaty mają te same %
for k, v in pairs(L.TEXT.PL) do
  local e = L.TEXT.EN[k]
  check('tekst EN: ' .. k, e ~= nil)
  if type(v) == 'string' and type(e) == 'string' then
    local fp, fe = '', ''
    for m in v:gmatch('%%[%+%d%.]*[sdf]') do fp = fp .. m end
    for m in e:gmatch('%%[%+%d%.]*[sdf]') do fe = fe .. m end
    check('formaty PL/EN: ' .. k, fp == fe)
  end
end

-- lista reakcji
local txt = L.formatReactions('PL', {
  { name = 'B', slot = 2, ms = 300 }, { name = 'A', slot = 1, ms = 210 },
  { name = 'C', slot = 3, jump = true, jumpMs = 90 }, { name = 'D', slot = 4, pit = true },
}, 'Tytuł')
check('lista: tytuł pogrubiony', txt:find('^%*%*Tytuł%*%*') ~= nil)
check('lista: kolejność wg czasu', txt:find('1%. A %(P1%) – 0%.210 s') and txt:find('2%. B %(P2%) – 0%.300 s'))
check('lista: falstart', txt:find('C %(P3%) – FALSTART %(90 ms') ~= nil)
check('lista: start z alei', txt:find('D %(P4%) – start z alei') ~= nil)

-- kolejność pól z położenia
local order = L.gridOrder({ 0.975, 0.980, 0.970, 0.985 })
check('kolejność pól: najbliżej linii = P1', order[1] == 4 and order[2] == 2 and order[3] == 1 and order[4] == 3)
local order2 = L.gridOrder({ 0.995, 0.002, 0.990 })
check('kolejność pól przez linię mety', order2[1] == 2 and order2[2] == 1 and order2[3] == 3)
check('minął punkt', L.passedPoint(0.31, 0.30) and not L.passedPoint(0.29, 0.30))
check('kara za spóźnienie > 20 m = stop & go', L.latePenalty(-35, cfg).kind == 'sg')
check('kara za spóźnienie < 20 m = DT', L.latePenalty(-8, cfg).kind == 'dt')
check('stop & go 10 s', L.parsePenalty('STOP_GO', cfg).param == 10)
check('stop & go surowszy niż DT', L.stronger(L.parsePenalty('DT', cfg), L.parsePenalty('SG', cfg)).kind == 'sg')
check('kara za spóźnienie domyślnie DT', L.parsePenalty(cfg.LATE_PENALTY, cfg).kind == 'dt')

print(string.format('logika: pass=%d fail=%d', pass, fail))
os.exit(fail == 0 and 0 or 1)

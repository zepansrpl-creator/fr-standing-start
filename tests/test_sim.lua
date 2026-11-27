-- Symulacja wyścigu z atrapą API CSP: sprawdza, że skrypt przechodzi przez wszystkie fazy
-- bez błędów i podejmuje właściwe decyzje. Uruchom: luajit tests/test_sim.lua

local pass, fail = 0, 0
local function check(name, cond)
  if cond then pass = pass + 1 else fail = fail + 1; print('FAIL: ' .. name) end
end

---------------------------------------------------------------- atrapy typów
local vec3mt = {}
vec3mt.__index = vec3mt
function vec3(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vec3mt) end
vec3mt.__add = function(a, b) return vec3(a.x + b.x, a.y + b.y, a.z + b.z) end
vec3mt.__sub = function(a, b) return vec3(a.x - b.x, a.y - b.y, a.z - b.z) end
vec3mt.__mul = function(a, b)
  if type(a) == 'number' then a, b = b, a end
  return vec3(a.x * b, a.y * b, a.z * b)
end
vec3mt.__unm = function(a) return vec3(-a.x, -a.y, -a.z) end
function vec3mt:clone() return vec3(self.x, self.y, self.z) end
function vec3mt:normalize()
  local l = math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2)
  if l > 0 then self.x, self.y, self.z = self.x / l, self.y / l, self.z / l end
  return self
end
local vec2mt = {}
vec2mt.__index = vec2mt
function vec2(x, y) return setmetatable({ x = x or 0, y = y or 0 }, vec2mt) end
vec2mt.__add = function(a, b) return vec2(a.x + b.x, a.y + b.y) end
vec2mt.__sub = function(a, b) return vec2(a.x - b.x, a.y - b.y) end
rgbm = setmetatable({ colors = { white = 'W', red = 'R', yellow = 'Y', green = 'G' } },
  { __call = function(_, r, g, b, m) return { r = r, g = g, b = b, mult = m } end })
bit = require('bit')

---------------------------------------------------------------- tor i auta
local TRACK = 1000
local R = TRACK / (2 * math.pi)
local function posOnTrack(s, latOff)
  local a = 2 * math.pi * s
  local p = vec3(R * math.cos(a), 0, R * math.sin(a))
  local look = vec3(-math.sin(a), 0, math.cos(a))
  local side = vec3(math.cos(a), 0, math.sin(a))
  return p + side * (latOff or 0), look, side
end

local function makeCar(index, s, lat)
  local c = { index = index, splinePosition = s, speedKmh = 0, isConnected = true, isInPitlane = false,
    racePosition = index + 1, sessionID = index + 10, lapCount = 0, aabbSize = vec3(2, 1.2, 4.6), lat = lat or 0 }
  c.position, c.look, c.side = posOnTrack(s, c.lat)
  return c
end
local function moveCar(c, s, speed)
  c.splinePosition = s % 1
  c.speedKmh = speed
  c.position, c.look, c.side = posOnTrack(c.splinePosition, c.lat)
end

---------------------------------------------------------------- środowisko CSP
local env
local function setup(serverCfg)
  env = {
    cars = { [0] = makeCar(0, 0.980, -1.5), [1] = makeCar(1, 0.975, 1.5) },
    sim = { raceSessionType = 3, currentSessionTime = -10000, timeToSessionStart = 10000, carsCount = 2,
      trackLengthM = TRACK, currentSessionIndex = 2, gameTime = 0, time = 0, isAdmin = true, windowWidth = 1920, windowHeight = 1080 },
    penalties = {}, chats = {}, throttle = 0, brakes = 0, extras = {}, events = {}, buttons = {},
    welcome = nil,
  }
  ac = {
    getSim = function() return env.sim end,
    getCar = function(i) return env.cars[i] end,
    getDriverName = function(i) return 'Kierowca' .. i end,
    getUI = function() return { uiScale = 1 } end,
    log = function() end,
    debug = function() end,
    sendChatMessage = function(m) env.chats[#env.chats + 1] = m; return true end,
    onOnlineWelcome = function(cb) env.welcome = cb end,
    onSessionStart = function(cb) env.sessionStart = cb end,
    onChatMessage = function(cb) env.chatCb = cb end,
    checkAdminPrivileges = function() return true end,
    setClipboardText = function(t) env.clipboard = t end,
    getTrackName = function() return 'Silverstone' end,
    SessionType = { Race = 3 },
    PenaltyType = { MandatoryPits = 1, TeleportToPits = 2 },
    SharedNamespace = { ServerScript = 'server_script' },
    StructItem = setmetatable({}, { __index = function() return function() return 0 end end }),
    OnlineEvent = function(layout, cb)
      local ev = { cb = cb }
      env.events[#env.events + 1] = ev
      return function(data)
        -- pętla zwrotna: wiadomość wraca do nadawcy (jak w CSP)
        cb(env.cars[0], data)
        return true
      end
    end,
  }
  physics = {
    setCarPenalty = function(t, p) env.penalties[#env.penalties + 1] = { t, p } end,
    forceUserThrottleFor = function() env.throttle = env.throttle + 1 end,
    forceUserBrakesFor = function() env.brakes = env.brakes + 1 end,
    raycastTrack = function() return 2.0 end,
  }
  render = setmetatable({ BlendMode = {}, DepthMode = {}, CullMode = {} },
    { __index = function() return function() end end })
  ui = setmetatable({
    Icons = {}, OnlineExtraFlags = { None = 0, Admin = 1, Tool = 2 }, WindowFlags = { None = 0 },
    measureDWriteText = function(t, s) return vec2(#t * s * 0.5, s) end,
    registerOnlineExtra = function(icon, title, avail, uiCb, closeCb, flags)
      env.extras[#env.extras + 1] = { title = title, ui = uiCb, close = closeCb, flags = flags }
    end,
    button = function(label) return env.buttons[label] == true end,
    drawCircleFilled = function(_, _, col)
      env.circles = (env.circles or 0) + 1
      if col and col.r == 1 then env.red = (env.red or 0) + 1 end
    end,
    slider = function(_, v) return v end,
    mousePos = function() return vec2(0, 0) end,
    mouseDelta = function() return vec2(0, 0) end,
    mouseDown = function() return false end,
  }, { __index = function() return function() end end })
  script = {}
  dofile('fr_standing_start.lua')
  serverCfg = serverCfg or {}
  if serverCfg.HOLD_MIN_MS == nil then serverCfg.HOLD_MIN_MS = 1000; serverCfg.HOLD_MAX_MS = 1000 end
  do
    env.welcome('', { get = function(_, section, key, def)
      if section == 'FR_STANDING_START' and serverCfg[key] ~= nil then return serverCfg[key] end
      return def
    end })
  end
end

local function frame(dtMs)
  env.sim.currentSessionTime = env.sim.currentSessionTime + dtMs
  if env.sim.timeToSessionStart > 0 then
    env.sim.timeToSessionStart = math.max(0, env.sim.timeToSessionStart - dtMs)
  end
  env.sim.gameTime = env.sim.gameTime + dtMs / 1000
  env.sim.time = env.sim.time + dtMs
  script.update(dtMs / 1000)
  script.drawUI()
  script.draw3D()
end

local function adminPanel()
  for _, e in ipairs(env.extras) do if e.flags == 2 then return e end end
end
local function press(label)
  env.buttons = { [label] = true }
  adminPanel().ui()
  env.buttons = {}
end

-- przejazd okrążenia formującego: auto jedzie od pola dookoła i staje z przesunięciem `stopOffset` m
local function driveFormation(stopOffset, speed)
  local me = env.cars[0]
  local slotS = 0.980
  local target = slotS + 1 + stopOffset / TRACK
  local s = slotS
  local v = speed or 70
  while s < target do
    local remaining = (target - s) * TRACK
    local vv = remaining < 30 and math.max(5, remaining * 2) or v
    s = math.min(target, s + vv / 3.6 * 0.05 / TRACK)
    moveCar(me, s, vv)
    frame(50)
  end
  moveCar(me, target, 0)
  for _ = 1, 10 do frame(50) end
end

local function runLights(moveAtMsBeforeOut)
  press('Zapal światła')
  local me = env.cars[0]
  local moved = false
  for _ = 1, 400 do
    frame(50)
    if moveAtMsBeforeOut and not moved and env.t0outAt == nil then end
    -- ruch auta przed zgaszeniem (falstart)
    if moveAtMsBeforeOut and not moved then
      local remaining = (env.sim._outAt or math.huge) - env.sim.currentSessionTime
      if remaining <= moveAtMsBeforeOut then
        moved = true
        moveCar(me, me.splinePosition + 1.0 / TRACK, 8)
      end
    end
  end
end

---------------------------------------------------------------- scenariusz 1: czysty start
setup({ AUTO_LIGHTS = 0 })
for _ = 1, 20 do frame(50) end -- przed startem
check('S1: panel admina zarejestrowany', adminPanel() ~= nil)
-- start z gry
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
frame(50)
-- jazda za szybko na formującym
moveCar(env.cars[0], 0.99, 120)
frame(50)
check('S1: limit prędkości na formującym', env.throttle > 0 and env.brakes > 0)
driveFormation(0.2)
-- czas zgaszenia świateł znamy dopiero po komendzie, więc tu bez falstartu
press('Zapal światła')
for _ = 1, 165 do frame(50) end
check('S1: brak kary przy czystym starcie', #env.penalties == 0)
-- reakcja: auto rusza po zgaszeniu
local me = env.cars[0]
moveCar(me, me.splinePosition + 2 / TRACK, 15)
frame(50)
local reaction = false
for _, m in ipairs(env.chats) do if m:find('reakcja') then reaction = true end end
check('S1: czas reakcji na czacie', reaction)

---------------------------------------------------------------- scenariusz 2: przestrzelone pole
setup(nil)
for _ = 1, 5 do frame(50) end
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
frame(50)
driveFormation(11.0)
press('Zapal światła')
for _ = 1, 300 do frame(50) end
check('S2: kara drive-through za przestrzelenie', #env.penalties == 1 and env.penalties[1][1] == 1 and env.penalties[1][2] == 3)
local over = false
for _, m in ipairs(env.chats) do if m:find('przestrzelone') then over = true end end
check('S2: wpis na czacie o przestrzeleniu', over)

---------------------------------------------------------------- scenariusz 3: ostrzeżenie 1.5 m bez kary
setup(nil)
for _ = 1, 5 do frame(50) end
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
frame(50)
driveFormation(8.0)
press('Zapal światła')
for _ = 1, 300 do frame(50) end
check('S3: 8 m = tylko ostrzeżenie', #env.penalties == 0)

---------------------------------------------------------------- scenariusz 4: falstart
setup({ JUMP_START_PENALTY = 'TELEPORT', TELEPORT_SECONDS = 7, LANGUAGE = 'EN' })
for _ = 1, 5 do frame(50) end
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
frame(50)
driveFormation(0.0)
press('Start lights')
-- po 2 s (świeci już kilka świateł) auto rusza o 1 m
for _ = 1, 100 do frame(50) end
moveCar(env.cars[0], env.cars[0].splinePosition + 1.0 / TRACK, 6)
for _ = 1, 300 do frame(50) end
check('S4: kara teleport za falstart', #env.penalties == 1 and env.penalties[1][1] == 2 and env.penalties[1][2] == 7)
local jump = false
for _, m in ipairs(env.chats) do if m:find('jump start') then jump = true end end
check('S4: wpis na czacie po angielsku', jump)

---------------------------------------------------------------- scenariusz 5: przerwany start i anulowanie kary
setup(nil)
for _ = 1, 5 do frame(50) end
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
frame(50)
driveFormation(11.0)
-- admin anuluje karę (target = sessionID auta 0 = 10)
env.buttons = { ['Anuluj karę##p0'] = true }
adminPanel().ui()
env.buttons = {}
press('Zapal światła')
for _ = 1, 300 do frame(50) end
check('S5: anulowana kara nie została nałożona', #env.penalties == 0)

---------------------------------------------------------------- scenariusz 6: przerwanie startu
setup(nil)
for _ = 1, 5 do frame(50) end
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
frame(50)
driveFormation(0.0)
press('Zapal światła')
for _ = 1, 40 do frame(50) end
press('Przerwij start (dodatkowe formujące)')
for _ = 1, 300 do frame(50) end
check('S6: po przerwaniu nie ma startu ani kary', #env.penalties == 0 and #env.chats == 0)
-- drugie formujące i start
driveFormation(0.1)
press('Zapal światła')
for _ = 1, 165 do frame(50) end
moveCar(env.cars[0], env.cars[0].splinePosition + 2 / TRACK, 15)
frame(50)
check('S6: start po dodatkowym okrążeniu', #env.chats >= 1 and #env.penalties == 0)

---------------------------------------------------------------- scenariusz 7: start z alei, wyjazd za wcześnie
setup(nil)
env.cars[0].isInPitlane = true
for _ = 1, 5 do frame(50) end
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
frame(50)
press('Pomiń formujące (test)')
press('Zapal światła')
for _ = 1, 80 do frame(50) end
env.cars[0].isInPitlane = false
for _ = 1, 300 do frame(50) end
check('S7: wyjazd z alei przed zgaszeniem = kara', #env.penalties == 1)

---------------------------------------------------------------- scenariusz 8: automat świateł
setup({ AUTO_LIGHTS = 1, AUTO_DELAY_S = 2 })
for _ = 1, 5 do frame(50) end
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
frame(50)
-- drugie auto melduje się jako stojące na polu
env.events[1].cb(env.cars[1], { state = 4, offsetCm = 0, pending = 0 })
driveFormation(0.0)
local waited, seen = 0, false
while waited < 800 do
  env.circles = 0
  frame(50); waited = waited + 1
  if env.circles > 0 then seen = true end
  if seen and env.circles == 0 then break end -- światła zgasły
end
moveCar(env.cars[0], env.cars[0].splinePosition + 2 / TRACK, 15)
frame(50)
local reacted = false
for _, m in ipairs(env.chats) do if m:find('reakcja') then reacted = true end end
check('S8: automat zapalił światła sam', reacted)

---------------------------------------------------------------- scenariusz 9: skrypt wczytany po starcie
setup(nil)
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
env.sim.currentSessionTime = 60000
for _ = 1, 20 do frame(50) end
check('S9: późne wczytanie bez błędów i kar', #env.penalties == 0)

---------------------------------------------------------------- scenariusz 10: admin po /admin i komenda na czacie
setup(nil)
env.sim.isAdmin = false
for _ = 1, 5 do frame(50) end
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
frame(50)
driveFormation(0.0)
local hidden = env.chatCb('!frss swiatla', 0, 10)
check('S10: komenda ukryta na czacie', hidden == true)
for _ = 1, 200 do frame(50) end
check('S10: bez admina komenda nic nie robi', #env.chats == 0)
env.chatCb('You are now Admin for this server', -1, -1)
env.chatCb('!frss swiatla', 0, 10)
for _ = 1, 165 do frame(50) end
moveCar(env.cars[0], env.cars[0].splinePosition + 2 / TRACK, 15)
frame(50)
local r10 = false
for _, m in ipairs(env.chats) do if m:find('reakcja') then r10 = true end end
check('S10: po /admin komenda !frss swiatla zapala światła', r10)

---------------------------------------------------------------- scenariusz 11: stoi obok pola → kara
setup(nil)
for _ = 1, 5 do frame(50) end
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
frame(50)
env.cars[0].lat = -1.5 + 2.6 -- stanie 2.6 m obok swojego pola
env.cars[0].wheels = nil
driveFormation(0.0)
press('Zapal światła')
for _ = 1, 300 do frame(50) end
local lane = false
for _, m in ipairs(env.chats) do if m:find('obok pola') then lane = true end end
check('S11: kara za stanie obok pola', #env.penalties == 1 and lane)

---------------------------------------------------------------- scenariusz 12: drive-through odbyty w alei
-- (kontynuacja S11: kierowca ma DT)
env.cars[0].lat = -1.5
-- najpierw pitstop (postój w boksie) – nie zalicza kary
local nPen = #env.penalties
env.cars[0].isInPitlane = true; env.cars[0].speedKmh = 40; frame(50)
env.cars[0].isInPit = true; env.cars[0].speedKmh = 0; for _ = 1, 40 do frame(50) end
env.cars[0].isInPit = false; env.cars[0].speedKmh = 40; frame(50)
env.cars[0].isInPitlane = false; frame(50)
local invalid = false
for _, m in ipairs(env.chats) do if m:find('nie zaliczył') then invalid = true end end
check('S12: pitstop nie zalicza drive-through', invalid and #env.penalties == nPen + 1)
-- potem przejazd bez zatrzymania
env.cars[0].isInPitlane = true; env.cars[0].speedKmh = 60; frame(50); frame(50)
env.cars[0].isInPitlane = false; frame(50)
local served = false
for _, m in ipairs(env.chats) do if m:find('drive%-through odbyty') then served = true end end
check('S12: odbycie drive-through rozpoznane', served)

---------------------------------------------------------------- scenariusz 13: czas reakcji innych ukryty
check('S13: cudzy czas reakcji ukryty', env.chatCb('FRSS>R P2 Kierowca1: reakcja 300 ms', 1, 11) == true)
check('S13: własny czas reakcji widoczny', env.chatCb('FRSS>R P1 Kierowca0: reakcja 250 ms', 0, 10) == false)
check('S13: kary innych widoczne', env.chatCb('FRSS> P2 Kierowca1: falstart 100 ms → drive-through', 1, 11) == false)

---------------------------------------------------------------- scenariusz 14: okno ustawień i podgląd
local settings
for _, e in ipairs(env.extras) do if e.title:find('ustawienia') then settings = e end end
check('S14: okno ustawień zarejestrowane', settings ~= nil)
settings.ui()
frame(50)
check('S14: podgląd bez błędów', true)

---------------------------------------------------------------- scenariusz 15: inny zegar sesji u kierowcy nie zmienia świateł
setup(nil)
for _ = 1, 5 do frame(50) end
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
frame(50)
driveFormation(0.0)
-- komenda od innego auta (admin = auto 1), a zegar sesji tego klienta „uciekł” o 5 s
env.sim.currentSessionTime = env.sim.currentSessionTime + 5000
env.cars[0].ping = 80
env.events[4].cb(env.cars[1], { cmd = 1, t0 = 0, hold = 1000, target = -1 })
env.red = 0; frame(50)
check('S15: zaraz po komendzie żadne światło nie świeci', env.red == 0)
local litAt
for k = 1, 200 do
  env.red = 0; frame(50)
  if not litAt and env.red > 0 then litAt = k end
end
-- pierwsze światło po LIGHTS_LEAD_MS (3000 ms) minus pół pingu ≈ 59–60 klatek po 50 ms
check('S15: pierwsze światło po ok. 3 s', litAt and litAt >= 57 and litAt <= 61)

---------------------------------------------------------------- scenariusz 16: strzałka w lewo/prawo
local function wheelsFor(c)
  -- koło 0 = przednie lewe, koło 1 = przednie prawe; „prawo” = -side w tej atrapie
  local p, look, side = c.position, c.look, c.side
  c.wheels = { [0] = { position = p + side * 0.8 + look * 1.3 }, [1] = { position = p - side * 0.8 + look * 1.3 } }
end
local dirs = {}
for _, offset in ipairs({ 1.0, -1.0 }) do
  setup(nil)
  for _ = 1, 5 do frame(50) end
  env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
  frame(50)
  env.cars[0].lat = -1.5 + offset
  driveFormation(0.0)
  wheelsFor(env.cars[0])
  local texts = {}
  ui.dwriteDrawText = function(t) texts[#texts + 1] = t end
  frame(50)
  local d = '?'
  for _, t in ipairs(texts) do
    if t:find('W LEWO') then d = 'L' elseif t:find('W PRAWO') then d = 'R' end
  end
  dirs[#dirs + 1] = d
end
-- auto przesunięte w stronę +side (w lewo) → ma jechać w prawo, i odwrotnie
check('S16: strzałki w przeciwne strony', dirs[1] == 'R' and dirs[2] == 'L')

---------------------------------------------------------------- scenariusz 17: lista czasów reakcji dla admina
setup(nil)
for _ = 1, 5 do frame(50) end
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
frame(50)
driveFormation(0.0)
press('Zapal światła')
for _ = 1, 165 do frame(50) end
moveCar(env.cars[0], env.cars[0].splinePosition + 2 / TRACK, 15)
frame(50)
-- czas reakcji drugiego kierowcy i falstart trzeciego przychodzą zdarzeniem
env.events[2].cb(env.cars[1], { ms = 180, slot = 2, flags = 0 })
env.cars[2] = makeCar(2, 0.97, -1.5); env.sim.carsCount = 3
env.events[2].cb(env.cars[2], { ms = 120, slot = 3, flags = 1 })
env.chatCb('!frss reakcje', 0, 10)
local clip = env.clipboard or ''
check('S17: lista skopiowana', clip:find('Czasy reakcji') ~= nil)
check('S17: najszybszy pierwszy', clip:find('1%. Kierowca1 %(P2%) – 0%.180 s') ~= nil)
check('S17: falstart na końcu', clip:find('Kierowca2 %(P3%) – FALSTART') ~= nil)
adminPanel().ui()
check('S17: panel z listą bez błędów', true)

---------------------------------------------------------------- scenariusz 18: przerwanie startu nie zostawia starych statusów w automacie
setup({ AUTO_LIGHTS = 1, AUTO_DELAY_S = 2, AUTO_TIMEOUT_S = 30 })
for _ = 1, 5 do frame(50) end
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
frame(50)
-- drugie auto (lider) melduje się na polu, ja jeszcze jadę
env.events[1].cb(env.cars[1], { state = 4, offsetCm = 0, pending = 0 })
moveCar(env.cars[0], 0.3, 60); frame(50)
press('Przerwij start (dodatkowe formujące)')
env.red = 0
-- przez 40 s po przerwaniu lider nie przysłał nowego statusu (stary „na polu” nie może uruchomić świateł)
for _ = 1, 800 do frame(50) end
check('S18: brak świateł od starego statusu po przerwaniu', (env.red or 0) == 0)

---------------------------------------------------------------- scenariusz 19: auto przeniesione do boksu i auto, które nie ruszyło, nie blokują świateł
setup({ AUTO_LIGHTS = 1, AUTO_DELAY_S = 2, AUTO_TIMEOUT_S = 600 })
env.cars[2] = makeCar(2, 0.97, -1.5); env.sim.carsCount = 3
for _ = 1, 5 do frame(50) end
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
frame(50)
-- auto 1: przeniesione do boksu → melduje start z alei; auto 2: nie ruszyło → melduje „nie ruszył”
env.cars[1].isInPitlane = true
env.events[1].cb(env.cars[1], { state = 8, offsetCm = 0, pending = 0 })
env.events[1].cb(env.cars[2], { state = 13, offsetCm = 0, pending = 0 })
driveFormation(0.0)
local seen19 = false
for _ = 1, 200 do env.red = 0; frame(50); if env.red > 0 then seen19 = true end end
check('S19: światła ruszyły bez czekania na limit czasu', seen19)

---------------------------------------------------------------- scenariusz 20: własne auto w boksie podczas formującego = start z alei; nie ruszyło = gotowy
setup(nil)
for _ = 1, 5 do frame(50) end
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
frame(50)
for _ = 1, 500 do frame(50) end -- stoi na polu 25 s
local texts = {}
local old = ui.dwriteDrawText
ui.dwriteDrawText = function(t) texts[#texts + 1] = t end
frame(50)
local dns = false
for _, t in ipairs(texts) do if t:find('Nie ruszyłeś') then dns = true end end
check('S20: auto, które nie ruszyło, ma stan „nie ruszył”', dns)
env.cars[0].isInPit = true; frame(50)
texts = {}; frame(50)
local pit = false
for _, t in ipairs(texts) do if t:find('START Z BOKSU') then pit = true end end
check('S20: auto w boksie = start z alei', pit)
ui.dwriteDrawText = old

---------------------------------------------------------------- scenariusz 22: jedzie w trakcie świateł (nie zdążył na pole) = DT
setup(nil)
for _ = 1, 5 do frame(50) end
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
frame(50)
moveCar(env.cars[0], 0.5, 70); frame(50)
press('Zapal światła')
for _ = 1, 300 do moveCar(env.cars[0], env.cars[0].splinePosition + 0.0005, 70); frame(50) end
local late = false
for _, m in ipairs(env.chats) do if m:find('nie stał na polu') and m:find('stop & go') then late = true end end
check('S22: spóźniony daleko od pola dostaje stop & go', late and #env.penalties == 1 and env.penalties[1][1] == 1)
-- odbycie: postój w boksie 10 s
env.cars[0].isInPitlane = true; env.cars[0].isInPit = true; env.cars[0].speedKmh = 0
for _ = 1, 210 do frame(50) end
env.cars[0].isInPit = false; env.cars[0].speedKmh = 40; frame(50)
env.cars[0].isInPitlane = false; frame(50)
local sgOk = false
for _, m in ipairs(env.chats) do if m:find('stop & go odbyty') then sgOk = true end end
check('S22: stop & go odbyty po 10 s w boksie', sgOk)

---------------------------------------------------------------- scenariusz 23: spóźniony blisko pola = DT
setup(nil)
for _ = 1, 5 do frame(50) end
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
frame(50)
press('Pomiń formujące (test)')
-- 10 m przed polem, jeszcze jedzie
moveCar(env.cars[0], 0.980 - 10 / TRACK, 20); frame(50)
press('Zapal światła')
for _ = 1, 300 do frame(50) end
local dt23 = false
for _, m in ipairs(env.chats) do if m:find('nie stał na polu') and m:find('drive%-through') then dt23 = true end end
check('S23: spóźniony blisko pola dostaje DT', dt23)

---------------------------------------------------------------- scenariusz 24: start z boksu – formujące, powrót do alei, zielone po T1
setup(nil)
env.cars[0].isInPitlane = true; env.cars[0].isInPit = true
moveCar(env.cars[0], 0.05, 0)
for _ = 1, 5 do frame(50) end
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
frame(50)
local tx = {}
local old24 = ui.dwriteDrawText
ui.dwriteDrawText = function(t) tx[#tx + 1] = t end
env.cars[0].isInPitlane = false; env.cars[0].isInPit = false
moveCar(env.cars[0], 0.2, 60); frame(50)
local pitOut = false
for _, t in ipairs(tx) do if t:find('po okrążeniu formującym zjedź') then pitOut = true end end
check('S24: komunikat o powrocie do alei po formującym', pitOut)
-- wraca do alei przed światłami
env.cars[0].isInPitlane = true; env.cars[0].speedKmh = 0; frame(50)
press('Zapal światła')
for _ = 1, 170 do frame(50) end
tx = {}; frame(50)
local wait = false
for _, t in ipairs(tx) do if t:find('WYJAZD Z ALEI: CZEKAJ') then wait = true end end
check('S24: po starcie czerwone światło wyjazdu', wait and #env.penalties == 0)
-- auto 1 (P2) mija punkt 500 m za polem P1
-- jedzie 510 m w krokach (odległość liczona z przejechanej drogi)
for k = 1, 51 do moveCar(env.cars[1], (0.975 + k * 0.01) % 1, 150); frame(50) end
tx = {}; frame(50); frame(50)
local go = false
for _, t in ipairs(tx) do if t:find('WYJAZD Z ALEI: JEDŹ') then go = true end end
check('S24: zielone po minięciu T1 przez stawkę', go)
env.cars[0].isInPitlane = false; frame(50)
check('S24: wyjazd na zielonym bez kary', #env.penalties == 0)
ui.dwriteDrawText = old24

---------------------------------------------------------------- scenariusz 25: wyjazd z boksu przed zielonym = kara
setup(nil)
env.cars[0].isInPitlane = true; env.cars[0].isInPit = true
for _ = 1, 5 do frame(50) end
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
frame(50)
press('Zapal światła')
for _ = 1, 170 do frame(50) end
env.cars[0].isInPit = false; env.cars[0].isInPitlane = false; frame(50)
local early = false
for _, m in ipairs(env.chats) do if m:find('przed zielonym') then early = true end end
check('S25: wyjazd przed zielonym = kara', early and #env.penalties == 1)

---------------------------------------------------------------- scenariusz 26: numer pola z położenia, nie z wyników
setup(nil)
env.cars[0].racePosition = 2; env.cars[1].racePosition = 3
env.cars[2] = makeCar(2, 0.30, 0); env.cars[2].isInPitlane = true; env.cars[2].racePosition = 1; env.sim.carsCount = 3
for _ = 1, 5 do frame(50) end
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
frame(50)
local tx26 = {}
local old26 = ui.dwriteDrawText
ui.dwriteDrawText = function(t) tx26[#tx26 + 1] = t end
moveCar(env.cars[0], 0.1, 60); frame(50)
local p1 = false
for _, t in ipairs(tx26) do if t:find('Twoje pole: P1') then p1 = true end end
check('S26: lider ma P1 mimo auta w boksie z P1 w wynikach', p1)
ui.dwriteDrawText = old26

---------------------------------------------------------------- scenariusz 27: dołączenie w trakcie formującego
setup(nil)
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 30000
env.cars[0].isInPitlane = true; env.cars[0].isInPit = true
for _ = 1, 5 do frame(50) end
-- admin (auto 1) ogłasza fazę: formujące
env.events[3].cb(env.cars[1], { phase = 2, released = 0 })
local tx27 = {}
local old27 = ui.dwriteDrawText
ui.dwriteDrawText = function(t) tx27[#tx27 + 1] = t end
frame(50)
local info = false
for _, t in ipairs(tx27) do if t:find('START Z BOKSU') then info = true end end
check('S27: dołączający w trakcie formującego widzi start z boksu', info)
ui.dwriteDrawText = old27

---------------------------------------------------------------- scenariusz 28: dołączenie w trakcie formującego bez admina (z meldunków innych aut)
setup(nil)
env.sim.isAdmin = false
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 30000
for _ = 1, 3 do frame(50) end
env.events[1].cb(env.cars[1], { state = 3, offsetCm = 0, pending = 0 }) -- inne auto dojeżdża do pola
local tx28 = {}
local old28 = ui.dwriteDrawText
ui.dwriteDrawText = function(t) tx28[#tx28 + 1] = t end
frame(50); frame(50)
local info28 = false
for _, t in ipairs(tx28) do if t:find('BOKSU') then info28 = true end end
check('S28: dołączający widzi start z boksu bez admina', info28)
ui.dwriteDrawText = old28

---------------------------------------------------------------- scenariusz 29: automat nie zapala świateł, gdy ktoś jedzie po torze
setup({ AUTO_LIGHTS = 1, AUTO_DELAY_S = 2, AUTO_TIMEOUT_S = 600 })
env.cars[2] = makeCar(2, 0.5, 0); env.sim.carsCount = 3
for _ = 1, 5 do frame(50) end
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
frame(50)
env.events[1].cb(env.cars[1], { state = 4, offsetCm = 0, pending = 0 })
-- auto 2 dołączyło w trakcie i melduje „brak pola”, ale jedzie po torze
env.cars[2].speedKmh = 150
env.events[1].cb(env.cars[2], { state = 9, offsetCm = 0, pending = 0 })
driveFormation(0.0)
env.red = 0
for _ = 1, 400 do frame(50) end -- 20 s
check('S29: brak świateł, gdy auto bez pola jedzie po torze', (env.red or 0) == 0)
-- auto z meldunkiem „na polu”, które jednak jedzie
env.cars[2].speedKmh = 0; env.cars[2].isInPitlane = true
env.cars[1].speedKmh = 60
env.red = 0
for _ = 1, 200 do frame(50) end
check('S29: brak świateł, gdy auto z meldunkiem „na polu” jedzie', (env.red or 0) == 0)
env.cars[1].speedKmh = 0
local seen29 = false
for _ = 1, 300 do env.red = 0; frame(50); if env.red > 0 then seen29 = true end end
check('S29: światła, gdy wszyscy naprawdę stoją', seen29)

---------------------------------------------------------------- scenariusz 30: startujący z boksu nie widzi świateł startowych, tylko swoje
setup(nil)
env.cars[0].isInPitlane = true; env.cars[0].isInPit = true
for _ = 1, 5 do frame(50) end
env.sim.timeToSessionStart = 0; env.sim.currentSessionTime = 0
frame(50)
press('Zapal światła')
local maxCircles = 0
for _ = 1, 120 do env.circles = 0; frame(50); maxCircles = math.max(maxCircles, env.circles) end
check('S30: w trakcie świateł widać tylko 1 światło (wyjazd z alei)', maxCircles == 1)
-- wyjazd z alei przy zapalonych światłach startowych = DT
env.cars[0].isInPit = false; env.cars[0].isInPitlane = false; frame(50)
for _ = 1, 100 do frame(50) end
check('S30: wyjazd za wcześnie = drive-through', #env.penalties == 1 and env.penalties[1][1] == 1 and env.penalties[1][2] == 3)

print(string.format('symulacja: pass=%d fail=%d', pass, fail))
os.exit(fail == 0 and 0 or 1)

-- Octo Planner Export: target dummy recorder (WoW 1.12 / Lua 5.0)
-- /ope dummy [name]  starts recording your damage; /ope dummy again stops and saves the run.
-- Runs are saved per character under "runs" and shown on the planner's Rotation tab.

local PREFIX = "|cff9f7aea[Octo Planner Export]|r "
local function say(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) end
local MAX_RUNS = 30

local rec = nil   -- the run being recorded
local function watching() return OctoPlannerExportDB and OctoPlannerExportDB.ccWatch end

local function ab(name)
  local a = rec.ab[name]
  if not a then a = { n = 0, c = 0, m = 0, d = 0, t = 0, td = 0, g = 0 }; rec.ab[name] = a end
  return a
end
-- time with no hit for more than 5 seconds (target dead, you walked away) is not counted as fight time
local IDLE_GAP = 5
local function stamp()
  local now = GetTime()
  if not rec.t0 then
    rec.t0 = now
    local base, pos, neg = UnitAttackPower("player")
    rec.ap = (base or 0) + (pos or 0) + (neg or 0)   -- read at the first hit, so it is your attack power in form
  elseif now - rec.t1 > IDLE_GAP then
    rec.idle = (rec.idle or 0) + (now - rec.t1)
  end
  rec.t1 = now
end
-- only your own abilities can use a Clearcasting, never an item proc
local CASTS = { ["Claw"] = 1, ["Shred"] = 1, ["Rake"] = 1, ["Rip"] = 1, ["Ferocious Bite"] = 1, ["Ravage"] = 1, ["Pounce"] = 1,
  ["Tiger's Fury"] = 1, ["Faerie Fire (Feral)"] = 1, ["Maul"] = 1, ["Swipe"] = 1, ["Savage Bite"] = 1 }
-- which ability used up each Clearcasting: the cast that lands within half a second of "Clearcasting fades"
local lastCast, fadeAt = nil, nil
local function useCC(name)
  if rec then rec.ccUse[name] = (rec.ccUse[name] or 0) + 1 end
  if watching() then
    if name == "ran out" then say("Clearcasting ran out without being used.")
    else say("Clearcasting used by |cffffd100" .. name .. "|r") end
  end
end
-- attack power: read live for direct hits; bleeds keep the attack power they were cast with
local snap = {}
local function curAP()
  local base, pos, neg = UnitAttackPower("player")
  return (base or 0) + (pos or 0) + (neg or 0)
end
local TICKOF = { ["Pounce Bleed"] = "Pounce" }
-- per ability, normal hits only (no crit, no glance): sums for a straight-line fit of damage against attack power
local function scale(name, amount, ap)
  rec.sc = rec.sc or {}
  local x = rec.sc[name]
  if not x then x = { n = 0, sd = 0, sa = 0, saa = 0, sad = 0, mn = ap, mx = ap }; rec.sc[name] = x end
  x.n = x.n + 1; x.sd = x.sd + amount; x.sa = x.sa + ap; x.saa = x.saa + ap * ap; x.sad = x.sad + ap * amount
  if ap < x.mn then x.mn = ap end
  if ap > x.mx then x.mx = ap end
end
local function cast(name)
  snap[name] = curAP()
  if not CASTS[name] then return end
  local now = GetTime()
  if fadeAt and now - fadeAt > 0.5 then useCC("ran out"); fadeAt = nil end
  if fadeAt and now - fadeAt <= 0.5 then useCC(name); fadeAt = nil; lastCast = nil; return end
  lastCast = { n = name, t = now }
end
local function faded()
  local now = GetTime()
  if lastCast and now - lastCast.t <= 0.5 then useCC(lastCast.n); lastCast = nil else fadeAt = now end
end
local function hasCC()
  local i = 1
  while UnitBuff("player", i) do
    if string.find(UnitBuff("player", i), "ManaBurn") then return true end
    i = i + 1
  end
  return false
end
local ccOn, auraSeen = false, false

-- energy ticks and Reshift: does Reshift restart the 2-second tick?
local lastE, lastTick, prevTick, pendingShift = nil, nil, nil, nil
local hist = {}
local function onEnergy()
  local e = UnitMana("player")
  local now = GetTime()
  local d = e - (lastE or e)
  table.insert(hist, e); if table.getn(hist) > 6 then table.remove(hist, 1) end
  if d == 20 or (d == 40 and lastE and lastE > 0) then
    prevTick, lastTick = lastTick, now
    if pendingShift and not pendingShift.n then
      pendingShift.n = math.floor((now - pendingShift.at) * 100 + 0.5) / 100
      pendingShift = nil
    end
  end
  lastE = e
end
local function onShift()
  local now = GetTime()
  -- energy just before the shift: skip the 0 and 40 the shift itself produced
  local before, i, skipped = lastE, table.getn(hist), 0
  if lastE == 40 then
    while i > 1 and skipped < 2 and (hist[i] == 40 or hist[i] == 0) do i = i - 1; skipped = skipped + 1 end
    before = hist[i]
  end
  if lastTick == now then lastTick = prevTick end   -- a shift from 20 to 40 is not a tick
  local s = { e = before or 0, at = now }
  if lastTick then s.p = math.floor(math.mod(now - lastTick, 2) * 100 + 0.5) / 100 end
  table.insert(rec.shifts, s)
  pendingShift = s
end

-- per target: damage, hits, time from first to last hit, what it was immune to, and its creature id (SuperWoW)
local MAX_TARGETS = 200
local function mobId(tname)
  if not UnitExists or UnitName("target") ~= tname then return nil end
  local _, guid = UnitExists("target")
  if type(guid) ~= "string" or string.sub(guid, 1, 2) ~= "0x" or string.len(guid) < 12 then return nil end
  local id = tonumber(string.sub(guid, 7, 12), 16)
  if id and id > 0 then return id end
end
local function tgt(tname)
  if not tname or tname == "" then return nil end
  rec.tg = rec.tg or {}
  local x = rec.tg[tname]
  if not x then
    local count = 0
    for _ in pairs(rec.tg) do count = count + 1 end
    if count >= MAX_TARGETS then return nil end
    x = { d = 0, n = 0, f = GetTime() - (rec.t0 or GetTime()), l = 0, ab = {} }
    rec.tg[tname] = x
  end
  x.l = GetTime() - (rec.t0 or GetTime())
  if not x.id then x.id = mobId(tname) end
  return x
end
local function dmgOn(tname, name, amount)
  local x = tgt(tname); if not x then return end
  x.d = x.d + amount; x.n = x.n + 1
  x.ab[name] = (x.ab[name] or 0) + amount
end
local function immune(tname, spell)
  if not rec then return end
  stamp()
  local x = tgt(tname); if not x then return end
  x.im = x.im or {}
  x.im[spell] = (x.im[spell] or 0) + 1
end
local function dmg(name, amount, crit, tick, glance)
  if not rec then if not tick and name ~= "Auto attack" then cast(name) end return end
  stamp()
  local a = ab(name)
  if tick then a.t = a.t + 1; a.td = a.td + amount else a.n = a.n + 1; if name ~= "Auto attack" then cast(name) end end
  if crit then a.c = a.c + 1 end
  if glance then a.g = a.g + 1 end
  a.d = a.d + amount
  rec.total = rec.total + amount
  if not crit and not glance and amount > 0 then
    if tick then
      local ap = snap[TICKOF[name] or name]
      if ap then scale(name .. " (tick)", amount, ap) end
    else
      scale(name, amount, curAP())
    end
  end
end
local function miss(name)
  if not rec then if name ~= "Auto attack" then cast(name) end return end
  stamp()
  local a = ab(name)
  a.n = a.n + 1; a.m = a.m + 1
  if name ~= "Auto attack" then cast(name) end
end

local function onMsg(msg)
  if (not rec and not watching()) or not msg then return end
  local _, _, spell, amt, who
  -- immune
  _, _, spell, who = string.find(msg, "^Your (.-) failed%. (.-) is immune%.")
  if spell then immune(who, spell) return end
  _, _, who, spell = string.find(msg, "^(.-) is immune to your (.-)%.")
  if who then immune(who, spell) return end
  -- auto attack
  _, _, who, amt = string.find(msg, "^You hit (.-) for (%d+)")
  if amt then dmg("Auto attack", tonumber(amt), false, false, string.find(msg, "glancing") ~= nil); if rec then dmgOn(who, "Auto attack", tonumber(amt)) end return end
  _, _, who, amt = string.find(msg, "^You crit (.-) for (%d+)")
  if amt then dmg("Auto attack", tonumber(amt), true); if rec then dmgOn(who, "Auto attack", tonumber(amt)) end return end
  if string.find(msg, "^You miss ") or string.find(msg, "^You attack%. ") then miss("Auto attack") return end
  -- abilities
  _, _, spell, who, amt = string.find(msg, "^Your (.-) hits (.-) for (%d+)")
  if spell then dmg(spell, tonumber(amt), false); if rec then dmgOn(who, spell, tonumber(amt)) end return end
  _, _, spell, who, amt = string.find(msg, "^Your (.-) crits (.-) for (%d+)")
  if spell then dmg(spell, tonumber(amt), true); if rec then dmgOn(who, spell, tonumber(amt)) end return end
  _, _, spell = string.find(msg, "^Your (.-) missed ")
  if spell then miss(spell) return end
  _, _, spell = string.find(msg, "^Your (.-) was %a+ by ")
  if spell then miss(spell) return end
  _, _, spell = string.find(msg, "^Your (.-) is parried")
  if spell then miss(spell) return end
  -- bleed ticks
  _, _, who, amt, spell = string.find(msg, "^(.-) suffers (%d+) .-damage from your (.-)%.")
  if amt then dmg(spell, tonumber(amt), false, true); if rec then dmgOn(who, spell, tonumber(amt)) end return end
  -- procs, energy and casts without a damage line
  if string.find(msg, "^You gain Clearcasting") then if rec then rec.cc = rec.cc + 1 end return end
  if string.find(msg, "^Clearcasting fades from you") then if not auraSeen then faded() end return end
  if string.find(msg, "^You gain Tiger's Fury") then cast("Tiger's Fury") return end
  _, _, spell = string.find(msg, " is afflicted by (.-)%.$")
  if spell and (spell == "Rip" or spell == "Pounce" or string.find(spell, "^Faerie Fire")) then cast(spell) return end
  _, _, amt, spell = string.find(msg, "^You gain (%d+) Energy from (.-)%.")
  if amt and spell == "Furor" and rec then onShift() end
  if amt and rec then
    rec.energy[spell] = (rec.energy[spell] or 0) + tonumber(amt)
    return
  end
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "CHAT_MSG_COMBAT_SELF_HITS", "CHAT_MSG_COMBAT_SELF_MISSES", "CHAT_MSG_SPELL_SELF_DAMAGE",
  "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE", "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS", "CHAT_MSG_SPELL_SELF_BUFF",
  "CHAT_MSG_SPELL_AURA_GONE_SELF" }) do
  f:RegisterEvent(e)
end
f:RegisterEvent("UNIT_AURA")
f:RegisterEvent("UNIT_ENERGY")
f:SetScript("OnEvent", function()
  if event == "UNIT_ENERGY" then if rec and arg1 == "player" then onEnergy() end return end
  if event == "UNIT_AURA" then
    if (not rec and not watching()) or arg1 ~= "player" then return end
    local now = hasCC()
    if now then auraSeen = true end
    if ccOn and not now then faded() end
    ccOn = now
    return
  end
  onMsg(arg1)
end)

local function start(label)
  snap = {}
  lastCast, fadeAt = nil, nil
  ccOn, auraSeen = false, false
  lastE, lastTick, prevTick, pendingShift = UnitMana("player"), nil, nil, nil
  hist = {}
  local base, pos, neg = UnitAttackPower("player")
  rec = { label = (label ~= "" and label) or nil, target = UnitName("target"), date = time(), total = 0, ab = {}, cc = 0, ccUse = {}, energy = {}, shifts = {},
          ap = (base or 0) + (pos or 0) + (neg or 0) }
  say("Recording" .. (rec.label and (" \"" .. rec.label .. "\"") or "") .. ". The clock starts at your first hit. Type /ope dummy again to stop.")
end

local function stop()
  local r = rec; rec = nil
  if not r.t0 then say("Stopped. No damage was recorded, so nothing was saved.") return end
  local idle = r.idle or 0
  r.dur = math.floor((r.t1 - r.t0 - idle + 1) * 10 + 0.5) / 10   -- +1 s so a single hit doesn't count as zero time
  r.idle = idle > 0 and math.floor(idle + 0.5) or nil
  r.t0 = nil; r.t1 = nil
  for _, x in ipairs(r.shifts or {}) do x.at = nil end
  for _, x in pairs(r.tg or {}) do x.f = math.floor(x.f + 0.5); x.l = math.floor(x.l + 0.5) end
  local db = OctoPlannerExportDB
  local name, realm = UnitName("player"), GetRealmName()
  local key = name .. " - " .. realm
  db.chars[key] = db.chars[key] or { name = name, realm = realm }
  local c = db.chars[key]
  c.runs = c.runs or {}
  table.insert(c.runs, r)
  while table.getn(c.runs) > MAX_RUNS do table.remove(c.runs, 1) end
  say(string.format("Saved run %d: %d damage in %.1f s = %.0f DPS%s. /reload or log out to write the file.", table.getn(c.runs), r.total, r.dur, r.total / r.dur,
    r.idle and string.format(" (%d s without hits not counted)", r.idle) or ""))
end

-- a run still recording at /reload or logout is saved instead of lost
local lf = CreateFrame("Frame")
lf:RegisterEvent("PLAYER_LOGOUT")
lf:SetScript("OnEvent", function() if rec then stop() end end)

function OPE_CCWatch()
  if type(OctoPlannerExportDB) ~= "table" then return end
  OctoPlannerExportDB.ccWatch = not OctoPlannerExportDB.ccWatch
  lastCast, fadeAt, ccOn = nil, nil, false
  say(OctoPlannerExportDB.ccWatch and "Clearcasting watch on: chat shows which ability uses each Clearcasting. /ope cc again turns it off." or "Clearcasting watch off.")
end

function OPE_Dummy(arg)
  if type(OctoPlannerExportDB) ~= "table" or not OctoPlannerExportDB.chars then say("Not ready yet, try again in a moment.") return end
  if arg == "clear" then
    local key = UnitName("player") .. " - " .. GetRealmName()
    local c = OctoPlannerExportDB.chars[key]
    if c then c.runs = nil end
    rec = nil
    say("All saved dummy runs for this character were deleted.")
    return
  end
  if rec then stop() else start(arg or "") end
end

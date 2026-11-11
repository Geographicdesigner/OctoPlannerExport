-- Octo Planner Export: fight log (WoW 1.12 / Lua 5.0)
-- /ope log [name]  starts a log (for a whole raid or dungeon); /ope log again stops it.
-- While a log is on, every time you enter and leave combat is saved as one fight, with:
--   every spell you cast (with SuperWoW), your damage per ability and its full hit table, damage per target and what it was immune to,
--   damage you took by enemy and ability, your deaths with the hits before them,
--   consumables you used, and how long your buffs and debuffs were up.
-- The log lives in SavedVariables while it runs, so a /reload or disconnect does not lose it.

local PREFIX = "|cff9f7aea[Octo Planner Export]|r "
local function say(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) end
local MAX_LOGS = 10
local MAX_FIGHTS = 400
local MAX_NAMES = 200
local LAST_HITS = 8

local LOG = nil     -- the running log (a table inside OctoPlannerExportDB, so it survives /reload)
local F = nil       -- the running fight
local T0 = 0        -- GetTime() when the fight started
local recent = {}   -- last hits you took, for deaths
local pending = {}  -- consumables used out of combat, added to the next fight as pre-pull
local active = {}   -- buffs and debuffs on you right now: name -> { since = GetTime(), debuff = bool }

local function now() return GetTime() - T0 end
local function r1(x) return math.floor(x * 10 + 0.5) / 10 end
local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function charKey() return (UnitName("player") or "?") .. " - " .. (GetRealmName() or "?") end
local function charDB()
  local db = OctoPlannerExportDB
  if type(db) ~= "table" then return nil end
  db.chars = db.chars or {}
  local key = charKey()
  db.chars[key] = db.chars[key] or { name = UnitName("player"), realm = GetRealmName() }
  return db.chars[key]
end

-- ---------- reading your buffs and debuffs ----------
local tip = CreateFrame("GameTooltip", "OPEFightTip", nil, "GameTooltipTemplate")
tip:SetOwner(WorldFrame, "ANCHOR_NONE")
local function auraNames(debuff)
  local out, i = {}, 1
  while true do
    local tex = debuff and UnitDebuff("player", i) or UnitBuff("player", i)
    if not tex then break end
    tip:ClearLines()
    if debuff then tip:SetUnitDebuff("player", i) else tip:SetUnitBuff("player", i) end
    local fs = getglobal("OPEFightTipTextLeft1")
    local n = fs and fs:GetText()
    if n then out[n] = true end
    i = i + 1
    if i > 40 then break end
  end
  return out
end

-- ---------- per-fight tables ----------
local function newAb() return { u = 0, n = 0, h = 0, c = 0, ms = 0, dg = 0, pr = 0, bl = 0, rs = 0, gl = 0, im = 0, d = 0, t = 0, td = 0, cd = 0 } end
local function abOf(name)
  local a = F.ab[name]
  if not a then
    if count(F.ab) >= MAX_NAMES then return nil end
    a = newAb(); F.ab[name] = a
  end
  return a
end
local function tgOf(who)
  if not who or who == "" or who == "you" then return nil end
  local x = F.tg[who]
  if not x then
    if count(F.tg) >= MAX_NAMES then return nil end
    x = { d = 0, tk = {}, im = {} }
    F.tg[who] = x
  end
  if UnitName("target") == who then
    if not x.boss and UnitClassification and UnitClassification("target") == "worldboss" then x.boss = 1 end
    if not x.id and UnitExists then
      local _, guid = UnitExists("target")
      if type(guid) == "string" and string.sub(guid, 1, 2) == "0x" and string.len(guid) >= 12 then
        local id = tonumber(string.sub(guid, 7, 12), 16)
        if id and id > 0 then x.id = id end
      end
    end
  end
  return x
end
local function takenOf(src, spell)
  local key = (src or "?") .. "|" .. (spell or "Melee")
  local x = F.tk[key]
  if not x then
    if count(F.tk) >= MAX_NAMES then return nil end
    x = { s = src or "?", a = spell or "Melee", n = 0, d = 0, c = 0, ms = 0 }
    F.tk[key] = x
  end
  return x
end

local function startFight()
  T0 = GetTime()
  recent = {}
  F = { at = time(), zone = GetRealZoneText and GetRealZoneText() or "", ab = {}, tg = {}, tk = {}, deaths = {}, cons = {}, aura = {}, dur = 0, dmg = 0, taken = 0 }
  for _, c in ipairs(pending) do c.t = -1; table.insert(F.cons, c) end
  pending = {}
  active = {}
  for n in pairs(auraNames(false)) do active[n] = { since = GetTime() } end
  for n in pairs(auraNames(true)) do active[n] = { since = GetTime(), debuff = true } end
end
-- Octo writes stacks as "Frailty (1)" when they land but "Frailty" when they fade: keep one name
local function auraName(n) return (string.gsub(n or "", " %(%d+%)$", "")) end
local function closeAura(n)
  local a = active[n]
  if not a or not F then active[n] = nil return end
  local x = F.aura[n] or { s = 0, debuff = a.debuff and 1 or nil, n = 0 }
  x.s = x.s + (GetTime() - a.since)
  x.n = x.n + 1
  F.aura[n] = x
  active[n] = nil
end
local function fightName(f)
  local boss, best, bd = nil, nil, -1
  for who, x in pairs(f.tg) do
    if x.boss and not boss then boss = who end
    if x.d > bd then best, bd = who, x.d end
  end
  local name = boss or best or "Fight"
  local others = count(f.tg) - 1
  if not boss and others > 0 then name = name .. " +" .. others end
  return name, boss and 1 or nil
end
local function endFight()
  if not F then return end
  for n in pairs(active) do closeAura(n) end
  F.dur = r1(GetTime() - T0)
  for _, x in pairs(F.aura) do x.s = r1(x.s) end
  -- drop zero counts so a long raid keeps the saved file small
  local function trim(t) for _, x in pairs(t) do for k, v in pairs(x) do if v == 0 then x[k] = nil end end end end
  trim(F.ab); trim(F.tk)
  for _, x in pairs(F.tg) do if next(x.tk) == nil then x.tk = nil end if next(x.im) == nil then x.im = nil end end
  if F.dur >= 3 and (F.dmg > 0 or F.taken > 0 or table.getn(F.deaths) > 0) then
    F.name, F.boss = fightName(F)
    table.insert(LOG.fights, F)
    while table.getn(LOG.fights) > MAX_FIGHTS do table.remove(LOG.fights, 1) end
  end
  F = nil
end

-- ---------- your damage ----------
local function myHit(spell, who, amt, crit, glance)
  if not F then return end
  local a = abOf(spell); if not a then return end
  a.n = a.n + 1; a.h = a.h + 1; a.d = a.d + amt
  if crit then a.c = a.c + 1 end
  if glance then a.gl = a.gl + 1 end
  F.dmg = F.dmg + amt
  local x = tgOf(who); if x then x.d = x.d + amt end
end
local function myTick(spell, who, amt)
  if not F then return end
  local a = abOf(spell); if not a then return end
  a.t = a.t + 1; a.td = a.td + amt; a.d = a.d + amt
  F.dmg = F.dmg + amt
  local x = tgOf(who)
  if x then x.d = x.d + amt; x.tk[spell] = (x.tk[spell] or 0) + 1 end
end
local function myMiss(spell, who, kind)
  if not F then return end
  local a = abOf(spell); if not a then return end
  a.n = a.n + 1
  a[kind] = (a[kind] or 0) + 1
  if kind == "im" then local x = tgOf(who); if x then x.im[spell] = (x.im[spell] or 0) + 1 end end
end

-- ---------- damage you take ----------
local function took(src, spell, amt, crit, kind)
  if not F then return end
  local x = takenOf(src, spell); if not x then return end
  if kind then x.ms = x.ms + 1 return end
  x.n = x.n + 1; x.d = x.d + amt
  if crit then x.c = x.c + 1 end
  F.taken = F.taken + amt
  table.insert(recent, { t = r1(now()), s = src, a = spell or "Melee", d = amt, c = crit and 1 or nil, hp = UnitHealth("player") })
  if table.getn(recent) > LAST_HITS then table.remove(recent, 1) end
end

local MISS = { dodges = "dg", parries = "pr", blocks = "bl", misses = "ms", evades = "ms", absorbs = "ms" }

local function onMsg(msg)
  if not msg then return end
  local _, spell, who, amt, src, kind
  -- ---- you -> enemy ----
  _, _, spell, who = string.find(msg, "^Your (.-) failed%. (.-) is immune%.")
  if spell then myMiss(spell, who, "im") return end
  _, _, who, spell = string.find(msg, "^(.-) is immune to your (.-)%.")
  if who then myMiss(spell, who, "im") return end
  _, _, who, amt = string.find(msg, "^You hit (.-) for (%d+)")
  if amt then myHit("Auto attack", who, tonumber(amt), false, string.find(msg, "glancing") ~= nil) return end
  _, _, who, amt = string.find(msg, "^You crit (.-) for (%d+)")
  if amt then myHit("Auto attack", who, tonumber(amt), true) return end
  _, _, who = string.find(msg, "^You miss (.-)%.")
  if who then myMiss("Auto attack", who, "ms") return end
  _, _, who, kind = string.find(msg, "^You attack%. (.-) (%a+)%.")
  if who then myMiss("Auto attack", who, MISS[kind] or "ms") return end
  _, _, spell, who, amt = string.find(msg, "^Your (.-) hits (.-) for (%d+)")
  if spell then myHit(spell, who, tonumber(amt), false) return end
  _, _, spell, who, amt = string.find(msg, "^Your (.-) crits (.-) for (%d+)")
  if spell then myHit(spell, who, tonumber(amt), true) return end
  _, _, spell, who = string.find(msg, "^Your (.-) missed (.-)%.")
  if spell then myMiss(spell, who, "ms") return end
  _, _, spell, kind, who = string.find(msg, "^Your (.-) was (%a+) by (.-)%.")
  if spell then
    local k = ({ dodged = "dg", parried = "pr", blocked = "bl", resisted = "rs", evaded = "ms", absorbed = "ms" })[kind] or "ms"
    myMiss(spell, who, k) return
  end
  _, _, spell, who = string.find(msg, "^Your (.-) is parried by (.-)%.")
  if spell then myMiss(spell, who, "pr") return end
  _, _, who, amt, spell = string.find(msg, "^(.-) suffers (%d+) .-damage from your (.-)%.")
  if amt then myTick(spell, who, tonumber(amt)) return end
  -- ---- enemy -> you ----
  _, _, src, spell, amt = string.find(msg, "^(.-)'s (.-) hits you for (%d+)")
  if amt then took(src, spell, tonumber(amt), false) return end
  _, _, src, spell, amt = string.find(msg, "^(.-)'s (.-) crits you for (%d+)")
  if amt then took(src, spell, tonumber(amt), true) return end
  _, _, amt, src, spell = string.find(msg, "^You suffer (%d+) .-damage from (.-)'s (.-)%.")
  if amt then took(src, spell, tonumber(amt), false) return end
  _, _, src, amt = string.find(msg, "^(.-) hits you for (%d+)")
  if amt then took(src, nil, tonumber(amt), false) return end
  _, _, src, amt = string.find(msg, "^(.-) crits you for (%d+)")
  if amt then took(src, nil, tonumber(amt), true) return end
  _, _, src = string.find(msg, "^(.-) misses you%.")
  if src then took(src, nil, 0, false, "ms") return end
  _, _, src = string.find(msg, "^(.-) attacks%. You %a+%.")
  if src then took(src, nil, 0, false, "ms") return end
  _, _, src, spell = string.find(msg, "^(.-)'s (.-) was resisted%.")
  if src then took(src, spell, 0, false, "ms") return end
  _, _, src, spell = string.find(msg, "^(.-)'s (.-) misse?d? you%.")
  if src then took(src, spell, 0, false, "ms") return end
  -- ---- you ----
  if msg == "You die." then
    if F then
      local last = {}
      for _, h in ipairs(recent) do table.insert(last, h) end
      table.insert(F.deaths, { t = r1(now()), last = last })
    end
    return
  end
  _, _, spell = string.find(msg, "^You are afflicted by (.-)%.")
  if spell then spell = auraName(spell) end
  if spell then if not active[spell] then active[spell] = { since = GetTime(), debuff = true } end return end
  _, _, spell = string.find(msg, "^You gain (.-)%.$")
  if spell then spell = auraName(spell) end
  if spell and not string.find(spell, "^%d") then if not active[spell] then active[spell] = { since = GetTime() } end return end
  _, _, spell = string.find(msg, "^(.-) fades from you%.")
  if spell then closeAura(auraName(spell)) return end
end

-- ---------- consumables: anything you use from your bags ----------
local function usedItem(bag, slot)
  if not LOG then return end
  local link = GetContainerItemLink(bag, slot)
  if not link then return end
  local _, _, name = string.find(link, "%[(.-)%]")
  if not name then return end
  local _, _, id = string.find(link, "item:(%d+)")
  local _, _, _, _, itype = GetItemInfo(tonumber(id) or 0)
  if itype and itype ~= "Consumable" and itype ~= "Trade Goods" then return end
  local c = { n = name, id = tonumber(id) }
  if F then c.t = r1(now()); table.insert(F.cons, c) else table.insert(pending, c); if table.getn(pending) > 10 then table.remove(pending, 1) end end
end
-- potions on your action bars: read the button's name, then find that item in your bags
local function usedAction(slot)
  if not LOG or not slot or GetActionText(slot) then return end   -- GetActionText is set for macros: skip those
  tip:ClearLines()
  tip:SetAction(slot)
  local fs = getglobal("OPEFightTipTextLeft1")
  local name = fs and fs:GetText()
  if not name then return end
  for bag = 0, 4 do
    for s = 1, GetContainerNumSlots(bag) do
      local link = GetContainerItemLink(bag, s)
      if link and string.find(link, "[" .. name .. "]", 1, true) then usedItem(bag, s) return end
    end
  end
end
local origAction = UseAction
UseAction = function(slot, a2, a3)
  usedAction(slot)
  return origAction(slot, a2, a3)
end
local origUse = UseContainerItem
UseContainerItem = function(bag, slot, a3, a4)
  usedItem(bag, slot)
  return origUse(bag, slot, a3, a4)
end

-- ---------- every spell you cast (SuperWoW): Bash, Feral Charge, Roars and other spells that do no damage ----------
local MYGUID = nil
local preCasts = {}   -- casts in the 3 seconds before combat starts (Feral Charge, a pull) count for that fight
local function myCast(spellId)
  if not SpellInfo then return end
  local name = SpellInfo(spellId)
  if not name or name == "" then return end
  if not F then
    table.insert(preCasts, { n = name, at = GetTime() })
    if table.getn(preCasts) > 5 then table.remove(preCasts, 1) end
    return
  end
  local a = abOf(name); if a then a.u = a.u + 1 end
end
local function addPreCasts()
  for _, c in ipairs(preCasts) do
    if GetTime() - c.at <= 3 then local a = abOf(c.n); if a then a.u = a.u + 1 end end
  end
  preCasts = {}
end

-- ---------- events ----------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "CHAT_MSG_COMBAT_SELF_HITS", "CHAT_MSG_COMBAT_SELF_MISSES", "CHAT_MSG_SPELL_SELF_DAMAGE",
  "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE", "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS", "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES",
  "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE", "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE", "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS",
  "CHAT_MSG_SPELL_SELF_BUFF", "CHAT_MSG_SPELL_AURA_GONE_SELF", "CHAT_MSG_COMBAT_FRIENDLY_DEATH",
  "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT" }) do
  ev:RegisterEvent(e)
end
pcall(function() ev:RegisterEvent("UNIT_CASTEVENT") end)
ev:SetScript("OnEvent", function()
  if event == "PLAYER_ENTERING_WORLD" then
    -- continue a log that was running before a /reload or disconnect
    if not LOG then
      local c = charDB()
      if c and c.logs then
        for _, l in ipairs(c.logs) do if l.live then LOG = l end end
        if LOG then say("Fight log \"" .. (LOG.label or "log") .. "\" is still on (" .. table.getn(LOG.fights) .. " fights). /ope log stops it.") end
      end
    end
    return
  end
  if not LOG then return end
  if event == "UNIT_CASTEVENT" then
    if arg3 ~= "CAST" then return end
    if not MYGUID then local _, g = UnitExists("player"); MYGUID = g end
    if arg1 == MYGUID then myCast(arg4) end
    return
  end
  if event == "PLAYER_REGEN_DISABLED" then startFight(); addPreCasts() return end
  if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_LOGOUT" then endFight() return end
  if F then onMsg(arg1) elseif event == "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS" or event == "CHAT_MSG_SPELL_AURA_GONE_SELF" then onMsg(arg1) end
end)

-- Raw.lua reads the running log through this
function OPE_CurrentLog() return LOG end

function OPE_Log(arg)
  local c = charDB()
  if not c then say("Not ready yet, try again in a moment.") return end
  if arg == "clear" then
    c.logs = nil; LOG = nil; F = nil
    say("All saved fight logs for this character were deleted.")
    return
  end
  if LOG then
    endFight()
    LOG.live = nil
    LOG.ended = time()
    local fights = table.getn(LOG.fights)
    LOG = nil
    say("Fight log saved: " .. fights .. " fights. /reload or log out to write the file, then upload it to the planner.")
    return
  end
  c.logs = c.logs or {}
  LOG = { label = (arg and arg ~= "") and arg or nil, date = time(), zone = GetRealZoneText and GetRealZoneText() or "", live = 1, fights = {} }
  table.insert(c.logs, LOG)
  while table.getn(c.logs) > MAX_LOGS do table.remove(c.logs, 1) end
  if UnitAffectingCombat("player") then startFight() end
  say("Fight log on" .. (LOG.label and (" \"" .. LOG.label .. "\"") or "") .. ". Everything is recorded until you type /ope log again. A /reload keeps it going.")
end

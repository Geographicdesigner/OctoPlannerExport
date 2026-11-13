-- Octo Planner Export: the full record (WoW 1.12 / Lua 5.0)
-- While /ope log is on, this saves everything, in and out of combat, with the time since the log started:
--   every combat text line (you, your group, other players, enemies, pets), resets and boss emotes,
--   every spell cast near you with who cast it and on whom (SuperWoW): buffs, totems, blessings, heals, enemy casts,
--   your energy, rage, mana and health as they change (ticks, Furor, rage from hits),
--   your group and any swaps, your target, your zone, and when you enter and leave combat,
--   and the loot and money you and your group get,
--   and where you and your group stand: every second in combat, every 5 seconds out of combat (SuperWoW).
-- The planner splits it up. Lines: "time<TAB>code<TAB>text".

-- 400,000 lines covers a full 40-man Molten Core (200,000 ran out after about an hour)
local MAX_EV = 400000

-- other people's "gains 164 Mana from ..." lines are about a tenth of a raid log and the planner never uses them
local function skipLine(text)
  if not text then return false end
  local _, _, kind = string.find(text, "^%S+ gains %d+ (%a+) from ")
  return kind == "Mana" or kind == "Rage" or kind == "Energy"
end

-- combat text channels, saved as their number to keep the file small (the planner has the same list)
local CH = {
  "CHAT_MSG_COMBAT_SELF_HITS", "CHAT_MSG_COMBAT_SELF_MISSES", "CHAT_MSG_COMBAT_PET_HITS", "CHAT_MSG_COMBAT_PET_MISSES",
  "CHAT_MSG_COMBAT_PARTY_HITS", "CHAT_MSG_COMBAT_PARTY_MISSES", "CHAT_MSG_COMBAT_FRIENDLYPLAYER_HITS", "CHAT_MSG_COMBAT_FRIENDLYPLAYER_MISSES",
  "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS", "CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES", "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS", "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES",
  "CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS", "CHAT_MSG_COMBAT_CREATURE_VS_PARTY_MISSES", "CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS", "CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_MISSES",
  "CHAT_MSG_COMBAT_FRIENDLY_DEATH", "CHAT_MSG_COMBAT_HOSTILE_DEATH", "CHAT_MSG_COMBAT_XP_GAIN",
  "CHAT_MSG_SPELL_SELF_DAMAGE", "CHAT_MSG_SPELL_SELF_BUFF", "CHAT_MSG_SPELL_PET_DAMAGE", "CHAT_MSG_SPELL_PET_BUFF",
  "CHAT_MSG_SPELL_PARTY_DAMAGE", "CHAT_MSG_SPELL_PARTY_BUFF", "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE", "CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF",
  "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE", "CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF", "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE", "CHAT_MSG_SPELL_CREATURE_VS_SELF_BUFF",
  "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE", "CHAT_MSG_SPELL_CREATURE_VS_PARTY_BUFF", "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE", "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_BUFF",
  "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF", "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS", "CHAT_MSG_SPELL_AURA_GONE_SELF", "CHAT_MSG_SPELL_AURA_GONE_PARTY",
  "CHAT_MSG_SPELL_AURA_GONE_OTHER", "CHAT_MSG_SPELL_ITEM_ENCHANTMENTS", "CHAT_MSG_SPELL_BREAK_AURA",
  "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE", "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS", "CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE", "CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS",
  "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE", "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS", "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE", "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS",
  "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE", "CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS", "CHAT_MSG_SPELL_FAILED_LOCALPLAYER",
  "CHAT_MSG_MONSTER_EMOTE", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_SYSTEM", "CHAT_MSG_LOOT", "CHAT_MSG_MONEY"
}
local CHN = {}
for i, e in ipairs(CH) do CHN[e] = i end

local LOG, G0 = nil, 0
local full = false
local function clock() return GetTime() - G0 end
-- (re)attach to the running log; after a /reload, line the clock up again from the real time
local function attach()
  local l = OPE_CurrentLog and OPE_CurrentLog()
  if l ~= LOG then
    LOG = l; full = false
    if LOG then
      if not LOG.t0 then LOG.t0 = time(); LOG.ev = {}; G0 = GetTime()
      else G0 = GetTime() - (time() - LOG.t0) end
      LOG.ev = LOG.ev or {}
    end
  end
  return LOG
end
local function put(code, text)
  if not attach() or full then return end
  local ev = LOG.ev
  if table.getn(ev) >= MAX_EV then
    full = true
    DEFAULT_CHAT_FRAME:AddMessage("|cff9f7aea[Octo Planner Export]|r The full record is full (" .. MAX_EV .. " lines). Fight summaries keep going. /ope log twice starts a fresh one.")
    return
  end
  table.insert(ev, string.format("%.1f\t%s\t%s", clock(), code, text or ""))
end

-- ---------- group ----------
local lastGroup = ""
local function groupNow()
  local out = {}
  local function add(u, sub)
    if not UnitExists(u) then return end
    local _, cls = UnitClass(u)
    table.insert(out, (UnitName(u) or "?") .. ":" .. (cls or "?") .. ":" .. (UnitLevel(u) or 0) .. ":" .. (sub or 0))
  end
  local n = GetNumRaidMembers and GetNumRaidMembers() or 0
  if n > 0 then
    for i = 1, n do local name, _, sub = GetRaidRosterInfo(i); if name then add("raid" .. i, sub) end end
  else
    add("player", 1)
    for i = 1, GetNumPartyMembers() do add("party" .. i, 1) end
  end
  table.sort(out)
  return table.concat(out, ",")
end
local function checkGroup(force)
  local g = groupNow()
  if force or g ~= lastGroup then lastGroup = g; put("G", g) end
end

-- ---------- your energy, rage, mana and health ----------
local last = {}
local function power()
  local p = UnitMana("player") or 0
  local t = UnitPowerType and UnitPowerType("player") or 0
  local key = "P" .. t
  if last.pt ~= t or last.p ~= p then last.pt = t; last.p = p; put(key, p .. "/" .. (UnitManaMax("player") or 0)) end
end
local function health()
  local h = UnitHealth("player") or 0
  if last.h ~= h then last.h = h; put("H", h .. "/" .. (UnitHealthMax("player") or 0)) end
end

-- ---------- every cast near you (SuperWoW) ----------
local names = {}
local function nameOf(guid)
  if not guid or guid == "" or guid == "0x0000000000000000" then return "" end
  local n = names[guid]
  if n then return n end
  n = UnitName(guid) or ""
  if n ~= "" then names[guid] = n end
  return n
end

local ev = CreateFrame("Frame")
for _, e in ipairs(CH) do ev:RegisterEvent(e) end
for _, e in ipairs({ "UNIT_ENERGY", "UNIT_RAGE", "UNIT_MANA", "UNIT_HEALTH", "UNIT_DISPLAYPOWER", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
  "PLAYER_TARGET_CHANGED", "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_UNGHOST" }) do
  ev:RegisterEvent(e)
end
pcall(function() ev:RegisterEvent("UNIT_CASTEVENT") end)
local wasOn = false
ev:SetScript("OnEvent", function()
  if not attach() then wasOn = false return end
  if not wasOn then
    -- first event of a new or resumed log: write where we are and who is with us
    wasOn = true
    put("Z", (GetRealZoneText and GetRealZoneText() or "") .. "|" .. (GetSubZoneText and GetSubZoneText() or ""))
    checkGroup(true); last = {}; power(); health()
  end
  local c = CHN[event]
  if c then if not skipLine(arg1) then put(c, arg1) end return end
  if event == "UNIT_CASTEVENT" then
    if arg3 == "MAINHAND" or arg3 == "OFFHAND" then return end
    local sn, rank = "", ""
    if SpellInfo then sn, rank = SpellInfo(arg4) end
    put("S", arg3 .. "|" .. nameOf(arg1) .. "|" .. nameOf(arg2) .. "|" .. (sn or arg4 or "") .. "|" .. (rank or "") .. "|" .. (arg4 or "") .. "|" .. (arg5 or 0))
  elseif event == "UNIT_ENERGY" or event == "UNIT_RAGE" or event == "UNIT_MANA" or event == "UNIT_DISPLAYPOWER" then
    if arg1 == "player" then power() end
  elseif event == "UNIT_HEALTH" then
    if arg1 == "player" then health() end
  elseif event == "PLAYER_REGEN_DISABLED" then put("C", "1")
  elseif event == "PLAYER_REGEN_ENABLED" then put("C", "0")
  elseif event == "PLAYER_TARGET_CHANGED" then
    local _, guid = UnitExists("target")
    put("T", (UnitName("target") or "") .. "|" .. (UnitLevel("target") or "") .. "|" .. (UnitClassification and UnitClassification("target") or "") .. "|" .. (type(guid) == "string" and guid or ""))
  elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then checkGroup()
  elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
    put("Z", (GetRealZoneText and GetRealZoneText() or "") .. "|" .. (GetSubZoneText and GetSubZoneText() or ""))
    checkGroup()
  elseif event == "PLAYER_DEAD" then put("D", "1")
  elseif event == "PLAYER_UNGHOST" then put("D", "0")
  end
end)

-- ---------- where everyone stands ----------
-- "X" lines: name:x:y;name:x:y in world yards (SuperWoW UnitPosition). Only people who moved more than a yard,
-- plus everyone every 10 seconds. Without SuperWoW, "Y" lines use the map position (0-1000) where the zone has a map.
local posLast, posFull, posT = {}, 0, 0
local function units()
  local u = {}
  local n = GetNumRaidMembers and GetNumRaidMembers() or 0
  if n > 0 then for i = 1, n do table.insert(u, "raid" .. i) end
  else table.insert(u, "player"); for i = 1, GetNumPartyMembers() do table.insert(u, "party" .. i) end end
  return u
end
local function samplePos()
  local now = GetTime()
  local all = now - posFull >= 10
  if all then posFull = now end
  local out, code = {}, "X"
  local useMap = not UnitPosition
  if useMap then
    if WorldMapFrame and WorldMapFrame:IsVisible() then return end
    if SetMapToCurrentZone then SetMapToCurrentZone() end
    code = "Y"
  end
  for _, u in ipairs(units()) do
    if UnitExists(u) and not UnitIsDeadOrGhost(u) then
      local name = UnitName(u)
      local x, y
      if useMap then
        local a, b = GetPlayerMapPosition(u)
        if a and (a > 0 or b > 0) then x, y = math.floor(a * 1000 + 0.5), math.floor(b * 1000 + 0.5) end
      else
        local ok, a, b = pcall(UnitPosition, u)
        if ok and a then x, y = math.floor(a * 10 + 0.5) / 10, math.floor(b * 10 + 0.5) / 10 end
      end
      if name and x then
        local l = posLast[name]
        if all or not l or math.abs(l[1] - x) + math.abs(l[2] - y) >= 1 then
          posLast[name] = { x, y }
          table.insert(out, name .. ":" .. x .. ":" .. y)
        end
      end
    end
  end
  if table.getn(out) > 0 then put(code, table.concat(out, ";")) end
end
local pf = CreateFrame("Frame")
pf:SetScript("OnUpdate", function()
  if not attach() then return end
  local now = GetTime()
  local every = UnitAffectingCombat("player") and 1 or 5
  if now - posT < every then return end
  posT = now
  samplePos()
end)

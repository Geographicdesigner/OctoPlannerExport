-- Octo Planner Export: the full record (WoW 1.12 / Lua 5.0)
-- While /ope log is on, this saves everything, in and out of combat, with the time since the log started:
--   every combat text line (you, your group, other players, enemies, pets), resets and boss emotes,
--   every spell cast near you with who cast it and on whom (SuperWoW): buffs, totems, blessings, heals, enemy casts,
--   your energy, rage, mana and health as they change (ticks, Furor, rage from hits),
--   your group and any swaps, your target, your zone, and when you enter and leave combat.
-- The planner splits it up. Lines: "time<TAB>code<TAB>text".

local MAX_EV = 200000

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
  "CHAT_MSG_MONSTER_EMOTE", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_SYSTEM", "CHAT_MSG_LOOT"
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
  if c then put(c, arg1) return end
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

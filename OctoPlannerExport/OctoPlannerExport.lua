-- Octo Planner Export (WoW 1.12 / Lua 5.0)
-- 1) Saves every character's talents when you log in or spend a point.
-- 2) /ope scan asks the server for each item in ItemList.lua, slowly, and saves the tooltip text and icon.
-- 3) Saves what each character wears, carries and keeps in the bank (with tooltips, enchants and icons) and their professions.
-- Everything is written to WTF/Account/<ACCOUNT>/SavedVariables/OctoPlannerExport.lua when you log out or reload.
-- v3: nothing is read at logout any more (the game has already emptied bags and talents by then, which wiped v2's data);
--     gear, bags, talents and professions are saved while you play and never overwritten with empty data.

local VERSION = 5
local PREFIX = "|cff9f7aea[Octo Planner Export]|r "
local DEFAULT_RATE = 4      -- items per second
local MAX_TRIES = 4         -- passes over an item before giving up on it
local RETRY_DELAY = 2       -- seconds before re-reading an item the server hasn't answered yet

local function say(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) end

local function initDB()
  if type(OctoPlannerExportDB) ~= "table" then OctoPlannerExportDB = {} end
  local db = OctoPlannerExportDB
  db.version = VERSION
  db.chars = db.chars or {}
  db.items = db.items or {}
  db.scan = db.scan or { pos = 0, tries = {}, failed = {}, rate = DEFAULT_RATE, running = false }
  db.scan.tries = db.scan.tries or {}
  db.scan.failed = db.scan.failed or {}
  db.scan.rate = db.scan.rate or DEFAULT_RATE
  return db
end

-- ---------- talents ----------
local function saveTalents()
  local db = initDB()
  local name, realm = UnitName("player"), GetRealmName()
  if not name or not realm then return end
  local _, classToken = UnitClass("player")
  local c = { tabs = {}, talents = {} }
  local tabs = GetNumTalentTabs() or 0
  for tab = 1, tabs do
    local tabName, _, points = GetTalentTabInfo(tab)
    c.tabs[tab] = { name = tabName, points = points or 0 }
    local n = GetNumTalents(tab) or 0
    for i = 1, n do
      local tName, _, tier, column, rank, maxRank = GetTalentInfo(tab, i)
      if tName then
        table.insert(c.talents, { tab = tab, index = i, tier = tier, column = column, rank = rank or 0, max = maxRank, name = tName })
      end
    end
  end
  if table.getn(c.talents) == 0 then return end
  local key = name .. " - " .. realm
  local e = db.chars[key] or {}
  db.chars[key] = e
  e.name = name; e.realm = realm; e.class = classToken; e.race = UnitRace("player"); e.time = time()
  local lvl = UnitLevel("player"); if lvl and lvl > 0 then e.level = lvl end
  e.tabs = c.tabs; e.talents = c.talents
end

-- ---------- what the character owns ----------
local gtip = CreateFrame("GameTooltip", "OPEGearTip", nil, "GameTooltipTemplate")
gtip:SetOwner(WorldFrame, "ANCHOR_NONE")
local function gearTooltip(setter)
  gtip:ClearLines(); gtip:SetOwner(WorldFrame, "ANCHOR_NONE"); setter(gtip)
  local n = gtip:NumLines() or 0
  if n == 0 then return nil end
  local lines = {}
  for i = 1, n do
    local l, r = getglobal("OPEGearTipTextLeft" .. i), getglobal("OPEGearTipTextRight" .. i)
    local lt = l and l:GetText() or ""
    local rt = r and r:IsShown() and r:GetText() or nil
    if rt and rt ~= "" then lt = lt .. "   " .. rt end
    table.insert(lines, lt)
  end
  return table.concat(lines, "\n")
end
local function linkId(link) local _, _, id = string.find(link or "", "item:(%d+)"); return tonumber(id) end
local function isGear(link) local id = linkId(link); if not id then return false end local _, _, _, _, _, _, _, loc = GetItemInfo(id); return loc and loc ~= "" end
local SLOTS = { "HeadSlot","NeckSlot","ShoulderSlot","ShirtSlot","ChestSlot","WaistSlot","LegsSlot","FeetSlot","WristSlot","HandsSlot","Finger0Slot","Finger1Slot","Trinket0Slot","Trinket1Slot","BackSlot","MainHandSlot","SecondaryHandSlot","RangedSlot","TabardSlot" }
local function charEntry()
  local db = initDB(); local name, realm = UnitName("player"), GetRealmName()
  if not name or not realm then return nil end
  local key = name .. " - " .. realm
  db.chars[key] = db.chars[key] or { name = name, realm = realm }
  return db.chars[key]
end
local function saveEquipped()
  local c = charEntry(); if not c then return end
  local out, n = {}, 0
  for _, sk in ipairs(SLOTS) do
    local slot = GetInventorySlotInfo(sk)
    local link = GetInventoryItemLink("player", slot)
    if link then
      n = n + 1
      out[sk] = { link = link, icon = GetInventoryItemTexture("player", slot), t = gearTooltip(function(t) t:SetInventoryItem("player", slot) end) }
    end
  end
  if n > 0 then c.equipped = out; c.time = time() end
end
local function saveBags(bags, field)
  local c = charEntry(); if not c then return end
  local out, slots = {}, 0
  for _, bag in ipairs(bags) do
    local size = GetContainerNumSlots(bag) or 0
    slots = slots + size
    for slot = 1, size do
      local link = GetContainerItemLink(bag, slot)
      if link then
        local tex, count = GetContainerItemInfo(bag, slot)
        local e = { link = link, count = count, icon = tex, bag = bag }
        if isGear(link) then e.t = gearTooltip(function(t) t:SetBagItem(bag, slot) end) end
        table.insert(out, e)
      end
    end
  end
  if slots > 0 then c[field] = out end  -- 0 slots means the game isn't ready (loading or logging out): keep what we had
end
local function saveSkills()
  local c = charEntry(); if not c then return end
  local out, n = {}, 0
  for i = 1, (GetNumSkillLines() or 0) do
    local sname, header, _, rank = GetSkillLineInfo(i)
    if sname and not header and rank then out[sname] = rank; n = n + 1 end
  end
  if n > 0 then c.skills = out end
end
-- spellbook: highest rank of every spell with its in-game tooltip (Octo's own numbers and extra ranks)
local function saveSpells()
  local c = charEntry(); if not c then return end
  local out, n = {}, 0
  for tab = 1, (GetNumSpellTabs() or 0) do
    local _, _, offset, num = GetSpellTabInfo(tab)
    for i = offset + 1, offset + (num or 0) do
      local sname, rank = GetSpellName(i, "spell")
      if sname then
        out[sname] = { r = rank or "", i = GetSpellTexture(i, "spell"), t = gearTooltip(function(t) t:SetSpell(i, "spell") end) }
        n = n + 1
      end
    end
  end
  if n > 0 then c.spells = out end
end
local atBank = false

-- ---------- item scan ----------
local tip = CreateFrame("GameTooltip", "OPEScanTip", nil, "GameTooltipTemplate")
tip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function readTooltip(id)
  tip:ClearLines()
  tip:SetOwner(WorldFrame, "ANCHOR_NONE")
  tip:SetHyperlink("item:" .. id .. ":0:0:0")
  local n = tip:NumLines() or 0
  if n == 0 then return nil end
  local first = getglobal("OPEScanTipTextLeft1")
  if not first or not first:GetText() or first:GetText() == "" then return nil end
  local lines = {}
  for i = 1, n do
    local l = getglobal("OPEScanTipTextLeft" .. i)
    local r = getglobal("OPEScanTipTextRight" .. i)
    local lt = l and l:GetText() or ""
    local rt = r and r:IsShown() and r:GetText() or nil
    if rt and rt ~= "" then lt = lt .. "   " .. rt end
    table.insert(lines, lt)
  end
  return table.concat(lines, "\n")
end

local function iconOf(id)
  local _, _, _, _, _, _, _, _, tex = GetItemInfo(id)
  if tex then local _, _, short = string.find(tex, "([^\\]+)$"); return short or tex end
  return nil
end

local scanner = CreateFrame("Frame")
local acc, waiting = 0, {}   -- waiting[id] = time we asked

local function total() return table.getn(OPE_ITEM_IDS or {}) end

local function finishScan()
  local db = initDB()
  db.scan.running = false
  scanner:Hide()
  local got, failed = 0, 0
  for _ in pairs(db.items) do got = got + 1 end
  for _ in pairs(db.scan.failed) do failed = failed + 1 end
  db.scan.finished = time()
  say("Scan finished: " .. got .. " items saved, " .. failed .. " the server never answered. Log out to write the file.")
end

local function step()
  local db = initDB()
  local s = db.scan
  -- first, re-read items we asked for a moment ago
  local now = GetTime()
  for id, t in pairs(waiting) do
    if now - t >= RETRY_DELAY then
      local text = readTooltip(id)
      if text then
        local _, _, quality = GetItemInfo(id)
        db.items[id] = { t = text, q = quality, i = iconOf(id) }
        waiting[id] = nil
      else
        s.tries[id] = (s.tries[id] or 0) + 1
        if s.tries[id] >= MAX_TRIES then s.failed[id] = true; waiting[id] = nil
        else waiting[id] = now end
      end
      return
    end
  end
  -- then ask about the next item
  if s.pos >= total() then
    local left = 0
    for _ in pairs(waiting) do left = left + 1 end
    if left == 0 then finishScan() end
    return
  end
  s.pos = s.pos + 1
  local id = OPE_ITEM_IDS[s.pos]
  while ((db.items[id] and db.items[id].i) or s.failed[id]) and s.pos < total() do s.pos = s.pos + 1; id = OPE_ITEM_IDS[s.pos] end
  if (db.items[id] and db.items[id].i) or s.failed[id] then return end
  local text = readTooltip(id)
  if text then
    local _, _, quality = GetItemInfo(id)
    db.items[id] = { t = text, q = quality, i = iconOf(id) }
  else
    waiting[id] = GetTime()
  end
  if math.mod(s.pos, 250) == 0 then
    say(string.format("%d / %d items (%d%%)", s.pos, total(), math.floor(s.pos * 100 / total())))
  end
end

scanner:SetScript("OnUpdate", function()
  local db = initDB()
  acc = acc + arg1
  local interval = 1 / (db.scan.rate or DEFAULT_RATE)
  if acc >= interval then acc = 0; step() end
end)
scanner:Hide()

local function startScan(restart)
  local db = initDB()
  if restart then db.items = {}; db.scan = { pos = 0, tries = {}, failed = {}, rate = db.scan.rate or DEFAULT_RATE } end
  db.scan.running = true
  waiting = {}
  scanner:Show()
  local mins = math.ceil((total() - db.scan.pos) / (db.scan.rate or DEFAULT_RATE) / 60)
  say(string.format("Scanning from item %d of %d, about %d min. Stay in a quiet place; /ope stop pauses it. Progress is kept if you log out.", db.scan.pos, total(), mins))
end

-- ---------- events ----------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("CHARACTER_POINTS_CHANGED")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:RegisterEvent("BANKFRAME_OPENED")
ev:RegisterEvent("BANKFRAME_CLOSED")
ev:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
ev:RegisterEvent("UNIT_INVENTORY_CHANGED")
ev:RegisterEvent("BAG_UPDATE")
ev:RegisterEvent("SKILL_LINES_CHANGED")
ev:RegisterEvent("LEARNED_SPELL_IN_TAB")
ev:RegisterEvent("SPELLS_CHANGED")
-- saves are batched a couple of seconds after the last change, so looting or swapping gear never stutters
local due = {}
local saver = CreateFrame("Frame")
saver:Hide()
saver:SetScript("OnUpdate", function()
  local now, left = GetTime(), false
  for what, t in pairs(due) do
    if now >= t then
      due[what] = nil
      if what == "talents" then saveTalents()
      elseif what == "equipped" then saveEquipped()
      elseif what == "bags" then saveBags({ 0, 1, 2, 3, 4 }, "bags")
      elseif what == "skills" then saveSkills()
      elseif what == "spells" then saveSpells() end
    else left = true end
  end
  if not left then saver:Hide() end
end)
local function later(what, secs) due[what] = GetTime() + (secs or 2); saver:Show() end
local function saveAllNow() saveTalents(); saveEquipped(); saveBags({ 0, 1, 2, 3, 4 }, "bags"); saveSkills(); saveSpells() end
ev:SetScript("OnEvent", function()
  initDB()
  if event == "PLAYER_LOGOUT" then return end  -- too late to read anything; the file is written from what was saved while playing
  if event == "PLAYER_ENTERING_WORLD" then later("talents", 3); later("equipped", 3); later("bags", 3); later("skills", 3); later("spells", 4) end
  if event == "LEARNED_SPELL_IN_TAB" or event == "SPELLS_CHANGED" then later("spells", 3) end
  if event == "CHARACTER_POINTS_CHANGED" then later("talents", 1) end
  if event == "UNIT_INVENTORY_CHANGED" and arg1 == "player" then later("equipped") end
  if event == "BAG_UPDATE" then later("bags") end
  if event == "SKILL_LINES_CHANGED" then later("skills") end
  if event == "BANKFRAME_OPENED" then atBank = true end
  if event == "BANKFRAME_CLOSED" then atBank = false end
  if (event == "BANKFRAME_OPENED" or event == "PLAYERBANKSLOTS_CHANGED") and atBank then saveBags({ -1, 5, 6, 7, 8, 9, 10 }, "bank") end
  if event == "PLAYER_ENTERING_WORLD" and OctoPlannerExportDB.scan.running and not scanner:IsShown() then
    say("Resuming the item scan where it stopped (/ope stop to pause).")
    startScan(false)
  end
end)

-- ---------- slash command ----------
SLASH_OCTOPLANNEREXPORT1 = "/ope"
SlashCmdList["OCTOPLANNEREXPORT"] = function(msg)
  local db = initDB()
  msg = string.lower(msg or "")
  local _, _, cmd, arg = string.find(msg, "^(%S*)%s*(.-)$")
  if cmd == "scan" then
    if db.scan.pos >= total() and not db.scan.running then
      -- second pass: keep everything already saved, only fill in items without an icon
      local missing = 0
      for _, id in ipairs(OPE_ITEM_IDS) do local e = db.items[id]; if e and not e.i then missing = missing + 1 end end
      if missing == 0 then say("All items are saved with icons. Use /ope rescan to start over.") return end
      db.scan.pos = 0; db.scan.tries = {}
      say(missing .. " saved items still need an icon; going through the list again (items that are done are skipped instantly).")
    end
    startScan(false)
  elseif cmd == "rescan" then startScan(true)
  elseif cmd == "stop" then db.scan.running = false; scanner:Hide(); say("Paused at item " .. db.scan.pos .. ". /ope scan continues.")
  elseif cmd == "speed" then
    local n = tonumber(arg)
    if n and n >= 1 and n <= 10 then db.scan.rate = n; say("Speed set to " .. n .. " items per second.")
    else say("Use /ope speed 1 to 10 (default " .. DEFAULT_RATE .. "). Lower is safer if you get disconnected.") end
  elseif cmd == "cc" then
    OPE_CCWatch()
  elseif cmd == "log" then
    OPE_Log(arg)
  elseif cmd == "dummy" then
    OPE_Dummy(arg)
  elseif cmd == "talents" or cmd == "save" then
    saveAllNow()
    local c = charEntry() or {}
    local eq, bg = 0, 0
    for _ in pairs(c.equipped or {}) do eq = eq + 1 end
    bg = table.getn(c.bags or {})
    say("Saved: " .. table.getn(c.talents or {}) .. " talents, " .. eq .. " worn items, " .. bg .. " bag items, " .. table.getn(c.bank or {}) .. " bank items. /reload or log out to write the file.")
  else
    local got = 0
    for _ in pairs(db.items) do got = got + 1 end
    say("Talents, worn gear, bags, bank (open it once) and professions are saved automatically. Items scanned: " .. got .. " of " .. total() .. (db.scan.running and " (scanning)" or "") .. ".")
    say("/ope scan  start or continue the item scan    /ope stop  pause it")
    say("/ope speed N  items per second (1-10)    /ope rescan  start over    /ope save  save gear, bags and talents now")
    say("/ope dummy [name]  record your damage on a dummy, again to stop    /ope dummy clear  delete saved runs")
    say("/ope log [name]  record everything in a raid or dungeon (fights, casts, group, time between pulls), again to stop    /ope log clear  delete saved logs")
    say("/ope cc  show in chat which ability uses each Clearcasting (on/off)")
    say("When done, log out and upload SavedVariables/OctoPlannerExport.lua to the planner.")
  end
end

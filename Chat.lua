-- Octo Planner Export: chat record (5.11)
-- Keeps what people write in chat, apart from the fight log, in its own table (OctoPlannerChatDB).
-- It is saved in the same OctoPlannerExport.lua file, so one upload brings both, but the site keeps them separate.
-- Every line says which chat it came from (say, yell, party, raid, guild, whisper, a channel ...),
-- so the site can show them split by chat.
-- It also turns on the game's own chat log (Logs/WoWChatLog.txt).
--
-- Line format: "<seconds since the session start>\t<chat>\t<who>\t<text>"
-- chat is one of: say yell emote party raid rl rw bg bgl guild officer wfrom wto ch:<name> sys
--   npcsay npcyell npcemote npcwhisper   (rl = raid leader, rw = raid warning, wfrom/wto = whispers in/out)

local PREFIX = "|cff9f7aea[Octo Planner Export]|r "
local function say(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) end

local KEEP_DAYS = 14         -- sessions older than this are dropped at login
local MAX_LINES = 40000      -- and the oldest sessions go when all of them together pass this
local GAP = 30 * 60          -- a login within 30 minutes of the last line carries on the same session

local KIND = {
  CHAT_MSG_SAY = "say", CHAT_MSG_YELL = "yell", CHAT_MSG_EMOTE = "emote", CHAT_MSG_TEXT_EMOTE = "emote",
  CHAT_MSG_PARTY = "party", CHAT_MSG_RAID = "raid", CHAT_MSG_RAID_LEADER = "rl", CHAT_MSG_RAID_WARNING = "rw",
  CHAT_MSG_BATTLEGROUND = "bg", CHAT_MSG_BATTLEGROUND_LEADER = "bgl",
  CHAT_MSG_GUILD = "guild", CHAT_MSG_OFFICER = "officer",
  CHAT_MSG_WHISPER = "wfrom", CHAT_MSG_WHISPER_INFORM = "wto",
  CHAT_MSG_CHANNEL = "ch", CHAT_MSG_SYSTEM = "sys",
  CHAT_MSG_MONSTER_SAY = "npcsay", CHAT_MSG_MONSTER_YELL = "npcyell",
  CHAT_MSG_MONSTER_EMOTE = "npcemote", CHAT_MSG_MONSTER_WHISPER = "npcwhisper",
}

-- channels that only carry addon data, never words people wrote
local SKIP_CHANNEL = { lft = true }

local S          -- the current session
local db

local function initDB()
  if type(OctoPlannerChatDB) ~= "table" then OctoPlannerChatDB = {} end
  db = OctoPlannerChatDB
  db.v = 1
  if db.on == nil then db.on = true end
  if db.file == nil then db.file = true end
  db.sessions = db.sessions or {}
  return db
end

local function trim()
  local now = time()
  local keep, total = {}, 0
  -- newest first, so the oldest are the ones dropped
  for i = table.getn(db.sessions), 1, -1 do
    local s = db.sessions[i]
    local n = table.getn(s.lines or {})
    if s.t0 and now - s.t0 < KEEP_DAYS * 86400 and total + n <= MAX_LINES and n > 0 then
      table.insert(keep, 1, s); total = total + n
    end
  end
  db.sessions = keep
end

local function startSession()
  local name, realm = UnitName("player"), GetRealmName and GetRealmName() or ""
  local last = db.sessions[table.getn(db.sessions)]
  if last and last.char == name and last.realm == realm and last.last and time() - last.last < GAP then
    S = last
  else
    S = { t0 = time(), date = date("%Y-%m-%d %H:%M:%S"), char = name, realm = realm, lines = {} }
    table.insert(db.sessions, S)
  end
end

-- addon traffic looks like "PWB:10610:A-O-09..." or "AuxData,..." : one word, no spaces, with : or ,
local function isAddonData(msg)
  if string.find(msg, " ") then return false end
  return string.len(msg) > 6 and string.find(msg, "^[%a_]+[%w_]*[:,]") ~= nil and string.find(msg, "%d") ~= nil
end

local function clean(s)
  s = string.gsub(s or "", "[\t\n\r]", " ")
  return s
end

local function record(event)
  if not db or not db.on or not S then return end
  local kind = KIND[event]
  if not kind then return end
  local msg, who = arg1 or "", arg2 or ""
  if msg == "" then return end
  if kind == "ch" then
    -- arg9 is the channel name; arg4 looks like "6. World"
    local cname = arg9
    if not cname or cname == "" then
      local _, _, n = string.find(arg4 or "", "^%d+%.%s*(.+)$")
      cname = n or arg4 or "?"
    end
    local _, _, base = string.find(cname, "^(.-)%s+%-%s+")   -- "General - Stormwind" -> "General"
    cname = base or cname
    if SKIP_CHANNEL[string.lower(cname)] or isAddonData(msg) then return end
    kind = "ch:" .. cname
  elseif kind ~= "sys" and isAddonData(msg) then
    return
  end
  local now = time()
  table.insert(S.lines, (now - S.t0) .. "\t" .. kind .. "\t" .. clean(who) .. "\t" .. clean(msg))
  S.last = now
end

local function fileLog()
  if not LoggingChat then return end
  if db.file and not LoggingChat() then LoggingChat(1) end
end

local ev = CreateFrame("Frame")
for e in pairs(KIND) do pcall(function() ev:RegisterEvent(e) end) end
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function()
  if event == "PLAYER_ENTERING_WORLD" then
    if not S then initDB(); trim(); startSession() end
    fileLog()
    return
  end
  record(event)
end)

function OPE_Chat(arg)
  initDB()
  arg = string.lower(arg or "")
  if arg == "off" then db.on = false; say("Chat record is off. /ope chat on turns it back on.")
  elseif arg == "on" then db.on = true; say("Chat record is on.")
  elseif arg == "file off" then
    db.file = false; if LoggingChat then LoggingChat(0) end; say("The game's chat log file (Logs/WoWChatLog.txt) is off.")
  elseif arg == "file on" then
    db.file = true; fileLog(); say("The game's chat log file (Logs/WoWChatLog.txt) is on.")
  elseif arg == "clear" then
    db.sessions = {}; S = nil; startSession(); say("Saved chat deleted.")
  else
    local n = 0
    for _, s in ipairs(db.sessions) do n = n + table.getn(s.lines or {}) end
    say("Chat record is " .. (db.on and "on" or "off") .. ": " .. n .. " lines in " .. table.getn(db.sessions) .. " sessions (kept " .. KEEP_DAYS .. " days). Game chat log file: " .. ((LoggingChat and LoggingChat()) and "on" or "off") .. ".")
    say("/ope chat on | off    /ope chat file on | off  (Logs/WoWChatLog.txt)    /ope chat clear  delete saved chat")
  end
end

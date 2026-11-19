-- Octo Planner Export: which client mods (DLLs) and add-ons this game has, and their versions (WoW 1.12 / Lua 5.0)
-- /ope dll   lists them in chat with a check mark or a cross.
-- The same list is saved with your character and at the start of every log ("V" line), so the planner
-- can show who recorded with which versions.
-- It also works out in which order SuperWoW gives positions (x, y or y, x): some versions swap them.
-- Outdoors, your map position and your world position move together; comparing the two tells the order.
-- The answer is saved and written to the log as an "O" line (xy or yx), and the planner turns the map to match.

local PREFIX = "|cff9f7aea[Octo Planner Export]|r "
local function say(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) end

local function addonVer(name)
  if not GetAddOnInfo then return nil end
  local _, _, _, enabled, loadable = GetAddOnInfo(name)
  if not loadable and not enabled and not (IsAddOnLoaded and IsAddOnLoaded(name)) then return nil end
  local v = GetAddOnMetadata and GetAddOnMetadata(name, "Version")
  return (v and v ~= "") and v or "yes"
end

-- every value is a short string, or nil when it is not there
function OPE_ClientInfo()
  local I = {}
  if GetBuildInfo then
    local v, b = GetBuildInfo()
    I.client = (v or "?") .. (b and (" " .. b) or "")
  end
  -- SuperWoW: sets SUPERWOW_VERSION; older builds only add its functions
  if SUPERWOW_VERSION then I.superwow = tostring(SUPERWOW_VERSION)
  elseif SpellInfo or UnitPosition or ExportFile then I.superwow = "yes (no version number)" end
  -- Nampower
  if GetNampowerVersion then
    local ok, a, b, c = pcall(GetNampowerVersion)
    if ok and a then I.nampower = tostring(a) .. (b and ("." .. b) or "") .. (c and ("." .. c) or "")
    else I.nampower = "yes (no version number)" end
  elseif QueueSpellByName or GetCastInfo or GetSpellIdForName then I.nampower = "yes (no version number)" end
  -- UnitXP Service Pack 3
  if UnitXP then
    local ok, v = pcall(UnitXP, "version", "coffTimeDateStamp")
    if ok and type(v) == "number" and v > 0 then I.unitxp = date("%Y-%m-%d", v)
    else
      local ok2, v2 = pcall(UnitXP, "version")
      I.unitxp = (ok2 and v2 and tostring(v2)) or "yes (no version number)"
    end
  end
  -- SuperMacro: only the Turtle WoW version has buffed() and the Extended LUA code box
  local sm = addonVer("SuperMacro")
  if sm then I.supermacro = sm .. (buffed and " (Turtle WoW version)" or " (not the Turtle WoW version: no buffed())") end
  I.ope = GetAddOnMetadata and GetAddOnMetadata("OctoPlannerExport", "Version") or "?"
  local db = OctoPlannerExportDB
  if db and db.xy and db.xy.order then I.xy = db.xy.order end
  return I
end

local ORDER = { "ope", "client", "superwow", "nampower", "unitxp", "supermacro", "xy" }
-- one line: ope=5.9;client=1.12.1 5875;superwow=1.5;...
function OPE_ClientLine()
  local I, out = OPE_ClientInfo(), {}
  for _, k in ipairs(ORDER) do
    if I[k] then table.insert(out, k .. "=" .. string.gsub(I[k], "[;=\t\n]", " ")) end
  end
  return table.concat(out, ";")
end

function OPE_ClientSay()
  local I = OPE_ClientInfo()
  local ok, no = "|cff40c040OK|r ", "|cffff4040MISSING|r "
  say("Octo Planner Export " .. (I.ope or "?") .. ", game " .. (I.client or "?"))
  say((I.superwow and ok or no) .. "SuperWoW " .. (I.superwow or "- the logs, casts and macros need it"))
  say((I.unitxp and ok or no) .. "UnitXP Service Pack 3 " .. (I.unitxp or "- the cat macros (behind, distance) and boss positions need it"))
  say((I.nampower and ok or no) .. "Nampower " .. (I.nampower or "- the macros are made for its spell queue"))
  if I.supermacro and buffed then say(ok .. "SuperMacro " .. I.supermacro)
  elseif I.supermacro then say(no .. "SuperMacro " .. I.supermacro)
  else say(no .. "SuperMacro (Turtle WoW version) - the macros need it") end
  if I.xy then say("Positions: " .. (I.xy == "xy" and "normal order" or "swapped (the planner turns them back)"))
  elseif UnitPosition then say("Positions: order not known yet. Walk around outdoors for a few seconds.") end
end

-- ---------- position order ----------
local S1, S2, n, lastA, lastB, lastMX, lastMY, acc = 0, 0, 0, nil, nil, nil, nil, 0
local f = CreateFrame("Frame")
f:SetScript("OnUpdate", function()
  acc = acc + (arg1 or 0)
  if acc < 0.5 then return end
  acc = 0
  local db = OctoPlannerExportDB
  if type(db) ~= "table" or not UnitPosition then return end
  local sw = SUPERWOW_VERSION and tostring(SUPERWOW_VERSION) or "?"
  if db.xy and db.xy.sw == sw and db.xy.order then f:Hide() return end
  if WorldMapFrame and WorldMapFrame:IsVisible() then return end
  if SetMapToCurrentZone then SetMapToCurrentZone() end
  local mx, my = GetPlayerMapPosition("player")
  local ok, a, b = pcall(UnitPosition, "player")
  if not ok or not a or not mx or (mx == 0 and my == 0) then lastA = nil return end
  if lastA then
    local da, db2, dmx = a - lastA, b - lastB, mx - lastMX
    if math.abs(da) + math.abs(db2) > 0.5 and dmx ~= 0 then
      -- map x grows east; world x grows north and world y grows west, so east is minus world y
      S1 = S1 + dmx * -db2
      S2 = S2 + dmx * -da
      n = n + 1
      if n >= 12 then
        local x1, x2 = math.abs(S1), math.abs(S2)
        if S1 > 0 and x1 > 3 * x2 then db.xy = { order = "xy", sw = sw }
        elseif S2 > 0 and x2 > 3 * x1 then db.xy = { order = "yx", sw = sw } end
        if db.xy and db.xy.order and db.xy.sw == sw then
          if OPE_RawPut then OPE_RawPut("O", db.xy.order) end
          S1, S2, n, lastA = 0, 0, 0, nil
          f:Hide()
        elseif n > 200 then S1, S2, n = 0, 0, 0 end
      end
    end
  end
  lastA, lastB, lastMX, lastMY = a, b, mx, my
end)

-- ---------- a fight summary as one line of JSON, for the "F" lines ----------
local function esc(s)
  s = string.gsub(s, "\\", "\\\\"); s = string.gsub(s, '"', '\\"')
  s = string.gsub(s, "\n", "\\n"); s = string.gsub(s, "\r", "\\r"); s = string.gsub(s, "\t", "\\t")
  return '"' .. s .. '"'
end
local function isArray(t)
  local n = table.getn(t)
  if n == 0 then return next(t) == nil end
  local k = 0
  for _ in pairs(t) do k = k + 1 end
  return k == n
end
function OPE_Json(v, depth)
  depth = depth or 0
  local tv = type(v)
  if tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "0" end
    if math.floor(v) == v then return string.format("%d", v) end
    return string.format("%.3f", v)
  elseif tv == "string" then return esc(v)
  elseif tv == "boolean" then return v and "true" or "false"
  elseif tv == "table" and depth < 8 then
    local out = {}
    if isArray(v) and next(v) ~= nil then
      for i = 1, table.getn(v) do table.insert(out, OPE_Json(v[i], depth + 1)) end
      return "[" .. table.concat(out, ",") .. "]"
    end
    for k, x in pairs(v) do
      local tx = type(x)
      if tx ~= "function" and tx ~= "userdata" then table.insert(out, esc(tostring(k)) .. ":" .. OPE_Json(x, depth + 1)) end
    end
    return "{" .. table.concat(out, ",") .. "}"
  end
  return "null"
end

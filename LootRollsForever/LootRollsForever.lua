local ADDON = ...

local DEFAULTS = { point = "LEFT", relative = "LEFT", x = 60, y = 120, scale = 1 }
local MIN_QUALITY = 3
local HOLD = 4
local NAMES_LIMIT = 5
local GAP = 12
local HEIGHT_CHOOSING, HEIGHT_RESULT = 34, 48
local GOLD = { 1, 0.84, 0.42 }
local FALL_ROWS, FALL_STEP = 10, 13
local RANK = { need = 1, greed = 2, disenchant = 3 }

local ICONS = {
  need = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
  greed = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
  pass = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
  disenchant = "Interface\\Buttons\\UI-GroupLoot-DE-Up",
}
local WORDS = { need = NEED or "Need", greed = GREED or "Greed", pass = PASS or "Pass", disenchant = ROLL_DISENCHANT or "Disenchant" }
local QUALITY_BY_COLOR = { ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5 }
local HISTORY_STATE = { [0] = "need", [1] = "need", [2] = "greed", [3] = "greed", [5] = "pass" }

local db = DEFAULTS
local root, hint, lock, slider
local setMoving
local moving = false

local dismiss, release, colored

local function hover(f)
  f.hit:EnableMouse(not moving)
  if not moving and f.hit.SetMouseClickEnabled then f.hit:SetMouseClickEnabled(false) end
  f.dismiss:EnableMouse(not moving)
  f.list:EnableMouse(not moving)
  if not moving and f.list.SetMouseClickEnabled then f.list:SetMouseClickEnabled(false) end
  local picking = not moving and f.pick.entry ~= nil and not f.pick.entry.done
  f.pick:EnableMouse(picking)
  if picking and f.pick.SetMouseClickEnabled then f.pick:SetMouseClickEnabled(false) end
end

local function showChoices(self)
  local entry = self.entry
  if not entry or entry.gone or entry.done then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText(entry.key)
  local function group(title, icon, wanted)
    local names = {}
    for _, name in ipairs(entry.players) do
      if entry.state[name].choice == wanted then names[#names + 1] = colored(entry, name) end
    end
    if #names == 0 then return end
    GameTooltip:AddLine((icon and ("|T" .. icon .. ":14|t ") or "") .. title .. " (" .. #names .. ")", GOLD[1], GOLD[2], GOLD[3])
    GameTooltip:AddLine(table.concat(names, ", "), 1, 1, 1, true)
  end
  for _, kind in ipairs({ "need", "greed", "disenchant", "pass" }) do group(WORDS[kind], ICONS[kind], kind) end
  group("Waiting", nil, nil)
  GameTooltip:Show()
end

local function showTip(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if self.link then
    GameTooltip:SetHyperlink(self.link)
  else
    GameTooltip:SetText(self.title or "")
  end
  GameTooltip:Show()
end

local function hideTip(self)
  if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
end
local test
local entries, pool = {}, {}
local serial = 0
local patterns

local function secret(value)
  return issecretvalue ~= nil and issecretvalue(value)
end

local driver = CreateFrame("Frame")
local tweens = {}

local function ease(t)
  if t >= 1 then return 1 end
  return 1 - 2 ^ (-10 * t)
end

local function advance(_, elapsed)
  local finished
  for i = #tweens, 1, -1 do
    local tw = tweens[i]
    tw.time = tw.time + elapsed
    if tw.time >= 0 then
      local t = math.min(tw.time / tw.duration, 1)
      tw.apply(tw.from + (tw.to - tw.from) * ease(t))
      if t >= 1 then
        table.remove(tweens, i)
        if tw.done then
          finished = finished or {}
          finished[#finished + 1] = tw.done
        end
      end
    end
  end
  if finished then
    for _, done in ipairs(finished) do done() end
  end
  if #tweens == 0 then driver:SetScript("OnUpdate", nil) end
end

local function tween(key, from, to, duration, delay, apply, done)
  for i = #tweens, 1, -1 do
    if tweens[i].key == key then table.remove(tweens, i) end
  end
  tweens[#tweens + 1] = { key = key, from = from, to = to, duration = duration, time = -(delay or 0), apply = apply, done = done }
  if not delay or delay == 0 then apply(from) end
  driver:SetScript("OnUpdate", advance)
end

local function cancel(prefix)
  for i = #tweens, 1, -1 do
    if tweens[i].key:sub(1, #prefix) == prefix then table.remove(tweens, i) end
  end
end

local function fade(key, region, to, duration, delay, done)
  tween(key, region:GetAlpha(), to, duration, delay, function(value) region:SetAlpha(value) end, done)
end

local function text(parent, size)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
  fs:SetShadowColor(0, 0, 0, 1)
  fs:SetShadowOffset(1, -1)
  fs:SetJustifyH("LEFT")
  return fs
end

local function savePosition()
  local point, _, relative, x, y = root:GetPoint()
  db.point, db.relative, db.x, db.y = point, relative, x, y
end

local function setScale(scale)
  scale = math.max(0.5, math.min(2.5, scale))
  local point, _, relative, x, y = root:GetPoint()
  local factor = root:GetScale() / scale
  root:SetScale(scale)
  root:ClearAllPoints()
  root:SetPoint(point, UIParent, relative, x * factor, y * factor)
  db.scale = scale
  savePosition()
end

local function showSize(value)
  slider.label:SetText(("Size %.2f"):format(value))
end

local function toggleSlider()
  if not slider then
    local box = CreateFrame("Frame", nil, UIParent)
    box:SetSize(250, 44)
    box:SetFrameStrata("DIALOG")
    box:EnableMouse(true)
    local fill = box:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(box)
    fill:SetColorTexture(0, 0, 0, 0.7)
    slider = CreateFrame("Slider", nil, box)
    slider.box = box
    slider:SetSize(150, 16)
    slider:SetPoint("BOTTOMLEFT", 34, 8)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(0.5, 2.5)
    slider:SetValueStep(0.05)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:EnableMouse(true)
    local rail = slider:CreateTexture(nil, "BACKGROUND")
    rail:SetPoint("LEFT", 0, 0)
    rail:SetPoint("RIGHT", 0, 0)
    rail:SetHeight(2)
    rail:SetColorTexture(1, 1, 1, 0.45)
    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(8, 16)
    thumb:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    slider:SetThumbTexture(thumb)
    slider.label = text(box, 11)
    slider.label:SetPoint("TOPLEFT", 10, -7)
    local function snap(value)
      return math.max(0.5, math.min(2.5, math.floor(value * 20 + 0.5) / 20))
    end
    slider:SetScript("OnValueChanged", function(_, value) showSize(snap(value)) end)
    slider:SetScript("OnMouseUp", function(self) setScale(snap(self:GetValue())) end)
    local function nudge(label, x, amount)
      local button = CreateFrame("Button", nil, box)
      button:SetSize(20, 20)
      button:SetPoint("BOTTOMLEFT", x, 6)
      local caption = text(button, 15)
      caption:SetPoint("CENTER", 0, 0)
      caption:SetText(label)
      caption:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
      button:SetScript("OnClick", function()
        local value = snap(db.scale + amount)
        setScale(value)
        slider:SetValue(value)
        showSize(value)
      end)
    end
    nudge("-", 8, -0.05)
    nudge("+", 192, 0.05)
    box:Hide()
  end
  local box = slider.box
  if box:IsShown() then
    box:Hide()
    return
  end
  local ratio = root:GetEffectiveScale() / UIParent:GetEffectiveScale()
  local left, right, top = (root:GetLeft() or 0) * ratio, (root:GetRight() or 0) * ratio, (root:GetTop() or 0) * ratio
  local x = right + 16
  if x + 250 > UIParent:GetWidth() then x = left - 266 end
  box:ClearAllPoints()
  box:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, top)
  slider:SetValue(db.scale)
  showSize(db.scale)
  box:Show()
end

local function ensureRoot()
  if root then return end
  root = CreateFrame("Frame", "LootRollsForeverAnchor", UIParent)
  root:SetSize(320, HEIGHT_RESULT)
  root:SetPoint(db.point, UIParent, db.relative or db.point, db.x, db.y)
  root:SetScale(db.scale)
  root:SetFrameStrata("MEDIUM")
  root:SetMovable(true)
  root:SetClampedToScreen(true)
  root:RegisterForDrag("LeftButton")
  root:SetScript("OnDragStart", root.StartMoving)
  root:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    savePosition()
  end)
  root:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then toggleSlider() end
  end)
  hint = text(root, 10)
  hint:SetPoint("TOPLEFT", root, "BOTTOMLEFT", 0, -8)
  hint:SetTextColor(0.75, 0.75, 0.75)
  hint:SetText("Drag to move. Right-click for size.")
  hint:Hide()
  lock = CreateFrame("Button", nil, root)
  lock:SetSize(44, 18)
  lock:SetPoint("LEFT", hint, "RIGHT", 10, 0)
  local fill = lock:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(lock)
  fill:SetColorTexture(0, 0, 0, 0.7)
  local caption = text(lock, 11)
  caption:SetPoint("CENTER", 0, 0)
  caption:SetText("Done")
  caption:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  lock:SetScript("OnClick", function() setMoving(false) end)
  lock:Hide()
end

local function acquire()
  local f = table.remove(pool)
  if not f then
    f = CreateFrame("Frame", nil, root)
    f:SetSize(320, HEIGHT_CHOOSING)
    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetSize(30, 30)
    f.border:SetPoint("TOPLEFT", 0, 0)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(28, 28)
    f.icon:SetPoint("TOPLEFT", 1, -1)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.name = text(f, 14)
    f.name:SetPoint("TOPLEFT", 38, 0)
    f.hit = CreateFrame("Frame", nil, f)
    f.hit:SetPoint("TOPLEFT", 34, 0)
    f.hit:SetHeight(18)
    f.hit:SetScript("OnEnter", showTip)
    f.hit:SetScript("OnLeave", hideTip)
    f.check = f:CreateTexture(nil, "OVERLAY")
    f.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    f.check:SetSize(30, 30)
    f.check:SetPoint("TOPLEFT", 0, 0)
    f.dismiss = CreateFrame("Button", nil, f)
    f.dismiss:SetSize(30, 30)
    f.dismiss:SetPoint("TOPLEFT", 0, 0)
    f.dismiss:SetScript("OnEnter", function(self)
      f.check:Show()
      f.icon:SetVertexColor(0.35, 0.35, 0.35)
      showTip(self)
    end)
    f.dismiss:SetScript("OnLeave", function(self)
      f.check:Hide()
      f.icon:SetVertexColor(1, 1, 1)
      hideTip(self)
    end)
    f.dismiss:SetScript("OnClick", function(self) dismiss(self.entry) end)
    f.choosing = CreateFrame("Frame", nil, f)
    f.choosing:SetSize(280, 14)
    f.pick = CreateFrame("Frame", nil, f.choosing)
    f.pick:SetAllPoints(f.choosing)
    f.pick:SetScript("OnEnter", showChoices)
    f.pick:SetScript("OnLeave", hideTip)
    f.counts = text(f.choosing, 11)
    f.counts:SetPoint("LEFT", 0, 0)
    f.slots = {}
    f.result = CreateFrame("Frame", nil, f)
    f.result:SetSize(280, 30)
    f.winIcon = f.result:CreateTexture(nil, "ARTWORK")
    f.winIcon:SetSize(16, 16)
    f.winIcon:SetPoint("TOPLEFT", 0, 0)
    f.winner = text(f.result, 15)
    f.winner:SetPoint("LEFT", f.winIcon, "RIGHT", 4, 0)
    f.roll = text(f.result, 15)
    f.roll:SetPoint("LEFT", f.winner, "RIGHT", 6, 0)
    f.roll:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    f.rest = text(f.result, 10)
    f.rest:SetPoint("TOPLEFT", 0, -19)
    f.rest:SetTextColor(0.8, 0.8, 0.8)
    f.fall = {}
    f.list = CreateFrame("Frame", nil, f.result)
    f.list:SetPoint("TOPLEFT", 0, -18)
    f.list:SetScript("OnEnter", function(self)
      local entry = self.entry
      if not entry or entry.gone then return end
      cancel(entry.id .. "out")
      entry.frame:SetAlpha(1)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(entry.key)
      local function line(name, r, g, b)
        local state = entry.state[name]
        GameTooltip:AddDoubleLine(("|T%s:14|t %s"):format(ICONS[state.choice or "greed"], colored(entry, name)), state.roll or "", 1, 1, 1, r, g, b)
      end
      if entry.winner then line(entry.winner, GOLD[1], GOLD[2], GOLD[3]) end
      for _, name in ipairs(entry.ranked) do line(name, 1, 1, 1) end
      local passed = 0
      for _, name in ipairs(entry.players) do
        if entry.state[name].choice == "pass" then passed = passed + 1 end
      end
      if passed > 0 then GameTooltip:AddLine(passed .. " passed", 0.6, 0.6, 0.6) end
      GameTooltip:Show()
    end)
    f.list:SetScript("OnLeave", function(self)
      hideTip(self)
      local entry = self.entry
      if not entry or entry.gone then return end
      fade(entry.id .. "out", entry.frame, 0, 0.6, 2, function() release(entry) end)
    end)
  end
  f:SetAlpha(0)
  f.choosing:SetAlpha(1)
  f.choosing:ClearAllPoints()
  f.choosing:SetPoint("TOPLEFT", f, "TOPLEFT", 38, -18)
  f.result:SetAlpha(0)
  f.result:ClearAllPoints()
  f.result:SetPoint("TOPLEFT", f, "TOPLEFT", 38, -24)
  f.rest:SetAlpha(0)
  f.rest:SetText("")
  f.check:Hide()
  f.icon:SetVertexColor(1, 1, 1)
  for _, row in ipairs(f.fall) do row:Hide() end
  f.list:Hide()
  f.list.entry = nil
  f.roll:SetText("")
  f.counts:SetText("")
  for _, slot in ipairs(f.slots) do
    slot.icon:Hide()
    slot.label:Hide()
  end
  f:Show()
  return f
end

local function slot(f, i)
  local s = f.slots[i]
  if not s then
    s = { icon = f.choosing:CreateTexture(nil, "ARTWORK"), label = text(f.choosing, 11) }
    s.icon:SetSize(13, 13)
    f.slots[i] = s
  end
  return s
end

local function place(entry)
  entry.frame:SetPoint("TOPLEFT", root, "TOPLEFT", entry.x, entry.y)
end

local function restack()
  local y = 0
  for _, entry in ipairs(entries) do
    if entry.targetY ~= y then
      entry.targetY = y
      tween(entry.id .. "y", entry.y or y, y, 0.45, 0, function(value)
        entry.y = value
        place(entry)
      end)
    end
    y = y - (entry.height + GAP)
  end
end

function release(entry)
  for i, other in ipairs(entries) do
    if other == entry then
      table.remove(entries, i)
      break
    end
  end
  cancel(entry.id)
  entry.gone = true
  hideTip(entry.frame.hit)
  hideTip(entry.frame.dismiss)
  hideTip(entry.frame.list)
  hideTip(entry.frame.pick)
  entry.frame.pick.entry = nil
  entry.frame:Hide()
  pool[#pool + 1] = entry.frame
  restack()
  if moving and entry.preview and #entries == 0 then
    C_Timer.After(0.4, function()
      if moving and #entries == 0 then test() end
    end)
  end
end

function setMoving(on)
  moving = on
  root:EnableMouse(on)
  hint:SetShown(on)
  lock:SetShown(on)
  GameTooltip:Hide()
  for _, entry in ipairs(entries) do hover(entry.frame) end
  if on then
    if #entries == 0 then test() end
  elseif slider then
    slider.box:Hide()
  end
end

function colored(entry, name)
  local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.class[name] or ""]
  if not color then return name end
  return ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, name)
end

local function drawChoosing(entry, changed)
  local f = entry.frame
  if #entry.players > 0 and #entry.players <= NAMES_LIMIT then
    f.counts:SetText("")
    local x = 0
    for i, name in ipairs(entry.players) do
      local s = slot(f, i)
      local choice = entry.state[name].choice
      s.label:SetText(colored(entry, name))
      s.icon:ClearAllPoints()
      s.icon:SetPoint("LEFT", f.choosing, "LEFT", x, 0)
      s.label:ClearAllPoints()
      s.label:SetPoint("LEFT", f.choosing, "LEFT", x + 15, 0)
      s.icon:Show()
      s.label:Show()
      if choice then s.icon:SetTexture(ICONS[choice]) end
      if name == changed then
        fade(entry.id .. "slot" .. i, s.label, 1, 0.35)
        fade(entry.id .. "pick" .. i, s.icon, 1, 0.35)
      elseif not choice then
        s.label:SetAlpha(0.3)
        s.icon:SetAlpha(0)
      end
      x = x + 15 + s.label:GetStringWidth() + 10
    end
    for i = #entry.players + 1, #f.slots do
      f.slots[i].icon:Hide()
      f.slots[i].label:Hide()
    end
    return
  end
  for _, s in ipairs(f.slots) do
    s.icon:Hide()
    s.label:Hide()
  end
  local count = { need = 0, greed = 0, pass = 0, disenchant = 0 }
  local waiting = 0
  for _, name in ipairs(entry.players) do
    local choice = entry.state[name].choice
    if choice then count[choice] = count[choice] + 1 else waiting = waiting + 1 end
  end
  local parts = {}
  for _, kind in ipairs({ "need", "greed", "disenchant", "pass" }) do
    if count[kind] > 0 then parts[#parts + 1] = ("|T%s:14|t %d"):format(ICONS[kind], count[kind]) end
  end
  if waiting > 0 then parts[#parts + 1] = ("|cff999999%d waiting|r"):format(waiting) end
  f.counts:SetText(table.concat(parts, "   "))
end

local function roster()
  local list, class = {}, {}
  local function add(unit)
    local name = UnitName(unit)
    if not name or secret(name) or class[name] then return end
    local _, file = UnitClass(unit)
    list[#list + 1] = name
    class[name] = (not secret(file)) and file or ""
  end
  add("player")
  if IsInRaid and IsInRaid() then
    for i = 1, GetNumGroupMembers() do add("raid" .. i) end
  else
    for i = 1, 4 do add("party" .. i) end
  end
  return list, class
end

local function start(name, link, quality, texture, seconds, players, class)
  ensureRoot()
  serial = serial + 1
  if not players then players, class = roster() end
  local entry = {
    id = "e" .. serial .. ":", key = name, link = link, players = players, class = class, state = {},
    frame = acquire(), x = -14, height = HEIGHT_CHOOSING,
  }
  for _, player in ipairs(players) do entry.state[player] = {} end
  local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] or { r = 1, g = 1, b = 1 }
  local f = entry.frame
  f.border:SetColorTexture(color.r, color.g, color.b, 1)
  f.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
  f.name:SetText(name)
  f.name:SetTextColor(color.r, color.g, color.b)
  f.hit.link, f.hit.title = link, name
  f.dismiss.link, f.dismiss.title, f.dismiss.entry = link, name, entry
  f.pick.entry = entry
  f.hit:SetWidth(8 + f.name:GetStringWidth())
  hover(f)
  entries[#entries + 1] = entry
  drawChoosing(entry)
  restack()
  fade(entry.id .. "in", f, 1, 0.5)
  tween(entry.id .. "x", -14, 0, 0.6, 0, function(value)
    entry.x = value
    place(entry)
  end)
  tween(entry.id .. "expire", 0, 1, 0.6, (seconds or 60) + 20, function(value)
    f:SetAlpha(1 - value)
  end, function() release(entry) end)
  return entry
end

local function player(entry, name, class)
  if not entry.state[name] then
    entry.state[name] = {}
    entry.players[#entry.players + 1] = name
    entry.class[name] = class or ""
  elseif class and entry.class[name] == "" then
    entry.class[name] = class
  end
  return entry.state[name]
end

local function choose(entry, name, choice, class)
  if entry.gone then return end
  local state = player(entry, name, class)
  if state.choice == choice then return end
  state.choice = choice
  if not entry.done then
    drawChoosing(entry, name)
    if GameTooltip:GetOwner() == entry.frame.pick then showChoices(entry.frame.pick) end
  end
end

local function finish(entry, winner, roll, choice)
  if entry.done or entry.gone then return end
  entry.done = true
  local f = entry.frame
  hideTip(f.pick)
  f.pick:EnableMouse(false)
  cancel(entry.id .. "expire")
  local state = winner and player(entry, winner) or {}
  roll = roll or state.roll
  choice = choice or state.choice or "greed"
  if winner then
    f.winIcon:SetTexture(ICONS[choice])
    f.winIcon:Show()
    f.winner:SetText(colored(entry, winner))
  else
    f.winIcon:SetTexture(ICONS.pass)
    f.winner:SetText("|cffbbbbbbEveryone passed|r")
  end
  local others = {}
  for _, name in ipairs(entry.players) do
    local other = entry.state[name]
    if name ~= winner and other.roll then others[#others + 1] = name end
  end
  table.sort(others, function(a, b)
    local ra, rb = RANK[entry.state[a].choice] or 2, RANK[entry.state[b].choice] or 2
    if ra ~= rb then return ra < rb end
    return entry.state[a].roll > entry.state[b].roll
  end)
  local rows = 0
  if #entry.players > NAMES_LIMIT then
    local function fall(label)
      rows = rows + 1
      local row = f.fall[rows]
      if not row then
        row = text(f.result, 11)
        f.fall[rows] = row
      end
      local x, y = 0, -20 - (rows - 1) * FALL_STEP
      row:SetText(label)
      row:SetAlpha(0)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", f.result, "TOPLEFT", x, y + 16)
      row:Show()
      tween(entry.id .. "fall" .. rows, 0, 1, 0.5, 0.6 + rows * 0.07, function(value)
        row:SetAlpha(value)
        row:SetPoint("TOPLEFT", f.result, "TOPLEFT", x, y + 16 * (1 - value))
      end)
    end
    for i = 1, math.min(#others, FALL_ROWS) do
      local other = entry.state[others[i]]
      fall(("|T%s:12|t %s  |cffffffff%d|r"):format(ICONS[other.choice or "greed"], colored(entry, others[i]), other.roll))
    end
    if #others > FALL_ROWS then fall(("|cff999999+%d more, hover to see all|r"):format(#others - FALL_ROWS)) end
    f.rest:SetText("")
    entry.height = 46 + rows * FALL_STEP
    entry.winner, entry.ranked = winner, others
    f.list.entry = entry
    f.list:SetSize(220, rows * FALL_STEP + 4)
    f.list:Show()
    hover(f)
  else
    local parts = {}
    for i = 1, math.min(#others, 4) do
      local other = entry.state[others[i]]
      local part = colored(entry, others[i]) .. " " .. other.roll
      if other.choice and other.choice ~= choice then part = part .. " " .. WORDS[other.choice]:lower() end
      parts[#parts + 1] = part
    end
    f.rest:SetText(table.concat(parts, "   "))
    entry.height = HEIGHT_RESULT
  end
  restack()
  fade(entry.id .. "choosing", f.choosing, 0, 0.3)
  tween(entry.id .. "result", 0, 1, 0.5, 0.25, function(value)
    f.result:SetAlpha(value)
    f.result:SetPoint("TOPLEFT", f, "TOPLEFT", 38, -24 + 6 * value)
  end)
  if winner and roll then
    tween(entry.id .. "roll", 1, roll, 0.9, 0.3, function(value)
      f.roll:SetText(math.floor(value + 0.5))
    end)
  end
  fade(entry.id .. "rest", f.rest, 1, 0.5, 1)
  fade(entry.id .. "out", f, 0, 0.6, HOLD + 1.2 + rows * 0.07, function() release(entry) end)
end

local ignored = {}

function dismiss(entry)
  if entry.gone then return end
  entry.gone = true
  if not entry.done and not entry.preview then ignored[entry.key] = GetTime() + 300 end
  cancel(entry.id)
  fade(entry.id .. "out", entry.frame, 0, 0.25, 0, function() release(entry) end)
end

local function compile(format)
  local order, n = {}, 0
  local pattern = format:gsub("%%(%d*)%$?([sd])", function(position, kind)
    n = n + 1
    order[n] = tonumber(position) or n
    return kind == "d" and "\1" or "\2"
  end)
  pattern = pattern:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
  pattern = pattern:gsub("\1", "(%%d+)"):gsub("\2", "(.+)")
  return "^" .. pattern .. "$", order
end

local MESSAGES = {
  { "LOOT_ROLL_ALL_PASSED", "passed", item = 1 },
  { "LOOT_ROLL_YOU_WON_NO_SPAM_NEED", "won", self = true, roll = 1, item = 2, choice = "need" },
  { "LOOT_ROLL_YOU_WON_NO_SPAM_GREED", "won", self = true, roll = 1, item = 2, choice = "greed" },
  { "LOOT_ROLL_YOU_WON_NO_SPAM_DE", "won", self = true, roll = 1, item = 2, choice = "disenchant" },
  { "LOOT_ROLL_WON_NO_SPAM_NEED", "won", name = 1, roll = 2, item = 3, choice = "need" },
  { "LOOT_ROLL_WON_NO_SPAM_GREED", "won", name = 1, roll = 2, item = 3, choice = "greed" },
  { "LOOT_ROLL_WON_NO_SPAM_DE", "won", name = 1, roll = 2, item = 3, choice = "disenchant" },
  { "LOOT_ROLL_ROLLED_NEED", "roll", roll = 1, item = 2, name = 3, choice = "need" },
  { "LOOT_ROLL_ROLLED_GREED", "roll", roll = 1, item = 2, name = 3, choice = "greed" },
  { "LOOT_ROLL_ROLLED_DE", "roll", roll = 1, item = 2, name = 3, choice = "disenchant" },
  { "LOOT_ROLL_NEED_SELF", "choice", self = true, item = 1, choice = "need" },
  { "LOOT_ROLL_GREED_SELF", "choice", self = true, item = 1, choice = "greed" },
  { "LOOT_ROLL_DISENCHANT_SELF", "choice", self = true, item = 1, choice = "disenchant" },
  { "LOOT_ROLL_PASSED_SELF_AUTO", "choice", self = true, item = 1, choice = "pass" },
  { "LOOT_ROLL_PASSED_SELF", "choice", self = true, item = 1, choice = "pass" },
  { "LOOT_ROLL_NEED", "choice", name = 1, item = 2, choice = "need" },
  { "LOOT_ROLL_GREED", "choice", name = 1, item = 2, choice = "greed" },
  { "LOOT_ROLL_DISENCHANT", "choice", name = 1, item = 2, choice = "disenchant" },
  { "LOOT_ROLL_PASSED_AUTO_FEMALE", "choice", name = 1, item = 2, choice = "pass" },
  { "LOOT_ROLL_PASSED_AUTO", "choice", name = 1, item = 2, choice = "pass" },
  { "LOOT_ROLL_PASSED", "choice", name = 1, item = 2, choice = "pass" },
  { "LOOT_ROLL_YOU_WON", "won", self = true, item = 1 },
  { "LOOT_ROLL_WON", "won", name = 1, item = 2 },
}

local function read(message)
  if not patterns then
    patterns = {}
    for _, spec in ipairs(MESSAGES) do
      local format = _G[spec[1]]
      if type(format) == "string" then
        local pattern, order = compile(format)
        patterns[#patterns + 1] = { pattern = pattern, order = order, spec = spec }
      end
    end
  end
  for _, entry in ipairs(patterns) do
    local captures = { message:match(entry.pattern) }
    if captures[1] then
      local args = {}
      for i, value in ipairs(captures) do args[entry.order[i]] = value end
      local spec = entry.spec
      local name = spec.self and UnitName("player") or (spec.name and args[spec.name])
      return spec[2], name and name:match("^[^-]+"), args[spec.item], spec.roll and tonumber(args[spec.roll]), spec.choice
    end
  end
end

local function find(item, name)
  local key = item:match("%[(.-)%]") or item
  local fallback
  for _, entry in ipairs(entries) do
    if entry.key == key and not entry.done then
      if not name or not (entry.state[name] and entry.state[name].choice) then return entry end
      fallback = fallback or entry
    end
  end
  if fallback then return fallback end
  if ignored[key] and GetTime() < ignored[key] then return end
  local _, link, quality, _, _, _, _, _, _, texture = GetItemInfo(item)
  if not quality then
    local color = item:match("|c%x%x(%x%x%x%x%x%x)")
    quality = color and QUALITY_BY_COLOR[color:lower()]
  end
  if not quality or quality < MIN_QUALITY then return end
  return start(key, link or item, quality, texture)
end

local function onChat(message)
  if type(message) ~= "string" or secret(message) then return end
  local kind, name, item, roll, choice = read(message)
  if not kind or not item then return end
  local entry = find(item, kind == "choice" and name or nil)
  if not entry then return end
  if kind == "choice" then
    choose(entry, name, choice)
  elseif kind == "roll" then
    local state = player(entry, name)
    state.roll = roll
    if not state.choice then choose(entry, name, choice) end
  elseif kind == "won" then
    finish(entry, name, roll, choice)
  else
    finish(entry)
  end
end

local function onHistory(encounterID, lootListID)
  if not (C_LootHistory and C_LootHistory.GetSortedInfoForDrop) then return end
  local ok, info = pcall(C_LootHistory.GetSortedInfoForDrop, encounterID, lootListID)
  if not ok or type(info) ~= "table" or type(info.itemHyperlink) ~= "string" or secret(info.itemHyperlink) then return end
  local entry = find(info.itemHyperlink)
  if not entry then return end
  local winner
  for _, rolled in ipairs(info.rollInfos or {}) do
    if type(rolled.playerName) == "string" and not secret(rolled.playerName) then
      local name = rolled.playerName:match("^[^-]+")
      local choice = HISTORY_STATE[rolled.state]
      local state = player(entry, name, rolled.playerClass)
      if type(rolled.roll) == "number" then state.roll = rolled.roll end
      if choice then choose(entry, name, choice, rolled.playerClass) end
      if rolled.isWinner then winner = name end
    end
  end
  if info.allPassed then
    finish(entry)
  elseif winner then
    finish(entry, winner)
  end
end

local function onRoll(rollID, rollTime)
  if not GetLootRollItemInfo then return end
  local texture, name, _, quality = GetLootRollItemInfo(rollID)
  if not name or secret(name) or not quality or quality < MIN_QUALITY then return end
  ignored[name] = nil
  start(name, GetLootRollItemLink and GetLootRollItemLink(rollID), quality, texture, (rollTime or 60000) / 1000)
end

local TESTS = {
  { "Golemheart Girdle", 3, "Interface\\Icons\\INV_Belt_03",
    { { "Brakk", "WARRIOR", "need", 71 }, { "Tekkon", "ROGUE", "greed", 88 }, { "Odrik", "HUNTER", "need", 34 },
      { "Mirelle", "MAGE", "greed", 12 }, { "Sunna", "PRIEST", "pass" } }, "Brakk" },
  { "Runed Core of the Sentinel", 4, "Interface\\Icons\\INV_Misc_Gem_Pearl_04",
    { { "Mirelle", "MAGE", "need", 93 }, { "Brakk", "WARRIOR", "greed", 60 }, { "Sunna", "PRIEST", "need", 95 },
      { "Tekkon", "ROGUE", "need", 41 }, { "Odrik", "HUNTER", "pass" } }, "Sunna" },
}
local testIndex = 0

function test()
  testIndex = testIndex % #TESTS + 1
  local name, quality, texture, rolls, winner = unpack(TESTS[testIndex])
  local players, class = {}, {}
  for i, roll in ipairs(rolls) do
    players[i] = roll[1]
    class[roll[1]] = roll[2]
  end
  local entry = start(name, nil, quality, texture, 60, players, class)
  entry.preview = true
  for i, roll in ipairs(rolls) do
    C_Timer.After(0.7 + (i - 1) * 0.6, function() choose(entry, roll[1], roll[3]) end)
  end
  C_Timer.After(0.7 + #rolls * 0.6 + 0.5, function()
    for _, roll in ipairs(rolls) do
      if roll[4] then entry.state[roll[1]].roll = roll[4] end
    end
    finish(entry, winner)
  end)
end

local RAID_CLASSES = { "WARRIOR", "ROGUE", "MAGE", "PRIEST", "HUNTER", "WARLOCK", "DRUID", "SHAMAN", "PALADIN" }

local function raidTest()
  local size, index = 25, 1
  local players, class, picks = {}, {}, {}
  for i = 1, size do
    players[i] = "Raider" .. i
    class[players[i]] = RAID_CLASSES[(i - 1) % #RAID_CLASSES + 1]
    local kind = (i + index) % 4 == 0 and "need" or ((i + index) % 3 == 0 and "pass" or "greed")
    picks[i] = { kind, math.random(100) }
  end
  local entry = start("Runed Core of the Sentinel", nil, 4, "Interface\\Icons\\INV_Misc_Gem_Pearl_04", 60, players, class)
  entry.preview = true
  for i, pick in ipairs(picks) do
    C_Timer.After(0.5 + i * 3.5 / size, function() choose(entry, players[i], pick[1]) end)
  end
  C_Timer.After(0.5 + 3.5 + 0.8, function()
    if entry.gone then return end
    local winner, best = nil, 0
    for i, pick in ipairs(picks) do
      if pick[1] ~= "pass" then entry.state[players[i]].roll = pick[2] end
      if pick[1] == "need" and pick[2] > best then winner, best = players[i], pick[2] end
    end
    finish(entry, winner)
  end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, a, b)
  if event == "ADDON_LOADED" then
    if a ~= ADDON then return end
    LootRollsForeverDB = LootRollsForeverDB or {}
    db = LootRollsForeverDB
    for option, value in pairs(DEFAULTS) do
      if db[option] == nil then db[option] = value end
    end
  elseif event == "START_LOOT_ROLL" then
    onRoll(a, b)
  elseif event == "CHAT_MSG_LOOT" then
    onChat(a)
  elseif event == "LOOT_HISTORY_UPDATE_DROP" then
    onHistory(a, b)
  end
end)
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("START_LOOT_ROLL")
events:RegisterEvent("CHAT_MSG_LOOT")
pcall(events.RegisterEvent, events, "LOOT_HISTORY_UPDATE_DROP")

SLASH_LOOTROLLSFOREVER1 = "/rolls"
SLASH_LOOTROLLSFOREVER2 = "/lootrolls"
SLASH_LOOTROLLSFOREVER3 = "/lrf"
SlashCmdList.LOOTROLLSFOREVER = function(message)
  local command, value = strtrim(message or ""):lower():match("^(%S*)%s*(.*)$")
  ensureRoot()
  if command == "test" and value == "raid" then
    raidTest()
  elseif command == "test" then
    test()
  elseif command == "move" then
    setMoving(not moving)
  elseif command == "scale" and tonumber(value) then
    setScale(tonumber(value))
  elseif command == "reset" then
    db.point, db.relative, db.x, db.y, db.scale = DEFAULTS.point, DEFAULTS.relative, DEFAULTS.x, DEFAULTS.y, DEFAULTS.scale
    root:ClearAllPoints()
    root:SetPoint(db.point, UIParent, db.relative, db.x, db.y)
    root:SetScale(db.scale)
  else
    print("|cffffd100Loot Rolls|r /rolls test: play an example")
    print("|cffffd100Loot Rolls|r /rolls test raid: play a 25 player example")
    print("|cffffd100Loot Rolls|r /rolls move: preview it, drag it, right-click for size; again to lock")
    print("|cffffd100Loot Rolls|r /rolls scale 1.2: size (now " .. db.scale .. ")")
    print("|cffffd100Loot Rolls|r /rolls reset: back to the default place and size")
  end
end

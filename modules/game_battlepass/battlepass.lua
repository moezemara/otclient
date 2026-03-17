--[[
  War Pass — OTClient module (v2)

  Server -> Client  opcode 100: "xp|hasPrem|daysLeft|<bitmask>|freeIds|premIds|freeTxts|premTxts"
  Client -> Server  opcode 101: claim tier  (string = tier number)
--]]

local OPCODE_OPEN   = 100
local OPCODE_CLAIM  = 101
local XP_PER_TIER   = 500
local TOTAL_TIERS   = 50
local TIERS_PER_ROW = 10
local CARD_W        = 72
local CARD_H        = 84
local CARD_GAP      = 8     -- also the arrow width
local ROW_LABEL_W   = 44
local PAGES         = TOTAL_TIERS / TIERS_PER_ROW  -- 5

local WIN_W = ROW_LABEL_W + TIERS_PER_ROW * CARD_W + (TIERS_PER_ROW - 1) * CARD_GAP + 24
local WIN_H = 380

local ICON_XP   = '/images/battlepass/icon_xp'
local ICON_TIER = '/images/battlepass/icon_tier'
local ICON_DAYS = '/images/battlepass/icon_days'

local battlepassWindow  = nil
local battlepassButton  = nil
local bpData            = nil
local bpCurTier         = 0
local bpPage            = 1
local bpCardContainer   = nil
local bpPageLabel       = nil

-- ── Data parser ───────────────────────────────────────────────────────────────
local function parseData(buffer)
  local fields = {}
  for f in buffer:gmatch('[^|]+') do fields[#fields + 1] = f end
  local d = {
    xp       = tonumber(fields[1]) or 0,
    hasPrem  = fields[2] == '1',
    daysLeft = tonumber(fields[3]) or 0,
    fc = {}, pc = {},
    freeIds = {}, premIds = {},
    freeTxts = {}, premTxts = {},
  }
  local bits = fields[4] or ''
  for i = 1, TOTAL_TIERS do
    d.fc[i] = bits:sub(i * 2 - 1, i * 2 - 1) == '1'
    d.pc[i] = bits:sub(i * 2,     i * 2)     == '1'
  end
  local fi, pi, ft, pt = {}, {}, {}, {}
  for v in (fields[5] or ''):gmatch('[^,]+') do
    local id, cnt = v:match('(%d+):(%d+)')
    fi[#fi+1] = { id = tonumber(id) or 3031, count = tonumber(cnt) or 1 }
  end
  for v in (fields[6] or ''):gmatch('[^,]+') do
    local id, cnt = v:match('(%d+):(%d+)')
    pi[#pi+1] = { id = tonumber(id) or 3031, count = tonumber(cnt) or 1 }
  end
  for v in (fields[7] or ''):gmatch('[^~]+') do ft[#ft+1] = v end
  for v in (fields[8] or ''):gmatch('[^~]+') do pt[#pt+1] = v end
  for i = 1, TOTAL_TIERS do
    d.freeIds[i]  = fi[i] or { id = 3031, count = 1 }
    d.premIds[i]  = pi[i] or { id = 3031, count = 1 }
    d.freeTxts[i] = ft[i] or '?'
    d.premTxts[i] = pt[i] or '?'
  end
  return d
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────
function init()
  g_ui.importStyle('battlepass')
  ProtocolGame.registerExtendedOpcode(OPCODE_OPEN, onReceiveBattlepass)
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE_OPEN, onReceiveBattlepass)
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  onGameEnd()
end

function onGameStart()
  battlepassButton = modules.game_mainpanel.addToggleButton(
    'battlepassButton', 'War Pass', '/images/options/rewardwall',
    function() g_game.talk('/battlepass') end, false, 999)
end

function onGameEnd()
  destroyWindow()
  if battlepassButton then
    battlepassButton:destroy()
    battlepassButton = nil
  end
end

function destroyWindow()
  if battlepassWindow then
    battlepassWindow:destroy()
    battlepassWindow = nil
  end
  bpData = nil
  bpCardContainer = nil
  bpPageLabel = nil
end

-- ── Card row builder ──────────────────────────────────────────────────────────
-- isPrem = true → premium track row; false → free track row
local function buildCardRow(rowParent, d, curTier, page, isPrem)
  local startTier  = (page - 1) * TIERS_PER_ROW + 1
  local nextLocked = curTier + 1   -- only this one shows XP-to-unlock
  local prefix     = isPrem and 'bp_p' or 'bp_f'

  for colIdx = 0, TIERS_PER_ROW - 1 do
    local tierNum  = startTier + colIdx
    local isMile   = (tierNum == 25 or tierNum % 10 == 0)
    local isNextLocked = (tierNum == nextLocked)

    -- ── Determine visual state ────────────────────────────────────────────
    local isLocked, isClaimed, isClaimable, noPass
    local cardStyle, badgeText, badgeColor

    if isPrem then
      noPass    = not d.hasPrem
      isLocked  = noPass or (tierNum > curTier)
      isClaimed = d.pc[tierNum] and not isLocked
      isClaimable = not isLocked and not isClaimed
    else
      isLocked  = tierNum > curTier
      isClaimed = d.fc[tierNum] and not isLocked
      isClaimable = not isLocked and not isClaimed
    end

    if isLocked then
      cardStyle = (isPrem and noPass) and 'BPCardNoPrem' or 'BPCardLocked'
      if noPass then
        badgeText  = 'NO PASS'
        badgeColor = '#2a2440'
      elseif isNextLocked then
        local xpNeeded = tierNum * XP_PER_TIER - d.xp
        badgeText  = xpNeeded .. ' XP'
        badgeColor = '#1a3a5c'
      else
        badgeText  = 'LOCKED'
        badgeColor = '#2a2d33'
      end
    elseif isClaimed then
      cardStyle  = 'BPCardDone'
      badgeText  = 'DONE'
      badgeColor = '#1a4020'
    else
      cardStyle   = isPrem and 'BPCardPrem' or 'BPCard'
      badgeText   = 'CLAIM'
      badgeColor  = isPrem and '#b8920a' or '#c03040'
    end

    local itemId     = isPrem and d.premIds[tierNum] or d.freeIds[tierNum]
    local rewardText = isPrem and d.premTxts[tierNum] or d.freeTxts[tierNum]

    -- ── Arrow before this card (skip first) ──────────────────────────────
    local arrowId = prefix .. 'A' .. tierNum
    if colIdx > 0 then
      local prevCardId = prefix .. 'C' .. (tierNum - 1)
      local arrowW = g_ui.createWidget('BPArrow', rowParent)
      arrowW:setId(arrowId)
      arrowW:setText('>')
      arrowW:setWidth(CARD_GAP)
      arrowW:setHeight(CARD_H)
      arrowW:setPhantom(true)
      arrowW:addAnchor(AnchorTop,  'parent', AnchorTop)
      arrowW:addAnchor(AnchorLeft, prevCardId, AnchorRight)
    end

    -- ── Card shell ────────────────────────────────────────────────────────
    local cardId = prefix .. 'C' .. tierNum
    local card   = g_ui.createWidget(cardStyle, rowParent)
    card:setId(cardId)
    card:setWidth(CARD_W)
    card:setHeight(CARD_H)
    card:addAnchor(AnchorTop, 'parent', AnchorTop)
    if colIdx == 0 then
      card:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      card:setMarginLeft(ROW_LABEL_W)
    else
      card:addAnchor(AnchorLeft, arrowId, AnchorRight)
    end

    -- Milestone gold border overlay
    if isMile and not isLocked then
      local mb = g_ui.createWidget('BPMilestoneBorder', card)
      mb:setWidth(CARD_W); mb:setHeight(CARD_H)
      mb:addAnchor(AnchorTop,  'parent', AnchorTop)
      mb:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      mb:setPhantom(true)
    end

    -- Tier number
    local numStyle = isMile and 'BPTierNumMilestone' or 'BPTierNum'
    local numW = g_ui.createWidget(numStyle, card)
    numW:setWidth(CARD_W); numW:setHeight(16)
    if tierNum == 50 then
      numW:setText('** ' .. tierNum .. ' **')
    elseif isMile then
      numW:setText('* ' .. tierNum)
    else
      numW:setText(tostring(tierNum))
    end
    numW:setColor(isMile and '#f0c040' or (isLocked and '#444c55' or '#c9d1d9'))
    numW:addAnchor(AnchorTop,  'parent', AnchorTop)
    numW:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    numW:setMarginTop(4)

    -- Tooltip on the card itself (phantom items can't receive mouse events)
    local tip
    if noPass then
      tip = 'Activate the Battle Pass to claim premium rewards'
    elseif isLocked and isNextLocked then
      tip = (tierNum * XP_PER_TIER - d.xp) .. ' XP needed to unlock'
    elseif isLocked then
      tip = 'Locked'
    else
      tip = rewardText
    end
    card:setTooltip(tip)

    -- Item sprite (centered, built-in stack count overlay)
    local itemW = g_ui.createWidget('UIItem', card)
    itemW:setItemId(itemId.id)
    itemW:setItemCount(itemId.count)
    itemW:setWidth(32); itemW:setHeight(32)
    itemW:setPhantom(true)
    itemW:addAnchor(AnchorTop,  'parent', AnchorTop)
    itemW:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    itemW:setMarginTop(22)
    itemW:setMarginLeft(math.floor((CARD_W - 32) / 2))

    -- Badge: interactive CLAIM button or static label
    local badgeW
    if isClaimable then
      badgeW = g_ui.createWidget('BPClaimBtn', card)
      badgeW:setColor('#ffffff')
      local capturedTier = tierNum
      badgeW.onClick = function()
        local proto = g_game.getProtocolGame()
        if proto then
          local msg = OutputMessage.create()
          msg:addU8(0x32)
          msg:addU8(OPCODE_CLAIM)
          msg:addString(tostring(capturedTier))
          proto:send(msg)
        end
      end
    else
      badgeW = g_ui.createWidget('BPBadge', card)
      badgeW:setColor(isNextLocked and '#58a6ff' or '#ffffff')
    end
    badgeW:setText(badgeText)
    badgeW:setBackgroundColor(badgeColor)
    badgeW:setWidth(CARD_W - 6)
    badgeW:setHeight(22)
    badgeW:addAnchor(AnchorTop,  'parent', AnchorTop)
    badgeW:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    badgeW:setMarginTop(CARD_H - 26)
    badgeW:setMarginLeft(3)
  end
end

-- ── Page builder ──────────────────────────────────────────────────────────────
local function buildCardPage(page)
  if not bpCardContainer or not bpData then return end

  while bpCardContainer:getChildCount() > 0 do
    bpCardContainer:getFirstChild():destroy()
  end

  bpPage = page
  local startTier = (page - 1) * TIERS_PER_ROW + 1
  local endTier   = startTier + TIERS_PER_ROW - 1

  if bpPageLabel then
    bpPageLabel:setText('Tiers ' .. startTier .. ' to ' .. endTier .. '   (' .. page .. ' / ' .. PAGES .. ')')
  end

  -- Free row
  local freeRow = g_ui.createWidget('UIWidget', bpCardContainer)
  freeRow:setId('bpFreeRow')
  freeRow:setWidth(WIN_W - 16)
  freeRow:setHeight(CARD_H)
  freeRow:addAnchor(AnchorTop,  'parent', AnchorTop)
  freeRow:addAnchor(AnchorLeft, 'parent', AnchorLeft)

  local freeLbl = g_ui.createWidget('BPRowLabel', freeRow)
  freeLbl:setText('FREE')
  freeLbl:setWidth(ROW_LABEL_W - 4)
  freeLbl:setHeight(16)
  freeLbl:setColor('#7ee787')
  freeLbl:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  freeLbl:addAnchor(AnchorLeft,           'parent', AnchorLeft)
  freeLbl:setMarginLeft(2)

  buildCardRow(freeRow, bpData, bpCurTier, page, false)

  -- Separator
  local sep = g_ui.createWidget('BPDivider', bpCardContainer)
  sep:setId('bpRowSep')
  sep:setHeight(1)
  sep:addAnchor(AnchorTop,   'bpFreeRow', AnchorBottom)
  sep:addAnchor(AnchorLeft,  'parent',    AnchorLeft)
  sep:addAnchor(AnchorRight, 'parent',    AnchorRight)
  sep:setMarginTop(4)

  -- Premium row
  local premRow = g_ui.createWidget('UIWidget', bpCardContainer)
  premRow:setId('bpPremRow')
  premRow:setWidth(WIN_W - 16)
  premRow:setHeight(CARD_H)
  premRow:addAnchor(AnchorTop,  'bpRowSep', AnchorBottom)
  premRow:addAnchor(AnchorLeft, 'parent',   AnchorLeft)
  premRow:setMarginTop(4)

  local premLbl   = g_ui.createWidget('BPRowLabel', premRow)
  premLbl:setText('PREM')
  premLbl:setWidth(ROW_LABEL_W - 4)
  premLbl:setHeight(16)
  premLbl:setColor('#f0c040')
  premLbl:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  premLbl:addAnchor(AnchorLeft,           'parent', AnchorLeft)
  premLbl:setMarginLeft(2)

  buildCardRow(premRow, bpData, bpCurTier, page, true)
end

-- ── Main window builder ───────────────────────────────────────────────────────
function onReceiveBattlepass(protocol, opcode, buffer)
  destroyWindow()

  local d       = parseData(buffer)
  local curTier = math.min(math.floor(d.xp / XP_PER_TIER), TOTAL_TIERS)
  local xpPct   = math.min(d.xp / (TOTAL_TIERS * XP_PER_TIER), 1.0)

  bpData    = d
  bpCurTier = curTier
  bpPage    = 1

  -- ── Window ───────────────────────────────────────────────────────────────
  battlepassWindow = g_ui.createWidget('MainWindow', rootWidget)
  battlepassWindow:setText('War Pass')
  battlepassWindow:setWidth(WIN_W)
  battlepassWindow:setHeight(WIN_H)
  battlepassWindow:centerIn(rootWidget)
  battlepassWindow:setDraggable(true)

  -- ── Footer (anchor first so card container refs it) ───────────────────
  local footer = g_ui.createWidget('BPFooter', battlepassWindow)
  footer:setId('bpFooter')
  footer:setHeight(40)
  footer:addAnchor(AnchorLeft,   'parent', AnchorLeft)
  footer:addAnchor(AnchorRight,  'parent', AnchorRight)
  footer:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  footer:setMarginLeft(4); footer:setMarginRight(4); footer:setMarginBottom(4)

  -- Nav group centered in footer
  local navGroup = g_ui.createWidget('UIWidget', footer)
  navGroup:setId('bpNavGroup')
  navGroup:setWidth(308)   -- 28 + 6 + 240 + 6 + 28
  navGroup:setHeight(28)
  navGroup:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
  navGroup:addAnchor(AnchorVerticalCenter,   'parent', AnchorVerticalCenter)

  local prevBtn = g_ui.createWidget('Button', navGroup)
  prevBtn:setId('bpPrevBtn')
  prevBtn:setText('<')
  prevBtn:setWidth(28); prevBtn:setHeight(28)
  prevBtn:addAnchor(AnchorTop,  'parent', AnchorTop)
  prevBtn:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  prevBtn.onClick = function()
    if bpPage > 1 then buildCardPage(bpPage - 1) end
  end

  bpPageLabel = g_ui.createWidget('BPStatLabel', navGroup)
  bpPageLabel:setId('bpPageLbl')
  bpPageLabel:setWidth(240); bpPageLabel:setHeight(28)
  bpPageLabel:setTextAlign(AlignCenter)
  bpPageLabel:addAnchor(AnchorTop,  'parent',    AnchorTop)
  bpPageLabel:addAnchor(AnchorLeft, 'bpPrevBtn', AnchorRight)
  bpPageLabel:setMarginLeft(6)

  local nextBtn = g_ui.createWidget('Button', navGroup)
  nextBtn:setId('bpNextBtn')
  nextBtn:setText('>')
  nextBtn:setWidth(28); nextBtn:setHeight(28)
  nextBtn:addAnchor(AnchorTop,  'parent',    AnchorTop)
  nextBtn:addAnchor(AnchorLeft, 'bpPageLbl', AnchorRight)
  nextBtn:setMarginLeft(6)
  nextBtn.onClick = function()
    if bpPage < PAGES then buildCardPage(bpPage + 1) end
  end

  local closeBtn = g_ui.createWidget('Button', footer)
  closeBtn:setText('Close')
  closeBtn:setWidth(76); closeBtn:setHeight(28)
  closeBtn:addAnchor(AnchorRight,          'parent', AnchorRight)
  closeBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  closeBtn:setMarginRight(12)
  closeBtn.onClick = function() destroyWindow() end

  -- ── Header ───────────────────────────────────────────────────────────────
  local header = g_ui.createWidget('BPHeader', battlepassWindow)
  header:setId('bpHeader')
  header:setHeight(100)
  header:addAnchor(AnchorTop,   'parent', AnchorTop)
  header:addAnchor(AnchorLeft,  'parent', AnchorLeft)
  header:addAnchor(AnchorRight, 'parent', AnchorRight)
  header:setMarginTop(4); header:setMarginLeft(4); header:setMarginRight(4)

  -- Title row (centered)
  local titleRow = g_ui.createWidget('UIWidget', header)
  titleRow:setId('bpTitleRow')
  titleRow:setWidth(240); titleRow:setHeight(22)
  titleRow:addAnchor(AnchorTop,              'parent', AnchorTop)
  titleRow:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
  titleRow:setMarginTop(8)

  local titleLbl = g_ui.createWidget('BPTitle', titleRow)
  titleLbl:setId('bpTitleLbl')
  titleLbl:setText('WAR PASS')
  titleLbl:setWidth(100); titleLbl:setHeight(22)
  titleLbl:addAnchor(AnchorTop,   'parent', AnchorTop)
  titleLbl:addAnchor(AnchorLeft,  'parent', AnchorLeft)

  local seasonLbl = g_ui.createWidget('BPSeason', titleRow)
  seasonLbl:setText('Season 1')
  seasonLbl:setWidth(80); seasonLbl:setHeight(22)
  seasonLbl:addAnchor(AnchorTop,  'bpTitleLbl', AnchorTop)
  seasonLbl:addAnchor(AnchorLeft, 'bpTitleLbl', AnchorRight)
  seasonLbl:setMarginLeft(6)

  local passLbl = g_ui.createWidget('BPSeason', titleRow)
  passLbl:setText(d.hasPrem and '● PREMIUM' or '○ FREE TRACK')
  passLbl:setColor(d.hasPrem and '#f0c040' or '#555e68')
  passLbl:setWidth(90); passLbl:setHeight(22)
  passLbl:setTextAlign(AlignRight)
  passLbl:addAnchor(AnchorTop,   'bpTitleLbl', AnchorTop)
  passLbl:addAnchor(AnchorRight, 'parent',      AnchorRight)

  -- Stat row (centered): XP | Tier | Days
  local statRow = g_ui.createWidget('UIWidget', header)
  statRow:setId('bpStatRow')
  statRow:setWidth(488); statRow:setHeight(34)
  statRow:addAnchor(AnchorTop,              'bpTitleRow', AnchorBottom)
  statRow:addAnchor(AnchorHorizontalCenter, 'parent',     AnchorHorizontalCenter)
  statRow:setMarginTop(6)

  -- XP box
  local xpBox = g_ui.createWidget('BPStatBox', statRow)
  xpBox:setId('bpXpBox')
  xpBox:setWidth(192); xpBox:setHeight(34)
  xpBox:addAnchor(AnchorTop,  'parent', AnchorTop)
  xpBox:addAnchor(AnchorLeft, 'parent', AnchorLeft)

  local xpIco = g_ui.createWidget('UIWidget', xpBox)
  xpIco:setImageSource(ICON_XP)
  xpIco:setWidth(16); xpIco:setHeight(16); xpIco:setPhantom(true)
  xpIco:setImageColor('#e94560')
  xpIco:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  xpIco:addAnchor(AnchorLeft,           'parent', AnchorLeft)
  xpIco:setMarginLeft(8)

  local xpCap = g_ui.createWidget('BPStatLabel', xpBox)
  xpCap:setText('Total Experience')
  xpCap:setWidth(150); xpCap:setHeight(14)
  xpCap:addAnchor(AnchorTop,  'parent', AnchorTop)
  xpCap:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  xpCap:setMarginTop(4); xpCap:setMarginLeft(30)

  local xpVal = g_ui.createWidget('BPStatValue', xpBox)
  xpVal:setText(d.xp .. ' XP earned')
  xpVal:setWidth(160); xpVal:setHeight(14)
  xpVal:addAnchor(AnchorTop,  'parent', AnchorTop)
  xpVal:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  xpVal:setMarginTop(17); xpVal:setMarginLeft(30)

  -- Tier box
  local tierBox = g_ui.createWidget('BPStatBox', statRow)
  tierBox:setId('bpTierBox')
  tierBox:setWidth(148); tierBox:setHeight(34)
  tierBox:addAnchor(AnchorTop,  'bpXpBox', AnchorTop)
  tierBox:addAnchor(AnchorLeft, 'bpXpBox', AnchorRight)
  tierBox:setMarginLeft(6)

  local tierIco = g_ui.createWidget('UIWidget', tierBox)
  tierIco:setImageSource(ICON_TIER)
  tierIco:setWidth(16); tierIco:setHeight(16); tierIco:setPhantom(true)
  tierIco:setImageColor('#f0c040')
  tierIco:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  tierIco:addAnchor(AnchorLeft,           'parent', AnchorLeft)
  tierIco:setMarginLeft(8)

  local tierCap = g_ui.createWidget('BPStatLabel', tierBox)
  tierCap:setText('Tier')
  tierCap:setWidth(40); tierCap:setHeight(14)
  tierCap:addAnchor(AnchorTop,  'parent', AnchorTop)
  tierCap:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  tierCap:setMarginTop(4); tierCap:setMarginLeft(30)

  local tierVal = g_ui.createWidget('BPStatValue', tierBox)
  tierVal:setText(curTier .. ' / ' .. TOTAL_TIERS)
  tierVal:setWidth(110); tierVal:setHeight(14)
  tierVal:addAnchor(AnchorTop,  'parent', AnchorTop)
  tierVal:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  tierVal:setMarginTop(17); tierVal:setMarginLeft(30)

  -- Days box
  local daysBox = g_ui.createWidget('BPStatBox', statRow)
  daysBox:setWidth(142); daysBox:setHeight(34)
  daysBox:addAnchor(AnchorTop,  'bpXpBox',  AnchorTop)
  daysBox:addAnchor(AnchorLeft, 'bpTierBox', AnchorRight)
  daysBox:setMarginLeft(6)

  local daysIco = g_ui.createWidget('UIWidget', daysBox)
  daysIco:setImageSource(ICON_DAYS)
  daysIco:setWidth(16); daysIco:setHeight(16); daysIco:setPhantom(true)
  daysIco:setImageColor('#58a6ff')
  daysIco:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  daysIco:addAnchor(AnchorLeft,           'parent', AnchorLeft)
  daysIco:setMarginLeft(8)

  local daysCap = g_ui.createWidget('BPStatLabel', daysBox)
  daysCap:setText('Season Ends')
  daysCap:setWidth(100); daysCap:setHeight(14)
  daysCap:addAnchor(AnchorTop,  'parent', AnchorTop)
  daysCap:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  daysCap:setMarginTop(4); daysCap:setMarginLeft(30)

  local daysVal = g_ui.createWidget('BPStatValue', daysBox)
  daysVal:setText(d.daysLeft .. ' days left')
  daysVal:setColor(d.daysLeft <= 3 and '#f85149' or '#e6edf3')
  daysVal:setWidth(110); daysVal:setHeight(14)
  daysVal:addAnchor(AnchorTop,  'parent', AnchorTop)
  daysVal:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  daysVal:setMarginTop(17); daysVal:setMarginLeft(30)

  -- XP progress bar (full width)
  local xpBg = g_ui.createWidget('BPXpBg', header)
  xpBg:setId('bpXpBg')
  xpBg:setHeight(14)
  xpBg:addAnchor(AnchorTop,   'bpStatRow', AnchorBottom)
  xpBg:addAnchor(AnchorLeft,  'parent',    AnchorLeft)
  xpBg:addAnchor(AnchorRight, 'parent',    AnchorRight)
  xpBg:setMarginTop(6); xpBg:setMarginLeft(14); xpBg:setMarginRight(14)

  local BAR_W = WIN_W - 8 - 28   -- approx inner width
  local fillW = math.max(4, math.floor(BAR_W * xpPct))

  local xpGlow = g_ui.createWidget('BPXpGlow', xpBg)
  xpGlow:setWidth(math.min(fillW + 8, BAR_W)); xpGlow:setHeight(14)
  xpGlow:addAnchor(AnchorTop,  'parent', AnchorTop)
  xpGlow:addAnchor(AnchorLeft, 'parent', AnchorLeft)

  local xpFill = g_ui.createWidget('BPXpFill', xpBg)
  xpFill:setWidth(fillW); xpFill:setHeight(14)
  xpFill:addAnchor(AnchorTop,  'parent', AnchorTop)
  xpFill:addAnchor(AnchorLeft, 'parent', AnchorLeft)

  local xpPctLbl = g_ui.createWidget('BPStatValue', xpBg)
  xpPctLbl:setText(math.floor(xpPct * 100) .. '%')
  xpPctLbl:setColor('#ffffff')
  xpPctLbl:setWidth(40); xpPctLbl:setHeight(14)
  xpPctLbl:setTextAlign(AlignCenter)
  xpPctLbl:addAnchor(AnchorTop,  'parent', AnchorTop)
  xpPctLbl:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  xpPctLbl:setMarginLeft(math.max(2, math.min(fillW - 20, BAR_W - 42)))

  -- ── Card container (two rows, no scroll) ─────────────────────────────────
  bpCardContainer = g_ui.createWidget('UIWidget', battlepassWindow)
  bpCardContainer:setId('bpCards')
  bpCardContainer:setWidth(WIN_W - 16)
  bpCardContainer:setHeight(2 * CARD_H + 9)   -- free + sep(1+4+4) + prem
  bpCardContainer:addAnchor(AnchorTop,  'bpHeader', AnchorBottom)
  bpCardContainer:addAnchor(AnchorLeft, 'parent',   AnchorLeft)
  bpCardContainer:setMarginTop(8); bpCardContainer:setMarginLeft(8)

  buildCardPage(1)
end

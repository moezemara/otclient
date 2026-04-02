--[[
  Smart Chest System — OTClient Module (HTML/CSS engine)
  Server -> Client  opcode 50: pipe-separated state
    "f1|e1|t1|f2|e2|t2|f3|e3|t3|f4|e4|t4|f5|e5|t5|f6|e6|t6|shards"
  Client -> Server  via g_game.talk() talkactions
--]]

SmartChestController = Controller:new()

local OPCODE_STATE  = 50
local FORTUNE_CAP   = { 80, 80, 80, 80, 40, 40 }
local EXCHANGE_MAX  = 4
local EXCHANGE_COST = 300
local TIER_NAMES    = { 'Wooden', 'Silver', 'Golden', 'Obsidian', 'Crimson', 'Celestial' }
local KEY_NAMES     = { [1]='Iron', [2]='Silver', [3]='Golden', [4]='Shadow' }
local CRAFT_COSTS   = { [1]=40, [2]=40, [3]=80, [4]=150 }
local REFINE_COSTS  = {
  [1]={ 8,  18,  40 }, [2]={ 12,  28,  60 }, [3]={ 20,  45, 100 },
  [4]={ 30,  68, 150 }, [5]={ 45, 100, 220 }, [6]={ 70, 160, 340 },
}
local FUSE_NAMES = { 'wooden', 'silver', 'golden' }

-- Bar widths in pixels (must match CSS .sc-bar-bg width)
local FORT_BAR_W = 190
local EXCH_BAR_W = 440

local scButton = nil

-- ── Reactive controller state (properties are live in HTML templates) ─────────
SmartChestController.currentTab       = 'overview'
SmartChestController.shards           = 0
SmartChestController.fortuneTiers     = {}
SmartChestController.exchangeTiers    = {}

SmartChestController.selRefineTier    = nil
SmartChestController.selRefineQuality = nil
SmartChestController.refineCostText   = 'Select a tier and target quality'

SmartChestController.selCraftKey      = nil
SmartChestController.craftCostText    = 'Select a key tier above'

SmartChestController.selFuseTier      = nil
SmartChestController.fuseCostText     = 'Select a chest tier to fuse above'

SmartChestController.selExchangeTier  = 1
SmartChestController.exData           = nil   -- currently selected exchange tier data

-- ── Lifecycle ─────────────────────────────────────────────────────────────────
function SmartChestController:onGameStart()
  ProtocolGame.registerExtendedOpcode(OPCODE_STATE, function(proto, op, buf)
    self:onReceiveState(buf)
  end)
  if not scButton then
    scButton = modules.game_mainpanel.addToggleButton(
      'smartChestButton', 'Smart Chest', '/images/options/rewardwall',
      function() g_game.talk('/chest') end, false, 998)
  end
end

function SmartChestController:onGameEnd()
  ProtocolGame.unregisterExtendedOpcode(OPCODE_STATE)
  if scButton then scButton:destroy(); scButton = nil end
  self:hide()
end

-- ── Opcode handler ────────────────────────────────────────────────────────────
function SmartChestController:onReceiveState(buffer)
  local fields = {}
  for v in buffer:gmatch('[^|]+') do
    fields[#fields + 1] = tonumber(v) or 0
  end

  self.shards        = fields[19] or 0
  self.fortuneTiers  = {}
  self.exchangeTiers = {}

  for tier = 1, 6 do
    local base = (tier - 1) * 3 + 1
    local f    = fields[base]     or 0
    local cap  = FORTUNE_CAP[tier]
    local pct  = math.min(100, f / cap * 100)
    self.fortuneTiers[tier] = {
      id      = tier,
      name    = TIER_NAMES[tier],
      fortune = f,
      cap     = cap,
      pct     = math.floor(pct),
      fillPx  = math.floor(pct / 100 * FORT_BAR_W),
    }
  end

  for tier = 1, EXCHANGE_MAX do
    local base = (tier - 1) * 3 + 1
    local e    = fields[base + 1] or 0
    local pct  = math.min(100, e / EXCHANGE_COST * 100)
    self.exchangeTiers[tier] = {
      id      = tier,
      name    = TIER_NAMES[tier],
      exchange = e,
      cost    = EXCHANGE_COST,
      pct     = math.floor(pct),
      fillPx  = math.floor(pct / 100 * FORT_BAR_W),
      fillPxFull = math.floor(pct / 100 * EXCH_BAR_W),
      ready   = e >= EXCHANGE_COST,
      remaining = math.max(0, EXCHANGE_COST - e),
    }
  end

  self:_syncExData()

  -- Build/show window
  if not self.ui or self.ui:isDestroyed() then
    self:loadHtml('game_smart_chest.html')
  end
  if self.ui then
    self.ui:centerIn('parent')
    self.ui:show()
    self.ui:raise()
    self.ui:focus()
  end
end

-- ── Tab switching ─────────────────────────────────────────────────────────────
function SmartChestController:setTab(name)
  self.currentTab = name
end

-- ── Window ────────────────────────────────────────────────────────────────────
function SmartChestController:hide()
  if self.ui and not self.ui:isDestroyed() then
    self.ui:destroy()
    self.ui = nil
  end
end

-- ── Refine tab ────────────────────────────────────────────────────────────────
function SmartChestController:setRefineTier(tier)
  self.selRefineTier = tier
  self:_syncRefineCost()
end

function SmartChestController:setRefineQuality(q)
  self.selRefineQuality = q
  self:_syncRefineCost()
end

function SmartChestController:_syncRefineCost()
  local qMap = { exceptional = 1, flawless = 2, radiant = 3 }
  if self.selRefineTier and self.selRefineQuality then
    local idx  = qMap[self.selRefineQuality]
    local cost = (REFINE_COSTS[self.selRefineTier] or {})[idx] or '?'
    self.refineCostText = 'Cost: ' .. tostring(cost) .. ' Arcane Shards  →  ' ..
      self.selRefineQuality:sub(1,1):upper() .. self.selRefineQuality:sub(2)
  else
    self.refineCostText = 'Cost: select a tier and target quality'
  end
end

function SmartChestController:doRefine()
  if not self.selRefineTier or not self.selRefineQuality then return end
  g_game.talk('/refine ' .. self.selRefineQuality)
end

-- ── Craft tab ─────────────────────────────────────────────────────────────────
function SmartChestController:setCraftKey(tier)
  self.selCraftKey  = tier
  self.craftCostText = 'Craft ' .. KEY_NAMES[tier] .. ' Key — costs ' ..
    CRAFT_COSTS[tier] .. ' Arcane Shards'
end

function SmartChestController:doCraftKey()
  if not self.selCraftKey then return end
  g_game.talk('/craftkey ' .. KEY_NAMES[self.selCraftKey]:lower())
end

function SmartChestController:setFuse(tier)
  self.selFuseTier  = tier
  self.fuseCostText = 'Fuse 3 ' .. TIER_NAMES[tier] ..
    ' Chests (same quality) + 120 shards  →  1 ' ..
    TIER_NAMES[tier + 1] .. ' Chest (Intact)'
end

function SmartChestController:doFuse()
  if not self.selFuseTier then return end
  g_game.talk('/fuse ' .. FUSE_NAMES[self.selFuseTier])
end

-- ── Exchange tab ──────────────────────────────────────────────────────────────
function SmartChestController:setExchangeTier(tier)
  self.selExchangeTier = tier
  self:_syncExData()
end

function SmartChestController:_syncExData()
  local t = self.selExchangeTier or 1
  self.exData = self.exchangeTiers[t] or nil
end

function SmartChestController:doExchangeClaim()
  if not self.selExchangeTier or not self.ui then return end
  local input = self.ui:recursiveGetChildById('exItemInput')
  local idx   = input and tonumber(input:getText())
  if not idx then return end
  g_game.talk('/exchange claim ' .. TIER_NAMES[self.selExchangeTier]:lower() .. ' ' .. idx)
end

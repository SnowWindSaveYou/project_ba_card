-- ============================================================================
-- Layout/ZoneLayout.lua - 牌桌区域布局管理（v2 极简版）
-- 桌面只保留：连招链(中央) + 预备区 + 牌库
-- 角色/架势/护具/充能/弃牌 全部 HUD 化
-- ============================================================================

local Card3D = require("Card.Card3D")
local Tween  = require("Core.Tween")
local Easing = require("Core.Easing")

local ZoneLayout = {}
ZoneLayout.__index = ZoneLayout

-- ============================================================================
-- 区域定义（世界坐标，单位：米）
-- ============================================================================

local TABLE_Y = -0.03  -- 与 TableScene.TABLE_Y 保持一致

local ZONE_DEFS = {
    -- === 己方桌面区域 (Z < 0) ===
    myArsenal = {
        pos = Vector3(0, TABLE_Y + 0.01, -1.3),
        width = 0.7, depth = 0.5,
        cardLimit = 1,
        label = "预备区",
    },
    myDeck = {
        pos = Vector3(3.6, TABLE_Y + 0.01, -1.3),
        width = 0.7, depth = 0.9,
        cardLimit = 40,
        label = "牌库",
    },

    -- === 中央连招链区域 ===
    combatChain = {
        pos = Vector3(0, TABLE_Y + 0.01, 0),
        width = 3.6, depth = 1.2,
        cardLimit = 20,
        label = "连招链",
    },

    -- === 对手桌面区域 (Z > 0) ===
    oppArsenal = {
        pos = Vector3(0, TABLE_Y + 0.01, 1.3),
        width = 0.7, depth = 0.5,
        cardLimit = 1,
        label = "对手预备区",
    },
    oppDeck = {
        pos = Vector3(3.6, TABLE_Y + 0.01, 1.3),
        width = 0.7, depth = 0.9,
        cardLimit = 40,
        label = "对手牌库",
    },

    -- === HUD 化区域（仅数据追踪，不占桌面） ===
    myGraveyard = {
        pos = Vector3(0, 0, 0),
        width = 0, depth = 0,
        cardLimit = 999,
        label = "弃牌堆",
        hudOnly = true,
    },
    myPitch = {
        pos = Vector3(0, 0, 0),
        width = 0, depth = 0,
        cardLimit = 10,
        label = "充能区",
        hudOnly = true,
    },
    myBanish = {
        pos = Vector3(0, 0, 0),
        width = 0, depth = 0,
        cardLimit = 999,
        label = "放逐区",
        hudOnly = true,
    },
    oppGraveyard = {
        pos = Vector3(0, 0, 0),
        width = 0, depth = 0,
        cardLimit = 999,
        label = "对手弃牌堆",
        hudOnly = true,
    },
    oppPitch = {
        pos = Vector3(0, 0, 0),
        width = 0, depth = 0,
        cardLimit = 10,
        label = "对手充能区",
        hudOnly = true,
    },
    oppBanish = {
        pos = Vector3(0, 0, 0),
        width = 0, depth = 0,
        cardLimit = 999,
        label = "对手放逐区",
        hudOnly = true,
    },
}

-- ============================================================================
-- 构造
-- ============================================================================

function ZoneLayout.create()
    local layout = setmetatable({}, ZoneLayout)
    layout.zones = {}
    for name, def in pairs(ZONE_DEFS) do
        layout.zones[name] = {
            def = def,
            cards = {},
        }
    end
    return layout
end

-- ============================================================================
-- 查询接口
-- ============================================================================

function ZoneLayout:getZoneDef(zoneName)
    local zone = self.zones[zoneName]
    return zone and zone.def or nil
end

function ZoneLayout:getZonePos(zoneName)
    local zone = self.zones[zoneName]
    return zone and zone.def.pos or nil
end

function ZoneLayout:getCards(zoneName)
    local zone = self.zones[zoneName]
    return zone and zone.cards or {}
end

function ZoneLayout:cardCount(zoneName)
    local zone = self.zones[zoneName]
    return zone and #zone.cards or 0
end

function ZoneLayout:isHudOnly(zoneName)
    local zone = self.zones[zoneName]
    return zone and zone.def.hudOnly == true or false
end

-- ============================================================================
-- 卡牌移动
-- ============================================================================

function ZoneLayout:addCard(zoneName, card3d)
    local zone = self.zones[zoneName]
    if not zone then
        print("[ZoneLayout] WARNING: unknown zone '" .. zoneName .. "'")
        return
    end
    zone.cards[#zone.cards + 1] = card3d
end

function ZoneLayout:removeCard(zoneName, card3d)
    local zone = self.zones[zoneName]
    if not zone then return false end
    for i, c in ipairs(zone.cards) do
        if c == card3d then
            table.remove(zone.cards, i)
            return true
        end
    end
    return false
end

function ZoneLayout:moveCard(card3d, fromZone, toZone)
    self:removeCard(fromZone, card3d)
    self:addCard(toZone, card3d)
end

function ZoneLayout:clearZone(zoneName)
    local zone = self.zones[zoneName]
    if zone then zone.cards = {} end
end

-- ============================================================================
-- 区域内排列计算
-- ============================================================================

function ZoneLayout:computeZoneSlots(zoneName)
    local zone = self.zones[zoneName]
    if not zone or zone.def.hudOnly then return {} end

    local def = zone.def
    local cards = zone.cards
    local n = #cards
    if n == 0 then return {} end

    local slots = {}
    local spacing = math.min(Card3D.WIDTH + 0.05, def.width / math.max(n, 1))
    local totalW = (n - 1) * spacing
    local startX = def.pos.x - totalW / 2

    local isOpp = zoneName:sub(1, 3) == "opp"
    local baseRotY = isOpp and 180 or 0

    for i = 1, n do
        local x = startX + (i - 1) * spacing
        slots[i] = {
            pos = Vector3(x, def.pos.y, def.pos.z),
            rot = Quaternion(0, baseRotY, 0),
        }
    end
    return slots
end

--- 重新排列区域中的卡牌（带 Tween 滑动动画）
---@param zoneName string
---@param instant boolean|nil  true 则跳过动画直接设置位置
function ZoneLayout:arrangeZone(zoneName, instant)
    local zone = self.zones[zoneName]
    if not zone or zone.def.hudOnly then return end

    local slots = self:computeZoneSlots(zoneName)
    for i, card in ipairs(zone.cards) do
        local slot = slots[i]
        if slot then
            if instant then
                card:setPosition(slot.pos)
                card:setRotation(slot.rot)
            else
                -- Tween 滑动到目标位置
                Tween.killAll(card.node)
                Tween.to(card.node, 0.25, {
                    position = slot.pos,
                    rotation = slot.rot,
                }, {
                    easing = Easing.outCubic,
                    onComplete = function()
                        card.targetPos = slot.pos
                        card.targetRot = slot.rot
                        card.baseY = slot.pos.y
                    end,
                })
            end
        end
    end
end

-- ============================================================================
-- 连招链专用
-- ============================================================================

function ZoneLayout:computeChainSlots()
    return self:computeZoneSlots("combatChain")
end

function ZoneLayout:getNextChainPos()
    local zone = self.zones["combatChain"]
    local n = #zone.cards  -- 当前已有 n 张，新卡将是第 n+1 张
    local def = zone.def

    local spacing = math.min(Card3D.WIDTH + 0.10, def.width / math.max(n + 1, 1))
    -- 按 n+1 张居中计算，新卡落在最右侧槽位
    local totalW = n * spacing
    local startX = def.pos.x - totalW / 2
    local x = startX + n * spacing
    return Vector3(x, def.pos.y + 0.02, def.pos.z)
end

return ZoneLayout

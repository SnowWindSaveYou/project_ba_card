-- ============================================================================
-- Card/CardData.lua - 卡牌数据结构
-- 定义卡牌的逻辑数据（不含 3D 表现）
-- ============================================================================

local CardData = {}
CardData.__index = CardData

-- ============================================================================
-- 卡牌类型枚举（权威参考: effect-system.md §10.5）
-- 仅牌组牌类型；英雄/武器/装备使用独立模型，不计入此枚举
-- ============================================================================

CardData.TYPE = {
    -- === 牌组牌 ===
    ATTACK   = "attack",     -- 攻击牌（原 Attack Action）
    SUPPORT  = "support",    -- 辅助牌（原 Non-Attack Action）
    CHASE    = "chase",      -- 追击牌（原 Attack Reaction）
    DODGE    = "dodge",      -- 闪避牌（原 Defense Reaction）
    INSTINCT = "instinct",   -- 本能牌（原 Instant）
    AURA     = "aura",       -- 状态牌（留场持续效果）
    ITEM     = "item",       -- 道具牌（留场一次性激活）

    -- === 非牌组牌（开局放置，独立模型）===
    HERO      = "hero",
    WEAPON    = "weapon",
    EQUIPMENT = "equipment",
}

-- ============================================================================
-- Pitch 颜色 → 资源值映射
-- ============================================================================

CardData.PITCH = {
    NONE   = 0,
    RED    = 1,
    YELLOW = 2,
    BLUE   = 3,
}

-- Pitch 颜色 → 显示色
CardData.PITCH_COLORS = {
    [1] = { r = 0.9, g = 0.15, b = 0.15 },  -- 红
    [2] = { r = 0.9, g = 0.75, b = 0.1 },   -- 黄
    [3] = { r = 0.15, g = 0.4, b = 0.9 },   -- 蓝
}

-- ============================================================================
-- 职业/流派枚举
-- ============================================================================

CardData.CLASS = {
    WARRIOR  = "warrior",   -- 剑道
    NINJA    = "ninja",     -- 跆拳道
    GUARDIAN = "guardian",   -- 太极
    BRUTE    = "brute",     -- 拳击
    GENERIC  = "generic",   -- 通用
}

-- ============================================================================
-- 关键词枚举
-- ============================================================================

CardData.KEYWORD = {
    GO_AGAIN    = "go_again",      -- 连招
    DOMINATE    = "dominate",      -- 必杀
    INTIMIDATE  = "intimidate",    -- 震慑
    CRUSH       = "crush",         -- 重击
    REPRISE     = "reprise",       -- 反击
    COMBO       = "combo",         -- 连击
    BATTLEWORN  = "battleworn",    -- 磨损
    BLADE_BREAK = "blade_break",   -- 脆弱
    TEMPER      = "temper",        -- 耐久
}

-- ============================================================================
-- 装备槽位枚举（2 槽简化版）
-- ============================================================================

CardData.SLOT = {
    UPPER = "upper",   -- 上半身
    LOWER = "lower",   -- 下半身
}

-- ============================================================================
-- 稀有度枚举
-- ============================================================================

CardData.RARITY = {
    COMMON     = "common",
    RARE       = "rare",
    SUPER_RARE = "super_rare",
    MAJESTIC   = "majestic",
    LEGENDARY  = "legendary",
    TOKEN      = "token",
}

-- ============================================================================
-- 构造
-- ============================================================================

--- 创建卡牌数据
---@param def table
---@return table
function CardData.new(def)
    local card = setmetatable({}, CardData)

    -- 基础属性
    card.id       = def.id or "unknown"
    card.name     = def.name or "???"          -- 本作换皮名
    card.cardType = def.type or CardData.TYPE.ATTACK
    card.pitch    = def.pitch or 0             -- 0=无, 1=红, 2=黄, 3=蓝
    card.cost     = def.cost or 0              -- 资源费用
    card.power    = def.power or 0             -- 攻击力
    card.defense  = def.defense or 0           -- 防御值

    -- 分类
    card.class          = def.class or CardData.CLASS.GENERIC
    card.specialization = def.specialization or nil   -- 专属英雄 id
    card.rarity         = def.rarity or CardData.RARITY.COMMON

    -- 关键词
    card.keywords = def.keywords or {}         -- {"go_again", "dominate"} 等
    card.goAgain  = def.goAgain or false       -- 固有 Go Again（快捷字段）

    -- Combo 系统
    card.comboFrom = def.comboFrom or nil      -- Combo 前置卡名（本作名）

    -- 效果系统（effect-system.md）
    card.effects       = def.effects or {}     -- EffectTag[]
    card.customHandler = def.customHandler or nil  -- 特殊处理器 ID

    -- 显示用
    card.text = def.text or ""                 -- 效果描述文字

    return card
end

-- ============================================================================
-- 查询方法
-- ============================================================================

--- 是否为攻击牌
function CardData:isAttack()
    return self.cardType == CardData.TYPE.ATTACK
end

--- 是否可用于防御（有防御值即可）
function CardData:canDefend()
    return self.defense > 0
end

--- 是否为反应牌（追击 / 闪避）
function CardData:isReaction()
    return self.cardType == CardData.TYPE.CHASE
        or self.cardType == CardData.TYPE.DODGE
end

--- 是否为留场牌（状态 / 道具）
function CardData:isArenaCard()
    return self.cardType == CardData.TYPE.AURA
        or self.cardType == CardData.TYPE.ITEM
end

--- 是否需要行动点来打出
function CardData:costsActionPoint()
    local t = self.cardType
    return t == CardData.TYPE.ATTACK
        or t == CardData.TYPE.SUPPORT
        or t == CardData.TYPE.AURA
        or t == CardData.TYPE.ITEM
end

--- 是否拥有指定关键词
---@param kw string 关键词 id
---@return boolean
function CardData:hasKeyword(kw)
    for _, k in ipairs(self.keywords) do
        if k == kw then return true end
    end
    return false
end

--- 获取 pitch 颜色信息
function CardData:getPitchColor()
    return CardData.PITCH_COLORS[self.pitch]
end

--- 获取 pitch 颜色名
function CardData:getPitchColorName()
    if self.pitch == 1 then return "red"
    elseif self.pitch == 2 then return "yellow"
    elseif self.pitch == 3 then return "blue"
    else return "none" end
end

return CardData

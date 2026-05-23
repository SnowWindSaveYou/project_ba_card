-- ============================================================================
-- AI/CardEvaluator.lua - 数据驱动的卡牌评估系统
-- 根据卡牌属性（攻击力/费用/关键词/效果）计算分数
-- 扩展新卡包时只需更新 CARD_OVERRIDES 表
-- ============================================================================

local CardData    = require("Card.CardData")
local CardDB      = require("Card.CardDB")
local PitchSystem = require("Game.PitchSystem")

local TYPE = CardData.TYPE
local KW   = CardData.KEYWORD
local P    = CardData.PITCH

local CardEvaluator = {}

-- ============================================================================
-- 扩展点 1: 每卡 ID 评分覆写（新卡包在这里加条目）
-- 值可以是数字（固定加分）或 function(card, ctx) → number
-- ============================================================================

---@type table<string, number|fun(card:table, ctx:table):number>
CardEvaluator.CARD_OVERRIDES = {
    -- === 剑道专属 ===
    spec_steelblade_supremacy   = 9,   -- 一刀入魂：架势+2 + 命中抽牌
    spec_singing_steelblade     = 7,   -- 残心追击：搜索追击牌
    spec_ironsong_determination = 8,   -- 不动心：架势+1+必杀+连招

    -- === 跆拳道专属 ===
    spec_mugenshi_release       = 8,   -- 无影·解放：combo 终端搜牌
    spec_lord_of_wind           = 7,   -- 疾风连环：combo 终端倍增

    -- === 太极专属 ===
    spec_crippling_crush        = 10,  -- 泰山压顶：重击弃2牌
    spec_show_time              = 7,   -- 四两拨千斤：搜索+抽牌

    -- === 拳击专属 ===
    spec_alpha_rampage_r        = 9,   -- 暴风连拳(仅红色)：高攻+震慑
    spec_sand_sketched_plan     = 7,   -- 拳感直觉：搜索+条件奖励

    -- === 通用高价值 ===
    gen_enlightened_strike       = 7,   -- 灵光一闪：三选一灵活
    gen_tome_of_fyendal          = 8,   -- 教练笔记：抽2+回血
    gen_energy_potion            = 5,   -- 能量饮料：即时资源
    gen_potion_of_strength       = 5,   -- 力量补剂：即时 buff

    -- === 重击系列（太极核心输出）===
    gua_spinal_crush             = 9,   -- 推山掌：禁连招
    gua_cranial_crush            = 8,   -- 封脉掌：禁抽牌
}

-- ============================================================================
-- 扩展点 2: 职业策略权重（影响评分侧重）
-- ============================================================================

---@type table<string, table>
CardEvaluator.CLASS_WEIGHTS = {
    warrior = {
        weapon_bonus     = 3.0,   -- 重视架势攻击
        support_bonus    = 2.0,   -- 重视 buff 辅助
        chase_bonus      = 2.5,   -- 重视追击牌
        combo_bonus      = 0.5,   -- 剑道无 combo
        crush_bonus      = 0.0,
        intimidate_bonus = 0.0,
        go_again_value   = 2.0,   -- 连招链条
        dominate_value   = 3.0,   -- 必杀限制防御
    },
    ninja = {
        weapon_bonus     = 1.0,   -- 站架便宜但弱
        support_bonus    = 1.0,
        chase_bonus      = 1.5,
        combo_bonus      = 3.0,   -- 核心机制
        crush_bonus      = 0.0,
        intimidate_bonus = 0.0,
        go_again_value   = 3.0,   -- 连招链核心
        dominate_value   = 2.5,
    },
    guardian = {
        weapon_bonus     = 1.5,   -- 太极起势费用高
        support_bonus    = 2.0,   -- aura 重要
        chase_bonus      = 1.0,
        combo_bonus      = 0.0,
        crush_bonus      = 3.0,   -- 核心机制
        intimidate_bonus = 0.0,
        go_again_value   = 1.5,
        dominate_value   = 2.0,
    },
    brute = {
        weapon_bonus     = 1.5,
        support_bonus    = 2.0,
        chase_bonus      = 1.0,
        combo_bonus      = 0.0,
        crush_bonus      = 0.0,
        intimidate_bonus = 3.0,   -- 核心机制
        go_again_value   = 2.0,
        dominate_value   = 2.0,
    },
}

-- 默认权重（通用/未知职业）
CardEvaluator.CLASS_WEIGHTS["generic"] = {
    weapon_bonus = 1.5, support_bonus = 1.5, chase_bonus = 1.5,
    combo_bonus = 1.0, crush_bonus = 1.0, intimidate_bonus = 1.0,
    go_again_value = 2.0, dominate_value = 2.0,
}

-- ============================================================================
-- 内部: 获取职业权重
-- ============================================================================

local function getWeights(class)
    return CardEvaluator.CLASS_WEIGHTS[class]
        or CardEvaluator.CLASS_WEIGHTS["generic"]
end

-- ============================================================================
-- 核心评分函数
-- ============================================================================

--- 评估攻击牌的进攻价值
---@param card table CardData
---@param player table Player (攻击方)
---@param opponent table Player (防御方)
---@return number score 分数 (越高越值得打出)
function CardEvaluator.scoreAttack(card, player, opponent)
    local w = getWeights(player.class)
    local score = 0

    -- 基础: 攻击力 - 费用
    score = score + (card.power or 0) - (card.cost or 0) * 0.8

    -- 关键词加分
    if card:hasKeyword(KW.GO_AGAIN) or card.goAgain then
        score = score + w.go_again_value
    end
    if card:hasKeyword(KW.DOMINATE) then
        score = score + w.dominate_value
    end
    if card:hasKeyword(KW.CRUSH) then
        score = score + w.crush_bonus
    end
    if card:hasKeyword(KW.INTIMIDATE) then
        score = score + w.intimidate_bonus
    end

    -- combo 条件匹配加分
    if card.comboFrom then
        local lastAtk = player.turnStats and player.turnStats.lastAttackName
        if lastAtk == card.comboFrom then
            score = score + w.combo_bonus + 2  -- combo 匹配: 大加分
        else
            score = score - 2  -- combo 不匹配: 减分（可能打不出）
        end
    end

    -- 效果文本中含 draw 或 on_hit 加分
    if card.effects then
        for _, eff in ipairs(card.effects) do
            if eff.id == "on_hit" then score = score + 1.5 end
            if eff.id == "draw"   then score = score + 1.0 end
            if eff.id == "return_to_hand_on_hit" then score = score + 2.0 end
            if eff.id == "crush_check" then score = score + w.crush_bonus end
        end
    end

    -- 对手血量低时高攻击力更有价值
    if opponent.life <= 8 and (card.power or 0) >= 5 then
        score = score + 2
    end

    -- CARD_OVERRIDES
    local override = CardEvaluator.CARD_OVERRIDES[card.id]
    if override then
        if type(override) == "number" then
            score = override  -- 固定分数覆写
        else
            score = override(card, { player = player, opponent = opponent })
        end
    end

    return score
end

--- 评估架势（武器）攻击价值
---@param weapon table { data=weaponData, hitCounters=N, usedThisTurn=bool }
---@param player table
---@param opponent table
---@return number
function CardEvaluator.scoreWeapon(weapon, player, opponent)
    local w = getWeights(player.class)
    local wData = weapon.data
    local score = (wData.power or 0) - (wData.cost or 0) * 0.8

    -- 武器攻击力含计数器
    score = score + (weapon.hitCounters or 0)

    -- 职业加成
    score = score + w.weapon_bonus

    -- 对手血量低时更激进
    if opponent.life <= 6 then
        score = score + 2
    end

    return score
end

--- 评估辅助牌价值
---@param card table
---@param player table
---@param opponent table
---@return number
function CardEvaluator.scoreSupport(card, player, opponent)
    local w = getWeights(player.class)
    local score = 0

    -- 辅助牌：buff 效果 + 连招价值
    if card.goAgain or card:hasKeyword(KW.GO_AGAIN) then
        score = score + w.go_again_value
    end

    -- 效果加分
    if card.effects then
        for _, eff in ipairs(card.effects) do
            if eff.id == "buff_power" then
                local amt = eff.params and eff.params.amount or 0
                score = score + amt * 1.2
            end
            if eff.id == "buff_power_until_eot" then
                local amt = eff.params and eff.params.amount or 0
                score = score + amt * 1.5
            end
            if eff.id == "grant_go_again" then score = score + 1.5 end
            if eff.id == "grant_dominate" then score = score + w.dominate_value end
            if eff.id == "draw" then score = score + 1.5 end
        end
    end

    -- 费用折扣
    score = score - (card.cost or 0) * 0.8

    -- 职业加成
    score = score + w.support_bonus

    -- CARD_OVERRIDES
    local override = CardEvaluator.CARD_OVERRIDES[card.id]
    if override then
        if type(override) == "number" then
            score = override
        else
            score = override(card, { player = player, opponent = opponent })
        end
    end

    return score
end

--- 评估追击牌价值
---@param card table
---@param player table
---@param opponent table
---@return number
function CardEvaluator.scoreChase(card, player, opponent)
    local w = getWeights(player.class)
    local score = 2  -- 基础: 追击总是有一定价值

    if card.effects then
        for _, eff in ipairs(card.effects) do
            if eff.id == "buff_power" then
                local amt = eff.params and eff.params.amount or 0
                score = score + amt
            end
            if eff.id == "draw" then score = score + 1.5 end
        end
    end

    -- reprise 条件（反击：对手用手牌防御时）
    if card:hasKeyword(KW.REPRISE) then
        local oppDefended = opponent.turnStats and opponent.turnStats.cardsDefendedWith or 0
        if oppDefended > 0 then
            score = score + 2  -- reprise 条件满足
        end
    end

    score = score - (card.cost or 0) * 0.8
    score = score + w.chase_bonus

    local override = CardEvaluator.CARD_OVERRIDES[card.id]
    if override then
        score = type(override) == "number" and override
            or override(card, { player = player, opponent = opponent })
    end

    return score
end

--- 评估闪避牌价值
---@param card table
---@param incomingDamage number 当前攻击的伤害
---@return number
function CardEvaluator.scoreDodge(card, incomingDamage)
    local score = (card.defense or 0)

    -- 如果闪避值 >= 攻击伤害，价值更高
    if (card.defense or 0) >= incomingDamage then
        score = score + 3
    end

    -- 额外效果加分
    if card.effects then
        for _, eff in ipairs(card.effects) do
            if eff.id == "deal_damage" then score = score + 2 end
            if eff.id == "draw" then score = score + 1.5 end
            if eff.id == "buff_defense" then
                local amt = eff.params and eff.params.amount or 0
                score = score + amt
            end
        end
    end

    score = score - (card.cost or 0) * 0.8
    return score
end

--- 评估一张手牌用于防御的价值（要减去其进攻机会成本）
---@param card table
---@param incomingDamage number
---@param player table (防御方)
---@return number score 正数=值得防御, 负数=不值得
function CardEvaluator.scoreDefenseCard(card, incomingDamage, player)
    local defValue = card.defense or 0
    if defValue <= 0 then return -100 end  -- 不能防御

    -- 防御贡献
    local score = defValue

    -- 减去进攻机会成本（攻击牌手牌防御代价更高）
    local oppCost = 0
    if card:isAttack() then
        oppCost = (card.power or 0) * 0.5  -- 攻击力折半视为机会成本
        if card:hasKeyword(KW.GO_AGAIN) or card.goAgain then
            oppCost = oppCost + 1  -- 连招牌更不舍得
        end
    end

    -- pitch 牌用于防御损失充能能力
    if card.pitch and card.pitch >= P.BLUE then
        oppCost = oppCost + 0.5
    end

    score = score - oppCost

    -- 如果血量充足，不需要过度防御
    if player.life > 14 and incomingDamage <= 3 then
        score = score - 1  -- 少扣分但仍倾向于少防
    end

    return score
end

--- 评估将手牌放入预备区的价值
---@param card table
---@param player table
---@return number
function CardEvaluator.scoreArsenal(card, player)
    local score = 0

    -- 攻击牌放入预备区（下回合打出）
    if card:isAttack() then
        score = (card.power or 0) * 0.6
        if card:hasKeyword(KW.GO_AGAIN) or card.goAgain then
            score = score + 1
        end
    end

    -- 闪避/追击牌放入预备区有即时价值
    if card.cardType == TYPE.DODGE then
        score = score + (card.defense or 0) * 0.8
    end
    if card.cardType == TYPE.CHASE then
        score = score + 2
    end

    -- 辅助牌也值得存
    if card.cardType == TYPE.SUPPORT then
        score = score + 2
    end

    -- 高 pitch 牌存预备区浪费充能潜力
    if card.pitch and card.pitch >= P.BLUE then
        score = score - 0.5
    end

    return score
end

--- 评估充能消耗的牌的损失（pitch 时优先丢哪些牌）
--- 返回值越低，越适合用来充能
---@param card table
---@param player table
---@return number lossScore 机会成本(低=好)
function CardEvaluator.scorePitchLoss(card, player)
    local w = getWeights(player.class)
    local loss = 0

    -- 攻击牌充能 → 失去攻击机会
    if card:isAttack() then
        loss = loss + (card.power or 0) * 0.4
        if card:hasKeyword(KW.GO_AGAIN) or card.goAgain then
            loss = loss + 1
        end
    end

    -- 辅助牌充能
    if card.cardType == TYPE.SUPPORT or card.cardType == TYPE.AURA then
        loss = loss + 1
    end

    -- 追击/闪避牌充能代价较低
    if card.cardType == TYPE.CHASE or card.cardType == TYPE.DODGE then
        loss = loss + 0.5
    end

    -- combo 牌如果当前 combo 链不匹配，充能代价很低
    if card.comboFrom then
        local lastAtk = player.turnStats and player.turnStats.lastAttackName
        if lastAtk ~= card.comboFrom then
            loss = loss - 1  -- 打不出的 combo 牌适合充能
        end
    end

    return loss
end

return CardEvaluator

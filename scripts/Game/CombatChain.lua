-- ============================================================================
-- Game/CombatChain.lua - 战斗链/连招系统
-- 管理一条完整的攻防链：攻击声明 → 防御声明 → 反应阶段 → 伤害结算
-- 支持多环节（Go Again 继续 → 新 chain link）
-- ============================================================================

local CardData = require("Card.CardData")
local CardDB   = require("Card.CardDB")
local KW = CardData.KEYWORD

local CombatChain = {}
CombatChain.__index = CombatChain

-- ============================================================================
-- 连招链环节 (Chain Link) 数据结构
-- ============================================================================

--- 创建一个空的连招链环节
---@return table
local function newChainLink()
    return {
        -- 攻击方
        attackCardId   = nil,     -- 攻击牌 ID
        attackCard     = nil,     -- CardData
        attackPower    = 0,       -- 当前攻击力（含 buff）
        isWeaponAttack = false,   -- 是否为架势攻击
        weaponIndex    = nil,     -- 架势索引（如适用）
        powerBuffs     = {},      -- 攻击力 buff 记录

        -- 防御方
        defendCards    = {},      -- { cardId, defValue } 用于防御的手牌
        equipDefends   = {},      -- { slot, defValue } 用于防御的护具
        totalDefense   = 0,       -- 总防御值

        -- 反应阶段
        attackReactions = {},     -- 追击牌 [{cardId, cardData}]
        defenseReactions = {},    -- 闪避牌 [{cardId, cardData}]

        -- 结算
        resolved       = false,
        damageDealt    = 0,       -- 实际伤害
        didHit         = false,   -- 是否命中（伤害 > 0）
        goAgain        = false,   -- 解算后是否获得连招

        -- 关键词
        hasDominate    = false,   -- 必杀
        hasIntimidated = false,   -- 本环节已触发震慑
    }
end

-- ============================================================================
-- 构造
-- ============================================================================

--- 创建新的连招链
---@param attacker table Player
---@param defender table Player
---@return table
function CombatChain.new(attacker, defender)
    local self = setmetatable({}, CombatChain)

    self.attacker = attacker
    self.defender = defender
    self.links    = {}           -- ChainLink[]
    self.current  = nil          -- 当前环节
    self.closed   = false        -- 连招链是否已关闭

    -- 事件回调（由 GameFSM 注册）
    self.callbacks = {
        onAttackDeclared  = nil,  -- function(link)
        onDefenseDeclared = nil,  -- function(link)
        onReactionPlayed  = nil,  -- function(link, card, isAttacker)
        onDamageResolved  = nil,  -- function(link, damage, didHit)
        onChainClosed     = nil,  -- function(chain)
        onGoAgain         = nil,  -- function(link)
    }

    return self
end

-- ============================================================================
-- 攻击声明
-- ============================================================================

--- 声明攻击（出攻击牌或架势）
---@param opts table { cardId?, weaponIndex?, powerBuff? }
---@return table|nil link 当前链接，nil 表示失败
---@return string|nil error
function CombatChain:declareAttack(opts)
    if self.closed then return nil, "chain_closed" end

    local link = newChainLink()
    link.powerBuffs = {}

    if opts.cardId then
        -- 卡牌攻击
        local card = CardDB.get(opts.cardId)
        if not card then return nil, "unknown_card" end

        link.attackCardId   = opts.cardId
        link.attackCard     = card
        link.attackPower    = card.power
        link.isWeaponAttack = false

        -- 检查固有 Go Again
        if card.goAgain or card:hasKeyword(KW.GO_AGAIN) then
            link.goAgain = true
        end

        -- 检查必杀
        if card:hasKeyword(KW.DOMINATE) then
            link.hasDominate = true
        end

        -- 记录攻击
        self.attacker:recordAttackPlayed(card.name)

    elseif opts.weaponIndex then
        -- 架势攻击
        local weaponState = self.attacker.weapons[opts.weaponIndex]
        if not weaponState then return nil, "invalid_weapon" end

        link.isWeaponAttack = true
        link.weaponIndex    = opts.weaponIndex
        link.attackCard     = nil -- 架势没有 CardData（数据在 weaponData 里）
        link.attackPower    = weaponState.data.power + (weaponState.hitCounters or 0)
        link.attackCardId   = weaponState.data.id
    else
        return nil, "no_attack_source"
    end

    -- 应用外部攻击力 buff
    if opts.powerBuff then
        link.attackPower = link.attackPower + opts.powerBuff
        link.powerBuffs[#link.powerBuffs + 1] = {
            source = "external",
            amount = opts.powerBuff,
        }
    end

    -- 加入链条
    self.links[#self.links + 1] = link
    self.current = link

    -- 更新回合统计
    self.attacker.turnStats.chainLinkIndex = #self.links

    -- 触发回调
    if self.callbacks.onAttackDeclared then
        self.callbacks.onAttackDeclared(link)
    end

    return link, nil
end

-- ============================================================================
-- 增益应用
-- ============================================================================

--- 给当前攻击增加攻击力
---@param amount number
---@param source? string
function CombatChain:buffCurrentPower(amount, source)
    if not self.current then return end
    self.current.attackPower = self.current.attackPower + amount
    self.current.powerBuffs[#self.current.powerBuffs + 1] = {
        source = source or "effect",
        amount = amount,
    }
end

--- 给当前攻击添加 Go Again
function CombatChain:grantGoAgain()
    if not self.current then return end
    self.current.goAgain = true
end

--- 给当前攻击添加必杀
function CombatChain:grantDominate()
    if not self.current then return end
    self.current.hasDominate = true
end

-- ============================================================================
-- 防御声明
-- ============================================================================

--- 声明防御（手牌 + 护具）
---@param handCardIds string[] 用于防御的手牌 ID
---@param equipSlots string[] 使用防御的护具槽位
---@return number totalDefense
function CombatChain:declareDefense(handCardIds, equipSlots)
    if not self.current or self.current.resolved then
        return 0
    end

    local link = self.current
    local totalDef = 0

    -- 必杀：只允许 1 张手牌防御
    local maxHandCards = link.hasDominate and 1 or #handCardIds

    -- 手牌防御
    for i = 1, math.min(maxHandCards, #handCardIds) do
        local cardId = handCardIds[i]
        local card = CardDB.get(cardId)
        if card and card.defense > 0 then
            -- 从防御方手牌移除
            if self.defender:removeFromHand(cardId) then
                local defValue = card.defense
                link.defendCards[#link.defendCards + 1] = {
                    cardId   = cardId,
                    defValue = defValue,
                }
                totalDef = totalDef + defValue
                self.defender.turnStats.cardsDefendedWith =
                    self.defender.turnStats.cardsDefendedWith + 1
            end
        end
    end

    -- 护具防御
    for _, slot in ipairs(equipSlots) do
        local defValue = self.defender:useEquipmentDefense(slot)
        if defValue > 0 then
            link.equipDefends[#link.equipDefends + 1] = {
                slot     = slot,
                defValue = defValue,
            }
            totalDef = totalDef + defValue
        end
    end

    link.totalDefense = totalDef

    -- 触发回调
    if self.callbacks.onDefenseDeclared then
        self.callbacks.onDefenseDeclared(link)
    end

    return totalDef
end

--- 获取防御方用了多少张手牌防御
---@return number
function CombatChain:getDefenseHandCount()
    if not self.current then return 0 end
    return #self.current.defendCards
end

--- 防御方是否使用了手牌防御（反击条件判定）
---@return boolean
function CombatChain:defenderUsedHandCards()
    return self:getDefenseHandCount() > 0
end

-- ============================================================================
-- 反应阶段
-- ============================================================================

--- 攻击方打出追击牌
---@param cardId string
---@return boolean success
function CombatChain:playAttackReaction(cardId)
    if not self.current or self.current.resolved then
        return false
    end

    local card = CardDB.get(cardId)
    if not card then return false end
    if card.cardType ~= CardData.TYPE.CHASE then return false end

    -- 从攻击方手牌移除
    if not self.attacker:removeFromHand(cardId) then
        return false
    end

    self.current.attackReactions[#self.current.attackReactions + 1] = {
        cardId = cardId,
        data   = card,
    }

    -- 追击牌通常 buff 攻击力（具体效果由 EffectProcessor 处理）
    -- 这里仅记录，实际 buff 应用由上层调用 buffCurrentPower

    if self.callbacks.onReactionPlayed then
        self.callbacks.onReactionPlayed(self.current, card, true)
    end

    return true
end

--- 防御方打出闪避牌
---@param cardId string
---@return boolean success
function CombatChain:playDefenseReaction(cardId)
    if not self.current or self.current.resolved then
        return false
    end

    local card = CardDB.get(cardId)
    if not card then return false end
    if card.cardType ~= CardData.TYPE.DODGE then return false end

    -- 从防御方手牌移除
    if not self.defender:removeFromHand(cardId) then
        return false
    end

    self.current.defenseReactions[#self.current.defenseReactions + 1] = {
        cardId = cardId,
        data   = card,
    }

    -- 闪避牌增加防御值
    local defBonus = card.defense
    self.current.totalDefense = self.current.totalDefense + defBonus

    if self.callbacks.onReactionPlayed then
        self.callbacks.onReactionPlayed(self.current, card, false)
    end

    return true
end

-- ============================================================================
-- 伤害结算
-- ============================================================================

--- 结算当前环节
---@return number damage 实际伤害
---@return boolean didHit 是否命中
function CombatChain:resolveCurrentLink()
    if not self.current or self.current.resolved then
        return 0, false
    end

    local link = self.current
    local rawDamage = math.max(0, link.attackPower - link.totalDefense)

    -- 实际扣血
    local actualDamage = 0
    if rawDamage > 0 then
        actualDamage = self.defender:takeDamage(rawDamage)
    end

    link.damageDealt = actualDamage
    link.didHit = actualDamage > 0
    link.resolved = true

    -- 架势命中记录
    if link.didHit and link.isWeaponAttack and link.weaponIndex then
        self.attacker:recordWeaponHit(link.weaponIndex)
    end

    -- 更新攻击方统计
    self.attacker.turnStats.totalDamageDealt =
        self.attacker.turnStats.totalDamageDealt + actualDamage

    -- 触发回调
    if self.callbacks.onDamageResolved then
        self.callbacks.onDamageResolved(link, actualDamage, link.didHit)
    end

    return actualDamage, link.didHit
end

-- ============================================================================
-- Go Again / 连招链接续
-- ============================================================================

--- 当前环节结算后检查是否继续
---@return boolean hasGoAgain
function CombatChain:checkGoAgain()
    if not self.current or not self.current.resolved then
        return false
    end
    return self.current.goAgain
end

--- 处理 Go Again：给攻击方行动点
function CombatChain:processGoAgain()
    if self:checkGoAgain() then
        self.attacker:gainActionPoint(1)
        if self.callbacks.onGoAgain then
            self.callbacks.onGoAgain(self.current)
        end
    end
end

-- ============================================================================
-- 关闭连招链
-- ============================================================================

--- 关闭连招链，所有攻防牌进弃牌堆
---@return table summary { totalDamage, linkCount, hits }
function CombatChain:close()
    if self.closed then
        return self:getSummary()
    end

    self.closed = true

    -- 将所有环节中的牌送入弃牌堆
    for _, link in ipairs(self.links) do
        -- 攻击牌 → 攻击方弃牌堆
        if link.attackCardId and not link.isWeaponAttack then
            -- 检查是否有 "to_deck_bottom_instead_of_graveyard" 效果
            local card = link.attackCard
            local toDeckBottom = false
            if card and card.effects then
                for _, eff in ipairs(card.effects) do
                    if eff.id == "to_deck_bottom_instead_of_graveyard" then
                        toDeckBottom = true
                        break
                    end
                end
            end

            if toDeckBottom then
                self.attacker:putToDeckBottom(link.attackCardId)
            else
                self.attacker:addToGraveyard(link.attackCardId)
            end
        end

        -- 追击牌 → 攻击方弃牌堆
        for _, ar in ipairs(link.attackReactions) do
            self.attacker:addToGraveyard(ar.cardId)
        end

        -- 防御手牌 → 防御方弃牌堆
        for _, dc in ipairs(link.defendCards) do
            self.defender:addToGraveyard(dc.cardId)
        end

        -- 闪避牌 → 防御方弃牌堆
        for _, dr in ipairs(link.defenseReactions) do
            self.defender:addToGraveyard(dr.cardId)
        end
    end

    -- 处理脆弱护具销毁
    self.defender:resolveBladeBreak()

    -- 触发回调
    if self.callbacks.onChainClosed then
        self.callbacks.onChainClosed(self)
    end

    return self:getSummary()
end

-- ============================================================================
-- 查询
-- ============================================================================

--- 获取连招链摘要
---@return table
function CombatChain:getSummary()
    local totalDamage = 0
    local hits = 0
    for _, link in ipairs(self.links) do
        totalDamage = totalDamage + link.damageDealt
        if link.didHit then hits = hits + 1 end
    end
    -- 取最后一个 link 的攻防数值，供结算动画显示
    local lastLink = self.links[#self.links]
    local lastAttackPower  = lastLink and lastLink.attackPower  or 0
    local lastTotalDefense = lastLink and lastLink.totalDefense or 0
    return {
        totalDamage      = totalDamage,
        linkCount        = #self.links,
        hits             = hits,
        closed           = self.closed,
        lastAttackPower  = lastAttackPower,
        lastTotalDefense = lastTotalDefense,
    }
end

--- 当前环节索引
---@return number
function CombatChain:currentLinkIndex()
    return #self.links
end

--- 获取上一个攻击牌的名称（Combo 判定）
---@return string|nil
function CombatChain:getLastAttackName()
    if #self.links < 2 then
        return self.attacker.turnStats.lastAttackName
    end
    local prevLink = self.links[#self.links - 1]
    if prevLink and prevLink.attackCard then
        return prevLink.attackCard.name
    end
    return nil
end

--- 检查 Combo 条件是否满足
---@param requiredPrevName string 需要的前置攻击名
---@return boolean
function CombatChain:checkCombo(requiredPrevName)
    local prevName = self:getLastAttackName()
    return prevName == requiredPrevName
end

--- 获取连招链中的所有攻击名称序列
---@return string[]
function CombatChain:getAttackSequence()
    local seq = {}
    for _, link in ipairs(self.links) do
        if link.attackCard then
            seq[#seq + 1] = link.attackCard.name
        elseif link.isWeaponAttack then
            local w = self.attacker.weapons[link.weaponIndex]
            if w then
                seq[#seq + 1] = w.data.name .. "(架势)"
            end
        end
    end
    return seq
end

--- 是否有任何未结算的环节
---@return boolean
function CombatChain:hasPendingLink()
    return self.current ~= nil and not self.current.resolved
end

--- 连招链是否为空
---@return boolean
function CombatChain:isEmpty()
    return #self.links == 0
end

return CombatChain

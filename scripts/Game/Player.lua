-- ============================================================================
-- Game/Player.lua - 玩家状态管理
-- 管理单个玩家的所有游戏状态：生命、手牌、牌库、弃牌堆、充能区、
-- 预备区、放逐区、护具、架势、行动点、体能资源
-- ============================================================================

local CardData = require("Card.CardData")
local HeroData = require("Card.HeroData")
local CardDB   = require("Card.CardDB")

local KW   = CardData.KEYWORD
local SLOT = CardData.SLOT

local Player = {}
Player.__index = Player

-- ============================================================================
-- 构造
-- ============================================================================

--- 创建玩家
---@param cfg table { heroKey, deckCardIds, equipmentIds? }
---@return table
function Player.new(cfg)
    local self = setmetatable({}, Player)

    -- 英雄数据
    local hero = HeroData.getHero(cfg.heroKey)
    assert(hero, "Unknown hero key: " .. tostring(cfg.heroKey))

    self.heroKey   = cfg.heroKey
    self.heroData  = hero
    self.heroName  = hero.name
    self.class     = hero.class

    -- 核心数值
    self.life         = hero.life          -- 当前体力
    self.maxLife      = hero.life          -- 最大体力
    self.intellect    = hero.intellect     -- 专注力（每回合抽牌上限）
    self.tempIntellect = 0                 -- 临时专注力加成（回合结束重置）

    -- 资源系统
    self.actionPoints  = 0                 -- 行动点
    self.resourcePool  = 0                 -- 体能资源池

    -- 区域 (存储 card ID 列表)
    self.deck       = {}                   -- 牌库（有序，[1]=顶部）
    self.hand       = {}                   -- 手牌
    self.graveyard  = {}                   -- 弃牌堆
    self.pitchZone  = {}                   -- 充能区（本回合横置的牌）
    self.arsenal     = {}                  -- 预备区（最多 1 张，面朝下）
    self.banishZone = {}                   -- 放逐区

    -- 震慑暂存区（回合结束归还手牌）
    self.intimidatedCards = {}

    -- 护具系统 (2 槽)
    self.equipment = {
        [SLOT.UPPER] = nil,    -- { data=equipData, defense=N, usedThisTurn=bool, counters={} }
        [SLOT.LOWER] = nil,
    }

    -- 架势（武器）系统
    self.weapons = {}                      -- { data=weaponData, hitCounters=0, usedThisTurn=bool }

    -- 场上留场牌 (aura/item)
    self.arenaCards = {}                   -- { cardData, ... }

    -- 回合统计
    self.turnStats = Player._newTurnStats()

    -- 英雄能力追踪
    self.heroAbilityUsed = false

    -- 初始化牌库
    self:_initDeck(cfg.deckCardIds or {})

    -- 初始化护具
    self:_initEquipment(cfg.equipmentIds or {})

    -- 初始化架势
    self:_initWeapons()

    return self
end

--- 重置回合统计
---@return table
function Player._newTurnStats()
    return {
        attacksPlayed     = 0,     -- 本回合打出的攻击牌数
        weaponHits        = 0,     -- 本回合架势命中次数
        chainLinkIndex    = 0,     -- 当前连招链环节索引
        totalDamageDealt  = 0,     -- 本回合造成的总伤害
        cardsDefendedWith = 0,     -- 本回合用于防御的手牌数
        lastAttackName    = nil,   -- 上一次攻击的卡名（Combo 判定）
        pitchedThisTurn   = {},    -- 本回合充能过的牌 ID 列表
        playedFromArsenal = false, -- 本回合是否从预备区打出过
    }
end

-- ============================================================================
-- 初始化
-- ============================================================================

--- 初始化牌库（洗牌）
---@param cardIds string[]
function Player:_initDeck(cardIds)
    self.deck = {}
    for i = 1, #cardIds do
        local card = CardDB.get(cardIds[i])
        if card then
            self.deck[#self.deck + 1] = cardIds[i]
        else
            print("[Player] WARNING: Unknown card ID in deck: " .. tostring(cardIds[i]))
        end
    end
    self:shuffleDeck()
end

--- 初始化护具
---@param equipIds string[]
function Player:_initEquipment(equipIds)
    for _, eqId in ipairs(equipIds) do
        local eqData = HeroData.getEquipmentById(eqId)
        if eqData then
            local slot = eqData.slot
            self.equipment[slot] = {
                data          = eqData,
                defense       = eqData.defense,    -- 当前防御值
                maxDefense    = eqData.defense,    -- 初始防御值
                usedThisTurn  = false,
                destroyed     = false,
                counters      = {},                -- 能量计数器等
            }
        else
            print("[Player] WARNING: Unknown equipment ID: " .. tostring(eqId))
        end
    end
end

--- 初始化架势（按职业自动配备）
function Player:_initWeapons()
    local weaponList = HeroData.getWeaponsForClass(self.class)
    for _, wData in ipairs(weaponList) do
        local count = wData.count or 1
        for _ = 1, count do
            self.weapons[#self.weapons + 1] = {
                data          = wData,
                hitCounters   = 0,         -- 命中计数器（如正眼之构）
                usedThisTurn  = false,
            }
        end
    end
end

-- ============================================================================
-- 牌库操作
-- ============================================================================

--- 洗牌
function Player:shuffleDeck()
    local n = #self.deck
    for i = n, 2, -1 do
        local j = math.random(1, i)
        self.deck[i], self.deck[j] = self.deck[j], self.deck[i]
    end
end

--- 抽牌（从牌库顶部抽 N 张到手牌）
---@param amount number
---@return string[] drawnIds 实际抽到的牌 ID
function Player:drawCards(amount)
    local drawn = {}
    for _ = 1, amount do
        if #self.deck == 0 then break end
        local cardId = table.remove(self.deck, 1)
        self.hand[#self.hand + 1] = cardId
        drawn[#drawn + 1] = cardId
    end
    return drawn
end

--- 补牌至专注力上限
---@return string[] drawnIds
function Player:drawToIntellect()
    local target = self.intellect + self.tempIntellect
    local need = target - #self.hand
    if need <= 0 then return {} end
    return self:drawCards(need)
end

--- 查看牌库顶部 N 张（不移除）
---@param n number
---@return string[]
function Player:peekDeck(n)
    local result = {}
    for i = 1, math.min(n, #self.deck) do
        result[i] = self.deck[i]
    end
    return result
end

--- 将卡牌放到牌库底部
---@param cardId string
function Player:putToDeckBottom(cardId)
    self.deck[#self.deck + 1] = cardId
end

--- 将卡牌放到牌库顶部
---@param cardId string
function Player:putToDeckTop(cardId)
    table.insert(self.deck, 1, cardId)
end

-- ============================================================================
-- 手牌操作
-- ============================================================================

--- 从手牌移除指定卡牌
---@param cardId string
---@return boolean success
function Player:removeFromHand(cardId)
    for i = 1, #self.hand do
        if self.hand[i] == cardId then
            table.remove(self.hand, i)
            return true
        end
    end
    return false
end

--- 手牌中是否有指定卡牌
---@param cardId string
---@return boolean
function Player:handContains(cardId)
    for _, id in ipairs(self.hand) do
        if id == cardId then return true end
    end
    return false
end

--- 获取手牌中所有攻击牌
---@return table[] { cardId, cardData }
function Player:getAttacksInHand()
    local result = {}
    for _, id in ipairs(self.hand) do
        local card = CardDB.get(id)
        if card and card:isAttack() then
            result[#result + 1] = { id = id, data = card }
        end
    end
    return result
end

--- 获取手牌的 CardData 列表
---@return table[]
function Player:getHandCards()
    local result = {}
    for _, id in ipairs(self.hand) do
        local card = CardDB.get(id)
        if card then
            result[#result + 1] = card
        end
    end
    return result
end

--- 随机弃牌
---@param amount number
---@return string[] discardedIds
function Player:discardRandom(amount)
    local discarded = {}
    for _ = 1, amount do
        if #self.hand == 0 then break end
        local idx = math.random(1, #self.hand)
        local cardId = table.remove(self.hand, idx)
        self.graveyard[#self.graveyard + 1] = cardId
        discarded[#discarded + 1] = cardId
    end
    return discarded
end

--- 弃指定手牌
---@param cardId string
---@return boolean success
function Player:discardFromHand(cardId)
    if self:removeFromHand(cardId) then
        self.graveyard[#self.graveyard + 1] = cardId
        return true
    end
    return false
end

--- 手牌数量
---@return number
function Player:handCount()
    return #self.hand
end

-- ============================================================================
-- 充能系统 (Pitch)
-- ============================================================================

--- 充能一张手牌（横置到充能区，获得体能）
---@param cardId string
---@return number resourceGained
function Player:pitchCard(cardId)
    if not self:removeFromHand(cardId) then
        return 0
    end
    local card = CardDB.get(cardId)
    if not card then
        -- 未知牌，退回手牌
        self.hand[#self.hand + 1] = cardId
        return 0
    end

    self.pitchZone[#self.pitchZone + 1] = cardId
    self.turnStats.pitchedThisTurn[#self.turnStats.pitchedThisTurn + 1] = cardId

    local gained = card.pitch
    self.resourcePool = self.resourcePool + gained
    return gained
end

--- 消耗体能
---@param amount number
---@return boolean success
function Player:spendResource(amount)
    if self.resourcePool < amount then return false end
    self.resourcePool = self.resourcePool - amount
    return true
end

--- 是否有足够体能
---@param amount number
---@return boolean
function Player:canAfford(amount)
    return self.resourcePool >= amount
end

--- 回合结束：充能区牌放回牌库底（按传入的顺序）
---@param order? string[] 可选：指定放回顺序的 cardId 列表
function Player:returnPitchZoneToDeck(order)
    if order and #order > 0 then
        -- 按指定顺序
        for _, cardId in ipairs(order) do
            self:putToDeckBottom(cardId)
        end
    else
        -- 默认：按充能顺序放回
        for _, cardId in ipairs(self.pitchZone) do
            self:putToDeckBottom(cardId)
        end
    end
    self.pitchZone = {}
end

-- ============================================================================
-- 预备区 (Arsenal)
-- ============================================================================

--- 将手牌放入预备区（面朝下，最多 1 张）
---@param cardId string
---@return boolean success
function Player:addToArsenal(cardId)
    if #self.arsenal >= 1 then return false end
    if not self:removeFromHand(cardId) then return false end
    self.arsenal[#self.arsenal + 1] = cardId
    return true
end

--- 从预备区打出卡牌
---@return string|nil cardId
function Player:playFromArsenal()
    if #self.arsenal == 0 then return nil end
    local cardId = table.remove(self.arsenal, 1)
    self.turnStats.playedFromArsenal = true
    return cardId
end

--- 预备区是否有牌
---@return boolean
function Player:hasArsenal()
    return #self.arsenal > 0
end

--- 获取预备区卡牌数据（不移除）
---@return table|nil cardData
function Player:peekArsenal()
    if #self.arsenal == 0 then return nil end
    return CardDB.get(self.arsenal[1])
end

--- 将预备区牌放到牌库底部（被对手效果强制）
---@return string|nil cardId
function Player:arsenalToDeckBottom()
    if #self.arsenal == 0 then return nil end
    local cardId = table.remove(self.arsenal, 1)
    self:putToDeckBottom(cardId)
    return cardId
end

-- ============================================================================
-- 弃牌堆 / 放逐区
-- ============================================================================

--- 将卡牌加入弃牌堆
---@param cardId string
function Player:addToGraveyard(cardId)
    self.graveyard[#self.graveyard + 1] = cardId
end

--- 从弃牌堆移除指定卡牌
---@param cardId string
---@return boolean
function Player:removeFromGraveyard(cardId)
    for i = 1, #self.graveyard do
        if self.graveyard[i] == cardId then
            table.remove(self.graveyard, i)
            return true
        end
    end
    return false
end

--- 从弃牌堆放逐指定卡名的牌（用于"可从弃牌堆放逐X"效果）
---@param cardName string
---@return string|nil banishedId
function Player:banishFromGraveyardByName(cardName)
    for i = 1, #self.graveyard do
        local card = CardDB.get(self.graveyard[i])
        if card and card.name == cardName then
            local cardId = table.remove(self.graveyard, i)
            self.banishZone[#self.banishZone + 1] = cardId
            return cardId
        end
    end
    return nil
end

--- 将卡牌放逐
---@param cardId string
function Player:addToBanish(cardId)
    self.banishZone[#self.banishZone + 1] = cardId
end

--- 从放逐区移除指定卡牌（应援等效果）
---@param cardId string
---@return boolean
function Player:removeFromBanish(cardId)
    for i = 1, #self.banishZone do
        if self.banishZone[i] == cardId then
            table.remove(self.banishZone, i)
            return true
        end
    end
    return false
end

--- 从弃牌堆洗回牌库
---@param cardIds string[]
function Player:shuffleFromGraveyardToDeck(cardIds)
    for _, cardId in ipairs(cardIds) do
        if self:removeFromGraveyard(cardId) then
            self.deck[#self.deck + 1] = cardId
        end
    end
    self:shuffleDeck()
end

-- ============================================================================
-- 震慑 (Intimidate) 暂存
-- ============================================================================

--- 震慑：从手牌随机放逐 N 张（面朝下，回合结束归还）
---@param amount number
---@return string[] intimidatedIds
function Player:intimidate(amount)
    local removed = {}
    for _ = 1, amount do
        if #self.hand == 0 then break end
        local idx = math.random(1, #self.hand)
        local cardId = table.remove(self.hand, idx)
        self.intimidatedCards[#self.intimidatedCards + 1] = cardId
        removed[#removed + 1] = cardId
    end
    return removed
end

--- 回合结束：归还被震慑的牌到手牌
function Player:returnIntimidatedCards()
    for _, cardId in ipairs(self.intimidatedCards) do
        self.hand[#self.hand + 1] = cardId
    end
    self.intimidatedCards = {}
end

-- ============================================================================
-- 体力 (Life)
-- ============================================================================

--- 受到伤害
---@param amount number
---@return number actualDamage 实际扣除的体力
function Player:takeDamage(amount)
    if amount <= 0 then return 0 end
    local actual = math.min(amount, self.life)
    self.life = self.life - actual
    self.turnStats.totalDamageDealt = self.turnStats.totalDamageDealt + actual
    return actual
end

--- 回复体力
---@param amount number
---@return number actualHealed
function Player:gainLife(amount)
    if amount <= 0 then return 0 end
    local actual = math.min(amount, self.maxLife - self.life)
    self.life = self.life + actual
    return actual
end

--- 是否被击败
---@return boolean
function Player:isDefeated()
    return self.life <= 0
end

--- 体力百分比
---@return number 0.0~1.0
function Player:lifePercent()
    if self.maxLife <= 0 then return 0 end
    return self.life / self.maxLife
end

-- ============================================================================
-- 行动点
-- ============================================================================

--- 获得行动点
---@param amount number
function Player:gainActionPoint(amount)
    self.actionPoints = self.actionPoints + (amount or 1)
end

--- 消耗行动点
---@return boolean success
function Player:spendActionPoint()
    if self.actionPoints <= 0 then return false end
    self.actionPoints = self.actionPoints - 1
    return true
end

--- 是否有行动点
---@return boolean
function Player:hasActionPoint()
    return self.actionPoints > 0
end

-- ============================================================================
-- 护具系统
-- ============================================================================

--- 获取指定槽位的护具
---@param slot string SLOT.UPPER / SLOT.LOWER
---@return table|nil equipState
function Player:getEquipment(slot)
    local eq = self.equipment[slot]
    if eq and not eq.destroyed then return eq end
    return nil
end

--- 获取所有未损毁的护具
---@return table[] { slot, state }
function Player:getActiveEquipment()
    local result = {}
    for slot, eq in pairs(self.equipment) do
        if eq and not eq.destroyed then
            result[#result + 1] = { slot = slot, state = eq }
        end
    end
    return result
end

--- 使用护具防御
---@param slot string
---@return number defenseProvided
function Player:useEquipmentDefense(slot)
    local eq = self:getEquipment(slot)
    if not eq then return 0 end
    if eq.defense <= 0 then return 0 end

    local def = eq.defense
    eq.usedThisTurn = true

    -- 根据关键词处理
    local keywords = eq.data.keywords or {}
    local hasBattleworn = false
    local hasBladeBreak = false
    local hasTemper = false

    for _, kw in ipairs(keywords) do
        if kw == KW.BATTLEWORN then hasBattleworn = true end
        if kw == KW.BLADE_BREAK then hasBladeBreak = true end
        if kw == KW.TEMPER then hasTemper = true end
    end

    -- 磨损 (Battleworn): 放 -1 防御计数器，永不销毁
    if hasBattleworn then
        eq.defense = math.max(0, eq.defense - 1)
    end

    -- 耐久 (Temper): 放 -1 防御计数器，归 0 时销毁
    if hasTemper then
        eq.defense = math.max(0, eq.defense - 1)
        if eq.defense <= 0 then
            eq.destroyed = true
        end
    end

    -- 脆弱 (Blade Break): 标记为待销毁（连招链关闭时处理）
    if hasBladeBreak then
        eq.pendingDestroy = true
    end

    return def
end

--- 连招链关闭时处理脆弱护具销毁
---@return table[] destroyedSlots
function Player:resolveBladeBreak()
    local destroyed = {}
    for slot, eq in pairs(self.equipment) do
        if eq and not eq.destroyed and eq.pendingDestroy then
            eq.destroyed = true
            eq.pendingDestroy = false
            destroyed[#destroyed + 1] = { slot = slot, data = eq.data }
        end
    end
    return destroyed
end

--- 销毁指定槽位护具
---@param slot string
---@return table|nil destroyedData
function Player:destroyEquipment(slot)
    local eq = self.equipment[slot]
    if eq and not eq.destroyed then
        eq.destroyed = true
        return eq.data
    end
    return nil
end

--- 获取护具总防御值
---@return number
function Player:getTotalEquipmentDefense()
    local total = 0
    for _, eq in pairs(self.equipment) do
        if eq and not eq.destroyed then
            total = total + eq.defense
        end
    end
    return total
end

-- ============================================================================
-- 架势（武器）系统
-- ============================================================================

--- 获取可用的架势列表
---@return table[]
function Player:getAvailableWeapons()
    local result = {}
    for i, w in ipairs(self.weapons) do
        if not w.usedThisTurn then
            result[#result + 1] = { index = i, state = w }
        end
    end
    return result
end

--- 使用架势攻击
---@param weaponIndex number
---@return table|nil weaponData
function Player:useWeapon(weaponIndex)
    local w = self.weapons[weaponIndex]
    if not w or w.usedThisTurn then return nil end
    w.usedThisTurn = true
    return w.data
end

--- 记录架势命中
---@param weaponIndex number
function Player:recordWeaponHit(weaponIndex)
    local w = self.weapons[weaponIndex]
    if w then
        w.hitCounters = w.hitCounters + 1
        self.turnStats.weaponHits = self.turnStats.weaponHits + 1
    end
end

--- 重置架势使用状态（回合结束）
function Player:resetWeapons()
    for _, w in ipairs(self.weapons) do
        w.usedThisTurn = false
        -- 正眼之构: 本回合未命中则清除所有命中计数器
        -- (由 customHandler 处理)
    end
end

-- ============================================================================
-- 场上留场牌 (Aura / Item)
-- ============================================================================

--- 放置留场牌到竞技场
---@param cardId string
function Player:placeArenaCard(cardId)
    self.arenaCards[#self.arenaCards + 1] = {
        id = cardId,
        data = CardDB.get(cardId),
        counters = {},
    }
end

--- 从竞技场移除留场牌
---@param cardId string
---@return boolean
function Player:removeArenaCard(cardId)
    for i = 1, #self.arenaCards do
        if self.arenaCards[i].id == cardId then
            table.remove(self.arenaCards, i)
            return true
        end
    end
    return false
end

--- 获取场上所有留场牌
---@return table[]
function Player:getArenaCards()
    return self.arenaCards
end

--- 销毁留场牌（进弃牌堆）
---@param cardId string
---@return boolean
function Player:destroyArenaCard(cardId)
    if self:removeArenaCard(cardId) then
        self:addToGraveyard(cardId)
        return true
    end
    return false
end

-- ============================================================================
-- 出牌
-- ============================================================================

--- 从手牌打出（移除手牌，不进弃牌堆——由连招链管理归宿）
---@param cardId string
---@return table|nil cardData
function Player:playFromHand(cardId)
    if self:removeFromHand(cardId) then
        return CardDB.get(cardId)
    end
    return nil
end

--- 记录打出攻击牌
---@param cardName string
function Player:recordAttackPlayed(cardName)
    self.turnStats.attacksPlayed = self.turnStats.attacksPlayed + 1
    self.turnStats.lastAttackName = cardName
end

-- ============================================================================
-- 回合生命周期
-- ============================================================================

--- 回合开始
function Player:beginTurn()
    self.turnStats = Player._newTurnStats()
    self.actionPoints = 1      -- 每回合获得 1 行动点
    self.resourcePool = 0      -- 体能重置
    self.tempIntellect = 0     -- 临时专注力重置
    self.heroAbilityUsed = false

    -- 重置护具
    for _, eq in pairs(self.equipment) do
        if eq and not eq.destroyed then
            eq.usedThisTurn = false
        end
    end

    -- 重置架势
    self:resetWeapons()
end

--- 回合结束
---@param arsenalCardId? string 可选：放入预备区的手牌 ID
---@param pitchOrder? string[] 可选：充能区放回牌库底的顺序
function Player:endTurn(arsenalCardId, pitchOrder)
    -- 1. 归还被震慑的牌
    self:returnIntimidatedCards()

    -- 2. 可将 1 张手牌放入预备区
    if arsenalCardId then
        self:addToArsenal(arsenalCardId)
    end

    -- 3. 充能区牌放回牌库底
    self:returnPitchZoneToDeck(pitchOrder)

    -- 4. 抽牌至专注力上限
    self:drawToIntellect()

    -- 5. 体能归零
    self.resourcePool = 0
end

-- ============================================================================
-- 搜索查询
-- ============================================================================

--- 在牌库中搜索符合条件的卡牌
---@param filter fun(card:table):boolean
---@param limit? number 最多找几张
---@return string[] matchedIds
function Player:searchDeck(filter, limit)
    limit = limit or 1
    local result = {}
    for _, cardId in ipairs(self.deck) do
        local card = CardDB.get(cardId)
        if card and filter(card) then
            result[#result + 1] = cardId
            if #result >= limit then break end
        end
    end
    return result
end

--- 在弃牌堆中搜索符合条件的卡牌
---@param filter fun(card:table):boolean
---@param limit? number
---@return string[] matchedIds
function Player:searchGraveyard(filter, limit)
    limit = limit or 1
    local result = {}
    for _, cardId in ipairs(self.graveyard) do
        local card = CardDB.get(cardId)
        if card and filter(card) then
            result[#result + 1] = cardId
            if #result >= limit then break end
        end
    end
    return result
end

-- ============================================================================
-- 牌组构建辅助
-- ============================================================================

--- 根据英雄和策略生成默认牌组（40 张 Blitz 牌组）
---@param heroKey string
---@return string[] deckCardIds
function Player.buildDefaultDeck(heroKey)
    local hero = HeroData.getHero(heroKey)
    if not hero then return {} end

    local pool = CardDB.getPoolForClass(hero.class)
    local deck = {}

    -- 简单策略：收集所有可用牌（排除 Token）
    for _, card in ipairs(pool) do
        if card.rarity ~= CardData.RARITY.TOKEN then
            deck[#deck + 1] = card.id
        end
    end

    -- 截断到 40 张
    while #deck > 40 do
        table.remove(deck, #deck)
    end

    -- 不足 40 张则重复填充
    local base = #deck
    while #deck < 40 and base > 0 do
        for i = 1, base do
            if #deck >= 40 then break end
            deck[#deck + 1] = deck[i]
        end
    end

    return deck
end

--- 获取英雄推荐的装备 ID 列表（各槽位 1 件）
---@param heroKey string
---@return string[]
function Player.getDefaultEquipment(heroKey)
    local hero = HeroData.getHero(heroKey)
    if not hero then return {} end

    local available = HeroData.getEquipmentForClass(hero.class)
    local picked = {}
    local slotFilled = {}

    -- 优先选本职高稀有度
    for _, eq in ipairs(available) do
        if eq.class == hero.class and not slotFilled[eq.slot] then
            picked[#picked + 1] = eq.id
            slotFilled[eq.slot] = true
        end
    end

    -- 补齐空槽位
    for _, eq in ipairs(available) do
        if not slotFilled[eq.slot] then
            picked[#picked + 1] = eq.id
            slotFilled[eq.slot] = true
        end
    end

    return picked
end

-- ============================================================================
-- 调试信息
-- ============================================================================

--- 返回状态摘要字符串
---@return string
function Player:debugSummary()
    local eqStr = ""
    for slot, eq in pairs(self.equipment) do
        if eq and not eq.destroyed then
            eqStr = eqStr .. string.format("  %s: %s (def=%d/%d)\n",
                slot, eq.data.name, eq.defense, eq.maxDefense)
        end
    end

    return string.format(
        "[%s] %s (%s)\n" ..
        "  体力: %d/%d | 行动点: %d | 体能: %d\n" ..
        "  手牌: %d | 牌库: %d | 弃牌堆: %d | 放逐区: %d\n" ..
        "  预备区: %d | 充能区: %d | 留场牌: %d\n" ..
        "  护具:\n%s",
        self.heroKey, self.heroName, self.class,
        self.life, self.maxLife, self.actionPoints, self.resourcePool,
        #self.hand, #self.deck, #self.graveyard, #self.banishZone,
        #self.arsenal, #self.pitchZone, #self.arenaCards,
        eqStr ~= "" and eqStr or "  (无)\n"
    )
end

return Player

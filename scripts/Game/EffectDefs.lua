-- ============================================================================
-- Game/EffectDefs.lua - 原子效果词条注册表
-- 每个词条 = 一个最小可执行效果
-- 词条带参数，由 EffectProcessor 按 id 查找并执行
-- ============================================================================

local CardDB = require("Card.CardDB")
local CardData = require("Card.CardData")
local KW = CardData.KEYWORD

local EffectDefs = {}

--- 注册表：id → handler(ctx, params)
--- ctx = { attacker, defender, chain, link, card, fsm, source }
EffectDefs.registry = {}

--- 注册一个效果词条
---@param id string
---@param handler fun(ctx:table, params:table):boolean, string|nil
function EffectDefs.register(id, handler)
    EffectDefs.registry[id] = handler
end

--- 获取处理器
---@param id string
---@return fun|nil
function EffectDefs.get(id)
    return EffectDefs.registry[id]
end

-- ============================================================================
-- 2.1 增益类 (Buff)
-- ============================================================================

EffectDefs.register("buff_power", function(ctx, params)
    local amount = params.amount or 0
    local target = params.target or "this"

    if target == "this" and ctx.chain and ctx.chain.current then
        ctx.chain:buffCurrentPower(amount, ctx.card and ctx.card.name or "effect")
    elseif target == "next_weapon" then
        -- 标记 buff：下次架势攻击 +N
        ctx.attacker._pendingBuffs = ctx.attacker._pendingBuffs or {}
        ctx.attacker._pendingBuffs[#ctx.attacker._pendingBuffs + 1] = {
            type = "weapon_power", amount = amount, used = false,
        }
    elseif target == "next_attack" then
        ctx.attacker._pendingBuffs = ctx.attacker._pendingBuffs or {}
        ctx.attacker._pendingBuffs[#ctx.attacker._pendingBuffs + 1] = {
            type = "attack_power", amount = amount, used = false,
        }
    elseif target == "weapon_attack" and ctx.chain and ctx.chain.current then
        -- 仅对架势攻击生效
        if ctx.chain.current.isWeaponAttack then
            ctx.chain:buffCurrentPower(amount, ctx.card and ctx.card.name or "effect")
        end
    end
    return true
end)

EffectDefs.register("buff_power_until_eot", function(ctx, params)
    local amount = params.amount or 0
    local target = params.target or "all_attacks_this_turn"

    ctx.attacker._eotBuffs = ctx.attacker._eotBuffs or {}
    ctx.attacker._eotBuffs[#ctx.attacker._eotBuffs + 1] = {
        target = target, amount = amount,
    }
    return true
end)

EffectDefs.register("buff_defense", function(ctx, params)
    -- 防御 buff 通常应用于闪避牌
    local amount = params.amount or 0
    if ctx.chain and ctx.chain.current then
        ctx.chain.current.totalDefense = ctx.chain.current.totalDefense + amount
    end
    return true
end)

EffectDefs.register("grant_go_again", function(ctx, params)
    local target = params.target or "this"
    if target == "this" or target == "self" or target == "self_ability" then
        if ctx.chain and ctx.chain.current then
            ctx.chain:grantGoAgain()
        else
            -- 非连招链中（辅助牌自带 Go Again）
            ctx.attacker:gainActionPoint(1)
        end
    elseif target == "next_attack" then
        ctx.attacker._pendingBuffs = ctx.attacker._pendingBuffs or {}
        ctx.attacker._pendingBuffs[#ctx.attacker._pendingBuffs + 1] = {
            type = "go_again", used = false,
        }
    end
    return true
end)

EffectDefs.register("grant_dominate", function(ctx, params)
    if ctx.chain and ctx.chain.current then
        ctx.chain:grantDominate()
    end
    return true
end)

EffectDefs.register("grant_keyword", function(ctx, params)
    -- 动态关键词附加，暂存到链接
    local keyword = params.keyword
    if ctx.chain and ctx.chain.current and keyword then
        ctx.chain.current["has_" .. keyword] = true
    end
    return true
end)

EffectDefs.register("reduce_cost", function(ctx, params)
    ctx.attacker._pendingBuffs = ctx.attacker._pendingBuffs or {}
    ctx.attacker._pendingBuffs[#ctx.attacker._pendingBuffs + 1] = {
        type = "reduce_cost",
        target = params.target or "next_attack",
        amount = params.amount or 1,
        used = false,
    }
    return true
end)

-- ============================================================================
-- 2.2 抽牌/弃牌/牌库操作
-- ============================================================================

EffectDefs.register("draw", function(ctx, params)
    local amount = params.amount or 1
    local drawn = ctx.attacker:drawCards(amount)
    if ctx.fsm then
        ctx.fsm:addLog(string.format("%s 抽了 %d 张牌", ctx.attacker.heroName, #drawn))
    end
    return true
end)

EffectDefs.register("discard_random", function(ctx, params)
    local amount = params.amount or 1
    local target = params.target or "opponent"
    local player = target == "opponent" and ctx.defender or ctx.attacker
    local discarded = player:discardRandom(amount)
    if ctx.fsm then
        ctx.fsm:addLog(string.format("%s 随机弃了 %d 张牌", player.heroName, #discarded))
    end
    return true
end)

EffectDefs.register("discard_chosen", function(ctx, params)
    -- 需要 UI 交互，先做简化处理：随机弃牌
    local amount = params.amount or 1
    local discarded = ctx.defender:discardRandom(amount)
    if ctx.fsm then
        ctx.fsm:addLog(string.format("%s 弃了 %d 张牌", ctx.defender.heroName, #discarded))
    end
    return true
end)

EffectDefs.register("search_deck", function(ctx, params)
    local filter = params.filter or "any"
    local dest = params.destination or "hand"

    local filterFn = function(card) return true end
    if filter == "combo" then
        filterFn = function(card) return card.comboFrom ~= nil end
    elseif filter == "attack_reaction" or filter == "chase" then
        filterFn = function(card) return card.cardType == CardData.TYPE.CHASE end
    elseif filter == "class_attack" then
        filterFn = function(card)
            return card:isAttack() and card.class == ctx.attacker.class
        end
    elseif filter == "defense_gte_3" then
        filterFn = function(card) return card.defense >= 3 end
    end

    local found = ctx.attacker:searchDeck(filterFn, 1)
    if #found > 0 then
        local cardId = found[1]
        -- 从牌库移除
        for i = 1, #ctx.attacker.deck do
            if ctx.attacker.deck[i] == cardId then
                table.remove(ctx.attacker.deck, i)
                break
            end
        end
        if dest == "hand" then
            ctx.attacker.hand[#ctx.attacker.hand + 1] = cardId
        elseif dest == "deck_top" then
            ctx.attacker:putToDeckTop(cardId)
        end
        ctx.attacker:shuffleDeck()
    end
    return true
end)

EffectDefs.register("shuffle_deck", function(ctx, params)
    ctx.attacker:shuffleDeck()
    return true
end)

EffectDefs.register("put_hand_to_deck_bottom", function(ctx, params)
    -- 简化：放最后 N 张
    local amount = params.amount or 1
    for _ = 1, amount do
        if #ctx.attacker.hand > 0 then
            local cardId = table.remove(ctx.attacker.hand, #ctx.attacker.hand)
            ctx.attacker:putToDeckBottom(cardId)
        end
    end
    return true
end)

EffectDefs.register("put_arsenal_to_deck_bottom", function(ctx, params)
    local amount = params.amount or 1
    for _ = 1, amount do
        ctx.defender:arsenalToDeckBottom()
    end
    return true
end)

EffectDefs.register("shuffle_from_graveyard", function(ctx, params)
    local amount = params.amount or 1
    local filter = params.filter or "any"

    local filterFn = function(card) return true end
    if filter == "defense_gte_3" then
        filterFn = function(card) return card.defense >= 3 end
    end

    local found = ctx.attacker:searchGraveyard(filterFn, amount)
    if #found > 0 then
        ctx.attacker:shuffleFromGraveyardToDeck(found)
    end
    return true
end)

EffectDefs.register("banish_from_hand", function(ctx, params)
    local amount = params.amount or 1
    ctx.defender:intimidate(amount)
    return true
end)

EffectDefs.register("banish_deck_top", function(ctx, params)
    local amount = params.amount or 1
    for _ = 1, amount do
        if #ctx.attacker.deck > 0 then
            local cardId = table.remove(ctx.attacker.deck, 1)
            ctx.attacker:addToBanish(cardId)
        end
    end
    return true
end)

-- ============================================================================
-- 2.3 伤害/回复
-- ============================================================================

EffectDefs.register("deal_damage", function(ctx, params)
    local amount = params.amount or 0
    local target = params.target or "opponent"
    local player = target == "opponent" and ctx.defender or ctx.attacker
    player:takeDamage(amount)
    if ctx.fsm then
        ctx.fsm:addLog(string.format("%s 受到 %d 点效果伤害", player.heroName, amount))
    end
    return true
end)

EffectDefs.register("deal_damage_double", function(ctx, params)
    if ctx.chain and ctx.chain.current then
        local link = ctx.chain.current
        link.attackPower = link.attackPower * 2
    end
    return true
end)

EffectDefs.register("gain_life", function(ctx, params)
    local amount = params.amount or 0
    local healed = ctx.attacker:gainLife(amount)
    if ctx.fsm then
        ctx.fsm:addLog(string.format("%s 回复 %d 体力", ctx.attacker.heroName, healed))
    end
    return true
end)

EffectDefs.register("prevent_damage", function(ctx, params)
    local amount = params.amount or 0
    ctx.defender._damageShield = (ctx.defender._damageShield or 0) + amount
    return true
end)

-- ============================================================================
-- 2.4 护具/装备操作
-- ============================================================================

EffectDefs.register("destroy_self", function(ctx, params)
    -- 销毁来源卡牌（护具/留场牌）
    if ctx.sourceSlot then
        ctx.attacker:destroyEquipment(ctx.sourceSlot)
    elseif ctx.sourceArenaId then
        ctx.attacker:destroyArenaCard(ctx.sourceArenaId)
    end
    return true
end)

EffectDefs.register("add_defense_counter", function(ctx, params)
    local target = params.target or "opp_equipment"
    local amount = params.amount or -1
    local player = (target == "opp_equipment") and ctx.defender or ctx.attacker

    -- 对第一个可用护具操作
    for _, eq in pairs(player.equipment) do
        if eq and not eq.destroyed then
            eq.defense = math.max(0, eq.defense + amount)
            if eq.defense <= 0 and eq.data and eq.data.keywords then
                for _, kw in ipairs(eq.data.keywords) do
                    if kw == KW.TEMPER then
                        eq.destroyed = true
                        break
                    end
                end
            end
            break
        end
    end
    return true
end)

EffectDefs.register("add_energy_counter", function(ctx, params)
    local amount = params.amount or 1
    if ctx.sourceEquip then
        ctx.sourceEquip.counters = ctx.sourceEquip.counters or {}
        ctx.sourceEquip.counters.energy = (ctx.sourceEquip.counters.energy or 0) + amount
    end
    return true
end)

EffectDefs.register("remove_energy_counter", function(ctx, params)
    local amount = params.amount or 1
    if ctx.sourceEquip and ctx.sourceEquip.counters then
        local cur = ctx.sourceEquip.counters.energy or 0
        if cur >= amount then
            ctx.sourceEquip.counters.energy = cur - amount
            return true
        end
        return false, "not_enough_counters"
    end
    return false
end)

-- ============================================================================
-- 2.5 资源/行动点
-- ============================================================================

EffectDefs.register("gain_resource", function(ctx, params)
    local amount = params.amount or 1
    ctx.attacker.resourcePool = ctx.attacker.resourcePool + amount
    return true
end)

EffectDefs.register("gain_action_point", function(ctx, params)
    local amount = params.amount or 1
    ctx.attacker:gainActionPoint(amount)
    return true
end)

EffectDefs.register("gain_intellect", function(ctx, params)
    local amount = params.amount or 1
    ctx.attacker.tempIntellect = ctx.attacker.tempIntellect + amount
    return true
end)

-- ============================================================================
-- 2.8 附加费用
-- ============================================================================

EffectDefs.register("additional_cost_discard_random", function(ctx, params)
    local amount = params.amount or 1
    local discarded = ctx.attacker:discardRandom(amount)
    -- 记录弃掉的牌（用于后续条件判定：如弃牌攻击力 ≥ 6）
    ctx._discardedCards = ctx._discardedCards or {}
    for _, id in ipairs(discarded) do
        ctx._discardedCards[#ctx._discardedCards + 1] = id
    end
    if ctx.fsm then
        ctx.fsm:addLog(string.format("%s 弃牌 %d 张(附加费用)", ctx.attacker.heroName, #discarded))
    end
    return true
end)

EffectDefs.register("additional_cost_put_hand_to_bottom", function(ctx, params)
    local amount = params.amount or 1
    for _ = 1, amount do
        if #ctx.attacker.hand > 0 then
            local cardId = table.remove(ctx.attacker.hand, #ctx.attacker.hand)
            ctx.attacker:putToDeckBottom(cardId)
        end
    end
    return true
end)

EffectDefs.register("additional_cost_pay_resource", function(ctx, params)
    local amount = params.amount or 1
    return ctx.attacker:spendResource(amount)
end)

-- ============================================================================
-- 2.9 骰子
-- ============================================================================

EffectDefs.register("roll_d6", function(ctx, params)
    local roll = math.random(1, 6)
    local formula = params.effect_formula or "gain_resource_half"

    if ctx.fsm then
        ctx.fsm:addLog(string.format("%s 掷骰：%d", ctx.attacker.heroName, roll))
    end

    if formula == "gain_resource_half" then
        local gain = math.floor(roll / 2)
        ctx.attacker.resourcePool = ctx.attacker.resourcePool + gain
    elseif formula == "gain_action_half" then
        local gain = math.floor(roll / 2)
        ctx.attacker:gainActionPoint(gain)
    elseif formula == "prevent_damage_full" then
        ctx.attacker._damageShield = (ctx.attacker._damageShield or 0) + roll
    end

    return true
end)

-- ============================================================================
-- 2.10 时机/标记
-- ============================================================================

EffectDefs.register("return_to_hand_on_hit", function(ctx, params)
    -- 标记此牌命中后回到手牌而非弃牌堆
    if ctx.chain and ctx.chain.current then
        ctx.chain.current._returnToHand = true
    end
    return true
end)

EffectDefs.register("to_deck_bottom_instead_of_graveyard", function(ctx, params)
    -- 此标记在 CombatChain.close() 中已处理
    -- 这里仅作为词条占位
    return true
end)

return EffectDefs

-- ============================================================================
-- Game/EffectProcessor.lua - 效果处理器
-- 卡牌效果的统一执行引擎：
--   1. 按优先级处理效果词条（附加费用 → 关键词 → 主效果 → 条件触发 → Go Again）
--   2. 评估条件包装器（on_hit, crush_check, combo_check 等）
--   3. customHandler 回退到 CustomHandlers
--   4. 管理待定增益（pending buffs）和回合结束清理
-- ============================================================================

local CardData = require("Card.CardData")
local CardDB   = require("Card.CardDB")
local EffectDefs = require("Game.EffectDefs")

local KW   = CardData.KEYWORD
local TYPE = CardData.TYPE

local EffectProcessor = {}

-- ============================================================================
-- 上下文构建
-- ============================================================================

--- 构建效果执行上下文
---@param opts table { attacker, defender, chain, card, cardId, fsm, source?, sourceSlot?, sourceEquip?, sourceArenaId? }
---@return table ctx
function EffectProcessor.buildContext(opts)
    return {
        attacker      = opts.attacker,
        defender      = opts.defender,
        chain         = opts.chain,
        link          = opts.chain and opts.chain.current or nil,
        card          = opts.card,
        cardId        = opts.cardId,
        fsm           = opts.fsm,
        source        = opts.source or "card",        -- "card" | "weapon" | "equipment" | "hero"
        sourceSlot    = opts.sourceSlot,               -- 护具槽位（护具能力时）
        sourceEquip   = opts.sourceEquip,              -- 护具状态对象
        sourceArenaId = opts.sourceArenaId,             -- 留场牌 ID

        -- 运行时状态（效果执行中填充）
        _discardedCards   = {},   -- 附加费用弃掉的牌（用于 if_discarded_power_gte）
        _deferredOnHit    = {},   -- 延迟到命中时执行的效果
        _deferredCrush    = {},   -- 延迟到重击判定时执行的效果
        _chooseOneResult  = nil,  -- choose_one 选择结果
    }
end

-- ============================================================================
-- 主入口：处理卡牌效果
-- ============================================================================

--- 处理一张牌的全部效果
--- 按优先级顺序：附加费用 → 关键词自动效果 → 主效果 → Go Again
---@param ctx table 效果上下文
---@return boolean ok
---@return string|nil error
function EffectProcessor.processCard(ctx)
    local card = ctx.card
    if not card then return true end

    -- 1. 检查是否有 customHandler（有则完全交给专用处理器）
    if card.customHandler then
        return EffectProcessor._processCustom(ctx, card.customHandler)
    end

    local effects = card.effects
    if not effects or #effects == 0 then
        -- 无效果词条（白板牌），仅处理关键词
        EffectProcessor._processKeywords(ctx, card)
        return true
    end

    -- 2. 分类效果词条
    local additionalCosts = {}   -- 附加费用
    local mainEffects     = {}   -- 主效果（含立即执行的条件效果）
    local deferredEffects = {}   -- 延迟效果（on_hit, crush_check 等战斗结算后触发）

    for _, tag in ipairs(effects) do
        local id = tag.id or tag[1]   -- 兼容两种格式
        if id and EffectProcessor._isAdditionalCost(id) then
            additionalCosts[#additionalCosts + 1] = tag
        elseif id and EffectProcessor._isDeferredCondition(id) then
            deferredEffects[#deferredEffects + 1] = tag
        else
            mainEffects[#mainEffects + 1] = tag
        end
    end

    -- 3. 执行附加费用（必须先支付）
    for _, tag in ipairs(additionalCosts) do
        local ok, err = EffectProcessor.executeTag(tag, ctx)
        if not ok then return false, err end
    end

    -- 4. 关键词自动效果（intimidate 等）
    EffectProcessor._processKeywords(ctx, card)

    -- 5. 执行主效果（按文本顺序）
    for _, tag in ipairs(mainEffects) do
        EffectProcessor.executeTag(tag, ctx)
    end

    -- 6. 注册延迟效果（等待战斗结算后触发）
    for _, tag in ipairs(deferredEffects) do
        EffectProcessor._registerDeferred(tag, ctx)
    end

    -- 7. Go Again 在结算阶段由 GameFSM/CombatChain 处理（不在此处）

    return true
end

-- ============================================================================
-- 单词条执行
-- ============================================================================

--- 执行单个效果词条
---@param tag table { id, [params...] } 或条件包装格式
---@param ctx table 效果上下文
---@return boolean ok
---@return string|nil error
function EffectProcessor.executeTag(tag, ctx)
    local id = tag.id
    if not id then return true end

    -- 条件包装器：先评估条件，满足后执行子效果
    if tag.condition then
        local condMet = EffectProcessor.evaluateCondition(
            tag.condition.id or tag.condition, ctx, tag.condition.params or tag.condition)
        if condMet and tag.then_effects then
            for _, subTag in ipairs(tag.then_effects) do
                EffectProcessor.executeTag(subTag, ctx)
            end
        end
        return true
    end

    -- 条件 ID 直接作为词条 ID（如 on_hit, crush_check 包装的效果）
    if EffectProcessor._isConditionWrapper(id) then
        return EffectProcessor._handleConditionWrapper(tag, ctx)
    end

    -- choose_one 特殊处理
    if id == "choose_one" then
        return EffectProcessor._handleChooseOne(tag, ctx)
    end

    -- 查找处理器
    local handler = EffectDefs.get(id)
    if not handler then
        -- 未知词条，记录警告但不中断
        if ctx.fsm then
            ctx.fsm:addLog(string.format("[WARN] 未知效果词条: %s", id))
        end
        return true
    end

    -- 构建参数（词条除 id 外的所有字段）
    local params = tag.params or tag
    return handler(ctx, params)
end

-- ============================================================================
-- 条件评估
-- ============================================================================

--- 评估条件是否满足
---@param condId string 条件 ID
---@param ctx table 效果上下文
---@param params table|nil 条件参数
---@return boolean met
function EffectProcessor.evaluateCondition(condId, ctx, params)
    params = params or {}

    -- on_hit：此攻击命中（伤害 > 0）
    if condId == "on_hit" then
        local link = ctx.link or (ctx.chain and ctx.chain.current)
        return link ~= nil and link.resolved and link.didHit

    -- crush_check：此攻击造成 ≥ N 伤害
    elseif condId == "crush_check" then
        local link = ctx.link or (ctx.chain and ctx.chain.current)
        local minDmg = params.min_damage or 4
        return link ~= nil and link.resolved and link.damageDealt >= minDmg

    -- on_defend_with_hand (Reprise)：防御方用手牌防御了
    elseif condId == "on_defend_with_hand" then
        return ctx.chain ~= nil and ctx.chain:defenderUsedHandCards()

    -- combo_check：上一次攻击为指定牌
    elseif condId == "combo_check" then
        local reqName = params.card_name
        return reqName ~= nil and ctx.chain ~= nil and ctx.chain:checkCombo(reqName)

    -- if_discarded_power_gte：弃掉的牌攻击力 ≥ N
    elseif condId == "if_discarded_power_gte" then
        local threshold = params.threshold or 6
        if ctx._discardedCards then
            for _, cardId in ipairs(ctx._discardedCards) do
                local card = CardDB.get(cardId)
                if card and card.power >= threshold then
                    return true
                end
            end
        end
        return false

    -- if_pitch_zone_has：充能区有符合条件的牌
    elseif condId == "if_pitch_zone_has" then
        local filter = params.filter or "any"
        local count  = params.count or 1
        local found  = 0
        for _, cardId in ipairs(ctx.attacker.pitchZone) do
            local card = CardDB.get(cardId)
            if card then
                if filter == "any" then
                    found = found + 1
                elseif filter == "cost_0" then
                    if card.cost == 0 then found = found + 1 end
                elseif filter == "cost_gte_3" then
                    if card.cost >= 3 then found = found + 1 end
                end
            end
        end
        return found >= count

    -- if_weapon_hit_this_turn：本回合架势攻击已命中
    elseif condId == "if_weapon_hit_this_turn" then
        return ctx.attacker.turnStats.weaponHits > 0

    -- if_second_weapon_hit：本回合架势第 2 次命中
    elseif condId == "if_second_weapon_hit" then
        return ctx.attacker.turnStats.weaponHits >= 2

    -- if_less_life：你的体力少于对手
    elseif condId == "if_less_life" then
        return ctx.attacker.life < ctx.defender.life

    -- if_from_arsenal：此牌从预备区打出
    elseif condId == "if_from_arsenal" then
        return ctx.source == "arsenal"

    -- if_defended_by_fewer_than：对手用少于 N 张非护具牌防御
    elseif condId == "if_defended_by_fewer_than" then
        local count = params.count or 2
        if ctx.chain then
            return ctx.chain:getDefenseHandCount() < count
        end
        return false

    -- if_chain_link_gte：此牌是连招链第 N 个或更高
    elseif condId == "if_chain_link_gte" then
        local count = params.count or 2
        if ctx.chain then
            return ctx.chain:currentLinkIndex() >= count
        end
        return false

    -- once_per_turn：每回合限一次
    elseif condId == "once_per_turn" then
        local key = "once_" .. (ctx.cardId or "unknown")
        if ctx.attacker.turnStats[key] then
            return false
        end
        ctx.attacker.turnStats[key] = true
        return true

    else
        -- 未知条件，默认不满足
        return false
    end
end

-- ============================================================================
-- 条件包装器处理
-- ============================================================================

--- 判断是否为条件包装器 ID
---@param id string
---@return boolean
function EffectProcessor._isConditionWrapper(id)
    local wrappers = {
        on_hit = true,
        crush_check = true,
        on_defend_with_hand = true,
        combo_check = true,
        if_discarded_power_gte = true,
        if_pitch_zone_has = true,
        if_weapon_hit_this_turn = true,
        if_second_weapon_hit = true,
        if_less_life = true,
        if_from_arsenal = true,
        if_defended_by_fewer_than = true,
        if_chain_link_gte = true,
        once_per_turn = true,
    }
    return wrappers[id] == true
end

--- 处理条件包装器词条
---@param tag table { id, params, then_effects }
---@param ctx table
---@return boolean
function EffectProcessor._handleConditionWrapper(tag, ctx)
    local condId = tag.id
    local params = tag.params or tag

    -- 对于延迟条件（on_hit, crush_check），注册而不立即评估
    if EffectProcessor._isDeferredCondition(condId) then
        EffectProcessor._registerDeferred(tag, ctx)
        return true
    end

    -- 立即条件：评估后执行子效果
    local met = EffectProcessor.evaluateCondition(condId, ctx, params)
    if met and tag.then_effects then
        for _, subTag in ipairs(tag.then_effects) do
            EffectProcessor.executeTag(subTag, ctx)
        end
    end
    return true
end

-- ============================================================================
-- 延迟效果（战斗结算后触发）
-- ============================================================================

--- 判断是否为需要延迟到结算后的条件
---@param id string
---@return boolean
function EffectProcessor._isDeferredCondition(id)
    return id == "on_hit" or id == "crush_check"
end

--- 注册延迟效果
---@param tag table
---@param ctx table
function EffectProcessor._registerDeferred(tag, ctx)
    local condId = tag.id
    if condId == "on_hit" then
        ctx._deferredOnHit[#ctx._deferredOnHit + 1] = tag
    elseif condId == "crush_check" then
        ctx._deferredCrush[#ctx._deferredCrush + 1] = tag
    end
end

--- 执行命中后触发的延迟效果
--- 在伤害结算完成后由 GameFSM 调用
---@param ctx table 原始效果上下文
---@param damage number 实际伤害
---@param didHit boolean 是否命中
function EffectProcessor.processPostCombat(ctx, damage, didHit)
    -- on_hit 效果
    if didHit then
        for _, tag in ipairs(ctx._deferredOnHit) do
            if tag.then_effects then
                for _, subTag in ipairs(tag.then_effects) do
                    EffectProcessor.executeTag(subTag, ctx)
                end
            end
        end
    end

    -- crush_check 效果
    for _, tag in ipairs(ctx._deferredCrush) do
        local minDmg = (tag.params and tag.params.min_damage) or 4
        if damage >= minDmg then
            if tag.then_effects then
                for _, subTag in ipairs(tag.then_effects) do
                    EffectProcessor.executeTag(subTag, ctx)
                end
            end
        end
    end

    -- return_to_hand_on_hit 标记处理
    if didHit and ctx.link and ctx.link._returnToHand then
        -- 攻击牌命中后回手牌（由 CombatChain.close 跳过弃牌）
        ctx.link._returnToHandCardId = ctx.cardId
    end
end

-- ============================================================================
-- 附加费用识别
-- ============================================================================

--- 判断是否为附加费用词条
---@param id string
---@return boolean
function EffectProcessor._isAdditionalCost(id)
    return id == "additional_cost_discard_random"
        or id == "additional_cost_put_hand_to_bottom"
        or id == "additional_cost_pay_resource"
end

-- ============================================================================
-- 关键词自动效果
-- ============================================================================

--- 处理卡牌关键词的自动效果
---@param ctx table
---@param card table CardData
function EffectProcessor._processKeywords(ctx, card)
    if not card.keywords then return end

    for _, kw in ipairs(card.keywords) do
        -- 震慑：随机放逐对手 1 张手牌
        if kw == KW.INTIMIDATE then
            if ctx.defender then
                ctx.defender:intimidate(1)
                if ctx.fsm then
                    ctx.fsm:addLog(string.format(
                        "震慑！%s 1 张手牌被放逐", ctx.defender.heroName))
                end
            end

        -- Go Again：标记到连招链或直接给行动点
        elseif kw == KW.GO_AGAIN then
            if ctx.chain and ctx.chain.current then
                ctx.chain:grantGoAgain()
            else
                ctx.attacker:gainActionPoint(1)
            end

        -- 必杀：标记到连招链
        elseif kw == KW.DOMINATE then
            if ctx.chain and ctx.chain.current then
                ctx.chain:grantDominate()
            end

        -- 重击/反击/连击：这些是条件关键词，由效果词条中的
        -- crush_check / on_defend_with_hand / combo_check 处理
        -- 此处不做自动处理
        end
    end
end

-- ============================================================================
-- 待定增益（Pending Buffs）
-- ============================================================================

--- 在攻击声明时应用待定增益
--- 由 GameFSM 在 _openCombatChain 后调用
---@param player table Player（攻击方）
---@param chain table CombatChain
---@param link table ChainLink
---@param card table|nil CardData（攻击牌，架势为 nil）
function EffectProcessor.applyPendingBuffs(player, chain, link, card)
    local buffs = player._pendingBuffs
    if not buffs then return end

    local remaining = {}

    for _, buff in ipairs(buffs) do
        if buff.used then
            -- 已使用的跳过
        elseif buff.type == "attack_power" then
            -- 下次攻击 +N
            chain:buffCurrentPower(buff.amount, "pending_buff")
            buff.used = true

        elseif buff.type == "weapon_power" then
            -- 下次架势攻击 +N
            if link.isWeaponAttack then
                chain:buffCurrentPower(buff.amount, "pending_buff")
                buff.used = true
            else
                remaining[#remaining + 1] = buff
            end

        elseif buff.type == "go_again" then
            -- 下次攻击获得连招
            chain:grantGoAgain()
            buff.used = true

        elseif buff.type == "hero_bravo_dominate" then
            -- 云柔英雄能力：费用≥3的攻击牌获得必杀+连招
            if card and card.cost >= 3 then
                chain:grantDominate()
                chain:grantGoAgain()
                buff.used = true
            else
                remaining[#remaining + 1] = buff
            end

        elseif buff.type == "reduce_cost" then
            -- 费用减少（在支付前已处理，此处清理）
            -- 费用减少需要在 pitchAndPay 前查询
            remaining[#remaining + 1] = buff

        else
            remaining[#remaining + 1] = buff
        end
    end

    player._pendingBuffs = remaining
end

--- 查询并消耗费用减少 buff
--- 在 PitchSystem.pitchAndPay 前调用
---@param player table Player
---@param target string "next_attack" | "next_weapon"
---@return number reduction 费用减少总量
function EffectProcessor.consumeCostReduction(player, target)
    local buffs = player._pendingBuffs
    if not buffs then return 0 end

    local total = 0
    for _, buff in ipairs(buffs) do
        if not buff.used and buff.type == "reduce_cost" then
            if buff.target == target or buff.target == "any" then
                total = total + buff.amount
                buff.used = true
            end
        end
    end
    return total
end

--- 应用回合结束持续增益到攻击
--- 在每次攻击声明时检查
---@param player table Player
---@param chain table CombatChain
---@param link table ChainLink
---@param card table|nil CardData
function EffectProcessor.applyEOTBuffs(player, chain, link, card)
    local eotBuffs = player._eotBuffs
    if not eotBuffs then return end

    for _, buff in ipairs(eotBuffs) do
        local target = buff.target or "all_attacks_this_turn"

        if target == "all_attacks_this_turn" then
            chain:buffCurrentPower(buff.amount, "eot_buff")

        elseif target == "all_class_attacks" then
            -- 仅对本流派攻击牌生效
            if card and card.class == player.class then
                chain:buffCurrentPower(buff.amount, "eot_buff")
            end

        elseif target == "attacks_with_crush" then
            -- 仅对带重击的攻击生效
            if card and card:hasKeyword(KW.CRUSH) then
                chain:buffCurrentPower(buff.amount, "eot_buff")
            end
        end
    end
end

-- ============================================================================
-- 回合结束清理
-- ============================================================================

--- 清理回合结束的临时效果
--- 在 GameFSM._finishTurn 中调用
---@param player table Player
function EffectProcessor.cleanupEndOfTurn(player)
    -- 清理 EOT buffs
    player._eotBuffs = nil

    -- 清理已使用的 pending buffs
    if player._pendingBuffs then
        local remaining = {}
        for _, buff in ipairs(player._pendingBuffs) do
            if not buff.used then
                remaining[#remaining + 1] = buff
            end
        end
        if #remaining > 0 then
            player._pendingBuffs = remaining
        else
            player._pendingBuffs = nil
        end
    end

    -- 清理伤害护盾
    player._damageShield = nil

    -- 清理 once_per_turn 标记
    if player.turnStats then
        local toRemove = {}
        for key, _ in pairs(player.turnStats) do
            if type(key) == "string" and key:sub(1, 5) == "once_" then
                toRemove[#toRemove + 1] = key
            end
        end
        for _, key in ipairs(toRemove) do
            player.turnStats[key] = nil
        end
    end
end

-- ============================================================================
-- choose_one 处理
-- ============================================================================

--- 处理 choose_one 组合词条
--- 简化版：AI 随机选择 / 玩家暂用第一个选项
---@param tag table { id="choose_one", options={...} }
---@param ctx table
---@return boolean
function EffectProcessor._handleChooseOne(tag, ctx)
    local options = tag.options or tag.then_effects
    if not options or #options == 0 then return true end

    -- TODO: 接入 UI 选择交互
    -- 当前简化：选择第一个选项（AI 会有自己的选择逻辑）
    local chosen = ctx._chooseOneResult or 1
    chosen = math.max(1, math.min(chosen, #options))

    local option = options[chosen]
    if option then
        -- 选项可能是 { effects = {...} } 或直接是效果列表
        local effects = option.effects or { option }
        for _, subTag in ipairs(effects) do
            EffectProcessor.executeTag(subTag, ctx)
        end
    end

    return true
end

-- ============================================================================
-- Custom Handler 处理
-- ============================================================================

--- CustomHandlers 延迟加载引用
---@type table|nil
local CustomHandlers = nil

--- 处理 customHandler 卡牌
---@param ctx table
---@param handlerId string
---@return boolean ok
---@return string|nil error
function EffectProcessor._processCustom(ctx, handlerId)
    -- 延迟加载 CustomHandlers 避免循环依赖
    if not CustomHandlers then
        local ok, mod = pcall(require, "Game.CustomHandlers")
        if ok then
            CustomHandlers = mod
        else
            if ctx.fsm then
                ctx.fsm:addLog(string.format("[WARN] CustomHandlers 加载失败: %s", tostring(mod)))
            end
            return true -- 不中断游戏
        end
    end

    local handler = CustomHandlers.get(handlerId)
    if handler then
        return handler(ctx)
    else
        if ctx.fsm then
            ctx.fsm:addLog(string.format("[WARN] 未找到 custom handler: %s", handlerId))
        end
        return true
    end
end

-- ============================================================================
-- 伤害护盾处理
-- ============================================================================

--- 应用伤害护盾（prevent_damage 效果）
--- 在实际扣血前由 CombatChain 或 GameFSM 调用
---@param player table Player（受伤方）
---@param rawDamage number 原始伤害
---@return number actualDamage 经过护盾后的实际伤害
function EffectProcessor.applyDamageShield(player, rawDamage)
    local shield = player._damageShield or 0
    if shield <= 0 then return rawDamage end

    local blocked = math.min(shield, rawDamage)
    player._damageShield = shield - blocked
    return rawDamage - blocked
end

-- ============================================================================
-- 辅助牌效果快捷方法
-- ============================================================================

--- 处理辅助牌效果（非连招链内）
---@param attacker table Player
---@param defender table Player
---@param card table CardData
---@param cardId string
---@param fsm table GameFSM
---@return boolean ok
function EffectProcessor.processSupportCard(attacker, defender, card, cardId, fsm)
    local ctx = EffectProcessor.buildContext({
        attacker = attacker,
        defender = defender,
        chain    = nil,
        card     = card,
        cardId   = cardId,
        fsm      = fsm,
        source   = "card",
    })
    return EffectProcessor.processCard(ctx)
end

--- 处理攻击牌声明时的效果（buff 类、附加费用等，非命中时效果）
---@param attacker table Player
---@param defender table Player
---@param chain table CombatChain
---@param card table|nil CardData
---@param cardId string
---@param fsm table GameFSM
---@return table ctx 返回上下文供后续 processPostCombat 使用
function EffectProcessor.processAttackCard(attacker, defender, chain, card, cardId, fsm)
    local ctx = EffectProcessor.buildContext({
        attacker = attacker,
        defender = defender,
        chain    = chain,
        card     = card,
        cardId   = cardId,
        fsm      = fsm,
        source   = "card",
    })

    -- 处理卡牌效果（附加费用、关键词、主效果、注册延迟效果）
    EffectProcessor.processCard(ctx)

    -- 应用待定增益
    if chain and chain.current then
        EffectProcessor.applyPendingBuffs(attacker, chain, chain.current, card)
        EffectProcessor.applyEOTBuffs(attacker, chain, chain.current, card)
    end

    return ctx
end

--- 处理追击牌效果
---@param attacker table Player
---@param defender table Player
---@param chain table CombatChain
---@param card table CardData
---@param cardId string
---@param fsm table GameFSM
---@return table ctx
function EffectProcessor.processChaseCard(attacker, defender, chain, card, cardId, fsm)
    local ctx = EffectProcessor.buildContext({
        attacker = attacker,
        defender = defender,
        chain    = chain,
        card     = card,
        cardId   = cardId,
        fsm      = fsm,
        source   = "card",
    })

    EffectProcessor.processCard(ctx)
    return ctx
end

--- 处理闪避牌效果
---@param defender table Player
---@param attacker table Player
---@param chain table CombatChain
---@param card table CardData
---@param cardId string
---@param fsm table GameFSM
---@return table ctx
function EffectProcessor.processDodgeCard(defender, attacker, chain, card, cardId, fsm)
    -- 注意：闪避牌的 "attacker" 是防御方（效果施放者）
    local ctx = EffectProcessor.buildContext({
        attacker = defender,
        defender = attacker,
        chain    = chain,
        card     = card,
        cardId   = cardId,
        fsm      = fsm,
        source   = "card",
    })

    EffectProcessor.processCard(ctx)
    return ctx
end

--- 处理护具主动能力
---@param player table Player
---@param opponent table Player
---@param slot string 护具槽位
---@param chain table|nil CombatChain
---@param fsm table GameFSM
---@return boolean ok
function EffectProcessor.processEquipmentAbility(player, opponent, slot, chain, fsm)
    local equip = player:getEquipment(slot)
    if not equip or equip.destroyed then return false end

    local abilityEffects = equip.data and equip.data.effects
    if not abilityEffects then return false end

    local ctx = EffectProcessor.buildContext({
        attacker    = player,
        defender    = opponent,
        chain       = chain,
        card        = equip.data,
        cardId      = equip.data.id,
        fsm         = fsm,
        source      = "equipment",
        sourceSlot  = slot,
        sourceEquip = equip,
    })

    return EffectProcessor.processCard(ctx)
end

return EffectProcessor

-- ============================================================================
-- Game/CustomHandlers.lua - 自定义效果处理器
-- 处理约 20% 无法用纯词条组合表达的卡牌效果：
--   - 4 个英雄能力
--   - 4 种架势特殊效果
--   - 5 个 Crush 持续效果（跨回合状态标记）
--   - 特殊行动牌
-- ============================================================================

local CardData = require("Card.CardData")
local CardDB   = require("Card.CardDB")

local KW = CardData.KEYWORD

local CustomHandlers = {}

--- 处理器注册表：handlerId → function(ctx) → boolean, string|nil
CustomHandlers.registry = {}

--- 注册处理器
---@param id string
---@param handler fun(ctx:table):boolean, string|nil
function CustomHandlers.register(id, handler)
    CustomHandlers.registry[id] = handler
end

--- 获取处理器
---@param id string
---@return fun|nil
function CustomHandlers.get(id)
    return CustomHandlers.registry[id]
end

-- ============================================================================
-- 跨回合状态标记系统
-- 保存在 Player._statusMarks 表中，在对手回合开始时检查
-- ============================================================================

--- 给对手挂载下回合状态标记
---@param player table 被标记的玩家
---@param markId string 标记 ID
---@param data table|nil 附加数据
local function applyMark(player, markId, data)
    player._statusMarks = player._statusMarks or {}
    player._statusMarks[markId] = data or true
end

--- 检查玩家是否有某个状态标记
---@param player table
---@param markId string
---@return any|nil
function CustomHandlers.hasMark(player, markId)
    if not player._statusMarks then return nil end
    return player._statusMarks[markId]
end

--- 消耗/清除一个状态标记
---@param player table
---@param markId string
function CustomHandlers.removeMark(player, markId)
    if player._statusMarks then
        player._statusMarks[markId] = nil
    end
end

--- 清理所有回合开始自动过期的标记
--- 在 GameFSM.beginTurn 中对当前玩家调用
---@param player table
function CustomHandlers.cleanupMarksOnTurnStart(player)
    if not player._statusMarks then return end

    -- 所有 "next_turn_*" 标记在此回合开始时仍然有效
    -- 它们在此回合结束时清除
end

--- 清理所有回合结束自动过期的标记
--- 在 GameFSM._finishTurn 中对当前玩家调用
---@param player table
function CustomHandlers.cleanupMarksOnTurnEnd(player)
    if not player._statusMarks then return end

    -- 清理本回合已过期的标记（上个回合的对手 Crush 施加的）
    local toRemove = {}
    for markId, _ in pairs(player._statusMarks) do
        -- "next_turn_*" 前缀的标记在持有者的回合结束时过期
        if markId:sub(1, 10) == "next_turn_" then
            toRemove[#toRemove + 1] = markId
        end
    end
    for _, id in ipairs(toRemove) do
        player._statusMarks[id] = nil
    end
end

-- ============================================================================
-- 状态标记的运行时影响钩子
-- 由 GameFSM / ActionValidator / CombatChain 在相应时机调用
-- ============================================================================

--- 检查玩家是否被压制 Go Again
---@param player table
---@return boolean suppressed
function CustomHandlers.isGoAgainSuppressed(player)
    return CustomHandlers.hasMark(player, "next_turn_suppress_go_again") ~= nil
end

--- 检查玩家是否被压制抽牌
---@param player table
---@return boolean suppressed
function CustomHandlers.isDrawSuppressed(player)
    return CustomHandlers.hasMark(player, "next_turn_suppress_draw") ~= nil
end

--- 检查玩家英雄能力是否被压制
---@param player table
---@return boolean suppressed
function CustomHandlers.isHeroAbilitySuppressed(player)
    return CustomHandlers.hasMark(player, "next_turn_suppress_hero") ~= nil
end

--- 获取首个行动的额外费用
---@param player table
---@return number extraCost
function CustomHandlers.getFirstActionExtraCost(player)
    local mark = CustomHandlers.hasMark(player, "next_turn_extra_cost_first")
    if mark then
        return type(mark) == "table" and mark.amount or 1
    end
    return 0
end

--- 获取首次攻击的攻击力修正
---@param player table
---@return number debuff（负数）
function CustomHandlers.getFirstAttackDebuff(player)
    local mark = CustomHandlers.hasMark(player, "next_turn_debuff_first_attack")
    if mark then
        return type(mark) == "table" and mark.amount or -2
    end
    return 0
end

--- 消耗"首个行动"类一次性标记
--- 在第一个行动执行后调用
---@param player table
function CustomHandlers.consumeFirstActionMarks(player)
    CustomHandlers.removeMark(player, "next_turn_extra_cost_first")
    CustomHandlers.removeMark(player, "next_turn_debuff_first_attack")
end

-- ============================================================================
-- 英雄能力处理器
-- ============================================================================

--- 一之濑枫 (Dorinthea / Warrior)
--- 能力：每回合一次，架势攻击命中后，可以额外再攻击一次（不消耗行动点）
CustomHandlers.register("hero_dorinthea", function(ctx)
    local player = ctx.attacker

    -- 检查条件：本回合未使用、架势已命中
    if player.heroAbilityUsed then
        return false, "hero_ability_used"
    end

    if player.turnStats.weaponHits < 1 then
        return false, "no_weapon_hit"
    end

    player.heroAbilityUsed = true

    -- 效果：获得额外行动点（用于再次攻击）
    player:gainActionPoint(1)

    if ctx.fsm then
        ctx.fsm:addLog(string.format(
            "%s 发动英雄能力：连击之刃！获得额外行动点", player.heroName))
    end

    return true
end)

--- 夏琳 (Katsu / Ninja)
--- 能力：每回合一次，攻击牌命中后，弃掉 1 张费用 0 的牌，
--- 从牌库搜索 1 张 Combo 牌到手牌
CustomHandlers.register("hero_katsu", function(ctx)
    local player = ctx.attacker

    if player.heroAbilityUsed then
        return false, "hero_ability_used"
    end

    -- 检查条件：本回合有攻击命中
    if player.turnStats.totalDamageDealt < 1 then
        return false, "no_hit_this_turn"
    end

    -- 检查手牌中是否有 0 费牌
    local zeroCostId = nil
    for _, cardId in ipairs(player.hand) do
        local card = CardDB.get(cardId)
        if card and card.cost == 0 then
            zeroCostId = cardId
            break
        end
    end

    if not zeroCostId then
        return false, "no_zero_cost_card"
    end

    player.heroAbilityUsed = true

    -- 弃掉 0 费牌
    player:removeFromHand(zeroCostId)
    player:addToGraveyard(zeroCostId)

    -- 搜索 Combo 牌
    local filterFn = function(card)
        return card.comboFrom ~= nil
    end
    local found = player:searchDeck(filterFn, 1)
    if #found > 0 then
        local comboCardId = found[1]
        -- 从牌库移除
        for i = 1, #player.deck do
            if player.deck[i] == comboCardId then
                table.remove(player.deck, i)
                break
            end
        end
        player.hand[#player.hand + 1] = comboCardId
        player:shuffleDeck()

        local comboCard = CardDB.get(comboCardId)
        if ctx.fsm then
            ctx.fsm:addLog(string.format(
                "%s 发动英雄能力：灵蛇之眼！搜索到 %s",
                player.heroName, comboCard and comboCard.name or comboCardId))
        end
    else
        player:shuffleDeck()
        if ctx.fsm then
            ctx.fsm:addLog(string.format(
                "%s 发动英雄能力：灵蛇之眼！牌库中没有连击牌", player.heroName))
        end
    end

    return true
end)

--- 云柔 (Bravo / Guardian)
--- 能力：每回合一次，支付 {2} 让下一个费用 ≥ 3 攻击牌获得必杀 + 连招
CustomHandlers.register("hero_bravo", function(ctx)
    local player = ctx.attacker

    if player.heroAbilityUsed then
        return false, "hero_ability_used"
    end

    -- 检查资源
    if player.resourcePool < 2 then
        return false, "not_enough_resource"
    end

    player.heroAbilityUsed = true
    player:spendResource(2)

    -- 挂载 pending buff：下一个费用 ≥ 3 攻击牌获得 dominate + go again
    player._pendingBuffs = player._pendingBuffs or {}
    player._pendingBuffs[#player._pendingBuffs + 1] = {
        type = "hero_bravo_dominate",
        used = false,
    }

    if ctx.fsm then
        ctx.fsm:addLog(string.format(
            "%s 发动英雄能力：气沉丹田！下次重击获得必杀+连招", player.heroName))
    end

    return true
end)

--- 铁拳小桃 (Rhinar / Brute)
--- 能力（被动）：行动阶段弃掉攻击力 ≥ 6 的牌时，触发震慑
--- 此 handler 由 EffectProcessor 在弃牌后自动检查触发
CustomHandlers.register("hero_rhinar", function(ctx)
    -- 铁拳小桃的能力是被动触发，不是主动使用
    -- 检查 ctx._discardedCards 中是否有攻击力 ≥ 6 的牌
    local player = ctx.attacker
    local triggered = false

    if ctx._discardedCards then
        for _, cardId in ipairs(ctx._discardedCards) do
            local card = CardDB.get(cardId)
            if card and card.power >= 6 then
                triggered = true
                break
            end
        end
    end

    if triggered and ctx.defender then
        ctx.defender:intimidate(1)
        if ctx.fsm then
            ctx.fsm:addLog(string.format(
                "%s 被动触发：野兽怒吼！%s 1 张手牌被放逐",
                player.heroName, ctx.defender.heroName))
        end
    end

    return true
end)

-- ============================================================================
-- 架势（武器）特殊效果处理器
-- 在架势攻击声明后由 EffectProcessor 调用
-- ============================================================================

--- 正眼之构 (Dawnblade / Warrior)
--- 第 2 次命中放 +1 计数器；回合未命中移除所有计数器
--- onHit 部分由 GameFSM 在结算后检查
CustomHandlers.register("weapon_dawnblade", function(ctx)
    -- 攻击声明时的效果：命中计数器作为攻击力 buff
    local player = ctx.attacker
    local weaponState = player.weapons and player.weapons[1]
    if not weaponState then return true end

    -- 命中计数器已在 CombatChain.declareAttack 中通过 hitCounters 加入基础攻击力
    return true
end)

--- 正眼之构 命中后处理
CustomHandlers.register("weapon_dawnblade_on_hit", function(ctx)
    local player = ctx.attacker
    local weaponIndex = ctx.link and ctx.link.weaponIndex

    if not weaponIndex then return true end
    local weaponState = player.weapons[weaponIndex]
    if not weaponState then return true end

    -- 第 2 次命中放 +1 计数器
    if player.turnStats.weaponHits >= 2 then
        weaponState.hitCounters = (weaponState.hitCounters or 0) + 1
        if ctx.fsm then
            ctx.fsm:addLog(string.format(
                "正眼之构：命中！获得 +1 计数器 (当前 %d)",
                weaponState.hitCounters))
        end
    end
    return true
end)

--- 正眼之构 回合结束处理
CustomHandlers.register("weapon_dawnblade_end_turn", function(ctx)
    local player = ctx.attacker
    local weaponState = player.weapons and player.weapons[1]
    if not weaponState then return true end

    -- 回合未命中架势 → 移除所有计数器
    if player.turnStats.weaponHits == 0 and (weaponState.hitCounters or 0) > 0 then
        if ctx.fsm then
            ctx.fsm:addLog(string.format(
                "正眼之构：本回合未用架势命中，移除 %d 个计数器",
                weaponState.hitCounters))
        end
        weaponState.hitCounters = 0
    end
    return true
end)

--- 战斗站架 (Kodachi / Ninja)
--- 充能区有 0 费牌时获得连招
CustomHandlers.register("weapon_kodachi", function(ctx)
    local player = ctx.attacker

    -- 检查充能区是否有 0 费牌
    for _, cardId in ipairs(player.pitchZone) do
        local card = CardDB.get(cardId)
        if card and card.cost == 0 then
            -- 授予 Go Again
            if ctx.chain and ctx.chain.current then
                ctx.chain:grantGoAgain()
            end
            if ctx.fsm then
                ctx.fsm:addLog("战斗站架：充能区有 0 费牌，获得连招！")
            end
            break
        end
    end
    return true
end)

--- 太极起势 (Anothos / Guardian)
--- 充能区有 ≥ 2 张费用 ≥ 3 的牌时 +2 攻击力
CustomHandlers.register("weapon_anothos", function(ctx)
    local player = ctx.attacker
    local count = 0

    for _, cardId in ipairs(player.pitchZone) do
        local card = CardDB.get(cardId)
        if card and card.cost >= 3 then
            count = count + 1
        end
    end

    if count >= 2 and ctx.chain and ctx.chain.current then
        ctx.chain:buffCurrentPower(2, "太极起势")
        if ctx.fsm then
            ctx.fsm:addLog("太极起势：充能区有足够重牌，攻击力 +2！")
        end
    end
    return true
end)

--- 拳击架势 (Romping Club / Brute)
--- 作为附加费用弃掉攻击力 ≥ 6 的牌时 +1 攻击力
--- 此效果与铁拳小桃英雄能力联动
CustomHandlers.register("weapon_romping_club", function(ctx)
    -- 弃牌 buff 在弃牌后检查
    if ctx._discardedCards then
        for _, cardId in ipairs(ctx._discardedCards) do
            local card = CardDB.get(cardId)
            if card and card.power >= 6 then
                if ctx.chain and ctx.chain.current then
                    ctx.chain:buffCurrentPower(1, "拳击架势")
                    if ctx.fsm then
                        ctx.fsm:addLog("拳击架势：弃掉高攻牌，攻击力 +1！")
                    end
                end
                break
            end
        end
    end
    return true
end)

-- ============================================================================
-- Crush 持续效果（跨回合状态标记）
-- ============================================================================

--- 推山掌 Crush 效果：对手下回合所有行动/攻击不能获得连招
CustomHandlers.register("crush_spinal", function(ctx)
    if ctx.defender then
        applyMark(ctx.defender, "next_turn_suppress_go_again")
        if ctx.fsm then
            ctx.fsm:addLog(string.format(
                "推山掌·重击！%s 下回合不能获得连招", ctx.defender.heroName))
        end
    end
    return true
end)

--- 封脉掌 Crush 效果：对手下回合不能抽牌
CustomHandlers.register("crush_cranial", function(ctx)
    if ctx.defender then
        applyMark(ctx.defender, "next_turn_suppress_draw")
        if ctx.fsm then
            ctx.fsm:addLog(string.format(
                "封脉掌·重击！%s 下回合不能抽牌", ctx.defender.heroName))
        end
    end
    return true
end)

--- 採劲 Crush 效果：对手下回合第一个行动额外支付 {1}
CustomHandlers.register("crush_cartilage", function(ctx)
    if ctx.defender then
        applyMark(ctx.defender, "next_turn_extra_cost_first", { amount = 1 })
        if ctx.fsm then
            ctx.fsm:addLog(string.format(
                "採劲·重击！%s 下回合首个行动额外支付 1 体能", ctx.defender.heroName))
        end
    end
    return true
end)

--- 挒劲 Crush 效果：对手失去英雄能力到下回合结束
CustomHandlers.register("crush_confidence", function(ctx)
    if ctx.defender then
        applyMark(ctx.defender, "next_turn_suppress_hero")
        if ctx.fsm then
            ctx.fsm:addLog(string.format(
                "挒劲·重击！%s 下回合不能使用英雄能力", ctx.defender.heroName))
        end
    end
    return true
end)

--- 肘靠 Crush 效果：对手下回合第一次攻击 -2 攻击力
CustomHandlers.register("crush_debilitate", function(ctx)
    if ctx.defender then
        applyMark(ctx.defender, "next_turn_debuff_first_attack", { amount = -2 })
        if ctx.fsm then
            ctx.fsm:addLog(string.format(
                "肘靠·重击！%s 下回合首次攻击 -2 攻击力", ctx.defender.heroName))
        end
    end
    return true
end)

-- ============================================================================
-- 特殊行动牌处理器
-- ============================================================================

--- 残心追击 (Singing Steelblade / Warrior)
--- Reprise → 搜索牌库找追击牌到手牌
CustomHandlers.register("spec_singing_steelblade", function(ctx)
    -- 基础效果：追击牌 buff
    if ctx.chain and ctx.chain.current then
        local card = ctx.card
        if card and card.power > 0 then
            ctx.chain:buffCurrentPower(card.power, card.name)
        end
    end

    -- Reprise 条件：防御方用手牌防御了
    if ctx.chain and ctx.chain:defenderUsedHandCards() then
        -- 搜索牌库找追击牌
        local filterFn = function(c)
            return c.cardType == CardData.TYPE.CHASE
        end
        local found = ctx.attacker:searchDeck(filterFn, 1)
        if #found > 0 then
            local foundId = found[1]
            for i = 1, #ctx.attacker.deck do
                if ctx.attacker.deck[i] == foundId then
                    table.remove(ctx.attacker.deck, i)
                    break
                end
            end
            ctx.attacker.hand[#ctx.attacker.hand + 1] = foundId
            ctx.attacker:shuffleDeck()

            local foundCard = CardDB.get(foundId)
            if ctx.fsm then
                ctx.fsm:addLog(string.format(
                    "残心追击·反击！搜索到追击牌 %s",
                    foundCard and foundCard.name or foundId))
            end
        end
    end

    return true
end)

--- 无影·解放 (Mugenshi: RELEASE / Ninja)
--- Combo 条件 → 命中时搜索所有同名牌到手牌
CustomHandlers.register("spec_mugenshi_release", function(ctx)
    local card = ctx.card
    if not card then return true end

    -- 注册 on_hit 延迟效果
    ctx._deferredOnHit = ctx._deferredOnHit or {}
    ctx._deferredOnHit[#ctx._deferredOnHit + 1] = {
        id = "on_hit",
        _customOnHit = function()
            -- Combo 检查
            if ctx.chain and card.comboFrom and ctx.chain:checkCombo(card.comboFrom) then
                -- 搜索所有同名牌
                local baseName = card.name:gsub(" %- .+$", "")  -- 去掉颜色后缀
                local filterFn = function(c)
                    local cName = c.name:gsub(" %- .+$", "")
                    return cName == baseName
                end
                local found = ctx.attacker:searchDeck(filterFn, 10) -- 搜索全部
                for _, foundId in ipairs(found) do
                    for i = 1, #ctx.attacker.deck do
                        if ctx.attacker.deck[i] == foundId then
                            table.remove(ctx.attacker.deck, i)
                            break
                        end
                    end
                    ctx.attacker.hand[#ctx.attacker.hand + 1] = foundId
                end
                if #found > 0 then
                    ctx.attacker:shuffleDeck()
                    if ctx.fsm then
                        ctx.fsm:addLog(string.format(
                            "无影·解放！搜索到 %d 张同名牌", #found))
                    end
                end
            end
        end,
    }

    return true
end)

--- 疾风连环 (Lord of Wind / Ninja)
--- Combo → 附加费用 pay X，从弃牌堆洗回 X 张牌，+X 攻击力
CustomHandlers.register("spec_lord_of_wind", function(ctx)
    local card = ctx.card
    if not card then return true end

    -- Combo 检查
    if card.comboFrom and ctx.chain and ctx.chain:checkCombo(card.comboFrom) then
        -- 简化：pay 2，洗回 2 张，+2 攻击力
        local payAmount = 2
        if ctx.attacker.resourcePool >= payAmount then
            ctx.attacker:spendResource(payAmount)

            -- 从弃牌堆洗回
            local filterFn = function(c) return true end
            local found = ctx.attacker:searchGraveyard(filterFn, payAmount)
            if #found > 0 then
                ctx.attacker:shuffleFromGraveyardToDeck(found)
            end

            -- 攻击力 buff
            if ctx.chain and ctx.chain.current then
                ctx.chain:buffCurrentPower(payAmount, "疾风连环")
            end

            if ctx.fsm then
                ctx.fsm:addLog(string.format(
                    "疾风连环·连击！支付 %d 体能，洗回 %d 张牌，攻击力 +%d",
                    payAmount, #found, payAmount))
            end
        end
    end

    return true
end)

--- 不屈斗志 (Drone of Brutality / Generic)
--- 进弃牌堆时改为放牌库底（替代规则）
--- 此效果已在 CombatChain.close() 中通过 effects 字段检查实现
--- 这个 handler 仅作为标记注册
CustomHandlers.register("gen_drone_of_brutality", function(ctx)
    -- 标记效果已在 CombatChain.close() 中硬编码处理
    -- 此处无需额外操作
    return true
end)

--- 必杀·暴风 (Pounding Gale / Ninja)
--- Combo 条件满足时伤害翻倍
CustomHandlers.register("nin_pounding_gale", function(ctx)
    local card = ctx.card
    if not card then return true end

    -- Combo 检查
    if card.comboFrom and ctx.chain and ctx.chain:checkCombo(card.comboFrom) then
        -- 注册 on_hit 前的翻倍效果（在结算前应用）
        if ctx.chain and ctx.chain.current then
            -- 翻倍 = 当前攻击力再加一次
            local link = ctx.chain.current
            local bonus = link.attackPower
            ctx.chain:buffCurrentPower(bonus, "必杀·暴风")
            if ctx.fsm then
                ctx.fsm:addLog(string.format(
                    "必杀·暴风·连击！攻击力翻倍 → %d", link.attackPower))
            end
        end
    end

    return true
end)

-- ============================================================================
-- 装备技能处理器
-- 对应 HeroData.equipment 中带 customHandler 的装备
-- ============================================================================

--- 桜風·改良水手服 (eq_braveforge_bracers / Warrior)
--- 每回合一次 [行动] {1}：若架势本回合已命中，下次架势攻击 +1 攻击力，获得连招
CustomHandlers.register("eq_braveforge_bracers", function(ctx)
    local player = ctx.attacker

    -- 条件：架势本回合已命中
    if (player.turnStats.weaponHits or 0) < 1 then
        return false, "no_weapon_hit"
    end

    -- 挂载 pending buff：下次架势攻击 +1 攻击力 + 连招
    player._pendingBuffs = player._pendingBuffs or {}
    player._pendingBuffs[#player._pendingBuffs + 1] = {
        type   = "eq_braveforge",
        used   = false,
    }

    if ctx.fsm then
        ctx.fsm:addLog(string.format(
            "%s 激活桜風改良水手服：下次架势攻击 +1{p} 并获得连招", player.heroName))
    end
    return true
end)

--- pending buff 消费：桜風改良水手服
CustomHandlers.register("apply_braveforge_buff", function(ctx)
    -- 武器攻击时触发
    if ctx.chain and ctx.chain.current then
        ctx.chain:buffCurrentPower(1, "桜風改良水手服")
        ctx.chain:grantGoAgain()
        if ctx.fsm then
            ctx.fsm:addLog("桜風改良水手服生效：架势 +1{p}，获得连招")
        end
        return true
    end
    return false
end)

--- 云裳·盘扣对襟衫 (eq_tectonic_plating / Guardian)
--- 每回合一次 [行动] {1}：创建「震波 (4)」令牌，获得连招
CustomHandlers.register("eq_tectonic_plating", function(ctx)
    local player = ctx.attacker

    -- 创建震波令牌（放入场上）
    player.arenaCards = player.arenaCards or {}
    local tokenCard = CardDB.get("token_seismic_surge")
    if tokenCard then
        player.arenaCards[#player.arenaCards + 1] = tokenCard
    end

    -- 给予连招（若在连招链中）
    if ctx.chain and ctx.chain.current then
        ctx.chain:grantGoAgain()
    else
        -- 不在连招链中：给一个行动点代替连招
        player:gainActionPoint(1)
    end

    if ctx.fsm then
        ctx.fsm:addLog(string.format(
            "%s 激活云裳盘扣对襟衫：创建震波令牌，获得连招", player.heroName))
    end
    return true
end)

--- DASH·露脐运动衫 (eq_mask_of_momentum / Ninja)
--- 连招链第 3 环节及以上命中时抽 1 张牌
--- 此效果为被动触发（由 GameFSM._afterLinkResolved 后检查）
--- handler 在护具技能激活时无直接操作，被动检测注册在 onHit 路径
CustomHandlers.register("eq_mask_of_momentum", function(ctx)
    -- 被动：主动激活时无效果（提示玩家这是被动护具）
    if ctx.fsm then
        ctx.fsm:addLog("DASH露脐运动衫：被动效果，连招链第3环及以上命中时自动抽牌")
    end
    return false, "equipment_no_ability"  -- 阻止消耗行动
end)

--- K.O.·铆钉皮背心 (eq_skullhorn / Brute)
--- [瞬发]：销毁本件护具，抽 1 张牌，然后随机弃 1 张牌
CustomHandlers.register("eq_skullhorn", function(ctx)
    local player = ctx.attacker
    local eq = ctx.sourceEquip

    -- 销毁护具
    if eq then eq.destroyed = true end

    -- 抽 1 张牌
    local drawn = player:drawCards(1)

    -- 随机弃 1 张牌（若手牌不为空）
    if #player.hand > 0 then
        local randIdx = math.random(1, #player.hand)
        local discardId = table.remove(player.hand, randIdx)
        player:addToGraveyard(discardId)
        local discardCard = CardDB.get(discardId)

        -- 触发铁拳小桃被动检查
        if player.heroData and player.heroData.customHandler == "hero_rhinar" then
            local rhinarCtx = {
                attacker = player,
                defender = ctx.defender,
                fsm      = ctx.fsm,
                _discardedCards = { discardId },
            }
            local rhinarHandler = CustomHandlers.get("hero_rhinar")
            if rhinarHandler then rhinarHandler(rhinarCtx) end
        end

        if ctx.fsm then
            ctx.fsm:addLog(string.format(
                "%s 激活铆钉皮背心：抽1牌，弃掉 %s",
                player.heroName, discardCard and discardCard.name or discardId))
        end
    else
        if ctx.fsm then
            ctx.fsm:addLog(string.format(
                "%s 激活铆钉皮背心：抽1牌（无牌可弃）", player.heroName))
        end
    end

    return true
end)

--- 春日碎花衬衫 (eq_fyendals_spring_tunic / Generic)
--- 回合开始放能量计数器（最多 3 个）
--- [瞬发]：移除 3 个能量计数器，获得 {1} 体能资源
CustomHandlers.register("eq_fyendals_spring_tunic", function(ctx)
    local player = ctx.attacker
    local eq = ctx.sourceEquip

    if not eq then return false, "no_equipment" end

    eq.counters = eq.counters or {}
    local energyCount = eq.counters.energy or 0

    if energyCount < 3 then
        return false, "insufficient_counters"
    end

    -- 移除 3 个能量计数器，获得 {1} 体能
    eq.counters.energy = energyCount - 3
    player:gainResource(1)

    if ctx.fsm then
        ctx.fsm:addLog(string.format(
            "%s 激活春日碎花衬衫：移除 3 个能量计数器，获得 {1} 体能",
            player.heroName))
    end
    return true
end)

--- 幸运兔耳帽衫 (eq_hope_merchants_hood / Generic)
--- [瞬发]：销毁本件护具，将任意张手牌洗回牌库，再抽等量手牌
CustomHandlers.register("eq_hope_merchants_hood", function(ctx)
    local player = ctx.attacker
    local eq = ctx.sourceEquip

    -- 销毁护具
    if eq then eq.destroyed = true end

    -- 将所有手牌洗回牌库（简化为全部，实际可做选择）
    local shuffledCount = #player.hand
    if shuffledCount > 0 then
        for _, cardId in ipairs(player.hand) do
            player.deck[#player.deck + 1] = cardId
        end
        player.hand = {}
        player:shuffleDeck()

        -- 再抽等量手牌
        player:drawCards(shuffledCount)
    end

    if ctx.fsm then
        ctx.fsm:addLog(string.format(
            "%s 激活幸运兔耳帽衫：将 %d 张手牌洗回牌库并重抽",
            player.heroName, shuffledCount))
    end
    return true
end)

--- K.O.·绑带运动内衣 (eq_barkbone_strapping / Brute)
--- [瞬发]：销毁本件护具，掷6面骰，获得 ⌊结果÷2⌋ 点体能资源
CustomHandlers.register("roll_gain_resource", function(ctx)
    local player = ctx.attacker
    local eq = ctx.sourceEquip

    -- 销毁护具
    if eq then eq.destroyed = true end

    -- 掷骰
    local roll = math.random(1, 6)
    local gained = math.floor(roll / 2)
    if gained > 0 then
        player:gainResource(gained)
    end

    if ctx.fsm then
        ctx.fsm:addLog(string.format(
            "%s 激活绑带运动内衣：掷骰 %d，获得 %d 点体能",
            player.heroName, roll, gained))
    end
    return true
end)

--- K.O.·破洞牛仔热裤 (eq_scabskin_leathers / Brute)
--- 每回合一次 [行动] {0}：掷6面骰，获得 ⌊结果÷2⌋ 个行动点
CustomHandlers.register("roll_gain_action", function(ctx)
    local player = ctx.attacker

    -- 掷骰
    local roll = math.random(1, 6)
    local gained = math.floor(roll / 2)
    if gained > 0 then
        player:gainActionPoint(gained)
    end

    if ctx.fsm then
        ctx.fsm:addLog(string.format(
            "%s 激活破洞牛仔热裤：掷骰 %d，获得 %d 个行动点",
            player.heroName, roll, gained))
    end
    return true
end)

-- ============================================================================
-- 春日碎花衬衫：回合开始放能量计数器
-- 由 GameFSM.beginTurn 调用
-- ============================================================================

--- 检查并放置春日碎花衬衫的能量计数器
---@param player table
function CustomHandlers.tickFyendalCounters(player)
    for _, eq in pairs(player.equipment) do
        if eq and not eq.destroyed and eq.data and eq.data.customHandler == "eq_fyendals_spring_tunic" then
            eq.counters = eq.counters or {}
            local current = eq.counters.energy or 0
            if current < 3 then
                eq.counters.energy = current + 1
            end
        end
    end
end

-- ============================================================================
-- DASH·露脐运动衫：连招链命中时被动检查
-- 由 GameFSM._afterLinkResolved 在命中后调用
-- ============================================================================

--- 检查 eq_mask_of_momentum 被动：连招链第 3 环节及以上命中时抽 1 张牌
---@param player table 防御方（命中时是 defender.attacker 角度则是被攻击方 → 此为携带护具的玩家）
---@param attacker table 攻击方
---@param linkNumber number 当前连招环节编号
---@param didHit boolean 是否命中
---@param fsm table GameFSM
function CustomHandlers.checkMaskOfMomentum(player, attacker, linkNumber, didHit, fsm)
    if not didHit then return end
    if linkNumber < 3 then return end

    -- 遍历两位玩家（attacker 携带此护具时检查）
    local function checkForPlayer(p)
        for _, eq in pairs(p.equipment) do
            if eq and not eq.destroyed and eq.data and eq.data.id == "eq_mask_of_momentum" then
                p:drawCards(1)
                if fsm then
                    fsm:addLog(string.format(
                        "DASH露脐运动衫：连招第 %d 环命中，%s 抽 1 张牌",
                        linkNumber, p.heroName))
                end
                return
            end
        end
    end
    checkForPlayer(attacker)
end

--- 云柔 英雄能力的 pending buff 消费处理
--- 由 EffectProcessor.applyPendingBuffs 的扩展逻辑调用
CustomHandlers.register("apply_bravo_dominate", function(ctx)
    -- 检查攻击牌费用 ≥ 3
    local card = ctx.card
    if card and card.cost >= 3 and ctx.chain and ctx.chain.current then
        ctx.chain:grantDominate()
        ctx.chain:grantGoAgain()
        if ctx.fsm then
            ctx.fsm:addLog("气沉丹田生效！此攻击获得必杀+连招")
        end
        return true
    end
    return false
end)

return CustomHandlers

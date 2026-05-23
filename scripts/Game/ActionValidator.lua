-- ============================================================================
-- Game/ActionValidator.lua - 出牌合法性验证
-- 集中管理所有出牌/行动的合法性校验逻辑
-- 供 GameFSM 和 UI 层共用：同一套规则判定"能不能做"
-- ============================================================================

local CardData   = require("Card.CardData")
local CardDB     = require("Card.CardDB")
local TurnPhase  = require("Game.TurnPhase")
local PitchSystem = require("Game.PitchSystem")

local TYPE = CardData.TYPE
local KW   = CardData.KEYWORD

local ActionValidator = {}

-- ============================================================================
-- 通用结果格式
-- ============================================================================

--- 构建验证结果
---@param ok boolean
---@param reason? string
---@return boolean, string|nil
local function result(ok, reason)
    return ok, reason
end

-- ============================================================================
-- 1. 攻击牌打出验证
-- ============================================================================

--- 检查能否从手牌打出攻击牌
---@param player table Player（攻击方）
---@param cardId string 要打出的牌 ID
---@param phase string 当前阶段
---@param chain table|nil CombatChain（nil=尚未开启）
---@return boolean ok
---@return string|nil reason
function ActionValidator.canPlayAttack(player, cardId, phase, chain)
    -- 阶段检查：必须在行动阶段或连招链的攻击子阶段
    if phase ~= TurnPhase.ACTION_PHASE and phase ~= TurnPhase.CHAIN_ATTACK then
        return result(false, "wrong_phase")
    end

    -- 行动点检查
    if not player:hasActionPoint() then
        return result(false, "no_action_point")
    end

    -- 手牌中存在该牌
    if not player:handContains(cardId) then
        return result(false, "not_in_hand")
    end

    -- 获取牌数据
    local card = CardDB.get(cardId)
    if not card then
        return result(false, "unknown_card")
    end

    -- 类型检查
    if not card:isAttack() then
        return result(false, "not_attack_card")
    end

    -- 费用检查（含手牌可充能的潜在资源）
    local canPay, deficit = PitchSystem.canPayFor(player, cardId)
    if not canPay then
        return result(false, "insufficient_resource")
    end

    -- Combo 条件检查
    if card.comboFrom then
        if chain and not chain:isEmpty() then
            if not chain:checkCombo(card.comboFrom) then
                return result(false, "combo_mismatch")
            end
        else
            -- 没有连招链（第一次攻击），Combo 牌需要 lastAttackName 匹配
            if player.turnStats.lastAttackName ~= card.comboFrom then
                return result(false, "combo_mismatch")
            end
        end
    end

    return result(true)
end

-- ============================================================================
-- 2. 从预备区打出验证
-- ============================================================================

--- 检查能否从预备区打出攻击牌
---@param player table
---@param phase string
---@param chain table|nil
---@return boolean, string|nil
function ActionValidator.canPlayFromArsenal(player, phase, chain)
    if phase ~= TurnPhase.ACTION_PHASE and phase ~= TurnPhase.CHAIN_ATTACK then
        return result(false, "wrong_phase")
    end

    if not player:hasActionPoint() then
        return result(false, "no_action_point")
    end

    if not player:hasArsenal() then
        return result(false, "arsenal_empty")
    end

    -- 预备区的牌也需要付费
    local arsenalCard = player:peekArsenal()
    if not arsenalCard then
        return result(false, "arsenal_empty")
    end

    -- 攻击牌/辅助牌才能打出（反应牌不能主动打出）
    if arsenalCard:isReaction() then
        return result(false, "reaction_cannot_main_play")
    end

    -- 费用检查：预备区的牌不在手中，所以可充能池=全部手牌
    if arsenalCard.cost > 0 then
        local available = player.resourcePool + PitchSystem.getPitchableTotal(player, nil)
        if available < arsenalCard.cost then
            return result(false, "insufficient_resource")
        end
    end

    return result(true)
end

-- ============================================================================
-- 3. 辅助牌打出验证
-- ============================================================================

--- 检查能否打出辅助牌
---@param player table
---@param cardId string
---@param phase string
---@return boolean, string|nil
function ActionValidator.canPlaySupport(player, cardId, phase)
    if phase ~= TurnPhase.ACTION_PHASE then
        return result(false, "wrong_phase")
    end

    if not player:hasActionPoint() then
        return result(false, "no_action_point")
    end

    if not player:handContains(cardId) then
        return result(false, "not_in_hand")
    end

    local card = CardDB.get(cardId)
    if not card then
        return result(false, "unknown_card")
    end

    if card.cardType ~= TYPE.SUPPORT then
        return result(false, "not_support_card")
    end

    local canPay = PitchSystem.canPayFor(player, cardId)
    if not canPay then
        return result(false, "insufficient_resource")
    end

    return result(true)
end

-- ============================================================================
-- 4. 留场牌（状态/道具）打出验证
-- ============================================================================

--- 检查能否打出留场牌
---@param player table
---@param cardId string
---@param phase string
---@return boolean, string|nil
function ActionValidator.canPlayArenaCard(player, cardId, phase)
    if phase ~= TurnPhase.ACTION_PHASE then
        return result(false, "wrong_phase")
    end

    if not player:hasActionPoint() then
        return result(false, "no_action_point")
    end

    if not player:handContains(cardId) then
        return result(false, "not_in_hand")
    end

    local card = CardDB.get(cardId)
    if not card then
        return result(false, "unknown_card")
    end

    if not card:isArenaCard() then
        return result(false, "not_arena_card")
    end

    local canPay = PitchSystem.canPayFor(player, cardId)
    if not canPay then
        return result(false, "insufficient_resource")
    end

    return result(true)
end

-- ============================================================================
-- 5. 架势（武器）攻击验证
-- ============================================================================

--- 检查能否使用架势攻击
---@param player table
---@param weaponIndex number
---@param phase string
---@return boolean, string|nil
function ActionValidator.canUseWeapon(player, weaponIndex, phase)
    if phase ~= TurnPhase.ACTION_PHASE and phase ~= TurnPhase.CHAIN_ATTACK then
        return result(false, "wrong_phase")
    end

    if not player:hasActionPoint() then
        return result(false, "no_action_point")
    end

    local weapon = player.weapons[weaponIndex]
    if not weapon then
        return result(false, "invalid_weapon")
    end

    if weapon.usedThisTurn then
        return result(false, "weapon_already_used")
    end

    -- 架势通常有费用条件
    local wData = weapon.data
    if wData.cost and wData.cost > 0 then
        local available = player.resourcePool + PitchSystem.getPitchableTotal(player, nil)
        if available < wData.cost then
            return result(false, "insufficient_resource")
        end
    end

    -- 特殊条件（由 HeroData 的 condition 字段定义）
    -- 具体条件由 GameFSM 的 customCondition 处理
    -- 这里仅做基础校验

    return result(true)
end

-- ============================================================================
-- 6. 防御声明验证
-- ============================================================================

--- 检查能否用手牌防御
---@param defender table Player
---@param cardId string
---@param chain table CombatChain
---@param phase string
---@return boolean, string|nil
function ActionValidator.canDefendWithCard(defender, cardId, chain, phase)
    if phase ~= TurnPhase.CHAIN_DEFEND then
        return result(false, "wrong_phase")
    end

    if not chain or not chain.current then
        return result(false, "no_active_attack")
    end

    if chain.current.resolved then
        return result(false, "already_resolved")
    end

    if not defender:handContains(cardId) then
        return result(false, "not_in_hand")
    end

    local card = CardDB.get(cardId)
    if not card then
        return result(false, "unknown_card")
    end

    if not card:canDefend() then
        return result(false, "no_defense_value")
    end

    -- 必杀限制：只允许 1 张手牌
    if chain.current.hasDominate then
        if #chain.current.defendCards >= 1 then
            return result(false, "dominate_limit")
        end
    end

    return result(true)
end

--- 检查能否用护具防御
---@param defender table Player
---@param slot string 护具槽位
---@param chain table CombatChain
---@param phase string
---@return boolean, string|nil
function ActionValidator.canDefendWithEquipment(defender, slot, chain, phase)
    if phase ~= TurnPhase.CHAIN_DEFEND then
        return result(false, "wrong_phase")
    end

    if not chain or not chain.current then
        return result(false, "no_active_attack")
    end

    if chain.current.resolved then
        return result(false, "already_resolved")
    end

    local eq = defender:getEquipment(slot)
    if not eq then
        return result(false, "no_equipment")
    end

    if eq.defense <= 0 then
        return result(false, "equipment_no_defense")
    end

    if eq.usedThisTurn then
        return result(false, "equipment_used")
    end

    return result(true)
end

-- ============================================================================
-- 7. 反应牌打出验证
-- ============================================================================

--- 检查攻击方能否打出追击牌
---@param attacker table Player
---@param cardId string
---@param chain table CombatChain
---@param phase string
---@return boolean, string|nil
function ActionValidator.canPlayChase(attacker, cardId, chain, phase)
    if phase ~= TurnPhase.CHAIN_REACTION then
        return result(false, "wrong_phase")
    end

    if not chain or not chain.current then
        return result(false, "no_active_attack")
    end

    if chain.current.resolved then
        return result(false, "already_resolved")
    end

    if not attacker:handContains(cardId) then
        return result(false, "not_in_hand")
    end

    local card = CardDB.get(cardId)
    if not card then
        return result(false, "unknown_card")
    end

    if card.cardType ~= TYPE.CHASE then
        return result(false, "not_chase_card")
    end

    -- 追击牌也有费用
    if card.cost > 0 then
        local canPay = PitchSystem.canPayFor(attacker, cardId)
        if not canPay then
            return result(false, "insufficient_resource")
        end
    end

    return result(true)
end

--- 检查防御方能否打出闪避牌
---@param defender table Player
---@param cardId string
---@param chain table CombatChain
---@param phase string
---@return boolean, string|nil
function ActionValidator.canPlayDodge(defender, cardId, chain, phase)
    if phase ~= TurnPhase.CHAIN_REACTION then
        return result(false, "wrong_phase")
    end

    if not chain or not chain.current then
        return result(false, "no_active_attack")
    end

    if chain.current.resolved then
        return result(false, "already_resolved")
    end

    if not defender:handContains(cardId) then
        return result(false, "not_in_hand")
    end

    local card = CardDB.get(cardId)
    if not card then
        return result(false, "unknown_card")
    end

    if card.cardType ~= TYPE.DODGE then
        return result(false, "not_dodge_card")
    end

    -- 闪避牌也有费用
    if card.cost > 0 then
        local canPay = PitchSystem.canPayFor(defender, cardId)
        if not canPay then
            return result(false, "insufficient_resource")
        end
    end

    return result(true)
end

-- ============================================================================
-- 8. 充能验证
-- ============================================================================

--- 检查能否充能指定手牌
---@param player table
---@param cardId string
---@return boolean, string|nil
function ActionValidator.canPitch(player, cardId)
    if not player:handContains(cardId) then
        return result(false, "not_in_hand")
    end

    local card = CardDB.get(cardId)
    if not card then
        return result(false, "unknown_card")
    end

    if card.pitch <= 0 then
        return result(false, "no_pitch_value")
    end

    return result(true)
end

-- ============================================================================
-- 9. 预备区存牌验证
-- ============================================================================

--- 检查能否将手牌放入预备区
---@param player table
---@param cardId string
---@param phase string
---@return boolean, string|nil
function ActionValidator.canPlaceToArsenal(player, cardId, phase)
    if phase ~= TurnPhase.END_PHASE then
        return result(false, "wrong_phase")
    end

    if #player.arsenal >= 1 then
        return result(false, "arsenal_full")
    end

    if not player:handContains(cardId) then
        return result(false, "not_in_hand")
    end

    return result(true)
end

-- ============================================================================
-- 10. 英雄能力验证
-- ============================================================================

--- 检查能否使用英雄能力
---@param player table
---@param phase string
---@return boolean, string|nil
function ActionValidator.canUseHeroAbility(player, phase)
    if phase ~= TurnPhase.ACTION_PHASE then
        return result(false, "wrong_phase")
    end

    if player.heroAbilityUsed then
        return result(false, "ability_already_used")
    end

    if not player:hasActionPoint() then
        return result(false, "no_action_point")
    end

    -- 英雄能力的特定条件由 GameFSM 的 hero handler 判断
    return result(true)
end

-- ============================================================================
-- 11. 综合：获取所有合法行动
-- ============================================================================

--- 枚举当前可执行的所有合法行动
---@param player table 当前行动玩家
---@param opponent table 对手
---@param phase string 当前阶段
---@param chain table|nil 当前连招链
---@return table actions { type, cardId?, weaponIndex?, slot? }
function ActionValidator.getAvailableActions(player, opponent, phase, chain)
    local actions = {}

    -- === 行动阶段 / 连招攻击子阶段 ===
    if phase == TurnPhase.ACTION_PHASE or phase == TurnPhase.CHAIN_ATTACK then

        -- 手牌攻击
        for _, id in ipairs(player.hand) do
            local ok = ActionValidator.canPlayAttack(player, id, phase, chain)
            if ok then
                actions[#actions + 1] = { type = "attack", cardId = id }
            end
        end

        -- 预备区打出
        if ActionValidator.canPlayFromArsenal(player, phase, chain) then
            actions[#actions + 1] = { type = "arsenal" }
        end

        -- 架势攻击
        for i, _ in ipairs(player.weapons) do
            local ok = ActionValidator.canUseWeapon(player, i, phase)
            if ok then
                actions[#actions + 1] = { type = "weapon", weaponIndex = i }
            end
        end

        -- 辅助牌（仅行动阶段）
        if phase == TurnPhase.ACTION_PHASE then
            for _, id in ipairs(player.hand) do
                local ok = ActionValidator.canPlaySupport(player, id, phase)
                if ok then
                    actions[#actions + 1] = { type = "support", cardId = id }
                end
            end

            -- 留场牌
            for _, id in ipairs(player.hand) do
                local ok = ActionValidator.canPlayArenaCard(player, id, phase)
                if ok then
                    actions[#actions + 1] = { type = "arena", cardId = id }
                end
            end

            -- 英雄能力
            if ActionValidator.canUseHeroAbility(player, phase) then
                actions[#actions + 1] = { type = "hero_ability" }
            end
        end

        -- 可以选择结束行动阶段
        actions[#actions + 1] = { type = "end_action" }
    end

    -- === 防御子阶段 ===
    if phase == TurnPhase.CHAIN_DEFEND then
        -- 手牌防御
        for _, id in ipairs(opponent.hand) do
            local ok = ActionValidator.canDefendWithCard(opponent, id, chain, phase)
            if ok then
                actions[#actions + 1] = { type = "defend_card", cardId = id }
            end
        end

        -- 护具防御
        for _, slot in ipairs({ CardData.SLOT.UPPER, CardData.SLOT.LOWER }) do
            local ok = ActionValidator.canDefendWithEquipment(opponent, slot, chain, phase)
            if ok then
                actions[#actions + 1] = { type = "defend_equip", slot = slot }
            end
        end

        -- 放弃防御
        actions[#actions + 1] = { type = "skip_defense" }
    end

    -- === 反应子阶段 ===
    if phase == TurnPhase.CHAIN_REACTION then
        -- 攻击方追击牌
        for _, id in ipairs(player.hand) do
            local ok = ActionValidator.canPlayChase(player, id, chain, phase)
            if ok then
                actions[#actions + 1] = { type = "chase", cardId = id }
            end
        end

        -- 防御方闪避牌
        for _, id in ipairs(opponent.hand) do
            local ok = ActionValidator.canPlayDodge(opponent, id, chain, phase)
            if ok then
                actions[#actions + 1] = { type = "dodge", cardId = id }
            end
        end

        -- 跳过反应
        actions[#actions + 1] = { type = "skip_reaction" }
    end

    -- === 结束阶段 ===
    if phase == TurnPhase.END_PHASE then
        -- 预备区存牌
        for _, id in ipairs(player.hand) do
            local ok = ActionValidator.canPlaceToArsenal(player, id, phase)
            if ok then
                actions[#actions + 1] = { type = "to_arsenal", cardId = id }
            end
        end

        -- 跳过（不存牌）
        actions[#actions + 1] = { type = "end_turn" }
    end

    return actions
end

-- ============================================================================
-- 12. 错误信息映射（UI 显示用）
-- ============================================================================

ActionValidator.ERROR_MESSAGES = {
    wrong_phase          = "当前阶段不能执行此操作",
    no_action_point      = "没有行动点",
    not_in_hand          = "手牌中没有这张牌",
    unknown_card         = "未知卡牌",
    not_attack_card      = "不是攻击牌",
    not_support_card     = "不是辅助牌",
    not_arena_card       = "不是留场牌",
    not_chase_card       = "不是追击牌",
    not_dodge_card       = "不是闪避牌",
    insufficient_resource = "体能不足",
    combo_mismatch       = "连击条件不满足",
    arsenal_empty        = "预备区为空",
    arsenal_full         = "预备区已满",
    reaction_cannot_main_play = "反应牌不能主动打出",
    invalid_weapon       = "无效的架势",
    weapon_already_used  = "架势本回合已使用",
    no_active_attack     = "没有正在进行的攻击",
    already_resolved     = "已经结算完毕",
    no_defense_value     = "没有防御值",
    dominate_limit       = "必杀限制：只能用 1 张手牌防御",
    no_equipment         = "没有装备此护具",
    equipment_no_defense = "护具防御值为 0",
    equipment_used       = "护具本回合已使用",
    no_pitch_value       = "该牌无充能值",
    ability_already_used = "英雄能力本回合已使用",
}

--- 获取友好错误消息
---@param reason string
---@return string
function ActionValidator.getErrorMessage(reason)
    return ActionValidator.ERROR_MESSAGES[reason] or ("未知错误: " .. tostring(reason))
end

return ActionValidator

-- ============================================================================
-- AI/AIPlayer.lua - AI 决策引擎
-- 基于 CardEvaluator 评分，在每个阶段选择最优行动
-- 支持难度级别、职业策略、可扩展的决策管线
-- ============================================================================

local CardData      = require("Card.CardData")
local CardDB        = require("Card.CardDB")
local TurnPhase     = require("Game.TurnPhase")
local PitchSystem   = require("Game.PitchSystem")
local CardEvaluator = require("AI.CardEvaluator")

local TYPE = CardData.TYPE
local KW   = CardData.KEYWORD

local AIPlayer = {}
AIPlayer.__index = AIPlayer

-- ============================================================================
-- 难度级别
-- ============================================================================

AIPlayer.DIFFICULTY = {
    EASY   = 1,  -- 随机因素大，经常做次优选择
    NORMAL = 2,  -- 适中，偶尔失误
    HARD   = 3,  -- 总是最优决策
}

-- ============================================================================
-- 构造
-- ============================================================================

--- 创建 AI 玩家
---@param cfg? table { difficulty?, randomSeed? }
---@return table
function AIPlayer.new(cfg)
    cfg = cfg or {}
    local self = setmetatable({}, AIPlayer)
    self.difficulty = cfg.difficulty or AIPlayer.DIFFICULTY.NORMAL
    self.name = cfg.name or "AI"
    -- 随机种子（可选，用于确定性测试）
    if cfg.randomSeed then
        math.randomseed(cfg.randomSeed)
    end
    return self
end

-- ============================================================================
-- 主入口: 决策
-- ============================================================================

--- 根据当前游戏状态选择一个行动
---@param fsm table GameFSM 实例
---@return table action { type, cardId?, pitchIds?, ... }
function AIPlayer:decideAction(fsm)
    local phase = fsm:effectivePhase()
    local player = fsm:currentPlayer()
    local opponent = fsm:opponent()
    local actions = fsm:getAvailableActions()

    if #actions == 0 then
        return { type = "end_turn" }
    end

    -- 按阶段分发
    if phase == TurnPhase.ACTION_PHASE or phase == TurnPhase.CHAIN_ATTACK then
        return self:_decideOffense(fsm, player, opponent, actions)

    elseif phase == TurnPhase.CHAIN_DEFEND then
        return self:_decideDefense(fsm, player, opponent, actions)

    elseif phase == TurnPhase.CHAIN_REACTION then
        return self:_decideReaction(fsm, player, opponent, actions)

    elseif phase == TurnPhase.END_PHASE then
        return self:_decideEndPhase(fsm, player, opponent, actions)

    else
        -- 其他阶段：返回第一个可用行动
        return actions[1]
    end
end

-- ============================================================================
-- 进攻阶段决策
-- ============================================================================

---@param fsm table
---@param player table
---@param opponent table
---@param actions table[]
---@return table
function AIPlayer:_decideOffense(fsm, player, opponent, actions)
    local scored = {}

    for _, action in ipairs(actions) do
        local score = self:_scoreOffenseAction(action, player, opponent, fsm)
        scored[#scored + 1] = { action = action, score = score }
    end

    -- 排序（降序）
    table.sort(scored, function(a, b) return a.score > b.score end)

    -- 难度控制: 加入随机性
    local pick = self:_pickByDifficulty(scored)
    local chosen = pick.action

    -- 如果选中的行动需要充能，附加 pitchIds
    chosen = self:_attachPitchIds(chosen, player)

    return chosen
end

--- 为进攻行动打分
---@return number
function AIPlayer:_scoreOffenseAction(action, player, opponent, fsm)
    local aType = action.type

    if aType == "attack" then
        local card = CardDB.get(action.cardId)
        if not card then return -10 end
        return CardEvaluator.scoreAttack(card, player, opponent)

    elseif aType == "weapon" then
        local weapon = player.weapons[action.weaponIndex]
        if not weapon then return -10 end
        return CardEvaluator.scoreWeapon(weapon, player, opponent)

    elseif aType == "support" or aType == "arena" then
        local card = CardDB.get(action.cardId)
        if not card then return -10 end
        return CardEvaluator.scoreSupport(card, player, opponent)

    elseif aType == "hero_ability" then
        return self:_scoreHeroAbility(player, opponent, fsm)

    elseif aType == "arsenal" then
        -- 从预备区打出
        local arsenalCard = player:peekArsenal()
        if arsenalCard then
            if arsenalCard:isAttack() then
                return CardEvaluator.scoreAttack(arsenalCard, player, opponent)
            else
                return CardEvaluator.scoreSupport(arsenalCard, player, opponent)
            end
        end
        return 0

    elseif aType == "end_action" then
        -- 结束行动的基准分: 手牌越少越倾向结束
        local handSize = #player.hand
        if handSize == 0 then return 5 end      -- 没手牌了就结束
        if handSize <= 1 then return 2 end      -- 只剩1张可考虑留
        return -1                                -- 还有牌，不急着结束
    end

    return 0
end

--- 英雄能力评分
function AIPlayer:_scoreHeroAbility(player, opponent, fsm)
    local heroKey = player.heroKey

    if heroKey == "kaede" then
        -- 剑道: 架势命中后额外攻击，价值取决于是否还有架势可用
        local hasWeapon = false
        for _, w in ipairs(player.weapons) do
            if not w.usedThisTurn then hasWeapon = true; break end
        end
        return hasWeapon and 6 or 2

    elseif heroKey == "xia_lin" then
        -- 跆拳道: 攻击命中后搜索 combo 牌
        return 5

    elseif heroKey == "yun_rou" then
        -- 太极: 让费用>=3 的攻击牌获得必杀+连招
        -- 检查手中是否有费用>=3 的攻击牌
        local hasExpensive = false
        for _, id in ipairs(player.hand) do
            local card = CardDB.get(id)
            if card and card:isAttack() and card.cost >= 3 then
                hasExpensive = true; break
            end
        end
        -- 还需要 2 体能来激活
        local canAfford = (player.resourcePool + PitchSystem.getPitchableTotal(player, nil)) >= 2
        return (hasExpensive and canAfford) and 7 or 1

    elseif heroKey == "xiao_tao" then
        -- 拳击: 弃掉攻击力>=6 的牌触发震慑
        -- 检查手中是否有攻击力>=6 的牌
        local hasBigAtk = false
        for _, id in ipairs(player.hand) do
            local card = CardDB.get(id)
            if card and (card.power or 0) >= 6 then
                hasBigAtk = true; break
            end
        end
        return hasBigAtk and 5 or 1
    end

    return 3  -- 默认中等价值
end

-- ============================================================================
-- 防御阶段决策
-- ============================================================================

---@param fsm table
---@param player table 当前回合玩家 (攻击方)
---@param opponent table 对手 (防御方)
---@param actions table[]
---@return table
function AIPlayer:_decideDefense(fsm, player, opponent, actions)
    -- 注意: 防御阶段，opponent 是防御方
    local chain = fsm.combatChain
    if not chain or not chain.current then
        return { type = "skip_defense" }
    end

    local link = chain.current
    local totalAttack = link.attackPower or 0
    local totalDefense = link.totalDefense or 0
    local remaining = totalAttack - totalDefense

    -- 如果攻击已经被完全格挡，不需要继续防御
    if remaining <= 0 then
        return { type = "skip_defense" }
    end

    -- 收集防御选项并打分
    local defCardIds = {}
    local defEquipSlots = {}

    -- 1) 先考虑用护具防御（低机会成本）
    for _, action in ipairs(actions) do
        if action.type == "defend_equip" then
            defEquipSlots[#defEquipSlots + 1] = action.slot
            local eq = opponent:getEquipment(action.slot)
            if eq then
                remaining = remaining - (eq.defense or 0)
            end
        end
    end

    -- 2) 如果还需要更多防御，评估手牌
    if remaining > 0 then
        local cardOptions = {}
        for _, action in ipairs(actions) do
            if action.type == "defend_card" then
                local card = CardDB.get(action.cardId)
                if card then
                    local score = CardEvaluator.scoreDefenseCard(card, remaining, opponent)
                    cardOptions[#cardOptions + 1] = {
                        cardId = action.cardId,
                        card = card,
                        defense = card.defense or 0,
                        score = score,
                    }
                end
            end
        end

        -- 按防御性价比排序（score 高的优先）
        table.sort(cardOptions, function(a, b) return a.score > b.score end)

        -- 决定要防多少
        local shouldDefend = self:_shouldBlockFully(remaining, opponent)

        if shouldDefend then
            -- 贪心选牌直到挡够
            for _, opt in ipairs(cardOptions) do
                if remaining <= 0 then break end
                if opt.score > -2 then  -- 机会成本不太高才用
                    defCardIds[#defCardIds + 1] = opt.cardId
                    remaining = remaining - opt.defense
                end
            end
        else
            -- 部分防御: 只用性价比最高的 1-2 张
            local maxCards = math.min(2, #cardOptions)
            for i = 1, maxCards do
                local opt = cardOptions[i]
                if opt and opt.score > 0 then
                    defCardIds[#defCardIds + 1] = opt.cardId
                end
            end
        end
    end

    -- 如果什么都不防
    if #defCardIds == 0 and #defEquipSlots == 0 then
        return { type = "skip_defense" }
    end

    return {
        type = "declare_defense",
        defCardIds = defCardIds,
        defEquipSlots = defEquipSlots,
    }
end

--- 判断是否应该完全格挡
---@param damage number
---@param defender table
---@return boolean
function AIPlayer:_shouldBlockFully(damage, defender)
    -- 血量低时必须全挡
    if defender.life <= damage then return true end
    if defender.life <= 6 then return true end

    -- 伤害很大也要挡
    if damage >= 7 then return true end

    -- 攻击有必杀标记时更要挡
    -- 血量充足且伤害不大时可以部分挡
    if defender.life >= 14 and damage <= 3 then
        return false
    end

    -- 默认全挡
    return true
end

-- ============================================================================
-- 反应阶段决策
-- ============================================================================

---@param fsm table
---@param player table 攻击方
---@param opponent table 防御方
---@param actions table[]
---@return table
function AIPlayer:_decideReaction(fsm, player, opponent, actions)
    local chain = fsm.combatChain

    -- 收集追击和闪避选项
    local chaseOptions = {}
    local dodgeOptions = {}

    local link = chain and chain.current
    local incomingDamage = 0
    if link then
        incomingDamage = (link.attackPower or 0) - (link.totalDefense or 0)
        if incomingDamage < 0 then incomingDamage = 0 end
    end

    for _, action in ipairs(actions) do
        if action.type == "chase" then
            local card = CardDB.get(action.cardId)
            if card then
                local score = CardEvaluator.scoreChase(card, player, opponent)
                chaseOptions[#chaseOptions + 1] = { action = action, score = score, card = card }
            end
        elseif action.type == "dodge" then
            local card = CardDB.get(action.cardId)
            if card then
                local score = CardEvaluator.scoreDodge(card, incomingDamage)
                dodgeOptions[#dodgeOptions + 1] = { action = action, score = score, card = card }
            end
        end
    end

    -- AI 作为攻击方: 考虑打追击牌
    if #chaseOptions > 0 then
        table.sort(chaseOptions, function(a, b) return a.score > b.score end)
        local best = chaseOptions[1]
        if best.score >= 3 then
            local chosen = best.action
            chosen = self:_attachPitchIds(chosen, player)
            return chosen
        end
    end

    -- AI 作为防御方: 考虑打闪避牌
    if #dodgeOptions > 0 and incomingDamage > 0 then
        table.sort(dodgeOptions, function(a, b) return a.score > b.score end)
        local best = dodgeOptions[1]
        if best.score >= 3 or opponent.life <= incomingDamage then
            local chosen = best.action
            chosen = self:_attachPitchIds(chosen, opponent)
            return chosen
        end
    end

    return { type = "skip_reaction" }
end

-- ============================================================================
-- 结束阶段决策
-- ============================================================================

---@param fsm table
---@param player table
---@param opponent table
---@param actions table[]
---@return table
function AIPlayer:_decideEndPhase(fsm, player, opponent, actions)
    -- 检查是否可以存预备区
    local arsenalOptions = {}
    for _, action in ipairs(actions) do
        if action.type == "to_arsenal" then
            local card = CardDB.get(action.cardId)
            if card then
                local score = CardEvaluator.scoreArsenal(card, player)
                arsenalOptions[#arsenalOptions + 1] = { action = action, score = score }
            end
        end
    end

    -- 选最值得存的牌
    if #arsenalOptions > 0 then
        table.sort(arsenalOptions, function(a, b) return a.score > b.score end)
        local best = arsenalOptions[1]
        if best.score >= 1 then
            return best.action
        end
    end

    return { type = "end_turn" }
end

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 为需要费用的行动附加充能方案
---@param action table
---@param player table
---@return table action (可能修改了 pitchIds)
function AIPlayer:_attachPitchIds(action, player)
    local cardId = action.cardId
    if not cardId then
        -- 武器攻击
        if action.type == "weapon" then
            local weapon = player.weapons[action.weaponIndex]
            if weapon and weapon.data and weapon.data.cost and weapon.data.cost > 0 then
                local pitchIds, waste = PitchSystem.suggestExactPitch(
                    player, weapon.data.cost, nil)
                if pitchIds then
                    action.pitchIds = pitchIds
                end
            end
        end
        return action
    end

    local card = CardDB.get(cardId)
    if not card or card.cost <= 0 then
        return action
    end

    -- 已有足够资源不需要充能
    if player.resourcePool >= card.cost then
        return action
    end

    local pitchIds, waste = PitchSystem.suggestExactPitch(player, card.cost, cardId)
    if pitchIds then
        action.pitchIds = pitchIds
    end

    return action
end

--- 根据难度级别从排名选项中选择
---@param scoredActions table[] { action, score }
---@return table chosen
function AIPlayer:_pickByDifficulty(scoredActions)
    if #scoredActions == 0 then
        return { action = { type = "end_action" }, score = 0 }
    end

    if self.difficulty == AIPlayer.DIFFICULTY.HARD then
        return scoredActions[1]  -- 总是最优

    elseif self.difficulty == AIPlayer.DIFFICULTY.EASY then
        -- 30% 概率选非最优
        if math.random() < 0.3 and #scoredActions > 1 then
            local idx = math.random(2, math.min(#scoredActions, 4))
            return scoredActions[idx]
        end
        return scoredActions[1]

    else -- NORMAL
        -- 15% 概率选第二名（如果有的话）
        if math.random() < 0.15 and #scoredActions > 1 then
            return scoredActions[2]
        end
        return scoredActions[1]
    end
end

-- ============================================================================
-- AI 自动对战（测试用）
-- ============================================================================

--- 运行一局 AI vs AI 对战，返回日志
---@param fsm table GameFSM（已初始化）
---@param maxTurns? number 最大回合数（防死循环，默认50）
---@return table result { winner, turns, log }
function AIPlayer.runTestGame(fsm, maxTurns)
    maxTurns = maxTurns or 50

    local ai1 = AIPlayer.new({ difficulty = AIPlayer.DIFFICULTY.HARD, name = "AI-1" })
    local ai2 = AIPlayer.new({ difficulty = AIPlayer.DIFFICULTY.HARD, name = "AI-2" })
    local ais = { ai1, ai2 }

    -- 开始游戏
    fsm:startGame()

    local turnCount = 0
    local actionCount = 0
    local maxActions = 500  -- 总行动次数上限

    while not fsm:isGameOver() and turnCount < maxTurns and actionCount < maxActions do
        local phase = fsm:effectivePhase()

        -- 确定当前应该由哪个 AI 行动
        local currentAI
        if phase == TurnPhase.CHAIN_DEFEND then
            -- 防御阶段: 由对手（非当前回合玩家）决策
            local oppIdx = fsm.turnPlayerIndex == 1 and 2 or 1
            currentAI = ais[oppIdx]
        else
            currentAI = ais[fsm.turnPlayerIndex]
        end

        local action = currentAI:decideAction(fsm)
        local ok, err = fsm:executeAction(action)

        if not ok then
            -- 行动失败，尝试跳过
            print(string.format("[AI-Test] Action failed: %s / %s, fallback",
                action.type, tostring(err)))
            if phase == TurnPhase.CHAIN_DEFEND then
                fsm:executeAction({ type = "skip_defense" })
            elseif phase == TurnPhase.CHAIN_REACTION then
                fsm:executeAction({ type = "skip_reaction" })
            elseif phase == TurnPhase.END_PHASE then
                fsm:executeAction({ type = "end_turn" })
            elseif phase == TurnPhase.ACTION_PHASE or phase == TurnPhase.CHAIN_ATTACK then
                fsm:executeAction({ type = "end_action" })
            end
        end

        actionCount = actionCount + 1

        -- 检查回合切换
        if fsm.turnNumber > turnCount then
            turnCount = fsm.turnNumber
        end
    end

    -- 结果
    local winner = nil
    if fsm:isGameOver() then
        if fsm.players[1].life <= 0 then
            winner = 2
        elseif fsm.players[2].life <= 0 then
            winner = 1
        else
            -- 牌库耗尽等其他情况
            winner = fsm.players[1].life >= fsm.players[2].life and 1 or 2
        end
    end

    return {
        winner = winner,
        turns = turnCount,
        actions = actionCount,
        p1Life = fsm.players[1].life,
        p2Life = fsm.players[2].life,
        p1Name = fsm.players[1].heroName,
        p2Name = fsm.players[2].heroName,
        log = fsm.log,
        timedOut = (not fsm:isGameOver()),
    }
end

return AIPlayer

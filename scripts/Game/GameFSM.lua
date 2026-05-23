-- ============================================================================
-- Game/GameFSM.lua - 主游戏状态机
-- 驱动回合流程：开始 → 抽牌 → 行动 ⇄ 连招链 → 结束 → 换边
-- 提供 executeAction() 统一入口供 UI / AI 调用
-- ============================================================================

local CardData        = require("Card.CardData")
local CardDB          = require("Card.CardDB")
local TurnPhase       = require("Game.TurnPhase")
local Player          = require("Game.Player")
local PitchSystem     = require("Game.PitchSystem")
local CombatChain     = require("Game.CombatChain")
local ActionValidator = require("Game.ActionValidator")
local EffectProcessor = require("Game.EffectProcessor")
local CustomHandlers  = require("Game.CustomHandlers")

local TYPE = CardData.TYPE
local KW   = CardData.KEYWORD

local GameFSM = {}
GameFSM.__index = GameFSM

-- ============================================================================
-- 构造
-- ============================================================================

--- 创建游戏状态机
---@param cfg table { player1Cfg, player2Cfg }
---  每个 playerCfg = { heroKey, deckCardIds?, equipmentIds? }
---@return table
function GameFSM.new(cfg)
    local self = setmetatable({}, GameFSM)

    -- 玩家
    self.players = {
        Player.new(cfg.player1Cfg),
        Player.new(cfg.player2Cfg),
    }

    -- 当前回合
    self.turnPlayerIndex = 1                   -- 先手玩家索引
    self.phase           = TurnPhase.GAME_START
    self.chainSubPhase   = nil                 -- 连招子阶段
    self.turnNumber      = 0

    -- 连招链
    self.combatChain = nil

    -- 当前攻击的效果上下文（用于延迟命中/重击效果）
    self._currentAttackCtx = nil

    -- 日志
    self.log = {}   -- { { text, time } }

    -- 事件回调（供 UI 层注册）
    self.callbacks = {
        onPhaseChanged    = nil,  -- function(phase, subPhase)
        onTurnStarted     = nil,  -- function(turnPlayerIndex, turnNumber)
        onCardPlayed      = nil,  -- function(playerIndex, cardId, cardData, action)
        onAttackDeclared  = nil,  -- function(link)
        onDefenseDeclared = nil,  -- function(link, totalDefense)
        onDamageResolved  = nil,  -- function(link, damage, didHit)
        onChainClosed     = nil,  -- function(summary)
        onGameOver        = nil,  -- function(winnerIndex, reason)
        onLogAdded        = nil,  -- function(entry)
        onDrawCards       = nil,  -- function(playerIndex, cardIds)
        onLifeChanged     = nil,  -- function(playerIndex, newLife, delta)
    }

    return self
end

-- ============================================================================
-- 日志
-- ============================================================================

function GameFSM:addLog(text)
    local entry = { text = text, turn = self.turnNumber }
    self.log[#self.log + 1] = entry
    if self.callbacks.onLogAdded then
        self.callbacks.onLogAdded(entry)
    end
end

-- ============================================================================
-- 玩家访问
-- ============================================================================

--- 当前行动玩家
---@return table Player
function GameFSM:currentPlayer()
    return self.players[self.turnPlayerIndex]
end

--- 对手
---@return table Player
function GameFSM:opponent()
    return self.players[self.turnPlayerIndex == 1 and 2 or 1]
end

--- 对手索引
---@return number
function GameFSM:opponentIndex()
    return self.turnPlayerIndex == 1 and 2 or 1
end

-- ============================================================================
-- 阶段转换
-- ============================================================================

--- 设置阶段（含合法性检查与回调）
---@param newPhase string
---@param subPhase? string
---@return boolean success
function GameFSM:setPhase(newPhase, subPhase)
    -- 连招子阶段在 combat_chain 阶段内部切换
    if newPhase == TurnPhase.COMBAT_CHAIN then
        self.phase = newPhase
        self.chainSubPhase = subPhase
    else
        self.phase = newPhase
        self.chainSubPhase = nil
    end

    if self.callbacks.onPhaseChanged then
        self.callbacks.onPhaseChanged(self.phase, self.chainSubPhase)
    end
    return true
end

--- 获取当前有效阶段（含子阶段）
---@return string effectivePhase
function GameFSM:effectivePhase()
    if self.phase == TurnPhase.COMBAT_CHAIN and self.chainSubPhase then
        return self.chainSubPhase
    end
    return self.phase
end

-- ============================================================================
-- 游戏生命周期
-- ============================================================================

--- 初始化游戏（选英雄后调用）
function GameFSM:startGame()
    self:setPhase(TurnPhase.GAME_START)
    self:addLog("游戏开始！")

    -- 双方初始抽牌
    for i, p in ipairs(self.players) do
        local drawn = p:drawToIntellect()
        self:addLog(string.format("%s 初始抽牌 %d 张", p.heroName, #drawn))
        if self.callbacks.onDrawCards then
            self.callbacks.onDrawCards(i, drawn)
        end
    end

    -- 开始第一回合
    self:beginTurn()
end

--- 开始一个回合
function GameFSM:beginTurn()
    self.turnNumber = self.turnNumber + 1
    local p = self:currentPlayer()
    p:beginTurn()

    -- 清理回合开始时过期的状态标记（Crush 持续效果等）
    CustomHandlers.cleanupMarksOnTurnStart(p)

    -- 检查抑制效果并记录日志
    if CustomHandlers.isGoAgainSuppressed(p) then
        self:addLog(string.format("⚡ %s 本回合不能获得连招（推山掌效果）", p.heroName))
    end
    if CustomHandlers.isDrawSuppressed(p) then
        self:addLog(string.format("⚡ %s 本回合不能抽牌（封脉掌效果）", p.heroName))
    end
    if CustomHandlers.isHeroAbilitySuppressed(p) then
        self:addLog(string.format("⚡ %s 本回合不能使用英雄能力（挒劲效果）", p.heroName))
    end

    self:addLog(string.format("=== 第 %d 回合 [%s] ===", self.turnNumber, p.heroName))

    if self.callbacks.onTurnStarted then
        self.callbacks.onTurnStarted(self.turnPlayerIndex, self.turnNumber)
    end

    -- 重置攻击上下文
    self._currentAttackCtx = nil

    -- 开始阶段 → 抽牌阶段 → 行动阶段
    self:setPhase(TurnPhase.START_PHASE)
    self:enterDrawPhase()
end

--- 进入抽牌阶段
function GameFSM:enterDrawPhase()
    self:setPhase(TurnPhase.DRAW_PHASE)
    -- 首回合已在 startGame 中抽过牌，后续回合在 endTurn 里 drawToIntellect
    -- 这里只做触发效果用
    self:enterActionPhase()
end

--- 进入行动阶段
function GameFSM:enterActionPhase()
    self:setPhase(TurnPhase.ACTION_PHASE)
    self:addLog("行动阶段开始")
end

-- ============================================================================
-- 统一行动入口
-- ============================================================================

--- 执行一个行动
--- UI / AI 通过此方法提交所有操作
---@param action table { type, cardId?, weaponIndex?, slot?, pitchIds?, defCardIds?, defEquipSlots? }
---@return boolean ok
---@return string|nil reason
function GameFSM:executeAction(action)
    local aType = action.type
    local phase = self:effectivePhase()
    local player = self:currentPlayer()
    local opp = self:opponent()

    -- === 行动阶段操作 ===

    if aType == "attack" then
        return self:_doAttack(player, action.cardId, action.pitchIds)

    elseif aType == "weapon" then
        return self:_doWeaponAttack(player, action.weaponIndex, action.pitchIds)

    elseif aType == "arsenal" then
        return self:_doPlayArsenal(player, action.pitchIds)

    elseif aType == "support" then
        return self:_doPlaySupport(player, action.cardId, action.pitchIds)

    elseif aType == "arena" then
        return self:_doPlayArena(player, action.cardId, action.pitchIds)

    elseif aType == "hero_ability" then
        return self:_doHeroAbility(player)

    elseif aType == "end_action" then
        return self:_doEndAction()

    -- === 防御操作 ===
    elseif aType == "declare_defense" then
        return self:_doDeclareDefense(opp, action.defCardIds or {}, action.defEquipSlots or {})

    elseif aType == "skip_defense" then
        return self:_doDeclareDefense(opp, {}, {})

    -- === 反应操作 ===
    elseif aType == "chase" then
        return self:_doPlayChase(player, action.cardId, action.pitchIds)

    elseif aType == "dodge" then
        return self:_doPlayDodge(opp, action.cardId, action.pitchIds)

    elseif aType == "skip_reaction" then
        return self:_doSkipReaction()

    -- === 结束阶段 ===
    elseif aType == "to_arsenal" then
        return self:_doPlaceArsenal(player, action.cardId)

    elseif aType == "end_turn" then
        return self:_doEndTurn()

    -- === 充能（可在任意需要支付费用的时机使用）===
    elseif aType == "pitch" then
        return self:_doPitch(player, action.cardId)

    else
        return false, "unknown_action"
    end
end

-- ============================================================================
-- 行动实现
-- ============================================================================

--- 打出攻击牌
function GameFSM:_doAttack(player, cardId, pitchIds)
    local phase = self:effectivePhase()
    local opp = self:opponent()
    local ok, reason = ActionValidator.canPlayAttack(player, cardId, phase, self.combatChain)
    if not ok then return false, reason end

    -- 充能 + 支付（检查费用减免）
    local card = CardDB.get(cardId)
    local actualCost = card.cost
    if actualCost > 0 then
        local reduction = EffectProcessor.consumeCostReduction(player, "next_attack")
        actualCost = math.max(0, actualCost - reduction)
    end

    -- 首个行动额外费用（Crush Cartilage 效果）
    local extraCost = CustomHandlers.getFirstActionExtraCost(player)
    if extraCost > 0 then
        actualCost = actualCost + extraCost
        self:addLog(string.format("採劲效果：额外支付 %d 体能", extraCost))
    end

    if actualCost > 0 then
        local payOk, payErr = PitchSystem.pitchAndPay(player, cardId, pitchIds, actualCost)
        if not payOk then return false, payErr end
    end

    -- 消耗行动点
    player:spendActionPoint()

    -- 消耗首个行动一次性标记
    CustomHandlers.consumeFirstActionMarks(player)

    -- 从手牌移除
    player:playFromHand(cardId)

    self:addLog(string.format("%s 出击：%s (攻:%d)", player.heroName, card.name, card.power))

    if self.callbacks.onCardPlayed then
        self.callbacks.onCardPlayed(self.turnPlayerIndex, cardId, card, "attack")
    end

    -- 进入连招流程（声明攻击、创建链环节）
    local chainOk, chainErr = self:_openCombatChain(cardId, nil)
    if not chainOk then return false, chainErr end

    -- 攻击牌效果处理（附加费用、关键词、主效果、注册延迟效果 + 应用 pending/EOT buffs）
    local ctx = EffectProcessor.processAttackCard(
        player, opp, self.combatChain, card, cardId, self)

    -- 首次攻击攻击力修正（Crush Debilitate 效果）
    local debuff = CustomHandlers.getFirstAttackDebuff(player)
    if debuff ~= 0 then
        self.combatChain:buffCurrentPower(debuff, "肘靠效果")
        self:addLog(string.format("肘靠效果：攻击力 %d", debuff))
    end

    -- 检查 Go Again 抑制（推山掌效果）
    if CustomHandlers.isGoAgainSuppressed(player) and self.combatChain.current then
        self.combatChain.current.goAgain = false
    end

    -- 保存上下文供命中后效果使用
    self._currentAttackCtx = ctx

    return true, nil
end

--- 架势攻击
function GameFSM:_doWeaponAttack(player, weaponIndex, pitchIds)
    local phase = self:effectivePhase()
    local opp = self:opponent()
    local ok, reason = ActionValidator.canUseWeapon(player, weaponIndex, phase)
    if not ok then return false, reason end

    local wData = player.weapons[weaponIndex].data

    -- 费用（含费用减免）
    local actualCost = wData.cost or 0
    if actualCost > 0 then
        local reduction = EffectProcessor.consumeCostReduction(player, "next_weapon")
        actualCost = math.max(0, actualCost - reduction)
    end

    -- 首个行动额外费用
    local extraCost = CustomHandlers.getFirstActionExtraCost(player)
    if extraCost > 0 then
        actualCost = actualCost + extraCost
        self:addLog(string.format("採劲效果：额外支付 %d 体能", extraCost))
    end

    if actualCost > 0 then
        local payOk, payErr = PitchSystem.pitchAndPay(player, wData.id, pitchIds, actualCost)
        if not payOk then return false, payErr end
    end

    -- 消耗行动点
    player:spendActionPoint()

    -- 消耗首个行动一次性标记
    CustomHandlers.consumeFirstActionMarks(player)

    -- 标记使用
    player:useWeapon(weaponIndex)

    self:addLog(string.format("%s 架势攻击：%s (攻:%d)",
        player.heroName, wData.name, wData.power + (player.weapons[weaponIndex].hitCounters or 0)))

    -- 进入连招流程
    local chainOk, chainErr = self:_openCombatChain(nil, weaponIndex)
    if not chainOk then return false, chainErr end

    -- 架势 customHandler（如武器特殊效果）
    if wData.customHandler then
        local weaponCtx = EffectProcessor.buildContext({
            attacker = player,
            defender = opp,
            chain    = self.combatChain,
            card     = nil,
            cardId   = wData.id,
            fsm      = self,
            source   = "weapon",
        })
        local handler = CustomHandlers.get(wData.customHandler)
        if handler then
            handler(weaponCtx)
        end
        self._currentAttackCtx = weaponCtx
    else
        self._currentAttackCtx = EffectProcessor.buildContext({
            attacker = player,
            defender = opp,
            chain    = self.combatChain,
            card     = nil,
            cardId   = wData.id,
            fsm      = self,
            source   = "weapon",
        })
    end

    -- 应用 pending buffs 和 EOT buffs
    if self.combatChain and self.combatChain.current then
        EffectProcessor.applyPendingBuffs(player, self.combatChain, self.combatChain.current, nil)
        EffectProcessor.applyEOTBuffs(player, self.combatChain, self.combatChain.current, nil)
    end

    -- 首次攻击攻击力修正
    local debuff = CustomHandlers.getFirstAttackDebuff(player)
    if debuff ~= 0 then
        self.combatChain:buffCurrentPower(debuff, "肘靠效果")
        self:addLog(string.format("肘靠效果：攻击力 %d", debuff))
    end

    -- Go Again 抑制检查
    if CustomHandlers.isGoAgainSuppressed(player) and self.combatChain.current then
        self.combatChain.current.goAgain = false
    end

    return true, nil
end

--- 从预备区打出
function GameFSM:_doPlayArsenal(player, pitchIds)
    local phase = self:effectivePhase()
    local ok, reason = ActionValidator.canPlayFromArsenal(player, phase, self.combatChain)
    if not ok then return false, reason end

    local arsenalCard = player:peekArsenal()
    if not arsenalCard then return false, "arsenal_empty" end

    -- 费用
    if arsenalCard.cost > 0 then
        local payOk, payErr = PitchSystem.pitchAndPay(player, arsenalCard.id, pitchIds)
        if not payOk then return false, payErr end
    end

    -- 消耗行动点
    player:spendActionPoint()

    -- 从预备区取出
    local cardId = player:playFromArsenal()

    self:addLog(string.format("%s 从预备区出击：%s", player.heroName, arsenalCard.name))

    if self.callbacks.onCardPlayed then
        self.callbacks.onCardPlayed(self.turnPlayerIndex, cardId, arsenalCard, "arsenal_attack")
    end

    -- 攻击牌进连招链，辅助牌直接结算
    if arsenalCard:isAttack() then
        local chainOk, chainErr = self:_openCombatChain(cardId, nil)
        if not chainOk then return false, chainErr end

        -- 攻击牌效果处理
        local opp = self:opponent()
        local ctx = EffectProcessor.processAttackCard(
            player, opp, self.combatChain, arsenalCard, cardId, self)
        ctx.source = "arsenal"  -- 标记来源为预备区

        -- Go Again 抑制检查
        if CustomHandlers.isGoAgainSuppressed(player) and self.combatChain.current then
            self.combatChain.current.goAgain = false
        end

        self._currentAttackCtx = ctx
        return true, nil
    else
        -- 辅助牌效果处理
        local opp = self:opponent()
        EffectProcessor.processSupportCard(player, opp, arsenalCard, cardId, self)

        -- Go Again 检查（EffectProcessor 已在 _processKeywords 中处理）
        player:addToGraveyard(cardId)
        return true, nil
    end
end

--- 打出辅助牌
function GameFSM:_doPlaySupport(player, cardId, pitchIds)
    local phase = self:effectivePhase()
    local opp = self:opponent()
    local ok, reason = ActionValidator.canPlaySupport(player, cardId, phase)
    if not ok then return false, reason end

    local card = CardDB.get(cardId)

    -- 费用（含费用减免）
    local actualCost = card.cost
    if actualCost > 0 then
        local reduction = EffectProcessor.consumeCostReduction(player, "any")
        actualCost = math.max(0, actualCost - reduction)
    end

    -- 首个行动额外费用
    local extraCost = CustomHandlers.getFirstActionExtraCost(player)
    if extraCost > 0 then
        actualCost = actualCost + extraCost
        self:addLog(string.format("採劲效果：额外支付 %d 体能", extraCost))
    end

    if actualCost > 0 then
        local payOk, payErr = PitchSystem.pitchAndPay(player, cardId, pitchIds, actualCost)
        if not payOk then return false, payErr end
    end

    -- 消耗行动点
    player:spendActionPoint()

    -- 消耗首个行动一次性标记
    CustomHandlers.consumeFirstActionMarks(player)

    -- 从手牌移除
    player:playFromHand(cardId)

    self:addLog(string.format("%s 使用辅助：%s", player.heroName, card.name))

    if self.callbacks.onCardPlayed then
        self.callbacks.onCardPlayed(self.turnPlayerIndex, cardId, card, "support")
    end

    -- 效果处理（EffectProcessor 处理关键词 Go Again、主效果等）
    EffectProcessor.processSupportCard(player, opp, card, cardId, self)

    -- Go Again 抑制检查
    if CustomHandlers.isGoAgainSuppressed(player) then
        -- EffectProcessor 可能已经给了行动点，需要撤回
        -- 简化处理：辅助牌的 Go Again 在 _processKeywords 中直接给行动点
        -- 此处不做额外处理，因为抑制效果主要针对连招链内的 Go Again
    end

    -- 辅助牌进弃牌堆
    player:addToGraveyard(cardId)

    return true, nil
end

--- 打出留场牌
function GameFSM:_doPlayArena(player, cardId, pitchIds)
    local phase = self:effectivePhase()
    local ok, reason = ActionValidator.canPlayArenaCard(player, cardId, phase)
    if not ok then return false, reason end

    local card = CardDB.get(cardId)

    -- 费用
    if card.cost > 0 then
        local payOk, payErr = PitchSystem.pitchAndPay(player, cardId, pitchIds)
        if not payOk then return false, payErr end
    end

    player:spendActionPoint()
    player:playFromHand(cardId)
    player:placeArenaCard(cardId)

    self:addLog(string.format("%s 放置状态：%s", player.heroName, card.name))

    if self.callbacks.onCardPlayed then
        self.callbacks.onCardPlayed(self.turnPlayerIndex, cardId, card, "arena")
    end

    return true, nil
end

--- 使用英雄能力
function GameFSM:_doHeroAbility(player)
    local phase = self:effectivePhase()
    local opp = self:opponent()
    local ok, reason = ActionValidator.canUseHeroAbility(player, phase)
    if not ok then return false, reason end

    -- 检查英雄能力是否被抑制（挒劲效果）
    if CustomHandlers.isHeroAbilitySuppressed(player) then
        return false, "hero_ability_suppressed"
    end

    -- 查找英雄的 customHandler
    local heroData = player.heroData
    if not heroData or not heroData.customHandler then
        return false, "no_hero_ability"
    end

    -- 构建效果上下文
    local ctx = EffectProcessor.buildContext({
        attacker = player,
        defender = opp,
        chain    = self.combatChain,
        card     = nil,
        cardId   = player.heroKey,
        fsm      = self,
        source   = "hero",
    })

    -- 调用英雄能力处理器（处理器内部管理 heroAbilityUsed 和 actionPoint）
    local handler = CustomHandlers.get(heroData.customHandler)
    if not handler then
        return false, "handler_not_found"
    end

    local heroOk, heroErr = handler(ctx)
    if not heroOk then
        return false, heroErr or "hero_ability_failed"
    end

    self:addLog(string.format("%s 使用英雄能力", player.heroName))

    return true, nil
end

--- 结束行动阶段
function GameFSM:_doEndAction()
    -- 如果有未关闭的连招链，先关闭
    if self.combatChain and not self.combatChain.closed then
        self:_closeCombatChain()
    end

    self:enterEndPhase()
    return true, nil
end

-- ============================================================================
-- 连招链管理
-- ============================================================================

--- 开启/继续连招链
---@param cardId string|nil 攻击牌 ID
---@param weaponIndex number|nil 架势索引
---@return boolean, string|nil
function GameFSM:_openCombatChain(cardId, weaponIndex)
    local player = self:currentPlayer()
    local opp = self:opponent()

    -- 创建或复用连招链
    if not self.combatChain or self.combatChain.closed then
        self.combatChain = CombatChain.new(player, opp)
        self:_registerChainCallbacks()
    end

    -- 声明攻击
    local link, err = self.combatChain:declareAttack({
        cardId = cardId,
        weaponIndex = weaponIndex,
    })

    if not link then
        return false, err or "declare_attack_failed"
    end

    -- 进入连招阶段 → 防御子阶段
    self:setPhase(TurnPhase.COMBAT_CHAIN, TurnPhase.CHAIN_DEFEND)

    return true, nil
end

--- 注册连招链回调
function GameFSM:_registerChainCallbacks()
    local chain = self.combatChain

    chain.callbacks.onAttackDeclared = function(link)
        if self.callbacks.onAttackDeclared then
            self.callbacks.onAttackDeclared(link)
        end
    end

    chain.callbacks.onDefenseDeclared = function(link)
        if self.callbacks.onDefenseDeclared then
            self.callbacks.onDefenseDeclared(link, link.totalDefense)
        end
    end

    chain.callbacks.onDamageResolved = function(link, damage, didHit)
        -- 检查体力变化
        if damage > 0 and self.callbacks.onLifeChanged then
            self.callbacks.onLifeChanged(self:opponentIndex(),
                self:opponent().life, -damage)
        end

        if self.callbacks.onDamageResolved then
            self.callbacks.onDamageResolved(link, damage, didHit)
        end

        -- 检查游戏结束
        if self:opponent():isDefeated() then
            self:_gameOver(self.turnPlayerIndex, "knockout")
        end
    end

    chain.callbacks.onChainClosed = function(ch)
        if self.callbacks.onChainClosed then
            self.callbacks.onChainClosed(ch:getSummary())
        end
    end
end

--- 声明防御
function GameFSM:_doDeclareDefense(defender, cardIds, equipSlots)
    local phase = self:effectivePhase()
    if phase ~= TurnPhase.CHAIN_DEFEND then
        return false, "wrong_phase"
    end

    if not self.combatChain then
        return false, "no_combat_chain"
    end

    -- 验证每张防御手牌
    for _, id in ipairs(cardIds) do
        local ok, reason = ActionValidator.canDefendWithCard(
            defender, id, self.combatChain, phase)
        if not ok then return false, reason end
    end

    -- 验证每个护具
    for _, slot in ipairs(equipSlots) do
        local ok, reason = ActionValidator.canDefendWithEquipment(
            defender, slot, self.combatChain, phase)
        if not ok then return false, reason end
    end

    -- 执行防御
    local totalDef = self.combatChain:declareDefense(cardIds, equipSlots)

    local defDesc = #cardIds .. " 张手牌"
    if #equipSlots > 0 then
        defDesc = defDesc .. " + " .. #equipSlots .. " 件护具"
    end
    self:addLog(string.format("%s 防御 (%s, 总防:%d)",
        defender.heroName, defDesc, totalDef))

    -- 进入反应子阶段
    self:setPhase(TurnPhase.COMBAT_CHAIN, TurnPhase.CHAIN_REACTION)

    return true, nil
end

--- 追击牌
function GameFSM:_doPlayChase(attacker, cardId, pitchIds)
    local phase = self:effectivePhase()
    local opp = self:opponent()
    local ok, reason = ActionValidator.canPlayChase(attacker, cardId, self.combatChain, phase)
    if not ok then return false, reason end

    local card = CardDB.get(cardId)

    -- 费用
    if card.cost > 0 then
        local payOk, payErr = PitchSystem.pitchAndPay(attacker, cardId, pitchIds)
        if not payOk then return false, payErr end
    end

    self.combatChain:playAttackReaction(cardId)

    -- 追击牌效果处理（customHandler 或默认 power buff + 效果词条）
    local ctx = EffectProcessor.processChaseCard(
        attacker, opp, self.combatChain, card, cardId, self)

    -- 如果没有 customHandler 也没有效果词条处理 power，手动 buff
    -- EffectProcessor.processCard 会处理 keywords 和 effects
    -- 但追击牌的 power 本身是作为 buff 添加的（不同于攻击牌的基础攻击力）
    -- 检查是否已经由效果系统 buff 过
    if not card.customHandler and (not card.effects or #card.effects == 0) then
        if card.power > 0 then
            self.combatChain:buffCurrentPower(card.power, card.name)
        end
    end

    self:addLog(string.format("%s 追击：%s (+%d)", attacker.heroName, card.name, card.power))

    if self.callbacks.onCardPlayed then
        self.callbacks.onCardPlayed(self.turnPlayerIndex, cardId, card, "chase")
    end

    return true, nil
end

--- 闪避牌
function GameFSM:_doPlayDodge(defender, cardId, pitchIds)
    local phase = self:effectivePhase()
    local attacker = self:currentPlayer()
    local ok, reason = ActionValidator.canPlayDodge(defender, cardId, self.combatChain, phase)
    if not ok then return false, reason end

    local card = CardDB.get(cardId)

    -- 费用
    if card.cost > 0 then
        local payOk, payErr = PitchSystem.pitchAndPay(defender, cardId, pitchIds)
        if not payOk then return false, payErr end
    end

    self.combatChain:playDefenseReaction(cardId)

    -- 闪避牌效果处理（如有额外效果词条）
    EffectProcessor.processDodgeCard(defender, attacker, self.combatChain, card, cardId, self)

    self:addLog(string.format("%s 闪避：%s (+%d 防)", defender.heroName, card.name, card.defense))

    if self.callbacks.onCardPlayed then
        self.callbacks.onCardPlayed(self:opponentIndex(), cardId, card, "dodge")
    end

    return true, nil
end

--- 跳过反应 → 结算
function GameFSM:_doSkipReaction()
    if self:effectivePhase() ~= TurnPhase.CHAIN_REACTION then
        return false, "wrong_phase"
    end

    -- 进入结算
    self:setPhase(TurnPhase.COMBAT_CHAIN, TurnPhase.CHAIN_RESOLVE)

    local player = self:currentPlayer()
    local opp = self:opponent()

    -- 结算前：应用伤害盾（防御方的 damageShield 减少受到的伤害）
    local link = self.combatChain.current
    if link then
        local rawDamage = math.max(0, link.attackPower - link.totalDefense)
        local afterShield = EffectProcessor.applyDamageShield(opp, rawDamage)
        local shieldUsed = rawDamage - afterShield
        if shieldUsed > 0 then
            -- 把 shield 吸收量加到 totalDefense，让 resolveCurrentLink 算出正确伤害
            link.totalDefense = link.totalDefense + shieldUsed
            self:addLog(string.format("护盾抵消 %d 点伤害", shieldUsed))
        end
    end

    local damage, didHit = self.combatChain:resolveCurrentLink()

    if didHit then
        self:addLog(string.format("命中！造成 %d 点伤害", damage))
    else
        self:addLog("完全格挡！")
    end

    -- 命中后/重击延迟效果处理（on_hit / crush_check）
    if self._currentAttackCtx then
        local postResults = EffectProcessor.processPostCombat(
            self._currentAttackCtx, damage, didHit)
        -- 输出触发的效果日志
        if postResults then
            for _, result in ipairs(postResults) do
                if result.triggered and result.log then
                    self:addLog(result.log)
                end
            end
        end
    end

    -- 武器命中后处理器（如晨光刃的命中计数器）
    if self._currentAttackCtx and self._currentAttackCtx.source == "weapon" then
        local wIndex = self.combatChain.current and self.combatChain.current.weaponIndex
        if wIndex then
            local wData = player.weapons[wIndex] and player.weapons[wIndex].data
            if wData and wData.onHitHandler and didHit then
                local onHitHandler = CustomHandlers.get(wData.onHitHandler)
                if onHitHandler then
                    onHitHandler(self._currentAttackCtx, damage)
                end
            end
        end
    end

    -- 清空当前攻击上下文
    self._currentAttackCtx = nil

    -- 结算后处理
    self:_afterLinkResolved()

    return true, nil
end

--- 单环节结算后处理
function GameFSM:_afterLinkResolved()
    -- 检查游戏结束
    if self:opponent():isDefeated() then
        self:_closeCombatChain()
        self:_gameOver(self.turnPlayerIndex, "knockout")
        return
    end

    -- 检查 Go Again
    self.combatChain:processGoAgain()
    local hasGoAgain = self.combatChain:checkGoAgain()

    if hasGoAgain then
        self:addLog("连招！可继续攻击")
        -- 保持连招链打开，回到攻击子阶段
        self:setPhase(TurnPhase.COMBAT_CHAIN, TurnPhase.CHAIN_ATTACK)
    else
        -- 没有 Go Again → 关闭连招链 → 回到行动阶段或结束
        self:_closeCombatChain()

        -- 检查是否还有行动点
        if self:currentPlayer():hasActionPoint() then
            self:enterActionPhase()
        else
            self:enterEndPhase()
        end
    end
end

--- 关闭连招链
function GameFSM:_closeCombatChain()
    if not self.combatChain or self.combatChain.closed then return end

    local summary = self.combatChain:close()
    self:addLog(string.format("连招链关闭：%d 环节, 总伤害 %d, 命中 %d 次",
        summary.linkCount, summary.totalDamage, summary.hits))
end

-- ============================================================================
-- 结束阶段
-- ============================================================================

--- 进入结束阶段
function GameFSM:enterEndPhase()
    -- 先关闭可能存在的连招链
    if self.combatChain and not self.combatChain.closed then
        self:_closeCombatChain()
    end

    self:setPhase(TurnPhase.END_PHASE)
    self:addLog("结束阶段")
end

--- 放入预备区
function GameFSM:_doPlaceArsenal(player, cardId)
    local phase = self:effectivePhase()
    local ok, reason = ActionValidator.canPlaceToArsenal(player, cardId, phase)
    if not ok then return false, reason end

    player:addToArsenal(cardId)
    self:addLog(string.format("%s 存入预备区 1 张牌", player.heroName))

    -- 自动进入结束回合
    self:_finishTurn()

    return true, nil
end

--- 结束回合（不存预备区）
function GameFSM:_doEndTurn()
    self:_finishTurn()
    return true, nil
end

--- 执行回合结束处理
function GameFSM:_finishTurn()
    local player = self:currentPlayer()
    local opp = self:opponent()

    -- 武器回合结束处理器（如晨光刃的回合结束处理）
    for i, w in ipairs(player.weapons) do
        if w.data and w.data.endTurnHandler then
            local handler = CustomHandlers.get(w.data.endTurnHandler)
            if handler then
                local ctx = EffectProcessor.buildContext({
                    attacker = player,
                    defender = opp,
                    chain    = nil,
                    card     = nil,
                    cardId   = w.data.id,
                    fsm      = self,
                    source   = "weapon_eot",
                })
                handler(ctx)
            end
        end
    end

    -- 效果系统回合结束清理（清除 pendingBuffs、eotBuffs、damageShield、costReduction）
    EffectProcessor.cleanupEndOfTurn(player)

    -- 状态标记回合结束清理（清除 apply_turn = "this" 的标记）
    CustomHandlers.cleanupMarksOnTurnEnd(player)

    -- endTurn 处理：归还震慑、预备区已在 _doPlaceArsenal 处理、充能区归底、抽牌
    player:endTurn(nil, nil)  -- arsenal 已单独处理，此处不传

    local drawnCount = #player.hand -- endTurn 已抽到上限
    self:addLog(string.format("%s 回合结束，手牌 %d 张", player.heroName, drawnCount))

    -- 检查牌库耗尽（FAB 的疲劳规则：牌库空时不立即输，但无牌可抽时也不结束游戏）
    -- 简化处理：不做 fatigue damage

    -- 切换回合
    self:_switchTurn()
end

--- 切换到对手的回合
function GameFSM:_switchTurn()
    self.turnPlayerIndex = self.turnPlayerIndex == 1 and 2 or 1
    self.combatChain = nil
    self:beginTurn()
end

-- ============================================================================
-- 充能操作
-- ============================================================================

--- 主动充能一张手牌
function GameFSM:_doPitch(player, cardId)
    local ok, reason = ActionValidator.canPitch(player, cardId)
    if not ok then return false, reason end

    local gained = player:pitchCard(cardId)
    local card = CardDB.get(cardId)
    local name = card and card.name or cardId

    self:addLog(string.format("%s 充能：%s (+%d 体能)", player.heroName, name, gained))

    return true, nil
end

-- ============================================================================
-- 游戏结束
-- ============================================================================

--- 游戏结束处理
---@param winnerIndex number
---@param reason string "knockout" | "concede" | "deckout"
function GameFSM:_gameOver(winnerIndex, reason)
    self:setPhase(TurnPhase.GAME_OVER)

    local winner = self.players[winnerIndex]
    local reasonText = ({
        knockout = "击倒",
        concede  = "认输",
        deckout  = "牌库耗尽",
    })[reason] or reason

    self:addLog(string.format("游戏结束！%s 获胜（%s）", winner.heroName, reasonText))

    if self.callbacks.onGameOver then
        self.callbacks.onGameOver(winnerIndex, reason)
    end
end

--- 玩家认输
---@param playerIndex number
function GameFSM:concede(playerIndex)
    local winnerIndex = playerIndex == 1 and 2 or 1
    self:_gameOver(winnerIndex, "concede")
end

-- ============================================================================
-- 查询接口
-- ============================================================================

--- 获取当前可执行的所有合法行动
---@return table[] actions
function GameFSM:getAvailableActions()
    local phase = self:effectivePhase()
    return ActionValidator.getAvailableActions(
        self:currentPlayer(),
        self:opponent(),
        phase,
        self.combatChain
    )
end

--- 游戏是否结束
---@return boolean
function GameFSM:isGameOver()
    return self.phase == TurnPhase.GAME_OVER
end

--- 获取当前状态摘要（调试用）
---@return string
function GameFSM:debugSummary()
    local p1 = self.players[1]
    local p2 = self.players[2]
    local chainInfo = "无"
    if self.combatChain and not self.combatChain.closed then
        local s = self.combatChain:getSummary()
        chainInfo = string.format("%d 环节, 总伤 %d", s.linkCount, s.totalDamage)
    end

    return string.format(
        "回合 %d | 阶段: %s/%s | 行动方: %s\n" ..
        "连招链: %s\n\n" ..
        "--- 玩家1 ---\n%s\n" ..
        "--- 玩家2 ---\n%s",
        self.turnNumber,
        self.phase,
        self.chainSubPhase or "-",
        self:currentPlayer().heroName,
        chainInfo,
        p1:debugSummary(),
        p2:debugSummary()
    )
end

return GameFSM

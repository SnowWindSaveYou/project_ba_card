-- ============================================================================
-- Controller/PlayerInput.lua - 玩家输入处理
-- 职责：等待/退出输入状态、拖拽出牌/充能提交、防御队列管理
-- ============================================================================

local CardData       = require("Card.CardData")
local CardDB         = require("Card.CardDB")
local CardAnimator   = require("Anim.CardAnimator")
local TurnPhase      = require("Game.TurnPhase")
local Timer          = require("Core.Timer")
local ActionBar      = require("UI.ActionBar")
local DefensePanel   = require("UI.DefensePanel")
local CombatLog      = require("UI.CombatLog")

local PlayerInput = {}

-- ============================================================================
-- 等待输入状态管理
-- ============================================================================

--- 进入等待玩家输入状态
---@param gc table GameController
---@param phase string
function PlayerInput.enter(gc, phase)
    print(string.format("[PI-enter] phase=%s", phase))
    gc._waitingForInput = true
    gc._inputPhase = phase

    -- 构建 ActionBar 按钮并显示
    local ActionBarBuilder = require("Controller.ActionBarBuilder")
    local buttons, hint = ActionBarBuilder.build(gc, phase)
    print(string.format("[PI-enter] ActionBar.show  buttons=%d", #buttons))
    ActionBar.show(buttons, hint)

    -- 启用卡牌拖拽
    if gc._cardPicker then
        gc._cardPicker.enabled = true
    end

    -- 防御阶段：清空队列 + 显示 DefensePanel
    if phase == TurnPhase.CHAIN_DEFEND then
        gc._defenseQueue = {}
        gc._defenseEquips = {}
        local chain = gc.fsm.combatChain
        local link = chain and chain.current
        local atkName = "攻击"
        local atkPower = 0
        if link then
            atkName = link.attackCard and link.attackCard.name or "架势"
            atkPower = link.attackPower or 0
        end
        DefensePanel.show(atkName, atkPower)
    else
        DefensePanel.hide()
    end
end

--- 退出等待输入状态
---@param gc table GameController
function PlayerInput.exit(gc)
    gc._waitingForInput = false
    gc._inputPhase = nil
    ActionBar.hide()
    DefensePanel.hide()
    gc._actionDelay = 0.6  -- AI 反应间隔
    -- 禁用拖拽，与 enter() 中的启用对称
    if gc._cardPicker then
        gc._cardPicker.enabled = false
    end
end

-- ============================================================================
-- 玩家出牌提交
-- ============================================================================

--- 提交玩家操作（由 main.lua 的拖拽/点击触发）
---@param gc table GameController
---@param action table { type=string, cardId=string?, ... }
---@return boolean ok
---@return string? reason
function PlayerInput.submitAction(gc, action)
    if not gc._waitingForInput then
        print("[GC] submitPlayerAction: not waiting for input")
        return false, "not_waiting"
    end

    -- 退出等待状态
    PlayerInput.exit(gc)

    -- 记住提交前的阶段
    local isDefenseAction = (action.type == "defend_card"
        or action.type == "defend_equip"
        or action.type == "declare_defense")

    -- 执行动作
    local ok, reason = gc.fsm:executeAction(action)

    local HUDSync = require("Controller.HUDSync")

    if ok then
        HUDSync.syncRemovedCards(gc, 1)
        HUDSync.syncRemovedCards(gc, 2)

        -- 防御确认成功后才清空队列（FSM 验证通过才清，避免失败时视觉错位）
        if action.type == "declare_defense" then
            gc._defenseQueue = {}
            gc._defenseEquips = {}
        end

        -- 预备区存牌成功提示
        if action.type == "to_arsenal" then
            local cardData = CardDB.get(action.cardId)
            local cardName = cardData and cardData.name or "?"
            CombatLog.system(string.format("存入预备区: %s", cardName))
        end

        -- 防御动作成功后，检查是否仍在防御阶段
        local newPhase = gc.fsm:effectivePhase()
        if isDefenseAction and newPhase == TurnPhase.CHAIN_DEFEND then
            PlayerInput._syncDefensePanel(gc)
            local actorIndex = gc:_getActorIndex(newPhase)
            if actorIndex == gc._playerIndex then
                PlayerInput.enter(gc, newPhase)
            end
        end
    else
        print(string.format("[GC] Player action failed: %s (%s)", action.type, reason or "?"))
        -- 失败后重新进入等待
        local phase = gc.fsm:effectivePhase()
        local actorIndex = gc:_getActorIndex(phase)
        if actorIndex == gc._playerIndex then
            PlayerInput.enter(gc, phase)
        end
        CombatLog.system("操作失败: " .. (reason or "未知"))
    end

    return ok, reason
end

--- 通过 Card3D 提交拖拽出牌
---@param gc table GameController
---@param card3d table Card3D 实例
---@return boolean
function PlayerInput.submitDragPlay(gc, card3d)
    local cardId = gc._card3DToCardId[card3d]
    if not cardId then
        print("[GC] submitDragPlay: card3d not mapped")
        return false
    end

    local phase = gc._inputPhase
    if not phase then return false end

    local cardData = CardDB.get(cardId)
    if not cardData then return false end

    local actionType
    if phase == TurnPhase.ACTION_PHASE or phase == TurnPhase.CHAIN_ATTACK then
        if cardData:isAttack() then
            actionType = "attack"
        elseif cardData.cardType == CardData.TYPE.SUPPORT then
            actionType = "support"
        elseif cardData:isArenaCard() then
            actionType = "arena"
        end
    elseif phase == TurnPhase.CHAIN_DEFEND then
        if cardData:canDefend() then
            actionType = "queue_defend"
        end
    elseif phase == TurnPhase.CHAIN_REACTION then
        if cardData.cardType == CardData.TYPE.CHASE then
            actionType = "chase"
        elseif cardData.cardType == CardData.TYPE.DODGE then
            actionType = "dodge"
        end
    elseif phase == TurnPhase.END_PHASE then
        local ActionValidator = require("Game.ActionValidator")
        local ok = ActionValidator.canPlaceToArsenal(
            gc.fsm.players[gc._playerIndex], cardId, phase)
        if ok then
            actionType = "to_arsenal"
        end
    end

    if not actionType then
        print("[GC] submitDragPlay: no valid action for card " .. cardId)
        return false
    end

    -- 防御队列：不提交 FSM，先累积
    if actionType == "queue_defend" then
        return PlayerInput._queueDefenseCard(gc, card3d, cardId)
    end

    local action = { type = actionType, cardId = cardId }
    return PlayerInput.submitAction(gc, action)
end

--- 通过 Card3D 提交拖拽充能（Pitch）
---@param gc table GameController
---@param card3d table Card3D 实例
---@return boolean
function PlayerInput.submitDragPitch(gc, card3d)
    if not gc._waitingForInput or not gc._inputPhase then
        print("[GC] submitDragPitch: not waiting for input")
        return false
    end

    local cardId = gc._card3DToCardId[card3d]
    if not cardId then
        print("[GC] submitDragPitch: card3d not mapped")
        return false
    end

    local cardData = CardDB.get(cardId)
    if not cardData or cardData.pitch <= 0 then
        print("[GC] submitDragPitch: card has no pitch value")
        return false
    end

    local player = gc.fsm.players[gc._playerIndex]

    local ok, reason = gc.fsm:_doPitch(player, cardId)

    if ok then
        local pitchVal = cardData.pitch
        CombatLog.system(string.format("充能: %s (+%d 体能)", cardData.name, pitchVal))

        gc._cardPicker:unregister(card3d)

        gc._cardIdToCard3D[cardId] = nil
        gc._card3DToCardId[card3d] = nil

        local fan = gc:_getHandFan(gc._playerIndex)
        fan:removeCard(card3d)

        -- 翻面 + 下沉动画
        if not card3d.faceUp then
            card3d:flip()
        end
        local startPos = card3d.node.worldPosition
        local targetPos = Vector3(startPos.x, startPos.y - 2.0, startPos.z)
        CardAnimator.playThrow(card3d, targetPos)
        Timer.after(0.5, function()
            card3d:destroy()
        end)

        Timer.after(0.3, function()
            fan:applyLayout(true)
        end)

        -- 同步 HUD 和 ActionBar
        local HUDSync = require("Controller.HUDSync")
        HUDSync.syncHUD(gc)

        local ActionBarBuilder = require("Controller.ActionBarBuilder")
        local phase = gc.fsm:effectivePhase()
        -- 同步 _inputPhase，确保后续出牌的阶段判断与 FSM 一致
        gc._inputPhase = phase
        local buttons, hint = ActionBarBuilder.build(gc, phase)
        ActionBar.show(buttons, hint)

        return true
    else
        print(string.format("[GC] Pitch failed: %s", reason or "?"))
        CombatLog.system("充能失败: " .. (reason or "未知"))
        return false
    end
end

-- ============================================================================
-- 防御队列管理
-- ============================================================================

--- 将一张手牌加入防御队列
---@param gc table GameController
---@param card3d table
---@param cardId string
---@return boolean
function PlayerInput._queueDefenseCard(gc, card3d, cardId)
    for _, id in ipairs(gc._defenseQueue) do
        if id == cardId then return false end
    end

    gc._defenseQueue[#gc._defenseQueue + 1] = cardId

    local fan = gc:_getHandFan(gc._playerIndex)
    fan:removeCard(card3d)
    gc._cardPicker:unregister(card3d)

    if not card3d.faceUp then
        card3d:flip()
    end

    local defPos = gc._zoneLayout:getNextChainPos()
    gc._zoneLayout:addCard("combatChain", card3d)
    local zl = gc._zoneLayout
    CardAnimator.playThrow(card3d, Vector3(defPos.x, defPos.y, defPos.z), function()
        -- 落地后重新居中整条战斗链
        zl:arrangeZone("combatChain")
    end)
    gc._cardPicker:registerDisplay(card3d)

    Timer.after(0.3, function()
        fan:applyLayout(true)
    end)

    PlayerInput._syncDefenseQueuePanel(gc)

    local ActionBarBuilder = require("Controller.ActionBarBuilder")
    local buttons, hint = ActionBarBuilder.build(gc, TurnPhase.CHAIN_DEFEND)
    ActionBar.show(buttons, hint)

    CombatLog.system(string.format("选择防御: %s", CardDB.get(cardId).name))
    return true
end

--- 同步防御队列面板显示
---@param gc table GameController
function PlayerInput._syncDefenseQueuePanel(gc)
    local totalDef = 0
    local defCards = {}
    for _, cardId in ipairs(gc._defenseQueue) do
        local cardData = CardDB.get(cardId)
        local def = cardData and cardData.defense or 0
        totalDef = totalDef + def
        defCards[#defCards + 1] = { name = cardData and cardData.name or "?", defense = def }
    end
    local defEquips = {}
    for _, slot in ipairs(gc._defenseEquips) do
        local defender = gc.fsm.players[gc._playerIndex]
        local eq = defender:getEquipment(slot)
        if eq then
            totalDef = totalDef + (eq.defense or 0)
            defEquips[#defEquips + 1] = { name = eq.data.name, defense = eq.defense or 0 }
        end
    end
    DefensePanel.updateDefense(totalDef, defCards, defEquips)
end

--- 取消防御队列：将已入队的手牌退回手牌扇面
---@param gc table GameController
function PlayerInput.cancelDefenseQueue(gc)
    local fan = gc:_getHandFan(gc._playerIndex)
    for _, cardId in ipairs(gc._defenseQueue) do
        local card3d = gc._cardIdToCard3D[cardId]
        if card3d then
            gc._zoneLayout:removeCard("combatChain", card3d)
            gc._cardPicker:unregisterDisplay(card3d)
            fan:addCard(card3d)
            gc._cardPicker:register(card3d)
        end
    end
    gc._defenseQueue = {}
    gc._defenseEquips = {}
    fan:applyLayout(true)
end

--- 同步 DefensePanel 数据（从 FSM link 中读取已提交的防御）
---@param gc table GameController
function PlayerInput._syncDefensePanel(gc)
    local chain = gc.fsm.combatChain
    if not chain or not chain.current then return end

    local link = chain.current
    local totalDef = 0
    local defCards = {}
    local defEquips = {}

    for _, def in ipairs(link.defendCards or {}) do
        local cardData = CardDB.get(def.cardId)
        local defVal = def.defense or (cardData and cardData.defense) or 0
        totalDef = totalDef + defVal
        defCards[#defCards + 1] = {
            name = cardData and cardData.name or "???",
            defense = defVal,
        }
    end

    for _, ed in ipairs(link.equipDefends or {}) do
        local defVal = ed.defense or 0
        totalDef = totalDef + defVal
        defEquips[#defEquips + 1] = {
            name = ed.name or "护具",
            defense = defVal,
        }
    end

    DefensePanel.updateDefense(totalDef, defCards, defEquips)
end

return PlayerInput

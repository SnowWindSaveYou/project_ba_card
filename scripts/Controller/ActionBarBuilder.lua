-- ============================================================================
-- Controller/ActionBarBuilder.lua - ActionBar 按钮构建与点击处理
-- 职责：根据阶段动态构建按钮列表、处理按钮点击回调
-- ============================================================================

local CardData   = require("Card.CardData")
local CardDB     = require("Card.CardDB")
local TurnPhase  = require("Game.TurnPhase")
local ActionBar  = require("UI.ActionBar")
local CombatLog  = require("UI.CombatLog")

local ActionBarBuilder = {}

-- ============================================================================
-- 按钮构建
-- ============================================================================

--- 根据当前阶段构建按钮列表
---@param gc table GameController
---@param phase string
---@return table[] buttons
---@return string hint
function ActionBarBuilder.build(gc, phase)
    local buttons = {}
    local hint = ""

    if phase == TurnPhase.ACTION_PHASE or phase == TurnPhase.CHAIN_ATTACK then
        -- 武器/护具操作已移至英雄区域直接点击，此处只保留结束行动
        buttons[#buttons + 1] = {
            label = "结束行动",
            actionType = "end_action",
        }

        hint = "拖拽手牌到出牌线攻击 | 点击英雄区使用武器/护具"

    elseif phase == TurnPhase.CHAIN_DEFEND then
        -- 护具防御按钮已移至英雄区域点击，此处只保留确认/跳过
        local hasQueued = #gc._defenseQueue > 0 or #gc._defenseEquips > 0
        if hasQueued then
            buttons[#buttons + 1] = {
                label = "确认防御",
                actionType = "confirm_defense",
            }
            buttons[#buttons + 1] = {
                label = "跳过防御",
                actionType = "skip_defense",
            }
            hint = "拖拽更多手牌 | 点击英雄护具 | 确认提交"
        else
            buttons[#buttons + 1] = {
                label = "跳过防御",
                actionType = "skip_defense",
            }
            hint = "拖拽手牌防御 | 点击英雄护具 | 跳过"
        end

    elseif phase == TurnPhase.CHAIN_REACTION then
        buttons[#buttons + 1] = {
            label = "跳过反应",
            actionType = "skip_reaction",
        }
        hint = "拖拽追击/闪避牌 | 点击跳过"

    elseif phase == TurnPhase.END_PHASE then
        local p = gc.fsm.players[gc._playerIndex]
        local arsenalFull = #p.arsenal >= 1
        local hasHand = #p.hand > 0

        buttons[#buttons + 1] = {
            label = "结束回合",
            actionType = "end_turn",
        }

        if arsenalFull then
            hint = "预备区已满 | 点击结束回合"
        elseif hasHand then
            hint = "拖拽手牌存入预备区 | 点击直接结束回合"
        else
            hint = "无手牌可存 | 点击结束回合"
        end
    end

    return buttons, hint
end

-- ============================================================================
-- 按钮点击回调
-- ============================================================================

--- ActionBar 按钮点击处理
---@param gc table GameController
---@param actionType string
function ActionBarBuilder.onClick(gc, actionType)
    if not gc._waitingForInput then return end

    local PlayerInput = require("Controller.PlayerInput")
    local action

    if actionType == "confirm_defense" then
        -- 值拷贝传给 FSM，清空操作延迟到 submitAction 成功后执行
        action = {
            type = "declare_defense",
            defCardIds    = { table.unpack(gc._defenseQueue) },
            defEquipSlots = { table.unpack(gc._defenseEquips) },
        }
    elseif actionType == "end_action" then
        action = { type = "end_action" }
    elseif actionType == "skip_defense" then
        if #gc._defenseQueue > 0 or #gc._defenseEquips > 0 then
            PlayerInput.cancelDefenseQueue(gc)
        end
        action = { type = "skip_defense" }
    elseif actionType == "skip_reaction" then
        action = { type = "skip_reaction" }
    elseif actionType == "end_turn" then
        action = { type = "end_turn" }
    else
        print("[GC] Unknown actionType: " .. tostring(actionType))
        return
    end

    PlayerInput.submitAction(gc, action)
end

return ActionBarBuilder

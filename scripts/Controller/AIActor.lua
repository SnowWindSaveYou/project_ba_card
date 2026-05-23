-- ============================================================================
-- Controller/AIActor.lua - AI 玩家行为控制器
-- 职责：思考延迟 → AI 决策 → 提交 action → 失败兜底
-- 未来 BossActor 可继承此类，覆写 _decideAction / 增加对话触发
-- ============================================================================

local AIPlayer  = require("AI.AIPlayer")
local TurnPhase = require("Game.TurnPhase")
local HUDSync   = require("Controller.HUDSync")

---@class AIActor
local AIActor = {}
AIActor.__index = AIActor

--- 创建 AI Actor
---@param opts? table { difficulty?: string, name?: string, thinkMin?: number, thinkMax?: number }
function AIActor.new(opts)
    opts = opts or {}
    local self = setmetatable({}, AIActor)

    self._ai = AIPlayer.new({
        difficulty = opts.difficulty or "normal",
        name       = opts.name or "OpponentAI",
    })

    -- 思考延迟配置（秒）
    self._thinkMin = opts.thinkMin or 0.6
    self._thinkMax = opts.thinkMax or 1.4

    -- 运行时状态
    self._active     = false
    self._thinking   = false
    self._thinkTimer = 0

    return self
end

--- 轮到此 Actor 行动
---@param gc table GameController
---@param phase string
function AIActor:onEnter(gc, phase)
    self._active   = true
    self._thinking = true
    self._thinkTimer = self._thinkMin + math.random() * (self._thinkMax - self._thinkMin)
end

--- 每帧推进思考计时器
---@param gc table GameController
---@param dt number
function AIActor:onUpdate(gc, dt)
    if not self._active then return end

    self._thinkTimer = self._thinkTimer - dt
    if self._thinkTimer <= 0 then
        self._thinking = false
        self:_executeAction(gc)
        self._active = false
    end
end

--- 退出行动状态
---@param gc table GameController
function AIActor:onExit(gc)
    self._active   = false
    self._thinking = false
end

--- AI 是否正在"思考"（用于 HUD 显示）
function AIActor:isThinking()
    return self._thinking
end

function AIActor:isActive()
    return self._active
end

--- 获取内部 AIPlayer 实例（供外部读取 difficulty 等配置）
function AIActor:getAIPlayer()
    return self._ai
end

-- ============================================================================
-- 内部：决策 + 提交
-- ============================================================================

--- 执行 AI 决策并提交
---@param gc table GameController
function AIActor:_executeAction(gc)
    if gc.fsm:isGameOver() then return end

    local phase  = gc.fsm:effectivePhase()
    local action = self:_decideAction(gc, phase)

    local ok, reason = gc.fsm:executeAction(action)

    if ok then
        HUDSync.syncRemovedCards(gc, 1)
        HUDSync.syncRemovedCards(gc, 2)
    else
        print(string.format("[AIActor] action failed: %s (%s)", action.type, reason or "?"))
        -- 兜底：使用安全动作
        local fallback = self:_getFallbackAction(phase)
        if fallback then
            gc.fsm:executeAction(fallback)
        end
        HUDSync.syncRemovedCards(gc, 1)
        HUDSync.syncRemovedCards(gc, 2)
    end

    -- 动作后设置短暂间隔
    gc._actionDelay = 0.3
end

--- AI 决策（子类可覆写实现 Boss 策略）
---@param gc table GameController
---@param phase string
---@return table action
function AIActor:_decideAction(gc, phase)
    local action = self._ai:decideAction(gc.fsm)
    if not action then
        action = self:_getFallbackAction(phase)
    end
    return action
end

--- 获取安全兜底动作
---@param phase string
---@return table?
function AIActor:_getFallbackAction(phase)
    if phase == TurnPhase.ACTION_PHASE or phase == TurnPhase.CHAIN_ATTACK then
        return { type = "end_action" }
    elseif phase == TurnPhase.END_PHASE then
        return { type = "end_turn" }
    elseif phase == TurnPhase.CHAIN_DEFEND then
        return { type = "skip_defense" }
    elseif phase == TurnPhase.CHAIN_REACTION then
        return { type = "skip_reaction" }
    end
    return nil
end

return AIActor

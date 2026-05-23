-- ============================================================================
-- Controller/HumanActor.lua - 人类玩家行为控制器
-- 职责：管理输入等待状态，将拖拽/点击操作转为 action 提交给 FSM
-- 槽位 1 恒定使用此 Actor
-- ============================================================================

local PlayerInput      = require("Controller.PlayerInput")
local ActionBarBuilder = require("Controller.ActionBarBuilder")

---@class HumanActor
local HumanActor = {}
HumanActor.__index = HumanActor

function HumanActor.new()
    return setmetatable({
        _gc = nil,  -- 绑定的 GameController，用于读 _waitingForInput
    }, HumanActor)
end

--- 轮到此 Actor 行动
---@param gc table GameController
---@param phase string
function HumanActor:onEnter(gc, phase)
    self._gc = gc
    PlayerInput.enter(gc, phase)
end

--- 每帧更新（人类玩家无需推进，等回调即可）
---@param gc table GameController
---@param dt number
function HumanActor:onUpdate(gc, dt)
    -- 人类输入由拖拽/点击回调驱动，无需轮询
end

--- 退出行动状态
---@param gc table GameController
function HumanActor:onExit(gc)
    PlayerInput.exit(gc)
end

--- 是否正在等待输入（直接读 gc._waitingForInput，与 PlayerInput.exit 自动同步）
function HumanActor:isActive()
    return self._gc ~= nil and self._gc._waitingForInput
end

--- 提交拖拽出牌
---@param gc table GameController
---@param card3d table
---@return boolean
function HumanActor:submitDragPlay(gc, card3d)
    return PlayerInput.submitDragPlay(gc, card3d)
end

--- 提交拖拽充能
---@param gc table GameController
---@param card3d table
---@return boolean
function HumanActor:submitDragPitch(gc, card3d)
    return PlayerInput.submitDragPitch(gc, card3d)
end

--- 提交按钮操作
---@param gc table GameController
---@param action table
---@return boolean, string?
function HumanActor:submitAction(gc, action)
    return PlayerInput.submitAction(gc, action)
end

return HumanActor

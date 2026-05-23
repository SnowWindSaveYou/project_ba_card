-- ============================================================================
-- UI/DefensePanel.lua - 防御阶段信息面板（墨甲武林风格 NanoVG）
-- 暗底面板 + 朱砂攻击 badge + 翡翠绿防御 badge
-- ============================================================================

local Theme        = require("UI.Theme")
local InputManager = require("Input.InputManager")

local DefensePanel = {}

-- ============================================================================
-- 状态
-- ============================================================================

local panelState = {
    visible     = false,
    attackName  = "",
    attackPower = 0,
    totalDef    = 0,
    defCards    = {},
    defEquips   = {},
    time        = 0,
}

-- ============================================================================
-- 控制 API
-- ============================================================================

function DefensePanel.show(attackName, attackPower)
    panelState.visible = true
    panelState.attackName = attackName or "攻击"
    panelState.attackPower = attackPower or 0
    panelState.totalDef = 0
    panelState.defCards = {}
    panelState.defEquips = {}
end

function DefensePanel.hide()
    panelState.visible = false
    panelState.defCards = {}
    panelState.defEquips = {}
end

function DefensePanel.updateDefense(totalDef, defCards, defEquips)
    panelState.totalDef = totalDef or 0
    panelState.defCards = defCards or {}
    panelState.defEquips = defEquips or {}
end

function DefensePanel.isVisible()
    return panelState.visible
end

--- 每帧输入处理（已禁用：由 BattleGrid 桌面动画替代）
---@param mx number NanoVG 逻辑坐标
---@param my number NanoVG 逻辑坐标
---@param w number 屏幕逻辑宽
---@param h number 屏幕逻辑高
function DefensePanel.update(mx, my, w, h)
    -- 已禁用
end

-- ============================================================================
-- 绘制
-- ============================================================================

--- 绘制（已禁用：由 BattleGrid 桌面动画替代）
function DefensePanel.draw(ctx, w, h, fontId, time)
end

return DefensePanel

-- ============================================================================
-- UI/PhaseBar.lua - 回合阶段进度条（墨甲武林风格）
-- 鎏金活跃节点 + 暗色底 + 金边连接线
-- ============================================================================

local Theme = require("UI.Theme")

local PhaseBar = {}

-- ============================================================================
-- 阶段定义
-- ============================================================================

PhaseBar.PHASES = {
    { id = "start",   label = "开始" },
    { id = "draw",    label = "抽牌" },
    { id = "action",  label = "行动" },
    { id = "chain",   label = "战斗链" },
    { id = "end",     label = "结束" },
}

-- ============================================================================
-- 状态
-- ============================================================================

local barState = {
    currentIndex = 1,
    animProgress = 1.0,
    targetIndex  = 1,

    -- 切换闪光
    flashTimer   = 0,       -- >0 时显示闪光
    flashIndex   = 0,       -- 闪光的节点索引
}

-- ============================================================================
-- 控制
-- ============================================================================

function PhaseBar.setPhase(index)
    barState.targetIndex = math.max(1, math.min(index, #PhaseBar.PHASES))
end

function PhaseBar.advance()
    barState.targetIndex = math.min(barState.targetIndex + 1, #PhaseBar.PHASES)
end

function PhaseBar.reset()
    barState.currentIndex = 1
    barState.targetIndex = 1
    barState.animProgress = 1.0
end

function PhaseBar.update(dt)
    if barState.currentIndex ~= barState.targetIndex then
        barState.animProgress = barState.animProgress + dt * 4
        if barState.animProgress >= 1.0 then
            barState.animProgress = 1.0
            barState.currentIndex = barState.targetIndex
            -- 触发闪光效果
            barState.flashTimer = 0.6
            barState.flashIndex = barState.currentIndex
        end
    end

    -- 闪光衰减
    if barState.flashTimer > 0 then
        barState.flashTimer = barState.flashTimer - dt
    end
end

function PhaseBar.getCurrentIndex()
    return barState.currentIndex
end

-- ============================================================================
-- 绘制
-- ============================================================================

function PhaseBar.draw(ctx, x, y, width, height, fontId, time)
    local phases = PhaseBar.PHASES
    local n = #phases
    local nodeR = 9
    local nodeSpacing = width / (n + 1)

    nvgFontFaceId(ctx, fontId)

    -- 连接线
    for i = 1, n - 1 do
        local x1 = x + i * nodeSpacing
        local x2 = x + (i + 1) * nodeSpacing
        local cy = y + height / 2

        nvgBeginPath(ctx)
        nvgMoveTo(ctx, x1 + nodeR + 2, cy)
        nvgLineTo(ctx, x2 - nodeR - 2, cy)

        if i < barState.currentIndex then
            nvgStrokeColor(ctx, Theme.rgba(Theme.BLUE, 120))
        else
            nvgStrokeColor(ctx, Theme.rgba(Theme.BLUE, 30))
        end
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)
    end

    -- 节点
    for i = 1, n do
        local cx = x + i * nodeSpacing
        local cy = y + height / 2
        local isCurrent = (i == barState.currentIndex)
        local isPast = (i < barState.currentIndex)

        if isCurrent then
            -- 切换闪光（短暂爆发白金光环）
            if barState.flashTimer > 0 and barState.flashIndex == i then
                local flashT = barState.flashTimer / 0.6  -- 1→0
                local flashR = nodeR * (3.5 + (1 - flashT) * 3.0)
                local flashAlpha = math.floor(flashT * flashT * 120)

                nvgBeginPath(ctx)
                nvgCircle(ctx, cx, cy, flashR)
                local flashGlow = nvgRadialGradient(ctx, cx, cy, nodeR, flashR,
                    nvgRGBA(240, 205, 120, flashAlpha),
                    nvgRGBA(240, 205, 120, 0))
                nvgFillPaint(ctx, flashGlow)
                nvgFill(ctx)
            end

            -- 鎏金脉冲外发光
            local pulse = 0.8 + 0.2 * math.sin(time * 3.5)
            local glowR = nodeR * 2.8 * pulse

            nvgBeginPath(ctx)
            nvgCircle(ctx, cx, cy, glowR)
            local glow = nvgRadialGradient(ctx, cx, cy, nodeR * 0.5, glowR,
                Theme.rgba(Theme.GOLD, 50), Theme.rgba(Theme.GOLD, 0))
            nvgFillPaint(ctx, glow)
            nvgFill(ctx)

            -- 鎏金实心
            nvgBeginPath(ctx)
            nvgCircle(ctx, cx, cy, nodeR)
            local grad = nvgLinearGradient(ctx, cx, cy - nodeR, cx, cy + nodeR,
                Theme.rgba(Theme.GOLD_BRIGHT, 255), Theme.rgba(Theme.GOLD, 255))
            nvgFillPaint(ctx, grad)
            nvgFill(ctx)

            -- 顶微光
            nvgBeginPath(ctx)
            nvgEllipse(ctx, cx, cy - nodeR * 0.3, nodeR * 0.5, nodeR * 0.3)
            nvgFillColor(ctx, nvgRGBA(255, 255, 255, 40))
            nvgFill(ctx)

            -- 金描边
            nvgBeginPath(ctx)
            nvgCircle(ctx, cx, cy, nodeR)
            nvgStrokeColor(ctx, Theme.rgba(Theme.GOLD_BRIGHT, 120))
            nvgStrokeWidth(ctx, 1.5)
            nvgStroke(ctx)
        elseif isPast then
            -- 已过阶段（蔚蓝填充）
            nvgBeginPath(ctx)
            nvgCircle(ctx, cx, cy, nodeR - 1)
            local grad = nvgLinearGradient(ctx, cx, cy - nodeR, cx, cy + nodeR,
                Theme.rgba(Theme.BLUE, 180), Theme.rgba(Theme.BLUE, 140))
            nvgFillPaint(ctx, grad)
            nvgFill(ctx)
            -- 白色勾（√）
            nvgBeginPath(ctx)
            nvgCircle(ctx, cx, cy, nodeR - 1)
            nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 180))
            nvgStrokeWidth(ctx, 1)
            nvgStroke(ctx)
        else
            -- 未来阶段（白底蓝边空心）
            nvgBeginPath(ctx)
            nvgCircle(ctx, cx, cy, nodeR - 1)
            nvgFillColor(ctx, nvgRGBA(255, 255, 255, 220))
            nvgFill(ctx)
            nvgBeginPath(ctx)
            nvgCircle(ctx, cx, cy, nodeR - 1)
            nvgStrokeColor(ctx, Theme.rgba(Theme.BLUE, 60))
            nvgStrokeWidth(ctx, 1.5)
            nvgStroke(ctx)
        end

        -- 标签
        nvgFontSize(ctx, 10)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        if isCurrent then
            nvgFillColor(ctx, Theme.rgba(Theme.GOLD_BRIGHT, 255))
        elseif isPast then
            nvgFillColor(ctx, Theme.rgba(Theme.BLUE, 200))
        else
            nvgFillColor(ctx, Theme.rgba(Theme.TEXT_SECONDARY, 160))
        end
        nvgText(ctx, cx, cy + nodeR + 5, phases[i].label, nil)
    end
end

return PhaseBar

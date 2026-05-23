-- ============================================================================
-- UI/PhaseBanner.lua - 阶段切换标签（小型角落版）
-- Blue Archive 风格：亮白底 + 马卡龙主题色描边
-- 右上角药丸标签，快进快出，不遮挡桌面视野
-- ============================================================================

local Theme = require("UI.Theme")

local PhaseBanner = {}

-- ============================================================================
-- 配置
-- ============================================================================

local IN_DUR    = 0.12
local HOLD_DUR  = 0.85
local OUT_DUR   = 0.20
local TOTAL_DUR = IN_DUR + HOLD_DUR + OUT_DUR

local PILL_W  = 148
local PILL_H  = 26
local PILL_R  = 8
local MARGIN_R = 14
local MARGIN_T = 52   -- PhaseBar 下方

-- ============================================================================
-- 状态
-- ============================================================================

local state = {
    active    = false,
    elapsed   = 0,
    title     = "",
    colorType = "gold",
    alpha     = 0,
}

local queue = {}

-- ============================================================================
-- 缓动
-- ============================================================================

local function easeOut(t)
    return 1 - (1 - t) * (1 - t)
end

-- ============================================================================
-- 控制 API（保持与旧版签名兼容）
-- ============================================================================

---@param title string
---@param subtitle string|nil
---@param colorType string|nil "gold" | "green" | "red"
function PhaseBanner.show(title, subtitle, colorType)
    if state.active then
        table.insert(queue, { title = title, colorType = colorType or "gold" })
        return
    end
    state.active    = true
    state.elapsed   = 0
    state.title     = title or ""
    state.colorType = colorType or "gold"
    state.alpha     = 0
end

function PhaseBanner.showPhase(phaseName, subtitle)
    PhaseBanner.show(phaseName, subtitle, "gold")
end

function PhaseBanner.showTurn(isPlayerTurn)
    if isPlayerTurn then
        PhaseBanner.show("你的回合", nil, "green")
    else
        PhaseBanner.show("对手回合", nil, "red")
    end
end

function PhaseBanner.isActive()
    return state.active
end

-- ============================================================================
-- 更新
-- ============================================================================

function PhaseBanner.update(dt)
    if not state.active then
        if #queue > 0 then
            local nxt = table.remove(queue, 1)
            PhaseBanner.show(nxt.title, nil, nxt.colorType)
        end
        return
    end

    state.elapsed = state.elapsed + dt
    local t = state.elapsed
    if t < IN_DUR then
        state.alpha = easeOut(t / IN_DUR)
    elseif t < IN_DUR + HOLD_DUR then
        state.alpha = 1.0
    elseif t < TOTAL_DUR then
        local ft = (t - IN_DUR - HOLD_DUR) / OUT_DUR
        state.alpha = 1.0 - ft * ft
    else
        state.active = false
        state.alpha  = 0
    end
end

-- ============================================================================
-- 绘制
-- ============================================================================

function PhaseBanner.draw(ctx, w, h, fontId, time)
    if not state.active or state.alpha < 0.01 then return end

    local a  = state.alpha
    local ct = state.colorType

    -- 按主题选色
    local mainColor, dimColor
    if ct == "green" then
        mainColor = Theme.GREEN
        dimColor  = Theme.GREEN_DIM
    elseif ct == "red" then
        mainColor = Theme.RED
        dimColor  = Theme.RED_DIM
    else
        mainColor = Theme.GOLD
        dimColor  = Theme.GOLD_DIM
    end

    -- 药丸位置（右上角，随 alpha 从右侧微滑入）
    local slideOffset = PILL_W * 0.15 * (1.0 - a)
    local px = w - MARGIN_R - PILL_W + slideOffset
    local py = MARGIN_T

    local bgAlpha     = math.floor(a * 245)
    local borderAlpha = math.floor(a * 200)
    local textAlpha   = math.floor(a * 220)
    local accentAlpha = math.floor(a * 255)

    -- ---- 白色底板（带淡蓝色调，与 BG_BASE 一致）----
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, px, py, PILL_W, PILL_H, PILL_R)
    nvgFillColor(ctx, nvgRGBA(
        Theme.BG_PANEL.r, Theme.BG_PANEL.g, Theme.BG_PANEL.b, bgAlpha))
    nvgFill(ctx)

    -- ---- 主题色描边 ----
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, px, py, PILL_W, PILL_H, PILL_R)
    nvgStrokeColor(ctx, Theme.rgba(mainColor, borderAlpha))
    nvgStrokeWidth(ctx, 1.5)
    nvgStroke(ctx)

    -- ---- 左侧彩色竖条 ----
    local barW = 3
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, px + 1, py + 5, barW, PILL_H - 10, barW * 0.5)
    nvgFillColor(ctx, Theme.rgba(mainColor, accentAlpha))
    nvgFill(ctx)

    -- ---- 文字（深藏青，与主题 TEXT_PRIMARY 一致）----
    nvgFontFaceId(ctx, fontId)
    nvgFontSize(ctx, 12)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, Theme.rgba(Theme.TEXT_PRIMARY, textAlpha))
    nvgText(ctx, px + barW + 10, py + PILL_H * 0.5, state.title, nil)
end

return PhaseBanner

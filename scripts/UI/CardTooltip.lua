-- ============================================================================
-- UI/CardTooltip.lua - 卡牌悬停详情（墨甲武林风格）
-- 暗底面板 + 金色边框 + 朱砂/翡翠/鎏金 Pitch 色带
-- ============================================================================

local CardData = require("Card.CardData")
local Theme = require("UI.Theme")

local CardTooltip = {}

-- ============================================================================
-- 配置
-- ============================================================================

local TIP_WIDTH  = 185
local TIP_HEIGHT = 225
local TIP_MARGIN = 15
local TIP_CORNER = 14

-- Pitch 色带颜色（墨甲武林色调）
local PITCH_BAND = {
    [1] = Theme.RED,          -- 朱砂红
    [2] = Theme.GOLD,         -- 鎏金
    [3] = Theme.BLUE,         -- 信息蓝
}

-- 类型显示名
local TYPE_LABELS = {
    hero     = "英雄",
    weapon   = "武器",
    equipment = "装备",
    action   = "行动",
    attack   = "攻击行动",
    reaction = "反应",
    instant  = "瞬发",
}

-- ============================================================================
-- 状态
-- ============================================================================

local tooltipState = {
    visible  = false,
    cardData = nil,
    screenX  = 0,
    screenY  = 0,
    alpha    = 0,
}

-- ============================================================================
-- 控制
-- ============================================================================

function CardTooltip.show(cardData, sx, sy)
    tooltipState.visible = true
    tooltipState.cardData = cardData
    tooltipState.screenX = sx
    tooltipState.screenY = sy
end

function CardTooltip.hide()
    tooltipState.visible = false
    tooltipState.cardData = nil
end

function CardTooltip.update(dt)
    local target = tooltipState.visible and 1.0 or 0.0
    tooltipState.alpha = tooltipState.alpha + (target - tooltipState.alpha) * math.min(dt * 12, 1.0)
end

-- ============================================================================
-- 绘制
-- ============================================================================

function CardTooltip.draw(ctx, w, h, fontId)
    if tooltipState.alpha < 0.01 then return end
    local data = tooltipState.cardData
    if not data then return end

    local a = tooltipState.alpha
    local intA = math.floor(a * 255)

    -- 计算位置
    local tx = tooltipState.screenX + TIP_MARGIN
    local ty = tooltipState.screenY - TIP_HEIGHT / 2
    if tx + TIP_WIDTH > w - 10 then
        tx = tooltipState.screenX - TIP_WIDTH - TIP_MARGIN
    end
    if ty < 10 then ty = 10 end
    if ty + TIP_HEIGHT > h - 10 then ty = h - TIP_HEIGHT - 10 end

    nvgFontFaceId(ctx, fontId)
    nvgSave(ctx)
    nvgGlobalAlpha(ctx, a)

    -- 柔阴影
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, tx + 2, ty + 3, TIP_WIDTH, TIP_HEIGHT, TIP_CORNER)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, math.floor(50 * a)))
    nvgFill(ctx)

    -- 暗色底板
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, tx, ty, TIP_WIDTH, TIP_HEIGHT, TIP_CORNER)
    local bg = nvgLinearGradient(ctx, tx, ty, tx, ty + TIP_HEIGHT,
        nvgRGBA(32, 28, 38, intA), nvgRGBA(22, 18, 28, intA))
    nvgFillPaint(ctx, bg)
    nvgFill(ctx)

    -- 金色细边
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, tx, ty, TIP_WIDTH, TIP_HEIGHT, TIP_CORNER)
    nvgStrokeColor(ctx, Theme.rgba(Theme.GOLD_DIM, math.floor(60 * a)))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)

    -- Pitch 色带（顶部圆角条）
    local pitchColor = PITCH_BAND[data.pitch]
    if pitchColor then
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, tx, ty, TIP_WIDTH, 7, TIP_CORNER)
        nvgFillColor(ctx, Theme.rgba(pitchColor, intA))
        nvgFill(ctx)
    end

    local curY = ty + 18

    -- 卡名（暖白）
    nvgFontSize(ctx, 16)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(ctx, Theme.rgba(Theme.TEXT_PRIMARY, intA))
    nvgText(ctx, tx + TIP_WIDTH / 2, curY, data.name, nil)
    curY = curY + 24

    -- 类型（次文本色）
    local typeLabel = TYPE_LABELS[data.cardType] or data.cardType
    nvgFontSize(ctx, 11)
    nvgFillColor(ctx, Theme.rgba(Theme.TEXT_SECONDARY, intA))
    nvgText(ctx, tx + TIP_WIDTH / 2, curY, typeLabel, nil)
    curY = curY + 20

    -- 分隔线（暗金）
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, tx + 14, curY)
    nvgLineTo(ctx, tx + TIP_WIDTH - 14, curY)
    nvgStrokeColor(ctx, Theme.rgba(Theme.GOLD_DIM, math.floor(40 * a)))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)
    curY = curY + 10

    -- 属性区块（Pitch 色微妙渐变块）
    local illustH = 48
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, tx + 14, curY, TIP_WIDTH - 28, illustH, 8)
    local pc = pitchColor or Theme.TEXT_DIM
    local illGrad = nvgLinearGradient(ctx, tx + 14, curY, tx + 14, curY + illustH,
        Theme.rgba(pc, math.floor(30 * a)),
        Theme.rgba(pc, math.floor(10 * a)))
    nvgFillPaint(ctx, illGrad)
    nvgFill(ctx)

    -- 职业文字
    nvgFontSize(ctx, 12)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, Theme.rgba(Theme.TEXT_DIM, math.floor(100 * a)))
    nvgText(ctx, tx + TIP_WIDTH / 2, curY + illustH / 2, data.class or "", nil)
    curY = curY + illustH + 10

    -- 费用 / 攻击 / 防御
    nvgFontSize(ctx, 13)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    if (data.cost or 0) > 0 then
        nvgFillColor(ctx, Theme.rgba(Theme.TEXT_SECONDARY, intA))
        nvgText(ctx, tx + 14, curY, "费用: " .. data.cost, nil)
    end

    if (data.power or 0) > 0 then
        nvgFillColor(ctx, Theme.rgba(Theme.RED_BRIGHT, intA))
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgText(ctx, tx + TIP_WIDTH / 2, curY, "⚔ " .. data.power, nil)
    end

    if (data.defense or 0) > 0 then
        nvgFillColor(ctx, Theme.rgba(Theme.GREEN, intA))
        nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        nvgText(ctx, tx + TIP_WIDTH - 14, curY, "🛡 " .. data.defense, nil)
    end

    curY = curY + 20

    -- 效果文字
    if data.text and data.text ~= "" then
        nvgFontSize(ctx, 11)
        nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(ctx, Theme.rgba(Theme.TEXT_SECONDARY, intA))
        nvgTextBox(ctx, tx + 14, curY, TIP_WIDTH - 28, data.text, nil)
        curY = curY + 16
    end

    -- Go Again 标记（翡翠绿）
    if data.goAgain then
        nvgFontSize(ctx, 11)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(ctx, Theme.rgba(Theme.GREEN, intA))
        nvgText(ctx, tx + TIP_WIDTH / 2, curY, "★ Go Again", nil)
    end

    -- Pitch 值
    if (data.pitch or 0) > 0 then
        local pitchNames = { "红 (1)", "金 (2)", "蓝 (3)" }
        nvgFontSize(ctx, 10)
        nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
        nvgFillColor(ctx, Theme.rgba(pc, intA))
        nvgText(ctx, tx + TIP_WIDTH - 10, ty + TIP_HEIGHT - 8, "Pitch: " .. (pitchNames[data.pitch] or "?"), nil)
    end

    nvgRestore(ctx)
end

return CardTooltip

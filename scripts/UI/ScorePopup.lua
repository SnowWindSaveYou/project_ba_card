-- ============================================================================
-- UI/ScorePopup.lua - 数字弹出动效（墨甲武林风格）
-- 朱砂红伤害 / 翡翠绿治疗 / 鎏金充能 / 信息蓝防御
-- ============================================================================

local Theme = require("UI.Theme")

local ScorePopup = {}

-- ============================================================================
-- 配置
-- ============================================================================

local POPUP_DURATION = 1.2
local POPUP_RISE     = 60
local POPUP_SCALE    = 1.5

-- 弹出类型配色（墨甲武林色调）
local POPUP_TYPES = {
    damage  = { r = Theme.RED.r,   g = Theme.RED.g,   b = Theme.RED.b,   prefix = "-" },
    defense = { r = Theme.GREEN.r, g = Theme.GREEN.g, b = Theme.GREEN.b, prefix = "🛡 " },
    heal    = { r = Theme.GREEN_BRIGHT.r, g = Theme.GREEN_BRIGHT.g, b = Theme.GREEN_BRIGHT.b, prefix = "+" },
    pitch   = { r = Theme.GOLD.r,  g = Theme.GOLD.g,  b = Theme.GOLD.b,  prefix = "" },
}

-- ============================================================================
-- 活跃弹出列表
-- ============================================================================

local activePopups = {}
local popupIdCounter = 0

-- ============================================================================
-- 创建弹出
-- ============================================================================

function ScorePopup.spawn(x, y, value, popupType)
    popupIdCounter = popupIdCounter + 1

    local pt = POPUP_TYPES[popupType] or POPUP_TYPES.damage

    local popup = {
        id      = popupIdCounter,
        x       = x + (math.random() - 0.5) * 20,
        y       = y,
        value   = value,
        type    = popupType,
        color   = pt,
        text    = pt.prefix .. tostring(value),
        elapsed = 0,
        alive   = true,
    }

    activePopups[#activePopups + 1] = popup
end

-- ============================================================================
-- 更新
-- ============================================================================

function ScorePopup.update(dt)
    local alive = {}
    for _, p in ipairs(activePopups) do
        p.elapsed = p.elapsed + dt
        if p.elapsed < POPUP_DURATION then
            alive[#alive + 1] = p
        end
    end
    activePopups = alive
end

-- ============================================================================
-- 绘制
-- ============================================================================

function ScorePopup.draw(ctx, fontId)
    if #activePopups == 0 then return end

    nvgFontFaceId(ctx, fontId)

    for _, p in ipairs(activePopups) do
        local t = p.elapsed / POPUP_DURATION

        local offsetY = -t * POPUP_RISE

        local scale
        if t < 0.15 then
            scale = 1.0 + (POPUP_SCALE - 1.0) * (t / 0.15)
        else
            scale = POPUP_SCALE - (POPUP_SCALE - 1.0) * ((t - 0.15) / 0.85)
        end

        local alpha
        if t < 0.5 then
            alpha = 255
        else
            alpha = math.floor(255 * (1.0 - (t - 0.5) / 0.5))
        end

        local px = p.x
        local py = p.y + offsetY

        nvgSave(ctx)

        -- 暗色阴影
        nvgFontSize(ctx, 22 * scale)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(0, 0, 0, math.floor(alpha * 0.4)))
        nvgText(ctx, px + 1, py + 2, p.text, nil)

        -- 正式文字
        nvgFillColor(ctx, nvgRGBA(p.color.r, p.color.g, p.color.b, alpha))
        nvgText(ctx, px, py, p.text, nil)

        nvgRestore(ctx)
    end
end

function ScorePopup.count()
    return #activePopups
end

function ScorePopup.clear()
    activePopups = {}
end

return ScorePopup

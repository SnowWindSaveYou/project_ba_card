-- ============================================================================
-- UI/CombatLog.lua - 战斗日志（墨甲武林风格）
-- 暗底面板 + 主题色日志条目
-- ============================================================================

local Theme = require("UI.Theme")

local CombatLog = {}

-- ============================================================================
-- 配置
-- ============================================================================

local MAX_ENTRIES = 20
local VISIBLE_ENTRIES = 6
local PANEL_WIDTH = 220
local LINE_HEIGHT = 16
local FADE_DURATION = 8.0

-- 日志类型配色（BA 亮色底）
local LOG_COLORS = {
    attack  = Theme.RED,           -- 珊瑚红
    defense = Theme.GREEN_DIM,     -- 深薄荷绿
    damage  = Theme.RED_DIM,       -- 深珊瑚（白底更清晰）
    heal    = Theme.GREEN_DIM,     -- 深薄荷
    phase   = Theme.BLUE,          -- 蔚蓝（替换鎏金）
    system  = Theme.TEXT_SECONDARY,-- 蓝灰
    pitch   = Theme.PURPLE,        -- 薰衣草紫（替换亮金）
}

-- ============================================================================
-- 日志队列
-- ============================================================================

local entries = {}
local entryIdCounter = 0

-- ============================================================================
-- 添加日志
-- ============================================================================

function CombatLog.add(text, logType)
    entryIdCounter = entryIdCounter + 1

    local entry = {
        id = entryIdCounter,
        text = text,
        type = logType or "system",
        time = 0,
        alpha = 1.0,
    }

    table.insert(entries, 1, entry)

    while #entries > MAX_ENTRIES do
        table.remove(entries)
    end
end

function CombatLog.attack(text) CombatLog.add(text, "attack") end
function CombatLog.defend(text) CombatLog.add(text, "defense") end
function CombatLog.damage(text) CombatLog.add(text, "damage") end
function CombatLog.heal(text)   CombatLog.add(text, "heal") end
function CombatLog.phase(text)  CombatLog.add(text, "phase") end
function CombatLog.system(text) CombatLog.add(text, "system") end

-- ============================================================================
-- 更新
-- ============================================================================

function CombatLog.update(dt)
    for _, e in ipairs(entries) do
        e.time = e.time + dt
        if e.time > FADE_DURATION * 0.6 then
            local fadeT = (e.time - FADE_DURATION * 0.6) / (FADE_DURATION * 0.4)
            e.alpha = math.max(0, 1.0 - fadeT)
        end
    end
end

-- ============================================================================
-- 绘制
-- ============================================================================

function CombatLog.draw(ctx, w, h, fontId)
    local visCount = math.min(#entries, VISIBLE_ENTRIES)
    if visCount == 0 then return end

    local panelH = visCount * LINE_HEIGHT + 18
    local px = w - PANEL_WIDTH - 12
    local py = h - panelH - 60

    nvgFontFaceId(ctx, fontId)

    -- 投影
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, px + 2, py + 4, PANEL_WIDTH, panelH, 10)
    nvgFillColor(ctx, nvgRGBA(100, 130, 200, 25))
    nvgFill(ctx)

    -- 白色半透明面板
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, px, py, PANEL_WIDTH, panelH, 10)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 210))
    nvgFill(ctx)

    -- 蓝色细边
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, px, py, PANEL_WIDTH, panelH, 10)
    nvgStrokeColor(ctx, Theme.rgba(Theme.BLUE, 35))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)

    -- 日志条目
    for i = 1, visCount do
        local entry = entries[i]
        if entry.alpha < 0.01 then break end

        local ey = py + 10 + (i - 1) * LINE_HEIGHT
        local alpha = math.floor(entry.alpha * 200)

        local color = LOG_COLORS[entry.type] or LOG_COLORS.system

        nvgFontSize(ctx, 11)
        nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(ctx, Theme.rgba(color, alpha))
        nvgText(ctx, px + 10, ey, entry.text, nil)
    end
end

function CombatLog.clear()
    entries = {}
end

return CombatLog

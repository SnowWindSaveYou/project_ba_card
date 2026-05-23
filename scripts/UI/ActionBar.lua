-- ============================================================================
-- UI/ActionBar.lua - 右侧操作面板（能量 + 计时 + 操作按钮）
-- 布局（从上到下）：
--   ① 回合计时器（圆形倒计时）
--   ② 能量水晶行（最多 10 颗）
--   ③ 操作按钮列表（结束行动 / 确认防御 / 跳过等）
-- ============================================================================

local Theme        = require("UI.Theme")
local SFX          = require("Audio.SFX")
local InputManager = require("Input.InputManager")

local ActionBar = {}

-- ============================================================================
-- 状态
-- ============================================================================

local barState = {
    visible   = false,
    buttons   = {},
    hovered   = 0,
    pressed   = 0,
    onAction  = nil,
    hintText  = "",
    time      = 0,

    -- 滑入动画
    slideProgress = 0,
    slideTarget   = 0,

    -- 能量（由外部每帧注入）
    energy    = 0,
    energyMax = 0,

    -- 回合计时器（秒）
    turnTime    = 0,     -- 当前剩余时间
    turnTimeMax = 60,    -- 最大时间（0 = 不显示）
    isPlayerTurn = false,
}

-- ============================================================================
-- 尺寸常量
-- ============================================================================
local PANEL_W   = 148      -- 面板总宽
local BTN_W     = 120
local BTN_H     = 38
local BTN_GAP   = 8
local PAD       = 14
local RADIUS    = 16       -- 面板圆角

-- ============================================================================
-- 按钮配色
-- ============================================================================
local function getButtonColor(actionType)
    if actionType == "end_action" or actionType == "end_turn" then
        return Theme.BLUE
    elseif actionType == "skip_defense" or actionType == "skip_reaction" then
        return Theme.TEXT_DIM
    elseif actionType == "confirm_defense" then
        return Theme.GREEN
    elseif actionType == "chase" then
        return Theme.ORANGE
    elseif actionType == "dodge" then
        return Theme.GREEN_DIM
    else
        return Theme.RED
    end
end

-- ============================================================================
-- 控制 API
-- ============================================================================

function ActionBar.show(buttons, hint)
    barState.visible = true
    barState.buttons = buttons or {}
    barState.hovered = 0
    barState.pressed = 0
    barState.hintText = hint or ""
    barState.slideTarget = 1
end

function ActionBar.hide()
    barState.slideTarget = 0
    barState.hovered = 0
    barState.pressed = 0
end

function ActionBar.setOnAction(fn)
    barState.onAction = fn
end

function ActionBar.isVisible()
    return barState.visible
end

--- 注入能量信息（由 HUDSync 每帧调用）
---@param energy number
---@param energyMax number
function ActionBar.setEnergy(energy, energyMax)
    barState.energy    = energy    or 0
    barState.energyMax = energyMax or 0
end

--- 注入计时器（由 GameController 每帧调用，seconds=0 则不显示）
---@param remaining number 剩余秒数
---@param total     number 回合总时长
---@param isPlayerTurn boolean
function ActionBar.setTimer(remaining, total, isPlayerTurn)
    barState.turnTime    = remaining   or 0
    barState.turnTimeMax = total       or 0
    barState.isPlayerTurn = isPlayerTurn or false
end

-- ============================================================================
-- 内部布局计算
-- ============================================================================

-- 根据当前状态计算面板总高（能量区 + 按钮区 + 计时区）
local function calcLayout(w, h)
    local n = #barState.buttons

    -- 计时器区高（若无计时，跳过）
    local timerH = barState.turnTimeMax > 0 and 70 or 0

    -- 能量区高（若无能量，跳过）
    local energyH = barState.energyMax > 0 and 44 or 0

    -- 按钮区高
    local btnAreaH = n > 0 and (n * BTN_H + (n - 1) * BTN_GAP + PAD) or 0

    -- 分隔线高（能量和按钮之间）
    local sepH = (energyH > 0 and btnAreaH > 0) and 1 or 0

    local totalH = PAD + timerH + energyH + sepH + btnAreaH + PAD

    -- 面板右侧锚点
    local panelX = w - PANEL_W - 10
    local panelY = (h - totalH) / 2

    return {
        panelX    = panelX,
        panelY    = panelY,
        panelW    = PANEL_W,
        panelH    = totalH,
        timerH    = timerH,
        energyH   = energyH,
        sepH      = sepH,
        btnAreaH  = btnAreaH,
        n         = n,
    }
end

-- ============================================================================
-- 输入处理
-- ============================================================================

function ActionBar.update(mx, my, w, h, mousePressed, dt)
    barState.time = barState.time + dt

    -- 滑入/滑出动画
    local speed = 6.0
    if barState.slideTarget > barState.slideProgress then
        barState.slideProgress = math.min(1.0, barState.slideProgress + dt * speed)
    elseif barState.slideTarget < barState.slideProgress then
        barState.slideProgress = math.max(0, barState.slideProgress - dt * speed)
        if barState.slideProgress <= 0.01 then
            barState.slideProgress = 0
            barState.visible = false
            barState.buttons = {}
            barState.hintText = ""
        end
    end

    -- 面板即使按钮为空，能量/计时器也要检测鼠标消费
    local layout = calcLayout(w, h)
    local t      = barState.slideProgress
    local eased  = 1 - (1 - t) * (1 - t) * (1 - t)
    local slideOffset = (1 - eased) * 80

    -- 面板右侧区域消费鼠标（防穿透）
    local pxOff = layout.panelX - slideOffset
    if mx >= pxOff then
        InputManager.consumeMouse()
    end

    if not barState.visible or barState.slideProgress < 0.01 then
        barState.hovered = 0
        return
    end

    local n = layout.n
    if n == 0 then
        barState.hovered = 0
        return
    end

    -- 按钮区起始 Y
    local btnStartY = layout.panelY + PAD + layout.timerH + layout.energyH + layout.sepH
    local btnX = layout.panelX - slideOffset + (PANEL_W - BTN_W) / 2

    barState.hovered = 0
    for i = 1, n do
        local bx = btnX
        local by = btnStartY + (i - 1) * (BTN_H + BTN_GAP)
        if mx >= bx and mx <= bx + BTN_W and my >= by and my <= by + BTN_H then
            local btn = barState.buttons[i]
            if btn and btn.enabled ~= false then
                barState.hovered = i
            end
        end
    end

    if mousePressed and barState.hovered > 0 then
        local btn = barState.buttons[barState.hovered]
        if btn and btn.enabled ~= false and barState.onAction then
            SFX.click()
            barState.onAction(btn.actionType)
        end
    end
end

-- ============================================================================
-- 绘制辅助
-- ============================================================================

local function drawDiamond(ctx, cx, cy, half)
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx, cy - half)
    nvgLineTo(ctx, cx + half, cy)
    nvgLineTo(ctx, cx, cy + half)
    nvgLineTo(ctx, cx - half, cy)
    nvgClosePath(ctx)
end

-- ============================================================================
-- 绘制
-- ============================================================================

function ActionBar.draw(ctx, w, h, fontId)
    -- 面板始终可见（含能量/计时），按钮在 visible=true 时出现
    local hasContent = barState.energyMax > 0 or barState.turnTimeMax > 0 or barState.visible

    -- 即使 visible=false 也需要显示能量/计时
    local showButtons = barState.visible and barState.slideProgress > 0.01

    if not hasContent then return end

    local layout = calcLayout(w, h)

    -- 当 visible=false 时面板只显示能量+计时（无按钮），高度重新计算
    if not showButtons then
        layout = calcLayout(w, h)
        layout.n = 0
        layout.btnAreaH = 0
        layout.sepH = 0
        layout.panelH = PAD + layout.timerH + layout.energyH + PAD
        layout.panelY = (h - layout.panelH) / 2
    end

    -- 按钮的滑入偏移
    local slideOffset = 0
    if showButtons then
        local t     = barState.slideProgress
        local eased = 1 - (1 - t) * (1 - t) * (1 - t)
        slideOffset = (1 - eased) * 80
    end

    local px = layout.panelX - slideOffset
    local py = layout.panelY
    local pw = layout.panelW
    local ph = layout.panelH

    nvgFontFaceId(ctx, fontId)
    nvgSave(ctx)

    -- 面板投影
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, px + 4, py + 6, pw, ph, RADIUS)
    nvgFillColor(ctx, nvgRGBA(80, 110, 180, 25))
    nvgFill(ctx)

    -- 白色主面板
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, px, py, pw, ph, RADIUS)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 235))
    nvgFill(ctx)

    -- 蓝色细边
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, px, py, pw, ph, RADIUS)
    nvgStrokeColor(ctx, Theme.rgba(Theme.BLUE, 45))
    nvgStrokeWidth(ctx, 1.5)
    nvgStroke(ctx)

    local curY = py + PAD

    -- -------------------------------------------------------------------------
    -- ① 回合计时器
    -- -------------------------------------------------------------------------
    if layout.timerH > 0 then
        local cx = px + pw / 2
        local cy = curY + 24
        local r  = 20
        local ratio = barState.turnTimeMax > 0
            and (barState.turnTime / barState.turnTimeMax) or 0
        ratio = math.max(0, math.min(1, ratio))

        -- 背景圆环
        nvgBeginPath(ctx)
        nvgArc(ctx, cx, cy, r, 0, math.pi * 2, 1)
        nvgStrokeColor(ctx, nvgRGBA(220, 228, 245, 120))
        nvgStrokeWidth(ctx, 5)
        nvgStroke(ctx)

        -- 进度圆弧（从顶部 -π/2 开始，顺时针）
        local arcColor = ratio > 0.35 and Theme.BLUE
            or (ratio > 0.15 and Theme.ORANGE or Theme.RED)
        if ratio > 0 then
            nvgBeginPath(ctx)
            nvgArc(ctx, cx, cy, r,
                -math.pi * 0.5,
                -math.pi * 0.5 + math.pi * 2 * ratio,
                1)
            nvgStrokeColor(ctx, Theme.rgba(arcColor, 220))
            nvgStrokeWidth(ctx, 5)
            nvgStroke(ctx)
        end

        -- 秒数文字
        local secs = math.ceil(barState.turnTime)
        nvgFontSize(ctx, 15)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, Theme.rgba(arcColor, 230))
        nvgText(ctx, cx, cy, tostring(secs), nil)

        -- "我方/对方回合" 小标签
        local label = barState.isPlayerTurn and "我方回合" or "对方回合"
        local labelColor = barState.isPlayerTurn and Theme.GREEN or Theme.RED
        nvgFontSize(ctx, 11)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(ctx, Theme.rgba(labelColor, 200))
        nvgText(ctx, cx, cy + r + 6, label, nil)

        curY = curY + layout.timerH
    end

    -- -------------------------------------------------------------------------
    -- ② 能量水晶行
    -- -------------------------------------------------------------------------
    if layout.energyH > 0 then
        local energy    = barState.energy
        local energyMax = barState.energyMax
        local maxShow   = math.min(energyMax, 10)

        -- "能量" 小标题
        nvgFontSize(ctx, 11)
        nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, Theme.rgba(Theme.TEXT_DIM, 160))
        nvgText(ctx, px + PAD - 2, curY + 10, "能量", nil)

        -- 数值
        nvgFontSize(ctx, 13)
        nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, Theme.rgba(Theme.BLUE, 210))
        nvgText(ctx, px + pw - PAD + 2, curY + 10, energy .. "/" .. energyMax, nil)

        -- 水晶菱形行
        local crystalH = 14
        local gap = math.min(22, math.floor((pw - PAD * 2) / maxShow))
        local totalCW = (maxShow - 1) * gap
        local startX = px + pw / 2 - totalCW / 2

        for i = 1, maxShow do
            local cx = startX + (i - 1) * gap
            local cy = curY + 30
            local full = i <= energy
            if full then
                -- 发光
                nvgBeginPath(ctx)
                nvgCircle(ctx, cx, cy, crystalH)
                local glow = nvgRadialGradient(ctx, cx, cy, 2, crystalH,
                    Theme.rgba(Theme.BLUE, 55), Theme.rgba(Theme.BLUE, 0))
                nvgFillPaint(ctx, glow)
                nvgFill(ctx)
                drawDiamond(ctx, cx, cy, crystalH * 0.52)
                nvgFillColor(ctx, Theme.rgba(Theme.BLUE, 235))
                nvgFill(ctx)
            else
                drawDiamond(ctx, cx, cy, crystalH * 0.52)
                nvgFillColor(ctx, Theme.rgba(Theme.TEXT_DIM, 55))
                nvgFill(ctx)
                drawDiamond(ctx, cx, cy, crystalH * 0.52)
                nvgStrokeColor(ctx, Theme.rgba(Theme.TEXT_DIM, 40))
                nvgStrokeWidth(ctx, 1)
                nvgStroke(ctx)
            end
        end

        curY = curY + layout.energyH
    end

    -- -------------------------------------------------------------------------
    -- 分隔线
    -- -------------------------------------------------------------------------
    if layout.sepH > 0 then
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, px + PAD, curY)
        nvgLineTo(ctx, px + pw - PAD, curY)
        nvgStrokeColor(ctx, Theme.rgba(Theme.BLUE, 25))
        nvgStrokeWidth(ctx, 1)
        nvgStroke(ctx)
        curY = curY + layout.sepH + PAD * 0.5
    end

    -- -------------------------------------------------------------------------
    -- ③ 操作按钮
    -- -------------------------------------------------------------------------
    if showButtons and layout.n > 0 then
        local btnX = px + (PANEL_W - BTN_W) / 2
        local slideAlpha = barState.slideProgress

        nvgGlobalAlpha(ctx, slideAlpha)

        for i = 1, layout.n do
            local btn = barState.buttons[i]
            local bx  = btnX
            local by  = curY + (i - 1) * (BTN_H + BTN_GAP)
            local color    = getButtonColor(btn.actionType)
            local r, g, b  = color.r, color.g, color.b
            local isHover  = (barState.hovered == i)
            local disabled = (btn.enabled == false)

            -- 阴影
            nvgBeginPath(ctx)
            nvgRoundedRect(ctx, bx + 2, by + 3, BTN_W, BTN_H, 10)
            nvgFillColor(ctx, nvgRGBA(0, 0, 0, disabled and 10 or 25))
            nvgFill(ctx)

            -- 按钮底色
            nvgBeginPath(ctx)
            nvgRoundedRect(ctx, bx, by, BTN_W, BTN_H, 10)
            if disabled then
                nvgFillColor(ctx, nvgRGBA(200, 208, 225, 80))
            elseif isHover then
                local grad = nvgLinearGradient(ctx, bx, by, bx, by + BTN_H,
                    nvgRGBA(r, g, b, 245),
                    nvgRGBA(math.max(0,r-30), math.max(0,g-30), math.max(0,b-30), 220))
                nvgFillPaint(ctx, grad)
                nvgFill(ctx)
                -- 外发光
                nvgBeginPath(ctx)
                nvgRoundedRect(ctx, bx - 3, by - 3, BTN_W + 6, BTN_H + 6, 13)
                local glow = nvgBoxGradient(ctx, bx, by, BTN_W, BTN_H, 10, 8,
                    nvgRGBA(r, g, b, 55), nvgRGBA(r, g, b, 0))
                nvgFillPaint(ctx, glow)
                nvgFill(ctx)
            else
                local grad = nvgLinearGradient(ctx, bx, by, bx, by + BTN_H,
                    nvgRGBA(r, g, b, 190),
                    nvgRGBA(math.max(0,r-25), math.max(0,g-25), math.max(0,b-25), 165))
                nvgFillPaint(ctx, grad)
                nvgFill(ctx)
            end

            -- 顶微光
            if not disabled then
                nvgBeginPath(ctx)
                nvgRoundedRect(ctx, bx + 3, by + 2, BTN_W - 6, BTN_H * 0.38, 8)
                nvgFillColor(ctx, nvgRGBA(255, 255, 255, isHover and 45 or 22))
                nvgFill(ctx)
            end

            -- 边框
            nvgBeginPath(ctx)
            nvgRoundedRect(ctx, bx, by, BTN_W, BTN_H, 10)
            if disabled then
                nvgStrokeColor(ctx, nvgRGBA(180, 192, 215, 70))
            else
                nvgStrokeColor(ctx, nvgRGBA(r, g, b, isHover and 180 or 75))
            end
            nvgStrokeWidth(ctx, isHover and 1.5 or 1)
            nvgStroke(ctx)

            -- 文字
            nvgFontSize(ctx, 15)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            if disabled then
                nvgFillColor(ctx, Theme.rgba(Theme.TEXT_DIM, 100))
            else
                nvgFillColor(ctx, nvgRGBA(255, 255, 255, isHover and 255 or 230))
            end
            nvgText(ctx, bx + BTN_W / 2, by + BTN_H / 2, btn.label, nil)
        end

        nvgGlobalAlpha(ctx, 1.0)

        -- 提示文字
        if barState.hintText and #barState.hintText > 0 then
            local hintY = curY + layout.n * BTN_H + (layout.n - 1) * BTN_GAP + 10
            local alpha = math.floor(130 + 55 * math.sin(barState.time * 2.5))
            nvgFontSize(ctx, 11)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(ctx, Theme.rgba(Theme.BLUE, alpha))
            local maxW = pw - PAD * 2
            nvgText(ctx, px + pw / 2, hintY, barState.hintText, nil)
        end
    end

    nvgRestore(ctx)
end

return ActionBar

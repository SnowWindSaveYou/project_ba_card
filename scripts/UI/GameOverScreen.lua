-- ============================================================================
-- UI/GameOverScreen.lua - 游戏结束画面（墨甲武林风格 NanoVG）
-- 暗幕渐入 + 翡翠绿胜利 / 朱砂红败北 + 鎏金战绩 + "再来一局" 按钮
-- ============================================================================

local Theme        = require("UI.Theme")
local SFX          = require("Audio.SFX")
local InputManager = require("Input.InputManager")

local GameOverScreen = {}

-- ============================================================================
-- 状态
-- ============================================================================

local screenState = {
    visible     = false,
    fadeIn      = 0,
    time        = 0,
    showTime    = 0,

    playerWon   = false,
    winnerName  = "",
    reason      = "",
    turnCount   = 0,
    playerLife  = 0,
    oppLife     = 0,

    btnHovered  = false,
}

local btnRect = { x = 0, y = 0, w = 0, h = 0 }
local onRestart = nil

-- ============================================================================
-- 控制 API
-- ============================================================================

function GameOverScreen.show(data)
    screenState.visible = true
    screenState.fadeIn = 0
    screenState.showTime = screenState.time
    screenState.playerWon   = data.playerWon or false
    screenState.winnerName  = data.winnerName or ""
    screenState.reason      = data.reason or ""
    screenState.turnCount   = data.turnCount or 0
    screenState.playerLife  = data.playerLife or 0
    screenState.oppLife     = data.oppLife or 0
    screenState.btnHovered  = false
end

function GameOverScreen.hide()
    screenState.visible = false
end

function GameOverScreen.isVisible()
    return screenState.visible
end

function GameOverScreen.setOnRestart(fn)
    onRestart = fn
end

function GameOverScreen.update(mx, my, w, h, mousePressed, dt)
    if not screenState.visible then return end

    -- 全屏遮罩，整个屏幕消费鼠标
    InputManager.consumeMouse()

    screenState.fadeIn = math.min(1.0, screenState.fadeIn + dt * 1.5)

    local bx, by, bw, bh = btnRect.x, btnRect.y, btnRect.w, btnRect.h
    screenState.btnHovered = (mx >= bx and mx <= bx + bw and my >= by and my <= by + bh)

    if screenState.fadeIn >= 1.0 and screenState.btnHovered and mousePressed then
        if onRestart then
            SFX.click()
            onRestart()
        end
    end
end

-- ============================================================================
-- 绘制
-- ============================================================================

function GameOverScreen.draw(ctx, w, h, fontId, time)
    if not screenState.visible then return end

    screenState.time = time
    local fade = screenState.fadeIn
    local t = time

    nvgFontFaceId(ctx, fontId)

    -- ============================================
    -- 全屏暗色遮罩
    -- ============================================
    local overlayAlpha = math.floor(fade * 200)
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, w, h)
    nvgFillColor(ctx, nvgRGBA(8, 6, 10, overlayAlpha))
    nvgFill(ctx)

    if fade < 0.3 then return end
    local contentAlpha = math.min(1.0, (fade - 0.3) / 0.7)
    local ca = math.floor(contentAlpha * 255)

    -- ============================================
    -- 中央面板（暗底 + 金边）
    -- ============================================
    local panelW = math.min(360, w * 0.85)
    local panelH = 260
    local px = (w - panelW) / 2
    local py = (h - panelH) / 2 - 20

    -- 阴影
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, px + 4, py + 5, panelW, panelH, 22)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, math.floor(contentAlpha * 50)))
    nvgFill(ctx)

    -- 暗底
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, px, py, panelW, panelH, 22)
    local bgTop, bgBot
    if screenState.playerWon then
        bgTop = nvgRGBA(18, 30, 22, ca)
        bgBot = nvgRGBA(12, 20, 15, ca)
    else
        bgTop = nvgRGBA(35, 18, 20, ca)
        bgBot = nvgRGBA(22, 12, 14, ca)
    end
    local bg = nvgLinearGradient(ctx, px, py, px, py + panelH, bgTop, bgBot)
    nvgFillPaint(ctx, bg)
    nvgFill(ctx)

    -- 金边
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, px, py, panelW, panelH, 22)
    nvgStrokeColor(ctx, Theme.rgba(Theme.GOLD_DIM, math.floor(contentAlpha * 80)))
    nvgStrokeWidth(ctx, 1.5)
    nvgStroke(ctx)

    local cx = w / 2

    -- ============================================
    -- 胜负标题（呼吸发光）
    -- ============================================
    local titleY = py + 45
    local title = screenState.playerWon and "胜利!" or "败北..."
    local titlePulse = math.floor(ca * (0.85 + 0.15 * math.sin(t * 2.5)))

    nvgFontSize(ctx, 38)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    if screenState.playerWon then
        nvgFillColor(ctx, Theme.rgba(Theme.GREEN_BRIGHT, titlePulse))
    else
        nvgFillColor(ctx, Theme.rgba(Theme.RED_BRIGHT, titlePulse))
    end
    nvgText(ctx, cx, titleY, title, nil)

    -- ============================================
    -- 获胜者 + 原因
    -- ============================================
    local subY = titleY + 34
    nvgFontSize(ctx, 16)
    nvgFillColor(ctx, Theme.rgba(Theme.TEXT_SECONDARY, ca))
    local reasonMap = {
        knockout = "击倒",
        concede  = "认输",
        deckout  = "牌库耗尽",
    }
    local reasonCN = reasonMap[screenState.reason] or screenState.reason
    nvgText(ctx, cx, subY, screenState.winnerName .. " 获胜 — " .. reasonCN, nil)

    -- ============================================
    -- 战绩摘要（三栏横排）
    -- ============================================
    local statY = subY + 40
    local colW = panelW / 3

    drawStatColumn(ctx, px + colW * 0.5, statY, "回合", tostring(screenState.turnCount), ca)
    drawStatColumn(ctx, px + colW * 1.5, statY, "我方生命", tostring(screenState.playerLife), ca)
    drawStatColumn(ctx, px + colW * 2.5, statY, "对手生命", tostring(screenState.oppLife), ca)

    -- ============================================
    -- "再来一局" 按钮
    -- ============================================
    local btnW = 160
    local btnH = 44
    local bx = cx - btnW / 2
    local by = py + panelH - btnH - 24

    btnRect.x = bx
    btnRect.y = by
    btnRect.w = btnW
    btnRect.h = btnH

    local hovered = screenState.btnHovered and fade >= 1.0

    -- 按钮阴影
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, bx + 2, by + 3, btnW, btnH, btnH / 2)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, math.floor(contentAlpha * 30)))
    nvgFill(ctx)

    -- 按钮主体
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, bx, by, btnW, btnH, btnH / 2)
    local btnAlpha = hovered and ca or math.floor(ca * 0.85)
    local btnTop, btnBot
    if screenState.playerWon then
        btnTop = Theme.rgba(Theme.GREEN, btnAlpha)
        btnBot = Theme.rgba(Theme.GREEN_DIM, btnAlpha)
    else
        btnTop = Theme.rgba(Theme.RED, btnAlpha)
        btnBot = Theme.rgba(Theme.RED_DIM, btnAlpha)
    end
    local btnGrad = nvgLinearGradient(ctx, bx, by, bx, by + btnH, btnTop, btnBot)
    nvgFillPaint(ctx, btnGrad)
    nvgFill(ctx)

    -- 悬停发光
    if hovered then
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, bx - 4, by - 4, btnW + 8, btnH + 8, btnH / 2 + 4)
        local glowColor = screenState.playerWon and Theme.GREEN or Theme.RED
        local glow = nvgBoxGradient(ctx, bx, by, btnW, btnH, btnH / 2, 12,
            Theme.rgba(glowColor, 50), Theme.rgba(glowColor, 0))
        nvgFillPaint(ctx, glow)
        nvgFill(ctx)
    end

    -- 金边
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, bx, by, btnW, btnH, btnH / 2)
    nvgStrokeColor(ctx, Theme.rgba(Theme.GOLD_DIM, math.floor(contentAlpha * 60)))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)

    -- 按钮文字
    nvgFontSize(ctx, 18)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, Theme.rgba(Theme.TEXT_PRIMARY, ca))
    nvgText(ctx, cx, by + btnH / 2, "再来一局", nil)
end

-- ============================================================================
-- 辅助: 战绩数据列
-- ============================================================================

function drawStatColumn(ctx, cx, cy, label, value, alpha)
    -- 标签
    nvgFontSize(ctx, 12)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(ctx, Theme.rgba(Theme.TEXT_DIM, alpha))
    nvgText(ctx, cx, cy, label, nil)

    -- 数值
    nvgFontSize(ctx, 26)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(ctx, Theme.rgba(Theme.GOLD, alpha))
    nvgText(ctx, cx, cy + 6, value, nil)
end

return GameOverScreen

-- ============================================================================
-- UI/CoinFlip.lua - 先手后手抽取动画
-- 风格：Blue Archive 亮色系 + 卡牌对决感
-- 流程：
--   PHASE_ENTER   : 暗色幕布淡入 + 标题落下（0.55s）
--   PHASE_DEAL    : 双方英雄牌从左右飞入（0.50s）
--   PHASE_SPIN    : 中央硬币高速自旋（1.30s，加速+减速）
--   PHASE_LAND    : 硬币落到胜者侧，胜者牌金光发亮（0.55s）
--   PHASE_REVEAL  : 结果大字冲出（震动 + 弹性缩放）（0.70s）
--   PHASE_HOLD    : 静止展示（1.10s）
--   PHASE_EXIT    : 整体淡出（0.50s）
-- ============================================================================

local Theme = require("UI.Theme")

local CoinFlip = {}

-- ============================================================================
-- 阶段常量
-- ============================================================================
local PHASE_IDLE   = 0
local PHASE_ENTER  = 1
local PHASE_DEAL   = 2
local PHASE_SPIN   = 3
local PHASE_LAND   = 4
local PHASE_REVEAL = 5
local PHASE_HOLD   = 6
local PHASE_EXIT   = 7

-- 阶段名称 → DUR 键的映射
local PHASE_DUR_KEY = {
    [PHASE_ENTER]  = "enter",
    [PHASE_DEAL]   = "deal",
    [PHASE_SPIN]   = "spin",
    [PHASE_LAND]   = "land",
    [PHASE_REVEAL] = "reveal",
    [PHASE_HOLD]   = "hold",
    [PHASE_EXIT]   = "exit",
}

-- ============================================================================
-- 时长配置
-- ============================================================================
local DUR = {
    enter  = 0.55,
    deal   = 0.50,
    spin   = 1.30,
    land   = 0.55,
    reveal = 0.70,
    hold   = 1.10,
    exit   = 0.50,
}

-- ============================================================================
-- 缓动函数
-- ============================================================================
local function easeOutCubic(t)
    local t1 = 1 - t
    return 1 - t1 * t1 * t1
end

local function easeOutBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

local function easeOutElastic(t)
    if t == 0 then return 0 end
    if t == 1 then return 1 end
    local c4 = (2 * math.pi) / 3
    return 2 ^ (-10 * t) * math.sin((t * 10 - 0.75) * c4) + 1
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function clamp01(t)
    return math.max(0, math.min(1, t))
end

-- ============================================================================
-- 英雄图片路径映射（最新版本；路径相对于资源根）
-- ============================================================================
local HERO_PORTRAITS = {
    kaede    = "image/hero_kaede_v6_20260523021216.png",
    xia_lin  = "image/hero_xia_lin_v4_20260522195334.png",
    yun_rou  = "image/hero_yun_rou_v8a_20260523022637.png",
    xiao_tao = "image/hero_xiao_tao_v4_20260522194257.png",
}

local HERO_NAMES = {
    kaede    = "一之濑枫",
    xia_lin  = "夏琳",
    yun_rou  = "云柔",
    xiao_tao = "铁拳小桃",
}

-- ============================================================================
-- 内部状态
-- ============================================================================
local state = {
    phase        = PHASE_IDLE,
    elapsed      = 0,
    masterAlpha  = 0,

    playerHero   = "kaede",
    opponentHero = "yun_rou",
    winner       = 1,         -- 1=玩家先手  2=对手先手

    -- NVG 图片句柄（draw 首次调用时懒加载）
    playerImgHandle   = -1,
    opponentImgHandle = -1,
    imgLoaded         = false,

    -- 硬币自旋
    coinAngle = 0,

    -- 完成回调
    onComplete = nil,
}

-- ============================================================================
-- 对外 API
-- ============================================================================

--- 显示先手抽取动画
---@param playerHero  string  玩家英雄 key
---@param opponentHero string 对手英雄 key
---@param winner number 1=玩家先手 2=对手先手
---@param onComplete  function|nil 动画结束回调
function CoinFlip.show(playerHero, opponentHero, winner, onComplete)
    state.phase        = PHASE_ENTER
    state.elapsed      = 0
    state.playerHero   = playerHero  or "kaede"
    state.opponentHero = opponentHero or "yun_rou"
    state.winner       = winner or 1
    state.coinAngle    = 0
    state.onComplete   = onComplete
    -- 图片句柄需要 NVG context，在 draw 时懒加载
    state.imgLoaded    = false
    state.playerImgHandle   = -1
    state.opponentImgHandle = -1
end

--- 是否正在播放
function CoinFlip.isActive()
    return state.phase ~= PHASE_IDLE
end

--- 跳过（直接触发回调）
function CoinFlip.skip()
    if state.phase == PHASE_IDLE then return end
    state.phase = PHASE_IDLE
    if state.onComplete then
        state.onComplete()
        state.onComplete = nil
    end
end

-- ============================================================================
-- 更新（每帧，在 GameController:update 中调用）
-- ============================================================================

function CoinFlip.update(dt)
    if state.phase == PHASE_IDLE then return end

    state.elapsed = state.elapsed + dt

    -- 硬币旋转更新
    if state.phase == PHASE_SPIN then
        local t = clamp01(state.elapsed / DUR.spin)
        local spinRate
        if t < 0.35 then
            spinRate = lerp(4, 20, t / 0.35)
        elseif t < 0.75 then
            spinRate = 20
        else
            spinRate = lerp(20, 1.5, (t - 0.75) / 0.25)
        end
        state.coinAngle = state.coinAngle + spinRate * dt * 360
    elseif state.phase == PHASE_LAND then
        local t = clamp01(state.elapsed / DUR.land)
        if t < 0.45 then
            state.coinAngle = state.coinAngle + 1.5 * dt * 360
        end
    end

    -- 阶段推进
    local durKey = PHASE_DUR_KEY[state.phase]
    if durKey and state.elapsed >= DUR[durKey] then
        state.elapsed = 0
        if state.phase == PHASE_ENTER then
            state.phase = PHASE_DEAL
        elseif state.phase == PHASE_DEAL then
            state.phase = PHASE_SPIN
        elseif state.phase == PHASE_SPIN then
            state.phase = PHASE_LAND
        elseif state.phase == PHASE_LAND then
            state.phase = PHASE_REVEAL
        elseif state.phase == PHASE_REVEAL then
            state.phase = PHASE_HOLD
        elseif state.phase == PHASE_HOLD then
            state.phase = PHASE_EXIT
        elseif state.phase == PHASE_EXIT then
            state.phase = PHASE_IDLE
            if state.onComplete then
                state.onComplete()
                state.onComplete = nil
            end
        end
    end
end

-- ============================================================================
-- 懒加载图片句柄
-- ============================================================================
local function ensureImages(ctx)
    if state.imgLoaded then return end
    state.imgLoaded = true
    local pPath = HERO_PORTRAITS[state.playerHero]   or HERO_PORTRAITS.kaede
    local oPath = HERO_PORTRAITS[state.opponentHero] or HERO_PORTRAITS.yun_rou
    state.playerImgHandle   = nvgCreateImage(ctx, pPath, 0) or -1
    state.opponentImgHandle = nvgCreateImage(ctx, oPath, 0) or -1
end

-- ============================================================================
-- 绘制辅助 - 英雄立绘卡片
-- ============================================================================
local function drawHeroCard(ctx, fontId, cx, cy, cardW, cardH,
                             imgHandle, heroName, label, labelColor,
                             alpha, isWinner, winT, time)
    if alpha < 0.01 then return end

    nvgSave(ctx)
    nvgTranslate(ctx, cx, cy)

    local hw = cardW * 0.5
    local hh = cardH * 0.5
    local r  = 12

    -- 阴影
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, -hw + 2, -hh + 8, cardW - 4, cardH + 4, r)
    nvgFillColor(ctx, nvgRGBA(20, 30, 70, math.floor(alpha * 100)))
    nvgFill(ctx)

    -- 卡片背景
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, -hw, -hh, cardW, cardH, r)
    nvgFillColor(ctx, nvgRGBA(238, 243, 255, math.floor(alpha * 255)))
    nvgFill(ctx)

    -- 英雄立绘
    if imgHandle and imgHandle > 0 then
        local iw, ih = nvgImageSize(ctx, imgHandle)
        if iw and iw > 0 and ih and ih > 0 then
            local imgAreaH = cardH * 0.80
            local scFit = math.max(cardW / iw, imgAreaH / ih)
            local dw = iw * scFit
            local dh = ih * scFit
            local ox = -dw * 0.5
            local oy = -hh + 2

            nvgSave(ctx)
            nvgScissor(ctx, -hw, -hh, cardW, imgAreaH)
            local imgPaint = nvgImagePattern(ctx, ox, oy, dw, dh, 0, imgHandle, alpha)
            nvgBeginPath(ctx)
            nvgRoundedRect(ctx, -hw, -hh, cardW, imgAreaH, r)
            nvgFillPaint(ctx, imgPaint)
            nvgFill(ctx)
            nvgResetScissor(ctx)
            nvgRestore(ctx)
        end
    end

    -- 底部信息栏渐变
    local infoH = cardH * 0.24
    local infoY = hh - infoH
    -- 渐变过渡
    nvgBeginPath(ctx)
    nvgRect(ctx, -hw, infoY - 18, cardW, 18)
    local fadeGrad = nvgLinearGradient(ctx, 0, infoY - 18, 0, infoY,
        nvgRGBA(240, 244, 255, 0),
        nvgRGBA(240, 244, 255, math.floor(alpha * 240)))
    nvgFillPaint(ctx, fadeGrad)
    nvgFill(ctx)
    -- 信息栏底色
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, -hw, infoY, cardW, infoH, r)
    nvgFillColor(ctx, nvgRGBA(240, 244, 255, math.floor(alpha * 248)))
    nvgFill(ctx)

    -- 英雄名
    nvgFontFaceId(ctx, fontId)
    nvgFontSize(ctx, 14)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(45, 53, 97, math.floor(alpha * 255)))
    nvgText(ctx, 0, infoY + infoH * 0.34, heroName, nil)

    -- 先手/后手标签胶囊
    if label and #label > 0 then
        local tagW, tagH = 54, 18
        local tagCY = infoY + infoH * 0.73
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, -tagW * 0.5, tagCY - tagH * 0.5, tagW, tagH, tagH * 0.5)
        nvgFillColor(ctx, nvgRGBA(
            labelColor.r, labelColor.g, labelColor.b, math.floor(alpha * 210)))
        nvgFill(ctx)
        nvgFontSize(ctx, 11)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, math.floor(alpha * 255)))
        nvgText(ctx, 0, tagCY, label, nil)
    end

    -- 胜者金边光效
    if isWinner == true and winT and winT > 0 then
        local gAlpha = math.floor(winT * alpha * 220)
        local pulse  = 1.0 + 0.05 * math.sin(time * 5.5)
        -- 内框
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, -hw * pulse, -hh * pulse,
            cardW * pulse, cardH * pulse, r)
        nvgStrokeColor(ctx, nvgRGBA(
            Theme.GOLD.r, Theme.GOLD.g, Theme.GOLD.b, gAlpha))
        nvgStrokeWidth(ctx, 3)
        nvgStroke(ctx)
        -- 外发光
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, -hw * pulse - 7, -hh * pulse - 7,
            cardW * pulse + 14, cardH * pulse + 14, r + 7)
        nvgStrokeColor(ctx, nvgRGBA(
            Theme.GOLD.r, Theme.GOLD.g, Theme.GOLD.b, math.floor(gAlpha * 0.30)))
        nvgStrokeWidth(ctx, 10)
        nvgStroke(ctx)
    end

    -- 败者暗化遮罩
    if isWinner == false and winT and winT > 0 then
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, -hw, -hh, cardW, cardH, r)
        nvgFillColor(ctx, nvgRGBA(20, 30, 70, math.floor(winT * alpha * 130)))
        nvgFill(ctx)
    end

    nvgRestore(ctx)
end

-- ============================================================================
-- 绘制辅助 - 中央硬币（透视翻转模拟）
-- ============================================================================
local function drawCoin(ctx, cx, cy, radius, angle, alpha, zScale)
    if alpha < 0.01 then return end
    zScale = zScale or 1.0

    local cosA   = math.cos(math.rad(angle))
    local scaleX = math.abs(cosA)
    local isTails = cosA < 0   -- 反面="后"

    nvgSave(ctx)
    nvgTranslate(ctx, cx, cy)
    nvgScale(ctx, scaleX * zScale, zScale)

    local r = radius
    local a = math.floor(alpha * 255)

    -- 阴影
    nvgBeginPath(ctx)
    nvgCircle(ctx, 2, 5, r + 3)
    nvgFillColor(ctx, nvgRGBA(20, 30, 80, math.floor(alpha * 55)))
    nvgFill(ctx)

    -- 硬币底色
    local cr, cg, cb
    if isTails then
        cr, cg, cb = Theme.RED.r, Theme.RED.g, Theme.RED.b
    else
        cr, cg, cb = Theme.GOLD.r, Theme.GOLD.g, Theme.GOLD.b
    end
    nvgBeginPath(ctx)
    nvgCircle(ctx, 0, 0, r)
    nvgFillColor(ctx, nvgRGBA(cr, cg, cb, a))
    nvgFill(ctx)

    -- 内圈纹理（同心圆装饰）
    nvgBeginPath(ctx)
    nvgCircle(ctx, 0, 0, r * 0.72)
    nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, math.floor(alpha * 50)))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)

    -- 高光
    nvgBeginPath(ctx)
    nvgCircle(ctx, 0, 0, r)
    local hlPaint = nvgRadialGradient(ctx, -r * 0.22, -r * 0.28, r * 0.08, r,
        nvgRGBA(255, 255, 255, math.floor(alpha * 140)),
        nvgRGBA(255, 255, 255, 0))
    nvgFillPaint(ctx, hlPaint)
    nvgFill(ctx)

    -- 边框
    nvgBeginPath(ctx)
    nvgCircle(ctx, 0, 0, r)
    nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, math.floor(alpha * 170)))
    nvgStrokeWidth(ctx, 2)
    nvgStroke(ctx)

    -- 中央汉字（"先"/"后"）
    nvgFontSize(ctx, r * 0.62)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, math.floor(alpha * 230)))
    nvgText(ctx, 0, 0, isTails and "后" or "先", nil)

    nvgRestore(ctx)
end

-- ============================================================================
-- 主绘制（在 HandleNanoVGRender 最后调用）
-- ============================================================================

function CoinFlip.draw(ctx, w, h, fontId, time)
    if state.phase == PHASE_IDLE then return end

    -- 懒加载图片
    ensureImages(ctx)

    local phase = state.phase
    local durKey = PHASE_DUR_KEY[phase] or "enter"
    local t = clamp01(state.elapsed / DUR[durKey])

    -- ---- 整体透明度 ----
    local masterAlpha
    if phase == PHASE_ENTER then
        masterAlpha = easeOutCubic(t)
    elseif phase == PHASE_EXIT then
        masterAlpha = 1.0 - easeOutCubic(t)
    else
        masterAlpha = 1.0
    end
    if masterAlpha < 0.005 then return end

    -- ============================================
    -- 1. 半透明白雾幕布 + 亮色面板
    -- ============================================
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, w, h)
    -- BA 风格：浅蓝白雾覆盖，不压暗画面
    nvgFillColor(ctx, nvgRGBA(
        Theme.BG_BASE.r, Theme.BG_BASE.g, Theme.BG_BASE.b,
        math.floor(masterAlpha * 210)))
    nvgFill(ctx)

    local panelW = math.min(w * 0.86, 680)
    local panelH = h * 0.70
    local panelX = (w - panelW) * 0.5
    local panelY = (h - panelH) * 0.5 - h * 0.025

    -- 面板阴影
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, panelX + 3, panelY + 8, panelW, panelH, 22)
    nvgFillColor(ctx, nvgRGBA(
        Theme.TEXT_PRIMARY.r, Theme.TEXT_PRIMARY.g, Theme.TEXT_PRIMARY.b,
        math.floor(masterAlpha * 30)))
    nvgFill(ctx)

    -- 面板主体：白色
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, panelX, panelY, panelW, panelH, 22)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, math.floor(masterAlpha * 252)))
    nvgFill(ctx)

    -- 顶部蓝色装饰条
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, panelX, panelY, panelW, 6, 3)
    nvgFillColor(ctx, nvgRGBA(
        Theme.BLUE.r, Theme.BLUE.g, Theme.BLUE.b, math.floor(masterAlpha * 255)))
    nvgFill(ctx)

    -- 面板描边
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, panelX, panelY, panelW, panelH, 22)
    nvgStrokeColor(ctx, nvgRGBA(
        Theme.BLUE.r, Theme.BLUE.g, Theme.BLUE.b, math.floor(masterAlpha * 55)))
    nvgStrokeWidth(ctx, 1.5)
    nvgStroke(ctx)

    -- ============================================
    -- 2. 顶部标题 "— 决定先手 —"
    -- ============================================
    local cx   = w * 0.5
    local titleCY = panelY + panelH * 0.135

    -- 入场时从上方落下
    local dropT = (phase == PHASE_ENTER) and easeOutBack(t) or 1.0
    local titleY = lerp(panelY - 30, titleCY, dropT)

    -- 左右装饰线（蓝色细线）
    local lineLen = panelW * 0.28 * masterAlpha
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx - lineLen - 68, titleY)
    nvgLineTo(ctx, cx - 68, titleY)
    nvgStrokeColor(ctx, nvgRGBA(
        Theme.BLUE.r, Theme.BLUE.g, Theme.BLUE.b, math.floor(masterAlpha * 130)))
    nvgStrokeWidth(ctx, 1.5)
    nvgStroke(ctx)
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx + 68, titleY)
    nvgLineTo(ctx, cx + 68 + lineLen, titleY)
    nvgStroke(ctx)

    nvgFontFaceId(ctx, fontId)
    nvgFontSize(ctx, 20)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(
        Theme.TEXT_PRIMARY.r, Theme.TEXT_PRIMARY.g, Theme.TEXT_PRIMARY.b,
        math.floor(masterAlpha * 220)))
    nvgText(ctx, cx, titleY, "— 决定先手 —", nil)

    -- ============================================
    -- 3. 英雄牌
    -- ============================================
    local cardW  = panelW * 0.285
    local cardH  = cardW * 1.48
    local cardCY = panelY + panelH * 0.525

    -- 飞入进度
    local dealT = 0
    if phase == PHASE_DEAL then
        dealT = easeOutBack(t)
    elseif phase > PHASE_DEAL then
        dealT = 1.0
    end
    local cardAlpha = dealT * masterAlpha

    local pCX = cx - panelW * 0.265    -- 玩家侧（左）
    local oCX = cx + panelW * 0.265    -- 对手侧（右）

    local pCardX = lerp(panelX - cardW, pCX, dealT)
    local oCardX = lerp(panelX + panelW + cardW, oCX, dealT)

    -- 胜者上浮 + 光效
    local pWinT, oWinT   = 0, 0
    local pIsWinner, oIsWinner = nil, nil
    local pLift, oLift   = 0, 0

    if phase >= PHASE_LAND then
        local landT = (phase == PHASE_LAND) and easeOutCubic(t) or 1.0
        if state.winner == 1 then
            pWinT = landT
            pIsWinner = true
            oIsWinner = false
            pLift = -12 * landT
        else
            oWinT = landT
            pIsWinner = false
            oIsWinner = true
            oLift = -12 * landT
        end
    end

    -- 标签（REVEAL 后显示）
    local pLabel, oLabel = "", ""
    local pLabelColor = Theme.TEXT_DIM
    local oLabelColor = Theme.TEXT_DIM
    if phase >= PHASE_REVEAL then
        pLabel = (state.winner == 1) and "先攻" or "后攻"
        oLabel = (state.winner == 2) and "先攻" or "后攻"
        pLabelColor = (state.winner == 1) and Theme.GOLD or Theme.TEXT_SECONDARY
        oLabelColor = (state.winner == 2) and Theme.GOLD or Theme.TEXT_SECONDARY
    end

    drawHeroCard(ctx, fontId,
        pCardX, cardCY + pLift,
        cardW, cardH,
        state.playerImgHandle,
        HERO_NAMES[state.playerHero] or state.playerHero,
        pLabel, pLabelColor,
        cardAlpha, pIsWinner, pWinT, time)

    drawHeroCard(ctx, fontId,
        oCardX, cardCY + oLift,
        cardW, cardH,
        state.opponentImgHandle,
        HERO_NAMES[state.opponentHero] or state.opponentHero,
        oLabel, oLabelColor,
        cardAlpha, oIsWinner, oWinT, time)

    -- VS 分隔（DEAL ~ SPIN 阶段）
    if phase == PHASE_DEAL or phase == PHASE_SPIN then
        local vsAlpha = math.floor(masterAlpha * clamp01((dealT - 0.6) / 0.4) * 180)
        if vsAlpha > 2 then
            nvgFontFaceId(ctx, fontId)
            nvgFontSize(ctx, 26)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(
                Theme.TEXT_SECONDARY.r, Theme.TEXT_SECONDARY.g, Theme.TEXT_SECONDARY.b,
                vsAlpha))
            nvgText(ctx, cx, cardCY, "VS", nil)
        end
    end

    -- ============================================
    -- 4. 中央硬币
    -- ============================================
    local coinR  = math.min(panelW * 0.088, 42)
    local coinCX = cx
    local coinCY = cardCY       -- 初始位置：两张英雄卡中间
    local coinAlpha = 0
    local coinZScale = 1.0

    -- 抛物线弧顶（相对 cardCY 向上偏移）
    local spinPeakY = panelY + panelH * 0.10

    if phase == PHASE_DEAL then
        coinAlpha = masterAlpha * clamp01((t - 0.55) / 0.45)
        coinCY = cardCY
    elseif phase == PHASE_SPIN then
        coinAlpha = masterAlpha
        -- 抛物线：arcFrac 0→1→0（sin 曲线），最高点在 spinPeakY
        local arcFrac = math.sin(t * math.pi)
        coinCX    = cx
        coinCY    = lerp(cardCY, spinPeakY, arcFrac)
        coinZScale = lerp(0.60, 1.0, arcFrac)   -- 地面小、飞起大、落地小
    elseif phase == PHASE_LAND then
        -- 从 cardCY（已落回）飞向胜者牌顶
        local landT2 = easeOutCubic(t)
        local targetX = (state.winner == 1) and pCardX or oCardX
        local targetY = cardCY - cardH * 0.50
        coinCX = lerp(cx, targetX, landT2)
        coinCY = lerp(cardCY, targetY, landT2)
        -- 后半段淡出
        coinAlpha = masterAlpha * (1.0 - clamp01((t - 0.6) / 0.4))
    end

    if coinAlpha > 0.01 then
        drawCoin(ctx, coinCX, coinCY, coinR, state.coinAngle, coinAlpha, coinZScale)

        -- 旋转残影光晕（翻转过渡时）
        if phase == PHASE_SPIN and math.abs(math.cos(math.rad(state.coinAngle))) < 0.25 then
            nvgBeginPath(ctx)
            nvgCircle(ctx, coinCX, coinCY, coinR * coinZScale + 8)
            nvgStrokeColor(ctx, nvgRGBA(
                Theme.GOLD.r, Theme.GOLD.g, Theme.GOLD.b,
                math.floor(coinAlpha * 55)))
            nvgStrokeWidth(ctx, 10)
            nvgStroke(ctx)
        end
    end

    -- ============================================
    -- 5. 结果大字（REVEAL + HOLD）
    -- ============================================
    if phase == PHASE_REVEAL or phase == PHASE_HOLD then
        local revealT
        if phase == PHASE_REVEAL then
            revealT = easeOutElastic(clamp01(t / 0.75))
        else
            revealT = 1.0
        end
        local rAlpha = revealT * masterAlpha

        local resultText  = (state.winner == 1) and "你是先攻！" or "对手先攻！"
        local resultColor = (state.winner == 1) and Theme.GOLD or Theme.RED

        local resultCY = panelY + panelH * 0.835
        local rScale   = 0.55 + 0.45 * revealT

        -- 背景光晕
        nvgBeginPath(ctx)
        nvgCircle(ctx, cx, resultCY, panelW * 0.32 * revealT)
        nvgFillColor(ctx, nvgRGBA(
            resultColor.r, resultColor.g, resultColor.b,
            math.floor(rAlpha * 30)))
        nvgFill(ctx)

        -- 微震动（REVEAL 前期）
        local shakeX, shakeY = 0, 0
        if phase == PHASE_REVEAL and t < 0.38 then
            local str = (0.38 - t) / 0.38 * 2.8
            shakeX = math.sin(time * 85) * str
            shakeY = math.cos(time * 78) * str * 0.5
        end

        nvgSave(ctx)
        nvgTranslate(ctx, cx + shakeX, resultCY + shakeY)
        nvgScale(ctx, rScale, rScale)

        nvgFontFaceId(ctx, fontId)
        nvgFontSize(ctx, 34)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

        -- 发光模糊底层
        nvgFontBlur(ctx, 4)
        nvgFillColor(ctx, nvgRGBA(
            resultColor.r, resultColor.g, resultColor.b, math.floor(rAlpha * 110)))
        nvgText(ctx, 0, 0, resultText, nil)
        nvgFontBlur(ctx, 0)

        -- 主文字
        nvgFillColor(ctx, nvgRGBA(
            resultColor.r, resultColor.g, resultColor.b, math.floor(rAlpha * 255)))
        nvgText(ctx, 0, 0, resultText, nil)

        nvgRestore(ctx)

        -- 副标题
        local winnerName = (state.winner == 1)
            and (HERO_NAMES[state.playerHero]   or "你")
            or  (HERO_NAMES[state.opponentHero] or "对手")
        local subAlpha = math.floor(rAlpha * 170)
        if subAlpha > 3 then
            nvgFontFaceId(ctx, fontId)
            nvgFontSize(ctx, 12)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(
                Theme.TEXT_SECONDARY.r, Theme.TEXT_SECONDARY.g,
                Theme.TEXT_SECONDARY.b, subAlpha))
            nvgText(ctx, cx, resultCY + 26, winnerName .. " 将首先行动", nil)
        end
    end

    -- ============================================
    -- 6. 跳过提示
    -- ============================================
    if phase ~= PHASE_EXIT and masterAlpha > 0.5 then
        nvgFontFaceId(ctx, fontId)
        nvgFontSize(ctx, 11)
        nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
        nvgFillColor(ctx, nvgRGBA(
            Theme.TEXT_DIM.r, Theme.TEXT_DIM.g, Theme.TEXT_DIM.b,
            math.floor(masterAlpha * 120)))
        nvgText(ctx, w - 14, h - 13, "点击任意处跳过", nil)
    end
end

-- ============================================================================
-- 点击跳过（供 main.lua 在 HandleUpdate 中调用）
-- ============================================================================

--- 处理鼠标点击（跳过/快进动画）
---@return boolean consumed 是否消费了此次点击
function CoinFlip.onMousePress()
    if not CoinFlip.isActive() then return false end
    if state.phase >= PHASE_HOLD then
        CoinFlip.skip()
    else
        -- 快进到 HOLD 阶段
        state.phase   = PHASE_HOLD
        state.elapsed = 0
    end
    return true
end

return CoinFlip

-- ============================================================================
-- UI/CombatCounter.lua - 场地中央战斗计数器
-- 攻击宣言 → 显示攻击力；防御宣言 → 显示攻防对比；结算后淡出
-- 参考：视频中场地中央 "†3 → †17" 以及 "'17 vs '12" 效果
-- ============================================================================

local Theme = require("UI.Theme")
local Tween = require("Core.Tween")
local Timer = require("Core.Timer")

local CombatCounter = {}

-- ============================================================================
-- 状态
-- ============================================================================

---@class CombatCounterState
local state_ = {
    -- 显示模式
    mode        = "hidden",  -- "hidden" | "attack" | "clash"

    -- 数值
    attack      = 0,
    defense     = 0,

    -- 透明度（0~1，Tween 驱动）
    alpha       = 0,

    -- 打击缩放脉冲（update 值变化时触发）
    scalePunch  = 1.0,

    -- 最近一次数值变化时间戳（用于区分是否需要 punch）
    lastAttack  = -1,
    lastDefense = -1,
}

-- ============================================================================
-- 缓动
-- ============================================================================

local function easeOutCubic(t)
    local t1 = 1 - t
    return 1 - t1 * t1 * t1
end

local function easeOutBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * (t - 1)^3 + c1 * (t - 1)^2
end

-- ============================================================================
-- 公开 API
-- ============================================================================

--- 攻击宣言：显示攻击力
---@param attackPower number
function CombatCounter.showAttack(attackPower)
    state_.mode    = "attack"
    state_.attack  = attackPower
    state_.defense = 0

    -- 淡入
    Tween.to(state_, 0.25, { alpha = 1.0 })

    -- 数字弹入
    state_.scalePunch = 1.35
end

--- 防御宣言：切换到攻防对比模式
---@param totalDefense number
function CombatCounter.showClash(totalDefense)
    state_.mode    = "clash"
    state_.defense = totalDefense

    -- 数字切换脉冲
    state_.scalePunch = 1.25
end

--- 结算后淡出
function CombatCounter.hide()
    Tween.to(state_, 0.4, { alpha = 0.0 })
    -- alpha 到 0 后重置 mode
    Timer.after(0.45, function()
        state_.mode    = "hidden"
        state_.attack  = 0
        state_.defense = 0
    end)
end

--- 每帧更新（平滑回弹 scalePunch）
---@param dt number
function CombatCounter.update(dt)
    if state_.scalePunch ~= 1.0 then
        state_.scalePunch = state_.scalePunch + (1.0 - state_.scalePunch) * math.min(1, dt * 10)
        if math.abs(state_.scalePunch - 1.0) < 0.005 then
            state_.scalePunch = 1.0
        end
    end
end

-- ============================================================================
-- 绘制
-- ============================================================================

--- 绘制战斗计数器
---@param ctx userdata NanoVG context
---@param w number 屏幕宽
---@param h number 屏幕高
---@param fontId number
function CombatCounter.draw(ctx, w, h, fontId)
    if state_.alpha < 0.01 then return end

    local masterAlpha = state_.alpha
    local cx = w * 0.5
    local cy = h * 0.48   -- 场地中央偏上（与剑/盾图标同区域）

    nvgFontFaceId(ctx, fontId)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    if state_.mode == "attack" then
        -- ------------------------------------------------
        -- 攻击模式：† + 大数字
        -- ------------------------------------------------
        local scale = state_.scalePunch
        local atkVal = state_.attack

        nvgSave(ctx)
        nvgTranslate(ctx, cx, cy)
        nvgScale(ctx, scale, scale)

        -- 外发光圈（代替剑图标的视觉锚点）
        local glowR = 38
        local glowPaint = nvgRadialGradient(ctx, 0, 0, 0, glowR,
            Theme.rgba(Theme.BLUE, math.floor(masterAlpha * 60)),
            Theme.rgba(Theme.BLUE, 0))
        nvgBeginPath(ctx)
        nvgCircle(ctx, 0, 0, glowR)
        nvgFillPaint(ctx, glowPaint)
        nvgFill(ctx)

        -- 主数字（大号，主题蓝）
        local numStr = tostring(atkVal)
        nvgFontSize(ctx, 52)
        -- 阴影
        nvgFillColor(ctx, nvgRGBA(30, 50, 120, math.floor(masterAlpha * 80)))
        nvgText(ctx, 2, 3, numStr, nil)
        -- 主体
        nvgFillColor(ctx, Theme.rgba(Theme.BLUE, math.floor(masterAlpha * 230)))
        nvgText(ctx, 0, 0, numStr, nil)

        -- 剑形前缀「†」（左上角小字）
        nvgFontSize(ctx, 18)
        local numW = nvgTextBounds(ctx, 0, 0, numStr) or (#numStr * 30)
        nvgFillColor(ctx, Theme.rgba(Theme.BLUE, math.floor(masterAlpha * 160)))
        nvgText(ctx, -numW * 0.5 - 10, -16, "†", nil)

        nvgRestore(ctx)

    elseif state_.mode == "clash" then
        -- ------------------------------------------------
        -- 攻防对比模式：'ATK  vs  'DEF
        -- ------------------------------------------------
        local scale   = state_.scalePunch
        local atkVal  = state_.attack
        local defVal  = state_.defense
        local winning = atkVal > defVal

        nvgSave(ctx)
        nvgTranslate(ctx, cx, cy)
        nvgScale(ctx, scale, scale)

        -- 攻击数字（上方，红/蓝取决于胜负）
        local atkColor = winning and Theme.RED or Theme.BLUE
        nvgFontSize(ctx, 48)
        nvgFillColor(ctx, nvgRGBA(30, 30, 60, math.floor(masterAlpha * 80)))
        nvgText(ctx, 2, -28 + 3, tostring(atkVal), nil)
        nvgFillColor(ctx, Theme.rgba(atkColor, math.floor(masterAlpha * 230)))
        nvgText(ctx, 0, -28, tostring(atkVal), nil)

        -- "vs" 分隔（小字，居中）
        nvgFontSize(ctx, 14)
        nvgFillColor(ctx, Theme.rgba(Theme.TEXT_PRIMARY, math.floor(masterAlpha * 120)))
        nvgText(ctx, 0, 0, "vs", nil)

        -- 防御数字（下方）
        local defColor = winning and Theme.BLUE or Theme.RED
        nvgFontSize(ctx, 48)
        nvgFillColor(ctx, nvgRGBA(30, 30, 60, math.floor(masterAlpha * 80)))
        nvgText(ctx, 2, 28 + 3, tostring(defVal), nil)
        nvgFillColor(ctx, Theme.rgba(defColor, math.floor(masterAlpha * 230)))
        nvgText(ctx, 0, 28, tostring(defVal), nil)

        -- 撇号前缀（模拟视频里 '17 vs '12 的撇号风格）
        nvgFontSize(ctx, 22)
        local atkStr = tostring(atkVal)
        local defStr = tostring(defVal)
        local atkW = nvgTextBounds(ctx, 0, 0, atkStr) or (#atkStr * 28)
        local defW = nvgTextBounds(ctx, 0, 0, defStr) or (#defStr * 28)
        nvgFontSize(ctx, 14)
        nvgFillColor(ctx, Theme.rgba(atkColor, math.floor(masterAlpha * 160)))
        nvgText(ctx, -atkW * 0.5 - 8, -36, "'", nil)
        nvgFillColor(ctx, Theme.rgba(defColor, math.floor(masterAlpha * 160)))
        nvgText(ctx, -defW * 0.5 - 8, 20, "'", nil)

        nvgRestore(ctx)
    end
end

return CombatCounter

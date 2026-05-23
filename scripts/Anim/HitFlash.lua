-- ============================================================================
-- Anim/HitFlash.lua - 被攻击时的白闪/红闪全屏效果（NanoVG overlay）
-- ============================================================================

local HitFlash = {}

-- 当前闪烁状态
local flash_ = {
    active   = false,
    timer    = 0,
    duration = 0.15,
    r = 255, g = 255, b = 255,  -- 白闪
    maxAlpha = 120,
}

--- 触发白闪效果
---@param duration number|nil 持续时间（默认 0.15s）
function HitFlash.trigger(duration)
    flash_.active   = true
    flash_.timer    = duration or 0.15
    flash_.duration = flash_.timer
    flash_.r = 255
    flash_.g = 255
    flash_.b = 255
    flash_.maxAlpha = 120
end

--- 触发红闪效果（受伤）
---@param duration number|nil 持续时间（默认 0.2s）
function HitFlash.triggerDamage(duration)
    flash_.active   = true
    flash_.timer    = duration or 0.2
    flash_.duration = flash_.timer
    flash_.r = 200
    flash_.g = 50
    flash_.b = 40
    flash_.maxAlpha = 80
end

--- 每帧更新
---@param dt number
function HitFlash.update(dt)
    if not flash_.active then return end
    flash_.timer = flash_.timer - dt
    if flash_.timer <= 0 then
        flash_.active = false
        flash_.timer = 0
    end
end

--- NanoVG 渲染（在所有 UI 之上绘制）
---@param ctx NVGContextWrapper
---@param w number 逻辑宽度
---@param h number 逻辑高度
function HitFlash.draw(ctx, w, h)
    if not flash_.active then return end

    local ratio = math.max(0, flash_.timer / flash_.duration)
    -- 快速淡出：前 30% 时间保持较强，后 70% 快速衰减
    local alpha = flash_.maxAlpha * ratio * ratio

    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, w, h)
    nvgFillColor(ctx, nvgRGBA(flash_.r, flash_.g, flash_.b, math.floor(alpha)))
    nvgFill(ctx)
end

--- 是否正在闪烁
---@return boolean
function HitFlash.isActive()
    return flash_.active
end

return HitFlash

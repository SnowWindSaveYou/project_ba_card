-- ============================================================================
-- Core/Easing.lua - 缓动曲线库
-- 30+ 缓动函数，用于 Balatro 风格卡牌动效
-- ============================================================================

local Easing = {}

local pi = math.pi
local sin = math.sin
local cos = math.cos
local sqrt = math.sqrt
local abs = math.abs
local pow = math.pow

-- ============================================================================
-- 基础缓动
-- ============================================================================

function Easing.linear(t)
    return t
end

-- ============================================================================
-- Quad
-- ============================================================================

function Easing.inQuad(t)
    return t * t
end

function Easing.outQuad(t)
    return t * (2 - t)
end

function Easing.inOutQuad(t)
    if t < 0.5 then
        return 2 * t * t
    else
        return -1 + (4 - 2 * t) * t
    end
end

-- ============================================================================
-- Cubic
-- ============================================================================

function Easing.inCubic(t)
    return t * t * t
end

function Easing.outCubic(t)
    local t1 = t - 1
    return t1 * t1 * t1 + 1
end

function Easing.inOutCubic(t)
    if t < 0.5 then
        return 4 * t * t * t
    else
        local t1 = 2 * t - 2
        return 0.5 * t1 * t1 * t1 + 1
    end
end

-- ============================================================================
-- Quart
-- ============================================================================

function Easing.inQuart(t)
    return t * t * t * t
end

function Easing.outQuart(t)
    local t1 = t - 1
    return 1 - t1 * t1 * t1 * t1
end

function Easing.inOutQuart(t)
    if t < 0.5 then
        return 8 * t * t * t * t
    else
        local t1 = t - 1
        return 1 - 8 * t1 * t1 * t1 * t1
    end
end

-- ============================================================================
-- Elastic (Balatro 弹性效果核心)
-- ============================================================================

function Easing.inElastic(t)
    if t == 0 or t == 1 then return t end
    return -pow(2, 10 * (t - 1)) * sin((t - 1.1) * 5 * pi)
end

function Easing.outElastic(t)
    if t == 0 or t == 1 then return t end
    return pow(2, -10 * t) * sin((t - 0.1) * 5 * pi) + 1
end

function Easing.inOutElastic(t)
    if t == 0 or t == 1 then return t end
    t = t * 2
    if t < 1 then
        return -0.5 * pow(2, 10 * (t - 1)) * sin((t - 1.1) * 5 * pi)
    else
        return 0.5 * pow(2, -10 * (t - 1)) * sin((t - 1.1) * 5 * pi) + 1
    end
end

-- ============================================================================
-- Bounce
-- ============================================================================

function Easing.outBounce(t)
    if t < 1 / 2.75 then
        return 7.5625 * t * t
    elseif t < 2 / 2.75 then
        t = t - 1.5 / 2.75
        return 7.5625 * t * t + 0.75
    elseif t < 2.5 / 2.75 then
        t = t - 2.25 / 2.75
        return 7.5625 * t * t + 0.9375
    else
        t = t - 2.625 / 2.75
        return 7.5625 * t * t + 0.984375
    end
end

function Easing.inBounce(t)
    return 1 - Easing.outBounce(1 - t)
end

function Easing.inOutBounce(t)
    if t < 0.5 then
        return Easing.inBounce(t * 2) * 0.5
    else
        return Easing.outBounce(t * 2 - 1) * 0.5 + 0.5
    end
end

-- ============================================================================
-- Back (超出目标后回弹)
-- ============================================================================

function Easing.inBack(t)
    local s = 1.70158
    return t * t * ((s + 1) * t - s)
end

function Easing.outBack(t)
    local s = 1.70158
    t = t - 1
    return t * t * ((s + 1) * t + s) + 1
end

function Easing.inOutBack(t)
    local s = 1.70158 * 1.525
    t = t * 2
    if t < 1 then
        return 0.5 * (t * t * ((s + 1) * t - s))
    else
        t = t - 2
        return 0.5 * (t * t * ((s + 1) * t + s) + 2)
    end
end

-- ============================================================================
-- Sine
-- ============================================================================

function Easing.inSine(t)
    return 1 - cos(t * pi / 2)
end

function Easing.outSine(t)
    return sin(t * pi / 2)
end

function Easing.inOutSine(t)
    return 0.5 * (1 - cos(pi * t))
end

-- ============================================================================
-- Expo
-- ============================================================================

function Easing.inExpo(t)
    if t == 0 then return 0 end
    return pow(2, 10 * (t - 1))
end

function Easing.outExpo(t)
    if t == 1 then return 1 end
    return 1 - pow(2, -10 * t)
end

function Easing.inOutExpo(t)
    if t == 0 or t == 1 then return t end
    t = t * 2
    if t < 1 then
        return 0.5 * pow(2, 10 * (t - 1))
    else
        return 0.5 * (2 - pow(2, -10 * (t - 1)))
    end
end

return Easing

-- ============================================================================
-- Core/Tween.lua - 缓动动画引擎
-- 支持属性动画、序列、并行、回调
-- ============================================================================

local Easing = require("Core.Easing")

local Tween = {}
Tween.__index = Tween

-- 全局活跃 tween 列表
local activeTweens = {}
local tweenIdCounter = 0

-- ============================================================================
-- 内部工具
-- ============================================================================

local function lerp(a, b, t)
    return a + (b - a) * t
end

--- 插值 Vector3
local function lerpVec3(a, b, t)
    return Vector3(
        lerp(a.x, b.x, t),
        lerp(a.y, b.y, t),
        lerp(a.z, b.z, t)
    )
end

--- 插值 Quaternion (使用 Slerp)
local function lerpQuat(a, b, t)
    return a:Slerp(b, t)
end

--- 插值 Color
local function lerpColor(a, b, t)
    return Color(
        lerp(a.r, b.r, t),
        lerp(a.g, b.g, t),
        lerp(a.b, b.b, t),
        lerp(a.a, b.a, t)
    )
end

-- ============================================================================
-- Tween 对象
-- ============================================================================

--- 创建属性动画
---@param target table|Node 目标对象
---@param duration number 时长(秒)
---@param props table 属性表 {position=Vector3(...), ...}
---@param options table|nil {easing, delay, onComplete, onUpdate, loops, yoyo}
---@return table tween
function Tween.to(target, duration, props, options)
    options = options or {}
    tweenIdCounter = tweenIdCounter + 1

    local tw = {
        id = tweenIdCounter,
        target = target,
        duration = duration,
        elapsed = 0,
        delay = options.delay or 0,
        delayElapsed = 0,
        easing = options.easing or Easing.outCubic,
        onComplete = options.onComplete,
        onUpdate = options.onUpdate,
        loops = options.loops or 1,     -- -1 = 无限
        yoyo = options.yoyo or false,
        currentLoop = 0,
        forward = true,
        props = {},
        active = true,
        paused = false,
        killed = false,
    }

    -- 记录起始值（延迟后才捕获）
    tw._propsRaw = props
    tw._startCaptured = false

    activeTweens[tw.id] = tw
    return tw
end

--- 捕获起始值
local function captureStartValues(tw)
    if tw._startCaptured then return end
    tw._startCaptured = true

    for key, endVal in pairs(tw._propsRaw) do
        local startVal = tw.target[key]
        if startVal == nil then
            print("[Tween] WARNING: target has no property '" .. key .. "'")
        else
            tw.props[key] = {
                startVal = startVal,
                endVal = endVal,
            }
        end
    end
end

--- 应用插值
local function applyProps(tw, t)
    local easedT = tw.easing(t)

    for key, prop in pairs(tw.props) do
        local sv = prop.startVal
        local ev = prop.endVal
        local val

        -- 根据类型选择插值方式
        if type(sv) == "number" then
            val = lerp(sv, ev, easedT)
        elseif sv.x ~= nil and sv.y ~= nil and sv.z ~= nil and sv.w == nil then
            -- Vector3
            val = lerpVec3(sv, ev, easedT)
        elseif sv.w ~= nil then
            -- Quaternion
            val = lerpQuat(sv, ev, easedT)
        elseif sv.r ~= nil then
            -- Color
            val = lerpColor(sv, ev, easedT)
        else
            val = ev -- 不支持的类型直接跳到终值
        end

        tw.target[key] = val
    end

    if tw.onUpdate then
        tw.onUpdate(tw.target, easedT)
    end
end

-- ============================================================================
-- 全局更新（每帧调用）
-- ============================================================================

function Tween.update(dt)
    local toRemove = {}

    for id, tw in pairs(activeTweens) do
        if tw.killed then
            toRemove[#toRemove + 1] = id
        elseif tw.active and not tw.paused then
            -- 延迟阶段
            if tw.delayElapsed < tw.delay then
                tw.delayElapsed = tw.delayElapsed + dt
            else
                -- 首次进入动画阶段，捕获起始值
                captureStartValues(tw)

                tw.elapsed = tw.elapsed + dt
                local t = math.min(tw.elapsed / tw.duration, 1.0)

                -- yoyo 模式：反向播放
                local applyT = tw.forward and t or (1.0 - t)
                applyProps(tw, applyT)

                -- 完成一次循环
                if t >= 1.0 then
                    tw.currentLoop = tw.currentLoop + 1

                    if tw.loops ~= -1 and tw.currentLoop >= tw.loops then
                        -- 动画结束
                        tw.active = false
                        if tw.onComplete then
                            tw.onComplete(tw.target)
                        end
                        toRemove[#toRemove + 1] = id
                    else
                        -- 重置进入下一循环
                        tw.elapsed = 0
                        if tw.yoyo then
                            tw.forward = not tw.forward
                        end
                    end
                end
            end
        end
    end

    for _, id in ipairs(toRemove) do
        activeTweens[id] = nil
    end
end

-- ============================================================================
-- 控制接口
-- ============================================================================

function Tween.kill(tw)
    if tw then tw.killed = true end
end

function Tween.pause(tw)
    if tw then tw.paused = true end
end

function Tween.resume(tw)
    if tw then tw.paused = false end
end

--- 停止目标上所有 tween
function Tween.killAll(target)
    for _, tw in pairs(activeTweens) do
        if tw.target == target then
            tw.killed = true
        end
    end
end

--- 停止所有 tween
function Tween.clear()
    activeTweens = {}
end

--- 获取活跃 tween 数量
function Tween.count()
    local n = 0
    for _ in pairs(activeTweens) do n = n + 1 end
    return n
end

-- ============================================================================
-- 序列/并行组合
-- ============================================================================

--- 顺序执行一组动画
---@param tweenDefs table[] 每项 {target, duration, props, options}
---@param onAllComplete function|nil 全部完成回调
function Tween.sequence(tweenDefs, onAllComplete)
    local idx = 0

    local function runNext()
        idx = idx + 1
        if idx > #tweenDefs then
            if onAllComplete then onAllComplete() end
            return
        end

        local def = tweenDefs[idx]
        local opts = def.options or {}
        opts.onComplete = function()
            if def.options and def.options.onComplete then
                def.options.onComplete(def.target)
            end
            runNext()
        end
        Tween.to(def.target, def.duration, def.props, opts)
    end

    runNext()
end

--- 并行执行一组动画
---@param tweenDefs table[]
---@param onAllComplete function|nil
function Tween.parallel(tweenDefs, onAllComplete)
    local remaining = #tweenDefs

    for _, def in ipairs(tweenDefs) do
        local opts = def.options or {}
        local origComplete = opts.onComplete
        opts.onComplete = function(t)
            if origComplete then origComplete(t) end
            remaining = remaining - 1
            if remaining <= 0 and onAllComplete then
                onAllComplete()
            end
        end
        Tween.to(def.target, def.duration, def.props, opts)
    end
end

return Tween

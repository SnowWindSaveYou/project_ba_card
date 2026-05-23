-- ============================================================================
-- Core/Timer.lua - 延时/序列调度器
-- 支持延时调用、重复定时器、帧计数
-- ============================================================================

local Timer = {}

local activeTimers = {}
local timerIdCounter = 0

--- 延迟执行回调
---@param delay number 延迟秒数
---@param callback function 回调函数
---@return number id 定时器ID（可用于取消）
function Timer.after(delay, callback)
    timerIdCounter = timerIdCounter + 1
    activeTimers[timerIdCounter] = {
        delay = delay,
        elapsed = 0,
        callback = callback,
        repeating = false,
    }
    return timerIdCounter
end

--- 重复定时器
---@param interval number 间隔秒数
---@param callback function 回调（返回 false 停止）
---@param immediate boolean|nil 是否立即执行第一次
---@return number id
function Timer.every(interval, callback, immediate)
    timerIdCounter = timerIdCounter + 1
    activeTimers[timerIdCounter] = {
        delay = interval,
        elapsed = immediate and interval or 0,
        callback = callback,
        repeating = true,
    }
    return timerIdCounter
end

--- 取消定时器
function Timer.cancel(id)
    activeTimers[id] = nil
end

--- 取消所有定时器
function Timer.clear()
    activeTimers = {}
end

--- 每帧调用
function Timer.update(dt)
    local toRemove = {}

    for id, t in pairs(activeTimers) do
        t.elapsed = t.elapsed + dt
        if t.elapsed >= t.delay then
            local result = t.callback()
            if t.repeating and result ~= false then
                t.elapsed = t.elapsed - t.delay
            else
                toRemove[#toRemove + 1] = id
            end
        end
    end

    for _, id in ipairs(toRemove) do
        activeTimers[id] = nil
    end
end

return Timer

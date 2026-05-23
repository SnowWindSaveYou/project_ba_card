-- ============================================================================
-- Input/InputManager.lua - 帧内输入消费仲裁器
--
-- 用法：
--   UI 组件在自己的 update() 中检测命中后调用 consumeMouse()
--   CardPicker 等 3D 拾取系统调用 isMouseConsumed() 决定是否跳过
--
-- 调用顺序（HandleUpdate 内）：
--   1. InputManager.beginFrame(nvgScale)   ← 每帧最先调用，重置状态
--   2. UI 组件 .update(...)               ← 各组件自行判断并 consumeMouse
--   3. if not InputManager.isMouseConsumed() then cardPicker:update() end
-- ============================================================================

local InputManager = {}

local consumed_ = false
local nvgScale_ = 1.0

--- 每帧最先调用，重置消费状态并更新坐标缩放
---@param nvgScale number  物理像素 / NanoVG逻辑坐标 的缩放比
function InputManager.beginFrame(nvgScale)
    consumed_ = false
    nvgScale_ = nvgScale or 1.0
end

--- 获取当前帧鼠标位置（NanoVG 逻辑坐标）
---@return number mx, number my
function InputManager.getMousePos()
    return input.mousePosition.x / nvgScale_,
           input.mousePosition.y / nvgScale_
end

--- UI 组件调用：声明本帧鼠标已被消费，3D 拾取系统将跳过
function InputManager.consumeMouse()
    consumed_ = true
end

--- 3D 拾取系统调用：查询本帧鼠标是否已被 UI 消费
---@return boolean
function InputManager.isMouseConsumed()
    return consumed_
end

return InputManager

-- ============================================================================
-- Scene/CameraRig.lua - 固定俯视相机
-- 俯视角 ~50°，微弱呼吸感 sin 波动
-- ============================================================================

local CameraRig = {}
CameraRig.__index = CameraRig

-- 相机默认参数
local DEFAULTS = {
    position  = Vector3(0, 9, -2.8),  -- 俯视位置（更接近正上方，炉石风格）
    fov       = 48.0,
    nearClip  = 0.1,
    farClip   = 100.0,
    -- 呼吸感参数
    breathAmpY   = 0.03,   -- Y 轴振幅（米）
    breathAmpRot = 0.15,   -- 旋转振幅（度）
    breathFreq   = 0.4,    -- 频率 (Hz)
}

--- 创建相机
---@param scene Scene
---@param config table|nil 覆盖默认参数
---@return table rig
function CameraRig.create(scene, config)
    config = config or {}

    local rig = setmetatable({}, CameraRig)

    -- 创建相机节点
    rig.node = scene:CreateChild("CameraRig")
    rig.node.position = config.position or DEFAULTS.position

    -- 朝桌面中央看（稍微偏上方）
    rig.node:LookAt(Vector3(0, 0, 0.3))

    -- 记录基准旋转
    rig.baseRotation = rig.node.rotation
    rig.basePosition = rig.node.position

    -- 相机组件
    local camera = rig.node:CreateComponent("Camera")
    camera.fov = config.fov or DEFAULTS.fov
    camera.nearClip = config.nearClip or DEFAULTS.nearClip
    camera.farClip = config.farClip or DEFAULTS.farClip
    rig.camera = camera

    -- 呼吸感参数
    rig.breathAmpY   = config.breathAmpY or DEFAULTS.breathAmpY
    rig.breathAmpRot = config.breathAmpRot or DEFAULTS.breathAmpRot
    rig.breathFreq   = config.breathFreq or DEFAULTS.breathFreq
    rig.time = 0

    -- 震动参数
    rig.shakeTimer     = 0      -- 剩余震动时间
    rig.shakeDuration  = 0      -- 总震动时长
    rig.shakeIntensity = 0      -- 震动强度（米）

    return rig
end

--- 获取相机组件
---@return Camera
function CameraRig:getCamera()
    return self.camera
end

--- 触发相机震动
---@param intensity number 震动强度（米），推荐 0.05~0.15
---@param duration number 震动持续时间（秒），推荐 0.15~0.3
function CameraRig:shake(intensity, duration)
    self.shakeIntensity = intensity or 0.08
    self.shakeDuration  = duration or 0.2
    self.shakeTimer     = self.shakeDuration
end

--- 每帧更新（呼吸感微动 + 震动）
---@param dt number
function CameraRig:update(dt)
    self.time = self.time + dt

    local t = self.time * self.breathFreq * math.pi * 2

    -- Y 轴微浮
    local offsetY = math.sin(t) * self.breathAmpY
    local offsetX = 0
    local offsetZ = 0

    -- 震动叠加
    if self.shakeTimer > 0 then
        self.shakeTimer = self.shakeTimer - dt
        local ratio = math.max(0, self.shakeTimer / self.shakeDuration)  -- 线性衰减
        local amp = self.shakeIntensity * ratio
        offsetX = (math.random() - 0.5) * 2 * amp
        offsetY = offsetY + (math.random() - 0.5) * 2 * amp
        offsetZ = (math.random() - 0.5) * 2 * amp * 0.5
    end

    self.node.position = Vector3(
        self.basePosition.x + offsetX,
        self.basePosition.y + offsetY,
        self.basePosition.z + offsetZ
    )

    -- 微旋转（绕 X 轴轻微点头）
    local rotOffset = math.sin(t * 0.7) * self.breathAmpRot
    self.node.rotation = self.baseRotation * Quaternion(rotOffset, Vector3.RIGHT)
end

return CameraRig

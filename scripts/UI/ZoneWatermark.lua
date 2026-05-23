-- ============================================================================
-- UI/ZoneWatermark.lua - 攻/防区域水印（3D 节点方案）
--
-- 在 3D 场景中，于两块区域中心放置平面节点（Plane.mdl），贴剑/盾贴图。
-- 天然渲染在所有 NanoVG UI 层之下，无需手动管理绘制顺序。
--
-- 动画：swap() 触发时
--   1. FLASH  (0.20s) : alpha idle → 1.0
--   2. SWAP   (0.55s) : 两节点在 XZ 平面沿相反弧线飞向对方位置，Y 轴略微抬起
--   3. SETTLE (0.30s) : alpha 1.0 → idle，拖尾 ghost 淡出
--
-- 图标不自转，只做位移弧线。
-- ============================================================================

local Tween = require("Core.Tween")

local ZoneWatermark = {}

-- ============================================================================
-- 3D 场地坐标
-- TABLE_WIDTH=6, TABLE_DEPTH=4, TABLE_Y=-0.03
-- 上区（对手）Z=-1，下区（玩家）Z=+1
-- ============================================================================
local TABLE_Y    = -0.03
local WORLD_Y    = TABLE_Y + 0.04  -- 贴在桌面上方，避免 Z-fighting

local UPPER_POS  = Vector3(0, WORLD_Y, -1.0)
local LOWER_POS  = Vector3(0, WORLD_Y,  1.0)

-- ============================================================================
-- 配置
-- ============================================================================
local CFG = {
    iconWorldSize = 1.4,    -- 世界尺寸（米）
    idleAlpha     = 0.15,   -- 静止半透明度
    flashDur      = 0.20,
    swapDur       = 0.52,
    settleDur     = 0.30,
    arcYLift      = 0.35,   -- 弧线飞行时最高抬起高度（米）
    arcXBow       = 0.6,    -- 弧线 X 方向弓度（米）
    ghostCount    = 5,      -- 拖尾 ghost 节点数
}

-- ============================================================================
-- 缓动
-- ============================================================================
local function easeInOutCubic(t)
    t = math.max(0, math.min(1, t))
    if t < 0.5 then return 4*t*t*t
    else local u = -2*t+2; return 1 - u*u*u/2 end
end

local function lerp(a, b, t) return a + (b-a)*math.max(0,math.min(1,t)) end

-- ============================================================================
-- 辅助：创建一个图标平面节点
-- ============================================================================
local function createIconNode(parent, texPath, pos, alpha)
    local node = parent:CreateChild("ZWMark")
    node.position = pos

    -- Plane.mdl 是 1×1，通过 scale 控制世界尺寸
    local sz = CFG.iconWorldSize
    node:SetScale(Vector3(sz, 1, sz))

    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
    model.castShadows = false

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
    mat:SetTexture(TU_DIFFUSE, cache:GetResource("Texture2D", texPath))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, alpha)))
    model:SetMaterial(mat)

    return node, mat
end

-- ============================================================================
-- 辅助：创建拖尾 ghost（复用同一材质实例即可）
-- ============================================================================
local function createGhost(parent, texPath)
    local node = parent:CreateChild("ZWGhost")
    node.enabled = false

    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
    model.castShadows = false

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
    mat:SetTexture(TU_DIFFUSE, cache:GetResource("Texture2D", texPath))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 0)))
    model:SetMaterial(mat)

    return node, mat
end

-- ============================================================================
-- 状态
-- ============================================================================
local STATE = { IDLE="idle", FLASH="flash", SWAP="swap", SETTLE="settle" }

local s = {
    phase        = STATE.IDLE,
    timer        = 0,
    swordInLower = true,

    -- 主节点 + 材质
    nodeSword    = nil, matSword    = nil,
    nodeShield   = nil, matShield   = nil,

    -- 拖尾 ghost 节点
    ghostsSword  = {},  ghostMatsSword  = {},
    ghostsShield = {},  ghostMatsShield = {},

    -- 动画起止世界坐标（SWAP 开始时快照）
    srcSword  = Vector3.ZERO,  dstSword  = Vector3.ZERO,
    srcShield = Vector3.ZERO,  dstShield = Vector3.ZERO,

    -- ghost 采样历史（世界坐标 + alpha）
    trailSword  = {},
    trailShield = {},
    trailTimer  = 0,

    initialized = false,
    onDone      = nil,
}

-- ============================================================================
-- 公开 API
-- ============================================================================

---@param scene Scene
---@param swordInLower boolean  初始剑是否在下区（玩家攻击）
function ZoneWatermark.init(scene, swordInLower)
    if s.initialized then return end
    s.swordInLower = (swordInLower ~= false)

    local swordPos  = s.swordInLower and LOWER_POS or UPPER_POS
    local shieldPos = s.swordInLower and UPPER_POS or LOWER_POS

    s.nodeSword,  s.matSword  = createIconNode(scene, "image/zone_sword_20260523033802.png",  swordPos,  CFG.idleAlpha)
    s.nodeShield, s.matShield = createIconNode(scene, "image/zone_shield_20260523033757.png", shieldPos, CFG.idleAlpha)

    -- 创建 ghost 池
    for i = 1, CFG.ghostCount do
        local gn, gm = createGhost(scene, "image/zone_sword_20260523033802.png")
        s.ghostsSword[i]    = gn
        s.ghostMatsSword[i] = gm

        local gn2, gm2 = createGhost(scene, "image/zone_shield_20260523033757.png")
        s.ghostsShield[i]    = gn2
        s.ghostMatsShield[i] = gm2
    end

    s.initialized = true
end

---@param swordInLower boolean  互换后剑是否在下区
---@param onDone function|nil
function ZoneWatermark.swap(swordInLower, onDone)
    if not s.initialized then return end
    if s.phase ~= STATE.IDLE then return end
    s.onDone = onDone

    -- 快照当前位置
    s.srcSword  = Vector3(s.nodeSword.position)
    s.srcShield = Vector3(s.nodeShield.position)

    -- 目标位置
    s.dstSword  = swordInLower and LOWER_POS or UPPER_POS
    s.dstShield = swordInLower and UPPER_POS or LOWER_POS

    s.swordInLower = swordInLower

    s.trailSword  = {}
    s.trailShield = {}
    s.trailTimer  = 0

    s.phase = STATE.FLASH
    s.timer = 0
end

function ZoneWatermark.isActive()
    return s.phase ~= STATE.IDLE
end

-- ============================================================================
-- 圆弧路径（三角函数，以桌面中心为圆心的半圆）
--
-- 两个区域都在 X=0 的 Z 轴上（z=-1 和 z=+1），半径=1。
-- 剑始终走 +X 一侧（右弧），盾始终走 -X 一侧（左弧），形成交叉感。
--
-- 一般公式：
--   z 分量 = sin(angle), x 分量 = cos(angle) * arcXBow
--   startAngle / direction 由运动方向决定，见下方调用处。
-- ============================================================================

-- 把 t∈[0,1] 映射为（半）圆弧上的 Vector3
-- startAngle: 起始极角（弧度）
-- angDir:     +1 or -1（决定绕向）
-- et:         已应用缓动的进度
local function circlePos(startAngle, angDir, et)
    local angle = startAngle + angDir * et * math.pi
    return Vector3(
        math.cos(angle) * CFG.arcXBow,
        WORLD_Y + math.sin(math.max(0, et) * math.pi) * CFG.arcYLift,
        math.sin(angle)   -- z 方向，半径 = 1（与区域距离一致）
    )
end

-- ============================================================================
-- 更新
-- ============================================================================

---@param dt number
function ZoneWatermark.update(dt)
    if not s.initialized then return end

    if s.phase == STATE.IDLE then
        -- 静止态：节点位置已固定，无需每帧更新
        return
    end

    s.timer = s.timer + dt

    -- -----------------------------------------------------------------------
    -- FLASH：淡入到不透明
    -- -----------------------------------------------------------------------
    if s.phase == STATE.FLASH then
        local p = math.min(1, s.timer / CFG.flashDur)
        local a = lerp(CFG.idleAlpha, 1.0, p)
        s.matSword:SetShaderParameter( "MatDiffColor", Variant(Color(1,1,1,a)))
        s.matShield:SetShaderParameter("MatDiffColor", Variant(Color(1,1,1,a)))
        if p >= 1 then
            s.phase = STATE.SWAP
            s.timer = 0
            s.trailTimer = 0
        end

    -- -----------------------------------------------------------------------
    -- SWAP：圆弧飞行 + 拖尾
    --
    -- 判断运动方向，确定半圆的起始极角和绕向：
    --   剑走 +X 侧（右弧）：
    --     lower(z=+1)→upper(z=-1)：startAngle=π/2，dir=-1（顺时针，过 +x）
    --     upper(z=-1)→lower(z=+1)：startAngle=-π/2，dir=+1（逆时针，过 +x）
    --   盾走 -X 侧（左弧）：
    --     lower(z=+1)→upper(z=-1)：startAngle=π/2，dir=+1（逆时针，过 -x）
    --     upper(z=-1)→lower(z=+1)：startAngle=-π/2，dir=-1（顺时针，过 -x）
    -- -----------------------------------------------------------------------
    elseif s.phase == STATE.SWAP then
        local p  = math.min(1, s.timer / CFG.swapDur)
        local ep = easeInOutCubic(p)

        -- s.swordInLower 是互换后的新状态
        -- swordInLower=true  → 剑从 upper(-1) 飞向 lower(+1)，z 增大
        -- swordInLower=false → 剑从 lower(+1) 飞向 upper(-1)，z 减小
        local sA, sD, shA, shD
        if s.swordInLower then
            -- 剑 upper→lower，走 +x：起始 -π/2，逆时针
            sA, sD   = -math.pi/2,  1
            -- 盾 lower→upper，走 -x：起始 +π/2，逆时针
            shA, shD =  math.pi/2,  1
        else
            -- 剑 lower→upper，走 +x：起始 +π/2，顺时针
            sA, sD   =  math.pi/2, -1
            -- 盾 upper→lower，走 -x：起始 -π/2，顺时针
            shA, shD = -math.pi/2, -1
        end

        local posSword  = circlePos(sA,  sD,  ep)
        local posShield = circlePos(shA, shD, ep)

        s.nodeSword.position  = posSword
        s.nodeShield.position = posShield

        -- 采样拖尾
        s.trailTimer = s.trailTimer + dt
        if s.trailTimer >= 0.04 then
            s.trailTimer = 0
            table.insert(s.trailSword,  { pos = Vector3(posSword),  a = 0.7 })
            table.insert(s.trailShield, { pos = Vector3(posShield), a = 0.7 })
            -- 超出上限时移除最老的
            if #s.trailSword  > CFG.ghostCount then table.remove(s.trailSword,  1) end
            if #s.trailShield > CFG.ghostCount then table.remove(s.trailShield, 1) end
        end

        -- 更新 ghost 节点
        for i, tf in ipairs(s.trailSword) do
            local gn = s.ghostsSword[i]
            if gn then
                gn.enabled  = true
                gn.position = tf.pos
                local ratio = i / CFG.ghostCount
                local gs    = CFG.iconWorldSize * lerp(0.55, 0.9, ratio)
                gn:SetScale(Vector3(gs, 1, gs))
                s.ghostMatsSword[i]:SetShaderParameter("MatDiffColor", Variant(Color(1,1,1, tf.a * ratio)))
            end
        end
        for i, tf in ipairs(s.trailShield) do
            local gn = s.ghostsShield[i]
            if gn then
                gn.enabled  = true
                gn.position = tf.pos
                local ratio = i / CFG.ghostCount
                local gs    = CFG.iconWorldSize * lerp(0.55, 0.9, ratio)
                gn:SetScale(Vector3(gs, 1, gs))
                s.ghostMatsShield[i]:SetShaderParameter("MatDiffColor", Variant(Color(1,1,1, tf.a * ratio)))
            end
        end

        if p >= 1 then
            s.nodeSword.position  = s.dstSword
            s.nodeShield.position = s.dstShield
            s.phase = STATE.SETTLE
            s.timer = 0
        end

    -- -----------------------------------------------------------------------
    -- SETTLE：淡回半透明，拖尾消散
    -- -----------------------------------------------------------------------
    elseif s.phase == STATE.SETTLE then
        local p = math.min(1, s.timer / CFG.settleDur)
        local a = lerp(1.0, CFG.idleAlpha, p)
        s.matSword:SetShaderParameter( "MatDiffColor", Variant(Color(1,1,1,a)))
        s.matShield:SetShaderParameter("MatDiffColor", Variant(Color(1,1,1,a)))

        -- ghost 快速消散
        for i = 1, CFG.ghostCount do
            if s.ghostsSword[i] and s.ghostsSword[i].enabled then
                local cur = s.trailSword[i]
                if cur then cur.a = math.max(0, cur.a - dt * 6) end
                local ratio = i / CFG.ghostCount
                local fa = cur and (cur.a * ratio) or 0
                s.ghostMatsSword[i]:SetShaderParameter("MatDiffColor", Variant(Color(1,1,1,fa)))
                if fa <= 0 then s.ghostsSword[i].enabled = false end
            end
            if s.ghostsShield[i] and s.ghostsShield[i].enabled then
                local cur = s.trailShield[i]
                if cur then cur.a = math.max(0, cur.a - dt * 6) end
                local ratio = i / CFG.ghostCount
                local fa = cur and (cur.a * ratio) or 0
                s.ghostMatsShield[i]:SetShaderParameter("MatDiffColor", Variant(Color(1,1,1,fa)))
                if fa <= 0 then s.ghostsShield[i].enabled = false end
            end
        end

        if p >= 1 then
            -- 清理所有 ghost
            for i = 1, CFG.ghostCount do
                if s.ghostsSword[i]  then s.ghostsSword[i].enabled  = false end
                if s.ghostsShield[i] then s.ghostsShield[i].enabled = false end
            end
            s.trailSword  = {}
            s.trailShield = {}
            s.phase = STATE.IDLE
            if s.onDone then s.onDone() end
        end
    end
end

-- draw() 空实现——3D 方案不需要 NanoVG 绘制
function ZoneWatermark.draw(_ctx, _w, _h) end

-- setScreenParams() 空实现——3D 方案不需要屏幕参数
function ZoneWatermark.setScreenParams(_pw, _ph, _sc) end

return ZoneWatermark

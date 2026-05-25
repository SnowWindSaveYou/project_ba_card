-- ============================================================================
-- Layout/HandFan.lua - 手牌弧形扇面布局（相机容器方案）
-- 卡牌挂载在 CameraNode 的子容器中，使用相机局部坐标
-- 拖拽时脱离容器到场景根，松手后回挂
-- ============================================================================

local Card3D       = require("Card.Card3D")
local Tween        = require("Core.Tween")
local Easing       = require("Core.Easing")
local CardAnimator = require("Anim.CardAnimator")

local HandFan = {}
HandFan.__index = HandFan

-- ============================================================================
-- 布局参数（相机局部空间）
-- ============================================================================

local DEFAULTS = {
    -- 容器在相机局部空间的位置
    -- 相机 FOV=50 → 半角 25° → tan(25°)=0.466
    -- Z=3.0 时视口半高=1.40m, 半宽≈2.49m (16:9)
    containerLocalPos = Vector3(0, -0.9, 3.0),

    -- 卡牌绕 X 轴前倾角度（相机局部空间）
    -- -75° = 几乎面向镜头，略有前倾透视
    cardPitchDeg = -75,

    -- 弧线参数
    arcRadius    = 6.0,     -- 弧线半径（越大越平）
    maxArcDeg    = 35,      -- 最大扇面角度
    minArcDeg    = 8,       -- 最小扇面角度

    -- 卡牌间距（相机局部空间中，因距离近所以值较小）
    maxSpacing   = 0.50,    -- 少牌时最大间距
    minSpacing   = 0.18,    -- 多牌时最小间距
    maxTotalW    = 2.8,     -- 手牌展开最大总宽度

    -- 悬停让位
    hoverSpread  = 0.12,    -- 悬停时相邻卡位移
    hoverLift    = 0.15,    -- 悬停时上浮（局部 Y）

    -- 动画
    layoutDur    = 0.25,

    -- 收起状态：右下角小幅展开排列
    -- collapsedPos：相机局部坐标，右下偏移
    collapsedPos   = Vector3(1.3, -1.05, 3.0),
    collapsedScale = 0.42,   -- 卡牌明显缩小（更小）
    collapsedMaxTotalW = 1.8,    -- 总宽加大，卡牌不那么拥挤
    collapsedMaxSpacing = 0.38,  -- 间距放开
    collapsedMinSpacing = 0.16,  -- 最小间距也放开
    collapsedMaxArcDeg  = 28,    -- 弧度略大，更自然
}

-- ============================================================================
-- 构造
-- ============================================================================

--- 创建手牌扇面布局管理器
---@param cameraNode Node 相机节点
---@param sceneNode Scene 场景根节点（用于拖拽时脱挂）
---@param config table|nil 可选覆盖参数
---@return table handFan
function HandFan.create(cameraNode, sceneNode, config)
    local fan = setmetatable({}, HandFan)
    fan.cards = {}
    fan.hoveredIndex = 0
    fan.scene = sceneNode

    -- 合并配置
    fan.cfg = {}
    for k, v in pairs(DEFAULTS) do fan.cfg[k] = v end
    if config then
        for k, v in pairs(config) do fan.cfg[k] = v end
    end

    -- 创建相机子容器节点
    fan.container = cameraNode:CreateChild("HandContainer")
    fan.container.position = fan.cfg.containerLocalPos

    -- 收起/展开状态
    -- 默认展开（对手扇面永远不收起，由 isCollapseEnabled 控制）
    fan.collapsed          = false
    fan.isCollapseEnabled  = false   -- 由外部设置为 true 才启用收起功能
    fan._collapseScale     = 1.0     -- 当前缩放系数（用于 computeSlots 注入）

    return fan
end

-- ============================================================================
-- 坐标转换
-- ============================================================================

--- 世界坐标 → 容器局部坐标
---@param worldPos Vector3
---@return Vector3
function HandFan:worldToLocal(worldPos)
    local cWPos = self.container.worldPosition
    local cWRot = self.container.worldRotation
    return cWRot:Inverse() * (worldPos - cWPos)
end

--- 容器局部坐标 → 世界坐标
---@param localPos Vector3
---@return Vector3
function HandFan:localToWorld(localPos)
    local cWPos = self.container.worldPosition
    local cWRot = self.container.worldRotation
    return cWPos + cWRot * localPos
end

-- ============================================================================
-- 管理卡牌
-- ============================================================================

--- 添加卡牌到手牌末尾（并挂载到容器）
---@param card3d table Card3D 实例
function HandFan:addCard(card3d)
    -- 保存世界变换
    local wPos = card3d.node.worldPosition
    local wRot = card3d.node.worldRotation
    -- 挂载到容器
    self.container:AddChild(card3d.node)
    -- 恢复世界位置（引擎自动计算局部坐标）
    card3d.node.worldPosition = wPos
    card3d.node.worldRotation = wRot

    -- 应用缩放（对手卡牌等场景使用，乘以原有缩放而非覆盖）
    if self.cfg.cardScale and self.cfg.cardScale ~= 1.0 then
        local s = self.cfg.cardScale
        local orig = card3d.node.scale
        card3d.node.scale = Vector3(orig.x * s, orig.y * s, orig.z * s)
    end

    self.cards[#self.cards + 1] = card3d
end

--- 移除指定卡牌（不脱离容器，由调用者决定是否脱离）
---@param card3d table
---@return boolean 是否移除成功
function HandFan:removeCard(card3d)
    for i, c in ipairs(self.cards) do
        if c == card3d then
            table.remove(self.cards, i)
            return true
        end
    end
    return false
end

--- 移除卡牌并将节点从容器脱离到场景根（保持世界位置不变）
--- 出牌/防御时必须用这个，否则后续用 worldPosition 驱动动画、
--- 但 arrangeZone 用 position（局部坐标）重排时，节点还挂在手牌
--- 容器下，位置会被解释为相对容器的偏移，导致卡牌"飞回手牌区"。
---@param card3d table
---@return boolean 是否移除成功
function HandFan:removeAndDetach(card3d)
    local removed = self:removeCard(card3d)
    if removed then
        local wPos = card3d.node.worldPosition
        local wRot = card3d.node.worldRotation
        self.scene:AddChild(card3d.node)
        card3d.node.worldPosition = wPos
        card3d.node.worldRotation = wRot
    end
    return removed
end

--- 清空手牌
function HandFan:clear()
    self.cards = {}
    self.hoveredIndex = 0
end

--- 获取手牌列表
---@return table[]
function HandFan:getCards()
    return self.cards
end

--- 获取手牌数量
---@return number
function HandFan:count()
    return #self.cards
end

-- ============================================================================
-- 拖拽 - 脱离/回挂容器
-- ============================================================================

--- 拖拽开始：将卡牌从容器脱离到场景根（保持世界位置不变）
---@param card3d table Card3D 实例
function HandFan:detachForDrag(card3d)
    local wPos = card3d.node.worldPosition
    local wRot = card3d.node.worldRotation
    self.scene:AddChild(card3d.node)
    card3d.node.worldPosition = wPos
    card3d.node.worldRotation = wRot
    self.isDraggingCard = true   -- 拖拽中：禁止手牌缩放
end

--- 拖拽取消：将卡牌从场景根回挂到容器（保持世界位置不变）
---@param card3d table Card3D 实例
function HandFan:reattachAfterDrag(card3d)
    local wPos = card3d.node.worldPosition
    local wRot = card3d.node.worldRotation
    self.container:AddChild(card3d.node)
    card3d.node.worldPosition = wPos
    card3d.node.worldRotation = wRot
    self.isDraggingCard = false  -- 拖拽结束：恢复缩放控制
end

-- ============================================================================
-- 布局计算（容器局部空间）
-- ============================================================================

--- 计算当前手牌的各卡目标位置和旋转（容器局部坐标）
---@param hoveredIdx number 当前悬停卡的索引（0=无悬停）
---@return table[] slots  { pos=Vector3, rot=Quaternion }
function HandFan:computeSlots(hoveredIdx)
    local n = #self.cards
    if n == 0 then return {} end

    local cfg = self.cfg

    -- 收起状态使用压缩参数
    local maxTotalW  = cfg.maxTotalW
    local maxSpacing = cfg.maxSpacing
    local minSpacing = cfg.minSpacing
    local maxArcDeg  = cfg.maxArcDeg
    if self.collapsed then
        maxTotalW  = cfg.collapsedMaxTotalW  or cfg.maxTotalW  * 0.5
        maxSpacing = cfg.collapsedMaxSpacing or cfg.maxSpacing * 0.56
        minSpacing = cfg.collapsedMinSpacing or cfg.minSpacing * 0.56
        maxArcDeg  = cfg.collapsedMaxArcDeg  or cfg.maxArcDeg  * 0.63
    end

    -- 动态间距：牌越多间距越小
    local spacing = maxSpacing
    if n > 1 then
        local idealSpacing = maxTotalW / n
        spacing = math.max(minSpacing, math.min(maxSpacing, idealSpacing))
    end

    -- 动态弧度：牌越多扇面越大
    local arcDeg = cfg.minArcDeg + (maxArcDeg - cfg.minArcDeg) * math.min(n / 10, 1.0)

    -- 卡牌前倾旋转（容器局部空间中面向镜头）
    local pitchRot = Quaternion(cfg.cardPitchDeg, Vector3.RIGHT)

    local slots = {}
    local totalWidth = (n - 1) * spacing

    for i = 1, n do
        -- 归一化位置: -0.5 ~ 0.5
        local t = n == 1 and 0 or ((i - 1) / (n - 1) - 0.5)

        -- X 位置（容器局部，左右展开）
        local x = t * totalWidth

        -- Z 弧线偏移（中间最前/最近，两侧后退）
        -- 在容器局部空间中 Z+ 是远离相机方向
        local arcZ = t * t * cfg.arcRadius * 0.02

        -- Y 高度：轻微弧形（中间略高）
        local arcY = (1 - t * t * 4) * 0.008

        -- 旋转：X 轴前倾 + Y 轴两侧微倾斜（底部收敛、顶部扩散 = 手持扇面）
        local yawAngle = t * arcDeg * 0.5
        local rot
        if cfg.extraRotation then
            rot = cfg.extraRotation * pitchRot * Quaternion(yawAngle, Vector3.UP)
        else
            rot = pitchRot * Quaternion(yawAngle, Vector3.UP)
        end

        -- 悬停让位：相邻卡牌向外推
        local hoverOffsetX = 0
        if hoveredIdx > 0 and i ~= hoveredIdx then
            local dist = i - hoveredIdx
            if math.abs(dist) <= 2 then
                local pushFactor = 1.0 - (math.abs(dist) - 1) * 0.5
                pushFactor = math.max(0, pushFactor)
                hoverOffsetX = (dist > 0 and 1 or -1) * cfg.hoverSpread * pushFactor
            end
        end

        -- 位置相对于容器原点（容器已在正确的相机局部位置）
        local pos = Vector3(
            x + hoverOffsetX,
            arcY,
            arcZ
        )

        slots[i] = { pos = pos, rot = rot }
    end

    return slots
end

-- ============================================================================
-- 布局应用
-- ============================================================================

--- 应用布局到所有手牌（带动画，容器局部坐标）
---@param animated boolean|nil 是否使用动画（默认 true）
function HandFan:applyLayout(animated)
    local slots = self:computeSlots(self.hoveredIndex)
    local n = #self.cards

    for i = 1, n do
        local card = self.cards[i]
        local slot = slots[i]

        if card and slot then
            -- 拖拽中的卡牌跳过布局（已脱离容器）
            if card.dragging then
                card.targetPos = slot.pos
                card.targetRot = slot.rot
                card.baseY = slot.pos.y
            elseif animated ~= false then
                Tween.killAll(card.node)
                Tween.to(card.node, self.cfg.layoutDur, {
                    position = slot.pos,
                    rotation = slot.rot,
                }, {
                    easing = Easing.outCubic,
                })
                card.targetPos = slot.pos
                card.targetRot = slot.rot
                card.baseY = slot.pos.y
            else
                card.node.position = slot.pos
                card.node.rotation = slot.rot
                card.targetPos = slot.pos
                card.targetRot = slot.rot
                card.baseY = slot.pos.y
            end
        end
    end
end

--- 设置悬停卡牌索引并重排
---@param index number 卡牌索引（0=取消悬停）
function HandFan:setHoveredIndex(index)
    if self.hoveredIndex == index then return end
    self.hoveredIndex = index
    self:applyLayout(true)
end

--- 根据 Card3D 实例查找索引
---@param card3d table
---@return number 索引（0=未找到）
function HandFan:indexOf(card3d)
    for i, c in ipairs(self.cards) do
        if c == card3d then return i end
    end
    return 0
end

--- 获取指定卡牌的当前目标 slot（容器局部坐标，供 snapBack 使用）
---@param card3d table
---@return table|nil {pos=Vector3, rot=Quaternion}
function HandFan:getSlotForCard(card3d)
    local idx = self:indexOf(card3d)
    if idx == 0 then return nil end
    local slots = self:computeSlots(0)
    return slots[idx]
end

-- ============================================================================
-- 发牌序列
-- ============================================================================

--- 从指定世界位置发牌到手牌中（带动画）
---@param fromWorldPos Vector3 牌库世界位置
---@param onAllDone function|nil 全部发完后回调
function HandFan:dealAll(fromWorldPos, onAllDone)
    local slots = self:computeSlots(0)
    local n = #self.cards
    if n == 0 then
        if onAllDone then onAllDone() end
        return
    end

    -- 将世界坐标的牌库位置转换为容器局部坐标
    local localFrom = self:worldToLocal(fromWorldPos)

    local doneCount = 0
    for i = 1, n do
        local card = self.cards[i]
        local slot = slots[i]

        if card and slot then
            -- dealSlide 内部操作 node.position（即容器局部坐标）
            CardAnimator.dealSlide(card, localFrom, slot.pos, slot.rot, i, function()
                doneCount = doneCount + 1
                if doneCount >= n and onAllDone then
                    onAllDone()
                end
            end)
        end
    end
end

--- 抽牌：从牌堆世界位置飞入手牌（单张）
---@param card3d table 已通过 addCard 加入手牌的卡牌
---@param fromWorldPos Vector3 牌库世界位置
---@param onComplete function|nil
function HandFan:drawFromDeck(card3d, fromWorldPos, onComplete)
    local slots = self:computeSlots(0)
    local idx = self:indexOf(card3d)
    if idx == 0 then return end

    local slot = slots[idx]
    if not slot then return end

    local localFrom = self:worldToLocal(fromWorldPos)

    CardAnimator.dealSlide(card3d, localFrom, slot.pos, slot.rot, 1, function()
        self:applyLayout(true)
        if onComplete then onComplete() end
    end)
end

-- ============================================================================
-- 收起 / 展开（仅 isCollapseEnabled=true 的扇面有效）
-- ============================================================================

--- 切换收起/展开状态，平滑移动容器位置并重排卡牌
---@param collapsed boolean  true=收起, false=展开
---@param animated  boolean|nil 默认 true
function HandFan:setCollapsed(collapsed, animated)
    if not self.isCollapseEnabled then return end
    if self.collapsed == collapsed then return end
    -- 拖拽进行中时不缩小手牌（可以展开，但不触发 collapsedScale）
    if collapsed and self.isDraggingCard then return end
    self.collapsed = collapsed

    local cfg = self.cfg
    local targetPos   = collapsed and cfg.collapsedPos   or cfg.containerLocalPos
    local targetScale = collapsed and cfg.collapsedScale or 1.0

    -- 平滑移动容器（Tween 容器节点位置）
    if animated ~= false then
        Tween.killAll(self.container)
        Tween.to(self.container, 0.28, { position = targetPos }, { easing = Easing.outCubic })
    else
        self.container.position = targetPos
    end

    -- 更新卡牌缩放
    for _, card in ipairs(self.cards) do
        if not card.dragging then
            local baseScale = self.cfg.cardScale or 1.0
            local s = baseScale * targetScale
            if animated ~= false then
                Tween.killAll(card.node)
                Tween.to(card.node, 0.28, { scale = Vector3(s, s, s) }, { easing = Easing.outCubic })
            else
                card.node.scale = Vector3(s, s, s)
            end
        end
    end

    -- 重排位置（给 computeSlots 用到的新间距）
    self:applyLayout(animated ~= false)
end

--- 获取玩家手牌扇面的近似 2D 屏幕包围盒（NanoVG 逻辑像素）
--- 用于检测是否点击到扇面区域
---@param camera Camera
---@param vpW number NanoVG 逻辑宽
---@param vpH number NanoVG 逻辑高
---@return number, number, number, number
function HandFan:getScreenBounds(camera, vpW, vpH)
    local node = self.container
    local worldPos = node:GetWorldPosition()
    local camNode  = camera:GetNode()
    local toFan    = worldPos - camNode:GetWorldPosition()
    local depth    = toFan:DotProduct(camNode:GetWorldDirection())
    if depth <= 0 then return 0, 0, 0, 0 end

    local sp = camera:WorldToScreenPoint(worldPos)
    local cx = sp.x * vpW
    local cy = sp.y * vpH

    -- 面积近似：以展开宽度 maxTotalW * fovFactor 作为参考
    local fovFactor = vpH / (2 * depth * math.tan(math.rad(camera.fov * 0.5)))
    local halfW = (self.collapsed and self.cfg.collapsedMaxTotalW or self.cfg.maxTotalW) * fovFactor * 0.6
    local halfH = 0.55 * fovFactor   -- 卡牌高度约 0.55 个单位

    return cx - halfW, cy - halfH * 0.4, halfW * 2, halfH * 1.4
end

return HandFan

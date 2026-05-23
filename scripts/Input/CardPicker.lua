-- ============================================================================
-- Input/CardPicker.lua - 炉石风格拖拽出牌交互
-- 状态机：IDLE → HOVER → DRAG_PENDING → DRAGGING → PLAY / SNAP_BACK
-- ============================================================================

local CardAnimator = require("Anim.CardAnimator")

local Card3D_WIDTH = 0.63  -- Card3D.WIDTH 常量

local CardPicker = {}
CardPicker.__index = CardPicker

-- 拖拽阈值（像素）
local DRAG_THRESHOLD = 5

-- 出牌线（归一化屏幕 Y，越大越靠近屏幕底部）
local PLAY_LINE_Y = 0.60
-- 充能线（归一化屏幕 Y，卡牌拖到此线以下释放 = Pitch 充能）
local PITCH_LINE_Y = 0.85

--- 屏幕归一化坐标 → 与水平面 Y=planeY 的交点
---@param camera Camera
---@param normX number
---@param normY number
---@param planeY number
---@return Vector3|nil
local function screenToPlane(camera, normX, normY, planeY)
    local ray = camera:GetScreenRay(normX, normY)
    local o = ray.origin
    local d = ray.direction
    if math.abs(d.y) < 0.0001 then return nil end
    local t = (planeY - o.y) / d.y
    if t < 0 then return nil end
    return Vector3(o.x + d.x * t, planeY, o.z + d.z * t)
end

--- 创建拾取器
---@param scene Scene
---@param camera Camera
---@return table picker
function CardPicker.create(scene, camera)
    local picker = setmetatable({}, CardPicker)
    picker.scene = scene
    picker.camera = camera
    picker.cards = {}             -- {nodeID => card3d} 映射（可拖拽）
    picker.displayCards = {}      -- {nodeID => card3d} 映射（仅 hover 展示，不可拖拽）
    picker.hoveredCard = nil      -- 当前悬停的 card3d
    picker.enabled = true

    -- 拖拽状态机
    picker.state = "IDLE"         -- IDLE / HOVER / DRAG_PENDING / DRAGGING
    picker.dragCard = nil         -- 当前拖拽的卡牌
    picker.dragStartMX = 0        -- 按下时鼠标 X（像素）
    picker.dragStartMY = 0        -- 按下时鼠标 Y（像素）
    picker.dragPlaneY = 0.3       -- 拖拽跟随平面 Y（与手牌 handCenterY 一致）

    -- 回调（由 main.lua 设置）
    picker.onDragBegin = nil      -- function(card3d) 拖拽开始（用于脱离容器）
    picker.onDragPlay = nil       -- function(card3d) 拖过出牌线释放
    picker.onDragPitch = nil      -- function(card3d) 拖到充能区释放
    picker.onDragCancel = nil     -- function(card3d) 未过出牌线释放

    return picker
end

--- 注册可拾取的卡牌
---@param card3d table Card3D 实例
function CardPicker:register(card3d)
    if card3d.node then
        self.cards[card3d.node:GetID()] = card3d
    end
end

--- 取消注册
---@param card3d table
function CardPicker:unregister(card3d)
    if card3d.node then
        self.cards[card3d.node:GetID()] = nil
        self.displayCards[card3d.node:GetID()] = nil
    end
end

--- 注册仅展示卡牌（可 hover 查看 tooltip，不可拖拽）
---@param card3d table Card3D 实例
function CardPicker:registerDisplay(card3d)
    if card3d.node then
        self.displayCards[card3d.node:GetID()] = card3d
    end
end

--- 取消仅展示注册
---@param card3d table
function CardPicker:unregisterDisplay(card3d)
    if card3d.node then
        self.displayCards[card3d.node:GetID()] = nil
    end
end

--- 清空所有注册
function CardPicker:clear()
    self.cards = {}
    self.displayCards = {}
    self.hoveredCard = nil
    self.state = "IDLE"
    self.dragCard = nil
end

--- 获取当前状态
---@return string
function CardPicker:getState()
    return self.state
end

--- 获取当前拖拽的卡牌
---@return table|nil
function CardPicker:getDragCard()
    return self.dragCard
end

--- 当前鼠标是否在出牌线上方
---@param screenH number 屏幕高度
---@return boolean
function CardPicker:isAbovePlayLine(screenH)
    if screenH == 0 then return false end
    local my = input.mousePosition.y
    return (my / screenH) < PLAY_LINE_Y
end

--- 获取出牌线归一化 Y
---@return number
function CardPicker.getPlayLineY()
    return PLAY_LINE_Y
end

--- 当前鼠标是否在充能线下方（屏幕底部区域）
---@param screenH number 屏幕高度
---@return boolean
function CardPicker:isBelowPitchLine(screenH)
    if screenH == 0 then return false end
    local my = input.mousePosition.y
    return (my / screenH) > PITCH_LINE_Y
end

--- 获取充能线归一化 Y
---@return number
function CardPicker.getPitchLineY()
    return PITCH_LINE_Y
end

-- ============================================================================
-- Octree Raycast
-- ============================================================================

--- 射线拾取
---@param mx number 鼠标 X
---@param my number 鼠标 Y
---@param sw number 屏幕宽
---@param sh number 屏幕高
---@return table|nil 命中的 card3d
function CardPicker:raycast(mx, my, sw, sh)
    local ray = self.camera:GetScreenRay(mx / sw, my / sh)

    local octree = self.scene:GetComponent("Octree")
    if octree == nil then return nil end

    local result = octree:RaycastSingle(ray, RAY_TRIANGLE, 100.0, DRAWABLE_GEOMETRY)
    if result.drawable == nil then return nil end

    local hitNode = result.drawable:GetNode()
    if hitNode == nil then return nil end

    -- 向上查找（可能命中子节点）
    local nodeID = hitNode:GetID()
    local parentID = hitNode:GetParent() and hitNode:GetParent():GetID() or nil

    local card = self.cards[nodeID] or self.displayCards[nodeID]
    if card == nil and parentID then
        card = self.cards[parentID] or self.displayCards[parentID]
    end

    if card == nil then
        log:Write(LOG_DEBUG, string.format("[CardPicker] raycast miss: hitNode=%s nodeID=%d parentID=%s",
            hitNode.name, nodeID, tostring(parentID)))
    end

    return card
end

-- ============================================================================
-- 每帧更新（状态机驱动）
-- ============================================================================

--- 清除当前悬停状态（鼠标被 UI 消费时调用）
function CardPicker:clearHover()
    if self.hoveredCard and not self.hoveredCard.dragging then
        self.hoveredCard:setHovered(false)
        CardAnimator.hoverExit(self.hoveredCard)
    end
    self.hoveredCard = nil
    if self.state == "HOVER" then
        self.state = "IDLE"
    end
end

--- 每帧更新
---@param screenW number
---@param screenH number
function CardPicker:update(screenW, screenH)
    if not self.enabled then return end
    if screenW == 0 or screenH == 0 then return end

    local mx = input.mousePosition.x
    local my = input.mousePosition.y

    local state = self.state

    -- ================================================================
    -- IDLE / HOVER: 射线检测悬停
    -- ================================================================
    if state == "IDLE" or state == "HOVER" then
        local hitCard = self:raycast(mx, my, screenW, screenH)

        -- 悬停状态变化
        if hitCard ~= self.hoveredCard then
            -- 离开旧卡
            if self.hoveredCard and not self.hoveredCard.dragging then
                self.hoveredCard:setHovered(false)
                CardAnimator.hoverExit(self.hoveredCard)
            end

            -- 进入新卡
            if hitCard and not hitCard.dragging then
                hitCard:setHovered(true)
                -- 计算鼠标在卡牌上的归一化 X（-1 ~ 1）
                local normX = 0
                if hitCard.node and screenW > 0 then
                    local cardWorldX = hitCard.node.worldPosition.x
                    local camRay = self.camera:GetScreenRay(mx / screenW, my / screenH)
                    -- 用射线方向在卡牌平面上的投影估算偏移
                    local mouseWorldX = camRay.origin.x + camRay.direction.x * ((hitCard.node.worldPosition.y - camRay.origin.y) / (camRay.direction.y + 0.0001))
                    local halfW = Card3D_WIDTH or 0.63
                    normX = math.max(-1, math.min(1, (mouseWorldX - cardWorldX) / (halfW * 0.5)))
                end
                CardAnimator.hoverEnter(hitCard, normX)
            end

            self.hoveredCard = hitCard
        end

        -- 状态转换
        if hitCard then
            self.state = "HOVER"

            -- 鼠标按下 → DRAG_PENDING（仅可拖拽卡牌）
            local isDraggable = hitCard.node and self.cards[hitCard.node:GetID()] ~= nil
            if isDraggable and input:GetMouseButtonPress(MOUSEB_LEFT) then
                self.state = "DRAG_PENDING"
                self.dragCard = hitCard
                self.dragStartMX = mx
                self.dragStartMY = my
                -- 使用世界坐标 Y（卡牌可能在相机容器中）
                self.dragPlaneY = hitCard.node.worldPosition.y
            end
        else
            self.state = "IDLE"
        end

    -- ================================================================
    -- DRAG_PENDING: 等待拖拽阈值
    -- ================================================================
    elseif state == "DRAG_PENDING" then
        -- 鼠标释放 → 取消（没有拖动就松手）
        if not input:GetMouseButtonDown(MOUSEB_LEFT) then
            self.state = "HOVER"
            self.dragCard = nil
            return
        end

        -- 检查移动距离
        local dx = mx - self.dragStartMX
        local dy = my - self.dragStartMY
        local dist = math.sqrt(dx * dx + dy * dy)

        if dist > DRAG_THRESHOLD then
            -- 进入拖拽！
            self.state = "DRAGGING"
            local card = self.dragCard

            -- 取消悬停动画
            if card.hovered then
                card:setHovered(false)
            end

            -- 通知脱离容器（main.lua 调用 HandFan:detachForDrag）
            if self.onDragBegin then
                self.onDragBegin(card)
            end

            -- 更新拖拽平面为脱离后的世界 Y
            self.dragPlaneY = card.node.worldPosition.y
            log:Write(LOG_INFO, string.format("[CardPicker] drag start: card=%s worldY=%.3f",
                card.node.name, self.dragPlaneY))

            -- 启动拖拽动效
            CardAnimator.dragStart(card)


        end

    -- ================================================================
    -- DRAGGING: 卡牌跟随鼠标
    -- ================================================================
    elseif state == "DRAGGING" then
        local card = self.dragCard
        if not card then
            self.state = "IDLE"
            return
        end

        -- 卡牌跟随鼠标（射线-平面交点）
        local normX = mx / screenW
        local normY = my / screenH
        local worldPos = screenToPlane(self.camera, normX, normY, self.dragPlaneY)

        if worldPos then
            card.node.position = worldPos
        end

        -- 鼠标释放 → 判断出牌线 / 充能线
        if not input:GetMouseButtonDown(MOUSEB_LEFT) then
            local releaseY = input.mousePosition.y
            local aboveLine = self:isAbovePlayLine(screenH)
            local belowPitch = self:isBelowPitchLine(screenH)
            log:Write(LOG_INFO, string.format("[CardPicker] drag release: mouseY=%d screenH=%d normY=%.3f aboveLine=%s belowPitch=%s",
                releaseY, screenH, screenH > 0 and (releaseY/screenH) or 0, tostring(aboveLine), tostring(belowPitch)))

            if aboveLine then
                -- 出牌！（拖过出牌线上方）
                card:setDragging(false)
                self.state = "IDLE"
                self.dragCard = nil
                self.hoveredCard = nil

                if self.onDragPlay then
                    self.onDragPlay(card)
                end
            elseif belowPitch then
                -- 充能！（拖到充能线下方）
                card:setDragging(false)
                self.state = "IDLE"
                self.dragCard = nil
                self.hoveredCard = nil

                if self.onDragPitch then
                    self.onDragPitch(card)
                else
                    -- 无充能回调，回弹
                    if self.onDragCancel then
                        self.onDragCancel(card)
                    end
                end
            else
                -- 取消拖拽 → 弹回（出牌线与充能线之间）
                self.state = "IDLE"
                self.dragCard = nil
                self.hoveredCard = nil

                if self.onDragCancel then
                    self.onDragCancel(card)
                end
            end
        end
    end
end

return CardPicker

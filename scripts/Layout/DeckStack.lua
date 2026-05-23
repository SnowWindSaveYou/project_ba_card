-- ============================================================================
-- Layout/DeckStack.lua - 牌堆叠放视觉
-- 3-5 张微错位叠放模拟牌堆厚度，抽牌飞出动画
-- ============================================================================

local Card3D       = require("Card.Card3D")
local CardData     = require("Card.CardData")
local Tween        = require("Core.Tween")
local Easing       = require("Core.Easing")

local DeckStack = {}
DeckStack.__index = DeckStack

-- ============================================================================
-- 常量
-- ============================================================================

local MAX_VISUAL_CARDS = 5    -- 最多显示几张叠放卡
local STACK_OFFSET_Y   = 0.003  -- 每张 Y 偏移（叠放高度）
local STACK_OFFSET_X   = 0.003  -- 每张 X 随机偏移范围
local STACK_OFFSET_Z   = 0.002  -- 每张 Z 随机偏移范围
local STACK_ROT_RANGE  = 1.5    -- 每张随机旋转范围（度）

-- 抽牌动画
local DRAW_DURATION    = 0.2
local DRAW_ARC_Y       = 0.5    -- 抽牌弧线高度

-- ============================================================================
-- 构造
-- ============================================================================

--- 创建牌堆视觉
---@param scene Scene
---@param position Vector3 牌堆中心位置
---@param totalCount number 牌堆总数（逻辑数量）
---@param faceUp boolean|nil 是否正面朝上（默认 false = 背面）
---@return table deckStack
function DeckStack.create(scene, position, totalCount, faceUp)
    local stack = setmetatable({}, DeckStack)

    stack.scene = scene
    stack.position = position
    stack.totalCount = totalCount or 0
    stack.faceUp = faceUp == true

    -- 创建视觉卡牌
    stack.visualCards = {}
    stack:rebuildVisuals()

    return stack
end

-- ============================================================================
-- 视觉重建
-- ============================================================================

--- 根据当前总数重建视觉叠放
function DeckStack:rebuildVisuals()
    -- 清理旧视觉卡
    for _, vc in ipairs(self.visualCards) do
        vc:destroy()
    end
    self.visualCards = {}

    if self.totalCount <= 0 then return end

    -- 创建视觉卡（数量=min(总数, MAX_VISUAL_CARDS)）
    local visCount = math.min(self.totalCount, MAX_VISUAL_CARDS)

    -- 伪数据（仅用于视觉展示）
    local dummyData = CardData.new({
        id = "deck_back",
        name = "牌库",
        type = "action",
        pitch = 0,
    })

    for i = 1, visCount do
        local card = Card3D.create(self.scene, dummyData, self.faceUp)

        -- 错位叠放
        local offsetX = (math.random() - 0.5) * 2 * STACK_OFFSET_X
        local offsetZ = (math.random() - 0.5) * 2 * STACK_OFFSET_Z
        local offsetY = (i - 1) * STACK_OFFSET_Y
        local rotY    = (math.random() - 0.5) * 2 * STACK_ROT_RANGE

        local pos = Vector3(
            self.position.x + offsetX,
            self.position.y + offsetY,
            self.position.z + offsetZ
        )
        card:setPosition(pos)
        card:setRotation(Quaternion(0, rotY, 0))

        self.visualCards[i] = card
    end
end

-- ============================================================================
-- 牌堆操作
-- ============================================================================

--- 设置牌堆总数并更新视觉
---@param count number
function DeckStack:setCount(count)
    local oldCount = self.totalCount
    self.totalCount = math.max(0, count)

    -- 数量变化较大才重建视觉
    local oldVis = math.min(oldCount, MAX_VISUAL_CARDS)
    local newVis = math.min(self.totalCount, MAX_VISUAL_CARDS)

    if oldVis ~= newVis then
        self:rebuildVisuals()
    end
end

--- 获取当前总数
---@return number
function DeckStack:getCount()
    return self.totalCount
end

--- 获取顶部位置（最上面一张卡的位置）
---@return Vector3
function DeckStack:getTopPos()
    local n = math.min(self.totalCount, MAX_VISUAL_CARDS)
    return Vector3(
        self.position.x,
        self.position.y + n * STACK_OFFSET_Y,
        self.position.z
    )
end

-- ============================================================================
-- 抽牌动画
-- ============================================================================

--- 从牌堆顶部抽出一张卡（动画飞向目标位置）
---@param targetCard table Card3D 实例（会被移动到目标位置）
---@param targetPos Vector3 目标位置
---@param targetRot Quaternion 目标旋转
---@param onComplete function|nil
function DeckStack:drawTo(targetCard, targetPos, targetRot, onComplete)
    -- 设置起始位置为牌堆顶部
    local topPos = self:getTopPos()
    targetCard:setPosition(topPos)
    targetCard:setRotation(Quaternion(0, 0, 0))

    -- 减少计数
    self.totalCount = math.max(0, self.totalCount - 1)

    -- 更新视觉
    local oldVis = #self.visualCards
    local newVis = math.min(self.totalCount, MAX_VISUAL_CARDS)
    if oldVis > newVis and oldVis > 0 then
        -- 移除顶部视觉卡
        local topVis = self.visualCards[oldVis]
        if topVis then
            topVis:destroy()
            self.visualCards[oldVis] = nil
        end
    end

    -- 弧线抽牌动画
    local startPos = topPos
    local proxy = { t = 0 }
    local startRot = Quaternion(0, 0, 0)

    Tween.to(proxy, DRAW_DURATION, { t = 1.0 }, {
        easing = Easing.outCubic,
        onUpdate = function(_, easedT)
            local x = startPos.x + (targetPos.x - startPos.x) * easedT
            local z = startPos.z + (targetPos.z - startPos.z) * easedT
            local y = startPos.y + (targetPos.y - startPos.y) * easedT
                + DRAW_ARC_Y * 4 * easedT * (1 - easedT)

            targetCard.node.position = Vector3(x, y, z)
            targetCard.node.rotation = startRot:Slerp(targetRot, easedT)
        end,
        onComplete = function()
            targetCard.targetPos = targetPos
            targetCard.targetRot = targetRot
            targetCard.baseY = targetPos.y
            targetCard.animState = "idle"
            if onComplete then onComplete() end
        end,
    })
end

-- ============================================================================
-- 清理
-- ============================================================================

--- 销毁牌堆所有视觉卡
function DeckStack:destroy()
    for _, vc in ipairs(self.visualCards) do
        vc:destroy()
    end
    self.visualCards = {}
    self.totalCount = 0
end

return DeckStack

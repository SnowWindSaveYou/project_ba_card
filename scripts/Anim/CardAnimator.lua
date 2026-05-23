-- ============================================================================
-- Anim/CardAnimator.lua - Balatro 风格 6 大卡牌动效
-- idle_wobble / hover_tilt / select_bounce / deal_slide / play_throw / discard_toss
-- ============================================================================

local Tween  = require("Core.Tween")
local Easing = require("Core.Easing")

local CardAnimator = {}

-- ============================================================================
-- 动效参数
-- ============================================================================

local PARAMS = {
    -- 待机摇摆
    wobble = {
        ampY    = 0.02,   -- Y 轴振幅(米)
        freq    = 1.5,    -- 频率(Hz)
    },
    -- 悬停倾斜
    hover = {
        liftY   = 0.3,    -- 上浮距离
        tiltDeg = 8.0,    -- 最大倾斜度数
        duration = 0.15,  -- 过渡时长
    },
    -- 选中弹跳
    select = {
        liftY   = 0.5,    -- 弹起高度
        scaleMul = 1.15,  -- 放大倍率
        duration = 0.3,
    },
    -- 发牌滑入
    deal = {
        duration = 0.25,  -- 每张时长
        stagger  = 0.08,  -- 每张延迟
    },
    -- 出牌抛出
    play = {
        duration = 0.4,
        arcY     = 1.0,   -- 弧线最高点
        scaleMul = 0.8,   -- 缩小
    },
    -- 弃牌甩出
    discard = {
        duration = 0.3,
        rotRange = 15,    -- 随机旋转范围(度)
        offsetX  = 2.5,   -- X 偏移
    },
}

-- ============================================================================
-- 1. 待机摇摆 (idle_wobble) — 持续性，在 Update 中调用
-- ============================================================================

--- 更新卡牌的 idle wobble（每帧调用）
---@param card3d table Card3D 实例
---@param time number 全局游戏时间
function CardAnimator.updateWobble(card3d, time)
    if card3d.hovered or card3d.dragging then return end
    if card3d.animState == "animating" then return end

    local t = time * PARAMS.wobble.freq * math.pi * 2 + card3d.wobblePhase
    local offsetY = math.sin(t) * PARAMS.wobble.ampY

    local pos = card3d.node.position
    card3d.node.position = Vector3(pos.x, card3d.baseY + offsetY, pos.z)
end

-- ============================================================================
-- 2. 悬停倾斜 (hover_tilt) — Tween 驱动
-- ============================================================================

--- 鼠标悬停：上浮 + 倾斜跟随
---@param card3d table
---@param mouseNormX number 鼠标在卡牌上的归一化 X 位置(-1~1)
function CardAnimator.hoverEnter(card3d, mouseNormX)
    if card3d.animState == "animating" then return end

    Tween.killAll(card3d.node)
    card3d.hovered = true

    local tiltAngle = (mouseNormX or 0) * PARAMS.hover.tiltDeg

    Tween.to(card3d.node, PARAMS.hover.duration, {
        position = Vector3(
            card3d.targetPos.x,
            card3d.baseY + PARAMS.hover.liftY,
            card3d.targetPos.z
        ),
    }, {
        easing = Easing.outCubic,
    })

    -- 倾斜（绕 Z 轴）
    local baseRot = card3d.targetRot
    local tiltRot = baseRot * Quaternion(0, 0, tiltAngle)
    Tween.to(card3d.node, PARAMS.hover.duration, {
        rotation = tiltRot,
    }, {
        easing = Easing.outCubic,
    })
end

--- 鼠标离开：回落
---@param card3d table
function CardAnimator.hoverExit(card3d)
    if card3d.animState == "animating" then return end

    Tween.killAll(card3d.node)
    card3d.hovered = false

    Tween.to(card3d.node, PARAMS.hover.duration, {
        position = Vector3(
            card3d.targetPos.x,
            card3d.baseY,
            card3d.targetPos.z
        ),
        rotation = card3d.targetRot,
    }, {
        easing = Easing.outCubic,
    })
end

-- ============================================================================
-- 3. 拖拽开始 (drag_start) — 放大 + 上浮
-- ============================================================================

--- 开始拖拽卡牌：放大 + 微上浮
---@param card3d table
function CardAnimator.dragStart(card3d)
    Tween.killAll(card3d.node)
    card3d.dragging = true
    card3d.animState = "dragging"

    local s = 1.2
    Tween.to(card3d.node, 0.15, {
        scale = Vector3(s, s, s),
    }, {
        easing = Easing.outCubic,
    })
end

-- ============================================================================
-- 3b. 拖拽取消弹回 (snap_back) — 弹性回位
-- ============================================================================

--- 拖拽取消：弹回手牌原位
---@param card3d table
---@param targetPos Vector3 目标位置
---@param targetRot Quaternion 目标旋转
---@param onComplete function|nil
function CardAnimator.snapBack(card3d, targetPos, targetRot, onComplete)
    Tween.killAll(card3d.node)

    -- 弹性回位
    Tween.to(card3d.node, 0.4, {
        position = targetPos,
        rotation = targetRot,
        scale = Vector3(1, 1, 1),
    }, {
        easing = Easing.outElastic,
        onComplete = function()
            card3d.dragging = false
            card3d.animState = "idle"
            card3d.targetPos = targetPos
            card3d.targetRot = targetRot
            card3d.baseY = targetPos.y
            if onComplete then onComplete() end
        end,
    })
end

-- ============================================================================
-- 4. 发牌滑入 (deal_slide) — 从牌库位置滑入手牌位置
-- ============================================================================

--- 发牌动画
---@param card3d table
---@param fromPos Vector3 起始位置(牌库)
---@param toPos Vector3 目标位置(手牌槽)
---@param toRot Quaternion 目标旋转
---@param index number 第几张（用于延迟计算）
---@param onComplete function|nil
function CardAnimator.dealSlide(card3d, fromPos, toPos, toRot, index, onComplete)
    card3d.animState = "animating"
    card3d.node.position = fromPos
    card3d.node.rotation = Quaternion(0, 180, 0)  -- 背面朝上

    local delay = (index - 1) * PARAMS.deal.stagger

    -- 滑入
    Tween.to(card3d.node, PARAMS.deal.duration, {
        position = toPos,
        rotation = toRot,
    }, {
        easing = Easing.outCubic,
        delay = delay,
        onComplete = function()
            card3d.targetPos = toPos
            card3d.targetRot = toRot
            card3d.baseY = toPos.y
            card3d.animState = "idle"
            if onComplete then onComplete() end
        end,
    })
end

-- ============================================================================
-- 5. 出牌抛出 (play_throw) — 弧线抛向战斗链区域
-- ============================================================================

--- 出牌动画
---@param card3d table
---@param targetPos Vector3 战斗链目标位置
---@param onComplete function|nil
function CardAnimator.playThrow(card3d, targetPos, onComplete)
    card3d.animState = "animating"

    local startPos = card3d.node.worldPosition
    local startRot = card3d.node.worldRotation
    local arcY = PARAMS.play.arcY
    local dur = PARAMS.play.duration

    -- 目标旋转：平放在桌面（无倾斜）
    local targetRot = Quaternion(0, 0, 0)

    -- 目标缩放：恢复原始大小
    local targetScale = Vector3(1, 1, 1)
    local startScale = card3d.node.scale

    -- 使用自定义 onUpdate 实现弧线 + 旋转过渡
    local proxy = { t = 0 }

    Tween.to(proxy, dur, { t = 1.0 }, {
        easing = Easing.inOutQuad,
        onUpdate = function(_, easedT)
            -- 线性插值 XZ + 抛物线 Y（世界坐标）
            local x = startPos.x + (targetPos.x - startPos.x) * easedT
            local z = startPos.z + (targetPos.z - startPos.z) * easedT
            local y = startPos.y + (targetPos.y - startPos.y) * easedT
                + arcY * 4 * easedT * (1 - easedT)  -- 抛物线

            card3d.node.worldPosition = Vector3(x, y, z)

            -- 旋转从拖拽姿态平滑过渡到平放
            card3d.node.worldRotation = startRot:Slerp(targetRot, easedT)

            -- 缩放恢复原始大小
            card3d.node.scale = Vector3(
                startScale.x + (targetScale.x - startScale.x) * easedT,
                startScale.y + (targetScale.y - startScale.y) * easedT,
                startScale.z + (targetScale.z - startScale.z) * easedT
            )
        end,
        onComplete = function()
            card3d.node.worldPosition = targetPos
            card3d.node.worldRotation = targetRot
            card3d.node.scale = targetScale
            card3d.targetPos = targetPos
            card3d.targetRot = targetRot
            card3d.baseY = targetPos.y
            card3d.animState = "idle"
            card3d.dragging = false
            if onComplete then onComplete() end
        end,
    })
end

-- ============================================================================
-- 6. 弃牌甩出 (discard_toss) — 随机偏移+旋转飞向弃牌堆
-- ============================================================================

--- 弃牌动画
---@param card3d table
---@param graveyardPos Vector3 弃牌堆位置
---@param onComplete function|nil
function CardAnimator.discardToss(card3d, graveyardPos, onComplete)
    card3d.animState = "animating"

    local randAngle = (math.random() - 0.5) * 2 * PARAMS.discard.rotRange
    local randOffX = (math.random() - 0.5) * 0.3

    Tween.to(card3d.node, PARAMS.discard.duration, {
        position = Vector3(
            graveyardPos.x + randOffX,
            graveyardPos.y + 0.01 * math.random(1, 10),
            graveyardPos.z
        ),
        rotation = Quaternion(0, randAngle, 0),
    }, {
        easing = Easing.inCubic,
        onComplete = function()
            card3d.animState = "idle"
            if onComplete then onComplete() end
        end,
    })
end

-- ============================================================================
-- 7. 出牌落地冲击 (impact_slam) — 缩放弹跳打击感
-- ============================================================================

--- 出牌落地时的冲击动效（缩放弹跳）
---@param card3d table
---@param onComplete function|nil
function CardAnimator.impactSlam(card3d, onComplete)
    local baseScale = Vector3(1, 1, 1)
    local bigScale = baseScale * 1.15

    -- 先放大
    Tween.to(card3d.node, 0.08, {
        scale = bigScale,
    }, {
        easing = Easing.outQuad,
        onComplete = function()
            -- 再弹回原尺寸
            Tween.to(card3d.node, 0.12, {
                scale = baseScale,
            }, {
                easing = Easing.outBounce,
                onComplete = onComplete,
            })
        end,
    })
end

return CardAnimator

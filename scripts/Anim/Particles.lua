-- ============================================================================
-- Anim/Particles.lua - NanoVG 2D 粒子系统（墨甲武林）
-- 轻量级粒子池，用于攻击火花、防御碎片、命中飞溅等视觉反馈
-- ============================================================================

local Theme = require("UI.Theme")

local Particles = {}

-- ============================================================================
-- 粒子池
-- ============================================================================

local MAX_PARTICLES = 120
local pool = {}
local activeCount = 0

-- 预分配粒子对象
for i = 1, MAX_PARTICLES do
    pool[i] = {
        alive = false,
        x = 0, y = 0,
        vx = 0, vy = 0,
        life = 0, maxLife = 1,
        size = 3,
        r = 255, g = 255, b = 255,
        alpha = 255,
        gravity = 0,
        drag = 0,
        shrink = true,      -- 粒子是否随生命缩小
        shape = "circle",   -- "circle" | "square" | "diamond" | "spark"
    }
end

-- ============================================================================
-- 内部工具
-- ============================================================================

local function spawn(cfg)
    for i = 1, MAX_PARTICLES do
        if not pool[i].alive then
            local p = pool[i]
            p.alive   = true
            p.x       = cfg.x or 0
            p.y       = cfg.y or 0
            p.vx      = cfg.vx or 0
            p.vy      = cfg.vy or 0
            p.life    = cfg.life or 1.0
            p.maxLife = p.life
            p.size    = cfg.size or 3
            p.r       = cfg.r or 255
            p.g       = cfg.g or 255
            p.b       = cfg.b or 255
            p.alpha   = cfg.alpha or 255
            p.gravity = cfg.gravity or 80
            p.drag    = cfg.drag or 0.98
            p.shrink  = cfg.shrink ~= false
            p.shape   = cfg.shape or "circle"
            activeCount = activeCount + 1
            return p
        end
    end
    return nil
end

--- 在 (cx, cy) 处生成一组径向爆发粒子
local function burst(cx, cy, count, cfg)
    for _ = 1, count do
        local angle = math.random() * math.pi * 2
        local speed = (cfg.speedMin or 40) + math.random() * ((cfg.speedMax or 120) - (cfg.speedMin or 40))
        spawn({
            x       = cx + (math.random() - 0.5) * (cfg.spread or 6),
            y       = cy + (math.random() - 0.5) * (cfg.spread or 6),
            vx      = math.cos(angle) * speed,
            vy      = math.sin(angle) * speed,
            life    = (cfg.lifeMin or 0.4) + math.random() * ((cfg.lifeMax or 0.9) - (cfg.lifeMin or 0.4)),
            size    = (cfg.sizeMin or 2) + math.random() * ((cfg.sizeMax or 5) - (cfg.sizeMin or 2)),
            r       = cfg.r or 255,
            g       = cfg.g or 255,
            b       = cfg.b or 255,
            alpha   = cfg.alpha or 220,
            gravity = cfg.gravity or 60,
            drag    = cfg.drag or 0.97,
            shrink  = cfg.shrink ~= false,
            shape   = cfg.shape or "circle",
        })
    end
end

-- ============================================================================
-- 预设特效 API
-- ============================================================================

--- 攻击火花（朱砂红 + 橙色）
function Particles.attackSpark(x, y)
    burst(x, y, 14, {
        r = Theme.RED.r, g = Theme.RED.g, b = Theme.RED.b,
        speedMin = 60, speedMax = 180,
        sizeMin = 2, sizeMax = 5,
        lifeMin = 0.3, lifeMax = 0.7,
        gravity = 50, shape = "spark",
    })
    burst(x, y, 6, {
        r = Theme.ORANGE.r, g = Theme.ORANGE.g, b = Theme.ORANGE.b,
        speedMin = 30, speedMax = 100,
        sizeMin = 1.5, sizeMax = 3,
        lifeMin = 0.2, lifeMax = 0.5,
        gravity = 40, shape = "circle",
    })
end

--- 防御碎片（翡翠绿闪光）
function Particles.defendFlash(x, y)
    burst(x, y, 10, {
        r = Theme.GREEN.r, g = Theme.GREEN.g, b = Theme.GREEN.b,
        speedMin = 50, speedMax = 140,
        sizeMin = 2, sizeMax = 4,
        lifeMin = 0.3, lifeMax = 0.6,
        gravity = 30, shape = "diamond",
    })
end

--- 命中伤害（深红飞溅）
function Particles.damageHit(x, y)
    burst(x, y, 18, {
        r = 200, g = 40, b = 30,
        speedMin = 80, speedMax = 220,
        sizeMin = 2, sizeMax = 6,
        lifeMin = 0.4, lifeMax = 0.8,
        gravity = 120, shape = "square",
    })
    burst(x, y, 8, {
        r = 255, g = 100, b = 60,
        speedMin = 40, speedMax = 100,
        sizeMin = 1, sizeMax = 3,
        lifeMin = 0.3, lifeMax = 0.6,
        gravity = 80, shape = "circle",
    })
end

--- 格挡成功（白色/冰蓝碎片扩散）
function Particles.blockSuccess(x, y)
    burst(x, y, 12, {
        r = 220, g = 235, b = 255,
        speedMin = 60, speedMax = 160,
        sizeMin = 2, sizeMax = 4,
        lifeMin = 0.3, lifeMax = 0.6,
        gravity = 20, shape = "diamond",
    })
end

--- 连招链关闭（鎏金粒子喷射）
function Particles.chainClose(x, y)
    burst(x, y, 22, {
        r = Theme.GOLD.r, g = Theme.GOLD.g, b = Theme.GOLD.b,
        speedMin = 40, speedMax = 160,
        sizeMin = 2, sizeMax = 5,
        lifeMin = 0.5, lifeMax = 1.0,
        gravity = 40, shape = "spark",
    })
    burst(x, y, 10, {
        r = Theme.GOLD_BRIGHT.r, g = Theme.GOLD_BRIGHT.g, b = Theme.GOLD_BRIGHT.b,
        speedMin = 20, speedMax = 80,
        sizeMin = 1, sizeMax = 3,
        lifeMin = 0.4, lifeMax = 0.8,
        gravity = 20, shape = "circle",
    })
end

--- 充能转化（蓝紫漩涡上升）
function Particles.pitchConvert(x, y)
    for _ = 1, 10 do
        local angle = math.random() * math.pi * 2
        local radius = 10 + math.random() * 15
        spawn({
            x       = x + math.cos(angle) * radius,
            y       = y + math.sin(angle) * radius,
            vx      = math.cos(angle + 1.2) * 30,
            vy      = -40 - math.random() * 60,  -- 上升
            life    = 0.5 + math.random() * 0.5,
            size    = 2 + math.random() * 3,
            r       = 140, g = 120, b = 220,
            alpha   = 200,
            gravity = -30,  -- 反重力上浮
            drag    = 0.96,
            shape   = "circle",
        })
    end
end

-- ============================================================================
-- 更新
-- ============================================================================

function Particles.update(dt)
    if activeCount == 0 then return end

    local alive = 0
    for i = 1, MAX_PARTICLES do
        local p = pool[i]
        if p.alive then
            p.life = p.life - dt
            if p.life <= 0 then
                p.alive = false
            else
                p.vx = p.vx * p.drag
                p.vy = p.vy * p.drag
                p.vy = p.vy + p.gravity * dt
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt
                alive = alive + 1
            end
        end
    end
    activeCount = alive
end

-- ============================================================================
-- 绘制
-- ============================================================================

function Particles.draw(ctx)
    if activeCount == 0 then return end

    for i = 1, MAX_PARTICLES do
        local p = pool[i]
        if p.alive then
            local t = p.life / p.maxLife  -- 1→0 生命比
            local alpha = math.floor(p.alpha * t)
            local size = p.shrink and (p.size * (0.3 + 0.7 * t)) or p.size

            if alpha < 2 or size < 0.5 then goto continue end

            nvgBeginPath(ctx)

            if p.shape == "circle" then
                nvgCircle(ctx, p.x, p.y, size)
            elseif p.shape == "square" then
                nvgRect(ctx, p.x - size, p.y - size, size * 2, size * 2)
            elseif p.shape == "diamond" then
                nvgMoveTo(ctx, p.x, p.y - size)
                nvgLineTo(ctx, p.x + size, p.y)
                nvgLineTo(ctx, p.x, p.y + size)
                nvgLineTo(ctx, p.x - size, p.y)
                nvgClosePath(ctx)
            elseif p.shape == "spark" then
                -- 拉伸的线条（沿运动方向）
                local speed = math.sqrt(p.vx * p.vx + p.vy * p.vy)
                if speed > 1 then
                    local dx = p.vx / speed * size * 2
                    local dy = p.vy / speed * size * 2
                    nvgMoveTo(ctx, p.x - dx, p.y - dy)
                    nvgLineTo(ctx, p.x + dx, p.y + dy)
                    nvgStrokeColor(ctx, nvgRGBA(p.r, p.g, p.b, alpha))
                    nvgStrokeWidth(ctx, math.max(1, size * 0.6))
                    nvgStroke(ctx)
                    goto continue
                else
                    nvgCircle(ctx, p.x, p.y, size)
                end
            end

            nvgFillColor(ctx, nvgRGBA(p.r, p.g, p.b, alpha))
            nvgFill(ctx)

            ::continue::
        end
    end
end

--- 清除所有粒子
function Particles.clear()
    for i = 1, MAX_PARTICLES do
        pool[i].alive = false
    end
    activeCount = 0
end

--- 是否有活跃粒子
function Particles.isActive()
    return activeCount > 0
end

return Particles

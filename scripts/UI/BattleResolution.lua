-- ============================================================================
-- UI/BattleResolution.lua - 战斗结算全屏动画
--
-- 七阶段状态机：
--   IDLE → BLOCKS_ENTER → SCORES_REVEAL → SCORES_CLASH
--        → WINNER_GLOW → ATTACK_EXEC → DISSOLVE → IDLE
--
-- 架构：
--   - 3D 方块动画：通过注入的 BattleGrid 实例驱动
--   - 2D 叠层：NanoVG 负责分数数字、攻击射线、粒子、震动
--   - 外部触发：GameController 在 onChainClosed 后调用 BattleResolution.trigger()
-- ============================================================================

local Theme        = require("UI.Theme")
local CardAnimator = require("Anim.CardAnimator")

local BattleResolution = {}

-- ============================================================================
-- 阶段常量
-- ============================================================================

local STATE = {
    IDLE          = 0,
    PRE_DELAY     = 1,  -- 触发后等待延迟（isActive()=true，阻断外部边框操作）
    BLOCKS_ENTER  = 2,  -- 金色方块从左到右横扫桌面
    SCORES_REVEAL = 3,  -- 中心向外揭露红蓝分区
    SCORES_CLASH  = 4,  -- 分数对冲碰撞 + 波环
    WINNER_GLOW   = 5,  -- 胜方区域变金
    ATTACK_EXEC   = 6,  -- 攻击射线 + 火焰 + 星爆
    DISSOLVE      = 7,  -- 从中心消散
}

-- 各阶段持续时间（秒）
local DURATION = {
    [STATE.BLOCKS_ENTER]  = 2.0,
    [STATE.SCORES_REVEAL] = 1.8,
    [STATE.SCORES_CLASH]  = 2.2,
    [STATE.WINNER_GLOW]   = 1.5,
    [STATE.ATTACK_EXEC]   = 2.2,
    [STATE.DISSOLVE]      = 2.0,
}

-- ============================================================================
-- 缓动函数
-- ============================================================================

local function easeOutCubic(t)
    local u = 1 - t
    return 1 - u * u * u
end

local function easeInOutQuad(t)
    if t < 0.5 then return 2 * t * t
    else return 1 - ((-2 * t + 2) ^ 2) / 2 end
end

local function easeOutBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

local function lerp(a, b, t)
    t = math.max(0, math.min(1, t))
    return a + (b - a) * t
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

-- ============================================================================
-- 粒子系统
-- ============================================================================

local PARTICLES = {}
local PARTICLE_MAX = 400

local function spawnBurst(cx, cy, count, color, speed, sizeMin, sizeMax, life, glow)
    for _ = 1, count do
        if #PARTICLES >= PARTICLE_MAX then break end
        local angle = math.random() * math.pi * 2
        local spd   = speed * (0.6 + math.random() * 0.8)
        table.insert(PARTICLES, {
            x    = cx, y = cy,
            vx   = math.cos(angle) * spd,
            vy   = math.sin(angle) * spd,
            size = sizeMin + math.random() * (sizeMax - sizeMin),
            r    = color.r, g = color.g, b = color.b,
            rot  = math.random() * 360,
            rotSpd = (math.random() - 0.5) * 600,
            life = life * (0.7 + math.random() * 0.6),
            maxLife = life,
            glow = glow or false,
        })
    end
end

local function spawnDirectional(cx, cy, count, color, dirX, dirY, spread, speed, life)
    for _ = 1, count do
        if #PARTICLES >= PARTICLE_MAX then break end
        local angle = math.atan(dirY, dirX) + (math.random() - 0.5) * spread * 2
        local spd   = speed * (0.7 + math.random() * 0.6)
        table.insert(PARTICLES, {
            x    = cx, y = cy,
            vx   = math.cos(angle) * spd,
            vy   = math.sin(angle) * spd,
            size = 4 + math.random() * 10,
            r    = color.r, g = color.g, b = color.b,
            rot  = math.random() * 360,
            rotSpd = (math.random() - 0.5) * 500,
            life = (life or 0.6) * (0.7 + math.random() * 0.6),
            maxLife = life or 0.6,
            glow = true,
        })
    end
end

local function updateParticles(dt)
    for i = #PARTICLES, 1, -1 do
        local p = PARTICLES[i]
        p.x   = p.x + p.vx * dt
        p.y   = p.y + p.vy * dt
        p.vy  = p.vy + 120 * dt      -- 重力
        p.vx  = p.vx * (1 - 0.5 * dt)
        p.rot = p.rot + p.rotSpd * dt
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(PARTICLES, i)
        end
    end
end

local function drawParticles(ctx)
    for _, p in ipairs(PARTICLES) do
        local a = clamp(p.life / (p.maxLife * 0.3), 0, 1)
        local alpha = math.floor(a * 230)
        if alpha < 5 then goto continue end

        nvgSave(ctx)
        nvgTranslate(ctx, p.x, p.y)
        nvgRotate(ctx, math.rad(p.rot))

        -- 外发光层
        if p.glow then
            local gs = p.size * 2
            nvgBeginPath(ctx)
            nvgRect(ctx, -gs / 2, -gs / 2, gs, gs)
            nvgFillColor(ctx, nvgRGBA(
                math.floor(p.r * 255),
                math.floor(p.g * 255),
                math.floor(p.b * 255),
                math.floor(alpha * 0.18)))
            nvgFill(ctx)
        end

        -- 主体方块
        nvgBeginPath(ctx)
        nvgRect(ctx, -p.size / 2, -p.size / 2, p.size, p.size)
        nvgFillColor(ctx, nvgRGBA(
            math.floor(p.r * 255),
            math.floor(p.g * 255),
            math.floor(p.b * 255),
            alpha))
        nvgFill(ctx)

        -- 白描边
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, math.floor(alpha * 0.28)))
        nvgStrokeWidth(ctx, 1)
        nvgStroke(ctx)

        nvgRestore(ctx)
        ::continue::
    end
end

-- ============================================================================
-- 预置颜色（0~1 浮点，供粒子用）
-- ============================================================================

local COL = {
    GOLD  = { r = 1.0,  g = 0.82, b = 0.20 },
    RED   = { r = 0.82, g = 0.18, b = 0.28 },
    BLUE  = { r = 0.25, g = 0.32, b = 0.72 },
    PINK  = { r = 0.9,  g = 0.35, b = 0.5  },
    CYAN  = { r = 0.3,  g = 0.8,  b = 0.9  },
    WHITE = { r = 1.0,  g = 1.0,  b = 1.0  },
}

-- ============================================================================
-- 内部状态
-- ============================================================================

local state = {
    phase       = STATE.IDLE,
    timer       = 0,
    progress    = 0,

    -- 触发参数
    playerWon       = true,    -- 玩家（下半）是否获胜
    attackVal       = 0,       -- 攻击方攻击力（用于碰撞数字显示）
    defVal          = 0,       -- 防御方防御值（用于碰撞数字显示）
    damage          = 0,       -- 最后一次攻击伤害
    attackerIsUpper      = false,   -- 攻击方是否在上半区
    newAttackerIsLower   = nil,     -- DISSOLVE 后新攻击方位置（传给 grid:dissolve）

    -- BattleGrid 引用（由外部注入）
    grid        = nil,
    gridTriggered = false, -- 当前阶段是否已触发 grid 动画

    -- 震动
    screenShake = 0,
    shakeX      = 0,
    shakeY      = 0,
    gameTime    = 0,

    -- SCORES_CLASH 阶段状态
    clashTriggered    = false,   -- 碰撞瞬间是否已触发
    clashFlash        = 0,       -- 水平闪光强度
    vsScale           = 1.0,     -- VS 文字缩放
    scoreAScale       = 1.0,
    scoreBScale       = 1.0,
    scoreTilt         = 0,

    -- ATTACK_EXEC 阶段状态
    fireAlpha         = 0,
    dmgAlpha          = 0,
    dmgScale          = 1.0,
    attackImpactDone  = false,

    -- WINNER_GLOW 阶段状态
    winnerAlpha       = 0,
    crownScrollX      = 0,

    -- onDone 回调
    onDone = nil,

    -- 3D 卡牌引用（由 trigger 传入，可为 nil）
    attackCard3d = nil,
    defCard3d    = nil,

    -- 卡牌动画触发标志
    cardChargeTriggered = false,
    cardDashTriggered   = false,
    cardHitTriggered    = false,
}

-- ============================================================================
-- 公开 API
-- ============================================================================

--- 注入 BattleGrid 3D 实例
---@param gridInstance table BattleGrid 实例
function BattleResolution.setGrid(gridInstance)
    state.grid = gridInstance
end

--- 触发结算动画
---@param params table
---  playerWon       : boolean       玩家下半区是否获胜
---  attackVal       : number        攻击方攻击力
---  defVal          : number        防御方防御值
---  damage          : number        最终伤害（用于 "-N" 显示）
---  attackerIsUpper : boolean|nil   攻击方是否在上半区
---  attackCard3d    : table|nil     攻击方卡牌 Card3D 实例
---  defCard3d       : table|nil     防御方卡牌 Card3D 实例
---  onDone          : function|nil  动画结束后回调
function BattleResolution.trigger(params)
    if state.phase ~= STATE.IDLE then return end  -- 已在运行则忽略

    state.playerWon       = params.playerWon or false
    state.attackVal       = params.attackVal or 0
    state.defVal          = params.defVal    or 0
    state.damage          = params.damage    or 0
    state.attackerIsUpper    = (params.attackerIsUpper == nil) and false or params.attackerIsUpper
    state.newAttackerIsLower = params.newAttackerIsLower  -- 可为 nil
    state.onDone             = params.onDone
    state.attackCard3d       = params.attackCard3d or nil
    state.defCard3d          = params.defCard3d    or nil

    -- 重置
    PARTICLES = {}
    state.timer           = 0
    state.progress        = 0
    state.gridTriggered   = false
    state.clashTriggered  = false
    state.clashFlash              = 0
    state.clashParticlesPending   = false
    state.attackImpactParticlesPending = false
    state.vsScale         = 1.0
    state.scoreAScale     = 1.0
    state.scoreBScale     = 1.0
    state.scoreTilt       = 0
    state.fireAlpha       = 0
    state.dmgAlpha        = 0
    state.dmgScale        = 1.0
    state.attackImpactDone = false
    state.winnerAlpha     = 0
    state.screenShake     = 0
    state.cardChargeTriggered = false
    state.cardDashTriggered   = false
    state.cardHitTriggered    = false

    -- 进入预等待阶段：isActive() 立即返回 true，阻断外部边框操作
    -- 实际动画在 preDelayTimer 倒计时结束后才开始
    state.preDelayTimer = 1.0
    state.phase = STATE.PRE_DELAY
end

--- 是否正在播放
function BattleResolution.isActive()
    return state.phase ~= STATE.IDLE
end

--- 强制跳过（调试用）
function BattleResolution.skip()
    if state.phase ~= STATE.IDLE then
        PARTICLES = {}
        if state.grid then state.grid:dissolve(0.1) end
        -- 隐藏残留的 3D 卡牌节点
        if state.attackCard3d and state.attackCard3d.node then
            state.attackCard3d.node.enabled = false
        end
        if state.defCard3d and state.defCard3d.node then
            state.defCard3d.node.enabled = false
        end
        state.phase = STATE.IDLE
        if state.onDone then state.onDone() end
    end
end

-- ============================================================================
-- 阶段切换
-- ============================================================================

local function nextPhase()
    local cur = state.phase
    state.timer    = 0
    state.progress = 0
    state.gridTriggered = false

    if cur == STATE.BLOCKS_ENTER then
        state.phase = STATE.SCORES_REVEAL
    elseif cur == STATE.SCORES_REVEAL then
        state.phase = STATE.SCORES_CLASH
    elseif cur == STATE.SCORES_CLASH then
        state.phase = STATE.WINNER_GLOW
    elseif cur == STATE.WINNER_GLOW then
        state.phase = STATE.ATTACK_EXEC
    elseif cur == STATE.ATTACK_EXEC then
        state.phase = STATE.DISSOLVE
    elseif cur == STATE.DISSOLVE then
        state.phase = STATE.IDLE
        PARTICLES = {}
        if state.onDone then state.onDone() end
    end
end

-- ============================================================================
-- 更新
-- ============================================================================

function BattleResolution.update(dt)
    if state.phase == STATE.IDLE then return end

    -- PRE_DELAY：等待延迟结束后再正式开始
    if state.phase == STATE.PRE_DELAY then
        state.preDelayTimer = state.preDelayTimer - dt
        if state.preDelayTimer <= 0 then
            state.phase       = STATE.BLOCKS_ENTER
            state.timer       = 0
            state.progress    = 0
            state.gridTriggered = false
        end
        return
    end

    state.gameTime = state.gameTime + dt

    -- 震动衰减
    state.screenShake = state.screenShake * (1 - 6 * dt)
    if state.screenShake < 0.01 then state.screenShake = 0 end
    state.shakeX = math.sin(state.gameTime * 45) * state.screenShake
    state.shakeY = math.cos(state.gameTime * 40) * state.screenShake * 0.7

    -- 粒子更新
    updateParticles(dt)

    local dur = DURATION[state.phase]
    state.timer    = state.timer + dt
    state.progress = math.min(1.0, state.timer / dur)

    -- ---------- 各阶段逻辑 ----------

    if state.phase == STATE.BLOCKS_ENTER then
        -- 触发 3D 方块横扫
        if not state.gridTriggered and state.grid then
            state.grid:sweepGold(dur * 0.75)
            state.gridTriggered = true
        end
        if state.progress >= 1.0 then nextPhase() end

    elseif state.phase == STATE.SCORES_REVEAL then
        if not state.gridTriggered and state.grid then
            -- revealSides 的 attackerIsUpper 参数含义：攻击方在 grid upper (row<=ROWS/2)
            -- BattleResolution 的 attackerIsUpper 是视觉坐标（true=视觉上方=row5~8=grid lower）
            -- 所以需要取反：视觉上方的攻击方 = grid lower = NOT grid upper
            state.grid:revealSides(dur * 0.7, not state.attackerIsUpper)
            state.gridTriggered = true
        end
        if state.progress >= 1.0 then nextPhase() end

    elseif state.phase == STATE.SCORES_CLASH then
        -- SCORES_CLASH 子逻辑
        local p = state.progress

        -- 进入阶段时立刻启动波环（波前从外向中心收缩，与分数同步冲向碰撞点）
        if not state.gridTriggered and state.grid then
            -- 波环在 progress=0.37 抵达中心（略晚于碰撞点 0.35），
            -- 使波前与分数数字视觉上"同时"冲向中心，碰撞瞬间波峰正在中心爆发
            state.grid:startClashWave(dur * 0.37)
            state.gridTriggered = true
        end

        -- ── 3D 卡牌动画 ──────────────────────────────────────────────────────
        -- progress=0.00：双方卡牌飞起到各自半场蓄力点，旋转 180°
        if not state.cardChargeTriggered then
            state.cardChargeTriggered = true
            -- 攻击方蓄力点：attackerIsUpper=true → 攻击方在视觉上方(Z>0)；反之在下方(Z<0)
            local attackChargeZ = state.attackerIsUpper and  0.9 or -0.9
            local defChargeZ    = state.attackerIsUpper and -0.9 or  0.9
            local chargeY       = 1.2

            if state.attackCard3d and state.attackCard3d.node then
                local ax = state.attackCard3d.node.worldPosition.x
                CardAnimator.chargeFlip(state.attackCard3d,
                    Vector3(ax, chargeY, attackChargeZ), 0.55)
            end
            if state.defCard3d and state.defCard3d.node then
                local dx = state.defCard3d.node.worldPosition.x
                CardAnimator.chargeFlip(state.defCard3d,
                    Vector3(dx, chargeY, defChargeZ), 0.55)
            end
        end

        -- progress=0.27：双方卡牌冲刺向中场碰撞点
        if p >= 0.27 and not state.cardDashTriggered then
            state.cardDashTriggered = true
            local midPoint = Vector3(0, 0.8, 0)
            if state.attackCard3d and state.attackCard3d.node then
                CardAnimator.dashToTarget(state.attackCard3d, midPoint, 0.20)
            end
            if state.defCard3d and state.defCard3d.node then
                CardAnimator.dashToTarget(state.defCard3d, midPoint, 0.20)
            end
        end
        -- ─────────────────────────────────────────────────────────────────────

        -- 碰撞瞬间（progress = 0.35）
        if p >= 0.35 and not state.clashTriggered then
            state.clashTriggered = true
            state.screenShake  = 8.0
            state.clashFlash   = 1.0
            state.vsScale      = 3.0
            state.scoreAScale  = 1.45
            state.scoreBScale  = 1.45
            state.scoreTilt    = 0.18

            -- 触发波环碰撞后余韵衰减
            if state.grid then state.grid:triggerClashDecay() end

            -- 粒子爆发（需要屏幕尺寸，用 0,0 占位，draw 时会用真实坐标）
            state.clashParticlesPending = true

            -- ── 3D 卡牌：判定胜负，败方击碎，胜方继续冲向英雄 ──────────────
            local attackWon = (state.attackVal >= state.defVal)
            -- 英雄命中目标点：胜方冲向对方英雄
            -- 攻击方胜：攻击卡飞向防御方英雄（对面），防御卡被击碎
            -- 防御方胜：防御卡飞向攻击方英雄（对面），攻击卡被击碎
            local heroTargetZ
            if attackWon then
                -- 攻击卡胜，攻击方在 attackerIsUpper 侧，英雄目标在对面
                heroTargetZ = state.attackerIsUpper and -1.8 or 1.8
            else
                -- 防御卡胜，防御方英雄目标在对面（攻击方侧）
                heroTargetZ = state.attackerIsUpper and 1.8 or -1.8
            end
            local heroTarget = Vector3(0, 0.3, heroTargetZ)

            if attackWon then
                -- 防御卡击碎
                if state.defCard3d and state.defCard3d.node then
                    CardAnimator.shatter(state.defCard3d)
                end
                -- 攻击卡冲向英雄
                if state.attackCard3d and state.attackCard3d.node then
                    CardAnimator.dashToTarget(state.attackCard3d, heroTarget, 0.35,
                        function()
                            if state.attackCard3d and state.attackCard3d.node then
                                state.attackCard3d.node.enabled = false
                            end
                            state.cardHitTriggered = true
                            state.screenShake = state.screenShake + 5.0
                        end)
                end
            else
                -- 攻击卡击碎
                if state.attackCard3d and state.attackCard3d.node then
                    CardAnimator.shatter(state.attackCard3d)
                end
                -- 防御卡冲向英雄
                if state.defCard3d and state.defCard3d.node then
                    CardAnimator.dashToTarget(state.defCard3d, heroTarget, 0.35,
                        function()
                            if state.defCard3d and state.defCard3d.node then
                                state.defCard3d.node.enabled = false
                            end
                            state.cardHitTriggered = true
                            state.screenShake = state.screenShake + 5.0
                        end)
                end
            end
            -- ─────────────────────────────────────────────────────────────────
        end

        -- 碰撞后各值回落
        state.clashFlash  = state.clashFlash  * (1 - 8 * dt)
        state.vsScale     = state.vsScale     + (1.0 - state.vsScale)     * math.min(1, dt * 3.5)
        state.scoreAScale = state.scoreAScale + (1.0 - state.scoreAScale) * math.min(1, dt * 3.5)
        state.scoreBScale = state.scoreBScale + (1.0 - state.scoreBScale) * math.min(1, dt * 3.5)
        state.scoreTilt   = state.scoreTilt   * (1 - 6 * dt)

        if state.progress >= 1.0 then
            nextPhase()
        end

    elseif state.phase == STATE.WINNER_GLOW then
        if not state.gridTriggered and state.grid then
            -- glowWinner(true) = row5~8(grid lower=视觉上方=对手侧)变金
            -- playerWon=true 表示玩家(视觉下方=row1~4=grid upper)获胜，需要取反
            state.grid:glowWinner(not state.playerWon, dur * 0.7)
            state.gridTriggered = true
        end
        state.winnerAlpha = easeOutCubic(state.progress)
        state.crownScrollX = state.crownScrollX + 18 * dt
        if state.progress >= 1.0 then nextPhase() end

    elseif state.phase == STATE.ATTACK_EXEC then
        -- 攻击撞击瞬间（progress = 0.35）
        if state.progress >= 0.35 and not state.attackImpactDone then
            state.attackImpactDone = true
            state.screenShake = 7.0
            state.fireAlpha   = 1.0
            state.dmgAlpha    = 1.0
            state.dmgScale    = 1.5
            state.attackImpactParticlesPending = true
        end

        -- 撞击后效果衰减
        if state.fireAlpha > 0 then
            state.fireAlpha = state.fireAlpha * (1 - 4 * dt)
        end
        if state.dmgAlpha > 0 then
            state.dmgAlpha  = state.dmgAlpha  * (1 - 2.5 * dt)
        end
        state.dmgScale = state.dmgScale + (1.0 - state.dmgScale) * math.min(1, dt * 5)

        if state.progress >= 1.0 then nextPhase() end

    elseif state.phase == STATE.DISSOLVE then
        -- 皇冠/获胜光晕渐隐
        state.winnerAlpha = math.max(0, state.winnerAlpha - dt * 3)
        state.fireAlpha   = math.max(0, state.fireAlpha   - dt * 4)
        state.dmgAlpha    = math.max(0, state.dmgAlpha    - dt * 3)

        if not state.gridTriggered and state.grid then
            state.grid:dissolve(dur * 0.7, state.newAttackerIsLower)
            state.gridTriggered = true
        end
        if state.progress >= 1.0 then nextPhase() end
    end
end

-- ============================================================================
-- NanoVG 绘制（2D 叠层）
-- ============================================================================

--- 主绘制入口
---@param ctx userdata NanoVG context
---@param w number 逻辑宽
---@param h number 逻辑高
---@param fontId number NanoVG 字体句柄
---@param time number 游戏时间（用于动画）
function BattleResolution.draw(ctx, w, h, fontId, time)
    if state.phase == STATE.IDLE then return end

    -- 应用震动偏移
    if state.screenShake > 0.01 then
        nvgSave(ctx)
        nvgTranslate(ctx, state.shakeX, state.shakeY)
    end

    local cx   = w * 0.5
    local cy   = h * 0.5
    local p    = state.progress
    local ph   = state.phase

    nvgFontFaceId(ctx, fontId)

    -- ================================================================
    -- 通用半透明背景遮罩（让 3D 桌面更聚焦）
    -- ================================================================
    if ph >= STATE.BLOCKS_ENTER and ph <= STATE.DISSOLVE then
        local maskAlpha = 0
        if ph == STATE.BLOCKS_ENTER then
            maskAlpha = easeOutCubic(p) * 60
        elseif ph == STATE.DISSOLVE then
            maskAlpha = (1 - p) * 60
        else
            maskAlpha = 60
        end
        nvgBeginPath(ctx)
        nvgRect(ctx, 0, 0, w, h)
        nvgFillColor(ctx, nvgRGBA(12, 10, 20, math.floor(maskAlpha)))
        nvgFill(ctx)
    end

    -- ================================================================
    -- SCORES_REVEAL：红蓝揭露指示文字
    -- ================================================================
    if ph == STATE.SCORES_REVEAL then
        _drawScoresRevealOverlay(ctx, w, h, p, fontId)
    end

    -- ================================================================
    -- SCORES_CLASH：分数对冲
    -- ================================================================
    if ph == STATE.SCORES_CLASH or ph == STATE.WINNER_GLOW
    or ph == STATE.ATTACK_EXEC or ph == STATE.DISSOLVE then
        _drawScoresClash(ctx, w, h, p, ph, fontId, time)
    end

    -- ================================================================
    -- WINNER_GLOW：皇冠水印
    -- ================================================================
    if (ph == STATE.WINNER_GLOW or ph == STATE.ATTACK_EXEC or ph == STATE.DISSOLVE)
    and state.winnerAlpha > 0.01 then
        _drawCrownWatermark(ctx, w, h, time, fontId)
    end

    -- ================================================================
    -- ATTACK_EXEC：攻击射线 + 火焰 + 星爆
    -- ================================================================
    if ph == STATE.ATTACK_EXEC then
        _drawAttackExec(ctx, w, h, p, time, fontId)
    end

    -- ================================================================
    -- 粒子（全阶段）
    -- ================================================================
    drawParticles(ctx)

    if state.screenShake > 0.01 then
        nvgRestore(ctx)
    end

    -- ================================================================
    -- 触发碰撞粒子（需要真实屏幕坐标，在 draw 时生成）
    -- ================================================================
    if state.clashParticlesPending then
        state.clashParticlesPending = false
        spawnBurst(cx, cy, 25, COL.PINK,  350, 5, 16, 0.7, true)
        spawnBurst(cx, cy, 25, COL.CYAN,  350, 5, 16, 0.7, true)
        spawnBurst(cx, cy, 12, COL.GOLD,  400, 8, 20, 0.9, true)
        spawnBurst(cx, cy,  8, COL.WHITE, 200, 3,  8, 0.4, false)
        spawnDirectional(cx, cy, 10, COL.PINK, -1, 0, 0.3, 350, 0.7)
        spawnDirectional(cx, cy, 10, COL.CYAN,  1, 0, 0.3, 350, 0.7)
    end

    if state.attackImpactParticlesPending then
        state.attackImpactParticlesPending = false
        local ix = w * 0.28  -- 撞击点（败方区域左下）
        local iy = h * 0.72
        spawnBurst(ix, iy, 15, COL.RED,   250, 5, 14, 0.6, true)
        spawnBurst(ix, iy, 10, COL.GOLD,  200, 4, 10, 0.5, true)
        spawnBurst(ix, iy,  5, COL.WHITE, 150, 3,  8, 0.3, false)
    end
end

-- ============================================================================
-- 子绘制函数
-- ============================================================================

function _drawScoresRevealOverlay(ctx, w, h, p, fontId)
    -- 分隔线（水平居中）
    local lineAlpha = math.floor(easeOutCubic(p) * 180)
    local midY = h * 0.5
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, 0, midY)
    nvgLineTo(ctx, w, midY)
    nvgStrokeColor(ctx, nvgRGBA(255, 200, 80, lineAlpha))
    nvgStrokeWidth(ctx, 2)
    nvgStroke(ctx)

    -- 阵营标签
    if p > 0.4 then
        local labelAlpha = math.floor(easeOutCubic((p - 0.4) / 0.6) * 200)
        nvgFontSize(ctx, 18)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

        -- 对手标签（上半，珊瑚红）
        nvgFillColor(ctx, nvgRGBA(255, 107, 107, labelAlpha))
        nvgText(ctx, w * 0.5, h * 0.28, "对 手", nil)

        -- 玩家标签（下半，薄荷绿）
        nvgFillColor(ctx, nvgRGBA(82, 200, 160, labelAlpha))
        nvgText(ctx, w * 0.5, h * 0.72, "你", nil)
    end
end

function _drawScoresClash(ctx, w, h, p, ph, fontId, time)
    local cx = w * 0.5
    local cy = h * 0.5

    -- 分数位置计算
    local topRest   = h * 0.28
    local botRest   = h * 0.72
    local midY      = cy
    local clashGap  = 30  -- 碰撞时数字间距（半值）

    -- 移动进度（CLASH 阶段 0→1，之后保持在碰撞后弹跳）
    local moveP = 0
    local bounceOffset = 0

    if ph == STATE.SCORES_CLASH then
        if p < 0.25 then
            moveP = easeInOutQuad(p / 0.25) * 0.6
        elseif p < 0.35 then
            moveP = 0.6 + easeOutCubic((p - 0.25) / 0.1) * 0.4
        else
            moveP = 1.0
            -- 弹性回弹
            local bp = (p - 0.35) / 0.65
            bounceOffset = math.sin(bp * math.pi * 3) * math.exp(-bp * 3.5) * 15
        end
    else
        moveP = 1.0
        -- 后续阶段数字归位
        local returnP = clamp((ph - STATE.WINNER_GLOW) / 1.0, 0, 1)
        moveP = 1.0 - returnP * 0.3  -- 轻微回弹后稳定
    end

    -- 分数 Y 位置
    local scoreAY = lerp(topRest, midY - clashGap, moveP) + bounceOffset
    local scoreBY = lerp(botRest, midY + clashGap, moveP) - bounceOffset

    -- 绘制水平闪光线（碰撞后）
    if state.clashFlash > 0.01 then
        local flashH = 4 + state.clashFlash * 12
        -- 红蓝渐变主光
        nvgBeginPath(ctx)
        nvgRect(ctx, 0, cy - flashH / 2, w, flashH)
        local flashGrad = nvgLinearGradient(ctx, 0, cy, w, cy,
            nvgRGBA(210, 46, 72,  math.floor(state.clashFlash * 180)),
            nvgRGBA(64,  82, 184, math.floor(state.clashFlash * 180)))
        nvgFillPaint(ctx, flashGrad)
        nvgFill(ctx)

        -- 白色核心线
        nvgBeginPath(ctx)
        nvgRect(ctx, 0, cy - 1.5, w, 3)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, math.floor(state.clashFlash * 200)))
        nvgFill(ctx)

        -- 辉光扩散
        nvgBeginPath(ctx)
        nvgRect(ctx, 0, cy - flashH * 1.5, w, flashH * 3)
        local glowGrad = nvgLinearGradient(ctx, 0, cy - flashH * 1.5, 0, cy + flashH * 1.5,
            nvgRGBA(255, 200, 100, 0),
            nvgRGBA(255, 200, 100, math.floor(state.clashFlash * 40)))
        nvgFillPaint(ctx, glowGrad)
        nvgFill(ctx)
    end

    -- 碰撞星形爆炸（进度 0.35 时出现，逐渐消失）
    if ph == STATE.SCORES_CLASH and p > 0.35 then
        local starAlpha = clamp(1 - (p - 0.35) / 0.5, 0, 1)
        if starAlpha > 0.01 then
            _drawClashStar(ctx, cx, cy, starAlpha, time)
        end
    end

    -- 上方数字：攻击方在上则显示攻击力(红)，否则显示防御值(绿)
    local upperVal, upperR, upperG, upperB
    if state.attackerIsUpper then
        upperVal = state.attackVal
        upperR, upperG, upperB = 255, 107, 107   -- 珊瑚红（攻击）
    else
        upperVal = state.defVal
        upperR, upperG, upperB = 82, 200, 160    -- 薄荷绿（防御）
    end
    local scaleA = (ph == STATE.SCORES_CLASH) and state.scoreAScale or 1.0
    local tiltA  = (ph == STATE.SCORES_CLASH) and state.scoreTilt or 0
    _drawScoreNumber(ctx, cx, scoreAY, upperVal, scaleA, tiltA,
        upperR, upperG, upperB, fontId)

    -- VS 文字
    if ph == STATE.SCORES_CLASH or ph == STATE.WINNER_GLOW then
        local vsAlpha = 200
        if ph == STATE.WINNER_GLOW then
            vsAlpha = math.floor(200 * (1 - easeOutCubic(p * 0.5)))
        end
        if vsAlpha > 5 then
            nvgSave(ctx)
            nvgTranslate(ctx, cx, cy)
            nvgScale(ctx, state.vsScale, state.vsScale)
            nvgFontSize(ctx, 18)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            if state.vsScale > 1.05 then
                nvgFillColor(ctx, nvgRGBA(255, 200, 80, math.floor(vsAlpha * (state.vsScale - 1) * 3)))
                nvgFontSize(ctx, 22)
                nvgText(ctx, 0, 0, "VS", nil)
                nvgFontSize(ctx, 18)
            end
            nvgFillColor(ctx, nvgRGBA(255, 220, 100, vsAlpha))
            nvgText(ctx, 0, 0, "VS", nil)
            nvgRestore(ctx)
        end
    end

    -- 下方数字：攻击方在上则显示防御值(绿)，否则显示攻击力(红)
    local lowerVal, lowerR, lowerG, lowerB
    if state.attackerIsUpper then
        lowerVal = state.defVal
        lowerR, lowerG, lowerB = 82, 200, 160    -- 薄荷绿（防御）
    else
        lowerVal = state.attackVal
        lowerR, lowerG, lowerB = 255, 107, 107   -- 珊瑚红（攻击）
    end
    local scaleB = (ph == STATE.SCORES_CLASH) and state.scoreBScale or 1.0
    local tiltB  = (ph == STATE.SCORES_CLASH) and (-state.scoreTilt) or 0
    _drawScoreNumber(ctx, cx, scoreBY, lowerVal, scaleB, tiltB,
        lowerR, lowerG, lowerB, fontId)
end

function _drawScoreNumber(ctx, x, y, score, scale, tilt, r, g, b, fontId)
    nvgSave(ctx)
    nvgTranslate(ctx, x, y)
    nvgScale(ctx, scale, scale)
    nvgRotate(ctx, tilt)

    nvgFontFaceId(ctx, fontId)

    -- 外发光（碰撞放大时）
    if scale > 1.05 then
        local glowAlpha = math.floor((scale - 1.0) * 3 * 80)
        nvgFontSize(ctx, 78)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(r, g, b, glowAlpha))
        nvgText(ctx, 0, 0, tostring(score), nil)
    end

    -- 黑色阴影
    nvgFontSize(ctx, 72)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 76))
    nvgText(ctx, 2, 3, tostring(score), nil)

    -- 主体数字（白色）
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 230))
    nvgText(ctx, 0, 0, tostring(score), nil)

    nvgRestore(ctx)
end

function _drawClashStar(ctx, cx, cy, alpha, time)
    -- 8 条射线
    nvgSave(ctx)
    nvgTranslate(ctx, cx, cy)
    for i = 0, 7 do
        local angle = i * math.pi / 4
        local len   = (80 + math.sin(time * 6 + i * 0.9) * 25) * alpha
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, 0, 0)
        nvgLineTo(ctx, math.cos(angle) * len, math.sin(angle) * len)
        nvgStrokeColor(ctx, nvgRGBA(255, 200, 80, math.floor(alpha * 160)))
        nvgStrokeWidth(ctx, 2.5)
        nvgStroke(ctx)
    end
    -- 中心发光圆
    local cr = 20 * alpha
    nvgBeginPath(ctx)
    nvgCircle(ctx, 0, 0, cr * 2.5)
    local radGrad = nvgRadialGradient(ctx, 0, 0, 0, cr * 2.5,
        nvgRGBA(255, 230, 100, math.floor(alpha * 160)),
        nvgRGBA(255, 200, 60, 0))
    nvgFillPaint(ctx, radGrad)
    nvgFill(ctx)
    nvgRestore(ctx)
end

function _drawCrownWatermark(ctx, w, h, time, fontId)
    local wa     = state.winnerAlpha * 0.14
    if wa < 0.01 then return end
    local alpha  = math.floor(wa * 255)

    -- 绘制区域：上半或下半（取决于胜方）
    local clipY1 = state.playerWon and (h * 0.5) or 0
    local clipY2 = state.playerWon and h         or (h * 0.5)

    nvgSave(ctx)
    nvgScissor(ctx, 0, clipY1, w, clipY2 - clipY1)
    nvgTranslate(ctx, w * 0.5, (clipY1 + clipY2) * 0.5)
    nvgRotate(ctx, -0.35)

    local scrollX = state.crownScrollX
    local spacX = 65
    local spacY = 55
    local rows = math.ceil(h / spacY) + 2
    local cols = math.ceil(w / spacX) + 4

    nvgFontFaceId(ctx, fontId)
    nvgFontSize(ctx, 22)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255, 200, 80, alpha))

    for row = -rows, rows do
        local offsetX = (row % 2 == 0) and 0 or (spacX * 0.5)
        for col = -cols, cols do
            local px = col * spacX + offsetX + (scrollX % spacX)
            local py = row * spacY
            nvgText(ctx, px, py, "♛", nil)
        end
    end

    nvgRestore(ctx)
end

function _drawAttackExec(ctx, w, h, p, time, fontId)
    -- 伤害星爆落点（始终居中偏上）
    local ex = w * 0.50
    local ey = h * 0.42

    -- 漫画星爆 "-N"
    if state.dmgAlpha > 0.01 then
        _drawDamageStarburst(ctx, ex + 30, ey - 35, state.damage, state.dmgAlpha, state.dmgScale, fontId)
    end
end

function _drawAttackLine(ctx, sx, sy, ex, ey, headP, time)
    local dx = ex - sx
    local dy = ey - sy
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return end

    local nx = dx / len
    local ny = dy / len

    local step     = 9
    local steps    = math.floor(len / step)
    local baseSize = 5

    for i = 0, steps do
        local frac     = i / steps
        if frac > headP then break end

        local tailFade = clamp((headP - frac) * 6, 0, 1)
        local headGlow = clamp(1 - (headP - frac) * 3, 0, 1)
        local a        = math.floor((0.5 + headGlow * 0.5) * tailFade * 220)
        if a < 5 then goto cont end

        local px  = sx + nx * i * step
        local py  = sy + ny * i * step
        local sz  = baseSize + ((i % 3 == 0) and 2 or 0)
        local rot = time * 4 + i * 0.7

        nvgSave(ctx)
        nvgTranslate(ctx, px, py)
        nvgRotate(ctx, rot)

        -- 外发光
        if headGlow > 0.3 then
            local gs = sz * 1.2 * 2
            nvgBeginPath(ctx)
            nvgRect(ctx, -gs/2, -gs/2, gs, gs)
            nvgFillColor(ctx, nvgRGBA(255, 215, 50, math.floor(a * 0.3)))
            nvgFill(ctx)
        end

        -- 方块
        nvgBeginPath(ctx)
        nvgRect(ctx, -sz/2, -sz/2, sz, sz)
        nvgFillColor(ctx, nvgRGBA(255, 200, 60, a))
        nvgFill(ctx)

        nvgRestore(ctx)
        ::cont::
    end

    -- 射线头部能量球（仅 headP < 1）
    if headP < 1.0 then
        local hx = sx + nx * headP * len
        local hy = sy + ny * headP * len
        local br = 8 + math.sin(time * 12) * 2

        nvgBeginPath(ctx)
        nvgCircle(ctx, hx, hy, br * 2.5)
        local gr = nvgRadialGradient(ctx, hx, hy, 0, br * 2.5,
            nvgRGBA(76, 204, 230, 90), nvgRGBA(76, 204, 230, 0))
        nvgFillPaint(ctx, gr)
        nvgFill(ctx)

        nvgBeginPath(ctx)
        nvgCircle(ctx, hx, hy, br)
        local gr2 = nvgRadialGradient(ctx, hx, hy, 0, br,
            nvgRGBA(255, 255, 255, 220), nvgRGBA(76, 204, 230, 180))
        nvgFillPaint(ctx, gr2)
        nvgFill(ctx)
    end
end

function _drawFireExplosion(ctx, x, y, alpha, time)
    local a = alpha
    -- 外层（暗红）
    nvgBeginPath(ctx)
    nvgCircle(ctx, x, y, 75)
    local g3 = nvgRadialGradient(ctx, x, y, 0, 75,
        nvgRGBA(230, 38, 13, math.floor(a * 180)),
        nvgRGBA(230, 38, 13, 0))
    nvgFillPaint(ctx, g3)
    nvgFill(ctx)

    -- 中层（橙红）
    nvgBeginPath(ctx)
    nvgCircle(ctx, x, y, 55)
    local g2 = nvgRadialGradient(ctx, x, y, 0, 55,
        nvgRGBA(255, 89, 13, math.floor(a * 180)),
        nvgRGBA(255, 89, 13, 0))
    nvgFillPaint(ctx, g2)
    nvgFill(ctx)

    -- 内核（橙黄）
    nvgBeginPath(ctx)
    nvgCircle(ctx, x, y, 35)
    local g1 = nvgRadialGradient(ctx, x, y, 0, 35,
        nvgRGBA(255, 153, 26, math.floor(a * 180)),
        nvgRGBA(255, 153, 26, 0))
    nvgFillPaint(ctx, g1)
    nvgFill(ctx)

    -- 火苗射线
    for i = 0, 9 do
        local angle = i * math.pi * 2 / 10
        local flen  = (30 + math.sin(time * 8 + i * 1.7) * 15) * a
        local fx    = x + math.cos(angle) * flen
        local fy    = y + math.sin(angle) * flen
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, x, y)
        nvgLineTo(ctx, fx, fy)
        nvgStrokeColor(ctx, nvgRGBA(255, 178, 51, math.floor(a * 154)))
        nvgStrokeWidth(ctx, 2.5)
        nvgStroke(ctx)
    end
end

function _drawDamageStarburst(ctx, x, y, damage, alpha, scale, fontId)
    if alpha < 0.01 then return end
    local a = alpha

    nvgSave(ctx)
    nvgTranslate(ctx, x, y)
    nvgScale(ctx, scale, scale)

    -- 红色星爆背景（12 尖角）
    local outerR = 38
    local innerR = 20
    local points = 12
    nvgBeginPath(ctx)
    for i = 0, points * 2 do
        local angle  = i * math.pi / points - math.pi / 2
        local radius = (i % 2 == 0) and outerR or innerR
        local px     = math.cos(angle) * radius
        local py     = math.sin(angle) * radius
        if i == 0 then
            nvgMoveTo(ctx, px, py)
        else
            nvgLineTo(ctx, px, py)
        end
    end
    nvgClosePath(ctx)
    nvgFillColor(ctx, nvgRGBA(230, 38, 26, math.floor(a * 230)))
    nvgFill(ctx)
    nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, math.floor(a * 200)))
    nvgStrokeWidth(ctx, 2)
    nvgStroke(ctx)

    -- "-N" 伤害数字
    nvgFontFaceId(ctx, fontId)
    nvgFontSize(ctx, 28)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 阴影
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, math.floor(a * 180)))
    nvgText(ctx, 1, 2, "-" .. damage, nil)

    -- 白色主体
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, math.floor(a * 240)))
    nvgText(ctx, 0, 0, "-" .. damage, nil)

    nvgRestore(ctx)
end

return BattleResolution

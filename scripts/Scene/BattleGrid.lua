-- ============================================================================
-- Scene/BattleGrid.lua - 战斗方块网格（替代牌桌表面）
--
-- 常驻场景，平时显示低饱和度中性底色，结算阶段驱动颜色/高度动画：
--   sweepGold        — 金色从左到右横扫（BLOCKS_ENTER）
--   revealSides      — 露出攻击方/防御方分区（SCORES_REVEAL）
--   startClashWave   — 波环从外向中心收缩，方块随波起伏（SCORES_CLASH）
--   stopClashWave    — 碰撞后余韵衰减
--   glowWinner       — 胜方区域变金（WINNER_GLOW）
--   dissolve         — 从中心消散回 idle（DISSOLVE）
-- ============================================================================

local BattleGrid = {}
BattleGrid.__index = BattleGrid

-- ============================================================================
-- 网格参数（与 TableScene 保持一致）
-- ============================================================================

local COLS       = 12
local ROWS       = 8
local TW         = 6.0       -- TableScene.TABLE_WIDTH
local TD         = 4.0       -- TableScene.TABLE_DEPTH
local TABLE_Y    = -0.03     -- TableScene.TABLE_Y

local CELL_W     = TW / COLS
local CELL_D     = TD / ROWS
local GAP        = 0.014
local BLOCK_W    = CELL_W - GAP
local BLOCK_D    = CELL_D - GAP

local BLOCK_H    = 0.22      -- 结算时方块完整高度
local IDLE_H     = 0.014     -- 平时方块高度（贴桌，略有厚度感）
local RISE_SPEED = 10        -- 高度插值速度

-- ============================================================================
-- 材质工厂
-- ============================================================================

local function makeMat(r, g, b, a, emissive, rough)
    local mat = Material:new()
    local tech = (a < 1.0)
        and "Techniques/PBR/PBRNoTextureAlpha.xml"
        or  "Techniques/PBR/PBRNoTexture.xml"
    mat:SetTechnique(0, cache:GetResource("Technique", tech))
    mat:SetShaderParameter("MatDiffColor",    Variant(Color(r, g, b, a)))
    mat:SetShaderParameter("Metallic",        Variant(0.12))
    mat:SetShaderParameter("Roughness",       Variant(rough or 0.55))
    if emissive then
        mat:SetShaderParameter("MatEmissiveColor", Variant(emissive))
    end
    return mat
end

-- 颜色定义表（共享材质的基础颜色，用于克隆后动态调整明度）
local MAT_DEF = {
    idle        = { diff = {0.22, 0.26, 0.38, 1.0},  emissive = nil,                    rough = 0.72 },
    gold        = { diff = {1.0,  0.82, 0.20, 0.95}, emissive = {0.28, 0.20, 0.04, 1}, rough = 0.40 },
    red         = { diff = {0.82, 0.18, 0.28, 0.92}, emissive = {0.14, 0.02, 0.03, 1}, rough = 0.50 },
    blue        = { diff = {0.25, 0.32, 0.72, 0.92}, emissive = {0.02, 0.05, 0.18, 1}, rough = 0.50 },
    fade        = { diff = {0.10, 0.10, 0.10, 0.00}, emissive = nil,                    rough = 0.55 },
    -- 回合提示专用：翠绿（己方）/ 深红（对手）
    turn_player = { diff = {0.20, 0.62, 0.36, 0.96}, emissive = {0.03, 0.16, 0.06, 1}, rough = 0.42 },
    turn_opp    = { diff = {0.72, 0.18, 0.26, 0.92}, emissive = {0.18, 0.02, 0.04, 1}, rough = 0.46 },
}

-- 高度→明度：直接正比，BLOCK_H 时系数 = BRIGHT_AMP，波峰时更亮
local BRIGHT_AMP   = 1.5              -- BLOCK_H 满高时的明度倍率
local BRIGHT_SCALE = BRIGHT_AMP / BLOCK_H

--- 根据当前高度计算明度系数（直接正比于 scaleY，整体放大；底部兜底保证可见）
local function heightBrightness(scaleY)
    return math.max(0.55, scaleY * BRIGHT_SCALE)
end

--- 将明度系数写入材质（调整 diffuse 和 emissive 的 RGB）
local function applyBrightness(mat, def, bright)
    local d = def.diff
    mat:SetShaderParameter("MatDiffColor",
        Variant(Color(d[1] * bright, d[2] * bright, d[3] * bright, d[4])))
    if def.emissive then
        local e = def.emissive
        mat:SetShaderParameter("MatEmissiveColor",
            Variant(Color(e[1] * bright, e[2] * bright, e[3] * bright, 1)))
    end
end

-- ============================================================================
-- 构造
-- ============================================================================

---@param scene Scene
---@return table BattleGrid 实例
function BattleGrid.create(scene)
    local self = setmetatable({}, BattleGrid)
    self._scene  = scene
    self._root   = scene:CreateChild("BattleGrid")
    self._blocks = {}

    -- 共享模板材质（只用于克隆，不直接赋给方块）
    self._matTemplates = {
        idle        = makeMat(0.22, 0.26, 0.38, 1.0,  nil,                     0.72),
        gold        = makeMat(1.0,  0.82, 0.20, 0.95, Color(0.28, 0.20, 0.04), 0.40),
        red         = makeMat(0.82, 0.18, 0.28, 0.92, Color(0.14, 0.02, 0.03), 0.50),
        blue        = makeMat(0.25, 0.32, 0.72, 0.92, Color(0.02, 0.05, 0.18), 0.50),
        fade        = makeMat(0.10, 0.10, 0.10, 0.00),
        turn_player = makeMat(0.20, 0.62, 0.36, 0.96, Color(0.03, 0.16, 0.06), 0.42),
        turn_opp    = makeMat(0.72, 0.18, 0.26, 0.92, Color(0.18, 0.02, 0.04), 0.46),
    }

    -- 回合信号计时器（signalYourTurn / signalOpponentTurn 保持后自动消散）
    self._signal = { active = false, timer = 0, holdDur = 0 }

    -- 创建所有方块节点（初始 idle 状态，每块独立材质以支持明度调整）
    for row = 1, ROWS do
        self._blocks[row] = {}
        for col = 1, COLS do
            local cx = -TW / 2 + (col - 0.5) * CELL_W
            local cz = -TD / 2 + (row - 0.5) * CELL_D

            local node = self._root:CreateChild("Blk_" .. row .. "_" .. col)
            node.scale    = Vector3(BLOCK_W, IDLE_H, BLOCK_D)
            node.position = Vector3(cx, TABLE_Y + IDLE_H * 0.5, cz)

            -- 每块克隆一份独立材质，后续通过 SetShaderParameter 调明度
            local mat = self._matTemplates.idle:Clone()

            local mdl = node:CreateComponent("StaticModel")
            mdl:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
            mdl:SetMaterial(mat)
            mdl.castShadows = false

            self._blocks[row][col] = {
                node         = node,
                mdl          = mdl,
                mat          = mat,          -- 独立材质引用
                matDefKey    = "idle",       -- 当前材质对应的 MAT_DEF key
                cx           = cx,
                cz           = cz,
                scaleY       = IDLE_H,
                targetScaleY = IDLE_H,
                baseH        = IDLE_H,
                delay        = 0,
                elapsed      = 0,
                triggered    = true,
                pendingMat   = nil,          -- 待切换的模板材质（切换时 Clone）
                pendingMatKey= "idle",       -- 对应的 MAT_DEF key
                pendingH     = IDLE_H,
                waveElev     = 0,
            }
        end
    end

    -- 波环状态
    self._wave = {
        active     = false,
        front      = 1.1,    -- 归一化波前位置（1→0，从边缘向中心）
        speed      = 0,      -- 波前移动速度（归一化/秒）
        peakH      = 0.18,   -- 波峰高度
        restH      = 0.10,   -- 波前扫过后的安息高度
        width      = 0.15,   -- 波环宽度（归一化）
        decaying   = false,  -- 碰撞后余韵衰减模式
        decayP     = 0,      -- 余韵衰减进度 0→1
        decaySpeed = 0.7,    -- 余韵衰减速度
        maxDist    = 0,      -- 最大格子距中心距离（归一化用）
        -- 确定性噪声缓存（避免每帧重算）
        noise      = {},
    }

    -- 扫描状态
    self._sweeping = false

    -- 预计算波环噪声
    self:_precomputeNoise()

    return self
end

function BattleGrid:_precomputeNoise()
    local w = self._wave
    for row = 1, ROWS do
        w.noise[row] = {}
        for col = 1, COLS do
            local n = math.sin(row * 0.9 + col * 1.3) * 0.7
                    + math.cos(row * 1.7 - col * 0.6) * 0.4
            w.noise[row][col] = n  -- 范围约 ±1.1
        end
    end
    -- 最大格子距中心距离
    local cx = (COLS + 1) * 0.5
    local cz = (ROWS + 1) * 0.5
    w.maxDist = math.sqrt((COLS * 0.5) ^ 2 + (ROWS * 0.5) ^ 2)
end

-- ============================================================================
-- 内部工具
-- ============================================================================

local function noise(amp)
    return (math.random() - 0.5) * amp * 2
end

--- 批量设置延迟/目标
function BattleGrid:_schedule(matKey, targetH, delayFn)
    for row = 1, ROWS do
        for col = 1, COLS do
            local b         = self._blocks[row][col]
            b.delay         = delayFn(row, col)
            b.elapsed       = 0
            b.triggered     = false
            b.pendingMat    = matKey and self._matTemplates[matKey] or nil
            b.pendingMatKey = matKey or b.matDefKey
            b.pendingH      = targetH
        end
    end
    self._sweeping = true
end

-- ============================================================================
-- 公开动画方法
-- ============================================================================

--- 金色从左到右横扫（BLOCKS_ENTER）
function BattleGrid:sweepGold(duration)
    duration = duration or 1.5
    self:_schedule("gold", BLOCK_H, function(row, col)
        local colNorm = (col - 1) / (COLS - 1)
        return math.max(0, colNorm * duration * 0.85 + noise(duration * 0.09))
    end)
end

--- 揭露攻击方/防御方分区，从中心向外扩展（SCORES_REVEAL）
--- attackerIsUpper: true = 攻击方在上半区（Z<0），false = 攻击方在下半区
function BattleGrid:revealSides(duration, attackerIsUpper)
    duration = duration or 1.0
    attackerIsUpper = (attackerIsUpper == nil) and true or attackerIsUpper
    local cx = (COLS + 1) * 0.5
    local cz = (ROWS + 1) * 0.5
    local maxDist = math.sqrt((COLS / 2) ^ 2 + (ROWS / 2) ^ 2)
    for row = 1, ROWS do
        for col = 1, COLS do
            local b   = self._blocks[row][col]
            local dx  = col - cx
            local dz  = row - cz
            local dist = math.sqrt(dx * dx + dz * dz) / maxDist

            b.delay     = math.max(0, dist * duration * 0.8 + noise(duration * 0.09))
            b.elapsed   = 0
            b.triggered = false
            -- 上半区 row <= ROWS/2，下半区 row > ROWS/2
            local isUpper = (row <= ROWS / 2)
            local key = (isUpper == attackerIsUpper) and "red" or "blue"
            b.pendingMat    = self._matTemplates[key]
            b.pendingMatKey = key
            b.pendingH      = BLOCK_H * 0.75
        end
    end
    self._sweeping = true
end

--- 启动 SCORES_CLASH 波环（从场地边缘向中心收缩）
--- moveProgress: 外部传入 0→1 表示分数移动进度，波环与之同步
function BattleGrid:startClashWave(totalDuration)
    totalDuration = totalDuration or 0.77  -- 碰撞前 35% × 2.2s ≈ 0.77s
    local w = self._wave
    w.active     = true
    w.front      = 1.05
    w.speed      = 1.05 / totalDuration   -- 波前从 1.05 → 0 的速度
    w.decaying   = false
    w.decayP     = 0
    w.peakH      = BLOCK_H * 0.85
    w.restH      = BLOCK_H * 0.50
end

--- 碰撞后启动余韵衰减
function BattleGrid:triggerClashDecay()
    local w = self._wave
    w.active   = true
    w.decaying = true
    w.decayP   = 0
    w.front    = 0  -- 波前已过中心
end

--- 胜方区域变金（WINNER_GLOW）
--- playerWon: true = 下半区（row > ROWS/2）获胜
function BattleGrid:glowWinner(playerWon, duration)
    duration = duration or 0.8
    local winRow1 = playerWon and (ROWS / 2 + 1) or 1
    local winRow2 = playerWon and ROWS           or (ROWS / 2)
    local maxDiag = COLS + ROWS
    for row = 1, ROWS do
        for col = 1, COLS do
            local b = self._blocks[row][col]
            if row >= winRow1 and row <= winRow2 then
                local diag = playerWon and (col + (ROWS - row)) or (col + row)
                b.delay         = math.max(0, (diag / maxDiag) * duration + noise(duration * 0.08))
                b.elapsed       = 0
                b.triggered     = false
                b.pendingMat    = self._matTemplates.gold
                b.pendingMatKey = "gold"
                b.pendingH      = BLOCK_H
            else
                b.delay         = math.random() * 0.3
                b.elapsed       = 0
                b.triggered     = false
                b.pendingMat    = nil
                b.pendingMatKey = b.matDefKey
                b.pendingH      = BLOCK_H * 0.40
            end
        end
    end
    self._sweeping = true
end

--- 己方回合信号：下半区升起翠绿，1.8s后自动消散
--- 若波环正在运行（结算动画进行中）则忽略
function BattleGrid:signalYourTurn()
    if self._wave.active then return end
    -- 中止任何进行中的回合信号
    self._signal.active = false

    local riseW = 0.50   -- 各列延迟窗口（秒）
    for row = 1, ROWS do
        for col = 1, COLS do
            local b = self._blocks[row][col]
            local isPlayerSide = (row > ROWS / 2)
            if isPlayerSide then
                -- 从中央边界（row=ROWS/2+1）向桌边（row=ROWS）依次升起
                local rowNorm = (row - ROWS / 2 - 1) / (ROWS / 2)  -- 0→1 中心到边缘
                b.delay         = rowNorm * riseW + noise(riseW * 0.08)
                b.elapsed       = 0
                b.triggered     = false
                b.pendingMat    = self._matTemplates.turn_player
                b.pendingMatKey = "turn_player"
                b.pendingH      = BLOCK_H * 0.72
            else
                -- 对手半区降回 idle 高度
                b.delay         = math.random() * 0.35
                b.elapsed       = 0
                b.triggered     = false
                b.pendingMat    = self._matTemplates.idle
                b.pendingMatKey = "idle"
                b.pendingH      = IDLE_H
            end
        end
    end
    self._sweeping            = true
    self._signal.active       = true
    self._signal.timer        = 0
    self._signal.holdDur      = 1.8
end

--- 对手回合信号：上半区升起深红，1.8s后自动消散
function BattleGrid:signalOpponentTurn()
    if self._wave.active then return end
    self._signal.active = false

    local riseW = 0.50
    for row = 1, ROWS do
        for col = 1, COLS do
            local b = self._blocks[row][col]
            local isOppSide = (row <= ROWS / 2)
            if isOppSide then
                -- 从中央边界（row=ROWS/2）向桌边（row=1）依次升起
                local rowNorm = (ROWS / 2 - row) / (ROWS / 2)  -- 0→1 中心到边缘
                b.delay         = rowNorm * riseW + noise(riseW * 0.08)
                b.elapsed       = 0
                b.triggered     = false
                b.pendingMat    = self._matTemplates.turn_opp
                b.pendingMatKey = "turn_opp"
                b.pendingH      = BLOCK_H * 0.72
            else
                b.delay         = math.random() * 0.35
                b.elapsed       = 0
                b.triggered     = false
                b.pendingMat    = self._matTemplates.idle
                b.pendingMatKey = "idle"
                b.pendingH      = IDLE_H
            end
        end
    end
    self._sweeping            = true
    self._signal.active       = true
    self._signal.timer        = 0
    self._signal.holdDur      = 1.8
end

--- 从中心向外消散回 idle（DISSOLVE）
function BattleGrid:dissolve(duration)
    duration = duration or 1.2
    -- 停止波环
    self._wave.active  = false
    self._wave.decaying = false

    local cx = (COLS + 1) * 0.5
    local cz = (ROWS + 1) * 0.5
    local maxDist = math.sqrt((COLS / 2) ^ 2 + (ROWS / 2) ^ 2)
    for row = 1, ROWS do
        for col = 1, COLS do
            local b   = self._blocks[row][col]
            local dx  = col - cx
            local dz  = row - cz
            local dist = math.sqrt(dx * dx + dz * dz) / maxDist
            b.delay     = math.max(0, dist * duration * 0.75 + noise(duration * 0.09))
            b.elapsed   = 0
            b.triggered = false
            b.pendingMat    = self._matTemplates.idle
            b.pendingMatKey = "idle"
            b.pendingH      = IDLE_H
        end
    end
    self._sweeping = true
end

-- ============================================================================
-- 更新
-- ============================================================================

function BattleGrid:update(dt)
    -- ---- 0. 回合信号计时器（波环激活时暂停，避免结算期间误消散）----
    if self._signal.active and not self._wave.active then
        self._signal.timer = self._signal.timer + dt
        if self._signal.timer >= self._signal.holdDur then
            self._signal.active = false
            self:dissolve(1.2)
        end
    end
    -- 波环启动时取消未到期的信号（结算动画接管）
    if self._wave.active then
        self._signal.active = false
    end

    -- ---- 1. 波环逻辑 ----
    self:_updateWave(dt)

    -- ---- 2. 延迟触发 + 高度平滑插值 ----
    if not self._sweeping then
        -- 平时只做波环高度，直接 apply
        if not self._wave.active then return end
    end

    local allSettled = true

    for row = 1, ROWS do
        for col = 1, COLS do
            local b = self._blocks[row][col]

            -- 触发检测：到达延迟时切换为新克隆材质
            if not b.triggered then
                b.elapsed = b.elapsed + dt
                if b.elapsed >= b.delay then
                    b.triggered = true
                    if b.pendingMat then
                        -- 克隆新材质，保留独立实例
                        local newMat = b.pendingMat:Clone()
                        b.mdl:SetMaterial(newMat)
                        b.mat       = newMat
                        b.matDefKey = b.pendingMatKey
                    end
                    b.targetScaleY = b.pendingH
                    b.baseH        = b.pendingH
                end
                allSettled = false
            end

            -- 波环叠加高度（叠在 baseH 上）
            local targetY = b.targetScaleY + b.waveElev

            -- 高度平滑插值
            local diff = targetY - b.scaleY
            local moving = math.abs(diff) > 0.0003
            if moving then
                b.scaleY = b.scaleY + diff * math.min(1, dt * RISE_SPEED)
                b.node.scale    = Vector3(BLOCK_W, b.scaleY, BLOCK_D)
                b.node.position = Vector3(
                    b.cx,
                    TABLE_Y + b.scaleY * 0.5,
                    b.cz
                )
                allSettled = false
            end

            -- 明度随高度更新（只在波环激活或方块正在运动时执行）
            if self._wave.active or moving or not b.triggered then
                local bright = heightBrightness(b.scaleY)
                applyBrightness(b.mat, MAT_DEF[b.matDefKey], bright)
            end
        end
    end

    if allSettled and not self._wave.active then
        self._sweeping = false
    end
end

function BattleGrid:_updateWave(dt)
    local w = self._wave
    if not w.active then
        -- 静止时清零 waveElev
        for row = 1, ROWS do
            for col = 1, COLS do
                self._blocks[row][col].waveElev = 0
            end
        end
        return
    end

    local cx = (COLS + 1) * 0.5
    local cz = (ROWS + 1) * 0.5

    if w.decaying then
        -- 碰撞后余韵衰减：全体高度按曲线归零
        w.decayP = math.min(1.0, w.decayP + dt * w.decaySpeed)
        local decay = (1 - w.decayP) ^ 2.5
        for row = 1, ROWS do
            for col = 1, COLS do
                local b = self._blocks[row][col]
                local cellNoise = w.noise[row][col]
                b.waveElev = math.max(0, w.restH * decay * (0.8 + cellNoise * 0.2))
            end
        end
        if w.decayP >= 1.0 then
            w.active   = false
            w.decaying = false
            for row = 1, ROWS do
                for col = 1, COLS do
                    self._blocks[row][col].waveElev = 0
                end
            end
        end
    else
        -- 波环收缩阶段
        w.front = w.front - w.speed * dt
        for row = 1, ROWS do
            for col = 1, COLS do
                local b = self._blocks[row][col]
                local dx   = (col - cx) / (COLS * 0.5)
                local dz   = (row - cz) / (ROWS * 0.5)
                local dist = math.sqrt(dx * dx + dz * dz)  -- 0~1.4 范围

                -- 归一化到 0~1
                local normDist = dist / 1.414

                local elev = 0
                if normDist >= w.front then
                    local passed = normDist - w.front
                    if passed < w.width then
                        -- 波环正在经过：接近峰值
                        elev = w.peakH * (1 - passed / w.width * 0.1)
                    else
                        -- 波环已离过：平滑回落到安息高度
                        local settle    = math.min(1, (passed - w.width) / 0.7)
                        local cellNoise = w.noise[row][col]
                        local rest      = math.max(0, (1 - normDist) * w.restH
                                                  + cellNoise * w.restH * 0.25)
                        elev = w.peakH + (rest - w.peakH) * (1 - (1 - settle) ^ 2)
                    end
                end
                b.waveElev = elev
            end
        end
    end
end

--- 是否仍在运动（外部可 poll 余韵是否结束）
function BattleGrid:isBusy()
    return self._sweeping or self._wave.active
end

function BattleGrid:isWaveDecayDone()
    return not self._wave.active
end

function BattleGrid:destroy()
    if self._root then
        self._root:Remove()
        self._root = nil
    end
end

return BattleGrid

-- ============================================================================
-- Scene/BattleGrid.lua - 战斗方块网格（替代牌桌表面）
--
-- 常驻场景，平时显示低饱和度中性底色，结算阶段驱动颜色/高度动画：
--   setBorderState    — 建立外圈红/蓝常态（每中回合开始）
--   signalActiveSide  — 当前行动方外圈抬高+变亮
--   flowBorderColors  — 无战斗换边时顺时针颜色流动
--   sweepGold         — 金色从左到右横扫（BLOCKS_ENTER）
--   revealSides       — 露出攻击方/防御方分区（SCORES_REVEAL）
--   startClashWave    — 波环从外向中心收缩，方块随波起伏（SCORES_CLASH）
--   stopClashWave     — 碰撞后余韵衰减
--   glowWinner        — 胜方区域变金（WINNER_GLOW）
--   dissolve          — 从中心消散回 idle（DISSOLVE）
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
local TABLE_Y    = -0.055    -- 比桌面略低，避免与场上卡牌深度竞争

local CELL_W     = TW / COLS
local CELL_D     = TD / ROWS
local GAP        = 0.014
local BLOCK_W    = CELL_W - GAP
local BLOCK_D    = CELL_D - GAP

local BLOCK_H    = 0.22      -- 结算时方块完整高度
local IDLE_H     = 0.014     -- 平时方块高度（贴桌，略有厚度感）
local RISE_SPEED = 10        -- 高度插值速度

-- ============================================================================
-- 边框系统常量
-- ============================================================================

-- 边框方块（最外圈）静止高度：比 IDLE_H 高一点，常态可见
local BORDER_REST_H   = BLOCK_H * 0.14   -- ~0.031
-- 注：行动方指示改为纯色变化（更强自发光），不再抬高高度以免遮挡桌面物件

-- 顺时针流动动画：相邻方块之间的延迟（秒）
local FLOW_STAGGER    = 0.035
-- 顺时针流动一圈的颜色切换点（完成时间）= 36 * FLOW_STAGGER ≈ 1.26s

-- ============================================================================
-- 边框 helper 函数
-- ============================================================================

--- 是否为边框方块（最外圈）
local function isBorderBlock(row, col)
    return row == 1 or row == ROWS or col == 1 or col == COLS
end

--- 根据所在半区和攻击方位置，返回该边框方块应有的颜色 key
--- attackerIsLower: true = 攻击方在下半区（row > ROWS/2）
--- activeIsLower: nil = 不高亮任何一侧；true/false = 高亮指定侧（使用 _active 变体）
local function borderColorKey(row, attackerIsLower, activeIsLower)
    local isLower = (row > ROWS / 2)
    local isRed   = (isLower == attackerIsLower)
    local isActive = (activeIsLower ~= nil) and (isLower == activeIsLower)
    if isActive then
        return isRed and "red_active" or "blue_active"
    end
    return isRed and "red" or "blue"
end

--- 构建边框外圈顺时针顺序列表（36 个方块）
--- 顺时针：上边从左到右 → 右边从上到下 → 下边从右到左 → 左边从下到上
local function buildBorderRing()
    local ring = {}
    -- 上边: row=1, col 1→12  (12)
    for col = 1, COLS do
        table.insert(ring, { row = 1, col = col })
    end
    -- 右边: col=12, row 2→8  (7)
    for row = 2, ROWS do
        table.insert(ring, { row = row, col = COLS })
    end
    -- 下边: row=8, col 11→1  (11)
    for col = COLS - 1, 1, -1 do
        table.insert(ring, { row = ROWS, col = col })
    end
    -- 左边: col=1, row 7→2  (6)
    for row = ROWS - 1, 2, -1 do
        table.insert(ring, { row = row, col = 1 })
    end
    -- 合计：12+7+11+6 = 36
    return ring
end

-- ============================================================================
-- 材质工厂
-- ============================================================================

local function makeMat(r, g, b, a, emissive, rough)
    local mat = Material:new()
    -- 不透明方块用 NoTextureUnlit：不受 ambient 暗化，颜色直出
    -- 半透明方块（动画用）保留 PBR，本身有强 emissive 覆盖 ambient 影响
    local tech = (a < 1.0)
        and "Techniques/PBR/PBRNoTextureAlpha.xml"
        or  "Techniques/NoTextureUnlit.xml"
    mat:SetTechnique(0, cache:GetResource("Technique", tech))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(r, g, b, a)))
    if a < 1.0 then
        mat:SetShaderParameter("Metallic",  Variant(0.12))
        mat:SetShaderParameter("Roughness", Variant(rough or 0.55))
    end
    if emissive then
        mat:SetShaderParameter("MatEmissiveColor", Variant(emissive))
    end
    return mat
end

-- 颜色定义表（共享材质的基础颜色，用于克隆后动态调整明度）
-- _active 变体：自发光约为普通版 4-5 倍，用于标识当前行动方（不改高度）
local MAT_DEF = {
    idle       = { diff = {0.32, 0.38, 0.55, 1.0},  emissive = {0.04, 0.06, 0.12, 1}, rough = 0.55 },
    gold       = { diff = {1.0,  0.82, 0.20, 0.95}, emissive = {0.28, 0.20, 0.04, 1}, rough = 0.40 },
    red        = { diff = {0.82, 0.18, 0.28, 0.92}, emissive = {0.14, 0.02, 0.03, 1}, rough = 0.50 },
    blue       = { diff = {0.25, 0.32, 0.72, 0.92}, emissive = {0.02, 0.05, 0.18, 1}, rough = 0.50 },
    -- 行动方高亮：更高自发光 + 稍高漫反射，外圈明显发光
    red_active  = { diff = {0.95, 0.22, 0.34, 1.0},  emissive = {0.65, 0.10, 0.16, 1}, rough = 0.30 },
    blue_active = { diff = {0.28, 0.40, 0.98, 1.0},  emissive = {0.07, 0.14, 0.68, 1}, rough = 0.30 },
}

-- 高度→明度：IDLE_H 时 = 1.0（与设计色一致），BLOCK_H 时 = BRIGHT_AMP（高亮发光）
local BRIGHT_AMP   = 2.8              -- BLOCK_H 满高时的明度倍率（提高使波前明显发亮）

--- 根据当前高度计算明度系数
--- IDLE_H → 1.0（设计原色）; BLOCK_H → BRIGHT_AMP（高亮）; 中间线性插值
local function heightBrightness(scaleY)
    local t = math.max(0, (scaleY - IDLE_H) / (BLOCK_H - IDLE_H))
    return 1.0 + t * (BRIGHT_AMP - 1.0)
end

--- 将明度系数写入材质（调整 diffuse 和 emissive 的 RGB）
--- 当 bright > 1（方块被抬高）且材质无 emissive 定义时，
--- 从 diffuse 颜色衍生自发光，模拟波环扫过时的发亮热度感
local function applyBrightness(mat, def, bright)
    local d = def.diff
    mat:SetShaderParameter("MatDiffColor",
        Variant(Color(d[1] * bright, d[2] * bright, d[3] * bright, d[4])))
    if def.emissive then
        local e = def.emissive
        mat:SetShaderParameter("MatEmissiveColor",
            Variant(Color(e[1] * bright, e[2] * bright, e[3] * bright, 1)))
    elseif bright > 1.0 then
        -- 无 emissive 定义时，从 diffuse 衍生自发光（仅在抬高时生效）
        local glow = (bright - 1.0) * 0.38   -- 超出基线部分转化为发光强度
        mat:SetShaderParameter("MatEmissiveColor",
            Variant(Color(d[1] * glow, d[2] * glow, d[3] * glow, 1)))
    else
        -- 方块回落到基线时确保 emissive 归零
        mat:SetShaderParameter("MatEmissiveColor",
            Variant(Color(0, 0, 0, 1)))
    end
end

--- 在两个 MAT_DEF 之间插值并写入材质（用于高亮补间）
--- p=0 → fromDef 颜色，p=1 → toDef 颜色
local function applyBlendedColor(mat, fromDef, toDef, p, bright)
    local fd, td = fromDef.diff, toDef.diff
    local r = fd[1] + (td[1] - fd[1]) * p
    local g = fd[2] + (td[2] - fd[2]) * p
    local b = fd[3] + (td[3] - fd[3]) * p
    local a = fd[4] + (td[4] - fd[4]) * p
    mat:SetShaderParameter("MatDiffColor", Variant(Color(r * bright, g * bright, b * bright, a)))

    local fe = fromDef.emissive
    local te = toDef.emissive
    if fe or te then
        local fer = fe and fe[1] or 0; local feg = fe and fe[2] or 0; local feb = fe and fe[3] or 0
        local ter = te and te[1] or 0; local teg = te and te[2] or 0; local teb = te and te[3] or 0
        mat:SetShaderParameter("MatEmissiveColor",
            Variant(Color((fer + (ter - fer) * p) * bright,
                         (feg + (teg - feg) * p) * bright,
                         (feb + (teb - feb) * p) * bright, 1)))
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
        idle        = makeMat(0.32, 0.38, 0.55, 1.0,  Color(0.04, 0.06, 0.12), 0.55),
        gold        = makeMat(1.0,  0.82, 0.20, 0.95, Color(0.28, 0.20, 0.04), 0.40),
        red         = makeMat(0.82, 0.18, 0.28, 0.92, Color(0.14, 0.02, 0.03), 0.50),
        blue        = makeMat(0.25, 0.32, 0.72, 0.92, Color(0.02, 0.05, 0.18), 0.50),
        red_active  = makeMat(0.95, 0.22, 0.34, 1.0,  Color(0.65, 0.10, 0.16), 0.30),
        blue_active = makeMat(0.28, 0.40, 0.98, 1.0,  Color(0.07, 0.14, 0.68), 0.30),
    }

    -- 回合信号状态（仅用于 wave.active 守卫检查，不再自动消散）
    self._signal = { active = false }

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
        width      = 0.25,   -- 波环宽度（归一化，加宽使更多方块同时发亮）
        decaying   = false,  -- 碰撞后余韵衰减模式
        decayP     = 0,      -- 余韵衰减进度 0→1
        decaySpeed = 1.3,    -- 余韵衰减速度（加快使碰撞后高度快速塌落）
        maxDist    = 0,      -- 最大格子距中心距离（归一化用）
        -- 确定性噪声缓存（避免每帧重算）
        noise      = {},
    }

    -- 扫描状态
    self._sweeping = false

    -- 边框系统状态
    self._borderState = {
        attackerIsLower = true,
        initialized     = false,
    }

    -- 行动方高亮补间：lower/upper 两侧各自独立的平滑因子（0=普通色, 1=active色）
    -- 设计：不依赖 matDefKey 的时序，每帧从 attackerIsLower 直接推导颜色，写入 b.mat
    -- 呼吸效果：factor 到达 1.0 后持续用 sin 波在 [breatheMin, 1.0] 间振荡
    self._highlightAnim = {
        active        = false,
        factor        = { lower = 0.0, upper = 0.0 },  -- 当前因子（淡入/淡出用）
        target        = { lower = 0.0, upper = 0.0 },  -- 目标因子
        speed         = 5.0,    -- 逼近速度（factor/秒，≈0.2s 完成）
        breatheTimer  = 0.0,    -- 呼吸计时器（持续累加，两侧共用相位）
        breatheSpeed  = 1.4,    -- 呼吸频率（rad/s，约 4.5s 一个完整周期）
        breatheMin    = 0.15,   -- 呼吸最低点（0=纯底色，1=完全激活色）；越低明暗越明显
    }
    -- 结算动画全程锁定高亮写色（由 GameController 在 BR 触发/结束时调用 lockHighlight/unlockHighlight）
    self._hlLocked = false

    -- 顺时针流动动画状态（逐帧旋转算法）
    -- redStart: 0-indexed，红色段起始 ring 位置（浮点，旋转中持续变化）
    -- halfRing: 红色段长度（始终为 ringSize/2 = 18）
    -- ringSize: 外圈总数（36）
    self._flowAnim = {
        active     = false,
        timer      = 0,
        duration   = 0,
        redStart   = 0,     -- 当前帧红色段起始位置（0-indexed 浮点）
        targetStart= 0,     -- 动画终态 redStart
        halfRing   = 18,    -- 红色段长度（固定 18 = 36/2）
        ringSize   = 36,    -- 外圈总数
        onDone     = nil,
    }

    -- 预计算外圈顺时针顺序
    self._borderRing = buildBorderRing()

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

--- 对单个方块设置延迟/目标（边框动画专用）
function BattleGrid:_scheduleBlock(row, col, matKey, targetH, delay)
    local b         = self._blocks[row][col]
    b.delay         = delay
    b.elapsed       = 0
    b.triggered     = false
    b.pendingMat    = matKey and self._matTemplates[matKey] or nil
    b.pendingMatKey = matKey or b.matDefKey
    b.pendingH      = targetH
    self._sweeping  = true
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
    w.peakH      = BLOCK_H * 1.0          -- 满高，最大亮度
    w.restH      = BLOCK_H * 0.65         -- 波后托底高度，整个场地保持一定蓄力感
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

--- 从中心向外消散，直接揭露下一阶段终态（DISSOLVE）
--- 所有方块（含边框）共用同一条"中心→外圈"的距离延迟波前：
---   内部方块 → idle
---   边框方块 → 新回合红/蓝（若传入 newAttackerIsLower），或保持当前色（不传入时不参与消散）
--- 设计意图：边框颜色随波前到达最外圈时自然揭开，无独立动画轨道。
---@param duration number
---@param newAttackerIsLower boolean|nil  传入则边框跟随波前在到达时切换到新回合颜色
function BattleGrid:dissolve(duration, newAttackerIsLower)
    duration = duration or 1.2
    -- 停止波环、流动动画、高亮呼吸（dissolve 将重建边框底态，高亮由后续 signalActiveSide 重新触发）
    self._wave.active        = false
    self._wave.decaying      = false
    self._flowAnim.active    = false
    local ha = self._highlightAnim
    ha.active          = false
    ha.factor.lower    = 0.0
    ha.factor.upper    = 0.0
    ha.target.lower    = 0.0
    ha.target.upper    = 0.0
    ha.breatheTimer    = 0.0

    local cx = (COLS + 1) * 0.5
    local cz = (ROWS + 1) * 0.5
    local maxDist = math.sqrt((COLS / 2) ^ 2 + (ROWS / 2) ^ 2)

    for row = 1, ROWS do
        for col = 1, COLS do
            local b    = self._blocks[row][col]
            local dx   = col - cx
            local dz   = row - cz
            local dist = math.sqrt(dx * dx + dz * dz) / maxDist
            -- 所有方块共用同一套距离→延迟公式，边框天然在最外圈所以最晚被揭开
            local delay = math.max(0, dist * duration * 0.75 + noise(duration * 0.09))

            if isBorderBlock(row, col) then
                -- 边框方块：有新攻击方信息时跟随波前切换颜色；否则不参与消散（保持当前状态）
                if newAttackerIsLower ~= nil then
                    local colorKey = borderColorKey(row, newAttackerIsLower)
                    b.delay         = delay
                    b.elapsed       = 0
                    b.triggered     = false
                    b.pendingMat    = self._matTemplates[colorKey]
                    b.pendingMatKey = colorKey
                    b.pendingH      = BORDER_REST_H
                end
            else
                -- 内部方块：从中心向外消散到 idle（复用循环顶部已算好的 b / delay）
                b.delay         = delay
                b.elapsed       = 0
                b.triggered     = false
                b.pendingMat    = self._matTemplates.idle
                b.pendingMatKey = "idle"
                b.pendingH      = IDLE_H
            end
        end
    end
    self._sweeping = true

    -- 若已传入新攻击方，边框状态直接更新为终态
    if newAttackerIsLower ~= nil then
        self._borderState.attackerIsLower = newAttackerIsLower
        self._borderState.initialized     = true
    else
        self._borderState.initialized = false
    end
end

-- ============================================================================
-- 边框视觉系统
-- ============================================================================

--- 建立边框底态：外圈红/蓝，内部灰
--- attackerIsLower: true = 下半区为红（攻击方），上半区为蓝（防御方）
--- instant: true = 立即切换，false = 带动画延迟
--- activeIsLower: nil = 不高亮任何一侧；true/false = 高亮指定侧（用 _active 变体色）
function BattleGrid:setBorderState(attackerIsLower, instant, activeIsLower)
    self._borderState.attackerIsLower = attackerIsLower
    self._borderState.initialized     = true

    instant = (instant == true)

    -- 预建 borderRing 序号查找表（避免 setBorderState 中 O(n²) 遍历）
    local ringIdxOf = {}
    for i, cell in ipairs(self._borderRing) do
        ringIdxOf[cell.row * 100 + cell.col] = i
    end

    for row = 1, ROWS do
        for col = 1, COLS do
            local b = self._blocks[row][col]
            if isBorderBlock(row, col) then
                -- 颜色：普通版或 active 高亮版；高度：始终 BORDER_REST_H
                local colorKey = borderColorKey(row, attackerIsLower, activeIsLower)

                if instant then
                    b.triggered     = true
                    b.targetScaleY  = BORDER_REST_H
                    b.baseH         = BORDER_REST_H
                    b.pendingH      = BORDER_REST_H
                    b.pendingMatKey = colorKey
                    local newMat = self._matTemplates[colorKey]:Clone()
                    b.mdl:SetMaterial(newMat)
                    b.mat       = newMat
                    b.matDefKey = colorKey
                else
                    -- 外圈按顺时针序号错开延迟，形成流光感
                    local ringIdx = ringIdxOf[row * 100 + col] or 1
                    local delay = (ringIdx - 1) * 0.012 + noise(0.02)
                    self:_scheduleBlock(row, col, colorKey, BORDER_REST_H, math.max(0, delay))
                end
            else
                -- 内部方块归回 idle（instant 下不需要重新触发，保持现状即可）
                if not instant then
                    local d = math.random() * 0.15
                    self:_scheduleBlock(row, col, "idle", IDLE_H, d)
                end
            end
        end
    end

    if instant then
        self._sweeping = true
    end
end

--- 行动方指示：指定侧切换到高亮色（_active 变体），另一侧回普通色
--- isLower: true = 下半区行动；false = 上半区行动；nil = 全部回普通色（无高亮）
--- 通过 _highlightAnim 平滑因子过渡，lower/upper 两侧独立淡入淡出
function BattleGrid:signalActiveSide(isLower)
    if not self._borderState.initialized then return end

    local ha = self._highlightAnim
    ha.target.lower = (isLower == true)  and 1.0 or 0.0
    ha.target.upper = (isLower == false) and 1.0 or 0.0
    ha.active       = true
    self._sweeping  = true
end

--- 计算给定 attackerIsLower 状态下，红色段的起始 ring 索引（0-indexed 浮点）
--- 设计：ring[0..35] 顺时针排列，attackerIsLower=true 时下半区为红
---   attackerIsLower=true:  ring[15..32] 为红（row>4 的方块居多），redStart=15
---   attackerIsLower=false: ring[33..35]+ring[0..14] 为红，等价 redStart=33
local function calcRedStart(attackerIsLower)
    -- 通过实际遍历统计确定：上边row=1为蓝，下边row=8为红
    -- ring 顺序: 上边(row=1,col1→12), 右边(row2→8,col=12), 下边(row=8,col11→1), 左边(row7→2,col=1)
    -- attackerIsLower=true（下半攻击=红）: 下边整行(row=8)=红，约 ring[19..29]；
    --   右下角+左下角也是红，实测红段为 ring[15..32]
    -- attackerIsLower=false: 红段为 ring[33..35]+ring[0..14]，等价起点 33
    if attackerIsLower then
        return 15.0
    else
        return 33.0
    end
end

--- 顺时针颜色流动动画（无战斗换边）
--- 逐帧算法：在动画时间内 redStart 从旧值旋转到新值（顺时针 = +halfRing），
--- 每帧根据当前 redStart 直接重新着色整圈方块，视觉上红蓝两段同时顺时针转动。
--- newAttackerIsLower: 换边后新的攻击方位置
--- duration: 整体流动时间（秒）
--- onDone: 流动完成后回调
function BattleGrid:flowBorderColors(newAttackerIsLower, duration, onDone)
    if self._flowAnim.active then return end

    duration = duration or 1.5

    local fa       = self._flowAnim
    local ringSize = fa.ringSize   -- 36
    local halfRing = fa.halfRing   -- 18

    -- 旧状态 redStart（如尚未初始化则用当前攻击方推算）
    local oldStart
    if self._borderState.initialized then
        oldStart = calcRedStart(self._borderState.attackerIsLower)
    else
        oldStart = calcRedStart(newAttackerIsLower)
    end

    -- 新状态 redStart
    local newStart = calcRedStart(newAttackerIsLower)

    -- 顺时针旋转距离（始终为正 halfRing，两段恰好换位）
    -- 两种攻击方状态正好互差 18，确保正向顺时针旋转 18 格
    local delta = (newStart - oldStart) % ringSize
    if delta == 0 then delta = halfRing end  -- 防守：同色换边也旋转半圈

    -- 动画参数写入
    fa.active      = true
    fa.timer       = 0
    fa.duration    = duration
    fa.redStart    = oldStart        -- 动画当前位置（逐帧递进）
    fa.targetStart = oldStart + delta
    fa.onDone      = onDone

    -- 流动期间锁定高亮写色，避免呼吸光覆盖流动颜色
    self:lockHighlight()

    -- 更新边框语义状态（立即，供其他逻辑读取）
    self._borderState.attackerIsLower = newAttackerIsLower
    self._borderState.initialized     = true
end

--- 查询边框是否已初始化（外部用于判断是否是第一次需要建立边框）
function BattleGrid:isBorderInitialized()
    return self._borderState.initialized
end

-- ============================================================================
-- 更新
-- ============================================================================

function BattleGrid:update(dt)
    -- 波环启动时清除信号标记（结算动画接管，生命周期由外部统一管理）
    if self._wave.active then
        self._signal.active = false
    end

    -- ---- 行动方高亮补间：lower/upper 两侧独立平滑因子 + 呼吸发亮 ----
    -- wave 活跃（金色覆盖等结算动画）期间：只推进计时器，不写色，避免与结算动画互相覆盖
    if self._highlightAnim.active and self._borderState.initialized then
        local ha   = self._highlightAnim
        local spd  = ha.speed * dt
        local done = true

        -- 推进淡入/淡出因子
        for _, key in ipairs({ "lower", "upper" }) do
            local diff = ha.target[key] - ha.factor[key]
            if math.abs(diff) > 0.001 then
                ha.factor[key] = ha.factor[key] + diff * math.min(1.0, spd)
                done = false
            else
                ha.factor[key] = ha.target[key]
            end
        end

        -- 推进呼吸计时器（任意一侧激活时持续运转）
        local anyActive = (ha.target.lower > 0.5 or ha.target.upper > 0.5)
        if anyActive then
            ha.breatheTimer = ha.breatheTimer + dt * ha.breatheSpeed
            done = false  -- 有激活侧时永不停止 active
        end

        -- 结算动画全程锁定时跳过写色（_hlLocked 由 GameController 在 BR 触发/结束时设置）
        if not self._hlLocked then
            -- 呼吸因子：sin 波映射到 [breatheMin, 1.0]
            local breatheBase = (1.0 + math.sin(ha.breatheTimer)) * 0.5  -- [0, 1]
            local breatheF    = ha.breatheMin + breatheBase * (1.0 - ha.breatheMin)

            -- 将当前因子写入所有边框方块（从 attackerIsLower 直接推导颜色，不依赖 matDefKey）
            local attackerIsLower = self._borderState.attackerIsLower
            -- 当前行动方在哪侧：lower 侧被激活时 activeSideIsLower=true，上侧激活时=false，无激活时=nil
            local activeSideIsLower = nil
            if ha.target.lower > 0.5 then activeSideIsLower = true
            elseif ha.target.upper > 0.5 then activeSideIsLower = false
            end
            for _, cell in ipairs(self._borderRing) do
                local b            = self._blocks[cell.row][cell.col]
                local isBlockLower = (cell.row > ROWS / 2)
                local baseKey      = borderColorKey(cell.row, attackerIsLower, nil)
                -- activeKey 仅当此块位于行动方侧时使用 _active 变体
                local activeKey    = borderColorKey(cell.row, attackerIsLower, activeSideIsLower)
                local rawF         = isBlockLower and ha.factor.lower or ha.factor.upper
                local f            = rawF * breatheF
                -- 边框块高度固定，用呼吸因子直接驱动亮度（让 emissive 随呼吸明显脉冲）
                local bright       = 1.0 + f * 1.6
                applyBlendedColor(b.mat, MAT_DEF[baseKey], MAT_DEF[activeKey], f, bright)
                if done then
                    b.matDefKey = (rawF >= 0.5) and activeKey or baseKey
                end
            end
        end

        if done then ha.active = false end
        self._sweeping = true
    end

    -- ---- 顺时针流动动画：逐帧旋转 ----
    if self._flowAnim.active then
        local fa  = self._flowAnim
        fa.timer  = fa.timer + dt
        local p   = math.min(1.0, fa.timer / fa.duration)

        -- 缓动：ease-in-out（视觉上加减速感）
        local easedP = p < 0.5 and (2 * p * p) or (1 - (-2 * p + 2) ^ 2 * 0.5)

        -- 当前帧 redStart（浮点，顺时针递进）
        local rStart = fa.redStart + easedP * (fa.targetStart - fa.redStart)
        local n      = fa.ringSize   -- 36
        local half   = fa.halfRing   -- 18

        -- 逐帧重新着色整圈外框
        for i, cell in ipairs(self._borderRing) do
            local idx0    = i - 1   -- 0-indexed
            -- 计算该位置到当前 redStart 的顺时针距离
            local dist    = (idx0 - rStart) % n
            local colorKey = (dist < half) and "red" or "blue"
            local b       = self._blocks[cell.row][cell.col]

            if b.matDefKey ~= colorKey then
                local newMat = self._matTemplates[colorKey]:Clone()
                b.mdl:SetMaterial(newMat)
                b.mat       = newMat
                b.matDefKey = colorKey
                applyBrightness(b.mat, MAT_DEF[colorKey], heightBrightness(b.scaleY))
            end
            b.triggered    = true
            b.targetScaleY = BORDER_REST_H
            b.baseH        = BORDER_REST_H
        end
        self._sweeping = true

        if p >= 1.0 then
            fa.active = false
            self:unlockHighlight()  -- 流动结束，恢复高亮呼吸
            if fa.onDone then
                fa.onDone()
                fa.onDone = nil
            end
        end
    end

    -- ---- 1. 波环逻辑 ----
    self:_updateWave(dt)

    -- ---- 2. 延迟触发 + 高度平滑插值 ----
    if not self._sweeping then
        -- 平时只做波环高度；但如果高亮呼吸在运行，也需要继续 update
        if not self._wave.active and not self._highlightAnim.active then return end
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
            -- 高亮补间激活且未被锁定时，边框方块由 _highlightAnim 段负责写色，此处跳过避免覆盖
            -- 锁定期间（结算动画）高亮不写色，applyBrightness 正常运行
            local isHL = self._highlightAnim.active and not self._hlLocked and isBorderBlock(row, col)
            if not isHL and (self._wave.active or moving or not b.triggered) then
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

--- 锁定高亮写色（结算动画期间调用，防止呼吸光与结算动画冲突）
function BattleGrid:lockHighlight()
    self._hlLocked = true
end

--- 解锁高亮写色（结算动画结束后调用）
--- 重置呼吸相位到最低点，确保解锁后从暗渐亮而非突然跳亮
function BattleGrid:unlockHighlight()
    self._hlLocked = false
    self._highlightAnim.breatheTimer = -math.pi * 0.5  -- sin(-π/2)=-1 → breatheF=breatheMin
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

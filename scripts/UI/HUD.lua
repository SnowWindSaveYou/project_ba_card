-- ============================================================================
-- UI/HUD.lua - NanoVG 全矢量主 HUD (v8 · Blue Archive)
-- 设计参考:
--   Blue Archive: 亮底白面板、珊瑚红/薄荷绿、左侧竖条、圆润阴影
--   配色: 浅蓝白底 + 珊瑚红 + 薄荷绿 + 暖黄 + 深藏青文字
--   布局: 英雄面板 → 3D Quad（HeroPanel3D），NanoVG 只叠加文字信息
-- ============================================================================

local Theme        = require("UI.Theme")
local InputManager = require("Input.InputManager")

local HUD = {}

-- ============================================================================
-- 交互区域常量（区域名称枚举）
-- ============================================================================
HUD.ZONE = {
    HERO        = "hero",
    WEAPON      = "weapon",
    ARMOR_UPPER = "armor_upper",
    ARMOR_LOWER = "armor_lower",
}

-- 每个区域的 hover 累计时间（长按检测）
local LONG_PRESS_THRESHOLD = 0.5   -- 秒

local interact_ = {
    hoveredZone   = nil,   -- 当前悬停区域
    hoverTime     = 0,     -- 悬停累计时间（秒）
    longFired     = false, -- 本次悬停是否已触发长按
}

-- ============================================================================
-- Blue Archive 配色表（基于 Theme 常量）
-- 亮底白面板 · 珊瑚红/薄荷绿双色系 · 深藏青文字
-- ============================================================================
local C = {
    -- 面板 / 底板（亮白、浅蓝）
    panelBg    = function(a) return Theme.rgba(Theme.BG_PANEL, a or 230) end,
    panelEdge  = function(a) return Theme.rgba(Theme.BLUE, a or 50) end,
    panelShadow= function(a) return nvgRGBA(180, 196, 230, a or 60) end,

    -- 玩家色系（薄荷绿）
    playerMain  = function(a) return Theme.rgba(Theme.GREEN, a or 255) end,
    playerLight = function(a) return Theme.rgba(Theme.GREEN_BRIGHT, a or 255) end,
    playerDark  = function(a) return Theme.rgba(Theme.GREEN_DIM, a or 255) end,
    playerGlow  = function(a) return Theme.rgba(Theme.GREEN, a or 40) end,

    -- 对手色系（珊瑚红）
    oppMain     = function(a) return Theme.rgba(Theme.RED, a or 255) end,
    oppLight    = function(a) return Theme.rgba(Theme.RED_BRIGHT, a or 255) end,
    oppDark     = function(a) return Theme.rgba(Theme.RED_DIM, a or 255) end,
    oppGlow     = function(a) return Theme.rgba(Theme.RED, a or 40) end,

    -- 生命值（珊瑚红填充）
    heartMain   = function(a) return Theme.rgba(Theme.RED, a or 255) end,
    heartDark   = function(a) return Theme.rgba(Theme.RED_DIM, a or 255) end,
    heartGlow   = function(a) return Theme.rgba(Theme.RED, a or 50) end,

    -- 架势 / 武器（暖黄）
    stanceMain  = function(a) return Theme.rgba(Theme.GOLD, a or 255) end,
    stanceDark  = function(a) return Theme.rgba(Theme.GOLD_DIM, a or 255) end,

    -- 充能（蔚蓝）
    energyMain  = function(a) return Theme.rgba(Theme.BLUE, a or 255) end,
    energyGlow  = function(a) return Theme.rgba(Theme.BLUE, a or 50) end,

    -- 费用（薰衣草紫）
    costMain    = function(a) return Theme.rgba(Theme.PURPLE, a or 255) end,

    -- 护具（薄荷绿圆点）
    armorFill   = function(a) return Theme.rgba(Theme.GREEN, a or 220) end,
    armorEmpty  = function(a) return Theme.rgba(Theme.TEXT_DIM, a or 70) end,

    -- 文字（深藏青主文 · 蓝灰次文 · 浅灰弱化）
    textPrimary   = function(a) return Theme.rgba(Theme.TEXT_PRIMARY, a or 255) end,
    textSecondary = function(a) return Theme.rgba(Theme.TEXT_SECONDARY, a or 200) end,
    textDim       = function(a) return Theme.rgba(Theme.TEXT_DIM, a or 160) end,

    -- 功能
    gold        = function(a) return Theme.rgba(Theme.GOLD, a or 255) end,
    goldBright  = function(a) return Theme.rgba(Theme.GOLD_BRIGHT, a or 255) end,
    goldDim     = function(a) return Theme.rgba(Theme.GOLD_DIM, a or 255) end,
}

-- ============================================================================
-- 状态
-- ============================================================================

local state = {
    -- === 己方角色 ===
    myName      = "一之濑枫",
    myStyle     = "剑道",
    myLife      = 20,
    myLifeMax   = 20,
    myLifeDisplay = 20,

    myStanceName  = "竹刀",
    myStancePower = 3,
    myStanceCost  = 1,

    myArmorUpper     = "剑道胴",
    myArmorUpperCur  = 3,
    myArmorUpperMax  = 3,
    myArmorLower     = "袴裙",
    myArmorLowerCur  = 2,
    myArmorLowerMax  = 2,

    myEnergy     = 0,
    myEnergyMax  = 0,

    myDeckCount  = 24,
    myHandCount  = 0,
    myGraveyardCount = 0,
    myBanishCount    = 0,
    myArsenalCount   = 0,

    -- === 对手角色 ===
    oppName      = "夏琳",
    oppStyle     = "跆拳道",
    oppLife      = 18,
    oppLifeMax   = 18,
    oppLifeDisplay = 18,

    oppStanceName  = "格斗站姿",
    oppStancePower = 2,
    oppStanceCost  = 0,

    oppArmorUpper     = "跆拳道护甲",
    oppArmorUpperCur  = 2,
    oppArmorUpperMax  = 2,
    oppArmorLower     = "竞技护腿",
    oppArmorLowerCur  = 3,
    oppArmorLowerMax  = 3,

    oppEnergy     = 0,
    oppEnergyMax  = 0,

    oppDeckCount  = 26,
    oppHandCount  = 4,
    oppGraveyardCount = 0,
    oppBanishCount    = 0,
    oppArsenalCount   = 0,

    -- === 游戏状态 ===
    actionPoints = 1,
    maxActionPoints = 1,

    dragging = false,
    abovePlayLine = false,
    belowPitchLine = false,
    chainCount = 0,
    currentPhase = 3,
    time = 0,

    -- === M4: 玩家交互状态 ===
    waitingForInput = false,
    isPlayerTurn    = false,
    statusHint      = "",
    aiThinking      = false,
}

-- ============================================================================
-- 更新状态
-- ============================================================================

function HUD.updateState(updates)
    for k, v in pairs(updates) do
        if state[k] ~= nil then
            state[k] = v
        end
    end
end

function HUD.setMyLife(newLife) state.myLife = newLife end
function HUD.setOppLife(newLife) state.oppLife = newLife end

-- ============================================================================
-- 交互区域检测
-- ============================================================================

-- ============================================================================
-- 3D 英雄面板屏幕矩形（由外部每帧注入，单位：NanoVG 逻辑像素）
-- ============================================================================
-- heroPanel_ 存储新版多子矩形投影（英雄卡/武器卡/装备卡各自的屏幕区域）
local heroPanel_ = {
    player = {
        hero    = { x=0, y=0, w=0, h=0 },
        weap    = { x=0, y=0, w=0, h=0 },
        equipUp = { x=0, y=0, w=0, h=0 },
        equipLo = { x=0, y=0, w=0, h=0 },
    },
    opp = {
        hero    = { x=0, y=0, w=0, h=0 },
        weap    = { x=0, y=0, w=0, h=0 },
        equipUp = { x=0, y=0, w=0, h=0 },
        equipLo = { x=0, y=0, w=0, h=0 },
    },
}

--- 注入 HeroPanel3D 实例的各子区域投影（每帧在 main.lua 中调用）
---@param playerPanel table HeroPanel3D 实例
---@param oppPanel    table HeroPanel3D 实例
function HUD.setHeroPanelRects(playerPanel, oppPanel)
    local function copyRects(dest, src)
        local function r(s) return { x=s.x, y=s.y, w=s.w, h=s.h } end
        dest.hero    = r(src.heroRect    or { x=0, y=0, w=0, h=0 })
        dest.weap    = r(src.weapRect    or { x=0, y=0, w=0, h=0 })
        dest.equipUp = r(src.equipUpRect or { x=0, y=0, w=0, h=0 })
        dest.equipLo = r(src.equipLoRect or { x=0, y=0, w=0, h=0 })
    end
    copyRects(heroPanel_.player, playerPanel)
    copyRects(heroPanel_.opp,    oppPanel)
end

--- 每帧处理玩家英雄区域（武器、护具）的鼠标交互。
--- 命中区域基于 3D 面板投影坐标（由 HeroPanel3D.calcScreenRect 提供）。
---@param mx number NanoVG 逻辑坐标鼠标 X
---@param my number NanoVG 逻辑坐标鼠标 Y
---@param w  number NanoVG 画布宽度
---@param h  number NanoVG 画布高度
---@param dt number 帧时间（秒）
---@param mousePressed boolean 本帧是否按下左键
---@return table result { hovered=string|nil, clicked=string|nil, longPressed=string|nil }
function HUD.update(mx, my, w, h, dt, mousePressed)
    -- ---- 从 3D 面板各子卡投影区域推导交互区域 ----
    local pr = heroPanel_.player
    local heroR  = pr.hero
    local weapR  = pr.weap
    local equipUpR = pr.equipUp
    local equipLoR = pr.equipLo

    local function hitRect(rx, ry, rw, rh)
        return mx >= rx and mx <= rx + rw and my >= ry and my <= ry + rh
    end

    local hitZone = nil
    if heroR.w > 0 and hitRect(heroR.x, heroR.y, heroR.w, heroR.h) then
        hitZone = HUD.ZONE.HERO
    elseif weapR.w > 0 and hitRect(weapR.x, weapR.y, weapR.w, weapR.h) then
        hitZone = HUD.ZONE.WEAPON
    elseif equipUpR.w > 0 and hitRect(equipUpR.x, equipUpR.y, equipUpR.w, equipUpR.h) then
        hitZone = HUD.ZONE.ARMOR_UPPER
    elseif equipLoR.w > 0 and hitRect(equipLoR.x, equipLoR.y, equipLoR.w, equipLoR.h) then
        hitZone = HUD.ZONE.ARMOR_LOWER
    end

    -- ---- 只要命中就消费鼠标（阻止 3D 卡牌响应）----
    if hitZone then
        InputManager.consumeMouse()
    end

    -- ---- 长按计时 ----
    local result = { hovered = hitZone, clicked = nil, longPressed = nil }

    if hitZone ~= interact_.hoveredZone then
        -- 切换到新区域：重置计时器
        interact_.hoveredZone = hitZone
        interact_.hoverTime   = 0
        interact_.longFired   = false
    end

    if hitZone then
        interact_.hoverTime = interact_.hoverTime + dt

        -- 长按判定（每次悬停只触发一次）
        if not interact_.longFired and interact_.hoverTime >= LONG_PRESS_THRESHOLD then
            interact_.longFired  = true
            result.longPressed   = hitZone
        end

        -- 点击判定
        if mousePressed then
            result.clicked = hitZone
        end
    end

    return result
end

-- ============================================================================
-- 辅助绘制
-- ============================================================================

--- 绘制亮色面板（BA 风格：白底 + 浅蓝阴影 + 蓝色细边）
local function drawLightPanel(ctx, x, y, w, h, radius, accentColor)
    accentColor = accentColor or Theme.BLUE
    -- 柔阴影（浅蓝色投影，BA 特色）
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, x + 2, y + 4, w, h, radius)
    nvgFillColor(ctx, C.panelShadow(55))
    nvgFill(ctx)
    -- 白色底（带顶部微渐变）
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, x, y, w, h, radius)
    local bg = nvgLinearGradient(ctx, x, y, x, y + h,
        nvgRGBA(255, 255, 255, 248), nvgRGBA(240, 245, 255, 235))
    nvgFillPaint(ctx, bg)
    nvgFill(ctx)
    -- 蓝色细边
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, x, y, w, h, radius)
    nvgStrokeColor(ctx, Theme.rgba(accentColor, 55))
    nvgStrokeWidth(ctx, 1.2)
    nvgStroke(ctx)
end

--- 绘制亮色圆形 badge（白底 + 彩色填充 + 浅阴影）
local function drawLightCircle(ctx, cx, cy, r, fillColor)
    -- 浅阴影
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx + 1, cy + 2, r + 1)
    nvgFillColor(ctx, C.panelShadow(40))
    nvgFill(ctx)
    -- 填充色
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy, r)
    nvgFillColor(ctx, fillColor)
    nvgFill(ctx)
    -- 白色顶部光泽
    nvgBeginPath(ctx)
    nvgEllipse(ctx, cx, cy - r * 0.28, r * 0.55, r * 0.28)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 70))
    nvgFill(ctx)
end

-- ============================================================================
-- 主绘制
-- ============================================================================

function HUD.draw(ctx, w, h, fontId, time)
    state.time = time

    -- 滚动数字
    state.myLifeDisplay  = state.myLifeDisplay  + (state.myLife  - state.myLifeDisplay)  * 0.1
    state.oppLifeDisplay = state.oppLifeDisplay + (state.oppLife - state.oppLifeDisplay) * 0.1

    nvgFontFaceId(ctx, fontId)

    drawPhaseColumn(ctx, w, h)
    -- 英雄面板主体由 HeroPanel3D（3D Quad）渲染，这里只叠加文字信息
    drawHeroPanelOverlay(ctx, w, h, fontId)
    drawOpponentPanelOverlay(ctx, w, h, fontId)
    -- 能量已迁移至右侧 ActionBar 面板显示（drawPlayerEnergy 已移除）
    drawBottomHint(ctx, w, h)
end

-- ============================================================================
-- 左侧竖排阶段指示器（BA 风格：白底 + 薄荷绿活跃项 + 蓝色细边）
-- ============================================================================

function drawPhaseColumn(ctx, w, h)
    local phases = { "开始", "抽牌", "行动", "连招", "结束" }
    local itemW = 72
    local itemH = 36
    local gap   = 7
    local totalH = #phases * itemH + (#phases - 1) * gap
    local startX = 12
    local startY = (h - totalH) / 2

    for i, name in ipairs(phases) do
        local ix = startX
        local iy = startY + (i - 1) * (itemH + gap)
        local active = (i == state.currentPhase)
        local isPast = (i < state.currentPhase)

        if active then
            -- 浅蓝阴影
            nvgBeginPath(ctx)
            nvgRoundedRect(ctx, ix + 2, iy + 4, itemW, itemH, 12)
            nvgFillColor(ctx, C.panelShadow(50))
            nvgFill(ctx)
            -- 薄荷绿底
            nvgBeginPath(ctx)
            nvgRoundedRect(ctx, ix, iy, itemW, itemH, 12)
            local bg = nvgLinearGradient(ctx, ix, iy, ix, iy + itemH,
                Theme.rgba(Theme.GREEN_BRIGHT, 240),
                Theme.rgba(Theme.GREEN, 230))
            nvgFillPaint(ctx, bg)
            nvgFill(ctx)
            -- 白色细边
            nvgBeginPath(ctx)
            nvgRoundedRect(ctx, ix, iy, itemW, itemH, 12)
            nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 160))
            nvgStrokeWidth(ctx, 1.5)
            nvgStroke(ctx)
            -- 白色文字
            nvgFontSize(ctx, 17)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
            nvgText(ctx, ix + itemW / 2, iy + itemH / 2, name, nil)
        else
            -- 白底浅蓝边
            nvgBeginPath(ctx)
            nvgRoundedRect(ctx, ix, iy, itemW, itemH, 12)
            nvgFillColor(ctx, nvgRGBA(255, 255, 255, isPast and 220 or 160))
            nvgFill(ctx)
            nvgBeginPath(ctx)
            nvgRoundedRect(ctx, ix, iy, itemW, itemH, 12)
            nvgStrokeColor(ctx, Theme.rgba(Theme.BLUE, isPast and 35 or 20))
            nvgStrokeWidth(ctx, 1)
            nvgStroke(ctx)
            -- 左侧竖条（已完成项显示薄荷绿小竖条）
            if isPast then
                nvgBeginPath(ctx)
                nvgRoundedRect(ctx, ix, iy + itemH * 0.2, 3, itemH * 0.6, 2)
                nvgFillColor(ctx, Theme.rgba(Theme.GREEN, 180))
                nvgFill(ctx)
            end
            nvgFontSize(ctx, 14)
            nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            if isPast then
                nvgFillColor(ctx, C.textSecondary(180))
            else
                nvgFillColor(ctx, C.textDim(130))
            end
            nvgText(ctx, ix + itemW / 2, iy + itemH / 2, name, nil)
        end
    end
end

-- ============================================================================
-- NanoVG 叠加层 — 己方英雄面板（显示在 3D Quad 上方）
-- ============================================================================

-- 内部：绘制英雄卡叠加层（HP 数字叠在右下角 3D badge 上）
-- 名称/流派已省略；badge 图形由 3D Quad 负责，NanoVG 只叠数字
local function drawHeroCardOverlay(ctx, r, name, style, lifeDisplay, isPlayer)
    if r.w <= 0 then return end
    local sz = isPlayer and 1.0 or 0.85

    -- HP 数字（右下角，叠在 3D defense badge 上）
    -- badge 中心 = 卡右侧 0.36w，卡底 0.38h（与 HeroPanel3D.buildCard 的 BADGE_SIZE 对齐）
    local bx = r.x + r.w * (1 - 0.14)   -- ≈ r.x + r.w - r.w*0.36*0.5（视角投影近似）
    local by = r.y + r.h * (1 - 0.12)
    local fontSize = math.max(10, math.floor(r.h * 0.16 * sz))
    nvgFontSize(ctx, fontSize)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
    nvgText(ctx, bx, by, string.format("%.0f", lifeDisplay), nil)
end

-- 内部：绘制武器卡叠加层（cost 数字叠左上 badge，attack 数字叠左下 badge）
-- 名称已省略；badge 图形由 3D Quad 负责，NanoVG 只叠数字
local function drawWeaponCardOverlay(ctx, r, stanceName, power, cost, isPlayer)
    if r.w <= 0 then return end
    local sz = isPlayer and 1.0 or 0.85
    local fontSize = math.max(9, math.floor(r.h * 0.18 * sz))

    nvgFontSize(ctx, fontSize)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))

    -- 费用数字（左上角 cost badge 上）
    local topBadgeX = r.x + r.w * 0.14
    local topBadgeY = r.y + r.h * 0.12
    nvgText(ctx, topBadgeX, topBadgeY, tostring(cost), nil)

    -- 攻击力数字（左下角 attack badge 上）
    local botBadgeX = r.x + r.w * 0.14
    local botBadgeY = r.y + r.h * (1 - 0.12)
    nvgText(ctx, botBadgeX, botBadgeY, tostring(power), nil)
end

-- 内部：绘制装备卡叠加层（耐久数字叠在右下角 3D defense badge 上）
-- 名称/钻石点已省略；badge 图形由 3D Quad 负责，NanoVG 只叠 "cur/max" 数字
local function drawEquipCardOverlay(ctx, r, armorName, cur, maxVal, isPlayer)
    if r.w <= 0 then return end
    local sz = isPlayer and 1.0 or 0.85
    local fontSize = math.max(9, math.floor(r.h * 0.18 * sz))

    -- 耐久数字（右下角 defense badge 上）
    local bx = r.x + r.w * (1 - 0.14)
    local by = r.y + r.h * (1 - 0.12)
    nvgFontSize(ctx, fontSize)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
    nvgText(ctx, bx, by, cur .. "/" .. maxVal, nil)
end

function drawHeroPanelOverlay(ctx, w, h, fontId)
    local pr = heroPanel_.player
    if pr.hero.w <= 0 then return end   -- 3D 面板尚未投影

    -- 英雄卡：名称 + 流派 + HP
    drawHeroCardOverlay(ctx, pr.hero,
        state.myName, state.myStyle, state.myLifeDisplay, true)

    -- 武器卡：武器名 + 攻击力 + 费用
    drawWeaponCardOverlay(ctx, pr.weap,
        state.myStanceName, state.myStancePower, state.myStanceCost, true)

    -- 上衣装备卡：名称 + 耐久
    drawEquipCardOverlay(ctx, pr.equipUp,
        state.myArmorUpper, state.myArmorUpperCur, state.myArmorUpperMax, true)

    -- 下衣装备卡：名称 + 耐久
    drawEquipCardOverlay(ctx, pr.equipLo,
        state.myArmorLower, state.myArmorLowerCur, state.myArmorLowerMax, true)

    -- 卡组信息（英雄卡正下方）
    local hr = pr.hero
    nvgFontSize(ctx, 10)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(ctx, C.textDim(130))
    local info = "手" .. state.myHandCount .. " 库" .. state.myDeckCount
        .. " 弃" .. state.myGraveyardCount
    nvgText(ctx, hr.x + hr.w * 0.5, hr.y + hr.h + 3, info, nil)
end

-- ============================================================================
-- NanoVG 叠加层 — 对手英雄面板
-- ============================================================================

function drawOpponentPanelOverlay(ctx, w, h, fontId)
    local pr = heroPanel_.opp
    if pr.hero.w <= 0 then return end

    -- 英雄卡：名称 + 流派 + HP
    drawHeroCardOverlay(ctx, pr.hero,
        state.oppName, state.oppStyle, state.oppLifeDisplay, false)

    -- 武器卡
    drawWeaponCardOverlay(ctx, pr.weap,
        state.oppStanceName, state.oppStancePower, state.oppStanceCost, false)

    -- 上衣装备卡
    drawEquipCardOverlay(ctx, pr.equipUp,
        state.oppArmorUpper, state.oppArmorUpperCur, state.oppArmorUpperMax, false)

    -- 下衣装备卡
    drawEquipCardOverlay(ctx, pr.equipLo,
        state.oppArmorLower, state.oppArmorLowerCur, state.oppArmorLowerMax, false)

    -- AI 思考动画（英雄卡下方）
    if state.aiThinking then
        local hr = pr.hero
        drawAIThinking(ctx, hr.x + hr.w * 0.5, hr.y + hr.h + 6)
    end
end

-- ============================================================================
-- 血量 badge（BA 风格：珊瑚红填充 + 白色数字）
-- ============================================================================

function drawHealthBubble(ctx, cx, cy, lifeDisplay, isPlayer)
    local r = isPlayer and 27 or 22

    drawLightCircle(ctx, cx, cy, r, C.heartMain(240))

    -- 数字（深色）
    nvgFontSize(ctx, isPlayer and 22 or 18)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
    nvgText(ctx, cx, cy, string.format("%.0f", lifeDisplay), nil)
end

-- ============================================================================
-- 架势/武器（BA 风格：白底圆形 + 薄荷绿/蓝边）
-- ============================================================================

function drawStanceBubble(ctx, cx, cy, name, power, cost, isPlayer)
    local r = isPlayer and 38 or 32
    local accentColor = isPlayer and Theme.GREEN or Theme.RED

    -- 浅阴影
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx + 1, cy + 2, r + 2)
    nvgFillColor(ctx, C.panelShadow(40))
    nvgFill(ctx)

    -- 白色底
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy, r)
    local bg = nvgRadialGradient(ctx, cx, cy - r * 0.3, r * 0.2, r,
        nvgRGBA(255, 255, 255, 255), nvgRGBA(235, 242, 255, 240))
    nvgFillPaint(ctx, bg)
    nvgFill(ctx)

    -- 彩色描边
    nvgBeginPath(ctx)
    nvgCircle(ctx, cx, cy, r)
    nvgStrokeWidth(ctx, 2)
    nvgStrokeColor(ctx, Theme.rgba(accentColor, 160))
    nvgStroke(ctx)

    -- 架势名首字（深色）
    local initial = string.sub(name, 1, 3)
    nvgFontSize(ctx, r * 0.56)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, C.textPrimary(230))
    nvgText(ctx, cx, cy - 4, initial, nil)

    -- 架势全名小字
    nvgFontSize(ctx, math.max(9, r * 0.22))
    nvgFillColor(ctx, C.textSecondary(140))
    nvgText(ctx, cx, cy + r * 0.45, name, nil)

    -- 攻击力 badge（左下角 — 珊瑚红）
    local badgeR = isPlayer and 14 or 11
    local rc = Theme.RED
    drawStatBubble(ctx, cx - r * 0.7, cy + r * 0.7, tostring(power),
        { rc.r, rc.g, rc.b }, badgeR)

    -- 费用 badge（右下角 — 紫）
    local pc = Theme.PURPLE
    drawStatBubble(ctx, cx + r * 0.7, cy + r * 0.7, tostring(cost),
        { pc.r, pc.g, pc.b }, badgeR)
end

--- 绘制小型数值角标（BA 风格：彩色填充 + 白色数字）
function drawStatBubble(ctx, cx, cy, text, color, r)
    drawLightCircle(ctx, cx, cy, r,
        nvgRGBA(color[1], color[2], color[3], 230))

    nvgFontSize(ctx, r * 1.3)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
    nvgText(ctx, cx, cy, text, nil)
end

-- ============================================================================
-- 护具槽（BA 风格：白底胶囊 + 薄荷绿耐久点）
-- ============================================================================

function drawArmorPill(ctx, x, y, name, cur, max, isPlayer)
    local slotW = isPlayer and 100 or 88
    local slotH = isPlayer and 30 or 26
    local radius = slotH / 2

    local broken = (cur <= 0)

    drawLightPanel(ctx, x, y, slotW, slotH, radius,
        broken and Theme.RED or (isPlayer and Theme.GREEN or Theme.RED))

    if broken then
        nvgFontSize(ctx, 12)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, C.textDim(160))
        nvgText(ctx, x + slotW / 2, y + slotH / 2, "破损", nil)
        return
    end

    -- 护具名
    local shortName = string.sub(name, 1, 5)
    local fontSize = isPlayer and 12 or 11
    nvgFontSize(ctx, fontSize)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, C.textPrimary(200))
    nvgText(ctx, x + 7, y + slotH / 2, shortName, nil)

    -- 耐久圆点（薄荷绿实心 + 浅色空心）
    local dotR = isPlayer and 4 or 3
    local dotSpacing = isPlayer and 11 or 9
    local dotsW = max * dotSpacing
    local dotStartX = x + slotW - dotsW - 4

    for i = 1, max do
        local dx = dotStartX + (i - 1) * dotSpacing
        local dy = y + slotH / 2
        nvgBeginPath(ctx)
        nvgCircle(ctx, dx, dy, dotR)
        if i <= cur then
            nvgFillColor(ctx, C.armorFill(220))
        else
            nvgFillColor(ctx, C.armorEmpty(80))
        end
        nvgFill(ctx)
    end
end

-- ============================================================================
-- 充能水晶 — 己方（底部右侧 — 信息蓝）
-- ============================================================================

function drawPlayerEnergy(ctx, w, h)
    local energy    = state.myEnergy
    local energyMax = state.myEnergyMax
    if energyMax <= 0 then return end

    local crystalSize = 18
    local spacing = 24
    local maxDisplay = math.min(energyMax, 10)

    local rowY = h - 40
    local totalW = maxDisplay * spacing + 64
    local startX = w - totalW - 20

    for i = 1, maxDisplay do
        local cx = startX + (i - 1) * spacing
        local cy = rowY
        local full = i <= energy

        if full then
            -- 蓝色发光
            nvgBeginPath(ctx)
            nvgCircle(ctx, cx, cy, crystalSize)
            local glow = nvgRadialGradient(ctx, cx, cy, 3, crystalSize,
                Theme.rgba(Theme.BLUE, 70), Theme.rgba(Theme.BLUE, 0))
            nvgFillPaint(ctx, glow)
            nvgFill(ctx)

            drawDiamond(ctx, cx, cy, crystalSize * 0.48)
            nvgFillColor(ctx, Theme.rgba(Theme.BLUE, 240))
            nvgFill(ctx)

            -- 微光
            drawDiamond(ctx, cx, cy - 2, crystalSize * 0.22)
            nvgFillColor(ctx, nvgRGBA(180, 220, 255, 80))
            nvgFill(ctx)
        else
            drawDiamond(ctx, cx, cy, crystalSize * 0.48)
            nvgFillColor(ctx, C.textDim(80))
            nvgFill(ctx)
            drawDiamond(ctx, cx, cy, crystalSize * 0.48)
            nvgStrokeColor(ctx, C.textDim(40))
            nvgStrokeWidth(ctx, 1)
            nvgStroke(ctx)
        end
    end

    local numX = startX + maxDisplay * spacing + 10
    nvgFontSize(ctx, 17)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, C.energyMain(220))
    nvgText(ctx, numX, rowY, energy .. "/" .. energyMax, nil)
end

--- 绘制菱形
function drawDiamond(ctx, cx, cy, half)
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cx, cy - half)
    nvgLineTo(ctx, cx + half, cy)
    nvgLineTo(ctx, cx, cy + half)
    nvgLineTo(ctx, cx - half, cy)
    nvgClosePath(ctx)
end

-- ============================================================================
-- 充能水晶 — 对手
-- ============================================================================

function drawOppEnergy(ctx, w, h)
    local energy    = state.oppEnergy
    local energyMax = state.oppEnergyMax
    if energyMax <= 0 then return end

    local heroR = 48
    local heroY = heroR + 50
    local ex = w * 0.50 + heroR + 58
    local ey = heroY + heroR + 46

    local r = 8
    drawDiamond(ctx, ex, ey, r)
    nvgFillColor(ctx, Theme.rgba(Theme.BLUE, 200))
    nvgFill(ctx)

    nvgFontSize(ctx, 14)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, C.energyMain(180))
    nvgText(ctx, ex + 12, ey, energy .. "/" .. energyMax, nil)
end

-- ============================================================================
-- AI 思考动画（暗底胶囊 + 朱砂红跳动圆点）
-- ============================================================================

function drawAIThinking(ctx, cx, cy)
    local t = state.time

    -- 暗色胶囊底板
    local pillW = 100
    local pillH = 26
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, cx - pillW / 2, cy, pillW, pillH, pillH / 2)
    nvgFillColor(ctx, nvgRGBA(28, 20, 24, 200))
    nvgFill(ctx)

    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, cx - pillW / 2, cy, pillW, pillH, pillH / 2)
    nvgStrokeColor(ctx, Theme.rgba(Theme.RED_DIM, 60))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)

    -- "思考中" 文字
    nvgFontSize(ctx, 12)
    nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, Theme.rgba(Theme.RED, 200))
    nvgText(ctx, cx + 2, cy + pillH / 2, "思考中", nil)

    -- 三个跳动圆点（朱砂红）
    local dotR = 3.5
    local dotSpacing = 10
    local baseX = cx + 12
    local baseY = cy + pillH / 2

    for i = 0, 2 do
        local phase = (t * 4.0 + i * 0.9) % (math.pi * 2)
        local bounce = math.max(0, math.sin(phase)) * 4
        local alpha = 160 + math.floor(math.max(0, math.sin(phase)) * 80)

        local dx = baseX + i * dotSpacing
        local dy = baseY - bounce

        nvgBeginPath(ctx)
        nvgCircle(ctx, dx, dy, dotR)
        nvgFillColor(ctx, Theme.rgba(Theme.RED, alpha))
        nvgFill(ctx)
    end
end

-- ============================================================================
-- 底部操作提示（暗色调呼吸闪烁）
-- ============================================================================

function drawBottomHint(ctx, w, h)
    local text
    if state.waitingForInput then
        return
    elseif state.statusHint and #state.statusHint > 0 then
        text = state.statusHint
    elseif state.aiThinking then
        text = "对手正在思考..."
    elseif state.isPlayerTurn then
        text = "你的回合"
    else
        text = "对手行动中..."
    end

    local alpha = math.floor(120 + 60 * math.sin(state.time * 2.5))
    nvgFontSize(ctx, 14)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(ctx, C.textSecondary(alpha))
    nvgText(ctx, w * 0.5, h - 8, text, nil)
end

-- ============================================================================
-- 出牌线（拖拽时显示 — 鎏金柔光线）
-- ============================================================================

function HUD.drawPlayLine(ctx, w, h, fontId, active)
    if not state.dragging then return end

    local lineY = h * 0.55

    local lineColor, lineAlpha
    if active then
        lineColor = Theme.GOLD
        lineAlpha = 200
    else
        lineColor = Theme.TEXT_DIM
        lineAlpha = 80
    end

    nvgBeginPath(ctx)
    nvgMoveTo(ctx, 0, lineY)
    nvgLineTo(ctx, w, lineY)
    nvgStrokeColor(ctx, Theme.rgba(lineColor, lineAlpha))
    nvgStrokeWidth(ctx, active and 2.5 or 1)
    nvgStroke(ctx)

    if active then
        nvgBeginPath(ctx)
        nvgRect(ctx, 0, lineY - 14, w, 28)
        local glow = nvgLinearGradient(ctx, 0, lineY - 14, 0, lineY + 14,
            Theme.rgba(Theme.GOLD, 0), Theme.rgba(Theme.GOLD, 40))
        nvgFillPaint(ctx, glow)
        nvgFill(ctx)
    end

    nvgFontFaceId(ctx, fontId)
    nvgFontSize(ctx, 16)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)

    if active then
        local pulse = math.floor(180 + 55 * math.sin(state.time * 5))
        nvgFillColor(ctx, Theme.rgba(Theme.GOLD_BRIGHT, pulse))
        nvgText(ctx, w * 0.5, lineY - 10, "松开出牌", nil)
    else
        nvgFillColor(ctx, C.textDim(130))
        nvgText(ctx, w * 0.5, lineY - 10, "拖到此处出牌", nil)
    end
end

-- ============================================================================
-- 充能线（拖拽时显示 — 信息蓝柔光线）
-- ============================================================================

function HUD.drawPitchLine(ctx, w, h, fontId, active)
    if not state.dragging then return end

    local lineY = h * 0.85

    local lineColor, lineAlpha
    if active then
        lineColor = Theme.BLUE
        lineAlpha = 200
    else
        lineColor = Theme.TEXT_DIM
        lineAlpha = 60
    end

    nvgBeginPath(ctx)
    nvgMoveTo(ctx, 0, lineY)
    nvgLineTo(ctx, w, lineY)
    nvgStrokeColor(ctx, Theme.rgba(lineColor, lineAlpha))
    nvgStrokeWidth(ctx, active and 2.5 or 1)
    nvgStroke(ctx)

    if active then
        nvgBeginPath(ctx)
        nvgRect(ctx, 0, lineY, w, h - lineY)
        local glow = nvgLinearGradient(ctx, 0, lineY, 0, h,
            Theme.rgba(Theme.BLUE, 40), Theme.rgba(Theme.BLUE, 0))
        nvgFillPaint(ctx, glow)
        nvgFill(ctx)
    end

    nvgFontFaceId(ctx, fontId)
    nvgFontSize(ctx, 14)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

    if active then
        local pulse = math.floor(180 + 55 * math.sin(state.time * 5))
        nvgFillColor(ctx, Theme.rgba(Theme.BLUE, pulse))
        nvgText(ctx, w * 0.5, lineY + 6, "松开充能", nil)
    else
        nvgFillColor(ctx, C.textDim(100))
        nvgText(ctx, w * 0.5, lineY + 6, "拖到此处充能", nil)
    end
end

-- ============================================================================
-- 战斗链信息（顶部居中 — 暗底金边胶囊）
-- ============================================================================

function HUD.drawChainInfo(ctx, w, h, fontId)
    if state.chainCount <= 0 then return end

    nvgFontFaceId(ctx, fontId)
    nvgFontSize(ctx, 15)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

    local textW = 160
    local cx, cy = w * 0.5, 10

    -- 暗底胶囊
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, cx - textW / 2, cy, textW, 30, 15)
    local bg = nvgLinearGradient(ctx, cx - textW / 2, cy, cx - textW / 2, cy + 30,
        nvgRGBA(40, 25, 20, 220), nvgRGBA(30, 18, 15, 200))
    nvgFillPaint(ctx, bg)
    nvgFill(ctx)

    -- 金边
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, cx - textW / 2, cy, textW, 30, 15)
    nvgStrokeColor(ctx, Theme.rgba(Theme.GOLD, 80))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)

    nvgFillColor(ctx, Theme.rgba(Theme.GOLD_BRIGHT, 240))
    nvgText(ctx, cx, cy + 8, "连招: " .. state.chainCount .. " 张", nil)
end

return HUD

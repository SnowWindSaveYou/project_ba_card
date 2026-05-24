-- ============================================================================
-- main.lua - 《血肉之战》电子版 入口
-- 3D 牌桌 + NanoVG 全矢量 UI + Balatro 风格卡牌动效
-- ============================================================================

-- 引擎工具
require "LuaScripts/Utilities/Sample"

-- 核心模块
local Tween        = require("Core.Tween")
local Timer        = require("Core.Timer")
local Easing       = require("Core.Easing")

-- 场景模块
local TableScene   = require("Scene.TableScene")
local CameraRig    = require("Scene.CameraRig")

-- 卡牌模块
local CardAnimator = require("Anim.CardAnimator")
local CardPicker   = require("Input.CardPicker")

-- 布局模块
local HandFan      = require("Layout.HandFan")
local ZoneLayout   = require("Layout.ZoneLayout")
local DeckStack    = require("Layout.DeckStack")

-- 反馈模块
local HitFlash     = require("Anim.HitFlash")
local Particles    = require("Anim.Particles")

-- UI 模块（NanoVG 全矢量 HUD）
local HUD          = require("UI.HUD")
local CardTooltip  = require("UI.CardTooltip")
local InputManager = require("Input.InputManager")
local ScorePopup   = require("UI.ScorePopup")
local PhaseBar     = require("UI.PhaseBar")
local CombatLog    = require("UI.CombatLog")
local ActionBar      = require("UI.ActionBar")
local DefensePanel   = require("UI.DefensePanel")
local HeroPanel3D    = require("UI.HeroPanel3D")
local GameOverScreen = require("UI.GameOverScreen")
local PhaseBanner    = require("UI.PhaseBanner")
local CombatCounter  = require("UI.CombatCounter")

-- 背景系统
local Background         = require("Scene.Background")

-- 游戏控制器
local GameController     = require("Controller.GameController")
local CardGlowManager    = require("Card.CardGlowManager")
local CardData           = require("Card.CardData")
local TurnPhase          = require("Game.TurnPhase")
local BattleResolution      = require("UI.BattleResolution")
local BattleGrid            = require("Scene.BattleGrid")
local CardTextRenderer      = require("Card.CardTextRenderer")
local CoinFlip              = require("UI.CoinFlip")
local ZoneWatermark         = require("UI.ZoneWatermark")

-- ============================================================================
-- 全局状态
-- ============================================================================
---@type Scene
local scene_       = nil
---@type NVGContextWrapper
local nvg_         = nil
local fontNormal_  = -1

local cameraRig_   = nil
local tableRoot_   = nil
local cardPicker_  = nil

-- 布局管理
local handFan_     = nil  -- HandFan 手牌扇面管理
local zoneLayout_  = nil  -- ZoneLayout 区域管理
local myDeckStack_ = nil  -- DeckStack 己方牌堆视觉
local oppDeckStack_ = nil -- DeckStack 对手牌堆视觉

-- 屏幕尺寸（每帧更新）
local screenW_     = 0
local screenH_     = 0
local dpr_         = 1.0
local nvgScale_    = 1.0   -- NanoVG DPR 缩放因子（物理→逻辑坐标转换）

-- 游戏时间
local gameTime_    = 0

-- 区域水印调试：剑当前是否在下区（true=玩家攻击）
local s_zoneSwapState_ = true

-- 对手手牌扇面（相机容器方案）
local oppHandFan_  = nil

-- 3D 英雄面板（相机空间 Quad）
---@type table|nil
local heroPanel3DPlayer_ = nil
---@type table|nil
local heroPanel3DOpp_ = nil

-- 战斗网格（常驻桌面）
---@type table
local battleGrid_  = nil

-- 游戏控制器
local gc_          = nil

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    SampleStart()
    graphics.windowTitle = "轻拳飞扬 - Light Punch"

    -- 1. 创建场景
    CreateScene()

    -- 2. 创建相机 + 视口
    SetupCamera()

    -- 3. 创建牌桌
    tableRoot_ = TableScene.create(scene_)
    -- 隐藏原始平面桌面（由 BattleGrid 方块替代）
    local tableSurface = tableRoot_:GetChild("TableSurface", false)
    if tableSurface then tableSurface.enabled = false end

    -- 3.5. 创建常驻 BattleGrid（替代牌桌表面）
    battleGrid_ = BattleGrid.create(scene_)
    BattleResolution.setGrid(battleGrid_)

    -- 4. 初始化 NanoVG（含卡牌文字渲染器）
    InitNanoVG()

    -- 4.2. 初始化背景系统（在 NanoVG 初始化之后）
    Background.init(scene_, nvg_, fontNormal_)

    -- 4.5. 区域水印（3D 节点，贴在桌面区域中心）
    -- 玩家先攻：swordInLower=false → 剑在 UPPER_POS(Z=-1)=玩家区
    ZoneWatermark.init(scene_, false)

    -- 5. 初始化布局系统
    InitLayouts()

    -- 6. 创建拾取器（拖拽模式）
    cardPicker_ = CardPicker.create(scene_, cameraRig_:getCamera())
    cardPicker_.onDragBegin  = OnDragBeginCard
    cardPicker_.onDragPlay   = OnDragPlayCard
    cardPicker_.onDragPitch  = OnDragPitchCard
    cardPicker_.onDragCancel = OnDragCancelCard

    -- 7. 创建 GameController 并启动对局
    gc_ = GameController.new({
        scene        = scene_,
        handFan      = handFan_,
        oppHandFan   = oppHandFan_,
        zoneLayout   = zoneLayout_,
        myDeckStack  = myDeckStack_,
        oppDeckStack = oppDeckStack_,
        cardPicker   = cardPicker_,
        cameraRig    = cameraRig_,
        playerHero   = "kaede",
        battleGrid   = battleGrid_,   -- 注入常驻网格，不再内部创建
    })
    -- 将 3D 英雄面板引用注入 GameController，HUDSync 通过 gc._heroPanels 访问
    gc_._heroPanels = { player = heroPanel3DPlayer_, opp = heroPanel3DOpp_ }
    gc_:startGame()

    -- 8. 订阅事件
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent(nvg_, "NanoVGRender", "HandleNanoVGRender")
    -- 注意：卡牌文字纹理由 HandleUpdate 中的 CardTextRenderer.renderDirty() 延迟烘焙（首帧后）

    -- 鼠标模式：绝对（需点击卡牌）
    SampleInitMouseMode(MM_ABSOLUTE)


end

function Stop()
    Background.destroy()
    Tween.clear()
    Timer.clear()
    ScorePopup.clear()
    CombatLog.clear()
    Particles.clear()
    if myDeckStack_ then myDeckStack_:destroy() end
    if oppDeckStack_ then oppDeckStack_:destroy() end
    if heroPanel3DPlayer_ then HeroPanel3D.destroy(heroPanel3DPlayer_) ; heroPanel3DPlayer_ = nil end
    if heroPanel3DOpp_    then HeroPanel3D.destroy(heroPanel3DOpp_)    ; heroPanel3DOpp_    = nil end
    CardTextRenderer.destroy()
    if nvg_ then
        nvgDelete(nvg_)
        nvg_ = nil
    end
end

-- ============================================================================
-- 场景初始化
-- ============================================================================

function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    -- LightGroup 预设光照（Daytime：平行光 + IBL + 半球 ambient）
    local lightGroupFile = cache:GetResource("XMLFile", "LightGroup/Daytime.xml")
    local lightGroup = scene_:CreateChild("LightGroup")
    lightGroup:LoadXML(lightGroupFile:GetRoot())

    -- 从 LightGroup 内部获取 Zone，仅调整雾效（不新建 Zone，避免覆盖 LightGroup 的 IBL/SH）
    local lgZone = lightGroup:GetComponent("Zone", true)
    if lgZone then
        lgZone.fogStart = 9000
        lgZone.fogEnd   = 10000
    end

    -- 天空盒
    local SkyUtils = require "urhox-libs.Rendering.SkyUtils"
    SkyUtils.CreateGradientSky(scene_, SkyUtils.Presets.Day)


end

function SetupCamera()
    cameraRig_ = CameraRig.create(scene_)

    local viewport = Viewport:new(scene_, cameraRig_:getCamera())
    renderer:SetViewport(0, viewport)
    renderer.hdrRendering = true


end

function InitNanoVG()
    nvg_ = nvgCreate(1)
    if nvg_ == nil then
        print("[main] ERROR: nvgCreate failed!")
        return
    end

    fontNormal_ = nvgCreateFont(nvg_, "sans", "Fonts/MiSans-Regular.ttf")
    if fontNormal_ == -1 then
        print("[main] ERROR: Font load failed!")
    end

    -- 初始化卡牌文字渲染器（复用主 context 做 render-to-texture）
    CardTextRenderer.init(nvg_)

    -- 初始化光效管理器（延迟生成粒子贴图，首帧后在 update 中完成）
    CardGlowManager.init(nvg_)
end

-- ============================================================================
-- 布局系统初始化
-- ============================================================================

function InitLayouts()
    -- 手牌扇面布局（相机容器方案，卡牌挂载在相机子节点）
    local camNode = cameraRig_:getCamera():GetNode()
    handFan_ = HandFan.create(camNode, scene_, {
        arcRadius = 8.0,
        maxArcDeg = 40,
    })
    -- 启用收起/展开功能，默认收起到右下角
    handFan_.isCollapseEnabled = true
    handFan_:setCollapsed(true, false)   -- 初始即为收起状态（不播动画）

    -- 牌桌区域布局
    zoneLayout_ = ZoneLayout.create()

    -- 己方牌堆视觉（数量由 GameController 设置）
    local deckDef = zoneLayout_:getZoneDef("myDeck")
    myDeckStack_ = DeckStack.create(scene_, deckDef.pos, 0, false)

    -- 对手牌堆视觉（数量由 GameController 设置）
    local oppDeckDef = zoneLayout_:getZoneDef("oppDeck")
    oppDeckStack_ = DeckStack.create(scene_, oppDeckDef.pos, 0, false)

    -- 对手手牌扇面（相机容器，屏幕顶部，卡背朝下）
    oppHandFan_ = HandFan.create(camNode, scene_, {
        containerLocalPos = Vector3(-1.6, 1.1, 3.0),
        cardPitchDeg = 75,
        extraRotation = Quaternion(180, Vector3.UP),
        arcRadius = 6.0,
        maxArcDeg = 25,
        maxSpacing = 0.35,
        minSpacing = 0.12,
        maxTotalW = 2.0,
        hoverSpread = 0,
        hoverLift = 0,
        cardScale = 0.7,
    })

    -- 3D 英雄面板（相机空间 Quad，挂在相机节点）
    -- heroKey/class 在 HUDSync 第一次同步时通过 HeroPanel3D.setHero() 更新
    heroPanel3DPlayer_ = HeroPanel3D.create(camNode, true,  "kaede",    "warrior",  { r=82,  g=200, b=160 })
    heroPanel3DOpp_    = HeroPanel3D.create(camNode, false, "xia_lin",  "ninja",    { r=255, g=107, b=107 })
end



-- ============================================================================
-- 每帧更新
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    gameTime_ = gameTime_ + dt

    -- 更新屏幕尺寸
    screenW_ = graphics:GetWidth()
    screenH_ = graphics:GetHeight()
    dpr_ = graphics:GetDPR()

    -- 更新核心系统
    Background.update(dt)
    Tween.update(dt)
    Timer.update(dt)

    -- 更新相机呼吸感
    if cameraRig_ then
        cameraRig_:update(dt)
    end

    -- 逻辑坐标（NanoVG 空间）
    local nvgW = screenW_ / nvgScale_
    local nvgH = screenH_ / nvgScale_
    local mx   = input.mousePosition.x / nvgScale_
    local my   = input.mousePosition.y / nvgScale_
    local mousePressed = input:GetMouseButtonPress(MOUSEB_LEFT)

    -- -----------------------------------------------------------------------
    -- 步骤0：先手动画点击跳过（最优先，全屏拦截）
    -- -----------------------------------------------------------------------
    if CoinFlip.isActive() and mousePressed then
        CoinFlip.onMousePress()
    end

    -- -----------------------------------------------------------------------
    -- 步骤1：UI 组件输入处理（内部自行 consumeMouse，顺序 = Z 轴从上到下）
    -- 必须在 cardPicker 之前运行，否则消费信号来不及拦截本帧的 hover
    -- -----------------------------------------------------------------------
    InputManager.beginFrame(nvgScale_)
    GameOverScreen.update(mx, my, nvgW, nvgH, mousePressed, dt)   -- 最高层：全屏遮挡
    ActionBar.update(mx, my, nvgW, nvgH, mousePressed, dt)         -- 底部操作栏
    DefensePanel.update(mx, my, nvgW, nvgH)                        -- 居中攻防面板

    -- HUD 英雄/武器/护具交互区域（会自行 consumeMouse）
    local hudResult = gc_ and HUD.update(mx, my, nvgW, nvgH, dt, mousePressed) or nil

    -- -----------------------------------------------------------------------
    -- 手牌扇面收起/展开：点击扇面区域展开，点击扇面外区域收起
    -- 拖拽中不切换状态
    -- -----------------------------------------------------------------------
    if handFan_ and handFan_.isCollapseEnabled and mousePressed
        and not InputManager.isMouseConsumed() then
        local isDraggingCard = cardPicker_ and (
            cardPicker_:getState() == "DRAGGING" or
            cardPicker_:getState() == "DRAG_PENDING")
        if not isDraggingCard then
            local cam = cameraRig_:getCamera()
            local fx, fy, fw, fh = handFan_:getScreenBounds(cam, nvgW, nvgH)
            local inFan = mx >= fx and mx <= fx + fw and my >= fy and my <= fy + fh
            if inFan then
                -- 点击扇面内：展开
                if handFan_.collapsed then
                    handFan_:setCollapsed(false)
                    InputManager.consumeMouse()
                end
            else
                -- 点击扇面外：收起（英雄区/ActionBar已消费的不再触发）
                if not handFan_.collapsed then
                    handFan_:setCollapsed(true)
                end
            end
        end
    end

    -- -----------------------------------------------------------------------
    -- 步骤2：3D 卡牌拾取（UI 未消费时才运行）
    -- -----------------------------------------------------------------------
    if cardPicker_ then
        if InputManager.isMouseConsumed() then
            -- UI 占用了鼠标：清除残留 hover，卡牌不响应
            cardPicker_:clearHover()
            handFan_:setHoveredIndex(0)
            -- HUD 区域有悬停/长按时显示对应卡牌的 Tooltip
            if hudResult and (hudResult.hovered or hudResult.longPressed) then
                local zone = hudResult.longPressed or hudResult.hovered
                local cardData = nil
                if zone == HUD.ZONE.HERO then
                    -- 英雄头像：暂无独立卡牌，跳过
                elseif zone == HUD.ZONE.WEAPON then
                    cardData = gc_:getWeaponCard()
                elseif zone == HUD.ZONE.ARMOR_UPPER then
                    cardData = gc_:getArmorCard(CardData.SLOT.UPPER)
                elseif zone == HUD.ZONE.ARMOR_LOWER then
                    cardData = gc_:getArmorCard(CardData.SLOT.LOWER)
                end
                if cardData then
                    CardTooltip.show(cardData, mx, my)
                else
                    CardTooltip.hide()
                end
            else
                CardTooltip.hide()
            end
        else
            cardPicker_:update(screenW_, screenH_)

            -- 同步悬停状态到 HandFan + Tooltip
            local hoveredCard = cardPicker_.hoveredCard
            local isDragging  = cardPicker_:getState() == "DRAGGING" or
                                cardPicker_:getState() == "DRAG_PENDING"

            if hoveredCard then
                local idx = handFan_:indexOf(hoveredCard)
                handFan_:setHoveredIndex(idx)
                if not isDragging then
                    CardTooltip.show(hoveredCard.data, mx, my)
                else
                    CardTooltip.hide()
                end
            else
                handFan_:setHoveredIndex(0)
                CardTooltip.hide()
            end
        end
    end

    -- HUD 点击激活（武器/护具）—— 仅行动阶段有效
    if hudResult and hudResult.clicked and gc_ and gc_:isWaitingForInput()
        and gc_:getInputPhase() == TurnPhase.ACTION_PHASE then
        local zone = hudResult.clicked
        if zone == HUD.ZONE.WEAPON then
            gc_:submitPlayerAction({ type = "weapon", weaponIndex = 1 })
        elseif zone == HUD.ZONE.ARMOR_UPPER then
            gc_:submitPlayerAction({ type = "armor_ability", slot = CardData.SLOT.UPPER })
        elseif zone == HUD.ZONE.ARMOR_LOWER then
            gc_:submitPlayerAction({ type = "armor_ability", slot = CardData.SLOT.LOWER })
        end
    end

    -- [调试] Y 键手动触发区域水印互换
    if input:GetKeyPress(KEY_Y) then
        if not ZoneWatermark.isActive() then
            -- 切换攻守：剑在下区 ↔ 剑在上区
            local nextSwordInLower = not s_zoneSwapState_
            s_zoneSwapState_ = nextSwordInLower
            ZoneWatermark.swap(nextSwordInLower)
        end
    end

    -- [调试] B 键手动触发战斗结算动画
    if input:GetKeyPress(KEY_B) then
        if BattleResolution.isActive() then
            BattleResolution.skip()
        else
            local p1life = gc_ and gc_.fsm and gc_.fsm.players[1] and gc_.fsm.players[1].life or 32
            local p2life = gc_ and gc_.fsm and gc_.fsm.players[2] and gc_.fsm.players[2].life or 26
            BattleResolution.trigger({
                playerWon   = true,
                playerScore = p1life,
                oppScore    = p2life,
                damage      = 4,
            })
        end
    end

    -- 更新反馈效果
    HitFlash.update(dt)
    Particles.update(dt)

    -- 更新 UI 动画子系统（纯动画，无输入，顺序无关）
    CardTooltip.update(dt)
    ScorePopup.update(dt)
    PhaseBar.update(dt)
    CombatLog.update(dt)
    PhaseBanner.update(dt)
    CombatCounter.update(dt)
    ZoneWatermark.update(dt)

    -- 更新 GameController（人/AI 分流 + HUD 同步）
    if gc_ then
        gc_._nvgScale = nvgScale_
        gc_:update(dt)
    end

    -- 每帧将 3D 英雄面板投影到 NanoVG 坐标，注入 HUD
    local nvgW2 = screenW_ / nvgScale_
    local nvgH2 = screenH_ / nvgScale_
    if heroPanel3DPlayer_ and heroPanel3DOpp_ and cameraRig_ then
        local cam = cameraRig_:getCamera()
        HeroPanel3D.calcScreenRect(heroPanel3DPlayer_, cam, nvgW2, nvgH2)
        HeroPanel3D.calcScreenRect(heroPanel3DOpp_,    cam, nvgW2, nvgH2)
        HUD.setHeroPanelRects(heroPanel3DPlayer_, heroPanel3DOpp_)
    end

    -- 同步拖拽状态到 HUD（视觉反馈，与 GameController 的 HUD 同步互补）
    local isDragging = cardPicker_ and cardPicker_.state == "DRAGGING"
    HUD.updateState({
        dragging       = isDragging or false,
        abovePlayLine  = isDragging and cardPicker_:isAbovePlayLine(screenH_) or false,
        belowPitchLine = isDragging and cardPicker_:isBelowPitchLine(screenH_) or false,
    })

    -- 将脏卡牌的文字烘焙到 Texture2D（必须在帧循环中，不能在 Start() 里调用）
    CardTextRenderer.renderDirty()

    -- 驱动可打出卡牌的光晕脉冲动画（同时完成粒子贴图的延迟初始化）
    CardGlowManager.update(dt)
end

--- 拖拽开始回调（将卡牌从相机容器脱离到场景根）
function OnDragBeginCard(card)
    if not card then return end
    -- 拖拽开始时自动展开手牌（让玩家看到完整手牌布局）
    if handFan_ and handFan_.collapsed then
        handFan_:setCollapsed(false)
    end
    handFan_:detachForDrag(card)
end

--- 拖拽出牌回调（卡牌拖到出牌线上方释放）
--- 由 GameController 处理真实出牌
function OnDragPlayCard(card)
    if not card then return end

    -- 必须在等待玩家输入状态才能出牌
    if not gc_ or not gc_:isWaitingForInput() then
        OnDragCancelCard(card)
        return
    end

    -- 尝试提交拖拽出牌
    local ok = gc_:submitDragPlay(card)
    if not ok then
        -- 出牌失败，回弹
        OnDragCancelCard(card)
    end
    -- 成功时卡牌由 FSM 回调（onCardPlayed）处理移除和动画
end

--- 拖拽充能回调（卡牌拖到屏幕底部充能线下方释放）
--- 将手牌 Pitch 为体能资源
function OnDragPitchCard(card)
    if not card then return end

    -- 必须在等待玩家输入状态才能充能
    if not gc_ or not gc_:isWaitingForInput() then
        OnDragCancelCard(card)
        return
    end

    -- 尝试提交充能
    local ok = gc_:submitDragPitch(card)
    if not ok then
        -- 充能失败，回弹
        OnDragCancelCard(card)
    end
    -- 成功时卡牌由 _syncRemovedCards 处理移除
end

--- 拖拽取消回调（卡牌拖回出牌线下方释放）
function OnDragCancelCard(card)
    if not card then return end

    -- 先回挂到相机容器（保持当前世界位置）
    handFan_:reattachAfterDrag(card)

    -- 获取该卡牌在手牌中的布局槽位（容器局部坐标）
    local slot = handFan_:getSlotForCard(card)
    if slot then
        -- snapBack 操作 node.position（现在是容器局部坐标）
        CardAnimator.snapBack(card, slot.pos, slot.rot)
    else
        card.dragging = false
        card.animState = "idle"
    end

end



-- ============================================================================
-- NanoVG 渲染（全矢量 HUD）
-- ============================================================================

---@param eventType string
---@param eventData table
function HandleNanoVGRender(eventType, eventData)
    if nvg_ == nil or fontNormal_ == -1 then return end

    if screenW_ == 0 or screenH_ == 0 then return end

    -- DPR_DENSITY_ADAPTIVE 缩放策略
    local dpr = dpr_
    local shortSide = math.min(screenW_, screenH_) / dpr
    local densityFactor = math.sqrt(shortSide / 720)
    densityFactor = math.max(0.625, math.min(densityFactor, 1.0))
    nvgScale_ = dpr * densityFactor
    local w = screenW_ / nvgScale_
    local h = screenH_ / nvgScale_

    -- 背景层渲染（写入各 RT，完成后自动恢复 nil target）
    Background.render()

    nvgBeginFrame(nvg_, w, h, nvgScale_)

    local ctx = nvg_

    -- 0.5 区域水印（剑/盾，半透明覆盖在 3D 桌面对应区域）
    ZoneWatermark.setScreenParams(screenW_, screenH_, nvgScale_)
    ZoneWatermark.draw(ctx, w, h)

    -- 1. 主 HUD（标题栏、玩家/对手面板、底部操作栏）
    HUD.draw(ctx, w, h, fontNormal_, gameTime_)

    -- 2. 出牌线（拖拽时显示）
    -- isAbovePlayLine 使用物理像素比例，不受 NanoVG 缩放影响
    local aboveLine = cardPicker_ and cardPicker_.state == "DRAGGING"
        and cardPicker_:isAbovePlayLine(screenH_) or false
    HUD.drawPlayLine(ctx, w, h, fontNormal_, aboveLine)

    -- 2.5 充能线（拖拽时显示，屏幕底部）
    local belowPitch = cardPicker_ and cardPicker_.state == "DRAGGING"
        and cardPicker_:isBelowPitchLine(screenH_) or false
    HUD.drawPitchLine(ctx, w, h, fontNormal_, belowPitch)

    -- 3. 战斗链信息（居中偏上）
    HUD.drawChainInfo(ctx, w, h, fontNormal_)

    -- 4. 卡牌悬停详情（跟随鼠标）
    CardTooltip.draw(ctx, w, h, fontNormal_)

    -- 5. 数字弹出（伤害/防御/回复）
    ScorePopup.draw(ctx, fontNormal_)

    -- 6. 战斗日志（右下角）
    CombatLog.draw(ctx, w, h, fontNormal_)

    -- 7. 防御面板（攻防信息）
    DefensePanel.draw(ctx, w, h, fontNormal_, gameTime_)

    -- 7.5 战斗计数器（场地中央 †攻击力 / 攻vs防）
    CombatCounter.draw(ctx, w, h, fontNormal_)

    -- 8. 操作栏（底部居中）
    ActionBar.draw(ctx, w, h, fontNormal_)

    -- 8.5 粒子特效（攻击火花、防御碎片等）
    Particles.draw(ctx)

    -- 8.6 阶段切换横幅（居中扫入，覆盖大部分 UI）
    PhaseBanner.draw(ctx, w, h, fontNormal_, gameTime_)

    -- 9. 打击闪烁效果（伤害/格挡反馈）
    HitFlash.draw(ctx, w, h)

    -- 9.5 战斗结算全屏动画（金色横扫 → 分数对冲 → 攻击射线）
    BattleResolution.draw(ctx, w, h, fontNormal_, gameTime_)

    -- 10. 游戏结束画面（全屏覆盖）
    GameOverScreen.draw(ctx, w, h, fontNormal_, gameTime_)

    -- 11. 先手抽取动画（最顶层，开局全屏覆盖）
    CoinFlip.draw(ctx, w, h, fontNormal_, gameTime_)

    -- 11. 调试信息（左下角）
    nvgFontFaceId(ctx, fontNormal_)
    nvgFontSize(ctx, 10)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
    nvgFillColor(ctx, nvgRGBA(120, 120, 120, 100))
    nvgText(ctx, 6, h - 54, "Tweens: " .. Tween.count() .. "  Time: " .. string.format("%.1f", gameTime_), nil)

    nvgEndFrame(nvg_)
end

-- ============================================================================


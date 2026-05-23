-- ============================================================================
-- UI/HeroPanel3D.lua — 相机空间 3D 英雄面板（Blue Archive 风格，卡牌布局）
--
-- 布局（挂在相机子节点，局部坐标 = 屏幕固定位置）：
--   玩家面板  — 相机正前方底部偏左，略微前倾朝向相机
--   对手面板  — 相机正前方顶部偏左，略微前倾朝向相机
--
-- 卡牌组成（每个面板，从左到右）：
--   武器卡    — 较小，左侧区域，含武器图 + 卡框 + 攻击/费用 badge
--   英雄卡    — 主体，中间区域，含英雄插画 + 卡框 + 底部渐变 + HP badge（右上）
--   装备卡上  — 较小，右侧上层（上衣）含装甲图 + 卡框 + 状态钻石
--   装备卡下  — 较小，右侧下层（下衣）含装甲图 + 卡框 + 状态钻石
--
-- NanoVG 叠加层：HP 数字、武器攻/费数字、装备耐久钻石颜色
-- （由 HUD.lua 的 drawHeroPanelOverlay / drawOpponentPanelOverlay 负责）
-- ============================================================================

local Theme = require("UI.Theme")

local HeroPanel3D = {}

-- ============================================================================
-- 面板元素尺寸（世界空间米）
-- ============================================================================

-- 英雄卡（标准卡比例 63×88mm 缩放到合适尺寸）
-- FOV=50, Z=3 时屏幕可视半高≈1.40m；英雄卡占屏幕高约 20%
local HERO_W  = 0.40
local HERO_H  = 0.56

-- 小卡（武器/装备，约 68% 英雄卡大小）
local SMALL_W = 0.27
local SMALL_H = 0.38

-- 三卡之间的水平间隙
local CARD_GAP = 0.015

-- 装备卡叠放偏移（两张卡错开显示）
local EQUIP_STACK_DX = 0.035  -- 右上卡比左下卡向右偏
local EQUIP_STACK_DZ = 0.055  -- 右上卡比左下卡向上偏（局部 Z）

-- 面板整体在相机局部空间的位置
local DIST  = 3.0

-- Y 层偏移（避免深度冲突，参考 Card3D）
local LAYER = {
    back     = -0.001,
    art      =  0.001,
    border   =  0.002,
    gradient =  0.003,
    badge    =  0.004,
}

-- 渲染优先级：普通场景 < 面板背景 < 面板内容 < 拖拽卡牌(200+)
local RO_BASE  = 120   -- 卡背底板
local RO_ART   = 121   -- 插画层
local RO_FRAME = 122   -- 卡框
local RO_GRAD  = 123   -- 底部渐变
local RO_BADGE = 124   -- badge

-- 纹理路径
local TEX_BORDER        = "image/card_border_mask.png"
local TEX_WEAPON        = "image/ba_card_weapon_shield_20260523161156.png"
local TEX_EQUIP_UP      = "image/ba_card_top_clothing_20260523161253.png"
local TEX_EQUIP_LO      = "image/ba_card_bottom_clothing_20260523161144.png"
local TEX_BADGE_COST    = "image/badge_cost.png"
local TEX_BADGE_ATTACK  = "image/badge_attack.png"
local TEX_BADGE_DEFENSE = "image/badge_defense.png"

-- 英雄插画映射（与 Card3D.ART_MAP 保持一致）
local HERO_ART = {
    kaede    = "image/hero_kaede_v6_20260523021216.png",
    xia_lin  = "image/hero_xia_lin_v4_20260522195334.png",
    yun_rou  = "image/hero_yun_rou_v8a_20260523022637.png",
    xiao_tao = "image/hero_xiao_tao_v4_20260522194257.png",
}
local CLASS_ART = {
    warrior  = "image/ba_placeholder_1_20260522181341.png",
    ninja    = "image/ba_placeholder_3_20260522181340.png",
    guardian = "image/ba_placeholder_4_20260522181427.png",
    brute    = "image/ba_placeholder_2_20260522181936.png",
}

local function getHeroArt(heroKey, class)
    return HERO_ART[heroKey] or CLASS_ART[class] or "image/ba_placeholder_1_20260522181341.png"
end

-- ============================================================================
-- 材质工厂
-- ============================================================================
local solidCache_ = {}
local texCache_   = {}

local function makeSolid(r, g, b, a)
    local key = r..","..g..","..b..","..a
    if solidCache_[key] then return solidCache_[key]:Clone("") end
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(r/255, g/255, b/255, a/255)))
    mat:SetShaderParameter("Metallic",  Variant(0.0))
    mat:SetShaderParameter("Roughness", Variant(1.0))
    solidCache_[key] = mat
    return mat:Clone("")
end

local function makeTextured(texPath)
    if not texPath then return nil end
    if texCache_[texPath] then return texCache_[texPath]:Clone("") end
    local tex = cache:GetResource("Texture2D", texPath)
    if not tex then return nil end
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffAlpha.xml"))
    mat:SetTexture(TU_DIFFUSE, tex)
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1,1,1,1)))
    texCache_[texPath] = mat
    return mat:Clone("")
end

-- ============================================================================
-- Plane Quad 辅助
-- (Plane.mdl 在 XZ 平面展开，Y 向上，scaleX/scaleZ 控制宽高)
-- ============================================================================
local function makeQuad(parent, name, lx, ly, lz, sw, sh, mat, ro)
    if not mat then return nil end
    local node = parent:CreateChild(name)
    node.position = Vector3(lx, ly, lz)
    node.scale    = Vector3(sw, 1.0, sh)
    local sm = node:CreateComponent("StaticModel")
    sm:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
    sm:SetMaterial(mat)
    sm.renderOrder = ro
    sm.castShadows = false
    return node
end

-- ============================================================================
-- badge 辅助：在卡角创建贴图角标 Quad
--   parent  — 父节点
--   prefix  — 命名前缀
--   cx, cz  — 卡面中心
--   bx, bz  — badge 中心相对卡中心的偏移 (已含卡位移)
--   size    — badge 正方形边长（米）
--   texPath — 角标纹理路径
-- ============================================================================
local function buildBadge(parent, prefix, bxWorld, bzWorld, size, texPath)
    local mat = makeTextured(texPath)
    if not mat then return nil end
    return makeQuad(parent, prefix, bxWorld, LAYER.badge, bzWorld, size, size, mat, RO_BADGE)
end

-- ============================================================================
-- 构建单张「卡牌」子结构（复用于英雄卡、武器卡、装备卡）
--   parent     — 父节点（panel.container）
--   prefix     — 节点命名前缀（"hero"/"weapon"/"equipUp"/"equipLo"）
--   cx, cz     — 卡面中心在容器局部坐标 (X, Z)，Y 由层级决定
--   cw, ch     — 卡宽、卡高（世界空间米）
--   artTex     — 插画纹理路径（nil → 白色底板占位）
--   accentRGB  — 卡框/底部强调色 {r,g,b}
--   badges     — badge 配置列表，每项 { pos="cost"|"attack"|"defense", tex=texPath }
--                pos 枚举对应卡角：
--                  "cost"    → 左上角
--                  "attack"  → 左下角
--                  "defense" → 右下角
-- 返回值：
--   nodes.art       — 插画节点（供 setHero 替换贴图）
--   nodes.badgeNodes — badge 节点列表（按 badges 顺序）
-- ============================================================================
local function buildCard(parent, prefix, cx, cz, cw, ch, artTex, accentRGB, badges)
    local ac = accentRGB or Theme.GREEN

    -- 1. 卡背底板（白色不透明，略带蓝灰）
    local bgNode = makeQuad(parent, prefix.."_bg",
        cx, LAYER.back, cz, cw, ch, makeSolid(248, 250, 255, 245), RO_BASE)

    -- 2. 插画层
    local artMat = makeTextured(artTex) or makeSolid(210, 220, 240, 200)
    local artNode = makeQuad(parent, prefix.."_art",
        cx, LAYER.art, cz, cw * 0.92, ch * 0.92, artMat, RO_ART)

    -- 3. 卡框（card_border_mask.png，全尺寸覆盖）
    makeQuad(parent, prefix.."_frame",
        cx, LAYER.border, cz, cw, ch, makeTextured(TEX_BORDER), RO_FRAME)

    -- 4. 顶边强调色细条
    makeQuad(parent, prefix.."_bar",
        cx, LAYER.badge, cz - ch * 0.47, cw, ch * 0.03,
        makeSolid(ac.r, ac.g, ac.b, 200), RO_BADGE)

    -- 5. 四角 badge（3D 贴图角标，参考 Card3D 布局）
    --    左上  (cost)    x=-0.36w  z=+0.38h
    --    左下  (attack)  x=-0.36w  z=-0.38h
    --    右下  (defense) x=+0.36w  z=-0.38h
    local BADGE_SIZE = cw * 0.22
    local badgePosMap = {
        cost    = { ox = -cw * 0.36, oz =  ch * 0.38 },
        attack  = { ox = -cw * 0.36, oz = -ch * 0.38 },
        defense = { ox =  cw * 0.36, oz = -ch * 0.38 },
    }
    local badgeNodes = {}
    if badges then
        for _, bCfg in ipairs(badges) do
            local p = badgePosMap[bCfg.pos]
            if p then
                local bn = buildBadge(parent,
                    prefix.."_badge_"..bCfg.pos,
                    cx + p.ox, cz + p.oz,
                    BADGE_SIZE, bCfg.tex)
                table.insert(badgeNodes, bn)
            end
        end
    end

    return {
        bg         = bgNode,
        art        = artNode,
        badgeNodes = badgeNodes,
    }
end

-- ============================================================================
-- HeroPanel3D.create
-- @param camNode   Node  相机节点
-- @param isPlayer  bool  true=玩家(底部左侧), false=对手(顶部左侧)
-- @param heroKey   string 如 "kaede"
-- @param class     string 如 "warrior"
-- @param accentRGB table  {r,g,b} 面板主题色
-- ============================================================================
function HeroPanel3D.create(camNode, isPlayer, heroKey, class, accentRGB)
    local panel = {}
    local ac = accentRGB or (isPlayer and Theme.GREEN or Theme.RED)

    -- ------------------------------------------------------------------
    -- 容器节点（挂在相机局部空间）
    -- ------------------------------------------------------------------
    local container = camNode:CreateChild(isPlayer and "HeroPanelPlayer" or "HeroPanelOpp")

    -- 整体位置：玩家区居中下，对手区居中上
    -- X=0 水平居中（相机局部坐标，X=0 正对屏幕中央）
    -- 可视 Y 范围约 ±1.40m（FOV=50, Z=3.0）
    -- 玩家 Y=-1.00：低于手牌展开中心(Y=-0.9)
    -- 对手 Y=+1.10：靠近屏幕上沿（距顶边约 0.30m）
    local offsetX = 0.0
    local offsetY = isPlayer and -1.00 or 1.10
    container.position = Vector3(offsetX, offsetY, DIST)

    -- 朝向相机：与 HandFan 卡牌一致，绕 X 轴前倾 -75°
    -- 玩家区稍微多倾（-78），对手区略少（-72）
    local pitchDeg = isPlayer and -78 or -72
    container.rotation = Quaternion(pitchDeg, Vector3.RIGHT)

    -- ------------------------------------------------------------------
    -- 三卡布局（以容器原点 X=0 为英雄卡中心，对称展开）
    --   weapCX         heroCX=0         equipBaseCX
    --   [武器卡]  gap  [英雄卡]  gap  [装备卡(叠放)]
    -- ------------------------------------------------------------------
    local heroCX      = 0.0
    local weapCX      = -(HERO_W * 0.5 + CARD_GAP + SMALL_W * 0.5)
    local equipBaseCX =   HERO_W * 0.5 + CARD_GAP + SMALL_W * 0.5

    -- 武器卡稍微下移（局部 Z+），装备区稍微上移（Z-），形成视觉层次
    local weapCZ      =  HERO_H * 0.06
    local equipBaseCZ = -HERO_H * 0.04

    local heroArt = getHeroArt(heroKey, class)
    -- 英雄卡：右下角 defense badge（显示 HP）
    panel.heroCard = buildCard(container, "hero",
        heroCX, 0, HERO_W, HERO_H, heroArt, ac,
        { { pos = "defense", tex = TEX_BADGE_DEFENSE } })

    -- 武器卡：左上角 cost badge + 左下角 attack badge
    panel.weaponCard = buildCard(container, "weapon",
        weapCX, weapCZ, SMALL_W, SMALL_H, TEX_WEAPON, ac,
        { { pos = "cost",   tex = TEX_BADGE_COST   },
          { pos = "attack", tex = TEX_BADGE_ATTACK } })

    -- ------------------------------------------------------------------
    -- 装备卡（英雄卡右侧，两张叠放）
    -- 下衣卡先渲染（renderOrder 低），上衣卡覆盖在上
    -- ------------------------------------------------------------------

    -- 下衣卡（右下偏移）：右下角 defense badge（显示耐久）
    panel.equipLoCard = buildCard(container, "equipLo",
        equipBaseCX + EQUIP_STACK_DX, equipBaseCZ - EQUIP_STACK_DZ,
        SMALL_W, SMALL_H, TEX_EQUIP_LO, ac,
        { { pos = "defense", tex = TEX_BADGE_DEFENSE } })

    -- 上衣卡（左上偏移，覆盖下衣卡）：右下角 defense badge（显示耐久）
    panel.equipUpCard = buildCard(container, "equipUp",
        equipBaseCX - EQUIP_STACK_DX * 0.5, equipBaseCZ + EQUIP_STACK_DZ,
        SMALL_W, SMALL_H, TEX_EQUIP_UP, ac,
        { { pos = "defense", tex = TEX_BADGE_DEFENSE } })

    -- ------------------------------------------------------------------
    -- 元数据（供 NanoVG 投影计算用）
    -- ------------------------------------------------------------------
    panel.container = container
    panel.isPlayer  = isPlayer
    panel.heroKey   = heroKey
    panel.class     = class
    panel.accentRGB = ac

    -- 屏幕投影缓存（每帧由 calcScreenRect 更新）
    -- 英雄卡区域
    panel.heroRect  = { x=0, y=0, w=0, h=0 }
    -- 武器卡区域
    panel.weapRect  = { x=0, y=0, w=0, h=0 }
    -- 装备上卡区域
    panel.equipUpRect = { x=0, y=0, w=0, h=0 }
    -- 装备下卡区域
    panel.equipLoRect = { x=0, y=0, w=0, h=0 }

    return panel
end

-- ============================================================================
-- 内部：将容器局部坐标 (lx, 0, lz) 投影到屏幕 NanoVG 坐标
-- ============================================================================
local function projectLocalPos(panel, camera, vpW, vpH, lx, lz)
    local node = panel.container
    -- 容器局部 → 世界
    local localPt = Vector3(lx, 0, lz)
    local worldPt = node:LocalToWorld(localPt)

    local camNode = camera:GetNode()
    local toP  = worldPt - camNode:GetWorldPosition()
    local depth = toP:DotProduct(camNode:GetWorldDirection())
    if depth <= 0 then return -9999, -9999, 0 end

    local sp = camera:WorldToScreenPoint(worldPt)
    return sp.x * vpW, sp.y * vpH, depth
end

local function depthToPixels(camera, vpH, cardH, depth)
    return cardH * vpH / (2 * depth * math.tan(math.rad(camera.fov * 0.5)))
end

-- ============================================================================
-- HeroPanel3D.calcScreenRect
-- 更新各子卡的屏幕投影矩形（每帧在 NanoVGRender 前调用）
-- @param panel     table   HeroPanel3D 实例
-- @param camera    Camera  场景相机组件
-- @param vpW, vpH  number  NanoVG 视口逻辑像素宽高（物理/DPR）
-- ============================================================================
function HeroPanel3D.calcScreenRect(panel, camera, vpW, vpH)
    local function fillRect(rect, cx, cz, cw, ch)
        local sx, sy, depth = projectLocalPos(panel, camera, vpW, vpH, cx, cz)
        if depth <= 0 then
            rect.x, rect.y, rect.w, rect.h = -9999, -9999, 0, 0
            return
        end
        local fovFactor = vpH / (2 * depth * math.tan(math.rad(camera.fov * 0.5)))
        local pw = cw * fovFactor
        local ph = ch * fovFactor
        rect.x = sx - pw * 0.5
        rect.y = sy - ph * 0.5
        rect.w = pw
        rect.h = ph
    end

    local heroCX      = 0.0
    local weapCX      = -(HERO_W * 0.5 + CARD_GAP + SMALL_W * 0.5)
    local weapCZ      =  HERO_H * 0.06
    local equipBaseCX =   HERO_W * 0.5 + CARD_GAP + SMALL_W * 0.5
    local equipBaseCZ = -HERO_H * 0.04

    fillRect(panel.heroRect,
        heroCX, 0, HERO_W, HERO_H)
    fillRect(panel.weapRect,
        weapCX, weapCZ, SMALL_W, SMALL_H)
    fillRect(panel.equipUpRect,
        equipBaseCX - EQUIP_STACK_DX * 0.5, equipBaseCZ + EQUIP_STACK_DZ,
        SMALL_W, SMALL_H)
    fillRect(panel.equipLoRect,
        equipBaseCX + EQUIP_STACK_DX, equipBaseCZ - EQUIP_STACK_DZ,
        SMALL_W, SMALL_H)

    -- 兼容旧字段（HUD 可能仍用 screenX/Y/W/H）
    panel.screenX = panel.heroRect.x
    panel.screenY = panel.heroRect.y
    panel.screenW = panel.heroRect.w
    panel.screenH = panel.heroRect.h
end

-- ============================================================================
-- HeroPanel3D.setHero
-- 动态替换英雄插画 + 主题色
-- ============================================================================
function HeroPanel3D.setHero(panel, heroKey, class, accentRGB)
    if not panel or not panel.container then return end
    panel.heroKey   = heroKey
    panel.class     = class
    if accentRGB then panel.accentRGB = accentRGB end

    if panel.heroCard and panel.heroCard.art then
        local artPath = getHeroArt(heroKey, class)
        local mat = makeTextured(artPath)
        if mat then
            local sm = panel.heroCard.art:GetComponent("StaticModel")
            if sm then sm:SetMaterial(mat) end
        end
    end
end

-- ============================================================================
-- HeroPanel3D.destroy
-- ============================================================================
function HeroPanel3D.destroy(panel)
    if panel and panel.container then
        panel.container:Remove()
        panel.container = nil
    end
end

-- ============================================================================
-- 暴露布局常量（供 HUD.lua 计算 NanoVG 叠加位置用）
-- ============================================================================
HeroPanel3D.HERO_W  = HERO_W
HeroPanel3D.HERO_H  = HERO_H
HeroPanel3D.SMALL_W = SMALL_W
HeroPanel3D.SMALL_H = SMALL_H

return HeroPanel3D

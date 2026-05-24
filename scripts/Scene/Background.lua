-- ============================================================================
-- Scene/Background.lua - 分层动态背景系统
--
-- 相机：(0,9,-2.8) 俯视约70°，几乎垂直向下
-- 视野主要是"地面俯视"，只有屏幕最上方一小条是"远景/天空"
--
-- 层次结构（所有背景层必须 Y < -0.03，即卡桌以下）：
--   竖向面片(Z=+16)  远景城市 + 圆环（出现在屏幕上方的"远处地平线"区域）
--   Y=-0.5  地面近景：城市轮廓水平贴图（卡桌外围可见）
--   Y=-1.5  中景：Metaball 云（卡桌外延可见）
--   Y=-4    远景：大圆环 + 半调网格（卡桌外更大范围）
--   Y=-10   底图：纯蓝渐变超大地面
--  ──────── 卡桌 Y=-0.03 ────────
--   Y=-0.1  卡桌两侧装饰（X=±8，横向偏出卡桌范围之外）
-- ============================================================================

local Background = {}

-- ============================================================================
-- 配置
-- ============================================================================

-- 卡牌参考尺寸（世界单位）
-- CARD_W=0.63, CARD_H=0.88  →  3张牌高≈2.64
local CARD_W, CARD_H = 0.63, 0.88

-- 各层 Quad 尺寸（世界单位）+ alpha 整体透明度
local CFG = {
    -- 底图：超出摄像头范围，纯色无需 NanoVG
    -- 相机 Y=9 俯视，sky 在 Y=-10 距离约 20 单位，FOV48° 可见宽约 30+，设 60 确保填满
    sky = {
        y     = -10,
        sizeX = 60,
        sizeZ = 60,
    },
    -- 远景层：quad 超出屏幕，圆环不会被 quad 边缘裁剪
    -- ratio=1:1 → 512×512，避免圆形拉伸
    far = {
        y     = -4,
        sizeX = 50,
        sizeZ = 50,
        texW  = 512,
        texH  = 512,
        alpha = 0.45,
    },
    -- 云层：超出镜头，正方形 quad（静态烘焙，节点呼吸移动）
    cloud = {
        y     = -1.5,
        sizeX = 50,
        sizeZ = 50,
        texW  = 512,
        texH  = 512,
        alpha = 0.50,
    },
    -- 城市中景：最靠近桌面，稍窄
    city = {
        y     = -0.5,
        sizeX = CARD_W * 8,   -- ≈5.04
        sizeZ = CARD_H * 4,   -- ≈3.52  ratio≈1.43 → 512×384
        texW  = 512,
        texH  = 384,
        alpha = 0.55,
    },
    -- 竖向地平线面片：quad 超出屏幕，圆环不裁剪；正方形 → 512×512
    backdrop = {
        z     = 10,
        y     = -1,
        sizeX = 50,
        sizeY = 50,
        texW  = 512,
        texH  = 512,
        alpha = 0.50,
    },
    -- 卡桌两侧装饰：向外扩大超出屏幕，内边缘靠齐桌沿 X=±3
    -- offsetX=8 → 内边缘 8-5=3，外边缘 8+5=13（屏幕外）
    -- ratio=10/15≈0.67 → 256×384
    side = {
        y       = -0.1,
        offsetX = 8,
        sizeX   = 10,
        sizeZ   = 15,
        texW    = 256,
        texH    = 384,
        alpha   = 0.55,
    },
}

-- 云朵颜色
local CLOUD_SHADOW = { r=219/255, g=244/255, b=253/255 }

-- ============================================================================
-- 内部状态
-- ============================================================================
---@type table
local self_ = {
    nvg            = nil,
    font           = -1,
    time           = 0,

    -- 3D 节点
    skyNode        = nil,
    farNode        = nil,
    cloudNode      = nil,
    cityNode       = nil,
    backdropNode   = nil,
    sideNodeL      = nil,
    sideNodeR      = nil,

    -- Render targets
    farTex         = nil,
    cloudTex       = nil,
    backdropTex    = nil,
    sideTex        = nil,

    -- Metaball blobs（云层，只在首帧烘焙一次）
    blobs          = {},
    cloudReady     = false,
}

-- ============================================================================
-- 工具：创建水平 Quad（Plane.mdl，法线朝上）
-- ============================================================================
local function createHorizQuad(scene, name, y, sx, sz)
    local node = scene:CreateChild(name)
    node.position = Vector3(0, y, 0)
    -- Plane.mdl 默认 1×1，用 scale 控制尺寸
    node.scale = Vector3(sx, 1, sz)
    local sm = node:CreateComponent("StaticModel")
    sm:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
    sm.castShadows = false
    return node, sm
end

-- 工具：创建 RenderTarget Texture2D
local function createRT(w, h)
    local tex = Texture2D:new()
    tex:SetNumLevels(1)
    tex:SetSize(w, h, Graphics:GetRGBAFormat(), TEXTURE_RENDERTARGET)
    tex:SetFilterMode(FILTER_BILINEAR)
    return tex
end

-- 克隆 DiffAlpha.xml + UNLIT define（只创建一次）：alpha 混合 + 不受光照暗化
local diffAlphaUnlitTech_ = nil
local function getDiffAlphaUnlitTech()
    if diffAlphaUnlitTech_ then return diffAlphaUnlitTech_ end
    local base = cache:GetResource("Technique", "Techniques/DiffAlpha.xml")
    diffAlphaUnlitTech_ = base:Clone("BG_DiffAlphaUnlit")
    local pass = diffAlphaUnlitTech_:GetPass("alpha")
    if pass then pass:SetPixelShaderDefines("DIFFMAP UNLIT") end
    return diffAlphaUnlitTech_
end

-- 工具：创建带透明的材质（用于 NanoVG Quad）
-- alpha 混合 + 不受 LightGroup SH ambient 影响，颜色直出
---@param tex Texture2D
---@param alpha number?  整体透明度 0~1，默认 1.0
local function makeMat(tex, alpha)
    local a = alpha or 1.0
    local mat = Material:new()
    mat:SetTechnique(0, getDiffAlphaUnlitTech())
    mat:SetTexture(TU_DIFFUSE, tex)
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 1.0, 1.0, a)))
    mat:SetCullMode(CULL_NONE)
    return mat
end

-- ============================================================================
-- 初始化 Metaball blobs
-- ============================================================================
local function initBlobs()
    self_.blobs = {}
    -- 3 组云团，每组 2-3 个 blob 紧密聚集，形成云朵轮廓
    -- r 相比前版缩小约一半；团内偏移 ≈ 1.5× blob 直径，确保相邻 blob 融合
    local rng = {
        -- 云团 A：左上区域
        {x=0.17, y=0.26, vx= 0.022, vy= 0.016, r=0.033},
        {x=0.22, y=0.21, vx= 0.018, vy= 0.020, r=0.028},
        {x=0.13, y=0.21, vx= 0.020, vy= 0.014, r=0.025},
        -- 云团 B：中右区域
        {x=0.63, y=0.52, vx=-0.014, vy= 0.018, r=0.031},
        {x=0.69, y=0.46, vx=-0.018, vy= 0.015, r=0.027},
        {x=0.72, y=0.54, vx=-0.012, vy= 0.021, r=0.024},
        -- 云团 C：左下区域
        {x=0.31, y=0.72, vx= 0.013, vy=-0.016, r=0.030},
        {x=0.37, y=0.68, vx= 0.016, vy=-0.019, r=0.026},
    }
    for _, b in ipairs(rng) do
        table.insert(self_.blobs, { x=b.x, y=b.y, vx=b.vx, vy=b.vy, r=b.r })
    end
end

-- ============================================================================
-- 底图：纯蓝→青渐变（直接用 PBR 材质自发光，不需要 NanoVG）
-- ============================================================================
local function createSkyLayer(scene)
    local node, sm = createHorizQuad(scene, "BG_Sky",
        CFG.sky.y, CFG.sky.sizeX, CFG.sky.sizeZ)

    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    -- 用 Emissive 驱动颜色（不受光照影响）
    mat:SetShaderParameter("MatDiffColor", Variant(Color(0.18, 0.55, 0.92, 1.0)))
    sm:SetMaterial(mat)
    self_.skyNode = node
end

-- ============================================================================
-- 远景层：动态大圆环 + 圆形半调网格
-- ============================================================================
local function createFarLayer(scene)
    local node, sm = createHorizQuad(scene, "BG_Far",
        CFG.far.y, CFG.far.sizeX, CFG.far.sizeZ)

    self_.farTex = createRT(CFG.far.texW, CFG.far.texH)
    nvgSetRenderTarget(self_.nvg, self_.farTex)
    sm:SetMaterial(makeMat(self_.farTex, CFG.far.alpha))
    self_.farNode = node
end

-- ============================================================================
-- 云层：Metaball
-- ============================================================================
local function createCloudLayer(scene)
    local node, sm = createHorizQuad(scene, "BG_Cloud",
        CFG.cloud.y, CFG.cloud.sizeX, CFG.cloud.sizeZ)

    self_.cloudTex = createRT(CFG.cloud.texW, CFG.cloud.texH)
    sm:SetMaterial(makeMat(self_.cloudTex, CFG.cloud.alpha))
    self_.cloudNode = node
    initBlobs()
end

-- ============================================================================
-- 城市中景：读取生成好的贴图
-- ============================================================================
local function createCityLayer(scene)
    local node, sm = createHorizQuad(scene, "BG_City",
        CFG.city.y, CFG.city.sizeX, CFG.city.sizeZ)

    local cityTex = cache:GetResource("Texture2D",
        "image/bg_city_skyline_20260524093401.png")
    if cityTex then
        cityTex:SetSRGB(true)
        sm:SetMaterial(makeMat(cityTex, CFG.city.alpha))
    else
        -- 占位：半透明灰色
        local mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique","Techniques/NoTextureUnlit.xml"))
        mat:SetShaderParameter("MatDiffColor", Variant(Color(0.4,0.4,0.5,0.3)))
        sm:SetMaterial(mat)
    end
    self_.cityNode = node
end

-- ============================================================================
-- 竖向远景面片（出现在屏幕上方地平线处）
-- Plane 绕 X 轴旋转 -90°，法线朝向 -Z（朝向相机）
-- ============================================================================
local function createBackdropLayer(scene)
    local c = CFG.backdrop
    local node = scene:CreateChild("BG_Backdrop")
    node.position = Vector3(0, c.y, c.z)
    -- 旋转 -90° 使面片竖立，法线朝 -Z（面向相机方向）
    node.rotation = Quaternion(-90, Vector3.RIGHT)
    node.scale = Vector3(c.sizeX, 1, c.sizeY)

    local sm = node:CreateComponent("StaticModel")
    sm:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
    sm.castShadows = false

    self_.backdropTex = createRT(c.texW, c.texH)
    sm:SetMaterial(makeMat(self_.backdropTex, CFG.backdrop.alpha))
    self_.backdropNode = node
end

-- ============================================================================
-- NanoVG 绘制：竖向远景面片（地平线处 - 渐变天空 + 动态圆环）
-- ============================================================================
local function drawBackdropLayer(t)
    local ctx = self_.nvg
    local w, h = CFG.backdrop.texW, CFG.backdrop.texH

    nvgBeginFrame(ctx, w, h, 1.0)

    -- 1. 渐变背景（上方青蓝 → 下方浅蓝白）
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, w, h)
    local bgPaint = nvgLinearGradient(ctx, 0, 0, 0, h,
        nvgRGBA(72, 168, 255, 220),    -- 上：鲜明天蓝
        nvgRGBA(200, 235, 255, 100))   -- 下：浅雾蓝（与地面融合）
    nvgFillPaint(ctx, bgPaint)
    nvgFill(ctx)

    -- 2. 远景城市轮廓（简单几何剪影，蓝紫调）
    local buildingColor = nvgRGBA(90, 130, 200, 160)
    -- 左侧建筑群
    local buildings = {
        {x=0.02,  w=0.06, h=0.55, style="rect"},
        {x=0.07,  w=0.04, h=0.40, style="rect"},
        {x=0.10,  w=0.07, h=0.65, style="rect"},
        {x=0.16,  w=0.03, h=0.30, style="rect"},
        {x=0.18,  w=0.05, h=0.50, style="rect"},
        -- 右侧建筑群（对称偏移）
        {x=0.76,  w=0.05, h=0.50, style="rect"},
        {x=0.80,  w=0.03, h=0.30, style="rect"},
        {x=0.82,  w=0.07, h=0.65, style="rect"},
        {x=0.88,  w=0.04, h=0.40, style="rect"},
        {x=0.91,  w=0.06, h=0.55, style="rect"},
        -- 中心区域（矮一些，不遮住圆环）
        {x=0.25,  w=0.04, h=0.25, style="rect"},
        {x=0.30,  w=0.03, h=0.20, style="rect"},
        {x=0.65,  w=0.03, h=0.20, style="rect"},
        {x=0.68,  w=0.04, h=0.25, style="rect"},
    }
    nvgBeginPath(ctx)
    for _, b in ipairs(buildings) do
        local bx = b.x * w
        local bw = b.w * w
        local bh = b.h * h
        local by = h - bh  -- 从底部向上
        nvgRect(ctx, bx, by, bw, bh)
    end
    nvgFillColor(ctx, buildingColor)
    nvgFill(ctx)

    -- 3. 动态大圆环（中心，远景感）—— 放大
    local cx, cy = w * 0.5, h * 0.62
    local rings = {
        { r = h * 0.80, speed =  0.05, alpha = 70, lw = 3.0 },
        { r = h * 0.58, speed = -0.07, alpha = 55, lw = 2.0 },
        { r = h * 0.36, speed =  0.10, alpha = 40, lw = 1.5 },
    }
    for _, ring in ipairs(rings) do
        local pulse = ring.r * (1.0 + 0.03 * math.sin(t * ring.speed * math.pi * 2))
        local segments = 32
        local gapRatio = 0.3
        for i = 0, segments - 1 do
            local a0 = (i / segments) * math.pi * 2 + t * ring.speed
            local a1 = a0 + (1 - gapRatio) * (math.pi * 2 / segments)
            nvgBeginPath(ctx)
            nvgArc(ctx, cx, cy, pulse, a0, a1, NVG_CW)
            nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, ring.alpha))
            nvgStrokeWidth(ctx, ring.lw)
            nvgStroke(ctx)
        end
    end

    -- 4. 底部渐隐（与地面融合）
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, h * 0.7, w, h * 0.3)
    local fadePaint = nvgLinearGradient(ctx, 0, h * 0.7, 0, h,
        nvgRGBA(0, 0, 0, 0),
        nvgRGBA(0, 0, 0, 180))
    nvgFillPaint(ctx, fadePaint)
    nvgFill(ctx)

    nvgEndFrame(ctx)
end

-- ============================================================================
-- 卡桌两侧装饰层
-- ============================================================================
local function createSideLayers(scene)
    -- 共用同一张 RT（两侧绘制相同内容）
    self_.sideTex = createRT(CFG.side.texW, CFG.side.texH)

    -- 左侧
    local nL = scene:CreateChild("BG_SideL")
    nL.position = Vector3(-CFG.side.offsetX, CFG.side.y, 0)
    nL.scale = Vector3(CFG.side.sizeX, 1, CFG.side.sizeZ)
    local smL = nL:CreateComponent("StaticModel")
    smL:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
    smL:SetMaterial(makeMat(self_.sideTex, CFG.side.alpha))
    smL.castShadows = false
    self_.sideNodeL = nL

    -- 右侧（同纹理，镜像靠 X scale 负值）
    local nR = scene:CreateChild("BG_SideR")
    nR.position = Vector3( CFG.side.offsetX, CFG.side.y, 0)
    nR.scale = Vector3(-CFG.side.sizeX, 1, CFG.side.sizeZ)  -- 负X镜像
    local smR = nR:CreateComponent("StaticModel")
    smR:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
    smR:SetMaterial(makeMat(self_.sideTex, CFG.side.alpha))
    smR.castShadows = false
    self_.sideNodeR = nR
end

-- ============================================================================
-- NanoVG 绘制：远景层（大圆环 + 半调圆形网格）
-- ============================================================================
local function drawFarLayer(t)
    local ctx = self_.nvg
    local w, h = CFG.far.texW, CFG.far.texH

    nvgBeginFrame(ctx, w, h, 1.0)

    -- 清空（透明）
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, w, h)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 0))
    nvgFill(ctx)

    -- 1. 半调圆形网格（固定，装饰性）
    local dotR    = 4
    local spacing = 28
    local gridOffX = w * 0.5
    local gridOffY = h * 0.5
    local gridR   = math.min(w, h) * 0.38

    nvgBeginPath(ctx)
    local cols = math.floor(gridR * 2 / spacing)
    local rows = math.floor(gridR * 2 / spacing)
    for row = -rows, rows do
        for col = -cols, cols do
            local px = gridOffX + col * spacing
            local py = gridOffY + row * spacing
            local dist = math.sqrt((px - gridOffX)^2 + (py - gridOffY)^2)
            if dist < gridR then
                -- 越靠近边缘，点越小（渐隐）
                local fade = 1.0 - dist / gridR
                local r = dotR * (0.4 + 0.6 * fade)
                nvgCircle(ctx, px, py, r)
            end
        end
    end
    nvgFillColor(ctx, nvgRGBA(100, 180, 255, 60))
    nvgFill(ctx)

    -- 2. 动态大圆环 —— 放大，最大环超出面片边缘，视觉上铺满整个远景
    local rings = {
        { cx=w*0.5, cy=h*0.5, r=h*0.70, speed= 0.12, alpha=70, lw=4.0 },
        { cx=w*0.5, cy=h*0.5, r=h*0.52, speed=-0.08, alpha=55, lw=2.5 },
        { cx=w*0.5, cy=h*0.5, r=h*0.92, speed= 0.05, alpha=30, lw=2.0 },
        { cx=w*0.5, cy=h*0.5, r=h*0.33, speed=-0.15, alpha=40, lw=1.5 },
    }
    for _, ring in ipairs(rings) do
        -- 半径微弱脉冲
        local pulse = ring.r * (1.0 + 0.04 * math.sin(t * ring.speed * math.pi * 2))
        -- 虚线圆环（用 arc 分段模拟）
        local segments = 36
        local gapRatio = 0.35  -- 间隙占比
        for i = 0, segments - 1 do
            local a0 = (i / segments) * math.pi * 2 + t * ring.speed
            local a1 = a0 + (1 - gapRatio) * (math.pi * 2 / segments)
            nvgBeginPath(ctx)
            nvgArc(ctx, ring.cx, ring.cy, pulse, a0, a1, NVG_CW)
            nvgStrokeColor(ctx, nvgRGBA(150, 210, 255, ring.alpha))
            nvgStrokeWidth(ctx, ring.lw)
            nvgStroke(ctx)
        end
    end

    nvgEndFrame(ctx)
end

-- ============================================================================
-- NanoVG 绘制：Metaball 云层（只调用一次，烘焙到 RT）
-- blob 位置固定，动画通过节点移动实现
-- ============================================================================
local function drawCloudLayerOnce()
    local ctx = self_.nvg
    local w, h = CFG.cloud.texW, CFG.cloud.texH

    nvgBeginFrame(ctx, w, h, 1.0)

    -- 清空
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, w, h)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 0))
    nvgFill(ctx)

    -- Metaball 简化实现：
    -- 每个 blob 绘制一个大径向渐变圆（中心白色不透明→边缘透明）
    -- 叠加时 alpha 累加，形成融合轮廓感
    -- 先绘制阴影层（偏移+浅蓝色）
    local sr, sg, sb = CLOUD_SHADOW.r, CLOUD_SHADOW.g, CLOUD_SHADOW.b
    for _, b in ipairs(self_.blobs) do
        local cx = b.x * w + 6
        local cy = b.y * h + 8
        local r  = b.r * h
        nvgBeginPath(ctx)
        nvgCircle(ctx, cx, cy, r * 0.85)
        local shadowPaint = nvgRadialGradient(ctx, cx, cy, r * 0.2, r * 0.85,
            nvgRGBAf(sr, sg, sb, 0.55),
            nvgRGBAf(sr, sg, sb, 0.0))
        nvgFillPaint(ctx, shadowPaint)
        nvgFill(ctx)
    end

    -- 再绘制白色主体
    for _, b in ipairs(self_.blobs) do
        local cx = b.x * w
        local cy = b.y * h
        local r  = b.r * h
        nvgBeginPath(ctx)
        nvgCircle(ctx, cx, cy, r)
        local cloudPaint = nvgRadialGradient(ctx, cx, cy, r * 0.15, r,
            nvgRGBA(255, 255, 255, 230),
            nvgRGBA(255, 255, 255, 0))
        nvgFillPaint(ctx, cloudPaint)
        nvgFill(ctx)
    end

    nvgEndFrame(ctx)
end

-- ============================================================================
-- NanoVG 绘制：卡桌两侧装饰（细圆环 + 像素星星）
-- ============================================================================
local function drawSideLayer(t)
    local ctx = self_.nvg
    local w, h = CFG.side.texW, CFG.side.texH

    nvgBeginFrame(ctx, w, h, 1.0)

    -- 清空
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, w, h)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 0))
    nvgFill(ctx)

    -- 1. 细圆环（3个，不同位置和相位）—— 放大
    local rings = {
        { cx=w*0.5, cy=h*0.35, r=w*0.48, speed=0.15,  alpha=80,  lw=1.5 },
        { cx=w*0.5, cy=h*0.35, r=w*0.65, speed=-0.10, alpha=50,  lw=1.0 },
        { cx=w*0.3, cy=h*0.65, r=w*0.34, speed=0.20,  alpha=60,  lw=1.2 },
    }
    for _, ring in ipairs(rings) do
        local pulse = ring.r * (1.0 + 0.05 * math.sin(t * ring.speed * math.pi * 2))
        local segments = 24
        local gapRatio = 0.4
        for i = 0, segments - 1 do
            local a0 = (i / segments) * math.pi * 2 + t * ring.speed
            local a1 = a0 + (1 - gapRatio) * (math.pi * 2 / segments)
            nvgBeginPath(ctx)
            nvgArc(ctx, ring.cx, ring.cy, pulse, a0, a1, NVG_CW)
            nvgStrokeColor(ctx, nvgRGBA(180, 230, 255, ring.alpha))
            nvgStrokeWidth(ctx, ring.lw)
            nvgStroke(ctx)
        end
    end

    -- 2. 像素星星（✦ 形，固定位置 + 呼吸缩放）
    local stars = {
        { cx=w*0.25, cy=h*0.20, size=14, phase=0.0  },
        { cx=w*0.72, cy=h*0.30, size=10, phase=1.2  },
        { cx=w*0.15, cy=h*0.55, size= 8, phase=2.4  },
        { cx=w*0.80, cy=h*0.60, size=12, phase=0.7  },
        { cx=w*0.45, cy=h*0.80, size= 9, phase=1.8  },
        { cx=w*0.60, cy=h*0.15, size=11, phase=3.0  },
    }
    for _, s in ipairs(stars) do
        local pulse = 0.7 + 0.3 * math.sin(t * 1.8 + s.phase)
        local sz = s.size * pulse
        local alpha = math.floor(160 * pulse)
        local cx, cy = s.cx, s.cy
        -- 像素星形：4 臂十字 + 45°斜臂（更细）
        local arms = { {1,0},{-1,0},{0,1},{0,-1} }
        local diag = { {0.6,0.6},{-0.6,0.6},{0.6,-0.6},{-0.6,-0.6} }
        nvgBeginPath(ctx)
        for _, a in ipairs(arms) do
            nvgRect(ctx, cx + a[1]*sz*0.12 - sz*0.12, cy + a[2]*sz*0.12 - sz*0.12,
                sz*0.24, sz*0.24)
            nvgRect(ctx, cx + a[1]*sz*0.4 - sz*0.10, cy + a[2]*sz*0.4 - sz*0.10,
                sz*0.20, sz*0.20)
            nvgRect(ctx, cx + a[1]*sz*0.7 - sz*0.08, cy + a[2]*sz*0.7 - sz*0.08,
                sz*0.16, sz*0.16)
        end
        for _, d in ipairs(diag) do
            nvgRect(ctx, cx + d[1]*sz*0.35 - sz*0.07, cy + d[2]*sz*0.35 - sz*0.07,
                sz*0.14, sz*0.14)
        end
        nvgFillColor(ctx, nvgRGBA(255, 235, 100, alpha))
        nvgFill(ctx)
    end

    nvgEndFrame(ctx)
end

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 初始化背景系统
---@param scene Scene
---@param nvg NVGContextWrapper  主 NanoVG context（来自 main.lua 的 nvg_）
---@param font number  字体 ID
function Background.init(scene, nvg, font)
    self_.nvg  = nvg
    self_.font = font
    self_.time = 0

    createSkyLayer(scene)
    createFarLayer(scene)
    createCloudLayer(scene)
    createCityLayer(scene)
    createBackdropLayer(scene)
    createSideLayers(scene)
end

--- 每帧更新（在 HandleUpdate 中调用）
---@param dt number
function Background.update(dt)
    self_.time = self_.time + dt

    -- 云层节点左右呼吸漂移（贴图静态，节点移动模拟云飘）
    if self_.cloudNode then
        local t = self_.time
        local driftX = math.sin(t * 0.20) * 1.2
        local driftZ = math.cos(t * 0.13) * 0.6
        self_.cloudNode.position = Vector3(driftX, CFG.cloud.y, driftZ)
    end
end

--- NanoVG 渲染（在 NanoVGRender 事件中，其他 UI 绘制之前调用）
--- 每次调用会依次切换 RT，绘制完后需恢复主 frame 的渲染目标
function Background.render()
    if self_.nvg == nil then return end
    local t = self_.time

    -- 远景层
    nvgSetRenderTarget(self_.nvg, self_.farTex)
    drawFarLayer(t)

    -- 云层：只在首帧烘焙一次，之后不再重绘（节点呼吸移动见 update）
    if not self_.cloudReady then
        nvgSetRenderTarget(self_.nvg, self_.cloudTex)
        drawCloudLayerOnce()
        self_.cloudReady = true
    end

    -- 竖向地平线面片
    nvgSetRenderTarget(self_.nvg, self_.backdropTex)
    drawBackdropLayer(t)

    -- 两侧装饰
    nvgSetRenderTarget(self_.nvg, self_.sideTex)
    drawSideLayer(t)

    -- 恢复为屏幕渲染（main 的 nvgBeginFrame 会接管）
    nvgSetRenderTarget(self_.nvg, nil)
end

--- 销毁
function Background.destroy()
    self_.blobs = {}
end

return Background

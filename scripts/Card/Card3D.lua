-- ============================================================================
-- Card/Card3D.lua - 3D 卡牌实体（多层 Quad 视差堆叠）
--
-- 层级结构（所有子节点直接挂在 root 上）:
--   L0  backPlate       — 卡背
--   L1  artClip         — 插画裁剪底板
--   L2  artArea         — 角色插画
--   L3  borderMask      — 边框 mask
--   L4  bottomGradient  — 底部暗色渐变遮罩
--   L5  costBadge       — 费用徽章（左上）
--   L6  powerBadge      — 攻击力徽章（左下）
--   L7  defenseBadge    — 防御力徽章（右下）
--   L8  pitchGem        — 资源宝石（右上）
--   T0-T3 Text3D        — 数字 + 卡名
--
-- 重要：card.node.scale = (1,1,1)，均匀缩放，避免子节点包围盒错乱。
-- 各 Plane 层的尺寸由 scaleX/scaleZ 显式传入世界空间米值。
-- ============================================================================

local CardData          = require("Card.CardData")
local CardTextRenderer  = require("Card.CardTextRenderer")

local Card3D = {}
Card3D.__index = Card3D

-- 卡牌物理尺寸（标准 63×88mm 映射到米）
local W = 0.63   -- 宽
local H = 0.88   -- 高

Card3D.WIDTH     = W
Card3D.HEIGHT    = H
Card3D.THICKNESS = 0.005

-- ============================================================================
-- 层级 Y 偏移（局部空间，根节点 scale=1，所以等于世界空间）
-- ============================================================================
local LAYER_Y = {
    back     = -0.001,
    clip     =  0.000,
    art      =  0.001,
    border   =  0.002,
    gradient =  0.003,
    badge    =  0.004,
    gem      =  0.004,
    text     =  0.015,   -- 文字纹理覆盖层（明显高于徽章，避免深度冲突）
}

local LAYER_BIAS = {
    back     = 0,
    clip     = -0.00001,
    art      = -0.00002,
    border   = -0.00003,
    gradient = -0.00004,
    badge    = -0.00005,
    gem      = -0.00005,
}

-- ============================================================================
-- 布局常量（世界空间米，card.node scale=1）
-- ============================================================================

local ART_W = W * 0.95
local ART_H = H * 0.95

-- 徽章尺寸（正方形）
local BADGE_SIZE = W * 0.22   -- ≈ 0.139m

-- 徽章位置（局部空间，原点在卡面中心）
local BADGE_POS = {
    cost    = { x = -W * 0.36, z =  H * 0.38 },
    power   = { x = -W * 0.36, z = -H * 0.38 },
    defense = { x =  W * 0.36, z = -H * 0.38 },
}

-- 宝石尺寸
local GEM_SIZE = W * 0.14

local GEM_POS = { x = W * 0.36, z = H * 0.38 }

-- （文字由 CardTextRenderer 通过 NanoVG render-to-texture 绘制，无需 Text3D）

-- ============================================================================
-- 纹理路径
-- ============================================================================
local TEX = {
    cardBack       = "image/card_back_pattern.png",
    artClip        = "image/card_art_clip.png",
    borderMask     = "image/card_border_mask.png",
    bottomGradient = "image/card_bottom_gradient.png",
    badgeCost      = "image/badge_cost.png",
    badgeAttack    = "image/badge_attack.png",
    badgeDefense   = "image/badge_defense.png",
    gemRed         = "image/pitch_gem_red.png",
    gemYellow      = "image/pitch_gem_yellow.png",
    gemBlue        = "image/pitch_gem_blue.png",
}

local PITCH_GEM_TEX = {
    [1] = TEX.gemRed,
    [2] = TEX.gemYellow,
    [3] = TEX.gemBlue,
}

local ART_MAP = {
    -- 英雄专属卡（精确前缀，优先匹配）
    ["spec_kaede"]   = "image/hero_kaede_v6_20260523021216.png",     -- 一之濑枫（GPT v6）
    ["spec_xia_lin"] = "image/hero_xia_lin_v4_20260522195334.png",   -- 夏琳（GPT v4）
    ["spec_yun_rou"] = "image/hero_yun_rou_v8a_20260523022637.png",  -- 云柔（GPT v8a）
    ["spec_xiao_tao"]= "image/hero_xiao_tao_v4b_20260522195237.png", -- 铁拳小桃（GPT v4）
    -- 职业通用占位图（前缀回退）
    ["spec_"] = "image/ba_placeholder_6_20260522181353.png",   -- 其他专属卡：白发紫瞳
    ["war_"]  = "image/ba_placeholder_1_20260522181341.png",   -- 剑道：银发制服
    ["nin_"]  = "image/ba_placeholder_3_20260522181340.png",   -- 跆拳道：短发运动
    ["gua_"]  = "image/ba_placeholder_4_20260522181427.png",   -- 太极：金发白裙
    ["bru_"]  = "image/ba_placeholder_2_20260522181936.png",   -- 拳击：棕发卫衣
    ["gen_"]  = "image/ba_placeholder_5_20260522181415.png",   -- 通用：粉发偶像
}

local function findArtPath(cardId)
    if ART_MAP[cardId] then return ART_MAP[cardId] end
    -- 最长前缀优先，避免短前缀（spec_）抢先匹配长前缀（spec_kaede）
    local bestPath, bestLen = nil, 0
    for prefix, path in pairs(ART_MAP) do
        local plen = #prefix
        if plen > bestLen and string.sub(cardId, 1, plen) == prefix then
            bestPath, bestLen = path, plen
        end
    end
    return bestPath
end

-- ============================================================================
-- 材质工厂
-- ============================================================================
local matCache_    = {}
local texMatCache_ = {}

local function getMaterial(key, r, g, b, metallic, roughness)
    if matCache_[key] then return matCache_[key]:Clone("") end
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(r, g, b, 1.0)))
    matCache_[key] = mat
    return mat:Clone("")
end

-- 克隆 DiffAlpha.xml 并加上 UNLIT define（只创建一次）
-- 效果：alpha 混合（透明）+ 不受 SH ambient / 平行光影响，颜色直出
local diffAlphaUnlitTech_ = nil
local function getDiffAlphaUnlitTechnique()
    if diffAlphaUnlitTech_ then return diffAlphaUnlitTech_ end
    local base = cache:GetResource("Technique", "Techniques/DiffAlpha.xml")
    diffAlphaUnlitTech_ = base:Clone("DiffAlphaUnlit")
    local pass = diffAlphaUnlitTech_:GetPass("alpha")
    if pass then
        -- DIFFMAP=启用贴图采样, UNLIT=跳过光照计算
        pass:SetPixelShaderDefines("DIFFMAP UNLIT")
    end
    return diffAlphaUnlitTech_
end

local function getTexturedMaterial(texturePath)
    if texMatCache_[texturePath] then return texMatCache_[texturePath]:Clone("") end
    local tex = cache:GetResource("Texture2D", texturePath)
    if not tex then return nil end
    tex:SetSRGB(true)   -- 颜色贴图须标记 sRGB，让 GPU 正确解码到线性空间
    local mat = Material:new()
    mat:SetTechnique(0, getDiffAlphaUnlitTechnique())  -- alpha 混合 + 不受光照暗化
    mat:SetTexture(TU_DIFFUSE, tex)
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
    texMatCache_[texturePath] = mat
    return mat:Clone("")
end

-- 克隆 DiffUnlit technique 并加上 ALPHAMASK define（只创建一次）
-- 注意：强制写入完整 defines，防止读取 pixelShaderDefines 为空时丢失 UNLIT
local unlitAlphaMaskTech_ = nil
local function getUnlitAlphaMaskTechnique()
    if unlitAlphaMaskTech_ then return unlitAlphaMaskTech_ end
    local base = cache:GetResource("Technique", "Techniques/DiffUnlit.xml")
    unlitAlphaMaskTech_ = base:Clone("DiffUnlitAlphaMask")
    local pass = unlitAlphaMaskTech_:GetPass("base")
    if pass then
        -- 强制写入完整 defines：DIFFMAP=启用贴图, UNLIT=不受光照, ALPHAMASK=裁剪透明
        pass:SetPixelShaderDefines("DIFFMAP UNLIT ALPHAMASK")
    end
    return unlitAlphaMaskTech_
end

local opaqueMatCache_ = {}

local function getOpaqueTexturedMaterial(texturePath)
    if opaqueMatCache_[texturePath] then return opaqueMatCache_[texturePath]:Clone("") end
    local tex = cache:GetResource("Texture2D", texturePath)
    if not tex then return nil end
    tex:SetSRGB(true)   -- 颜色贴图须标记 sRGB，让 GPU 正确解码到线性空间
    -- DiffUnlit + ALPHAMASK：不受光照影响，且裁剪掉透明区域
    local mat = Material:new()
    mat:SetTechnique(0, getUnlitAlphaMaskTechnique())
    mat:SetTexture(TU_DIFFUSE, tex)
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
    opaqueMatCache_[texturePath] = mat
    return mat:Clone("")
end

-- ============================================================================
-- 扩大 Plane.mdl 包围盒（防止小尺寸 Plane 被 Octree 错误剔除）
-- ============================================================================
do
    local planeModel = cache:GetResource("Model", "Models/Plane.mdl")
    if planeModel then
        planeModel:SetBoundingBox(BoundingBox(Vector3(-2, -1, -2), Vector3(2, 1, 2)))
    end
end

-- ============================================================================
-- Plane 层辅助（scaleX/scaleZ 为世界空间米，card.node.scale=1）
-- ============================================================================

local function createSolidLayer(parentNode, name, localY, scaleX, scaleZ, posX, posZ, matKey, r, g, b, metallic, roughness, renderOrd)
    local child = parentNode:CreateChild(name)
    child.position = Vector3(posX, localY, posZ)
    child.scale = Vector3(scaleX, 1.0, scaleZ)
    local sm = child:CreateComponent("StaticModel")
    sm:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
    sm:SetMaterial(getMaterial(matKey, r, g, b, metallic, roughness))
    sm.renderOrder = renderOrd
    sm.castShadows = false
    return child
end

local function createTexturedLayer(parentNode, name, localY, scaleX, scaleZ, posX, posZ, texPath, renderOrd, opaque, bias)
    local mat
    if opaque then
        mat = getOpaqueTexturedMaterial(texPath)
    else
        mat = getTexturedMaterial(texPath)
    end
    if not mat then return nil end

    if bias and bias ~= 0 then
        mat:SetDepthBias(BiasParameters(bias, 0.0))
    end

    local child = parentNode:CreateChild(name)
    child.position = Vector3(posX, localY, posZ)
    child.scale = Vector3(scaleX, 1.0, scaleZ)
    local sm = child:CreateComponent("StaticModel")
    sm:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
    sm:SetMaterial(mat)
    sm.renderOrder = renderOrd
    sm.castShadows = false
    return child
end

-- （文字覆盖层已改为屏幕空间 NanoVG 投影，在 main.lua HandleNanoVGRender 中处理）

-- ============================================================================
-- Card3D.create
-- ============================================================================

function Card3D.create(scene, cardData, faceUp)
    local card = setmetatable({}, Card3D)

    card.data   = cardData
    card.faceUp = faceUp ~= false

    -- 根节点：均匀缩放 scale=(1,1,1)，避免子节点包围盒错乱
    card.node = scene:CreateChild("Card_" .. cardData.id)
    card.node.scale = Vector3(1.0, 1.0, 1.0)

    -- 碰撞体（薄片，世界空间尺寸）
    local body = card.node:CreateComponent("RigidBody")
    body.mass = 0
    body.collisionLayer = 2
    body.collisionMask  = 0
    local shape = card.node:CreateComponent("CollisionShape")
    shape:SetBox(Vector3(W, Card3D.THICKNESS, H))

    -- L0: 卡背
    card.backNode = createTexturedLayer(card.node, "backPlate",
        LAYER_Y.back, W, H, 0, 0,
        TEX.cardBack, 100, true, LAYER_BIAS.back)
    if not card.backNode then
        card.backNode = createSolidLayer(card.node, "backPlate",
            LAYER_Y.back, W, H, 0, 0,
            "back", 0.08, 0.12, 0.28, 0.05, 0.6, 100)
    end

    -- L1: 插画裁剪底板
    card.artClipNode = createTexturedLayer(card.node, "artClip",
        LAYER_Y.clip, W, H, 0, 0,
        TEX.artClip, 101, true, LAYER_BIAS.clip)
    if not card.artClipNode then
        card.artClipNode = createSolidLayer(card.node, "artClip",
            LAYER_Y.clip, W, H, 0, 0,
            "body", 0.97, 0.96, 0.93, 0.02, 0.25, 101)
    end

    -- L2: 插画
    local artPath = findArtPath(cardData.id)
    card.artNode = nil
    if artPath then
        card.artNode = createTexturedLayer(card.node, "artArea",
            LAYER_Y.art, ART_W, ART_H, 0, 0,
            artPath, 102, true, LAYER_BIAS.art)
    end

    -- L3: 边框
    card.borderNode = createTexturedLayer(card.node, "borderMask",
        LAYER_Y.border, W, H, 0, 0,
        TEX.borderMask, 103, true, LAYER_BIAS.border)

    -- L4: 底部渐变（透明混合，保留渐变效果）
    card.gradientNode = createTexturedLayer(card.node, "bottomGradient",
        LAYER_Y.gradient, W, H, 0, 0,
        TEX.bottomGradient, 104, false, LAYER_BIAS.gradient)

    -- L5: 费用徽章（左上）
    card.costNode = createTexturedLayer(card.node, "costBadge",
        LAYER_Y.badge, BADGE_SIZE, BADGE_SIZE,
        BADGE_POS.cost.x, BADGE_POS.cost.z,
        TEX.badgeCost, 105, true, LAYER_BIAS.badge)

    -- L6: 攻击力徽章（左下）
    card.powerNode = nil
    if cardData.power and cardData.power > 0 then
        card.powerNode = createTexturedLayer(card.node, "powerBadge",
            LAYER_Y.badge, BADGE_SIZE, BADGE_SIZE,
            BADGE_POS.power.x, BADGE_POS.power.z,
            TEX.badgeAttack, 105, true, LAYER_BIAS.badge)
    end

    -- L7: 防御力徽章（右下）
    card.defenseNode = nil
    if cardData.defense and cardData.defense > 0 then
        card.defenseNode = createTexturedLayer(card.node, "defenseBadge",
            LAYER_Y.badge, BADGE_SIZE, BADGE_SIZE,
            BADGE_POS.defense.x, BADGE_POS.defense.z,
            TEX.badgeDefense, 105, true, LAYER_BIAS.badge)
    end

    -- L8: 资源宝石（右上，按 pitch 数量垂直排列）
    -- pitch=1(红)→1个, pitch=2(黄)→2个, pitch=3(蓝)→3个
    card.gemNodes = {}
    local gemTex = PITCH_GEM_TEX[cardData.pitch]
    if gemTex and cardData.pitch > 0 then
        local count   = cardData.pitch
        local spacing = GEM_SIZE           -- 图片自带留白，直接贴合排列
        -- 顶部对齐：第1个在最上方，向下依次排列
        for i = 1, count do
            local gz = GEM_POS.z - (i - 1) * spacing
            local gn = createTexturedLayer(card.node, "pitchGem" .. i,
                LAYER_Y.gem, GEM_SIZE, GEM_SIZE,
                GEM_POS.x, gz,
                gemTex, 105, true, LAYER_BIAS.gem)
            if gn then
                table.insert(card.gemNodes, gn)
            end
        end
    end

    -- 向 CardTextRenderer 注册，获取文字纹理
    local textTex = CardTextRenderer.register(card)

    -- L9: 文字覆盖层（全卡面透明纹理，高于徽章）
    card.textOverlayNode = nil
    if textTex then
        local overlayMat = Material:new()
        overlayMat:SetTechnique(0, getDiffAlphaUnlitTechnique())  -- alpha 混合 + 不受光照暗化
        overlayMat:SetTexture(TU_DIFFUSE, textTex)
        overlayMat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))

        local overlayNode = card.node:CreateChild("textOverlay")
        overlayNode.position = Vector3(0, LAYER_Y.text, 0)
        overlayNode.scale    = Vector3(W, 1.0, H)
        local sm = overlayNode:CreateComponent("StaticModel")
        sm:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
        sm:SetMaterial(overlayMat)
        sm.renderOrder = 110
        sm.castShadows = false
        card.textOverlayNode = overlayNode
    end

    -- 正面层列表（翻面控制）
    card.frontLayers = { card.artClipNode }
    if card.artNode         then table.insert(card.frontLayers, card.artNode)         end
    if card.borderNode      then table.insert(card.frontLayers, card.borderNode)      end
    if card.gradientNode    then table.insert(card.frontLayers, card.gradientNode)    end
    if card.costNode        then table.insert(card.frontLayers, card.costNode)        end
    if card.powerNode       then table.insert(card.frontLayers, card.powerNode)       end
    if card.defenseNode     then table.insert(card.frontLayers, card.defenseNode)     end
    for _, gn in ipairs(card.gemNodes) do table.insert(card.frontLayers, gn) end
    if card.textOverlayNode then table.insert(card.frontLayers, card.textOverlayNode) end

    card:applyVisibility()

    -- 动画状态
    card.hovered     = false
    card.dragging    = false
    card.animState   = "idle"
    card.wobblePhase = math.random() * math.pi * 2

    card.targetPos = Vector3.ZERO
    card.targetRot = Quaternion.IDENTITY
    card.baseY     = 0

    -- 光效状态（由 CardGlowManager 控制）
    card.glowNode_       = nil
    card.glowMat_        = nil
    card.glowPhase_      = math.random() * math.pi * 2  -- 随机相位，避免同步脉冲
    card.playable_       = false
    card.glowTexApplied_ = false   -- 贴图是否已经应用（延迟由 CardGlowManager 注入）

    -- 光晕平面（略大于卡牌，初始使用无贴图材质占位）
    local glowMat = Material:new()
    glowMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    glowMat:SetShaderParameter("MatDiffColor",      Variant(Color(1.0, 0.82, 0.15, 0)))
    glowMat:SetShaderParameter("MatEmissiveColor",  Variant(Color(0.0, 0.0, 0.0)))
    glowMat:SetShaderParameter("Metallic",          Variant(0.0))
    glowMat:SetShaderParameter("Roughness",         Variant(1.0))

    local glowNode = card.node:CreateChild("cardGlow")
    glowNode.position = Vector3(0, LAYER_Y.back - 0.002, 0)
    glowNode.scale    = Vector3(W * 1.12, 1.0, H * 1.08)
    local glowSM = glowNode:CreateComponent("StaticModel")
    glowSM:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
    glowSM:SetMaterial(glowMat)
    glowSM.renderOrder = 98
    glowSM.castShadows = false
    glowNode.enabled   = false

    card.glowNode_ = glowNode
    card.glowMat_  = glowMat

    return card
end

-- ============================================================================
-- 可见性 / 翻面
-- ============================================================================

function Card3D:applyVisibility()
    if self.faceUp then
        self.backNode.enabled = false
        for _, n in ipairs(self.frontLayers) do
            if n then n.enabled = true end
        end
    else
        self.backNode.enabled = true
        for _, n in ipairs(self.frontLayers) do
            if n then n.enabled = false end
        end
    end
end

function Card3D:flip()
    self.faceUp = not self.faceUp
    self:applyVisibility()
end

-- ============================================================================
-- 位置 / 旋转
-- ============================================================================

function Card3D:setPosition(pos)
    self.node.position = pos
    self.targetPos     = pos
    self.baseY         = pos.y
end

function Card3D:setRotation(rot)
    self.node.rotation = rot
    self.targetRot     = rot
end

function Card3D:setHovered(hovered)
    self.hovered = hovered
end

function Card3D:setDragging(dragging)
    self.dragging = dragging
end

function Card3D:getNode()
    return self.node
end

-- ============================================================================
-- 光效 / 可打出状态
-- ============================================================================

--- 应用柔边光晕贴图（由 CardGlowManager 在 init 后首次 setPlayable 时注入）
---@param tex Texture2D NanoVG 生成的柔边贴图
function Card3D:setGlowTex(tex)
    if self.glowTexApplied_ or not self.glowNode_ then return end
    local mat = Material:new()
    mat:SetTechnique(0, getDiffAlphaUnlitTechnique())  -- alpha 混合 + 不受光照暗化
    mat:SetTexture(TU_DIFFUSE, tex)
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.82, 0.15, 0)))
    local sm = self.glowNode_:GetComponent("StaticModel")
    if sm then sm:SetMaterial(mat) end
    self.glowMat_        = mat
    self.glowTexApplied_ = true
end

--- 开启或关闭光效（由 CardGlowManager 调用）
---@param playable boolean
function Card3D:applyGlow(playable)
    self.playable_ = playable
    if self.glowNode_ then
        self.glowNode_.enabled = playable
    end
end

--- 每帧更新光晕脉冲（由 CardGlowManager.update 驱动）
---@param t number 全局时间
function Card3D:updateGlow(t)
    if not self.glowMat_ then return end
    -- smoothstep 呼吸曲线：比原始 sin 更柔和，峰谷过渡平滑
    local s = 0.5 + 0.5 * math.sin(t * 1.6 + self.glowPhase_)
    local eased = s * s * (3 - 2 * s)  -- smoothstep(0,1,s)
    local alpha = 0.2 + 0.65 * eased   -- 范围 0.2 ~ 0.85
    -- 细微缩放：随呼吸轻微膨胀，增加"活"的感觉
    local scale = 1.0 + 0.025 * eased
    self.glowMat_:SetShaderParameter("MatDiffColor",
        Variant(Color(1.0, 0.82, 0.15, alpha)))
    self.glowNode_.scale = Vector3(W * 1.12 * scale, 1.0, H * 1.08 * scale)
end

function Card3D:destroy()
    CardTextRenderer.unregister(self)
    if self.node then
        self.node:Remove()
        self.node = nil
    end
    self.glowNode_ = nil
    self.glowMat_  = nil
end

return Card3D

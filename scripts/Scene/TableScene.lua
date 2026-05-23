-- ============================================================================
-- Scene/TableScene.lua - 3D 牌桌场景（v3 墨甲武林）
-- 深色花梨木桌面 + 鎏金边线 + 暗色武侠风区域标记
-- ============================================================================

local Theme = require("UI.Theme")

local TableScene = {}

TableScene.TABLE_WIDTH  = 6.0
TableScene.TABLE_DEPTH  = 4.0
TableScene.TABLE_Y      = -0.03

local function createPBRMaterial(color, metallic, roughness, technique)
    local mat = Material:new()
    local tech = technique or "Techniques/PBR/PBRNoTexture.xml"
    mat:SetTechnique(0, cache:GetResource("Technique", tech))
    mat:SetShaderParameter("MatDiffColor", Variant(color))
    mat:SetShaderParameter("Metallic", Variant(metallic))
    mat:SetShaderParameter("Roughness", Variant(roughness))
    return mat
end

local function createZoneMarker(parent, name, pos, scaleX, scaleZ, color)
    local node = parent:CreateChild(name)
    node.position = pos
    node.scale = Vector3(scaleX, 1, scaleZ)

    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
    model:SetMaterial(createPBRMaterial(color, 0.0, 0.9, "Techniques/PBR/PBRNoTextureAlpha.xml"))
    model.castShadows = false
    return node
end

--- 创建鎏金分隔线
local function createGiltDividers(parent)
    local giltColor = Theme.DIVIDER
    local giltMat = createPBRMaterial(giltColor, 0.6, 0.35, "Techniques/PBR/PBRNoTextureAlpha.xml")
    -- 添加微弱金色自发光
    giltMat:SetShaderParameter("MatEmissiveColor", Variant(Color(0.3, 0.22, 0.08)))
    local y = TableScene.TABLE_Y + 0.003

    -- 连招链两侧的竖分隔线
    for _, xPos in ipairs({-2.2, 2.2}) do
        local node = parent:CreateChild("Divider")
        node.position = Vector3(xPos, y, 0)
        node.scale = Vector3(1.4, 1, 0.010)
        local m = node:CreateComponent("StaticModel")
        m:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
        m:SetMaterial(giltMat)
        m.castShadows = false
    end

    -- 己方/对手区域分界线（连招链上下边）
    for _, zPos in ipairs({-0.65, 0.65}) do
        local node = parent:CreateChild("HLine")
        node.position = Vector3(0, y, zPos)
        node.scale = Vector3(4.5, 1, 0.005)
        local m = node:CreateComponent("StaticModel")
        m:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
        m:SetMaterial(giltMat)
        m.castShadows = false
    end

    -- 中央十字交汇点装饰（小正方形）
    local centerDot = parent:CreateChild("CenterDot")
    centerDot.position = Vector3(0, y + 0.001, 0)
    centerDot.scale = Vector3(0.04, 1, 0.04)
    local cdm = centerDot:CreateComponent("StaticModel")
    cdm:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
    cdm:SetMaterial(createPBRMaterial(Theme.TABLE_GILT, 0.7, 0.3))
    cdm.castShadows = false
end

--- 创建鎏金内边线（桌面内侧，与木框呼应）
local function createInnerGiltBorder(parent)
    local y = TableScene.TABLE_Y + 0.003
    local W, D = TableScene.TABLE_WIDTH, TableScene.TABLE_DEPTH
    local inset = 0.12  -- 距边框的内缩距离
    local lineW = 0.015 -- 线宽

    local giltMat = createPBRMaterial(
        Color(Theme.TABLE_GILT.r, Theme.TABLE_GILT.g, Theme.TABLE_GILT.b, 0.25),
        0.5, 0.4, "Techniques/PBR/PBRNoTextureAlpha.xml"
    )
    giltMat:SetShaderParameter("MatEmissiveColor", Variant(Color(0.2, 0.15, 0.05)))

    local lines = {
        { Vector3(0, y, D / 2 - inset),  W - inset * 2, lineW },   -- 上
        { Vector3(0, y, -D / 2 + inset), W - inset * 2, lineW },   -- 下
        { Vector3(-W / 2 + inset, y, 0), lineW, D - inset * 2 },   -- 左
        { Vector3(W / 2 - inset, y, 0),  lineW, D - inset * 2 },   -- 右
    }
    for i, lp in ipairs(lines) do
        local ln = parent:CreateChild("InnerGilt" .. i)
        ln.position = lp[1]
        ln.scale = Vector3(lp[2], 1, lp[3])
        local lm = ln:CreateComponent("StaticModel")
        lm:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
        lm:SetMaterial(giltMat)
        lm.castShadows = false
    end
end

function TableScene.create(scene)
    local root = scene:CreateChild("TableRoot")

    -- 1. 桌面主体（深色花梨木，低反射）
    local tableNode = root:CreateChild("TableSurface")
    tableNode.position = Vector3(0, TableScene.TABLE_Y, 0)
    tableNode.scale = Vector3(TableScene.TABLE_WIDTH, 1, TableScene.TABLE_DEPTH)

    local tableModel = tableNode:CreateComponent("StaticModel")
    tableModel:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
    tableModel:SetMaterial(createPBRMaterial(
        Theme.TABLE_SURFACE, 0.0, 0.78
    ))
    tableModel.castShadows = false

    -- 2. 花梨木边框（深红棕，微光泽）
    local borderY = TableScene.TABLE_Y - 0.02
    local bw = 0.10  -- 稍宽的边框，显得厚重
    local W, D = TableScene.TABLE_WIDTH, TableScene.TABLE_DEPTH
    local borderMat = createPBRMaterial(Theme.TABLE_WOOD, 0.05, 0.55)

    local borders = {
        { Vector3(0, borderY, D / 2),  W + bw * 2, bw },
        { Vector3(0, borderY, -D / 2), W + bw * 2, bw },
        { Vector3(-W / 2, borderY, 0), bw, D },
        { Vector3(W / 2, borderY, 0),  bw, D },
    }
    for i, bp in ipairs(borders) do
        local bn = root:CreateChild("Border" .. i)
        bn.position = bp[1]
        bn.scale = Vector3(bp[2], 1, bp[3])
        local bm = bn:CreateComponent("StaticModel")
        bm:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
        bm:SetMaterial(borderMat)
        bm.castShadows = false
    end

    -- 3. 鎏金内边线
    createInnerGiltBorder(root)

    -- 4. 区域标记（极低饱和度，融入暗色桌面）
    local markY = TableScene.TABLE_Y + 0.002

    -- 连招链（中央）
    createZoneMarker(root, "Zone_CombatChain",
        Vector3(0, markY, 0), 3.6, 1.2, Theme.ZONE_CHAIN)

    -- 己方预备区
    createZoneMarker(root, "Zone_MyArsenal",
        Vector3(0, markY, -1.3), 0.7, 0.5, Theme.ZONE_ARSENAL)

    -- 己方牌库
    createZoneMarker(root, "Zone_MyDeck",
        Vector3(2.3, markY, -1.3), 0.7, 0.9, Theme.ZONE_DECK)

    -- 对手预备区
    createZoneMarker(root, "Zone_OppArsenal",
        Vector3(0, markY, 1.3), 0.7, 0.5, Theme.ZONE_ARSENAL)

    -- 对手牌库
    createZoneMarker(root, "Zone_OppDeck",
        Vector3(2.3, markY, 1.3), 0.7, 0.9, Theme.ZONE_DECK)

    -- 5. 鎏金分隔线装饰
    createGiltDividers(root)

    return root
end

return TableScene

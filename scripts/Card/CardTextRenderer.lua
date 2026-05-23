-- ============================================================================
-- Card/CardTextRenderer.lua - 卡牌文字 render-to-texture
--
-- 方案：独立离线 NanoVG context (texVg) + Y 轴翻转对齐 UV 约定。
-- 每张卡牌持有一张 Texture2D 纹理，初始化后在 renderDirty() 中一次性烘焙。
-- 由 HandleUpdate 调用 renderDirty()，确保在首帧之后烘焙（nvgSetRenderTarget 在 Start() 阶段无效）。
-- ============================================================================

local CardTextRenderer = {}

-- 卡牌物理尺寸（米，与 Card3D.lua 保持一致）
CardTextRenderer.CARD_W    = 0.63
CardTextRenderer.CARD_H    = 0.88
CardTextRenderer.BADGE_SIZE = 0.63 * 0.22   -- ≈ 0.139m

-- 文字纹理分辨率（像素）
local TEX_W = 512
local TEX_H = 512

-- 徽章中心在纹理上的 UV 比例（0-1，原点左下）
-- 与 Card3D 的 BADGE_POS 保持一致：
-- Plane.mdl UV 约定：v=0 在卡牌底部（z 负方向），v=1 在顶部（z 正方向）
-- Y-flip 变换后：draw y = v*h → texture v_tex = 1-v
-- 因此 BADGE_UV.v = 1 - (0.5 + z/H) = 0.5 - z/H
--   cost    左上 z=+H*0.38  → v = 1-(0.5+0.38) = 0.12
--   power   左下 z=-H*0.38  → v = 1-(0.5-0.38) = 0.88
--   defense 右下 z=-H*0.38  → v = 1-(0.5-0.38) = 0.88
--   name    中下 z=-H*0.40  → v = 1-(0.5-0.40) = 0.90
local BADGE_UV = {
    cost    = { u = (0.5 - 0.36),       v = (0.5 - 0.38) },   -- ~0.14, ~0.12
    power   = { u = (0.5 - 0.36),       v = (0.5 + 0.38) },   -- ~0.14, ~0.88
    defense = { u = (0.5 + 0.36),       v = (0.5 + 0.38) },   -- ~0.86, ~0.88
    name    = { u = 0.5,                v = (0.5 + 0.40) },    -- ~0.50, ~0.90
}

-- ──────────────────────────────────────────────────────────────────────────────
-- 内部状态
-- ──────────────────────────────────────────────────────────────────────────────
local texVg_      = nil   -- 独立离线 NanoVG context
local fontId_     = -1

local cards_      = {}    -- 有序列表 { card, dirty }
local cardMap_    = {}    -- card → index in cards_
local initialized_ = false

-- ──────────────────────────────────────────────────────────────────────────────
-- 初始化（传入独立 context，在 Start() 中调用）
-- ──────────────────────────────────────────────────────────────────────────────

--- 初始化渲染器（复用主 NanoVG context，nvgSetRenderTarget 需要绑定到渲染管线的 context）
---@param vg userdata 主 NanoVG context（由 main.lua 的 nvgCreate 创建）
---@return boolean
function CardTextRenderer.init(vg)
    if vg == nil then
        print("[CardTextRenderer] ERROR: vg is nil")
        return false
    end
    texVg_ = vg

    -- 字体已由 main.lua 注册为 "sans"，这里无需重复创建
    fontId_ = 0  -- 占位，实际用 nvgFontFace(ctx, "sans")

    initialized_ = true
    print("[CardTextRenderer] init OK, texVg=" .. tostring(texVg_))
    return true
end

-- ──────────────────────────────────────────────────────────────────────────────
-- 注册 / 注销
-- ──────────────────────────────────────────────────────────────────────────────

--- 注册卡牌：创建 Texture2D 并标脏
---@param card table Card3D 实例（需有 card.data）
---@return Texture2D|nil
function CardTextRenderer.register(card)
    if cardMap_[card] then return cardMap_[card].tex end

    -- 创建 RGBA 纹理，可渲染
    local tex = Texture2D:new()
    tex:SetNumLevels(1)
    tex:SetSize(TEX_W, TEX_H, Graphics:GetRGBAFormat(), TEXTURE_RENDERTARGET)
    tex:SetFilterMode(FILTER_TRILINEAR)
    tex:SetAddressMode(COORD_U, ADDRESS_CLAMP)
    tex:SetAddressMode(COORD_V, ADDRESS_CLAMP)

    local entry = { card = card, tex = tex, dirty = true }
    table.insert(cards_, entry)
    cardMap_[card] = entry

    -- 不在 Start() 阶段立即渲染：nvgSetRenderTarget 在首帧之前无效。
    -- 由 HandleUpdate 调用 renderDirty() 在第一帧之后烘焙。

    return tex
end

--- 注销卡牌
function CardTextRenderer.unregister(card)
    local entry = cardMap_[card]
    if not entry then return end
    cardMap_[card] = nil
    for i, e in ipairs(cards_) do
        if e == entry then
            table.remove(cards_, i)
            break
        end
    end
end

--- 标脏并立即重新渲染（卡牌数据变化时调用）
function CardTextRenderer.markDirty(card)
    local entry = cardMap_[card]
    if not entry then return end
    entry.dirty = false
    CardTextRenderer._renderCard(entry)
end

-- ──────────────────────────────────────────────────────────────────────────────
-- 渲染（在 HandleUpdate 中调用，首帧后有效）
-- ──────────────────────────────────────────────────────────────────────────────

--- 渲染所有脏卡牌的文字纹理
function CardTextRenderer.renderDirty()
    if not initialized_ or texVg_ == nil then return end

    for _, entry in ipairs(cards_) do
        if entry.dirty then
            CardTextRenderer._renderCard(entry)
            entry.dirty = false
        end
    end
end

--- 渲染单张卡牌文字到 entry.tex
---@param entry table {card, tex, dirty}
function CardTextRenderer._renderCard(entry)
    local card = entry.card
    local tex  = entry.tex
    local d    = card.data
    if not d then
        print("[CardTextRenderer] _renderCard: card.data is nil, skip")
        return
    end

    local ctx = texVg_
    if not ctx then
        print("[CardTextRenderer] _renderCard: texVg_ is nil, skip")
        return
    end

    print(string.format("[CardTextRenderer] _renderCard: card=%s cost=%s power=%s defense=%s name=%s",
        tostring(d.id or "?"), tostring(d.cost), tostring(d.power), tostring(d.defense), tostring(d.name)))

    local w, h = TEX_W, TEX_H

    -- 切換渲染目标 → 纹理
    nvgSetRenderTarget(ctx, tex)
    nvgBeginFrame(ctx, w, h, 1.0)

    -- Y 轴翻转：render-target 存储约定与 UV V=0=顶部 对齐（与参考项目 CardTextures.lua 完全一致）
    nvgTranslate(ctx, 0, h)
    nvgScale(ctx, 1, -1)

    -- 清空为透明
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, w, h)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 0))
    nvgFill(ctx)

    -- 徽章字号（根据纹理大小换算，徽章直径约占纹理宽 14%）
    local badgePx = w * (CardTextRenderer.BADGE_SIZE / CardTextRenderer.CARD_W)
    local numSize = badgePx * 0.48   -- 数字占徽章直径约 48%

    -- 坐标转换：UV(0-1) → 像素，在 Y-flip 空间内 v=0 对应纹理底部
    -- Y-flip 后坐标系：Y 轴朝上，原点在左下角，与正常 UV 对应
    local function px(u) return u * w end
    local function py(v) return v * h end  -- Y-flip 空间，直接用 v*h

    local function drawNumText(u, v, text)
        local nx, ny = px(u), py(v)
        local sz = numSize
        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, sz)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        -- 白色主体
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
        nvgText(ctx, nx, ny, text)
    end

    local function drawNameText(u, v, name)
        local nx, ny = px(u), py(v)
        local sz = w * 0.065
        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, sz)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        -- 投影（向右下偏移，半透明黑色）
        local shadow = sz * 0.08
        nvgFillColor(ctx, nvgRGBA(0, 0, 0, 180))
        nvgText(ctx, nx + shadow, ny + shadow, name)
        -- 主体白色
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 245))
        nvgText(ctx, nx, ny, name)
    end

    -- 绘制文字（在同一 Y-flip 空间内，与参考项目一致）
    if d.cost ~= nil then
        drawNumText(BADGE_UV.cost.u, BADGE_UV.cost.v, tostring(d.cost))
    end
    if d.power and d.power > 0 then
        drawNumText(BADGE_UV.power.u, BADGE_UV.power.v, tostring(d.power))
    end
    if d.defense and d.defense > 0 then
        drawNumText(BADGE_UV.defense.u, BADGE_UV.defense.v, tostring(d.defense))
    end
    if d.name and d.name ~= "" then
        drawNameText(BADGE_UV.name.u, BADGE_UV.name.v, d.name)
    end

    nvgEndFrame(ctx)

    -- 还原渲染目标 → 屏幕
    nvgSetRenderTarget(ctx, nil)
end

--- 获取卡牌的文字纹理（供 Card3D 创建 overlay 层使用）
---@param card table
---@return Texture2D|nil
function CardTextRenderer.getTexture(card)
    local entry = cardMap_[card]
    return entry and entry.tex or nil
end

--- 获取所有注册的卡牌（向后兼容，屏幕空间渲染备用）
---@return table
function CardTextRenderer.getCards()
    local result = {}
    for _, e in ipairs(cards_) do
        table.insert(result, e.card)
    end
    return result
end

--- 释放
function CardTextRenderer.destroy()
    -- texVg_ 是主 context，由 main.lua 管理，这里不 delete
    texVg_      = nil
    cards_      = {}
    cardMap_    = {}
    initialized_ = false
end

return CardTextRenderer

-- ============================================================================
-- Card/CardGlowManager.lua - 可打出卡牌光效管理器
--
-- 职责：
--   1. 管理哪些 Card3D 实例处于"可打出"状态
--   2. 每帧驱动 smoothstep 呼吸脉冲动画
--   3. 通过 NanoVG BoxGradient 生成柔边光晕贴图（init 时立即生成）
-- ============================================================================

local CardGlowManager = {}

local glowCards_ = {}
local time_      = 0
local glowTex_   = nil   -- 柔边光晕贴图（init 时生成）

-- ──────────────────────────────────────────────────────────────────────────────
-- 光晕贴图生成（卡牌形状柔边边框 glow，128×178）
-- 比例近似光晕平面比例 W*1.12 : H*1.08 = 0.706 : 0.950 ≈ 1 : 1.346
-- ──────────────────────────────────────────────────────────────────────────────

local GTEX_W = 128
local GTEX_H = 178

local function createGlowTex(vg)
    local tex = Texture2D:new()
    tex:SetNumLevels(1)
    tex:SetSize(GTEX_W, GTEX_H, Graphics:GetRGBAFormat(), TEXTURE_RENDERTARGET)
    tex:SetFilterMode(FILTER_BILINEAR)
    tex:SetAddressMode(COORD_U, ADDRESS_CLAMP)
    tex:SetAddressMode(COORD_V, ADDRESS_CLAMP)

    nvgSetRenderTarget(vg, tex)
    nvgBeginFrame(vg, GTEX_W, GTEX_H, 1.0)

    -- 透明底
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, GTEX_W, GTEX_H)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 0))
    nvgFill(vg)

    -- 卡牌在光晕平面内的边距（光晕平面比卡牌大 12%/8%）
    -- 卡牌边缘在贴图中的内缩量：≈ 5.4% × W，3.7% × H
    local padX    = math.floor(GTEX_W * 0.054)  -- ≈ 7px
    local padY    = math.floor(GTEX_H * 0.037)  -- ≈ 7px
    local iw      = GTEX_W - padX * 2
    local ih      = GTEX_H - padY * 2
    local feather = 20   -- 光晕向外扩散宽度（px），越大越柔
    local cr      = 5    -- 圆角半径

    -- 外层宽扩散（很柔，低亮度）
    local gradOuter = nvgBoxGradient(vg, padX, padY, iw, ih, cr, feather * 1.6,
        nvgRGBA(255, 220, 80, 160),
        nvgRGBA(255, 180, 40, 0))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, GTEX_W, GTEX_H)
    nvgFillPaint(vg, gradOuter)
    nvgFill(vg)

    -- 内层窄边框（贴卡牌边缘，亮度更高）
    local gradInner = nvgBoxGradient(vg, padX, padY, iw, ih, cr, feather * 0.6,
        nvgRGBA(255, 245, 160, 240),
        nvgRGBA(255, 200, 60, 0))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, GTEX_W, GTEX_H)
    nvgFillPaint(vg, gradInner)
    nvgFill(vg)

    nvgEndFrame(vg)
    nvgSetRenderTarget(vg, nil)
    return tex
end

-- ──────────────────────────────────────────────────────────────────────────────
-- 初始化（在 Start() 的 InitNanoVG 后调用，贴图立即生成）
-- ──────────────────────────────────────────────────────────────────────────────

---@param vg userdata 主 NanoVG context
function CardGlowManager.init(vg)
    glowTex_ = createGlowTex(vg)
end

-- ──────────────────────────────────────────────────────────────────────────────
-- 公共接口
-- ──────────────────────────────────────────────────────────────────────────────

--- 设置卡牌可打出状态
---@param card3d table Card3D 实例
---@param playable boolean
function CardGlowManager.setPlayable(card3d, playable)
    -- 从列表移除（避免重复）
    for i = #glowCards_, 1, -1 do
        if glowCards_[i] == card3d then
            table.remove(glowCards_, i)
        end
    end
    -- 首次激活时注入柔边贴图
    if playable and glowTex_ then
        card3d:setGlowTex(glowTex_)
    end
    card3d:applyGlow(playable)
    if playable then
        table.insert(glowCards_, card3d)
    end
end

--- 清除所有光效（阶段结束或清场时调用）
function CardGlowManager.clearAll()
    for _, card3d in ipairs(glowCards_) do
        card3d:applyGlow(false)
    end
    glowCards_ = {}
end

--- 每帧调用，驱动呼吸脉冲动画
---@param dt number
function CardGlowManager.update(dt)
    time_ = time_ + dt
    for _, card3d in ipairs(glowCards_) do
        card3d:updateGlow(time_)
    end
end

return CardGlowManager

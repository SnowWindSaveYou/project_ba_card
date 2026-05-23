-- ============================================================================
-- UI/Theme.lua - 全局色彩常量
-- Blue Archive 风格：亮底 + 马卡龙色系 + 圆润清爽
-- ============================================================================

local Theme = {}

-- ============================================================================
-- 核心色板（NanoVG RGBA 值）
-- ============================================================================

-- 背景 / 底色
Theme.BG_BASE      = { r = 239, g = 243, b = 251 }  -- 浅蓝白底 (#EFF3FB)
Theme.BG_PANEL     = { r = 255, g = 255, b = 255 }  -- 纯白面板 (#FFFFFF)
Theme.BG_CARD      = { r = 245, g = 248, b = 255 }  -- 卡面底色 (#F5F8FF)

-- 别名（向后兼容）
Theme.BG_DARK      = Theme.BG_BASE
Theme.BG_PANEL_ALT = { r = 240, g = 244, b = 255 }  -- 淡蓝面板（区分层级）

-- 珊瑚红（攻击 / 伤害 / 对手）
Theme.RED          = { r = 255, g = 107, b = 107 }  -- 珊瑚红 (#FF6B6B)
Theme.RED_BRIGHT   = { r = 255, g = 142, b = 142 }  -- 亮珊瑚 (#FF8E8E)
Theme.RED_DIM      = { r = 224, g = 85,  b = 85  }  -- 深珊瑚 (#E05555)

-- 薄荷绿（防御 / 格挡 / 生命 / 玩家）
Theme.GREEN        = { r = 82,  g = 200, b = 160 }  -- 薄荷 (#52C8A0)
Theme.GREEN_BRIGHT = { r = 112, g = 222, b = 184 }  -- 亮薄荷 (#70DEB8)
Theme.GREEN_DIM    = { r = 61,  g = 171, b = 136 }  -- 深薄荷 (#3DAB88)

-- 暖黄（强调 / 特殊 / 高光）
Theme.GOLD         = { r = 255, g = 209, b = 102 }  -- 暖黄 (#FFD166)
Theme.GOLD_BRIGHT  = { r = 255, g = 224, b = 138 }  -- 亮黄 (#FFE08A)
Theme.GOLD_DIM     = { r = 232, g = 184, b = 75  }  -- 深黄 (#E8B84B)

-- 深蓝（主文本 / 标题）
Theme.TEXT_PRIMARY   = { r = 45,  g = 53,  b = 97  }  -- 深藏青 (#2D3561)
Theme.TEXT_SECONDARY = { r = 107, g = 122, b = 157 }  -- 蓝灰 (#6B7A9D)
Theme.TEXT_DIM       = { r = 160, g = 174, b = 192 }  -- 浅蓝灰 (#A0AEC0)

-- 功能色
Theme.BLUE         = { r = 91,  g = 156, b = 246 }  -- 蔚蓝 (#5B9CF6)
Theme.ORANGE       = { r = 255, g = 159, b = 67  }  -- 暖橙 (#FF9F43)
Theme.PURPLE       = { r = 167, g = 139, b = 250 }  -- 薰衣草紫 (#A78BFA)

-- ============================================================================
-- 3D 场景色板（引擎 Color 值，0~1）
-- ============================================================================

-- 牌桌（改为柔和的浅蓝灰色调）
Theme.TABLE_SURFACE  = Color(0.22, 0.26, 0.38, 1.0)   -- 深蓝灰桌面
Theme.TABLE_WOOD     = Color(0.30, 0.34, 0.48, 1.0)   -- 蓝灰边框
Theme.TABLE_GILT     = Color(0.55, 0.72, 0.98, 1.0)   -- 浅蓝高光线条

-- 区域标记（低透明度，融入桌面）
Theme.ZONE_CHAIN     = Color(1.0,  0.42, 0.42, 0.10)   -- 珊瑚红暗影
Theme.ZONE_DECK      = Color(0.36, 0.61, 0.96, 0.12)   -- 蓝色暗影
Theme.ZONE_ARSENAL   = Color(1.0,  0.82, 0.40, 0.10)   -- 暖黄暗影

-- 分隔线
Theme.DIVIDER        = Color(0.36, 0.61, 0.96, 0.20)   -- 蓝色分隔线

-- ============================================================================
-- 辅助方法
-- ============================================================================

--- 返回 NanoVG RGBA 颜色（带可选 alpha）
---@param c table { r, g, b } 主题色
---@param a number|nil alpha 0~255，默认 255
---@return userdata nvgRGBA
function Theme.rgba(c, a)
    return nvgRGBA(c.r, c.g, c.b, a or 255)
end

--- 返回 NanoVG RGBA 颜色（alpha 为 0~1 浮点）
---@param c table { r, g, b } 主题色
---@param a number|nil alpha 0~1，默认 1.0
---@return userdata nvgRGBAf
function Theme.rgbaf(c, a)
    return nvgRGBA(c.r, c.g, c.b, math.floor((a or 1.0) * 255))
end

return Theme

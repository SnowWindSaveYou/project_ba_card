"""
卡牌矢量素材生成器
用 Pillow 绘制精确几何图形，4x 超采样抗锯齿，导出 PNG 到 assets/image/

素材清单:
  card_border_mask.png   — 粗圆角边框形状 (白色, 内外透明)
  card_art_clip.png      — 圆角矩形内区填充 (白色, 四角透明)
  badge_attack.png       — 六边形 + 剑图标 (珊瑚红)        [保留兼容]
  badge_defense.png      — 六边形 + 盾图标 (天蓝)          [保留兼容]
  badge_cost.png         — 六边形 + 星图标 (紫罗兰)        [保留兼容]
  pitch_gem_red.png      — 菱形宝石 (红)
  pitch_gem_yellow.png   — 菱形宝石 (黄)
  pitch_gem_blue.png     — 菱形宝石 (蓝)
  name_strip.png         — 半透明暗色名条
  card_bottom_gradient.png — 底部暗色渐变遮罩 (下方不透明→上方透明)
  card_back_pattern.png  — 圆角卡背 (菱形暗纹 + 星形logo)
  overlay_<id>.png       — 全卡尺寸覆盖层 (徽章+数字+宝石，解决小平面消失问题)
"""

from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageFont
import math
import os
import json

# ============================================================================
# 配置
# ============================================================================
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "image")
os.makedirs(OUT_DIR, exist_ok=True)

SS = 4  # 超采样倍数

# 卡牌最终尺寸
CARD_W, CARD_H = 504, 704
BORDER_T = 24          # 边框厚度 (最终像素)
RADIUS_OUTER = 36      # 外圆角半径
RADIUS_INNER = 22      # 内圆角半径

# 徽章最终尺寸
BADGE_SIZE = 160

# 宝石最终尺寸
GEM_SIZE = 96

# 名条最终尺寸
STRIP_W, STRIP_H = 440, 56

# 颜色
COST_COLOR    = (150, 90, 220, 255)
POWER_COLOR   = (235, 90, 95, 255)
DEFENSE_COLOR = (85, 165, 245, 255)
WHITE         = (255, 255, 255, 255)
TRANSPARENT   = (0, 0, 0, 0)


def save_ss(img, name, final_size):
    """超采样缩放并保存"""
    result = img.resize(final_size, Image.LANCZOS)
    path = os.path.join(OUT_DIR, name)
    result.save(path)
    print(f"  -> {name}  ({final_size[0]}x{final_size[1]})")
    return path


# ============================================================================
# 1. 卡牌边框 mask
# ============================================================================
def gen_border_mask():
    W, H = CARD_W * SS, CARD_H * SS
    border = BORDER_T * SS
    r_out = RADIUS_OUTER * SS
    r_in = RADIUS_INNER * SS

    outer = Image.new('L', (W, H), 0)
    ImageDraw.Draw(outer).rounded_rectangle(
        [0, 0, W - 1, H - 1], radius=r_out, fill=255)

    inner = Image.new('L', (W, H), 0)
    ImageDraw.Draw(inner).rounded_rectangle(
        [border, border, W - 1 - border, H - 1 - border], radius=r_in, fill=255)

    mask = ImageChops.subtract(outer, inner)

    img = Image.new('RGBA', (W, H), TRANSPARENT)
    white_layer = Image.new('RGBA', (W, H), WHITE)
    img = Image.composite(white_layer, img, mask)

    save_ss(img, "card_border_mask.png", (CARD_W, CARD_H))


# ============================================================================
# 2. 插画裁剪 mask (内区填白，四角透明)
# ============================================================================
def gen_art_clip():
    W, H = CARD_W * SS, CARD_H * SS
    border = BORDER_T * SS
    r_in = RADIUS_INNER * SS

    mask = Image.new('L', (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [border, border, W - 1 - border, H - 1 - border], radius=r_in, fill=255)

    img = Image.new('RGBA', (W, H), TRANSPARENT)
    white_layer = Image.new('RGBA', (W, H), WHITE)
    img = Image.composite(white_layer, img, mask)

    save_ss(img, "card_art_clip.png", (CARD_W, CARD_H))


# ============================================================================
# 3-5. 六边形徽章
# ============================================================================
def hex_points(cx, cy, r, flat_top=False):
    """正六边形顶点 (默认尖顶)"""
    offset = 0 if not flat_top else 30
    return [(cx + r * math.cos(math.radians(60 * i - 90 + offset)),
             cy + r * math.sin(math.radians(60 * i - 90 + offset)))
            for i in range(6)]


def draw_sword_icon(draw, cx, cy, s, color):
    """剑图标"""
    lw = max(2, int(s * 0.06))  # 线宽

    # 剑身 (竖线，粗)
    bw = s * 0.055
    draw.rectangle([cx - bw, cy - s * 0.32, cx + bw, cy + s * 0.12], fill=color)

    # 剑尖 (三角形)
    draw.polygon([
        (cx, cy - s * 0.40),
        (cx - bw * 1.8, cy - s * 0.28),
        (cx + bw * 1.8, cy - s * 0.28),
    ], fill=color)

    # 护手 (横条)
    gw = s * 0.22
    gh = s * 0.045
    draw.rounded_rectangle(
        [cx - gw, cy + s * 0.10, cx + gw, cy + s * 0.10 + gh],
        radius=int(gh * 0.4), fill=color)

    # 握柄
    hw = s * 0.04
    draw.rectangle([cx - hw, cy + s * 0.15, cx + hw, cy + s * 0.30], fill=color)

    # 柄头 (小圆)
    pr = s * 0.05
    draw.ellipse([cx - pr, cy + s * 0.29, cx + pr, cy + s * 0.29 + pr * 2], fill=color)


def draw_shield_icon(draw, cx, cy, s, color):
    """盾牌图标"""
    # 盾形 = 上方圆弧矩形 + 下方尖角
    sw, sh = s * 0.28, s * 0.22
    # 上半部 (圆角矩形)
    draw.rounded_rectangle(
        [cx - sw, cy - sh, cx + sw, cy + sh * 0.3],
        radius=int(sw * 0.3), fill=color)
    # 下半尖角
    draw.polygon([
        (cx - sw, cy + sh * 0.1),
        (cx + sw, cy + sh * 0.1),
        (cx, cy + sh * 1.2),
    ], fill=color)


def draw_star_icon(draw, cx, cy, s, color):
    """四角星图标 (Cost 用)"""
    # 竖菱形
    draw.polygon([
        (cx, cy - s * 0.30),
        (cx + s * 0.10, cy),
        (cx, cy + s * 0.30),
        (cx - s * 0.10, cy),
    ], fill=color)
    # 横菱形
    draw.polygon([
        (cx, cy - s * 0.10),
        (cx + s * 0.30, cy),
        (cx, cy + s * 0.10),
        (cx - s * 0.30, cy),
    ], fill=color)
    # 中心亮点
    cr = s * 0.06
    draw.ellipse([cx - cr, cy - cr, cx + cr, cy + cr],
                 fill=(255, 255, 255, 200))


def gen_badge(name, base_color, icon_func):
    S = BADGE_SIZE * SS
    img = Image.new('RGBA', (S, S), TRANSPARENT)
    cx, cy = S // 2, S // 2
    hex_r = S * 0.42

    # 阴影层
    shadow = Image.new('RGBA', (S, S), TRANSPARENT)
    sd = ImageDraw.Draw(shadow)
    pts = hex_points(cx, cy + SS * 4, hex_r + SS * 2)
    sd.polygon(pts, fill=(0, 0, 0, 50))
    shadow = shadow.filter(ImageFilter.GaussianBlur(SS * 5))
    img = Image.alpha_composite(img, shadow)

    draw = ImageDraw.Draw(img)

    # 六边形底色
    pts = hex_points(cx, cy, hex_r)
    draw.polygon(pts, fill=base_color)

    # 顶部高光椭圆
    hl = Image.new('RGBA', (S, S), TRANSPARENT)
    hd = ImageDraw.Draw(hl)
    ew, eh = hex_r * 0.7, hex_r * 0.45
    hd.ellipse([cx - ew, cy - hex_r * 0.85, cx + ew, cy - hex_r * 0.85 + eh],
               fill=(255, 255, 255, 55))
    img = Image.alpha_composite(img, hl)

    # 底部暗角
    dk = Image.new('RGBA', (S, S), TRANSPARENT)
    dd = ImageDraw.Draw(dk)
    dd.ellipse([cx - ew, cy + hex_r * 0.25, cx + ew, cy + hex_r * 0.25 + eh],
               fill=(0, 0, 0, 35))
    img = Image.alpha_composite(img, dk)

    # 图标 — 偏移到右下角，缩小尺寸，避免与中心数字重叠
    draw = ImageDraw.Draw(img)
    icon_func(draw, cx + S * 0.14, cy + S * 0.16, S * 0.40, (255, 255, 255, 140))

    # 白色描边
    draw.polygon(hex_points(cx, cy, hex_r), outline=(255, 255, 255, 160), width=max(1, SS))

    save_ss(img, f"badge_{name}.png", (BADGE_SIZE, BADGE_SIZE))


# ============================================================================
# 6. Pitch 宝石
# ============================================================================
def gen_pitch_gem(name, color):
    S = GEM_SIZE * SS
    img = Image.new('RGBA', (S, S), TRANSPARENT)
    draw = ImageDraw.Draw(img)
    cx, cy = S // 2, S // 2

    gem_h = S * 0.40
    gem_w = S * 0.26

    pts = [
        (cx, cy - gem_h),      # top
        (cx + gem_w, cy),      # right
        (cx, cy + gem_h),      # bottom
        (cx - gem_w, cy),      # left
    ]

    # 阴影
    shadow_pts = [(p[0] + SS * 2, p[1] + SS * 3) for p in pts]
    draw.polygon(shadow_pts, fill=(0, 0, 0, 35))

    # 宝石主体
    draw.polygon(pts, fill=color)

    # 上半切面高光
    top_pts = [pts[0], pts[1], (cx, cy * 1.02), pts[3]]
    top_hl = Image.new('RGBA', (S, S), TRANSPARENT)
    ImageDraw.Draw(top_hl).polygon(top_pts, fill=(255, 255, 255, 50))
    img = Image.alpha_composite(img, top_hl)

    # 中心高光点
    draw = ImageDraw.Draw(img)
    hr = S * 0.06
    hcy = cy - gem_h * 0.3
    draw.ellipse([cx - hr, hcy - hr, cx + hr, hcy + hr], fill=(255, 255, 255, 200))

    # 描边
    draw.polygon(pts, outline=(255, 255, 255, 150), width=max(1, SS))

    save_ss(img, f"pitch_gem_{name}.png", (GEM_SIZE, GEM_SIZE))


# ============================================================================
# 7. 名条 (半透明暗色胶囊)
# ============================================================================
def gen_name_strip():
    W, H = STRIP_W * SS, STRIP_H * SS
    img = Image.new('RGBA', (W, H), TRANSPARENT)
    draw = ImageDraw.Draw(img)

    r = H // 2  # 完全胶囊形
    draw.rounded_rectangle([0, 0, W - 1, H - 1], radius=r,
                           fill=(15, 15, 25, 150))

    # 顶部高光线
    draw.rounded_rectangle([SS * 2, SS, W - 1 - SS * 2, H // 4], radius=r // 2,
                           fill=(255, 255, 255, 18))

    save_ss(img, "name_strip.png", (STRIP_W, STRIP_H))


# ============================================================================
# 8. 底部渐变遮罩 (从下方不透明深色渐变到上方全透明)
# ============================================================================
def gen_bottom_gradient():
    W, H = CARD_W * SS, CARD_H * SS
    border = BORDER_T * SS
    r_in = RADIUS_INNER * SS

    img = Image.new('RGBA', (W, H), TRANSPARENT)
    draw = ImageDraw.Draw(img)

    # 渐变区域：底部 38%
    grad_h = int(H * 0.38)
    grad_start = H - grad_h

    for y in range(grad_start, H):
        t = (y - grad_start) / grad_h  # 0→1
        alpha = int(t * t * 190)        # 二次缓入，底部最深 alpha≈190
        draw.line([(0, y), (W - 1, y)], fill=(10, 12, 20, alpha))

    # 用内边框圆角裁剪（与插画区域对齐）
    mask = Image.new('L', (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [border, border, W - 1 - border, H - 1 - border], radius=r_in, fill=255)

    result = Image.new('RGBA', (W, H), TRANSPARENT)
    result = Image.composite(img, result, mask)

    save_ss(result, "card_bottom_gradient.png", (CARD_W, CARD_H))


# ============================================================================
# 9. 卡背 (菱形暗纹 + 星形 logo + 圆角)
# ============================================================================
def gen_card_back():
    W, H = CARD_W * SS, CARD_H * SS
    r_out = RADIUS_OUTER * SS

    # 底色
    bg = Image.new('RGBA', (W, H), (30, 40, 75, 255))
    draw = ImageDraw.Draw(bg)

    # 45° 菱形网格暗纹
    grid_step = SS * 28
    line_color = (45, 55, 90, 255)
    lw = max(1, SS)
    for offset in range(-H, W + H, grid_step):
        draw.line([(offset, 0), (offset + H, H)], fill=line_color, width=lw)
        draw.line([(offset, H), (offset + H, 0)], fill=line_color, width=lw)

    # 中心星形 logo
    cx, cy = W // 2, H // 2
    star_r = W * 0.18
    star_color = (255, 255, 255, 30)
    # 8 角星
    for i in range(4):
        angle = math.radians(45 * i)
        dx, dy = math.cos(angle), math.sin(angle)
        # 长线
        draw.line(
            [(cx - dx * star_r, cy - dy * star_r),
             (cx + dx * star_r, cy + dy * star_r)],
            fill=star_color, width=SS * 3)
    # 中心光点
    cr = star_r * 0.15
    draw.ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=(255, 255, 255, 45))

    # 四角小星星装饰
    for sx, sy in [(0.15, 0.10), (0.85, 0.10), (0.15, 0.90), (0.85, 0.90)]:
        scx, scy = int(W * sx), int(H * sy)
        sr = SS * 8
        for i in range(4):
            a = math.radians(45 * i)
            ddx, ddy = math.cos(a), math.sin(a)
            draw.line([(scx - ddx * sr, scy - ddy * sr),
                       (scx + ddx * sr, scy + ddy * sr)],
                      fill=(255, 255, 255, 25), width=max(1, SS))

    # 细白色圆角边框
    border_w = SS * 2
    draw.rounded_rectangle(
        [border_w, border_w, W - 1 - border_w, H - 1 - border_w],
        radius=r_out - border_w,
        outline=(255, 255, 255, 50), width=SS * 2)

    # 圆角裁剪
    mask = Image.new('L', (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, W - 1, H - 1], radius=r_out, fill=255)
    result = Image.new('RGBA', (W, H), TRANSPARENT)
    result = Image.composite(bg, result, mask)

    save_ss(result, "card_back_pattern.png", (CARD_W, CARD_H))


# ============================================================================
# 10. 全卡覆盖层 (徽章 + 数字 + 宝石 合成在全卡尺寸画布上)
# 解决小平面子节点在 Octree 中消失的问题
# ============================================================================

# 覆盖层中的徽章/宝石位置（最终像素坐标，基于 504x704）
# 与 Card3D.lua 的本地坐标对应:
#   local pos = {x=-0.43, z=0.43} 对应左上角
#   本地坐标 [-0.5, 0.5] 映射到像素 [0, CARD_W/CARD_H]
#   px = (x + 0.5) * CARD_W, py = (0.5 - z) * CARD_H   (z 向上, 像素 y 向下)

def local_to_pixel(lx, lz):
    """Card3D 本地坐标 → 覆盖层像素坐标"""
    px = (lx + 0.5) * CARD_W
    py = (0.5 - lz) * CARD_H
    return int(px), int(py)

OVERLAY_BADGE_SIZE = 100   # 覆盖层上每个徽章的直径（像素）
OVERLAY_GEM_SIZE = 72      # 覆盖层上宝石的直径（像素）

# 对应 Card3D.lua 中的位置常量
OV_BADGE_POS = {
    "cost":    (-0.43,  0.43),   # 左上
    "power":   (-0.43, -0.43),   # 左下
    "defense": ( 0.43, -0.43),   # 右下
}
OV_GEM_POS = (0.43, 0.43)       # 右上

BADGE_TYPES = {
    "cost":    {"color": COST_COLOR,    "icon": draw_star_icon},
    "power":   {"color": POWER_COLOR,   "icon": draw_sword_icon},
    "defense": {"color": DEFENSE_COLOR, "icon": draw_shield_icon},
}

GEM_COLORS = {
    1: (235, 75, 80, 255),    # red
    2: (245, 200, 60, 255),   # yellow
    3: (80, 140, 235, 255),   # blue
}

# 字体路径（按优先级排列）
FONT_PATHS = [
    os.path.join(os.path.dirname(__file__), "..", "..", "assets", "Fonts", "MiSans-Regular.ttf"),
    "/home/Maker/.claude/skills/ui-brawlforge/fonts/NotoSansSC-Black.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]


def _get_font(size):
    """获取字体，优先使用支持中文的字体"""
    for fp in FONT_PATHS:
        if os.path.exists(fp):
            return ImageFont.truetype(fp, size)
    return ImageFont.load_default()


def _draw_hex_badge(img, cx, cy, size, base_color, icon_func):
    """在全卡画布上绘制一个六边形徽章"""
    s = size * SS
    # 创建临时徽章图像
    badge = Image.new('RGBA', (s, s), TRANSPARENT)
    bcx, bcy = s // 2, s // 2
    hex_r = s * 0.42

    # 阴影
    shadow = Image.new('RGBA', (s, s), TRANSPARENT)
    sd = ImageDraw.Draw(shadow)
    pts = hex_points(bcx, bcy + SS * 2, hex_r + SS)
    sd.polygon(pts, fill=(0, 0, 0, 50))
    shadow = shadow.filter(ImageFilter.GaussianBlur(SS * 3))
    badge = Image.alpha_composite(badge, shadow)

    draw = ImageDraw.Draw(badge)
    pts = hex_points(bcx, bcy, hex_r)
    draw.polygon(pts, fill=base_color)

    # 高光
    hl = Image.new('RGBA', (s, s), TRANSPARENT)
    hd = ImageDraw.Draw(hl)
    ew, eh = hex_r * 0.7, hex_r * 0.45
    hd.ellipse([bcx - ew, bcy - hex_r * 0.85, bcx + ew, bcy - hex_r * 0.85 + eh],
               fill=(255, 255, 255, 55))
    badge = Image.alpha_composite(badge, hl)

    # 图标（右下偏移）
    draw = ImageDraw.Draw(badge)
    icon_func(draw, bcx + s * 0.14, bcy + s * 0.16, s * 0.40, (255, 255, 255, 140))

    # 描边
    draw.polygon(hex_points(bcx, bcy, hex_r), outline=(255, 255, 255, 160), width=max(1, SS))

    # 缩放到最终尺寸
    badge = badge.resize((size, size), Image.LANCZOS)

    # 粘贴到全卡画布
    paste_x = cx - size // 2
    paste_y = cy - size // 2
    img.alpha_composite(badge, (paste_x, paste_y))


def _draw_gem(img, cx, cy, size, color):
    """在全卡画布上绘制一颗菱形宝石"""
    s = size * SS
    gem = Image.new('RGBA', (s, s), TRANSPARENT)
    draw = ImageDraw.Draw(gem)
    gcx, gcy = s // 2, s // 2

    gem_h = s * 0.40
    gem_w = s * 0.26

    pts = [
        (gcx, gcy - gem_h),
        (gcx + gem_w, gcy),
        (gcx, gcy + gem_h),
        (gcx - gem_w, gcy),
    ]
    draw.polygon(pts, fill=color)

    # 高光
    top_pts = [pts[0], pts[1], (gcx, gcy * 1.02), pts[3]]
    top_hl = Image.new('RGBA', (s, s), TRANSPARENT)
    ImageDraw.Draw(top_hl).polygon(top_pts, fill=(255, 255, 255, 50))
    gem = Image.alpha_composite(gem, top_hl)

    draw = ImageDraw.Draw(gem)
    hr = s * 0.06
    hcy = gcy - gem_h * 0.3
    draw.ellipse([gcx - hr, hcy - hr, gcx + hr, hcy + hr], fill=(255, 255, 255, 200))
    draw.polygon(pts, outline=(255, 255, 255, 150), width=max(1, SS))

    gem = gem.resize((size, size), Image.LANCZOS)
    img.alpha_composite(gem, (cx - size // 2, cy - size // 2))


def _draw_number(img, cx, cy, text, font_size, color=(255, 255, 255, 255)):
    """在全卡画布上绘制居中数字（带阴影）"""
    font = _get_font(font_size)

    # 先画阴影
    shadow_layer = Image.new('RGBA', img.size, TRANSPARENT)
    sd = ImageDraw.Draw(shadow_layer)
    bbox = sd.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = cx - tw // 2
    ty = cy - th // 2 - bbox[1]  # 修正 baseline 偏移
    sd.text((tx + 2, ty + 2), text, fill=(0, 0, 0, 130), font=font)
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(2))
    img.alpha_composite(shadow_layer)

    # 再画文字
    draw = ImageDraw.Draw(img)
    draw.text((tx, ty), text, fill=color, font=font)


def _draw_name_text(img, cx, cy, text, font_size, color=(240, 240, 240, 255)):
    """在全卡画布上绘制居中卡名（带阴影）"""
    font = _get_font(font_size)

    shadow_layer = Image.new('RGBA', img.size, TRANSPARENT)
    sd = ImageDraw.Draw(shadow_layer)
    bbox = sd.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = cx - tw // 2
    ty = cy - th // 2 - bbox[1]
    sd.text((tx + 1, ty + 1), text, fill=(0, 0, 0, 150), font=font)
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(1.5))
    img.alpha_composite(shadow_layer)

    draw = ImageDraw.Draw(img)
    draw.text((tx, ty), text, fill=color, font=font)


def gen_card_overlay(card_id, cost, power, defense, pitch, name=""):
    """
    生成全卡尺寸覆盖层 (504×704 透明 PNG)
    所有徽章、数字、宝石、卡名都合成在一张纹理中
    """
    img = Image.new('RGBA', (CARD_W, CARD_H), TRANSPARENT)

    # --- 绘制三个角落徽章 ---
    badge_values = {
        "cost": cost,
        "power": power,
        "defense": defense,
    }

    for badge_key, (lx, lz) in OV_BADGE_POS.items():
        px, py = local_to_pixel(lx, lz)
        info = BADGE_TYPES[badge_key]
        value = badge_values[badge_key]

        # 只有有值(>0)的徽章才绘制；cost 总是显示
        if value > 0 or badge_key == "cost":
            _draw_hex_badge(img, px, py, OVERLAY_BADGE_SIZE, info["color"], info["icon"])
            _draw_number(img, px, py - 4, str(value), 42)

    # --- 绘制右上角 Pitch 宝石 ---
    if pitch in GEM_COLORS:
        gx, gy = local_to_pixel(*OV_GEM_POS)
        _draw_gem(img, gx, gy, OVERLAY_GEM_SIZE, GEM_COLORS[pitch])

    # --- 绘制卡名 ---
    if name:
        # 名条位置：Card3D.lua NAME_POS_Z = -0.36
        nx, ny = local_to_pixel(0, -0.36)
        _draw_name_text(img, nx, ny, name, 28)

    filename = f"overlay_{card_id}.png"
    path = os.path.join(OUT_DIR, filename)
    img.save(path)
    print(f"  -> {filename}  ({CARD_W}x{CARD_H})")
    return path


# ============================================================================
# 卡牌数据定义 (与 main.lua 的 demoCards 保持一致)
# ============================================================================
DEMO_CARDS = [
    {"id": "dori_slash_r",  "name": "斩击",     "cost": 1, "power": 6, "defense": 3, "pitch": 1},
    {"id": "dori_slash_y",  "name": "斩击",     "cost": 1, "power": 5, "defense": 3, "pitch": 2},
    {"id": "dori_slash_b",  "name": "斩击",     "cost": 1, "power": 4, "defense": 3, "pitch": 3},
    {"id": "driving_blade", "name": "驱动之刃", "cost": 2, "power": 7, "defense": 3, "pitch": 1},
    {"id": "warrior_def_r", "name": "铁壁防御", "cost": 0, "power": 0, "defense": 5, "pitch": 1},
    {"id": "sigil_solace",  "name": "慰藉印记", "cost": 3, "power": 0, "defense": 4, "pitch": 3},
]


# ============================================================================
# Main
# ============================================================================
if __name__ == "__main__":
    print("=== 卡牌矢量素材生成 ===\n")

    print("[1/9] 边框 mask...")
    gen_border_mask()

    print("[2/9] 插画裁剪 mask...")
    gen_art_clip()

    print("[3/9] 攻击徽章...")
    gen_badge("attack", POWER_COLOR, draw_sword_icon)

    print("[4/9] 防御徽章...")
    gen_badge("defense", DEFENSE_COLOR, draw_shield_icon)

    print("[5/9] 费用徽章...")
    gen_badge("cost", COST_COLOR, draw_star_icon)

    print("[6/9] Pitch 宝石 x3...")
    gen_pitch_gem("red", (235, 75, 80, 255))
    gen_pitch_gem("yellow", (245, 200, 60, 255))
    gen_pitch_gem("blue", (80, 140, 235, 255))

    print("[7/9] 名条...")
    gen_name_strip()

    print("[8/9] 底部渐变 + 卡背...")
    gen_bottom_gradient()
    gen_card_back()

    print("[9/9] 全卡覆盖层 (徽章+数字+宝石)...")
    for card in DEMO_CARDS:
        gen_card_overlay(card["id"], card["cost"], card["power"],
                         card["defense"], card["pitch"], card["name"])

    print("\n=== 全部完成! ===")

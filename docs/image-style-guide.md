# 图片生成风格基底

## BA 风格基底关键词

```
Blue Archive style, high-key lighting, soft pastel, minimal cel-shading,
cool-toned soft shadows, translucent wire-frame halo, airy atmosphere,
clean lineart, bokeh background, luminous skin,
no UI, no text, no frame, no border, character illustration only
```

### 关键词含义说明

| 关键词 | 作用 |
|--------|------|
| `Blue Archive style` | 触发整体 BA 画风 |
| `high-key lighting` | 高调曝光，整体偏亮白 |
| `soft pastel` | 粉彩色调，不刺眼 |
| `minimal cel-shading` | 极简赛璐珞，阴影极浅 |
| `cool-toned soft shadows` | 阴影用冷色（浅蓝/浅灰），不用深色 |
| `translucent wire-frame halo` | 细线几何光环，半透明发光 |
| `airy atmosphere` | 空气感，整体通透轻盈 |
| `clean lineart` | 细腻均匀的轮廓线 |
| `bokeh background` | 背景虚化，有景深感 |
| `luminous skin` | 皮肤白皙通透，近乎发光 |
| `no UI, no text, no frame, no border` | 禁止生成 UI 元素 |
| `character illustration only` | 纯角色立绘 |

---

## 角色变量（追加在基底后）

基于 `docs/characters.md` v0.2 精确描述：

| 角色 | 追加关键词 |
|------|-----------|
| 一之濑枫（剑道） | `long straight black hair with subtle inner red highlights, deep red maple leaf hair clip on left ear, steel blue eyes with faint golden ring, navy sailor school uniform with cherry blossom embroidery, right hand cotton wrist wrap, holding shinai` |
| 夏琳（跆拳道） | `chestnut brown hair in low double ponytails with white ribbon bows, upturned blue eyes, white cropped DASH sports top with blue trim, left ankle strap, blue star badge on chest, dynamic taekwondo kick pose` |
| 云柔（太极） | `pure white silky hair with faint silver sheen, white jade hairpin half-loose updo, pale ink-green calm eyes, tall graceful figure, moon white Chinese hanfu with cloud-shaped buttons, water ink gradient sleeves, smoke grey lantern pants, wooden bead bracelet on left wrist, tai chi open palm serene stance, flowing sleeves` |
| 铁拳小桃（拳击） | `pink short high pigtails with thick blunt bangs, rose red large eyes, 148cm petite figure, red-black cross-strap sports bra, distressed denim hot shorts, red boxing gloves with white MOMO bandages, peach stud earrings, fearless fighting stance` |

---

## 已生成的英雄人设图

### v4（当前使用版，GPT 模型 + 具体构图描述）

| 英雄 | 文件路径 |
|------|---------|
| 一之濑枫 | `assets/image/hero_kaede_v4_20260522195237.png` |
| 夏琳 | `assets/image/hero_xia_lin_v4_20260522195334.png` |
| 云柔 | `assets/image/hero_yun_rou_v4_20260522195242.png` |
| 铁拳小桃 | `assets/image/hero_xiao_tao_v4b_20260522195237.png` |

### v1-v3（已废弃）

| 英雄 | 文件路径 |
|------|---------|
| 一之濑枫 | `assets/image/hero_kaede_20260522183130.png` |
| 夏琳 | `assets/image/hero_xia_lin_20260522183204.png` |
| 云柔 | `assets/image/hero_yun_rou_20260522183131.png` |
| 铁拳小桃 | `assets/image/hero_xiao_tao_20260522183131.png` |

## 已生成的通用占位图

| 用途 | 文件路径 |
|------|---------|
| 剑道（war_*） | `assets/image/ba_placeholder_1_20260522181341.png` |
| 拳击（bru_*） | `assets/image/ba_placeholder_2_20260522181936.png` |
| 跆拳道（nin_*） | `assets/image/ba_placeholder_3_20260522181340.png` |
| 太极（gua_*） | `assets/image/ba_placeholder_4_20260522181427.png` |
| 通用（gen_*） | `assets/image/ba_placeholder_5_20260522181415.png` |
| 专属卡（spec_*） | `assets/image/ba_placeholder_6_20260522181353.png` |

---

---

## 游戏背景图风格：矢量街机 + 蔚蓝档案色调

### 核心定位

> **矢量底层（flat vector）+ 千禧街机要素（Y2K arcade）+ 蔚蓝档案色调（Blue Archive tone）**

两层叠加逻辑：
- 基础层：大色块、有机圆形、平涂渐变、干净边缘 → 来自矢量插画
- 装饰层：像素十字星、等距砖块平台、半调网点、厚描边 → 来自千禧街机游戏

### 可复用 Prompt 模板

```
wide horizontal city skyline poster,
flat vector illustration style, Y2K arcade aesthetic, thick outline vector shapes,
isometric and layered city buildings silhouette, large smooth organic blob shapes as background elements,
color tone inspired by Blue Archive game: vivid sky blue, warm white, golden sunlight yellow, soft coral,
airy and bright high saturation pastels, clean summer daylight atmosphere, cheerful and youthful energy,
no doodles, no characters, no crayon texture, pure clean vector arcade art
```

### 关键词拆解

| 关键词 | 作用 |
|--------|------|
| `flat vector illustration style` | 定义基础画风：扁平矢量 |
| `Y2K arcade aesthetic` | 引入千禧街机装饰要素 |
| `thick outline vector shapes` | 厚描边贴纸感 |
| `isometric and layered city buildings silhouette` | 等距城市轮廓，多层景深 |
| `large smooth organic blob shapes` | 大色块有机形状背景 |
| `color tone inspired by Blue Archive` | 色调锚点：明亮青春 |
| `vivid sky blue, warm white, golden sunlight yellow, soft coral` | 具体色彩定义 |
| `airy and bright high saturation pastels` | 通透感、高饱和粉彩 |
| `no crayon texture` | 排除蜡笔画风干扰 |

### 风格变量（可替换）

- **内容**：`city skyline` 可换 `beach`, `campus`, `rooftop`, `arcade hall` 等场景
- **色调**：`Blue Archive` 可换 `sunset warm orange`, `night neon`, `rainy cool grey` 等
- **装饰元素**（可追加）：doodle icons, pixel sparkles, halftone dot patches, cloud puffs

### 推荐参数

- 比例：`16:9`（横版背景）
- 尺寸：`1344x768`
- 模型：GPT

---

## 推荐参数

- 比例：`2:3`（卡牌竖版）
- 尺寸：`512x768`
- 模型：GPT

## 构图规范（重要）

**基底关键词必须完整保留**，构图描述追加在最后，不要替换基底。

| 规范 | 说明 |
|------|------|
| 景别 | 3/4 身（膝盖以上），不做极端特写 |
| 镜头角度 | 轻微仰角（camera slightly below eye level），增加气势 |
| 构图结构 | 基底 + 角色变量 + 构图追加词 |
| 光环 | `translucent wire-frame halo` 必须在基底中保留，不可删除 |

**追加构图词模板**（放在角色变量之后）：
```
3/4 body shot from knees up, slight low angle, subject centered, soft bokeh background
```

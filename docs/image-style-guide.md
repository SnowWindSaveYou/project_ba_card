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

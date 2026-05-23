# 《轻拳飞扬》开发进度追踪

> **项目代号**: Light Punch (轻拳飞扬)
> **引擎**: UrhoX (3D + NanoVG)
> **最后更新**: 2026-05-21

---

## 总览

| 指标       | 当前值           |
|-----------|-----------------|
| 总文件数   | 30 个 Lua 模块   |
| 总代码行数 | ~6,500 行        |
| 已完成步骤 | 5.5 / 7          |
| 当前阶段   | 游戏逻辑核心完成，GameController 桥接层 Phase 1 完成 |

---

## 七步实现计划

```
[██████████████████████████████░░░░] 79%  (5.5/7 步完成)
```

| 步骤 | 名称 | 状态 | 文件数 | 行数 |
|------|------|------|--------|------|
| 1 | 核心基建 | ✅ 完成 | 6 | 1,312 |
| 2 | 3D 卡牌 + Balatro 动效 | ✅ 完成 | 4 | 699 |
| 3 | 手牌布局 + 牌桌区域 | ✅ 完成 | 3 | 787 |
| 4 | NanoVG 全矢量 HUD | ✅ 完成 | 5 | 1,123 |
| 5 | 游戏逻辑 (FSM + 战斗链) | ✅ 完成 | 12 | ~2,580 |
| 6 | AI 对手 | ✅ 完成 | 1 | ~350 |
| 7 | 主菜单 + 英雄选择 | ⬚ 待开发 | — | — |

---

## 第五步模块清单 — 游戏逻辑层

| 文件 | 行数 | 职责 | 状态 |
|------|------|------|------|
| `Game/GameFSM.lua` | ~700 | 主状态机：15+ action 类型，完整回合生命周期 | ✅ 完整 |
| `Game/TurnPhase.lua` | ~30 | 回合阶段枚举 | ✅ 完整 |
| `Game/Player.lua` | ~530 | 玩家状态：life/hand/deck/graveyard/pitchZone/arsenal/equipment | ✅ 完整 |
| `Game/CombatChain.lua` | ~380 | 战斗链解算：多链路，Dominate 限制，combo 检查 | ✅ 完整 |
| `Game/EffectProcessor.lua` | ~490 | 效果处理管线：~25 原子效果，延迟效果，pendingBuff | ✅ 完整 |
| `Game/PitchSystem.lua` | ~220 | 充能系统：贪心+精确搜索，pitchAndPay 一步执行 | ✅ 完整 |
| `Game/ActionValidator.lua` | ~370 | 出牌合法性校验：12 种行动类型 | ✅ 完整 |
| `Game/EffectDefs.lua` | ~320 | 原子效果注册表：25 个效果处理函数 | ✅ 完整 |
| `Game/CustomHandlers.lua` | ~400 | 自定义处理器：4 英雄能力 + 4 武器 + crush 等 ~15 个 | ✅ 完整 |
| `Card/CardDB.lua` | ~1,300 | 卡牌数据库：80+ 张卡 (红/黄/蓝三色变体, per-color 精确) | ✅ 完整 |
| `Card/HeroData.lua` | ~300 | 4 英雄 + 武器 + 25 装备定义 | ✅ 完整 |
| `Card/CardData.lua` | ~150 | 卡牌数据结构 + 类型/关键词/稀有度枚举 | ✅ 完整 |

### 第六步 — AI

| 文件 | 行数 | 职责 | 状态 |
|------|------|------|------|
| `AI/AIPlayer.lua` | ~350 | 评分式 AI：攻击/防御/充能决策 | ✅ 基本可用 |

### 桥接层 — GameController (Phase 1)

| 文件 | 行数 | 职责 | 状态 |
|------|------|------|------|
| `Game/GameController.lua` | ~200 | FSM ↔ 视觉层桥接，11 个回调 | ✅ Phase 1 |

---

## 五阶段交互实现计划

> GameController 将 FSM 回调桥接到视觉层

| Phase | 名称 | 状态 | 内容 |
|-------|------|------|------|
| 1 | GameController 骨架 + main.lua 重构 | ✅ 完成 | 11 个回调桥接，FSM 驱动游戏流程 |
| 2 | 玩家 ACTION 阶段交互 | ⬚ 待开发 | 拖拽出牌 + 自动充能 + ActionBar |
| 3 | 防御 & 反应交互 | ⬚ 待开发 | 防御牌拖拽 + 护具点击 + 追击/闪避 |
| 4 | AI 回合可视化 | ⬚ 待开发 | AI 动作逐步播放动画 |
| 5 | 完善 | ⬚ 待开发 | 预备区、游戏结束、边界情况 |

---

## Bug 修复记录

| # | 严重度 | 描述 | 修复日期 | 文件 |
|---|--------|------|---------|------|
| 1 | 🔴 致命 | `applyDamageShield` 传入 CombatChain 表而非数字，导致崩溃 | 2026-05-20 | GameFSM.lua:843 |
| 2 | 🔴 严重 | AI 永不防御：`link.totalAttack` 字段不存在，应为 `link.attackPower` | 2026-05-20 | AIPlayer.lua:223,345 |
| 3 | 🔴 严重 | `PitchSystem.pitchAndPay` 忽略第4参数 `actualCost`，费用减免无效 | 2026-05-21 | PitchSystem.lua:200 |
| 4 | 🟡 中等 | `hero_bravo_dominate` pendingBuff 类型未在 `applyPendingBuffs` 中处理 | 2026-05-21 | EffectProcessor.lua:475 |
| 5 | 🟡 中等 | 4 张闪避牌防御值为 0（受流返打/化劲/铁壁/下潜闪避） | 2026-05-21 | CardDB.lua |
| 6 | 🟡 低 | `gen_drone_of_brutality` 缺少 cost 和 defense 字段 | 2026-05-21 | CardDB.lua |

---

## 机制审计摘要 (2026-05-21)

### 与 FAB 规则一致的核心机制 ✅

- 回合流程：抽牌→行动→结束
- 资源三用：出牌/防御/充能
- 充能值：红1/黄2/蓝3
- 战斗链：攻击→防御→反应→结算
- 预备区放牌
- Go Again / Dominate / Intimidate / Crush / Reprise / Combo

### 已实现关键词 (9/20+)

| 已实现 | 未实现 |
|--------|--------|
| go_again, dominate, intimidate, crush, reprise, combo, battleworn, blade_break, temper | piercing, overpower, stealth, ambush, phantasm, boost, blood_debt, 华丽连击, 破绽, 闪耀时刻, 应援 |

### 设计文档差异（暂保留 FAB 原版，后续对齐）

| 项目 | 设计文档 | 当前实现 (FAB) | 决策 |
|------|---------|---------------|------|
| 角色 HP | 枫20/夏琳18/云柔22/小桃19 | 全部 20 | 暂用 FAB |
| 英雄技能 | 设计文档自定义版本 | FAB 原版技能 | 暂用 FAB |
| 武器数值 | 设计文档自定义 | FAB 原版数值 | 暂用 FAB |
| 卡组大小 | 30 张 | 40 张 (Blitz) | 暂用 FAB |
| 同名牌上限 | 2 张 | 无校验 | 暂用 FAB |
| 护具名称/效果 | 设计文档自定义 | FAB 原版装备 | 暂用 FAB |
| 缺失关键词 | 11 个新/修改关键词 | 未实现 | 后续添加 |

### 已知待修复项（非 Bug，功能缺失）

- 充能牌回牌库底的**玩家排序**未实现（当前默认顺序）
- ~~辅助牌三色效果数值差异未实现~~ → ✅ 已在 M3.7 全部修正

### M3.7: 卡牌数值精确化 (2026-05-21)

**消除全部简化处理**，21 张卡的 per-color 差异已精确实现：

1. **tri() 增强**: 新增 `opts.defenses`/`opts.rarities`/`opts.amounts` 支持三色差异
2. **辅助牌 (6 张)**: war_sharpen_steel, war_driving_blade, war_warriors_valor, bru_awakening_bellow, bru_barraging_beatdown, bru_primeval_bellow — per-color buff amount
3. **闪避牌 (4 张)**: war_steelblade_shunt, gen_unmovable, gen_sink_below, gua_staunch_response — per-color defense
4. **追击牌 (5 张)**: war_overpower, war_ironsong_response, war_biting_blade, gen_pummel, gen_razor_reflex — per-color buff amount
5. **稀有度 (1 张)**: nin_open_the_center — Red=Common, Yellow/Blue=Rare
6. **生命恢复 (1 张)**: gen_sigil_of_solace — R:3, Y:2, B:1
7. **Aura 牌 (4 张)**: gen_nimblism, gen_sloggism, gua_emerging_power, gua_stonewall_confidence — per-color buff amount

**特殊处理**: war_overpower, war_biting_blade, bru_primeval_bellow 因 effects 内含多个不同 amount 字段，改用手动 `do...end` 注册块，避免 amounts 机制误替换

---

## 模块清单（完整）

### Core — 核心引擎 (3 文件, 562 行)

| 文件 | 行数 | 职责 |
|------|------|------|
| `Core/Tween.lua` | 281 | 补间动画引擎 |
| `Core/Easing.lua` | 208 | 30+ 缓动曲线 |
| `Core/Timer.lua` | 73 | 延时/重复调度器 |

### Scene — 3D 场景 (2 文件, 256 行)

| 文件 | 行数 | 职责 |
|------|------|------|
| `Scene/TableScene.lua` | 170 | 牌桌场景 |
| `Scene/CameraRig.lua` | 86 | 固定俯视相机 |

### Card — 卡牌数据与实体 (4 文件, ~1,060 行)

| 文件 | 行数 | 职责 |
|------|------|------|
| `Card/CardData.lua` | ~150 | 卡牌数据结构定义 |
| `Card/Card3D.lua` | 171 | PBR 3D 卡牌实体 |
| `Card/CardDB.lua` | ~1,300 | 完整卡牌数据库 (80+张, tri() 增强 + per-color 精确) |
| `Card/HeroData.lua` | ~300 | 英雄/武器/装备数据 |

### Anim — 动画系统 (1 文件, 297 行)

| 文件 | 行数 | 职责 |
|------|------|------|
| `Anim/CardAnimator.lua` | 297 | 6 种 Balatro 风格卡牌动效 |

### Input — 输入处理 (1 文件, 154 行)

| 文件 | 行数 | 职责 |
|------|------|------|
| `Input/CardPicker.lua` | 154 | Octree 射线拾取 |

### Layout — 布局管理 (3 文件, 787 行)

| 文件 | 行数 | 职责 |
|------|------|------|
| `Layout/HandFan.lua` | 270 | 弧形手牌扇面 |
| `Layout/ZoneLayout.lua` | 313 | 16 区域管理 |
| `Layout/DeckStack.lua` | 204 | 牌堆视觉叠放 |

### UI — NanoVG 矢量 HUD (5 文件, 1,123 行)

| 文件 | 行数 | 职责 |
|------|------|------|
| `UI/HUD.lua` | 444 | 主 HUD |
| `UI/CardTooltip.lua` | 239 | 卡牌悬停详情 |
| `UI/PhaseBar.lua` | 164 | 回合阶段进度条 |
| `UI/ScorePopup.lua` | 141 | 浮动数字弹出 |
| `UI/CombatLog.lua` | 135 | 战斗日志面板 |

### Game — 游戏逻辑 (7 文件, ~2,580 行)

| 文件 | 行数 | 职责 |
|------|------|------|
| `Game/GameFSM.lua` | ~700 | 主状态机 |
| `Game/TurnPhase.lua` | ~30 | 阶段枚举 |
| `Game/Player.lua` | ~530 | 玩家状态管理 |
| `Game/CombatChain.lua` | ~380 | 战斗链解算 |
| `Game/EffectProcessor.lua` | ~490 | 效果处理器 |
| `Game/PitchSystem.lua` | ~220 | 充能系统 |
| `Game/ActionValidator.lua` | ~370 | 行动验证器 |
| `Game/EffectDefs.lua` | ~320 | 原子效果注册表 |
| `Game/CustomHandlers.lua` | ~400 | 自定义处理器 |
| `Game/GameController.lua` | ~200 | FSM↔视觉层桥接 |

### AI — 人工智能 (1 文件, ~350 行)

| 文件 | 行数 | 职责 |
|------|------|------|
| `AI/AIPlayer.lua` | ~350 | 评分式 AI |

### 入口 (1 文件, ~500 行)

| 文件 | 行数 | 职责 |
|------|------|------|
| `main.lua` | ~500 | 生命周期管理 |

---

## 里程碑

| 里程碑 | 范围 | 状态 |
|--------|------|------|
| **M1: 视觉原型** | Steps 1-4 — 3D 牌桌、Balatro 动效、手牌布局、矢量 HUD | ✅ 2026-05-18 完成 |
| **M2: 游戏逻辑** | Step 5 — 完整 Blitz 规则、战斗链、Pitch 资源、效果系统 | ✅ 2026-05-20 完成 |
| **M3: AI 对手** | Step 6 — 评分式 AI，可完成完整单局 | ✅ 2026-05-20 完成 |
| **M3.5: 桥接层** | GameController Phase 1 — FSM 驱动视觉层 | ✅ 2026-05-20 完成 |
| **M3.6: 审计修复** | 机制审计 + 4 个 Bug 修复 | ✅ 2026-05-21 完成 |
| **M3.7: 数值精确化** | 21 张卡三色差异精确化，消除全部简化处理 | ✅ 2026-05-21 完成 |
| **M4: 可交互对战** | GameController Phase 2-5 — 玩家出牌/防御/AI 可视化 | ⬚ 待开发 |
| **M5: 完整体验** | Step 7 — 主菜单、英雄选择、4 英雄可选 | ⬚ 待开发 |

---

## 技术规格

| 项目 | 值 |
|------|-----|
| 坐标系 | Y-up 左手坐标系 (与 Unity 一致) |
| 长度单位 | 米 (m) |
| 卡牌尺寸 | 0.63 x 0.005 x 0.88 m |
| 牌桌尺寸 | 6.0 x 4.0 m |
| 相机位置 | (0, 7, -4.5), FOV=50 |
| 材质系统 | PBR (PBRNoTexture / PBRNoTextureAlpha) |
| UI 渲染 | NanoVG 矢量 (NanoVGRender 事件) |
| 鼠标模式 | MM_ABSOLUTE (绝对定位) |
| 拾取方式 | Octree RaycastSingle + RAY_TRIANGLE |
| 赛制 | Blitz (40 张牌库, 年轻英雄) — 暂用 FAB 原版 |
| 初始英雄 | 枫 (战士) / 夏琳 (忍者) / 云柔 (守护者) / 小桃 (拳击手) |

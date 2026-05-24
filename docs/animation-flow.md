# 《轻拳飞扬》动画流程文档

> **版本**: v1.2  
> **最后更新**: 2026-05-24  
> **目标**: 梳理当前桌面动画整体流程，作为优化讨论的基础

---

## 一、整体架构概览

游戏动画系统分为三层：

```
┌─────────────────────────────────────────────────────┐
│  逻辑层 (Game/)                                      │
│  GameFSM → CombatChain → Player                     │
│  产出：回调事件（onAttackDeclared, onDamageResolved…） │
└────────────────────┬────────────────────────────────┘
                     │ 回调
┌────────────────────▼────────────────────────────────┐
│  桥接层 (Controller/GameController.lua)              │
│  接收 FSM 回调 → 驱动 3D 动画 + UI 动画              │
└──────┬────────────────────────────┬─────────────────┘
       │ 3D 动画                    │ NanoVG 2D 动画
┌──────▼──────────┐       ┌─────────▼────────────────┐
│ Anim/            │       │ UI/                      │
│ CardAnimator     │       │ BattleResolution         │
│ HitFlash         │       │ CombatCounter            │
│ Particles        │       │ PhaseBanner              │
│ Scene/ZoneWmark* │       │ CombatLog / ScorePopup   │
└──────────────────┘       └──────────────────────────┘
```

> *`ZoneWatermark`（剑/盾区域水印交换动画）目前只在 `main.lua` 由 KEY_Y 手动触发，**尚未接入 GameController 回调**，见第三节讨论。

---

## 二、回合生命周期与动画触发时机

### 2.1 回合开始（含抽牌）

`START_PHASE` 和 `DRAW_PHASE` 在代码里是同步连续触发的——`beginTurn()` 内部紧接着调用 `enterDrawPhase()`，中间没有任何等待或玩家交互窗口。两个阶段的 `onPhaseChanged` 回调虽然都会触发，但动画上**没有必要区分**，可以视为一个阶段。

```
FSM:beginTurn()
  │
  ├─ onTurnStarted(turnPlayerIndex, turnNumber)
  │    └─ GC: CombatLog.phase("第 N 回合 [英雄名]")
  │         HUDSync.syncHandVisuals() × 2
  │         _actionDelay = 1.5s
  │
  ├─ setPhase(START_PHASE) → 立刻 setPhase(DRAW_PHASE)  ← 两个 onPhaseChanged 连续触发
  │    └─ GC: PhaseBar.setPhase(1→2)，PhaseBanner.show("抽牌阶段")，SFX.phase()
  │         [START_PHASE 自身没有任何游戏逻辑，效果已在 beginTurn() 顶部直接执行]
  │
  └─ onDrawCards(playerIndex, cardIds)
       └─ GC: Card3D.create() × N 张
            HandFan.addCard() × N 张
            CardAnimator.dealSlide()  ← 发牌滑入动画（stagger 0.08s/张）
            DeckStack.setCount()
            SFX.draw()
```

**动画时序**：发牌完成后 `_pendingDeals` 归零，触发 `_dealDone = true` + `_actionDelay = 1.5s` 缓冲。

> **注**：START_PHASE 在规则上有意义（"回合开始时触发"类效果的合法窗口），FSM 保留它是正确的。但只要该阶段没有玩家交互窗口，它就会瞬间穿透到 DRAW_PHASE，**动画层无需单独处理**。待将来有实际触发效果需要玩家选择时，再为其添加动画响应即可。

---

### 2.2 行动阶段

```
FSM → ACTION_PHASE
  │
  ├─ cb.onPhaseChanged(ACTION_PHASE)
  │    └─ GC: PhaseBar.setPhase(3)
  │         BattleGrid.signalYourTurn() 或 signalOpponentTurn()  ← 3D 网格高亮
  │         方块升起后保持，等待 dissolve() 统一归零（⚠️ 不再自动消散）
  │         SFX.phase()
  │
  └─ HumanActor / AIActor 等待出牌输入
```

---

### 2.3 出牌动画（攻击/充能）

**触发路径**：玩家拖拽出牌 → `GameController:submitDragPlay()` → `FSM:executeAction()` → `cb.onCardPlayed()`

```
cb.onCardPlayed(playerIndex, cardId, cardData, actionType)
  │
  ├─ [actionType == "attack" / "arsenal_attack"]
  │    ├─ SFX.attack()
  │    ├─ Card3D.flip()  ← 翻面（若背面朝上）
  │    ├─ CardAnimator.playThrow(card, chainPos)  ← 抛物弧线飞入战斗链区域
  │    │    onComplete:
  │    │      ├─ CardAnimator.impactSlam()       ← 落地弹跳冲击
  │    │      ├─ CameraRig.shake(0.06, 0.15)     ← 镜头震动
  │    │      ├─ Particles.attackSpark(cx, cy)   ← 红色火花粒子
  │    │      └─ ZoneLayout.arrangeZone("combatChain")  ← 重排战斗链
  │    └─ HandFan.applyLayout(true)  ← 剩余手牌重新布局（delay 0.3s）
  │
  └─ [actionType == "pitch" / 其他]
       ├─ SFX.pitch()
       ├─ Card3D.flip()
       ├─ Particles.pitchConvert(cx, cy)  ← 紫色向上飘散粒子
       └─ Timer.after(0.8, card:destroy())  ← 延迟销毁
```

---

### 2.4 战斗链开启 → 攻击声明

```
FSM:_openCombatChain() → CombatChain:declareAttack()
  │
  └─ cb.onAttackDeclared(link)
       ├─ CombatLog.attack("攻击: 卡名 (攻击力 N)")
       └─ CombatCounter.showAttack(attackPower)
            └─ 动画：场中央出现攻击力大数字（蓝色，带弹出缩放）
```

---

### 2.5 防御声明

```
FSM → CHAIN_DEFEND 子阶段
  │
  ├─ cb.onPhaseChanged(COMBAT_CHAIN, CHAIN_DEFEND)
  │    └─ GC: PhaseBar.setPhase(4)
  │         [当前无其他动画]
  │
  └─ cb.onDefenseDeclared(link, totalDefense)
       ├─ 对每张防御手牌：
       │    ├─ HandFan.removeCard()
       │    ├─ Card3D.flip()  ← 翻面
       │    ├─ CardAnimator.playThrow(card, defPos)  ← 飞入战斗链区
       │    │    onComplete: ZoneLayout.arrangeZone("combatChain")
       │    └─ CardPicker.registerDisplay(card)
       │
       ├─ CombatLog.system("防御: N 张手牌 + M 件护具 (总防 N)")
       ├─ SFX.defend()
       ├─ Particles.defendFlash(cx, cy)  ← 绿色菱形粒子
       └─ CombatCounter.showClash(totalDefense)
            └─ 动画：攻击力 vs 防御力数字对比（上/下，胜方红色高亮）
```

---

### 2.6 伤害结算

```
CombatChain:resolveCurrentLink()
  │
  └─ cb.onDamageResolved(link, damage, didHit)
       │
       ├─ [didHit == true]  命中
       │    ├─ CombatLog.attack("命中! 造成 N 点伤害")
       │    ├─ SFX.hit()
       │    ├─ HitFlash.triggerDamage(0.2)        ← 红色全屏闪烁（200ms）
       │    ├─ CameraRig.shake(intensity, 0.25)   ← 镜头震动（按伤害量）
       │    ├─ Particles.damageHit(cx, cy)        ← 深红色方块粒子爆炸
       │    └─ Timer.after(0.6, CombatCounter.hide())
       │
       └─ [didHit == false]  完全格挡
            ├─ CombatLog.system("完全格挡!")
            ├─ HitFlash.trigger(0.1)              ← 白色全屏闪烁（100ms）
            ├─ Particles.blockSuccess(cx, cy)     ← 白蓝色菱形粒子
            └─ Timer.after(0.6, CombatCounter.hide())
```

---

### 2.7 连招链关闭

```
CombatChain:close()
  │
  └─ cb.onChainClosed(summary)
       │
       ├─ Timer.after(0.5) → 清理战斗链区所有卡牌（destroy）
       ├─ CombatLog.system("连招链关闭: N 环节, 总伤 D, 命中 H")
       │
       ├─ [summary.totalDamage > 0]
       │    ├─ SFX.combo()
       │    └─ Particles.chainClose(cx, cy)  ← 金色火花粒子（22+10 个）
       │
       └─ Timer.after(1.0) → BattleResolution.trigger({...})
```

---

### 2.8 BattleResolution 战斗结算动画

内置状态机驱动，共约 3.5–4s：

```
IDLE → BLOCKS_ENTER → SCORES_REVEAL → SCORES_CLASH → WINNER_GLOW → ATTACK_EXEC → DISSOLVE → IDLE
```

| 状态 | 时长 | 内容 |
|------|------|------|
| `BLOCKS_ENTER` | ~0.5s | 攻防双方区块从屏幕两侧滑入 |
| `SCORES_REVEAL` | ~0.8s | 攻击力/防御值数字逐渐浮现 |
| `SCORES_CLASH` | ~0.6s | 数字向中心冲击，碰撞星形爆炸 |
| `WINNER_GLOW` | ~0.6s | 胜方数字发光，王冠水印出现 |
| `ATTACK_EXEC` | ~1.0s | 攻击执行线动画 + 火焰爆炸 + 伤害光爆 |
| `DISSOLVE` | ~0.5s | 整体淡出 |

---

### 2.8.1 BattleGrid 生命周期（统一管理）

> **变更说明（v1.2）**：原 `signalYourTurn/signalOpponentTurn` 内置 1.8s 计时后自动调 `dissolve()`，导致开局时出现两次"从中心扩散"效果（signal 升起 + 自消散，各一次）。后续回合因 `wave.active` 守卫阻止 signal 执行，只剩 BattleResolution 的 dissolve，视觉不一致。
>
> 已按**统一管理生命周期**方向修改：

```
信号升起（signalYourTurn/signalOpponentTurn）
  └─ 只负责升起，不再自动消散

归零时机（三种路径，互斥）：
  ①  有战斗 → BattleResolution.DISSOLVE 阶段调 grid:dissolve(dur*0.7)
  ②  无战斗 → END_PHASE 时 GameController 检查 !BattleResolution.isActive() 后调 grid:dissolve(1.0)
  ③  跳过/中断 → BattleResolution.skip() 内部调 grid:dissolve(0.1)
```

---

### 2.9 回合结束阶段

```
FSM:_finishTurn()
  │
  ├─ cb.onPhaseChanged(END_PHASE)
  │    └─ GC: PhaseBar.setPhase(5)
  │         ① BattleGrid.dissolve(1.0)  ← 若本回合无战斗（网格仍处于信号升起状态）
  │         PhaseBanner.show("结束阶段", "回合收尾")
  │
  └─ beginTurn(nextPlayer)  ← 换边，触发下一回合抽牌流程
```

---

## 三、ZoneWatermark（攻防区域交换动画）— 待集成

### 3.1 动画内容

`ZoneWatermark` 在 3D 桌面上放置两个图标（剑/盾）标识当前攻守方。调用 `swap()` 时播放：

| 阶段 | 时长 | 内容 |
|------|------|------|
| FLASH | 0.20s | 图标亮度从静止半透明（alpha 0.15）升至不透明 |
| SWAP | 0.52s | 剑/盾沿 XZ 平面相反弧线互换位置，Y 轴略微抬起，附带拖尾 ghost |
| SETTLE | 0.30s | 亮度淡回半透明，ghost 消散 |

**总时长约 1.02s**，动画完成后触发可选的 `onDone` 回调。

### 3.2 当前状态

```
main.lua
  ├─ ZoneWatermark.init(scene_, true)      ✅ 已初始化（剑在下方/玩家侧）
  ├─ ZoneWatermark.update(dt)              ✅ 每帧更新
  ├─ ZoneWatermark.draw(ctx, w, h)         ✅ 每帧绘制（实现为空，3D 方案）
  │
  └─ input:GetKeyPress(KEY_Y)              ← 🔧 只有调试键触发
       └─ ZoneWatermark.swap(nextState)    ← GameController 完全没有调用

GameController.lua
  └─ ZoneWatermark 未 require，未在任何回调中调用   ← ⚠️ 未集成
```

### 3.3 应在哪里触发

逻辑上，剑/盾对调对应**回合换边**时刻，有两个候选点：

**方案 A：在 `onTurnStarted` 回调触发**

```lua
-- GameController:_onTurnStarted()
cb.onTurnStarted = function(turnPlayerIndex, turnNumber)
    if turnNumber > 1 then
        local swordInLower = (turnPlayerIndex == self._playerIndex)
        ZoneWatermark.swap(swordInLower)
    end
    -- ...现有逻辑...
end
```

- 优点：语义清晰，换边即换标
- 缺点：`onTurnStarted` 触发后紧接着是发牌动画，两个动画会重叠

**方案 B：在 `onPhaseChanged → END_PHASE` 触发，用 onDone 回调衔接**

```lua
-- GameController:_onPhaseChanged() 中，当 phase == END_PHASE
local swordInLower = (self.fsm.turnPlayerIndex ~= self._playerIndex)  -- 下一回合的进攻方
ZoneWatermark.swap(swordInLower, function()
    -- swap 动画结束后才允许继续（1s 后）
    self._actionDelay = math.max(self._actionDelay, 0.3)
end)
```

- 优点：swap 动画在发牌前完成，视觉节奏清晰
- 缺点：END_PHASE 回调时下一回合攻守方需要提前推算

**方案 C：独立新回调 `onTurnSwap`（需改 FSM）**

在 FSM `_finishTurn()` 结束、`beginTurn()` 开始之间新增一个回调，专门给动画系统用。

- 优点：时机最精确，不侵入现有回调逻辑
- 缺点：需要改动 `GameFSM.lua`

### 3.4 待讨论

1. 选哪个方案？目前最低成本是**方案 A**，加一行 require 和一次 swap 调用
2. swap 动画（1s）期间是否要阻塞后续动画？还是让发牌在 swap 进行中同步播放？
3. 游戏第一回合要不要播 swap？（当前初始化时 `swordInLower=true`，先手永远是玩家侧剑，如果先手是对手则需要在 `startGame` 后立即 swap）

---

## 四、已知问题

### 🔴 重要：CombatCounter 与 BattleResolution 视觉重叠

**问题描述**：

- `CombatCounter` 在屏幕中央（`w*0.5, h*0.48`）绘制大号攻防数字
- `BattleResolution` 的覆层动画也占据屏幕中央大面积区域
- 流程上，`onDamageResolved` 触发 `CombatCounter.hide()`（delay 0.6s），然后 1.0s 后触发 `BattleResolution`，但 `CombatCounter.hide()` 只是开始淡出 Tween（0.4s），**两者存在约 0.2s 的同时活跃窗口**

**更严重的情况**：多环节连击时，第 N 环结算后 CombatCounter 还未消失，第 N+1 环的 `showAttack` 就又刷新了数字，此时若 BattleResolution 提前触发，三者同时绘制。

**修复方案**：

```lua
-- GameController:_onChainClosed() 中，触发 BattleResolution 前强制隐藏
Timer.after(1.0, function()
    CombatCounter.hide()   -- ← 加这一行，强制立即开始淡出
    BattleResolution.trigger({ ... })
end)
```

或者在 `BattleResolution.trigger()` 内部调用 `CombatCounter.hide()`，由结算动画自己负责清场。

---

### 其他问题

| # | 问题 | 位置 | 优先级 |
|---|------|------|--------|
| 1 | 粒子发射点固定屏幕中央，与实际卡牌落点不匹配 | `GameController._onCardPlayed` | 低 |
| 2 | `BattleResolution` 触发延迟 1.0s 硬编码，连击节奏略僵 | `GameController._onChainClosed` | 低 |
| 3 | 缺少 Go Again 专属视觉反馈 | `GameFSM._afterLinkResolved` | 低 |

---

## 五、动画模块依赖关系

```
main.lua
  ├─ GameController ─────────── 统一调度中心
  │    ├─ Anim/CardAnimator     卡牌 3D 动画（Tween 驱动）
  │    ├─ Anim/HitFlash         全屏闪烁叠加
  │    ├─ Anim/Particles        粒子系统（对象池）
  │    ├─ UI/BattleResolution   战斗结算动画（状态机）
  │    ├─ UI/CombatCounter      攻防数字对比
  │    ├─ UI/PhaseBanner        阶段标签药丸
  │    ├─ UI/CombatLog          战斗日志
  │    ├─ UI/PhaseBar           阶段进度条
  │    └─ Scene/CameraRig       镜头震动
  │
  ├─ Scene/ZoneWatermark ────── 剑/盾交换动画（⚠️ 未接入 GameController）
  ├─ Core/Tween                 补间动画引擎
  ├─ Core/Timer                 延迟回调
  └─ Audio/SFX                  音效触发
```

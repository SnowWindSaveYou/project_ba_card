# 已知问题记录

> 最后更新：2026-05-22

---

## [ISSUE-001] 武器/装备技能实际效果未实现

**状态**: 待开发  
**优先级**: 高  
**发现时间**: 2026-05-22

### 现象

点击 HUD 武器气泡或护甲区域，CardTooltip 可以正常显示卡牌信息，但触发技能后游戏没有任何反应。

### 根本原因

**1. action type 不匹配**

`main.lua` 提交的 action type 为 `"weapon_attack"` 和 `"armor_ability"`，但 `GameFSM:executeAction()` 中没有这两个分支：

```lua
-- GameFSM.lua ~L220
-- 存在: "attack" / "weapon" / "hero_ability" / ...
-- 缺失: "weapon_attack" / "armor_ability"
-- 结果: 走到 else → return false, "unknown_action"
```

`"weapon_attack"` 对应 FSM 现有的 `"weapon"` type，改名即可复用 `_doWeaponAttack()`。  
`"armor_ability"` 完全没有对应入口，需要新增 `_doArmorAbility()` 实现。

**2. 装备 customHandler 全部缺失**

`CustomHandlers.lua` 目前只注册了 4 个武器的 handler：

| 已注册 | 缺失 |
|--------|------|
| `weapon_dawnblade` | `eq_braveforge_bracers` |
| `weapon_dawnblade_on_hit` | `eq_tectonic_plating` |
| `weapon_dawnblade_end_turn` | `eq_mask_of_momentum` |
| `weapon_kodachi` | `eq_skullhorn` |
| `weapon_anothos` | `eq_fyendals_spring_tunic` |
| `weapon_romping_club` | `eq_hope_merchants_hood` |
| | `eq_scabskin_leathers`（骰子行动点） |
| | `eq_barkbone_strapping`（骰子资源） |
| | `roll_gain_resource` |
| | `roll_gain_action` |

没有 `customHandler` 的装备（通过 `effects` 字段描述逻辑的）同样未接入 `_doArmorAbility()` 调度。

### 修复方案

1. **快速修复（weapon）**  
   `main.lua` 中将 `{ type = "weapon_attack" }` 改为 `{ type = "weapon", weaponIndex = 1 }`，复用现有 FSM 逻辑，无需改 FSM。

2. **新增 armor_ability 入口**  
   在 `GameFSM:executeAction()` 新增分支：
   ```lua
   elseif aType == "armor_ability" then
       return self:_doArmorAbility(player, action.slot)
   ```
   `_doArmorAbility()` 逻辑：找到对应槽位装备 → 验证可用性（未销毁、有行动点）→ 调用 `customHandler` 或通用 `effects` 处理 → 标记冷却/消耗。

3. **逐步注册装备 customHandler**  
   优先实现核心传奇装备（`eq_braveforge_bracers`、`eq_tectonic_plating`、`eq_mask_of_momentum`、`eq_skullhorn`、`eq_fyendals_spring_tunic`），通用装备（destroy_self + 单一 effects）通过 `EffectDefs` 通用处理。

### 受影响文件

- `scripts/main.lua` — action type 修正
- `scripts/Game/GameFSM.lua` — 新增 `armor_ability` 分支 + `_doArmorAbility()`
- `scripts/Game/CustomHandlers.lua` — 注册各装备 handler
- `scripts/Game/ActionValidator.lua` — 可能需要新增装备技能校验

---

## [ISSUE-002] HUD 点击武器/护甲未校验当前回合阶段

**状态**: 已修复  
**优先级**: 中  
**发现时间**: 2026-05-22  
**修复时间**: 2026-05-22

### 现象

在非行动阶段（防御阶段、结算阶段）点击武器/护甲区域也会尝试提交 action，虽然 FSM 会拒绝，但 UI 没有视觉反馈（不变灰、不弹提示）。

### 修复方案

`main.lua` 中点击处理前加阶段判断：
```lua
if hudResult.clicked and gc_:isWaitingForInput() then
    local phase = gc_:getCurrentPhase()
    if phase == "action" then  -- 仅行动阶段允许触发武器/护甲技能
        ...
    end
end
```

---

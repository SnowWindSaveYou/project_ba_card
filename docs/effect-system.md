# 《轻拳飞扬》效果系统设计

> 卡牌效果词条化方案：关键词词典 + 原子效果定义 + 卡牌分解示例
> 基于 `fab-cardpool-v1.md` 和 `light-punch-design.md`

---

## 一、关键词词典（完整版）

### 1.1 核心关键词（影响游戏规则的机制词）

| 本作关键词 | FAB 原名 | 精确机制 | 类别 |
|-----------|---------|---------|------|
| **连招** | Go Again | 此牌/能力解算后，获得 1 行动点 | 节奏 |
| **必杀** | Dominate | 防御方只能用 **1 张手牌** 防御此攻击（护具不受限制） | 压制 |
| **震慑** | Intimidate | 随机放逐对手 1 张手牌（面朝下），回合结束归还 | 压制 |
| **重击** | Crush | 此攻击造成 **≥ 4 伤害** 时，触发额外效果（效果写在卡面） | 条件触发 |
| **反击** | Reprise | 防御方用 **手牌** 防御了此连招环节时，触发额外效果 | 条件触发 |
| **连击(X)** | Combo(X) | 本连招链中上一次攻击为指定牌 X 时，触发额外效果 | 条件触发 |

### 1.2 装备关键词（三者机制完全不同，不可合并）

| 本作关键词 | FAB 原名 | 精确机制 | 品质定位 |
|-----------|---------|---------|---------|
| **磨损** | Battleworn | 用此护具防御后放 -1 防御计数器。**永远不会因此关键词被销毁**。耐久归 0 后仍在场、能力仍可使用（仅无法再提供防御值） | 高端·经久 |
| **脆弱** | Blade Break | 用此护具防御后，**连招链关闭时销毁此护具**。不论防御了多少，用一次就没 | 低端·一次性 |
| **耐久** | Temper | 用此护具防御后放 -1 防御计数器。**防御值归 0 时销毁** | 中端·有限次 |

> ⚠️ 关键区别：
> - 磨损 vs 耐久：磨损**不销毁**（0 防仍在场），耐久**到 0 销毁**
> - 脆弱：与计数器无关，用过就炸（连招链关闭时），防御值可以很高
> - 设计文档 `light-punch-design.md` §5.2 中"Battleworn 到 0 时销毁"的描述**有误**，需修正

### 1.3 预留/扩展关键词（首发可不实现）

| 本作关键词 | FAB 原名 | 精确机制 | 状态 |
|-----------|---------|---------|------|
| **虚招** | Phantasm | 被防御值 ≥ 4 的单张牌防御则此攻击失效（改编版） | 首发不用 |
| **爆气** | Boost | 放逐牌库顶 1 张，若为同流派则获得连招 | 首发不用 |
| **疲劳** | Blood Debt | 放逐区每 2 张疲劳牌，回合末扣 1 体力（降低版） | 首发不用 |
| **运气护体(X)** | Arcane Barrier X | 支付 X 体能防御 X 点内劲伤害 | 首发不用 |

### 1.4 辅助术语（非关键词，但效果中频繁出现）

| 术语 | 精确含义 |
|------|---------|
| **命中** (hit) | 攻击造成 > 0 伤害（穿透防御） |
| **防御值** (defense) | 牌/护具用于防御时提供的格挡数值 |
| **攻击力** (power / {p}) | 牌/架势的攻击数值 |
| **体能** (resource / {r}) | 充能产出的资源点数，用于支付费用 |
| **连招链** (combat chain) | 一次攻防交互的完整链条，含攻击→防御→反应→结算 |
| **连招环节** (chain link) | 连招链中的一个攻击单元 |
| **预备区** (arsenal) | 回合结束可面朝下放 1 张牌，下回合可直接打出 |
| **充能区** (pitch zone) | 本回合横置充能的牌所在区域，回合结束放回牌库底 |
| **放逐区** (banish zone) | 被放逐的牌存放区域 |
| **{X}** | 支付 X 点体能（写在费用描述中） |
| **+N{p}** | 攻击力 +N |
| **-1 防御计数器** | 永久降低护具防御值 1 点的标记 |

---

## 二、原子效果词条（Effect Tags）

### 设计原则

1. **每个词条 = 一个最小可执行效果**，可组合但不可再分
2. **参数化**：词条带参数，同一词条不同数值复用同一处理器
3. **触发条件与效果分离**：条件是独立词条，效果也是独立词条，组合使用
4. **不过度设计**：列出的词条覆盖 v1 卡池即可，特殊卡用 `custom` 标记

### 2.1 增益类（Buff）

| 词条 ID | 参数 | 效果描述 | 使用频率 |
|---------|------|---------|---------|
| `buff_power` | target, amount | 目标攻击 +N{p} | ★★★★★ |
| `buff_power_until_eot` | target, amount | 目标攻击 +N{p} 直到回合结束 | ★★★ |
| `buff_defense` | target, amount | 目标防御 +N 直到效果结束 | ★★ |
| `grant_go_again` | target | 目标获得"连招" | ★★★★ |
| `grant_dominate` | target | 目标获得"必杀" | ★★ |
| `grant_keyword` | target, keyword | 目标获得指定关键词 | ★ |
| `reduce_cost` | target, amount | 目标费用降低 N | ★★ |

> **target 取值**：`"next_weapon"` (下次架势攻击)、`"next_attack"` (下次攻击牌)、`"next_class_attack"` (下次本流派攻击牌)、`"this"` (此牌自身)、`"weapons_this_turn"` (本回合所有架势)、`"all_attacks_this_turn"` (本回合所有攻击)

### 2.2 抽牌/弃牌/牌库操作

| 词条 ID | 参数 | 效果描述 | 使用频率 |
|---------|------|---------|---------|
| `draw` | amount | 抽 N 张牌 | ★★★★ |
| `discard_random` | amount | 随机弃 N 张手牌 | ★★★ |
| `discard_chosen` | amount | 对手选择弃 N 张手牌 | ★ |
| `search_deck` | filter, destination | 从牌库搜索符合条件的牌到指定位置 | ★★ |
| `shuffle_deck` | — | 洗牌 | ★★ |
| `put_hand_to_deck_bottom` | amount | 从手牌放 N 张到牌库底 | ★★ |
| `put_arsenal_to_deck_bottom` | amount | 对手预备区 N 张牌放到牌库底 | ★ |
| `shuffle_from_graveyard` | filter, amount | 从弃牌堆洗回 N 张到牌库 | ★ |
| `banish_from_hand` | amount | 放逐对手 N 张手牌（= intimidate 的效果部分） | ★★ |
| `banish_deck_top` | amount | 放逐牌库顶 N 张 | ★ |

> **filter 取值**：`"any"`, `"combo"`, `"attack_reaction"`, `"class_attack"`, `"cost_0"`, `"defense_gte_3"`, `"named:XXX"`, `"power_gte_6"`

> **destination 取值**：`"hand"`, `"banish_face_up"`, `"deck_top"`, `"deck_bottom"`

### 2.3 伤害/回复

| 词条 ID | 参数 | 效果描述 | 使用频率 |
|---------|------|---------|---------|
| `deal_damage` | amount, target | 对指定目标造成 N 点伤害 | ★★ |
| `deal_damage_double` | — | 此攻击伤害翻倍 | ★（仅必杀·暴风） |
| `gain_life` | amount | 回复 N 点体力 | ★★ |
| `prevent_damage` | amount | 阻止接下来 N 点对自己的伤害 | ★（仅硬扛） |

### 2.4 护具/装备操作

| 词条 ID | 参数 | 效果描述 | 使用频率 |
|---------|------|---------|---------|
| `destroy_self` | — | 销毁此牌（护具/道具/状态） | ★★★ |
| `add_defense_counter` | target, amount | 给目标护具加 N 防御计数器（负数 = 减） | ★ |
| `equipment_defense_buff` | amount | 你的所有护具防御 +N（持续） | ★ |
| `add_energy_counter` | amount | 给此牌加 N 能量计数器 | ★ |
| `remove_energy_counter` | amount | 移除此牌 N 个能量计数器 | ★ |

### 2.5 资源/行动点

| 词条 ID | 参数 | 效果描述 | 使用频率 |
|---------|------|---------|---------|
| `gain_resource` | amount | 获得 N 点体能 | ★★ |
| `gain_action_point` | amount | 获得 N 个行动点 | ★ |
| `gain_intellect` | amount | 专注力 +N 直到回合结束 | ★ |

### 2.6 条件前缀（Condition Wrappers）

条件词条**包裹**效果词条，形成 `if CONDITION then EFFECT` 结构：

| 条件 ID | 参数 | 判定条件 | 使用频率 |
|---------|------|---------|---------|
| `on_hit` | — | 此攻击命中时（伤害 > 0） | ★★★★ |
| `on_defend_with_hand` | — | 防御方用手牌防御了此环节（= Reprise 条件） | ★★★ |
| `crush_check` | min_damage | 此攻击伤害 ≥ N 时（默认 4） | ★★★ |
| `combo_check` | card_name | 上一次攻击为指定牌时 | ★★★ |
| `if_discarded_power_gte` | threshold | 弃掉的牌攻击力 ≥ N 时（默认 6） | ★★★ |
| `if_pitch_zone_has` | filter, count | 充能区有 ≥ N 张符合条件的牌 | ★★ |
| `if_weapon_hit_this_turn` | — | 本回合架势攻击已命中 | ★ |
| `if_less_life` | — | 你的体力少于对手时 | ★★ |
| `if_from_arsenal` | — | 此牌从预备区打出时 | ★★ |
| `if_defended_by_fewer_than` | count | 对手用少于 N 张非护具牌防御时 | ★★ |
| `if_chain_link_gte` | count | 此牌是连招链第 N 个或更高的环节 | ★ |
| `if_second_weapon_hit` | — | 本回合架势第 2 次命中 | ★ |
| `once_per_turn` | — | 每回合限触发一次 | ★★ |

### 2.7 时机/持续效果

| 词条 ID | 参数 | 效果描述 | 使用频率 |
|---------|------|---------|---------|
| `until_eot` | — | 效果持续到回合结束 | ★★★ |
| `next_action_phase_destroy` | — | 在你下一个行动阶段开始时销毁此牌 | ★★（Aura 标准） |
| `on_enter_arena` | — | 进场时触发 | ★★ |
| `while_in_arena` | — | 在场期间持续有效 | ★★ |
| `at_turn_start` | — | 回合开始时触发 | ★ |
| `return_to_hand_on_hit` | — | 命中后回到手牌 | ★（仅三连踢） |
| `to_deck_bottom_instead_of_graveyard` | — | 进弃牌堆时改为放牌库底 | ★（仅不屈斗志） |

### 2.8 费用/附加费用

| 词条 ID | 参数 | 效果描述 | 使用频率 |
|---------|------|---------|---------|
| `additional_cost_discard_random` | amount | 附加费用：随机弃 N 张手牌 | ★★★（Brute 核心） |
| `additional_cost_put_hand_to_bottom` | amount | 附加费用：将 N 张手牌放到牌库底 | ★ |
| `additional_cost_pay_resource` | amount | 附加费用：额外支付 N 体能 | ★ |

### 2.9 骰子（赌拳）

| 词条 ID | 参数 | 效果描述 | 使用频率 |
|---------|------|---------|---------|
| `roll_d6` | effect_formula | 掷 6 面骰，结果按公式生效 | ★（仅 3 张牌） |

> **effect_formula 取值**：
> - `"gain_resource_half"`: 获得 ⌊结果/2⌋ 点体能
> - `"gain_action_half"`: 获得 ⌊结果/2⌋ 个行动点
> - `"prevent_damage_full"`: 阻止等于结果的伤害

### 2.10 特殊标记

| 词条 ID | 参数 | 效果描述 |
|---------|------|---------|
| `custom` | handler_id | 此牌效果需要专用处理器，handler_id 指向具体实现 |

---

## 三、卡牌效果分解示例

### 3.1 简单牌（纯词条组合）

#### 面打 / Wounding Blow（白板攻击）

```yaml
id: war_wounding_blow_r
effects: []  # 无效果，纯数值牌
```

> 白板牌没有效果词条，只有基础属性（power/defense/cost/pitch）。

#### 素振蓄力 / Sharpen Steel（辅助牌）

```yaml
id: war_sharpen_steel_r
effects:
  - buff_power: { target: "next_weapon", amount: 3 }
  - grant_go_again: { target: "self" }
```

黄色和蓝色版本仅改 `amount: 2 / 1`。

#### 组合拳 / Pack Hunt（攻击+震慑）

```yaml
id: bru_pack_hunt_r
keywords: [intimidate]
effects: []  # intimidate 作为关键词自动执行，无额外效果文本
```

> 关键词效果（如 intimidate）由关键词系统统一处理，不需要写入效果词条。

#### 深呼吸 / Sigil of Solace（本能牌）

```yaml
id: gen_sigil_of_solace_r
effects:
  - gain_life: { amount: 3 }
```

### 3.2 条件触发牌

#### 切落 / Overpower（追击牌 + Reprise）

```yaml
id: war_overpower_r
effects:
  - buff_power: { target: "weapon_attack", amount: 4 }
  - on_defend_with_hand:  # Reprise 条件
      - buff_power: { target: "weapon_attack", amount: 2 }  # 额外 +2
```

#### 旋风踢 / Whelming Gustwave（Combo 牌）

```yaml
id: nin_whelming_gustwave_r
effects:
  - combo_check: { card_name: "前踢" }  # Surging Strike
    then:
      - buff_power: { target: "this", amount: 1 }
      - grant_go_again: { target: "this" }
      - on_hit:
          - draw: { amount: 1 }
```

#### 按劲 / Buckling Blow（Crush 牌）

```yaml
id: gua_buckling_blow_r
effects:
  - crush_check: { min_damage: 4 }
    then:
      - add_defense_counter: { target: "opponent_equipment", amount: -1 }
```

#### 猛虎出笼 / Savage Feast（弃牌触发）

```yaml
id: bru_savage_feast_r
effects:
  - additional_cost_discard_random: { amount: 1 }
  - if_discarded_power_gte: { threshold: 6 }
    then:
      - draw: { amount: 1 }
```

### 3.3 复合效果牌

#### 灵光一闪 / Enlightened Strike

```yaml
id: gen_enlightened_strike
effects:
  - additional_cost_put_hand_to_bottom: { amount: 1 }
  - choose_one:
      - draw: { amount: 1 }
      - buff_power: { target: "this", amount: 2 }
      - grant_go_again: { target: "this" }
```

> `choose_one` 是一个组合词条，让玩家从多个效果中选一个。

#### 怒火中烧 / Bloodrush Bellow

```yaml
id: bru_bloodrush_bellow
effects:
  - additional_cost_discard_random: { amount: 1 }
  - buff_power_until_eot: { target: "all_class_attacks", amount: 2 }
  - if_discarded_power_gte: { threshold: 6 }
    then:
      - draw: { amount: 2 }
      - grant_go_again: { target: "self" }
```

### 3.4 护具效果

#### 桜風·改良水手服 / Braveforge Bracers（磨损 + 主动能力）

```yaml
id: eq_braveforge_bracers
keywords: [battleworn]
abilities:
  - type: "action"
    once_per_turn: true
    cost: 1  # {r}
    condition: if_weapon_hit_this_turn
    effects:
      - buff_power: { target: "next_weapon", amount: 1 }
      - grant_go_again: { target: "self_ability" }
```

#### DASH·露脐运动衫 / Mask of Momentum（脆弱 + 被动能力）

```yaml
id: eq_mask_of_momentum
keywords: [blade_break]
abilities:
  - type: "passive"
    once_per_turn: true
    condition: if_chain_link_gte: { count: 3, and: "all_hit" }
    effects:
      - draw: { amount: 1 }
```

#### 云裳·水袖罩衫 / Crater Fist（耐久 + 主动能力）

```yaml
id: eq_crater_fist
keywords: [temper]
abilities:
  - type: "action"
    cost: 1  # {r}
    effects:
      - destroy_self: {}
      - buff_power_until_eot: { target: "attacks_with_crush", amount: 2 }
      - grant_go_again: { target: "self_ability" }
```

### 3.5 状态牌 (Aura) 效果

#### 运气蓄力 / Emerging Power

```yaml
id: gua_emerging_power_r
effects:
  - grant_go_again: { target: "self" }  # 打出时自带连招
  - next_action_phase_destroy: {}       # 下个行动阶段销毁
  - on_destroy:                         # 销毁时触发
      - buff_power: { target: "next_class_attack", amount: 3 }
```

#### 铁布衫 / Stonewall Confidence

```yaml
id: gua_stonewall_confidence_r
effects:
  - while_in_arena:
      - buff_defense: { target: "your_cards_cost_gte_3_defending", amount: 4 }
  - next_action_phase_destroy: {}
```

### 3.6 道具

#### 春日碎花衬衫 / Fyendal's Spring Tunic（能量计数器）

```yaml
id: eq_fyendals_spring_tunic
keywords: [blade_break]
abilities:
  - type: "passive"
    trigger: at_turn_start
    condition: "energy_counters < 3"
    effects:
      - add_energy_counter: { amount: 1 }
  - type: "instant"
    effects:
      - remove_energy_counter: { amount: 3 }
      - gain_resource: { amount: 1 }
```

---

## 四、choose_one 词条

部分牌需要玩家做选择，用 `choose_one` 组合词条：

| 牌名 | 选项 |
|------|------|
| 灵光一闪 (Enlightened Strike) | 抽 1 / +2 攻 / 获得连招 |
| 追拳 (Pummel) | 力量型架势攻击 +N **或** 费用 ≥ 2 攻击牌 +N 且命中弃牌 |
| 本能追击 (Razor Reflex) | 灵巧型架势攻击 +N **或** 费用 ≤ 1 攻击牌 +N 且命中连招 |

```yaml
# choose_one 通用结构
choose_one:
  options:
    - label: "选项A描述"
      condition: { ... }   # 可选：选项的前提条件
      effects: [ ... ]
    - label: "选项B描述"
      effects: [ ... ]
```

---

## 五、Crush 效果速查表

太极（Guardian）所有攻击牌都带 Crush，各自效果不同：

| 本作名称 | FAB 名称 | Crush 效果（造成 ≥ 4 伤害时） | 词条表示 |
|---------|---------|---------------------------|---------|
| 泰山压顶 | Crippling Crush | 对手弃 2 张随机手牌 | `discard_random: {amount: 2, target: "opponent"}` |
| 推山掌 | Spinal Crush | 对手下回合所有行动/攻击失去且不能获得连招 | `custom: "suppress_go_again_next_turn"` |
| 封脉掌 | Cranial Crush | 对手下回合不能抽牌 | `custom: "suppress_draw_next_turn"` |
| 缠丝劲 | Disable | 将对手预备区 1 张牌放到牌库底 | `put_arsenal_to_deck_bottom: {amount: 1}` |
| 按劲 | Buckling Blow | 对手 1 件护具获得 -1 防御计数器 | `add_defense_counter: {target: "opp_equipment", amount: -1}` |
| 採劲 | Cartilage Crush | 对手下回合第一个行动额外支付 {1} | `custom: "extra_cost_next_turn_first_action"` |
| 挒劲 | Crush Confidence | 对手失去角色卡效果和激活能力到下回合结束 | `custom: "suppress_hero_ability_next_turn"` |
| 肘靠 | Debilitate | 对手下回合第一次攻击 -2{p} | `custom: "debuff_first_attack_next_turn"` |

> 大部分 Crush 效果涉及"对手下回合"持续效果，需要状态标记系统支持，标记为 `custom`。

---

## 六、需要特殊处理的卡牌（custom handler）

### 6.1 英雄能力（4 个，都需要独立处理器）

| 角色 | 能力摘要 | handler_id |
|------|---------|-----------|
| 一之濑枫 | 架势命中后可额外再攻击一次 | `hero_dorinthea` |
| 夏琳 | 攻击牌命中后弃 0 费牌搜索 combo 牌打出 | `hero_katsu` |
| 云柔 | 支付 {2} 让费用 ≥ 3 攻击牌获得必杀+连招 | `hero_bravo` |
| 铁拳小桃 | 弃掉攻击力 ≥ 6 的牌时触发震慑 | `hero_rhinar` |

### 6.2 架势（武器）特殊能力

| 架势 | 特殊逻辑 | handler_id |
|------|---------|-----------|
| 正眼之构 (Dawnblade) | 第 2 次命中放 +1 计数器；回合未命中移除所有计数器 | `weapon_dawnblade` |
| 战斗站架 (Kodachi) | 充能区有 0 费牌时获得连招 | `weapon_kodachi` |
| 太极起势 (Anothos) | 充能区有 ≥ 2 张费用 ≥ 3 的牌时 +2{p} | `weapon_anothos` |
| 拳击架势 (Romping Club) | 弃掉攻击力 ≥ 6 的牌时 +1{p} | `weapon_romping_club` |

### 6.3 效果复杂的行动牌

| 本作名称 | FAB 名称 | 复杂原因 | handler_id |
|---------|---------|---------|-----------|
| 残心追击 | Singing Steelblade | Reprise → 搜索牌库找追击牌打出（搜索+即时打出） | `spec_singing_steelblade` |
| 无影·解放 | Mugenshi: RELEASE | Combo → 命中时搜索所有同名牌到手牌 | `spec_mugenshi_release` |
| 疾风连环 | Lord of Wind | Combo → 附加费用 pay X 从弃牌堆洗回 X 张指定牌，+X{p} | `spec_lord_of_wind` |
| 四两拨千斤 | Show Time! | 进场搜牌+延迟效果（下行动阶段销毁时抽牌） | `spec_show_time` |
| 拳感直觉 | Sand Sketched Plan | 搜索任意牌到手牌→随机弃→条件触发 | `spec_sand_sketched_plan` |
| 不屈斗志 | Drone of Brutality | 进弃牌堆时改为放牌库底（替代规则） | `gen_drone_of_brutality` |
| 必杀·暴风 | Pounding Gale | 伤害翻倍（Combo 条件） | `nin_pounding_gale` |

### 6.4 骰子牌（3 张）

| 本作名称 | FAB 名称 | 骰子效果 | handler_id |
|---------|---------|---------|-----------|
| K.O.·绑带运动内衣 | Barkbone Strapping | 掷骰，获得 ⌊结果/2⌋ 体能 | `roll_gain_resource` |
| K.O.·破洞牛仔热裤 | Scabskin Leathers | 掷骰，获得 ⌊结果/2⌋ 行动点 | `roll_gain_action` |
| 硬扛 | Bone Head Barrier | 掷骰，阻止等于结果的伤害 | `roll_prevent_damage` |

> 骰子牌可统一用 `roll_d6` 词条 + 不同 formula 处理，也可为每张写独立 handler。推荐统一处理。

### 6.5 Crush 持续效果（需下回合状态标记）

以下 Crush 效果影响对手的**下回合**，需要挂载持续状态：

| 效果 | 标记类型 | handler_id |
|------|---------|-----------|
| 对手下回合行动/攻击不能获得连招 | suppress_go_again | `crush_spinal` |
| 对手下回合不能抽牌 | suppress_draw | `crush_cranial` |
| 对手下回合首个行动 +1 费用 | extra_cost_first | `crush_cartilage` |
| 对手失去英雄能力到下回合结束 | suppress_hero | `crush_confidence` |
| 对手下回合首次攻击 -2{p} | debuff_first_attack | `crush_debilitate` |

---

## 七、效果处理优先级

当一个牌/能力触发多个效果时，按以下顺序执行：

```
1. 附加费用（additional_cost_*）→ 必须先支付
2. 关键词自动效果（intimidate 等）→ 关键词系统处理
3. 主效果（buff/draw/damage 等）→ 按文本顺序
4. 条件触发效果（on_hit/crush_check 等）→ 等条件满足后
5. 连招判定（go_again）→ 结算结束后
```

---

## 八、数据模型补充

在 `light-punch-design.md` 的 Card 数据模型基础上，增加效果字段：

```
Card {
  // ... 原有字段不变 ...

  // 效果词条化字段
  effects: EffectTag[]        -- 词条列表（按执行顺序）
  customHandler: string?      -- 特殊处理器 ID（有此字段时忽略 effects）
}

EffectTag {
  id: string                  -- 词条 ID（如 "buff_power"）
  params: table               -- 参数表（如 { target="next_weapon", amount=3 }）
  condition: ConditionTag?    -- 可选前置条件
  then: EffectTag[]?          -- 条件满足时执行的子效果
}

ConditionTag {
  id: string                  -- 条件 ID（如 "on_hit"、"crush_check"）
  params: table?              -- 条件参数（如 { min_damage=4 }）
}
```

### customHandler 与 effects 的关系

```
if card.customHandler then
    -- 调用专用处理函数，完全跳过词条系统
    handlers[card.customHandler](card, context)
else
    -- 按词条列表依次执行
    for _, tag in ipairs(card.effects) do
        executeTag(tag, context)
    end
end
```

> **原则**：能用词条组合表达的就不写 custom。只有涉及搜索牌库打出、替代规则、跨回合状态等复杂交互时才用 custom。

---

## 九、统计总结

### 词条覆盖率

| 类别 | 总牌数 | 纯词条 | 含 custom | custom 占比 |
|------|--------|--------|----------|------------|
| 英雄 | 4 | 0 | 4 | 100%（预期内） |
| 架势 | 5 | 0 | 5 | 100%（预期内） |
| 护具 | 21 | ~14 | ~7 | 33% |
| 攻击牌 | ~78 | ~68 | ~10 | 13% |
| 辅助牌 | ~31 | ~25 | ~6 | 19% |
| 追击牌 | ~15 | ~13 | ~2 | 13% |
| 闪避牌 | ~12 | ~12 | 0 | 0% |
| 本能牌 | ~4 | ~2 | ~2 | 50% |
| **合计** | ~170 | ~134 | ~36 | **~21%** |

> **结论**：约 80% 的牌可以用纯词条组合描述，约 20% 需要 custom handler。
> 这 20% 主要是：英雄能力（4）、架势（5）、专属牌（11）、Crush 持续效果（5）、骰子牌（3）、替代规则牌（2）。

### 词条使用频率 Top 10

1. `buff_power` — 武器/攻击力增强，出现在 ~30 张牌
2. `grant_go_again` — 给予连招，~20 张
3. `additional_cost_discard_random` — 随机弃牌（蛮兽核心），~15 张
4. `draw` — 抽牌，~10 张
5. `destroy_self` — 销毁自身（护具/道具），~10 张
6. `on_hit` — 命中触发条件，~8 张
7. `crush_check` — Crush 条件，~8 张
8. `on_defend_with_hand` — Reprise 条件，~6 张
9. `combo_check` — Combo 条件，~6 张
10. `gain_life` — 回复体力，~5 张

---

## 十、卡牌类型权威参考表

> 三份文档（`fab-rules.md`、`fab-cardpool-v1.md`、`light-punch-design.md`）对卡牌类型的描述存在不一致。
> 本节统一梳理，作为开发实现的**唯一权威参考**。

### 10.1 类型映射总表

| FAB 原版类型 | fab-rules.md §4 | cardpool cardType 枚举 | 本作术语 | Card.type 枚举 | 说明 |
|-------------|-----------------|----------------------|---------|---------------|------|
| Hero | §4.1 英雄卡 | `"hero"` | 角色 | — (独立模型) | 非牌组牌，开局放置 |
| Weapon | §4.2 武器卡 | `"weapon"` | 架势 | — (独立模型) | 非牌组牌，开局放置 |
| Equipment | §4.3 装备卡 | `"equipment"` | 护具 | — (独立模型) | 非牌组牌，开局放置 |
| Attack Action | §4.4 攻击行动 | `"attack_action"` | 攻击牌 | `"attack"` | 核心进攻手段 |
| Non-Attack Action | §4.4 非攻击行动 | `"non_attack_action"` | 辅助牌 | `"support"` | 非伤害效果 |
| Attack Reaction | §4.5 攻击反应 | `"attack_reaction"` | 追击牌 | `"chase"` | 攻击方反应阶段 |
| Defense Reaction | §4.5 防御反应 | `"defense_reaction"` | 闪避牌 | `"dodge"` | 防御方反应阶段 |
| Instant | §4.6 即时牌 | `"instant"` | 本能牌 | `"instinct"` | 任意时机 |
| Aura | §4.7 灵光/光环 | `"aura"` | 状态牌 | `"aura"` | 留场持续效果 |
| Item | §4.7 物品 | `"item"` | 道具牌 | `"item"` | 留场一次性道具 |
| Ally | §4.7 盟友 | — (v1 无) | — | — | 首发不实现 |
| Landmark | §4.7 地标 | — (v1 无) | — | — | 首发不实现 |
| Token | §4.7 标记 | `"token"` | 标记 | — (运行时生成) | 由效果创建，不进牌组 |

> ⚠️ **修正**：`light-punch-design.md` §7.5 的 `Card.type` 枚举缺少 `"item"`，需补充。

### 10.2 牌组牌详细行为规则

以下 **8 种类型** 是实际进入牌组、在对局中使用的牌：

#### 表 A：使用时机与费用

| 类型 | 使用时机 | 消耗行动点 | 消耗体能(资源) | 从哪里打出 |
|------|---------|-----------|--------------|-----------|
| **攻击牌** attack | 己方行动阶段 | ✅ 1 AP | ✅ 牌面费用 | 手牌 / 预备区 |
| **辅助牌** support | 己方行动阶段 | ✅ 1 AP | ✅ 牌面费用 | 手牌 / 预备区 |
| **追击牌** chase | 反应阶段（攻击方） | ❌ | ✅ 牌面费用 | 手牌 |
| **闪避牌** dodge | 反应阶段（防御方） | ❌ | ✅ 牌面费用 | 手牌 |
| **本能牌** instinct | **任意时机**（双方回合均可） | ❌ | ✅ 牌面费用 | 手牌 |
| **状态牌** aura | 己方行动阶段（作为辅助牌打出） | ✅ 1 AP | ✅ 牌面费用 | 手牌 / 预备区 |
| **道具牌** item | 己方行动阶段（作为辅助牌打出） | ✅ 1 AP | ✅ 牌面费用 | 手牌 / 预备区 |
| **标记** token | 由其他效果生成 | — | — | — |

#### 表 B：使用后去向与防御能力

| 类型 | 使用后去向 | 能否用于防御 | 能否放入预备区 | 能否充能 |
|------|-----------|------------|-------------|---------|
| **攻击牌** | 连招链关闭 → 弃牌堆 | ✅ 有防御值 | ✅ | ✅ |
| **辅助牌** | 解算后 → 弃牌堆 | ✅ 有防御值 | ✅ | ✅ |
| **追击牌** | 解算后 → 成为连招链防御牌（弃牌堆） | ❌ 无法直接防御 | ✅ | ✅ |
| **闪避牌** | 解算后 → 成为连招链防御牌（弃牌堆） | ✅ 有防御值 + 反应防御 | ✅ | ✅ |
| **本能牌** | 解算后 → 弃牌堆 | ❌ 通常无防御值 | ✅ | ✅ |
| **状态牌** | 打出后 → **留在场上** | ✅ 有防御值（打出前） | ✅（打出前） | ✅（打出前） |
| **道具牌** | 打出后 → **留在场上**（激活后销毁） | ✅ 有防御值（打出前） | ✅（打出前） | ✅（打出前） |
| **标记** | 留在场上直到被移除 | ❌ | ❌ | ❌ |

### 10.3 常见混淆点

#### Q1：状态牌(Aura)和辅助牌(Support)有什么区别？

在 FAB 中，Aura 是 Non-Attack Action 的子类型。打出方式与辅助牌完全相同（消耗 1 AP + 费用），但**使用后不进弃牌堆而是留在场上**，持续提供效果。

```
辅助牌：打出 → 效果生效 → 进弃牌堆（一次性）
状态牌：打出 → 留在场上 → 持续提供效果（直到被移除/触发后消耗）
```

**v1 卡池实例**：
- Blessing of Deliverance（拯救祝福）— Guardian Non-Attack Action (Aura)：留在场上，之后可以销毁来阻止伤害
- Seismic Surge（地震脉冲）— Token (Aura)：由 Crush 效果生成，给下次攻击 +2

#### Q2：道具牌(Item)和状态牌(Aura)有什么区别？

两者都"留在场上"，但激活方式不同：

```
状态牌：被动持续 / 满足条件时自动触发
道具牌：需要主动激活（"Action -- Destroy this: ..." 或 "Instant -- Destroy this: ..."）
```

道具牌的激活方式写在牌面上：
- `"Action -- Destroy this: 效果"` → 需消耗 1 行动点来激活，激活后销毁
- `"Instant -- Destroy this: 效果"` → 任意时机激活，激活后销毁

**v1 卡池实例**：
- Potion of Strength（力量药水）— Item，Instant 激活：销毁 → 下次攻击 +2
- Energy Potion（能量药水）— Item，Instant 激活：销毁 → 获得 2 资源

#### Q3：追击牌(Chase)和闪避牌(Dodge)的使用时机？

```
攻击声明 → 防御声明 → 反应阶段 {
    攻击方：使用追击牌（增加攻击力/附加效果）
    防御方：使用闪避牌（增加防御值/附加效果）
    交替直到双方 Pass
} → 伤害结算
```

- **追击牌**的攻击力**加算到**当前攻击的总攻击力上
- **闪避牌**的防御值**加算到**当前防御总值上
- 两者都可能需要支付体能费用（看牌面 Cost）
- 两者都**不消耗行动点**

#### Q4：本能牌(Instinct)到底什么时候能用？

几乎任何时候——己方行动阶段、反应阶段、甚至**对手回合**。这是最灵活的类型：

- ❌ 不消耗行动点
- ✅ 需支付体能费用（如果有）
- ⚡ 如果带"连招"(Go Again)关键词，使用后获得 1 行动点

**v1 卡池实例**：
- Bone Head Barrier（骨头壁障）— Brute Instant：掷骰子阻止伤害
- Sigil of Solace（慰藉印记）— Generic Instant：回复体力

#### Q5：哪些牌可以用来防御？

```
几乎所有牌都有防御值（右下角数字），都能用来防御。

例外：
- 追击牌（Attack Reaction）：不能直接用于防御
- 本能牌（Instant）：通常无防御值（但如果有就能用）
- Token：不能用于防御
- 当前正在使用的牌：已经充能/打出的牌不能再用来防御
```

**关键规则**：防御是"声明"行为，不消耗行动点/体能，但该牌本回合不能再用于其他用途。

### 10.4 非牌组牌（开局放置）

| 类型 | 开局放置位置 | 使用方式 | 被击败/移除后 |
|------|------------|---------|-------------|
| **角色** hero | 角色区 | 被动（提供能力/体力/专注力） | — (体力归 0 = 败北) |
| **架势** weapon | 架势区(武器区) | 主动攻击（消耗 1 AP + 费用） | 连招链关闭后**返回原位** |
| **护具** equipment | 护具区(装备区) | 被动防御 / 主动能力 | 销毁后移除出游戏 |

### 10.5 本作 Card.type 权威枚举（修正版）

```
Card.type: "attack" | "support" | "chase" | "dodge" | "instinct" | "aura" | "item"
```

相比 `light-punch-design.md` §7.5 新增了 `"item"`。

> **为什么需要 item？**
> v1 卡池中有 Potion of Strength、Energy Potion、Nullrune 系列等道具。它们的行为模式（留场 → 主动激活 → 销毁）与状态牌(aura)、辅助牌(support) 均不同，需要独立类型标识。

### 10.6 v1 卡池中各类型分布

| 本作类型 | Card.type | v1 卡池数量 | 占比 | 代表牌 |
|---------|-----------|------------|------|--------|
| 攻击牌 | `attack` | ~78 | ~46% | Wounding Blow, Rising Knee Thrust, Crippling Crush |
| 辅助牌 | `support` | ~31 | ~18% | Awakening Bellow, Sharpen Steel, Sink Below |
| 追击牌 | `chase` | ~15 | ~9% | Blade Flurry, Razor Reflex, Pummel |
| 闪避牌 | `dodge` | ~12 | ~7% | Unmovable, Springboard Somersault |
| 本能牌 | `instinct` | ~4 | ~2% | Sigil of Solace, Bone Head Barrier |
| 状态牌 | `aura` | ~5 | ~3% | Blessing of Deliverance, Token (Seismic Surge / Might / Quicken) |
| 道具牌 | `item` | ~4 | ~2% | Potion of Strength, Energy Potion |
| 护具 | — | 21 | ~12% | (独立模型，不计入 Card.type) |
| 架势 | — | 5 | — | (独立模型) |
| 角色 | — | 4 | — | (独立模型) |

### 10.7 各类型的连招链(Combat Chain)交互

```
连招链环节结构：

    攻击声明 ─── 攻击牌 / 架势攻击 ──→ 开始新环节
        │
        ├── 防御声明 ─── 手牌(任意有防御值的牌) + 护具
        │
        ├── 攻击方反应 ─── 追击牌
        │
        ├── 防御方反应 ─── 闪避牌
        │
        └── 结算 ─── 计算伤害

    本能牌 ──→ 可在上述任意环节之间插入
    辅助牌 ──→ 只能在行动阶段打出（会关闭当前连招链！）
    状态牌 ──→ 同辅助牌（行动阶段打出，留在场上）
    道具牌 ──→ 同辅助牌（行动阶段打出），但 Instant 激活的道具可随时激活
```

> ⚠️ **关键规则**：打出辅助牌/状态牌会**关闭当前连招链**。如果你想在攻击之间使用辅助效果，应该在攻击之前使用（利用 Go Again 获得额外行动点），或者使用本能牌（不会关闭连招链）。

---

*文档版本：v1.1*
*最后更新：2026-05-19*

# 《血肉之战》电子版 -- 第一版卡池完整参数表

> **版本**: v1.0
> **最后更新**: 2026-05-18
> **数据来源**: [cards.fabtcg.com](https://cards.fabtcg.com), [fabdb.net](https://fabdb.net), [fabrary.net](https://fabrary.net)
> **卡池范围**: Welcome to Rathe (WTR) 为主 + 少量关键补充
> **验证状态**: 部分数据需与官方数据库交叉验证（已标注）

---

## 目录

1. [设计决策](#一设计决策)
2. [英雄卡](#二英雄卡-4-位)
3. [武器卡](#三武器卡-5-张)
4. [装备卡](#四装备卡)
5. [战士 (Warrior) 卡池](#五战士-warrior-卡池)
6. [忍者 (Ninja) 卡池](#六忍者-ninja-卡池)
7. [守护者 (Guardian) 卡池](#七守护者-guardian-卡池)
8. [蛮兽 (Brute) 卡池](#八蛮兽-brute-卡池)
9. [通用 (Generic) 卡池](#九通用-generic-卡池)
10. [Token 列表](#十token-列表)
11. [数据模型字段定义](#十一数据模型字段定义)
12. [卡池统计](#十二卡池统计)

---

## 一、设计决策

### 1.1 赛制选择: 闪电战 (Blitz)

第一版采用 **闪电战 (Blitz)** 赛制：
- 使用**年轻版 (Young)** 英雄（生命值更低，对局更快）
- 牌组大小: **正好 40 张**（含武器和装备）
- 同名牌上限: **每张独特牌 1 张**
- 对局时长: 约 15-25 分钟

### 1.2 初始英雄: 4 位

| 职业 | 英雄 | 选择理由 |
|------|------|---------|
| 战士 (Warrior) | Dorinthea | 机制简洁，武器连击直观 |
| 忍者 (Ninja) | Katsu | Combo 机制有趣，易于理解 |
| 守护者 (Guardian) | Bravo | 攻防转换清晰，高费重击 |
| 蛮兽 (Brute) | Rhinar | 高风险高回报，Intimidate 有张力 |

### 1.3 关键词实现优先级

**第一版必须实现**:
- Go Again, Dominate, Intimidate, Combo, Crush, Reprise
- Battleworn, Blade Break, Temper
- Arcane Barrier（基础版）

**第一版可选/简化**:
- Phantasm, Boost, Blood Debt（后续职业需要时再加）

---

## 二、英雄卡 (4 位)

### 数据字段

| 字段 | 类型 | 说明 |
|------|------|------|
| id | string | 唯一 ID |
| name | string | 英文名 |
| name_cn | string | 中文名 |
| class | string | 职业 |
| life | number | 生命值 |
| intellect | number | 智力值（每回合结束抽牌数） |
| ability | string | 英雄特殊能力 |

### 英雄数据

#### H01: Dorinthea (年轻版)

| 字段 | 值 |
|------|-----|
| id | `hero_dorinthea_young` |
| name | Dorinthea |
| name_cn | 多琳希亚 |
| class | warrior |
| life | **20** |
| intellect | **4** |
| ability | Once per turn -- When your weapon attack hits, you may attack an additional time with that weapon this turn. |

#### H02: Katsu (年轻版)

| 字段 | 值 |
|------|-----|
| id | `hero_katsu_young` |
| name | Katsu, the Wanderer |
| name_cn | �的流浪者·胜 |
| class | ninja |
| life | **20** |
| intellect | **4** |
| ability | Once per turn -- When an attack action card you control hits, you may discard a card with cost 0. If you do, search your deck for a card with combo, banish it face up, then shuffle your deck. You may play it this turn. |

#### H03: Bravo (年轻版)

| 字段 | 值 |
|------|-----|
| id | `hero_bravo_young` |
| name | Bravo |
| name_cn | 布拉沃 |
| class | guardian |
| life | **20** |
| intellect | **4** |
| ability | Action -- {r}{r}: Until end of turn, your attack action cards with cost 3 or greater gain dominate. Go again. |

#### H04: Rhinar (年轻版)

| 字段 | 值 |
|------|-----|
| id | `hero_rhinar_young` |
| name | Rhinar |
| name_cn | 莱纳 |
| class | brute |
| life | **20** |
| intellect | **4** |
| ability | Whenever you discard a card with 6 or more {Power} during your action phase, intimidate. |

---

## 三、武器卡 (5 张)

### 数据字段

| 字段 | 类型 | 说明 |
|------|------|------|
| id | string | 唯一 ID |
| name | string | 英文名 |
| cardType | string | "weapon" |
| subtype | string | 武器子类型 (sword/dagger/hammer/club) |
| class | string | 职业限制 |
| hands | number | 1=单手, 2=双手 |
| power | number | 基础攻击力 |
| cost | number | 激活费用 |
| ability | string | 能力描述 |

### 武器数据

#### W01: Dawnblade (破晓之刃)

| 字段 | 值 |
|------|-----|
| id | `weapon_dawnblade` |
| name | Dawnblade |
| subtype | sword |
| class | warrior |
| hands | **2** |
| power | **3** |
| cost | **1** |
| ability | Once per Turn Action -- {r}: Attack. If Dawnblade hits, and it is the second time it has hit this turn, put a +1{p} counter on Dawnblade. At the beginning of your end phase, if Dawnblade did not hit this turn, remove all +1{p} counters from Dawnblade. |

#### W02: Harmonized Kodachi (调和小太刀) x2

| 字段 | 值 |
|------|-----|
| id | `weapon_harmonized_kodachi` |
| name | Harmonized Kodachi |
| subtype | dagger |
| class | ninja |
| hands | **1** |
| power | **1** |
| cost | **1** |
| ability | Once per Turn Action -- {r}: Attack. If you have a card in your pitch zone with cost 0, Harmonized Kodachi gains go again. |

> **注意**: 装备 2 把（双持），各占一只手。两把同名但各自独立触发"Once per Turn"。

#### W03: Anothos (安诺索斯)

| 字段 | 值 |
|------|-----|
| id | `weapon_anothos` |
| name | Anothos |
| subtype | hammer |
| class | guardian |
| hands | **2** |
| power | **4** |
| cost | **3** |
| ability | Once per Turn Action -- {r}{r}{r}: Attack. If there are 2 or more cards in your pitch zone with cost 3 or greater, Anothos gains +2{p}. |

#### W04: Romping Club (狂暴棍棒)

| 字段 | 值 |
|------|-----|
| id | `weapon_romping_club` |
| name | Romping Club |
| subtype | club |
| class | brute |
| hands | **2** |
| power | **4** |
| cost | **2** |
| ability | Once per Turn Action -- {r}{r}: Attack. Once per turn, when you discard a card with 6 or more {p}, this gets +1{p} until end of turn. |

---

## 四、装备卡

### 数据字段

| 字段 | 类型 | 说明 |
|------|------|------|
| id | string | 唯一 ID |
| name | string | 英文名 |
| cardType | string | "equipment" |
| slot | string | head / chest / arms / legs |
| class | string | 职业限制 ("generic" = 所有职业) |
| defense | number | 防御值 |
| keywords | string[] | 关键词列表 |
| ability | string | 能力描述 |
| rarity | string | 稀有度 |

### 4.1 战士装备

| ID | 名称 | 槽位 | 防御 | 关键词 | 能力 | 稀有度 |
|----|------|------|------|--------|------|--------|
| eq_braveforge_bracers | Braveforge Bracers | arms | 2 | Battleworn | Once per Turn Action -- {r}: Your next weapon attack this turn gets +1{p}. Activate only if a weapon you control has hit this turn. Go again. | Legendary |
| eq_refraction_bolters | Refraction Bolters | legs | 2 | Battleworn | When a weapon attack you control hits, you may destroy this. If you do, the attack gains go again. | Common |
| eq_courage_of_bladehold | Courage of Bladehold | chest | 2 | Temper | Action -- Destroy this: Your sword attacks cost {1} less to activate this turn. Go again. | Majestic |

### 4.2 忍者装备

| ID | 名称 | 槽位 | 防御 | 关键词 | 能力 | 稀有度 |
|----|------|------|------|--------|------|--------|
| eq_mask_of_momentum | Mask of Momentum | head | 2 | Blade Break | Once per Turn -- When an attack action card you control is the 3rd or higher chain link in a row to hit, draw a card. Blade Break. | Legendary |
| eq_breaking_scales | Breaking Scales | arms | 1 | Battleworn | Attack Reaction -- Destroy this: Target attack action card with combo gains +1{p}. Battleworn. | Common |

### 4.3 守护者装备

| ID | 名称 | 槽位 | 防御 | 关键词 | 能力 | 稀有度 |
|----|------|------|------|--------|------|--------|
| eq_tectonic_plating | Tectonic Plating | chest | 2 | Battleworn | Once per Turn Action -- {r}: Create a Seismic Surge token. Go again. Battleworn. | Legendary |
| eq_helm_of_isens_peak | Helm of Isen's Peak | head | 1 | Battleworn | Action -- {r}, destroy this: Your hero gains +1 Intellect until end of turn. Battleworn. | Common |
| eq_crater_fist | Crater Fist | arms | 2 | Temper | Action -- {r}, destroy this: Your attacks with Crush get +2{p} this turn. Go again. Temper. | Common |

### 4.4 蛮兽装备

| ID | 名称 | 槽位 | 防御 | 关键词 | 能力 | 稀有度 |
|----|------|------|------|--------|------|--------|
| eq_skullhorn | Skullhorn | head | 0 | -- | Action -- Destroy this: Draw a card then discard a random card. Go again. Arcane Barrier 2. | Majestic |
| eq_barkbone_strapping | Barkbone Strapping | chest | 1 | Battleworn | Instant -- Destroy this: Roll a 6 sided die. Gain {r} equal to half the number rolled, rounded down. Battleworn. | Common |
| eq_scabskin_leathers | Scabskin Leathers | legs | 2 | Battleworn | Once per Turn Action -- {0}: Roll a 6 sided die. Gain action points equal to half the number rolled, rounded down. Battleworn. | Legendary |

### 4.5 通用装备

| ID | 名称 | 槽位 | 防御 | 关键词 | 能力 | 稀有度 |
|----|------|------|------|--------|------|--------|
| eq_fyendals_spring_tunic | Fyendal's Spring Tunic | chest | 1 | Blade Break | At the start of your turn, if this has less than 3 energy counters, you may put an energy counter on it. Instant -- Remove 3 energy counters: Gain {r}. Blade Break. | Legendary |
| eq_hope_merchants_hood | Hope Merchant's Hood | head | 0 | -- | Instant -- Destroy this: Shuffle any number of cards from your hand into your deck, then draw that many cards. | Common |
| eq_heartened_cross_strap | Heartened Cross Strap | chest | 0 | -- | Action -- Destroy this: The next attack action card you play this turn costs {2} less. Go again. | Common |
| eq_goliath_gauntlet | Goliath Gauntlet | arms | 0 | -- | Action -- Destroy this: The next attack action card with cost {2}+ you play this turn gains +2{p}. Go again. | Common |
| eq_snapdragon_scalers | Snapdragon Scalers | legs | 0 | -- | Attack Reaction -- Destroy this: Target attack action card with cost {1} or less gains go again. | Common |
| eq_ironrot_helm | Ironrot Helm | head | 1 | Blade Break | Blade Break. | Common |
| eq_ironrot_plate | Ironrot Plate | chest | 1 | Blade Break | Blade Break. | Common |
| eq_ironrot_gauntlet | Ironrot Gauntlet | arms | 1 | Blade Break | Blade Break. | Common |
| eq_ironrot_legs | Ironrot Legs | legs | 1 | Blade Break | Blade Break. | Common |

---

## 五、战士 (Warrior) 卡池

### 5.1 Dorinthea Specialization（专属卡）

#### SPEC_W01: Steelblade Supremacy (钢刃至上)

| 字段 | 值 |
|------|-----|
| id | `spec_steelblade_supremacy` |
| type | Non-Attack Action |
| class | warrior |
| pitch | 1 (Red) |
| cost | 1 |
| power | -- |
| defense | 3 |
| keywords | Go Again, Dorinthea Specialization |
| text | Until end of turn, target weapon you control gains +2{p} and "Whenever this weapon hits a hero, draw a card." Go again. |
| rarity | Majestic |

#### SPEC_W02: Singing Steelblade (歌唱钢刃)

| 字段 | 值 |
|------|-----|
| id | `spec_singing_steelblade` |
| type | Attack Reaction |
| class | warrior |
| pitch | 2 (Yellow) |
| cost | 1 |
| power | +1 (武器攻击) |
| defense | 3 |
| keywords | Reprise, Dorinthea Specialization |
| text | Target weapon attack gains +1{p}. Reprise -- If the defending hero has defended with a card from their hand this chain link, search your deck for an attack reaction card, banish it face up, then shuffle your deck. You may play it this chain link. |
| rarity | Majestic |

#### SPEC_W03: Ironsong Determination (铁歌决意)

| 字段 | 值 |
|------|-----|
| id | `spec_ironsong_determination` |
| type | Non-Attack Action |
| class | warrior |
| pitch | 2 (Yellow) |
| cost | 0 |
| power | -- |
| defense | 3 |
| keywords | Go Again, Dominate |
| text | Target weapon gets +1{p} and dominate until end of turn. Go again. |
| rarity | Super Rare |

### 5.2 Warrior 攻击行动卡

> **颜色规则**: 同名卡有红/黄/蓝三版本。红色 = Pitch 1（效果最强），蓝色 = Pitch 3（资源最多）。

#### WAR_ATK01: Wounding Blow (致伤打击) -- 白板攻击

| 颜色 | ID | Pitch | Cost | Power | Defense | 关键词 | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|--------|------|--------|
| Red | war_wounding_blow_r | 1 | 0 | **4** | 3 | -- | (无) | Common |
| Yellow | war_wounding_blow_y | 2 | 0 | **3** | 3 | -- | (无) | Common |
| Blue | war_wounding_blow_b | 3 | 0 | **2** | 3 | -- | (无) | Common |

### 5.3 Warrior 非攻击行动卡

#### WAR_ACT01: Sharpen Steel (磨砺钢刃)

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | war_sharpen_steel_r | 1 | 0 | -- | 3 | Your next weapon attack this turn gains +3{p}. Go again. | Common |
| Yellow | war_sharpen_steel_y | 2 | 0 | -- | 3 | ...gains +2{p}. Go again. | Common |
| Blue | war_sharpen_steel_b | 3 | 0 | -- | 3 | ...gains +1{p}. Go again. | Common |

**关键词**: Go Again

#### WAR_ACT02: Driving Blade (驱动之刃)

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | war_driving_blade_r | 1 | 2 | -- | 3 | Your next weapon attack this turn gains +3{p} and go again. Go again. | Common |
| Yellow | war_driving_blade_y | 2 | 2 | -- | 3 | ...gains +2{p} and go again. Go again. | Common |
| Blue | war_driving_blade_b | 3 | 2 | -- | 3 | ...gains +1{p} and go again. Go again. | Common |

**关键词**: Go Again

#### WAR_ACT03: Warrior's Valor (战士之勇)

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | war_warriors_valor_r | 1 | 0 | -- | 3 | Your next weapon attack gains +3{p} and "If this hits, the attack gains go again." Go again. | Common |
| Yellow | war_warriors_valor_y | 2 | 0 | -- | 3 | ...gains +2{p}... | Common |
| Blue | war_warriors_valor_b | 3 | 0 | -- | 3 | ...gains +1{p}... | Common |

**关键词**: Go Again

### 5.4 Warrior 攻击反应卡

#### WAR_AR01: Overpower (压倒)

| 颜色 | ID | Pitch | Cost | Bonus | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | war_overpower_r | 1 | 3 | +4 | 3 | Target weapon attack gains +4{p}. Reprise -- +2{p} additional. | Rare |
| Yellow | war_overpower_y | 2 | 3 | +3 | 3 | ...gains +3{p}. Reprise -- +2{p} additional. | Rare |
| Blue | war_overpower_b | 3 | 3 | +2 | 3 | ...gains +2{p}. Reprise -- +2{p} additional. | Rare |

**关键词**: Reprise

#### WAR_AR02: Ironsong Response (铁歌回应)

| 颜色 | ID | Pitch | Cost | Bonus | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | war_ironsong_response_r | 1 | 0 | +3 | 3 | Reprise -- Target weapon attack gains +3{p}. | Common |
| Yellow | war_ironsong_response_y | 2 | 0 | +2 | 3 | Reprise -- ...gains +2{p}. | Common |
| Blue | war_ironsong_response_b | 3 | 0 | +1 | 3 | Reprise -- ...gains +1{p}. | Common |

**关键词**: Reprise (无 Reprise 时无效果)

#### WAR_AR03: Biting Blade (噬咬之刃)

| 颜色 | ID | Pitch | Cost | Bonus | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | war_biting_blade_r | 1 | 0 | +3 | 3 | Target weapon attack gains +3{p}. Reprise -- Weapons you control gain +1{p} until end of turn. | Common |
| Yellow | war_biting_blade_y | 2 | 0 | +2 | 3 | ...gains +2{p}. Reprise -- ... | Common |
| Blue | war_biting_blade_b | 3 | 0 | +1 | 3 | ...gains +1{p}. Reprise -- ... | Common |

**关键词**: Reprise

### 5.5 Warrior 防御反应卡

#### WAR_DR01: Steelblade Shunt (钢刃挡击)

| 颜色 | ID | Pitch | Cost | Defense | 效果 | 稀有度 |
|------|-----|-------|------|---------|------|--------|
| Red | war_steelblade_shunt_r | 1 | 1 | **6** | If this defends a weapon attack, deal 1 damage to the attacking hero. | Rare |
| Yellow | war_steelblade_shunt_y | 2 | 1 | **5** | (同上) | Rare |
| Blue | war_steelblade_shunt_b | 3 | 1 | **4** | (同上) | Rare |

---

## 六、忍者 (Ninja) 卡池

### 6.1 Katsu Specialization（专属卡）

#### SPEC_N01: Mugenshi: RELEASE (无限·解放)

| 字段 | 值 |
|------|-----|
| id | `spec_mugenshi_release` |
| type | Attack Action |
| class | ninja |
| pitch | 2 (Yellow) -- 单版本 |
| cost | 1 |
| power | 4 |
| defense | 3 |
| keywords | Combo, Katsu Specialization |
| text | Combo -- If Whelming Gustwave was the last attack this combat chain, Mugenshi: RELEASE gains +1{p}, go again, and "If this hits, search your deck for any number of cards named Lord of Wind, reveal them, put them into your hand, then shuffle." |
| rarity | Super Rare |

#### SPEC_N02: Lord of Wind (风之主)

| 字段 | 值 |
|------|-----|
| id | `spec_lord_of_wind` |
| type | Attack Action |
| class | ninja |
| pitch | 3 (Blue) -- 单版本 |
| cost | 0 |
| power | 2 |
| defense | 3 |
| keywords | Combo, Katsu Specialization |
| text | Combo -- If Mugenshi: RELEASE was the last attack this combat chain, as an additional cost you may pay {X}. Shuffle X target Surging Strike / Whelming Gustwave / Mugenshi: RELEASE from your graveyard into your deck, then Lord of Wind gets +X{p}. |
| rarity | Majestic |

### 6.2 Ninja 攻击行动卡 -- 非 Combo（链条起手）

#### NIN_ATK01: Surging Strike (奔涌突击) -- Go Again 起手

| 颜色 | ID | Pitch | Cost | Power | Defense | 关键词 | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|--------|------|--------|
| Red | nin_surging_strike_r | 1 | 2 | **5** | 2 | Go Again | (无额外效果) | Common |
| Yellow | nin_surging_strike_y | 2 | 2 | **4** | 2 | Go Again | | Common |
| Blue | nin_surging_strike_b | 3 | 2 | **3** | 2 | Go Again | | Common |

> 触发: Whelming Gustwave 的 Combo 条件

#### NIN_ATK02: Head Jab (头击) -- 免费起手

| 颜色 | ID | Pitch | Cost | Power | Defense | 关键词 | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|--------|------|--------|
| Red | nin_head_jab_r | 1 | 0 | **3** | 2 | Go Again | (无) | Common |
| Yellow | nin_head_jab_y | 2 | 0 | **2** | 2 | Go Again | | Common |
| Blue | nin_head_jab_b | 3 | 0 | **1** | 2 | Go Again | | Common |

> 触发: Open the Center 的 Combo 条件

#### NIN_ATK03: Leg Tap (扫腿) -- 中等起手

| 颜色 | ID | Pitch | Cost | Power | Defense | 关键词 | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|--------|------|--------|
| Red | nin_leg_tap_r | 1 | 1 | **4** | 2 | Go Again | (无) | Common |
| Yellow | nin_leg_tap_y | 2 | 1 | **3** | 2 | Go Again | | Common |
| Blue | nin_leg_tap_b | 3 | 1 | **2** | 2 | Go Again | | Common |

> 触发: Rising Knee Thrust 的 Combo 条件

### 6.3 Ninja Combo 链卡

#### NIN_CMB01: Whelming Gustwave (涌风浪) -- Combo off Surging Strike

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | nin_whelming_gustwave_r | 1 | 0 | **3** | 3 | Combo(Surging Strike): +1{p}, go again, "If this hits, draw a card." | Common |
| Yellow | nin_whelming_gustwave_y | 2 | 0 | **2** | 3 | (同上，但基础 power 不同) | Common |
| Blue | nin_whelming_gustwave_b | 3 | 0 | **1** | 3 | | Common |

**关键词**: Combo

#### NIN_CMB02: Rising Knee Thrust (飞膝击) -- Combo off Leg Tap

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | nin_rising_knee_thrust_r | 1 | 0 | **3** | 3 | Combo(Leg Tap): +2{p}, go again. | Common |
| Yellow | nin_rising_knee_thrust_y | 2 | 0 | **2** | 3 | | Common |
| Blue | nin_rising_knee_thrust_b | 3 | 0 | **1** | 3 | | Common |

**关键词**: Combo

#### NIN_CMB03: Open the Center (攻破中路) -- Combo off Head Jab

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | nin_open_the_center_r | 1 | 2 | **5** | 3 | Combo(Head Jab): +1{p}, go again, dominate. | Common |
| Yellow | nin_open_the_center_y | 2 | 2 | **4** | 3 | | Rare |
| Blue | nin_open_the_center_b | 3 | 2 | **3** | 3 | | Rare |

**关键词**: Combo, (Dominate 条件获得)

#### NIN_CMB04: Blackout Kick (断电飞踢) -- Combo off Rising Knee Thrust

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | nin_blackout_kick_r | 1 | 1 | **4** | 3 | Combo(Rising Knee Thrust): +3{p}. | Rare |
| Yellow | nin_blackout_kick_y | 2 | 1 | **3** | 3 | | Rare |
| Blue | nin_blackout_kick_b | 3 | 1 | **2** | 3 | | Rare |

**关键词**: Combo

#### NIN_CMB05: Hurricane Technique (飓风技) -- Combo off Rising Knee Thrust

| ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|-----|-------|------|-------|---------|------|--------|
| nin_hurricane_technique | 2 (Yellow) 单版本 | 1 | **4** | 3 | Combo(Rising Knee Thrust): +1{p}, go again, "If this hits, put it into your hand." | Super Rare |

#### NIN_CMB06: Pounding Gale (猛击飓风) -- Combo off Open the Center

| ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|-----|-------|------|-------|---------|------|--------|
| nin_pounding_gale | 1 (Red) 单版本 | 1 | **5** | 3 | Combo(Open the Center): "If this would deal damage to a hero, instead it deals double that much damage." | Super Rare |

### 6.4 Ninja 反应卡

#### NIN_AR01: Ancestral Empowerment (祖传赋能) -- 攻击反应

| 颜色 | ID | Pitch | Cost | Bonus | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | nin_ancestral_empowerment_r | 1 | 0 | +1 | 3 | Target Ninja attack action card gets +1{p}. Draw a card. | Common |
| Yellow | nin_ancestral_empowerment_y | 2 | 0 | +1 | 3 | (同上) | Common |
| Blue | nin_ancestral_empowerment_b | 3 | 0 | +1 | 3 | (同上) | Common |

> **注意**: 三色版本 bonus 相同（均为 +1），仅 pitch 不同。

#### NIN_DR01: Flic Flak (闪避反击) -- 防御反应

| 颜色 | ID | Pitch | Cost | Defense | 效果 | 稀有度 |
|------|-----|-------|------|---------|------|--------|
| Red | nin_flic_flak_r | 1 | 0 | **4** | If the next card you defend with this turn has combo, it gains +2 Defense. | Rare |
| Yellow | nin_flic_flak_y | 2 | 0 | **4** | (同上) | Rare |
| Blue | nin_flic_flak_b | 3 | 0 | **4** | (同上) | Rare |

### 6.5 Combo 链路速查

```
链 A (Katsu 核心链):
  Surging Strike → Whelming Gustwave → [SPEC] Mugenshi: RELEASE → [SPEC] Lord of Wind

链 B (踢击链):
  Leg Tap → Rising Knee Thrust → Blackout Kick / Hurricane Technique

链 C (头击链):
  Head Jab → Open the Center → Pounding Gale
```

---

## 七、守护者 (Guardian) 卡池

### 7.1 Bravo Specialization（专属卡）

#### SPEC_G01: Crippling Crush (残废粉碎)

| 字段 | 值 |
|------|-----|
| id | `spec_crippling_crush` |
| type | Attack Action |
| class | guardian |
| pitch | 1 (Red) -- 单版本 |
| cost | 7 |
| power | **11** |
| defense | 3 |
| keywords | Crush, Bravo Specialization |
| text | Crush -- If this deals 4 or more damage to a hero, they discard 2 random cards. |
| rarity | Majestic |

#### SPEC_G02: Show Time! (表演时间!)

| 字段 | 值 |
|------|-----|
| id | `spec_show_time` |
| type | Non-Attack Action (Aura) |
| class | guardian |
| pitch | 3 (Blue) -- 单版本 |
| cost | 3 |
| power | -- |
| defense | 3 |
| keywords | Bravo Specialization |
| text | When this enters the arena, search your deck for a Guardian attack action card, reveal it, put it into your hand, then shuffle. At the beginning of your action phase, destroy this, then draw a card. |
| rarity | Super Rare |

### 7.2 Guardian 攻击行动卡

> **守护者特点**: 高费用、高攻击力、所有攻击牌都带 Crush 关键词。防御值统一为 3。

#### GUA_ATK01: Spinal Crush (脊椎粉碎) -- 单版本

| ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|-----|-------|------|-------|---------|------|--------|
| gua_spinal_crush | 1 (Red) | 5 | **9** | 3 | Crush: 4+ 伤害时，对手下回合行动卡/激活能力/攻击失去且不能获得 go again。 | Majestic |

#### GUA_ATK02: Cranial Crush (颅骨粉碎) -- 单版本

| ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|-----|-------|------|-------|---------|------|--------|
| gua_cranial_crush | 3 (Blue) | 6 | **8** | 3 | Crush: 4+ 伤害时，对手下回合不能抽牌。 | Super Rare |

#### GUA_ATK03: Disable (瘫痪)

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | gua_disable_r | 1 | 5 | **9** | 3 | Crush: 4+ 伤害时，将对手军械库中 1 张牌放到牌库底。 | Rare |
| Yellow | gua_disable_y | 2 | 5 | **8** | 3 | | Rare |
| Blue | gua_disable_b | 3 | 5 | **7** | 3 | | Rare |

**关键词**: Crush

#### GUA_ATK04: Buckling Blow (扣压之击)

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | gua_buckling_blow_r | 1 | 4 | **8** | 3 | Crush: 4+ 伤害时，对手 1 件装备获得 -1 防御标记。 | Common |
| Yellow | gua_buckling_blow_y | 2 | 4 | **7** | 3 | | Common |
| Blue | gua_buckling_blow_b | 3 | 4 | **6** | 3 | | Common |

**关键词**: Crush

#### GUA_ATK05: Cartilage Crush (软骨粉碎)

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | gua_cartilage_crush_r | 1 | 3 | **7** | 3 | Crush: 4+ 伤害时，对手下回合第一个行动额外支付 {r}。 | Common |
| Yellow | gua_cartilage_crush_y | 2 | 3 | **6** | 3 | | Common |
| Blue | gua_cartilage_crush_b | 3 | 3 | **5** | 3 | | Common |

**关键词**: Crush

#### GUA_ATK06: Crush Confidence (碎裂信心)

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | gua_crush_confidence_r | 1 | 3 | **7** | 3 | Crush: 4+ 伤害时，对手失去英雄卡效果和激活能力直到下回合结束。 | Common |
| Yellow | gua_crush_confidence_y | 2 | 3 | **6** | 3 | | Common |
| Blue | gua_crush_confidence_b | 3 | 3 | **5** | 3 | | Common |

**关键词**: Crush

#### GUA_ATK07: Debilitate (衰弱)

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | gua_debilitate_r | 1 | 4 | **8** | 3 | Crush: 4+ 伤害时，对手下回合第一次攻击 -2{p}。 | Common |
| Yellow | gua_debilitate_y | 2 | 4 | **7** | 3 | | Common |
| Blue | gua_debilitate_b | 3 | 4 | **6** | 3 | | Common |

**关键词**: Crush

### 7.3 Guardian 非攻击行动卡（光环 Aura）

#### GUA_ACT01: Forged for War (战争锻造) -- 单版本

| ID | Pitch | Cost | Defense | 效果 | 稀有度 |
|-----|-------|------|---------|------|--------|
| gua_forged_for_war | 2 (Yellow) | 2 | 3 | Go again. While this is in the arena, equipment you control gain +1 Defense. Destroy at beginning of your action phase. | Super Rare |

#### GUA_ACT02: Blessing of Deliverance (解救祝福)

| 颜色 | ID | Pitch | Cost | Defense | 效果 | 稀有度 |
|------|-----|-------|------|---------|------|--------|
| Red | gua_blessing_of_deliverance_r | 1 | 2 | 3 | Go again. On enter: if pitch zone has cost 3+ card, draw 1. Destroy next action phase: reveal top 3 cards, gain 1 life per cost 3+ card. | Rare |
| Yellow | gua_blessing_of_deliverance_y | 2 | 2 | 3 | ...reveal top 2 cards... | Rare |
| Blue | gua_blessing_of_deliverance_b | 3 | 2 | 3 | ...reveal top 1 card... | Rare |

**关键词**: Go Again

#### GUA_ACT03: Emerging Power (涌现之力)

| 颜色 | ID | Pitch | Cost | Defense | 效果 | 稀有度 |
|------|-----|-------|------|---------|------|--------|
| Red | gua_emerging_power_r | 1 | 0 | 3 | Go again. Destroy next action phase: next Guardian attack action card gains +3{p}. | Common |
| Yellow | gua_emerging_power_y | 2 | 0 | 3 | ...gains +2{p}. | Common |
| Blue | gua_emerging_power_b | 3 | 0 | 3 | ...gains +1{p}. | Common |

**关键词**: Go Again

#### GUA_ACT04: Stonewall Confidence (石墙信心)

| 颜色 | ID | Pitch | Cost | Defense | 效果 | 稀有度 |
|------|-----|-------|------|---------|------|--------|
| Red | gua_stonewall_confidence_r | 1 | 2 | 3 | While in arena, your cards with cost 3+ gain +4 Defense while defending. Destroy next action phase. | Common |
| Yellow | gua_stonewall_confidence_y | 2 | 2 | 3 | ...gain +3 Defense... | Common |
| Blue | gua_stonewall_confidence_b | 3 | 2 | 3 | ...gain +2 Defense... | Common |

### 7.4 Guardian 防御反应卡

#### GUA_DR01: Staunch Response (坚定回应)

| 颜色 | ID | Pitch | Cost | Defense | 效果 | 稀有度 |
|------|-----|-------|------|---------|------|--------|
| Red | gua_staunch_response_r | 1 | 2 | **7** | As additional cost, you may pay {r}{r}{r}{r}. If you do, +3 Defense. | Rare |
| Yellow | gua_staunch_response_y | 2 | 2 | **6** | (同上) | Rare |
| Blue | gua_staunch_response_b | 3 | 2 | **5** | (同上) | Rare |

---

## 八、蛮兽 (Brute) 卡池

### 8.1 Rhinar Specialization（专属卡）

#### SPEC_B01: Alpha Rampage (首领狂暴)

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | spec_alpha_rampage_r | 1 | 3 | **9** | 3 | As additional cost, discard a random card. Intimidate. | Majestic |
| Yellow | spec_alpha_rampage_y | 2 | 3 | **9** | 3 | (同上) | Majestic |
| Blue | spec_alpha_rampage_b | 3 | 3 | **9** | 3 | (同上) | Majestic |

> **异常**: 三色版本 Power/Cost/Defense 完全相同（仅 Pitch 不同）。

**关键词**: Intimidate, Rhinar Specialization

#### SPEC_B02: Sand Sketched Plan (沙绘计划) -- 单版本

| 字段 | 值 |
|------|-----|
| id | `spec_sand_sketched_plan` |
| type | Non-Attack Action |
| class | brute |
| pitch | 3 (Blue) |
| cost | 0 |
| power | -- |
| defense | 3 |
| keywords | Rhinar Specialization |
| text | Search your deck for a card, put it into your hand, discard a random card, then shuffle. If the discarded card has 6+ Power, gain 2 action points. |
| rarity | Super Rare |

### 8.2 Brute 攻击行动卡

#### BRU_ATK01: Pack Hunt (群猎)

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | bru_pack_hunt_r | 1 | 2 | **6** | 3 | Intimidate. | Common |
| Yellow | bru_pack_hunt_y | 2 | 2 | **5** | 3 | | Common |
| Blue | bru_pack_hunt_b | 3 | 2 | **4** | 3 | | Common |

**关键词**: Intimidate

#### BRU_ATK02: Smash Instinct (粉碎本能)

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | bru_smash_instinct_r | 1 | 3 | **7** | 3 | Intimidate. | Common |
| Yellow | bru_smash_instinct_y | 2 | 3 | **6** | 3 | | Common |
| Blue | bru_smash_instinct_b | 3 | 3 | **5** | 3 | | Common |

**关键词**: Intimidate

#### BRU_ATK03: Wrecker Romp (破坏狂暴)

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | bru_wrecker_romp_r | 1 | 2 | **8** | 3 | As additional cost, discard a random card. | Common |
| Yellow | bru_wrecker_romp_y | 2 | 2 | **7** | 3 | | Common |
| Blue | bru_wrecker_romp_b | 3 | 2 | **6** | 3 | | Common |

> Wrecker Romp (Blue) Power 6，被弃掉时可触发 Rhinar 英雄能力。

#### BRU_ATK04: Savage Swing (蛮荒挥击)

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | bru_savage_swing_r | 1 | 1 | **7** | 3 | As additional cost, discard a random card. | Common |
| Yellow | bru_savage_swing_y | 2 | 1 | **6** | 3 | | Common |
| Blue | bru_savage_swing_b | 3 | 1 | **5** | 3 | | Common |

#### BRU_ATK05: Savage Feast (蛮荒盛宴)

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | bru_savage_feast_r | 1 | 1 | **6** | 3 | As additional cost, discard a random card. If the discarded card has 6+ Power, draw a card. | Common |
| Yellow | bru_savage_feast_y | 2 | 1 | **5** | 3 | | Common |
| Blue | bru_savage_feast_b | 3 | 1 | **4** | 3 | | Common |

#### BRU_ATK06: Breakneck Battery (破颈电池)

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | bru_breakneck_battery_r | 1 | 2 | **6** | 3 | As additional cost, discard a random card. If the discarded card has 6+ Power, Breakneck Battery gains go again. | Common |
| Yellow | bru_breakneck_battery_y | 2 | 2 | **5** | 3 | | Common |
| Blue | bru_breakneck_battery_b | 3 | 2 | **4** | 3 | | Common |

### 8.3 Brute 非攻击行动卡

#### BRU_ACT01: Awakening Bellow (觉醒怒吼)

| 颜色 | ID | Pitch | Cost | Defense | 效果 | 稀有度 |
|------|-----|-------|------|---------|------|--------|
| Red | bru_awakening_bellow_r | 1 | 1 | 3 | Next Brute attack gains +3{p}. Intimidate. Go again. | Common |
| Yellow | bru_awakening_bellow_y | 2 | 1 | 3 | ...+2{p}... | Common |
| Blue | bru_awakening_bellow_b | 3 | 1 | 3 | ...+1{p}... | Common |

**关键词**: Go Again, Intimidate

#### BRU_ACT02: Barraging Beatdown (弹幕暴打)

| 颜色 | ID | Pitch | Cost | Defense | 效果 | 稀有度 |
|------|-----|-------|------|---------|------|--------|
| Red | bru_barraging_beatdown_r | 1 | 0 | 3 | Next Brute attack: if defended by fewer than 2 non-equipment cards, +4{p}. Intimidate. Go again. | Rare |
| Yellow | bru_barraging_beatdown_y | 2 | 0 | 3 | ...+3{p}... | Rare |
| Blue | bru_barraging_beatdown_b | 3 | 0 | 3 | ...+2{p}... | Rare |

**关键词**: Go Again, Intimidate

#### BRU_ACT03: Bloodrush Bellow (血涌怒吼) -- 单版本

| ID | Pitch | Cost | Defense | 效果 | 稀有度 |
|-----|-------|------|---------|------|--------|
| bru_bloodrush_bellow | 2 (Yellow) | 1 | 3 | As additional cost, discard a random card. Your Brute attacks gain +2{p} this turn. If discarded card has 6+ Power, draw 2 cards and this gains go again. | Common |

#### BRU_ACT04: Primeval Bellow (原始怒吼)

| 颜色 | ID | Pitch | Cost | Defense | 效果 | 稀有度 |
|------|-----|-------|------|---------|------|--------|
| Red | bru_primeval_bellow_r | 1 | 0 | 3 | As additional cost, discard a random card. Next Brute attack gains +5{p}. Go again. | Common |
| Yellow | bru_primeval_bellow_y | 2 | 0 | 3 | ...+4{p}... | Common |
| Blue | bru_primeval_bellow_b | 3 | 0 | 3 | ...+3{p}... | Common |

**关键词**: Go Again

### 8.4 Brute 防御反应卡

#### BRU_DR01: Reckless Swing (鲁莽挥砍) -- 单版本

| ID | Pitch | Cost | Defense | 效果 | 稀有度 |
|-----|-------|------|---------|------|--------|
| bru_reckless_swing | 3 (Blue) | 0 | **4** | As additional cost, discard a random card. If discarded card has 6+ Power, deal 2 damage to the attacking hero. | Common |

### 8.5 Brute 瞬发牌

#### BRU_INS01: Bone Head Barrier (骨头壁障) -- 单版本

| ID | Pitch | Cost | Defense | 效果 | 稀有度 |
|-----|-------|------|---------|------|--------|
| bru_bone_head_barrier | 2 (Yellow) | 1 | -- | Roll a 6 sided die. Prevent the next X damage that would be dealt to your hero this turn (X = number rolled). | Common |

---

## 九、通用 (Generic) 卡池

> 通用牌所有英雄都可使用，是牌组构建的基石。

### 9.1 通用攻击行动卡

#### GEN_ATK01: Wounding Blow (致伤打击) -- 白板

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | gen_wounding_blow_r | 1 | 0 | **4** | 3 | (无) | Common |
| Yellow | gen_wounding_blow_y | 2 | 0 | **3** | 3 | (无) | Common |
| Blue | gen_wounding_blow_b | 3 | 0 | **2** | 3 | (无) | Common |

> **注意**: Wounding Blow 同时列在 Warrior 卡池中。在 FaB 中它实际是 Generic 卡。

#### GEN_ATK02: Enlightened Strike (启迪一击) -- 单版本

| ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|-----|-------|------|-------|---------|------|--------|
| gen_enlightened_strike | 1 (Red) | 0 | **5** | 3 | As additional cost, put a card from hand on bottom of deck. Choose 1: draw a card; +2{p}; go again. | Majestic |

#### GEN_ATK03: Snatch (抢夺)

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | gen_snatch_r | 1 | 1 | **4** | 2 | If this hits, draw a card. | Rare |
| Yellow | gen_snatch_y | 2 | 1 | **3** | 2 | | Rare |
| Blue | gen_snatch_b | 3 | 1 | **2** | 2 | | Rare |

#### GEN_ATK04: Nimble Strike (灵巧突袭)

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | gen_nimble_strike_r | 1 | 1 | **4** | 2 | May banish Nimblism from graveyard: +1{p} and go again. | Common |
| Yellow | gen_nimble_strike_y | 2 | 1 | **3** | 2 | | Common |
| Blue | gen_nimble_strike_b | 3 | 1 | **3** | 2 | | Common |

#### GEN_ATK05: Raging Onslaught (怒火猛攻) -- 白板

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | gen_raging_onslaught_r | 1 | 3 | **7** | 3 | (无) | Common |
| Yellow | gen_raging_onslaught_y | 2 | 3 | **6** | 3 | (无) | Common |
| Blue | gen_raging_onslaught_b | 3 | 3 | **5** | 3 | (无) | Common |

#### GEN_ATK06: Scar for a Scar (以伤报伤)

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | gen_scar_for_a_scar_r | 1 | 0 | **4** | 2 | If you have less Life than opponent, gains go again. | Common |
| Yellow | gen_scar_for_a_scar_y | 2 | 0 | **3** | 2 | | Common |
| Blue | gen_scar_for_a_scar_b | 3 | 0 | **2** | 2 | | Common |

#### GEN_ATK07: Wounded Bull (受伤公牛)

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | gen_wounded_bull_r | 1 | 3 | **7** | 2 | If you have less Life than opponent, +1{p}. | Common |
| Yellow | gen_wounded_bull_y | 2 | 3 | **6** | 2 | | Common |
| Blue | gen_wounded_bull_b | 3 | 3 | **5** | 2 | | Common |

#### GEN_ATK08: Scour the Battlescape (扫视战场)

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | gen_scour_the_battlescape_r | 1 | 0 | **3** | 2 | May put 1 hand card on deck bottom, draw 1. If played from arsenal, gains go again. | Common |
| Yellow | gen_scour_the_battlescape_y | 2 | 0 | **2** | 2 | | Common |
| Blue | gen_scour_the_battlescape_b | 3 | 0 | **1** | 2 | | Common |

#### GEN_ATK09: Regurgitating Slog (回流之击)

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | gen_regurgitating_slog_r | 1 | 2 | **6** | 2 | May banish Sloggism from graveyard: gains dominate. | Common |
| Yellow | gen_regurgitating_slog_y | 2 | 2 | **5** | 2 | | Common |
| Blue | gen_regurgitating_slog_b | 3 | 2 | **4** | 2 | | Common |

#### GEN_ATK10: Barraging Brawnhide (弹幕厚皮)

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | gen_barraging_brawnhide_r | 1 | 3 | **7** | 2 | If defended by fewer than 2 non-equipment cards, +1{p}. | Common |
| Yellow | gen_barraging_brawnhide_y | 2 | 3 | **6** | 2 | | Common |
| Blue | gen_barraging_brawnhide_b | 3 | 3 | **5** | 2 | | Common |

#### GEN_ATK11: Drone of Brutality (残暴无人机)

| 颜色 | ID | Pitch | Cost | Power | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | gen_drone_of_brutality_r | 1 | 0 | **6** | 2 | If this would go to graveyard, put it on bottom of deck instead. | Rare |
| Yellow | gen_drone_of_brutality_y | 2 | 1 | **5** | 2 | | Rare |
| Blue | gen_drone_of_brutality_b | 3 | 2 | **4** | 2 | | Rare |

### 9.2 通用攻击反应卡

#### GEN_AR01: Pummel (猛击)

| 颜色 | ID | Pitch | Cost | Bonus | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | gen_pummel_r | 1 | 0 | +4 | 2 | Choose 1: club/hammer weapon attack +N{p}; OR attack action card with cost 2+ gains +N{p} and "If this hits, defending hero discards a card." | Common |
| Yellow | gen_pummel_y | 2 | 0 | +3 | 2 | | Common |
| Blue | gen_pummel_b | 3 | 0 | +2 | 2 | | Common |

#### GEN_AR02: Razor Reflex (剃刀反射)

| 颜色 | ID | Pitch | Cost | Bonus | Defense | 效果 | 稀有度 |
|------|-----|-------|------|-------|---------|------|--------|
| Red | gen_razor_reflex_r | 1 | 0 | +3 | 2 | Choose 1: sword/dagger weapon attack +N{p}; OR attack action card with cost 1 or less gains +N{p} and "If this hits, gains go again." | Common |
| Yellow | gen_razor_reflex_y | 2 | 0 | +2 | 2 | | Common |
| Blue | gen_razor_reflex_b | 3 | 0 | +1 | 2 | | Common |

### 9.3 通用防御反应卡

#### GEN_DR01: Unmovable (不动如山)

| 颜色 | ID | Pitch | Cost | Defense | 效果 | 稀有度 |
|------|-----|-------|------|---------|------|--------|
| Red | gen_unmovable_r | 1 | 0 | **7** | If played from arsenal, +1 Defense. | Common |
| Yellow | gen_unmovable_y | 2 | 0 | **6** | | Common |
| Blue | gen_unmovable_b | 3 | 0 | **5** | | Common |

#### GEN_DR02: Sink Below (下沉闪避)

| 颜色 | ID | Pitch | Cost | Defense | 效果 | 稀有度 |
|------|-----|-------|------|---------|------|--------|
| Red | gen_sink_below_r | 1 | 0 | **4** | May put 1 hand card on deck bottom. If you do, draw a card. | Common |
| Yellow | gen_sink_below_y | 2 | 0 | **3** | | Common |
| Blue | gen_sink_below_b | 3 | 0 | **2** | | Common |

### 9.4 通用非攻击行动卡（Aura / Item）

#### GEN_ACT01: Nimblism (轻捷之态) -- Aura

| 颜色 | ID | Pitch | Cost | Defense | 效果 | 稀有度 |
|------|-----|-------|------|---------|------|--------|
| Red | gen_nimblism_r | 1 | 0 | 2 | Next attack action card with cost 1 or less gains +3{p}. Go again. | Common |
| Yellow | gen_nimblism_y | 2 | 0 | 2 | ...+2{p}... | Common |
| Blue | gen_nimblism_b | 3 | 0 | 2 | ...+1{p}... | Common |

#### GEN_ACT02: Sloggism (重击之态) -- Aura

| 颜色 | ID | Pitch | Cost | Defense | 效果 | 稀有度 |
|------|-----|-------|------|---------|------|--------|
| Red | gen_sloggism_r | 1 | 0 | 2 | Next attack action card with cost 2+ gains +6{p}. Go again. | Common |
| Yellow | gen_sloggism_y | 2 | 0 | 2 | ...+5{p}... | Common |
| Blue | gen_sloggism_b | 3 | 0 | 2 | ...+4{p}... | Common |

#### GEN_ACT03: Energy Potion (能量药水) -- Item

| ID | Pitch | Cost | Defense | 效果 | 稀有度 |
|-----|-------|------|---------|------|--------|
| gen_energy_potion | 3 (Blue) | 0 | -- | Instant -- Destroy this: Gain {2 Resources}. | Rare |

#### GEN_ACT04: Potion of Strength (力量药水) -- Item

| ID | Pitch | Cost | Defense | 效果 | 稀有度 |
|-----|-------|------|---------|------|--------|
| gen_potion_of_strength | 3 (Blue) | 0 | -- | Action -- Destroy this: Your next attack gains +2{p}. Go again. | Rare |

#### GEN_ACT05: Tome of Fyendal (费恩达尔之书) -- 单版本

| ID | Pitch | Cost | Defense | 效果 | 稀有度 |
|-----|-------|------|---------|------|--------|
| gen_tome_of_fyendal | 2 (Yellow) | 0 | 2 | Draw 2 cards. If played from arsenal, gain 1 Life for each card in your hand. | Super Rare |

### 9.5 通用瞬发卡

#### GEN_INS01: Sigil of Solace (慰籍徽记)

| 颜色 | ID | Pitch | Cost | Defense | 效果 | 稀有度 |
|------|-----|-------|------|---------|------|--------|
| Red | gen_sigil_of_solace_r | 1 | 0 | -- | Gain 3 Life. | Common |
| Yellow | gen_sigil_of_solace_y | 2 | 0 | -- | Gain 2 Life. | Common |
| Blue | gen_sigil_of_solace_b | 3 | 0 | -- | Gain 1 Life. | Common |

---

## 十、Token 列表

游戏中由卡牌效果生成的 Token：

| Token | 类型 | 来源 | 效果 |
|-------|------|------|------|
| **Seismic Surge** | Aura | Guardian (Tectonic Plating) | When you play an attack action card or use a weapon attack with cost 3+, you may destroy this: the attack gains +1{p}. |
| **Might** | Aura | 部分卡牌效果 | 消耗时给攻击 +1{p}。 |
| **Quicken** | Aura | 部分卡牌效果 | 获得 1 个额外行动点。 |

---

## 十一、数据模型字段定义

### 11.1 卡牌通用字段

```
Card {
  id: string              -- 唯一标识 (如 "war_wounding_blow_r")
  name: string            -- 英文名 (如 "Wounding Blow")
  name_cn: string         -- 中文名 (如 "致伤打击")
  cardType: string        -- 卡牌大类: "hero" | "weapon" | "equipment" | "attack_action" | "non_attack_action" | "attack_reaction" | "defense_reaction" | "instant" | "item" | "aura"
  subtype: string?        -- 子类型: "sword" | "dagger" | "hammer" | "club" | "head" | "chest" | "arms" | "legs" | null
  class: string           -- 职业: "warrior" | "ninja" | "guardian" | "brute" | "generic"
  specialization: string? -- 专属英雄: "dorinthea" | "katsu" | "bravo" | "rhinar" | null
  pitch: number           -- Pitch 值: 0(无) | 1(红) | 2(黄) | 3(蓝)
  cost: number            -- 使用费用
  power: number?          -- 攻击力 (攻击牌/武器才有)
  defense: number?        -- 防御值 (几乎所有牌都有)
  keywords: string[]      -- 关键词列表: ["Go Again", "Dominate", "Intimidate", "Combo", "Crush", "Reprise", ...]
  text: string            -- 效果描述 (英文)
  text_cn: string         -- 效果描述 (中文) -- 后续翻译填入
  rarity: string          -- 稀有度: "common" | "rare" | "super_rare" | "majestic" | "legendary" | "fabled" | "token"
  goAgain: boolean        -- 是否固有 Go Again
  comboFrom: string?      -- Combo 前置条件卡名 (仅 Combo 卡)
  pitchColor: string      -- Pitch 颜色标识: "red" | "yellow" | "blue" | "none"
}
```

### 11.2 英雄字段

```
Hero extends Card {
  life: number            -- 生命值
  intellect: number       -- 智力值
  ability: string         -- 英雄能力描述
}
```

### 11.3 武器字段

```
Weapon extends Card {
  hands: number           -- 手数: 1 | 2
  activationCost: number  -- 激活费用 (pitch 支付)
}
```

### 11.4 装备字段

```
Equipment extends Card {
  slot: string            -- 槽位: "head" | "chest" | "arms" | "legs"
}
```

---

## 十二、卡池统计

### 按类别统计

| 类别 | 数量 | 说明 |
|------|------|------|
| 英雄卡 | 4 | 4 职业各 1 位 |
| 武器卡 | 5 | 含忍者双持 x2 |
| 装备卡 | 21 | 职业装备 + 通用装备 |
| 战士攻击行动 | 3 张 (红/黄/蓝各 1 = 白板) | |
| 战士非攻击行动 | 9 张 (3 种 x 3 色) | |
| 战士攻击反应 | 9 张 (3 种 x 3 色) | |
| 战士防御反应 | 3 张 (1 种 x 3 色) | |
| 战士专属 | 3 张 | |
| 忍者攻击行动 (非Combo) | 9 张 (3 种 x 3 色) | |
| 忍者 Combo 链卡 | 14 张 (4种x3色 + 2种单版本) | |
| 忍者反应 | 6 张 (2 种 x 3 色) | |
| 忍者专属 | 2 张 | |
| 守护者攻击行动 | 17 张 (5种x3色 + 2种单版本) | |
| 守护者非攻击行动 | 11 张 (3种x3色 + 2种单版本) | |
| 守护者防御反应 | 3 张 (1 种 x 3 色) | |
| 守护者专属 | 2 张 | |
| 蛮兽攻击行动 | 18 张 (6 种 x 3 色) | |
| 蛮兽非攻击行动 | 11 张 (3种x3色 + 1种单色 + 1种单版本) | |
| 蛮兽防御反应 | 1 张 (单版本) | |
| 蛮兽瞬发 | 1 张 (单版本) | |
| 蛮兽专属 | 4 张 (1种x3色 + 1种单版本) | |
| 通用攻击行动 | 31 张 | |
| 通用攻击反应 | 6 张 (2 种 x 3 色) | |
| 通用防御反应 | 6 张 (2 种 x 3 色) | |
| 通用非攻击行动 | 9 张 | |
| 通用瞬发 | 3 张 (1 种 x 3 色) | |
| Token | 3 | Seismic Surge, Might, Quicken |

### 按职业可用卡池

每个英雄可用的卡: **本职业卡 + 通用卡**

| 英雄 | 职业卡 | 专属卡 | 通用卡 | 合计可选 |
|------|--------|--------|--------|---------|
| Dorinthea | ~27 | 3 | ~55 | ~85 |
| Katsu | ~31 | 2 | ~55 | ~88 |
| Bravo | ~33 | 2 | ~55 | ~90 |
| Rhinar | ~35 | 4 | ~55 | ~94 |

> 闪电战牌组: 从可选卡池中选 40 张 + 武器 + 装备

---

## 附录 A: 关键词效果速查

| 关键词 | 效果 |
|--------|------|
| **Go Again** | 解算后获得 1 个行动点 |
| **Dominate** | 对手只能用 1 张手牌防御 |
| **Intimidate** | 随机放逐对手 1 张手牌（回合结束返回） |
| **Combo (X)** | 如果 X 是本战斗链上一次攻击，触发额外效果 |
| **Crush** | 如果此攻击造成 4+ 伤害，触发额外效果 |
| **Reprise** | 如果防御方用手牌防御了，触发额外效果 |
| **Battleworn** | 用此装备防御后，放 -1 防御标记 |
| **Blade Break** | 用此装备防御后，战斗链关闭时销毁 |
| **Temper** | 防御后放 -1 防御标记，防御值为 0 时销毁 |
| **Arcane Barrier X** | 支付 X 资源防御 X 点奥术伤害 |

## 附录 B: 需验证的数据

以下数据在多个来源间存在不一致，建议与 [cards.fabtcg.com](https://cards.fabtcg.com) 交叉验证：

1. Biting Blade 的 Cost 值（部分来源显示 Cost 2，其他显示 Cost 0）
2. Ironsong Determination 是否为 Dorinthea Specialization（部分来源列为 Warrior 通用）
3. Drone of Brutality 红/黄/蓝版本的 Cost 差异（非标准模式）
4. Nimble Strike 蓝色版本 Power 是否为 2 或 3
5. Alpha Rampage 三色版本是否真的 Power/Cost 完全相同

---

## 附录 C: 开源数据源推荐

用于自动化数据导入和验证：

- **[the-fab-cube/flesh-and-blood-cards](https://github.com/the-fab-cube/flesh-and-blood-cards)** -- GitHub 上最完整的 FaB 卡牌 JSON/CSV 数据集
- **[@flesh-and-blood/cards](https://github.com/fabrary/cards)** -- NPM 包，提供类型化卡牌数据
- **[cards.fabtcg.com](https://cards.fabtcg.com)** -- 官方数据库（真理来源）

---

*文档结束*

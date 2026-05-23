# 《轻拳飞扬》换皮对照表

> 基于 `fab-cardpool-v1.md` 的完整换皮映射
> 本文件是独立参考表，不修改原始卡池数据

---

## 一、装备槽位合并映射

### 规则

| FAB 原槽位 | → 本作槽位 |
|-----------|-----------|
| head（头） | 上半身 |
| chest（胸） | 上半身 |
| arms（臂） | 上半身 |
| legs（腿） | 下半身 |

### 全装备槽位映射

#### 剑道（Warrior）装备

| FAB ID | FAB 名称 | 原槽位 | → 本作槽位 |
|--------|---------|--------|-----------|
| eq_braveforge_bracers | Braveforge Bracers | arms | 上半身 |
| eq_courage_of_bladehold | Courage of Bladehold | chest | 上半身 |
| eq_refraction_bolters | Refraction Bolters | legs | 下半身 |

#### 跆拳道（Ninja）装备

| FAB ID | FAB 名称 | 原槽位 | → 本作槽位 |
|--------|---------|--------|-----------|
| eq_mask_of_momentum | Mask of Momentum | head | 上半身 |
| eq_breaking_scales | Breaking Scales | arms | 上半身 |

> 跆拳道缺 legs 装备，无下半身专属护具，使用通用护具补位。

#### 太极（Guardian）装备

| FAB ID | FAB 名称 | 原槽位 | → 本作槽位 |
|--------|---------|--------|-----------|
| eq_tectonic_plating | Tectonic Plating | chest | 上半身 |
| eq_helm_of_isens_peak | Helm of Isen's Peak | head | 上半身 |
| eq_crater_fist | Crater Fist | arms | 上半身 |

> 太极缺 legs 装备，无下半身专属护具，使用通用护具补位。

#### 拳击（Brute）装备

| FAB ID | FAB 名称 | 原槽位 | → 本作槽位 |
|--------|---------|--------|-----------|
| eq_skullhorn | Skullhorn | head | 上半身 |
| eq_barkbone_strapping | Barkbone Strapping | chest | 上半身 |
| eq_scabskin_leathers | Scabskin Leathers | legs | 下半身 |

#### 通用装备

| FAB ID | FAB 名称 | 原槽位 | → 本作槽位 |
|--------|---------|--------|-----------|
| eq_fyendals_spring_tunic | Fyendal's Spring Tunic | chest | 上半身 |
| eq_hope_merchants_hood | Hope Merchant's Hood | head | 上半身 |
| eq_heartened_cross_strap | Heartened Cross Strap | chest | 上半身 |
| eq_goliath_gauntlet | Goliath Gauntlet | arms | 上半身 |
| eq_ironrot_helm | Ironrot Helm | head | 上半身 |
| eq_ironrot_plate | Ironrot Plate | chest | 上半身 |
| eq_ironrot_gauntlet | Ironrot Gauntlet | arms | 上半身 |
| eq_snapdragon_scalers | Snapdragon Scalers | legs | 下半身 |
| eq_ironrot_legs | Ironrot Legs | legs | 下半身 |

### 槽位分布统计

| 本作槽位 | 数量 | 来源 |
|---------|------|------|
| 上半身 | 15 张 | head×4 + chest×5 + arms×4 + 2通用 |
| 下半身 | 6 张 | legs×6 |

> 上半身装备严重过剩（15 选 1），下半身偏少（6 选 1）。
> 这是位置直接合并的自然结果，后续平衡调整时可考虑把部分 arms 装备重新分配到下半身。

---

## 二、卡名换皮对照表

### 命名原则

1. **格斗化**：暗黑奇幻名 → 格斗运动/武术招式名
2. **流派贴合**：剑道用剑道术语、跆拳道用腿法术语、太极用太极术语、拳击用拳击术语
3. **保留辨识度**：换皮名仍需反映原牌的机制特征（连招牌就要听起来像连续技）
4. **不改 ID**：ID 保持不变，仅换显示名

---

### 2.1 英雄卡

| FAB ID | FAB 名称 | → 本作名称 | 流派 |
|--------|---------|-----------|------|
| hero_dorinthea_young | Dorinthea | 一之濑枫 | 剑道 |
| hero_katsu_young | Katsu, the Wanderer | 夏琳 | 跆拳道 |
| hero_bravo_young | Bravo | 云柔 | 太极 |
| hero_rhinar_young | Rhinar | 铁拳小桃 | 拳击 |

---

### 2.2 武器 → 架势

| FAB ID | FAB 名称 | → 本作名称 | 说明 |
|--------|---------|-----------|------|
| weapon_dawnblade | Dawnblade（破晓之刃） | 正眼之构 | 剑道基本架势，双手持竹刀中段 |
| weapon_harmonized_kodachi | Harmonized Kodachi（调和小太刀） | 战斗站架 | 跆拳道格斗姿态，双手起手式 |
| weapon_anothos | Anothos（安诺索斯） | 太极起势 | 太极拳起始动作，气沉丹田 |
| weapon_romping_club | Romping Club（狂暴棍棒） | 拳击架势 | 标准拳击 peek-a-boo 站姿 |

---

### 2.3 装备 → 护具（时装路线）

#### 品牌体系

每个角色对应一个时装品牌，反映其性格与流派美学：

| 品牌 | 风格 | 对应角色 | 设计语言 |
|------|------|---------|---------|
| **桜風 (ŌKAZE)** | 和风学院 | 一之濑枫·剑道 | 水手服改良、和服元素、樱花刺绣、深蓝白配色 |
| **DASH** | 韩系运动潮牌 | 夏琳·跆拳道 | 露脐短款、撞色拼接、机能面料、荧光色系 |
| **云裳** | 新中式国风 | 云柔·太极 | 盘扣对襟、水墨印花、飘逸丝绸、素雅配色 |
| **K.O.** | 美式街头朋克 | 铁拳小桃·拳击 | 铆钉皮革、涂鸦印花、破洞做旧、黑红配色 |
| *(无品牌)* | 校服 / 基础运动装 | 通用 | 普通校服、基础运动款 |

#### 剑道·桜風 (ŌKAZE)

| FAB ID | FAB 名称 | 槽位 | → 本作名称 | 描述 |
|--------|---------|------|-----------|------|
| eq_braveforge_bracers | Braveforge Bracers | 上半身 | 桜風·改良水手服 | 深蓝色水手领上衣，袖口樱花刺绣，胸前蝴蝶结 |
| eq_courage_of_bladehold | Courage of Bladehold | 上半身 | 桜風·剑道羽织 | 白底靛蓝纹样的短羽织外套，背后印有道场家纹 |
| eq_refraction_bolters | Refraction Bolters | 下半身 | 桜風·百褶短裙 | 深蓝百褶裙配白色运动内衬，裙摆有樱花暗纹 |

#### 跆拳道·DASH

| FAB ID | FAB 名称 | 槽位 | → 本作名称 | 描述 |
|--------|---------|------|-----------|------|
| eq_mask_of_momentum | Mask of Momentum | 上半身 | DASH·露脐运动衫 | 荧光绿撞色露脐速干衫，背后大 logo |
| eq_breaking_scales | Breaking Scales | 上半身 | DASH·机能拉链外套 | 白色短款机能夹克，拉链可调节通风 |

> DASH 缺下半身专属，使用通用护具补位。

#### 太极·云裳

| FAB ID | FAB 名称 | 槽位 | → 本作名称 | 描述 |
|--------|---------|------|-----------|------|
| eq_tectonic_plating | Tectonic Plating | 上半身 | 云裳·盘扣对襟衫 | 真丝对襟上衣，云纹盘扣，袖口渐变水墨 |
| eq_helm_of_isens_peak | Helm of Isen's Peak | 上半身 | 云裳·绣花抹额 | 白色丝绸抹额，额心绣青莲花纹 |
| eq_crater_fist | Crater Fist | 上半身 | 云裳·水袖罩衫 | 轻薄水袖外罩，随动作飘逸如行云 |

> 云裳缺下半身专属，使用通用护具补位。

#### 拳击·K.O.

| FAB ID | FAB 名称 | 槽位 | → 本作名称 | 描述 |
|--------|---------|------|-----------|------|
| eq_skullhorn | Skullhorn | 上半身 | K.O.·铆钉皮背心 | 黑色短款皮背心，肩部铆钉装饰，背后涂鸦骷髅 |
| eq_barkbone_strapping | Barkbone Strapping | 上半身 | K.O.·绑带运动内衣 | 红黑撞色运动束胸，交叉绑带设计 |
| eq_scabskin_leathers | Scabskin Leathers | 下半身 | K.O.·破洞牛仔热裤 | 做旧水洗热裤，膝盖铆钉护膝，链条腰饰 |

#### 通用装备

| FAB ID | FAB 名称 | 槽位 | → 本作名称 | 描述 |
|--------|---------|------|-----------|------|
| eq_fyendals_spring_tunic | Fyendal's Spring Tunic | 上半身 | 春日碎花衬衫 | 清新碎花短袖衬衫，休闲日常款 |
| eq_hope_merchants_hood | Hope Merchant's Hood | 上半身 | 幸运兔耳帽衫 | 带兔耳帽兜的宽松卫衣 |
| eq_heartened_cross_strap | Heartened Cross Strap | 上半身 | 交叉绑带背心 | 运动风交叉带背心 |
| eq_goliath_gauntlet | Goliath Gauntlet | 上半身 | 加厚护腕手套 | 半指格斗手套，腕部加厚 |
| eq_snapdragon_scalers | Snapdragon Scalers | 下半身 | 高帮帆布鞋 | 涂鸦风格高帮鞋，鞋带荧光色 |
| eq_ironrot_helm | Ironrot Helm | 上半身 | 校服上衣（旧） | 有点起球的学校指定运动T恤 |
| eq_ironrot_plate | Ironrot Plate | 上半身 | 校服外套（旧） | 洗得发白的标准校服拉链外套 |
| eq_ironrot_gauntlet | Ironrot Gauntlet | 上半身 | 棉质护腕 | 最便宜的药店款棉护腕 |
| eq_ironrot_legs | Ironrot Legs | 下半身 | 校服运动裤（旧） | 膝盖磨亮了的校服运动长裤 |

---

### 2.4 剑道（Warrior）卡牌

#### 专属卡

| FAB ID | FAB 名称 | → 本作名称 | 取名理由 |
|--------|---------|-----------|---------|
| spec_steelblade_supremacy | Steelblade Supremacy（钢刃至上） | 一刀入魂 | 剑道极意：一击倾注全部精神 |
| spec_singing_steelblade | Singing Steelblade（歌唱钢刃） | 残心追击 | 剑道术语「残心」：斩击后保持警觉追击 |
| spec_ironsong_determination | Ironsong Determination（铁歌决意） | 不动心 | 剑道精神：心如止水不受动摇 |

#### 攻击牌

| FAB ID 前缀 | FAB 名称 | → 本作名称 | 取名理由 |
|-------------|---------|-----------|---------|
| war_wounding_blow | Wounding Blow（致伤打击） | 面打 | 剑道基本技：正面击打 |

#### 辅助牌

| FAB ID 前缀 | FAB 名称 | → 本作名称 | 取名理由 |
|-------------|---------|-----------|---------|
| war_sharpen_steel | Sharpen Steel（磨砺钢刃） | 素振蓄力 | 素振=空挥练习，蓄力调整 |
| war_driving_blade | Driving Blade（驱动之刃） | 踏込突刺 | 剑道术语：踏步前冲攻击 |
| war_warriors_valor | Warrior's Valor（战士之勇） | 气合 | 剑道喊声集中精神 |

#### 追击牌（攻击反应）

| FAB ID 前缀 | FAB 名称 | → 本作名称 | 取名理由 |
|-------------|---------|-----------|---------|
| war_overpower | Overpower（压倒） | 切落 | 剑道技法：压制对方竹刀后击打 |
| war_ironsong_response | Ironsong Response（铁歌回应） | 返刀 | 挡住后顺势回击 |
| war_biting_blade | Biting Blade（噬咬之刃） | 连续打 | 连续追击 |

#### 闪避牌（防御反应）

| FAB ID 前缀 | FAB 名称 | → 本作名称 | 取名理由 |
|-------------|---------|-----------|---------|
| war_steelblade_shunt | Steelblade Shunt（钢刃挡击） | 受流返打 | 剑道：接住攻击顺势反击 |

---

### 2.5 跆拳道（Ninja）卡牌

#### 专属卡

| FAB ID | FAB 名称 | → 本作名称 | 取名理由 |
|--------|---------|-----------|---------|
| spec_mugenshi_release | Mugenshi: RELEASE（无限·解放） | 无影·解放 | 速度快到看不见残影 |
| spec_lord_of_wind | Lord of Wind（风之主） | 疾风连环 | 连续腿法的终结技 |

#### 攻击牌（非 Combo 起手）

| FAB ID 前缀 | FAB 名称 | → 本作名称 | 取名理由 |
|-------------|---------|-----------|---------|
| nin_surging_strike | Surging Strike（奔涌突击） | 前踢 | 跆拳道基本正面踢击 |
| nin_head_jab | Head Jab（头击） | 刺拳 | 快速试探性攻击 |
| nin_leg_tap | Leg Tap（扫腿） | 下段踢 | 低位腿法 |

#### Combo 链卡

| FAB ID 前缀 | FAB 名称 | → 本作名称 | Combo 前置 | 取名理由 |
|-------------|---------|-----------|----------|---------|
| nin_whelming_gustwave | Whelming Gustwave（涌风浪） | 旋风踢 | 前踢 | 前踢接旋转踢击 |
| nin_rising_knee_thrust | Rising Knee Thrust（飞膝击） | 下段踢 | 飞膝 | 低踢变高膝撞 |
| nin_open_the_center | Open the Center（攻破中路） | 中段突破 | 刺拳 | 突破防御中线 |
| nin_blackout_kick | Blackout Kick（断电飞踢） | 后旋踢 | 飞膝 | 转身踢击重创 |
| nin_hurricane_technique | Hurricane Technique（飓风技） | 三连踢 | 飞膝 | 连续三次踢击 |
| nin_pounding_gale | Pounding Gale（猛击飓风） | 必杀·暴风 | 中段突破 | 终结爆发技 |

#### Combo 链路速查（换皮后）

```
链 A（夏琳核心链）：
  前踢 → 旋风踢 → [专属] 无影·解放 → [专属] 疾风连环

链 B（踢击链）：
  下段踢 → 飞膝 → 后旋踢 / 三连踢

链 C（拳击链）：
  刺拳 → 中段突破 → 必杀·暴风
```

#### 反应牌

| FAB ID 前缀 | FAB 名称 | → 本作名称 | 类型 | 取名理由 |
|-------------|---------|-----------|------|---------|
| nin_ancestral_empowerment | Ancestral Empowerment（祖传赋能） | 气势追加 | 追击 | 气势上涨追加伤害 |
| nin_flic_flak | Flic Flak（闪避反击） | 侧闪 | 闪避 | 侧身躲避 |

---

### 2.6 太极（Guardian）卡牌

#### 专属卡

| FAB ID | FAB 名称 | → 本作名称 | 取名理由 |
|--------|---------|-----------|---------|
| spec_crippling_crush | Crippling Crush（残废粉碎） | 泰山压顶 | 太极大招，不可阻挡的重击 |
| spec_show_time | Show Time!（表演时间!） | 四两拨千斤 | 太极核心理念：蓄势后以柔克刚 |

#### 攻击牌

| FAB ID 前缀 | FAB 名称 | → 本作名称 | 取名理由 |
|-------------|---------|-----------|---------|
| gua_spinal_crush | Spinal Crush（脊椎粉碎） | 推山掌 | 太极实战重掌 |
| gua_cranial_crush | Cranial Crush（颅骨粉碎） | 封脉掌 | 封住气脉的致命一掌 |
| gua_disable | Disable（瘫痪） | 缠丝劲 | 太极核心劲法 |
| gua_buckling_blow | Buckling Blow（扣压之击） | 按劲 | 太极八法之一 |
| gua_cartilage_crush | Cartilage Crush（软骨粉碎） | 採劲 | 太极八法之一 |
| gua_crush_confidence | Crush Confidence（碎裂信心） | 挒劲 | 太极八法之一 |
| gua_debilitate | Debilitate（衰弱） | 肘靠 | 太极近身重击 |

#### 辅助牌（状态/光环）

| FAB ID 前缀 | FAB 名称 | → 本作名称 | 取名理由 |
|-------------|---------|-----------|---------|
| gua_forged_for_war | Forged for War（战争锻造） | 站桩 | 太极基础功法，强化防御 |
| gua_blessing_of_deliverance | Blessing of Deliverance（解救祝福） | 吐纳调息 | 太极呼吸法，回复状态 |
| gua_emerging_power | Emerging Power（涌现之力） | 运气蓄力 | 凝聚内劲准备重击 |
| gua_stonewall_confidence | Stonewall Confidence（石墙信心） | 铁布衫 | 硬功抗击打 |

#### 闪避牌（防御反应）

| FAB ID 前缀 | FAB 名称 | → 本作名称 | 取名理由 |
|-------------|---------|-----------|---------|
| gua_staunch_response | Staunch Response（坚定回应） | 化劲 | 太极核心防御：化解来力 |

---

### 2.7 拳击（Brute）卡牌

#### 专属卡

| FAB ID 前缀 | FAB 名称 | → 本作名称 | 取名理由 |
|-------------|---------|-----------|---------|
| spec_alpha_rampage | Alpha Rampage（首领狂暴） | 暴风连拳 | 不顾一切的密集连拳 |
| spec_sand_sketched_plan | Sand Sketched Plan（沙绘计划） | 拳感直觉 | 拳击手的本能直觉选牌 |

#### 攻击牌

| FAB ID 前缀 | FAB 名称 | → 本作名称 | 取名理由 |
|-------------|---------|-----------|---------|
| bru_pack_hunt | Pack Hunt（群猎） | 组合拳 | 拳击基础组合 |
| bru_smash_instinct | Smash Instinct（粉碎本能） | 重拳出击 | 全力挥出直拳 |
| bru_wrecker_romp | Wrecker Romp（破坏狂暴） | 乱拳 | 不计后果的狂暴出拳 |
| bru_savage_swing | Savage Swing（蛮荒挥击） | 摆拳 | 拳击弧线攻击 |
| bru_savage_feast | Savage Feast（蛮荒盛宴） | 猛虎出笼 | 饥饿感驱动的爆发 |
| bru_breakneck_battery | Breakneck Battery（破颈电池） | 连环重拳 | 连续重击 |

#### 辅助牌

| FAB ID 前缀 | FAB 名称 | → 本作名称 | 取名理由 |
|-------------|---------|-----------|---------|
| bru_awakening_bellow | Awakening Bellow（觉醒怒吼） | 战吼 | 上场前的气势呐喊 |
| bru_barraging_beatdown | Barraging Beatdown（弹幕暴打） | 压制拳 | 密集拳攻让对手没法反击 |
| bru_bloodrush_bellow | Bloodrush Bellow（血涌怒吼） | 怒火中烧 | 愤怒驱动的全回合增益 |
| bru_primeval_bellow | Primeval Bellow（原始怒吼） | 气势爆发 | 凝聚全力的一声吼 |

#### 闪避牌（防御反应）

| FAB ID 前缀 | FAB 名称 | → 本作名称 | 取名理由 |
|-------------|---------|-----------|---------|
| bru_reckless_swing | Reckless Swing（鲁莽挥砍） | 以牙还牙 | 挨打了就要打回去 |

#### 本能牌

| FAB ID | FAB 名称 | → 本作名称 | 取名理由 |
|--------|---------|-----------|---------|
| bru_bone_head_barrier | Bone Head Barrier（骨头壁障） | 硬扛 | 拳击手靠身体硬吃一击 |

---

### 2.8 通用卡牌

#### 攻击牌

| FAB ID 前缀 | FAB 名称 | → 本作名称 | 取名理由 |
|-------------|---------|-----------|---------|
| gen_wounding_blow | Wounding Blow（致伤打击） | 直拳 | 最基础的通用攻击 |
| gen_enlightened_strike | Enlightened Strike（启迪一击） | 灵光一闪 | 灵感爆发的一击（弃牌换效果） |
| gen_snatch | Snatch（抢夺） | 抢攻 | 抢先出手打中后抽牌 |
| gen_nimble_strike | Nimble Strike（灵巧突袭） | 快拳 | 灵活快速的打击 |
| gen_raging_onslaught | Raging Onslaught（怒火猛攻） | 全力猛攻 | 高费白板重击 |
| gen_scar_for_a_scar | Scar for a Scar（以伤报伤） | 以伤换伤 | 落后时获得连招 |
| gen_wounded_bull | Wounded Bull（受伤公牛） | 绝地反击 | 被压血时攻击力提升 |
| gen_scour_the_battlescape | Scour the Battlescape（扫视战场） | 观察试探 | 换牌+预备区连招 |
| gen_regurgitating_slog | Regurgitating Slog（回流之击） | 蓄力重击 | 放逐弃牌堆资源获得必杀 |
| gen_barraging_brawnhide | Barraging Brawnhide（弹幕厚皮） | 铁拳连击 | 防御不足时追加伤害 |
| gen_drone_of_brutality | Drone of Brutality（残暴无人机） | 不屈斗志 | 进弃牌堆时回到牌库底（打不死） |

#### 追击牌（攻击反应）

| FAB ID 前缀 | FAB 名称 | → 本作名称 | 取名理由 |
|-------------|---------|-----------|---------|
| gen_pummel | Pummel（猛击） | 追拳 | 重武器/高费攻击的追加打击 |
| gen_razor_reflex | Razor Reflex（剃刀反射） | 本能追击 | 轻武器/低费攻击的追加打击 |

#### 闪避牌（防御反应）

| FAB ID 前缀 | FAB 名称 | → 本作名称 | 取名理由 |
|-------------|---------|-----------|---------|
| gen_unmovable | Unmovable（不动如山） | 铁壁 | 高防御，预备区加成 |
| gen_sink_below | Sink Below（下沉闪避） | 下潜闪避 | 下蹲躲过攻击+换牌 |

#### 辅助牌（状态/道具）

| FAB ID 前缀 | FAB 名称 | → 本作名称 | 类型 | 取名理由 |
|-------------|---------|-----------|------|---------|
| gen_nimblism | Nimblism（轻捷之态） | 轻步状态 | 状态 | 轻盈步伐强化低费攻击 |
| gen_sloggism | Sloggism（重击之态） | 重拳状态 | 状态 | 沉稳架势强化高费攻击 |
| gen_energy_potion | Energy Potion（能量药水） | 能量饮料 | 道具 | 场边补给 |
| gen_potion_of_strength | Potion of Strength（力量药水） | 力量补剂 | 道具 | 临时增强攻击力 |
| gen_tome_of_fyendal | Tome of Fyendal（费恩达尔之书） | 教练笔记 | 道具 | 教练的战术指导，抽牌+回体力 |

#### 本能牌

| FAB ID 前缀 | FAB 名称 | → 本作名称 | 取名理由 |
|-------------|---------|-----------|---------|
| gen_sigil_of_solace | Sigil of Solace（慰藉徽记） | 深呼吸 | 紧急恢复体力 |

---

### 2.9 Token

| FAB 名称 | → 本作名称 | 取名理由 |
|---------|-----------|---------|
| Seismic Surge | 震波 | 太极蓄力释放的冲击波 |
| Might | 力量 | 临时攻击力增益 |
| Quicken | 加速 | 额外行动点 |

---

## 三、Combo 链路总览（换皮后）

### 跆拳道·夏琳

```
链 A（核心链）：前踢 → 旋风踢 → [专属]无影·解放 → [专属]疾风连环
链 B（踢击链）：下段踢 → 飞膝 → 后旋踢 / 三连踢
链 C（拳击链）：刺拳 → 中段突破 → 必杀·暴风
```

### 其他流派

剑道/太极/拳击不使用 Combo 关键词，通过架势连击（剑道）、重击 Crush（太极）、震慑 Intimidate（拳击）作为核心循环。

---

*文档版本：v1.0*
*最后更新：2026-05-18*

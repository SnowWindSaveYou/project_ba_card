-- ============================================================================
-- Card/HeroData.lua - 英雄 / 武器 / 装备 数据定义
-- 数据来源: fab-cardpool-v1.md + skinning-map.md
-- ============================================================================

local CardData = require("Card.CardData")
local KW = CardData.KEYWORD
local SLOT = CardData.SLOT

local HeroData = {}

-- ============================================================================
-- 英雄定义 (4 位, Blitz 年轻版, 20 生命 / 4 专注力)
-- ============================================================================

HeroData.heroes = {
    -- 剑道
    kaede = {
        id   = "hero_dorinthea_young",
        name = "一之濑枫",
        class = "warrior",
        life = 20,
        intellect = 4,
        customHandler = "hero_dorinthea",
        -- 能力: 每回合一次，架势命中后可额外再攻击一次
    },
    -- 跆拳道
    xia_lin = {
        id   = "hero_katsu_young",
        name = "夏琳",
        class = "ninja",
        life = 20,
        intellect = 4,
        customHandler = "hero_katsu",
        -- 能力: 攻击牌命中后弃 0 费牌搜索 combo 牌打出
    },
    -- 太极
    yun_rou = {
        id   = "hero_bravo_young",
        name = "云柔",
        class = "guardian",
        life = 20,
        intellect = 4,
        customHandler = "hero_bravo",
        -- 能力: 支付 {2} 让费用 ≥ 3 攻击牌获得必杀 + 连招
    },
    -- 拳击
    xiao_tao = {
        id   = "hero_rhinar_young",
        name = "铁拳小桃",
        class = "brute",
        life = 20,
        intellect = 4,
        customHandler = "hero_rhinar",
        -- 能力: 行动阶段弃掉攻击力 ≥ 6 的牌时触发震慑
    },
}

-- ============================================================================
-- 武器（架势）定义
-- ============================================================================

HeroData.weapons = {
    -- 剑道: 正眼之构 (Dawnblade)
    {
        id    = "weapon_dawnblade",
        name  = "正眼之构",
        class = "warrior",
        cardType = "weapon",
        hands = 2,
        power = 3,
        cost  = 1,
        text  = "第 2 次命中后，放置 +1 计数器。\n若本回合结束时未命中，移除全部计数器。",
        customHandler = "weapon_dawnblade",
    },
    -- 跆拳道: 战斗站架 (Harmonized Kodachi) x2
    {
        id    = "weapon_harmonized_kodachi",
        name  = "战斗站架",
        class = "ninja",
        cardType = "weapon",
        hands = 1,
        power = 1,
        cost  = 1,
        count = 2,
        text  = "双持。\n若本回合充能区有至少 1 张费用为 0 的牌，此次架势攻击获得【连招】。",
        customHandler = "weapon_kodachi",
    },
    -- 太极: 太极起势 (Anothos)
    {
        id    = "weapon_anothos",
        name  = "太极起势",
        class = "guardian",
        cardType = "weapon",
        hands = 2,
        power = 4,
        cost  = 3,
        text  = "若充能区有 ≥ 2 张费用 ≥ 3 的牌，此次架势攻击 +2 攻击力。",
        customHandler = "weapon_anothos",
    },
    -- 拳击: 拳击架势 (Romping Club)
    {
        id    = "weapon_romping_club",
        name  = "拳击架势",
        class = "brute",
        cardType = "weapon",
        hands = 2,
        power = 4,
        cost  = 2,
        text  = "每当你在攻击结算时弃掉攻击力 ≥ 6 的牌，此次架势攻击 +1 攻击力。",
        customHandler = "weapon_romping_club",
    },
}

-- ============================================================================
-- 装备（护具）定义
-- 槽位已从 FAB 4 槽合并为 2 槽 (upper/lower)
-- ============================================================================

HeroData.equipment = {
    -- ==================== 剑道·桜風 ====================
    {
        id       = "eq_braveforge_bracers",
        name     = "桜風·改良水手服",
        class    = "warrior",
        cardType = "equipment",
        slot     = SLOT.UPPER,
        defense  = 2,
        keywords = { KW.BATTLEWORN },
        rarity   = "legendary",
        text     = "【磨损】\n每回合一次 [行动] {1}：若架势本回合已命中，下次架势攻击 +1 攻击力，获得【连招】。",
        customHandler = "eq_braveforge_bracers",
    },
    {
        id       = "eq_courage_of_bladehold",
        name     = "桜風·剑道羽织",
        class    = "warrior",
        cardType = "equipment",
        slot     = SLOT.UPPER,
        defense  = 2,
        keywords = { KW.TEMPER },
        rarity   = "majestic",
        text     = "【韧性】\n[瞬发]：销毁本件护具，本回合所有剑术攻击牌费用 -1。",
        effects  = {
            { id = "destroy_self" },
            { id = "reduce_cost", params = { target = "sword_attacks_this_turn", amount = 1 } },
            { id = "grant_go_again", params = { target = "self_ability" } },
        },
    },
    {
        id       = "eq_refraction_bolters",
        name     = "桜風·百褶短裙",
        class    = "warrior",
        cardType = "equipment",
        slot     = SLOT.LOWER,
        defense  = 2,
        keywords = { KW.BATTLEWORN },
        rarity   = "common",
        text     = "【磨损】\n[瞬发]：销毁本件护具，赋予下次架势攻击【连招】。",
        effects  = {
            { id = "destroy_self" },
            { id = "grant_go_again", params = { target = "weapon_attack" } },
        },
    },

    -- ==================== 跆拳道·DASH ====================
    {
        id       = "eq_mask_of_momentum",
        name     = "DASH·露脐运动衫",
        class    = "ninja",
        cardType = "equipment",
        slot     = SLOT.UPPER,
        defense  = 2,
        keywords = { KW.BLADE_BREAK },
        rarity   = "legendary",
        text     = "【脆弱】\n连招链第 3 环节及以上命中时，抽 1 张牌。",
        customHandler = "eq_mask_of_momentum",
    },
    {
        id       = "eq_breaking_scales",
        name     = "DASH·机能拉链外套",
        class    = "ninja",
        cardType = "equipment",
        slot     = SLOT.UPPER,
        defense  = 1,
        keywords = { KW.BATTLEWORN },
        rarity   = "common",
        text     = "【磨损】\n[瞬发]：销毁本件护具，本回合下一张连招攻击 +1 攻击力。",
        effects  = {
            { id = "destroy_self" },
            { id = "buff_power", params = { target = "combo_attack", amount = 1 } },
        },
    },

    -- ==================== 太极·云裳 ====================
    {
        id       = "eq_tectonic_plating",
        name     = "云裳·盘扣对襟衫",
        class    = "guardian",
        cardType = "equipment",
        slot     = SLOT.UPPER,
        defense  = 2,
        keywords = { KW.BATTLEWORN },
        rarity   = "legendary",
        text     = "【磨损】\n每回合一次 [行动] {1}：创建「震波 (4)」令牌，获得【连招】。",
        customHandler = "eq_tectonic_plating",
    },
    {
        id       = "eq_helm_of_isens_peak",
        name     = "云裳·绣花抹额",
        class    = "guardian",
        cardType = "equipment",
        slot     = SLOT.UPPER,
        defense  = 1,
        keywords = { KW.BATTLEWORN },
        rarity   = "common",
        text     = "【磨损】\n[瞬发]：销毁本件护具，获得 1 专注力（本回合多抽 1 张牌）。",
        effects  = {
            { id = "destroy_self" },
            { id = "gain_intellect", params = { amount = 1 } },
        },
    },
    {
        id       = "eq_crater_fist",
        name     = "云裳·水袖罩衫",
        class    = "guardian",
        cardType = "equipment",
        slot     = SLOT.UPPER,
        defense  = 2,
        keywords = { KW.TEMPER },
        rarity   = "common",
        text     = "【韧性】\n[行动] {1}：销毁本件护具，本回合带【碎击】的攻击 +2 攻击力，获得【连招】。",
        effects  = {
            { id = "destroy_self" },
            { id = "buff_power_until_eot", params = { target = "attacks_with_crush", amount = 2 } },
            { id = "grant_go_again", params = { target = "self_ability" } },
        },
    },

    -- ==================== 拳击·K.O. ====================
    {
        id       = "eq_skullhorn",
        name     = "K.O.·铆钉皮背心",
        class    = "brute",
        cardType = "equipment",
        slot     = SLOT.UPPER,
        defense  = 0,
        keywords = {},
        rarity   = "majestic",
        text     = "[瞬发]：销毁本件护具，抽 1 张牌，然后随机弃 1 张牌。\n奥术屏障 2。",
        effects  = {
            { id = "destroy_self" },
            { id = "draw", params = { amount = 1 } },
            { id = "discard_random", params = { amount = 1 } },
            { id = "grant_go_again", params = { target = "self_ability" } },
        },
    },
    {
        id       = "eq_barkbone_strapping",
        name     = "K.O.·绑带运动内衣",
        class    = "brute",
        cardType = "equipment",
        slot     = SLOT.UPPER,
        defense  = 1,
        keywords = { KW.BATTLEWORN },
        rarity   = "common",
        text     = "【磨损】\n[瞬发]：销毁本件护具，掷一个六面骰，获得 ⌊结果÷2⌋ 点体能资源。",
        customHandler = "roll_gain_resource",
    },
    {
        id       = "eq_scabskin_leathers",
        name     = "K.O.·破洞牛仔热裤",
        class    = "brute",
        cardType = "equipment",
        slot     = SLOT.LOWER,
        defense  = 2,
        keywords = { KW.BATTLEWORN },
        rarity   = "legendary",
        text     = "【磨损】\n每回合一次 [行动] {0}：掷一个六面骰，获得 ⌊结果÷2⌋ 个行动点。",
        customHandler = "roll_gain_action",
    },

    -- ==================== 通用装备 ====================
    {
        id       = "eq_fyendals_spring_tunic",
        name     = "春日碎花衬衫",
        class    = "generic",
        cardType = "equipment",
        slot     = SLOT.UPPER,
        defense  = 1,
        keywords = { KW.BLADE_BREAK },
        rarity   = "legendary",
        text     = "【脆弱】\n回合开始：放置 1 个能量计数器（最多 3 个）。\n[瞬发]：移除 3 个能量计数器，获得 {1} 体能资源。",
        customHandler = "eq_fyendals_spring_tunic",
    },
    {
        id       = "eq_hope_merchants_hood",
        name     = "幸运兔耳帽衫",
        class    = "generic",
        cardType = "equipment",
        slot     = SLOT.UPPER,
        defense  = 0,
        keywords = {},
        rarity   = "common",
        text     = "[瞬发]：销毁本件护具，将任意张手牌洗回牌库，再抽等量手牌。",
        effects  = {
            { id = "destroy_self" },
            { id = "shuffle_from_hand_draw", params = {} },
        },
        customHandler = "eq_hope_merchants_hood",
    },
    {
        id       = "eq_heartened_cross_strap",
        name     = "交叉绑带背心",
        class    = "generic",
        cardType = "equipment",
        slot     = SLOT.UPPER,
        defense  = 0,
        keywords = {},
        rarity   = "common",
        text     = "[瞬发]：销毁本件护具，下一张攻击动作牌费用 -2，获得【连招】。",
        effects  = {
            { id = "destroy_self" },
            { id = "reduce_cost", params = { target = "next_attack_action", amount = 2 } },
            { id = "grant_go_again", params = { target = "self_ability" } },
        },
    },
    {
        id       = "eq_goliath_gauntlet",
        name     = "加厚护腕手套",
        class    = "generic",
        cardType = "equipment",
        slot     = SLOT.UPPER,
        defense  = 0,
        keywords = {},
        rarity   = "common",
        text     = "[瞬发]：销毁本件护具，下一张费用 ≥ 2 的攻击牌 +2 攻击力，获得【连招】。",
        effects  = {
            { id = "destroy_self" },
            { id = "buff_power", params = { target = "next_attack_cost_2_plus", amount = 2 } },
            { id = "grant_go_again", params = { target = "self_ability" } },
        },
    },
    {
        id       = "eq_snapdragon_scalers",
        name     = "高帮帆布鞋",
        class    = "generic",
        cardType = "equipment",
        slot     = SLOT.LOWER,
        defense  = 0,
        keywords = {},
        rarity   = "common",
        text     = "[瞬发]：销毁本件护具，赋予费用 ≤ 1 的攻击动作牌【连招】。",
        effects  = {
            { id = "destroy_self" },
            { id = "grant_go_again", params = { target = "attack_cost_1_or_less" } },
        },
    },
    -- Ironrot 系列（校服旧装，纯防御）
    {
        id = "eq_ironrot_helm", name = "校服上衣（旧）",
        class = "generic", cardType = "equipment", slot = SLOT.UPPER, defense = 1,
        keywords = { KW.BLADE_BREAK }, rarity = "common",
        text = "【脆弱】",
    },
    {
        id = "eq_ironrot_plate", name = "校服外套（旧）",
        class = "generic", cardType = "equipment", slot = SLOT.UPPER, defense = 1,
        keywords = { KW.BLADE_BREAK }, rarity = "common",
        text = "【脆弱】",
    },
    {
        id = "eq_ironrot_gauntlet", name = "棉质护腕",
        class = "generic", cardType = "equipment", slot = SLOT.UPPER, defense = 1,
        keywords = { KW.BLADE_BREAK }, rarity = "common",
        text = "【脆弱】",
    },
    {
        id = "eq_ironrot_legs", name = "校服运动裤（旧）",
        class = "generic", cardType = "equipment", slot = SLOT.LOWER, defense = 1,
        keywords = { KW.BLADE_BREAK }, rarity = "common",
        text = "【脆弱】",
    },
}

-- ============================================================================
-- 查询接口
-- ============================================================================

--- 按 key 获取英雄数据
---@param key string 如 "kaede"
---@return table|nil
function HeroData.getHero(key)
    return HeroData.heroes[key]
end

--- 获取某职业的武器列表
---@param class string
---@return table[]
function HeroData.getWeaponsForClass(class)
    local result = {}
    for _, w in ipairs(HeroData.weapons) do
        if w.class == class then
            result[#result + 1] = w
        end
    end
    return result
end

--- 获取某职业可用的装备列表（本职 + 通用）
---@param class string
---@return table[]
function HeroData.getEquipmentForClass(class)
    local result = {}
    for _, eq in ipairs(HeroData.equipment) do
        if eq.class == class or eq.class == "generic" then
            result[#result + 1] = eq
        end
    end
    return result
end

--- 按 id 查找装备
---@param id string
---@return table|nil
function HeroData.getEquipmentById(id)
    for _, eq in ipairs(HeroData.equipment) do
        if eq.id == id then return eq end
    end
    return nil
end

return HeroData

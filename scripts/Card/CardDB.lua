-- ============================================================================
-- Card/CardDB.lua - 完整卡牌数据库
-- 数据来源: fab-cardpool-v1.md + skinning-map.md + effect-system.md
-- ============================================================================

local CardData = require("Card.CardData")
local T   = CardData.TYPE
local P   = CardData.PITCH
local C   = CardData.CLASS
local KW  = CardData.KEYWORD
local R   = CardData.RARITY

local CardDB = {}

-- ============================================================================
-- 辅助: 批量生成红/黄/蓝三色变体
-- ============================================================================

--- 创建三色变体 (Red/Yellow/Blue)
---@param base table 基础属性（不含 pitch / id 后缀 / power 差异）
---@param powers table {red, yellow, blue} 三色攻击力
---@param opts? table 可选 per-color 差异:
---   defenses = {r, y, b}       -- 三色防御值
---   rarities = {r, y, b}       -- 三色稀有度
---   amounts  = {r, y, b}       -- 三色 effects amount (替换 effects 中所有 .params.amount)
---@return table, table, table
local function tri(base, powers, opts)
    opts = opts or {}
    local cards = {}
    local suffixes = { "r", "y", "b" }
    local pitches  = { P.RED, P.YELLOW, P.BLUE }
    for i = 1, 3 do
        local def = {}
        for k, v in pairs(base) do def[k] = v end
        def.id    = base.id .. "_" .. suffixes[i]
        def.pitch = pitches[i]
        def.power = powers[i]
        -- per-color defense
        if opts.defenses then
            def.defense = opts.defenses[i]
        end
        -- per-color rarity
        if opts.rarities then
            def.rarity = opts.rarities[i]
        end
        -- per-color effects amount: deep-copy effects and replace .params.amount
        if opts.amounts and def.effects then
            local newEffects = {}
            for ei, eff in ipairs(def.effects) do
                local newEff = {}
                for ek, ev in pairs(eff) do
                    if ek == "params" then
                        local newParams = {}
                        for pk, pv in pairs(ev) do newParams[pk] = pv end
                        if newParams.amount then
                            newParams.amount = opts.amounts[i]
                        end
                        newEff.params = newParams
                    elseif ek == "then_" then
                        -- deep-copy then_ effects and replace amount
                        local newThen = {}
                        for ti, teff in ipairs(ev) do
                            local nt = {}
                            for tk, tv in pairs(teff) do
                                if tk == "params" then
                                    local np = {}
                                    for pk, pv in pairs(tv) do np[pk] = pv end
                                    if np.amount then
                                        np.amount = opts.amounts[i]
                                    end
                                    nt.params = np
                                else
                                    nt[tk] = tv
                                end
                            end
                            newThen[ti] = nt
                        end
                        newEff.then_ = newThen
                    elseif ek == "options" then
                        -- deep-copy choose_one options and replace amount in nested effects
                        local newOptions = {}
                        for oi, opt in ipairs(ev) do
                            local newOpt = { label = opt.label }
                            if opt.effects then
                                local newOptEffects = {}
                                for oei, oeff in ipairs(opt.effects) do
                                    local noe = {}
                                    for ok, ov in pairs(oeff) do
                                        if ok == "params" then
                                            local np = {}
                                            for pk, pv in pairs(ov) do np[pk] = pv end
                                            if np.amount then
                                                np.amount = opts.amounts[i]
                                            end
                                            noe.params = np
                                        else
                                            noe[ok] = ov
                                        end
                                    end
                                    newOptEffects[oei] = noe
                                end
                                newOpt.effects = newOptEffects
                            end
                            newOptions[oi] = newOpt
                        end
                        newEff.options = newOptions
                    else
                        newEff[ek] = ev
                    end
                end
                newEffects[ei] = newEff
            end
            def.effects = newEffects
        end
        cards[i] = CardData.new(def)
    end
    return cards[1], cards[2], cards[3]
end

-- ============================================================================
-- 全部卡牌存储
-- ============================================================================

---@type table<string, table>
CardDB.cards = {}

--- 注册单张卡牌
local function reg(card)
    CardDB.cards[card.id] = card
end

--- 注册三色变体
local function reg3(r, y, b)
    reg(r); reg(y); reg(b)
end

-- ============================================================================
-- 一、剑道 (Warrior) 卡池
-- ============================================================================

-- === 专属卡 ===

reg(CardData.new({
    id = "spec_steelblade_supremacy",
    name = "一刀入魂",
    type = T.SUPPORT,
    class = C.WARRIOR,
    specialization = "kaede",
    pitch = P.RED, cost = 1, power = 0, defense = 3,
    keywords = { KW.GO_AGAIN },
    goAgain = true,
    rarity = R.MAJESTIC,
    effects = {
        { id = "buff_power", params = { target = "next_weapon", amount = 2 } },
        { id = "on_hit", then_ = {
            { id = "draw", params = { amount = 1 } },
        }},
    },
    text = "本回合目标架势攻击+2{p}，且\"命中时抽1牌\"。连招。",
}))

reg(CardData.new({
    id = "spec_singing_steelblade",
    name = "残心追击",
    type = T.CHASE,
    class = C.WARRIOR,
    specialization = "kaede",
    pitch = P.YELLOW, cost = 1, power = 1, defense = 3,
    keywords = { KW.REPRISE },
    rarity = R.MAJESTIC,
    customHandler = "spec_singing_steelblade",
    text = "目标架势攻击+1{p}。反击: 搜索牌库找1张追击牌，打出。",
}))

reg(CardData.new({
    id = "spec_ironsong_determination",
    name = "不动心",
    type = T.SUPPORT,
    class = C.WARRIOR,
    pitch = P.YELLOW, cost = 0, power = 0, defense = 3,
    keywords = { KW.GO_AGAIN, KW.DOMINATE },
    goAgain = true,
    rarity = R.SUPER_RARE,
    effects = {
        { id = "buff_power", params = { target = "next_weapon", amount = 1 } },
        { id = "grant_dominate", params = { target = "next_weapon" } },
    },
    text = "目标架势+1{p}，获得必杀。连招。",
}))

-- === 攻击牌 ===

reg3(tri({
    id = "war_wounding_blow", name = "面打",
    type = T.ATTACK, class = C.WARRIOR,
    cost = 0, defense = 3, rarity = R.COMMON,
}, { 4, 3, 2 }))

-- === 辅助牌 ===

reg3(tri({
    id = "war_sharpen_steel", name = "素振蓄力",
    type = T.SUPPORT, class = C.WARRIOR,
    cost = 0, defense = 3, rarity = R.COMMON,
    keywords = { KW.GO_AGAIN }, goAgain = true,
    effects = {
        { id = "buff_power", params = { target = "next_weapon", amount = 3 } },
    },
    text = "下次架势攻击+N{p}。连招。",
}, { 0, 0, 0 }, { amounts = { 3, 2, 1 } }))

reg3(tri({
    id = "war_driving_blade", name = "踏込突刺",
    type = T.SUPPORT, class = C.WARRIOR,
    cost = 2, defense = 3, rarity = R.COMMON,
    keywords = { KW.GO_AGAIN }, goAgain = true,
    effects = {
        { id = "buff_power", params = { target = "next_weapon", amount = 3 } },
        { id = "grant_go_again", params = { target = "next_weapon" } },
    },
    text = "下次架势攻击+N{p}，获得连招。连招。",
}, { 0, 0, 0 }, { amounts = { 3, 2, 1 } }))

reg3(tri({
    id = "war_warriors_valor", name = "气合",
    type = T.SUPPORT, class = C.WARRIOR,
    cost = 0, defense = 3, rarity = R.COMMON,
    keywords = { KW.GO_AGAIN }, goAgain = true,
    effects = {
        { id = "buff_power", params = { target = "next_weapon", amount = 3 } },
        { id = "on_hit", then_ = {
            { id = "grant_go_again", params = { target = "weapon_attack" } },
        }},
    },
    text = "下次架势攻击+N{p}，\"命中时获得连招\"。连招。",
}, { 0, 0, 0 }, { amounts = { 3, 2, 1 } }))

-- === 追击牌 (Attack Reaction) ===

do
    local suffixes = { "r", "y", "b" }
    local pitches  = { P.RED, P.YELLOW, P.BLUE }
    local buffs    = { 4, 3, 2 }  -- 红+4, 黄+3, 蓝+2 (Reprise +2 三色相同)
    for i = 1, 3 do
        reg(CardData.new({
            id = "war_overpower_" .. suffixes[i],
            name = "切落",
            type = T.CHASE, class = C.WARRIOR,
            pitch = pitches[i], cost = 3, power = 0, defense = 3,
            rarity = R.RARE,
            keywords = { KW.REPRISE },
            effects = {
                { id = "buff_power", params = { target = "weapon_attack", amount = buffs[i] } },
                { id = "on_defend_with_hand", then_ = {
                    { id = "buff_power", params = { target = "weapon_attack", amount = 2 } },
                }},
            },
            text = "目标架势攻击+N{p}。反击: 额外+2{p}。",
        }))
    end
end

reg3(tri({
    id = "war_ironsong_response", name = "返刀",
    type = T.CHASE, class = C.WARRIOR,
    cost = 0, defense = 3, rarity = R.COMMON,
    keywords = { KW.REPRISE },
    effects = {
        { id = "on_defend_with_hand", then_ = {
            { id = "buff_power", params = { target = "weapon_attack", amount = 3 } },
        }},
    },
    text = "反击: 目标架势攻击+N{p}。(无反击时无效果)",
}, { 0, 0, 0 }, { amounts = { 3, 2, 1 } }))

do
    local suffixes = { "r", "y", "b" }
    local pitches  = { P.RED, P.YELLOW, P.BLUE }
    local buffs    = { 3, 2, 1 }  -- 红+3, 黄+2, 蓝+1 (Reprise +1 三色相同)
    for i = 1, 3 do
        reg(CardData.new({
            id = "war_biting_blade_" .. suffixes[i],
            name = "连续打",
            type = T.CHASE, class = C.WARRIOR,
            pitch = pitches[i], cost = 2, power = 0, defense = 3,
            rarity = R.COMMON,
            keywords = { KW.REPRISE },
            effects = {
                { id = "buff_power", params = { target = "weapon_attack", amount = buffs[i] } },
                { id = "on_defend_with_hand", then_ = {
                    { id = "buff_power_until_eot", params = { target = "weapons_this_turn", amount = 1 } },
                }},
            },
            text = "目标架势攻击+N{p}。反击: 本回合架势+1{p}。",
        }))
    end
end

-- === 闪避牌 (Defense Reaction) ===

reg3(tri({
    id = "war_steelblade_shunt", name = "受流返打",
    type = T.DODGE, class = C.WARRIOR,
    cost = 1, power = 0, defense = 6, rarity = R.RARE,
    effects = {
        { id = "deal_damage", params = { amount = 1, target = "attacking_hero" } },
    },
    text = "防御架势攻击时，对攻击方角色造成1点伤害。",
}, { 0, 0, 0 }, { defenses = { 6, 5, 4 } }))

-- ============================================================================
-- 二、跆拳道 (Ninja) 卡池
-- ============================================================================

-- === 专属卡 ===

reg(CardData.new({
    id = "spec_mugenshi_release",
    name = "无影·解放",
    type = T.ATTACK, class = C.NINJA,
    specialization = "xia_lin",
    pitch = P.YELLOW, cost = 1, power = 4, defense = 3,
    keywords = { KW.COMBO },
    comboFrom = "旋风踢",
    rarity = R.SUPER_RARE,
    customHandler = "spec_mugenshi_release",
    text = "连击(旋风踢): +1{p}，连招，命中时搜索所有疾风连环到手牌。",
}))

reg(CardData.new({
    id = "spec_lord_of_wind",
    name = "疾风连环",
    type = T.ATTACK, class = C.NINJA,
    specialization = "xia_lin",
    pitch = P.BLUE, cost = 0, power = 2, defense = 3,
    keywords = { KW.COMBO },
    comboFrom = "无影·解放",
    rarity = R.MAJESTIC,
    customHandler = "spec_lord_of_wind",
    text = "连击(无影·解放): 额外支付{X}，从弃牌堆洗回X张指定牌，+X{p}。",
}))

-- === 攻击牌 (非 Combo 起手) ===

reg3(tri({
    id = "nin_surging_strike", name = "前踢",
    type = T.ATTACK, class = C.NINJA,
    cost = 2, defense = 2, rarity = R.COMMON,
    keywords = { KW.GO_AGAIN }, goAgain = true,
}, { 5, 4, 3 }))

reg3(tri({
    id = "nin_head_jab", name = "刺拳",
    type = T.ATTACK, class = C.NINJA,
    cost = 0, defense = 2, rarity = R.COMMON,
    keywords = { KW.GO_AGAIN }, goAgain = true,
}, { 3, 2, 1 }))

reg3(tri({
    id = "nin_leg_tap", name = "下段踢",
    type = T.ATTACK, class = C.NINJA,
    cost = 1, defense = 2, rarity = R.COMMON,
    keywords = { KW.GO_AGAIN }, goAgain = true,
}, { 4, 3, 2 }))

-- === Combo 链卡 ===

reg3(tri({
    id = "nin_whelming_gustwave", name = "旋风踢",
    type = T.ATTACK, class = C.NINJA,
    cost = 0, defense = 3, rarity = R.COMMON,
    keywords = { KW.COMBO },
    comboFrom = "前踢",
    effects = {
        { id = "combo_check", params = { card_name = "前踢" }, then_ = {
            { id = "buff_power", params = { target = "this", amount = 1 } },
            { id = "grant_go_again", params = { target = "this" } },
            { id = "on_hit", then_ = {
                { id = "draw", params = { amount = 1 } },
            }},
        }},
    },
    text = "连击(前踢): +1{p}，连招，命中时抽1牌。",
}, { 3, 2, 1 }))

reg3(tri({
    id = "nin_rising_knee_thrust", name = "飞膝",
    type = T.ATTACK, class = C.NINJA,
    cost = 0, defense = 3, rarity = R.COMMON,
    keywords = { KW.COMBO },
    comboFrom = "下段踢",
    effects = {
        { id = "combo_check", params = { card_name = "下段踢" }, then_ = {
            { id = "buff_power", params = { target = "this", amount = 2 } },
            { id = "grant_go_again", params = { target = "this" } },
        }},
    },
    text = "连击(下段踢): +2{p}，连招。",
}, { 3, 2, 1 }))

reg3(tri({
    id = "nin_open_the_center", name = "中段突破",
    type = T.ATTACK, class = C.NINJA,
    cost = 2, defense = 3,
    keywords = { KW.COMBO },
    comboFrom = "刺拳",
    effects = {
        { id = "combo_check", params = { card_name = "刺拳" }, then_ = {
            { id = "buff_power", params = { target = "this", amount = 1 } },
            { id = "grant_go_again", params = { target = "this" } },
            { id = "grant_dominate", params = { target = "this" } },
        }},
    },
    text = "连击(刺拳): +1{p}，连招，必杀。",
}, { 5, 4, 3 }, { rarities = { R.COMMON, R.RARE, R.RARE } }))

reg3(tri({
    id = "nin_blackout_kick", name = "后旋踢",
    type = T.ATTACK, class = C.NINJA,
    cost = 1, defense = 3, rarity = R.RARE,
    keywords = { KW.COMBO },
    comboFrom = "飞膝",
    effects = {
        { id = "combo_check", params = { card_name = "飞膝" }, then_ = {
            { id = "buff_power", params = { target = "this", amount = 3 } },
        }},
    },
    text = "连击(飞膝): +3{p}。",
}, { 4, 3, 2 }))

reg(CardData.new({
    id = "nin_hurricane_technique",
    name = "三连踢",
    type = T.ATTACK, class = C.NINJA,
    pitch = P.YELLOW, cost = 1, power = 4, defense = 3,
    keywords = { KW.COMBO },
    comboFrom = "飞膝",
    rarity = R.SUPER_RARE,
    effects = {
        { id = "combo_check", params = { card_name = "飞膝" }, then_ = {
            { id = "buff_power", params = { target = "this", amount = 1 } },
            { id = "grant_go_again", params = { target = "this" } },
            { id = "return_to_hand_on_hit" },
        }},
    },
    text = "连击(飞膝): +1{p}，连招，命中后回到手牌。",
}))

reg(CardData.new({
    id = "nin_pounding_gale",
    name = "必杀·暴风",
    type = T.ATTACK, class = C.NINJA,
    pitch = P.RED, cost = 1, power = 5, defense = 3,
    keywords = { KW.COMBO },
    comboFrom = "中段突破",
    rarity = R.SUPER_RARE,
    customHandler = "nin_pounding_gale",
    text = "连击(中段突破): 伤害翻倍。",
}))

-- === 追击牌 ===

reg3(tri({
    id = "nin_ancestral_empowerment", name = "气势追加",
    type = T.CHASE, class = C.NINJA,
    cost = 0, defense = 3, rarity = R.COMMON,
    effects = {
        { id = "buff_power", params = { target = "ninja_attack", amount = 1 } },
        { id = "draw", params = { amount = 1 } },
    },
    text = "目标跆拳道攻击牌+1{p}。抽1牌。",
}, { 0, 0, 0 }))
-- 三色 bonus 均为 +1, 仅 pitch 不同

-- === 闪避牌 ===

reg3(tri({
    id = "nin_flic_flak", name = "侧闪",
    type = T.DODGE, class = C.NINJA,
    cost = 0, power = 0, defense = 4, rarity = R.RARE,
    effects = {
        { id = "buff_defense", params = { target = "next_combo_defense", amount = 2 } },
    },
    text = "防御4。下一张用于防御的连击牌+2防御。",
}, { 0, 0, 0 }))

-- ============================================================================
-- 三、太极 (Guardian) 卡池
-- ============================================================================

-- === 专属卡 ===

reg(CardData.new({
    id = "spec_crippling_crush",
    name = "泰山压顶",
    type = T.ATTACK, class = C.GUARDIAN,
    specialization = "yun_rou",
    pitch = P.RED, cost = 7, power = 11, defense = 3,
    keywords = { KW.CRUSH },
    rarity = R.MAJESTIC,
    effects = {
        { id = "crush_check", params = { min_damage = 4 }, then_ = {
            { id = "discard_random", params = { amount = 2, target = "opponent" } },
        }},
    },
    text = "重击: 造成≥4伤害时，对手随机弃2张手牌。",
}))

reg(CardData.new({
    id = "spec_show_time",
    name = "四两拨千斤",
    type = T.AURA, class = C.GUARDIAN,
    specialization = "yun_rou",
    pitch = P.BLUE, cost = 3, power = 0, defense = 3,
    rarity = R.SUPER_RARE,
    customHandler = "spec_show_time",
    text = "进场时搜索1张太极攻击牌到手牌。下个行动阶段销毁，抽1牌。",
}))

-- === 攻击牌 ===

reg(CardData.new({
    id = "gua_spinal_crush",
    name = "推山掌",
    type = T.ATTACK, class = C.GUARDIAN,
    pitch = P.RED, cost = 5, power = 9, defense = 3,
    keywords = { KW.CRUSH },
    rarity = R.MAJESTIC,
    customHandler = "crush_spinal",
    text = "重击: 造成≥4伤害时，对手下回合所有行动/攻击失去且不能获得连招。",
}))

reg(CardData.new({
    id = "gua_cranial_crush",
    name = "封脉掌",
    type = T.ATTACK, class = C.GUARDIAN,
    pitch = P.BLUE, cost = 6, power = 8, defense = 3,
    keywords = { KW.CRUSH },
    rarity = R.SUPER_RARE,
    customHandler = "crush_cranial",
    text = "重击: 造成≥4伤害时，对手下回合不能抽牌。",
}))

reg3(tri({
    id = "gua_disable", name = "缠丝劲",
    type = T.ATTACK, class = C.GUARDIAN,
    cost = 5, defense = 3, rarity = R.RARE,
    keywords = { KW.CRUSH },
    effects = {
        { id = "crush_check", params = { min_damage = 4 }, then_ = {
            { id = "put_arsenal_to_deck_bottom", params = { amount = 1 } },
        }},
    },
    text = "重击: 造成≥4伤害时，对手预备区1张牌放到牌库底。",
}, { 9, 8, 7 }))

reg3(tri({
    id = "gua_buckling_blow", name = "按劲",
    type = T.ATTACK, class = C.GUARDIAN,
    cost = 4, defense = 3, rarity = R.COMMON,
    keywords = { KW.CRUSH },
    effects = {
        { id = "crush_check", params = { min_damage = 4 }, then_ = {
            { id = "add_defense_counter", params = { target = "opponent_equipment", amount = -1 } },
        }},
    },
    text = "重击: 造成≥4伤害时，对手1件护具-1防御。",
}, { 8, 7, 6 }))

reg3(tri({
    id = "gua_cartilage_crush", name = "採劲",
    type = T.ATTACK, class = C.GUARDIAN,
    cost = 3, defense = 3, rarity = R.COMMON,
    keywords = { KW.CRUSH },
    customHandler = "crush_cartilage",
    text = "重击: 造成≥4伤害时，对手下回合第一个行动额外支付{1}。",
}, { 7, 6, 5 }))

reg3(tri({
    id = "gua_crush_confidence", name = "挒劲",
    type = T.ATTACK, class = C.GUARDIAN,
    cost = 3, defense = 3, rarity = R.COMMON,
    keywords = { KW.CRUSH },
    customHandler = "crush_confidence",
    text = "重击: 造成≥4伤害时，对手失去角色能力到下回合结束。",
}, { 7, 6, 5 }))

reg3(tri({
    id = "gua_debilitate", name = "肘靠",
    type = T.ATTACK, class = C.GUARDIAN,
    cost = 4, defense = 3, rarity = R.COMMON,
    keywords = { KW.CRUSH },
    customHandler = "crush_debilitate",
    text = "重击: 造成≥4伤害时，对手下回合首次攻击-2{p}。",
}, { 8, 7, 6 }))

-- === 辅助牌 (Aura) ===

reg(CardData.new({
    id = "gua_forged_for_war",
    name = "站桩",
    type = T.AURA, class = C.GUARDIAN,
    pitch = P.YELLOW, cost = 2, power = 0, defense = 3,
    keywords = { KW.GO_AGAIN }, goAgain = true,
    rarity = R.SUPER_RARE,
    effects = {
        { id = "while_in_arena", then_ = {
            { id = "equipment_defense_buff", params = { amount = 1 } },
        }},
        { id = "next_action_phase_destroy" },
    },
    text = "在场时护具+1防御。下个行动阶段销毁。连招。",
}))

reg3(tri({
    id = "gua_blessing_of_deliverance", name = "吐纳调息",
    type = T.AURA, class = C.GUARDIAN,
    cost = 2, defense = 3, rarity = R.RARE,
    keywords = { KW.GO_AGAIN }, goAgain = true,
    customHandler = "gua_blessing_of_deliverance",
    text = "进场: 充能区有费用≥3的牌时抽1牌。销毁时翻牌库顶N张，每有费用≥3的牌回复1体力。",
}, { 0, 0, 0 }))

reg3(tri({
    id = "gua_emerging_power", name = "运气蓄力",
    type = T.AURA, class = C.GUARDIAN,
    cost = 0, defense = 3, rarity = R.COMMON,
    keywords = { KW.GO_AGAIN }, goAgain = true,
    effects = {
        { id = "next_action_phase_destroy" },
        { id = "on_destroy", then_ = {
            { id = "buff_power", params = { target = "next_class_attack", amount = 3 } },
        }},
    },
    text = "连招。销毁时下次太极攻击+N{p}。",
}, { 0, 0, 0 }, { amounts = { 3, 2, 1 } }))

reg3(tri({
    id = "gua_stonewall_confidence", name = "铁布衫",
    type = T.AURA, class = C.GUARDIAN,
    cost = 2, defense = 3, rarity = R.COMMON,
    effects = {
        { id = "while_in_arena", then_ = {
            { id = "buff_defense", params = { target = "your_cards_cost_gte_3_defending", amount = 4 } },
        }},
        { id = "next_action_phase_destroy" },
    },
    text = "在场时费用≥3的牌防御+N。下个行动阶段销毁。",
}, { 0, 0, 0 }, { amounts = { 4, 3, 2 } }))

-- === 闪避牌 ===

reg3(tri({
    id = "gua_staunch_response", name = "化劲",
    type = T.DODGE, class = C.GUARDIAN,
    cost = 2, power = 0, defense = 7, rarity = R.RARE,
    effects = {
        { id = "additional_cost_pay_resource", params = { amount = 4, optional = true } },
        { id = "buff_defense", params = { target = "this", amount = 3 } },
    },
    text = "防御N。可额外支付{4}: 额外+3防御。",
}, { 0, 0, 0 }, { defenses = { 7, 6, 5 } }))

-- ============================================================================
-- 四、拳击 (Brute) 卡池
-- ============================================================================

-- === 专属卡 ===

reg(CardData.new({
    id = "spec_alpha_rampage_r",
    name = "暴风连拳",
    type = T.ATTACK, class = C.BRUTE,
    specialization = "xiao_tao",
    pitch = P.RED, cost = 3, power = 9, defense = 3,
    rarity = R.MAJESTIC,
    keywords = { KW.INTIMIDATE },
    effects = {
        { id = "additional_cost_discard_random", params = { amount = 1 } },
    },
    text = "附加费用: 随机弃1张牌。震慑。",
}))

reg(CardData.new({
    id = "spec_sand_sketched_plan",
    name = "拳感直觉",
    type = T.SUPPORT, class = C.BRUTE,
    specialization = "xiao_tao",
    pitch = P.BLUE, cost = 0, power = 0, defense = 3,
    rarity = R.SUPER_RARE,
    customHandler = "spec_sand_sketched_plan",
    text = "搜索牌库找1张牌到手牌，随机弃1张。弃牌攻击力≥6时获得2行动点。",
}))

-- === 攻击牌 ===

reg3(tri({
    id = "bru_pack_hunt", name = "组合拳",
    type = T.ATTACK, class = C.BRUTE,
    cost = 2, defense = 3, rarity = R.COMMON,
    keywords = { KW.INTIMIDATE },
    text = "震慑。",
}, { 6, 5, 4 }))

reg3(tri({
    id = "bru_smash_instinct", name = "重拳出击",
    type = T.ATTACK, class = C.BRUTE,
    cost = 3, defense = 3, rarity = R.COMMON,
    keywords = { KW.INTIMIDATE },
    text = "震慑。",
}, { 7, 6, 5 }))

reg3(tri({
    id = "bru_wrecker_romp", name = "乱拳",
    type = T.ATTACK, class = C.BRUTE,
    cost = 2, defense = 3, rarity = R.COMMON,
    effects = {
        { id = "additional_cost_discard_random", params = { amount = 1 } },
    },
    text = "附加费用: 随机弃1张牌。",
}, { 8, 7, 6 }))

reg3(tri({
    id = "bru_savage_swing", name = "摆拳",
    type = T.ATTACK, class = C.BRUTE,
    cost = 1, defense = 3, rarity = R.COMMON,
    effects = {
        { id = "additional_cost_discard_random", params = { amount = 1 } },
    },
    text = "附加费用: 随机弃1张牌。",
}, { 7, 6, 5 }))

reg3(tri({
    id = "bru_savage_feast", name = "猛虎出笼",
    type = T.ATTACK, class = C.BRUTE,
    cost = 1, defense = 3, rarity = R.COMMON,
    effects = {
        { id = "additional_cost_discard_random", params = { amount = 1 } },
        { id = "if_discarded_power_gte", params = { threshold = 6 }, then_ = {
            { id = "draw", params = { amount = 1 } },
        }},
    },
    text = "附加费用: 随机弃1张牌。弃牌攻击力≥6时抽1牌。",
}, { 6, 5, 4 }))

reg3(tri({
    id = "bru_breakneck_battery", name = "连环重拳",
    type = T.ATTACK, class = C.BRUTE,
    cost = 2, defense = 3, rarity = R.COMMON,
    effects = {
        { id = "additional_cost_discard_random", params = { amount = 1 } },
        { id = "if_discarded_power_gte", params = { threshold = 6 }, then_ = {
            { id = "grant_go_again", params = { target = "this" } },
        }},
    },
    text = "附加费用: 随机弃1张牌。弃牌攻击力≥6时获得连招。",
}, { 6, 5, 4 }))

-- === 辅助牌 ===

reg3(tri({
    id = "bru_awakening_bellow", name = "战吼",
    type = T.SUPPORT, class = C.BRUTE,
    cost = 1, defense = 3, rarity = R.COMMON,
    keywords = { KW.GO_AGAIN, KW.INTIMIDATE },
    goAgain = true,
    effects = {
        { id = "buff_power", params = { target = "next_class_attack", amount = 3 } },
    },
    text = "下次拳击攻击+N{p}。震慑。连招。",
}, { 0, 0, 0 }, { amounts = { 3, 2, 1 } }))

reg3(tri({
    id = "bru_barraging_beatdown", name = "压制拳",
    type = T.SUPPORT, class = C.BRUTE,
    cost = 0, defense = 3, rarity = R.RARE,
    keywords = { KW.GO_AGAIN, KW.INTIMIDATE },
    goAgain = true,
    effects = {
        { id = "if_defended_by_fewer_than", params = { count = 2 }, then_ = {
            { id = "buff_power", params = { target = "next_class_attack", amount = 4 } },
        }},
    },
    text = "下次拳击攻击: 对手用少于2张非护具牌防御时+N{p}。震慑。连招。",
}, { 0, 0, 0 }, { amounts = { 4, 3, 2 } }))

reg(CardData.new({
    id = "bru_bloodrush_bellow",
    name = "怒火中烧",
    type = T.SUPPORT, class = C.BRUTE,
    pitch = P.YELLOW, cost = 1, power = 0, defense = 3,
    rarity = R.COMMON,
    effects = {
        { id = "additional_cost_discard_random", params = { amount = 1 } },
        { id = "buff_power_until_eot", params = { target = "all_class_attacks", amount = 2 } },
        { id = "if_discarded_power_gte", params = { threshold = 6 }, then_ = {
            { id = "draw", params = { amount = 2 } },
            { id = "grant_go_again", params = { target = "self" } },
        }},
    },
    text = "附加费用: 随机弃1张。本回合拳击攻击+2{p}。弃牌攻击力≥6时抽2牌，获得连招。",
}))

do
    local suffixes = { "r", "y", "b" }
    local pitches  = { P.RED, P.YELLOW, P.BLUE }
    local buffs    = { 5, 4, 3 }
    for i = 1, 3 do
        reg(CardData.new({
            id = "bru_primeval_bellow_" .. suffixes[i],
            name = "气势爆发",
            type = T.SUPPORT, class = C.BRUTE,
            pitch = pitches[i], cost = 0, power = 0, defense = 3,
            rarity = R.COMMON,
            keywords = { KW.GO_AGAIN }, goAgain = true,
            effects = {
                { id = "additional_cost_discard_random", params = { amount = 1 } },
                { id = "buff_power", params = { target = "next_class_attack", amount = buffs[i] } },
            },
            text = "附加费用: 随机弃1张牌。下次拳击攻击+N{p}。连招。",
        }))
    end
end

-- === 闪避牌 ===

reg(CardData.new({
    id = "bru_reckless_swing",
    name = "以牙还牙",
    type = T.DODGE, class = C.BRUTE,
    pitch = P.BLUE, cost = 0, power = 0, defense = 4,
    rarity = R.COMMON,
    effects = {
        { id = "additional_cost_discard_random", params = { amount = 1 } },
        { id = "if_discarded_power_gte", params = { threshold = 6 }, then_ = {
            { id = "deal_damage", params = { amount = 2, target = "attacking_hero" } },
        }},
    },
    text = "附加费用: 随机弃1张牌。弃牌攻击力≥6时对攻击方造成2点伤害。",
}))

-- === 本能牌 ===

reg(CardData.new({
    id = "bru_bone_head_barrier",
    name = "硬扛",
    type = T.INSTINCT, class = C.BRUTE,
    pitch = P.YELLOW, cost = 1, power = 0, defense = 0,
    rarity = R.COMMON,
    customHandler = "roll_prevent_damage",
    text = "掷6面骰。阻止等于结果点数的伤害。",
}))

-- ============================================================================
-- 五、通用 (Generic) 卡池
-- ============================================================================

-- === 攻击牌 ===

reg3(tri({
    id = "gen_wounding_blow", name = "直拳",
    type = T.ATTACK, class = C.GENERIC,
    cost = 0, defense = 3, rarity = R.COMMON,
}, { 4, 3, 2 }))

reg(CardData.new({
    id = "gen_enlightened_strike",
    name = "灵光一闪",
    type = T.ATTACK, class = C.GENERIC,
    pitch = P.RED, cost = 0, power = 5, defense = 3,
    rarity = R.MAJESTIC,
    effects = {
        { id = "additional_cost_put_hand_to_bottom", params = { amount = 1 } },
        { id = "choose_one", options = {
            { label = "抽1牌", effects = { { id = "draw", params = { amount = 1 } } } },
            { label = "+2攻击力", effects = { { id = "buff_power", params = { target = "this", amount = 2 } } } },
            { label = "获得连招", effects = { { id = "grant_go_again", params = { target = "this" } } } },
        }},
    },
    text = "附加费用: 将1张手牌放到牌库底。三选一: 抽1牌/+2{p}/连招。",
}))

reg3(tri({
    id = "gen_snatch", name = "抢攻",
    type = T.ATTACK, class = C.GENERIC,
    cost = 1, defense = 2, rarity = R.RARE,
    effects = {
        { id = "on_hit", then_ = {
            { id = "draw", params = { amount = 1 } },
        }},
    },
    text = "命中时抽1牌。",
}, { 4, 3, 2 }))

reg3(tri({
    id = "gen_nimble_strike", name = "快拳",
    type = T.ATTACK, class = C.GENERIC,
    cost = 1, defense = 2, rarity = R.COMMON,
    effects = {
        { id = "banish_from_graveyard", params = { card_name = "轻步状态" }, then_ = {
            { id = "buff_power", params = { target = "this", amount = 1 } },
            { id = "grant_go_again", params = { target = "this" } },
        }},
    },
    text = "可从弃牌堆放逐轻步状态: +1{p}，连招。",
}, { 4, 3, 3 }))
-- 蓝色 power = 3 (与黄色相同，非标准)

reg3(tri({
    id = "gen_raging_onslaught", name = "全力猛攻",
    type = T.ATTACK, class = C.GENERIC,
    cost = 3, defense = 3, rarity = R.COMMON,
}, { 7, 6, 5 }))

reg3(tri({
    id = "gen_scar_for_a_scar", name = "以伤换伤",
    type = T.ATTACK, class = C.GENERIC,
    cost = 0, defense = 2, rarity = R.COMMON,
    effects = {
        { id = "if_less_life", then_ = {
            { id = "grant_go_again", params = { target = "this" } },
        }},
    },
    text = "你体力少于对手时获得连招。",
}, { 4, 3, 2 }))

reg3(tri({
    id = "gen_wounded_bull", name = "绝地反击",
    type = T.ATTACK, class = C.GENERIC,
    cost = 3, defense = 2, rarity = R.COMMON,
    effects = {
        { id = "if_less_life", then_ = {
            { id = "buff_power", params = { target = "this", amount = 1 } },
        }},
    },
    text = "你体力少于对手时+1{p}。",
}, { 7, 6, 5 }))

reg3(tri({
    id = "gen_scour_the_battlescape", name = "观察试探",
    type = T.ATTACK, class = C.GENERIC,
    cost = 0, defense = 2, rarity = R.COMMON,
    effects = {
        { id = "put_hand_to_deck_bottom", params = { amount = 1, optional = true } },
        { id = "draw", params = { amount = 1 } },
        { id = "if_from_arsenal", then_ = {
            { id = "grant_go_again", params = { target = "this" } },
        }},
    },
    text = "可将1张手牌放到牌库底，抽1牌。从预备区打出时获得连招。",
}, { 3, 2, 1 }))

reg3(tri({
    id = "gen_regurgitating_slog", name = "蓄力重击",
    type = T.ATTACK, class = C.GENERIC,
    cost = 2, defense = 2, rarity = R.COMMON,
    effects = {
        { id = "banish_from_graveyard", params = { card_name = "重拳状态" }, then_ = {
            { id = "grant_dominate", params = { target = "this" } },
        }},
    },
    text = "可从弃牌堆放逐重拳状态: 获得必杀。",
}, { 6, 5, 4 }))

reg3(tri({
    id = "gen_barraging_brawnhide", name = "铁拳连击",
    type = T.ATTACK, class = C.GENERIC,
    cost = 3, defense = 2, rarity = R.COMMON,
    effects = {
        { id = "if_defended_by_fewer_than", params = { count = 2 }, then_ = {
            { id = "buff_power", params = { target = "this", amount = 1 } },
        }},
    },
    text = "对手用少于2张非护具牌防御时+1{p}。",
}, { 7, 6, 5 }))

-- Drone of Brutality: 三色 cost 不同 (红0/黄1/蓝2)，defense=2，手动注册
do
    local base = {
        name = "不屈斗志",
        type = T.ATTACK, class = C.GENERIC,
        defense = 2, rarity = R.RARE,
        effects = {
            { id = "to_deck_bottom_instead_of_graveyard" },
        },
        text = "进弃牌堆时改为放到牌库底。",
    }
    local variants = {
        { suffix = "r", pitch = P.RED,    cost = 0, power = 6 },
        { suffix = "y", pitch = P.YELLOW, cost = 1, power = 5 },
        { suffix = "b", pitch = P.BLUE,   cost = 2, power = 4 },
    }
    for _, v in ipairs(variants) do
        local def = {}
        for k, val in pairs(base) do def[k] = val end
        def.id    = "gen_drone_of_brutality_" .. v.suffix
        def.pitch = v.pitch
        def.cost  = v.cost
        def.power = v.power
        reg(CardData.new(def))
    end
end

-- === 追击牌 ===

reg3(tri({
    id = "gen_pummel", name = "追拳",
    type = T.CHASE, class = C.GENERIC,
    cost = 0, defense = 2, rarity = R.COMMON,
    effects = {
        { id = "choose_one", options = {
            { label = "力量型架势攻击+N{p}",
              effects = { { id = "buff_power", params = { target = "hammer_club_weapon", amount = 4 } } } },
            { label = "费用≥2攻击牌+N{p}，命中弃牌",
              effects = {
                { id = "buff_power", params = { target = "attack_cost_2_plus", amount = 4 } },
                { id = "on_hit", then_ = {
                    { id = "discard_chosen", params = { amount = 1, target = "opponent" } },
                }},
              } },
        }},
    },
    text = "选一: 力量型架势+N{p}; 或费用≥2攻击牌+N{p}，命中时对手弃1牌。",
}, { 0, 0, 0 }, { amounts = { 4, 3, 2 } }))

reg3(tri({
    id = "gen_razor_reflex", name = "本能追击",
    type = T.CHASE, class = C.GENERIC,
    cost = 0, defense = 2, rarity = R.COMMON,
    effects = {
        { id = "choose_one", options = {
            { label = "灵巧型架势攻击+N{p}",
              effects = { { id = "buff_power", params = { target = "sword_dagger_weapon", amount = 3 } } } },
            { label = "费用≤1攻击牌+N{p}，命中连招",
              effects = {
                { id = "buff_power", params = { target = "attack_cost_1_or_less", amount = 3 } },
                { id = "on_hit", then_ = {
                    { id = "grant_go_again", params = { target = "attack" } },
                }},
              } },
        }},
    },
    text = "选一: 灵巧型架势+N{p}; 或费用≤1攻击牌+N{p}，命中时获得连招。",
}, { 0, 0, 0 }, { amounts = { 3, 2, 1 } }))

-- === 闪避牌 ===

reg3(tri({
    id = "gen_unmovable", name = "铁壁",
    type = T.DODGE, class = C.GENERIC,
    cost = 0, power = 0, defense = 7, rarity = R.COMMON,
    effects = {
        { id = "if_from_arsenal", then_ = {
            { id = "buff_defense", params = { target = "this", amount = 1 } },
        }},
    },
    text = "从预备区打出时+1防御。",
}, { 0, 0, 0 }, { defenses = { 7, 6, 5 } }))

reg3(tri({
    id = "gen_sink_below", name = "下潜闪避",
    type = T.DODGE, class = C.GENERIC,
    cost = 0, power = 0, defense = 4, rarity = R.COMMON,
    effects = {
        { id = "put_hand_to_deck_bottom", params = { amount = 1, optional = true } },
        { id = "draw", params = { amount = 1 } },
    },
    text = "可将1张手牌放到牌库底，抽1牌。",
}, { 0, 0, 0 }, { defenses = { 4, 3, 2 } }))

-- === 辅助牌 (Aura) ===

reg3(tri({
    id = "gen_nimblism", name = "轻步状态",
    type = T.AURA, class = C.GENERIC,
    cost = 0, defense = 2, rarity = R.COMMON,
    keywords = { KW.GO_AGAIN }, goAgain = true,
    effects = {
        { id = "buff_power", params = { target = "next_attack_cost_1_or_less", amount = 3 } },
    },
    text = "下次费用≤1攻击牌+N{p}。连招。",
}, { 0, 0, 0 }, { amounts = { 3, 2, 1 } }))

reg3(tri({
    id = "gen_sloggism", name = "重拳状态",
    type = T.AURA, class = C.GENERIC,
    cost = 0, defense = 2, rarity = R.COMMON,
    keywords = { KW.GO_AGAIN }, goAgain = true,
    effects = {
        { id = "buff_power", params = { target = "next_attack_cost_2_plus", amount = 6 } },
    },
    text = "下次费用≥2攻击牌+N{p}。连招。",
}, { 0, 0, 0 }, { amounts = { 6, 5, 4 } }))

-- === 道具牌 (Item) ===

reg(CardData.new({
    id = "gen_energy_potion",
    name = "能量饮料",
    type = T.ITEM, class = C.GENERIC,
    pitch = P.BLUE, cost = 0, power = 0, defense = 0,
    rarity = R.RARE,
    effects = {
        { id = "destroy_self" },
        { id = "gain_resource", params = { amount = 2 } },
    },
    text = "即时 — 销毁: 获得{2}体能。",
}))

reg(CardData.new({
    id = "gen_potion_of_strength",
    name = "力量补剂",
    type = T.ITEM, class = C.GENERIC,
    pitch = P.BLUE, cost = 0, power = 0, defense = 0,
    rarity = R.RARE,
    keywords = { KW.GO_AGAIN }, goAgain = true,
    effects = {
        { id = "destroy_self" },
        { id = "buff_power", params = { target = "next_attack", amount = 2 } },
    },
    text = "行动 — 销毁: 下次攻击+2{p}。连招。",
}))

reg(CardData.new({
    id = "gen_tome_of_fyendal",
    name = "教练笔记",
    type = T.SUPPORT, class = C.GENERIC,
    pitch = P.YELLOW, cost = 0, power = 0, defense = 2,
    rarity = R.SUPER_RARE,
    effects = {
        { id = "draw", params = { amount = 2 } },
        { id = "if_from_arsenal", then_ = {
            { id = "gain_life", params = { amount_formula = "hand_count" } },
        }},
    },
    text = "抽2牌。从预备区打出时，每张手牌回复1体力。",
}))

-- === 本能牌 ===

reg3(tri({
    id = "gen_sigil_of_solace", name = "深呼吸",
    type = T.INSTINCT, class = C.GENERIC,
    cost = 0, defense = 0, rarity = R.COMMON,
    effects = {
        { id = "gain_life", params = { amount = 3 } },
    },
    text = "回复N点体力。",
}, { 0, 0, 0 }, { amounts = { 3, 2, 1 } }))

-- ============================================================================
-- 六、Token 定义
-- ============================================================================

reg(CardData.new({
    id = "token_seismic_surge",
    name = "震波",
    type = T.AURA, class = C.GENERIC,
    pitch = P.NONE, cost = 0, power = 0, defense = 0,
    rarity = R.TOKEN,
    effects = {
        { id = "destroy_self" },
        { id = "buff_power", params = { target = "attack_cost_3_plus", amount = 1 } },
    },
    text = "打出费用≥3的攻击牌/架势时，可销毁此标记: +1{p}。",
}))

reg(CardData.new({
    id = "token_might",
    name = "力量",
    type = T.AURA, class = C.GENERIC,
    pitch = P.NONE, cost = 0, power = 0, defense = 0,
    rarity = R.TOKEN,
    effects = {
        { id = "destroy_self" },
        { id = "buff_power", params = { target = "next_attack", amount = 1 } },
    },
    text = "可销毁: 下次攻击+1{p}。",
}))

reg(CardData.new({
    id = "token_quicken",
    name = "加速",
    type = T.AURA, class = C.GENERIC,
    pitch = P.NONE, cost = 0, power = 0, defense = 0,
    rarity = R.TOKEN,
    effects = {
        { id = "destroy_self" },
        { id = "gain_action_point", params = { amount = 1 } },
    },
    text = "可销毁: 获得1行动点。",
}))

-- ============================================================================
-- 七、查询接口
-- ============================================================================

--- 按 ID 获取卡牌
---@param id string
---@return table|nil
function CardDB.get(id)
    return CardDB.cards[id]
end

--- 获取某职业可用的所有牌组牌（本职 + 通用）
---@param class string
---@return table[]
function CardDB.getPoolForClass(class)
    local result = {}
    for _, card in pairs(CardDB.cards) do
        if card.class == class or card.class == C.GENERIC then
            result[#result + 1] = card
        end
    end
    return result
end

--- 获取所有攻击牌
---@param class? string 可选职业过滤
---@return table[]
function CardDB.getAttacks(class)
    local result = {}
    for _, card in pairs(CardDB.cards) do
        if card:isAttack() then
            if not class or card.class == class or card.class == C.GENERIC then
                result[#result + 1] = card
            end
        end
    end
    return result
end

--- 按类型获取
---@param cardType string
---@param class? string
---@return table[]
function CardDB.getByType(cardType, class)
    local result = {}
    for _, card in pairs(CardDB.cards) do
        if card.cardType == cardType then
            if not class or card.class == class or card.class == C.GENERIC then
                result[#result + 1] = card
            end
        end
    end
    return result
end

--- 按名称模糊搜索
---@param namePattern string
---@return table[]
function CardDB.searchByName(namePattern)
    local result = {}
    for _, card in pairs(CardDB.cards) do
        if string.find(card.name, namePattern) then
            result[#result + 1] = card
        end
    end
    return result
end

--- 获取全部卡牌数量
---@return number
function CardDB.count()
    local n = 0
    for _ in pairs(CardDB.cards) do n = n + 1 end
    return n
end

--- 获取指定英雄的专属卡
---@param heroKey string 英雄 key (如 "kaede")
---@return table[]
function CardDB.getSpecializationCards(heroKey)
    local result = {}
    for _, card in pairs(CardDB.cards) do
        if card.specialization == heroKey then
            result[#result + 1] = card
        end
    end
    return result
end

--- 获取 Combo 链: 从指定卡名可以接续的牌
---@param cardName string
---@return table[]
function CardDB.getComboFollowups(cardName)
    local result = {}
    for _, card in pairs(CardDB.cards) do
        if card.comboFrom == cardName then
            result[#result + 1] = card
        end
    end
    return result
end

return CardDB

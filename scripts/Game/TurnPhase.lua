-- ============================================================================
-- Game/TurnPhase.lua - 回合阶段枚举与转换规则
-- ============================================================================

local TurnPhase = {}

-- ============================================================================
-- 阶段枚举
-- ============================================================================

TurnPhase.GAME_START      = "game_start"       -- 游戏开局（选英雄、洗牌、初始抽牌）
TurnPhase.START_PHASE     = "start_phase"      -- 开始阶段（回合开始触发效果）
TurnPhase.DRAW_PHASE      = "draw_phase"       -- 抽牌阶段（补满至 intellect 张）
TurnPhase.ACTION_PHASE    = "action_phase"     -- 行动阶段（出牌主阶段）
TurnPhase.COMBAT_CHAIN    = "combat_chain"     -- 连招阶段（攻防交互）
TurnPhase.END_PHASE       = "end_phase"        -- 结束阶段（预备区存牌、充能区归底）
TurnPhase.GAME_OVER       = "game_over"        -- 游戏结束

-- 连招链内部子阶段
TurnPhase.CHAIN_ATTACK    = "chain_attack"     -- 声明攻击
TurnPhase.CHAIN_DEFEND    = "chain_defend"     -- 声明防御
TurnPhase.CHAIN_REACTION  = "chain_reaction"   -- 反应阶段（交替追击/闪避）
TurnPhase.CHAIN_RESOLVE   = "chain_resolve"    -- 伤害结算
TurnPhase.CHAIN_LINK_END  = "chain_link_end"   -- 单环节结束（检查 Go Again）
TurnPhase.CHAIN_CLOSE     = "chain_close"      -- 连招链关闭（所有牌进弃牌堆）

-- ============================================================================
-- 阶段显示名（HUD 用）
-- ============================================================================

TurnPhase.DISPLAY = {
    [TurnPhase.START_PHASE]   = "开始",
    [TurnPhase.DRAW_PHASE]    = "抽牌",
    [TurnPhase.ACTION_PHASE]  = "行动",
    [TurnPhase.COMBAT_CHAIN]  = "连招",
    [TurnPhase.END_PHASE]     = "结束",
    [TurnPhase.GAME_START]    = "准备",
    [TurnPhase.GAME_OVER]     = "结束",
}

-- ============================================================================
-- 合法转换表
-- ============================================================================

TurnPhase.TRANSITIONS = {
    [TurnPhase.GAME_START]   = { TurnPhase.START_PHASE },
    [TurnPhase.START_PHASE]  = { TurnPhase.DRAW_PHASE },
    [TurnPhase.DRAW_PHASE]   = { TurnPhase.ACTION_PHASE },
    [TurnPhase.ACTION_PHASE] = { TurnPhase.COMBAT_CHAIN, TurnPhase.END_PHASE },
    [TurnPhase.COMBAT_CHAIN] = { TurnPhase.ACTION_PHASE, TurnPhase.END_PHASE },
    [TurnPhase.END_PHASE]    = { TurnPhase.START_PHASE, TurnPhase.GAME_OVER },
}

--- 检查阶段转换是否合法
---@param from string
---@param to string
---@return boolean
function TurnPhase.canTransition(from, to)
    local valid = TurnPhase.TRANSITIONS[from]
    if not valid then return false end
    for _, v in ipairs(valid) do
        if v == to then return true end
    end
    return false
end

return TurnPhase

-- ============================================================================
-- Game/PitchSystem.lua - 充能/资源系统
-- 高层充能管理：费用校验、自动充能建议、多牌充能序列
-- Player.lua 提供底层的 pitchCard/spendResource；
-- 本模块在此基础上提供游戏规则层的充能决策支持
-- ============================================================================

local CardData = require("Card.CardData")
local CardDB   = require("Card.CardDB")

local PitchSystem = {}

-- ============================================================================
-- 费用校验
-- ============================================================================

--- 检查玩家是否能支付某张牌的费用
--- 考虑当前资源池 + 可充能手牌的最大产出
---@param player table Player
---@param cardId string 要打出的牌 ID
---@return boolean canPay
---@return number deficit 差额 (>0 表示不够)
function PitchSystem.canPayFor(player, cardId)
    local card = CardDB.get(cardId)
    if not card then return false, 999 end

    local cost = card.cost
    if cost <= 0 then return true, 0 end

    local available = player.resourcePool
    if available >= cost then return true, 0 end

    -- 计算手牌可充能总量（排除要打出的牌本身）
    local pitchable = PitchSystem.getPitchableTotal(player, cardId)
    local total = available + pitchable

    if total >= cost then
        return true, 0
    else
        return false, cost - total
    end
end

--- 获取手牌中可充能的总体能（排除指定牌）
---@param player table
---@param excludeId? string 排除的卡牌 ID（正要打出的）
---@return number total
function PitchSystem.getPitchableTotal(player, excludeId)
    local total = 0
    local excluded = false
    for _, id in ipairs(player.hand) do
        -- 同 ID 可能有多张，只排除一张
        if id == excludeId and not excluded then
            excluded = true
        else
            local card = CardDB.get(id)
            if card and card.pitch > 0 then
                total = total + card.pitch
            end
        end
    end
    return total
end

--- 获取手牌中所有可充能的牌及其 pitch 值
---@param player table
---@param excludeId? string
---@return table[] { id, pitch, name }
function PitchSystem.getPitchableCards(player, excludeId)
    local result = {}
    local excluded = false
    for _, id in ipairs(player.hand) do
        if id == excludeId and not excluded then
            excluded = true
        else
            local card = CardDB.get(id)
            if card and card.pitch > 0 then
                result[#result + 1] = {
                    id    = id,
                    pitch = card.pitch,
                    name  = card.name,
                }
            end
        end
    end
    return result
end

-- ============================================================================
-- 充能建议（自动/AI 用）
-- ============================================================================

--- 计算最优充能方案：用最少的牌凑够 targetCost
--- 贪心策略：优先选 pitch 值刚好或略多的牌，减少浪费
---@param player table
---@param targetCost number 需要的体能
---@param excludeId? string 排除的卡牌 ID
---@return string[]|nil pitchIds 需要充能的牌 ID 列表（nil=无法凑够）
---@return number totalPitch 这些牌的总 pitch
function PitchSystem.suggestPitch(player, targetCost, excludeId)
    if targetCost <= 0 then return {}, 0 end

    -- 已有的资源
    local need = targetCost - player.resourcePool
    if need <= 0 then return {}, 0 end

    local pitchable = PitchSystem.getPitchableCards(player, excludeId)
    if #pitchable == 0 then return nil, 0 end

    -- 按 pitch 值降序排列（优先使用大额牌凑够）
    table.sort(pitchable, function(a, b) return a.pitch > b.pitch end)

    local selected = {}
    local total = 0

    for _, p in ipairs(pitchable) do
        selected[#selected + 1] = p.id
        total = total + p.pitch
        if total >= need then
            return selected, total
        end
    end

    -- 凑不够
    return nil, total
end

--- 计算最精确充能方案（最小浪费）
--- 使用动态规划寻找浪费最少的组合
---@param player table
---@param targetCost number
---@param excludeId? string
---@return string[]|nil pitchIds
---@return number waste 浪费的体能
function PitchSystem.suggestExactPitch(player, targetCost, excludeId)
    local need = targetCost - player.resourcePool
    if need <= 0 then return {}, 0 end

    local pitchable = PitchSystem.getPitchableCards(player, excludeId)
    if #pitchable == 0 then return nil, 0 end

    -- 暴力搜索（手牌通常 ≤ 4 张，2^4 = 16 组合，可接受）
    local bestCombo = nil
    local bestTotal = 999
    local bestWaste = 999

    local n = #pitchable
    -- 限制：最多搜索 2^8 = 256 组合
    local maxBit = math.min(n, 8)
    local combos = 1 << maxBit

    for mask = 1, combos - 1 do
        local total = 0
        local combo = {}
        for i = 1, maxBit do
            if mask & (1 << (i - 1)) ~= 0 then
                total = total + pitchable[i].pitch
                combo[#combo + 1] = pitchable[i].id
            end
        end
        if total >= need then
            local waste = total - need
            if waste < bestWaste or (waste == bestWaste and #combo < #bestCombo) then
                bestWaste = waste
                bestTotal = total
                bestCombo = combo
            end
        end
    end

    if bestCombo then
        return bestCombo, bestWaste
    end
    return nil, 0
end

-- ============================================================================
-- 充能执行
-- ============================================================================

--- 执行充能序列：依次充能指定的牌
---@param player table
---@param pitchIds string[]
---@return number totalGained 实际获得的总体能
function PitchSystem.executePitch(player, pitchIds)
    local total = 0
    for _, id in ipairs(pitchIds) do
        local gained = player:pitchCard(id)
        total = total + gained
    end
    return total
end

--- 充能并支付费用（一步到位）
---@param player table
---@param cardId string 要打出的牌
---@param pitchIds? string[] 手动指定充能方案（nil=自动）
---@param overrideCost? number 覆盖费用（费用减免后的实际费用，nil=使用卡牌原始费用）
---@return boolean success
---@return string|nil error 失败原因
function PitchSystem.pitchAndPay(player, cardId, pitchIds, overrideCost)
    local card = CardDB.get(cardId)
    if not card then return false, "unknown_card" end

    local cost = overrideCost or card.cost
    if cost <= 0 then return true, nil end

    -- 先尝试用已有资源
    if player.resourcePool >= cost then
        player:spendResource(cost)
        return true, nil
    end

    -- 需要充能
    if not pitchIds then
        -- 自动寻找最优方案
        pitchIds = PitchSystem.suggestExactPitch(player, cost)
        if not pitchIds then
            return false, "insufficient_resource"
        end
    end

    -- 执行充能
    PitchSystem.executePitch(player, pitchIds)

    -- 支付费用
    if player.resourcePool >= cost then
        player:spendResource(cost)
        return true, nil
    else
        return false, "pitch_insufficient"
    end
end

-- ============================================================================
-- 查询
-- ============================================================================

--- 充能区有指定条件的牌数
---@param player table
---@param filter fun(card:table):boolean
---@return number
function PitchSystem.countInPitchZone(player, filter)
    local count = 0
    for _, id in ipairs(player.pitchZone) do
        local card = CardDB.get(id)
        if card and filter(card) then
            count = count + 1
        end
    end
    return count
end

--- 充能区有 pitch=0 的牌？（跆拳道·战斗站架判定）
---@param player table
---@return boolean
function PitchSystem.pitchZoneHasCostZero(player)
    return PitchSystem.countInPitchZone(player, function(card)
        return card.cost == 0
    end) > 0
end

--- 充能区有费用 ≥ N 的牌数（太极·太极起势判定）
---@param player table
---@param minCost number
---@return number
function PitchSystem.pitchZoneCountCostGte(player, minCost)
    return PitchSystem.countInPitchZone(player, function(card)
        return card.cost >= minCost
    end)
end

return PitchSystem

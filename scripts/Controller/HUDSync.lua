-- ============================================================================
-- Controller/HUDSync.lua - HUD 与手牌视觉同步
-- 职责：_syncHUD / _syncHandVisuals / _syncRemovedCards
-- ============================================================================

local CardDB          = require("Card.CardDB")
local Card3D          = require("Card.Card3D")
local CardData        = require("Card.CardData")
local HUD             = require("UI.HUD")
local HeroPanel3D     = require("UI.HeroPanel3D")
local PhaseBar        = require("UI.PhaseBar")
local ActionValidator = require("Game.ActionValidator")
local CardGlowManager = require("Card.CardGlowManager")
local ActionBar       = require("UI.ActionBar")

local SLOT = CardData.SLOT

local CLASS_DISPLAY = {
    warrior  = "剑道",
    ninja    = "跆拳道",
    guardian = "太极",
    brute    = "拳击",
}

-- BA 风格：玩家薄荷绿，对手珊瑚红
local CLASS_ACCENT = {
    warrior  = { r=82,  g=200, b=160 },  -- 薄荷绿
    ninja    = { r=255, g=107, b=107 },  -- 珊瑚红
    guardian = { r=91,  g=156, b=246 },  -- 天蓝
    brute    = { r=255, g=182, b=80  },  -- 暖橙
}
local PLAYER_ACCENT = { r=82,  g=200, b=160 }  -- 玩家固定薄荷绿
local OPP_ACCENT    = { r=255, g=107, b=107 }  -- 对手固定珊瑚红

-- 上一次推送的 heroKey，避免每帧重建
local lastPlayerHero_ = nil
local lastOppHero_    = nil

local HUDSync = {}

-- ============================================================================
-- HUD 状态推送
-- ============================================================================

--- 每帧同步 HUD 数据
---@param gc table GameController
function HUDSync.syncHUD(gc)
    local p1 = gc.fsm.players[1]  -- 玩家
    local p2 = gc.fsm.players[2]  -- 对手

    local updates = {
        -- 己方
        myName     = p1.heroName,
        myStyle    = CLASS_DISPLAY[p1.class] or p1.class,
        myLife     = p1.life,
        myLifeMax  = p1.maxLife,
        myDeckCount  = gc._myDeckStack:getCount(),
        myHandCount  = gc._handFan:count(),
        myGraveyardCount = #p1.graveyard,
        myBanishCount    = #p1.banishZone,
        myArsenalCount   = #p1.arsenal,
        myEnergy   = p1.resourcePool,
        myEnergyMax = math.max(p1.resourcePool, 3),

        -- 对手
        oppName    = p2.heroName,
        oppStyle   = CLASS_DISPLAY[p2.class] or p2.class,
        oppLife    = p2.life,
        oppLifeMax = p2.maxLife,
        oppDeckCount  = gc._oppDeckStack:getCount(),
        oppHandCount  = gc._oppHandFan:count(),
        oppGraveyardCount = #p2.graveyard,
        oppBanishCount    = #p2.banishZone,
        oppArsenalCount   = #p2.arsenal,
        oppEnergy  = p2.resourcePool,
        oppEnergyMax = math.max(p2.resourcePool, 3),

        -- 游戏状态
        actionPoints    = gc.fsm:currentPlayer().actionPoints,
        maxActionPoints = 1,
        chainCount      = gc._zoneLayout:cardCount("combatChain"),
        currentPhase    = PhaseBar.getCurrentIndex(),

        -- 玩家交互状态
        waitingForInput = gc._waitingForInput,
        isPlayerTurn    = (gc.fsm.turnPlayerIndex == gc._playerIndex),
        aiThinking      = gc._aiThinking,
    }

    -- 架势（武器）
    if #p1.weapons > 0 then
        local w = p1.weapons[1]
        updates.myStanceName  = w.data.name
        updates.myStancePower = w.data.power + (w.hitCounters or 0)
        updates.myStanceCost  = w.data.cost or 0
    end
    if #p2.weapons > 0 then
        local w = p2.weapons[1]
        updates.oppStanceName  = w.data.name
        updates.oppStancePower = w.data.power + (w.hitCounters or 0)
        updates.oppStanceCost  = w.data.cost or 0
    end

    -- 护具
    local eq1u = p1.equipment[SLOT.UPPER]
    if eq1u and eq1u.data then
        updates.myArmorUpper    = eq1u.data.name
        updates.myArmorUpperCur = eq1u.defense
        updates.myArmorUpperMax = eq1u.data.defense or eq1u.defense
    end
    local eq1l = p1.equipment[SLOT.LOWER]
    if eq1l and eq1l.data then
        updates.myArmorLower    = eq1l.data.name
        updates.myArmorLowerCur = eq1l.defense
        updates.myArmorLowerMax = eq1l.data.defense or eq1l.defense
    end

    local eq2u = p2.equipment[SLOT.UPPER]
    if eq2u and eq2u.data then
        updates.oppArmorUpper    = eq2u.data.name
        updates.oppArmorUpperCur = eq2u.defense
        updates.oppArmorUpperMax = eq2u.data.defense or eq2u.defense
    end
    local eq2l = p2.equipment[SLOT.LOWER]
    if eq2l and eq2l.data then
        updates.oppArmorLower    = eq2l.data.name
        updates.oppArmorLowerCur = eq2l.defense
        updates.oppArmorLowerMax = eq2l.data.defense or eq2l.defense
    end

    HUD.updateState(updates)

    -- 推送玩家能量到右侧 ActionBar 面板
    ActionBar.setEnergy(p1.resourcePool or 0, math.max(p1.resourcePool or 0, 3))

    -- 推送英雄 key 到 3D 面板（仅 heroKey 变化时重建贴图/颜色，避免每帧触发）
    local panels = gc._heroPanels   -- { player = HeroPanel3D, opp = HeroPanel3D }
    if panels then
        local p1Key = p1.heroKey or "kaede"
        local p2Key = p2.heroKey or "xia_lin"
        if p1Key ~= lastPlayerHero_ then
            lastPlayerHero_ = p1Key
            HeroPanel3D.setHero(panels.player, p1Key, p1.class, PLAYER_ACCENT)
        end
        if p2Key ~= lastOppHero_ then
            lastOppHero_ = p2Key
            HeroPanel3D.setHero(panels.opp, p2Key, p2.class, OPP_ACCENT)
        end
    end
end

-- ============================================================================
-- 手牌视觉同步
-- ============================================================================

--- 检测 FSM 中新增的手牌（无 Card3D 映射），创建并加入扇面
---@param gc table GameController
---@param playerIndex number
function HUDSync.syncHandVisuals(gc, playerIndex)
    local player    = gc.fsm.players[playerIndex]
    local fan       = gc:_getHandFan(playerIndex)
    local deckStack = gc:_getDeckStack(playerIndex)
    local isPlayer  = (playerIndex == 1)

    local newCardIds = {}
    for _, cardId in ipairs(player.hand) do
        if not gc._cardIdToCard3D[cardId] then
            newCardIds[#newCardIds + 1] = cardId
        end
    end

    if #newCardIds == 0 then return end

    local deckPos = deckStack:getTopPos()
    for _, cardId in ipairs(newCardIds) do
        local cardData = CardDB.get(cardId)
        if cardData then
            local card3d = Card3D.create(gc._scene, cardData, isPlayer)
            fan:addCard(card3d)
            if isPlayer then
                gc._cardPicker:register(card3d)
            end
            gc._cardIdToCard3D[cardId] = card3d
            gc._card3DToCardId[card3d] = cardId

            fan:drawFromDeck(card3d, deckPos)
        end
    end

    deckStack:setCount(#player.deck)
end

--- 检测 FSM 中已移除的手牌，销毁对应 Card3D
---@param gc table GameController
---@param playerIndex number
function HUDSync.syncRemovedCards(gc, playerIndex)
    local player   = gc.fsm.players[playerIndex]
    local fan      = gc:_getHandFan(playerIndex)
    local isPlayer = (playerIndex == 1)

    local handSet = {}
    for _, cardId in ipairs(player.hand) do
        handSet[cardId] = true
    end

    local cards = fan:getCards()
    local toRemove = {}
    for _, card3d in ipairs(cards) do
        local cardId = gc._card3DToCardId[card3d]
        if cardId and not handSet[cardId] then
            toRemove[#toRemove + 1] = { card3d = card3d, cardId = cardId }
        end
    end

    for _, entry in ipairs(toRemove) do
        fan:removeCard(entry.card3d)
        if isPlayer then
            gc._cardPicker:unregister(entry.card3d)
        end
        entry.card3d:destroy()
        gc._cardIdToCard3D[entry.cardId] = nil
        gc._card3DToCardId[entry.card3d] = nil
    end

    if #toRemove > 0 then
        fan:applyLayout(true)
    end
end

-- ============================================================================
-- 可打出状态同步（光效）
-- ============================================================================

--- 根据当前 FSM 状态，更新玩家 1 手牌的可打出光效
---@param gc table GameController
function HUDSync.syncPlayability(gc)
    if not gc.fsm or not gc._started then
        CardGlowManager.clearAll()
        return
    end

    -- 仅在玩家回合的行动/连招阶段有意义
    local phase   = gc.fsm:effectivePhase()
    local player  = gc.fsm.players[1]
    local opponent = gc.fsm.players[2]
    local chain   = gc.fsm.combatChain

    CardGlowManager.clearAll()

    -- 只在己方回合（玩家 index=1）且处于可行动阶段时点亮
    if gc.fsm.turnPlayerIndex ~= 1 then return end

    for _, cardId in ipairs(player.hand) do
        local card3d = gc._cardIdToCard3D[cardId]
        if card3d then
            -- 只要有任意合法行动（攻击/辅助/留场/充能）即高亮
            local playable = false
            if ActionValidator.canPlayAttack(player, cardId, phase, chain) then
                playable = true
            elseif ActionValidator.canPlaySupport(player, cardId, phase) then
                playable = true
            elseif ActionValidator.canPlayArenaCard(player, cardId, phase) then
                playable = true
            elseif ActionValidator.canPitch(player, cardId) then
                playable = true
            end
            if playable then
                CardGlowManager.setPlayable(card3d, true)
            end
        end
    end
end

return HUDSync

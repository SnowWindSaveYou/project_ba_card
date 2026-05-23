-- ============================================================================
-- Controller/GameController.lua - FSM ↔ 视觉层桥梁
-- 职责：生命周期管理、FSM 回调注册与处理、update 主循环
-- Actor 驱动：actors[1]=HumanActor, actors[2]=AIActor/RemoteActor/BossActor
-- ============================================================================

local CardData     = require("Card.CardData")
local CardDB       = require("Card.CardDB")
local Card3D       = require("Card.Card3D")
local CardAnimator = require("Anim.CardAnimator")
local HitFlash     = require("Anim.HitFlash")
local GameFSM      = require("Game.GameFSM")
local Player       = require("Game.Player")
local TurnPhase    = require("Game.TurnPhase")
local Timer        = require("Core.Timer")
local PhaseBar     = require("UI.PhaseBar")
local CombatLog    = require("UI.CombatLog")
local ActionBar      = require("UI.ActionBar")
local DefensePanel   = require("UI.DefensePanel")
local GameOverScreen = require("UI.GameOverScreen")
local PhaseBanner    = require("UI.PhaseBanner")
local CombatCounter  = require("UI.CombatCounter")
local SFX            = require("Audio.SFX")
local Particles      = require("Anim.Particles")
local BattleGrid       = require("Scene.BattleGrid")
local BattleResolution = require("UI.BattleResolution")
local CoinFlip         = require("UI.CoinFlip")

-- 子模块
local ActionBarBuilder = require("Controller.ActionBarBuilder")
local HUDSync          = require("Controller.HUDSync")
local HumanActor       = require("Controller.HumanActor")
local AIActor          = require("Controller.AIActor")

local GameController = {}
GameController.__index = GameController

-- ============================================================================
-- 构造
-- ============================================================================

--- 创建游戏控制器
---@param deps table 依赖注入
---  scene       : Scene
---  handFan     : HandFan (玩家手牌)
---  oppHandFan  : HandFan (对手手牌)
---  zoneLayout  : ZoneLayout
---  myDeckStack : DeckStack (玩家牌堆)
---  oppDeckStack: DeckStack (对手牌堆)
---  cardPicker  : CardPicker
---  playerHero  : string (玩家英雄 key)
---  aiHero      : string|nil (AI英雄 key, nil=随机)
---  opponentActor : table|nil (对手 Actor 实例, nil=默认 AIActor)
function GameController.new(deps)
    local self = setmetatable({}, GameController)

    -- 视觉组件引用
    self._scene        = deps.scene
    self._handFan      = deps.handFan
    self._oppHandFan   = deps.oppHandFan
    self._zoneLayout   = deps.zoneLayout
    self._myDeckStack  = deps.myDeckStack
    self._oppDeckStack = deps.oppDeckStack
    self._cardPicker   = deps.cardPicker
    self._cameraRig    = deps.cameraRig

    -- Card ID ↔ Card3D 双向映射
    self._cardIdToCard3D = {}
    self._card3DToCardId = {}

    -- Actor 表：槽位 1 恒定人类，槽位 2 可替换
    self._actors = {
        [1] = HumanActor.new(),
        [2] = deps.opponentActor or AIActor.new(),
    }
    self._activeActor = nil  -- 当前正在行动的 actor

    -- 游戏状态
    self.fsm        = nil
    self._dealDone  = false
    self._pendingDeals = 0
    self._actionDelay  = 0
    self._gameOver  = false
    self._started   = false

    -- 玩家交互状态（HumanActor / PlayerInput 读写）
    self._waitingForInput = false
    self._playerIndex     = 1
    self._inputPhase      = nil

    -- 防御队列（PlayerInput 读写）
    self._defenseQueue    = {}
    self._defenseEquips   = {}

    -- 英雄选择
    self._playerHero = deps.playerHero or "kaede"
    self._aiHero     = deps.aiHero

    -- 横幅去重：记录上次显示的 barIndex，防止子阶段重复触发
    self._lastBannerIndex = 0

    -- 战斗结算网格（由外部 main.lua 创建后注入，避免重复构造）
    self._battleGrid = deps.battleGrid or BattleGrid.create(deps.scene)
    -- setGrid 已在 main.lua 中调用；若无外部注入则在此处补设
    if not deps.battleGrid then
        BattleResolution.setGrid(self._battleGrid)
    end

    return self
end

-- ============================================================================
-- 生命周期
-- ============================================================================

--- 重新开始对局
function GameController:restartGame()
    GameOverScreen.hide()
    ActionBar.hide()
    DefensePanel.hide()

    -- 退出当前 actor
    if self._activeActor then
        self._activeActor:onExit(self)
        self._activeActor = nil
    end

    -- 清理所有 Card3D
    for _, card3d in pairs(self._cardIdToCard3D) do
        self._cardPicker:unregister(card3d)
        card3d:destroy()
    end
    self._cardIdToCard3D = {}
    self._card3DToCardId = {}

    self._handFan:clear()
    self._oppHandFan:clear()

    -- 清理战斗区
    local chainCards = self._zoneLayout:getCards("combatChain")
    for i = #chainCards, 1, -1 do
        self._cardPicker:unregisterDisplay(chainCards[i])
        chainCards[i]:destroy()
    end
    self._zoneLayout:clearZone("combatChain")

    -- 重置状态
    self._waitingForInput = false
    self._inputPhase = nil
    self._defenseQueue = {}
    self._defenseEquips = {}
    self._dealDone = false
    self._pendingDeals = 0
    self._actionDelay = 0
    self._gameOver = false
    self._started = false
    self._lastBannerIndex = 0

    self:startGame()
end

--- 启动对局
function GameController:startGame()
    -- 选对手英雄（与玩家不同）
    local aiHero = self._aiHero
    if not aiHero then
        local heroes = { "kaede", "xia_lin", "yun_rou", "xiao_tao" }
        repeat
            aiHero = heroes[math.random(#heroes)]
        until aiHero ~= self._playerHero
    end

    -- 构建牌组和装备
    local deck1  = Player.buildDefaultDeck(self._playerHero)
    local equip1 = Player.getDefaultEquipment(self._playerHero)
    local deck2  = Player.buildDefaultDeck(aiHero)
    local equip2 = Player.getDefaultEquipment(aiHero)

    -- 创建 FSM
    self.fsm = GameFSM.new({
        player1Cfg = { heroKey = self._playerHero, deckCardIds = deck1, equipmentIds = equip1 },
        player2Cfg = { heroKey = aiHero,           deckCardIds = deck2, equipmentIds = equip2 },
    })

    -- 注册回调
    self:_registerCallbacks()

    -- 设置 ActionBar 回调
    ActionBar.setOnAction(function(actionType)
        ActionBarBuilder.onClick(self, actionType)
    end)

    -- 设置 GameOverScreen 重启回调
    GameOverScreen.setOnRestart(function()
        self:restartGame()
    end)

    -- 设置初始牌堆数
    self._myDeckStack:setCount(#self.fsm.players[1].deck)
    self._oppDeckStack:setCount(#self.fsm.players[2].deck)

    -- 初始化音效
    SFX.init()

    -- 清理 UI 和粒子
    CombatLog.clear()
    PhaseBar.reset()
    Particles.clear()
    CombatLog.phase("游戏开始!")

    -- 随机决定先手（1=玩家先手，2=对手先手）
    local coinWinner = math.random(2)

    -- 播放先手抽取动画，动画结束后再启动 FSM
    CoinFlip.show(
        self._playerHero,
        self.fsm.players[2].heroKey,
        coinWinner,
        function()
            -- 动画结束 → 根据结果调整先手
            if coinWinner == 2 then
                self.fsm.turnPlayerIndex = 2
            end
            print("[GC-CB] 调用 startGame, turnPlayerIndex=" .. tostring(self.fsm.turnPlayerIndex))
            local ok, err = pcall(function() self.fsm:startGame() end)
            if not ok then
                print("[GC-CB] startGame 错误: " .. tostring(err))
                CombatLog.phase("startGame错误: " .. tostring(err))
                return
            end
            print("[GC-CB] startGame 完成, _started=true")
            self._started = true
            HUDSync.syncHUD(self)
        end
    )
end

--- 每帧更新
function GameController:update(dt)
    -- CoinFlip 动画始终更新（游戏启动前也需要）
    CoinFlip.update(dt)

    if not self._started then return end

    -- 战斗结算网格 & 全屏动画始终更新（独立于游戏状态）
    if self._battleGrid then
        self._battleGrid:update(dt)
    end
    BattleResolution.update(dt)

    -- 同步 HUD（含 AI 思考状态）
    self._aiThinking = self._actors[2].isThinking and self._actors[2]:isThinking() or false
    HUDSync.syncHUD(self)

    if not self._dealDone then return end
    if self._gameOver then return end

    -- 当前 actor 正在行动：推进其 update
    if self._activeActor then
        if self._activeActor:isActive() then
            self._activeActor:onUpdate(self, dt)
            return
        else
            -- actor 已完成行动，对称调用 onExit 后清除引用
            self._activeActor:onExit(self)
            self._activeActor = nil
        end
    end

    -- 通用延迟（发牌后、动作后间隔）
    if self._actionDelay > 0 then
        self._actionDelay = self._actionDelay - dt
        return
    end

    -- 判断当前应由谁行动，激活对应 actor
    local phase = self.fsm:effectivePhase()
    local actorIndex = self:_getActorIndex(phase)
    local actor = self._actors[actorIndex]
    local actorName = (actorIndex == 1) and "HumanActor" or "AIActor"
    print(string.format("[GC-update] 激活 %s  phase=%s", actorName, phase))

    self._activeActor = actor
    actor:onEnter(self, phase)
    print(string.format("[GC-update] 激活完成 %s  waiting=%s", actorName, tostring(self._waitingForInput)))
end

--- 对局是否结束
function GameController:isGameOver()
    return self._gameOver
end

--- 获取 FSM 实例
function GameController:getFSM()
    return self.fsm
end

--- 获取对手 Actor（供外部查询类型/状态）
function GameController:getOpponentActor()
    return self._actors[2]
end

-- ============================================================================
-- 外部调用接口（委托给槽位 1 的 HumanActor）
-- ============================================================================

function GameController:submitPlayerAction(action)
    return self._actors[1]:submitAction(self, action)
end

function GameController:submitDragPlay(card3d)
    return self._actors[1]:submitDragPlay(self, card3d)
end

function GameController:submitDragPitch(card3d)
    return self._actors[1]:submitDragPitch(self, card3d)
end

function GameController:isWaitingForInput()
    return self._waitingForInput
end

function GameController:getInputPhase()
    return self._inputPhase
end

--- 获取玩家当前武器/架势的完整卡牌数据（用于 CardTooltip）
---@return table|nil weaponData
function GameController:getWeaponCard()
    local p1 = self.fsm and self.fsm.players and self.fsm.players[1]
    if not p1 or #p1.weapons == 0 then return nil end
    return p1.weapons[1].data
end

--- 获取玩家指定槽位护具的完整卡牌数据（用于 CardTooltip）
---@param slot string CardData.SLOT.UPPER / SLOT.LOWER
---@return table|nil equipData
function GameController:getArmorCard(slot)
    local p1 = self.fsm and self.fsm.players and self.fsm.players[1]
    if not p1 then return nil end
    local eq = p1.equipment[slot]
    if eq and not eq.destroyed then return eq.data end
    return nil
end

-- ============================================================================
-- FSM 回调注册
-- ============================================================================

function GameController:_registerCallbacks()
    local cb = self.fsm.callbacks

    cb.onDrawCards = function(playerIndex, cardIds)
        self:_onDrawCards(playerIndex, cardIds)
    end

    cb.onCardPlayed = function(playerIndex, cardId, cardData, actionType)
        self:_onCardPlayed(playerIndex, cardId, cardData, actionType)
    end

    cb.onAttackDeclared = function(link)
        self:_onAttackDeclared(link)
    end

    cb.onDefenseDeclared = function(link, totalDefense)
        self:_onDefenseDeclared(link, totalDefense)
    end

    cb.onDamageResolved = function(link, damage, didHit)
        self:_onDamageResolved(link, damage, didHit)
    end

    cb.onLifeChanged = function(playerIndex, newLife, delta)
        -- HUD 由 syncHUD 每帧更新
    end

    cb.onPhaseChanged = function(phase, subPhase)
        self:_onPhaseChanged(phase, subPhase)
    end

    cb.onGameOver = function(winnerIndex, reason)
        self:_onGameOver(winnerIndex, reason)
    end

    cb.onLogAdded = function(entry)
        -- FSM 日志已通过各回调用 CombatLog 处理
    end

    cb.onChainClosed = function(summary)
        self:_onChainClosed(summary)
    end

    cb.onTurnStarted = function(turnPlayerIndex, turnNumber)
        self:_onTurnStarted(turnPlayerIndex, turnNumber)
    end
end

-- ============================================================================
-- FSM 回调处理
-- ============================================================================

function GameController:_onDrawCards(playerIndex, cardIds)
    local isPlayer  = (playerIndex == 1)
    local fan       = self:_getHandFan(playerIndex)
    local deckStack = self:_getDeckStack(playerIndex)

    for _, cardId in ipairs(cardIds) do
        local cardData = CardDB.get(cardId)
        if cardData then
            local card3d = Card3D.create(self._scene, cardData, isPlayer)
            fan:addCard(card3d)

            if isPlayer then
                self._cardPicker:register(card3d)
            end

            self._cardIdToCard3D[cardId] = card3d
            self._card3DToCardId[card3d] = cardId
        end
    end

    local player = self.fsm.players[playerIndex]
    deckStack:setCount(#player.deck)

    SFX.draw()

    local deckPos = deckStack:getTopPos()
    self._pendingDeals = self._pendingDeals + 1
    fan:dealAll(deckPos, function()
        self._pendingDeals = self._pendingDeals - 1
        if self._pendingDeals <= 0 then
            self._dealDone = true
            self._actionDelay = 1.5
            print("[GC-deal] _dealDone=true, delay=1.5")
        end
    end)
end

function GameController:_onCardPlayed(playerIndex, cardId, cardData, actionType)
    local card3d = self._cardIdToCard3D[cardId]
    if not card3d then return end

    local isPlayer = (playerIndex == 1)
    local fan = self:_getHandFan(playerIndex)

    fan:removeCard(card3d)
    if isPlayer then
        self._cardPicker:unregister(card3d)
    end

    if actionType == "attack" or actionType == "arsenal_attack" then
        SFX.attack()
        if not card3d.faceUp then
            card3d:flip()
        end

        local chainPos = self._zoneLayout:getNextChainPos()
        local cameraRig = self._cameraRig
        local gc = self
        self._zoneLayout:addCard("combatChain", card3d)
        CardAnimator.playThrow(card3d, Vector3(chainPos.x, chainPos.y, chainPos.z), function()
            -- 出牌落地：冲击弹跳 + 镜头震动 + 攻击火花
            CardAnimator.impactSlam(card3d)
            if cameraRig then cameraRig:shake(0.06, 0.15) end
            local cx, cy = gc:_screenCenter()
            Particles.attackSpark(cx, cy * 0.75)
            -- 落地后重新居中整条战斗链
            gc._zoneLayout:arrangeZone("combatChain")
        end)
        self._cardPicker:registerDisplay(card3d)
    else
        SFX.pitch()
        if not card3d.faceUp then
            card3d:flip()
        end
        -- 充能粒子（底部区域）
        local cx, cy = self:_screenCenter()
        Particles.pitchConvert(cx, cy * 1.4)
        Timer.after(0.8, function()
            card3d:destroy()
        end)
    end

    self._cardIdToCard3D[cardId] = nil
    self._card3DToCardId[card3d] = nil

    Timer.after(0.3, function()
        fan:applyLayout(true)
    end)

    -- 出牌/充能后手牌变化，重新同步可打出光效
    if playerIndex == 1 then
        HUDSync.syncPlayability(self)
    end
end

function GameController:_onAttackDeclared(link)
    local atkName = link.attackCard and link.attackCard.name or "架势"
    CombatLog.attack(string.format("攻击: %s (攻击力 %d)", atkName, link.attackPower))
    CombatCounter.showAttack(link.attackPower)
end

function GameController:_onDefenseDeclared(link, totalDefense)
    local defenderIndex = self.fsm:opponentIndex()
    local fan       = self:_getHandFan(defenderIndex)
    local isPlayer  = (defenderIndex == 1)

    for _, def in ipairs(link.defendCards) do
        local cardId = def.cardId
        local card3d = self._cardIdToCard3D[cardId]
        if card3d then
            local inFan = fan:indexOf(card3d) > 0
            if inFan then
                fan:removeCard(card3d)
                if isPlayer then
                    self._cardPicker:unregister(card3d)
                end

                if not card3d.faceUp then
                    card3d:flip()
                end

                local defPos = self._zoneLayout:getNextChainPos()
                self._zoneLayout:addCard("combatChain", card3d)
                local zl = self._zoneLayout
                CardAnimator.playThrow(card3d, Vector3(defPos.x, defPos.y, defPos.z), function()
                    -- 落地后重新居中整条战斗链
                    zl:arrangeZone("combatChain")
                end)
                self._cardPicker:registerDisplay(card3d)
            end

            self._cardIdToCard3D[cardId] = nil
            self._card3DToCardId[card3d] = nil
        end
    end

    fan:applyLayout(true)

    local defDesc = #link.defendCards .. " 张手牌"
    if #link.equipDefends > 0 then
        defDesc = defDesc .. " + " .. #link.equipDefends .. " 件护具"
    end
    CombatLog.system(string.format("防御: %s (总防 %d)", defDesc, totalDefense))
    SFX.defend()
    -- 防御粒子（战斗区）
    local cx, cy = self:_screenCenter()
    Particles.defendFlash(cx, cy * 0.75)
    -- 切换到攻防对比模式
    CombatCounter.showClash(totalDefense)
end

function GameController:_onDamageResolved(link, damage, didHit)
    local cx, cy = self:_screenCenter()
    if didHit then
        CombatLog.attack(string.format("命中! 造成 %d 点伤害", damage))
        SFX.hit()
        -- 命中反馈：红闪 + 镜头震动 + 伤害粒子
        HitFlash.triggerDamage(0.2)
        if self._cameraRig then
            local intensity = math.min(0.15, 0.05 + damage * 0.015)
            self._cameraRig:shake(intensity, 0.25)
        end
        Particles.damageHit(cx, cy * 0.75)
    else
        CombatLog.system("完全格挡!")
        -- 格挡反馈：白闪 + 格挡粒子
        HitFlash.trigger(0.1)
        Particles.blockSuccess(cx, cy * 0.75)
    end
    -- 结算后延迟淡出计数器
    Timer.after(0.6, function() CombatCounter.hide() end)
end

-- 阶段横幅映射表
local PHASE_BANNER_INFO = {
    [1] = { title = "开始阶段",  subtitle = "回合开始" },
    [2] = { title = "抽牌阶段",  subtitle = "补充手牌" },
    [3] = { title = "行动阶段",  subtitle = "选择出牌或充能" },
    [4] = { title = "战斗链",    subtitle = "攻防交锋" },
    [5] = { title = "结束阶段",  subtitle = "回合收尾" },
}

function GameController:_onPhaseChanged(phase, subPhase)
    local barIndex = self:_phaseToBarIndex(phase, subPhase)
    PhaseBar.setPhase(barIndex)

    -- 播报当前阶段（每次阶段变化都输出，含子阶段）
    local phaseName = TurnPhase.DISPLAY[phase] or phase
    if subPhase then
        phaseName = phaseName .. " > " .. (TurnPhase.DISPLAY[subPhase] or subPhase)
    end
    local turnInfo = self.fsm and self.fsm.turnPlayerIndex
        and (self.fsm.turnPlayerIndex == self._playerIndex and "我方回合" or "对手回合")
        or ""
    CombatLog.phase(string.format("[阶段] %s  %s", phaseName, turnInfo))

    -- 刷新手牌可打出光效（阶段变化后重新判定）
    HUDSync.syncPlayability(self)

    -- 触发阶段切换提示（仅主阶段切换，子阶段不重复触发）
    if barIndex == self._lastBannerIndex then return end
    self._lastBannerIndex = barIndex

    if barIndex == 3 then
        -- 行动阶段：BattleGrid 信号动画（翠绿=己方，深红=对手）
        local isPlayerTurn = (self.fsm.turnPlayerIndex == self._playerIndex)
        if self._battleGrid then
            if isPlayerTurn then
                self._battleGrid:signalYourTurn()
            else
                self._battleGrid:signalOpponentTurn()
            end
        end
        SFX.phase()
    else
        -- 其他阶段：小型角落标签
        local info = PHASE_BANNER_INFO[barIndex]
        if info then
            PhaseBanner.show(info.title, info.subtitle, "gold")
            SFX.phase()
        end
    end
end

function GameController:_onGameOver(winnerIndex, reason)
    self._gameOver = true
    ActionBar.hide()
    DefensePanel.hide()

    -- 退出当前 actor
    if self._activeActor then
        self._activeActor:onExit(self)
        self._activeActor = nil
    end

    local winner = self.fsm.players[winnerIndex]
    local reasonText = ({
        knockout = "击倒",
        concede  = "认输",
        deckout  = "牌库耗尽",
    })[reason] or reason
    CombatLog.phase(string.format("游戏结束! %s 获胜 (%s)", winner.heroName, reasonText))

    local isPlayerWin = (winnerIndex == self._playerIndex)
    Timer.after(1.2, function()
        if isPlayerWin then SFX.victory() else SFX.defeat() end
        GameOverScreen.show({
            playerWon  = isPlayerWin,
            winnerName = winner.heroName,
            reason     = reason,
            turnCount  = self.fsm.turnNumber or 0,
            playerLife = self.fsm.players[self._playerIndex].life,
            oppLife    = self.fsm.players[self._playerIndex == 1 and 2 or 1].life,
        })
    end)
end

function GameController:_onChainClosed(summary)
    Timer.after(0.5, function()
        local chainCards = self._zoneLayout:getCards("combatChain")
        for i = #chainCards, 1, -1 do
            self._cardPicker:unregisterDisplay(chainCards[i])
            chainCards[i]:destroy()
        end
        self._zoneLayout:clearZone("combatChain")
    end)

    CombatLog.system(string.format(
        "连招链关闭: %d 环节, 总伤 %d, 命中 %d",
        summary.linkCount, summary.totalDamage, summary.hits))

    -- 只要有战斗发生（至少一次攻击声明），无论伤害是否为零都播放结算动画
    if summary.linkCount > 0 then
        if summary.totalDamage > 0 then
            SFX.combo()
            local cx, cy = self:_screenCenter()
            Particles.chainClose(cx, cy * 0.75)
        end

        -- 触发战斗结算全屏动画
        if not BattleResolution.isActive() then
            local isPlayerWon = summary.hits > 0
                and (self.fsm.turnPlayerIndex == self._playerIndex)
            -- 攻击方是否在上半区：turn player = 玩家(index=1) 时攻击方在下半(upper=false)
            local attackerIsUpper = (self.fsm.turnPlayerIndex ~= self._playerIndex)
            Timer.after(1.0, function()
                BattleResolution.trigger({
                    playerWon       = isPlayerWon,
                    attackVal       = summary.lastAttackPower,
                    defVal          = summary.lastTotalDefense,
                    damage          = summary.totalDamage,
                    attackerIsUpper = attackerIsUpper,
                })
            end)
        end
    end
end

function GameController:_onTurnStarted(turnPlayerIndex, turnNumber)
    if turnNumber > 1 then
        HUDSync.syncHandVisuals(self, 1)
        HUDSync.syncHandVisuals(self, 2)
        HUDSync.syncRemovedCards(self, 1)
        HUDSync.syncRemovedCards(self, 2)
        self._actionDelay = math.max(self._actionDelay, 1.5)
    end

    CombatLog.phase(string.format("第 %d 回合 [%s]",
        turnNumber, self.fsm.players[turnPlayerIndex].heroName))
end

-- ============================================================================
-- 操作者判定
-- ============================================================================

function GameController:_getActorIndex(phase)
    if phase == TurnPhase.CHAIN_DEFEND then
        return self.fsm:opponentIndex()
    else
        return self.fsm.turnPlayerIndex
    end
end

-- ============================================================================
-- 辅助方法
-- ============================================================================

function GameController:_getHandFan(playerIndex)
    return playerIndex == 1 and self._handFan or self._oppHandFan
end

function GameController:_getDeckStack(playerIndex)
    return playerIndex == 1 and self._myDeckStack or self._oppDeckStack
end

--- 获取屏幕中心的 NanoVG 逻辑坐标
function GameController:_screenCenter()
    local s = self._nvgScale or 1
    local cx = graphics:GetWidth() / s * 0.5
    local cy = graphics:GetHeight() / s * 0.5
    return cx, cy
end

function GameController:_phaseToBarIndex(phase, subPhase)
    if phase == TurnPhase.START_PHASE  then return 1
    elseif phase == TurnPhase.DRAW_PHASE   then return 2
    elseif phase == TurnPhase.ACTION_PHASE then return 3
    elseif phase == TurnPhase.COMBAT_CHAIN then return 4
    elseif phase == TurnPhase.END_PHASE    then return 5
    else return 3
    end
end

return GameController

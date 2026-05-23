-- ============================================================================
-- Audio/SFX.lua - 音效管理器（墨甲武林）
-- 统一加载、播放、音量控制
-- ============================================================================

local SFX = {}

-- ============================================================================
-- 配置
-- ============================================================================

local SOUNDS = {
    attack      = { path = "audio/sfx/card_attack.ogg",  gain = 0.7 },
    defend      = { path = "audio/sfx/card_defend.ogg",   gain = 0.7 },
    draw        = { path = "audio/sfx/card_draw.ogg",     gain = 0.5 },
    hit         = { path = "audio/sfx/damage_hit.ogg",    gain = 0.8 },
    phase       = { path = "audio/sfx/phase_change.ogg",  gain = 0.4 },
    click       = { path = "audio/sfx/button_click.ogg",  gain = 0.5 },
    victory     = { path = "audio/sfx/victory.ogg",       gain = 0.8 },
    defeat      = { path = "audio/sfx/defeat.ogg",        gain = 0.7 },
    combo       = { path = "audio/sfx/chain_combo.ogg",   gain = 0.6 },
    pitch       = { path = "audio/sfx/card_pitch.ogg",    gain = 0.5 },
}

-- ============================================================================
-- 状态
-- ============================================================================

local loaded = {}       -- name → Sound resource
local masterGain = 1.0  -- 主音量乘数
local initialized = false

-- ============================================================================
-- 初始化
-- ============================================================================

--- 预加载所有音效（在 Start() 中调用一次）
function SFX.init()
    if initialized then return end

    for name, cfg in pairs(SOUNDS) do
        local sound = cache:GetResource("Sound", cfg.path)
        if sound then
            loaded[name] = sound
        else
            print("[SFX] WARNING: Failed to load " .. cfg.path)
        end
    end

    initialized = true
end

-- ============================================================================
-- 播放 API
-- ============================================================================

--- 播放一个音效
---@param name string 音效名称（attack/defend/draw/hit/phase/click/victory/defeat/combo/pitch）
---@param gainOverride number|nil 可选音量覆盖 (0-1)
function SFX.play(name, gainOverride)
    if not initialized then SFX.init() end

    local sound = loaded[name]
    if not sound then return end

    local cfg = SOUNDS[name]
    local gain = (gainOverride or cfg.gain) * masterGain

    -- scene_ 未就绪时跳过（Start() 初始化阶段可能尚未创建场景）
    if not scene_ then return end

    -- 创建临时 SoundSource 播放（自动移除）
    local node = scene_:CreateChild("SFX_" .. name)
    local source = node:CreateComponent("SoundSource")
    source.soundType = "Effect"
    source.gain = gain
    source.autoRemoveMode = REMOVE_NODE  -- 播放完毕自动删除节点
    source:Play(sound)
end

--- 快捷方法
function SFX.attack()   SFX.play("attack")  end
function SFX.defend()   SFX.play("defend")   end
function SFX.draw()     SFX.play("draw")     end
function SFX.hit()      SFX.play("hit")      end
function SFX.phase()    SFX.play("phase")    end
function SFX.click()    SFX.play("click")    end
function SFX.victory()  SFX.play("victory")  end
function SFX.defeat()   SFX.play("defeat")   end
function SFX.combo()    SFX.play("combo")    end
function SFX.pitch()    SFX.play("pitch")    end

-- ============================================================================
-- 音量控制
-- ============================================================================

--- 设置主音量
function SFX.setMasterGain(gain)
    masterGain = math.max(0, math.min(1, gain))
end

function SFX.getMasterGain()
    return masterGain
end

return SFX

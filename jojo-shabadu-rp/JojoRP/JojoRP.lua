-- ==========================================
-- JOJO RP SETTINGS (Edit these two anytime!)
-- ==========================================
local CHANCE = 30        -- Percentage chance (1-100) per kill/action
local COOLDOWN = 25      -- Minimum seconds between any two Jojo RP lines
-- ==========================================

local savedAmmo = 0
local lowAmmoWarned = false
local lastTargetType = UnitExists("target") and UnitCreatureType("target") or nil
local lastTargetName = UnitExists("target") and UnitName("target") or nil
local pendingSlug = nil
local pendingMobName = nil
local lastFiredTime = 0
local sceneCooldowns = {}
local lastLineText = {}
local rollCounter = 0

local function TrueRandom(maxVal)
    rollCounter = rollCounter + 17
    local raw = math.floor(GetTime() * 1000) + rollCounter + math.random(1, 997)
    return (raw % maxVal) + 1
end

local function CanSkinTarget()
    if C_Spell and C_Spell.IsSpellUsable then
        return C_Spell.IsSpellUsable(8613) or C_Spell.IsSpellUsable("Skinning")
    elseif IsUsableSpell then
        return IsUsableSpell(8613) or IsUsableSpell("Skinning")
    end
    return false
end

local function IsDemonicName(rawName)
    local name = string.lower(rawName or "")
    return string.find(name, "familiar")
        or string.find(name, "imp")
        or string.find(name, "satyr")
        or string.find(name, "felguard")
        or string.find(name, "felhound")
        or string.find(name, "felstalker")
        or string.find(name, "voidwalker")
        or string.find(name, "succubus")
        or string.find(name, "doomguard")
        or string.find(name, "infernal")
        or string.find(name, "shadowbeast")
        or string.find(name, "hellhound")
end

-- Reads directly from SpeakEasyDB, replaces {targetName} safely, and avoids repeating the last line
local function PlaySceneFromSpeakEasyDB(slug, cachedName)
    if not (SpeakEasyDB and SpeakEasyDB.scenes) then return end

    local targetScene = nil
    for _, scene in pairs(SpeakEasyDB.scenes) do
        if scene.id == slug or string.lower(scene.name or "") == slug then
            targetScene = scene
            break
        end
    end

    if not targetScene or targetScene.enabled == false or not targetScene.lines then return end

    local sceneCD = targetScene.cooldown or 0
    if sceneCooldowns[slug] and (GetTime() - sceneCooldowns[slug]) < sceneCD then
        return
    end

    local validLines = {}
    for _, line in pairs(targetScene.lines) do
        if type(line) == "table" and line.enabled ~= false and line.text and line.text ~= "" then
            table.insert(validLines, line)
        end
    end

    if #validLines == 0 then return end

    -- Pick a random line, and if there is more than 1 line, guarantee it is not the exact one used last time
    local idx = TrueRandom(#validLines)
    local chosen = validLines[idx]
    if #validLines > 1 and chosen.text == lastLineText[slug] then
        idx = (idx % #validLines) + 1
        chosen = validLines[idx]
    end
    lastLineText[slug] = chosen.text

    local finalText = chosen.text

    -- Resolve {targetName} using live target first, then cached mob name, then fallback
    local mobName = UnitName("target") or cachedName or "dat beast"
    finalText = string.gsub(finalText, "{targetName}", mobName)
    finalText = string.gsub(finalText, "{playerName}", UnitName("player") or "Jojo")

    local channel = string.upper(targetScene.channel or "SAY")
    if channel ~= "SAY" and channel ~= "EMOTE" and channel ~= "YELL" and channel ~= "PARTY" then
        channel = "SAY"
    end

    sceneCooldowns[slug] = GetTime()
    lastFiredTime = GetTime()

    SendChatMessage(finalText, channel)

    if chosen.emote and chosen.emote ~= "" and string.upper(chosen.emote) ~= "NONE" and DoEmote then
        DoEmote(string.upper(chosen.emote))
    end
end

local function QueueScene(baseTag, mobName)
    if (GetTime() - lastFiredTime) < COOLDOWN then return end
    if TrueRandom(100) > CHANCE then return end

    local suffix = (TrueRandom(2) == 1) and "say" or "emote"
    pendingSlug = string.lower(baseTag) .. suffix
    pendingMobName = mobName or lastTargetName
end

local function FlushPending()
    if pendingSlug then
        local slug = pendingSlug
        local mobName = pendingMobName
        pendingSlug = nil
        pendingMobName = nil
        PlaySceneFromSpeakEasyDB(slug, mobName)
    end
end

-- Fires queued scenes on your next keypress or loot-close click
local keyFrame = CreateFrame("Frame", "JojoRPKeyFrame", UIParent)
keyFrame:EnableKeyboard(true)
keyFrame:SetPropagateKeyboardInput(true)
keyFrame:SetScript("OnKeyDown", FlushPending)

if LootFrameCloseButton then
    LootFrameCloseButton:HookScript("OnClick", FlushPending)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("LOOT_CLOSED")
f:RegisterEvent("UNIT_SPELLCAST_START")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("MERCHANT_CLOSED")
f:RegisterEvent("BAG_UPDATE")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_TARGET_CHANGED" then
        if UnitExists("target") and not UnitIsFriend("player", "target") then
            lastTargetType = UnitCreatureType("target")
            lastTargetName = UnitName("target")
        end

    -- 50/50 coin flip between SkinSay and SkinEmote when you start skinning
    elseif event == "UNIT_SPELLCAST_START" then
        local unitTarget, _, spellID = ...
        if unitTarget == "player" and spellID then
            local spellInfo = C_Spell and C_Spell.GetSpellInfo(spellID)
            local spellName = spellInfo and spellInfo.name or (GetSpellInfo and GetSpellInfo(spellID))
            if spellID == 8613 or spellName == "Skinning" then
                QueueScene("Skin", lastTargetName)
                lastTargetType = nil
            end
        end

    -- Triggers NoSkin only if the beast cannot be skinned
    elseif event == "LOOT_CLOSED" then
        local cType = (UnitExists("target") and UnitCreatureType("target")) or lastTargetType
        local mobName = (UnitExists("target") and UnitName("target")) or lastTargetName
        if cType == "Beast" then
            if not CanSkinTarget() then
                QueueScene("NoSkin", mobName)
            end
            lastTargetType = nil
        end

    -- All other creature types after combat ends
    elseif event == "PLAYER_REGEN_ENABLED" then
        local cType = (UnitExists("target") and UnitCreatureType("target")) or lastTargetType
        local rawName = (UnitExists("target") and UnitName("target")) or lastTargetName or ""
        if cType and cType ~= "Beast" then
            if cType == "Demon" or IsDemonicName(rawName) then
                QueueScene("Demon", rawName)
            elseif cType == "Humanoid" then
                QueueScene("Hum", rawName)
            elseif cType == "Undead" then
                QueueScene("Undead", rawName)
            elseif cType == "Mechanical" then
                QueueScene("Mech", rawName)
            elseif cType == "Elemental" then
                local name = string.lower(rawName)
                if string.find(name, "earth") or string.find(name, "rock") or string.find(name, "stone") or string.find(name, "crag") or string.find(name, "rumbler") or string.find(name, "boulder") then QueueScene("Earth", rawName)
                elseif string.find(name, "water") or string.find(name, "tide") or string.find(name, "surf") or string.find(name, "stream") or string.find(name, "wave") or string.find(name, "sea") then QueueScene("Water", rawName)
                elseif string.find(name, "fire") or string.find(name, "flame") or string.find(name, "ember") or string.find(name, "scorch") or string.find(name, "blaze") or string.find(name, "magma") or string.find(name, "lava") then QueueScene("Fire", rawName)
                elseif string.find(name, "air") or string.find(name, "wind") or string.find(name, "dust") or string.find(name, "gale") or string.find(name, "cyclone") or string.find(name, "tempest") or string.find(name, "whirlwind") then QueueScene("Air", rawName)
                else QueueScene("Elem", rawName) end
            end
            lastTargetType = nil
        end

    elseif event == "MERCHANT_SHOW" then
        savedAmmo = GetInventoryItemCount("player", 0) or 0
    elseif event == "MERCHANT_CLOSED" then
        local currentAmmo = GetInventoryItemCount("player", 0) or 0
        if currentAmmo > savedAmmo then
            savedAmmo = currentAmmo
            if currentAmmo >= 150 then lowAmmoWarned = false end
            QueueScene("AmmoBuy")
        end
    elseif event == "BAG_UPDATE" then
        local currentAmmo = GetInventoryItemCount("player", 0) or 0
        if currentAmmo > 0 and currentAmmo < 100 and not lowAmmoWarned then
            lowAmmoWarned = true
            QueueScene("AmmoLow")
        end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        local slotID, hasItem = ...
        if slotID == 18 and hasItem then
            QueueScene("NewBow")
        end
    end
end)

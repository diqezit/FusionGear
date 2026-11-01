-- Optional compact item tooltip formatter for WoW 3.3.5a
-- Blizzard remains owner of tooltip layout and refresh timing
-- Format only inside native OnTooltipSetItem event
-- Never queue delayed writes or call tooltip Show after editing
local _, F = ...


-- Short stat names are also used in Stats.lua
F.StatNames = {
    STA = "Stamina",
    INT = "Intellect",
    SPI = "Spirit",
    AGI = "Agility",
    STR = "Strength",
    DODGE = "Dodge",
    PARRY = "Parry",
    CRIT = "Crit",
    HASTE = "Haste",
    TOHIT = "Hit",
    EXPERTISE = "Expertise",
}

-- Colors affect only plain native text rows we explicitly support
-- Other addon lines and item quality colors stay untouched
local GOLD = { 1, 0.824, 0 }
local GREEN = { 0, 1, 0 }
local SOCKET = { 0, 1, 0.75 }
local RED = { 1, 0.20, 0.20 }

-- Escape Lua pattern tokens in Blizzard format strings
-- Without escaping percent and brackets can match wrong rows
local function EscapePattern(text)
    return (text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

-- Convert Blizzard percent placeholders into Lua captures
-- Build anchored pattern so only complete stat line matches
local function FormatPattern(format)
    if not format or format == "" then
        return nil
    end

    local pattern = EscapePattern(format)
    pattern = pattern:gsub("%%%%d", "([+-]?%%d+)")
    pattern = pattern:gsub("%%%%s", "(.-)")
    pattern = pattern:gsub("%%%%c", "([+-])")
    return "^" .. pattern .. "$"
end

-- Check prefix without interpreting it as Lua pattern
local function StartsWith(text, prefix)
    return text and prefix and text:sub(1, #prefix) == prefix
end

-- Green native text often marks equipment bonus or enchant
local function IsGreen(red, green, blue)
    return red < 0.20 and green > 0.90 and blue < 0.20
end

-- Red native text represents inactive or negative bonus
local function IsRed(red, green, blue)
    return red > 0.85 and green < 0.25 and blue < 0.25
end

-- List known Blizzard stat format global names
-- BuildPatterns skips globals missing from this client build
local modNames = {
    "ITEM_MOD_ARMOR_PENETRATION_RATING",
    "ITEM_MOD_ATTACK_POWER",
    "ITEM_MOD_BLOCK_RATING",
    "ITEM_MOD_BLOCK_VALUE",
    "ITEM_MOD_CRIT_MELEE_RATING",
    "ITEM_MOD_CRIT_RANGED_RATING",
    "ITEM_MOD_CRIT_RATING",
    "ITEM_MOD_CRIT_SPELL_RATING",
    "ITEM_MOD_CRIT_TAKEN_MELEE_RATING",
    "ITEM_MOD_CRIT_TAKEN_RANGED_RATING",
    "ITEM_MOD_CRIT_TAKEN_RATING",
    "ITEM_MOD_CRIT_TAKEN_SPELL_RATING",
    "ITEM_MOD_DEFENSE_SKILL_RATING",
    "ITEM_MOD_DODGE_RATING",
    "ITEM_MOD_EXPERTISE_RATING",
    "ITEM_MOD_FERAL_ATTACK_POWER",
    "ITEM_MOD_HASTE_MELEE_RATING",
    "ITEM_MOD_HASTE_RANGED_RATING",
    "ITEM_MOD_HASTE_RATING",
    "ITEM_MOD_HASTE_SPELL_RATING",
    "ITEM_MOD_HEALTH_REGEN",
    "ITEM_MOD_HEALTH_REGENERATION",
    "ITEM_MOD_HIT_MELEE_RATING",
    "ITEM_MOD_HIT_RANGED_RATING",
    "ITEM_MOD_HIT_RATING",
    "ITEM_MOD_HIT_SPELL_RATING",
    "ITEM_MOD_HIT_TAKEN_MELEE_RATING",
    "ITEM_MOD_HIT_TAKEN_RANGED_RATING",
    "ITEM_MOD_HIT_TAKEN_RATING",
    "ITEM_MOD_HIT_TAKEN_SPELL_RATING",
    "ITEM_MOD_MANA_REGENERATION",
    "ITEM_MOD_PARRY_RATING",
    "ITEM_MOD_RANGED_ATTACK_POWER",
    "ITEM_MOD_RESILIENCE_RATING",
    "ITEM_MOD_SPELL_DAMAGE_DONE",
    "ITEM_MOD_SPELL_HEALING_DONE",
    "ITEM_MOD_SPELL_PENETRATION",
    "ITEM_MOD_SPELL_POWER",
    "FERAL_DRUID_ITEM_AP",
}

-- Known equip effect texts that can be shortened safely
-- Only exact full line matches are eligible
local equipDescriptions = {
    ITEM_MOD_ARMOR_PENETRATION_RATING = { "Increases armor penetration rating by $s1." },
    ITEM_MOD_ATTACK_POWER = {
        "Increases your attack power by $s1.",
        "Increases melee and ranged attack power by $s1.",
    },
    ITEM_MOD_BLOCK_RATING = { "Increases your block rating by $s1." },
    ITEM_MOD_CRIT_RANGED_RATING = { "Increases your ranged critical strike rating by $s1." },
    ITEM_MOD_CRIT_RATING = {
        "Increases your critical strike rating by $s1.",
        "Increases your spell critical strike rating by $s1.",
        "Improves your critical strike rating by $s1.",
        "Increases your crit rating by $s1.",
        "Crit Rating increased by $s1.",
    },
    ITEM_MOD_CRIT_SPELL_RATING = { "Increases spell critical strike rating by $s1." },
    ITEM_MOD_EXPERTISE_RATING = { "Increases expertise rating by $s1." },
    ITEM_MOD_HASTE_RATING = { "Increases haste rating by $s1.", "Increases your haste rating by $s1." },
    ITEM_MOD_DODGE_RATING = { "Increases your dodge rating by $s1." },
    ITEM_MOD_PARRY_RATING = { "Increases your parry rating by $s1." },
    ITEM_MOD_DEFENSE_SKILL_RATING = { "Increases defense rating by $s1." },
    ITEM_MOD_HEALTH_REGEN = { "Restores $s1 health and mana every 5 sec." },
    ITEM_MOD_HIT_RANGED_RATING = { "Increases your ranged hit rating by $s1." },
    ITEM_MOD_HIT_RATING = { "Increases your hit rating by $s1." },
    ITEM_MOD_HIT_SPELL_RATING = { "Increases your spell hit rating by $s1." },
    ITEM_MOD_MANA_REGENERATION = {
        "Gain $s1 mana every 5 seconds.",
        "Restores $s1 health and mana every 5 sec.",
        "Restores $s1 mana every 5 seconds.",
    },
    ITEM_MOD_RESILIENCE_RATING = {
        "+$s1 Resilience Rating.",
        "+$s1 resilience rating.",
        "Increases resilience by $s1.",
    },
    ITEM_MOD_SPELL_DAMAGE_DONE = { "Increases damage from spells and effects by $s1." },
    ITEM_MOD_SPELL_HEALING_DONE = { "Increases healing done by spells and effects by up to $s1." },
    ITEM_MOD_SPELL_PENETRATION = { "Increases your spell penetration by $s1." },
    ITEM_MOD_SPELL_POWER = { "Increases your spell power by $s1." },
}

-- Short labels used in formatted tooltip output
-- Fallback global SHORT name is checked during setup
local shortNames = {
    ITEM_MOD_ARMOR_PENETRATION_RATING = "Armor Pen.",
    ITEM_MOD_ATTACK_POWER = "Attack Power",
    ITEM_MOD_BLOCK_RATING = "Block",
    ITEM_MOD_BLOCK_VALUE = "Block Value",
    ITEM_MOD_CRIT_MELEE_RATING = "Crit",
    ITEM_MOD_CRIT_RANGED_RATING = "Crit",
    ITEM_MOD_CRIT_RATING = "Crit",
    ITEM_MOD_CRIT_SPELL_RATING = "Crit",
    ITEM_MOD_DEFENSE_SKILL_RATING = "Defense",
    ITEM_MOD_DODGE_RATING = "Dodge",
    ITEM_MOD_EXPERTISE_RATING = "Expertise",
    ITEM_MOD_HASTE_MELEE_RATING = "Haste",
    ITEM_MOD_HASTE_RANGED_RATING = "Haste",
    ITEM_MOD_HASTE_RATING = "Haste",
    ITEM_MOD_HASTE_SPELL_RATING = "Haste",
    ITEM_MOD_HIT_MELEE_RATING = "Hit",
    ITEM_MOD_HIT_RANGED_RATING = "Hit",
    ITEM_MOD_HIT_RATING = "Hit",
    ITEM_MOD_HIT_SPELL_RATING = "Hit",
    ITEM_MOD_HEALTH_REGEN = "Health / 5 sec",
    ITEM_MOD_HEALTH_REGENERATION = "Health / 5 sec",
    ITEM_MOD_FERAL_ATTACK_POWER = "Feral Attack Power",
    ITEM_MOD_SPELL_HEALING_DONE = "Healing",
    ITEM_MOD_SPELL_DAMAGE_DONE = "Spell Damage",
    ITEM_MOD_RANGED_ATTACK_POWER = "Ranged Attack Power",
    ITEM_MOD_MANA_REGENERATION = "Mana / 5 sec",
    ITEM_MOD_PARRY_RATING = "Parry",
    ITEM_MOD_RESILIENCE_RATING = "Resilience",
    ITEM_MOD_SPELL_PENETRATION = "Spell Pen.",
    ITEM_MOD_SPELL_POWER = "Spell Power",
}

-- Full race requirement lines mapped to compact labels
local factionNames = {
    ["Races: Human, Dwarf, Night Elf, Gnome, Draenei"] = "Alliance Only",
    ["Races: Orc, Undead, Tauren, Troll, Blood Elf"] = "Horde Only",
}

-- Recipe tooltips use special layout and are not rewritten
local recipePrefixes = {
    "Pattern:", "Plans:", "Schematic:", "Recipe:",
    "Formula:", "Design:",
}

-- Compile patterns once during initialization
-- Avoid reading global templates for every tooltip hover
local statPatterns = {}
local equipPatterns = {}
local itemLevelPattern

-- Match native item level and known stat or equip lines
-- Use current client text globals where possible
-- Preserve source order while collecting patterns
local function BuildPatterns()
    itemLevelPattern = FormatPattern(ITEM_LEVEL)

    for _, key in ipairs(modNames) do
        local format = _G[key]
        local short = shortNames[key] or _G[key .. "_SHORT"]

        if format and short then
            local pattern = FormatPattern(format)
            if pattern then
                statPatterns[#statPatterns + 1] = { pattern, short }
            end
        end
    end

    for key, descriptions in pairs(equipDescriptions) do
        local short = shortNames[key] or _G[key .. "_SHORT"]

        if short then
            for _, description in ipairs(descriptions) do
                local pattern = EscapePattern(description:gsub("%$s%d+", "FUSION_NUMBER"))
                pattern = pattern:gsub("FUSION_NUMBER", "(%%d+)")
                equipPatterns[#equipPatterns + 1] = { "^" .. pattern .. "$", short }
            end
        end
    end
end

-- Try only exact known stat lines and known equip effect formats
-- Return original text when no supported pattern matches
-- Keep sign and numerical amount from original line
local function ShortenStat(text)
    for _, entry in ipairs(statPatterns) do
        local first, second = text:match(entry[1])

        if first then
            local sign = "+"
            local amount = first

            if (first == "+" or first == "-") and second then
                sign = first
                amount = second
            elseif first:sub(1, 1) == "-" then
                sign = ""
            end

            return sign .. amount .. " " .. entry[2], true
        end
    end

    local equipPrefix = ITEM_SPELL_TRIGGER_ONEQUIP
    if StartsWith(text, equipPrefix) then
        local description = text:sub(#equipPrefix + 1):gsub("^%s+", "")

        for _, entry in ipairs(equipPatterns) do
            local amount = description:match(entry[1])
            if amount then
                return "+" .. amount .. " " .. entry[2], true
            end
        end
    end

    return text, false
end

-- Replace first literal %s marker without parsing format
-- Never use string format with user SavedVariables template
-- This prevents format errors from literal percent characters
local function ConfiguredText(template, text)
    local startPos, endPos = template:find("%s", 1, true)
    if startPos then
        return template:sub(1, startPos - 1) .. text .. template:sub(endPos + 1)
    end

    return template .. " " .. text
end

-- Calculate desired text and color without changing tooltip
-- Keep Item Level, faction, socket and stat rules separate
-- Already formatted enchant lines must remain unchanged
local function FormatLine(text, red, green, blue, settings)
    local color

    if settings.itemLevel and itemLevelPattern and text:match(itemLevelPattern) then
        color = GOLD
    elseif settings.faction and factionNames[text] then
        text = factionNames[text]
    elseif StartsWith(text, "Enchanted:") then
        return text, nil
    elseif StartsWith(text, "Socket Bonus:") then
        local bonus = text:sub(#"Socket Bonus:" + 1):gsub("^%s+", "")
        text = ConfiguredText(settings.socketText, bonus)

        if IsGreen(red, green, blue) then
            color = settings.socketColor
        end
    else
        local short, changed = ShortenStat(text)
        local isEnchanted = text:match("^[+-]%d") and
            (IsGreen(red, green, blue) or IsRed(red, green, blue))

        if isEnchanted then
            text = ConfiguredText(settings.enchantText, changed and short or text)
            if IsGreen(red, green, blue) then
                color = settings.enchantColor
            end
        elseif changed then
            text = short
            color = StartsWith(short, "-") and RED or settings.statColor
        end
    end

    return text, color
end

-- Detect special profession recipe tooltip by title prefix
local function IsRecipe(title)
    for _, prefix in ipairs(recipePrefixes) do
        if StartsWith(title, prefix) then
            return true
        end
    end

    return false
end

-- Find FontStrings used as anchors for textures or money
-- Rewriting their text may disturb Blizzard row layout
-- Protected anchors are never formatted
local function ReadProtectedRows(tip, name)
    local protected = {}

    for index = 1, 10 do
        local texture = _G[name .. "Texture" .. index]
        if texture and texture:IsShown() then
            local _, relative = texture:GetPoint()
            if relative then
                protected[relative] = true
            end
        end
    end

    if tip.hasMoney then
        for index = 1, (tip.numMoneyFrames or 0) do
            local money = _G[name .. "MoneyFrame" .. index]
            if money and money:IsShown() then
                local _, relative = money:GetPoint()
                if relative then
                    protected[relative] = true
                end
            end
        end
    end

    return protected
end

-- Confirm tooltip currently contains item link
-- GetItem can fail while another addon updates tooltip
local function GetItemLink(tip)
    if not tip.GetItem then
        return nil
    end

    local ok, _, link = pcall(tip.GetItem, tip)
    if ok and type(link) == "string" and link ~= "" then
        return link
    end

    return nil
end

-- Limit changes to plain left column text only
-- Ignore embedded textures and color escape sequences
-- Ignore rows with right column text and protected anchors
local function CanFormatRow(font, right, text, protectedRows)
    if type(text) ~= "string" or text == "" then
        return false
    end

    if text:find("|T", 1, true) or text:find("|A", 1, true) or
        text:find("|c", 1, true) then
        return false
    end

    if right and right.GetText then
        local rightText = right:GetText()
        if type(rightText) == "string" and rightText ~= "" then
            return false
        end
    end

    if protectedRows[font] then
        return false
    end

    return true
end

-- Apply formatting while Blizzard prepares item tooltip
-- Never clear rows, reorder lines or force tooltip redraw
-- Use FontString text only after row safety checks
local function ApplyNativeLines(tip, settings)
    if not GetItemLink(tip) or not tip.GetName or not tip.NumLines then
        return false
    end

    local name = tip:GetName()
    local count = tip:NumLines()
    if not name or type(count) ~= "number" or count < 1 then
        return false
    end

    local first = _G[name .. "TextLeft1"]
    if not first or not first.GetText or IsRecipe(first:GetText()) then
        return false
    end

    -- Collect texture and money anchors once per formatting pass
    local protectedRows = ReadProtectedRows(tip, name)
    for index = 2, count do
        local font = _G[name .. "TextLeft" .. index]
        local right = _G[name .. "TextRight" .. index]

        if font and font.GetText and font.GetTextColor then
            local original = font:GetText()
            if CanFormatRow(font, right, original, protectedRows) and
                not (F.tooltipLastText and F.tooltipLastText[font] == original) then
                local red, green, blue = font:GetTextColor()
                red = type(red) == "number" and red or 1
                green = type(green) == "number" and green or 1
                blue = type(blue) == "number" and blue or 1

                local text, color = FormatLine(
                    original, red, green, blue, settings
                )

                -- Only write changed text to avoid unnecessary layout changes
                -- Remember result to prevent duplicate enchant prefixes
                if text ~= original then
                    font:SetText(text)
                    F.tooltipLastText[font] = text
                end

                -- Write RGB only when actual value differs
                if color and font.SetTextColor and
                    (color[1] ~= red or color[2] ~= green or color[3] ~= blue) then
                    font:SetTextColor(color[1], color[2], color[3])
                end
            end
        end
    end

    return true
end

-- Entry point used by native tooltip event hook
-- Check saved enable flag and block accidental recursion
-- Keep temporary guard valid even if formatter throws error
function F:FormatItemTooltip(tip)
    local settings = FusionGearDB and FusionGearDB.tooltips
    if not settings or not settings.enabled or not tip or tip.fgFormatting then
        return false
    end

    tip.fgFormatting = true
    local ok, result = pcall(ApplyNativeLines, tip, settings)
    tip.fgFormatting = false

    return ok and result == true
end

-- Add native item event hook once per tooltip frame
-- Do not replace Blizzard SetItemRef, SetHyperlink or Show
-- Lazy frames can be hooked after their parent addon loads
local function HookTooltip(tip)
    if not tip or not tip.GetItem or not tip.HookScript or
        F.tooltipHooks[tip] then
        return
    end

    local name = tip:GetName()
    if not name or name:find("FusionGear", 1, true) then
        return
    end

    F.tooltipHooks[tip] = true
    tip:HookScript("OnTooltipSetItem", function(frame)
        F:FormatItemTooltip(frame)
    end)
end

-- Hook existing Blizzard and supported external tooltip frames
-- Missing optional frames are ignored by HookTooltip
function F:HookTooltips()
    if not self.tooltipHooks then
        return
    end

    HookTooltip(GameTooltip)
    HookTooltip(ItemRefTooltip)
    HookTooltip(ShoppingTooltip1)
    HookTooltip(ShoppingTooltip2)
    HookTooltip(ShoppingTooltip3)
    HookTooltip(AtlasLootTooltip)
    HookTooltip(AtlasLootTooltipTEMP)
end

-- Reject invalid SavedVariables RGB values
-- Every channel must be finite number between zero and one
local function ValidColor(color, fallback)
    if type(color) ~= "table" then
        return fallback
    end

    for index = 1, 3 do
        local value = color[index]
        if type(value) ~= "number" or value ~= value or
            value < 0 or value > 1 then
            return fallback
        end
    end

    return color
end

-- Reject malformed custom text templates
-- Control characters and embedded textures could break tooltip
local function ValidText(value, fallback)
    if type(value) ~= "string" or value == "" or #value > 96 or
        value:find("[%c]") or value:find("|T", 1, true) or
        value:find("|A", 1, true) or value:find("|c", 1, true) then
        return fallback
    end

    return value
end

-- Initialize settings and hooks once after player login
-- Use defaults when old saved data is invalid
-- Never overwrite Blizzard localization globals
function F:InitTooltips()
    if self.tooltipHooks then
        return
    end

    if type(FusionGearDB.tooltips) ~= "table" then
        FusionGearDB.tooltips = {}
    end
    local settings = FusionGearDB.tooltips

    -- Blizzard and TipTac can both rebuild item tooltip FontStrings
    -- Older releases enabled our formatter automatically for every user
    -- Turn it off once on upgrade to avoid the old flicker on existing saves
    -- After migration /fg tooltip on is a persistent user choice
    if settings.safeModeInitialized ~= true then
        settings.enabled = false
        settings.safeModeInitialized = true
    elseif type(settings.enabled) ~= "boolean" then
        settings.enabled = false
    end
    for _, key in ipairs({ "itemLevel", "faction" }) do
        if type(settings[key]) ~= "boolean" then
            settings[key] = true
        end
    end

    settings.statColor = ValidColor(settings.statColor, GREEN)
    settings.enchantColor = ValidColor(settings.enchantColor, GREEN)
    settings.socketColor = ValidColor(settings.socketColor, SOCKET)
    settings.enchantText = ValidText(settings.enchantText, "Enchanted: %s")
    settings.socketText = ValidText(settings.socketText, "Socket Bonus: %s")

    self.tooltipHooks = {}
    -- Track text last written by FusionGear for each FontString
    -- Guard avoids treating already shortened text as new enchant
    self.tooltipLastText = setmetatable({}, { __mode = "k" })
    BuildPatterns()

    self:HookTooltips()
end

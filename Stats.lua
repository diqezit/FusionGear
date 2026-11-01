-- Player stats panel using Blizzard PaperDoll calculations
-- Never invent custom combat rating math
-- Copy native values and color changes including aura penalties
local _, F = ...

-- Short labels are shared with tooltip formatting module
local names = F.StatNames

-- Two columns of native Wrath stat categories
-- Each row stores display label and Blizzard helper suffix
-- Optional third value is Stat index or combat rating constant
-- Row order controls appearance in player side panel
local groups = {
    {
        {
            title = "ATTRIBUTES",
            rows = {
                { names.STR, "Stat", 1 },
                { names.AGI, "Stat", 2 },
                { names.STA, "Stat", 3 },
                { names.INT, "Stat", 4 },
                { names.SPI, "Stat", 5 },
            },
        },
        {
            title = "MELEE",
            rows = {
                { "Damage", "Damage" },
                { "Speed", "AttackSpeed" },
                { "Attack Power", "AttackPower" },
                { names.TOHIT, "Rating", "CR_HIT_MELEE" },
                { names.CRIT, "MeleeCritChance" },
                { names.EXPERTISE, "Expertise" },
            },
        },
        {
            title = "RANGED",
            rows = {
                { "Damage", "RangedDamage" },
                { "Speed", "RangedAttackSpeed" },
                { "Attack Power", "RangedAttackPower" },
                { names.TOHIT, "Rating", "CR_HIT_RANGED" },
                { names.CRIT, "RangedCritChance" },
                { names.HASTE, "Rating", "CR_HASTE_RANGED" },
            },
        },
    },
    {
        {
            title = "SPELLS",
            rows = {
                { "Spell Power", "SpellBonusDamage" },
                { "Healing", "SpellBonusHealing" },
                { names.TOHIT, "Rating", "CR_HIT_SPELL" },
                { names.CRIT, "SpellCritChance" },
                { names.HASTE, "SpellHaste" },
                { "Mana / 5 sec", "ManaRegen" },
            },
        },
        {
            title = "DEFENSE",
            rows = {
                { "Armor", "Armor" },
                { "Defense", "Defense" },
                { names.DODGE, "Dodge" },
                { names.PARRY, "Parry" },
                { "Block", "Block" },
                { "Resilience", "Resilience" },
            },
        },
        {
            title = "SECONDARY",
            rows = {
                { "Armor Pen.", "Rating", "CR_ARMOR_PENETRATION" },
                { "Spell Pen.", "SpellPenetration" },
                { "Melee Haste", "Rating", "CR_HASTE_MELEE" },
                { "Defense Rating", "Rating", "CR_DEFENSE_SKILL" },
            },
        },
    },
}

-- Blizzard helpers expect named Label and StatText children
-- Build invisible frame with exact names they can access
-- Proxy is calculation target and never appears on screen
local function CreateStatProxy(index)
    local name = "FusionGearStatProxy" .. index
    local frame = CreateFrame("Frame", name, F.hiddenStatParent)
    frame:SetSize(1, 1)
    frame:CreateFontString(name .. "Label", "OVERLAY", "GameFontNormalSmall")
    local text = frame:CreateFontString(name .. "StatText", "OVERLAY", "GameFontHighlightSmall")
    frame.value = text
    return frame
end

-- Call original PaperDoll function to compute stat value
-- Clear old tooltip and RGB values before every calculation
-- Native functions may write color into text or FontString
local function UpdateProxy(row)
    local func = row.func
    local id = row.arg
    row.proxy.tooltip = nil
    row.proxy.tooltip2 = nil

    row.proxy.value:SetTextColor(1, 1, 1)
    -- Blizzard helpers differ in number of required arguments
    -- Pass stat or rating ID only to functions that need one
    if type(func) == "function" then
        if row.method == "Stat" or row.method == "Rating" then
            if id then
                func(row.proxy, id)
            else
                row.proxy.value:SetText("0")
            end
        else
            func(row.proxy)
        end
    else
        row.proxy.value:SetText("")
    end
    return row.proxy.value:GetText() or ""
end

-- Use help text produced by native PaperDoll helper
-- No separate stat descriptions are maintained here
local function ShowStatTooltip(self)
    local stat = self.statRow
    if not stat or not stat.proxy.tooltip then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(stat.proxy.tooltip, 1, 1, 1, true)
    if stat.proxy.tooltip2 then
        GameTooltip:AddLine(stat.proxy.tooltip2, 1, 0.82, 0, true)
    end
    GameTooltip:Show()
end

-- Draw category caption and divider once at frame creation
local function CreateGroupHeading(frame, title, left, top)
    local heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    heading:SetPoint("TOPLEFT", frame, "TOPLEFT", left + 3, -top)
    heading:SetText(title)

    local separator = frame:CreateTexture(nil, "ARTWORK")
    separator:SetTexture("Interface\\Buttons\\WHITE8X8")
    separator:SetVertexColor(0.48, 0.48, 0.48, 0.65)
    separator:SetSize(75, 1)
    separator:SetPoint("LEFT", heading, "RIGHT", 6, -1)
end

-- Create visible label and value for one statistic
-- Attach hidden Blizzard proxy used to calculate its value
-- Resolve function and rating ID once rather than each refresh
local function CreateStatRow(frame, entry, left, top, index)
    local rowFrame = CreateFrame("Frame", nil, frame)
    rowFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", left + 4, -top + 2)
    rowFrame:SetSize(173, 16)
    rowFrame:EnableMouse(true)
    rowFrame:SetScript("OnEnter", ShowStatTooltip)
    rowFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local label = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", rowFrame, "LEFT", 2, 0)
    label:SetWidth(104)
    label:SetJustifyH("LEFT")
    label:SetText(entry[1])

    local value = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    value:SetPoint("RIGHT", rowFrame, "RIGHT", 0, 0)
    value:SetWidth(70)
    value:SetJustifyH("RIGHT")

    local arg = entry[3]
    -- Convert CR constant name to numeric ID during setup
    if type(arg) == "string" then
        arg = _G[arg]
    end

    local stat = {
        method = entry[2],
        func = _G["PaperDollFrame_Set" .. entry[2]],
        arg = arg,
        proxy = CreateStatProxy(index),
        value = value,
    }
    rowFrame.statRow = stat
    return stat
end

-- Draw subtle divider between values in same category
local function CreateRowSeparator(frame, left, top)
    local separator = frame:CreateTexture(nil, "BACKGROUND")
    separator:SetTexture("Interface\\Buttons\\WHITE8X8")
    separator:SetVertexColor(0.22, 0.22, 0.22, 0.30)
    separator:SetSize(168, 1)
    separator:SetPoint("TOPLEFT", frame, "TOPLEFT", left + 5, -top - 14)
end

-- Create heading then stack all rows underneath
-- Return vertical offset for next category
local function CreateStatGroup(frame, group, left, top)
    CreateGroupHeading(frame, group.title, left, top)
    top = top + 18

    for index, entry in ipairs(group.rows) do
        local stat = CreateStatRow(frame, entry, left, top, #frame.rows + 1)
        frame.rows[#frame.rows + 1] = stat

        if index < #group.rows then
            CreateRowSeparator(frame, left, top)
        end
        top = top + 16
    end

    return top + 7
end

-- Build two stat columns once when player panel is created
-- Only text contents get updated during play
function F:CreateStats(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 11, -69)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -11, 10)
    frame.rows = {}

    -- Hide proxy parent so calculation FontStrings never render
    self.hiddenStatParent = CreateFrame("Frame", nil, UIParent)
    self.hiddenStatParent:Hide()

    for column, columnGroups in ipairs(groups) do
        local left = (column - 1) * 187
        local top = 0

        for _, group in ipairs(columnGroups) do
            top = CreateStatGroup(frame, group, left, top)
        end
    end

    self.statsFrame = frame
end

-- Recompute visible stat rows with protected native calls
-- Copy output text and RGB without replacing Blizzard functions
-- Invisible panels do not need stat refresh work
function F:RefreshStats()
    if not self.statsFrame or not self.statsFrame:IsShown() then
        return
    end

    for _, row in ipairs(self.statsFrame.rows) do
        -- One broken native helper should not blank entire panel
        -- Inline color tags stay in text while RGB uses native result
        local ok, display = pcall(UpdateProxy, row)
        row.value:SetText(ok and display or "")

        local red, green, blue = 1, 1, 1
        if ok then
            red, green, blue = row.proxy.value:GetTextColor()
        end
        row.value:SetTextColor(red, green, blue)
    end
end

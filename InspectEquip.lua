-- InspectEquip source lookup and panel for WoW 3.3.5a
-- Items.lua stores raw item IDs and compact source codes
-- This module decodes those codes and displays known loot sources
-- All 17 slot rows are created once and reused on every update
local _, F = ...

-- Use one fallback label for missing or unknown source codes
F.UNKNOWN_SOURCE = "Unknown source"

-- Single letter prefix identifies emblem reward type
local currencies = {
    j = "Justice",
    h = "Heroism",
    v = "Valor",
    u = "Conquest",
    i = "Triumph",
    o = "Frost",
}

-- PvP source code identifies reward group or arena season
local pvpNames = {
    m = "Accessories",
    l = "Low level",
    w = "World PvP",
    g = "Wintergrasp",
    s1 = "Season 1",
    s2 = "Season 2",
    s3 = "Season 3",
    s4 = "Season 4",
    s5 = "Season 5",
    s6 = "Season 6",
    s7 = "Season 7",
    s8 = "Season 8",
}

-- Raid difficulty codes are preserved from InspectEquip data
local raidDifficulties = {
    n = "10",
    h = "25",
    N = "10 HC",
    H = "25 HC",
    ["4"] = "40",
    q = "10 Quest",
    Q = "25 Quest",
}

-- Dungeon sources use separate difficulty labels
local dungeonDifficulties = {
    h = "heroic",
    n = "normal",
    q = "quest",
}

-- Encoded entries use underscores between their fields
-- Keep parsing independent from display labels
local function SplitSourceCode(code)
    local fields = {}
    for field in code:gmatch("[^_]+") do
        fields[#fields + 1] = field
    end
    return fields
end

-- Look up zone, boss and difficulty in source database
-- Unknown boss can still produce useful zone name
local function DescribeBossSource(fields)
    local database = FusionGear_ItemSources
    local sourceType = fields[1]
    local zone = database.Zones[tonumber(fields[2])] or F.UNKNOWN_SOURCE
    local boss = database.Bosses[tonumber(fields[4])]
    local difficulty

    if sourceType == "r" then
        difficulty = raidDifficulties[fields[3]]
    else
        difficulty = dungeonDifficulties[fields[3]]
    end

    if difficulty then
        zone = zone .. " (" .. difficulty .. ")"
    end
    if boss then
        zone = zone .. " - " .. boss
    end

    return zone
end

-- Format currency name and required emblem count
-- Count may be absent in older source entries
local function DescribeCurrency(fields)
    local name = "Emblems " .. currencies[fields[1]]
    local count = tonumber(fields[2])
    if count then
        return name .. ": " .. count
    end
    return name
end

-- Codes without zone or boss use fixed source labels
local sourceLabels = {
    c = "Crafted",
    t = "Argent Tournament",
    f = "Reputation",
    e = "World event",
    g = "Vendor",
    m = "Darkmoon Faire",
}

-- Dispatch source code to raid, dungeon, currency or PvP decoder
-- Unknown codes receive shared fallback text
local function DescribeEntry(code)
    local fields = SplitSourceCode(code)
    local sourceType = fields[1]

    if sourceType == "r" or sourceType == "d" then
        return DescribeBossSource(fields)
    end
    if currencies[sourceType] then
        return DescribeCurrency(fields)
    end

    if sourceType == "p" then
        return "PvP: " .. (pvpNames[fields[2]] or "")
    end

    return sourceLabels[sourceType] or F.UNKNOWN_SOURCE
end

-- Cache decoded result for each item ID during session
-- Item source database is static until UI reload
-- Cache only uses item ID because source codes do not depend on enchants
local sourceCache = {}

-- Extract item ID from hyperlink and decode known sources
-- Return empty list for missing item or unknown item ID
-- Cached lists are reused for player and Inspect panels
function F:GetSourceLines(itemLink)
    if not itemLink or not FusionGear_ItemSources then
        return {}
    end

    local itemID = tonumber(itemLink:match("item:(%d+)"))
    if not itemID then
        return {}
    end

    local cached = sourceCache[itemID]
    -- No need to parse same item sources on every refresh
    if cached then
        return cached
    end

    local sources = {}
    -- Multiple source codes are separated by semicolons
    local encoded = FusionGear_ItemSources.Items[itemID]
    if encoded then
        for code in encoded:gmatch("[^;]+") do
            sources[#sources + 1] = DescribeEntry(code)
        end
    end

    sourceCache[itemID] = sources
    return sources
end

-- Build one label using standard Blizzard font template
-- This helper belongs to source panel and does not create globals
local function MakeSourceText(parent, font, width)
    local text = parent:CreateFontString(nil, "OVERLAY", font)
    if width then
        text:SetWidth(width)
    end
    text:SetJustifyH("LEFT")
    return text
end

-- Show native item tooltip when user hovers over source row
-- SetHyperlink lets Blizzard render normal item stats
-- Append known loot sources without replacing Blizzard item text
-- Limit extra lines to keep tooltip readable
local function ShowSourceTooltip(row)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(row.itemLink)

    -- Source rows are ours, so extra information goes after native item text
    -- Avoid empty separators when item has no known source
    if row.sources and #row.sources > 0 then
        GameTooltip:AddLine(" ")
        for index = 1, math.min(#row.sources, 8) do
            GameTooltip:AddLine(row.sources[index], 1, 0.80, 0.38, true)
        end
    end

    -- Reuse enchant names only in FusionGear-owned hover rows
    -- Native inventory item tooltips are not modified by this feature
    if row.enchantName then
        GameTooltip:AddLine("Enchant: " .. row.enchantName, 0.42, 0.95, 0.55, true)
    end

    GameTooltip:Show()
end

-- Create one reusable row for item name and first loot source
-- Each row stores item link so hover shows correct tooltip
local function CreateSourceRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(362, 23)
    row:EnableMouse(true)

    row.itemName = MakeSourceText(row, "GameFontHighlightSmall", 354)
    row.itemName:SetPoint("TOPLEFT", row, "TOPLEFT", 3, 0)

    row.itemSource = MakeSourceText(row, "GameFontDisableSmall", 354)
    row.itemSource:SetPoint("TOPLEFT", row, "TOPLEFT", 11, -11)
    row.itemSource:SetTextColor(0.76, 0.78, 0.82)

    local separator = row:CreateTexture(nil, "BACKGROUND")
    separator:SetTexture("Interface\\Buttons\\WHITE8X8")
    separator:SetVertexColor(0.35, 0.38, 0.43, 0.30)
    separator:SetSize(354, 1)
    separator:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 0)

    -- Use one hover handler for every row
    -- Hide tooltip only when row still owns it
    row:SetScript("OnEnter", ShowSourceTooltip)
    row:SetScript("OnLeave", function(self)
        if GameTooltip:GetOwner() == self then
            GameTooltip:Hide()
        end
    end)

    return row
end

-- Create exactly one source row per supported equipment slot
-- Rows are allocated once and reused during refresh
local function CreateSourceRows(frame)
    frame.rows = {}

    for index = 1, #F.EquipmentSlots do
        frame.rows[index] = CreateSourceRow(frame)
    end
end

-- Place source rows under panel heading
-- Slot data will be filled later by RefreshSources
function F:CreateSourceList(panel)
    local frame = CreateFrame("Frame", nil, panel)
    frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -68)
    frame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 11)
    CreateSourceRows(frame)
    return frame
end

-- Display occupied slots in compact source list
-- Each row is tied to one fixed inventory slot
-- Hide empty equipment slots instead of leaving blank rows
-- Source rows are repositioned only when compact order changes
function F:RefreshSources(sourcesFrame, items)
    if not sourcesFrame or not sourcesFrame:IsShown() or not items then
        return
    end
    -- Visible row index differs from inventory slot index
    local visible = 0
    for index, entry in ipairs(self.EquipmentSlots) do
        local row = sourcesFrame.rows[index]
        local item = items[entry[1]]
        row.itemLink = item and item.link
        row.sources = nil
        row.enchantName = nil
        if item then
            local sources = self:GetSourceLines(item.link)
            row.sources = sources
            -- Enchant ID is second numeric field of item link
            -- Parse it without requesting additional server data
            local enchantID = item.link:match("item:%d+:(%d+)")
            if enchantID then
                row.enchantName = self:GetEnchantName(enchantID)
            end
            local fallbackName = item.link:match("%[(.-)%]") or entry[2]
            row.itemName:SetText(
                (item.level and ("[" .. item.level .. "] ") or "") ..
                (item.name or fallbackName)
            )
            if item.quality then
                local red, green, blue = GetItemQualityColor(item.quality)
                row.itemName:SetTextColor(red, green, blue)
            else
                row.itemName:SetTextColor(1, 1, 1)
            end
            row.itemSource:SetText(sources[1] or self.UNKNOWN_SOURCE)
            if row.displayIndex ~= visible then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", sourcesFrame, "TOPLEFT", 0, -visible * 23)
                row.displayIndex = visible
            end
            row:Show()
            visible = visible + 1
        else
            row:Hide()
        end
    end
end

-- Release old row item links before next Inspect refresh
-- A new inspected player may have incomplete item data
-- Also prevents hover from displaying previous player item
function F:ClearInspectSources()
    for _, row in ipairs(self.inspectSourcesFrame.rows) do
        row.itemLink = nil
        row.sources = nil
        row.enchantName = nil
        row:Hide()
    end
end


-- Equipment markers for WoW 3.3.5a
-- Draw tiny icons on top of native character and Inspect slots
-- Never replace Blizzard inventory buttons or their tooltips
local _, F = ...

-- Slot item levels use FusionGear display colors, not GearScore formulas
-- These colors only style level numbers on equipment buttons
-- Map item level to display color
-- These thresholds style labels only and do not change item rarity
function F:GetItemLevelColor(level)
    local quality = 1
    if level >= 278 then
        quality = 5
    elseif level >= 200 then
        quality = 4
    elseif level >= 186 then
        quality = 3
    elseif level >= 150 then
        quality = 2
    end
    return GetItemQualityColor(quality)
end


-- Sizes match compact Blizzard character slot art
-- MAX_GEMS limits markers on one equipment slot
local GEM_SIZE = 11
local ENCHANT_SIZE = 12
local MAX_GEMS = 4

-- Blizzard art for socket with no equipped gem
-- Use placeholder only when item has no known inserted gem
local EMPTY_SOCKET_TEXTURES = {
    META = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Meta",
    RED = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Red",
    YELLOW = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Yellow",
    BLUE = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Blue",
    PRISMATIC = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic",
}

-- Socket counts are read from GetItemStats result
-- Keep fixed order for stable marker placement
local SOCKET_ORDER = { "META", "RED", "YELLOW", "BLUE", "PRISMATIC" }

-- Opacity is normalized during Core initialization
-- All marker textures share same saved alpha
local function GetIconOpacity()
    return FusionGearDB.iconAlpha
end

-- Extract numeric fields from item hyperlink
-- Field 1 is item ID and field 2 is permanent enchant ID
-- Fields 3 through 6 hold socket enchant IDs
-- Invalid links return nil instead of guessing item data
local function ParseItemLink(link)
    if not link then
        return nil
    end

    local itemString = link:match("item:([%d%-:]+)")
    if not itemString then
        return nil
    end

    local fields = {}
    for field in (itemString .. ":"):gmatch("(.-):") do
        fields[#fields + 1] = tonumber(field) or 0
    end

    local itemID = fields[1]
    if not itemID or itemID <= 0 then
        return nil
    end

    local gemEnchants = {
        fields[3] or 0,
        fields[4] or 0,
        fields[5] or 0,
        fields[6] or 0,
    }

    return itemID, fields[2] or 0, gemEnchants
end

-- Use local client item cache to resolve icon
-- GetItemInfo can be incomplete during fresh Inspect requests
-- Errors must not interrupt other equipment markers
local function GetCachedItemIcon(item)
    if type(GetItemIcon) == "function" then
        local ok, icon = pcall(GetItemIcon, item)
        if ok and icon then
            return icon
        end
    end

    if type(GetItemInfo) == "function" then
        local data = { pcall(GetItemInfo, item) }
        if data[1] then
            return data[11]
        end
    end

    return nil
end

-- Ask Blizzard which gem item is inserted into socket
-- Gem link and gem icon can arrive at different times
-- When link exists but artwork is missing return retry flag
local function GetGemIcon(itemLink, socketIndex)
    if type(GetItemGem) ~= "function" then
        return nil, false
    end

    local ok, _, gemLink = pcall(GetItemGem, itemLink, socketIndex)
    if not ok or not gemLink then
        return nil, false
    end

    local gemID = tonumber(gemLink:match("item:(%d+)"))
    local icon = gemID and GetCachedItemIcon(gemID)
    icon = icon or GetCachedItemIcon(gemLink)

    return icon, not icon
end

-- Resolve enchant artwork from EnchantIconMetadata
-- Prefer item icon and fall back to matching spell icon
-- Not every enchant has icon metadata
local function GetEnchantIcon(enchantID)
    if not enchantID or enchantID <= 0 then
        return nil
    end

    local metadata = F.EnchantIconMetadata and F.EnchantIconMetadata[enchantID]
    if not metadata then
        return nil
    end

    local spellID = metadata[1]
    local itemID = metadata[2]

    if itemID and itemID > 0 then
        local itemIcon = GetCachedItemIcon(itemID)
        if itemIcon then
            return itemIcon
        end
    end

    if spellID and spellID > 0 and type(GetSpellInfo) == "function" then
        local _, _, spellIcon = GetSpellInfo(spellID)
        return spellIcon
    end

    return nil
end

-- Compare base item and equipped item socket counts
-- This helps find sockets added by enchant or item effects
-- Item stats may not exist in client cache immediately
-- Never draw more than MAX_GEMS markers
local function GetSocketTypes(itemLink, itemID)
    local types = {}
    if type(GetItemStats) ~= "function" then
        return types
    end

    local baseLink = "item:" .. itemID .. ":0:0:0:0:0:0:0:0"
    local baseOk, baseStats = pcall(GetItemStats, baseLink)
    local actualOk, actualStats = pcall(GetItemStats, itemLink)
    baseStats = baseOk and type(baseStats) == "table" and baseStats or nil
    actualStats = actualOk and type(actualStats) == "table" and actualStats or nil
    local pending = not baseStats and not actualStats
    baseStats = baseStats or {}
    actualStats = actualStats or {}

    for _, socketType in ipairs(SOCKET_ORDER) do
        local statName = "EMPTY_SOCKET_" .. socketType
        local baseCount = tonumber(baseStats[statName]) or 0
        local actualCount = tonumber(actualStats[statName]) or 0
        local count = math.max(baseCount, actualCount)

        for _ = 1, count do
            if #types >= MAX_GEMS then
                return types, pending
            end
            types[#types + 1] = socketType
        end
    end

    return types, pending
end

-- Create texture once and keep it hidden until icon is known
-- Slot button continues handling clicks and native tooltip
local function CreateOverlay(slot, x, y, size)
    local texture = slot:CreateTexture(nil, "OVERLAY")
    texture:SetSize(size, size)
    texture:SetPoint("TOPLEFT", slot, "TOPLEFT", x, y)
    texture:SetAlpha(GetIconOpacity())
    texture:Hide()
    return texture
end

-- Allocate enchant marker and four gem markers per slot
-- Borders track visibility of matching gem textures
local function CreateSlotMarkers(slot)
    local marker = {
        enchant = CreateOverlay(slot, 1, -1, ENCHANT_SIZE),
        gems = {},
        borders = {},
        dirty = true,
    }

    for index = 1, MAX_GEMS do
        local offsetY = -1 - (index - 1) * 9
        local border = CreateOverlay(slot, 25, offsetY + 1, GEM_SIZE + 2)
        border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        border:SetTexCoord(0, 1, 0, 1)

        marker.borders[index] = border
        marker.gems[index] = CreateOverlay(slot, 26, offsetY, GEM_SIZE)
    end

    return marker
end

-- Single helper for icon art and visibility
-- Crop removes dark edges from inventory icon artwork
local function SetMarkerIcon(texture, icon, crop)
    if icon then
        texture:SetTexture(icon)
        texture:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
        texture:Show()
    else
        texture:Hide()
    end
end

-- Only show enchant icon when metadata resolves artwork
-- Unknown enchant does not get fake placeholder icon
local function UpdateEnchantMarker(marker, enchantID)
    SetMarkerIcon(marker.enchant, GetEnchantIcon(enchantID), 0.08)
end

-- Choose real gem icon before considering empty socket
-- Known gem with missing texture stays hidden until retry
-- False empty socket would misrepresent equipped item
local function UpdateGemMarker(marker, index, itemLink, gemEnchants, socketTypes)
    local texture = marker.gems[index]
    local icon, missingIcon
    if itemLink then
        icon, missingIcon = GetGemIcon(itemLink, index)
    end

    -- Installed gem artwork takes priority over empty socket art
    local socketType = socketTypes[index]
    local waiting = missingIcon or
        (gemEnchants and gemEnchants[index] > 0)

    if icon then
        SetMarkerIcon(texture, icon, 0.08)
    -- Gem exists but client has not cached its icon yet
    elseif waiting then
        SetMarkerIcon(texture, nil, 0)
    else
        local emptyIcon = socketType and EMPTY_SOCKET_TEXTURES[socketType]
        SetMarkerIcon(texture, emptyIcon, 0)
    end

    if texture:IsShown() then
        marker.borders[index]:Show()
    else
        marker.borders[index]:Hide()
    end

    -- Retry only while data for known gem is still missing
    return not icon and waiting
end

-- Update enchant and all gem markers from same item link
-- Return pending flag so unchanged slot may be retried
local function UpdateSlotMarkers(marker, itemLink)
    local itemID, enchantID, gemEnchants = ParseItemLink(itemLink)
    UpdateEnchantMarker(marker, enchantID)

    local socketTypes = {}
    local waitingForStats = false
    if itemID then
        socketTypes, waitingForStats = GetSocketTypes(itemLink, itemID)
    end

    local waitingForGem = false
    for index = 1, MAX_GEMS do
        if UpdateGemMarker(marker, index, itemLink, gemEnchants, socketTypes) then
            waitingForGem = true
        end
    end

    return waitingForGem or waitingForStats
end

-- Create separate texture groups for Character and Inspect
-- Keep slot frames owned by Blizzard
function F:CreateEquipmentMarkers(prefix)
    self.equipmentMarkers = self.equipmentMarkers or {}
    if self.equipmentMarkers[prefix] then
        return
    end

    local markers = {}
    for _, entry in ipairs(self.EquipmentSlots) do
        local slot = _G[prefix .. entry[2]]
        if slot then
            markers[entry[1]] = CreateSlotMarkers(slot)
        end
    end

    self.equipmentMarkers[prefix] = markers
end

-- Force redraw after inspected player identity changes
-- Existing textures are reused instead of recreated
function F:ResetEquipmentCache(prefix)
    local markers = self.equipmentMarkers and self.equipmentMarkers[prefix]
    if not markers then
        return
    end

    for _, marker in pairs(markers) do
        marker.dirty = true
    end
end

-- Skip identical item links unless retry is pending
-- Dirty marker always gets refreshed after Inspect reset
function F:RefreshEquipmentMarkers(prefix, items)
    local markers = self.equipmentMarkers and self.equipmentMarkers[prefix]
    if not markers then
        return
    end

    for _, entry in ipairs(self.EquipmentSlots) do
        local marker = markers[entry[1]]
        if marker then
            local item = items[entry[1]]
            local itemLink = item and item.link
            if marker.dirty or marker.lastLink ~= itemLink or marker.needsRetry then
                marker.lastLink = itemLink
                marker.needsRetry = UpdateSlotMarkers(marker, itemLink)
                marker.dirty = false
            end
        end
    end
end

-- Apply opacity to enchant icon, gems and borders
local function SetMarkerOpacity(marker, alpha)
    marker.enchant:SetAlpha(alpha)

    for index = 1, MAX_GEMS do
        marker.gems[index]:SetAlpha(alpha)
        marker.borders[index]:SetAlpha(alpha)
    end
end

-- Change marker alpha immediately after slash command
-- No item data lookup or texture allocation is needed
function F:RefreshEquipmentOpacity()
    local alpha = GetIconOpacity()
    for _, markers in pairs(self.equipmentMarkers or {}) do
        for _, marker in pairs(markers) do
            SetMarkerOpacity(marker, alpha)
        end
    end
end

-- One snapshot is reused for labels, average and source list
-- This avoids reading every equipment slot several times per refresh
-- A missing item level is kept as nil until GetItemInfo is ready
-- Do not replace unknown item level with zero

-- Take one equipment snapshot for requested unit
-- Each entry keeps link and item info from same refresh pass
-- GetItemInfo can return nil while item cache is loading
-- Empty slots never receive fabricated items
function F:ReadEquipment(unit)
    local items = {}
    for _, entry in ipairs(self.EquipmentSlots) do
        local slotID = entry[1]
        local link = GetInventoryItemLink(unit, slotID)
        if link then
            local name, _, quality, level = GetItemInfo(link)
            items[slotID] = {
                link = link,
                name = name,
                quality = quality,
                level = level,
            }
        end
    end
    return items
end

-- Update item level labels and small gem or enchant icons
-- Use same snapshot for text and icons to avoid extra reads
-- Clear label when item level is not yet available
function F:RefreshSlotLabels(prefix, items)
    local labels = self.slotLabels[prefix]
    if not labels then
        return
    end
    self:RefreshEquipmentMarkers(prefix, items)
    for _, entry in ipairs(self.EquipmentSlots) do
        local label = labels[entry[1]]
        if label then
            local item = items[entry[1]]
            local level = item and item.level
            if level then
                label:SetText(level)
                local red, green, blue = self:GetItemLevelColor(level)
                label:SetTextColor(red, green, blue)
            else
                label:SetText("")
            end
        end
    end
end


-- Attach item level text to original Blizzard equipment buttons
-- Prefix selects Character or Inspect slot names
-- Both views have different label tables and marker caches
-- Do not replace item button or original item tooltip
function F:CreateSlotLabels(prefix)
    if self.slotLabels[prefix] then
        return
    end
    local labels = {}
    for _, entry in ipairs(self.EquipmentSlots) do
        local slot = _G[prefix .. entry[2]]
        if slot then
            local label = slot:CreateFontString(nil, "OVERLAY", "SystemFont_Outline_Small")
            label:SetPoint("BOTTOM", slot, "BOTTOM", 0, 2)
            label:SetJustifyH("CENTER")
            label:SetShadowColor(0, 0, 0, 1)
            label:SetShadowOffset(1, -1)
            labels[entry[1]] = label
        end
    end
    self.slotLabels[prefix] = labels
    self:CreateEquipmentMarkers(prefix)
end


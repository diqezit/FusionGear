-- FusionGear window controller and event router for WoW 3.3.5a
-- WoW loads modules in the order listed in FusionGear.toc
-- F is shared addon table used by all FusionGear Lua files
-- Core creates panels after PLAYER_LOGIN and keeps views in sync
-- InspectEquip handles source rows and item source descriptions
-- Equipment handles item snapshots, slot labels and gem markers
-- GearScore displays values from original GearScoreLite API
-- No duplicate GearScore formulas are used by FusionGear
-- Tooltip and statistics have their own modules
local _, F = ...

-- Equipment slots used by both player and Inspect panels
-- First value is inventory slot ID used by Blizzard API
-- Second value is suffix of Blizzard equipment button name
-- Keep order stable so labels and source rows match equipment
local slots = {
    { 1, "HeadSlot" }, { 2, "NeckSlot" }, { 3, "ShoulderSlot" },
    { 5, "ChestSlot" }, { 6, "WaistSlot" }, { 7, "LegsSlot" },
    { 8, "FeetSlot" }, { 9, "WristSlot" }, { 10, "HandsSlot" },
    { 11, "Finger0Slot" }, { 12, "Finger1Slot" },
    { 13, "Trinket0Slot" }, { 14, "Trinket1Slot" },
    { 15, "BackSlot" }, { 16, "MainHandSlot" },
    { 17, "SecondaryHandSlot" }, { 18, "RangedSlot" },
}

F.EquipmentSlots = slots

-- Create single font string without a global frame name
-- Optional width lets several panels reuse this helper
local function MakeText(parent, font, width)
    local text = parent:CreateFontString(nil, "OVERLAY", font)
    if width then
        text:SetWidth(width)
    end
    text:SetJustifyH("LEFT")
    return text
end

-- Create shared background and title for side panels
-- Character and Inspect use separate frame instances
local function CreatePanelShell(name)
    local panel = CreateFrame("Frame", name, UIParent)
    panel:SetSize(390, 488)
    panel:SetFrameStrata("HIGH")
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 13,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel:SetBackdropColor(0.06, 0.07, 0.09, 0.97)
    panel:SetBackdropBorderColor(0.38, 0.40, 0.45, 1)

    local title = MakeText(panel, "GameFontNormal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 13, -11)
    title:SetText("FusionGear")

    panel:Hide()

    return panel
end

-- Create tab button with fixed destination
-- Click changes player panel only
local function CreateTabButton(panel, text, x, tab)
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(110, 22)
    button:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -34)
    button:SetText(text)
    button:SetScript("OnClick", function()
        F:SetTab(tab)
    end)
    return button
end

-- Build player side panel with Stats and Item Sources tabs
-- Stat rows are prepared before initial tab selection
function F:CreatePanel()
    local panel = CreatePanelShell("FusionGearPanel")
    panel.statsButton = CreateTabButton(panel, "Statistics", 12, "stats")
    panel.sourcesButton = CreateTabButton(panel, "Item Sources", 126, "sources")

    self:CreateStats(panel)
    self.panel = panel
    self.sourcesFrame = self:CreateSourceList(panel)
    self:SetTab("stats")
end

-- Build separate Inspect panel when Blizzard InspectUI exists
-- Inspect shows sources and average item level but no player stats
function F:CreateInspectPanel()
    if self.inspectPanel or not InspectFrame then
        return
    end

    local panel = CreatePanelShell("FusionGearInspectPanel")
    local heading = MakeText(panel, "GameFontNormal")
    heading:SetPoint("TOPLEFT", panel, "TOPLEFT", 15, -38)
    heading:SetText("Item Sources")

    self.inspectPanel = panel
    self.inspectSourcesFrame = self:CreateSourceList(panel)
end

-- Share visibility logic between both player tabs
-- Missing frame is valid before lazy Blizzard UI loads
local function SetFrameVisible(frame, visible)
    if not frame then
        return
    end

    if visible then
        frame:Show()
    else
        frame:Hide()
    end
end

-- Select player panel tab without changing Inspect panel
-- Panel height differs because source list needs more space
function F:SetTab(name)
    if name ~= "stats" and name ~= "sources" then
        return
    end

    self.currentTab = name

    if self.panel then
        self.panel:SetHeight(name == "sources" and 488 or 428)
        if name == "stats" then
            self.panel.statsButton:Disable()
            self.panel.sourcesButton:Enable()
        else
            self.panel.statsButton:Enable()
            self.panel.sourcesButton:Disable()
        end
    end

    SetFrameVisible(self.statsFrame, name == "stats")
    SetFrameVisible(self.sourcesFrame, name == "sources")

    self:Refresh()
end

-- Read unit token from Blizzard InspectFrame
-- Token can disappear when target changes or frame closes
function F:GetInspectUnit()
    local unit = InspectFrame and InspectFrame.unit
    if unit and UnitExists(unit) then
        return unit
    end
    return nil
end

-- Keep Inspect state tied to current unit GUID
-- One GUID identifies one inspected character
-- Reset markers and rows only when inspected identity changes
-- INSPECT_READY can be delayed and is not sole data source
function F:SyncInspectGuid(guid)
    if guid == self.inspectGuid then
        return
    end

    self.inspectGuid = guid

    self:ClearInspectSummary()
    self:ClearInspectSources()
    self:ResetEquipmentCache("Inspect")
end

-- Collect available Inspect equipment using native API
-- Never block entire panel just because INSPECT_READY is late
-- Inspect data is asynchronous and may arrive in several updates
-- Current unit may have incomplete item data during load
function F:RefreshInspect()
    if not self.inspectPanel or not InspectFrame or not InspectFrame:IsShown() then
        return nil
    end

    local unit = self:GetInspectUnit()
    local guid = unit and UnitGUID(unit)
    self:SyncInspectGuid(guid)

    -- No valid target means all slot labels must be empty
    if not unit or not guid then
        self:RefreshSlotLabels("Inspect", {})
        return nil
    end

    local items = self:ReadEquipment(unit)
    self:RefreshSlotLabels("Inspect", items)
    self:RefreshAverage(unit, items)
    return unit, items
end

-- Update visible character views from fresh item snapshots
-- Each visible unit is read once and shared by labels and source rows
-- Character and Inspect read distinct units and never share items
-- Stats and sources are refreshed only for selected tab
function F:Refresh()
    if not self.slotLabels then
        return
    end

    local playerItems
    if PaperDollFrame and PaperDollFrame:IsShown() then
        playerItems = self:ReadEquipment("player")
        self:RefreshSlotLabels("Character", playerItems)
        self:RefreshAverage("player", playerItems)
    end

    local inspectedUnit, inspectedItems = self:RefreshInspect()

    if self.panel and self.panel:IsShown() then
        if self.currentTab == "stats" then
            self:RefreshStats()
        else
            self:RefreshSources(self.sourcesFrame, playerItems)
        end
    end

    if self.inspectPanel and self.inspectPanel:IsShown() then
        self:RefreshSources(self.inspectSourcesFrame, inspectedItems)
    end
end

-- Show enabled panel state through toggle button text color
-- Inspect option must not fall back to player option when false
function F:UpdateButtons()
    for prefix, button in pairs(self.toggleButtons) do
        local inspect = prefix == "Inspect"
        local enabled = FusionGearDB.showPanel
        if inspect then
            enabled = FusionGearDB.showInspectPanel
        end
        if button.fgEnabled ~= enabled then
            local label = button:GetFontString()
            if enabled then
                label:SetTextColor(1, 0.82, 0.22)
            else
                label:SetTextColor(0.85, 0.85, 0.85)
            end
            button.fgEnabled = enabled
        end
    end
end

-- Choose side with enough free screen space
-- Prefer right side until window approaches screen edge
function F:GetPanelSide(parent, panel)
    local right = parent:GetRight()
    local left = parent:GetLeft()
    local screenRight = UIParent:GetRight()
    local screenLeft = UIParent:GetLeft() or 0
    if right and left and screenRight then
        local availableRight = screenRight - right
        local availableLeft = left - screenLeft
        if availableRight < panel:GetWidth() - 18 and availableLeft > availableRight then
            return "LEFT"
        end
    end
    return "RIGHT"
end

-- Keep side panel inside current UI screen bounds
-- Offsets account for panel width and window position
function F:GetPanelOffset(parent, panel, side)
    local screenLeft = UIParent:GetLeft() or 0
    local screenRight = UIParent:GetRight()
    if side == "LEFT" then
        local left = parent:GetLeft()
        if left then
            return math.max(18, screenLeft + panel:GetWidth() + 4 - left)
        end
        return 18
    end
    local right = parent:GetRight()
    if right and screenRight then
        return math.min(-18, screenRight - panel:GetWidth() - right - 4)
    end
    return -18
end

-- Anchor panel to moving Blizzard character window
-- Keep chosen side and offset for later comparison
function F:AnchorPanel(parent, panel, side, offset)
    if not parent or not panel then
        return
    end
    panel:SetParent(parent)
    panel:ClearAllPoints()
    side = side or self:GetPanelSide(parent, panel)
    offset = offset or self:GetPanelOffset(parent, panel, side)
    panel.anchorSide = side
    panel.anchorOffset = offset
    if side == "LEFT" then
        panel:SetPoint("TOPRIGHT", parent, "TOPLEFT", offset, -14)
    else
        panel:SetPoint("TOPLEFT", parent, "TOPRIGHT", offset, -14)
    end
    panel:SetFrameLevel(parent:GetFrameLevel() + 8)
end

-- Check for changed anchor without moving panel each frame
-- Prevents needless layout updates while character window is still
function F:SyncPanelPosition(panel, parent)
    if not panel or not panel:IsShown() or not parent or not parent:IsShown() then
        return
    end
    local side = self:GetPanelSide(parent, panel)
    local offset = self:GetPanelOffset(parent, panel, side)
    if panel.anchorSide ~= side or math.abs((panel.anchorOffset or 0) - offset) > 1 then
        self:AnchorPanel(parent, panel, side, offset)
    end
end

-- Use space left by hidden Blizzard stat categories
-- Model moves without replacing equipment slot buttons
function F:ExpandCharacterModel()
    if not CharacterModelFrame then
        return
    end
    CharacterModelFrame:ClearAllPoints()
    CharacterModelFrame:SetPoint("TOPLEFT", PaperDollFrame, "TOPLEFT", 65, -78)
    CharacterModelFrame:SetSize(233, 294)
end

-- Show correct panel for active Blizzard character view
-- Hide opposite panel so both panels never overlap
-- Read per-view visibility from independent saved options
function F:ShowFor(view)
    local inspect = view == "inspect"
    local parent = inspect and InspectFrame or CharacterFrame
    local panel = inspect and self.inspectPanel or self.panel
    local other = inspect and self.panel or self.inspectPanel
    if not panel or not parent or not parent:IsShown() then
        return
    end

    self.activeView = view
    if other then
        other:Hide()
    end
    self:AnchorPanel(parent, panel)
    -- Frame OnUpdate is enabled only for visible Blizzard equipment windows
    if self.ticker then
        self.ticker:Show()
    end
    local setting = inspect and "showInspectPanel" or "showPanel"
    local visible = FusionGearDB[setting]
    -- Open Outfitter window covers player panel
    if not inspect and OutfitterFrame and OutfitterFrame:IsShown() then
        visible = false
    end
    SetFrameVisible(panel, visible)
    self:UpdateButtons()
    self:Refresh()
end

-- Change visibility option for player or Inspect independently
-- Opening different view first enables its panel
function F:TogglePanel(view)
    view = view or self.activeView or "player"
    local setting = view == "inspect" and "showInspectPanel" or "showPanel"
    if self.activeView == view then
        FusionGearDB[setting] = not FusionGearDB[setting]
    else
        FusionGearDB[setting] = true
    end
    self:ShowFor(view)
end

-- Create small button beside ranged equipment slot
-- Player button opens Stats and Inspect button opens Sources
-- Keep native equipment slots clickable
function F:CreateToggle(prefix, parent)
    local rangedSlot = _G[prefix .. "RangedSlot"]
    if not parent or not rangedSlot then
        return
    end
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(48, 30)
    button:SetText(prefix == "Inspect" and "Sources" or "Stats")
    -- Place player Stats button left of the bottom equipment row
    if prefix == "Character" and CharacterMainHandSlot then
        button:SetPoint("RIGHT", CharacterMainHandSlot, "LEFT", -8, -7)
    else
        button:SetPoint("LEFT", rangedSlot, "RIGHT", 55, -7)
    end
    button:SetFrameLevel(rangedSlot:GetFrameLevel() + 5)
    button:SetScript("OnClick", function()
        F:TogglePanel(prefix == "Inspect" and "inspect" or "player")
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Show / Hide FusionGear", 1, 0.82, 0.35)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    self.toggleButtons[prefix] = button
    self:UpdateButtons()
end

-- InspectUI is loaded by Blizzard only when requested
-- Create inspect widgets and attach handlers once
-- Hide stored inspect view when InspectFrame closes
function F:HookInspect()
    if self.inspectHooked or not InspectFrame then
        return
    end
    self.inspectHooked = true
    self:CreateSlotLabels("Inspect")
    self:CreateInspectPanel()
    self:CreateToggle("Inspect", InspectPaperDollFrame)
    self:CreateInspectSummary()
    InspectFrame:HookScript("OnShow", function()
        F:ShowFor("inspect")
    end)
    InspectFrame:HookScript("OnHide", function()
        F.inspectGuid = nil
        F:ResetEquipmentCache("Inspect")
        if F.inspectPanel then
            F.inspectPanel:Hide()
        end
        if PaperDollFrame and PaperDollFrame:IsShown() then
            F:ShowFor("player")
        elseif F.ticker then
            F.ticker:Hide()
        end
    end)
    InspectFrame:HookScript("OnMouseDown", function()
        F:ShowFor("inspect")
    end)
    if InspectFrame:IsShown() then
        self:ShowFor("inspect")
    end
end

-- Write defaults only when saved option does not exist
-- Preserve settings chosen in earlier sessions
local function SetDefaultOption(name, value)
    if FusionGearDB[name] == nil then
        FusionGearDB[name] = value
    end
end

-- Build FusionGear UI after PLAYER_LOGIN
-- Validate saved settings before markers use them
-- Hook existing Blizzard frames instead of replacing scripts
function F:Initialize()
    -- Corrupt SavedVariables should not break login
    if type(FusionGearDB) ~= "table" then
        FusionGearDB = {}
    end
    SetDefaultOption("showPanel", true)
    SetDefaultOption("showInspectPanel", true)
    if type(FusionGearDB.iconAlpha) ~= "number" or
        FusionGearDB.iconAlpha ~= FusionGearDB.iconAlpha then
        FusionGearDB.iconAlpha = 0.80
    end
    FusionGearDB.iconAlpha = math.max(0.2, math.min(1, FusionGearDB.iconAlpha))
    self.slotLabels = {}
    self.toggleButtons = {}

    -- Hide Blizzard attribute category area to make room for addon
    -- Keep original PaperDoll slots and helper functions intact
    if CharacterAttributesFrame then
        CharacterAttributesFrame:Hide()
        CharacterAttributesFrame:HookScript("OnShow", function(self)
            self:Hide()
        end)
    end

    self:CreateSlotLabels("Character")
    self:CreateGearSummary()
    self:CreatePanel()
    self:InitTooltips()
    self:CreateToggle("Character", PaperDollFrame)
    self:HookInspect()

    -- Closing player window must not hide an open Inspect view
    local function RestoreInspectPanel()
        if F.panel then
            F.panel:Hide()
        end
        if InspectFrame and InspectFrame:IsShown() then
            F:ShowFor("inspect")
        elseif F.ticker then
            F.ticker:Hide()
        end
    end

    if PaperDollFrame then
        PaperDollFrame:HookScript("OnShow", function()
            F:ExpandCharacterModel()
            F:PositionGearScore()
            F:ShowFor("player")
        end)
        PaperDollFrame:HookScript("OnHide", RestoreInspectPanel)
    end
    if CharacterFrame then
        CharacterFrame:HookScript("OnMouseDown", function()
            F:ShowFor("player")
        end)
        CharacterFrame:HookScript("OnHide", RestoreInspectPanel)
    end
    -- OutfitterFrame is created by its XML before PLAYER_LOGIN
    -- ShowFor reads its state so other callers keep panel hidden too
    if OutfitterFrame then
        OutfitterFrame:HookScript("OnShow", function()
            F.panel:Hide()
        end)
        OutfitterFrame:HookScript("OnHide", function()
            -- OnHide also fires when Character window or tab closes
            if F.activeView == "player" and PaperDollFrame:IsVisible() then
                F:ShowFor("player")
            end
        end)
    end
    if PaperDollFrame and PaperDollFrame:IsShown() then
        self:ExpandCharacterModel()
        self:PositionGearScore()
        self:ShowFor("player")
    end
end

-- Listen only to events affecting character data or late item cache
-- Stat changes update visible values without rescanning slots
local events = CreateFrame("Frame")
-- Fast events handled by Blizzard stat proxy functions
-- UNIT events use first argument as unit token
local statEvents = {
    UNIT_AURA = true,
    UNIT_STATS = true,
    UNIT_LEVEL = true,
    UNIT_RESISTANCES = true,
    UNIT_ATTACK = true,
    UNIT_DAMAGE = true,
    UNIT_RANGEDDAMAGE = true,
    UNIT_ATTACK_POWER = true,
    UNIT_RANGED_ATTACK_POWER = true,
    UNIT_ATTACK_SPEED = true,
    COMBAT_RATING_UPDATE = true,
    PLAYER_DAMAGE_DONE_MODS = true,
}

for event in pairs(statEvents) do
    events:RegisterEvent(event)
end

-- Equipment and Inspect changes use full item refresh path
local otherEvents = {
    "PLAYER_LOGIN", "ADDON_LOADED", "PLAYER_EQUIPMENT_CHANGED",
    "UNIT_INVENTORY_CHANGED", "INSPECT_READY", "PLAYER_TARGET_CHANGED",
    "GET_ITEM_INFO_RECEIVED", "PLAYER_ENTERING_WORLD",
}
for _, event in ipairs(otherEvents) do
    events:RegisterEvent(event)
end

-- Ignore changes from unrelated party and raid units
-- Allow player and currently inspected unit only
local function IsRelevantUnit(unit)
    if not unit then
        return true
    end
    if unit == "player" then
        return true
    end
    local inspectUnit = F:GetInspectUnit()
    return inspectUnit and unit == inspectUnit
end

-- Route Blizzard events to minimal required work
-- PLAYER_LOGIN creates UI before other handlers read it
events:SetScript("OnEvent", function(self, event, arg)
    if event == "PLAYER_LOGIN" then
        F:Initialize()
        return
    end
    -- InspectUI and AtlasLoot may load after player login
    -- Hook lazily created frames when they become available
    if event == "ADDON_LOADED" then
        if arg == "Blizzard_InspectUI" and F.panel then
            F:HookInspect()
        elseif arg == "GearScoreLite" and F.panel then
            F:PositionGearScore()
        end
        if F.panel and (arg == "AtlasLoot" or arg == "AtlasLootLoader") then
            F:HookTooltips()
        end
        return
    end
    if not F.panel then
        return
    end

    -- InspectFrame may change unit token when target changes
    -- Always verify identity before reading equipment
    if event == "PLAYER_TARGET_CHANGED" then
        if InspectFrame and InspectFrame:IsShown() then
            F:Refresh()
        end
        return
    end
    -- Ignore readiness events for players other than current target
    -- Never request extra inspection from this handler
    if event == "INSPECT_READY" then
        local unit = F:GetInspectUnit()
        if not unit then
            return
        end
        local guid = UnitGUID and UnitGUID(unit)
        if not guid or (type(arg) == "string" and guid ~= arg) then
            return
        end
        F:SyncInspectGuid(guid)
        F:Refresh()
        return
    end
    -- Foreign inventory events must not trigger full refresh
    if event == "UNIT_INVENTORY_CHANGED" and not IsRelevantUnit(arg) then
        return
    end

    -- Coalesce overlapping inventory and cache events
    -- Ticker performs one full refresh after short delay
    if event == "PLAYER_EQUIPMENT_CHANGED" or
        event == "UNIT_INVENTORY_CHANGED" or
        event == "GET_ITEM_INFO_RECEIVED" then
        F.equipmentDirty = true
        return
    end

    if event:sub(1, 5) == "UNIT_" and not IsRelevantUnit(arg) then
        return
    end

    -- Update visible statistics immediately on aura or rating changes
    -- Avoid socket and source scans for stat-only events
    if statEvents[event] then
        if F.panel and F.panel:IsVisible() and
            F.currentTab == "stats" then
            F:RefreshStats()
        end
        return
    end

    F:Refresh()
end)

-- Lightweight timer for batched updates and layout checks
-- Slow fallback refresh helps incomplete client item cache
-- No ticker work is needed when both Blizzard windows are closed
local ticker = CreateFrame("Frame")
F.ticker = ticker
-- Hidden frames do not receive OnUpdate in WoW 3.3.5a
-- ShowFor wakes ticker when Character or Inspect opens
-- Closing last equipment window puts ticker back to sleep
ticker:Hide()
local refreshElapsed, anchorElapsed, cacheElapsed = 0, 0, 0
ticker:SetScript("OnUpdate", function(self, delta)
    local characterShown = PaperDollFrame and PaperDollFrame:IsShown()
    local inspectShown = InspectFrame and InspectFrame:IsShown()
    if not characterShown and not inspectShown then
        refreshElapsed, anchorElapsed, cacheElapsed = 0, 0, 0
        F.equipmentDirty = false
        self:Hide()
        return
    end
    -- Delay related inventory notifications by one tenth second
    if F.equipmentDirty then
        cacheElapsed = cacheElapsed + delta
        if cacheElapsed >= 0.10 then
            F.equipmentDirty = false
            cacheElapsed = 0
            F:Refresh()
        end
    end
    anchorElapsed = anchorElapsed + delta
    -- Reposition side panels only when their parent window moves
    if anchorElapsed >= 0.5 then
        anchorElapsed = 0
        if F.panel and F.panel:IsShown() then
            F:SyncPanelPosition(F.panel, CharacterFrame)
        end
        if F.inspectPanel and F.inspectPanel:IsShown() then
            F:SyncPanelPosition(F.inspectPanel, InspectFrame)
        end
    end
    refreshElapsed = refreshElapsed + delta
    -- Inspect uses faster fallback polling while remote items load
    local interval = inspectShown and 3 or 8
    if refreshElapsed >= interval then
        refreshElapsed = 0
        F:Refresh()
    end
end)

-- Slash commands keep options small and avoid separate settings UI
-- Commands change current tab, icon opacity or tooltip formatting
SLASH_FUSIONGEAR1 = "/fusiongear"
SLASH_FUSIONGEAR2 = "/fg"
SlashCmdList.FUSIONGEAR = function(message)
    if not F.panel then
        return
    end
    local command, argument = message:match("^(%S+)%s*(.-)$")
    command = command or ""
    if command == "sources" then
        F:SetTab("sources")
    elseif command == "stats" then
        F:SetTab("stats")
    elseif command == "help" then
        DEFAULT_CHAT_FRAME:AddMessage(
            "FusionGear: /fg stats, /fg sources, /fg tooltip on|off, /fg icons 20-100"
        )
    -- Icon opacity expects percent and stores fraction from 0 to 1
    elseif command == "icons" then
        local percent = tonumber(argument)
        if percent and percent >= 20 and percent <= 100 then
            FusionGearDB.iconAlpha = percent / 100
            F:RefreshEquipmentOpacity()
        else
            DEFAULT_CHAT_FRAME:AddMessage("FusionGear: usage /fg icons 20-100 (default 80)")
        end
    -- Enable or disable addon formatting without touching Blizzard API
    elseif command == "tooltip" then
        local settings = FusionGearDB.tooltips
        if type(settings) ~= "table" then
            return
        end
        if argument == "on" then
            settings.enabled = true
        elseif argument == "off" then
            settings.enabled = false
        else
            settings.enabled = not settings.enabled
        end
        DEFAULT_CHAT_FRAME:AddMessage("FusionGear tooltips: " .. (settings.enabled and "On" or "Off"))
    else
        F:TogglePanel()
    end
end

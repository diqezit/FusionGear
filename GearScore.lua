-- Display original GearScoreLite results in FusionGear panels
-- GearScoreLite Reborn 3x05 owns all score formulas and score colors
-- This file contains only frames, text layout and external API calls
-- Do not copy GearScoreLite code or modify its original functions
local _, F = ...

-- Keep both summary numbers aligned with character equipment
-- UI coordinates do not affect item scores
local SCORE_X = 105
local SCORE_Y = 151
local SCORE_TITLE_Y = 135
local SUMMARY_WIDTH = 126

-- Use same font for player and inspected character values
local function StyleSummaryText(text, size)
    text:SetWidth(SUMMARY_WIDTH)
    text:SetJustifyH("CENTER")
    text:SetFont("Fonts\\FRIZQT__.TTF", size, "OUTLINE")
end

-- Each summary uses a number with a small label below it
-- Both objects belong to FusionGear except original player GS text
local function CreateSummaryNumber(parent, title, x)
    local number = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    number:SetPoint("BOTTOM", parent, "BOTTOMLEFT", x, SCORE_Y)
    StyleSummaryText(number, 17)

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOP", number, "BOTTOM", 0, -1)
    StyleSummaryText(label, 13)
    label:SetText(title)

    return number, label
end

-- Show average next to original GearScoreLite player number
-- Never create another player GearScore text or calculate score here
function F:CreateGearSummary()
    if self.gearOverlay then
        return
    end

    local overlay = CreateFrame("Frame", nil, PaperDollFrame)
    overlay:SetAllPoints(PaperDollFrame)
    if CharacterModelFrame then
        overlay:SetFrameLevel(CharacterModelFrame:GetFrameLevel() + 4)
    end
    self.gearOverlay = overlay
    self.itemLevelText, self.itemLevelLabel = CreateSummaryNumber(
        overlay, "Item Level", 264
    )
end

-- Inspect has its own numbers because GearScoreLite has no Inspect labels
-- Never copy current player score into another player's window
function F:CreateInspectSummary()
    if self.inspectOverlay then
        return
    end

    local overlay = CreateFrame("Frame", nil, InspectPaperDollFrame)
    overlay:SetAllPoints(InspectPaperDollFrame)
    overlay:SetFrameLevel(InspectPaperDollFrame:GetFrameLevel() + 10)
    self.inspectOverlay = overlay

    self.inspectGearScoreText = CreateSummaryNumber(overlay, "GearScore", SCORE_X)
    self.inspectItemLevelText = CreateSummaryNumber(overlay, "Item Level", 263)
end

-- Clear all inspected values when the target identity changes
-- New Inspect results must never inherit values from old target
function F:ClearInspectSummary()
    self.inspectGearScoreText:SetText("")
    self.inspectItemLevelText:SetText("")
end

-- GearScoreLite is optional but is the only score provider
-- Original API returns score first and average item level second
-- A failing call means item information may still be loading
-- Never replace missing scores with a home-made calculation
local function ReadGearScore(unit, items)
    if type(GearScore_GetScore) ~= "function" then
        return nil, nil
    end
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then
        return nil, nil
    end

    -- Empty inspected inventory must not produce a guessed score
    -- Let original function decide whether cached items are sufficient
    -- pcall protects panel if original code receives missing GetItemInfo data
    if not items or not next(items) then
        return nil, nil
    end

    -- This is original GearScoreLite API, not a FusionGear formula
    local ok, score, average = pcall(GearScore_GetScore, UnitName(unit), unit)
    if not ok or type(score) ~= "number" or score ~= score then
        return nil, nil
    end
    if type(average) ~= "number" or average ~= average then
        average = nil
    end
    return score > 0 and score or nil, average and average > 0 and average or nil
end

-- Apply colors returned by GearScoreLite without editing its palette
-- Unavailable external data clears text instead of displaying stale score
local function SetScoreText(text, score)
    if not score then
        text:SetText("")
        return
    end

    text:SetText(score)
    if type(GearScore_GetQuality) == "function" then
        -- Reborn 3x05 returns red, blue, green despite its usual RGB names
        -- Mirror order used by original PersonalGearScore FontString
        local ok, red, blue, green = pcall(GearScore_GetQuality, score)
        if ok and type(red) == "number" and type(green) == "number"
            and type(blue) == "number" then
            text:SetTextColor(red, green, blue)
        end
    end
end

-- Style item level using the existing FusionGear equipment palette
-- This only changes text color and never recalculates item level
local function SetItemLevelText(text, average)
    if not average then
        text:SetText("")
        return
    end

    text:SetText(average)
    local red, green, blue = F:GetItemLevelColor(average)
    text:SetTextColor(red, green, blue)
end

-- Average item level is taken from original GetScore second return value
-- No item level averaging or custom GearScore math is used here
function F:RefreshAverage(unit, items)
    local score, average = ReadGearScore(unit, items)

    if unit == "player" then
        SetItemLevelText(self.itemLevelText, average)
        self.itemLevelLabel:SetText(average and "Item Level" or "")
        return
    end

    SetScoreText(self.inspectGearScoreText, score)
    SetItemLevelText(self.inspectItemLevelText, average)

end

-- Move GearScoreLite's existing player number into the model area
-- Keep the same FontStrings so original addon still updates them
-- GearScoreLite continues to control its text and color
function F:PositionGearScore()
    if not self.gearOverlay then
        return
    end

    local number = _G.PersonalGearScore
    local title = _G.GearScore2

    if number then
        if number:GetParent() ~= self.gearOverlay then
            number:SetParent(self.gearOverlay)
        end
        number:ClearAllPoints()
        number:SetPoint("BOTTOM", self.gearOverlay, "BOTTOMLEFT", SCORE_X, SCORE_Y)
        StyleSummaryText(number, 17)
    end

    if title then
        if title:GetParent() ~= self.gearOverlay then
            title:SetParent(self.gearOverlay)
        end
        title:ClearAllPoints()
        StyleSummaryText(title, 13)
        if number then
            title:SetPoint("TOP", number, "BOTTOM", 0, -1)
        else
            title:SetPoint("BOTTOM", self.gearOverlay, "BOTTOMLEFT", SCORE_X, SCORE_TITLE_Y)
        end
    end
end

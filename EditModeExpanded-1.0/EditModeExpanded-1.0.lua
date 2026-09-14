--
-- Internal variables
--

local MAJOR, MINOR = "EditModeExpanded-1.0", 118
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local L = {
    ["enUS"] = {
        ["CLAMP_TO_SCREEN"] = "Clamp to Screen",
        ["TOGGLE_VISIBILITY_COMBAT"] = "Toggle Visibility in Combat",
        ["COORDINATES"] = "Coordinates:",
        ["EXPANDED"] = "Expanded",
    },
    ["zhCN"] = {
        ["CLAMP_TO_SCREEN"] = "Text needed here",
        ["TOGGLE_VISIBILITY_COMBAT"] = "Text needed here",
        ["COORDINATES"] = "Coordinates:",
        ["EXPANDED"] = "Expanded",
    },
    -- ["frFR"] ptBR etc
}

L = L[GetLocale()] or L["enUS"]

-- the internal frames provided by Blizzard go up to index 19. They reference Enum.EditModeSystem, which starts from index 0
local STARTING_INDEX = 0
for _ in pairs(Enum.EditModeSystem) do
    STARTING_INDEX = STARTING_INDEX + 1
end
local nextSystemIDIndex = STARTING_INDEX
local frames = lib.frames or {}
lib.frames = frames
local baseFramesDB = lib.baseFramesDB or {} -- the base db that includes all profiles inside
lib.baseFramesDB = baseFramesDB
local framesDB = lib.framesDB or {} -- the currently selected db inside the profile
lib.framesDB = framesDB
local framesDialogs = lib.framesDialogs or {}
lib.framesDialogs = framesDialogs
local framesDialogsKeys = lib.framesDialogsKeys or {}
lib.framesDialogsKeys = framesDialogsKeys
local existingFrames = lib.exitingFrames or {} -- frames already part of Edit Mode where we are adding more options
lib.existingFrames = existingFrames
local enteringCombat = InCombatLockdown()

local ENUM_EDITMODEACTIONBARSETTING_HIDEABLE = 10 -- Enum.EditModeActionBarSetting.Hideable = 10
local ENUM_EDITMODEACTIONBARSETTING_MINIMAPPINNED = 11
local ENUM_EDITMODEACTIONBARSETTING_CUSTOM = 12
local ENUM_EDITMODEACTIONBARSETTING_CLAMPED = 13
local ENUM_EDITMODEACTIONBARSETTING_TOGGLEHIDEINCOMBAT = 14
local ENUM_EDITMODEACTIONBARSETTING_BUTTON = 15
local ENUM_EDITMODEACTIONBARSETTING_FRAMESIZE = 16 -- Enum.EditModeUnitFrameSetting.FrameSize
local ENUM_EDITMODEACTIONBARSETTING_DROPDOWN = 17
local ENUM_EDITMODEACTIONBARSETTING_SLIDER = 18
local ENUM_EDITMODEACTIONBARSETTING_COORDINATES = 19
local ENUM_EDITMODEACTIONBARSETTING_HIDDENUNTILMOUSEOVER = 20

-- run OnLoad the first time RegisterFrame is called by an addon
local f = lib.internalOnLoadFrame or {}
lib.internalOnLoadFrame = f
function f.OnLoad() f.OnLoad = nil end

-- some caching tables, save the state of frames just before entering Edit Mode
local wasVisible = {}
local originalSize = {}
local defaultSize = {}

local profilesInitialised
local previousProfileNames = {}

-- Custom version of FrameXML\Mixin.lua where I instead do *not* overwrite existing functions 
local function Mixin(object, ...)
    for i = 1, select("#", ...) do
        local mixin = select(i, ...);
        for k, v in pairs(mixin) do
            if not object[k] then
                -- 11.1: bugfix - need to not include AddSnappedFrame as this spreads taint and causes errors
                if k ~= "AddSnappedFrame" then
                    object[k] = v;
                end
            end
        end
    end

    return object;
end

-- functions declared further down
local pinToMinimap
local unpinFromMinimap
local getOffsetXY
local registerFrameMovableWithArrowKeys
local refreshCurrentProfile
local runOutOfCombat

local function getSystemID(frame)
    if not frame.system then return false end
    if frame.system < STARTING_INDEX then
        return frame.EMESystemID
    end
    return frame.system
end

setmetatable(framesDB, {
    __newindex = function(t, k, v)
        rawset(t, k, v)
        if type(v) ~= "table" then return end
        if not v.settings then
            rawset(v, "settings", {})
        end
    end,
    -- Eliminate need for calls like
    --     if not framesDB[systemID] then framesDB[systemID] = {} end
    __index = function(t, k)
        rawset(t, k, {settings={}})
        return t[k]
    end,
})

setmetatable(framesDialogs, {
    __index = function(t, k)
        rawset(t, k, {})
        return t[k]
    end,
})

setmetatable(framesDialogsKeys, {
    -- if not framesDialogsKeys[systemID] then framesDialogsKeys[systemID] = {} end
    __index = function(t, k)
        rawset(t, k, {})
        return t[k]
    end,
})

-- archived from EditModeSystemTemplates.lua
local EditModeSystemSelectionLayout =
{
	["TopRightCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x=8, y=8 },
	["TopLeftCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x=-8, y=8 },
	["BottomLeftCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x=-8, y=-8 },
	["BottomRightCorner"] = { atlas = "%s-NineSlice-Corner",  mirrorLayout = true, x=8, y=-8 },
	["TopEdge"] = { atlas = "_%s-NineSlice-EdgeTop" },
	["BottomEdge"] = { atlas = "_%s-NineSlice-EdgeBottom" },
	["LeftEdge"] = { atlas = "!%s-NineSlice-EdgeLeft" },
	["RightEdge"] = { atlas = "!%s-NineSlice-EdgeRight" },
	["Center"] = { atlas = "%s-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8, },
};

--
-- Public API
--

-- Call this on a frame to register it for capture during Edit Mode
-- param1: frame, the Frame to register
-- param2: name, localized name to appear when the frame is selected during Edit Mode
-- param3: db, a table in your saved variables to save the frame position in
-- param4: frame to anchor to, default is UIParent
-- param5: point to anchor, default is BOTTOMLEFT
-- param6: whether to enable "clamped to screen". default is TRUE
function lib:RegisterFrame(frame, name, db, anchorTo, anchorPoint, clamped)
    assert(type(frame) == "table")
    assert(type(name) == "string")
    assert(type(db) == "table")
    
    if frame:IsUserPlaced() then
        if frame:IsMovable() or frame:IsResizable() then
            frame:SetUserPlaced(false)
        end
    end
    
    if not anchorTo then anchorTo = UIParent end
    if not anchorPoint then anchorPoint = "BOTTOMLEFT" end
    frame.EMEanchorTo = anchorTo
    frame.EMEanchorPoint = anchorPoint
    
    if clamped == nil then clamped = true end
    
    -- if this is the first frame being registered, load the other parts of this library
    if f.OnLoad then f.OnLoad() end
    
    local baseDB = db
    
    -- If the frame was already registered (perhaps by another addon that uses this library), don't register it again
    for _, registeredFrame in ipairs(frames) do
        if frame == registeredFrame then
            if (not framesDB[frame.system].x) and (not framesDB[frame.system].y) then
                -- import new db settings if there are none saved in the existing db
                framesDB[frame.system].x = db.x
                framesDB[frame.system].y = db.y
                local x, y = getOffsetXY(frame, db.x, db.y)
                frame:SetPoint(anchorPoint, anchorTo, anchorPoint, x, y)
            end
            return
        end
    end
    
    local systemID = frame.system
    
    -- frame is an existing Edit Mode frame by Blizzard, handle it differently
    if systemID then
        if existingFrames[frame:GetName()] then return end
        existingFrames[frame:GetName()] = true
        
        systemID = nextSystemIDIndex
        nextSystemIDIndex = nextSystemIDIndex + 1
        frame.EMESystemID = systemID
        baseFramesDB[systemID] = baseDB
        framesDB[systemID] = db
        hooksecurefunc(frame, "SelectSystem", function()
            if framesDialogs[systemID] then
                EditModeExpandedSystemSettingsDialog:AttachToSystemFrame(frame)
            end
        end)

        frame.Selection:HookScript("OnDragStop", function(self)
            EditModeExpandedSystemSettingsDialog:UpdateSettings(frame)
            if frame:IsUserPlaced() then
                frame:SetUserPlaced(false)
            end
        end)
        
        return
    end
    
    if profilesInitialised then
        local layoutInfo = EditModeManagerFrame:GetActiveLayoutInfo()
        local profileName = layoutInfo.layoutType.."-"..layoutInfo.layoutName
        if layoutInfo.layoutType == Enum.EditModeLayoutType.Character then
            local unitName, unitRealm = UnitFullName("player")
            -- See https://github.com/teelolws/EditModeExpanded/issues/201
            -- Despite the docs, it seems unitRealm can still sometimes be nil
            if unitName and unitRealm then
                profileName = layoutInfo.layoutType.."-"..unitName.."-"..unitRealm.."-"..layoutInfo.layoutName
            end
        end
        
        if not db.profiles then db.profiles = {} end
        if not db.profiles[profileName] then
            db.profiles[profileName] = {}
            db.profiles[profileName].x = db.x
            db.profiles[profileName].y = db.y
            db.profiles[profileName].enabled = db.enabled
            db.profiles[profileName].settings = db.settings
            db.profiles[profileName].defaultX = db.defaultX
            db.profiles[profileName].defaultY = db.defaultY
            
            db.x = nil
            db.y = nil
            db.enabled = nil
            db.settings = nil
        end
        
        db = db.profiles[profileName]
    end
     
    table.insert(frames, frame)
    
    Mixin(frame, EditModeSystemMixin)
    
    frame.BreakFrameSnap = function() end
    frame.SnapToFrame = function() end
    
    function frame:HighlightSystem()
    	if self.isDragging then
    		self:OnDragStop();
    	end

    	self:SetMovable(false);
    	--self:AnchorSelectionFrame();
    	self.Selection:ShowHighlighted();
    	self.isHighlighted = true;
    	self.isSelected = false;
    	--self:UpdateMagnetismRegistration();
    end
    
    frame.system = nextSystemIDIndex
    nextSystemIDIndex = nextSystemIDIndex + 1
    baseFramesDB[frame.system] = baseDB 
    framesDB[frame.system] = db

    db.defaultScale = frame:GetScale()
    db.defaultX, db.defaultY = frame:GetRect()
    
    -- needs investigation: why does this frame behave 'weirdly' if default scale 1 is not set?
    if frame == FocusFrameSpellBar then
        if not db.settings[ENUM_EDITMODEACTIONBARSETTING_FRAMESIZE] then
            db.settings[ENUM_EDITMODEACTIONBARSETTING_FRAMESIZE] = 100
        end
    end

    frame.Selection = CreateFrame("Frame", nil, frame, "EditModeSystemSelectionTemplate")
    frame.Selection.CheckShowInstructionalTooltip = nop
    frame.Selection:SetAllPoints(frame)
    frame.defaultHideSelection = true
    frame.Selection:Hide()
    
    function frame.Selection:ShowHighlighted()
    	if self.textureShown ~= "highlight" then
    		NineSliceUtil.ApplyLayout(self, EditModeSystemSelectionLayout, self.highlightTextureKit);
    		self.textureShown = "highlight";
    	end
    	self.isSelected = false;
    	--self:UpdateLabelVisibility();
    	self:Show();
    end

    function frame.Selection:ShowSelected()
    	if self.textureShown ~= "selected" then
    		NineSliceUtil.ApplyLayout(self, EditModeSystemSelectionLayout, self.selectedTextureKit);
    		self.textureShown = "selected";
    	end
    	self.isSelected = true;
    	--self:UpdateLabelVisibility();
    	--self:CheckShowInstructionalTooltip();
    	self:Show();
    end
    
    frame.Selection.UpdateLabelVisibility = nop
    
    frame.systemNameString = name
    
    frame.Selection:SetSystem(frame)
    
    frame:SetupSettingsDialogAnchor();
    
    --frame.snappedFrames = {}; -- this was spreading taint, need to check for the absence causing errors
    registerFrameMovableWithArrowKeys(frame)
    
    -- prevent the frame from going outside the screen boundaries
    if db.clamped == nil then db.clamped = (clamped and 1 or 0) end
    if profilesInitialised and (db.clamped == 1) then
        frame:SetClampedToScreen(true)
    elseif profilesInitialised then
        frame:SetClampedToScreen(false)
    end
    framesDialogsKeys[frame.system][ENUM_EDITMODEACTIONBARSETTING_CLAMPED] = clamped
    table.insert(framesDialogs[frame.system],
        {
            setting = ENUM_EDITMODEACTIONBARSETTING_CLAMPED,
            name = L["CLAMP_TO_SCREEN"],
            type = Enum.EditModeSettingDisplayType.Checkbox,
        }
    )
    
    frame.UpdateMagnetismRegistration = nop

    frame.Selection:SetScript("OnMouseDown", function()
        frame:SelectSystem()
    end)
    
    function frame:SelectSystem()
        if not self.isSelected then
            self:SetMovable(true);
            self.Selection:ShowSelected();
            self.isSelected = true;
            if framesDialogs[self.system] then
                EditModeManagerFrame:ClearSelectedSystem()  -- needs further taint testing; disable if there are issues
                EditModeExpandedSystemSettingsDialog:AttachToSystemFrame(self)
            else
                EditModeExpandedSystemSettingsDialog:Hide()
            end
        end
        
        for _, frame2 in ipairs(frames) do
            if frame2 ~= frame then
                frame2:HighlightSystem()
            end
        end
        lib.selectedFrame = frame
    end
    
    frame.Selection:SetScript("OnDragStop", function(self)
        if frame:CanBeMoved() then
            frame:StopMovingOrSizing();
        end
        local profiledb = framesDB[frame.system]
        profiledb.x, profiledb.y = self:GetRect()
        
        local x, y, isSecret = getOffsetXY(frame, profiledb.x, profiledb.y)
        if not isSecret then
            frame:ClearAllPoints()
            frame:SetPoint(frame.EMEanchorPoint, frame.EMEanchorTo, frame.EMEanchorPoint, x, y)
        end
        
        EditModeExpandedSystemSettingsDialog:UpdateSettings(frame)
        
        if (not issecretvalue(frame:IsUserPlaced())) and frame:IsUserPlaced() then
            frame:SetUserPlaced(false)
        end
    end)
    
    function frame:ClearHighlight()
        if self.isSelected then
            self.isSelected = false;
        end
    
        self.Selection:Hide();
        self.isHighlighted = false;
    end
    
    function frame:SetHasActiveChanges(hasActiveChanges)
        self.hasActiveChanges = hasActiveChanges;
    end

    local scrollChild = EditModeManagerExpandedFrame.AccountSettings:GetScrollChild()
    scrollChild[frame.system] = CreateFrame("Frame", nil, scrollChild, "ResizeCheckButtonTemplate")
    local checkButtonFrame = scrollChild[frame.system]
    frame.EMECheckButtonFrame = checkButtonFrame.Button
    checkButtonFrame.layoutIndex = EditModeManagerExpandedFrame.AccountSettings.nextLayoutIndex
    EditModeManagerExpandedFrame.AccountSettings.nextLayoutIndex = EditModeManagerExpandedFrame.AccountSettings.nextLayoutIndex + 1
    checkButtonFrame.fixedWidth = 225
    checkButtonFrame.fixedHeight = 32
    
    local resetButton = CreateFrame("Button", nil, checkButtonFrame, "UIPanelButtonTemplate")
    frame.EMEResetButton = resetButton
    resetButton.ignoreInLayout = true
    resetButton:SetText(RESET)
    resetButton:SetPoint("TOPLEFT", checkButtonFrame.Label, "TOPRIGHT", 5, 2)
    resetButton:SetScript("OnClick", function()
        local profiledb = framesDB[frame.system]
        frame:ClearAllPoints()
        frame:SetClampedToScreen(true)

        if not profiledb.defaultX then profiledb.defaultX = 0 end
        if not profiledb.defaultY then profiledb.defaultY = 0 end
        local x, y = getOffsetXY(frame, profiledb.defaultX, profiledb.defaultY)
        if not pcall( function() frame:SetPoint(frame.EMEanchorPoint, frame.EMEanchorTo, frame.EMEanchorPoint, x, y) end ) then
            -- need a better solution here
            frame:SetPoint("BOTTOMLEFT", nil, "BOTTOMLEFT", x, y)
        end
        
        profiledb.clamped = true
        profiledb.x = profiledb.defaultX
        profiledb.y = profiledb.defaultY
        frame:SetScaleOverride(profiledb.defaultScale)
        profiledb.settings[ENUM_EDITMODEACTIONBARSETTING_FRAMESIZE] = profiledb.defaultScale * 100
        EditModeExpandedSystemSettingsDialog:Hide()
        frame:HighlightSystem()
        
        profiledb.settings[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] = 0
    end)
    
    EditModeManagerExpandedFrame:HookScript("OnHide", function()
        resetButton:Hide()
    end)
    
    EditModeManagerExpandedFrame:HookScript("OnShow", function()
        if resetButton.hiddenByGrouping then return end
        resetButton:Show()
    end)
    
    checkButtonFrame.Button:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked()
        framesDB[frame.system].enabled = isChecked
        frame:SetShown(isChecked)
    end)
    
    checkButtonFrame.Label:SetText(name)
    checkButtonFrame.Label:SetFontObject(GameFontHighlightMedium)
    
    if db.enabled == nil then db.enabled = true end
    checkButtonFrame.Button:SetChecked(db.enabled)
    
    function frame:GetSettingValue(setting)
        local profiledb = framesDB[frame.system]
        if (not self:IsInitialized()) or (not profiledb.settings) or (not profiledb.settings[setting]) then
            return 0;
        end
        return profiledb.settings[setting]
    end
    
    function frame:SetScaleOverride(newScale)
        local oldScale = self:GetScale();
    
        self:SetScale(newScale);
    
        if oldScale == newScale then
            return;
        end
    
        -- Update position to try and keep the system frame in the same position since scale changes how offsets work
        local numPoints = self:GetNumPoints();
        if not issecretvalue(numPoints) then
            for i = 1, numPoints do
                local point, relativeTo, relativePoint, offsetX, offsetY = self:GetPoint(i);
        
                -- Undo old scale adjustment so we're working with 1.0 scale offsets
                -- Then apply the newScale adjustment
                offsetX = offsetX * oldScale / newScale;
                offsetY = offsetY * oldScale / newScale;
                self:SetPoint(point, relativeTo, relativePoint, offsetX, offsetY);
            end
        end
    end
    
    if db.x and db.y then
        if (frame:GetScale() == 1) and (anchorTo == UIParent) and (anchorPoint == "TOPLEFT") then
            -- if stored coordinates are outside the screen resolution, reset them back to defaults
            local _, _, screenX, screenY = UIParent:GetRect()
            if (db.x < 0) or (db.x >= screenX) or (db.y < 0) or (db.y > screenY) then
                db.x, db.y = frame:GetRect()
            end
        end 
        frame:ClearAllPoints()
        local x, y = getOffsetXY(frame, db.x, db.y)
        frame:SetPoint(anchorPoint, anchorTo, anchorPoint, x, y)
    else
        db.x, db.y = frame:GetRect()
    end
    
    if db.settings and (db.settings[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] ~= nil) then
        frame:SetShown(framesDB[frame.system].settings[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] ~= 1)
    end
    
    hooksecurefunc(frame, "AddExtraButtons", function(self)
        self.resetToDefaultPositionButton:SetOnClickHandler(function()
            resetButton:Click()
        end)
    end)
end

-- use this if a frame by default doesn't have a size set yet
function lib:SetDefaultSize(frame, x, y)
    assert(type(frame) == "table")
    assert(type(x) == "number")
    assert(type(y) == "number")
    
    defaultSize[frame.system] = {["x"] = x, ["y"] = y}
end

-- use this for small frames - frames that have a dimension < 40, that you don't want to be bumped up to 40 during Edit Mode
function lib:SetDontResize(frame)
    assert(type(frame) == "table")
    
    frame.EMEDontResize = true
end

-- call this if the frame needs to be moved back into position at some point after ADDON_LOADED
function lib:RepositionFrame(frame)
    assert(type(frame) == "table")
    assert(frame.system > 12)
    
    local systemID = getSystemID(frame)
    local db = framesDB[systemID]
    
    if (not (db.x or db.defaultX)) or (not (db.y or db.defaultY)) or (not frame.EMEanchorTo) or (not frame.EMEanchorTo:GetRect()) then
        return
    end
    
    frame:ClearAllPoints()
    
    local dialogs = framesDialogsKeys[systemID]
    
    if (not EditModeManagerFrame.editModeActive) and dialogs[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] then
        if dialogs[ENUM_EDITMODEACTIONBARSETTING_TOGGLEHIDEINCOMBAT] then
            if (db.settings[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] == 1) and (db.settings[ENUM_EDITMODEACTIONBARSETTING_TOGGLEHIDEINCOMBAT] == 1) and (enteringCombat or InCombatLockdown()) then
                frame:Show()
            elseif (db.settings[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] == 1) and (db.settings[ENUM_EDITMODEACTIONBARSETTING_TOGGLEHIDEINCOMBAT] ~= 1) then
                frame:Hide()
                return
            elseif (db.settings[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] == 1) and (db.settings[ENUM_EDITMODEACTIONBARSETTING_TOGGLEHIDEINCOMBAT] == 1) and (not (enteringCombat or InCombatLockdown())) then
                frame:Hide()
                return
            elseif (db.settings[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] ~= 1) and (db.settings[ENUM_EDITMODEACTIONBARSETTING_TOGGLEHIDEINCOMBAT] == 1) and (enteringCombat or InCombatLockdown()) then
                frame:Hide()
                return
            elseif (db.settings[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] ~= 1) and (db.settings[ENUM_EDITMODEACTIONBARSETTING_TOGGLEHIDEINCOMBAT] == 1) and (not (enteringCombat or InCombatLockdown())) then
                frame:Show()
            elseif (db.settings[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] ~= 1) and (db.settings[ENUM_EDITMODEACTIONBARSETTING_TOGGLEHIDEINCOMBAT] ~= 1) then
                frame:Show()
            end
        else
            if db.settings[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] == 1 then
                frame:Hide()
                if frame.EMEOnEventHandler then
                    frame:SetScript("OnEvent", nil)
                end
                return
            end
        end
    end
    
    local x, y = getOffsetXY(frame, db.x or db.defaultX, db.y or db.defaultY)
    local anchorPoint = frame.EMEanchorPoint
    if not pcall( function() frame:SetPoint(anchorPoint, frame.EMEanchorTo, anchorPoint, x, y) end ) then
        frame:SetPoint(anchorPoint, nil, anchorPoint, x, y)
    end
end

-- Call this to change what the frame is anchored to
-- Its position will remain the same
function lib:ReanchorFrame(frame, anchorTo, anchorPoint)
    assert(type(frame) == "table")
    assert(type(anchorTo) == "table")
    assert(type(anchorPoint == "string"))
    
    frame.EMEanchorTo = anchorTo
    frame.EMEanchorPoint = anchorPoint
    
    local x, y = frame:GetRect()
    if not (x and y) then return end
    
    x, y = getOffsetXY(frame, frame:GetRect())
    
    frame:ClearAllPoints()
    frame:SetPoint(anchorPoint, anchorTo, anchorPoint, x, y)
end

-- Call this to add a slider to the frames dialog box, allowing it to be resized using frame:SetScale
-- param1: an edit mode registered frame, either one already registered by Blizz, or a custom one you have registered with lib:RegisterFrame
-- param2: minimum size, default will be 10
-- param3: maximum size, default will be 200
-- param3: step size, default will be 5
function lib:RegisterResizable(frame, minSize, maxSize, step)
    minSize = minSize or 10
    maxSize = maxSize or 200
    step = step or 5
    local systemID = getSystemID(frame)
    
    if framesDialogsKeys[systemID][ENUM_EDITMODEACTIONBARSETTING_FRAMESIZE] then return end
    framesDialogsKeys[systemID][ENUM_EDITMODEACTIONBARSETTING_FRAMESIZE] = true
    table.insert(framesDialogs[systemID],
        {
            setting = ENUM_EDITMODEACTIONBARSETTING_FRAMESIZE,
            name = HUD_EDIT_MODE_SETTING_UNIT_FRAME_FRAME_SIZE,
            type = Enum.EditModeSettingDisplayType.Slider,
            minValue = minSize,
            maxValue = maxSize,
            stepSize = step,
        })
    
    local db = framesDB[systemID]
    if db.settings and db.settings[ENUM_EDITMODEACTIONBARSETTING_FRAMESIZE] then
        frame:SetScaleOverride(db.settings[ENUM_EDITMODEACTIONBARSETTING_FRAMESIZE]/100)
    end
    
    if db.x and db.y then 
        if frame.system >= STARTING_INDEX then
            -- only reposition if its a custom frame - frames handled by base edit mode already correctly deal with scaling
            if (frame:GetScale() == 1) and (frame.EMEanchorTo == UIParent) and (frame.EMEanchorPoint == "TOPLEFT") then
                local _, _, screenX, screenY = UIParent:GetRect()
                if (db.x < 0) or (db.x >= screenX) or (db.y < 0) or (db.y > screenY) then
                    db.x, db.y = frame:GetRect()
                end
            end
            frame:ClearAllPoints()
            local x, y = getOffsetXY(frame, db.x, db.y)
            frame:SetPoint(frame.EMEanchorPoint, frame.EMEanchorTo, frame.EMEanchorPoint, x, y)
        end
    else
        db.x, db.y = frame:GetRect()
    end
end

function lib:UpdateFrameResize(frame)
    local systemID = getSystemID(frame)
    local db = framesDB[systemID]
    
    if not framesDialogsKeys[systemID][ENUM_EDITMODEACTIONBARSETTING_FRAMESIZE] then return end
    
    if db.settings[ENUM_EDITMODEACTIONBARSETTING_FRAMESIZE] ~= nil then
        frame:SetScale(db.settings[ENUM_EDITMODEACTIONBARSETTING_FRAMESIZE]/100)
    end
end
 
-- Call this to add a checkbox to the frames dialog box, allowing the frame to be permanently hidden outside of Edit Mode
-- param1: an edit mode registered frame, either one already registered by Blizz, or a custom one you have registered with lib:RegisterFrame
-- onEventHandler: optional function that is called when an event is fired for this frame, while it is shown. This will replace any existing event handlers, so it is useful to disable events on frames while it is hidden, and re-enable them while it is shown.
function lib:RegisterHideable(frame, onEventHandler)
    local systemID = getSystemID(frame)
    
    if framesDialogsKeys[systemID][ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] then return end
    framesDialogsKeys[systemID][ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] = true
    table.insert(framesDialogs[systemID],
        {
            setting = ENUM_EDITMODEACTIONBARSETTING_HIDEABLE,
            name = HIDE,
            type = Enum.EditModeSettingDisplayType.Checkbox,
    })
    
    frame.EMEOnEventHandler = onEventHandler
end

-- Call this to find out if the user has marked the frame hidden by their lib:RegisterHideable setting
function lib:IsFrameMarkedHidden(frame)
    local systemID = getSystemID(frame)
    
    local settings = framesDB[systemID].settings 
    
    if framesDialogsKeys[systemID][ENUM_EDITMODEACTIONBARSETTING_HIDDENINCOMBAT] and (settings[ENUM_EDITMODEACTIONBARSETTING_HIDDENINCOMBAT] == 1) then
        if settings[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] == 1 then
            return not InCombatLockdown()
        else
            return InCombatLockdown()
        end
    end
    return settings[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] == 1
end

-- implemented further down the file
-- param1: custom system frame
--function lib:RegisterMinimapPinnable(frame)

-- a simple check of "has this frame been registered with EME" - maybe you want to test if another addon registered it already?
function lib:IsRegistered(frame)
    local systemID = getSystemID(frame)
    if not systemID or not framesDB[systemID] then return false end
    
    return true
end

-- Is the Expanded frame checkbox checked for this frame, making it visible during Edit Mode?
function lib:IsFrameEnabled(frame)
    local db = framesDB[frame.system]
    return db.enabled
end

local customCheckboxCallDuringProfileInit = {}
-- call this to register a custom checkbox where you're providing the handler
-- internalName is a name to use in the database to identify this checkbox
-- for backwards compatibility, internalName defaults to "1"
-- returns: function that can be called to reset this back to default
function lib:RegisterCustomCheckbox(frame, name, onChecked, onUnchecked, internalName)
    if not internalName then
        internalName = 1
    end
    
    local systemID = getSystemID(frame)
    
    if not framesDialogsKeys[systemID][ENUM_EDITMODEACTIONBARSETTING_CUSTOM] then framesDialogsKeys[systemID][ENUM_EDITMODEACTIONBARSETTING_CUSTOM] = {} end 
    framesDialogsKeys[systemID][ENUM_EDITMODEACTIONBARSETTING_CUSTOM][internalName] = true
    
    table.insert(framesDialogs[systemID],
        {
            setting = ENUM_EDITMODEACTIONBARSETTING_CUSTOM,
            name = name,
            type = Enum.EditModeSettingDisplayType.Checkbox,
            onChecked = onChecked,
            onUnchecked = onUnchecked,
            customCheckBoxID = internalName,
    })
    
    local function callLater()
        local db = framesDB[systemID]
        if not db.settings[ENUM_EDITMODEACTIONBARSETTING_CUSTOM] then db.settings[ENUM_EDITMODEACTIONBARSETTING_CUSTOM] = {} end
        
        -- backward compatibility
        if type(db.settings[ENUM_EDITMODEACTIONBARSETTING_CUSTOM]) == "number" then
            local old = db.settings[ENUM_EDITMODEACTIONBARSETTING_CUSTOM]
            db.settings[ENUM_EDITMODEACTIONBARSETTING_CUSTOM] = {}
            db.settings[ENUM_EDITMODEACTIONBARSETTING_CUSTOM][internalName] = old
        end
        
        if db.settings[ENUM_EDITMODEACTIONBARSETTING_CUSTOM][internalName] == 1 then
            onChecked()
        else
            onUnchecked(true)
        end
    end
    
    if profilesInitialised then
        callLater()
    else
        table.insert(customCheckboxCallDuringProfileInit, callLater)
    end

    RunNextFrame(function() EventRegistry:RegisterFrameEventAndCallback("EDIT_MODE_LAYOUTS_UPDATED", callLater) end)
    
    return function()
        local db = framesDB[systemID]
        if not db.settings[ENUM_EDITMODEACTIONBARSETTING_CUSTOM] then db.settings[ENUM_EDITMODEACTIONBARSETTING_CUSTOM] = {} end
        db.settings[ENUM_EDITMODEACTIONBARSETTING_CUSTOM][internalName] = 0
    end
end

local extraDialogItems = {}
-- call this to register a custom button
-- the button will not save any settings
function lib:RegisterCustomButton(frame, name, onClick, internalName)
    local systemID = getSystemID(frame)
    
    local button = CreateFrame("Button", nil, EditModeExpandedSystemSettingsDialog.Settings, "UIPanelButtonTemplate,ResizeLayoutFrame")
    button.SetupSetting = nop
    button:SetScript("OnClick", onClick)
    button.Text:SetText(name)
    
    table.insert(framesDialogs[systemID],
        {
            setting = ENUM_EDITMODEACTIONBARSETTING_BUTTON,
            type = ENUM_EDITMODEACTIONBARSETTING_BUTTON,
            name = name,
            settingFrame = button,
        }
    )
    
    table.insert(extraDialogItems, button)
    
    local function getCurrentDB()
        local db = framesDB[getSystemID(frame)]
        if not db.settings[ENUM_EDITMODEACTIONBARSETTING_BUTTON] then db.settings[ENUM_EDITMODEACTIONBARSETTING_BUTTON] = {} end
        if not db.settings[ENUM_EDITMODEACTIONBARSETTING_BUTTON][internalName] then db.settings[ENUM_EDITMODEACTIONBARSETTING_BUTTON][internalName] = {} end
        
        return db.settings[ENUM_EDITMODEACTIONBARSETTING_BUTTON][internalName]
    end
    
    return getCurrentDB
end

-- call this to register a frame to have its position specified by the user using screen coordinates
function lib:RegisterCoordinates(frame)
    local systemID = getSystemID(frame)
    
    for _, settings in pairs(framesDialogs[systemID]) do
        if settings.type == ENUM_EDITMODEACTIONBARSETTING_COORDINATES then
            return
        end
    end
    
    local coordinatePanel = CreateFrame("Frame", nil, EditModeExpandedSystemSettingsDialog.Settings, "HorizontalLayoutFrame")
    coordinatePanel.widthPadding = 15
    coordinatePanel.fixedHeight = 28
    coordinatePanel.SetupSetting = nop
    coordinatePanel.spacing = 20
    table.insert(extraDialogItems, coordinatePanel)
    
    coordinatePanel.label = coordinatePanel:CreateFontString(nil, nil, "GameTooltipText")
    local label = coordinatePanel.label
    label.layoutIndex = 1
    label:SetText(L["COORDINATES"])
    
    coordinatePanel.xEditBox = CreateFrame("EditBox", nil, coordinatePanel, "InputBoxTemplate")
    local xEditBox = coordinatePanel.xEditBox
    xEditBox.layoutIndex = 2
    xEditBox.topPadding = -5
    xEditBox:SetSize(30, 20)
    xEditBox:SetNumeric(true)
    xEditBox:SetAutoFocus(false)
    
    coordinatePanel.yEditBox = CreateFrame("EditBox", nil, coordinatePanel, "InputBoxTemplate")
    local yEditBox = coordinatePanel.yEditBox
    yEditBox.layoutIndex = 3
    yEditBox.topPadding = -5
    yEditBox:SetSize(30, 20)
    yEditBox:SetNumeric(true)
    yEditBox:SetAutoFocus(false)
    
    local function onEnterPressed()
        local db = framesDB[getSystemID(frame)]
        local x, y = tonumber(xEditBox:GetText()), tonumber(yEditBox:GetText())
        if (type(x) ~= "number") or (type(y) ~= "number") then return end
        
        if frame.EMESystemID then
            -- Frame is a base UI frame already handled by Edit Mode
            -- So we need to store the new coordinates into the Edit Mode profile
            frame:ClearAllPoints()
            frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
            frame:SetUserPlaced(true)
            --EditModeSystemSettingsDialog:UpdateSettings(frame)
            EditModeManagerFrame:OnSystemPositionChange(frame)
        else
            db.x, db.y = x, y
            frame.EMEanchorTo = UIParent
            frame.EMEanchorPoint = "BOTTOMLEFT"
            
            frame:ClearAllPoints()
            frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
            
            if frame:IsUserPlaced() then
                frame:SetUserPlaced(false)
            end
        end
    end
    
    xEditBox:SetScript("OnEnterPressed", onEnterPressed)
    yEditBox:SetScript("OnEnterPressed", onEnterPressed)
    
    xEditBox:SetScript("OnTabPressed", function()
        yEditBox:SetFocus()
    end)
    yEditBox:SetScript("OnTabPressed", function()
        xEditBox:SetFocus()
    end)
    
    table.insert(framesDialogs[systemID],
        {
            setting = ENUM_EDITMODEACTIONBARSETTING_COORDINATES,
            type = ENUM_EDITMODEACTIONBARSETTING_COORDINATES,
            settingFrame = coordinatePanel,
        }
    )
end

-- call this to register a custom dropdown menu
-- requirement: must have LibUIDropDownMenu installed
-- @param1: frame - parent frame to create a dropdown about
-- @param2: libUIDropDownMenu - an instance of LibUIDropDownMenu obtained from LibStub:GetLibrary("LibUIDropDownMenu")
-- @param3: internalName - a name used in the database to identify this dropdown
-- @return1: the dropdown created by LibUIDropDownMenu, for you to call UIDropDownMenu_Initialize on
-- @return2: a function that returns a table for you to save/retrieve settings from, based on the currently selected profile
function lib:RegisterDropdown(frame, libUIDropDownMenu, internalName)
    local systemID = getSystemID(frame)
    local layoutFrame = CreateFrame("Frame", nil, EditModeExpandedSystemSettingsDialog.Settings, "ResizeLayoutFrame")
    layoutFrame.SetupSetting = nop
    local dropdown = libUIDropDownMenu:Create_UIDropDownMenu(nil, layoutFrame)
    layoutFrame.dropdown = dropdown
    dropdown:SetPoint("TOPLEFT", layoutFrame, "TOPLEFT")
    
    if not framesDialogsKeys[systemID][ENUM_EDITMODEACTIONBARSETTING_DROPDOWN] then framesDialogsKeys[systemID][ENUM_EDITMODEACTIONBARSETTING_DROPDOWN] = {} end 
    framesDialogsKeys[systemID][ENUM_EDITMODEACTIONBARSETTING_DROPDOWN][internalName] = true
    
    table.insert(framesDialogs[systemID],
        {
            setting = ENUM_EDITMODEACTIONBARSETTING_DROPDOWN,
			type = Enum.EditModeSettingDisplayType.Dropdown,
            settingFrame = layoutFrame,
        }
    )
    
    table.insert(extraDialogItems, layoutFrame)
    
    local function getCurrentDB()
        local db = framesDB[getSystemID(frame)]
        if not db.settings[ENUM_EDITMODEACTIONBARSETTING_DROPDOWN] then db.settings[ENUM_EDITMODEACTIONBARSETTING_DROPDOWN] = {} end
        if not db.settings[ENUM_EDITMODEACTIONBARSETTING_DROPDOWN][internalName] then db.settings[ENUM_EDITMODEACTIONBARSETTING_DROPDOWN][internalName] = {} end
        
        return db.settings[ENUM_EDITMODEACTIONBARSETTING_DROPDOWN][internalName]
    end
    
    return dropdown, getCurrentDB
end

-- register a custom slider
function lib:RegisterSlider(frame, name, internalName, onChanged, min, max, step)
    local systemID = getSystemID(frame)
    
    if not framesDialogsKeys[systemID][ENUM_EDITMODEACTIONBARSETTING_SLIDER] then framesDialogsKeys[systemID][ENUM_EDITMODEACTIONBARSETTING_SLIDER] = {} end
    framesDialogsKeys[systemID][ENUM_EDITMODEACTIONBARSETTING_SLIDER][internalName] = true
    
    table.insert(framesDialogs[systemID],
        {
            setting = ENUM_EDITMODEACTIONBARSETTING_SLIDER,
            name = name,
            type = Enum.EditModeSettingDisplayType.Slider,
            onChanged = onChanged,
            minValue = min,
            maxValue = max,
            stepSize = step,
            internalName = internalName,
        }
    )
        
    local function callLater()
        local db = framesDB[systemID]
        if not db.settings[ENUM_EDITMODEACTIONBARSETTING_SLIDER] then db.settings[ENUM_EDITMODEACTIONBARSETTING_SLIDER] = {} end
        
        if db.settings[ENUM_EDITMODEACTIONBARSETTING_SLIDER][internalName] ~= nil then
            onChanged(db.settings[ENUM_EDITMODEACTIONBARSETTING_SLIDER][internalName])
        end
    end
    
    if profilesInitialised then
        callLater()
    else
        table.insert(customCheckboxCallDuringProfileInit, callLater)
    end
end

--
-- Code for Expanded Manager Frame here
-- This is a frame that will show checkboxes, to turn on/off all custom frames during Edit Mode
--

local function clearSelectedSystem(_, systemFrame)
    -- Only highlight a system if it was already highlighted
    if systemFrame.isHighlighted then
        systemFrame:HighlightSystem();
    end
end

hooksecurefunc(f, "OnLoad", function()
    -- this will stop the handlers being called more than once if multiple versions of this library exist
    -- will only work from version 97 onward, implemented just before expansion Midnight
    f.hookScriptWrappers = f.hookScriptWrappers or {}
    local function hookScriptWrapper(frame, event, hookfunc)
        f.hookScriptWrappers[frame] = f.hookScriptWrappers[frame] or {}
        f.hookScriptWrappers[frame][event] = f.hookScriptWrappers[frame][event] or {}
        wipe(f.hookScriptWrappers[frame][event])
        f.hookScriptWrappers[frame][event][MINOR] = hookfunc
        frame:HookScript(event, function(...)
            if f.hookScriptWrappers[frame][event][MINOR] then
                f.hookScriptWrappers[frame][event][MINOR](...)
            end
        end)
    end
    
    f.hooksecurefuncWrappers = f.hooksecurefuncWrappers or {}
    local function hooksecurefuncWrapper(frame, functionName, hookfunc)
        f.hooksecurefuncWrappers[frame] = f.hooksecurefuncWrappers[frame] or {}
        f.hooksecurefuncWrappers[frame][functionName] = f.hooksecurefuncWrappers[frame][functionName] or {}
        wipe(f.hooksecurefuncWrappers[frame][functionName])
        f.hooksecurefuncWrappers[frame][functionName][MINOR] = hookfunc
        hooksecurefunc(frame, functionName, function(...)
            if f.hooksecurefuncWrappers[frame][functionName][MINOR] then
                f.hooksecurefuncWrappers[frame][functionName][MINOR](...)
            end
        end)
    end
    
    if not EditModeManagerExpandedFrame then
        CreateFrame("Frame", "EditModeManagerExpandedFrame", UIParent, "VerticalLayoutFrame")
    elseif not EditModeManagerExpandedFrame.Layout then
        -- workaround for bug prior to v108
        -- remove this in a future update when older versions of this library no longer work
        for _, frame in pairs(frames) do
            if frame.EMEResetButton and (frame.EMEResetButton:GetParent() == EditModeManagerFrame) then
                frame.EMEResetButton:SetParent(UIParent)
                frame.EMEResetButton:ClearAllPoints()
                frame.EMEResetButton:Hide()
            end
        end
        
        -- backward compatibility: expanded frame was created by an older version of the library before vertical layout template was added
        Mixin(EditModeManagerExpandedFrame, LayoutMixin, VerticalLayoutMixin)
    end
    EditModeManagerExpandedFrame:Hide();
    
    -- Cannot parent it to EditModeManagerFrame, as I'd have to set a "ignoreInLayout" value, which would then spread taint
    EditModeManagerExpandedFrame:SetFrameStrata("DIALOG")
    
    EditModeManagerExpandedFrame:ClearAllPoints()
    EditModeManagerExpandedFrame:SetPoint("TOPLEFT", EditModeManagerFrame, "BOTTOMLEFT", 0, -2)
    EditModeManagerExpandedFrame:SetPoint("TOPRIGHT", EditModeManagerFrame, "BOTTOMRIGHT", 0, -2)
    EditModeManagerExpandedFrame.spacing = -5
    
    EditModeManagerExpandedFrame.Expander = EditModeManagerExpandedFrame.Expander or CreateFrame("Frame", nil, EditModeManagerExpandedFrame, "ResizeLayoutFrame")
    EditModeManagerExpandedFrame.Expander.layoutIndex = 3
    EditModeManagerExpandedFrame.Expander.heightPadding = 8
    EditModeManagerExpandedFrame.Expander.align = "center"
    
    EditModeManagerExpandedFrame.Expander.Divider = EditModeManagerExpandedFrame.Expander.Divider or EditModeManagerExpandedFrame.Expander:CreateTexture(nil, "ARTWORK")
    EditModeManagerExpandedFrame.Expander.Divider:SetTexture("Interface\\FriendsFrame\\UI-FriendsFrame-OnlineDivider")
    EditModeManagerExpandedFrame.Expander.Divider:SetSize(330, 16)
    EditModeManagerExpandedFrame.Expander.Divider:SetPoint("TOP")
    
    EditModeManagerExpandedFrame.Expander.Label = EditModeManagerExpandedFrame.Expander.Label or EditModeManagerExpandedFrame.Expander:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    EditModeManagerExpandedFrame.Expander.Label:SetText(HUD_EDIT_MODE_EXPAND_OPTIONS)
    EditModeManagerExpandedFrame.Expander.Label:SetPoint("TOP", EditModeManagerExpandedFrame.Expander.Divider, "BOTTOM", 0, 5)
    EditModeManagerExpandedFrame.Expander:SetScript("OnMouseUp", function()
        local expanded = not EditModeManagerExpandedFrame.AccountSettings:IsShown()
        EditModeManagerExpandedFrame.AccountSettings:SetShown(expanded)
        EditModeManagerExpandedFrame.Expander.Label:SetText(expanded and HUD_EDIT_MODE_COLLAPSE_OPTIONS or HUD_EDIT_MODE_EXPAND_OPTIONS);
        EditModeManagerExpandedFrame:Layout()
    end)
    
    EditModeManagerExpandedFrame.Title = EditModeManagerExpandedFrame.Title or EditModeManagerExpandedFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    EditModeManagerExpandedFrame.Title:SetText(L["EXPANDED"])
    EditModeManagerExpandedFrame.Title.layoutIndex = 1
    EditModeManagerExpandedFrame.Title.align = "center"
    EditModeManagerExpandedFrame.Title.topPadding = 15
    EditModeManagerExpandedFrame.Title.bottomPadding = 8
    
    EditModeManagerExpandedFrame.Border = EditModeManagerExpandedFrame.Border or CreateFrame("Frame", nil, EditModeManagerExpandedFrame, "DialogBorderTranslucentTemplate")
    EditModeManagerExpandedFrame.Border.ignoreInLayout = true
    
    EditModeManagerExpandedFrame.CloseButton = EditModeManagerExpandedFrame.CloseButton or CreateFrame("Button", nil, EditModeManagerExpandedFrame, "UIPanelCloseButton")
    EditModeManagerExpandedFrame.CloseButton:SetPoint("TOPRIGHT")
    EditModeManagerExpandedFrame.CloseButton.ignoreInLayout = true

    if EditModeManagerExpandedFrame.AccountSettings then
        if not EditModeManagerExpandedFrame.AccountSettings.ScrollChild then
            -- backward compatibility: old version of the library exists
            EditModeManagerExpandedFrame.AccountSettings:Hide()
            EditModeManagerExpandedFrame.AccountSettings:SetParent(UIParent)
            EditModeManagerExpandedFrame.AccountSettings = CreateFrame("ScrollFrame", nil, EditModeManagerExpandedFrame, "ResizeLayoutFrame, ScrollFrameTemplate")
        end
    else
        EditModeManagerExpandedFrame.AccountSettings = CreateFrame("ScrollFrame", nil, EditModeManagerExpandedFrame, "ResizeLayoutFrame, ScrollFrameTemplate")
    end
    EditModeManagerExpandedFrame.AccountSettings.layoutIndex = 2
    EditModeManagerExpandedFrame.AccountSettings.fixedWidth = 470
    EditModeManagerExpandedFrame.AccountSettings.maximumHeight = 195
    EditModeManagerExpandedFrame.AccountSettings.leftPadding = 20
	EditModeManagerExpandedFrame.AccountSettings.ScrollBar:SetHideIfUnscrollable(true)
	EditModeManagerExpandedFrame.AccountSettings.ScrollBar:SetPoint("TOPLEFT", EditModeManagerExpandedFrame.AccountSettings, "TOPRIGHT", -15, -5)
	EditModeManagerExpandedFrame.AccountSettings.ScrollBar:SetPoint("BOTTOMLEFT", EditModeManagerExpandedFrame.AccountSettings, "BOTTOMRIGHT", -15, SCROLL_FRAME_SCROLL_BAR_OFFSET_BOTTOM)
    EditModeManagerExpandedFrame.AccountSettings:Hide()
    EditModeManagerExpandedFrame.AccountSettings.nextLayoutIndex = EditModeManagerExpandedFrame.AccountSettings.nextLayoutIndex or 1
    
    EditModeManagerExpandedFrame.AccountSettings.ScrollChild = EditModeManagerExpandedFrame.AccountSettings.ScrollChild or CreateFrame("Frame", nil, EditModeManagerExpandedFrame.AccountSettings, "GridLayoutFrame")
    EditModeManagerExpandedFrame.AccountSettings.ScrollChild:SetSize(1, 1)
    EditModeManagerExpandedFrame.AccountSettings.ScrollChild:SetPoint("TOPLEFT")
    EditModeManagerExpandedFrame.AccountSettings.ScrollChild.childXPadding = 0
    EditModeManagerExpandedFrame.AccountSettings.ScrollChild.childYPadding = 0
    EditModeManagerExpandedFrame.AccountSettings.ScrollChild.isHorizontal = true
    EditModeManagerExpandedFrame.AccountSettings.ScrollChild.stride = 2
    EditModeManagerExpandedFrame.AccountSettings.ScrollChild.layoutFramesGoingRight = true
    EditModeManagerExpandedFrame.AccountSettings.ScrollChild.layoutFramesGoingUp = false
    EditModeManagerExpandedFrame.AccountSettings.ScrollChild.alwaysUpdateLayout = true
    EditModeManagerExpandedFrame.AccountSettings:SetScrollChild(EditModeManagerExpandedFrame.AccountSettings.ScrollChild)

    
    hookScriptWrapper(EditModeManagerFrame, "OnShow", function()
        EditModeManagerExpandedFrame:Show()
        EditModeManagerExpandedFrame:Layout()
    end)
    
    hookScriptWrapper(EditModeManagerFrame, "OnHide", function()
        EditModeManagerExpandedFrame:Hide()
    end)
    
    function EditModeManagerExpandedFrame:ClearSelectedSystem()
        secureexecuterange(frames, clearSelectedSystem)
        EditModeExpandedSystemSettingsDialog:Hide()
        lib.selectedFrame = nil
    end

    hooksecurefuncWrapper(EditModeManagerFrame, "EnterEditMode", function(self)
        -- can cause errors if the player is in combat - eg trying to move or show/hide protected frames
        if InCombatLockdown() then return end
        if not EditModeManagerExpandedFrame then return end -- happens if library is embedded but nothing has been registered
        
        if #frames <= 0 then EditModeManagerExpandedFrame:Hide() end
        for _, frame in ipairs(frames) do
            frame:SetHasActiveChanges(false)
            frame:HighlightSystem();
            wasVisible[frame.system] = frame:IsShown()
            frame:SetShown(framesDB[frame.system].enabled)
            local x, y = frame:GetSize()
            if (not (issecretvalue(x) or issecretvalue(y))) and (not frame.EMEDontResize) and ((x < 40) or (y < 40)) then
                originalSize[frame.system] = {["x"] = x, ["y"] = y}
                if defaultSize[frame.system] then
                    frame:SetSize(defaultSize[frame.system].x, defaultSize[frame.system].y)
                elseif (x < 40) and (y > 0) then
                    frame:SetSize(40, y)
                elseif (x > 0) and (y < 40) then
                    frame:SetSize(x, 40)
                else
                    frame:SetSize(40, 40)
                end
            end
        end
        
        for frameName in pairs(existingFrames) do
            local frame = _G[frameName]
            local systemID = getSystemID(frame)
            if framesDB[systemID] and framesDB[systemID].settings and (framesDB[systemID].settings[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] ~= nil) then
                if (framesDB[systemID].settings[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] == 1) then
                    frame:Show()
                    if frame.EMEOnEventHandler then
                        frame:SetScript("OnEvent", frame.EMEOnEventHandler)
                    end
                end
            end
        end
    end)

    hooksecurefuncWrapper(EditModeManagerFrame, "ExitEditMode", function(self)
        if InCombatLockdown() then
            print("EditModeExpanded Error: could not hide Edit Mode properly - you were in combat!")
            return
        end
        if not EditModeManagerExpandedFrame then return end -- happens if library is embedded but nothing has been registered
        
        for _, frame in ipairs(frames) do
            frame:ClearHighlight();
            frame:StopMovingOrSizing();
            
            if framesDB[frame.system] and framesDB[frame.system].settings and (framesDB[frame.system].settings[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] ~= nil) then
                if (framesDB[frame.system].settings[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] == 1) then
                    frame:Hide()
                    if frame.EMEOnEventHandler then
                        frame:SetScript("OnEvent", nil)
                    end
                else
                    frame:SetShown(wasVisible[frame.system])
                end
            else
                frame:SetShown(wasVisible[frame.system])
            end
            
            if originalSize[frame.system] then
                frame:SetSize(originalSize[frame.system].x, originalSize[frame.system].y)
            end
        end
        
        for frameName in pairs(existingFrames) do
            local frame = _G[frameName]
            local systemID = getSystemID(frame)
            if framesDB[systemID] and framesDB[systemID].settings and (framesDB[systemID].settings[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] ~= nil) then
                if (framesDB[systemID].settings[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] == 1) then
                    frame:Hide()
                    if frame.EMEOnEventHandler then
                        frame:SetScript("OnEvent", nil)
                    end
                end
            end
        end
        
        wipe(wasVisible)
        wipe(originalSize)
        EditModeExpandedSystemSettingsDialog:Hide()
    end)

    hooksecurefuncWrapper(EditModeManagerFrame, "SelectSystem", function(self, systemFrame)
        lib.selectedFrame = systemFrame
        if EditModeExpandedSystemSettingsDialog and EditModeExpandedSystemSettingsDialog.attachedToSystem ~= systemFrame then
            EditModeExpandedSystemSettingsDialog:Hide()
        end
        
        if InCombatLockdown() then return end
        
        for _, frame in ipairs(frames) do
            if systemFrame ~= frame then
                frame:HighlightSystem()
            end
        end
    end)
    
    hooksecurefuncWrapper(EditModeManagerFrame, "ClearSelectedSystem", function()
        lib.selectedFrame = nil
    end)
    
    hooksecurefuncWrapper(EditModeManagerFrame, "MakeNewLayout", function(self, _, layoutType, layoutName)
        if InCombatLockdown() then return end
        local oldProfileName = previousProfileNames[2]
        if not oldProfileName then
            oldProfileName = previousProfileNames[1]
            if not oldProfileName then return end
        end
        
        local newProfileName = layoutType.."-"..layoutName
        if layoutType == Enum.EditModeLayoutType.Character then
            local unitName, unitRealm = UnitFullName("player")
            newProfileName = layoutType.."-"..unitName.."-"..unitRealm.."-"..layoutName
        end
        
        if oldProfileName == newProfileName then return end

        for _, allFrames in pairs({frames, existingFrames}) do
            for name, frame in pairs(allFrames) do
                if type(frame) == "boolean" then
                    frame = _G[name]
                end
                local systemID = frame.EMESystemID or frame.system
                local db = baseFramesDB[systemID]
                
                if db.profiles[oldProfileName] then
                    db.profiles[newProfileName] = CopyTable(db.profiles[oldProfileName])
                end
            end
        end
        
        refreshCurrentProfile() 
    end)

    --
    -- Edit Mode Dialog Box code
    --
    local emeDialog = EditModeExpandedSystemSettingsDialog or CreateFrame("Frame", "EditModeExpandedSystemSettingsDialog", UIParent, "ResizeLayoutFrame")
    Mixin(emeDialog, EditModeSystemSettingsDialogMixin)
    emeDialog:SetMovable(true)
    emeDialog:SetClampedToScreen(true)
    emeDialog:EnableMouse(true)
    emeDialog:RegisterForDrag("LeftButton")
    emeDialog:SetDontSavePosition(true)
    emeDialog:SetFrameStrata("DIALOG")
    emeDialog:SetFrameLevel(200)
    emeDialog:Hide()
    emeDialog:SetSize(300, 350)
    emeDialog:SetPoint("TOPLEFT")
    emeDialog.widthPadding = 40
    emeDialog.heightPadding = 10
    emeDialog.Title = emeDialog.Title or emeDialog:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    emeDialog.Title:SetPoint("TOP", 0, -15)
    emeDialog.Border = emeDialog.Border or CreateFrame("Frame", nil, emeDialog, "DialogBorderTranslucentTemplate")
    emeDialog.Border.ignoreInLayout = true
    emeDialog.CloseButton = emeDialog.CloseButton or CreateFrame("Button", nil, emeDialog, "UIPanelCloseButton")
    emeDialog.CloseButton.ignoreInLayout = true
    emeDialog.CloseButton:SetPoint("TOPRIGHT")
    emeDialog.Settings = emeDialog.Settings or CreateFrame("Frame", nil, emeDialog, "VerticalLayoutFrame")
    emeDialog.Settings:SetSize(1, 1)
    emeDialog.Settings.spacing = 2
    emeDialog.Settings:SetPoint("TOP", emeDialog.Title, "BOTTOM", 0, -12)
    emeDialog.Buttons = emeDialog.Buttons or CreateFrame("Frame", nil, emeDialog, "VerticalLayoutFrame")
    emeDialog.Buttons.spacing = 2
    emeDialog.Buttons:SetPoint("TOPLEFT", emeDialog.Settings, "BOTTOMLEFT", 0, -12)
    emeDialog.Buttons.RevertChangesButton = emeDialog.Buttons.RevertChangesButton or CreateFrame("Button", nil, emeDialog.Buttons, "EditModeSystemSettingsDialogButtonTemplate")
    emeDialog.Buttons.RevertChangesButton:SetText(HUD_EDIT_MODE_REVERT_CHANGES)
    emeDialog.Buttons.RevertChangesButton.layoutIndex = 1
    emeDialog.Buttons.Divider = emeDialog.Buttons:CreateTexture(nil, "ARTWORK")
    emeDialog.Buttons.Divider:SetMask("Interface/FriendsFrame/UI-FriendsFrame-OnlineDivider")
    emeDialog.Buttons.Divider:Hide()
    emeDialog.Buttons.Divider:SetSize(330, 16)
    emeDialog.Buttons.Divider.layoutIndex = 2
    emeDialog:SetScript("OnLoad", emeDialog.OnLoad)
    emeDialog:SetScript("OnHide", emeDialog.OnHide)
    emeDialog:SetScript("OnDragStart", emeDialog.OnDragStart)
    emeDialog:SetScript("OnDragStop", emeDialog.OnDragStop)
    emeDialog:OnLoad()
    function emeDialog:UpdateSizeAndAnchors(systemFrame)
        if systemFrame == self.attachedToSystem then
            self:ClearAllPoints()
            self:SetPoint("TOP", EditModeSystemSettingsDialog, "BOTTOM")
            self:Layout()
        else
            self:Hide()
        end
    end
    
    -- hide the duplicate buttons we won't ever need
    emeDialog.Buttons.RevertChangesButton:Hide()
    function emeDialog:UpdateExtraButtons(systemFrame) -- from EditModeDialogs.lua function EditModeSystemSettingsDialogMixin:UpdateExtraButtons
        if systemFrame == self.attachedToSystem then
            self.pools:ReleaseAllByTemplate("EditModeSystemSettingsDialogExtraButtonTemplate");
            self.Buttons.Divider:SetShown(true)
        end
    end
    
    -- Add the option to hide the highlight textures
    local scrollChild = EditModeManagerExpandedFrame.AccountSettings:GetScrollChild()
    if scrollChild.disableHighlightTexturesOption then return end
    scrollChild.disableHighlightTexturesOption = CreateFrame("Frame", nil, scrollChild, "ResizeCheckButtonTemplate")
    local checkButtonFrame = scrollChild.disableHighlightTexturesOption
    checkButtonFrame.layoutIndex = EditModeManagerExpandedFrame.AccountSettings.nextLayoutIndex
    EditModeManagerExpandedFrame.AccountSettings.nextLayoutIndex = EditModeManagerExpandedFrame.AccountSettings.nextLayoutIndex + 1
    checkButtonFrame.fixedWidth = 225
    checkButtonFrame.fixedHeight = 32
    
    checkButtonFrame.Button:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked()
        local sides = {
        	"TopRightCorner",
        	"TopLeftCorner",
        	"BottomLeftCorner",
        	"BottomRightCorner",
        	"TopEdge",
        	"BottomEdge",
        	"LeftEdge",
        	"RightEdge",
        	"Center",
        }
                                   
        for _, frame in pairs(frames) do
            local selection = frame.Selection
            for _, side in pairs(sides) do
                selection[side]:SetShown(not isChecked)
            end
        end
        
        for frame in pairs(existingFrames) do
            local selection = _G[frame].Selection
            for _, side in pairs(sides) do
                if selection[side] then
                    selection[side]:SetShown(not isChecked)
                end
            end
        end
    end)
    
    checkButtonFrame.Label:SetText(DISABLE.." "..string.gsub(HIGHLIGHTING, ":", ""))
    checkButtonFrame.Label:SetFontObject(GameFontHighlightMedium)
    checkButtonFrame:SetSize(32, 32)
end)

local function hideFrameUntilMouseover(frame)
    local handler = frame.EMESecureHandlerEnterLeave
    if not handler then
        frame.EMESecureHandlerEnterLeave = CreateFrame("Frame", nil, nil, "SecureHandlerEnterLeaveTemplate")
        handler = frame.EMESecureHandlerEnterLeave
        --handler:SetPoint("TOPLEFT", frame, "TOPLEFT")
        --handler:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
        
        local function updateHandlerPosition()
            local point, relativeTo, relativePoint = frame:GetPoint()
            if (point == "TOPRIGHT") and (relativeTo == UIParent) and (relativePoint == "BOTTOMLEFT") then return end
            
            local x = frame:GetLeft()
            local y = frame:GetBottom()
            local scale = UIParent:GetScale()
            x = x * scale
            y = y * scale
            handler:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
            x = frame:GetWidth()
            y = frame:GetHeight()
            x = x * scale
            y = y * scale
            handler:SetSize(x, y)
        end
        hooksecurefunc(frame, "SetPoint", updateHandlerPosition)
        updateHandlerPosition()
        
        handler:SetFrameRef("parent", frame)
        handler:SetFrameRef("uiparent", UIParent)
        handler:SetFrameStrata("TOOLTIP")
        handler:EnableMouse(false)
        handler:EnableMouseMotion(true)
        handler:SetPropagateMouseMotion(true)
    end
    
    handler:SetAttribute("_onenter", [[
            local parent = self:GetFrameRef('parent')
            parent:ClearAllPoints()
            parent:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT")
        ]])
    handler:SetAttribute("_onleave", [[
            local uiparent = self:GetFrameRef("uiparent")
            local parent = self:GetFrameRef('parent')
            parent:ClearAllPoints()
            parent:SetPoint("TOPRIGHT", uiparent, "BOTTOMLEFT")
            
        ]])
    frame:ClearAllPoints()
    frame:SetClampedToScreen(false)
    frame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT")
end

local function pauseHideFrameUntilMouseover(frame)
    local handler = frame.EMESecureHandlerEnterLeave
    if not handler then return end
    
    handler:SetAttribute("_onenter", "")
    handler:SetAttribute("_onleave", "")
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", handler, "BOTTOMLEFT")
end

hooksecurefunc(f, "OnLoad", function()
    function EditModeExpandedSystemSettingsDialog:UpdateSettings(systemFrame)
        if systemFrame == self.attachedToSystem then
            self:ReleaseAllNonSliders();
            local draggingSlider = self:ReleaseNonDraggingSliders();
            
            for _, frame in pairs(extraDialogItems) do
                frame.layoutIndex = nil
                frame:Hide()
            end
            
            local settingsToSetup = {};
            local systemID = getSystemID(self.attachedToSystem)
            
            local systemSettingDisplayInfo = framesDialogs[systemID];
            if systemSettingDisplayInfo and (#systemSettingDisplayInfo > 0) then
                for index, displayInfo in ipairs(systemSettingDisplayInfo) do
                    local settingPool = self:GetSettingPool(displayInfo.type);
                    local settingFrame
                    
                    if settingPool then
                        if draggingSlider and draggingSlider.setting == displayInfo.setting then
                            settingFrame = draggingSlider
                        else
                            settingFrame = settingPool:Acquire()
                        end
                    else
                        settingFrame = displayInfo.settingFrame
                    end
                    
                    if settingFrame then
                        settingFrame:SetPoint("TOPLEFT");
                        settingFrame.layoutIndex = index;
                        
                        local settingName = displayInfo.name
                        local updatedDisplayInfo = self.attachedToSystem:UpdateDisplayInfoOptions(displayInfo);
                        if not framesDB[systemID].settings then framesDB[systemID].settings = {} end
                          
                        local savedValue = framesDB[systemID].settings[updatedDisplayInfo.setting]
                        
                        if displayInfo.setting == ENUM_EDITMODEACTIONBARSETTING_FRAMESIZE then
                            savedValue = savedValue or 100
                            
                            CallbackRegistryMixin.OnLoad(settingFrame)
                
                          	local function OnValueChanged(self, value)
                                if not self.initInProgress then
                                    EditModeExpandedSystemSettingsDialog:OnSettingValueChanged(self.setting, value);
                                end
                            end
                              
                            settingFrame.cbrHandles = EventUtil.CreateCallbackHandleContainer()
                          	settingFrame.cbrHandles:RegisterCallback(settingFrame.Slider, MinimalSliderWithSteppersMixin.Event.OnValueChanged, OnValueChanged, settingFrame)
                        end
                        
                        if displayInfo.setting == ENUM_EDITMODEACTIONBARSETTING_SLIDER then
                            if not framesDB[systemID].settings[displayInfo.setting] then framesDB[systemID].settings[displayInfo.setting] = {} end
                            savedValue = framesDB[systemID].settings[displayInfo.setting][displayInfo.internalName]
                            if savedValue == nil then savedValue = 100 end
                            CallbackRegistryMixin.OnLoad(settingFrame)
                            local function OnValueChanged(self, value)
                                if not self.initInProgress then
                                    EditModeExpandedSystemSettingsDialog:OnSettingValueChanged(self.setting, value, displayInfo.internalName, displayInfo.onChanged);
                                end
                            end
                              
                            settingFrame.cbrHandles = EventUtil.CreateCallbackHandleContainer()
                          	settingFrame.cbrHandles:RegisterCallback(settingFrame.Slider, MinimalSliderWithSteppersMixin.Event.OnValueChanged, OnValueChanged, settingFrame)
                        end
                        
                        if displayInfo.setting == ENUM_EDITMODEACTIONBARSETTING_HIDEABLE then
                            savedValue = framesDB[systemID].settings[displayInfo.setting]
                            if savedValue == nil then savedValue = 0 end
                            settingFrame.Button:SetChecked(savedValue)
                            settingFrame.Button:SetScript("OnClick", function()
                                local frame = EditModeExpandedSystemSettingsDialog.attachedToSystem
                                if settingFrame.Button:GetChecked() then
                                    framesDB[systemID].settings[displayInfo.setting] = 1
                                    frame:Hide()
                                    if frame.EMEOnEventHandler then
                                        frame:SetScript("OnEvent", nil)
                                    end
                                    wasVisible[systemID] = false
                                else
                                    framesDB[systemID].settings[displayInfo.setting] = 0
                                    frame:Show()
                                    if frame.EMEOnEventHandler then
                                        frame:SetScript("OnEvent", frame.EMEOnEventHandler)
                                    end
                                    wasVisible[systemID] = true
                                end
                            end)
                        end
                        
                        if displayInfo.setting == ENUM_EDITMODEACTIONBARSETTING_MINIMAPPINNED then
                            savedValue = framesDB[systemID].settings[displayInfo.setting]
                            if savedValue == nil then savedValue = 0 end
                            settingFrame.Button:SetChecked(savedValue)
                            settingFrame.Button:SetScript("OnClick", function()
                                if settingFrame.Button:GetChecked() then
                                    framesDB[systemID].settings[displayInfo.setting] = 1
                                    pinToMinimap(EditModeExpandedSystemSettingsDialog.attachedToSystem)
                                else
                                    framesDB[systemID].settings[displayInfo.setting] = 0
                                    unpinFromMinimap(EditModeExpandedSystemSettingsDialog.attachedToSystem)
                                end
                            end)
                        end
                        
                        if displayInfo.setting == ENUM_EDITMODEACTIONBARSETTING_CUSTOM then
                            if not framesDB[systemID].settings[displayInfo.setting] then framesDB[systemID].settings[displayInfo.setting] = {} end
                            savedValue = framesDB[systemID].settings[displayInfo.setting][displayInfo.customCheckBoxID]
                            if savedValue == nil then savedValue = 0 end
                            settingFrame.Button:SetChecked(savedValue)
                            settingFrame.Button:SetScript("OnClick", function()
                                if settingFrame.Button:GetChecked() then
                                    framesDB[systemID].settings[displayInfo.setting][displayInfo.customCheckBoxID] = 1
                                    displayInfo.onChecked()
                                else
                                    framesDB[systemID].settings[displayInfo.setting][displayInfo.customCheckBoxID] = 0
                                    displayInfo.onUnchecked(false)
                                end
                            end)
                        end
                        
                        if displayInfo.setting == ENUM_EDITMODEACTIONBARSETTING_BUTTON then
                            settingFrame.widthPadding = 15
                            settingFrame.fixedHeight = 28
                        end
                        
                        if displayInfo.setting == ENUM_EDITMODEACTIONBARSETTING_DROPDOWN then
                            settingFrame.widthPadding = 15
                            settingFrame.fixedHeight = 28
                        end
                        
                        if displayInfo.setting == ENUM_EDITMODEACTIONBARSETTING_CLAMPED then
                            savedValue = framesDB[systemID].clamped
                            if savedValue == nil then savedValue = 1 end
                            settingFrame.Button:SetChecked(savedValue)
                            settingFrame.Button:SetScript("OnClick", function()
                                if settingFrame.Button:GetChecked() then
                                    framesDB[systemID].clamped = 1
                                    systemFrame:SetClampedToScreen(true)
                                else
                                    framesDB[systemID].clamped = 0
                                    systemFrame:SetClampedToScreen(false)
                                end
                            end)
                        end
                        
                        if displayInfo.setting == ENUM_EDITMODEACTIONBARSETTING_TOGGLEHIDEINCOMBAT then
                            savedValue = framesDB[systemID].settings[displayInfo.setting]
                            if savedValue == nil then savedValue = 0 end
                            settingFrame.Button:SetChecked(savedValue)
                            settingFrame.Button:SetScript("OnClick", function()
                                if settingFrame.Button:GetChecked() then
                                    framesDB[systemID].settings[displayInfo.setting] = 1
                                else
                                    framesDB[systemID].settings[displayInfo.setting] = 0
                                end
                            end)
                        end
                        
                        if displayInfo.setting == ENUM_EDITMODEACTIONBARSETTING_HIDDENUNTILMOUSEOVER then
                            savedValue = framesDB[systemID].settings[displayInfo.setting]
                            if savedValue == nil then savedValue = 0 end
                            settingFrame.Button:SetChecked(savedValue)
                            settingFrame.Button:SetScript("OnClick", function()
                                if settingFrame.Button:GetChecked() then
                                    framesDB[systemID].settings[displayInfo.setting] = 1
                                    hideFrameUntilMouseover(systemFrame)
                                else
                                    framesDB[systemID].settings[displayInfo.setting] = 0
                                    pauseHideFrameUntilMouseover(systemFrame)
                                end
                            end)
                        end
                        
                        if type(settingName) == "function" then
                            settingName = settingName()
                        end
                        settingsToSetup[settingFrame] = { displayInfo = updatedDisplayInfo, currentValue = savedValue, settingName = settingName }
                        settingFrame:Show();
                    end
                end
        
                self.Buttons:ClearAllPoints();
        
                if not next(settingsToSetup) then
                    self.Settings:Hide();
                    self.Buttons:SetPoint("TOP", self.Title, "BOTTOM", 0, -12);
                else
                    self.Settings:Show();
                    self.Settings:SetSize(1,1)
                    self.Settings:Layout();
                    for settingFrame, settingData in pairs(settingsToSetup) do
                        settingFrame:SetupSetting(settingData);
                    end
                    self.Buttons:SetPoint("TOPLEFT", self.Settings, "BOTTOMLEFT", 0, -12);
                end
            else
                self.attachedToSystem = nil
                EditModeExpandedSystemSettingsDialog:Hide()
            end
        end
    end
end)

hooksecurefunc(f, "OnLoad", function()
    function EditModeExpandedSystemSettingsDialog:GetSettingPool(settingType)
        -- EditModesettingDropdownTemplate not usable due to spreading taint
        -- Use LibUIDropDownMenu instead and avoid frame pools (cannot use custom templates in a library)
        --if settingType == Enum.EditModeSettingDisplayType.Dropdown then
        --    return self.pools:GetPool("EditModeSettingDropdownTemplate");
        --else
        if settingType == Enum.EditModeSettingDisplayType.Slider then
            return self.pools:GetPool("EditModeSettingSliderTemplate")
        elseif settingType == Enum.ChrCustomizationOptionType.Checkbox then
            return self.pools:GetPool("EditModeSettingCheckboxTemplate");
        end
    end

    function EditModeExpandedSystemSettingsDialog:ReleaseNonDraggingSliders()
        local draggingSlider;
        local releaseSliders = {};

        for settingSlider in self.pools:EnumerateActiveByTemplate("EditModeSettingSliderTemplate") do
            if settingSlider.Slider.Slider:IsDraggingThumb() then
                draggingSlider = settingSlider;
            else
                table.insert(releaseSliders, settingSlider);
            end
        end

        for _, releaseSlider in ipairs(releaseSliders) do
            releaseSlider.Slider:Release();
            self.pools:Release(releaseSlider);
        end

        return draggingSlider;
    end
    
    function EditModeExpandedSystemSettingsDialog:OnSettingValueChanged(setting, value, internalName, onChanged)
        local attachedToSystem = self.attachedToSystem
        if attachedToSystem then
            local db = framesDB[getSystemID(attachedToSystem)]
            if setting == ENUM_EDITMODEACTIONBARSETTING_FRAMESIZE then
                db.settings[setting] = value
                attachedToSystem:SetScaleOverride(value/100)
                db.x, db.y = attachedToSystem:GetRect()
            elseif setting == ENUM_EDITMODEACTIONBARSETTING_SLIDER then
                if not db.settings[setting] then db.settings[setting] = {} end
                db.settings[setting][internalName] = value
                onChanged(value)
            end
        end
    end
    
    function EditModeExpandedSystemSettingsDialog:OnLoad()
        local function onCloseCallback()
            if not EditModeSystemSettingsDialog:IsShown() then
                EditModeManagerExpandedFrame:ClearSelectedSystem()
            else
                EditModeExpandedSystemSettingsDialog:Hide()
            end
        end
    
        self.Buttons.RevertChangesButton:SetOnClickHandler(GenerateClosure(self.RevertChanges, self));
    
        self.onCloseCallback = onCloseCallback;
    
        self.pools = CreateFramePoolCollection();
        --self.pools:CreatePool("FRAME", self.Settings, "EditModeSettingDropdownTemplate") -- trying to use dropdowns causes taint issues, probably because of long-running taint issues with dropdowns in general
        self.pools:CreatePool("FRAME", self.Settings, "EditModeSettingSliderTemplate");
        self.pools:CreatePool("FRAME", self.Settings, "EditModeSettingCheckboxTemplate");
    
        local function resetExtraButton(pool, button)
            FramePool_HideAndClearAnchors(pool, button);
            button:Enable();
        end
        self.pools:CreatePool("BUTTON", self.Buttons, "EditModeSystemSettingsDialogExtraButtonTemplate", resetExtraButton);
    end
    EditModeExpandedSystemSettingsDialog:OnLoad()
end)

--
-- Profile handling
--
function refreshCurrentProfile()
    local layoutInfo = EditModeManagerFrame:GetActiveLayoutInfo()
    local profileName = layoutInfo.layoutType.."-"..layoutInfo.layoutName
    if layoutInfo.layoutType == Enum.EditModeLayoutType.Character then
        local unitName, unitRealm = UnitFullName("player")
        profileName = layoutInfo.layoutType.."-"..unitName.."-"..unitRealm.."-"..layoutInfo.layoutName
    end
    
    if not previousProfileNames[1] then
        previousProfileNames[1] = profileName
    elseif previousProfileNames[1] == profileName then
        nop()
    else
        previousProfileNames[2] = previousProfileNames[1]
        previousProfileNames[1] = profileName
    end
    
    for _, allFrames in pairs({frames, existingFrames}) do
        for name, frame in pairs(allFrames) do
            if type(frame) == "boolean" then
                frame = _G[name]
            end
            EditModeExpandedSystemSettingsDialog:Hide()
            local systemID = frame.EMESystemID or frame.system
            local db = baseFramesDB[systemID]
            
            if not db.profiles then db.profiles = {} end
            if not db.profiles[profileName] then
                db.profiles[profileName] = {}
                db.profiles[profileName].x = db.x
                db.profiles[profileName].y = db.y
                if frame.EMEdisabledByDefault then
                    db.profiles[profileName].enabled = false
                else
                    db.profiles[profileName].enabled = db.enabled
                end
                db.profiles[profileName].settings = db.settings
                db.profiles[profileName].defaultX = db.defaultX
                db.profiles[profileName].defaultY = db.defaultY
                
                db.x = nil
                db.y = nil
                db.enabled = nil
                db.settings = nil
                db.clamped = nil
            end
            
            if db.minimap then
                db.profiles[profileName].minimap = db.minimap
                db.minimap = nil
            end
            
            db = db.profiles[profileName]
            framesDB[systemID] = db
            
            runOutOfCombat(function()
                if not db.settings then db.settings = {} end
            
                -- frame hide option
                if framesDialogsKeys[systemID][ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] and (db.settings[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] ~= nil) then
                    if frame ~= TalkingHeadFrame then
                        frame:SetShown(framesDB[systemID].settings[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] ~= 1)
                        if frame.EMEOnEventHandler then
                            if frame:IsShown() then
                                frame:SetScript("OnEvent", frame.EMEOnEventHandler)
                            else
                                frame:SetScript("OnEvent", nil)
                            end
                        end
                    end
                end
                    
                -- update scale
                if framesDialogsKeys[systemID][ENUM_EDITMODEACTIONBARSETTING_FRAMESIZE] and db.settings[ENUM_EDITMODEACTIONBARSETTING_FRAMESIZE] then
                    frame:SetScaleOverride(db.settings[ENUM_EDITMODEACTIONBARSETTING_FRAMESIZE]/100)
                end
                
                if not frame.EMESystemID then
                    
                    -- update position
                    frame:ClearAllPoints()
                    local anchorPoint = frame.EMEanchorPoint
                    if db.x and db.y then
                        local x, y = getOffsetXY(frame, db.x, db.y)
                        frame:SetPoint(anchorPoint, frame.EMEanchorTo, anchorPoint, x, y)
                    else
                        if db.defaultX and db.defaultY then
                            local x, y = getOffsetXY(frame, db.defaultX, db.defaultY)
                            if not pcall( function() frame:SetPoint(anchorPoint, frame.EMEanchorTo, anchorPoint, x, y) end ) then
                                frame:SetPoint(anchorPoint, nil, anchorPoint, x, y)
                            end
                        end
                    end
                
                    -- minimap pinning
                    if framesDialogsKeys[systemID][ENUM_EDITMODEACTIONBARSETTING_MINIMAPPINNED] then
                        if db.settings and (db.settings[ENUM_EDITMODEACTIONBARSETTING_MINIMAPPINNED] ~= nil) then
                            if db.settings[ENUM_EDITMODEACTIONBARSETTING_MINIMAPPINNED] == 1 then
                                pinToMinimap(frame)
                            else
                                unpinFromMinimap(frame)
                            end
                        end
                    end
                    
                    -- the option in the expanded frame
                    if frame.EMEdisabledByDefault then
                        db.enabled = false
                    end
                    if db.enabled == nil then
                        db.enabled = true
                    end
                    frame.EMECheckButtonFrame:SetChecked(db.enabled)
                    
                    -- only way I can find to un-select frames
                    if EditModeManagerFrame.editModeActive and frame:IsShown() then
                        frame:HighlightSystem()
                    end
                    
                    if db.clamped == 1 then
                        frame:SetClampedToScreen(true)
                    else
                        frame:SetClampedToScreen(false)
                    end
                end
                
            end)
        end
        
        for _, func in pairs(customCheckboxCallDuringProfileInit) do
            func()
        end
    end
end


do
    local initialLayout
    initialLayout = function()
        if EditModeManagerFrame:GetActiveLayoutInfo() then
            profilesInitialised = true
            refreshCurrentProfile()
            initialLayout = nop
            RunNextFrame(function() EventRegistry:RegisterFrameEventAndCallback("EDIT_MODE_LAYOUTS_UPDATED", refreshCurrentProfile) end)
        end
    end
    
    hooksecurefunc(f, "OnLoad", function()
        initialLayout()
        EventUtil.RegisterOnceFrameEventAndCallback("EDIT_MODE_LAYOUTS_UPDATED", initialLayout)
        RunNextFrame(initialLayout)
    end)
end

--
-- allow a frame to be pinned to the minimap
--

-- Prerequsities: LibDataBroker and LibDBIcon
-- Must be called during PLAYER_ENTERING_WORLD or later, or issues with MBB compatibility can occur
function lib:RegisterMinimapPinnable(frame)
    local name = frame:GetName().."LDB"
    local db = framesDB[frame.system]
    if not db.minimap then db.minimap = {} end
    
    -- requirements to show the minimap icon:
    -- 1. player has selected option to pin the frame to the minimap
    -- 2. the frame is actually currently visible
    db.minimap.hide = not ((db.settings[ENUM_EDITMODEACTIONBARSETTING_MINIMAPPINNED] == 1) and frame:IsShown())
    
    local LDB = LibStub("LibDataBroker-1.1"):NewDataObject(name, {
        type = "data source",
        text = frame:GetName(),
        icon = "",
    })
    local icon = LibStub("LibDBIcon-1.0")
    icon:Register(name, LDB, db.minimap)
    
    -- compatibility with Minimap Button Bag
    if MBB_Version and MBB_OnClick and MBB_Ignore then
        icon:Show(name)
        table.insert(MBB_Ignore, icon:GetMinimapButton(name):GetName())
        icon:Hide(name)
    end
    
    frame:HookScript("OnShow", function()
        db = framesDB[frame.system]
        if not db.minimap then db.minimap = {} end
        if db.settings[ENUM_EDITMODEACTIONBARSETTING_MINIMAPPINNED] == 1 then
            db.minimap.hide = nil
            icon:Show(name)
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", icon:GetMinimapButton(name), "CENTER")
        end
    end)
    
    frame:HookScript("OnHide", function()
        db = framesDB[frame.system]
        if not db.minimap then db.minimap = {} end
        db.minimap.hide = true
        icon:Hide(name)
    end)
    
    local function showHide()
        db = framesDB[frame.system]
        if not db.minimap then db.minimap = {} end
        if (db.settings[ENUM_EDITMODEACTIONBARSETTING_MINIMAPPINNED] == 1) and frame:IsShown() then
            db.minimap.hide = nil
            icon:Show(name)
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", icon:GetMinimapButton(name), "CENTER")
        else
            db.minimap.hide = true
            icon:Hide(name)
        end
    end
    
    hooksecurefunc(frame, "SetShown", function()
        showHide()
    end)
    showHide()
    
    if framesDialogsKeys[frame.system][ENUM_EDITMODEACTIONBARSETTING_MINIMAPPINNED] then return end
    framesDialogsKeys[frame.system][ENUM_EDITMODEACTIONBARSETTING_MINIMAPPINNED] = true
    table.insert(framesDialogs[frame.system],
        {
            setting = ENUM_EDITMODEACTIONBARSETTING_MINIMAPPINNED,
            name = "Pin to Minimap",
            type = Enum.EditModeSettingDisplayType.Checkbox,
        }
    )
    
    frame.minimapLDBIcon = icon
end

function pinToMinimap(frame)
    local db = framesDB[frame.system]
    if not db.minimap then db.minimap = {} end
    
    if db.minimap.hide then
        frame.minimapLDBIcon:Hide(frame:GetName().."LDB")
    else
        frame.minimapLDBIcon:Show(frame:GetName().."LDB")
    end
    
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", frame.minimapLDBIcon:GetMinimapButton(frame:GetName().."LDB"), "CENTER")
end

function unpinFromMinimap(frame)
    local db = framesDB[frame.system]
    frame:ClearAllPoints()
    frame:SetPoint(frame.EMEanchorPoint, frame.EMEanchorTo, frame.EMEanchorPoint, db.x, db.y)
    db.minimap.hide = true
    frame.minimapLDBIcon:Hide(frame:GetName().."LDB")
end

--
-- Handle frame being based on a frame other than UIParent
--
function getOffsetXY(frame, x, y)
    if issecretvalue(x) or issecretvalue(y) then
        return x, y, true
    end
    
    local width, height = frame:GetSize()
    if issecretvalue(width) or issecretvalue(height) then
        return x, y, true
    end
    
    local scale = frame:GetEffectiveScale()
    local parentscale = frame.EMEanchorTo:GetEffectiveScale()

    local anchorPoint = frame.EMEanchorPoint or "BOTTOMLEFT"
    if anchorPoint == "BOTTOMLEFT" then
        local targetX, targetY = frame.EMEanchorTo:GetRect()
        return x - ((targetX * parentscale) / scale), y - ((targetY * parentscale) / scale)
    elseif anchorPoint == "BOTTOMRIGHT" then
        local targetX, targetY, targetWidth = frame.EMEanchorTo:GetRect()
        return (x + width) - (((targetX + targetWidth) * parentscale) / scale), y - ((targetY * parentscale) / scale)
    elseif anchorPoint == "TOPLEFT" then
        local targetX, targetY, _, targetHeight = frame.EMEanchorTo:GetRect()
        return x - ((targetX * parentscale) / scale), (y + height) - (((targetY + targetHeight) * parentscale) / scale)
    elseif anchorPoint == "TOPRIGHT" then
        local targetX, targetY, targetWidth, targetHeight = frame.EMEanchorTo:GetRect()
        return (x + width) - (((targetX + targetWidth) * parentscale) / scale), (y + height) - (((targetY + targetHeight) * parentscale) / scale)
    elseif anchorPoint == "CENTER" then
        local targetX, targetY, targetWidth, targetHeight = frame.EMEanchorTo:GetRect()
        return (x + 0.5 * width) - (((targetX + 0.5 * targetWidth) * parentscale) / scale), (y + 0.5 * height) - (((targetY + 0.5 * targetHeight) * parentscale) / scale)
    elseif anchorPoint == "TOP" then
        local targetX, targetY, targetWidth, targetHeight = frame.EMEanchorTo:GetRect()
        return (x + 0.5 * width) - (((targetX + 0.5 * targetWidth) * parentscale) / scale), (y + height) - (((targetY + targetHeight) * parentscale) / scale)
    elseif anchorPoint == "BOTTOM" then
        local targetX, targetY, targetWidth = frame.EMEanchorTo:GetRect()
        return (x + 0.5 * width) - (((targetX + 0.5 * targetWidth) * parentscale) / scale), y - ((targetY * parentscale) / scale)
    elseif anchorPoint == "LEFT" then
        local targetX, targetY, _, targetHeight = frame.EMEanchorTo:GetRect()
        return x - ((targetX * parentscale) / scale), (y + 0.5 * height) - (((targetY + 0.5 * targetHeight) * parentscale) / scale)
    elseif anchorPoint == "RIGHT" then
        local targetX, targetY, targetWidth, targetHeight = frame.EMEanchorTo:GetRect()
        return (x + width) - (((targetX + targetWidth) * parentscale) / scale), (y + 0.5 * height) - (((targetY + 0.5 * targetHeight) * parentscale) / scale)
    end 
end

--
-- Handle allowing frame to be moved with arrow keys
--
function registerFrameMovableWithArrowKeys(frame)
    frame.Selection:EnableKeyboard();
    frame.Selection:SetPropagateKeyboardInput(true);
    frame.Selection:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        frame:MoveWithArrowKey(key);
    end)

    function frame:MoveWithArrowKey(key)
        if self.isSelected then
            local x, y = self:GetRect();
            if issecretvalue(x) or issecretvalue(y) then return end

            local new_x = x;
            local new_y = y;

            if key == "RIGHT" then      new_x = new_x + 1;
            elseif key == "LEFT" then   new_x = new_x - 1;
            elseif key == "UP" then     new_y = new_y + 1;
            elseif key == "DOWN" then   new_y = new_y - 1;
            end
            
            if new_x ~= x or new_y ~= y then
                -- consume the key used to prevent movement / cam turning
                self.Selection:SetPropagateKeyboardInput(false);
                
                if existingFrames[frame:GetName()] then
                    local layoutInfoCopy = CopyTable(EditModeManagerFrame.layoutInfo)
                    local activeLayout = layoutInfoCopy.layouts[layoutInfoCopy.activeLayout]
                    local a, b, c, d, e = self:GetPoint()
                    for _, frameData in ipairs(activeLayout.systems) do
                        local anchorInfo = frameData.anchorInfo
                        if frame.EMELayoutInfoIDKnown then
                            if (frame.EMELayoutInfoIDKnown.system == frameData.system) and (frame.EMELayoutInfoIDKnown.systemIndex == frameData.systemIndex) then
                                anchorInfo.offsetX = new_x
                                anchorInfo.offsetY = new_y
                                break
                            end
                        end
                        if 
                            (anchorInfo.point == a) and 
                            (anchorInfo.relativeTo == b:GetName()) and 
                            (anchorInfo.relativePoint == c) and 
                            (tonumber(string.format("%.3f", anchorInfo.offsetX)) == tonumber(string.format("%.3f", d))) and 
                            (tonumber(string.format("%.3f", anchorInfo.offsetY)) == tonumber(string.format("%.3f", e))) 
                        then
                            frame.EMELayoutInfoIDKnown = {
                                system = frameData.system,
                                systemIndex = frameData.systemIndex,
                            }
                            anchorInfo.offsetX = new_x
                            anchorInfo.offsetY = new_y
                            break
                        end
                    end
                    C_EditMode.SaveLayouts(layoutInfoCopy)
                else
                    local db = framesDB[getSystemID(frame)]
                    db.x, db.y = new_x, new_y
                end
                self:ClearAllPoints()
                local offsetX, offsetY = getOffsetXY(frame, new_x, new_y)
                self:SetPoint(frame.EMEanchorPoint, frame.EMEanchorTo, frame.EMEanchorPoint, offsetX, offsetY);
                return
            end
        end

        self.Selection:SetPropagateKeyboardInput(true);
    end
end

-- Will make the frame not shown during edit mode by default
function lib:HideByDefault(frame)
    local db = framesDB[frame.system]
    db.enabled = false
    frame.EMEdisabledByDefault = true
    frame.EMECheckButtonFrame:SetChecked(false)
end

-- Adds an option to hide the frame during combat
-- Frame must be already have had :RegisterHideable called on it for this to work
function lib:RegisterToggleInCombat(frame, toggleCallback)
    local systemID = getSystemID(frame)
    
    if framesDialogsKeys[systemID][ENUM_EDITMODEACTIONBARSETTING_TOGGLEHIDEINCOMBAT] then return end
    framesDialogsKeys[systemID][ENUM_EDITMODEACTIONBARSETTING_TOGGLEHIDEINCOMBAT] = true
    table.insert(framesDialogs[systemID],
        {
            setting = ENUM_EDITMODEACTIONBARSETTING_TOGGLEHIDEINCOMBAT,
            name = L["TOGGLE_VISIBILITY_COMBAT"],
            type = Enum.EditModeSettingDisplayType.Checkbox,
            toggleCallback = toggleCallback,
    })
end

do
    local lf = CreateFrame("Frame")
    local outOfCombatCallbacks = {}
    runOutOfCombat = function(callback)
        if InCombatLockdown() then
            table.insert(outOfCombatCallbacks, callback)
        else
            callback()
        end
    end
    hooksecurefunc(f, "OnLoad", function()
        lf:RegisterEvent("PLAYER_REGEN_DISABLED")
        lf:RegisterEvent("PLAYER_REGEN_ENABLED")
    end)
    lf:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" then
            enteringCombat = true
            -- entering combat
            for _, allFrames in pairs({frames, existingFrames}) do
                for name, frame in pairs(allFrames) do
                    if type(frame) == "boolean" then
                        frame = _G[name]
                    end
                    
                    local systemID = getSystemID(frame)
                    local db = framesDB[systemID]
                    if db then
                        local settings = db.settings
                        local dialogs = framesDialogsKeys[systemID]
                        
                        if dialogs and dialogs[ENUM_EDITMODEACTIONBARSETTING_TOGGLEHIDEINCOMBAT] and settings and (settings[ENUM_EDITMODEACTIONBARSETTING_TOGGLEHIDEINCOMBAT] == 1) and dialogs[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] then
                            if settings[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] == 1 then
                                -- if "Hide" is enabled and this option too, then hide it while out of combat, show it while in combat
                                frame:Show()
                                if frame.EMEOnEventHandler then
                                    frame:SetScript("OnEvent", nil)
                                end
                            else
                                frame:Hide()
                                if frame.EMEOnEventHandler then
                                    frame:SetScript("OnEvent", frame.EMEOnEventHandler)
                                end
                            end
                        end
                    end
                end
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            for _, callback in ipairs(outOfCombatCallbacks) do
                callback()
            end
            wipe(outOfCombatCallbacks)
            enteringCombat = false
            -- exiting combat
            for _, allFrames in pairs({frames, existingFrames}) do
                for name, frame in pairs(allFrames) do
                    if type(frame) == "boolean" then
                        frame = _G[name]
                    end
                    local systemID = getSystemID(frame)
                    local db = framesDB[systemID]
                    if db then
                        local settings = db.settings
                        local dialogs = framesDialogsKeys[systemID]
                        
                        if dialogs and settings and dialogs[ENUM_EDITMODEACTIONBARSETTING_TOGGLEHIDEINCOMBAT] and (settings[ENUM_EDITMODEACTIONBARSETTING_TOGGLEHIDEINCOMBAT] == 1) and dialogs[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] then
                            if settings[ENUM_EDITMODEACTIONBARSETTING_HIDEABLE] == 1 then
                                frame:Hide()
                                if frame.EMEOnEventHandler then
                                    frame:SetScript("OnEvent", frame.EMEOnEventHandler)
                                end
                            else
                                frame:Show()
                                if frame.EMEOnEventHandler then
                                    frame:SetScript("OnEvent", nil)
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end

-- Allows frames to be grouped into a single option on the Expanded frame
function lib:GroupOptions(frameGroup, name)
    assert(type(frameGroup) == "table")
    assert(table.getn(frameGroup) > 0)
    assert(type(name) == "string")
    
    local defaultFrame = frameGroup[1]
    local checkButtonFrame = defaultFrame.EMECheckButtonFrame
    local resetButton = defaultFrame.EMEResetButton

    resetButton:HookScript("OnClick", function()
        for i, frame in ipairs(frameGroup) do
            if i > 1 then
                frame.EMEResetButton:Click()
            end
        end
    end)
    
    checkButtonFrame:HookScript("OnClick", function(self)
        for i, frame in ipairs(frameGroup) do
            if i > 1 then
                frame.EMECheckButtonFrame:Click()
            end
        end
    end)
    
    checkButtonFrame:GetParent().Label:SetText(name)
    
    for i, frame in ipairs(frameGroup) do
        if i > 1 then
            frame.EMECheckButtonFrame.hiddenByGrouping = true
            frame.EMECheckButtonFrame:GetParent():Hide()
            frame.EMEResetButton.hiddenByGrouping = true
            frame.EMEResetButton:Hide()
        end
    end
end

-- Adds the option to make this frame hidden except while mouseover
-- @param 2: localized description for the checkbox to show
function lib:RegisterHiddenUntilMouseover(frame, name)
    local systemID = getSystemID(frame)
    
    if framesDialogsKeys[systemID][ENUM_EDITMODEACTIONBARSETTING_HIDDENUNTILMOUSEOVER] then return end
    framesDialogsKeys[systemID][ENUM_EDITMODEACTIONBARSETTING_HIDDENUNTILMOUSEOVER] = true
    table.insert(framesDialogs[systemID],
        {
            setting = ENUM_EDITMODEACTIONBARSETTING_HIDDENUNTILMOUSEOVER,
            name = name or "Hide Until Mouseover",
            type = Enum.EditModeSettingDisplayType.Checkbox,
        }
    )
    
    local function callLater()
        local db = framesDB[systemID]
        
        if db.settings[ENUM_EDITMODEACTIONBARSETTING_HIDDENUNTILMOUSEOVER] == 1 then
            hideFrameUntilMouseover(frame)
            if EditModeManagerFrame.editModeActive then
                pauseHideFrameUntilMouseover(frame)
            end
        else
            pauseHideFrameUntilMouseover(frame)
        end
    end
    
    if profilesInitialised then
        callLater()
    else
        table.insert(customCheckboxCallDuringProfileInit, callLater)
    end

    RunNextFrame(function() EventRegistry:RegisterFrameEventAndCallback("EDIT_MODE_LAYOUTS_UPDATED", callLater) end)
    
    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
        if InCombatLockdown() then return end
        local db = framesDB[systemID]
        
        if db.settings[ENUM_EDITMODEACTIONBARSETTING_HIDDENUNTILMOUSEOVER] == 1 then
            pauseHideFrameUntilMouseover(frame)
        end
    end)
    
    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
        if InCombatLockdown() then return end
        local db = framesDB[systemID]
        
        if db.settings[ENUM_EDITMODEACTIONBARSETTING_HIDDENUNTILMOUSEOVER] == 1 then
            hideFrameUntilMouseover(frame)
        end
    end)
end

-- Check if frame has the "Hidden Until Mouseover" option selected
function lib:IsFrameHiddenUntilMouseover(frame)
    local systemID = getSystemID(frame)
    local db = framesDB[systemID]
    
    return db.settings[ENUM_EDITMODEACTIONBARSETTING_HIDDENUNTILMOUSEOVER] == 1
end

-- Return currently selected frame
-- returns: selectedFrame, selectedFrameOrigin
-- @return1 - frame currently selected, or nil if nothing is selected
-- #return2 - nil if nothing is selected, 1 if frame is managed by EditModeManagerFrame, 2 if frame is managed by EditModeExpanded
function lib:GetSelectedFrame()
    if not lib.selectedFrame then
        return
    end
    
    for _, frame in pairs(frames) do
        if lib.selectedFrame == frame then
            return frame, 2
        end
    end
    
    return lib.selectedFrame, 1
end
-- Blizzard Edit Mode integration
local _
-- global functions and variables to locals to keep LINT happy
local assert = _G.assert
local issecretvalue = _G.issecretvalue
local LibStub = _G.LibStub; assert(LibStub ~= nil,'LibStub')
local UIParent = _G.UIParent; assert(UIParent ~= nil,'UIParent')
-- local AddOn
local ADDON, P = ...
local NOP = LibStub("AceAddon-3.0"):GetAddon(ADDON)
--
local L = P.L
local EDIT_MODE_MIGRATION_VERSION = 1

local function IsSecret(value)
  return issecretvalue and issecretvalue(value)
end

local function GetSafeFrameRect(frame)
  local x, y, width, height = frame:GetRect()
  if not (x and y and width and height) then return end
  if IsSecret(x) or IsSecret(y) or IsSecret(width) or IsSecret(height) then return end

  local screenX, screenY, screenWidth, screenHeight = UIParent:GetRect()
  if not (screenX and screenY and screenWidth and screenHeight) then return end
  if IsSecret(screenX) or IsSecret(screenY) or IsSecret(screenWidth) or IsSecret(screenHeight) then return end

  -- At least part of the button must be on screen. This also rejects stale
  -- coordinates left behind after resolution or UI-scale changes.
  if x + width <= screenX or y + height <= screenY or x >= screenX + screenWidth or y >= screenY + screenHeight then return end
  return x, y
end

local function MigrateLegacyPosition(self)
  if (self.AceDB.global.editModeMigration or 0) >= EDIT_MODE_MIGRATION_VERSION then return end

  local x, y = GetSafeFrameRect(self.BF)
  if not (x and y) then
    self.BF:ClearAllPoints()
    self.BF:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    x, y = GetSafeFrameRect(self.BF)
  end

  if x and y then
    local db = self.AceDB.global.editMode
    -- Releases before this migration marker could leave an incomplete Edit
    -- Mode profile behind. Re-seed it once from the visible legacy position.
    db.profiles = nil
    db.x = x
    db.y = y
    db.enabled = true
    db.settings = db.settings or {}
  end
end

function NOP:EditModeIsActive()
  return _G.EditModeManagerFrame and _G.EditModeManagerFrame.editModeActive or false
end

function NOP:EditModeSavePosition()
  if not (self.editModeRegistered and self.editModeLib and self.BF and self.BF.system) then return end

  local framesDB = self.editModeLib.framesDB
  local db = framesDB and framesDB[self.BF.system]
  if not db then return end

  local x, y = self.BF:GetRect()
  if not (x and y) then return end
  if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then return end

  db.x = x
  db.y = y
end

function NOP:EditModeRegister()
  if self.editModeRegistered or not (self.BF and self.AceDB) then return end

  local lib = LibStub("EditModeExpanded-1.0", true)
  if not lib then return end

  MigrateLegacyPosition(self)
  lib:RegisterFrame(self.BF, L["NOP_TITLE"], self.AceDB.global.editMode, UIParent, "BOTTOMLEFT")
  lib:SetDontResize(self.BF)
  lib:RegisterCoordinates(self.BF)

  self.editModeLib = lib
  self.editModeRegistered = true
  self.AceDB.global.editModeMigration = EDIT_MODE_MIGRATION_VERSION

  if self.BF.Selection then
    self.BF.Selection:EnableMouse(true)
    self.BF.Selection:RegisterForDrag("LeftButton")
    self.BF.Selection:SetScript("OnDragStart", function()
      if NOP:inCombat() then return end
      NOP.BF:SetMovable(true)
      NOP.BF:StartMoving()
    end)
    self.BF.Selection:HookScript("OnDragStop", function()
      NOP:EditModeSavePosition()
      NOP:ButtonSave(true)
      NOP:QBAnchorSave()
    end)
    self.BF.Selection:HookScript("OnKeyUp", function(_, key)
      if key == "LEFT" or key == "RIGHT" or key == "UP" or key == "DOWN" then
        NOP:ButtonSave(true)
        NOP:QBAnchorSave()
      end
    end)
  end

  -- Mirror the migrated legacy position back to the old settings controls.
  self:ButtonSave(true)
end

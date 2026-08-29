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

  lib:RegisterFrame(self.BF, L["NOP_TITLE"], self.AceDB.global.editMode, UIParent, "BOTTOMLEFT")
  lib:SetDontResize(self.BF)
  lib:RegisterCoordinates(self.BF)

  self.editModeLib = lib
  self.editModeRegistered = true

  if self.BF.Selection then
    self.BF.Selection:HookScript("OnDragStop", function()
      NOP:ButtonSave(true)
      NOP:QBAnchorSave()
    end)
  end

  -- Mirror the migrated legacy position back to the old settings controls.
  self:ButtonSave(true)
end

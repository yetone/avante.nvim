---@meta

---@class NuiSignalValue: boolean
local NuiSignalValue = require("nui-components.signal.value")

---@return boolean
function NuiSignalValue:negate() end

---@class NuiSignal
---@field is_loading boolean | NuiSignalValue
---@field text string
local AvanteSignal = require("nui-components.signal")

---@return any
function AvanteSignal:get_value() end

---@class NuiRenderer
local AvanteRenderer = require("nui-components.renderer")

---@class NuiComponent
---@field winid integer | nil
local AvanteComponent = require("nui-components.component")

---@param opts table<string, any>
---@return NuiRenderer
function AvanteRenderer.create(opts) end

---@return NuiComponent[]
function AvanteRenderer:get_focusable_components() end

---@param body fun():NuiComponent
function AvanteRenderer:render(body) end

---@return nil
function AvanteRenderer:focus() end

---@return nil
function AvanteRenderer:close() end

---@param callback fun():nil
---@return nil
function AvanteRenderer:on_mount(callback) end

---@param callback fun():nil
---@return nil
function AvanteRenderer:on_unmount(callback) end

---@class LayoutSize
---@field width integer?
---@field height integer?

---@param size LayoutSize
---@return nil
function AvanteRenderer:set_size(size) end

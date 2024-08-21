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
---@field bufnr integer | nil
local AvanteComponent = require("nui-components.component")

---@class NuiSplit
---@field winid integer | nil
---@field bufnr integer | nil
local AvanteSplit = require("nui.split")

---@return nil
function AvanteSplit:mount() end

---@return nil
function AvanteSplit:unmount() end

---@param event string | string[]
---@param handler string | function
---@param options? table<"'once'" | "'nested'", boolean>
---@return nil
function AvanteSplit:on(event, handler, options) end

-- set keymap for this split
---@param mode string check `:h :map-modes`
---@param key string|string[] key for the mapping
---@param handler string | fun(): nil handler for the mapping
---@param opts? table<"'expr'"|"'noremap'"|"'nowait'"|"'remap'"|"'script'"|"'silent'"|"'unique'", boolean>
---@return nil
function AvanteSplit:map(mode, key, handler, opts, ___force___) end

---@param opts table<string, any>
---@return NuiRenderer
function AvanteRenderer.create(opts) end

---@return NuiComponent[]
function AvanteRenderer:get_focusable_components() end

---@param mappings {mode: string[], key: string, handler: fun(): any}[]
---@return nil
function AvanteRenderer:add_mappings(mappings) end

---@param id string
---@return NuiComponent
function AvanteRenderer:get_component_by_id(id) end

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

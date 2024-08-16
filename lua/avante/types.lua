---@meta

---@class NuiRenderer
_G.AvanteRenderer = require("nui-components.renderer")

---@class NuiComponent
_G.AvanteComponent = require("nui-components.component")

---@param opts table<string, any>
---@return NuiRenderer
function AvanteRenderer.create(opts) end

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

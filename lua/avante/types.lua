---@meta

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

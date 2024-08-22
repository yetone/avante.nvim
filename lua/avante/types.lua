---@meta

---@class AvanteComp
---@field winid integer | nil
---@field bufnr integer | nil
local AvanteComp = {}

---@return nil
function AvanteComp:mount() end

---@return nil
function AvanteComp:unmount() end

---@param event string | string[]
---@param handler string | function
---@param options? table<"'once'" | "'nested'", boolean>
---@return nil
function AvanteComp:on(event, handler, options) end

-- set keymap for this split
---@param mode string check `:h :map-modes`
---@param key string|string[] key for the mapping
---@param handler string | fun(): nil handler for the mapping
---@param opts? table<"'expr'"|"'noremap'"|"'nowait'"|"'remap'"|"'script'"|"'silent'"|"'unique'", boolean>
---@return nil
function AvanteComp:map(mode, key, handler, opts, ___force___) end

local M = {}

function M:__call(opts, on_log, on_complete) return self.func(opts, on_log, on_complete) end

return M

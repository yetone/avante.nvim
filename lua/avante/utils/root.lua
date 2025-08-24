-- COPIED and MODIFIED from https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/util/root.lua
local Utils = require("avante.utils")
local Config = require("avante.config")

---@class avante.utils.root
---@overload fun(): string
local M = setmetatable({}, {
  __call = function(m) return m.get() end,
})

---@class AvanteRoot
---@field paths string[]
---@field spec AvanteRootSpec

---@alias AvanteRootFn fun(buf: number): (string|string[])

---@alias AvanteRootSpec string|string[]|AvanteRootFn

---@type AvanteRootSpec[]
M.spec = { "lsp", { ".git", "lua" }, "cwd" }

M.detectors = {}

function M.detectors.cwd() return { vim.uv.cwd() } end

---@param buf number
function M.detectors.lsp(buf)
  local bufpath = M.bufpath(buf)
  if not bufpath then return {} end
  local roots = {} ---@type string[]
  local lsp_clients = Utils.lsp.get_clients({ bufnr = buf })
  for _, client in ipairs(lsp_clients) do
    local workspace = client.config.workspace_folders
    for _, ws in ipairs(workspace or {}) do
      roots[#roots + 1] = vim.uri_to_fname(ws.uri)
    end
    if client.root_dir then roots[#roots + 1] = client.root_dir end
  end
  return vim.tbl_filter(function(path)
    path = Utils.norm(path)
    return path and bufpath:find(path, 1, true) == 1
  end, roots)
end

---@param patterns string[]|string
function M.detectors.pattern(buf, patterns)
  local patterns_ = type(patterns) == "string" and { patterns } or patterns
  ---@cast patterns_ string[]
  local path = M.bufpath(buf) or vim.uv.cwd()
  local pattern = vim.fs.find(function(name)
    for _, p in ipairs(patterns_) do
      if name == p then return true end
      if p:sub(1, 1) == "*" and name:find(vim.pesc(p:sub(2)) .. "$") then return true end
    end
    return false
  end, { path = path, upward = true })[1]
  return pattern and { vim.fs.dirname(pattern) } or {}
end

function M.bufpath(buf)
  if buf == nil or type(buf) ~= "number" then
    -- TODO: Consider logging this unexpected buffer type or nil value if assert was bypassed.
    vim.notify("avante: M.bufpath received invalid buffer: " .. tostring(buf), vim.log.levels.WARN)
    return nil
  end

  local buf_name_str
  local success, result = pcall(vim.api.nvim_buf_get_name, buf)

  if not success then
    -- TODO: Consider logging the actual error from pcall.
    vim.notify(
      "avante: nvim_buf_get_name failed for buffer " .. tostring(buf) .. ": " .. tostring(result),
      vim.log.levels.WARN
    )
    return nil
  end
  buf_name_str = result

  -- M.realpath will handle buf_name_str == "" (empty string for unnamed buffer) correctly, returning nil.
  return M.realpath(buf_name_str)
end

function M.cwd() return M.realpath(vim.uv.cwd()) or "" end

function M.realpath(path)
  if path == "" or path == nil then return nil end
  path = vim.uv.fs_realpath(path) or path
  return Utils.norm(path)
end

---@param spec AvanteRootSpec
---@return AvanteRootFn
function M.resolve(spec)
  if M.detectors[spec] then
    return M.detectors[spec]
  elseif type(spec) == "function" then
    return spec
  end
  return function(buf) return M.detectors.pattern(buf, spec) end
end

---@param opts? { buf?: number, spec?: AvanteRootSpec[], all?: boolean }
function M.detect(opts)
  opts = opts or {}
  opts.spec = opts.spec or type(vim.g.root_spec) == "table" and vim.g.root_spec or M.spec
  opts.buf = (opts.buf == nil or opts.buf == 0) and vim.api.nvim_get_current_buf() or opts.buf

  local ret = {} ---@type AvanteRoot[]
  for _, spec in ipairs(opts.spec) do
    local paths = M.resolve(spec)(opts.buf)
    paths = paths or {}
    paths = type(paths) == "table" and paths or { paths }
    local roots = {} ---@type string[]
    for _, p in ipairs(paths) do
      local pp = M.realpath(p)
      if pp and not vim.tbl_contains(roots, pp) then roots[#roots + 1] = pp end
    end
    table.sort(roots, function(a, b) return #a > #b end)
    if #roots > 0 then
      ret[#ret + 1] = { spec = spec, paths = roots }
      if opts.all == false then break end
    end
  end
  return ret
end

---@type table<number, string>
M.cache = {}
local buf_names = {}

-- returns the root directory based on:
-- * lsp workspace folders
-- * lsp root_dir
-- * root pattern of filename of the current buffer
-- * root pattern of cwd
---@param opts? {normalize?:boolean, buf?:number}
---@return string
function M.get(opts)
  local cwd = vim.uv.cwd()
  if Config.behaviour.use_cwd_as_project_root then
    if cwd and cwd ~= "" then return cwd end
  end
  opts = opts or {}
  local buf = opts.buf or vim.api.nvim_get_current_buf()
  local buf_name = vim.api.nvim_buf_get_name(buf)
  local ret = buf_names[buf] == buf_name and M.cache[buf] or nil
  if not ret then
    local roots = M.detect({ all = false, buf = buf })
    ret = roots[1] and roots[1].paths[1] or vim.uv.cwd()
    buf_names[buf] = buf_name
    M.cache[buf] = ret
  end
  if cwd ~= nil and #ret > #cwd then ret = cwd end
  if opts and opts.normalize then return ret end
  return Utils.is_win() and ret:gsub("/", "\\") or ret
end

function M.git()
  local root = M.get()
  local git_root = vim.fs.find(".git", { path = root, upward = true })[1]
  local ret = git_root and vim.fn.fnamemodify(git_root, ":h") or root
  return ret
end

return M

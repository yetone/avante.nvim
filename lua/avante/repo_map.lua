local Popup = require("nui.popup")
local Utils = require("avante.utils")
local event = require("nui.utils.autocmd").event
local Config = require("avante.config")

local filetype_map = {
  ["javascriptreact"] = "javascript",
  ["typescriptreact"] = "typescript",
  ["cs"] = "csharp",
}

---@class AvanteRepoMap
---@field stringify_definitions fun(lang: string, source: string): string
local repo_map_lib = nil

---@class avante.utils.repo_map
local RepoMap = {}

---@return AvanteRepoMap|nil
function RepoMap._init_repo_map_lib()
  if repo_map_lib ~= nil then return repo_map_lib end

  local ok, core = pcall(require, "avante_repo_map")
  if not ok then return nil end

  repo_map_lib = core
  return repo_map_lib
end

function RepoMap.setup() vim.defer_fn(RepoMap._init_repo_map_lib, 1000) end

function RepoMap.get_ts_lang(filepath)
  local filetype = RepoMap.get_filetype(filepath)
  return filetype_map[filetype] or filetype
end

function RepoMap.get_filetype(filepath)
  -- Some files are sometimes not detected correctly when buffer is not included
  -- https://github.com/neovim/neovim/issues/27265

  local buf = vim.api.nvim_create_buf(false, true)
  local filetype = vim.filetype.match({ filename = filepath, buf = buf })
  vim.api.nvim_buf_delete(buf, { force = true })

  return filetype
end

function RepoMap._build_repo_map(project_root, file_ext)
  local output = {}
  local gitignore_path = project_root .. "/.gitignore"
  local gitignore_patterns, gitignore_negate_patterns = Utils.parse_gitignore(gitignore_path)
  local ignore_patterns = vim.list_extend(gitignore_patterns, Config.repo_map.ignore_patterns)
  local negate_patterns = vim.list_extend(gitignore_negate_patterns, Config.repo_map.negate_patterns)

  local filepaths = Utils.scan_directory({
    directory = project_root,
    gitignore_patterns = ignore_patterns,
    gitignore_negate_patterns = negate_patterns,
  })
  if filepaths and not RepoMap._init_repo_map_lib() then
    -- or just throw an error if we don't want to execute request without codebase
    Utils.error("Failed to load avante_repo_map")
    return
  end
  vim.iter(filepaths):each(function(filepath)
    if not Utils.is_same_file_ext(file_ext, filepath) then return end
    local filetype = RepoMap.get_ts_lang(filepath)
    local definitions = filetype
        and repo_map_lib.stringify_definitions(filetype, Utils.file.read_content(filepath) or "")
      or ""
    if definitions == "" then return end
    table.insert(output, {
      path = Utils.relative_path(filepath),
      lang = RepoMap.get_filetype(filepath),
      defs = definitions,
    })
  end)
  return output
end

local cache = {}

function RepoMap.get_repo_map(file_ext)
  local repo_map = RepoMap._get_repo_map(file_ext) or {}
  if not repo_map or next(repo_map) == nil then
    Utils.warn("The repo map is empty. Maybe do not support this language: " .. file_ext)
  end
  return repo_map
end

function RepoMap._get_repo_map(file_ext)
  file_ext = file_ext or vim.fn.expand("%:e")
  local project_root = Utils.root.get()
  local cache_key = project_root .. "." .. file_ext
  local cached = cache[cache_key]
  if cached then return cached end

  local PPath = require("plenary.path")
  local Path = require("avante.path")
  local repo_map

  local function build_and_save()
    repo_map = RepoMap._build_repo_map(project_root, file_ext)
    cache[cache_key] = repo_map
    Path.repo_map.save(project_root, file_ext, repo_map)
  end

  repo_map = Path.repo_map.load(project_root, file_ext)

  if not repo_map or next(repo_map) == nil then
    build_and_save()
    if not repo_map then return end
  else
    local timer = vim.loop.new_timer()

    if timer then
      timer:start(
        0,
        0,
        vim.schedule_wrap(function()
          build_and_save()
          timer:close()
        end)
      )
    end
  end

  local update_repo_map = vim.schedule_wrap(function(rel_filepath)
    if rel_filepath and Utils.is_same_file_ext(file_ext, rel_filepath) then
      local abs_filepath = PPath:new(project_root):joinpath(rel_filepath):absolute()
      local definitions = repo_map_lib.stringify_definitions(
        RepoMap.get_ts_lang(abs_filepath),
        Utils.file.read_content(abs_filepath) or ""
      )
      if definitions == "" then return end
      local found = false
      for _, m in ipairs(repo_map) do
        if m.path == rel_filepath then
          m.defs = definitions
          found = true
          break
        end
      end
      if not found then
        table.insert(repo_map, {
          path = Utils.relative_path(abs_filepath),
          lang = RepoMap.get_filetype(abs_filepath),
          defs = definitions,
        })
      end
      cache[cache_key] = repo_map
      Path.repo_map.save(project_root, file_ext, repo_map)
    end
  end)

  local handle = vim.loop.new_fs_event()

  if handle then
    handle:start(project_root, { recursive = true }, function(err, rel_filepath)
      if err then
        print("Error watching directory " .. project_root .. ":", err)
        return
      end

      if rel_filepath then update_repo_map(rel_filepath) end
    end)
  end

  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    callback = function(ev)
      vim.defer_fn(function()
        local ok, filepath = pcall(vim.api.nvim_buf_get_name, ev.buf)
        if not ok or not filepath then return end
        if not vim.startswith(filepath, project_root) then return end
        local rel_filepath = Utils.relative_path(filepath)
        update_repo_map(rel_filepath)
      end, 0)
    end,
  })

  return repo_map
end

function RepoMap.show()
  local file_ext = vim.fn.expand("%:e")
  local repo_map = RepoMap.get_repo_map(file_ext)

  if not repo_map or next(repo_map) == nil then
    Utils.warn("The repo map is empty or not supported for this language: " .. file_ext)
    return
  end

  local popup = Popup({
    position = "50%",
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      padding = { 1, 1 },
      text = {
        top = " Avante Repo Map ",
        top_align = "center",
      },
    },
    size = {
      width = math.floor(vim.o.columns * 0.8),
      height = math.floor(vim.o.lines * 0.8),
    },
  })

  popup:mount()

  popup:map("n", "q", function() popup:unmount() end, { noremap = true, silent = true })

  popup:on(event.BufLeave, function() popup:unmount() end)

  -- Format the repo map for display
  local lines = {}
  for _, entry in ipairs(repo_map) do
    table.insert(lines, string.format("Path: %s", entry.path))
    table.insert(lines, string.format("Lang: %s", entry.lang))
    table.insert(lines, "Defs:")
    for def_line in entry.defs:gmatch("[^\r\n]+") do
      table.insert(lines, def_line)
    end
    table.insert(lines, "") -- Add an empty line between entries
  end

  -- Set the buffer content
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
end

return RepoMap

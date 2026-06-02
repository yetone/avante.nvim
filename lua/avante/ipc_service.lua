---@mod avante-ipc-service Avante IPC service
---@brief [[
---
--- The IPC service is a lightweight Docker/Nix sidecar that lets root Avante
--- sidebar instances running in *separate Neovim processes* discover each other,
--- share responsibility summaries, and exchange messages.
---
--- Without this service, `send_message` only works between sidebars inside the
--- same nvim process.  With it, any nvim process with Avante open can see and
--- message every other live instance on the machine.
---
--->
---   require("avante").setup({
---     ipc_service = {
---       enabled = false,
---       runner = "docker",      -- "docker" or "nix"
---       image  = "quay.io/yetoneful/avante-ipc-service:0.0.1",
---       docker_extra_args = "",
---     },
---   })
---<
---
---@brief ]]

local curl = require("plenary.curl")
local PlenaryPath = require("plenary.path")
local Config = require("avante.config")
local Utils = require("avante.utils")

local M = {}

local container_name = "avante-ipc-service"
local service_path = "/tmp/" .. container_name

-- Port for the IPC service (distinct from RAG service port 20250).
local IPC_PORT = 20251

-- How often (ms) to send heartbeats / poll for incoming messages.
local HEARTBEAT_INTERVAL_MS = 10000 -- 10 seconds
local POLL_INTERVAL_MS = 3000 -- 3 seconds

-- Module-level state.
local _instance_id = nil ---@type string | nil
local _instance_name = nil ---@type string | nil
local _heartbeat_timer = nil ---@type any
local _poll_timer = nil ---@type any
-- Callback invoked when messages arrive: fun(from_name: string, message: string)
local _on_message_cb = nil ---@type fun(from_name: string, message: string) | nil

---@return string
function M.get_ipc_service_url() return string.format("http://localhost:%d", IPC_PORT) end

---@return string
function M.get_ipc_service_image()
  if Config.ipc_service and Config.ipc_service.image then return Config.ipc_service.image end
  return "quay.io/yetoneful/avante-ipc-service:0.0.1"
end

---@return string
function M.get_ipc_service_runner()
  return (Config.ipc_service and Config.ipc_service.runner) or "docker"
end

---@return string
function M.get_data_path()
  local p = PlenaryPath:new(vim.fn.stdpath("data")):joinpath("avante/ipc_service")
  if not p:exists() then p:mkdir({ parents = true }) end
  return tostring(p)
end

-- ---------------------------------------------------------------------------
-- Readiness check
-- ---------------------------------------------------------------------------

---@return boolean
function M.is_ready()
  local url = M.get_ipc_service_url() .. "/api/health"
  local cmd = { "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", url }
  local result = vim.system(cmd, { text = true }):wait()
  return result.code == 0 and vim.trim(result.stdout or "") == "200"
end

-- ---------------------------------------------------------------------------
-- Launch / stop
-- ---------------------------------------------------------------------------

---@param cb fun()
function M.launch_ipc_service(cb)
  if M.get_ipc_service_runner() == "docker" then
    local image = M.get_ipc_service_image()
    local data_path = M.get_data_path()
    local docker_extra = (Config.ipc_service and Config.ipc_service.docker_extra_args) or ""

    -- Check existing container state.
    local inspect = vim.system({ "docker", "inspect", "--format", "{{.State.Status}}", container_name }, { text = true }):wait()
    local status = vim.trim(inspect.stdout or "")

    if status == "running" then
      -- Check if it's the same image.
      local cur_img_result = vim.system({ "docker", "inspect", "--format", "{{.Config.Image}}", container_name }, { text = true }):wait()
      local cur_img = vim.trim(cur_img_result.stdout or "")
      if cur_img == image then
        cb()
        return
      end
      Utils.debug(string.format("ipc container running with different image (%s vs %s), restarting", cur_img, image))
      M.stop_ipc_service()
    elseif status ~= "" then
      -- Exists but not running.
      M.stop_ipc_service()
    end

    local cmd_ = string.format(
      "docker run --platform=linux/amd64 -d -p 0.0.0.0:%d:%d --name %s -v %s:/data -e DATA_DIR=/data %s %s",
      IPC_PORT,
      IPC_PORT,
      container_name,
      data_path,
      docker_extra,
      image
    )
    vim.fn.jobstart(cmd_, {
      detach = true,
      on_exit = function(_, exit_code)
        if exit_code ~= 0 then
          Utils.error(string.format("avante-ipc-service container failed to start (exit %d)", exit_code))
        else
          Utils.debug("avante-ipc-service container started")
          cb()
        end
      end,
    })
  elseif M.get_ipc_service_runner() == "nix" then
    local check_result = vim.system({ "pgrep", "-f", service_path }, { text = true }):wait().stdout
    if check_result ~= "" then
      Utils.debug("avante-ipc-service already running")
      cb()
      return
    end

    local dirname = Utils.trim(
      string.sub(debug.getinfo(1).source, 2, #"/lua/avante/ipc_service.lua" * -1),
      { suffix = "/" }
    )
    local ipc_service_dir = dirname .. "/py/ipc-service"

    -- Spawn the nix-shell service detached. Because the process runs
    -- indefinitely (it IS the service), the on_exit callback would never
    -- fire during normal operation, so we cannot use it to signal readiness.
    -- Instead, call cb() immediately and let the try_ipc_ready polling loop
    -- in init.lua detect when the service actually responds to /api/health.
    vim.system({ "sh", "run.sh", service_path }, {
      detach = true,
      cwd = ipc_service_dir,
      env = {
        PORT = tostring(IPC_PORT),
        DATA_DIR = service_path,
      },
    })
    cb()
  end
end

function M.stop_ipc_service()
  if M.get_ipc_service_runner() == "docker" then
    local status = vim.trim((vim.system({ "docker", "inspect", "--format", "{{.State.Status}}", container_name }, { text = true }):wait().stdout) or "")
    if status ~= "" then vim.system({ "docker", "rm", "-fv", container_name }):wait() end
  else
    local pid = vim.trim((vim.system({ "pgrep", "-f", service_path }, { text = true }):wait().stdout) or "")
    if pid ~= "" then vim.system({ "kill", "-9", pid }):wait() end
  end
end

-- ---------------------------------------------------------------------------
-- HTTP helpers (non-blocking)
-- ---------------------------------------------------------------------------

---@param path string
---@param body table
---@param cb fun(ok: boolean, data: any)|nil
local function post_async(path, body, cb)
  local url = M.get_ipc_service_url() .. path
  local ok, json = pcall(vim.json.encode, body)
  if not ok then
    Utils.debug("ipc_service: failed to encode request body: " .. tostring(json))
    if cb then cb(false, nil) end
    return
  end
  curl.post(url, {
    body = json,
    headers = { ["Content-Type"] = "application/json" },
    callback = function(res)
      if not res or res.status ~= 200 then
        if cb then cb(false, nil) end
        return
      end
      local ok2, data = pcall(vim.json.decode, res.body)
      if cb then cb(ok2, data) end
    end,
  })
end

---@param path string
---@param cb fun(ok: boolean, data: any)
local function get_async(path, cb)
  local url = M.get_ipc_service_url() .. path
  curl.get(url, {
    callback = function(res)
      if not res or res.status ~= 200 then
        cb(false, nil)
        return
      end
      local ok, data = pcall(vim.json.decode, res.body)
      cb(ok, data)
    end,
  })
end

-- ---------------------------------------------------------------------------
-- Registry API
-- ---------------------------------------------------------------------------

---Register (or re-register) this sidebar with the IPC service.
---@param name string Instance name, e.g. "swift-fox"
---@param instance_id string Stable UUID from chat_history
---@param description string Current responsibility summary
---@param project string Absolute project root path
function M.register(name, instance_id, description, project)
  _instance_id = instance_id
  _instance_name = name
  post_async("/api/v1/register", {
    name = name,
    instance_id = instance_id,
    nvim_pid = vim.fn.getpid(),
    project = project or "",
    description = description or "",
  }, function(ok)
    if not ok then Utils.debug("ipc_service: register failed") end
  end)
end

---Unregister this instance (call on sidebar close).
function M.unregister()
  if not _instance_id then return end
  M.stop_timers()
  post_async("/api/v1/unregister", { instance_id = _instance_id }, nil)
  _instance_id = nil
  _instance_name = nil
end

---Update the responsibility description advertised to coworkers.
---@param description string
function M.update_description(description)
  if not _instance_id then return end
  post_async("/api/v1/update_description", {
    instance_id = _instance_id,
    description = description or "",
  }, nil)
end

-- ---------------------------------------------------------------------------
-- Instance listing (synchronous — called from tool func on the main thread)
-- ---------------------------------------------------------------------------

---Return all live peer instances (excluding self).
---@return { name: string, project: string, description: string }[]
function M.list_instances()
  if not _instance_id then return {} end
  local url = M.get_ipc_service_url()
    .. "/api/v1/instances?exclude_instance_id="
    .. vim.uri_encode(_instance_id)
  local res = curl.get(url, { timeout = 3000 })
  if not res or res.status ~= 200 then return {} end
  local ok, data = pcall(vim.json.decode, res.body)
  if not ok or type(data) ~= "table" then return {} end
  return data
end

---Send a message to a named peer (synchronous).
---@param to_name string
---@param message string
---@return boolean ok
---@return string|nil err
function M.send_message(to_name, message)
  if not _instance_name then return false, "IPC: not registered" end
  local url = M.get_ipc_service_url() .. "/api/v1/send_message"
  local ok, json = pcall(vim.json.encode, {
    from_name = _instance_name,
    to_name = to_name,
    message = message,
  })
  if not ok then return false, "IPC: encode error" end
  local res = curl.post(url, {
    body = json,
    headers = { ["Content-Type"] = "application/json" },
    timeout = 3000,
  })
  if not res then return false, "IPC: no response" end
  if res.status == 404 then
    local ok2, data = pcall(vim.json.decode, res.body or "")
    local detail = (ok2 and data and data.detail) or "target not found"
    return false, detail
  end
  if res.status ~= 200 then return false, string.format("IPC: HTTP %d", res.status) end
  return true, nil
end

-- ---------------------------------------------------------------------------
-- Heartbeat + message polling timers
-- ---------------------------------------------------------------------------

---Send a heartbeat, re-registering if the service has forgotten us.
local function do_heartbeat()
  if not _instance_id or not _instance_name then return end
  post_async("/api/v1/heartbeat", {
    instance_id = _instance_id,
  }, function(ok, _)
    if not ok then
      -- 404 means the service was restarted; re-register.
      Utils.debug("ipc_service: heartbeat failed, re-registering...")
      M.register(_instance_name, _instance_id, nil, nil)
    end
  end)
end

---Poll for pending messages and deliver them via the registered callback.
local function do_poll()
  if not _instance_name then return end
  get_async("/api/v1/poll_messages/" .. _instance_name, function(ok, data)
    if not ok or type(data) ~= "table" then return end
    if #data == 0 then return end
    if not _on_message_cb then return end
    vim.schedule(function()
      for _, msg in ipairs(data) do
        if _on_message_cb and msg.from_name and msg.message then
          _on_message_cb(msg.from_name, msg.message)
        end
      end
    end)
  end)
end

---Start periodic heartbeat and message-poll timers.
---@param on_message fun(from_name: string, message: string)
function M.start_timers(on_message)
  _on_message_cb = on_message

  if _heartbeat_timer then
    _heartbeat_timer:stop()
    _heartbeat_timer:close()
  end
  _heartbeat_timer = vim.uv.new_timer()
  _heartbeat_timer:start(HEARTBEAT_INTERVAL_MS, HEARTBEAT_INTERVAL_MS, vim.schedule_wrap(do_heartbeat))

  if _poll_timer then
    _poll_timer:stop()
    _poll_timer:close()
  end
  _poll_timer = vim.uv.new_timer()
  _poll_timer:start(POLL_INTERVAL_MS, POLL_INTERVAL_MS, vim.schedule_wrap(do_poll))
end

---Stop heartbeat and poll timers.
function M.stop_timers()
  if _heartbeat_timer then
    _heartbeat_timer:stop()
    _heartbeat_timer:close()
    _heartbeat_timer = nil
  end
  if _poll_timer then
    _poll_timer:stop()
    _poll_timer:close()
    _poll_timer = nil
  end
  _on_message_cb = nil
end

return M


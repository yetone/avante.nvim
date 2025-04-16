local curl = require("plenary.curl")
local Path = require("plenary.path")
local Config = require("avante.config")
local Utils = require("avante.utils")

local M = {}

local container_name = "avante-rag-service"
local service_path = "/tmp/" .. container_name

function M.get_rag_service_image() return "quay.io/yetoneful/avante-rag-service:0.0.10" end

function M.get_rag_service_port() return 20250 end

function M.get_rag_service_url() return string.format("http://localhost:%d", M.get_rag_service_port()) end

function M.get_data_path()
  local p = Path:new(vim.fn.stdpath("data")):joinpath("avante/rag_service")
  if not p:exists() then p:mkdir({ parents = true }) end
  return p
end

function M.get_current_image()
  local cmd = string.format("docker inspect %s | grep Image | grep %s", container_name, container_name)
  local result = vim.fn.system(cmd)
  if result == "" then return nil end
  local exit_code = vim.v.shell_error
  if exit_code ~= 0 then return nil end
  local image = result:match('"Image":%s*"(.*)"')
  if image == nil then return nil end
  return image
end

function M.get_rag_service_runner() return (Config.rag_service and Config.rag_service.runner) or "docker" end

---@param cb fun()
function M.launch_rag_service(cb)
  local openai_api_key = os.getenv("OPENAI_API_KEY")
  if Config.rag_service.provider == "openai" then
    if openai_api_key == nil then
      error("cannot launch avante rag service, OPENAI_API_KEY is not set")
      return
    end
  end
  local port = M.get_rag_service_port()

  if M.get_rag_service_runner() == "docker" then
    local image = M.get_rag_service_image()
    local data_path = M.get_data_path()
    local cmd = string.format("docker ps | grep '%s'", container_name)
    local result = vim.fn.system(cmd)
    if result ~= "" then
      Utils.debug(string.format("container %s already running", container_name))
      local current_image = M.get_current_image()
      if current_image == image then
        cb()
        return
      end
      Utils.debug(
        string.format(
          "container %s is running with different image: %s != %s, stopping...",
          container_name,
          current_image,
          image
        )
      )
      M.stop_rag_service()
    else
      Utils.debug(string.format("container %s not found, starting...", container_name))
    end
    result = vim.fn.system(string.format("docker ps -a | grep '%s'", container_name))
    if result ~= "" then
      Utils.info(string.format("container %s already started but not running, stopping...", container_name))
      M.stop_rag_service()
    end
    local cmd_ = string.format(
      "docker run --platform=linux/amd64 -d --network=host --name %s -v %s:/data -v %s:/host:ro -e ALLOW_RESET=TRUE -e DATA_DIR=/data -e RAG_PROVIDER=%s -e %s_API_KEY=%s -e %s_API_BASE=%s -e RAG_LLM_MODEL=%s -e RAG_EMBED_MODEL=%s %s %s",
      container_name,
      data_path,
      Config.rag_service.host_mount,
      Config.rag_service.provider,
      Config.rag_service.provider:upper(),
      openai_api_key,
      Config.rag_service.provider:upper(),
      Config.rag_service.endpoint,
      Config.rag_service.llm_model,
      Config.rag_service.embed_model,
      Config.rag_service.docker_extra_args,
      image
    )
    vim.fn.jobstart(cmd_, {
      detach = true,
      on_exit = function(_, exit_code)
        if exit_code ~= 0 then
          Utils.error(string.format("container %s failed to start, exit code: %d", container_name, exit_code))
        else
          Utils.debug(string.format("container %s started", container_name))
          cb()
        end
      end,
    })
  elseif M.get_rag_service_runner() == "nix" then
    -- Check if service is already running
    local check_cmd = string.format("pgrep -f '%s'", service_path)
    local check_result = vim.fn.system(check_cmd)
    if check_result ~= "" then
      Utils.debug(string.format("RAG service already running at %s", service_path))
      cb()
      return
    end

    local dirname =
      Utils.trim(string.sub(debug.getinfo(1).source, 2, #"/lua/avante/rag_service.lua" * -1), { suffix = "/" })
    local rag_service_dir = dirname .. "/py/rag-service"

    Utils.debug(string.format("launching %s with nix...", container_name))

    local cmd = string.format(
      "cd %s && ALLOW_RESET=TRUE PORT=%d DATA_DIR=%s RAG_PROVIDER=%s %s_API_KEY=%s %s_API_BASE=%s RAG_LLM_MODEL=%s RAG_EMBED_MODEL=%s sh run.sh %s",
      rag_service_dir,
      port,
      service_path,
      Config.rag_service.provider,
      Config.rag_service.provider:upper(),
      openai_api_key,
      Config.rag_service.provider:upper(),
      Config.rag_service.endpoint,
      Config.rag_service.llm_model,
      Config.rag_service.embed_model,
      service_path
    )

    vim.fn.jobstart(cmd, {
      detach = true,
      on_exit = function(_, exit_code)
        if exit_code ~= 0 then
          Utils.error(string.format("service %s failed to start, exit code: %d", container_name, exit_code))
        else
          Utils.debug(string.format("service %s started", container_name))
          cb()
        end
      end,
    })
  end
end

function M.stop_rag_service()
  if M.get_rag_service_runner() == "docker" then
    local cmd = string.format("docker ps -a | grep '%s'", container_name)
    local result = vim.fn.system(cmd)
    if result ~= "" then vim.fn.system(string.format("docker rm -fv %s", container_name)) end
  else
    local cmd = string.format("pgrep -f '%s' | xargs -r kill -9", service_path)
    vim.fn.system(cmd)
    Utils.debug(string.format("Attempted to kill processes related to %s", service_path))
  end
end

function M.get_rag_service_status()
  if M.get_rag_service_runner() == "docker" then
    local cmd = string.format("docker ps -a | grep '%s'", container_name)
    local result = vim.fn.system(cmd)
    if result == "" then
      return "stopped"
    else
      return "running"
    end
  elseif M.get_rag_service_runner() == "nix" then
    local cmd = string.format("pgrep -f '%s'", service_path)
    local result = vim.fn.system(cmd)
    if result == "" then
      return "stopped"
    else
      return "running"
    end
  end
end

function M.get_scheme(uri)
  local scheme = uri:match("^(%w+)://")
  if scheme == nil then return "unknown" end
  return scheme
end

function M.to_container_uri(uri)
  local runner = M.get_rag_service_runner()
  if runner == "nix" then return uri end
  local scheme = M.get_scheme(uri)
  if scheme == "file" then
    local path = uri:match("^file://(.*)$")
    local host_dir = Config.rag_service.host_mount
    if path:sub(1, #host_dir) == host_dir then path = "/host" .. path:sub(#host_dir + 1) end
    uri = string.format("file://%s", path)
  end
  return uri
end

function M.to_local_uri(uri)
  local scheme = M.get_scheme(uri)
  local path = uri:match("^file:///host(.*)$")

  if scheme == "file" and path ~= nil then
    local host_dir = Config.rag_service.host_mount
    local full_path = Path:new(host_dir):joinpath(path:sub(2)):absolute()
    uri = string.format("file://%s", full_path)
  end

  return uri
end

function M.is_ready()
  vim.fn.system(string.format("curl -s -o /dev/null -w '%%{http_code}' %s", M.get_rag_service_url()))
  return vim.v.shell_error == 0
end

---@class AvanteRagServiceAddResourceResponse
---@field status string
---@field message string

---@param uri string
function M.add_resource(uri)
  uri = M.to_container_uri(uri)
  local resource_name = uri:match("([^/]+)/$")
  local resources_resp = M.get_resources()
  if resources_resp == nil then
    Utils.error("Failed to get resources")
    return nil
  end
  local already_added = false
  for _, resource in ipairs(resources_resp.resources) do
    if resource.uri == uri then
      already_added = true
      resource_name = resource.name
      break
    end
  end
  if not already_added then
    local names_map = {}
    for _, resource in ipairs(resources_resp.resources) do
      names_map[resource.name] = true
    end
    if names_map[resource_name] then
      for i = 1, 100 do
        local resource_name_ = string.format("%s-%d", resource_name, i)
        if not names_map[resource_name_] then
          resource_name = resource_name_
          break
        end
      end
      if names_map[resource_name] then
        Utils.error(string.format("Failed to add resource, name conflict: %s", resource_name))
        return nil
      end
    end
  end
  local cmd = {
    "curl",
    "-X",
    "POST",
    M.get_rag_service_url() .. "/api/v1/add_resource",
    "-H",
    "Content-Type: application/json",
    "-d",
    vim.json.encode({ name = resource_name, uri = uri }),
  }
  vim.system(cmd, { text = true }, function(output)
    if output.code == 0 then
      Utils.debug(string.format("Added resource: %s", uri))
    else
      Utils.error(string.format("Failed to add resource: %s; output: %s", uri, output.stderr))
    end
  end)
end

function M.remove_resource(uri)
  uri = M.to_container_uri(uri)
  local resp = curl.post(M.get_rag_service_url() .. "/api/v1/remove_resource", {
    headers = {
      ["Content-Type"] = "application/json",
    },
    body = vim.json.encode({
      uri = uri,
    }),
  })
  if resp.status ~= 200 then
    Utils.error("failed to remove resource: " .. resp.body)
    return
  end
  return vim.json.decode(resp.body)
end

---@class AvanteRagServiceRetrieveSource
---@field uri string
---@field content string

---@class AvanteRagServiceRetrieveResponse
---@field response string
---@field sources AvanteRagServiceRetrieveSource[]

---@param base_uri string
---@param query string
---@return AvanteRagServiceRetrieveResponse | nil resp
---@return string | nil error
function M.retrieve(base_uri, query)
  base_uri = M.to_container_uri(base_uri)
  local resp = curl.post(M.get_rag_service_url() .. "/api/v1/retrieve", {
    headers = {
      ["Content-Type"] = "application/json",
    },
    body = vim.json.encode({
      base_uri = base_uri,
      query = query,
      top_k = 10,
    }),
    timeout = 100000,
  })
  if resp.status ~= 200 then
    Utils.error("failed to retrieve: " .. resp.body)
    return nil, "failed to retrieve: " .. resp.body
  end
  local jsn = vim.json.decode(resp.body)
  jsn.sources = vim
    .iter(jsn.sources)
    :map(function(source)
      local uri = M.to_local_uri(source.uri)
      return vim.tbl_deep_extend("force", source, { uri = uri })
    end)
    :totable()
  return jsn, nil
end

---@class AvanteRagServiceIndexingStatusSummary
---@field indexing integer
---@field completed integer
---@field failed integer

---@class AvanteRagServiceIndexingStatusResponse
---@field uri string
---@field is_watched boolean
---@field total_files integer
---@field status_summary AvanteRagServiceIndexingStatusSummary

---@param uri string
---@return AvanteRagServiceIndexingStatusResponse | nil
function M.indexing_status(uri)
  uri = M.to_container_uri(uri)
  local resp = curl.post(M.get_rag_service_url() .. "/api/v1/indexing_status", {
    headers = {
      ["Content-Type"] = "application/json",
    },
    body = vim.json.encode({
      uri = uri,
    }),
  })
  if resp.status ~= 200 then
    Utils.error("Failed to get indexing status: " .. resp.body)
    return
  end
  local jsn = vim.json.decode(resp.body)
  jsn.uri = M.to_local_uri(jsn.uri)
  return jsn
end

---@class AvanteRagServiceResource
---@field name string
---@field uri string
---@field type string
---@field status string
---@field indexing_status string
---@field created_at string
---@field indexing_started_at string | nil
---@field last_indexed_at string | nil

---@class AvanteRagServiceResourceListResponse
---@field resources AvanteRagServiceResource[]
---@field total_count number

---@return AvanteRagServiceResourceListResponse | nil
function M.get_resources()
  local resp = curl.get(M.get_rag_service_url() .. "/api/v1/resources", {
    headers = {
      ["Content-Type"] = "application/json",
    },
  })
  if resp.status ~= 200 then
    Utils.error("Failed to get resources: " .. resp.body)
    return
  end
  local jsn = vim.json.decode(resp.body)
  jsn.resources = vim
    .iter(jsn.resources)
    :map(function(resource)
      local uri = M.to_local_uri(resource.uri)
      return vim.tbl_deep_extend("force", resource, { uri = uri })
    end)
    :totable()
  return jsn
end

return M

local curl = require("plenary.curl")
local Config = require("avante.config")

local ModelFetcher = {}

function ModelFetcher.fetch_models(provider_name, state)
  local fetch_functions = {
    copilot = function()
      if not state.github_token then
        vim.notify("GitHub token not available. Cannot fetch Copilot models.", vim.log.levels.WARN)
        return
      end
      
      local provider_config = Config.get_provider_config("copilot")
      local endpoint = provider_config.endpoint
      
      local response = curl.get(endpoint .. "/models", {
        headers = {
          ["Authorization"] = "Bearer " .. state.github_token.token,
          ["Editor-Version"] = ("Neovim/%s.%s.%s"):format(
            vim.version().major,
            vim.version().minor,
            vim.version().patch
          ),
          ["Editor-Plugin-Version"] = "CopilotChat.nvim/1.0.0",
          ["Copilot-Integration-Id"] = "vscode-chat",
        },
        timeout = Config.copilot.timeout,
        proxy = Config.copilot.proxy,
        insecure = Config.copilot.allow_insecure,
      })

      if response.status == 200 then
        local models = vim.json.decode(response.body).data
        Config.override({ copilot = { dynamic_models = models } })
      else
        error("Failed to fetch Copilot models: " .. vim.inspect(response))
      end
    end,
  }

  local fetch_function = fetch_functions[provider_name]
  if fetch_function then
    return fetch_function()
  else
    error("No fetch function found for provider: " .. provider_name)
  end
end

return ModelFetcher

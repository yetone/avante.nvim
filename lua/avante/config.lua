---NOTE: user will be merged with defaults and
---we add a default var_accessor for this table to config values.

---@alias WebSearchEngineProviderResponseBodyFormatter fun(body: table): (string, string?)
---@alias avante.InputProvider "native" | "dressing" | "snacks" | fun(input: avante.ui.Input): nil

local Utils = require("avante.utils")

---@class avante.file_selector.IParams
---@field public title      string
---@field public filepaths  string[]
---@field public handler    fun(filepaths: string[]|nil): nil

---@class avante.file_selector.opts.IGetFilepathsParams
---@field public cwd                string
---@field public selected_filepaths string[]

---@class avante.CoreConfig: avante.Config
local M = {}
---@class avante.Config
M._defaults = {
  debug = false,
  ---@alias avante.Mode "agentic" | "legacy"
  ---@type avante.Mode
  mode = "agentic",
  ---@alias avante.ProviderName "claude" | "openai" | "azure" | "gemini" | "vertex" | "cohere" | "copilot" | "bedrock" | "ollama" | string
  ---@type avante.ProviderName
  provider = "claude",
  -- WARNING: Since auto-suggestions are a high-frequency operation and therefore expensive,
  -- currently designating it as `copilot` provider is dangerous because: https://github.com/yetone/avante.nvim/issues/1048
  -- Of course, you can reduce the request frequency by increasing `suggestion.debounce`.
  auto_suggestions_provider = nil,
  memory_summary_provider = nil,
  ---@alias Tokenizer "tiktoken" | "hf"
  ---@type Tokenizer
  -- Used for counting tokens and encoding text.
  -- By default, we will use tiktoken.
  -- For most providers that we support we will determine this automatically.
  -- If you wish to use a given implementation, then you can override it here.
  tokenizer = "tiktoken",
  ---@type string | fun(): string | nil
  system_prompt = nil,
  ---@type string | fun(): string | nil
  override_prompt_dir = nil,
  rules = {
    project_dir = nil, ---@type string | nil (could be relative dirpath)
    global_dir = nil, ---@type string | nil (absolute dirpath)
  },
  rag_service = { -- RAG service configuration
    enabled = false, -- Enables the RAG service
    host_mount = os.getenv("HOME"), -- Host mount path for the RAG service (Docker will mount this path)
    runner = "docker", -- The runner for the RAG service (can use docker or nix)
    llm = { -- Configuration for the Language Model (LLM) used by the RAG service
      provider = "openai", -- The LLM provider
      endpoint = "https://api.openai.com/v1", -- The LLM API endpoint
      api_key = "OPENAI_API_KEY", -- The environment variable name for the LLM API key
      model = "gpt-4o-mini", -- The LLM model name
      extra = nil, -- Extra configuration options for the LLM
    },
    embed = { -- Configuration for the Embedding model used by the RAG service
      provider = "openai", -- The embedding provider
      endpoint = "https://api.openai.com/v1", -- The embedding API endpoint
      api_key = "OPENAI_API_KEY", -- The environment variable name for the embedding API key
      model = "text-embedding-3-large", -- The embedding model name
      extra = nil, -- Extra configuration options for the embedding model
    },
    docker_extra_args = "", -- Extra arguments to pass to the docker command
  },
  web_search_engine = {
    provider = "tavily",
    proxy = nil,
    providers = {
      tavily = {
        api_key_name = "TAVILY_API_KEY",
        extra_request_body = {
          include_answer = "basic",
        },
        ---@type WebSearchEngineProviderResponseBodyFormatter
        format_response_body = function(body) return body.answer, nil end,
      },
      serpapi = {
        api_key_name = "SERPAPI_API_KEY",
        extra_request_body = {
          engine = "google",
          google_domain = "google.com",
        },
        ---@type WebSearchEngineProviderResponseBodyFormatter
        format_response_body = function(body)
          if body.answer_box ~= nil and body.answer_box.result ~= nil then return body.answer_box.result, nil end
          if body.organic_results ~= nil then
            local jsn = vim
              .iter(body.organic_results)
              :map(
                function(result)
                  return {
                    title = result.title,
                    link = result.link,
                    snippet = result.snippet,
                    date = result.date,
                  }
                end
              )
              :take(10)
              :totable()
            return vim.json.encode(jsn), nil
          end
          return "", nil
        end,
      },
      searchapi = {
        api_key_name = "SEARCHAPI_API_KEY",
        extra_request_body = {
          engine = "google",
        },
        ---@type WebSearchEngineProviderResponseBodyFormatter
        format_response_body = function(body)
          if body.answer_box ~= nil then return body.answer_box.result, nil end
          if body.organic_results ~= nil then
            local jsn = vim
              .iter(body.organic_results)
              :map(
                function(result)
                  return {
                    title = result.title,
                    link = result.link,
                    snippet = result.snippet,
                    date = result.date,
                  }
                end
              )
              :take(10)
              :totable()
            return vim.json.encode(jsn), nil
          end
          return "", nil
        end,
      },
      google = {
        api_key_name = "GOOGLE_SEARCH_API_KEY",
        engine_id_name = "GOOGLE_SEARCH_ENGINE_ID",
        extra_request_body = {},
        ---@type WebSearchEngineProviderResponseBodyFormatter
        format_response_body = function(body)
          if body.items ~= nil then
            local jsn = vim
              .iter(body.items)
              :map(
                function(result)
                  return {
                    title = result.title,
                    link = result.link,
                    snippet = result.snippet,
                  }
                end
              )
              :take(10)
              :totable()
            return vim.json.encode(jsn), nil
          end
          return "", nil
        end,
      },
      kagi = {
        api_key_name = "KAGI_API_KEY",
        extra_request_body = {
          limit = "10",
        },
        ---@type WebSearchEngineProviderResponseBodyFormatter
        format_response_body = function(body)
          if body.data ~= nil then
            local jsn = vim
              .iter(body.data)
              -- search results only
              :filter(function(result) return result.t == 0 end)
              :map(
                function(result)
                  return {
                    title = result.title,
                    url = result.url,
                    snippet = result.snippet,
                  }
                end
              )
              :take(10)
              :totable()
            return vim.json.encode(jsn), nil
          end
          return "", nil
        end,
      },
      brave = {
        api_key_name = "BRAVE_API_KEY",
        extra_request_body = {
          count = "10",
          result_filter = "web",
        },
        format_response_body = function(body)
          if body.web == nil then return "", nil end

          local jsn = vim.iter(body.web.results):map(
            function(result)
              return {
                title = result.title,
                url = result.url,
                snippet = result.description,
              }
            end
          )

          return vim.json.encode(jsn), nil
        end,
      },
      searxng = {
        api_url_name = "SEARXNG_API_URL",
        extra_request_body = {
          format = "json",
        },
        ---@type WebSearchEngineProviderResponseBodyFormatter
        format_response_body = function(body)
          if body.results == nil then return "", nil end

          local jsn = vim.iter(body.results):map(
            function(result)
              return {
                title = result.title,
                url = result.url,
                snippet = result.content,
              }
            end
          )

          return vim.json.encode(jsn), nil
        end,
      },
    },
  },
  ---To add support for custom provider, follow the format below
  ---See https://github.com/yetone/avante.nvim/wiki#custom-providers for more details
  ---@type {[string]: AvanteProvider}
  providers = {
    ---@type AvanteSupportedProvider
    openai = {
      endpoint = "https://api.openai.com/v1",
      model = "gpt-4o",
      timeout = 30000, -- Timeout in milliseconds, increase this for reasoning models
      context_window = 128000, -- Number of tokens to send to the model for context
      extra_request_body = {
        temperature = 0.75,
        max_completion_tokens = 16384, -- Increase this to include reasoning tokens (for reasoning models)
        reasoning_effort = "medium", -- low|medium|high, only used for reasoning models
      },
    },
    ---@type AvanteSupportedProvider
    copilot = {
      endpoint = "https://api.githubcopilot.com",
      model = "gpt-4o-2024-11-20",
      proxy = nil, -- [protocol://]host[:port] Use this proxy
      allow_insecure = false, -- Allow insecure server connections
      timeout = 30000, -- Timeout in milliseconds
      context_window = 64000, -- Number of tokens to send to the model for context
      extra_request_body = {
        temperature = 0.75,
        max_tokens = 20480,
      },
    },
    ---@type AvanteAzureProvider
    azure = {
      endpoint = "", -- example: "https://<your-resource-name>.openai.azure.com"
      deployment = "", -- Azure deployment name (e.g., "gpt-4o", "my-gpt-4o-deployment")
      api_version = "2024-12-01-preview",
      timeout = 30000, -- Timeout in milliseconds, increase this for reasoning models
      extra_request_body = {
        temperature = 0.75,
        max_completion_tokens = 20480, -- Increase this to include reasoning tokens (for reasoning models)
        reasoning_effort = "medium", -- low|medium|high, only used for reasoning models
      },
    },
    ---@type AvanteSupportedProvider
    claude = {
      endpoint = "https://api.anthropic.com",
      model = "claude-sonnet-4-20250514",
      timeout = 30000, -- Timeout in milliseconds
      context_window = 200000,
      extra_request_body = {
        temperature = 0.75,
        max_tokens = 64000,
      },
    },
    ---@type AvanteSupportedProvider
    bedrock = {
      model = "anthropic.claude-3-5-sonnet-20241022-v2:0",
      timeout = 30000, -- Timeout in milliseconds
      extra_request_body = {
        temperature = 0.75,
        max_tokens = 20480,
      },
      aws_region = "", -- AWS region to use for authentication and bedrock API
      aws_profile = "", -- AWS profile to use for authentication, if unspecified uses default credentials chain
    },
    ---@type AvanteSupportedProvider
    gemini = {
      endpoint = "https://generativelanguage.googleapis.com/v1beta/models",
      model = "gemini-2.0-flash",
      timeout = 30000, -- Timeout in milliseconds
      context_window = 1048576,
      use_ReAct_prompt = true,
      extra_request_body = {
        generationConfig = {
          temperature = 0.75,
        },
      },
    },
    ---@type AvanteSupportedProvider
    vertex = {
      endpoint = "https://aiplatform.googleapis.com/v1/projects/PROJECT_ID/locations/LOCATION/publishers/google/models",
      model = "gemini-1.5-flash-002",
      timeout = 30000, -- Timeout in milliseconds
      context_window = 1048576,
      use_ReAct_prompt = true,
      extra_request_body = {
        generationConfig = {
          temperature = 0.75,
        },
      },
    },
    ---@type AvanteSupportedProvider
    cohere = {
      endpoint = "https://api.cohere.com/v2",
      model = "command-r-plus-08-2024",
      timeout = 30000, -- Timeout in milliseconds
      extra_request_body = {
        temperature = 0.75,
        max_tokens = 20480,
      },
    },
    ---@type AvanteSupportedProvider
    ollama = {
      endpoint = "http://127.0.0.1:11434",
      timeout = 30000, -- Timeout in milliseconds
      extra_request_body = {
        options = {
          temperature = 0.75,
          num_ctx = 20480,
          keep_alive = "5m",
        },
      },
    },
    ---@type AvanteSupportedProvider
    vertex_claude = {
      endpoint = "https://LOCATION-aiplatform.googleapis.com/v1/projects/PROJECT_ID/locations/LOCATION/publishers/antrhopic/models",
      model = "claude-3-5-sonnet-v2@20241022",
      timeout = 30000, -- Timeout in milliseconds
      extra_request_body = {
        temperature = 0.75,
        max_tokens = 20480,
      },
    },
    ---@type AvanteSupportedProvider
    ["claude-haiku"] = {
      __inherited_from = "claude",
      model = "claude-3-5-haiku-20241022",
      timeout = 30000, -- Timeout in milliseconds
      extra_request_body = {
        temperature = 0.75,
        max_tokens = 8192,
      },
    },
    ---@type AvanteSupportedProvider
    ["claude-opus"] = {
      __inherited_from = "claude",
      model = "claude-3-opus-20240229",
      timeout = 30000, -- Timeout in milliseconds
      extra_request_body = {
        temperature = 0.75,
        max_tokens = 20480,
      },
    },
    ["openai-gpt-4o-mini"] = {
      __inherited_from = "openai",
      model = "gpt-4o-mini",
    },
    aihubmix = {
      __inherited_from = "openai",
      endpoint = "https://aihubmix.com/v1",
      model = "gpt-4o-2024-11-20",
      api_key_name = "AIHUBMIX_API_KEY",
    },
    ["aihubmix-claude"] = {
      __inherited_from = "claude",
      endpoint = "https://aihubmix.com",
      model = "claude-3-7-sonnet-20250219",
      api_key_name = "AIHUBMIX_API_KEY",
    },
    ["bedrock-claude-3.7-sonnet"] = {
      __inherited_from = "bedrock",
      model = "us.anthropic.claude-3-7-sonnet-20250219-v1:0",
      extra_request_body = {
        max_tokens = 4096,
      },
    },
    morph = {
      __inherited_from = "openai",
      endpoint = "https://api.morphllm.com/v1",
      model = "auto",
      api_key_name = "MORPH_API_KEY",
    },
    moonshot = {
      __inherited_from = "openai",
      endpoint = "https://api.moonshot.ai/v1",
      model = "kimi-k2-0711-preview",
      api_key_name = "MOONSHOT_API_KEY",
    },
  },
  ---Specify the special dual_boost mode
  ---1. enabled: Whether to enable dual_boost mode. Default to false.
  ---2. first_provider: The first provider to generate response. Default to "openai".
  ---3. second_provider: The second provider to generate response. Default to "claude".
  ---4. prompt: The prompt to generate response based on the two reference outputs.
  ---5. timeout: Timeout in milliseconds. Default to 60000.
  ---How it works:
  --- When dual_boost is enabled, avante will generate two responses from the first_provider and second_provider respectively. Then use the response from the first_provider as provider1_output and the response from the second_provider as provider2_output. Finally, avante will generate a response based on the prompt and the two reference outputs, with the default Provider as normal.
  ---Note: This is an experimental feature and may not work as expected.
  dual_boost = {
    enabled = false,
    first_provider = "openai",
    second_provider = "claude",
    prompt = "Based on the two reference outputs below, generate a response that incorporates elements from both but reflects your own judgment and unique perspective. Do not provide any explanation, just give the response directly. Reference Output 1: [{{provider1_output}}], Reference Output 2: [{{provider2_output}}]",
    timeout = 60000, -- Timeout in milliseconds
  },
  ---Specify the behaviour of avante.nvim
  ---1. auto_focus_sidebar              : Whether to automatically focus the sidebar when opening avante.nvim. Default to true.
  ---2. auto_suggestions = false, -- Whether to enable auto suggestions. Default to false.
  ---3. auto_apply_diff_after_generation: Whether to automatically apply diff after LLM response.
  ---                                     This would simulate similar behaviour to cursor. Default to false.
  ---4. auto_set_keymaps                : Whether to automatically set the keymap for the current line. Default to true.
  ---                                     Note that avante will safely set these keymap. See https://github.com/yetone/avante.nvim/wiki#keymaps-and-api-i-guess for more details.
  ---5. auto_set_highlight_group        : Whether to automatically set the highlight group for the current line. Default to true.
  ---6. jump_result_buffer_on_finish = false, -- Whether to automatically jump to the result buffer after generation
  ---7. support_paste_from_clipboard    : Whether to support pasting image from clipboard. This will be determined automatically based whether img-clip is available or not.
  ---8. minimize_diff                   : Whether to remove unchanged lines when applying a code block
  ---9. enable_token_counting           : Whether to enable token counting. Default to true.
  behaviour = {
    auto_focus_sidebar = true,
    auto_suggestions = false, -- Experimental stage
    auto_suggestions_respect_ignore = false,
    auto_set_highlight_group = true,
    auto_set_keymaps = true,
    auto_apply_diff_after_generation = false,
    jump_result_buffer_on_finish = false,
    support_paste_from_clipboard = false,
    minimize_diff = true,
    enable_token_counting = true,
    use_cwd_as_project_root = false,
    auto_focus_on_diff_view = false,
    ---@type boolean | string[] -- true: auto-approve all tools, false: normal prompts, string[]: auto-approve specific tools by name
    auto_approve_tool_permissions = false, -- Default: show permission prompts for all tools
    auto_check_diagnostics = true,
    enable_fastapply = false,
  },
  prompt_logger = { -- logs prompts to disk (timestamped, for replay/debugging)
    enabled = true, -- toggle logging entirely
    log_dir = vim.fn.stdpath("cache"), -- directory where logs are saved
    max_entries = 100, -- the uplimit of entries that can be sotred
    next_prompt = {
      normal = "<C-n>", -- load the next (newer) prompt log in normal mode
      insert = "<C-n>",
    },
    prev_prompt = {
      normal = "<C-p>", -- load the previous (older) prompt log in normal mode
      insert = "<C-p>",
    },
  },
  history = {
    max_tokens = 4096,
    carried_entry_count = nil,
    storage_path = Utils.join_paths(vim.fn.stdpath("state"), "avante"),
    paste = {
      extension = "png",
      filename = "pasted-%Y-%m-%d-%H-%M-%S",
    },
  },
  highlights = {
    diff = {
      current = nil,
      incoming = nil,
    },
  },
  img_paste = {
    url_encode_path = true,
    template = "\nimage: $FILE_PATH\n",
  },
  mappings = {
    ---@class AvanteConflictMappings
    diff = {
      ours = "co",
      theirs = "ct",
      all_theirs = "ca",
      both = "cb",
      cursor = "cc",
      next = "]x",
      prev = "[x",
    },
    suggestion = {
      accept = "<M-l>",
      next = "<M-]>",
      prev = "<M-[>",
      dismiss = "<C-]>",
    },
    jump = {
      next = "]]",
      prev = "[[",
    },
    submit = {
      normal = "<CR>",
      insert = "<C-s>",
    },
    cancel = {
      normal = { "<C-c>", "<Esc>", "q" },
      insert = { "<C-c>" },
    },
    -- NOTE: The following will be safely set by avante.nvim
    ask = "<leader>aa",
    new_ask = "<leader>an",
    edit = "<leader>ae",
    refresh = "<leader>ar",
    focus = "<leader>af",
    stop = "<leader>aS",
    toggle = {
      default = "<leader>at",
      debug = "<leader>ad",
      hint = "<leader>ah",
      suggestion = "<leader>as",
      repomap = "<leader>aR",
    },
    sidebar = {
      next_prompt = "]p",
      prev_prompt = "[p",
      apply_all = "A",
      apply_cursor = "a",
      retry_user_request = "r",
      edit_user_request = "e",
      switch_windows = "<Tab>",
      reverse_switch_windows = "<S-Tab>",
      toggle_code_window = "x",
      remove_file = "d",
      add_file = "@",
      close = { "q" },
      ---@alias AvanteCloseFromInput { normal: string | nil, insert: string | nil }
      ---@type AvanteCloseFromInput | nil
      close_from_input = nil, -- e.g., { normal = "<Esc>", insert = "<C-d>" }
      ---@alias AvanteToggleCodeWindowFromInput { normal: string | nil, insert: string | nil }
      ---@type AvanteToggleCodeWindowFromInput | nil
      toggle_code_window_from_input = nil, -- e.g., { normal = "x", insert = "<C-;>" }
    },
    files = {
      add_current = "<leader>ac", -- Add current buffer to selected files
      add_all_buffers = "<leader>aB", -- Add all buffer files to selected files
    },
    select_model = "<leader>a?", -- Select model command
    select_history = "<leader>ah", -- Select history command
    confirm = {
      focus_window = "<C-w>f",
      code = "c",
      resp = "r",
      input = "i",
    },
  },
  windows = {
    ---@alias AvantePosition "right" | "left" | "top" | "bottom" | "smart"
    ---@type AvantePosition
    position = "right",
    fillchars = "eob: ",
    wrap = true, -- similar to vim.o.wrap
    width = 30, -- default % based on available width in vertical layout
    height = 30, -- default % based on available height in horizontal layout
    sidebar_header = {
      enabled = true, -- true, false to enable/disable the header
      align = "center", -- left, center, right for title
      rounded = true,
    },
    spinner = {
      editing = {
        "⡀",
        "⠄",
        "⠂",
        "⠁",
        "⠈",
        "⠐",
        "⠠",
        "⢀",
        "⣀",
        "⢄",
        "⢂",
        "⢁",
        "⢈",
        "⢐",
        "⢠",
        "⣠",
        "⢤",
        "⢢",
        "⢡",
        "⢨",
        "⢰",
        "⣰",
        "⢴",
        "⢲",
        "⢱",
        "⢸",
        "⣸",
        "⢼",
        "⢺",
        "⢹",
        "⣹",
        "⢽",
        "⢻",
        "⣻",
        "⢿",
        "⣿",
      },
      generating = { "·", "✢", "✳", "∗", "✻", "✽" },
      thinking = { "🤯", "🙄" },
    },
    input = {
      prefix = "> ",
      height = 8, -- Height of the input window in vertical layout
    },
    edit = {
      border = { " ", " ", " ", " ", " ", " ", " ", " " },
      start_insert = true, -- Start insert mode when opening the edit window
    },
    ask = {
      floating = false, -- Open the 'AvanteAsk' prompt in a floating window
      border = { " ", " ", " ", " ", " ", " ", " ", " " },
      start_insert = true, -- Start insert mode when opening the ask window
      ---@alias AvanteInitialDiff "ours" | "theirs"
      ---@type AvanteInitialDiff
      focus_on_apply = "ours", -- which diff to focus after applying
    },
  },
  --- @class AvanteConflictConfig
  diff = {
    autojump = true,
    --- Override the 'timeoutlen' setting while hovering over a diff (see :help timeoutlen).
    --- Helps to avoid entering operator-pending mode with diff mappings starting with `c`.
    --- Disable by setting to -1.
    override_timeoutlen = 500,
  },
  --- @class AvanteHintsConfig
  hints = {
    enabled = true,
  },
  --- @class AvanteRepoMapConfig
  repo_map = {
    ignore_patterns = { "%.git", "%.worktree", "__pycache__", "node_modules" }, -- ignore files matching these
    negate_patterns = {}, -- negate ignore files matching these.
  },
  --- @class AvanteFileSelectorConfig
  file_selector = {
    provider = nil,
    -- Options override for custom providers
    provider_opts = {},
  },
  selector = {
    ---@alias avante.SelectorProvider "native" | "fzf_lua" | "mini_pick" | "snacks" | "telescope" | fun(selector: avante.ui.Selector): nil
    ---@type avante.SelectorProvider
    provider = "native",
    provider_opts = {},
    exclude_auto_select = {}, -- List of items to exclude from auto selection
  },
  input = {
    provider = "native",
    provider_opts = {},
  },
  suggestion = {
    debounce = 600,
    throttle = 600,
  },
  disabled_tools = {}, ---@type string[]
  ---@type AvanteLLMToolPublic[] | fun(): AvanteLLMToolPublic[]
  custom_tools = {},
  ---@type AvanteSlashCommand[]
  slash_commands = {},
  ---@type AvanteShortcut[]
  shortcuts = {},
}

---@type avante.Config
---@diagnostic disable-next-line: missing-fields
M._options = {}

local function get_config_dir_path() return Utils.join_paths(vim.fn.expand("~"), ".config", "avante.nvim") end
local function get_config_file_path() return Utils.join_paths(get_config_dir_path(), "config.json") end

--- Function to save the last used model
---@param model_name string
function M.save_last_model(model_name, provider_name)
  local config_dir = get_config_dir_path()
  local storage_path = get_config_file_path()

  if not Utils.path_exists(config_dir) then vim.fn.mkdir(config_dir, "p") end

  local file = io.open(storage_path, "w")
  if file then
    file:write(vim.json.encode({ last_model = model_name, last_provider = provider_name }))
    file:close()
  end
end

--- Retrieves names of the last used model and provider. May remove saved config if it is deemed invalid
---@param known_providers table<string, AvanteSupportedProvider>
---@return string|nil Model name
---@return string|nil Provider name
function M.get_last_used_model(known_providers)
  local storage_path = get_config_file_path()
  local file = io.open(storage_path, "r")
  if file then
    local content = file:read("*a")
    file:close()

    if not content or content == "" then
      Utils.warn("Last used model file is empty: " .. storage_path)
      -- Remove to not have repeated warnings
      os.remove(storage_path)
    end

    local success, data = pcall(vim.json.decode, content)
    if not success or not data or not data.last_model or data.last_model == "" or data.last_provider == "" then
      Utils.warn("Invalid or corrupt JSON in last used model file: " .. storage_path)
      -- Rename instead of deleting so user can examine contents
      os.rename(storage_path, storage_path .. ".bad")
      return
    end

    if data.last_provider and not known_providers[data.last_provider] then
      Utils.warn(
        "Provider " .. data.last_provider .. " is no longer a valid provider, falling back to default configuration"
      )
      os.remove(storage_path)
      return
    end

    return data.last_model, data.last_provider
  end
end

---Applies given model and provider to the config
---@param config avante.Config
---@param model_name string
---@param provider_name? string
local function apply_model_selection(config, model_name, provider_name)
  local provider_list = config.providers or {}
  local current_provider_name = config.provider

  local target_provider_name = provider_name or current_provider_name
  local target_provider = provider_list[target_provider_name]

  if not target_provider then return end

  local current_provider_data = provider_list[current_provider_name]
  local current_model_name = current_provider_data and current_provider_data.model

  if target_provider_name ~= current_provider_name or model_name ~= current_model_name then
    config.provider = target_provider_name
    target_provider.model = model_name
    Utils.info(string.format("Using previously selected model: %s/%s", target_provider_name, model_name))
  end
end

---@param opts table<string, any>|nil -- Optional table parameter for configuration settings
function M.setup(opts)
  opts = opts or {} -- Ensure `opts` is defined with a default table
  if vim.fn.has("nvim-0.11") == 1 then
    vim.validate("opts", opts, "table", true)
  else
    vim.validate({ opts = { opts, "table", true } })
  end

  opts = opts or {}

  local migration_url = "https://github.com/yetone/avante.nvim/wiki/Provider-configuration-migration-guide"

  if opts.providers ~= nil then
    for k, v in pairs(opts.providers) do
      local extra_request_body
      if type(v) == "table" then
        if M._defaults.providers[k] ~= nil then
          extra_request_body = M._defaults.providers[k].extra_request_body
        elseif v.__inherited_from ~= nil then
          if M._defaults.providers[v.__inherited_from] ~= nil then
            extra_request_body = M._defaults.providers[v.__inherited_from].extra_request_body
          end
        end
      end
      if extra_request_body ~= nil then
        for k_, v_ in pairs(v) do
          if extra_request_body[k_] ~= nil then
            opts.providers[k].extra_request_body = opts.providers[k].extra_request_body or {}
            opts.providers[k].extra_request_body[k_] = v_
            Utils.warn(
              string.format(
                "[DEPRECATED] The configuration of `providers.%s.%s` should be placed in `providers.%s.extra_request_body.%s`; for detailed migration instructions, please visit: %s",
                k,
                k_,
                k,
                k_,
                migration_url
              ),
              { title = "Avante" }
            )
          end
        end
      end
    end
  end

  for k, v in pairs(opts) do
    if M._defaults.providers[k] ~= nil then
      opts.providers = opts.providers or {}
      opts.providers[k] = v
      Utils.warn(
        string.format(
          "[DEPRECATED] The configuration of `%s` should be placed in `providers.%s`. For detailed migration instructions, please visit: %s",
          k,
          k,
          migration_url
        ),
        { title = "Avante" }
      )
      local extra_request_body = M._defaults.providers[k].extra_request_body
      if type(v) == "table" and extra_request_body ~= nil then
        for k_, v_ in pairs(v) do
          if extra_request_body[k_] ~= nil then
            opts.providers[k].extra_request_body = opts.providers[k].extra_request_body or {}
            opts.providers[k].extra_request_body[k_] = v_
            Utils.warn(
              string.format(
                "[DEPRECATED] The configuration of `%s.%s` should be placed in `providers.%s.extra_request_body.%s`; for detailed migration instructions, please visit: %s",
                k,
                k_,
                k,
                k_,
                migration_url
              ),
              { title = "Avante" }
            )
          end
        end
      end
    end
    if k == "vendors" and v ~= nil then
      for k2, v2 in pairs(v) do
        opts.providers = opts.providers or {}
        opts.providers[k2] = v2
        Utils.warn(
          string.format(
            "[DEPRECATED] The configuration of `vendors.%s` should be placed in `providers.%s`. For detailed migration instructions, please visit: %s",
            k2,
            k2,
            migration_url
          ),
          { title = "Avante" }
        )
        if
          type(v2) == "table"
          and v2.__inherited_from ~= nil
          and M._defaults.providers[v2.__inherited_from] ~= nil
        then
          local extra_request_body = M._defaults.providers[v2.__inherited_from].extra_request_body
          if extra_request_body ~= nil then
            for k2_, v2_ in pairs(v2) do
              if extra_request_body[k2_] ~= nil then
                opts.providers[k2].extra_request_body = opts.providers[k2].extra_request_body or {}
                opts.providers[k2].extra_request_body[k2_] = v2_
                Utils.warn(
                  string.format(
                    "[DEPRECATED] The configuration of `vendors.%s.%s` should be placed in `providers.%s.extra_request_body.%s`; for detailed migration instructions, please visit: %s",
                    k2,
                    k2_,
                    k2,
                    k2_,
                    migration_url
                  ),
                  { title = "Avante" }
                )
              end
            end
          end
        end
      end
    end
  end

  local merged = vim.tbl_deep_extend(
    "force",
    M._defaults,
    opts,
    ---@type avante.Config
    {
      behaviour = {
        support_paste_from_clipboard = M.support_paste_image(),
      },
    }
  )

  local last_model, last_provider = M.get_last_used_model(merged.providers or {})
  if last_model then apply_model_selection(merged, last_model, last_provider) end

  M._options = merged

  ---@diagnostic disable-next-line: undefined-field
  if M._options.disable_tools ~= nil then
    Utils.warn(
      "`disable_tools` is provider-scoped, not globally scoped. Therefore, you cannot set `disable_tools` at the top level. It should be set under a provider, for example: `openai.disable_tools = true`",
      { title = "Avante" }
    )
  end

  if type(M._options.disabled_tools) == "boolean" then
    Utils.warn(
      '`disabled_tools` must be a list, not a boolean. Please change it to `disabled_tools = { "tool1", "tool2" }`. Note the difference between `disabled_tools` and `disable_tools`.',
      { title = "Avante" }
    )
  end

  if vim.fn.has("nvim-0.11") == 1 then
    vim.validate("provider", M._options.provider, "string", false)
  else
    vim.validate({ provider = { M._options.provider, "string", false } })
  end

  for k, v in pairs(M._options.providers) do
    M._options.providers[k] = type(v) == "function" and v() or v
  end
end

---@param opts table<string, any>
function M.override(opts)
  if vim.fn.has("nvim-0.11") == 1 then
    vim.validate("opts", opts, "table", true)
  else
    vim.validate({ opts = { opts, "table", true } })
  end

  M._options = vim.tbl_deep_extend("force", M._options, opts or {})

  for k, v in pairs(M._options.providers) do
    M._options.providers[k] = type(v) == "function" and v() or v
  end
end

M = setmetatable(M, {
  __index = function(_, k)
    if M._options[k] then return M._options[k] end
  end,
})

function M.support_paste_image() return Utils.has("img-clip.nvim") or Utils.has("img-clip") end

function M.get_window_width() return math.ceil(vim.o.columns * (M.windows.width / 100)) end

---get supported providers
---@param provider_name avante.ProviderName
function M.get_provider_config(provider_name)
  local found = false
  local config = {}

  if M.providers[provider_name] ~= nil then
    found = true
    config = vim.tbl_deep_extend("force", config, vim.deepcopy(M.providers[provider_name], true))
  end

  if not found then error("Failed to find provider: " .. provider_name, 2) end

  return config
end

return M

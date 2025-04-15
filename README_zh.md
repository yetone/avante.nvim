<div align="center">
  <img alt="logo" width="120" src="https://github.com/user-attachments/assets/2e2f2a58-2b28-4d11-afd1-87b65612b2de" />
  <h1>avante.nvim</h1>
</div>

<div align="center">
  <a href="https://neovim.io/" target="_blank">
    <img src="https://img.shields.io/static/v1?style=flat-square&label=Neovim&message=v0.10%2b&logo=neovim&labelColor=282828&logoColor=8faa80&color=414b32" alt="Neovim: v0.10+" />
  </a>
  <a href="https://github.com/yetone/avante.nvim/actions/workflows/lua.yaml" target="_blank">
    <img src="https://img.shields.io/github/actions/workflow/status/yetone/avante.nvim/lua.yaml?style=flat-square&logo=lua&logoColor=c7c7c7&label=Lua+CI&labelColor=1E40AF&color=347D39&event=push" alt="Lua CI status" />
  </a>
  <a href="https://github.com/yetone/avante.nvim/actions/workflows/rust.yaml" target="_blank">
    <img src="https://img.shields.io/github/actions/workflow/status/yetone/avante.nvim/rust.yaml?style=flat-square&logo=rust&logoColor=ffffff&label=Rust+CI&labelColor=BC826A&color=347D39&event=push" alt="Rust CI status" />
  </a>
  <a href="https://github.com/yetone/avante.nvim/actions/workflows/pre-commit.yaml" target="_blank">
    <img src="https://img.shields.io/github/actions/workflow/status/yetone/avante.nvim/pre-commit.yaml?style=flat-square&logo=pre-commit&logoColor=ffffff&label=pre-commit&labelColor=FAAF3F&color=347D39&event=push" alt="pre-commit status" />
  </a>
  <a href="https://discord.gg/QfnEFEdSjz" target="_blank">
    <img src="https://img.shields.io/discord/1302530866362323016?style=flat-square&logo=discord&label=Discord&logoColor=ffffff&labelColor=7376CF&color=268165" alt="Discord" />
  </a>
  <a href="https://dotfyle.com/plugins/yetone/avante.nvim">
    <img src="https://dotfyle.com/plugins/yetone/avante.nvim/shield?style=flat-square" />
  </a>
</div>

**avante.nvim** 是一个 Neovim 插件，旨在模拟 [Cursor](https://www.cursor.com) AI IDE 的行为。它为用户提供 AI 驱动的代码建议，并能够轻松地将这些建议直接应用到源文件中。

[View in English](README.md)

> [!NOTE]
>
> 🥰 该项目正在快速迭代中，许多令人兴奋的功能将陆续添加。敬请期待！

<https://github.com/user-attachments/assets/510e6270-b6cf-459d-9a2f-15b397d1fe53>

<https://github.com/user-attachments/assets/86140bfd-08b4-483d-a887-1b701d9e37dd>

## 赞助 ❤️

如果您喜欢这个项目，请考虑在 Patreon 上支持我，因为这有助于我继续维护和改进它：

[赞助我](https://patreon.com/yetone)

## 功能

- **AI 驱动的代码辅助**：与 AI 互动，询问有关当前代码文件的问题，并接收智能建议以进行改进或修改。
- **一键应用**：通过单个命令快速将 AI 的建议更改应用到源代码中，简化编辑过程并节省时间。

## 安装

如果您希望从源代码构建二进制文件，则需要 `cargo`。否则，将使用 `curl` 和 `tar` 从 GitHub 获取预构建的二进制文件。

<details open>

  <summary><a href="https://github.com/folke/lazy.nvim">lazy.nvim</a> (推荐)</summary>

```lua
{
  "yetone/avante.nvim",
  event = "VeryLazy",
  version = false, -- 永远不要将此值设置为 "*"！永远不要！
  opts = {
    -- 在此处添加任何选项
    -- 例如
    provider = "openai",
    openai = {
      endpoint = "https://api.openai.com/v1",
      model = "gpt-4o", -- 您想要的模型（或使用 gpt-4o 等）
      timeout = 30000, -- 超时时间（毫秒），增加此值以适应推理模型
      temperature = 0,
      max_tokens = 8192, -- 增加此值以包括推理模型的推理令牌
      --reasoning_effort = "medium", -- low|medium|high，仅用于推理模型
    },
  },
  -- 如果您想从源代码构建，请执行 `make BUILD_FROM_SOURCE=true`
  build = "make",
  -- build = "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false" -- 对于 Windows
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "stevearc/dressing.nvim",
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    --- 以下依赖项是可选的，
    "echasnovski/mini.pick", -- 用于文件选择器提供者 mini.pick
    "nvim-telescope/telescope.nvim", -- 用于文件选择器提供者 telescope
    "hrsh7th/nvim-cmp", -- avante 命令和提及的自动完成
    "ibhagwan/fzf-lua", -- 用于文件选择器提供者 fzf
    "nvim-tree/nvim-web-devicons", -- 或 echasnovski/mini.icons
    "zbirenbaum/copilot.lua", -- 用于 providers='copilot'
    {
      -- 支持图像粘贴
      "HakonHarnes/img-clip.nvim",
      event = "VeryLazy",
      opts = {
        -- 推荐设置
        default = {
          embed_image_as_base64 = false,
          prompt_for_file_name = false,
          drag_and_drop = {
            insert_mode = true,
          },
          -- Windows 用户必需
          use_absolute_path = true,
        },
      },
    },
    {
      -- 如果您有 lazy=true，请确保正确设置
      'MeanderingProgrammer/render-markdown.nvim',
      opts = {
        file_types = { "markdown", "Avante" },
      },
      ft = { "markdown", "Avante" },
    },
  },
}
```

</details>

<details>

  <summary>vim-plug</summary>

```vim

" 依赖项
Plug 'nvim-treesitter/nvim-treesitter'
Plug 'stevearc/dressing.nvim'
Plug 'nvim-lua/plenary.nvim'
Plug 'MunifTanjim/nui.nvim'
Plug 'MeanderingProgrammer/render-markdown.nvim'

" 可选依赖项
Plug 'hrsh7th/nvim-cmp'
Plug 'nvim-tree/nvim-web-devicons' "或 Plug 'echasnovski/mini.icons'
Plug 'HakonHarnes/img-clip.nvim'
Plug 'zbirenbaum/copilot.lua'

" Yay，如果您想从源代码构建，请传递 source=true
Plug 'yetone/avante.nvim', { 'branch': 'main', 'do': 'make' }
autocmd! User avante.nvim lua << EOF
require('avante').setup()
EOF
```

</details>

<details>

  <summary><a href="https://github.com/echasnovski/mini.deps">mini.deps</a></summary>

```lua
local add, later, now = MiniDeps.add, MiniDeps.later, MiniDeps.now

add({
  source = 'yetone/avante.nvim',
  monitor = 'main',
  depends = {
    'nvim-treesitter/nvim-treesitter',
    'stevearc/dressing.nvim',
    'nvim-lua/plenary.nvim',
    'MunifTanjim/nui.nvim',
    'echasnovski/mini.icons'
  },
  hooks = { post_checkout = function() vim.cmd('make') end }
})
--- 可选
add({ source = 'hrsh7th/nvim-cmp' })
add({ source = 'zbirenbaum/copilot.lua' })
add({ source = 'HakonHarnes/img-clip.nvim' })
add({ source = 'MeanderingProgrammer/render-markdown.nvim' })

later(function() require('render-markdown').setup({...}) end)
later(function()
  require('img-clip').setup({...}) -- 配置 img-clip
  require("copilot").setup({...}) -- 根据您的喜好设置 copilot
  require("avante").setup({...}) -- 配置 avante.nvim
end)
```

</details>

<details>

  <summary><a href="https://github.com/wbthomason/packer.nvim">Packer</a></summary>

```vim

  -- 必需插件
  use 'nvim-treesitter/nvim-treesitter'
  use 'stevearc/dressing.nvim'
  use 'nvim-lua/plenary.nvim'
  use 'MunifTanjim/nui.nvim'
  use 'MeanderingProgrammer/render-markdown.nvim'

  -- 可选依赖项
  use 'hrsh7th/nvim-cmp'
  use 'nvim-tree/nvim-web-devicons' -- 或使用 'echasnovski/mini.icons'
  use 'HakonHarnes/img-clip.nvim'
  use 'zbirenbaum/copilot.lua'

  -- Avante.nvim 带有构建过程
  use {
    'yetone/avante.nvim',
    branch = 'main',
    run = 'make',
    config = function()
      require('avante').setup()
    end
  }
```

</details>

<details>

  <summary><a href="https://github.com/nix-community/home-manager">Home Manager</a></summary>

```nix
programs.neovim = {
  plugins = [
    {
      plugin = pkgs.vimPlugins.avante-nvim;
      type = "lua";
      config = ''
              require("avante_lib").load()
              require("avante").setup()
      '' # 或 builtins.readFile ./plugins/avante.lua;
    }
  ];
};
```

</details>

<details>

  <summary><a href="https://nix-community.github.io/nixvim/plugins/avante/index.html">Nixvim</a></summary>

```nix
  plugins.avante.enable = true;
  plugins.avante.settings = {
    # 在此处设置选项
  };
```

</details>

<details>

  <summary>Lua</summary>

```lua
-- 依赖项：
require('cmp').setup ({
  -- 使用上面的推荐设置
})
require('img-clip').setup ({
  -- 使用上面的推荐设置
})
require('copilot').setup ({
  -- 使用上面的推荐设置
})
require('render-markdown').setup ({
  -- 使用上面的推荐设置
})
require('avante').setup ({
  -- 在此处配置！
})
```

</details>

> [!IMPORTANT]
>
> `avante.nvim` 目前仅兼容 Neovim 0.10.1 或更高版本。请确保您的 Neovim 版本符合这些要求后再继续。

> [!NOTE]
>
> 在同步加载插件时，我们建议在您的配色方案之后的某个时间 `require` 它。

> [!NOTE]
>
> 推荐的 **Neovim** 选项：
>
> ```lua
> -- 视图只能通过全局状态栏完全折叠
> vim.opt.laststatus = 3
> ```

> [!TIP]
>
> 任何支持 markdown 的渲染插件都可以与 Avante 一起使用，只要您添加支持的文件类型 `Avante`。有关更多信息，请参见 <https://github.com/yetone/avante.nvim/issues/175> 和 [此评论](https://github.com/yetone/avante.nvim/issues/175#issuecomment-2313749363)。

### 默认设置配置

_请参见 [config.lua#L9](./lua/avante/config.lua) 以获取完整配置_

<details>
<summary>默认配置</summary>

```lua
{
  ---@alias Provider "claude" | "openai" | "azure" | "gemini" | "cohere" | "copilot" | string
  provider = "claude", -- 在 Aider 模式或 Cursor 规划模式的规划阶段使用的提供者
  -- 警告：由于自动建议是高频操作，因此成本较高，
  -- 目前将其指定为 `copilot` 提供者是危险的，因为：https://github.com/yetone/avante.nvim/issues/1048
  -- 当然，您可以通过增加 `suggestion.debounce` 来减少请求频率。
  auto_suggestions_provider = "claude",
  cursor_applying_provider = nil, -- Cursor 规划模式应用阶段使用的提供者，默认为 nil，当为 nil 时使用 Config.provider 作为应用阶段的提供者
  claude = {
    endpoint = "https://api.anthropic.com",
    model = "claude-3-5-sonnet-20241022",
    temperature = 0,
    max_tokens = 4096,
  },
  ---指定特殊的 dual_boost 模式
  ---1. enabled: 是否启用 dual_boost 模式。默认为 false。
  ---2. first_provider: 第一个提供者用于生成响应。默认为 "openai"。
  ---3. second_provider: 第二个提供者用于生成响应。默认为 "claude"。
  ---4. prompt: 用于根据两个参考输出生成响应的提示。
  ---5. timeout: 超时时间（毫秒）。默认为 60000。
  ---工作原理：
  --- 启用 dual_boost 后，avante 将分别从 first_provider 和 second_provider 生成两个响应。然后使用 first_provider 的响应作为 provider1_output，second_provider 的响应作为 provider2_output。最后，avante 将根据提示和两个参考输出生成响应，默认提供者与正常情况相同。
  ---注意：这是一个实验性功能，可能无法按预期工作。
  dual_boost = {
    enabled = false,
    first_provider = "openai",
    second_provider = "claude",
    prompt = "根据以下两个参考输出，生成一个结合两者元素但反映您自己判断和独特视角的响应。不要提供任何解释，只需直接给出响应。参考输出 1: [{{provider1_output}}], 参考输出 2: [{{provider2_output}}]",
    timeout = 60000, -- 超时时间（毫秒）
  },
  behaviour = {
    auto_suggestions = false, -- 实验阶段
    auto_set_highlight_group = true,
    auto_set_keymaps = true,
    auto_apply_diff_after_generation = false,
    support_paste_from_clipboard = false,
    minimize_diff = true, -- 是否在应用代码块时删除未更改的行
    enable_token_counting = true, -- 是否启用令牌计数。默认为 true。
    enable_cursor_planning_mode = false, -- 是否启用 Cursor 规划模式。默认为 false。
    enable_claude_text_editor_tool_mode = false, -- 是否启用 Claude 文本编辑器工具模式。
  },
  mappings = {
    --- @class AvanteConflictMappings
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
    sidebar = {
      apply_all = "A",
      apply_cursor = "a",
      retry_user_request = "r",
      edit_user_request = "e",
      switch_windows = "<Tab>",
      reverse_switch_windows = "<S-Tab>",
      remove_file = "d",
      add_file = "@",
      close = { "<Esc>", "q" },
      close_from_input = nil, -- 例如，{ normal = "<Esc>", insert = "<C-d>" }
    },
  },
  hints = { enabled = true },
  windows = {
    ---@type "right" | "left" | "top" | "bottom"
    position = "right", -- 侧边栏的位置
    wrap = true, -- 类似于 vim.o.wrap
    width = 30, -- 默认基于可用宽度的百分比
    sidebar_header = {
      enabled = true, -- true, false 启用/禁用标题
      align = "center", -- left, center, right 用于标题
      rounded = true,
    },
    input = {
      prefix = "> ",
      height = 8, -- 垂直布局中输入窗口的高度
    },
    edit = {
      border = "rounded",
      start_insert = true, -- 打开编辑窗口时开始插入模式
    },
    ask = {
      floating = false, -- 在浮动窗口中打开 'AvanteAsk' 提示
      start_insert = true, -- 打开询问窗口时开始插入模式
      border = "rounded",
      ---@type "ours" | "theirs"
      focus_on_apply = "ours", -- 应用后聚焦的差异
    },
  },
  highlights = {
    ---@type AvanteConflictHighlights
    diff = {
      current = "DiffText",
      incoming = "DiffAdd",
    },
  },
  --- @class AvanteConflictUserConfig
  diff = {
    autojump = true,
    ---@type string | fun(): any
    list_opener = "copen",
    --- 覆盖悬停在差异上时的 'timeoutlen' 设置（请参阅 :help timeoutlen）。
    --- 有助于避免进入以 `c` 开头的差异映射的操作员挂起模式。
    --- 通过设置为 -1 禁用。
    override_timeoutlen = 500,
  },
  suggestion = {
    debounce = 600,
    throttle = 600,
  },
}
```

</details>

## Blink.cmp 用户

对于 blink cmp 用户（nvim-cmp 替代品），请查看以下配置说明
这是通过使用 blink.compat 模拟 nvim-cmp 实现的
或者您可以使用 [Kaiser-Yang/blink-cmp-avante](https://github.com/Kaiser-Yang/blink-cmp-avante)。

<details>
  <summary>Lua</summary>

```lua
      selector = {
        --- @alias avante.SelectorProvider "native" | "fzf_lua" | "mini_pick" | "snacks" | "telescope" | fun(selector: avante.ui.Selector): nil
        provider = "fzf",
        -- 自定义提供者的选项覆盖
        provider_opts = {},
      }
```

要创建自定义选择器，您可以指定一个自定义函数来启动选择器以选择项目，并将选定的项目传递给 `on_select` 回调。

```lua
      selector = {
        ---@param selector avante.ui.Selector
        provider = function(selector)
          local items = selector.items ---@type avante.ui.SelectorItem[]
          local title = selector.title ---@type string
          local on_select = selector.on_select ---@type fun(selected_item_ids: string[]|nil): nil

          --- 在这里添加您的自定义选择器逻辑
        end,
      }
```

选择 native 以外的选择器，默认情况下目前存在问题
对于 lazyvim 用户，请从网站复制 blink.cmp 的完整配置或扩展选项

```lua
      compat = {
        "avante_commands",
        "avante_mentions",
        "avante_files",
      }
```

对于其他用户，只需添加自定义提供者

```lua
      default = {
        ...
        "avante_commands",
        "avante_mentions",
        "avante_files",
      }
```

```lua
      providers = {
        avante_commands = {
          name = "avante_commands",
          module = "blink.compat.source",
          score_offset = 90, -- 显示优先级高于 lsp
          opts = {},
        },
        avante_files = {
          name = "avante_files",
          module = "blink.compat.source",
          score_offset = 100, -- 显示优先级高于 lsp
          opts = {},
        },
        avante_mentions = {
          name = "avante_mentions",
          module = "blink.compat.source",
          score_offset = 1000, -- 显示优先级高于 lsp
          opts = {},
        }
        ...
    }
```

</details>

## 用法

鉴于其早期阶段，`avante.nvim` 目前支持以下基本功能：

> [!IMPORTANT]
>
> Avante 仅支持 Claude 和 OpenAI（及其变体，包括 azure）开箱即用，因为它具有高质量的代码生成。
> 对于所有兼容 OpenAI 的提供者，请参见 [wiki](https://github.com/yetone/avante.nvim/wiki/Custom-providers) 以获取更多详细信息。

> [!IMPORTANT]
>
> ~~由于其他模型的性能较差，avante.nvim 仅推荐使用 claude-3.5-sonnet 模型。~~ > ~~所有功能只能保证在 claude-3.5-sonnet 模型上正常工作。~~ > ~~我们不接受对代码或提示的更改以适应其他模型。否则，这将大大增加我们的维护成本。~~ > ~~我们希望大家能够理解。谢谢！~~

> [!IMPORTANT]
>
> 由于 avante.nvim 现在支持 [cursor planning mode](./cursor-planning-mode.md)，上述声明不再有效！avante.nvim 现在支持大多数模型！如果您在正常使用中遇到问题，请尝试启用 [cursor planning mode](./cursor-planning-mode.md)。

> [!IMPORTANT]
>
> 为了在 neovim 会话之间保持一致性，建议在 shell 文件中设置环境变量。
> 默认情况下，`Avante` 会在启动时提示您输入所选提供者的 API 密钥。
>
> 对于 Claude：
>
> ```sh
> export ANTHROPIC_API_KEY=your-api-key
> ```
>
> 对于 OpenAI：
>
> ```sh
> export OPENAI_API_KEY=your-api-key
> ```
>
> 对于 Azure OpenAI：
>
> ```sh
> export AZURE_OPENAI_API_KEY=your-api-key
> ```
>
> 对于 Amazon Bedrock：
>
> ```sh
> export BEDROCK_KEYS=aws_access_key_id,aws_secret_access_key,aws_region[,aws_session_token]
>
> ```
>
> 注意：aws_session_token 是可选的，仅在使用临时 AWS 凭证时需要

1. 在 Neovim 中打开代码文件。
2. 使用 `:AvanteAsk` 命令查询 AI 关于代码的问题。
3. 查看 AI 的建议。
4. 通过简单的命令或按键绑定将推荐的更改直接应用到代码中。

**注意**：该插件仍在积极开发中，其功能和界面可能会发生重大变化。随着项目的发展，预计会有一些粗糙的边缘和不稳定性。

## 键绑定

以下键绑定可用于 `avante.nvim`：

| 键绑定                                    | 描述                          |
| ----------------------------------------- | ----------------------------- |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>a</kbd> | 显示侧边栏                    |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>t</kbd> | 切换侧边栏可见性              |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>r</kbd> | 刷新侧边栏                    |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>f</kbd> | 切换侧边栏焦点                |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>?</kbd> | 选择模型                      |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>e</kbd> | 编辑选定的块                  |
| <kbd>Leader</kbd><kbd>a</kbd><kbd>S</kbd> | 停止当前 AI 请求              |
| <kbd>c</kbd><kbd>o</kbd>                  | 选择我们的                    |
| <kbd>c</kbd><kbd>t</kbd>                  | 选择他们的                    |
| <kbd>c</kbd><kbd>a</kbd>                  | 选择所有他们的                |
| <kbd>c</kbd><kbd>0</kbd>                  | 选择无                        |
| <kbd>c</kbd><kbd>b</kbd>                  | 选择两者                      |
| <kbd>c</kbd><kbd>c</kbd>                  | 选择光标                      |
| <kbd>]</kbd><kbd>x</kbd>                  | 移动到上一个冲突              |
| <kbd>[</kbd><kbd>x</kbd>                  | 移动到下一个冲突              |
| <kbd>[</kbd><kbd>[</kbd>                  | 跳转到上一个代码块 (结果窗口) |
| <kbd>]</kbd><kbd>]</kbd>                  | 跳转到下一个代码块 (结果窗口) |

> [!NOTE]
>
> 如果您使用 `lazy.nvim`，那么此处的所有键映射都将安全设置，这意味着如果 `<leader>aa` 已经绑定，则 avante.nvim 不会绑定此映射。
> 在这种情况下，用户将负责设置自己的。有关更多详细信息，请参见 [关于键映射的说明](https://github.com/yetone/avante.nvim/wiki#keymaps-and-api-i-guess)。

### Neotree 快捷方式

在 neotree 侧边栏中，您还可以添加新的键盘快捷方式，以快速将 `file/folder` 添加到 `Avante Selected Files`。

<details>
<summary>Neotree 配置</summary>

```lua
return {
  {
    'nvim-neo-tree/neo-tree.nvim',
    config = function()
      require('neo-tree').setup({
        filesystem = {
          commands = {
            avante_add_files = function(state)
              local node = state.tree:get_node()
              local filepath = node:get_id()
              local relative_path = require('avante.utils').relative_path(filepath)

              local sidebar = require('avante').get()

              local open = sidebar:is_open()
              -- 确保 avante 侧边栏已打开
              if not open then
                require('avante.api').ask()
                sidebar = require('avante').get()
              end

              sidebar.file_selector:add_selected_file(relative_path)

              -- 删除 neo tree 缓冲区
              if not open then
                sidebar.file_selector:remove_selected_file('neo-tree filesystem [1]')
              end
            end,
          },
          window = {
            mappings = {
              ['oa'] = 'avante_add_files',
            },
          },
        },
      })
    end,
  },
}
```

</details>

## 命令

| 命令                               | 描述                                                                                     | 示例                                                |
| ---------------------------------- | ---------------------------------------------------------------------------------------- | --------------------------------------------------- |
| `:AvanteAsk [question] [position]` | 询问 AI 关于您的代码的问题。可选的 `position` 设置窗口位置和 `ask` 启用/禁用直接询问模式 | `:AvanteAsk position=right Refactor this code here` |
| `:AvanteBuild`                     | 构建项目的依赖项                                                                         |                                                     |
| `:AvanteChat`                      | 启动与 AI 的聊天会话，讨论您的代码库。默认情况下 `ask`=false                             |                                                     |
| `:AvanteClear`                     | 清除聊天记录                                                                             |                                                     |
| `:AvanteEdit`                      | 编辑选定的代码块                                                                         |                                                     |
| `:AvanteFocus`                     | 切换焦点到/从侧边栏                                                                      |                                                     |
| `:AvanteRefresh`                   | 刷新所有 Avante 窗口                                                                     |                                                     |
| `:AvanteStop`                      | 停止当前 AI 请求                                                                         |                                                     |
| `:AvanteSwitchProvider`            | 切换 AI 提供者（例如 openai）                                                            |                                                     |
| `:AvanteShowRepoMap`               | 显示项目结构的 repo map                                                                  |                                                     |
| `:AvanteToggle`                    | 切换 Avante 侧边栏                                                                       |                                                     |
| `:AvanteModels`                    | 显示模型列表                                                                             |                                                     |

## 高亮组

| 高亮组                      | 描述                       | 备注                                       |
| --------------------------- | -------------------------- | ------------------------------------------ |
| AvanteTitle                 | 标题                       |                                            |
| AvanteReversedTitle         | 用于圆角边框               |                                            |
| AvanteSubtitle              | 选定代码标题               |                                            |
| AvanteReversedSubtitle      | 用于圆角边框               |                                            |
| AvanteThirdTitle            | 提示标题                   |                                            |
| AvanteReversedThirdTitle    | 用于圆角边框               |                                            |
| AvanteConflictCurrent       | 当前冲突高亮               | 默认值为 `Config.highlights.diff.current`  |
| AvanteConflictIncoming      | 即将到来的冲突高亮         | 默认值为 `Config.highlights.diff.incoming` |
| AvanteConflictCurrentLabel  | 当前冲突标签高亮           | 默认值为 `AvanteConflictCurrent` 的阴影    |
| AvanteConflictIncomingLabel | 即将到来的冲突标签高亮     | 默认值为 `AvanteConflictIncoming` 的阴影   |
| AvantePopupHint             | 弹出菜单中的使用提示       |                                            |
| AvanteInlineHint            | 在可视模式下显示的行尾提示 |                                            |

有关更多信息，请参见 [highlights.lua](./lua/avante/highlights.lua)

## Ollama

ollama 是 avante.nvim 的一流提供者。您可以通过在配置中设置 `provider = "ollama"` 来使用它，并在 `ollama` 中设置 `model` 字段为您想要使用的模型。例如：

```lua
provider = "ollama",
ollama = {
  model = "qwq:32b",
}
```

> [!NOTE]
> 如果您使用 ollama，代码规划效果可能不理想，因此强烈建议您启用 [cursor-planning-mode](https://github.com/yetone/avante.nvim/blob/main/cursor-planning-mode.md)

## AiHubMix

[AiHubMix](https://s.kiiro.ai/r/PPELHy) 是 avante.nvim 的内置提供者。您可以在 [AiHubMix 官方网站](https://s.kiiro.ai/r/PPELHy) 上注册一个帐户，然后在网站内创建一个 API 密钥，并在环境变量中设置此 API 密钥：

```bash
export AIHUBMIX_API_KEY=your_api_key
```

然后在您的配置中设置 `provider = "aihubmix"`，并将 `model` 字段设置为您想要使用的模型名称，例如：

```lua
provider = "aihubmix",
aihubmix = {
  model = "gpt-4o-2024-11-20",
}
```

## 自定义提供者

Avante 提供了一组默认提供者，但用户也可以创建自己的提供者。

有关更多信息，请参见 [自定义提供者](https://github.com/yetone/avante.nvim/wiki/Custom-providers)

## Cursor 规划模式

因为 avante.nvim 一直使用 Aider 的方法进行规划应用，但其提示对模型要求很高，需要像 claude-3.5-sonnet 或 gpt-4o 这样的模型才能正常工作。

因此，我采用了 Cursor 的方法来实现规划应用。有关实现的详细信息，请参阅 [cursor-planning-mode.md](./cursor-planning-mode.md)

## RAG 服务

Avante 提供了一个 RAG 服务，这是一个用于获取 AI 生成代码所需上下文的工具。默认情况下，它未启用。您可以通过以下方式启用它：

```lua
rag_service = {
  enabled = false, -- 启用 RAG 服务
  host_mount = os.getenv("HOME"), -- RAG 服务的主机挂载路径
  provider = "openai", -- 用于 RAG 服务的提供者（例如 openai 或 ollama）
  llm_model = "", -- 用于 RAG 服务的 LLM 模型
  embed_model = "", -- 用于 RAG 服务的嵌入模型
  endpoint = "https://api.openai.com/v1", -- RAG 服务的 API 端点
},
```

如果您的 rag_service 提供者是 `openai`，那么您需要设置 `OPENAI_API_KEY` 环境变量！

如果您的 rag_service 提供者是 `ollama`，您需要将端点设置为 `http://localhost:11434`（注意末尾没有 `/v1`）或您自己的 ollama 服务器的任何地址。

如果您的 rag_service 提供者是 `ollama`，当 `llm_model` 为空时，默认为 `llama3`，当 `embed_model` 为空时，默认为 `nomic-embed-text`。请确保这些模型在您的 ollama 服务器中可用。

此外，RAG 服务还依赖于 Docker！（对于 macOS 用户，推荐使用 OrbStack 作为 Docker 的替代品）。

`host_mount` 是将挂载到容器的路径，默认是主目录。挂载是 RAG 服务访问主机机器中文件所必需的。用户可以决定是否要挂载整个 `/` 目录、仅项目目录或主目录。如果您计划使用 avante 和 RAG 事件处理存储在主目录之外的项目，您需要将 `host_mount` 设置为文件系统的根目录。

挂载将是只读的。

更改 rag_service 配置后，您需要手动删除 rag_service 容器以确保使用新配置：`docker rm -fv avante-rag-service`

## Web 搜索引擎

Avante 的工具包括一些 Web 搜索引擎，目前支持：

- [Tavily](https://tavily.com/)
- [SerpApi](https://serpapi.com/)
- [SearchAPI](https://www.searchapi.io/)
- Google's [Programmable Search Engine](https://developers.google.com/custom-search/v1/overview)
- [Kagi](https://help.kagi.com/kagi/api/search.html)
- [Brave Search](https://api-dashboard.search.brave.com/app/documentation/web-search/get-started)
- [SearXNG](https://searxng.github.io/searxng/)

默认是 Tavily，可以通过配置 `Config.web_search_engine.provider` 进行更改：

```lua
web_search_engine = {
  provider = "tavily", -- tavily, serpapi, searchapi, google, kagi, brave 或 searxng
  proxy = nil, -- proxy support, e.g., http://127.0.0.1:7890
}
```

提供者所需的环境变量：

- Tavily: `TAVILY_API_KEY`
- SerpApi: `SERPAPI_API_KEY`
- SearchAPI: `SEARCHAPI_API_KEY`
- Google:
  - `GOOGLE_SEARCH_API_KEY` 作为 [API 密钥](https://developers.google.com/custom-search/v1/overview)
  - `GOOGLE_SEARCH_ENGINE_ID` 作为 [搜索引擎](https://programmablesearchengine.google.com) ID
- Kagi: `KAGI_API_KEY` 作为 [API 令牌](https://kagi.com/settings?p=api)
- Brave Search: `BRAVE_API_KEY` 作为 [API 密钥](https://api-dashboard.search.brave.com/app/keys)
- SearXNG: `SEARXNG_API_URL` 作为 [API URL](https://docs.searxng.org/dev/search_api.html)

## 禁用工具

Avante 默认启用工具，但某些 LLM 模型不支持工具。您可以通过为提供者设置 `disable_tools = true` 来禁用工具。例如：

```lua
{
  claude = {
    endpoint = "https://api.anthropic.com",
    model = "claude-3-5-sonnet-20241022",
    timeout = 30000, -- 超时时间（毫秒）
    temperature = 0,
    max_tokens = 4096,
    disable_tools = true, -- 禁用工具！
  },
}
```

如果您想禁止某些工具以避免其使用（例如 Claude 3.7 过度使用 python 工具），您可以仅禁用特定工具

```lua
{
  disabled_tools = { "python" },
}
```

工具列表

> rag_search, python, git_diff, git_commit, list_files, search_files, search_keyword, read_file_toplevel_symbols,
> read_file, create_file, rename_file, delete_file, create_dir, rename_dir, delete_dir, bash, web_search, fetch

## 自定义工具

Avante 允许您定义自定义工具，AI 可以在代码生成和分析期间使用这些工具。这些工具可以执行 shell 命令、运行脚本或执行您需要的任何自定义逻辑。

### 示例：Go 测试运行器

<details>
<summary>以下是一个运行 Go 单元测试的自定义工具示例：</summary>

```lua
{
  custom_tools = {
    {
      name = "run_go_tests",  -- 工具的唯一名称
      description = "运行 Go 单元测试并返回结果",  -- 显示给 AI 的描述
      command = "go test -v ./...",  -- 要执行的 shell 命令
      param = {  -- 输入参数（可选）
        type = "table",
        fields = {
          {
            name = "target",
            description = "要测试的包或目录（例如 './pkg/...' 或 './internal/pkg'）",
            type = "string",
            optional = true,
          },
        },
      },
      returns = {  -- 预期返回值
        {
          name = "result",
          description = "获取的结果",
          type = "string",
        },
        {
          name = "error",
          description = "如果获取不成功的错误消息",
          type = "string",
          optional = true,
        },
      },
      func = function(params, on_log, on_complete)  -- 要执行的自定义函数
        local target = params.target or "./..."
        return vim.fn.system(string.format("go test -v %s", target))
      end,
    },
  },
}
```

</details>

## MCP

现在您可以通过 `mcphub.nvim` 为 Avante 集成 MCP 功能。有关详细文档，请参阅 [mcphub.nvim](https://github.com/ravitemer/mcphub.nvim#avante-integration)

## Claude 文本编辑器工具模式

Avante 利用 [Claude 文本编辑器工具](https://docs.anthropic.com/en/docs/build-with-claude/tool-use/text-editor-tool) 提供更优雅的代码编辑体验。您现在可以通过在 `behaviour` 配置中将 `enable_claude_text_editor_tool_mode` 设置为 `true` 来启用此功能：

```lua
{
  behaviour = {
    enable_claude_text_editor_tool_mode = true,
  },
}
```

> [!NOTE]
> 要启用 **Claude 文本编辑器工具模式**，您必须使用 `claude-3-5-sonnet-*` 或 `claude-3-7-sonnet-*` 模型与 `claude` 提供者！此功能不支持任何其他模型！

## 自定义提示

默认情况下，`avante.nvim` 提供三种不同的模式进行交互：`planning`、`editing` 和 `suggesting`，每种模式都有三种不同的提示。

- `planning`：与侧边栏上的 `require("avante").toggle()` 一起使用
- `editing`：与选定代码块上的 `require("avante").edit()` 一起使用
- `suggesting`：与 Tab 流上的 `require("avante").get_suggestion():suggest()` 一起使用。
- `cursor-planning`：与 Tab 流上的 `require("avante").toggle()` 一起使用，但仅在启用 cursor 规划模式时。

用户可以通过 `Config.system_prompt` 自定义系统提示。我们建议根据您的需要在自定义 Autocmds 中调用此方法：

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "ToggleMyPrompt",
  callback = function() require("avante.config").override({system_prompt = "MY CUSTOM SYSTEM PROMPT"}) end,
})

vim.keymap.set("n", "<leader>am", function() vim.api.nvim_exec_autocmds("User", { pattern = "ToggleMyPrompt" }) end, { desc = "avante: toggle my prompt" })
```

如果希望为每种模式自定义提示，`avante.nvim` 将根据给定缓冲区的项目根目录检查是否包含以下模式：`*.{mode}.avanterules`。

根目录层次结构的规则：

- lsp 工作区文件夹
- lsp root_dir
- 当前缓冲区的文件名的根模式
- cwd 的根模式

<details>

  <summary>自定义提示的示例文件夹结构</summary>

如果您有以下结构：

```bash
.
├── .git/
├── typescript.planning.avanterules
├── snippets.editing.avanterules
├── suggesting.avanterules
└── src/

```

- `typescript.planning.avanterules` 将用于 `planning` 模式
- `snippets.editing.avanterules` 将用于 `editing` 模式
- `suggesting.avanterules` 将用于 `suggesting` 模式。

</details>

> [!important]
>
> `*.avanterules` 是一个 jinja 模板文件，将使用 [minijinja](https://github.com/mitsuhiko/minijinja) 渲染。有关如何扩展当前模板的示例，请参见 [templates](https://github.com/yetone/avante.nvim/blob/main/lua/avante/templates)。

## TODOs

- [x] 与当前文件聊天
- [x] 应用差异补丁
- [x] 与选定的块聊天
- [x] 斜杠命令
- [x] 编辑选定的块
- [x] 智能 Tab（Cursor 流）
- [x] 与项目聊天（您可以使用 `@codebase` 与整个项目聊天）
- [x] 与选定文件聊天
- [x] 工具使用
- [x] MCP
- [ ] 更好的代码库索引

## 路线图

- **增强的 AI 交互**：提高 AI 分析和建议的深度，以应对更复杂的编码场景。
- **LSP + Tree-sitter + LLM 集成**：与 LSP 和 Tree-sitter 以及 LLM 集成，以提供更准确和强大的代码建议和分析。

## 贡献

欢迎为 avante.nvim 做出贡献！如果您有兴趣提供帮助，请随时提交拉取请求或打开问题。在贡献之前，请确保您的代码已经过彻底测试。

有关更多配方和技巧，请参见 [wiki](https://github.com/yetone/avante.nvim/wiki)。

## 致谢

我们要向以下开源项目的贡献者表示衷心的感谢，他们的代码为 avante.nvim 的开发提供了宝贵的灵感和参考：

| Nvim 插件                                                             | 许可证            | 功能             | 位置                                                                                                                                   |
| --------------------------------------------------------------------- | ----------------- | ---------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| [git-conflict.nvim](https://github.com/akinsho/git-conflict.nvim)     | 无许可证          | 差异比较功能     | [lua/avante/diff.lua](https://github.com/yetone/avante.nvim/blob/main/lua/avante/diff.lua)                                             |
| [ChatGPT.nvim](https://github.com/jackMort/ChatGPT.nvim)              | Apache 2.0 许可证 | 令牌计数的计算   | [lua/avante/utils/tokens.lua](https://github.com/yetone/avante.nvim/blob/main/lua/avante/utils/tokens.lua)                             |
| [img-clip.nvim](https://github.com/HakonHarnes/img-clip.nvim)         | MIT 许可证        | 剪贴板图像支持   | [lua/avante/clipboard.lua](https://github.com/yetone/avante.nvim/blob/main/lua/avante/clipboard.lua)                                   |
| [copilot.lua](https://github.com/zbirenbaum/copilot.lua)              | MIT 许可证        | Copilot 支持     | [lua/avante/providers/copilot.lua](https://github.com/yetone/avante.nvim/blob/main/lua/avante/providers/copilot.lua)                   |
| [jinja.vim](https://github.com/HiPhish/jinja.vim)                     | MIT 许可证        | 模板文件类型支持 | [syntax/jinja.vim](https://github.com/yetone/avante.nvim/blob/main/syntax/jinja.vim)                                                   |
| [codecompanion.nvim](https://github.com/olimorris/codecompanion.nvim) | MIT 许可证        | Secrets 逻辑支持 | [lua/avante/providers/init.lua](https://github.com/yetone/avante.nvim/blob/main/lua/avante/providers/init.lua)                         |
| [aider](https://github.com/paul-gauthier/aider)                       | Apache 2.0 许可证 | 规划模式用户提示 | [lua/avante/templates/planning.avanterules](https://github.com/yetone/avante.nvim/blob/main/lua/avante/templates/planning.avanterules) |

这些项目的源代码的高质量和独创性在我们的开发过程中提供了极大的帮助。我们向这些项目的作者和贡献者表示诚挚的感谢和敬意。正是开源社区的无私奉献推动了像 avante.nvim 这样的项目向前发展。

## 商业赞助商

<table>
  <tr>
    <td align="center">
      <a href="https://s.kiiro.ai/r/ylVbT6" target="_blank">
        <img height="80" src="https://github.com/user-attachments/assets/1abd8ede-bd98-4e6e-8ee0-5a661b40344a" alt="Meshy AI" /><br/>
        <strong>Meshy AI</strong>
        <div>&nbsp;</div>
        <div>为创作者提供的 #1 AI 3D 模型生成器</div>
      </a>
    </td>
    <td align="center">
      <a href="https://s.kiiro.ai/r/mGPJOd" target="_blank">
        <img height="80" src="https://github.com/user-attachments/assets/7b7bd75e-1fd2-48cc-a71a-cff206e4fbd7" alt="BabelTower API" /><br/>
        <strong>BabelTower API</strong>
        <div>&nbsp;</div>
        <div>无需帐户，立即使用任何模型</div>
      </a>
    </td>
  </tr>
</table>

## 许可证

avante.nvim 根据 Apache 2.0 许可证授权。有关更多详细信息，请参阅 [LICENSE](./LICENSE) 文件。

# Star 历史

<p align="center">
  <a target="_blank" href="https://star-history.com/#yetone/avante.nvim&Date">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=yetone/avante.nvim&type=Date&theme=dark">
      <img alt="NebulaGraph Data Intelligence Suite(ngdi)" src="https://api.star-history.com/svg?repos=yetone/avante.nvim&type=Date">
    </picture>
  </a>
</p>

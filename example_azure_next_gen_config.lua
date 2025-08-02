-- Example configuration for the new azure_next_gen provider
-- This demonstrates the enhanced features requested in issue #2561
-- Simplified implementation that inherits from OpenAI provider

local config = {
  provider = "azure_next_gen",

  providers = {
    -- The user might still have a standard openai provider configured.
    -- avante.nvim has sensible defaults for models like "gpt-4o" here.
    openai = {
      model = "gpt-4o",
    },

    -- The new, clean configuration for Azure with inheritance
    azure_next_gen = {
      endpoint = "https://my-azure-resource.openai.azure.com/v1/",
      api_key_name = "AZURE_OPENAI_API_KEY", -- or "cmd:bw get secret azure-openai-api-key"

      -- Select the default model to use by its friendly name
      model = "azure_gpt_4o",

      -- Model configurations with inheritance support
      models = {
        ["azure_gpt_4o"] = {
          -- This is the actual name of the deployment on Azure
          deployment = "my-gpt4o-deployment",

          -- This is the new key that enables inheritance.
          -- It tells avante to apply all the sensible defaults it has for "gpt-4o"
          -- to this deployment (context_window, extra_request_body, timeout).
          openai_model = "gpt-4o",

          -- (Optional) The API version to use. Defaults to 'preview'.
          -- Other valid options might include 'latest' or a specific version string.
          api_version = "preview",

          -- Optional: Custom display name in model selector
          display_name = "Azure GPT-4o",
        },

        ["finetuned_gpt_4o"] = {
          deployment = "my-finetuned-code-deploy",
          openai_model = "gpt-4o", -- Also inherits from gpt-4o
          display_name = "Finetuned GPT-4o",
        },

        ["production_chat_model"] = {
          deployment = "prod-chat-v4",
          openai_model = "gpt-4o",
          display_name = "Production Chat",
        },
      },

      -- Global settings that apply to all models in this provider
      timeout = 30000,
      extra_request_body = {
        temperature = 0.7, -- This can be overridden by inherited values
      },
    },
  },
}

-- Key benefits of this implementation:
-- 1. Inherits ALL OpenAI provider functionality automatically
-- 2. Azure-specific model inheritance with openai_model key
-- 3. Proper model selector integration
-- 4. Deployment-aware request building
-- 5. Uses api-key authentication and api-version=preview
-- 6. Only ~20 lines of provider code vs 100+ lines
-- 7. Automatically benefits from OpenAI provider improvements

return config

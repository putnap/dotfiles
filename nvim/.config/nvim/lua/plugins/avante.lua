return {
    "yetone/avante.nvim",
    event = "VeryLazy",
    version = false, -- Never set this value to "*"! Never!
    opts = {
        provider = "gemini",
        providers = {
            gemini = {
                model = "gemini-2.5-pro-preview-06-05", -- your desired model (or use gpt-4o, etc.)
                timeout = 30000, -- Timeout in milliseconds, increase this for reasoning models
                temperature = 0,
                max_tokens = 8192, -- Increase this to include reasoning tokens (for reasoning models)
                api_key_name = "cmd:security find-generic-password -s GEMINI_KEY -w",
                --reasoning_effort = "medium", -- low|medium|high, only used for reasoning models
            },
        },
        file_selector = {
            provider = "snacks",
            -- Options override for custom providers
            provider_opts = {},
        },
    },
    build = "make",
    dependencies = {
        "nvim-treesitter/nvim-treesitter",
        "stevearc/dressing.nvim",
        "nvim-lua/plenary.nvim",
        "MunifTanjim/nui.nvim",
        --- The below dependencies are optional,
        "nvim-tree/nvim-web-devicons", -- or echasnovski/mini.icons
        {
            -- support for image pasting
            "HakonHarnes/img-clip.nvim",
            event = "VeryLazy",
            opts = {
                -- recommended settings
                default = {
                    embed_image_as_base64 = false,
                    prompt_for_file_name = false,
                    drag_and_drop = {
                        insert_mode = true,
                    },
                    -- required for Windows users
                    use_absolute_path = true,
                },
            },
        },
        {
            -- Make sure to set this up properly if you have lazy=true
            "MeanderingProgrammer/render-markdown.nvim",
            opts = {
                file_types = { "markdown", "Avante" },
            },
            ft = { "markdown", "Avante" },
        },
    },
}

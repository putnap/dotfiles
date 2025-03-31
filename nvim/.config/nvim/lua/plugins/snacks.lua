return {
    "folke/snacks.nvim",
    opts = {
        picker = {
            sources = {
                buffers = {
                    on_show = function()
                        vim.cmd.stopinsert()
                    end,
                    finder = "buffers",
                    format = "buffer",
                    hidden = false,
                    unloaded = true,
                    current = true,
                    sort_lastused = true,
                    win = {
                        input = {
                            keys = {
                                ["d"] = "bufdelete",
                            },
                        },
                        list = { keys = { ["d"] = "bufdelete" } },
                    },
                },
                explorer = {
                    hidden = true,
                    -- ignored = true,
                    win = {
                        list = {
                            keys = {
                                ["<C-h>"] = false,
                                ["<C-j>"] = false,
                                ["<C-k>"] = false,
                                ["<C-l>"] = false,
                                ["<leader>af"] = "avante_add_files",
                            },
                        },
                    },
                    actions = {
                        avante_add_files = function(_, selected)
                            local filepath = selected.file
                            local relative_path = require("avante.utils").relative_path(filepath)

                            local sidebar = require("avante").get()

                            local open = sidebar:is_open()
                            -- ensure avante sidebar is open
                            if not open then
                                require("avante.api").ask()
                                sidebar = require("avante").get()
                            end

                            sidebar.file_selector:add_selected_file(relative_path)
                        end,
                    },
                },
                files = {
                    hidden = true,
                    -- ignored = true,
                },
                grep = {
                    hidden = true,
                },
            },
            matcher = {
                frequency = true,
            },
            layout = {
                preset = "ivy",
                cycle = false,
            },
            win = {
                input = {
                    keys = {
                        ["<Esc>"] = { "close", mode = { "n", "i" } },

                        ["J"] = { "preview_scroll_down", mode = { "i", "n" } },
                        ["K"] = { "preview_scroll_up", mode = { "i", "n" } },
                        ["H"] = { "preview_scroll_left", mode = { "i", "n" } },
                        ["L"] = { "preview_scroll_right", mode = { "i", "n" } },
                        ["<c-j>"] = { "", mode = { "i", "n" } },
                        ["<c-k>"] = { "", mode = { "i", "n" } },
                    },
                },
            },
        },
    },
}

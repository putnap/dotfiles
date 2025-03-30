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
                            },
                        },
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

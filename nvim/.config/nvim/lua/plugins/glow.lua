-- A separate reader window for markdown, because no in-buffer renderer can fix
-- a wide table. render-markdown and markview both align columns to their
-- natural width and have no way to reflow a cell, so one long column pushes the
-- table past the window and the borders shred (markview calls this out as a
-- known bug in its own table renderer). glow re-wraps cell text to a set width.
--
-- render-markdown stays as-is for editing; this is for reading.
local ratio = 0.8

return {
    "folke/snacks.nvim",
    keys = {
        {
            "<leader>cP",
            ft = "markdown",
            function()
                if vim.fn.executable("glow") == 0 then
                    Snacks.notify.error("glow is not installed -- run the nix rebuild")
                    return
                end

                -- Render the buffer rather than the path, so unsaved edits and
                -- scratch buffers both show what is actually on screen.
                local source = vim.fn.tempname() .. ".md"
                vim.fn.writefile(vim.api.nvim_buf_get_lines(0, 0, -1, false), source)

                -- snacks sizes the window without its border, matching what the
                -- terminal inside it gets, so glow wraps to exactly that.
                local width = math.floor(vim.o.columns * ratio) - 2

                Snacks.terminal.open({
                    "glow",
                    "--style",
                    vim.o.background,
                    "--width",
                    tostring(width),
                    "--pager",
                    source,
                }, {
                    win = {
                        position = "float",
                        width = ratio,
                        height = 0.9,
                        border = "rounded",
                        title = " " .. vim.fn.expand("%:t") .. " ",
                        title_pos = "center",
                    },
                })
            end,
            desc = "Markdown Read (glow)",
        },
    },
}

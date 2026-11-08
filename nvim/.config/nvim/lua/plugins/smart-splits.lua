-- Replaces aserowy/tmux.nvim: one plugin covers both tmux and herdr, and
-- auto-detects which is running (herdr wins when both are present).
-- The tmux side is the TPM plugin in tmux.conf; the herdr side is the local
-- plugin in this repo (herdr/.config/herdr/local-plugins/smart-splits).
return {
    "mrjones2014/smart-splits.nvim",
    -- Not lazy: the tmux integration needs @pane-is-vim set as soon as nvim starts.
    lazy = false,
    opts = {
        -- Matches the old tmux.nvim resize_step_x/y.
        default_amount = 5,
        -- Matches tmux.nvim's cycle_navigation = false and herdr's no-neighbor fallthrough.
        -- herdr-app has no smart-splits backend, so at an edge its window moves the pane
        -- (herdr-app/.config/herdr-app/mods/keys forwards ctrl+hjkl here).
        at_edge = function(ctx)
            if vim.env.HC_TERMINAL_ID and not vim.env.HERDR_PANE_ID and not vim.env.TMUX then
                vim.system({ "herdr-app", "do", "pane.go", "--direction", ctx.direction })
            end
        end,
        ignored_filetypes = { "NvimTree", "neo-tree" },
        float_win_behavior = "previous",
    },
}

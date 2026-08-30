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
        at_edge = "stop",
        ignored_filetypes = { "NvimTree", "neo-tree" },
        float_win_behavior = "previous",
    },
}

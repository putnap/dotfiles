-- Replaces aserowy/tmux.nvim: one plugin covers both tmux and herdr, and
-- auto-detects which is running (herdr wins when both are present).
-- The tmux side is the TPM plugin in tmux.conf; the herdr side is the local
-- plugin in this repo (herdr/.config/herdr/local-plugins/smart-splits).

local function in_herdr_app()
    return vim.env.HC_TERMINAL_ID and not vim.env.HERDR_PANE_ID and not vim.env.TMUX
end

-- A killed nvim leaves its socket file behind, and serverstart refuses to replace it.
local function is_listening(socket)
    local ok, channel = pcall(vim.fn.sockconnect, "pipe", socket)
    if ok and channel > 0 then
        vim.fn.chanclose(channel)
        return true
    end
    return false
end

-- herdr-app's keys mod sends ctrl+hjkl here (herdr-app/.config/herdr-app/mods/keys): hc keys
-- waits until you stop typing (herdr-core #52), a socket doesn't.
local function listen_for_herdr_app()
    local socket = vim.fn.stdpath("state") .. "/hc/" .. vim.env.HC_TERMINAL_ID .. ".sock"
    vim.fn.mkdir(vim.fs.dirname(socket), "p")
    if vim.uv.fs_stat(socket) and not is_listening(socket) then
        os.remove(socket)
    end
    -- Fails when an outer nvim in this same terminal already listens; it keeps the socket.
    pcall(vim.fn.serverstart, socket)
end

return {
    "mrjones2014/smart-splits.nvim",
    -- v3 moved tmux/herdr support into separate backend plugins; keep v2 until they mature.
    tag = "v2.1.1-final",
    -- Not lazy: the tmux integration needs @pane-is-vim set as soon as nvim starts.
    lazy = false,
    init = function()
        if in_herdr_app() then
            listen_for_herdr_app()
        end
    end,
    opts = {
        -- Matches the old tmux.nvim resize_step_x/y.
        default_amount = 5,
        -- Matches tmux.nvim's cycle_navigation = false and herdr's no-neighbor fallthrough.
        -- herdr-app has no smart-splits backend, so at an edge its window moves the pane
        -- (herdr-app/.config/herdr-app/mods/keys forwards ctrl+hjkl here).
        at_edge = function(ctx)
            if in_herdr_app() then
                vim.system({ "herdr-app", "do", "pane.go", "--direction", ctx.direction })
            end
        end,
        ignored_filetypes = { "NvimTree", "neo-tree" },
        float_win_behavior = "previous",
    },
}

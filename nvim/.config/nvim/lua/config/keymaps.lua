-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selected line down" })
-- vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selected line up" })

vim.keymap.set("n", "J", "mzJ`z", { desc = "Move next line to end of this line" })

vim.keymap.set("n", "<leader>p", [["+p]], { desc = "Paste from system clipboard" })
vim.keymap.set("x", "<leader>p", [["_dP]], { desc = "Paste over without changing register" })
vim.keymap.set({ "n", "v" }, "<leader>y", [["+y]], { desc = "Yank to system clipboard" })
vim.keymap.set("n", "<leader>Y", [["+Y]], { desc = "Yank line wise to system clipboard" })
vim.keymap.set({ "n", "v" }, "<leader>d", '"_d', { desc = "Delete to void register" })

vim.keymap.set(
    "n",
    "<C-Left>",
    [[<cmd>lua require("tmux").resize_left()<cr>]],
    { remap = true, desc = "Vertical Window size increase" }
)
vim.keymap.set(
    "n",
    "<C-Right>",
    [[<cmd>lua require("tmux").resize_right()<cr>]],
    { remap = true, desc = "Vertical Window size decrease" }
)
vim.keymap.set(
    "n",
    "<C-Down>",
    [[<cmd>lua require("tmux").resize_bottom()<cr>]],
    { remap = true, desc = "Horizontal Window size increase" }
)
vim.keymap.set(
    "n",
    "<C-Up>",
    [[<cmd>lua require("tmux").resize_top()<cr>]],
    { remap = true, desc = "Horizontal Window size decrease" }
)

vim.keymap.set("n", "<C-h>", [[<cmd>lua require("tmux").move_left()<cr>]], { desc = "Go to Left Window", remap = true })
vim.keymap.set(
    "n",
    "<C-j>",
    [[<cmd>lua require("tmux").move_bottom()<cr>]],
    { desc = "Go to Lower Window", remap = true }
)
vim.keymap.set("n", "<C-k>", [[<cmd>lua require("tmux").move_top()<cr>]], { desc = "Go to Upper Window", remap = true })
vim.keymap.set(
    "n",
    "<C-l>",
    [[<cmd>lua require("tmux").move_right()<cr>]],
    { desc = "Go to Right Window", remap = true }
)

-- Navigate in terminal mode too, so <C-hjkl> works inside terminals like
-- lazygit (snacks float). tmux forwards the keys to nvim, but the maps above
-- are normal-mode only, so without this they leak into the terminal program.
local tmux_dirs = { h = "left", j = "bottom", k = "top", l = "right" }
for key, dir in pairs(tmux_dirs) do
    vim.keymap.set(
        "t",
        "<C-" .. key .. ">",
        ([[<cmd>lua require("tmux").move_%s()<cr>]]):format(dir),
        { desc = "Go " .. dir .. " window (term)" }
    )
end

vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true, desc = "Make current file executable" })

vim.keymap.set("n", "<C-a>", "gg0vG$", { desc = "Select all text" })

-- Terminal Mappings
vim.keymap.set("n", "<C-/>", "gcc", { remap = true, desc = "Toggle comment line" })
vim.keymap.set("n", "<c-_>", "gcc", { remap = true, desc = "which_key_ignore" })
vim.keymap.set("v", "<C-/>", "gc", { remap = true, desc = "Toggle comment for selection" })
vim.keymap.set("v", "<c-_>", "gc", { remap = true, desc = "which_key_ignore" })

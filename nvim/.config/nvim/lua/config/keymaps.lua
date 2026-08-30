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

-- smart-splits: <C-hjkl> and <C-arrows> treat nvim splits and tmux/herdr panes
-- as one surface. The multiplexer side forwards the keys here when nvim owns
-- the pane, and smart-splits calls back out at a split edge.
local smart_splits = {
    ["<C-h>"] = { "move_cursor_left", "Go to Left Window" },
    ["<C-j>"] = { "move_cursor_down", "Go to Lower Window" },
    ["<C-k>"] = { "move_cursor_up", "Go to Upper Window" },
    ["<C-l>"] = { "move_cursor_right", "Go to Right Window" },
    ["<C-Left>"] = { "resize_left", "Vertical Window size increase" },
    ["<C-Right>"] = { "resize_right", "Vertical Window size decrease" },
    ["<C-Down>"] = { "resize_down", "Horizontal Window size increase" },
    ["<C-Up>"] = { "resize_up", "Horizontal Window size decrease" },
}

-- Terminal mode too, so the keys work inside lazygit and other snacks floats
-- rather than leaking into the terminal program.
for key, spec in pairs(smart_splits) do
    local fn, desc = spec[1], spec[2]
    vim.keymap.set({ "n", "t" }, key, function()
        require("smart-splits")[fn]()
    end, { desc = desc })
end

vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true, desc = "Make current file executable" })

vim.keymap.set("n", "<C-a>", "gg0vG$", { desc = "Select all text" })

-- Terminal Mappings
vim.keymap.set("n", "<C-/>", "gcc", { remap = true, desc = "Toggle comment line" })
vim.keymap.set("n", "<c-_>", "gcc", { remap = true, desc = "which_key_ignore" })
vim.keymap.set("v", "<C-/>", "gc", { remap = true, desc = "Toggle comment for selection" })
vim.keymap.set("v", "<c-_>", "gc", { remap = true, desc = "which_key_ignore" })

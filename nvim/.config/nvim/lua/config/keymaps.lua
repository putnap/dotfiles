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

vim.keymap.set("n", "=", [[<cmd>vertical resize +5<cr>]], { desc = "Vertical Window size increase" })
vim.keymap.set("n", "-", [[<cmd>vertical resize -5<cr>]], { desc = "Vertical Window size decrease" })
vim.keymap.set("n", "+", [[<cmd>horizontal resize +2<cr>]], { desc = "Horizontal Window size increase" })
vim.keymap.set("n", "_", [[<cmd>horizontal resize -2<cr>]], { desc = "Horizontal Window size decrease" })

vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true, desc = "Make current file executable" })

vim.keymap.set("n", "<C-a>", "gg0vG$", { desc = "Select all text" })

-- Terminal Mappings
vim.keymap.set("n", "<C-/>", "gcc", { remap = true, desc = "Toggle comment line" })
vim.keymap.set("n", "<c-_>", "gcc", { remap = true, desc = "which_key_ignore" })
vim.keymap.set("v", "<C-/>", "gc", { remap = true, desc = "Toggle comment for selection" })
vim.keymap.set("v", "<c-_>", "gc", { remap = true, desc = "which_key_ignore" })

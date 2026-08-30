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

-- smart-splits: <C-hjkl> navigates, <C-S-arrows> resizes. Plain <C-arrows> is
-- word motion now, so resize took Shift on top. The multiplexer side forwards the keys here when nvim owns
-- the pane, and smart-splits calls back out at a split edge.
local smart_splits = {
    ["<C-h>"] = { "move_cursor_left", "Go to Left Window" },
    ["<C-j>"] = { "move_cursor_down", "Go to Lower Window" },
    ["<C-k>"] = { "move_cursor_up", "Go to Upper Window" },
    ["<C-l>"] = { "move_cursor_right", "Go to Right Window" },
    ["<C-S-Left>"] = { "resize_left", "Vertical Window size increase" },
    ["<C-S-Right>"] = { "resize_right", "Vertical Window size decrease" },
    ["<C-S-Down>"] = { "resize_down", "Horizontal Window size increase" },
    ["<C-S-Up>"] = { "resize_up", "Horizontal Window size decrease" },
}

-- Terminal mode too, so the keys work inside lazygit and other snacks floats
-- rather than leaking into the terminal program.
--
-- Resize needs two different amounts. Neovim counts columns and rows; herdr's
-- `pane resize --amount` is a ratio of the whole width, so smart-splits passing
-- its default_amount straight through meant 2 => 200% and half the screen went
-- missing. Pick by whether Neovim has another window to give space to.
local function resize_amount()
    return vim.fn.winnr("$") > 1 and 2 or 0.03
end

for key, spec in pairs(smart_splits) do
    local fn, desc = spec[1], spec[2]
    vim.keymap.set({ "n", "t" }, key, function()
        if fn:match("^resize_") then
            require("smart-splits")[fn](resize_amount())
        else
            require("smart-splits")[fn]()
        end
    end, { desc = desc })
end

-- Word motion. Ghostty sends Alt+arrows as CSI 1;3D/C (see ghostty/config), so
-- these arrive as a single key rather than Esc-then-letter. Normal and insert
-- differ: <C-o> in normal mode is the jumplist, not "run one command".
vim.keymap.set("n", "<M-Left>", "b", { desc = "Word left" })
vim.keymap.set("n", "<M-Right>", "w", { desc = "Word right" })
vim.keymap.set("i", "<M-Left>", "<C-o>b", { desc = "Word left" })
vim.keymap.set("i", "<M-Right>", "<C-o>w", { desc = "Word right" })

-- z is zoom: alt-z in Aerospace, prefix+z in herdr, here. LazyVim puts the same
-- toggle on <leader>wm and <leader>uZ; this is the one that matches the others.
-- Deliberately not Snacks.toggle.zoom():map(...) at file scope: that touches the
-- Snacks global while this file loads, and if it is not ready yet the error
-- takes every mapping below it with it. Inside a callback it runs at keypress.
vim.keymap.set("n", "<leader>z", function()
    Snacks.toggle.zoom():toggle()
end, { desc = "Zoom" })

-- LazyVim ships <leader>| and <leader>-; \ is the same key as | unshifted, so
-- splitting right costs one keypress fewer, matching zen and both multiplexers.
vim.keymap.set("n", "<leader>\\", "<C-W>v", { remap = true, desc = "Split Window Right" })

-- = undivides, as in Zen and herdr. <C-w>= is Vim's own; this is the alias that
-- matches the other two. Alt+Shift+= cannot be used here -- Aerospace takes it
-- globally for the same idea one level up.
vim.keymap.set("n", "<leader>=", "<C-W>=", { remap = true, desc = "Equalize splits" })

vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true, desc = "Make current file executable" })

-- PC-style text keys, matching Karabiner's GUI layer and readline at the prompt.
-- Ctrl+A is line start everywhere now, so select-all moves to <leader>A and
-- Vim's own Ctrl+A increment goes -- deliberate, and flagged as an experiment.
vim.keymap.set("n", "<C-a>", "^", { desc = "Line start" })
vim.keymap.set("n", "<C-e>", "$", { desc = "Line end" })
vim.keymap.set("i", "<C-a>", "<Home>", { desc = "Line start" })
vim.keymap.set("i", "<C-e>", "<End>", { desc = "Line end" })
-- ggVG is linewise, so it takes whole lines including the last one; gg0vG$ is
-- charwise and stops short when the final line is empty.
vim.keymap.set("n", "<leader>A", "ggVG", { desc = "Select all text" })

vim.keymap.set("n", "<C-z>", "u", { desc = "Undo" })
vim.keymap.set("n", "<C-y>", "<C-r>", { desc = "Redo" })
vim.keymap.set("i", "<C-z>", "<C-o>u", { desc = "Undo" })
vim.keymap.set("i", "<C-y>", "<C-o><C-r>", { desc = "Redo" })

-- Terminal Mappings
vim.keymap.set("n", "<C-/>", "gcc", { remap = true, desc = "Toggle comment line" })
vim.keymap.set("n", "<c-_>", "gcc", { remap = true, desc = "which_key_ignore" })
vim.keymap.set("v", "<C-/>", "gc", { remap = true, desc = "Toggle comment for selection" })
vim.keymap.set("v", "<c-_>", "gc", { remap = true, desc = "which_key_ignore" })

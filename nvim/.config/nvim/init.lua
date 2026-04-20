-- Use system compiler to avoid macOS code signing issues with Nix-built binaries.
vim.env.CC = "/usr/bin/cc"

-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- import/override with your plugins
    { import = "plugins" },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- always use the latest git commit
    -- version = "*", -- try installing the latest stable version for plugins that support semver
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  checker = {
    enabled = true, -- check for plugin updates periodically
    notify = false, -- notify on update
  }, -- automatically check for plugin updates
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})

local persistenceGroup = vim.api.nvim_create_augroup("Persistence", { clear = true })
local home = vim.fn.expand("~")
local disabled_dirs = {
  home,
  home .. "/Downloads",
  "/private/tmp",
}

vim.api.nvim_create_autocmd({ "VimEnter" }, {
  group = persistenceGroup,
  callback = function()
    local cwd = vim.fn.getcwd()
    for _, path in pairs(disabled_dirs) do
      if path == cwd then
        require("persistence").stop()
        return
      end
    end
    if vim.fn.argc() == 0 and not vim.g.started_with_stdin then
      vim.notify("Restoring session...")
      require("persistence").load()
    else
      require("persistence").stop()
    end
  end,
  nested = true,
})

-- disable persistence if nvim started with stdin
-- vim.api.nvim_create_autocmd({ "StdinReadPre" }, {
--   group = persistenceGroup,
--   callback = function()
--     vim.notify("stdin event 222")
--     vim.g.started_with_stdin = true
--   end,
-- })

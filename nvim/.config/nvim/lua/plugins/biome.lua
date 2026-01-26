return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters = {
        biome = {
          -- Run "biome check --write" instead of "biome format" to enable import sorting.
          -- "biome check" runs the formatter, linter, and import sorting.
          command = "biome",
          args = { "check", "--write", "--stdin-file-path", "$FILENAME" },
          -- "check" exits with code 1 if there are remaining lint errors/warnings,
          -- but we still want to apply the formatting and import sorting.
          exit_codes = { 0, 1 },
        },
      },
      formatters_by_ft = {
        ["javascript"] = { "biome" },
        ["javascriptreact"] = { "biome" },
        ["typescript"] = { "biome" },
        ["typescriptreact"] = { "biome" },
        ["json"] = { "biome" },
        ["jsonc"] = { "biome" },
        ["css"] = { "biome" },
      },
    },
  },
}

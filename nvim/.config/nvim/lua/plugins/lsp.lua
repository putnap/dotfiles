return {
    "neovim/nvim-lspconfig",
    opts = {
        servers = {
            ["*"] = {
                keys = {
                    {
                        "<leader>.",
                        vim.lsp.buf.code_action,
                        desc = "Code Action",
                        mode = { "n", "v" },
                        has = "codeAction",
                    },
                },
            },
        },
    },
}

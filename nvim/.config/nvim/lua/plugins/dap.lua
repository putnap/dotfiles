return {
    "mfussenegger/nvim-dap",
    dependencies = {
        {
            "jay-babu/mason-nvim-dap.nvim",
            event = "BufReadPre",
        },
    },
    opts = function()
        local dap = require("dap")
        local function nearest_main_go_info()
            local current_dir = vim.fn.expand("%:p:h")
            local main_go_path = vim.fn.findfile("main.go", current_dir .. ";")
            if main_go_path == "" then
                return nil, nil
            end
            main_go_path = vim.fn.fnamemodify(main_go_path, ":p")
            return main_go_path, vim.fn.fnamemodify(main_go_path, ":h")
        end

        dap.configurations.go = {
            {
                type = "delve",
                name = "Delve: Debug Go",
                request = "launch",
                program = function()
                    local main_go, _ = nearest_main_go_info()
                    return main_go
                end,
                cwd = function()
                    local _, cwd = nearest_main_go_info()
                    return cwd
                end,
            },
        }
    end,
}

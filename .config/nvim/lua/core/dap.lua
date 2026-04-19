local js_debug_dap = "/home/max/.local/share/nvim/mason/packages/js-debug-adapter/js-debug/src/dapDebugServer.js"

local function js_debug_adapter()
    return {
        type = "server",
        host = "localhost",
        port = "${port}",
        executable = {
            command = "node",
            args = { js_debug_dap, "${port}" },
        },
    }
end

require("dap").adapters["pwa-node"] = js_debug_adapter()
require("dap").adapters["pwa-chrome"] = js_debug_adapter()

require("dap").configurations.javascript = {
    {
        type = "pwa-node",
        request = "launch",
        name = "Launch file",
        program = "${file}",
        cwd = "${workspaceFolder}",
    },
    {
        type = "pwa-chrome",
        request = "launch",
        name = "Debug Angular",
        url = "http://localhost:4200",
        webRoot = "${workspaceFolder}",
        sourceMaps = true,
    },
}

require("dap").configurations.typescript = {
    {
        type = 'pwa-node',
        request = 'launch',
        name = "Launch file",
        runtimeExecutable = "deno",
        runtimeArgs = {
            "run",
            "--inspect-wait",
            "--allow-all"
        },
        program = "${file}",
        cwd = "${workspaceFolder}",
        attachSimplePort = 9229,
    },
    {
        type = "pwa-chrome",
        request = "launch",
        name = "Debug Angular",
        url = "http://localhost:4200",
        webRoot = "${workspaceFolder}",
        sourceMaps = true,
    },
}

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

require("dap").adapters["pwa-chrome"] = js_debug_adapter()

require("dap").configurations.typescript = {
    {
        type = "pwa-chrome",
        request = "launch",
        name = "Debug Angular",
        url = "http://localhost:4200",
        webRoot = "${workspaceFolder}",
        sourceMaps = true,
    },
}

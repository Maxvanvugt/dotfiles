local dap = require("dap")
local dapui = require("dapui")

-- Mason's `js-debug-adapter` wraps vscode-js-debug; the plugin's default `debugger_path`
-- targets a Packer layout that vim.pack does not use.
local js_adapter = vim.fn.stdpath("data") .. "/mason/bin/js-debug-adapter"
if vim.fn.executable(js_adapter) == 0 and vim.fn.executable("js-debug-adapter") == 1 then
    js_adapter = "js-debug-adapter"
end

-- Stale js-debug-adapter processes often keep the default DAP listen port busy (EADDRINUSE).
local JS_DEBUG_DAP_PORT = 8123

-- Kill listeners on `port` before spawning js-debug-adapter; no-op if a DAP session exists.
local function free_stale_js_debug_port(port)
    if dap.session() then
        return
    end
    port = port or JS_DEBUG_DAP_PORT
    local sh = string.format(
        "(command -v fuser >/dev/null 2>&1 && fuser -k %d/tcp >/dev/null 2>&1); "
            .. "(command -v lsof >/dev/null 2>&1 && PIDS=$(lsof -t -iTCP:%d -sTCP:LISTEN 2>/dev/null) && "
            .. '[ -n "$PIDS" ] && kill -TERM $PIDS 2>/dev/null); true',
        port,
        port
    )
    if vim.system then
        vim.system({ "sh", "-c", sh }, { text = true }):wait()
    else
        os.execute(sh)
    end
end

-- nvim-dap-vscode-js assumes stdout is only the port number. Current vscode-js-debug prints
-- a line like "Debug server listening at 127.0.0.1:8123", so nvim-dap's connect() gets
-- tonumber(adapter.port) == nil → "adapter.port is required". Buffer chunks and parse.
do
    local utils = require("dap-vscode-js.utils")
    local orig_start = utils.start_debugger
    ---@param chunk string
    local function parse_listen_port(chunk)
        local s = chunk:gsub("\r", ""):gsub("\n", "")
        local n = tonumber(s)
        if n then
            return n
        end
        return tonumber(s:match(":%s*(%d+)%s*$") or s:match("(%d+)%s*$"))
    end

    function utils.start_debugger(config, on_launch, on_exit, on_error, on_stderror)
        local buf = ""
        local launched = false
        local proc_ref

        local function on_launch_parsed(chunk, proc)
            if launched then
                return
            end
            proc_ref = proc_ref or proc
            buf = buf .. tostring(chunk)
            local port = parse_listen_port(buf)
            if not port then
                return
            end
            launched = true
            on_launch(port, proc_ref)
        end

        free_stale_js_debug_port(JS_DEBUG_DAP_PORT)
        return orig_start(config, on_launch_parsed, on_exit, on_error, on_stderror)
    end
end

require("dap-vscode-js").setup({
    debugger_cmd = { js_adapter },
    adapters = { "pwa-node", "pwa-chrome", "node-terminal", "pwa-msedge" },
})

-- nvim-dap resolves `startDebugging` by calling the adapter with a parent session
-- (`:h dap-adapter`, third argument). Child sessions must open another TCP connection
-- to the *same* js-debug server; nvim-dap-vscode-js spawns a second process instead,
-- which causes EADDRINUSE on 8123 and "adapter.port is required".
local js_adapter_names = { "pwa-node", "pwa-chrome", "node-terminal", "pwa-msedge" }
for _, name in ipairs(js_adapter_names) do
    local orig = dap.adapters[name]
    if type(orig) == "function" then
        dap.adapters[name] = function(cb, config, parent)
            local pa = parent and parent.adapter
            if pa and tonumber(pa.port) and pa.type == "server" then
                local a = vim.deepcopy(pa)
                a.executable = nil
                cb(a)
                return
            end
            orig(cb, config, parent)
        end
    end
end

vim.schedule(function()
    if vim.fn.executable(js_adapter) == 0 then
        vim.notify("Install the JS debug adapter: :MasonInstall js-debug-adapter", vim.log.levels.WARN)
    end
end)

local function angular_and_node_configs()
    local cwd = vim.fn.getcwd()
    return {
        {
            type = "pwa-chrome",
            request = "launch",
            name = "Angular: launch Chrome (ng serve)",
            url = "http://localhost:4200",
            webRoot = cwd,
            sourceMaps = true,
        },
        {
            type = "pwa-chrome",
            request = "attach",
            name = "Angular: attach Chrome :9222",
            port = 9222,
            webRoot = cwd,
        },
        {
            type = "pwa-node",
            request = "launch",
            name = "Node: launch current file",
            program = "${file}",
            cwd = cwd,
        },
        {
            type = "pwa-node",
            request = "attach",
            name = "Node: attach to process",
            processId = require("dap.utils").pick_process,
            cwd = cwd,
        },
    }
end

local cfgs = angular_and_node_configs()
for _, lang in ipairs({ "typescript", "javascript" }) do
    dap.configurations[lang] = cfgs
end

dapui.setup()

dap.listeners.before.attach.dapui_config = function()
    dapui.open()
end
dap.listeners.before.launch.dapui_config = function()
    dapui.open()
end
dap.listeners.before.event_terminated.dapui_config = function()
    dapui.close()
end
dap.listeners.before.event_exited.dapui_config = function()
    dapui.close()
end

vim.keymap.set("n", "<leader>dc", dap.continue, { desc = "DAP continue / start" })
vim.keymap.set("n", "<leader>db", dap.toggle_breakpoint, { desc = "DAP toggle breakpoint" })
vim.keymap.set("n", "<leader>dB", function()
    dap.set_breakpoint(vim.fn.input("Condition: "))
end, { desc = "DAP conditional breakpoint" })
vim.keymap.set("n", "<leader>dl", dap.run_last, { desc = "DAP run last" })
vim.keymap.set("n", "<leader>di", dap.step_into, { desc = "DAP step into" })
vim.keymap.set("n", "<leader>do", dap.step_over, { desc = "DAP step over" })
vim.keymap.set("n", "<leader>dO", dap.step_out, { desc = "DAP step out" })
vim.keymap.set("n", "<leader>dr", function()
    require("dap.repl").toggle()
end, { desc = "DAP REPL" })
vim.keymap.set("n", "<leader>du", dapui.toggle, { desc = "DAP UI toggle" })
vim.keymap.set("n", "<leader>dk", dap.terminate, { desc = "DAP terminate" })

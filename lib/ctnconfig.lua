-- ctnconfig.lua
-- Shared config loader. Each terminal stores its settings in /.ctn_config.
-- If the config doesn't exist or is incomplete, we run a first-run wizard.
-- This eliminates the "edit /startup.lua and change MAINFRAME_ID" step.

local M = {}

M.PATH = "/.ctn_config"

local function readFile(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r"); local s = f.readAll(); f.close()
    return s
end

local function writeFile(path, s)
    local f = fs.open(path, "w"); f.write(s); f.close()
end

function M.load()
    local s = readFile(M.PATH)
    if not s then return nil end
    local ok, t = pcall(textutils.unserialize, s)
    if not ok or type(t) ~= "table" then return nil end
    return t
end

function M.save(cfg)
    writeFile(M.PATH, textutils.serialize(cfg))
end

--- Run the first-run wizard for the given role, filling required fields.
-- Each field spec: {key, prompt, type="string"|"number"|"pick", options?, default?}
function M.wizard(role, fieldSpecs)
    local ui = require("ctnui")
    local cfg = M.load() or {role = role}

    ui.clear(term.current())
    ui.header(term.current(), "FIRST-RUN SETUP: "..role:upper())
    term.setCursorPos(2, 5)
    term.setTextColor(ui.WARN)
    print("This terminal has not been configured.")
    term.setCursorPos(2, 6)
    print("Answer a few questions to set it up.")
    term.setCursorPos(2, 7)
    term.setTextColor(ui.DIM); print("(You can re-run this later with: ctn-reconfigure)")
    term.setCursorPos(2, 9)

    local y = 9
    for _, spec in ipairs(fieldSpecs) do
        term.setCursorPos(2, y); term.setTextColor(ui.FG)
        if spec.type == "pick" then
            print(spec.prompt)
            for i, opt in ipairs(spec.options) do
                term.setCursorPos(4, y + i)
                term.setTextColor(ui.DIM); write("["..i.."] ")
                term.setTextColor(ui.FG);  write(opt)
            end
            term.setCursorPos(2, y + #spec.options + 2)
            term.setTextColor(ui.FG); write("> "); term.setTextColor(ui.ACCENT)
            local n = tonumber(read())
            cfg[spec.key] = spec.options[n] or spec.default or spec.options[1]
            term.setTextColor(ui.FG)
            y = y + #spec.options + 3
        else
            write(spec.prompt)
            if spec.default ~= nil then write(" ["..tostring(spec.default).."]") end
            write(": ")
            term.setTextColor(ui.ACCENT)
            local input = read()
            term.setTextColor(ui.FG)
            if input == "" and spec.default ~= nil then
                cfg[spec.key] = spec.default
            elseif spec.type == "number" then
                cfg[spec.key] = tonumber(input) or spec.default
            else
                cfg[spec.key] = input
            end
            y = y + 1
        end
        if y >= select(2, term.getSize()) - 2 then
            term.setTextColor(ui.DIM); write("[Enter to continue]"); read()
            ui.clear(term.current())
            ui.header(term.current(), "FIRST-RUN SETUP: "..role:upper())
            y = 5
        end
    end

    M.save(cfg)
    ui.bigStatus(term.current(), {"SETUP COMPLETE", "", "Rebooting..."}, "granted")
    sleep(1.5)
    os.reboot()
end

--- Load config or run wizard. Returns the config table.
function M.loadOrWizard(role, fieldSpecs)
    local cfg = M.load()
    if cfg and cfg.role == role then
        for _, spec in ipairs(fieldSpecs) do
            if cfg[spec.key] == nil then
                -- missing field, re-run wizard
                M.wizard(role, fieldSpecs)
                return
            end
        end
        return cfg
    end
    M.wizard(role, fieldSpecs)
end

return M

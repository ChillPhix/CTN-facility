-- ctnui.lua
-- Shared UI library for CTN terminals.
-- Supports dynamic color schemes per-facility.
-- Place at /lib/ctnui.lua on every computer that has a UI.

local M = {}

-- ============================================================
-- Color schemes
-- ============================================================
M.SCHEMES = {
    yellow = {
        fg = colors.yellow, bg = colors.black, dim = colors.gray,
        border = colors.yellow, ok = colors.lime, warn = colors.orange,
        err = colors.red, accent = colors.white,
    },
    red = {
        fg = colors.red, bg = colors.black, dim = colors.gray,
        border = colors.red, ok = colors.lime, warn = colors.orange,
        err = colors.red, accent = colors.white,
    },
    cyan = {
        fg = colors.cyan, bg = colors.black, dim = colors.gray,
        border = colors.cyan, ok = colors.lime, warn = colors.orange,
        err = colors.red, accent = colors.white,
    },
    green = {
        fg = colors.green, bg = colors.black, dim = colors.gray,
        border = colors.green, ok = colors.lime, warn = colors.orange,
        err = colors.red, accent = colors.white,
    },
    purple = {
        fg = colors.purple, bg = colors.black, dim = colors.gray,
        border = colors.purple, ok = colors.lime, warn = colors.orange,
        err = colors.red, accent = colors.white,
    },
    blue = {
        fg = colors.blue, bg = colors.black, dim = colors.gray,
        border = colors.blue, ok = colors.lime, warn = colors.orange,
        err = colors.red, accent = colors.white,
    },
    white = {
        fg = colors.white, bg = colors.black, dim = colors.gray,
        border = colors.white, ok = colors.lime, warn = colors.orange,
        err = colors.red, accent = colors.lightBlue,
    },
    orange = {
        fg = colors.orange, bg = colors.black, dim = colors.gray,
        border = colors.orange, ok = colors.lime, warn = colors.yellow,
        err = colors.red, accent = colors.white,
    },
    lime = {
        fg = colors.lime, bg = colors.black, dim = colors.gray,
        border = colors.lime, ok = colors.green, warn = colors.orange,
        err = colors.red, accent = colors.white,
    },
    pink = {
        fg = colors.pink, bg = colors.black, dim = colors.gray,
        border = colors.pink, ok = colors.lime, warn = colors.orange,
        err = colors.red, accent = colors.white,
    },
}

-- ============================================================
-- Theme (defaults to yellow, can be swapped at runtime)
-- ============================================================
M.BG      = colors.black
M.FG      = colors.yellow
M.DIM     = colors.gray
M.BORDER  = colors.yellow
M.OK      = colors.lime
M.WARN    = colors.orange
M.ERR     = colors.red
M.ACCENT  = colors.white

-- Facility identity (set by applyIdentity)
M.facilityName     = "C.T.N"
M.facilitySubtitle = "CONTAINMENT DIVISION"
M.colorSchemeName  = "yellow"

--- Apply a color scheme by name.
function M.applyScheme(schemeName)
    local scheme = M.SCHEMES[schemeName] or M.SCHEMES.yellow
    M.BG      = scheme.bg
    M.FG      = scheme.fg
    M.DIM     = scheme.dim
    M.BORDER  = scheme.border
    M.OK      = scheme.ok
    M.WARN    = scheme.warn
    M.ERR     = scheme.err
    M.ACCENT  = scheme.accent
    M.colorSchemeName = schemeName
end

--- Apply full facility identity (name + subtitle + colors).
-- Called by terminals after receiving identity from mainframe.
function M.applyIdentity(identity)
    if not identity then return end
    M.facilityName     = identity.name or M.facilityName
    M.facilitySubtitle = identity.subtitle or M.facilitySubtitle
    if identity.colorScheme then
        M.applyScheme(identity.colorScheme)
    end
end

--- Save identity to a local cache file so it persists across reboots
--- even before the mainframe is contacted.
function M.cacheIdentity()
    local f = fs.open("/.ctn_identity", "w")
    f.write(textutils.serialize({
        name = M.facilityName,
        subtitle = M.facilitySubtitle,
        colorScheme = M.colorSchemeName,
    }))
    f.close()
end

--- Load cached identity from disk (if any).
function M.loadCachedIdentity()
    if not fs.exists("/.ctn_identity") then return false end
    local f = fs.open("/.ctn_identity", "r")
    local s = f.readAll(); f.close()
    local ok, t = pcall(textutils.unserialize, s)
    if ok and type(t) == "table" then
        M.applyIdentity(t)
        return true
    end
    return false
end

-- ============================================================
-- Low-level helpers
-- ============================================================

--- Normalise either term.native() or a monitor peripheral into a target.
function M.target(dev)
    return dev or term.current()
end

function M.setColors(t, fg, bg)
    t = M.target(t)
    t.setTextColor(fg or M.FG)
    t.setBackgroundColor(bg or M.BG)
end

function M.clear(t)
    t = M.target(t)
    M.setColors(t)
    t.clear()
    t.setCursorPos(1,1)
end

function M.writeAt(t, x, y, text, fg, bg)
    t = M.target(t)
    t.setCursorPos(x, y)
    if fg or bg then M.setColors(t, fg, bg) end
    t.write(text)
end

function M.center(t, y, text, fg, bg)
    t = M.target(t)
    local w = select(1, t.getSize())
    local x = math.max(1, math.floor((w - #text) / 2) + 1)
    M.writeAt(t, x, y, text, fg, bg)
end

function M.hline(t, y, char, fg, bg)
    t = M.target(t)
    local w = select(1, t.getSize())
    M.writeAt(t, 1, y, string.rep(char or "-", w), fg, bg)
end

--- Draw a filled rectangle of a single colour (background).
function M.fill(t, x, y, w, h, bg)
    t = M.target(t)
    t.setBackgroundColor(bg or M.BG)
    for i = 0, h - 1 do
        t.setCursorPos(x, y + i)
        t.write(string.rep(" ", w))
    end
end

--- Draw a box with single-line borders using `-` `|` `+`.
function M.box(t, x, y, w, h, fg, bg)
    t = M.target(t)
    M.setColors(t, fg or M.BORDER, bg or M.BG)
    t.setCursorPos(x, y);           t.write("+"..string.rep("-", w-2).."+")
    t.setCursorPos(x, y + h - 1);   t.write("+"..string.rep("-", w-2).."+")
    for i = 1, h - 2 do
        t.setCursorPos(x, y + i);         t.write("|")
        t.setCursorPos(x + w - 1, y + i); t.write("|")
    end
end

-- ============================================================
-- Standard layouts
-- ============================================================

--- Draw the CTN header bar across the top of the screen.
-- Shows facility name and a subtitle line.
function M.header(t, subtitle)
    t = M.target(t)
    local w = select(1, t.getSize())
    -- Top banner: themed color background
    t.setCursorPos(1, 1); t.setBackgroundColor(M.FG); t.setTextColor(M.BG)
    t.write(string.rep(" ", w))
    local title = M.facilityName .. "  -  " .. M.facilitySubtitle
    t.setCursorPos(math.max(1, math.floor((w - #title)/2)+1), 1)
    t.write(title)
    -- Subtitle line
    t.setCursorPos(1, 2); t.setBackgroundColor(M.BG); t.setTextColor(M.FG)
    t.write(string.rep(" ", w))
    if subtitle then
        t.setCursorPos(math.max(1, math.floor((w - #subtitle)/2)+1), 2)
        t.write(subtitle)
    end
    -- Divider
    t.setCursorPos(1, 3); t.setTextColor(M.BORDER)
    t.write(string.rep("=", w))
    t.setBackgroundColor(M.BG); t.setTextColor(M.FG)
end

--- Draw a footer bar at the bottom with status text.
function M.footer(t, text, fg)
    t = M.target(t)
    local w, h = t.getSize()
    t.setCursorPos(1, h); t.setBackgroundColor(M.FG); t.setTextColor(M.BG)
    t.write(string.rep(" ", w))
    if text then
        t.setCursorPos(2, h)
        t.write(text)
    end
    t.setCursorPos(1, h - 1); t.setBackgroundColor(M.BG); t.setTextColor(fg or M.BORDER)
    t.write(string.rep("=", w))
    t.setBackgroundColor(M.BG); t.setTextColor(M.FG)
end

--- Clear screen and draw header+footer, leaving content area between rows 4 and h-2.
function M.frame(t, subtitle, footerText)
    t = M.target(t)
    M.clear(t)
    M.header(t, subtitle)
    M.footer(t, footerText or M.facilityName.." SECURE TERMINAL")
end

--- Content-area bounds after frame(): returns x1, y1, x2, y2.
function M.contentBounds(t)
    t = M.target(t)
    local w, h = t.getSize()
    return 1, 4, w, h - 2
end

-- ============================================================
-- Prompts (console input with themed styling)
-- ============================================================
function M.prompt(label)
    term.setBackgroundColor(M.BG)
    term.setTextColor(M.FG)
    write(label)
    term.setTextColor(M.ACCENT)
    local s = read()
    term.setTextColor(M.FG)
    return s
end

function M.promptHidden(label)
    term.setBackgroundColor(M.BG)
    term.setTextColor(M.FG)
    write(label)
    term.setTextColor(M.ACCENT)
    local s = read("*")
    term.setTextColor(M.FG)
    return s
end

--- Simple numbered menu. Returns the choice (1-indexed) or nil on cancel.
function M.menu(title, options, startY)
    startY = startY or 5
    term.setBackgroundColor(M.BG)
    term.setTextColor(M.FG)
    if title then
        M.center(term.current(), startY - 1, title, M.ACCENT)
    end
    for i, opt in ipairs(options) do
        term.setCursorPos(4, startY + i)
        term.setTextColor(M.DIM);    write("["..i.."] ")
        term.setTextColor(M.FG);     write(opt)
    end
    term.setCursorPos(4, startY + #options + 2)
    term.setTextColor(M.FG); write("> ")
    term.setTextColor(M.ACCENT)
    local n = tonumber(read())
    term.setTextColor(M.FG)
    if n and options[n] then return n end
    return nil
end

--- Big centered status block. Call with a list of lines and a state keyword.
-- states: "idle", "working", "granted", "denied", "error"
function M.bigStatus(t, lines, state)
    t = M.target(t)
    M.clear(t)
    M.header(t, "SECURE TERMINAL")

    local w, h = t.getSize()
    local stateColor = ({
        idle    = M.FG,
        working = M.WARN,
        granted = M.OK,
        denied  = M.ERR,
        error   = M.ERR,
    })[state] or M.FG

    -- Big border box in the middle
    local boxH = math.min(#lines + 4, h - 6)
    local boxY = math.floor((h - boxH) / 2) + 1
    M.box(t, 2, boxY, w - 2, boxH, stateColor)

    for i, line in ipairs(lines) do
        M.center(t, boxY + 1 + i, line, stateColor)
    end

    M.footer(t, M.facilityName.." // "..string.upper(state or "status"))
end

--- Blocking confirmation dialog on the console. Returns true/false.
function M.confirm(msg)
    M.clear(term.current())
    M.header(term.current(), "CONFIRMATION REQUIRED")
    term.setCursorPos(2, 5); term.setTextColor(M.WARN); write(msg)
    term.setCursorPos(2, 7); term.setTextColor(M.FG);   write("Type YES to confirm: ")
    term.setTextColor(M.ACCENT)
    local s = read()
    return s == "YES"
end

-- ============================================================
-- Touch/click button framework
-- ============================================================
-- Each button is a rectangular region with a label. Call drawButton to
-- render it, then waitForClick to block until any button is hit or an
-- external event arrives.

--- Draw a button. Returns the button descriptor for hit-testing.
-- @param t           target (term or monitor)
-- @param x, y, w, h  bounds
-- @param label       button text
-- @param opts        {fg, bg, selected=bool, disabled=bool, hotkey="a"}
function M.drawButton(t, x, y, w, h, label, opts)
    t = M.target(t); opts = opts or {}
    local bg = opts.bg or (opts.selected and M.FG or M.BG)
    local fg = opts.fg or (opts.selected and M.BG or M.FG)
    if opts.disabled then bg = M.BG; fg = M.DIM end

    -- Fill
    t.setBackgroundColor(bg); t.setTextColor(fg)
    for i = 0, h - 1 do
        t.setCursorPos(x, y + i); t.write(string.rep(" ", w))
    end

    -- Border
    local bc = opts.disabled and M.DIM or (opts.selected and M.ACCENT or M.BORDER)
    t.setTextColor(bc)
    t.setCursorPos(x, y);         t.write("+"..string.rep("-", w-2).."+")
    t.setCursorPos(x, y + h - 1); t.write("+"..string.rep("-", w-2).."+")
    for i = 1, h - 2 do
        t.setCursorPos(x, y + i);         t.write("|")
        t.setCursorPos(x + w - 1, y + i); t.write("|")
    end

    -- Label centered
    t.setBackgroundColor(bg); t.setTextColor(fg)
    local ly = y + math.floor(h / 2)
    local lx = x + math.max(1, math.floor((w - #label) / 2))
    t.setCursorPos(lx, ly); t.write(label)

    -- Hotkey hint (bottom-right)
    if opts.hotkey then
        t.setCursorPos(x + w - 3, y + h - 1)
        t.setTextColor(M.DIM); t.write("["..opts.hotkey:upper().."]")
    end

    t.setBackgroundColor(M.BG); t.setTextColor(M.FG)
    return {x=x, y=y, w=w, h=h, label=label, hotkey=opts.hotkey, disabled=opts.disabled}
end

--- Test whether (cx, cy) is inside a button.
function M.hit(btn, cx, cy)
    return not btn.disabled
       and cx >= btn.x and cx < btn.x + btn.w
       and cy >= btn.y and cy < btn.y + btn.h
end

--- Wait for a click/touch on any of the buttons, or pass through any
--- other event. Returns (buttonIndex) on hit, or (nil, event, ...) on
--- other events so the caller can still react to rednet/disk/etc.
-- @param buttons  list of button descriptors from drawButton
-- @param monTarget  optional monitor peripheral (pass if buttons drawn on monitor)
function M.waitForClick(buttons, monTarget)
    while true do
        local evt = {os.pullEvent()}
        local etype = evt[1]
        if etype == "mouse_click" then
            local cx, cy = evt[3], evt[4]
            for i, b in ipairs(buttons) do
                if M.hit(b, cx, cy) then return i end
            end
        elseif etype == "monitor_touch" then
            -- evt[2] is monitor side; evt[3], evt[4] are coords
            for i, b in ipairs(buttons) do
                if M.hit(b, evt[3], evt[4]) then return i end
            end
        elseif etype == "char" then
            local key = evt[2]:lower()
            for i, b in ipairs(buttons) do
                if b.hotkey and b.hotkey:lower() == key then return i end
            end
        else
            return nil, table.unpack(evt)
        end
    end
end

--- Like waitForClick but only for buttons + hotkeys. Blocks until one is hit.
function M.clickMenu(buttons)
    while true do
        local choice = M.waitForClick(buttons)
        if choice then return choice end
    end
end

-- ============================================================
-- Layout helpers
-- ============================================================

--- Automatically lay out a grid of button labels.
-- @param t       target
-- @param labels  list of strings
-- @param opts    {startY=4, cols=1, padY=1, btnH=3, hotkeys=bool}
-- @return list of button descriptors in the same order as labels
function M.buttonGrid(t, labels, opts)
    t = M.target(t); opts = opts or {}
    local w, _ = t.getSize()
    local cols = opts.cols or (w >= 40 and 2 or 1)
    local startY = opts.startY or 5
    local btnH = opts.btnH or 3
    local padY = opts.padY or 0
    local padX = 2
    local btnW = math.floor((w - padX * (cols + 1)) / cols)

    local buttons = {}
    for i, label in ipairs(labels) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = padX + col * (btnW + padX)
        local y = startY + row * (btnH + padY)
        local hotkey
        if opts.hotkeys then
            if i <= 9 then hotkey = tostring(i)
            else hotkey = string.char(96 + i - 9) end  -- a, b, c...
        end
        buttons[i] = M.drawButton(t, x, y, btnW, btnH, label, {hotkey=hotkey})
    end
    return buttons
end

-- ============================================================
-- Ornamented header variants (looks better)
-- ============================================================

--- Large warning banner for lockdown/breach states.
function M.alertBanner(t, state, subtitle)
    t = M.target(t)
    local w = select(1, t.getSize())
    local colors_by_state = {
        lockdown = {bg=M.ERR, fg=M.BG,  title="!! FACILITY LOCKDOWN !!"},
        breach   = {bg=M.ERR, fg=M.BG,  title="!! CONTAINMENT BREACH !!"},
        warning  = {bg=M.WARN, fg=M.BG, title="** SECURITY ALERT **"},
        caution  = {bg=M.WARN, fg=M.BG, title="* CAUTION *"},
    }
    local spec = colors_by_state[state]
    if not spec then return end

    -- Top banner
    t.setCursorPos(1, 1); t.setBackgroundColor(spec.bg); t.setTextColor(spec.fg)
    t.write(string.rep(" ", w))
    t.setCursorPos(math.max(1, math.floor((w - #spec.title)/2)+1), 1); t.write(spec.title)

    t.setCursorPos(1, 2); t.setBackgroundColor(spec.bg); t.setTextColor(spec.fg)
    t.write(string.rep(" ", w))
    if subtitle then
        local st = subtitle:sub(1, w - 2)
        t.setCursorPos(math.max(1, math.floor((w - #st)/2)+1), 2); t.write(st)
    end

    t.setCursorPos(1, 3); t.setBackgroundColor(M.BG); t.setTextColor(spec.bg)
    t.write(string.rep("=", w))
    t.setBackgroundColor(M.BG); t.setTextColor(M.FG)
end

--- Mini badge (for small status indicators in corners etc.)
function M.badge(t, x, y, label, fg, bg)
    t = M.target(t)
    t.setCursorPos(x, y); t.setBackgroundColor(bg or M.FG); t.setTextColor(fg or M.BG)
    t.write(" "..label.." ")
    t.setBackgroundColor(M.BG); t.setTextColor(M.FG)
end

--- Call on terminal boot to load cached identity. Returns true if loaded.
function M.bootIdentity()
    return M.loadCachedIdentity()
end

--- Call when receiving a reply from mainframe that includes identity.
--- Updates colors + caches to disk for next boot.
function M.syncIdentity(reply)
    if reply and reply.identity then
        M.applyIdentity(reply.identity)
        M.cacheIdentity()
        -- Also sync GPU colors if ctngpu is loaded
        local ok, gpu = pcall(require, "ctngpu")
        if ok and gpu and gpu.applyScheme then
            gpu.applyScheme(reply.identity.colorScheme or "yellow")
        end
    end
end

return M

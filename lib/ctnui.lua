-- ctnui.lua
-- Shared UI library for CTN terminals.
-- Yellow-on-black CTN Containment Division theme.
-- Place at /lib/ctnui.lua on every computer that has a UI.

local M = {}

-- ============================================================
-- Theme
-- ============================================================
M.BG      = colors.black
M.FG      = colors.yellow
M.DIM     = colors.gray
M.BORDER  = colors.yellow
M.OK      = colors.lime
M.WARN    = colors.orange
M.ERR     = colors.red
M.ACCENT  = colors.white

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
-- Shows "C.T.N - CONTAINMENT DIVISION" and a subtitle line.
function M.header(t, subtitle)
    t = M.target(t)
    local w = select(1, t.getSize())
    -- Top banner: yellow background, black text
    t.setCursorPos(1, 1); t.setBackgroundColor(M.FG); t.setTextColor(M.BG)
    t.write(string.rep(" ", w))
    local title = "C.T.N  -  CONTAINMENT DIVISION"
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
    M.footer(t, footerText or "C.T.N SECURE TERMINAL")
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

    M.footer(t, "C.T.N // "..string.upper(state or "status"))
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

return M

-- lib/ctngpu.lua
-- CTN DirectGPU wrapper and widget library.
--
-- Provides high-level drawing primitives (titled panels, status bars,
-- gauges, warning lights, log feeds) in the CTN yellow/black theme.
-- Automatically uses DirectGPU if present, falls back to a monitor
-- peripheral using standard CC drawing if not.
--
-- Target: attach a DirectGPU block, OR a regular advanced monitor.
-- The library figures out which you have and renders accordingly.

local M = {}

-- ============================================================
-- CTN color palette (RGB, 0-255)
-- ============================================================
M.COLORS = {
    bg       = {  0,   0,   0},   -- black
    fg       = {255, 204,   0},   -- CTN yellow
    dim      = {102,  82,   0},   -- dimmed yellow
    border   = {255, 204,   0},
    ok       = { 34, 177,  76},   -- green
    warn     = {255, 140,   0},   -- orange
    err      = {237,  28,  36},   -- red
    accent   = {255, 255, 255},
    accent2  = {  0, 204, 255},   -- cyan (for info)
    purple   = {163,  73, 164},
    panelBg  = { 20,  18,   5},   -- very dark yellow-tinted bg for panels
    panelHdr = {255, 204,   0},
    panelHdrFg = { 0,   0,   0},
}

local CC_COLOR_MAP = {
    bg       = colors.black,
    fg       = colors.yellow,
    dim      = colors.gray,
    border   = colors.yellow,
    ok       = colors.lime,
    warn     = colors.orange,
    err      = colors.red,
    accent   = colors.white,
    accent2  = colors.lightBlue,
    purple   = colors.purple,
    panelBg  = colors.black,
    panelHdr = colors.yellow,
    panelHdrFg = colors.black,
}

-- ============================================================
-- Backend detection
-- ============================================================

--- Try to open a rendering backend. Returns a backend table with methods:
---   :clear(), :fillRect(x,y,w,h,color), :drawLine, :text(x,y,s,fg,bg),
---   :update(), :size() -> w,h (pixels or chars), :mode ("gpu"|"mon"|"term")
---   :pollEvent() -> evt or nil (returns nil immediately if no event)
--- Options: {preferGpu=true, monitorName=?, gpuName=?}
function M.openBackend(opts)
    opts = opts or {}

    -- Try DirectGPU first
    if opts.preferGpu ~= false then
        local gpu = peripheral.find("directgpu")
        if gpu then
            local ok, display = pcall(gpu.autoDetectAndCreateDisplay)
            if ok and display then
                return M.gpuBackend(gpu, display)
            end
        end
    end

    -- Fallback: monitor peripheral
    local mon
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == "monitor" then
            mon = peripheral.wrap(side); break
        end
    end
    if mon then
        mon.setTextScale(0.5)
        return M.monBackend(mon)
    end

    -- Last resort: the terminal itself
    return M.termBackend(term.current())
end

-- ============================================================
-- GPU backend
-- ============================================================
function M.gpuBackend(gpu, display)
    local be = {mode="gpu", gpu=gpu, display=display}

    local info = gpu.getDisplayInfo(display)
    -- getDisplayInfo returns a string (JSON-like). We fall back to safe defaults.
    be.w, be.h = 164, 81
    if type(info) == "string" then
        local pw = info:match("pixelWidth[%s:=]*(%d+)")
        local ph = info:match("pixelHeight[%s:=]*(%d+)")
        if pw then be.w = tonumber(pw) end
        if ph then be.h = tonumber(ph) end
    elseif type(info) == "table" then
        be.w = info.pixelWidth or be.w
        be.h = info.pixelHeight or be.h
    end

    function be:size() return self.w, self.h end

    function be:clear(color)
        color = color or M.COLORS.bg
        self.gpu.clear(self.display, color[1], color[2], color[3])
    end

    function be:fillRect(x, y, w, h, color)
        self.gpu.fillRect(self.display, x, y, w, h, color[1], color[2], color[3])
    end

    function be:drawRect(x, y, w, h, color)
        -- GPU has drawRect? Use rounded rect with radius 0 or 4 lines.
        self.gpu.drawLine(self.display, x, y, x+w-1, y, color[1], color[2], color[3])
        self.gpu.drawLine(self.display, x, y+h-1, x+w-1, y+h-1, color[1], color[2], color[3])
        self.gpu.drawLine(self.display, x, y, x, y+h-1, color[1], color[2], color[3])
        self.gpu.drawLine(self.display, x+w-1, y, x+w-1, y+h-1, color[1], color[2], color[3])
    end

    function be:roundedRect(x, y, w, h, radius, color, filled)
        pcall(self.gpu.drawRoundedRect, self.display, x, y, w, h, radius or 4,
              color[1], color[2], color[3], filled and true or false)
    end

    function be:line(x1, y1, x2, y2, color)
        self.gpu.drawLine(self.display, x1, y1, x2, y2, color[1], color[2], color[3])
    end

    function be:circle(cx, cy, r, color, filled)
        self.gpu.drawCircle(self.display, cx, cy, r,
            color[1], color[2], color[3], filled and true or false)
    end

    function be:text(x, y, s, fg, size, style)
        fg = fg or M.COLORS.fg
        size = size or 14
        self.gpu.drawText(self.display, s, x, y,
            fg[1], fg[2], fg[3], "Monospaced", size, style or "plain")
    end

    function be:textBg(x, y, s, fg, bg, size, style)
        fg = fg or M.COLORS.fg; bg = bg or M.COLORS.bg
        size = size or 14
        self.gpu.drawTextWithBg(self.display, s, x, y,
            fg[1], fg[2], fg[3], bg[1], bg[2], bg[3], 2,
            "Monospaced", size, style or "plain")
    end

    function be:update() self.gpu.updateDisplay(self.display) end

    function be:pollEvent()
        if self.gpu.hasEvents and self.gpu.hasEvents(self.display) then
            local evt = self.gpu.pollEvent(self.display)
            if type(evt) == "string" then
                -- Parse simple event string
                local type_, x, y = evt:match('type[%s:=]*"?(%w+)"?.*x[%s:=]*(%d+).*y[%s:=]*(%d+)')
                if type_ then return {type=type_, x=tonumber(x), y=tonumber(y)} end
            elseif type(evt) == "table" then
                return evt
            end
        end
        return nil
    end

    return be
end

-- ============================================================
-- Monitor backend (standard CC:T drawing on advanced monitor)
-- ============================================================
function M.monBackend(mon)
    local be = {mode="mon", mon=mon}

    function be:size() return self.mon.getSize() end

    local function findColor(color)
        -- Map RGB tuple to nearest CC color by name lookup
        for name, rgb in pairs(M.COLORS) do
            if rgb[1] == color[1] and rgb[2] == color[2] and rgb[3] == color[3] then
                return CC_COLOR_MAP[name] or colors.yellow
            end
        end
        return colors.yellow
    end

    function be:clear(color)
        self.mon.setBackgroundColor(findColor(color or M.COLORS.bg))
        self.mon.clear()
    end

    function be:fillRect(x, y, w, h, color)
        -- In monitor mode, x/y/w/h are character cells, not pixels
        self.mon.setBackgroundColor(findColor(color))
        for i = 0, h - 1 do
            self.mon.setCursorPos(x, y + i)
            self.mon.write(string.rep(" ", w))
        end
    end

    function be:drawRect(x, y, w, h, color)
        local c = findColor(color)
        self.mon.setTextColor(c)
        self.mon.setBackgroundColor(CC_COLOR_MAP.bg)
        self.mon.setCursorPos(x, y); self.mon.write("+"..string.rep("-", w-2).."+")
        self.mon.setCursorPos(x, y+h-1); self.mon.write("+"..string.rep("-", w-2).."+")
        for i = 1, h - 2 do
            self.mon.setCursorPos(x, y+i); self.mon.write("|")
            self.mon.setCursorPos(x+w-1, y+i); self.mon.write("|")
        end
    end

    function be:roundedRect(x, y, w, h, _, color, filled)
        if filled then return be:fillRect(x, y, w, h, color) end
        return be:drawRect(x, y, w, h, color)
    end

    function be:line(x1, y1, x2, y2, color)
        local c = findColor(color)
        self.mon.setTextColor(c)
        self.mon.setBackgroundColor(CC_COLOR_MAP.bg)
        -- Horizontal / vertical only
        if y1 == y2 then
            self.mon.setCursorPos(math.min(x1,x2), y1)
            self.mon.write(string.rep("-", math.abs(x2-x1)+1))
        elseif x1 == x2 then
            for y = math.min(y1,y2), math.max(y1,y2) do
                self.mon.setCursorPos(x1, y); self.mon.write("|")
            end
        end
    end

    function be:circle(cx, cy, r, color, filled)
        -- No circles on char-cell monitors; approximate as a small box
        be:drawRect(cx - r, cy - r/2, r*2+1, r+1, color)
    end

    function be:text(x, y, s, fg, _, _)
        self.mon.setTextColor(findColor(fg or M.COLORS.fg))
        self.mon.setBackgroundColor(CC_COLOR_MAP.bg)
        self.mon.setCursorPos(x, y)
        self.mon.write(s)
    end

    function be:textBg(x, y, s, fg, bg, _, _)
        self.mon.setTextColor(findColor(fg or M.COLORS.fg))
        self.mon.setBackgroundColor(findColor(bg or M.COLORS.bg))
        self.mon.setCursorPos(x, y)
        self.mon.write(s)
    end

    function be:update() end  -- no-op, monitors update immediately

    function be:pollEvent()
        return nil  -- monitor touches come via os.pullEvent("monitor_touch")
    end

    return be
end

-- ============================================================
-- Terminal backend (fallback when no monitor / GPU exists)
-- ============================================================
function M.termBackend(t)
    -- Same methods as monBackend but targeting the computer screen itself
    local be = {mode="term", t=t}

    function be:size() return self.t.getSize() end

    local function findColor(color)
        for name, rgb in pairs(M.COLORS) do
            if rgb[1] == color[1] and rgb[2] == color[2] and rgb[3] == color[3] then
                return CC_COLOR_MAP[name] or colors.yellow
            end
        end
        return colors.yellow
    end

    function be:clear(color)
        self.t.setBackgroundColor(findColor(color or M.COLORS.bg))
        self.t.clear()
    end
    function be:fillRect(x, y, w, h, color)
        self.t.setBackgroundColor(findColor(color))
        for i = 0, h - 1 do
            self.t.setCursorPos(x, y + i); self.t.write(string.rep(" ", w))
        end
    end
    function be:drawRect(x, y, w, h, color)
        self.t.setTextColor(findColor(color))
        self.t.setBackgroundColor(CC_COLOR_MAP.bg)
        self.t.setCursorPos(x, y); self.t.write("+"..string.rep("-", w-2).."+")
        self.t.setCursorPos(x, y+h-1); self.t.write("+"..string.rep("-", w-2).."+")
        for i = 1, h - 2 do
            self.t.setCursorPos(x, y+i); self.t.write("|")
            self.t.setCursorPos(x+w-1, y+i); self.t.write("|")
        end
    end
    function be:roundedRect(x, y, w, h, _, color, filled)
        if filled then return be:fillRect(x, y, w, h, color) end
        return be:drawRect(x, y, w, h, color)
    end
    function be:line(x1, y1, x2, y2, color)
        local c = findColor(color)
        self.t.setTextColor(c); self.t.setBackgroundColor(CC_COLOR_MAP.bg)
        if y1 == y2 then
            self.t.setCursorPos(math.min(x1,x2), y1); self.t.write(string.rep("-", math.abs(x2-x1)+1))
        elseif x1 == x2 then
            for y = math.min(y1,y2), math.max(y1,y2) do
                self.t.setCursorPos(x1, y); self.t.write("|")
            end
        end
    end
    function be:circle(cx, cy, r, color, filled)
        be:drawRect(cx - r, cy - r/2, r*2+1, r+1, color)
    end
    function be:text(x, y, s, fg, _, _)
        self.t.setTextColor(findColor(fg or M.COLORS.fg))
        self.t.setBackgroundColor(CC_COLOR_MAP.bg)
        self.t.setCursorPos(x, y); self.t.write(s)
    end
    function be:textBg(x, y, s, fg, bg, _, _)
        self.t.setTextColor(findColor(fg or M.COLORS.fg))
        self.t.setBackgroundColor(findColor(bg or M.COLORS.bg))
        self.t.setCursorPos(x, y); self.t.write(s)
    end
    function be:update() end
    function be:pollEvent() return nil end

    return be
end

-- ============================================================
-- Widgets — work on any backend
-- ============================================================

--- Titled panel. Yellow header bar, colored body outline, content area.
-- @param be backend
-- @param x, y, w, h  bounds (pixels for GPU, cells for mon/term)
-- @param title  header text
-- @param state  "ok"|"warn"|"err"|"normal"  (affects border color)
function M.panel(be, x, y, w, h, title, state)
    local borderColor = M.COLORS.border
    if state == "ok" then borderColor = M.COLORS.ok
    elseif state == "warn" then borderColor = M.COLORS.warn
    elseif state == "err" then borderColor = M.COLORS.err
    end

    local hdrH = be.mode == "gpu" and 18 or 1

    if be.mode == "gpu" then
        -- Panel body
        be:fillRect(x, y, w, h, M.COLORS.panelBg)
        be:roundedRect(x, y, w, h, 3, borderColor, false)
        -- Header bar
        be:fillRect(x, y, w, hdrH, M.COLORS.panelHdr)
        be:text(x + 4, y + 3, title, M.COLORS.panelHdrFg, 10, "bold")
    else
        -- Char-cell mode
        be:drawRect(x, y, w, h, borderColor)
        -- Header row (row 1 of panel) as filled yellow bar
        be:fillRect(x + 1, y, w - 2, 1, M.COLORS.panelHdr)
        be:textBg(x + 2, y, title:sub(1, w - 4), M.COLORS.panelHdrFg, M.COLORS.panelHdr)
    end

    return {x=x, y=y, w=w, h=h, contentY = y + hdrH + (be.mode == "gpu" and 2 or 1),
            contentH = h - hdrH - (be.mode == "gpu" and 4 or 2)}
end

--- Status label: "LABEL: VALUE" on a line, value colored by state.
function M.statusLine(be, x, y, label, value, state, size)
    local valColor = M.COLORS.fg
    if state == "ok" then valColor = M.COLORS.ok
    elseif state == "warn" then valColor = M.COLORS.warn
    elseif state == "err" then valColor = M.COLORS.err
    elseif state == "info" then valColor = M.COLORS.accent2
    end
    be:text(x, y, label, M.COLORS.dim, size, "plain")
    local offset = be.mode == "gpu" and (#label * (size or 10) * 0.6 + 8) or (#label + 2)
    be:text(x + offset, y, value, valColor, size, "bold")
end

--- Horizontal progress bar.
-- @param percent  0..1
-- @param state  colors the filled portion
function M.bar(be, x, y, w, h, percent, state)
    percent = math.max(0, math.min(1, percent))
    local fillColor = M.COLORS.ok
    if state == "warn" then fillColor = M.COLORS.warn
    elseif state == "err" then fillColor = M.COLORS.err
    elseif state == "info" then fillColor = M.COLORS.accent2
    end
    be:fillRect(x, y, w, h, M.COLORS.panelBg)
    if be.mode == "gpu" then
        be:drawRect(x, y, w, h, M.COLORS.dim)
        if percent > 0 then
            be:fillRect(x + 2, y + 2, math.max(1, math.floor((w - 4) * percent)), h - 4, fillColor)
        end
    else
        local fw = math.max(0, math.floor(w * percent))
        if fw > 0 then be:fillRect(x, y, fw, h, fillColor) end
        if fw < w then be:fillRect(x + fw, y, w - fw, h, M.COLORS.dim) end
    end
end

--- LED indicator: a small filled circle (or square) colored by state.
function M.led(be, x, y, label, state)
    local color = ({ok=M.COLORS.ok, warn=M.COLORS.warn, err=M.COLORS.err, off=M.COLORS.dim})[state] or M.COLORS.dim
    if be.mode == "gpu" then
        be:circle(x + 6, y + 6, 4, color, true)
        if label then be:text(x + 16, y + 2, label, M.COLORS.fg, 10, "plain") end
    else
        be:textBg(x, y, " ", M.COLORS.bg, color)
        if label then be:text(x + 2, y, label, M.COLORS.fg) end
    end
end

--- Scrolling list of entries (strings). Truncates to fit.
function M.logList(be, x, y, w, h, entries)
    if be.mode == "gpu" then
        local rowH = 12
        local rows = math.floor(h / rowH)
        for i = 1, math.min(rows, #entries) do
            local e = entries[#entries - i + 1]  -- newest first
            if not e then break end
            local color = M.COLORS.fg
            if type(e) == "table" then
                color = ({security=M.COLORS.err, access=M.COLORS.warn, admin=M.COLORS.ok,
                          facility=M.COLORS.accent2, docs=M.COLORS.fg, error=M.COLORS.err})[e.category] or M.COLORS.fg
            end
            local text = (type(e) == "table" and (e.message or tostring(e))) or tostring(e)
            be:text(x + 2, y + (i - 1) * rowH, text:sub(1, math.floor(w / 6)), color, 10, "plain")
        end
    else
        local rows = h
        for i = 1, math.min(rows, #entries) do
            local e = entries[#entries - i + 1]
            if not e then break end
            local color = M.COLORS.fg
            if type(e) == "table" then
                color = ({security=M.COLORS.err, access=M.COLORS.warn, admin=M.COLORS.ok,
                          facility=M.COLORS.accent2, docs=M.COLORS.fg, error=M.COLORS.err})[e.category] or M.COLORS.fg
            end
            local text = (type(e) == "table" and (e.message or tostring(e))) or tostring(e)
            be:text(x, y + i - 1, text:sub(1, w), color)
        end
    end
end

--- Big centered banner across the top for major state (LOCKDOWN/BREACH).
function M.bigBanner(be, text, state)
    local w, _ = be:size()
    local color = M.COLORS.err
    if state == "warn" then color = M.COLORS.warn
    elseif state == "ok" then color = M.COLORS.ok
    end
    if be.mode == "gpu" then
        be:fillRect(0, 0, w, 30, color)
        be:text(math.floor(w/2 - #text * 5), 8, text, M.COLORS.bg, 20, "bold")
    else
        be:fillRect(1, 1, w, 1, color)
        be:textBg(math.max(1, math.floor((w - #text)/2)+1), 1, text, M.COLORS.bg, color)
    end
end

--- Header strip across the top.
function M.header(be, title, subtitle)
    local w, _ = be:size()
    if be.mode == "gpu" then
        be:fillRect(0, 0, w, 24, M.COLORS.fg)
        be:text(8, 4, title, M.COLORS.bg, 16, "bold")
        if subtitle then
            be:fillRect(0, 24, w, 12, M.COLORS.panelBg)
            be:text(8, 26, subtitle, M.COLORS.fg, 10, "plain")
        end
    else
        be:fillRect(1, 1, w, 1, M.COLORS.fg)
        be:textBg(math.max(1, math.floor((w - #title)/2)+1), 1, title, M.COLORS.bg, M.COLORS.fg)
        if subtitle then
            be:text(math.max(1, math.floor((w - #subtitle)/2)+1), 2, subtitle, M.COLORS.fg)
        end
    end
end

return M

-- terminals/widget.lua
-- CTN Widget Terminal - drives a small monitor (1x1 or 1x2) showing ONE
-- kind of panel. Place these around the facility for at-a-glance info.
--
-- Widget types (configurable in wizard):
--   breaches     - active breach list
--   zones        - zone lockdown status
--   entities     - entity roster
--   log          - scrolling audit log
--   personnel    - personnel count per zone
--   clock        - big time display + facility state
--   state        - big facility state indicator only
--
-- Peripherals:
--   - wireless modem
--   - advanced monitor (any size, but small works great)
--   - optional: DirectGPU block for fancy rendering

package.path = package.path .. ";/lib/?.lua"
local proto = require("ctnproto")
local ui    = require("ctnui")
local cfg   = require("ctnconfig")
local gpu   = require("ctngpu")

local myCfg = cfg.loadOrWizard("widget", {
    {key="mainframe_id", prompt="Mainframe computer ID", type="number", default=1},
    {key="widget_type", prompt="Which widget to display",
     type="pick", options={"breaches","zones","entities","log","fulllog","personnel","clock","state"},
     default="state"},
})

proto.openModem()
ui.bootIdentity()
local MAINFRAME = myCfg.mainframe_id
local WIDGET    = myCfg.widget_type

-- Try GPU first, then monitor, then terminal
local backend
local function getBackend()
    if backend then return backend end
    backend = gpu.openBackend({preferGpu=true})
    return backend
end

local function getZones()
    local z = {}
    for name in pairs(status.zones or {}) do z[#z+1] = name end
    table.sort(z)
    if #z == 0 then z = {"(no zones)"} end
    return z
end

-- Status cache
local status = {
    facility = {state="normal"},
    zones = {}, breaches = {}, entities = {}, recentLog = {}, lastUpdate = 0,
}

local function refresh()
    local reply = proto.request(MAINFRAME, "status_request", {}, 2)
    if reply and reply.ok then
        status.facility = reply.facility or status.facility
        status.zones    = reply.zones or {}
        status.breaches = reply.breaches or {}
        status.recentLog = reply.recentLog or {}
        status.lastUpdate = os.epoch("utc")
    end
end

local function flashing()
    return math.floor(os.epoch("utc") / 500) % 2 == 0
end

-- ============================================================
-- Widget renderers
-- ============================================================

local function drawState(be)
    local w, h = be:size()
    local st = status.facility.state or "normal"
    local breaching = st == "breach" or st == "lockdown"

    local bg = breaching and (flashing() and {60,0,0} or gpu.COLORS.bg) or gpu.COLORS.bg
    be:clear(bg)

    local col = ({normal=gpu.COLORS.ok, warning=gpu.COLORS.warn, caution=gpu.COLORS.warn,
                  lockdown=gpu.COLORS.err, breach=gpu.COLORS.err})[st] or gpu.COLORS.fg

    if be.mode == "gpu" then
        be:fillRect(0, 0, w, 32, gpu.COLORS.fg)
        be:text(16, 8, "FACILITY STATE", gpu.COLORS.bg, 14, "bold")

        -- Big centered state
        local text = string.upper(st)
        local tx = math.floor(w/2 - #text * 10)
        be:text(tx, math.floor(h/2) - 20, text, col, 40, "bold")

        be:text(16, h - 20, "Breaches: "..#status.breaches, gpu.COLORS.dim, 12, "plain")
    else
        be:fillRect(1, 1, w, 1, gpu.COLORS.fg)
        local title = "FACILITY STATE"
        be:textBg(math.max(1, math.floor((w-#title)/2)+1), 1, title, gpu.COLORS.bg, gpu.COLORS.fg)

        local big = string.upper(st)
        be:text(math.max(1, math.floor((w-#big)/2)+1), math.floor(h/2), big, col)

        be:text(2, h, "Breaches: "..#status.breaches, gpu.COLORS.dim)
    end
    be:update()
end

local function drawBreaches(be)
    local w, h = be:size()
    be:clear(gpu.COLORS.bg)

    if be.mode == "gpu" then
        local p = gpu.panel(be, 4, 4, w-8, h-8, "ACTIVE BREACHES",
            #status.breaches > 0 and "err" or "ok")
        if #status.breaches == 0 then
            be:text(p.x + 12, p.contentY + 10, "ALL CONTAINED", gpu.COLORS.ok, 24, "bold")
            be:text(p.x + 12, p.contentY + 42, "No active breaches.", gpu.COLORS.dim, 11, "plain")
        else
            local y = p.contentY + 4
            for _, b in ipairs(status.breaches) do
                if y > p.y + p.h - 16 then break end
                gpu.led(be, p.x + 10, y, nil, "err")
                local col = flashing() and gpu.COLORS.err or gpu.COLORS.warn
                be:text(p.x + 32, y + 2, b.scpId, col, 16, "bold")
                be:text(p.x + 140, y + 2, "@ "..b.zone, gpu.COLORS.warn, 12, "plain")
                y = y + 22
            end
        end
    else
        local p = gpu.panel(be, 1, 1, w, h, "BREACHES", #status.breaches > 0 and "err" or "ok")
        if #status.breaches == 0 then
            be:text(p.x + 2, p.contentY, "All contained", gpu.COLORS.ok)
        else
            local y = p.contentY
            for _, b in ipairs(status.breaches) do
                if y > p.y + p.h - 2 then break end
                be:text(p.x + 2, y, b.scpId.." @ "..b.zone, gpu.COLORS.err)
                y = y + 1
            end
        end
    end
    be:update()
end

local function drawZones(be)
    local w, h = be:size()
    be:clear(gpu.COLORS.bg)
    if be.mode == "gpu" then
        local p = gpu.panel(be, 4, 4, w-8, h-8, "ZONE STATUS", "normal")
        local y = p.contentY + 4
        for _, zn in ipairs(getZones()) do
            if y > p.y + p.h - 16 then break end
            local z = status.zones[zn] or {}
            local st = z.lockdown and "err" or "ok"
            gpu.led(be, p.x + 10, y, nil, st)
            be:text(p.x + 32, y + 2, zn, gpu.COLORS.fg, 12, "bold")
            local col = z.lockdown and gpu.COLORS.err or gpu.COLORS.ok
            be:text(p.x + 130, y + 2, z.lockdown and "LOCKED" or "open", col, 11, "plain")
            local occ = z.occupants and #z.occupants or 0
            be:text(p.x + 210, y + 2, occ.." ppl", gpu.COLORS.dim, 10, "plain")
            y = y + 20
        end
    else
        local p = gpu.panel(be, 1, 1, w, h, "ZONES", "normal")
        local y = p.contentY
        for _, zn in ipairs(getZones()) do
            if y > p.y + p.h - 2 then break end
            local z = status.zones[zn] or {}
            local col = z.lockdown and gpu.COLORS.err or gpu.COLORS.ok
            be:textBg(p.x + 2, y, " ", gpu.COLORS.bg, col)
            be:text(p.x + 4, y, zn, gpu.COLORS.fg)
            be:text(p.x + 14, y, z.lockdown and "LOCK" or "open", col)
            y = y + 1
        end
    end
    be:update()
end

local function drawLog(be)
    local w, h = be:size()
    be:clear(gpu.COLORS.bg)
    if be.mode == "gpu" then
        local p = gpu.panel(be, 4, 4, w-8, h-8, "AUDIT LOG / LIVE", "normal")
        gpu.logList(be, p.x + 4, p.contentY + 2, p.w - 8, p.h - 20, status.recentLog)
    else
        local p = gpu.panel(be, 1, 1, w, h, "LOG", "normal")
        gpu.logList(be, p.x + 1, p.contentY, p.w - 2, p.h - 2, status.recentLog)
    end
    be:update()
end

local function drawClock(be)
    local w, h = be:size()
    local st = status.facility.state or "normal"
    local breaching = st == "breach" or st == "lockdown"
    local bg = breaching and (flashing() and {60,0,0} or gpu.COLORS.bg) or gpu.COLORS.bg
    be:clear(bg)

    if be.mode == "gpu" then
        be:fillRect(0, 0, w, 28, gpu.COLORS.fg)
        be:text(16, 6, "C.T.N CLOCK", gpu.COLORS.bg, 14, "bold")

        local timeStr = os.date("%H:%M:%S")
        be:text(math.floor(w/2 - 90), math.floor(h/2) - 30, timeStr, gpu.COLORS.fg, 40, "bold")

        local dateStr = os.date("%Y-%m-%d")
        be:text(math.floor(w/2 - #dateStr * 5), math.floor(h/2) + 20, dateStr, gpu.COLORS.dim, 14, "plain")

        local stCol = ({normal=gpu.COLORS.ok, warning=gpu.COLORS.warn, caution=gpu.COLORS.warn,
                       lockdown=gpu.COLORS.err, breach=gpu.COLORS.err})[st] or gpu.COLORS.fg
        be:text(math.floor(w/2 - #st * 4), math.floor(h/2) + 50,
            string.upper(st), stCol, 16, "bold")
    else
        be:fillRect(1, 1, w, 1, gpu.COLORS.fg)
        be:textBg(math.max(1, math.floor((w-6)/2)+1), 1, "CLOCK", gpu.COLORS.bg, gpu.COLORS.fg)
        local t = os.date("%H:%M:%S")
        be:text(math.max(1, math.floor((w-#t)/2)+1), math.floor(h/2), t, gpu.COLORS.fg)
        local d = os.date("%Y-%m-%d")
        be:text(math.max(1, math.floor((w-#d)/2)+1), math.floor(h/2)+1, d, gpu.COLORS.dim)
        local stCol = ({normal=gpu.COLORS.ok, warning=gpu.COLORS.warn,
                       lockdown=gpu.COLORS.err, breach=gpu.COLORS.err})[st] or gpu.COLORS.fg
        be:text(math.max(1, math.floor((w-#st)/2)+1), h-1, string.upper(st), stCol)
    end
    be:update()
end

local function drawPersonnel(be)
    local w, h = be:size()
    be:clear(gpu.COLORS.bg)
    if be.mode == "gpu" then
        local p = gpu.panel(be, 4, 4, w-8, h-8, "PERSONNEL / ZONE", "normal")
        local y = p.contentY + 4
        local total = 0
        for _, zn in ipairs(getZones()) do
            if y > p.y + p.h - 30 then break end
            local z = status.zones[zn] or {}
            local occ = z.occupants and #z.occupants or 0
            total = total + occ
            be:text(p.x + 10, y, zn, gpu.COLORS.dim, 12, "plain")
            gpu.bar(be, p.x + 90, y + 4, p.w - 140, 10, math.min(1, occ/10),
                occ > 5 and "warn" or "ok")
            be:text(p.x + p.w - 30, y, tostring(occ), gpu.COLORS.fg, 12, "bold")
            y = y + 18
        end
        be:text(p.x + 10, p.y + p.h - 18, "TOTAL: "..total, gpu.COLORS.accent, 14, "bold")
    else
        local p = gpu.panel(be, 1, 1, w, h, "PERSONNEL", "normal")
        local y = p.contentY
        local total = 0
        for _, zn in ipairs(getZones()) do
            if y > p.y + p.h - 3 then break end
            local z = status.zones[zn] or {}
            local occ = z.occupants and #z.occupants or 0
            total = total + occ
            be:text(p.x + 2, y, zn, gpu.COLORS.dim)
            be:text(p.x + 12, y, tostring(occ), gpu.COLORS.fg)
            y = y + 1
        end
        be:text(p.x + 2, p.y + p.h - 1, "TOTAL: "..total, gpu.COLORS.accent)
    end
    be:update()
end

local function drawEntities(be)
    local w, h = be:size()
    be:clear(gpu.COLORS.bg)
    -- fetch entities via status_request... actually status_request doesn't send entities.
    -- Best we can do is show active breaches + a count.
    if be.mode == "gpu" then
        local p = gpu.panel(be, 4, 4, w-8, h-8, "ENTITIES", "normal")
        be:text(p.x + 12, p.contentY + 8, tostring(#status.breaches).." breached",
            #status.breaches > 0 and gpu.COLORS.err or gpu.COLORS.ok, 14, "bold")
        local y = p.contentY + 32
        for _, b in ipairs(status.breaches) do
            if y > p.y + p.h - 14 then break end
            be:text(p.x + 12, y, b.scpId.." @ "..b.zone, gpu.COLORS.err, 11, "plain")
            y = y + 14
        end
    else
        local p = gpu.panel(be, 1, 1, w, h, "ENTITIES", "normal")
        be:text(p.x + 2, p.contentY,
            #status.breaches.." breached",
            #status.breaches > 0 and gpu.COLORS.err or gpu.COLORS.ok)
        local y = p.contentY + 2
        for _, b in ipairs(status.breaches) do
            if y > p.y + p.h - 2 then break end
            be:text(p.x + 2, y, b.scpId, gpu.COLORS.err)
            y = y + 1
        end
    end
    be:update()
end

-- Full detailed log: every entry with computer ID, terminal name, zone, category
local fullLogCache = {}
local fullLogLastFetch = 0

local function drawFullLog(be)
    local w, h = be:size()
    be:clear(gpu.COLORS.bg)

    -- Fetch full log every 3 seconds
    if os.epoch("utc") - fullLogLastFetch > 3000 then
        local reply = proto.request(MAINFRAME, "full_log_request", {count=200}, 3)
        if reply and reply.ok and reply.entries then
            fullLogCache = reply.entries
        end
        fullLogLastFetch = os.epoch("utc")
    end

    if be.mode == "gpu" then
        local p = gpu.panel(be, 4, 4, w-8, h-8, "FULL SECURITY LOG", "normal")
        local y = p.contentY + 2
        local rowH = 11
        local maxRows = math.floor((p.h - 10) / rowH)
        local start = math.max(1, #fullLogCache - maxRows + 1)
        for i = start, #fullLogCache do
            if y > p.y + p.h - 10 then break end
            local e = fullLogCache[i]
            if e then
                local ts = os.date("%H:%M:%S", (e.ts or 0) / 1000)
                local catCol = ({
                    security=gpu.COLORS.err, access=gpu.COLORS.warn,
                    admin=gpu.COLORS.ok, facility=gpu.COLORS.accent2,
                    mail=gpu.COLORS.accent, radio=gpu.COLORS.accent,
                    docs=gpu.COLORS.fg, error=gpu.COLORS.err,
                })[e.category] or gpu.COLORS.fg

                -- Time
                be:text(p.x + 4, y, ts, gpu.COLORS.dim, 9, "plain")
                -- Category
                be:text(p.x + 64, y, ("["..((e.category or "?"):upper()).."]"):sub(1,12), catCol, 9, "bold")
                -- Computer ID + terminal
                local src = ""
                if e.meta then
                    if e.meta.from then src = "#"..tostring(e.meta.from) end
                    if e.meta.terminal_name then src = src.." "..e.meta.terminal_name end
                    if e.meta.zone then src = src.." @"..e.meta.zone end
                end
                if src ~= "" then
                    be:text(p.x + 140, y, src:sub(1, 25), gpu.COLORS.dim, 8, "plain")
                end
                -- Message
                local msg = (e.message or ""):sub(1, math.floor((p.w - 320) / 5))
                be:text(p.x + 310, y, msg, gpu.COLORS.fg, 9, "plain")

                y = y + rowH
            end
        end
    else
        local p = gpu.panel(be, 1, 1, w, h, "FULL LOG", "normal")
        local y = p.contentY
        local maxRows = p.h - 3
        local start = math.max(1, #fullLogCache - maxRows + 1)
        for i = start, #fullLogCache do
            if y > p.y + p.h - 2 then break end
            local e = fullLogCache[i]
            if e then
                local ts = os.date("%H:%M", (e.ts or 0) / 1000)
                local catCol = ({
                    security=gpu.COLORS.err, access=gpu.COLORS.warn,
                    admin=gpu.COLORS.ok, facility=gpu.COLORS.accent2,
                    mail=gpu.COLORS.accent, docs=gpu.COLORS.fg, error=gpu.COLORS.err,
                })[e.category] or gpu.COLORS.fg

                -- Compact: time cat #ID message
                local src = ""
                if e.meta and e.meta.from then src = "#"..tostring(e.meta.from) end
                if e.meta and e.meta.terminal_name then
                    src = src.." "..tostring(e.meta.terminal_name):sub(1,8)
                end
                local cat = (e.category or "?"):sub(1,4):upper()
                local msg = (e.message or ""):sub(1, w - #ts - #cat - #src - 8)
                be:text(p.x + 1, y, ts, gpu.COLORS.dim)
                be:text(p.x + 7, y, cat, catCol)
                be:text(p.x + 12, y, src, gpu.COLORS.dim)
                be:text(p.x + 12 + #src + 1, y, msg, gpu.COLORS.fg)
                y = y + 1
            end
        end
    end
    be:update()
end

local RENDERERS = {
    state = drawState,
    breaches = drawBreaches,
    zones = drawZones,
    log = drawLog,
    fulllog = drawFullLog,
    clock = drawClock,
    personnel = drawPersonnel,
    entities = drawEntities,
}

local function announce()
    local _aReply = proto.request(MAINFRAME, "announce", {
        type = "widget",
        hostname = os.getComputerLabel() or ("widget-"..WIDGET),
    }, 2)
    ui.syncIdentity(_aReply)
end

-- ============================================================
-- Local status screen (what the computer itself shows - not the monitor)
-- ============================================================
local function drawLocal()
    ui.clear(term.current())
    ui.header(term.current(), "WIDGET: "..WIDGET:upper())
    term.setCursorPos(2, 5); term.setTextColor(ui.FG); write("Mainframe: ")
    term.setTextColor(ui.ACCENT); write("#"..MAINFRAME)
    term.setCursorPos(2, 6); term.setTextColor(ui.FG); write("Type:      ")
    term.setTextColor(ui.ACCENT); write(WIDGET)
    term.setCursorPos(2, 7); term.setTextColor(ui.FG); write("Backend:   ")
    local be = getBackend()
    term.setTextColor(ui.ACCENT); write(be and be.mode or "none")
    local age = (os.epoch("utc") - status.lastUpdate) / 1000
    local link = age < 5 and "LIVE" or "STALE"
    term.setCursorPos(2, 9); term.setTextColor(ui.DIM); write("Status: ")
    term.setTextColor(age < 5 and ui.OK or ui.WARN); write(link)
    ui.footer(term.current(), "WIDGET #"..os.getComputerID())
end

-- ============================================================
-- Main loop
-- ============================================================
announce()

while true do
    pcall(refresh)
    local be = getBackend()
    if be then
        local render = RENDERERS[WIDGET] or drawState
        pcall(render, be)
    end
    drawLocal()
    sleep(0.5)
end

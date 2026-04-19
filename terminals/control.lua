-- terminals/control.lua
-- C.T.N CONTROL ROOM TERMINAL
--
-- Two-surface design:
--   1. Monitor (any size, ideally 8x4): packed dashboard with 10+ panels
--      showing zones, entities, breaches, personnel, activity, stats,
--      network health, alarms, timers, clock. Uses DirectGPU if present.
--   2. Computer screen: fully clickable operator console.
--
-- Peripherals:
--   - wireless modem (required)
--   - advanced monitor (recommended; 8x4 for the full experience)
--   - DirectGPU block (optional; upgrades the dashboard visuals)

package.path = package.path .. ";/lib/?.lua"
local proto  = require("ctnproto")
local ui     = require("ctnui")
local cfg    = require("ctnconfig")
local gpu    = require("ctngpu")

local myCfg = cfg.loadOrWizard("control", {
    {key="mainframeId", prompt="Mainframe computer ID", type="number", default=1},
})

proto.openModem()
ui.bootIdentity()

local function getZones()
    local z = {}
    for name in pairs(status.zones or {}) do z[#z+1] = name end
    table.sort(z)
    if #z == 0 then z = {"(no zones)"} end
    return z
end

-- Session state
local session = {loggedIn=false, username=nil, passcode=nil}

-- Status cache
local status = {
    facility = {state="normal"},
    zones    = {},
    breaches = {},
    recentLog = {},
    entities = {},
    personnel = {},
    stats     = {scans=0, grants=0, denies=0, breaches_total=0},
    lastUpdate = 0,
    networkHealth = {pendingCount = 0, lastMessage = 0},
}

-- Flashing state for animated elements
local flashState = {phase = 0, lastTick = 0}

-- ============================================================
-- Backend (GPU or monitor)
-- ============================================================
local backend
local function getBackend()
    if backend then return backend end
    backend = gpu.openBackend({preferGpu=true})
    return backend
end

-- ============================================================
-- Network helpers
-- ============================================================
local function sendCmd(action, args)
    if not session.passcode then return nil end
    return proto.request(myCfg.mainframeId, "facility_command", {
        passcode = session.passcode,
        issuedBy = session.username,
        action = action,
        args = args or {},
    }, 4)
end

local function refreshStatus()
    local reply = proto.request(myCfg.mainframeId, "status_request", {}, 2)
    if reply and reply.ok then
        status.facility = reply.facility or status.facility
        status.zones    = reply.zones or {}
        status.breaches = reply.breaches or {}
        status.recentLog = reply.recentLog or {}
        status.lastUpdate = os.epoch("utc")
        ui.syncIdentity(reply)
    end
    -- Also pull entity list (read-only via facility_command)
    if session.passcode then
        local er = sendCmd("list_entities", {})
        if er and er.ok then status.entities = er.entities or {} end
    end
end

-- ============================================================
-- DASHBOARD (monitor / GPU)
-- ============================================================

local function flashing()
    return math.floor(os.epoch("utc") / 500) % 2 == 0
end

local function drawDashGpu(be)
    local w, h = be:size()
    local st = status.facility.state or "normal"
    local breaching = (st == "breach" or st == "lockdown")

    -- Background: darker if in breach/lockdown, normal otherwise
    local bgCol = breaching and flashing() and {30,0,0} or gpu.COLORS.bg
    be:clear(bgCol)

    -- ===== TOP HEADER BAR =====
    local bannerColor = gpu.COLORS.fg
    if st == "breach" or st == "lockdown" then bannerColor = gpu.COLORS.err
    elseif st == "warning" or st == "caution" then bannerColor = gpu.COLORS.warn end

    be:fillRect(0, 0, w, 32, bannerColor)
    be:text(16, 8, "C.T.N // CONTAINMENT DIVISION", gpu.COLORS.bg, 20, "bold")

    local stateStr = "STATUS: " .. string.upper(st)
    be:text(w - 260, 8, stateStr, gpu.COLORS.bg, 18, "bold")

    -- Clock + session info below banner
    be:fillRect(0, 32, w, 22, gpu.COLORS.panelBg)
    be:text(16, 36, os.date("%Y-%m-%d  %H:%M:%S"), gpu.COLORS.dim, 12, "plain")
    be:text(w - 220, 36, "OPERATOR: "..(session.username or "-----"), gpu.COLORS.dim, 12, "plain")

    -- ===== GRID LAYOUT =====
    -- Divide remaining area into a 3-column x 3-row panel grid
    local topY = 58
    local pad = 6
    local usableW = w - pad * 4
    local usableH = h - topY - pad * 2 - 16
    local colW = math.floor(usableW / 3)
    local rowH = math.floor(usableH / 3)

    -- ===== PANEL 1 (top-left): ZONES =====
    local p1x = pad
    local p1y = topY
    local p1 = gpu.panel(be, p1x, p1y, colW, rowH, "ZONE STATUS", "normal")
    local zy = p1.contentY + 2
    for _, zn in ipairs(getZones()) do
        if zy > p1.y + p1.h - 14 then break end
        local z = status.zones[zn] or {}
        local locked = z.lockdown
        local st = locked and "err" or "ok"
        gpu.led(be, p1.x + 10, zy, nil, st)
        be:text(p1.x + 32, zy + 2, zn, gpu.COLORS.fg, 12, "bold")
        local stateText = locked and "LOCKED" or "open"
        local col = locked and gpu.COLORS.err or gpu.COLORS.ok
        be:text(p1.x + 120, zy + 2, stateText, col, 11, "plain")
        local occ = z.occupants and #z.occupants or 0
        be:text(p1.x + 200, zy + 2, occ.." in zone", gpu.COLORS.dim, 10, "plain")
        zy = zy + 18
    end

    -- ===== PANEL 2 (top-middle): ACTIVE BREACHES =====
    local p2x = pad * 2 + colW
    local p2 = gpu.panel(be, p2x, topY, colW, rowH, "CONTAINMENT STATUS",
        (#status.breaches > 0) and "err" or "ok")
    if #status.breaches == 0 then
        be:text(p2.x + 12, p2.contentY + 8, "ALL CONTAINED", gpu.COLORS.ok, 18, "bold")
        be:text(p2.x + 12, p2.contentY + 34, "No active breaches.", gpu.COLORS.dim, 11, "plain")
        be:text(p2.x + 12, p2.contentY + 52, #status.entities.." entities in containment", gpu.COLORS.dim, 10, "plain")
    else
        local by = p2.contentY + 4
        for _, b in ipairs(status.breaches) do
            if by > p2.y + p2.h - 14 then break end
            local flash = flashing() and gpu.COLORS.err or gpu.COLORS.warn
            gpu.led(be, p2.x + 10, by, nil, "err")
            be:text(p2.x + 32, by + 2, b.scpId, flash, 14, "bold")
            be:text(p2.x + 130, by + 2, "@ "..b.zone, gpu.COLORS.warn, 11, "plain")
            by = by + 18
        end
    end

    -- ===== PANEL 3 (top-right): FACILITY ALARM STATE =====
    local p3x = pad * 3 + colW * 2
    local p3 = gpu.panel(be, p3x, topY, colW, rowH, "ALARM SYSTEM",
        breaching and "err" or "normal")
    local alarmLabel = ({
        normal   = "NOMINAL",
        caution  = "CAUTION",
        warning  = "ALERT",
        lockdown = "LOCKDOWN",
        breach   = "BREACH",
    })[st] or "UNKNOWN"
    local alarmCol = ({
        normal   = gpu.COLORS.ok,
        caution  = gpu.COLORS.warn,
        warning  = gpu.COLORS.warn,
        lockdown = gpu.COLORS.err,
        breach   = gpu.COLORS.err,
    })[st] or gpu.COLORS.fg

    -- big state banner
    if breaching and flashing() then
        be:fillRect(p3.x + 8, p3.contentY + 4, p3.w - 16, 26, gpu.COLORS.err)
        be:text(p3.x + 20, p3.contentY + 10, alarmLabel, gpu.COLORS.bg, 16, "bold")
    else
        be:text(p3.x + 20, p3.contentY + 8, alarmLabel, alarmCol, 20, "bold")
    end
    be:text(p3.x + 12, p3.contentY + 40, "Sirens: all zones", gpu.COLORS.dim, 10, "plain")
    be:text(p3.x + 12, p3.contentY + 54, "Lights: responsive", gpu.COLORS.dim, 10, "plain")

    -- ===== PANEL 4 (mid-left): ENTITY ROSTER =====
    local p4y = topY + rowH + pad
    local p4 = gpu.panel(be, pad, p4y, colW, rowH, "ENTITY REGISTRY",
        (#status.entities == 0) and "warn" or "normal")
    if #status.entities == 0 then
        be:text(p4.x + 12, p4.contentY + 8, "No entities registered.", gpu.COLORS.dim, 11, "plain")
    else
        local ey = p4.contentY + 2
        for _, e in ipairs(status.entities) do
            if ey > p4.y + p4.h - 14 then break end
            local classCol = ({
                Safe=gpu.COLORS.ok, Euclid=gpu.COLORS.warn, Keter=gpu.COLORS.err,
                Thaumiel=gpu.COLORS.accent2, Apollyon=gpu.COLORS.purple,
            })[e.class] or gpu.COLORS.fg
            local stIcon = e.status == "breached" and "err" or
                          (e.status == "testing" or e.status == "maintenance") and "warn" or "ok"
            gpu.led(be, p4.x + 10, ey, nil, stIcon)
            be:text(p4.x + 32, ey + 2, e.entityId, gpu.COLORS.fg, 11, "bold")
            be:text(p4.x + 110, ey + 2, (e.class or ""):sub(1,4), classCol, 10, "plain")
            be:text(p4.x + 150, ey + 2, e.zone or "", gpu.COLORS.dim, 10, "plain")
            local thrBar = (e.threat or 0) / 5
            gpu.bar(be, p4.x + 195, ey + 4, 40, 6, thrBar,
                (e.threat or 0) >= 4 and "err" or ((e.threat or 0) >= 3 and "warn" or "ok"))
            ey = ey + 16
        end
    end

    -- ===== PANEL 5 (mid-middle): BIG FACILITY STATE =====
    local p5x = pad * 2 + colW
    local p5 = gpu.panel(be, p5x, p4y, colW, rowH, "FACILITY STATE", "normal")

    -- Huge status text centered
    local bigText = string.upper(st)
    local textCol = breaching and (flashing() and gpu.COLORS.err or gpu.COLORS.warn) or gpu.COLORS.ok
    be:text(p5.x + 20, p5.contentY + 16, bigText, textCol, 32, "bold")

    -- Sub-stats
    be:text(p5.x + 12, p5.contentY + 60, "Zones locked: ", gpu.COLORS.dim, 10, "plain")
    local lockCount = 0
    for _, z in pairs(status.zones) do if z.lockdown then lockCount = lockCount + 1 end end
    be:text(p5.x + 110, p5.contentY + 60, lockCount .. " / 5", gpu.COLORS.fg, 10, "bold")

    be:text(p5.x + 12, p5.contentY + 74, "Active breaches: ", gpu.COLORS.dim, 10, "plain")
    be:text(p5.x + 130, p5.contentY + 74, tostring(#status.breaches), gpu.COLORS.fg, 10, "bold")

    -- ===== PANEL 6 (mid-right): PERSONNEL BY ZONE =====
    local p6x = pad * 3 + colW * 2
    local p6 = gpu.panel(be, p6x, p4y, colW, rowH, "PERSONNEL / ZONES", "normal")
    local py = p6.contentY + 2
    local totalOcc = 0
    for _, zn in ipairs(getZones()) do
        if py > p6.y + p6.h - 14 then break end
        local z = status.zones[zn] or {}
        local occ = z.occupants and #z.occupants or 0
        totalOcc = totalOcc + occ
        be:text(p6.x + 12, py + 2, zn, gpu.COLORS.dim, 10, "plain")
        gpu.bar(be, p6.x + 90, py + 4, 100, 8, math.min(1, occ/10),
            occ == 0 and "ok" or (occ > 5 and "warn" or "ok"))
        be:text(p6.x + 200, py + 2, tostring(occ), gpu.COLORS.fg, 10, "bold")
        py = py + 16
    end
    be:text(p6.x + 12, p6.y + p6.h - 16, "TOTAL: "..totalOcc.." personnel", gpu.COLORS.accent, 11, "bold")

    -- ===== PANEL 7 (bottom, full-width): SECURITY AUDIT LOG =====
    local p7y = topY + (rowH + pad) * 2
    local p7h = usableH - (rowH + pad) * 2
    local p7 = gpu.panel(be, pad, p7y, usableW + pad * 2, p7h,
        "SECURITY AUDIT LOG // LIVE", "normal")

    local ly = p7.contentY + 2
    local maxLines = math.floor((p7.h - 20) / 12)
    local entries = status.recentLog or {}
    local startIdx = math.max(1, #entries - maxLines + 1)
    for i = startIdx, #entries do
        if ly > p7.y + p7.h - 14 then break end
        local e = entries[i]
        if e then
            local ts = os.date("%H:%M:%S", (e.ts or 0) / 1000)
            be:text(p7.x + 8, ly, ts, gpu.COLORS.dim, 10, "plain")
            local catCol = ({
                security=gpu.COLORS.err, access=gpu.COLORS.warn,
                admin=gpu.COLORS.ok, facility=gpu.COLORS.accent2,
                docs=gpu.COLORS.fg, error=gpu.COLORS.err, action=gpu.COLORS.accent,
            })[e.category] or gpu.COLORS.fg
            be:text(p7.x + 80, ly, "["..(e.category or "?"):upper().."]", catCol, 10, "bold")
            local msg = tostring(e.message or ""):sub(1, math.floor((p7.w - 200) / 6))
            be:text(p7.x + 180, ly, msg, gpu.COLORS.fg, 10, "plain")
            -- add zone/terminal meta if present
            if e.meta and e.meta.terminal_name then
                local metaStr = "<"..e.meta.terminal_name..">"
                be:text(p7.x + p7.w - 140, ly, metaStr, gpu.COLORS.dim, 9, "plain")
            end
            ly = ly + 12
        end
    end

    -- ===== BOTTOM BAR: Links =====
    local age = (os.epoch("utc") - status.lastUpdate) / 1000
    local linkText
    local linkCol
    if age < 5 then
        linkText = "MAINFRAME LINKED"
        linkCol = gpu.COLORS.ok
    else
        linkText = "LINK STALE ("..math.floor(age).."s)"
        linkCol = gpu.COLORS.warn
    end
    be:text(16, h - 14, linkText, linkCol, 11, "bold")
    be:text(w - 240, h - 14, "c.t.n control node // classified", gpu.COLORS.dim, 10, "plain")

    be:update()
end

-- Monitor fallback when GPU isn't present
local function drawDashMon(be)
    local w, h = be:size()
    local st = status.facility.state or "normal"
    be:clear(gpu.COLORS.bg)

    -- Top banner
    local bannerCol = gpu.COLORS.fg
    if st == "breach" or st == "lockdown" then bannerCol = gpu.COLORS.err
    elseif st == "warning" then bannerCol = gpu.COLORS.warn end
    be:fillRect(1, 1, w, 1, bannerCol)
    local title = "C.T.N  //  "..string.upper(st)
    be:textBg(math.max(1, math.floor((w-#title)/2)+1), 1, title, gpu.COLORS.bg, bannerCol)

    -- 3-column layout for smaller monitors
    local col1W = math.floor(w * 0.33)
    local col2W = math.floor(w * 0.33)
    local col3X = col1W + col2W + 1
    local col3W = w - col3X
    local topY = 3
    local halfH = math.floor((h - 4) / 2)

    -- Zones
    local p1 = gpu.panel(be, 1, topY, col1W, halfH, "ZONES", "normal")
    local zy = p1.contentY
    for _, zn in ipairs(getZones()) do
        if zy > p1.y + p1.h - 2 then break end
        local z = status.zones[zn] or {}
        local col = z.lockdown and gpu.COLORS.err or gpu.COLORS.ok
        be:textBg(p1.x + 2, zy, " ", gpu.COLORS.bg, col)
        be:text(p1.x + 4, zy, zn, gpu.COLORS.fg)
        be:text(p1.x + 14, zy, z.lockdown and "LOCK" or "open", col)
        local occ = z.occupants and #z.occupants or 0
        be:text(p1.x + 22, zy, "("..occ..")", gpu.COLORS.dim)
        zy = zy + 1
    end

    -- Breaches
    local p2 = gpu.panel(be, col1W + 1, topY, col2W, halfH,
        "BREACHES", (#status.breaches > 0) and "err" or "ok")
    if #status.breaches == 0 then
        be:text(p2.x + 2, p2.contentY, "All contained", gpu.COLORS.ok)
    else
        local by = p2.contentY
        for _, b in ipairs(status.breaches) do
            if by > p2.y + p2.h - 2 then break end
            be:text(p2.x + 2, by, "!! "..b.scpId.." @ "..b.zone, gpu.COLORS.err)
            by = by + 1
        end
    end

    -- Entities
    local p3 = gpu.panel(be, col3X, topY, col3W, halfH, "ENTITIES", "normal")
    local ey = p3.contentY
    for _, e in ipairs(status.entities) do
        if ey > p3.y + p3.h - 2 then break end
        local col = e.status == "breached" and gpu.COLORS.err or gpu.COLORS.ok
        be:text(p3.x + 2, ey, e.entityId, col)
        be:text(p3.x + 12, ey, (e.class or ""):sub(1,3), gpu.COLORS.dim)
        ey = ey + 1
    end

    -- Bottom: log
    local p4y = topY + halfH
    local p4 = gpu.panel(be, 1, p4y, w, h - p4y - 1, "AUDIT LOG", "normal")
    local ly = p4.contentY
    local entries = status.recentLog or {}
    local startIdx = math.max(1, #entries - (p4.h - 3))
    for i = startIdx, #entries do
        if ly > p4.y + p4.h - 2 then break end
        local e = entries[i]
        if e then
            local ts = os.date("%H:%M:%S", (e.ts or 0) / 1000)
            be:text(p4.x + 2, ly, ts, gpu.COLORS.dim)
            local col = ({security=gpu.COLORS.err, access=gpu.COLORS.warn,
                admin=gpu.COLORS.ok, facility=gpu.COLORS.accent2})[e.category] or gpu.COLORS.fg
            be:text(p4.x + 12, ly, (e.message or ""):sub(1, w - 14), col)
            ly = ly + 1
        end
    end

    be:fillRect(1, h, w, 1, gpu.COLORS.fg)
    be:textBg(2, h, "CONTROL ROOM  "..os.date("%H:%M:%S"), gpu.COLORS.bg, gpu.COLORS.fg)
end

local function drawDashboard()
    local be = getBackend()
    if not be then return end
    if be.mode == "gpu" then
        drawDashGpu(be)
    else
        drawDashMon(be)
    end
end

-- ============================================================
-- OPERATOR CONSOLE (computer screen, clickable)
-- ============================================================
local function drawLogin()
    ui.clear(term.current())
    ui.header(term.current(), "CONTROL ROOM AUTHENTICATION")
    local w, h = term.getSize()
    ui.box(term.current(), 2, 5, w - 2, 8, ui.BORDER)
    term.setCursorPos(4, 6); term.setTextColor(ui.WARN)
    print("UNAUTHORISED ACCESS IS A CLASS-3 OFFENCE")
    term.setCursorPos(4, 8); term.setTextColor(ui.FG)
    write("Username: "); term.setTextColor(ui.ACCENT)
    local username = read(); term.setTextColor(ui.FG)
    term.setCursorPos(4, 10); write("Passcode: "); term.setTextColor(ui.ACCENT)
    local passcode = read("*"); term.setTextColor(ui.FG)

    session.username = username; session.passcode = passcode
    ui.bigStatus(term.current(), {"AUTHENTICATING..."}, "working")
    local reply = sendCmd("list_entities", {})
    if not reply then
        ui.bigStatus(term.current(), {"MAINFRAME","UNREACHABLE"}, "error"); sleep(2)
    elseif reply.ok then
        session.loggedIn = true
        ui.bigStatus(term.current(), {"ACCESS GRANTED","","Welcome, "..username}, "granted"); sleep(1)
    else
        ui.bigStatus(term.current(), {"ACCESS DENIED","",(reply.reason or "?"):upper()}, "denied"); sleep(2)
    end
end

local function pickZoneButtons()
    ui.clear(term.current())
    ui.header(term.current(), "SELECT ZONE")
    local buttons = ui.buttonGrid(term.current(), ZONES, {startY=5, cols=1, btnH=2, hotkeys=true})
    local _, h = term.getSize()
    local cancel = ui.drawButton(term.current(), 2, h - 3, select(1, term.getSize()) - 2, 2,
        "CANCEL", {fg=ui.DIM, hotkey="x"})
    table.insert(buttons, cancel)
    local idx = ui.clickMenu(buttons)
    if idx and idx <= #ZONES then return ZONES[idx] end
    return nil
end

local function pickEntity()
    local r = sendCmd("list_entities", {})
    if not r or not r.ok then return nil end
    if #r.entities == 0 then
        ui.bigStatus(term.current(), {"NO ENTITIES"}, "idle"); sleep(1.5); return nil
    end
    ui.clear(term.current())
    ui.header(term.current(), "SELECT ENTITY")
    local labels = {}
    for i, e in ipairs(r.entities) do
        labels[i] = e.entityId.." "..e.class:sub(1,4).." @"..e.zone.." ["..e.status.."]"
    end
    local buttons = ui.buttonGrid(term.current(), labels, {startY=5, cols=1, btnH=2, hotkeys=true})
    local _, h = term.getSize()
    local cancel = ui.drawButton(term.current(), 2, h - 3, select(1, term.getSize()) - 2, 2,
        "CANCEL", {fg=ui.DIM, hotkey="x"})
    table.insert(buttons, cancel)
    local idx = ui.clickMenu(buttons)
    if idx and idx <= #r.entities then return r.entities[idx] end
    return nil
end

local function showReply(reply, msg)
    if not reply then
        ui.bigStatus(term.current(), {"MAINFRAME","UNREACHABLE"}, "error")
    elseif reply.ok then
        ui.bigStatus(term.current(), {msg or "OK"}, "granted")
    else
        ui.bigStatus(term.current(), {"FAILED","",(reply.reason or "?"):upper()}, "denied")
    end
    sleep(1.5)
end

-- ============================================================
-- Actions
-- ============================================================
local actions = {}

actions.zoneLockdown = function()
    local z = pickZoneButtons(); if not z then return end
    showReply(sendCmd("zone_lockdown", {zone=z, issuedBy=session.username}),
        "LOCKDOWN: "..z)
end

actions.zoneUnlock = function()
    local z = pickZoneButtons(); if not z then return end
    showReply(sendCmd("zone_unlock", {zone=z, issuedBy=session.username}),
        "UNLOCKED: "..z)
end

actions.declareBreach = function()
    local e = pickEntity(); if not e then return end
    showReply(sendCmd("declare_breach", {scpId=e.entityId, zone=e.zone, issuedBy=session.username}),
        "BREACH: "..e.entityId)
end

actions.endBreach = function()
    if #status.breaches == 0 then
        ui.bigStatus(term.current(), {"NO ACTIVE","BREACHES"}, "idle"); sleep(1.5); return
    end
    ui.clear(term.current())
    ui.header(term.current(), "END WHICH BREACH")
    local labels = {}
    for i, b in ipairs(status.breaches) do labels[i] = b.scpId.." @ "..b.zone end
    local buttons = ui.buttonGrid(term.current(), labels, {startY=5, cols=1, btnH=2, hotkeys=true})
    local _, h = term.getSize()
    local cancel = ui.drawButton(term.current(), 2, h - 3, select(1, term.getSize()) - 2, 2,
        "CANCEL", {fg=ui.DIM, hotkey="x"})
    table.insert(buttons, cancel)
    local idx = ui.clickMenu(buttons)
    if idx and idx <= #status.breaches then
        local b = status.breaches[idx]
        showReply(sendCmd("end_breach", {scpId=b.scpId, issuedBy=session.username}),
            "CONTAINED: "..b.scpId)
    end
end

actions.facilityState = function()
    local states = {"normal","caution","warning","lockdown"}
    ui.clear(term.current())
    ui.header(term.current(), "SET FACILITY STATE")
    local buttons = ui.buttonGrid(term.current(), states, {startY=5, cols=1, btnH=2, hotkeys=true})
    local _, h = term.getSize()
    local cancel = ui.drawButton(term.current(), 2, h - 3, select(1, term.getSize()) - 2, 2,
        "CANCEL", {fg=ui.DIM, hotkey="x"})
    table.insert(buttons, cancel)
    local idx = ui.clickMenu(buttons)
    if idx and idx <= #states then
        showReply(sendCmd("set_state", {state=states[idx], issuedBy=session.username}),
            "STATE: "..states[idx]:upper())
    end
end

actions.setEntityStatus = function()
    local e = pickEntity(); if not e then return end
    local statuses = {"contained","testing","maintenance","decommissioned","deceased"}
    ui.clear(term.current())
    ui.header(term.current(), "STATUS FOR "..e.entityId)
    local buttons = ui.buttonGrid(term.current(), statuses, {startY=5, cols=1, btnH=2, hotkeys=true})
    local _, h = term.getSize()
    local cancel = ui.drawButton(term.current(), 2, h - 3, select(1, term.getSize()) - 2, 2,
        "CANCEL", {fg=ui.DIM, hotkey="x"})
    table.insert(buttons, cancel)
    local idx = ui.clickMenu(buttons)
    if idx and idx <= #statuses then
        showReply(sendCmd("set_entity_status",
            {entityId=e.entityId, status=statuses[idx], issuedBy=session.username}),
            e.entityId.." -> "..statuses[idx]:upper())
    end
end

actions.viewStatus = function()
    refreshStatus()
    ui.clear(term.current())
    ui.header(term.current(), "FACILITY SNAPSHOT")
    local w, h = term.getSize()

    local y = 4
    term.setCursorPos(2, y); term.setTextColor(ui.FG); term.write("Facility: ")
    local st = status.facility.state or "normal"
    local col = ({normal=ui.OK, warning=ui.WARN, breach=ui.ERR, lockdown=ui.ERR})[st] or ui.FG
    term.setTextColor(col); term.write(st:upper()); y = y + 2

    term.setCursorPos(2, y); term.setTextColor(ui.ACCENT); term.write("ZONES:"); y = y + 1
    for _, zn in ipairs(getZones()) do
        local z = status.zones[zn] or {}
        term.setCursorPos(4, y); term.setTextColor(ui.FG); term.write(string.format("%-10s ", zn))
        if z.lockdown then term.setTextColor(ui.ERR); term.write("LOCKED ")
        else term.setTextColor(ui.OK); term.write("normal ") end
        local occ = z.occupants and #z.occupants or 0
        term.setTextColor(ui.DIM); term.write(occ.." personnel")
        y = y + 1
    end
    y = y + 1

    term.setCursorPos(2, y); term.setTextColor(ui.ACCENT); term.write("BREACHES: "..#status.breaches)
    y = y + 1
    for _, b in ipairs(status.breaches) do
        if y >= h - 3 then break end
        term.setCursorPos(4, y); term.setTextColor(ui.ERR)
        term.write(b.scpId.." @ "..b.zone)
        y = y + 1
    end

    local btn = ui.drawButton(term.current(), 2, h - 3, w - 2, 2, "BACK", {hotkey="enter"})
    ui.clickMenu({btn})
end

actions.logout = function()
    session.loggedIn = false; session.username = nil; session.passcode = nil
end

-- ============================================================
-- Main console loop (clickable menu)
-- ============================================================
local function consoleLoop()
    while not session.loggedIn do drawLogin() end

    local options = {
        {"Zone Lockdown",      actions.zoneLockdown,    "err"},
        {"Zone Unlock",        actions.zoneUnlock,      "ok"},
        {"Declare Breach",     actions.declareBreach,   "err"},
        {"End Breach",         actions.endBreach,       "ok"},
        {"Entity Status",      actions.setEntityStatus, "warn"},
        {"Facility State",    actions.facilityState,   "warn"},
        {"View Status",        actions.viewStatus,      nil},
        {"Log Out",            actions.logout,          nil},
    }

    while true do
        if not session.loggedIn then drawLogin() end

        ui.clear(term.current())
        -- Banner with current state
        local st = status.facility.state or "normal"
        local stCol = ({normal=ui.OK, warning=ui.WARN, breach=ui.ERR, lockdown=ui.ERR, caution=ui.WARN})[st] or ui.FG

        local w, h = term.getSize()
        -- Custom header
        term.setCursorPos(1, 1); term.setBackgroundColor(stCol); term.setTextColor(ui.BG)
        term.write(string.rep(" ", w))
        local title = "CONTROL ROOM // "..string.upper(st)
        term.setCursorPos(math.max(1, math.floor((w-#title)/2)+1), 1); term.write(title)

        term.setCursorPos(1, 2); term.setBackgroundColor(ui.BG); term.setTextColor(ui.DIM)
        local sub = "Operator: "..(session.username or "-").."  //  "..os.date("%H:%M:%S")
        term.setCursorPos(math.max(1, math.floor((w-#sub)/2)+1), 2); term.write(sub)

        -- Breach count badge
        if #status.breaches > 0 then
            term.setCursorPos(2, 3); term.setBackgroundColor(ui.ERR); term.setTextColor(ui.BG)
            term.write(" "..#status.breaches.." ACTIVE BREACH"..(#status.breaches > 1 and "ES" or "").." ")
            term.setBackgroundColor(ui.BG); term.setTextColor(ui.FG)
        end

        -- Menu buttons
        local labels = {}
        for i, o in ipairs(options) do labels[i] = o[1] end
        local buttons = ui.buttonGrid(term.current(), labels, {startY=5, cols=2, btnH=3, hotkeys=true})

        local choice = ui.clickMenu(buttons)
        if choice and options[choice] then
            local ok, err = pcall(options[choice][2])
            if not ok then
                ui.bigStatus(term.current(), {"ERROR","",tostring(err)}, "error"); sleep(2)
            end
        end
    end
end

-- ============================================================
-- Background: refresh status + draw dashboard
-- ============================================================
local function pollerLoop()
    while true do
        if session.passcode then
            pcall(refreshStatus)
        end
        sleep(2)
    end
end

local function dashLoop()
    while true do
        pcall(drawDashboard)
        sleep(0.5)   -- faster redraw for flashing animations
    end
end

parallel.waitForAny(consoleLoop, pollerLoop, dashLoop)

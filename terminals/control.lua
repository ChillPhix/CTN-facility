-- terminals/control.lua
-- CTN Control Room Terminal.
-- Provides:
--   * Live dashboard (zones, occupants, breaches, log) on an Advanced Monitor
--   * Interactive control panel on the computer screen: lockdown, breach, facility state
-- Peripherals: wireless modem, advanced monitor (recommended 3x2 or 4x3 blocks).

package.path = package.path .. ";/lib/?.lua"
local proto  = require("ctnproto")
local ui     = require("ctnui")
local config = require("ctnconfig")

proto.openModem()

local cfg = config.loadOrWizard("control", {
    {key="mainframeId", prompt="Mainframe computer ID", type="number"},
})

local ZONES = {"Office","Security","Testing","LCZ","HCZ"}

-- Find a monitor if present
local monitor
for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "monitor" then
        monitor = peripheral.wrap(side)
        monitor.setTextScale(0.5)
        break
    end
end

-- ============================================================
-- Session state
-- ============================================================
local session = {
    loggedIn = false,
    username = nil,
    passcode = nil,
}

-- Last received status from the mainframe
local status = {
    facility = {state="normal"},
    zones = {}, breaches = {}, recentLog = {},
}

-- ============================================================
-- Monitor dashboard drawing (DirectGPU or standard monitor)
-- ============================================================
local gpu = require("ctngpu")

-- Open the backend once (detects directgpu, then monitor, then term)
local dashBackend
local function ensureBackend()
    if dashBackend then return dashBackend end
    dashBackend = gpu.openBackend({preferGpu = true})
    return dashBackend
end

local function drawDashboard()
    local be = ensureBackend()
    if not be then return end
    local w, h = be:size()
    local isGpu = be.mode == "gpu"

    -- State colors
    local state = status.facility.state or "normal"
    local bannerColor
    if state == "lockdown" or state == "breach" then bannerColor = gpu.COLORS.err
    elseif state == "warning" or state == "caution" then bannerColor = gpu.COLORS.warn
    else bannerColor = gpu.COLORS.fg end

    be:clear(gpu.COLORS.bg)

    -- Top banner
    if isGpu then
        be:fillRect(0, 0, w, 28, bannerColor)
        be:text(10, 6, "C.T.N  //  CONTAINMENT DIVISION", gpu.COLORS.bg, 16, "bold")
        be:text(w - 200, 6, "STATUS: "..state:upper(), gpu.COLORS.bg, 14, "bold")
        be:fillRect(0, 28, w, 2, gpu.COLORS.bg)
    else
        be:fillRect(1, 1, w, 1, bannerColor)
        local title = "C.T.N  //  STATUS: "..state:upper()
        be:textBg(math.max(1, math.floor((w - #title)/2)+1), 1, title, gpu.COLORS.bg, bannerColor)
    end

    -- Layout: 4 panels in a 2x2 grid (or simpler for small screens)
    -- GPU dimensions are pixels; monitor dimensions are chars. Different layouts.
    if isGpu then
        local pad = 6
        local topY = 34
        local halfW = math.floor((w - pad * 3) / 2)
        local halfH = math.floor((h - topY - pad * 2) / 2) - 4

        -- Panel 1: Zones (top-left)
        local p1 = gpu.panel(be, pad, topY, halfW, halfH, "ZONE STATUS", "normal")
        local zy = p1.contentY
        for _, zname in ipairs(ZONES) do
            local z = status.zones[zname] or {}
            local st = z.lockdown and "err" or "ok"
            gpu.led(be, p1.x + 8, zy, nil, st)
            be:text(p1.x + 28, zy + 2, zname, gpu.COLORS.fg, 12, "bold")
            local statusText = z.lockdown and "[LOCKDOWN]" or "[NORMAL]"
            local stCol = z.lockdown and gpu.COLORS.err or gpu.COLORS.ok
            be:text(p1.x + 110, zy + 2, statusText, stCol, 11, "bold")
            local occ = z.occupants and #z.occupants or 0
            be:text(p1.x + 220, zy + 2, occ.." in zone", gpu.COLORS.dim, 10, "plain")
            zy = zy + 18
        end

        -- Panel 2: Active Breaches (top-right)
        local p2 = gpu.panel(be, pad*2 + halfW, topY, halfW, halfH, "ACTIVE BREACHES",
            (#status.breaches > 0) and "err" or "ok")
        if #status.breaches == 0 then
            be:text(p2.x + 12, p2.contentY + 8, "Facility nominal.", gpu.COLORS.ok, 14, "bold")
            be:text(p2.x + 12, p2.contentY + 28, "No active containment breaches.", gpu.COLORS.dim, 10, "plain")
        else
            local by = p2.contentY
            for _, b in ipairs(status.breaches) do
                gpu.led(be, p2.x + 8, by, nil, "err")
                be:text(p2.x + 28, by + 2, b.scpId, gpu.COLORS.err, 14, "bold")
                be:text(p2.x + 120, by + 2, "@ "..b.zone, gpu.COLORS.warn, 11, "plain")
                by = by + 18
                if by > p2.contentY + p2.contentH - 12 then break end
            end
        end

        -- Panel 3: Activity log (bottom-left, wider)
        local logW = halfW * 2 + pad
        local logY = topY + halfH + pad
        local p3 = gpu.panel(be, pad, logY, logW, halfH, "SECURITY AUDIT LOG", "normal")
        gpu.logList(be, p3.x + 4, p3.contentY, p3.w - 8, p3.contentH, status.recentLog or {})

        -- Bottom strip: timestamp, identity
        be:text(pad, h - 14, "CONTROL ROOM  //  "..os.date("%Y-%m-%d %H:%M:%S"), gpu.COLORS.dim, 10, "plain")
        be:text(w - 200, h - 14, "OPERATOR: "..(session.username or "---"), gpu.COLORS.dim, 10, "plain")
    else
        -- Char-cell monitor layout
        local topY = 3
        local splitX = math.floor(w / 2)
        local panelH = math.floor((h - topY - 2) / 2)

        -- Zones panel
        local p1 = gpu.panel(be, 1, topY, splitX, panelH, "ZONE STATUS", "normal")
        local zy = p1.contentY
        for _, zname in ipairs(ZONES) do
            if zy > p1.y + p1.h - 2 then break end
            local z = status.zones[zname] or {}
            local stCol = z.lockdown and gpu.COLORS.err or gpu.COLORS.ok
            be:textBg(p1.x + 2, zy, " ", gpu.COLORS.bg, stCol)
            be:text(p1.x + 4, zy, zname, gpu.COLORS.fg)
            local txt = z.lockdown and " [LOCKDOWN]" or " [normal]"
            be:text(p1.x + 15, zy, txt, stCol)
            local occ = z.occupants and #z.occupants or 0
            be:text(p1.x + 28, zy, "("..occ..")", gpu.COLORS.dim)
            zy = zy + 1
        end

        -- Breaches panel
        local p2 = gpu.panel(be, splitX + 1, topY, w - splitX, panelH, "BREACHES",
            (#status.breaches > 0) and "err" or "ok")
        if #status.breaches == 0 then
            be:text(p2.x + 2, p2.contentY, "No active breaches.", gpu.COLORS.ok)
        else
            local by = p2.contentY
            for _, b in ipairs(status.breaches) do
                if by > p2.y + p2.h - 2 then break end
                be:text(p2.x + 2, by, "!! "..b.scpId.." @ "..b.zone, gpu.COLORS.err)
                by = by + 1
            end
        end

        -- Log panel (full width, bottom)
        local p3 = gpu.panel(be, 1, topY + panelH, w, h - topY - panelH - 1,
            "SECURITY AUDIT LOG", "normal")
        gpu.logList(be, p3.x + 2, p3.contentY, p3.w - 4, p3.contentH, status.recentLog or {})

        -- Footer
        be:fillRect(1, h, w, 1, gpu.COLORS.fg)
        be:textBg(2, h, "CONTROL ROOM  //  "..os.date("%H:%M:%S"), gpu.COLORS.bg, gpu.COLORS.fg)
    end

    be:update()
end

-- ============================================================
-- Control panel (computer screen) - interactive menu
-- ============================================================
local function sendCmd(action, args)
    -- Used both for normal commands and for login validation. If the
    -- user hasn't finished logging in yet, session.passcode is already
    -- set by the login flow below so the request is still valid.
    if not session.passcode then return nil end
    return proto.request(cfg.mainframeId, "facility_command", {
        passcode = session.passcode,
        issuedBy = session.username,
        action   = action,
        args     = args or {},
    }, 4)
end

local function pickZone()
    ui.frame(term.current(), "SELECT ZONE", "CONTROL ROOM")
    for i, z in ipairs(ZONES) do
        term.setCursorPos(4, 4 + i)
        term.setTextColor(ui.DIM); write("["..i.."] ")
        term.setTextColor(ui.FG);  write(z)
    end
    term.setCursorPos(2, 4 + #ZONES + 2)
    term.setTextColor(ui.FG); write("> "); term.setTextColor(ui.ACCENT)
    return ZONES[tonumber(read())]
end

local function showReply(reply, msg)
    if not reply then
        ui.bigStatus(term.current(), {"MAINFRAME", "UNREACHABLE"}, "error")
    elseif reply.ok then
        ui.bigStatus(term.current(), {msg or "OK"}, "granted")
    else
        ui.bigStatus(term.current(), {"FAILED", "", string.upper(reply.reason or "?")}, "denied")
    end
    sleep(1.5)
end

local actions = {}

actions.zoneLockdown = function()
    local zone = pickZone()
    if zone then showReply(sendCmd("zone_lockdown", {zone=zone, issuedBy=session.username}),
        "LOCKDOWN ACTIVE: "..zone) end
end

actions.zoneUnlock = function()
    local zone = pickZone()
    if zone then showReply(sendCmd("zone_unlock", {zone=zone, issuedBy=session.username}),
        "ZONE UNLOCKED: "..zone) end
end

actions.declareBreach = function()
    ui.frame(term.current(), "DECLARE BREACH", "CRITICAL ACTION")
    term.setCursorPos(2, 5); term.setTextColor(ui.WARN)
    print("This triggers facility-wide alarms.")

    -- Fetch entity list from mainframe so user can pick
    local entReply = sendCmd("list_entities", {})

    local entities = (entReply and entReply.ok) and entReply.entities or {}
    local containedOnly = {}
    for _, e in ipairs(entities) do
        if e.status == "contained" or e.status == "testing" or e.status == "maintenance" then
            containedOnly[#containedOnly+1] = e
        end
    end

    if #containedOnly > 0 then
        term.setCursorPos(2, 7); term.setTextColor(ui.FG)
        print("Registered entities:")
        for i, e in ipairs(containedOnly) do
            if i > 9 then break end
            term.setCursorPos(4, 7 + i)
            term.setTextColor(ui.DIM); write("["..i.."] ")
            term.setTextColor(ui.FG);  write(e.entityId.." - "..e.name.." @ "..e.zone)
        end
        term.setCursorPos(2, 18); term.setTextColor(ui.DIM)
        print("Pick a number, or type 0 to enter manually.")
        term.setCursorPos(2, 19); term.setTextColor(ui.FG); write("> ")
        term.setTextColor(ui.ACCENT)
        local n = tonumber(read())
        term.setTextColor(ui.FG)
        if n and n > 0 and containedOnly[n] then
            local e = containedOnly[n]
            showReply(sendCmd("declare_breach", {scpId=e.entityId, zone=e.zone, issuedBy=session.username}),
                "BREACH: "..e.entityId)
            return
        end
    end

    -- Manual entry fallback
    term.setCursorPos(2, 20); term.setTextColor(ui.FG)
    local scpId = ui.prompt("Entity ID: ")
    if scpId == "" then return end
    local zone = pickZone()
    if zone then
        showReply(sendCmd("declare_breach", {scpId=scpId, zone=zone, issuedBy=session.username}),
            "BREACH DECLARED")
    end
end

actions.endBreach = function()
    ui.frame(term.current(), "END BREACH", "CONTAINMENT RESTORED")
    if #status.breaches == 0 then
        ui.bigStatus(term.current(), {"NO ACTIVE BREACHES"}, "idle"); sleep(1.5); return
    end
    term.setCursorPos(2, 5); term.setTextColor(ui.FG)
    print("Active breaches:")
    for i, b in ipairs(status.breaches) do
        term.setCursorPos(4, 5 + i); write("["..i.."] "..b.scpId.." @ "..b.zone)
    end
    term.setCursorPos(2, 6 + #status.breaches); write("> ")
    term.setTextColor(ui.ACCENT)
    local b = status.breaches[tonumber(read())]
    if b then
        showReply(sendCmd("end_breach", {scpId=b.scpId, issuedBy=session.username}),
            "BREACH CONTAINED: "..b.scpId)
    end
end

actions.setEntityStatus = function()
    -- Fetch entity list
    local entReply = sendCmd("list_entities", {})
    if not entReply or not entReply.ok then
        ui.bigStatus(term.current(), {"MAINFRAME","UNREACHABLE"}, "error"); sleep(2); return
    end
    local entities = entReply.entities
    if #entities == 0 then
        ui.bigStatus(term.current(), {"NO ENTITIES","","Register via admin terminal."}, "idle"); sleep(2); return
    end

    ui.frame(term.current(), "ENTITY STATUS", "SELECT ENTITY")
    local _, h = term.getSize()
    local maxShow = math.min(#entities, h - 8)
    for i = 1, maxShow do
        local e = entities[i]
        term.setCursorPos(4, 4 + i); term.setTextColor(ui.DIM); write("["..i.."] ")
        term.setTextColor(ui.FG)
        write(string.format("%-10s %-12s ", e.entityId, e.class))
        local sc = ({contained=ui.OK, breached=ui.ERR, testing=ui.WARN, maintenance=ui.WARN})[e.status] or ui.FG
        term.setTextColor(sc); write("["..e.status.."]")
    end
    term.setCursorPos(2, 5 + maxShow + 1); term.setTextColor(ui.FG); write("> ")
    term.setTextColor(ui.ACCENT); local n = tonumber(read()); term.setTextColor(ui.FG)
    local e = entities[n]
    if not e then return end

    local statuses = {"contained","testing","maintenance","decommissioned","deceased"}
    ui.frame(term.current(), "SET STATUS: "..e.entityId, "")
    for i, s in ipairs(statuses) do
        term.setCursorPos(4, 4 + i); term.setTextColor(ui.DIM); write("["..i.."] ")
        term.setTextColor(ui.FG); write(s:upper())
    end
    term.setCursorPos(2, 5 + #statuses + 1); write("> "); term.setTextColor(ui.ACCENT)
    local newStatus = statuses[tonumber(read())]
    if newStatus then
        showReply(sendCmd("set_entity_status", {entityId=e.entityId, status=newStatus, issuedBy=session.username}),
            e.entityId.." -> "..newStatus:upper())
    end
end

actions.listEntities = function()
    local r = sendCmd("list_entities", {})
    if not r or not r.ok then
        ui.bigStatus(term.current(), {"FETCH FAILED"}, "error"); sleep(1.5); return
    end
    ui.frame(term.current(), "ENTITY REGISTRY", tostring(#r.entities).." contained")
    local y, _, h = 4, nil, select(2, term.getSize())
    for _, e in ipairs(r.entities) do
        if y > h - 2 then break end
        term.setCursorPos(2, y); term.setTextColor(ui.ACCENT); write(string.format("%-10s ", e.entityId))
        term.setTextColor(ui.FG); write(string.format("%-10s ", e.class))
        term.setTextColor(ui.DIM); write(string.format("%-6s ", e.zone))
        local c = ({contained=ui.OK, breached=ui.ERR, testing=ui.WARN, maintenance=ui.WARN})[e.status] or ui.FG
        term.setTextColor(c); write("["..e.status.."] ")
        term.setTextColor(ui.DIM); write("T"..(e.threat or "?"))
        y = y + 1
    end
    term.setCursorPos(2, select(2, term.getSize()) - 2); term.setTextColor(ui.DIM)
    write("[ press Enter ]"); read()
end

actions.setState = function()
    local states = {"normal","caution","warning","lockdown"}
    ui.frame(term.current(), "FACILITY STATE", "CONTROL ROOM")
    for i, s in ipairs(states) do
        term.setCursorPos(4, 4 + i)
        term.setTextColor(ui.DIM); write("["..i.."] ")
        term.setTextColor(ui.FG);  write(s:upper())
    end
    term.setCursorPos(2, 4 + #states + 2); write("> "); term.setTextColor(ui.ACCENT)
    local s = states[tonumber(read())]
    if s then
        showReply(sendCmd("set_state", {state=s, issuedBy=session.username}),
            "FACILITY STATE: "..s:upper())
    end
end

actions.logout = function()
    session.loggedIn = false; session.username = nil; session.passcode = nil
end

-- ============================================================
-- Login flow
-- ============================================================
local function login()
    while not session.loggedIn do
        ui.frame(term.current(), "CONTROL ROOM LOGIN", "AUTHENTICATION REQUIRED")
        term.setCursorPos(2, 5); term.setTextColor(ui.WARN)
        print("Unauthorised access is a Class-3 offence.")
        term.setCursorPos(2, 7); term.setTextColor(ui.FG)
        local username = ui.prompt("Username:        ")
        term.setCursorPos(2, 8)
        local passcode = ui.promptHidden("Control passcode: ")

        session.username = username; session.passcode = passcode

        ui.bigStatus(term.current(), {"AUTHENTICATING..."}, "working")
        local reply = sendCmd("list_entities", {})
        -- read-only action validates passcode without side effects
        if not reply then
            ui.bigStatus(term.current(), {"MAINFRAME UNREACHABLE"}, "error"); sleep(2)
        elseif reply.ok then
            session.loggedIn = true
            ui.bigStatus(term.current(), {"ACCESS GRANTED", "", "Welcome, "..username}, "granted")
            sleep(1)
        else
            ui.bigStatus(term.current(), {"ACCESS DENIED", "",
                string.upper(reply.reason or "?")}, "denied"); sleep(2)
        end
    end
end

-- ============================================================
-- Parallel loops
-- ============================================================
local function statusPoller()
    while true do
        local reply = proto.request(cfg.mainframeId, "status_request", {}, 2)
        if reply and reply.ok then
            status.facility = reply.facility or status.facility
            status.zones    = reply.zones or {}
            status.breaches = reply.breaches or {}
            status.recentLog = reply.recentLog or {}
        end
        sleep(2)
    end
end

local function dashboardLoop()
    while true do
        pcall(drawDashboard)
        sleep(1)
    end
end

local function alertListener()
    -- Disabled: calling proto.receive here would race with statusPoller's
    -- and sendCmd's request/reply cycles, stealing replies. The status
    -- poll every 2 seconds is responsive enough for dashboard updates.
    while true do sleep(60) end
end

local function uiLoop()
    login()
    local options = {
        {"Zone Lockdown",       actions.zoneLockdown},
        {"Zone Unlock",         actions.zoneUnlock},
        {"Declare Breach",      actions.declareBreach},
        {"End Breach",          actions.endBreach},
        {"Set Entity Status",   actions.setEntityStatus},
        {"List Entities",       actions.listEntities},
        {"Set Facility State",  actions.setState},
        {"Log Out",             actions.logout},
    }
    while true do
        if not session.loggedIn then login() end
        ui.frame(term.current(), "CONTROL ROOM - "..(session.username or ""), "C.T.N")

        -- Show current facility state banner
        local state = status.facility.state or "normal"
        local stCol = ({normal=ui.OK, caution=ui.WARN, warning=ui.WARN, lockdown=ui.ERR, breach=ui.ERR})[state] or ui.FG
        term.setCursorPos(2, 5); term.setTextColor(ui.FG); write("Facility: ")
        term.setTextColor(stCol); write(state:upper())
        if #status.breaches > 0 then
            term.setCursorPos(2, 6); term.setTextColor(ui.ERR)
            write("!! "..#status.breaches.." ACTIVE BREACH(ES) !!")
        end

        local labels = {}
        for i, opt in ipairs(options) do labels[i] = opt[1] end
        local choice = ui.menu(nil, labels, 8)
        if choice and options[choice] then
            local ok, err = pcall(options[choice][2])
            if not ok then
                ui.bigStatus(term.current(), {"ERROR", "", tostring(err)}, "error"); sleep(2)
            end
        end
    end
end

parallel.waitForAny(statusPoller, dashboardLoop, alertListener, uiLoop)

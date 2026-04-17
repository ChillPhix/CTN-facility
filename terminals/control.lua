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
-- Monitor dashboard drawing
-- ============================================================
local function drawDashboard(t)
    ui.clear(t)
    local w, h = t.getSize()

    -- Top banner (yellow bar with facility state color swap when breach/lockdown)
    local state = status.facility.state or "normal"
    local topColor = ({normal=ui.FG, caution=ui.WARN, warning=ui.WARN, lockdown=ui.ERR, breach=ui.ERR})[state] or ui.FG

    t.setCursorPos(1, 1); t.setBackgroundColor(topColor); t.setTextColor(ui.BG)
    t.write(string.rep(" ", w))
    local title = "C.T.N // FACILITY STATUS: "..string.upper(state)
    t.setCursorPos(math.max(1, math.floor((w - #title)/2)+1), 1); t.write(title)
    t.setBackgroundColor(ui.BG); t.setTextColor(ui.FG)

    -- Main layout: left half = zones, right half = breaches + log
    local splitX = math.floor(w / 2)

    -- === ZONES column ===
    t.setCursorPos(2, 3); t.setTextColor(ui.ACCENT); t.write("== ZONES ==")
    local zy = 5
    for _, zname in ipairs(ZONES) do
        local z = status.zones[zname] or {}
        local col = z.lockdown and ui.ERR or ui.OK
        t.setCursorPos(2, zy); t.setTextColor(col); t.write(z.lockdown and "[LOCK] " or "[OPEN] ")
        t.setTextColor(ui.FG); t.write(zname)
        local occ = z.occupants and #z.occupants or 0
        if occ > 0 then
            t.setTextColor(ui.DIM); t.write("  ["..occ.." personnel]")
        end
        zy = zy + 1

        -- List occupants if any
        if z.occupants and #z.occupants > 0 then
            for i = 1, math.min(3, #z.occupants) do
                t.setCursorPos(6, zy); t.setTextColor(ui.DIM); t.write("- "..z.occupants[i])
                zy = zy + 1
            end
            if #z.occupants > 3 then
                t.setCursorPos(6, zy); t.setTextColor(ui.DIM); t.write("  (+"..(#z.occupants - 3).." more)")
                zy = zy + 1
            end
        end
        zy = zy + 1
        if zy > h - 3 then break end
    end

    -- === BREACHES (top-right) ===
    t.setCursorPos(splitX + 2, 3); t.setTextColor(ui.ACCENT); t.write("== ACTIVE BREACHES ==")
    if #status.breaches == 0 then
        t.setCursorPos(splitX + 2, 5); t.setTextColor(ui.OK); t.write("None. Facility nominal.")
    else
        local by = 5
        for _, b in ipairs(status.breaches) do
            t.setCursorPos(splitX + 2, by); t.setTextColor(ui.ERR)
            t.write("!! "..b.scpId.." @ "..b.zone)
            by = by + 1
            if by > math.floor(h / 2) then break end
        end
    end

    -- === LOG (bottom-right) ===
    local ly = math.floor(h / 2) + 2
    t.setCursorPos(splitX + 2, ly); t.setTextColor(ui.ACCENT); t.write("== RECENT ACTIVITY ==")
    ly = ly + 2
    local entries = status.recentLog or {}
    local start = math.max(1, #entries - (h - ly - 1))
    for i = start, #entries do
        if ly >= h - 1 then break end
        local e = entries[i]
        if e then
            local tstr = os.date("%H:%M:%S", (e.ts or 0) / 1000)
            t.setCursorPos(splitX + 2, ly); t.setTextColor(ui.DIM); t.write(tstr.." ")
            local c = ({security=ui.ERR, access=ui.WARN, admin=ui.OK, facility=ui.ACCENT})[e.category] or ui.FG
            t.setTextColor(c)
            local msg = tostring(e.message or ""):sub(1, w - splitX - 15)
            t.write(msg)
            ly = ly + 1
        end
    end

    -- Footer
    t.setCursorPos(1, h); t.setBackgroundColor(ui.FG); t.setTextColor(ui.BG)
    t.write(string.rep(" ", w))
    t.setCursorPos(2, h); t.write("CONTROL ROOM  " .. os.date("%H:%M:%S"))
    t.setBackgroundColor(ui.BG); t.setTextColor(ui.FG)
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
        if monitor then pcall(drawDashboard, monitor) end
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

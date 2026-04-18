-- terminals/chamber.lua
-- Containment Chamber Terminal. Mounted on the front of an entity's cell.
-- Shows designation, class, threat level, and current status.
-- Researchers can swipe an ID card to view containment procedures.
-- Flashes red during a breach.
--
-- Peripherals:
--   - wireless modem
--   - optional: advanced monitor (recommended, any array size)
--   - optional: disk drive (for ID card procedure viewing)
--   - optional: redstone output for chamber emergency lighting

package.path = package.path .. ";/lib/?.lua"
local proto  = require("ctnproto")
local ui     = require("ctnui")
local cfg    = require("ctnconfig")

-- First-run wizard
local myCfg = cfg.loadOrWizard("chamber", {
    {key="mainframe_id", prompt="Mainframe computer ID", type="number", default=1},
    {key="redstone_side", prompt="Emergency light redstone side (or 'none')",
     type="pick", options={"back","front","left","right","top","bottom","none"}, default="none"},
})

proto.openModem()

local MAINFRAME = myCfg.mainframe_id
local RS_SIDE   = myCfg.redstone_side ~= "none" and myCfg.redstone_side or nil

-- Find peripherals
local function findPeripheral(typeName)
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == typeName then return peripheral.wrap(side), side end
    end
end

local monitor = findPeripheral("monitor")
if monitor then monitor.setTextScale(0.5) end

local drive = findPeripheral("drive")

-- ============================================================
-- Announce ourselves for admin approval
-- ============================================================
local function announce()
    proto.request(MAINFRAME, "announce", {
        type = "chamber",
        hostname = os.getComputerLabel() or ("chamber-"..os.getComputerID()),
    }, 2)
end

-- ============================================================
-- Local state
-- ============================================================
local state = {
    entity   = nil,      -- entity info from mainframe
    chamber  = nil,      -- {entityId, zone}
    status   = nil,      -- current status (contained/breached/testing/maintenance)
    procedures = nil,    -- loaded procedures text (when card swiped)
    viewer   = nil,      -- viewer name/clearance when swiped
    lastPoll = 0,
    error    = nil,
    breachFlash = false,
}

-- ============================================================
-- Render
-- ============================================================
local CLASS_COLORS = {
    Safe      = colors.lime,
    Euclid    = colors.orange,
    Keter     = colors.red,
    Thaumiel  = colors.lightBlue,
    Apollyon  = colors.magenta,
}

local function drawChamber(t)
    ui.clear(t)
    local w, h = t.getSize()

    -- Top banner: colour depends on breach state
    local bannerBg = state.breachFlash and ui.ERR or ui.FG
    local bannerFg = ui.BG
    t.setCursorPos(1, 1); t.setBackgroundColor(bannerBg); t.setTextColor(bannerFg)
    t.write(string.rep(" ", w))
    local title = state.breachFlash and ">>> CONTAINMENT BREACH <<<" or "C.T.N CONTAINMENT CHAMBER"
    t.setCursorPos(math.max(1, math.floor((w - #title)/2)+1), 1); t.write(title)

    t.setCursorPos(1, 2); t.setBackgroundColor(ui.BG); t.setTextColor(ui.FG)
    t.write(string.rep(" ", w))
    t.setCursorPos(1, 3); t.setTextColor(ui.BORDER); t.write(string.rep("=", w))

    if state.error then
        t.setCursorPos(2, 5); t.setTextColor(ui.ERR); t.write("NOT CONFIGURED")
        t.setCursorPos(2, 7); t.setTextColor(ui.FG);  t.write(state.error)
        ui.footer(t, "WAITING FOR APPROVAL // ID#"..os.getComputerID())
        return
    end

    if not state.entity then
        t.setCursorPos(2, 5); t.setTextColor(ui.WARN); t.write("No entity assigned.")
        t.setCursorPos(2, 7); t.setTextColor(ui.DIM); t.write("Awaiting configuration from mainframe.")
        ui.footer(t, "CHAMBER #"..os.getComputerID())
        return
    end

    local e = state.entity

    -- Designation (big)
    t.setCursorPos(2, 5); t.setTextColor(ui.ACCENT)
    t.write("DESIGNATION:")
    t.setCursorPos(2, 6); t.setTextColor(ui.FG)
    t.write("  "..e.entityId.."  -  "..e.name)

    -- Class + threat
    t.setCursorPos(2, 8); t.setTextColor(ui.ACCENT); t.write("OBJECT CLASS:")
    t.setCursorPos(2, 9)
    t.setTextColor(CLASS_COLORS[e.class] or ui.FG)
    t.write("  "..string.upper(e.class))

    t.setCursorPos(2, 11); t.setTextColor(ui.ACCENT); t.write("THREAT LEVEL:")
    t.setCursorPos(2, 12); t.setTextColor(ui.WARN)
    local bar = string.rep("#", e.threat or 0) .. string.rep("-", 5 - (e.threat or 0))
    t.write("  ["..bar.."]  "..(e.threat or "?").."/5")

    -- Status
    local s = state.status or e.status or "contained"
    local statusColor = ({
        contained   = ui.OK,
        breached    = ui.ERR,
        testing     = ui.WARN,
        maintenance = ui.WARN,
        decommissioned = ui.DIM,
        deceased    = ui.DIM,
    })[s] or ui.FG
    t.setCursorPos(2, 14); t.setTextColor(ui.ACCENT); t.write("CURRENT STATUS:")
    t.setCursorPos(2, 15); t.setTextColor(statusColor); t.write("  "..string.upper(s))

    -- Description (wrapped, short)
    if e.description and e.description ~= "" then
        t.setCursorPos(2, 17); t.setTextColor(ui.ACCENT); t.write("DESCRIPTION:")
        local y = 18
        local desc = e.description
        local line = ""
        for word in desc:gmatch("%S+") do
            if #line + #word + 1 > w - 4 then
                t.setCursorPos(3, y); t.setTextColor(ui.FG); t.write(line)
                y = y + 1
                if y > h - 4 then break end
                line = word
            else
                line = (line == "" and word) or (line.." "..word)
            end
        end
        if line ~= "" and y <= h - 4 then
            t.setCursorPos(3, y); t.setTextColor(ui.FG); t.write(line)
        end
    end

    -- Procedures (if a card was swiped)
    if state.procedures then
        local py = h - 10
        if py > 18 then
            t.setCursorPos(1, py - 1); t.setTextColor(ui.BORDER); t.write(string.rep("-", w))
            t.setCursorPos(2, py); t.setTextColor(ui.ACCENT)
            t.write("CONTAINMENT PROCEDURES (viewer: "..(state.viewer and state.viewer.name or "?")..")")
            local y = py + 1
            for line in state.procedures:gmatch("[^\n]+") do
                if y > h - 2 then break end
                t.setCursorPos(3, y); t.setTextColor(ui.FG); t.write(line:sub(1, w-4))
                y = y + 1
            end
        end
    elseif state.procedures_denied then
        t.setCursorPos(2, h - 3); t.setTextColor(ui.ERR)
        t.write("PROCEDURES ACCESS DENIED")
        t.setCursorPos(2, h - 2); t.setTextColor(ui.DIM)
        t.write("Insufficient clearance (L"..(state.viewer and state.viewer.clearance or "?")..")")
    else
        t.setCursorPos(2, h - 3); t.setTextColor(ui.DIM)
        if drive then
            t.write("Insert ID card to view procedures.")
        end
    end

    ui.footer(t, e.entityId.." // "..(state.chamber and state.chamber.zone or "?"))
end

-- Try to use DirectGPU if available, for fancier chamber display on large monitors
local gpu = require("ctngpu")
local gpuBackend
local function ensureGpuBackend()
    if gpuBackend ~= nil then return gpuBackend end
    -- Try once; if no directgpu, remember that we failed so we don't retry constantly
    local g = peripheral.find("directgpu")
    if g then
        local ok, display = pcall(g.autoDetectAndCreateDisplay)
        if ok and display then
            gpuBackend = gpu.gpuBackend(g, display)
            return gpuBackend
        end
    end
    gpuBackend = false
    return false
end

local function drawChamberGpu(be)
    be:clear(gpu.COLORS.bg)
    local w, h = be:size()

    -- Banner
    local bannerColor = state.breachFlash and gpu.COLORS.err or gpu.COLORS.fg
    be:fillRect(0, 0, w, 28, bannerColor)
    local title = state.breachFlash and ">>> CONTAINMENT BREACH <<<" or "C.T.N CONTAINMENT CHAMBER"
    be:text(math.floor(w/2 - #title * 5), 6, title, gpu.COLORS.bg, 16, "bold")

    if state.error then
        gpu.panel(be, 20, 50, w - 40, 80, "NOT CONFIGURED", "warn")
        be:text(30, 80, state.error, gpu.COLORS.warn, 12, "plain")
        be:update(); return
    end

    if not state.entity then
        gpu.panel(be, 20, 50, w - 40, 80, "NO ENTITY ASSIGNED", "warn")
        be:text(30, 80, "Awaiting configuration from mainframe.", gpu.COLORS.dim, 11, "plain")
        be:update(); return
    end

    local e = state.entity
    local classColor = ({
        Safe=gpu.COLORS.ok, Euclid=gpu.COLORS.warn, Keter=gpu.COLORS.err,
        Thaumiel=gpu.COLORS.accent2, Apollyon=gpu.COLORS.purple,
    })[e.class] or gpu.COLORS.fg

    -- Designation panel
    local p1 = gpu.panel(be, 20, 40, math.floor(w/2) - 30, 100, "DESIGNATION", "normal")
    be:text(p1.x + 12, p1.contentY + 8, e.entityId, gpu.COLORS.fg, 36, "bold")
    be:text(p1.x + 12, p1.contentY + 50, e.name, gpu.COLORS.accent, 14, "plain")

    -- Class/Threat panel
    local p2 = gpu.panel(be, math.floor(w/2) + 10, 40, math.floor(w/2) - 30, 100, "OBJECT CLASSIFICATION", "normal")
    be:text(p2.x + 12, p2.contentY + 8, string.upper(e.class), classColor, 26, "bold")
    be:text(p2.x + 12, p2.contentY + 50, "Threat Level", gpu.COLORS.dim, 10, "plain")
    gpu.bar(be, p2.x + 12, p2.contentY + 62, p2.w - 24, 12, (e.threat or 0) / 5,
        (e.threat or 0) >= 4 and "err" or ((e.threat or 0) >= 3 and "warn" or "ok"))

    -- Status panel (full width)
    local stColor, stState
    if state.status == "breached" then stColor=gpu.COLORS.err; stState="err"
    elseif state.status == "testing" or state.status == "maintenance" then stColor=gpu.COLORS.warn; stState="warn"
    else stColor=gpu.COLORS.ok; stState="ok" end

    local p3 = gpu.panel(be, 20, 150, w - 40, 50, "CURRENT STATUS", stState)
    be:text(p3.x + 12, p3.contentY + 4, string.upper(state.status or e.status or "contained"), stColor, 20, "bold")

    -- Description panel
    local p4 = gpu.panel(be, 20, 210, w - 40, 100, "DESCRIPTION", "normal")
    local desc = e.description or "(no description)"
    -- crude wrap
    local maxChars = math.floor((p4.w - 24) / 6)
    local y = p4.contentY + 4
    for word in desc:gmatch("%S+") do
        -- too crude a wrap; just print first line worth
    end
    if desc ~= "" then
        be:text(p4.x + 12, p4.contentY + 8, desc:sub(1, maxChars), gpu.COLORS.fg, 11, "plain")
        if #desc > maxChars then
            be:text(p4.x + 12, p4.contentY + 22, desc:sub(maxChars+1, maxChars*2), gpu.COLORS.fg, 11, "plain")
        end
    end

    -- Procedures (if card swiped)
    if state.procedures then
        local p5 = gpu.panel(be, 20, 320, w - 40, h - 340, "CONTAINMENT PROCEDURES", "normal")
        be:text(p5.x + 12, p5.contentY + 4,
            "Viewer: "..(state.viewer and state.viewer.name or "?"), gpu.COLORS.accent, 10, "plain")
        local py = p5.contentY + 20
        for line in (state.procedures or ""):gmatch("[^\n]+") do
            if py > p5.y + p5.h - 16 then break end
            be:text(p5.x + 12, py, line:sub(1, maxChars), gpu.COLORS.fg, 10, "plain")
            py = py + 12
        end
    elseif state.procedures_denied then
        gpu.panel(be, 20, 320, w - 40, 40, "ACCESS DENIED", "err")
        be:text(32, 340, "Insufficient clearance (L"..(state.viewer and state.viewer.clearance or "?")..")",
            gpu.COLORS.err, 12, "bold")
    elseif drive then
        be:text(20, h - 30, "Insert ID card to view containment procedures.", gpu.COLORS.dim, 11, "plain")
    end

    -- Footer
    be:text(20, h - 14, e.entityId.." // "..(state.chamber and state.chamber.zone or "?").." // ID#"..os.getComputerID(),
        gpu.COLORS.dim, 10, "plain")

    be:update()
end

local function render()
    drawChamber(term.current())
    local be = ensureGpuBackend()
    if be then
        pcall(drawChamberGpu, be)
    elseif monitor then
        drawChamber(monitor)
    end
end

-- ============================================================
-- Polling and events
-- ============================================================
local function pollStatus(diskID)
    local reply = proto.request(MAINFRAME, "chamber_info", {diskID=diskID}, 3)
    if not reply then
        state.error = "Mainframe unreachable."
        return
    end
    if not reply.ok then
        state.error = "Not registered. Contact admin to approve this chamber."
        announce()
        return
    end
    state.error = nil
    state.chamber = reply.chamber
    state.entity = reply.entity
    if reply.entity then state.status = reply.entity.status end
    state.procedures = reply.procedures
    state.procedures_denied = reply.procedures_denied
    state.viewer = reply.viewer
    state.lastPoll = os.epoch("utc")
end

local function setEmergencyLight(on)
    if RS_SIDE then redstone.setOutput(RS_SIDE, on and true or false) end
end

-- Breach flash loop runs while status=breached
local function breachLoop()
    while true do
        if state.status == "breached" then
            state.breachFlash = not state.breachFlash
            setEmergencyLight(state.breachFlash)
            render()
            sleep(0.5)
        else
            if state.breachFlash then
                state.breachFlash = false
                setEmergencyLight(false)
                render()
            end
            sleep(0.3)
        end
    end
end

-- Main event loop.
-- Handles: disk insert/eject events, chamber_alert pushes from mainframe,
-- and a periodic status refresh. Using a single os.pullEvent() loop avoids
-- two parallel tasks fighting over rednet messages.
local function mainLoop()
    announce()
    pollStatus()
    render()

    local pollTimer = os.startTimer(10)
    while true do
        local event, a, b, c, d = os.pullEvent()
        if event == "disk" and drive then
            local id = drive.getDiskID()
            if id then pollStatus(id); render() end
        elseif event == "disk_eject" then
            state.procedures = nil
            state.procedures_denied = nil
            state.viewer = nil
            render()
        elseif event == "timer" and a == pollTimer then
            pollStatus(drive and drive.getDiskID() or nil)
            render()
            pollTimer = os.startTimer(10)
        elseif event == "rednet_message" then
            -- a = senderID, b = message (envelope), c = protocol
            -- Verify through proto by handing the event back, but we're
            -- already past proto's queue. Instead, re-fetch status on any
            -- alert-type message.
            if c == proto.PROTOCOL and type(b) == "table" then
                if b.type == "chamber_alert" and b.from == MAINFRAME then
                    -- Verify signature against the secret to avoid spoofing.
                    -- proto exposes hmac + canonical internally; we just re-poll
                    -- which is simpler and guaranteed correct.
                    pollStatus(drive and drive.getDiskID() or nil)
                    render()
                end
            end
        end
    end
end

parallel.waitForAny(mainLoop, breachLoop)

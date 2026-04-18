-- terminals/action.lua
-- CTN Action Terminal - facility-wide emergency response station.
-- Scattered throughout the facility. Authenticates by ID card;
-- available actions depend on the card holder's clearance.
--
-- Supports mouse click, monitor touch, AND numeric hotkeys.
-- Includes a panic-button redstone input for instant security alerts.
--
-- Peripherals:
--   - wireless modem
--   - disk drive
--   - optional: advanced monitor (any size, touch-enabled by default)
--   - optional: panic button (redstone input on configured side)

package.path = package.path .. ";/lib/?.lua"
local proto = require("ctnproto")
local ui    = require("ctnui")
local cfg   = require("ctnconfig")

local myCfg = cfg.loadOrWizard("action", {
    {key="mainframe_id",   prompt="Mainframe computer ID", type="number", default=1},
    {key="label",          prompt="Terminal label (e.g. 'Security Guard Post 3')", default="Action Terminal"},
    {key="zone",           prompt="Zone this terminal is in",
     type="pick", options={"Office","Security","Testing","LCZ","HCZ"}, default="Office"},
    {key="panic_side",     prompt="Panic button redstone input side (or 'none')",
     type="pick", options={"back","front","left","right","top","bottom","none"}, default="none"},
})

proto.openModem()
local MAINFRAME   = myCfg.mainframe_id
local ZONE        = myCfg.zone
local LABEL       = myCfg.label
local PANIC_SIDE  = myCfg.panic_side ~= "none" and myCfg.panic_side or nil

local function findPeripheral(typeName)
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == typeName then return peripheral.wrap(side), side end
    end
end

local drive, driveSide = findPeripheral("drive")
if not drive then error("No disk drive attached.") end

local monitor = findPeripheral("monitor")
if monitor then monitor.setTextScale(0.5) end

-- Announce to mainframe
local function announce()
    proto.request(MAINFRAME, "announce", {
        type = "action",
        hostname = os.getComputerLabel() or LABEL,
    }, 2)
end

-- ============================================================
-- Shared state
-- ============================================================
local state = {
    facility    = "normal",
    zoneLock    = false,  -- whether OUR zone is locked down
    breaches    = {},
    registered  = false,
    session     = nil,    -- {name, clearance, department} when card is in
    diskID      = nil,
    message     = nil,
    messageTimer = nil,
}

local function setMessage(msg, duration)
    state.message = msg
    state.messageTimer = os.startTimer(duration or 2)
end

-- ============================================================
-- Rendering
-- ============================================================

-- Available actions by clearance. Lower number = more access.
local ACTIONS_BY_CLEARANCE = {
    -- Each entry: {label, action_key, arg_builder?}
    [5] = {
        {label="View Facility Status",       key="view_status"},
    },
    [4] = {
        {label="View Facility Status",       key="view_status"},
        {label="SECURITY BREACH ALARM",      key="security_breach"},
    },
    [3] = {
        {label="View Facility Status",       key="view_status"},
        {label="SECURITY BREACH ALARM",      key="security_breach"},
        {label="DECLARE CONTAINMENT BREACH", key="declare_breach"},
        {label="Zone Lockdown (THIS zone)",  key="zone_lockdown"},
    },
    [2] = {
        {label="View Facility Status",       key="view_status"},
        {label="SECURITY BREACH ALARM",      key="security_breach"},
        {label="DECLARE CONTAINMENT BREACH", key="declare_breach"},
        {label="END BREACH",                 key="end_breach"},
        {label="Zone Lockdown (any zone)",   key="zone_lockdown", picks="zone"},
        {label="Zone Unlock",                key="zone_unlock",   picks="zone"},
    },
    [1] = {
        {label="View Facility Status",       key="view_status"},
        {label="SECURITY BREACH ALARM",      key="security_breach"},
        {label="DECLARE CONTAINMENT BREACH", key="declare_breach"},
        {label="END BREACH",                 key="end_breach"},
        {label="Zone Lockdown (any)",        key="zone_lockdown", picks="zone"},
        {label="Zone Unlock",                key="zone_unlock",   picks="zone"},
        {label="FACILITY LOCKDOWN",          key="facility_lockdown"},
    },
    [0] = {
        {label="View Facility Status",       key="view_status"},
        {label="SECURITY BREACH ALARM",      key="security_breach"},
        {label="DECLARE CONTAINMENT BREACH", key="declare_breach"},
        {label="END BREACH",                 key="end_breach"},
        {label="Zone Lockdown (any)",        key="zone_lockdown", picks="zone"},
        {label="Zone Unlock",                key="zone_unlock",   picks="zone"},
        {label="FACILITY LOCKDOWN",          key="facility_lockdown"},
        {label="Facility: NORMAL",           key="facility_normal"},
    },
}

local function actionsForClearance(c)
    return ACTIONS_BY_CLEARANCE[c] or ACTIONS_BY_CLEARANCE[5]
end

-- Draw the idle screen (no card)
local function drawIdle(t)
    ui.clear(t)
    -- Facility-state aware banner
    if state.facility == "lockdown" or state.facility == "breach" or state.zoneLock then
        ui.alertBanner(t, state.zoneLock and "lockdown" or state.facility,
            state.zoneLock and (ZONE.." ZONE LOCKDOWN") or string.upper(state.facility))
    else
        ui.header(t, "ACTION TERMINAL - "..ZONE)
    end

    local w, h = t.getSize()

    -- Central big prompt
    local bx, by, bw, bh = 2, math.floor(h/2) - 3, w - 2, 7
    ui.box(t, bx, by, bw, bh, ui.BORDER)
    t.setBackgroundColor(ui.BG); t.setTextColor(ui.ACCENT)
    local l1 = ">> INSERT ID CARD <<"
    t.setCursorPos(math.max(1, math.floor((w - #l1)/2) + 1), by + 2); t.write(l1)
    t.setTextColor(ui.DIM)
    local l2 = "Facility emergency response terminal"
    t.setCursorPos(math.max(1, math.floor((w - #l2)/2) + 1), by + 4); t.write(l2)

    -- Active breaches row
    if #state.breaches > 0 then
        t.setCursorPos(2, by + bh + 1); t.setTextColor(ui.ERR)
        t.write("ACTIVE BREACHES: ")
        local first = true
        for _, b in ipairs(state.breaches) do
            if not first then t.write(", ") end
            t.write(b.scpId)
            first = false
        end
    end

    -- Footer
    local right = state.registered and "LINKED" or "PENDING"
    if PANIC_SIDE then right = right .. "  PANIC OK" end
    ui.footer(t, LABEL.." // "..ZONE.."  //  "..right)
end

-- Draw the authenticated menu (card inserted, clearance known)
local function drawMenu(t)
    ui.clear(t)
    if state.facility == "lockdown" or state.facility == "breach" or state.zoneLock then
        ui.alertBanner(t, state.zoneLock and "lockdown" or state.facility,
            (state.session.name).."  L"..state.session.clearance)
    else
        ui.header(t, "WELCOME: "..state.session.name.."  (L"..state.session.clearance..")")
    end

    local actions = actionsForClearance(state.session.clearance)
    local labels = {}
    for i, a in ipairs(actions) do labels[i] = a.label end

    -- Grid of buttons
    local _, h = t.getSize()
    local buttons = ui.buttonGrid(t, labels, {startY=5, cols=1, btnH=2, hotkeys=true})

    -- Cancel button at bottom
    local _, screenH = t.getSize()
    local cancelBtn = ui.drawButton(t, 2, screenH - 3, select(1, t.getSize()) - 2, 2,
        "REMOVE CARD TO CANCEL", {fg=ui.DIM})

    ui.footer(t, ZONE.." // "..LABEL.." // Tap or press number")
    return buttons, actions
end

-- Utility to render on both terminal + monitor
local function render()
    if state.session then
        return drawMenu(term.current())  -- return buttons for clicking
    else
        drawIdle(term.current())
        if monitor then drawIdle(monitor) end
        return nil
    end
end

-- ============================================================
-- Action executors
-- ============================================================
local ZONES = {"Office","Security","Testing","LCZ","HCZ"}

local function pickZoneWithButtons()
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

local function pickEntityForBreach()
    ui.bigStatus(term.current(), {"LOADING ENTITIES..."}, "working")
    local reply = proto.request(MAINFRAME, "entity_list_by_card", {diskID=state.diskID}, 3)
    if not reply or not reply.ok then
        ui.bigStatus(term.current(), {"FAILED",  "", (reply and reply.reason or "NO RESPONSE"):upper()}, "error")
        sleep(2); return nil
    end
    -- Filter out already-breached
    local candidates = {}
    for _, e in ipairs(reply.entities) do
        if e.status ~= "breached" and e.status ~= "decommissioned" and e.status ~= "deceased" then
            candidates[#candidates+1] = e
        end
    end
    if #candidates == 0 then
        ui.bigStatus(term.current(), {"NO CONTAINED","","ENTITIES"}, "idle"); sleep(1.5); return nil
    end

    ui.clear(term.current())
    ui.header(term.current(), "SELECT ENTITY TO BREACH")
    local labels = {}
    for i, e in ipairs(candidates) do
        labels[i] = string.format("%s  %s  (%s)", e.entityId, e.name, e.zone)
    end
    local buttons = ui.buttonGrid(term.current(), labels, {startY=5, cols=1, btnH=2, hotkeys=true})
    local _, h = term.getSize()
    local cancel = ui.drawButton(term.current(), 2, h - 3, select(1, term.getSize()) - 2, 2,
        "CANCEL", {fg=ui.DIM, hotkey="x"})
    table.insert(buttons, cancel)
    local idx = ui.clickMenu(buttons)
    if idx and idx <= #candidates then return candidates[idx] end
    return nil
end

local function pickActiveBreachToEnd()
    if #state.breaches == 0 then
        ui.bigStatus(term.current(), {"NO ACTIVE","BREACHES"}, "idle"); sleep(1.5); return nil
    end
    ui.clear(term.current())
    ui.header(term.current(), "END WHICH BREACH?")
    local labels = {}
    for i, b in ipairs(state.breaches) do
        labels[i] = b.scpId.." @ "..b.zone
    end
    local buttons = ui.buttonGrid(term.current(), labels, {startY=5, cols=1, btnH=2, hotkeys=true})
    local _, h = term.getSize()
    local cancel = ui.drawButton(term.current(), 2, h - 3, select(1, term.getSize()) - 2, 2,
        "CANCEL", {fg=ui.DIM, hotkey="x"})
    table.insert(buttons, cancel)
    local idx = ui.clickMenu(buttons)
    if idx and idx <= #state.breaches then return state.breaches[idx] end
    return nil
end

local function executeAction(actionDef)
    local args = {}
    if actionDef.key == "declare_breach" then
        local ent = pickEntityForBreach()
        if not ent then return end
        args.entityId = ent.entityId
    elseif actionDef.key == "end_breach" then
        local b = pickActiveBreachToEnd()
        if not b then return end
        args.entityId = b.scpId
    elseif actionDef.picks == "zone" then
        local z = pickZoneWithButtons()
        if not z then return end
        args.zone = z
    end

    ui.bigStatus(term.current(), {"TRANSMITTING..."}, "working")
    local reply = proto.request(MAINFRAME, "action_command", {
        diskID = state.diskID,
        action = actionDef.key,
        args = args,
    }, 4)
    if not reply then
        ui.bigStatus(term.current(), {"MAINFRAME","UNREACHABLE"}, "error"); sleep(2); return
    elseif not reply.ok then
        ui.bigStatus(term.current(), {"ACTION DENIED", "", (reply.reason or "?"):upper()}, "denied"); sleep(2); return
    else
        if actionDef.key == "view_status" then
            -- Display facility status screen
            ui.clear(term.current())
            ui.header(term.current(), "FACILITY STATUS")
            term.setCursorPos(2, 5); term.setTextColor(ui.FG); term.write("Facility state: ")
            local stateColor = ({normal=ui.OK, caution=ui.WARN, warning=ui.WARN, lockdown=ui.ERR, breach=ui.ERR})[reply.facility.state] or ui.FG
            term.setTextColor(stateColor); term.write(reply.facility.state:upper())
            local y = 7
            term.setCursorPos(2, y); term.setTextColor(ui.FG); term.write("Zones:")
            for _, zn in ipairs(ZONES) do
                y = y + 1
                local z = reply.zones[zn] or {}
                term.setCursorPos(4, y); term.setTextColor(ui.ACCENT); term.write(string.format("%-10s ", zn))
                if z.lockdown then term.setTextColor(ui.ERR); term.write("[LOCKDOWN]")
                else term.setTextColor(ui.OK); term.write("[normal]  ") end
                local occ = #(z.occupants or {})
                if occ > 0 then term.setTextColor(ui.DIM); term.write("  "..occ.." in zone") end
            end
            y = y + 2
            if #reply.breaches > 0 then
                term.setCursorPos(2, y); term.setTextColor(ui.ERR); term.write("ACTIVE BREACHES:")
                for _, b in ipairs(reply.breaches) do
                    y = y + 1
                    term.setCursorPos(4, y); term.setTextColor(ui.ERR); term.write(b.scpId.." @ "..b.zone)
                end
            end
            local _, h = term.getSize()
            local btn = ui.drawButton(term.current(), 2, h - 3, select(1, term.getSize()) - 2, 2,
                "OK", {hotkey="enter"})
            ui.clickMenu({btn})
        else
            ui.bigStatus(term.current(), {"EXECUTED", "", reply.effect or "OK"}, "granted")
            sleep(2)
        end
    end
end

-- ============================================================
-- Main loop (single event pump to avoid rednet races)
-- ============================================================
announce()
state.registered = true  -- optimistic; will be corrected on first action if wrong
render()

local pollTimer = os.startTimer(5)
local panicState = false

while true do
    local menuBtns, menuActions = render()
    local evt = {os.pullEvent()}
    local etype = evt[1]

    if etype == "disk" then
        local id = drive.getDiskID()
        if id then
            state.diskID = id
            -- Fetch a lightweight status-view to verify the card and learn clearance.
            -- We use action_command view_status since it's always allowed for any valid card.
            local reply = proto.request(MAINFRAME, "action_command", {
                diskID=id, action="view_status"
            }, 3)
            if reply and reply.ok and reply.person then
                state.session = reply.person
                state.facility = reply.facility and reply.facility.state or state.facility
                state.breaches = reply.breaches or {}
                if reply.zones and reply.zones[ZONE] then
                    state.zoneLock = reply.zones[ZONE].lockdown
                end
            else
                local reason = reply and reply.reason or "no_response"
                ui.bigStatus(term.current(), {"CARD REJECTED", "", reason:upper()}, "denied")
                sleep(2)
                state.diskID = nil; state.session = nil
            end
        end

    elseif etype == "disk_eject" then
        state.diskID = nil; state.session = nil

    elseif etype == "timer" and evt[2] == pollTimer then
        -- Passive poll to sync facility state when idle
        if not state.session then
            local reply = proto.request(MAINFRAME, "announce", {
                type="action", hostname=LABEL,
            }, 1)
            if reply and reply.ok and reply.known then
                state.registered = true
            end
        end
        pollTimer = os.startTimer(5)

    elseif etype == "redstone" and PANIC_SIDE then
        -- Panic button edge-trigger
        local currentSignal = redstone.getInput(PANIC_SIDE)
        if currentSignal and not panicState then
            panicState = true
            ui.bigStatus(term.current(), {">>> PANIC BUTTON <<<", "", "ALERTING..."}, "error")
            proto.request(MAINFRAME, "panic_button", {}, 2)
            sleep(2)
        elseif not currentSignal then
            panicState = false
        end

    elseif etype == "rednet_message" then
        -- Lockdown / alert push from mainframe
        local senderID, message, proto_name = evt[2], evt[3], evt[4]
        if proto_name == proto.PROTOCOL and type(message) == "table"
           and message.from == MAINFRAME and message.type == "facility_alert" then
            local payload = message.payload or {}
            state.facility = payload.state or state.facility
            if payload.zones and payload.zones[ZONE] then
                state.zoneLock = payload.zones[ZONE].lockdown
            end
            state.breaches = payload.breaches or state.breaches
        end

    elseif (etype == "mouse_click" or etype == "monitor_touch" or etype == "char") and state.session and menuBtns then
        -- Figure out which menu button got clicked
        local cx, cy
        if etype == "mouse_click" then cx, cy = evt[3], evt[4]
        elseif etype == "monitor_touch" then cx, cy = evt[3], evt[4]
        end
        if etype == "char" then
            local key = evt[2]:lower()
            for i, btn in ipairs(menuBtns) do
                if btn.hotkey and btn.hotkey:lower() == key and i <= #menuActions then
                    executeAction(menuActions[i]); break
                end
            end
        elseif cx then
            for i, btn in ipairs(menuBtns) do
                if ui.hit(btn, cx, cy) and i <= #menuActions then
                    executeAction(menuActions[i]); break
                end
            end
        end
    end
end

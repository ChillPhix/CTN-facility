-- terminals/pocket.lua
-- C.T.N PORTABLE COMMAND TABLET
--
-- THE tablet. Full facility control from your pocket.
-- Requires PIN authentication on every boot.
-- Clearance-gated menu: what you see depends on who you are.
--
-- Features:
--   - Facility status view (zones, breaches, entities)
--   - Radio system (send/receive broadcasts, channel-filtered)
--   - Remote door control (open any door you have clearance for)
--   - Zone lockdown / unlock
--   - Declare / end breach
--   - Entity status changes
--   - Facility state control
--   - Personnel lookup
--   - View audit log
--   - Emergency panic broadcast
--
-- Requires: pocket computer (has built-in wireless modem)
-- PIN is set per-person via radmin (field: pin)

package.path = package.path .. ";/lib/?.lua"
local proto = require("ctnproto")
local ui    = require("ctnui")
local cfg   = require("ctnconfig")

local myCfg = cfg.loadOrWizard("pocket", {
    {key="mainframe_id", prompt="Mainframe computer ID", type="number", default=1},
})

proto.openModem()
ui.bootIdentity()
local MAINFRAME = myCfg.mainframe_id
local function getZones()
    local z = {}
    for name in pairs(status.zones or {}) do z[#z+1] = name end
    table.sort(z)
    if #z == 0 then z = {"(no zones)"} end
    return z
end

-- ============================================================
-- Session (wiped on every boot = every time you open the tablet)
-- ============================================================
local session = {
    authed   = false,
    person   = nil,   -- {name, clearance, department, ...}
    pin      = nil,
}

-- Radio message buffer (kept in memory for this session)
local radioLog = {}
local MAX_RADIO = 50

-- Status cache
local status = {
    facility = {state="normal"},
    zones = {},
    breaches = {},
    entities = {},
    recentLog = {},
    doors = {},
    lastUpdate = 0,
}

-- ============================================================
-- Network helpers
-- ============================================================
local function sendCmd(action, args)
    -- Route through tablet_request with PIN auth instead of facility_command
    return tabletRequest(action, args or {})
end

local function tabletRequest(action, payload)
    payload = payload or {}
    payload.action = action
    payload.pin = session.pin
    payload.operatorName = session.person and session.person.name or "?"
    return proto.request(MAINFRAME, "tablet_request", payload, 4)
end

local function refreshStatus()
    local reply = proto.request(MAINFRAME, "status_request", {}, 2)
    if reply and reply.ok then
        status.facility  = reply.facility or status.facility
        status.zones     = reply.zones or {}
        status.breaches  = reply.breaches or {}
        status.recentLog = reply.recentLog or {}
        status.lastUpdate = os.epoch("utc")
        ui.syncIdentity(reply)
    end
    -- Entities
    local er = tabletRequest("list_entities")
    if er and er.ok then status.entities = er.entities or {} end
    -- Doors
    local dr = tabletRequest("list_doors")
    if dr and dr.ok then status.doors = dr.doors or {} end
end

-- ============================================================
-- PIN Login
-- ============================================================
local function login()
    while true do
        ui.clear(term.current())
        local w, h = term.getSize()

        -- Header
        term.setCursorPos(1, 1); term.setBackgroundColor(ui.FG); term.setTextColor(ui.BG)
        term.write(string.rep(" ", w))
        local title = "C.T.N TABLET"
        term.setCursorPos(math.max(1, math.floor((w - #title)/2)+1), 1); term.write(title)
        term.setBackgroundColor(ui.BG); term.setTextColor(ui.FG)

        term.setCursorPos(1, 2); term.setTextColor(ui.BORDER)
        term.write(string.rep("=", w))

        -- Login box
        local bx, by, bw, bh = 2, 4, w - 2, 9
        ui.box(term.current(), bx, by, bw, bh, ui.BORDER)

        term.setCursorPos(bx + 2, by + 1); term.setTextColor(ui.WARN)
        term.write("SECURE TERMINAL")
        term.setCursorPos(bx + 2, by + 3); term.setTextColor(ui.FG)
        term.write("Operator: ")
        term.setTextColor(ui.ACCENT)
        local name = read()

        term.setCursorPos(bx + 2, by + 5); term.setTextColor(ui.FG)
        term.write("PIN: ")
        term.setTextColor(ui.ACCENT)
        local pin = read("*")

        -- Authenticate via mainframe
        ui.bigStatus(term.current(), {"AUTHENTICATING..."}, "working")
        local reply = proto.request(MAINFRAME, "tablet_auth", {
            operatorName = name,
            pin = pin,
        }, 4)

        if not reply then
            ui.bigStatus(term.current(), {"MAINFRAME","UNREACHABLE"}, "error")
            sleep(2)
        elseif reply.ok then
            session.authed = true
            session.person = reply.person
            session.pin = pin
            ui.bigStatus(term.current(), {
                "ACCESS GRANTED", "",
                reply.person.name,
                "L"..reply.person.clearance.."  "..reply.person.department,
            }, "granted")
            sleep(1)
            return true
        else
            ui.bigStatus(term.current(), {
                "ACCESS DENIED", "",
                (reply.reason or "bad_pin"):upper(),
            }, "denied")
            sleep(2)
        end
    end
end

-- ============================================================
-- Menu helpers (adapted for pocket computer's small screen)
-- Pocket computers are 26x20 characters
-- ============================================================
local function smallHeader(title)
    local w = term.getSize()
    term.setCursorPos(1, 1); term.setBackgroundColor(ui.FG); term.setTextColor(ui.BG)
    term.write(string.rep(" ", w))
    term.setCursorPos(math.max(1, math.floor((w - #title)/2)+1), 1)
    term.write(title:sub(1, w))
    term.setBackgroundColor(ui.BG); term.setTextColor(ui.FG)
    term.setCursorPos(1, 2); term.setTextColor(ui.BORDER)
    term.write(string.rep("-", w))
end

local function smallFooter(text)
    local w, h = term.getSize()
    term.setCursorPos(1, h); term.setBackgroundColor(ui.FG); term.setTextColor(ui.BG)
    term.write(string.rep(" ", w))
    term.setCursorPos(1, h); term.write((text or ""):sub(1, w))
    term.setBackgroundColor(ui.BG); term.setTextColor(ui.FG)
end

local function scrollList(title, items, footer)
    local selected, top = 1, 1
    while true do
        ui.clear(term.current())
        smallHeader(title)
        local w, h = term.getSize()
        local rows = h - 4
        top = math.max(1, math.min(top, math.max(1, #items - rows + 1)))

        if #items == 0 then
            term.setCursorPos(2, 4); term.setTextColor(ui.DIM)
            term.write("(empty)")
        else
            for row = 1, rows do
                local idx = top + row - 1
                local item = items[idx]
                if not item then break end
                local y = 2 + row
                term.setCursorPos(1, y)
                if idx == selected then
                    term.setBackgroundColor(ui.FG); term.setTextColor(ui.BG)
                else
                    term.setBackgroundColor(ui.BG); term.setTextColor(item.color or ui.FG)
                end
                local line = (idx == selected and ">" or " ") .. " " .. (item.label or "?")
                term.write(line:sub(1, w))
                term.write(string.rep(" ", math.max(0, w - #line)))
                term.setBackgroundColor(ui.BG)
            end
        end

        smallFooter(footer or "ENTER=select  Q=back")

        local evt = {os.pullEvent()}
        if evt[1] == "key" then
            local key = evt[2]
            if key == keys.up and selected > 1 then
                selected = selected - 1
                if selected < top then top = selected end
            elseif key == keys.down and selected < #items then
                selected = selected + 1
                if selected >= top + rows then top = top + 1 end
            elseif key == keys.enter and items[selected] then
                return selected, items[selected]
            elseif key == keys.q or key == keys.backspace then
                return nil
            end
        elseif evt[1] == "mouse_click" then
            local x, y = evt[3], evt[4]
            local idx = top + (y - 3)
            if idx >= 1 and idx <= #items then
                return idx, items[idx]
            end
        elseif evt[1] == "mouse_scroll" then
            top = math.max(1, math.min(math.max(1, #items - rows + 1), top + evt[2]))
        end
    end
end

local function confirm(msg)
    ui.clear(term.current())
    smallHeader("CONFIRM")
    local w = term.getSize()
    term.setCursorPos(2, 4); term.setTextColor(ui.WARN)
    term.write(msg:sub(1, w - 2))
    term.setCursorPos(2, 6); term.setTextColor(ui.FG)
    term.write("Type YES: "); term.setTextColor(ui.ACCENT)
    return read() == "YES"
end

local function showResult(reply, success)
    if not reply then
        ui.bigStatus(term.current(), {"MAINFRAME","UNREACHABLE"}, "error")
    elseif reply.ok then
        ui.bigStatus(term.current(), {success or "OK"}, "granted")
    else
        ui.bigStatus(term.current(), {"FAILED","",tostring(reply.reason or "?"):upper()}, "denied")
    end
    sleep(1.5)
end

local function pickZone()
    local items = {}
    for _, z in ipairs(getZones()) do
        items[#items+1] = {label=z, value=z}
    end
    local idx = scrollList("SELECT ZONE", items)
    if idx then return items[idx].value end
    return nil
end

-- ============================================================
-- Feature: View Status
-- ============================================================
local function viewStatus()
    refreshStatus()
    ui.clear(term.current())
    smallHeader("FACILITY STATUS")
    local w, h = term.getSize()
    local y = 3

    -- State
    local st = status.facility.state or "normal"
    local col = ({normal=ui.OK, warning=ui.WARN, caution=ui.WARN,
                  breach=ui.ERR, lockdown=ui.ERR})[st] or ui.FG
    term.setCursorPos(2, y); term.setTextColor(ui.DIM); term.write("State: ")
    term.setTextColor(col); term.write(st:upper())
    y = y + 2

    -- Zones
    for _, zn in ipairs(getZones()) do
        if y >= h - 2 then break end
        local z = status.zones[zn] or {}
        local occ = z.occupants and #z.occupants or 0
        term.setCursorPos(2, y)
        if z.lockdown then
            term.setTextColor(ui.ERR); term.write("[X]")
        else
            term.setTextColor(ui.OK); term.write("[O]")
        end
        term.setTextColor(ui.FG); term.write(" "..zn)
        term.setTextColor(ui.DIM); term.write(" ("..occ..")")
        y = y + 1
    end
    y = y + 1

    -- Breaches
    if #status.breaches > 0 then
        term.setCursorPos(2, y); term.setTextColor(ui.ERR)
        term.write("BREACHES:")
        y = y + 1
        for _, b in ipairs(status.breaches) do
            if y >= h - 1 then break end
            term.setCursorPos(3, y); term.setTextColor(ui.ERR)
            term.write(b.scpId.." @"..b.zone)
            y = y + 1
        end
    end

    smallFooter("Any key to return")
    os.pullEvent("key")
end

-- ============================================================
-- Feature: Radio
-- ============================================================
local function addRadio(from, msg, channel)
    radioLog[#radioLog+1] = {
        ts = os.epoch("utc"),
        from = from,
        msg = msg,
        channel = channel or "ALL",
    }
    while #radioLog > MAX_RADIO do table.remove(radioLog, 1) end
end

local function radioView()
    local w, h = term.getSize()
    local scroll = 0
    local inputMode = false

    while true do
        ui.clear(term.current())
        smallHeader("RADIO // "..session.person.name)

        -- Show messages
        local msgArea = h - 4
        local startIdx = math.max(1, #radioLog - msgArea - scroll + 1)
        local y = 3
        for i = startIdx, math.min(#radioLog, startIdx + msgArea - 1) do
            local r = radioLog[i]
            if r and y < h - 1 then
                local ts = os.date("%H:%M", (r.ts or 0) / 1000)
                local chanTag = r.channel ~= "ALL" and ("["..r.channel.."] ") or ""
                term.setCursorPos(1, y); term.setTextColor(ui.DIM)
                term.write(ts.." ")
                term.setTextColor(ui.ACCENT)
                term.write((r.from or "?"):sub(1, 8)..": ")
                term.setTextColor(ui.FG)
                term.write((chanTag..tostring(r.msg)):sub(1, w - 16))
                y = y + 1
            end
        end

        -- Input bar
        term.setCursorPos(1, h - 1); term.setTextColor(ui.BORDER)
        term.write(string.rep("-", w))
        smallFooter("T=type  Q=back  R=refresh")

        local evt = {os.pullEvent()}
        if evt[1] == "key" then
            local key = evt[2]
            if key == keys.q or key == keys.backspace then return
            elseif key == keys.t then
                -- Type a message
                term.setCursorPos(1, h - 1); term.setBackgroundColor(ui.BG)
                term.setTextColor(ui.FG); term.write(string.rep(" ", w))
                term.setCursorPos(1, h - 1); term.write("> ")
                term.setTextColor(ui.ACCENT)
                local msg = read()
                if msg and msg ~= "" then
                    -- Send via mainframe
                    local reply = tabletRequest("radio_send", {
                        message = msg,
                        channel = "ALL",
                    })
                    if reply and reply.ok then
                        addRadio(session.person.name, msg, "ALL")
                    end
                end
            elseif key == keys.r then
                -- Pull recent radio from mainframe
                local reply = tabletRequest("radio_history")
                if reply and reply.ok and reply.messages then
                    for _, m in ipairs(reply.messages) do
                        -- Dedupe by timestamp
                        local isDupe = false
                        for _, existing in ipairs(radioLog) do
                            if existing.ts == m.ts and existing.from == m.from then
                                isDupe = true; break
                            end
                        end
                        if not isDupe then addRadio(m.from, m.msg, m.channel) end
                    end
                end
            elseif key == keys.up then
                scroll = math.min(scroll + 1, math.max(0, #radioLog - (h - 4)))
            elseif key == keys.down then
                scroll = math.max(0, scroll - 1)
            end
        elseif evt[1] == "rednet_message" then
            -- Check for incoming radio broadcasts
            local message, pname = evt[3], evt[4]
            if pname == proto.PROTOCOL and type(message) == "table"
               and message.type == "radio_broadcast" and message.from == MAINFRAME then
                local p = message.payload or {}
                addRadio(p.from or "?", p.message or "", p.channel or "ALL")
            end
        end
    end
end

-- ============================================================
-- Feature: Remote Door Control
-- ============================================================
local function doorControl()
    refreshStatus()
    local items = {}
    for _, d in ipairs(status.doors or {}) do
        local lockIcon = ""
        local z = status.zones[d.zone] or {}
        if z.lockdown then lockIcon = " [LOCKED]" end
        items[#items+1] = {
            label = (d.name or d.id or "?"):sub(1, 12).." "..d.zone..lockIcon,
            door = d,
            color = z.lockdown and ui.ERR or ui.FG,
        }
    end
    if #items == 0 then
        ui.bigStatus(term.current(), {"NO DOORS","REGISTERED"}, "idle")
        sleep(1.5); return
    end

    local idx, item = scrollList("DOOR CONTROL", items, "ENTER=open  Q=back")
    if not idx then return end

    local door = item.door
    ui.bigStatus(term.current(), {"OPENING...","",(door.name or door.id or "?")}, "working")
    local reply = tabletRequest("remote_door_open", {
        doorId = door.id,
        computerId = door.computerId,
    })
    showResult(reply, "DOOR OPENED: "..(door.name or "?"))
end

-- ============================================================
-- Feature: Zone Lockdown / Unlock
-- ============================================================
local function zoneLockdown()
    local zone = pickZone()
    if not zone then return end
    if not confirm("LOCKDOWN "..zone.."?") then return end
    showResult(sendCmd("zone_lockdown", {zone=zone, issuedBy=session.person.name}),
        "LOCKDOWN: "..zone)
end

local function zoneUnlock()
    local zone = pickZone()
    if not zone then return end
    showResult(sendCmd("zone_unlock", {zone=zone, issuedBy=session.person.name}),
        "UNLOCKED: "..zone)
end

-- ============================================================
-- Feature: Declare / End Breach
-- ============================================================
local function declareBreach()
    refreshStatus()
    local items = {}
    for _, e in ipairs(status.entities) do
        if e.status ~= "breached" and e.status ~= "decommissioned" and e.status ~= "deceased" then
            items[#items+1] = {
                label = e.entityId.." "..e.class:sub(1,3).." @"..e.zone,
                entity = e,
            }
        end
    end
    if #items == 0 then
        ui.bigStatus(term.current(), {"NO ENTITIES","TO BREACH"}, "idle")
        sleep(1.5); return
    end
    local idx, item = scrollList("DECLARE BREACH", items)
    if not idx then return end
    if not confirm("BREACH "..item.entity.entityId.."?") then return end
    showResult(sendCmd("declare_breach", {
        scpId=item.entity.entityId, zone=item.entity.zone,
        issuedBy=session.person.name,
    }), "BREACH: "..item.entity.entityId)
end

local function endBreach()
    refreshStatus()
    if #status.breaches == 0 then
        ui.bigStatus(term.current(), {"NO ACTIVE","BREACHES"}, "idle")
        sleep(1.5); return
    end
    local items = {}
    for _, b in ipairs(status.breaches) do
        items[#items+1] = {label=b.scpId.." @ "..b.zone, breach=b, color=ui.ERR}
    end
    local idx, item = scrollList("END BREACH", items)
    if not idx then return end
    showResult(sendCmd("end_breach", {
        scpId=item.breach.scpId, issuedBy=session.person.name,
    }), "CONTAINED: "..item.breach.scpId)
end

-- ============================================================
-- Feature: Entity Status
-- ============================================================
local function entityStatus()
    refreshStatus()
    local items = {}
    for _, e in ipairs(status.entities) do
        local col = ({breached=ui.ERR, testing=ui.WARN, maintenance=ui.WARN,
                      contained=ui.OK})[e.status] or ui.FG
        items[#items+1] = {
            label = e.entityId.." ["..e.status.."]",
            entity = e, color = col,
        }
    end
    if #items == 0 then
        ui.bigStatus(term.current(), {"NO ENTITIES"}, "idle")
        sleep(1.5); return
    end
    local idx, item = scrollList("ENTITY STATUS", items)
    if not idx then return end

    local statuses = {"contained","testing","maintenance","decommissioned","deceased"}
    local statusItems = {}
    for _, s in ipairs(statuses) do statusItems[#statusItems+1] = {label=s} end
    local si = scrollList("SET: "..item.entity.entityId, statusItems)
    if not si then return end
    showResult(sendCmd("set_entity_status", {
        entityId=item.entity.entityId, status=statuses[si],
        issuedBy=session.person.name,
    }), item.entity.entityId.." -> "..statuses[si]:upper())
end

-- ============================================================
-- Feature: Facility State
-- ============================================================
local function facilityState()
    local states = {"normal","caution","warning","lockdown"}
    local items = {}
    for _, s in ipairs(states) do
        local col = ({normal=ui.OK, caution=ui.WARN, warning=ui.WARN, lockdown=ui.ERR})[s] or ui.FG
        items[#items+1] = {label=s:upper(), value=s, color=col}
    end
    local idx, item = scrollList("SET FACILITY STATE", items)
    if not idx then return end
    if item.value == "lockdown" and not confirm("FACILITY LOCKDOWN?") then return end
    showResult(sendCmd("set_state", {state=item.value, issuedBy=session.person.name}),
        "STATE: "..item.value:upper())
end

-- ============================================================
-- Feature: Audit Log
-- ============================================================
local function viewLog()
    refreshStatus()
    local items = {}
    local entries = status.recentLog or {}
    for i = #entries, math.max(1, #entries - 40), -1 do
        local e = entries[i]
        if e then
            local ts = os.date("%H:%M:%S", (e.ts or 0) / 1000)
            local col = ({security=ui.ERR, access=ui.WARN, admin=ui.OK,
                          facility=ui.ACCENT, docs=ui.FG, error=ui.ERR})[e.category] or ui.FG
            items[#items+1] = {
                label = ts.." "..(e.message or ""):sub(1, 30),
                color = col,
            }
        end
    end
    scrollList("AUDIT LOG", items, "Q=back  scroll=arrows")
end

-- ============================================================
-- Feature: Personnel Lookup
-- ============================================================
local function personnelLookup()
    ui.clear(term.current())
    smallHeader("PERSONNEL LOOKUP")
    term.setCursorPos(2, 4); term.setTextColor(ui.FG)
    term.write("Name: "); term.setTextColor(ui.ACCENT)
    local name = read()
    if not name or name == "" then return end

    local reply = tabletRequest("personnel_lookup", {name=name})
    if not reply or not reply.ok then
        ui.bigStatus(term.current(), {"NOT FOUND"}, "denied")
        sleep(1.5); return
    end

    local p = reply.person
    ui.clear(term.current())
    smallHeader("PERSONNEL FILE")
    local y = 3
    local w = term.getSize()
    local function line(label, val, col)
        if y >= 18 then return end
        term.setCursorPos(2, y); term.setTextColor(ui.DIM); term.write(label..": ")
        term.setTextColor(col or ui.FG); term.write(tostring(val or "?"):sub(1, w - #label - 4))
        y = y + 1
    end

    line("Name", p.name, ui.ACCENT)
    line("Clearance", "L"..p.clearance, ({[0]=ui.ERR,[1]=ui.ERR,[2]=ui.WARN,[3]=ui.WARN,[4]=ui.OK,[5]=ui.DIM})[p.clearance])
    line("Department", p.department)
    line("Status", p.status, p.status == "active" and ui.OK or ui.ERR)
    if p.flags and #p.flags > 0 then
        line("Flags", table.concat(p.flags, ", "))
    end

    smallFooter("Any key to return")
    os.pullEvent("key")
end

-- ============================================================
-- Feature: Emergency Panic
-- ============================================================
local function panicBroadcast()
    if not confirm("SEND PANIC ALERT?") then return end
    local reply = tabletRequest("panic_broadcast")
    showResult(reply, "PANIC ALERT SENT")
end

-- ============================================================
-- Main menu
-- ============================================================
local function buildMenu()
    local c = session.person.clearance
    local items = {}

    -- Everyone gets these
    items[#items+1] = {label="View Status",      action="status",    minC=5}
    items[#items+1] = {label="Radio",            action="radio",     minC=5}
    items[#items+1] = {label="View Audit Log",   action="log",       minC=4}

    -- L4+
    items[#items+1] = {label="Personnel Lookup", action="personnel", minC=4}

    -- L3+
    items[#items+1] = {label="Remote Door Open", action="doors",     minC=3}
    items[#items+1] = {label="Security Alert",   action="panic",     minC=3}

    -- L2+
    items[#items+1] = {label="Zone Lockdown",    action="lock",      minC=2}
    items[#items+1] = {label="Zone Unlock",      action="unlock",    minC=2}
    items[#items+1] = {label="Declare Breach",   action="breach",    minC=2}
    items[#items+1] = {label="End Breach",       action="endbreach", minC=2}
    items[#items+1] = {label="Entity Status",    action="entity",    minC=2}

    -- L1+
    items[#items+1] = {label="Facility State",   action="state",     minC=1}

    -- Always
    items[#items+1] = {label="Lock Tablet",      action="lock_tablet", minC=5}

    -- Filter by clearance
    local filtered = {}
    for _, item in ipairs(items) do
        if c <= item.minC then
            filtered[#filtered+1] = item
        end
    end
    return filtered
end

local ACTIONS = {
    status      = viewStatus,
    radio       = radioView,
    log         = viewLog,
    personnel   = personnelLookup,
    doors       = doorControl,
    panic       = panicBroadcast,
    lock        = zoneLockdown,
    unlock      = zoneUnlock,
    breach      = declareBreach,
    endbreach   = endBreach,
    entity      = entityStatus,
    state       = facilityState,
}

local function mainMenu()
    while session.authed do
        local menuItems = buildMenu()

        -- Draw
        ui.clear(term.current())
        local w, h = term.getSize()
        local st = status.facility.state or "normal"
        local stCol = ({normal=ui.OK, warning=ui.WARN, caution=ui.WARN,
                        breach=ui.ERR, lockdown=ui.ERR})[st] or ui.FG

        -- Header with state
        term.setCursorPos(1, 1); term.setBackgroundColor(stCol); term.setTextColor(ui.BG)
        term.write(string.rep(" ", w))
        local title = "CTN // "..st:upper()
        term.setCursorPos(math.max(1, math.floor((w - #title)/2)+1), 1); term.write(title)
        term.setBackgroundColor(ui.BG)

        term.setCursorPos(1, 2); term.setTextColor(ui.DIM)
        local sub = session.person.name.." L"..session.person.clearance
        term.setCursorPos(math.max(1, math.floor((w - #sub)/2)+1), 2); term.write(sub)

        -- Breach badge
        if #status.breaches > 0 then
            term.setCursorPos(1, 3); term.setBackgroundColor(ui.ERR); term.setTextColor(ui.BG)
            local badge = " "..#status.breaches.." BREACH"..(#status.breaches > 1 and "ES" or "").." "
            term.write(badge)
            term.setBackgroundColor(ui.BG)
        end

        -- Menu items
        local startY = #status.breaches > 0 and 4 or 3
        local rows = h - startY - 1
        local selected, top = 1, 1

        while true do
            -- Draw items
            for row = 1, rows do
                local idx = top + row - 1
                local item = menuItems[idx]
                local y = startY + row
                term.setCursorPos(1, y)
                if not item then
                    term.setBackgroundColor(ui.BG); term.write(string.rep(" ", w))
                elseif idx == selected then
                    term.setBackgroundColor(ui.FG); term.setTextColor(ui.BG)
                    local line = "> "..item.label
                    term.write(line:sub(1, w))
                    term.write(string.rep(" ", math.max(0, w - #line)))
                    term.setBackgroundColor(ui.BG)
                else
                    term.setBackgroundColor(ui.BG); term.setTextColor(ui.FG)
                    local line = "  "..item.label
                    term.write(line:sub(1, w))
                    term.write(string.rep(" ", math.max(0, w - #line)))
                end
            end

            smallFooter(os.date("%H:%M").."  "..session.person.name)

            local evt = {os.pullEvent()}
            if evt[1] == "key" then
                local key = evt[2]
                if key == keys.up and selected > 1 then
                    selected = selected - 1
                    if selected < top then top = selected end
                elseif key == keys.down and selected < #menuItems then
                    selected = selected + 1
                    if selected >= top + rows then top = top + 1 end
                elseif key == keys.enter and menuItems[selected] then
                    local action = menuItems[selected].action
                    if action == "lock_tablet" then
                        session.authed = false
                        return
                    end
                    local fn = ACTIONS[action]
                    if fn then
                        local ok, err = pcall(fn)
                        if not ok then
                            ui.bigStatus(term.current(), {"ERROR","",tostring(err):sub(1,20)}, "error")
                            sleep(2)
                        end
                    end
                    pcall(refreshStatus)
                    break  -- redraw main menu
                end
            elseif evt[1] == "mouse_click" then
                local y = evt[4]
                local idx = top + (y - startY) - 1
                if idx >= 1 and idx <= #menuItems then
                    selected = idx
                    local action = menuItems[selected].action
                    if action == "lock_tablet" then
                        session.authed = false
                        return
                    end
                    local fn = ACTIONS[action]
                    if fn then pcall(fn) end
                    pcall(refreshStatus)
                    break
                end
            elseif evt[1] == "mouse_scroll" then
                top = math.max(1, math.min(math.max(1, #menuItems - rows + 1), top + evt[2]))
            elseif evt[1] == "rednet_message" then
                -- Catch radio broadcasts in the background
                local message, pname = evt[3], evt[4]
                if pname == proto.PROTOCOL and type(message) == "table"
                   and message.type == "radio_broadcast" and message.from == MAINFRAME then
                    local p = message.payload or {}
                    addRadio(p.from or "?", p.message or "", p.channel or "ALL")
                end
            end
        end
    end
end

-- ============================================================
-- Boot loop — re-authenticate on every lock/reopen
-- ============================================================
while true do
    login()
    pcall(refreshStatus)
    mainMenu()
end

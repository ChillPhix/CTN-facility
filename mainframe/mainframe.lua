-- mainframe/mainframe.lua
-- CTN Mainframe Server.
-- Runs on the central mainframe. Handles all network traffic from the facility.
--
-- New in this version:
--  - Auto-discovery of new terminals (they announce, admin approves)
--  - Facility-wide lockdown / breach broadcasts
--  - Alarm node control (redstone siren pulses per zone)
--  - Player detector integration (zone occupancy tracking)
--  - Live status panel on the mainframe's own screen/monitor

package.path = package.path .. ";/lib/?.lua;/mainframe/?.lua"
local proto = require("ctnproto")
local ui    = require("ctnui")
local db    = require("db")

db.load()
proto.openModem()

-- Optional monitor for the mainframe status display
local monitor
for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "monitor" then
        monitor = peripheral.wrap(side)
        monitor.setTextScale(0.5)
        break
    end
end

-- ============================================================
-- Status panel drawer
-- ============================================================
local function drawStatus()
    local targets = { term.current() }
    if monitor then targets[#targets+1] = monitor end

    for _, t in ipairs(targets) do
        ui.clear(t)
        ui.header(t, "MAINFRAME // CLASSIFIED")
        local w, h = t.getSize()

        -- Left column: facility state
        t.setCursorPos(2, 5); t.setTextColor(ui.FG); t.write("FACILITY STATE:")
        t.setCursorPos(2, 6)
        local state = db.get().facility.state
        local stateColor = ({normal=ui.OK, caution=ui.WARN, warning=ui.WARN, lockdown=ui.ERR, breach=ui.ERR})[state] or ui.FG
        t.setTextColor(stateColor); t.write("   "..string.upper(state))

        -- Zone status
        t.setCursorPos(2, 8); t.setTextColor(ui.FG); t.write("ZONES:")
        local y = 9
        for _, zname in ipairs({"Office","Security","Testing","LCZ","HCZ"}) do
            if y < h - 4 then
                local z = db.get().zones[zname]
                t.setCursorPos(4, y); t.setTextColor(ui.DIM); t.write(zname..": ")
                if z.lockdown then
                    t.setTextColor(ui.ERR); t.write("LOCKDOWN")
                else
                    t.setTextColor(ui.OK); t.write("normal")
                end
                local occ = #(z.occupants or {})
                if occ > 0 then
                    t.setTextColor(ui.DIM); t.write("  ["..occ.." in zone]")
                end
                y = y + 1
            end
        end

        -- Active breaches
        local breaches = db.activeBreaches()
        if #breaches > 0 then
            y = y + 1
            if y < h - 3 then
                t.setCursorPos(2, y); t.setTextColor(ui.ERR); t.write("!! ACTIVE BREACHES !!")
                y = y + 1
            end
            for _, b in ipairs(breaches) do
                if y < h - 3 then
                    t.setCursorPos(4, y); t.setTextColor(ui.ERR); t.write(b.scpId.." @ "..b.zone)
                    y = y + 1
                end
            end
        end

        -- Pending approvals
        local pending = db.listPending()
        if #pending > 0 then
            y = y + 1
            if y < h - 3 then
                t.setCursorPos(2, y); t.setTextColor(ui.WARN)
                t.write(#pending.." TERMINAL(S) PENDING")
                y = y + 1
                t.setCursorPos(2, y); t.setTextColor(ui.DIM)
                t.write("Run 'admin' to approve")
            end
        end

        ui.footer(t, "ID#"..os.getComputerID().."  ONLINE  "..os.date("%H:%M:%S"))
    end
end

-- ============================================================
-- Handlers. Each returns a reply payload (or nil).
-- ============================================================
local handlers = {}

-- Door scanner: {diskID}
function handlers.auth_request(from, payload)
    local doorName, door = db.getDoorByTerminal(from)
    if not door then
        db.logFrom("security", "auth from unregistered terminal", from, {})
        return {granted=false, reason="unregistered_terminal"}
    end

    local person, diskOrErr = db.lookupDisk(payload.diskID)
    if not person then
        db.logFrom("access", "DENIED: bad disk", from, {
            door=doorName, diskID=payload.diskID, reason=diskOrErr
        })
        return {granted=false, reason=diskOrErr or "bad_disk"}
    end

    local ok, reason = db.checkAccess(person, door)
    db.logFrom("access", (ok and "GRANTED: " or "DENIED: ")..person.name.." @ "..doorName, from, {
        door=doorName, actor=person.name,
        clearance=person.clearance, department=person.department, reason=reason,
    })

    return {
        granted = ok, reason = reason,
        person = { name=person.name, clearance=person.clearance, department=person.department },
        door = { name=doorName, zone=door.zone },
    }
end

-- Auto-discovery: a new terminal on boot announces itself.
-- Payload: {type = "door"|"alarm"|"detector", hostname="label"}
function handlers.announce(from, payload)
    -- If already known, just acknowledge without re-pending.
    local data = db.get()
    if data.doors then
        for _, d in pairs(data.doors) do
            if d.terminalId == from then return {ok=true, known=true, kind="door"} end
        end
    end
    if data.alarms[from] then return {ok=true, known=true, kind="alarm"} end
    if data.detectors[from] then return {ok=true, known=true, kind="detector"} end
    if data.chambers[from] then return {ok=true, known=true, kind="chamber"} end
    if data.actions and data.actions[from] then return {ok=true, known=true, kind="action"} end
    if data.pending[from] then return {ok=true, pending=true} end

    -- Map "siren" to alarm type in the queue (same slot)
    local pType = payload.type
    if pType == "siren" then pType = "alarm" end

    -- Widgets are read-only; no approval needed, auto-acknowledge
    if pType == "widget" then
        return {ok=true, known=true, kind="widget"}
    end

    db.addPending(from, pType, payload.hostname)
    db.log("admin", "new terminal announced: "..pType, {from=from, hostname=payload.hostname})
    return {ok=true, pending=true}
end

-- Issuer: {passcode, diskID, playerName, clearance, department, issuedBy}
function handlers.issue_request(from, payload)
    if not db.checkPasscode("issuer", payload.passcode) then
        db.logFrom("security", "ISSUER: bad passcode", from, {attempted=payload.issuedBy or "?"})
        return {ok=false, reason="bad_passcode"}
    end

    local data = db.get()
    if not data.personnel[payload.playerName] then
        db.addPerson(payload.playerName, payload.clearance, payload.department, {})
        db.logFrom("admin", "person created: "..payload.playerName, from,
            {name=payload.playerName, by=payload.issuedBy})
    end

    local ok, err = db.issueDisk(payload.diskID, payload.playerName, payload.issuedBy)
    if not ok then return {ok=false, reason=err} end

    db.logFrom("admin", "card issued to "..payload.playerName.." by "..(payload.issuedBy or "?"), from, {
        diskID=payload.diskID, owner=payload.playerName, by=payload.issuedBy
    })
    return {ok=true}
end

-- Document terminal: {diskID, action, docId?}
function handlers.doc_request(from, payload)
    local person = db.lookupDisk(payload.diskID)
    if not person then return {ok=false, reason="bad_disk"} end

    if payload.action == "list" then
        db.logFrom("docs", "archive browsed by "..person.name, from,
            {actor=person.name, clearance=person.clearance})
        return {ok=true, docs=db.listDocuments(person.clearance),
                person={name=person.name, clearance=person.clearance}}
    elseif payload.action == "read" then
        local doc, err = db.getDocument(payload.docId, person.clearance)
        if not doc then
            db.logFrom("docs", "read denied: "..tostring(payload.docId).." to "..person.name, from,
                {actor=person.name, docId=payload.docId, reason=err})
            return {ok=false, reason=err}
        end
        db.logFrom("docs", "read: "..payload.docId.." by "..person.name, from,
            {actor=person.name, docId=payload.docId})
        return {ok=true, doc=doc}
    end
    return {ok=false, reason="unknown_action"}
end

-- ============================================================
-- Facility commands (control room)
-- Payload: {passcode, action, args?, issuedBy}
-- ============================================================
local function broadcastFacilityAlert()
    local d = db.get()
    proto.send(nil, "facility_alert", {
        state = d.facility.state,
        zones = d.zones,
        breaches = db.activeBreaches(),
    })
end

local function pulseAlarms(zone, pattern)
    -- pattern: "steady" | "pulse" | "off"
    -- Send a command to all alarms in the given zone (or all if zone=nil).
    local targets = zone and db.getAlarmsInZone(zone) or db.allAlarms()
    for _, computerId in ipairs(targets) do
        proto.send(computerId, "alarm_set", {pattern=pattern})
    end
end

local facilityActions = {}

facilityActions.zone_lockdown = function(args)
    db.setZoneLockdown(args.zone, true)
    db.log("facility", "zone lockdown ON", {zone=args.zone, by=args.issuedBy})
    pulseAlarms(args.zone, "lockdown")
    broadcastFacilityAlert()
end

facilityActions.zone_unlock = function(args)
    db.setZoneLockdown(args.zone, false)
    db.log("facility", "zone lockdown OFF", {zone=args.zone, by=args.issuedBy})
    pulseAlarms(args.zone, "allclear")
    broadcastFacilityAlert()
end

facilityActions.set_state = function(args)
    db.setFacilityState(args.state)
    db.log("facility", "facility state: "..args.state, {by=args.issuedBy})
    if args.state == "breach" or args.state == "lockdown" then
        pulseAlarms(nil, "breach")
    elseif args.state == "normal" then
        pulseAlarms(nil, "allclear")
    end
    broadcastFacilityAlert()
end

facilityActions.declare_breach = function(args)
    db.declareBreach(args.scpId, args.zone, args.issuedBy)
    db.log("facility", "BREACH: "..args.scpId.." in "..args.zone, {by=args.issuedBy})
    db.setFacilityState("breach")
    db.setZoneLockdown(args.zone, true)
    pulseAlarms(nil, "breach")
    db.setEntityStatus(args.scpId, "breached")
    local cid = db.getChamberByEntity(args.scpId)
    if cid then proto.send(cid, "chamber_alert", {status="breached"}) end
    broadcastFacilityAlert()
end

facilityActions.end_breach = function(args)
    db.endBreach(args.scpId)
    db.log("facility", "breach contained: "..args.scpId, {by=args.issuedBy})
    db.setEntityStatus(args.scpId, "contained")
    local cid = db.getChamberByEntity(args.scpId)
    if cid then proto.send(cid, "chamber_alert", {status="contained"}) end
    if #db.activeBreaches() == 0 then
        db.setFacilityState("normal")
        pulseAlarms(nil, "allclear")
    end
    broadcastFacilityAlert()
end

facilityActions.set_entity_status = function(args)
    db.setEntityStatus(args.entityId, args.status)
    db.log("facility", "entity status: "..args.entityId.." -> "..args.status, {by=args.issuedBy})
    local cid = db.getChamberByEntity(args.entityId)
    if cid then proto.send(cid, "chamber_alert", {status=args.status}) end
end

-- Read-only: control room can query the entity list without admin passcode.
facilityActions.list_entities = function(args)
    -- handler modifies the outer reply; we'll handle this specially below.
    return db.listEntities()
end

function handlers.facility_command(from, payload)
    if not db.checkPasscode("control", payload.passcode) then
        db.log("security", "CONTROL: bad passcode", {from=from})
        return {ok=false, reason="bad_passcode"}
    end
    local action = facilityActions[payload.action]
    if not action then return {ok=false, reason="unknown_action"} end

    -- Some actions return data, others don't
    local result = action(payload.args or {})
    if payload.action == "list_entities" then
        return {ok=true, entities=result}
    end
    return {ok=true}
end

-- Dashboard status poll (control room)
function handlers.status_request(from, payload)
    local data = db.get()
    return {
        ok=true,
        facility=data.facility,
        zones=data.zones,
        breaches=db.activeBreaches(),
        recentLog=db.readLog(15),
    }
end

-- Player detector report: {players = {"Bob","Alice"}}
function handlers.detector_report(from, payload)
    local zone = db.getDetectorZone(from)
    if not zone then
        -- unknown detector; silently ignore (will be logged if pending approval flow ran)
        return
    end
    db.updateZoneOccupants(zone, payload.players or {})
    return {ok=true}
end

-- Chamber terminal polls for its entity info.
-- Payload: {diskID?} (optional - if present, the caller is requesting procedures)
function handlers.chamber_info(from, payload)
    local chamber = db.getChamber(from)
    if not chamber then
        return {ok=false, reason="unregistered_chamber"}
    end
    if not chamber.entityId then
        return {ok=true, chamber=chamber, entity=nil}
    end
    local entity = db.getEntity(chamber.entityId)
    if not entity then
        return {ok=true, chamber=chamber, entity=nil}
    end

    -- Basic info is always shown. Procedures are clearance-gated if diskID provided.
    local publicView = {
        entityId    = entity.entityId,
        name        = entity.name,
        class       = entity.class,
        zone        = entity.zone,
        status      = entity.status,
        threat      = entity.threat,
        description = entity.description,
    }
    local result = {ok=true, chamber=chamber, entity=publicView}

    if payload.diskID then
        local person = db.lookupDisk(payload.diskID)
        if person and person.clearance <= entity.minClearance then
            result.procedures = entity.procedures
            result.viewer = {name=person.name, clearance=person.clearance}
            db.log("docs", "procedures read", {person=person.name, entity=entity.entityId})
        elseif person then
            result.viewer = {name=person.name, clearance=person.clearance}
            result.procedures_denied = true
        end
    end
    return result
end

-- Card-authenticated entity list for action terminals (L3+ only)
function handlers.entity_list_by_card(from, payload)
    local person = db.lookupDisk(payload.diskID)
    if not person then return {ok=false, reason="bad_card"} end
    if person.clearance > 3 then return {ok=false, reason="insufficient_clearance"} end
    return {ok=true, entities=db.listEntities(), person={name=person.name, clearance=person.clearance}}
end

-- ============================================================
-- Action terminal commands (card-swipe authenticated).
-- These are fired by facility-wide action terminals when personnel
-- swipe their ID and pick an action. Authorization is by the card
-- owner's clearance, NOT a passcode.
-- Payload: {diskID, action, args?}
-- ============================================================

-- Minimum clearance (LOWER = HIGHER access; e.g. 3 means L0-L3 allowed).
local ACTION_CLEARANCE = {
    view_status         = 5,   -- anyone with a valid card
    security_breach     = 4,   -- Security/Researcher+
    declare_breach      = 3,   -- Captain/Research Director+
    end_breach          = 2,   -- Director+
    zone_lockdown       = 3,   -- Captain+ can lockdown ANY zone from here
    zone_unlock         = 2,   -- Director+ can unlock
    facility_lockdown   = 1,   -- Ethical Board+
    facility_normal     = 1,   -- Ethical Board+
}

local function authorizeCard(diskID, action)
    local person = db.lookupDisk(diskID)
    if not person then return nil, "bad_card" end
    local required = ACTION_CLEARANCE[action]
    if not required then return nil, "unknown_action" end
    if person.clearance > required then return nil, "insufficient_clearance" end
    return person
end

function handlers.action_command(from, payload)
    local actionTerm = db.getActionTerminal(from)
    if not actionTerm then
        db.logFrom("security", "action from unregistered terminal", from, {})
        return {ok=false, reason="unregistered_terminal"}
    end

    local person, err = authorizeCard(payload.diskID, payload.action)
    if not person then
        db.logFrom("security", "action denied: "..payload.action, from,
            {reason=err, action=payload.action})
        return {ok=false, reason=err}
    end

    local meta = {
        action      = payload.action,
        actor       = person.name,
        clearance   = person.clearance,
        department  = person.department,
        terminal_zone = actionTerm.zone,
        terminal_label = actionTerm.label,
    }

    -- Execute the action
    if payload.action == "view_status" then
        local data = db.get()
        db.logFrom("action", "status viewed", from, meta)
        return {ok=true, facility=data.facility, zones=data.zones,
                breaches=db.activeBreaches(), person={name=person.name, clearance=person.clearance}}

    elseif payload.action == "security_breach" then
        -- Non-containment threat - hostile/intruder
        db.setFacilityState("warning")
        pulseAlarms(actionTerm.zone, "security")
        db.logFrom("facility", ">>> SECURITY BREACH <<< raised by "..person.name, from, meta)
        broadcastFacilityAlert()
        return {ok=true, effect="SECURITY BREACH RAISED"}

    elseif payload.action == "declare_breach" then
        -- Containment breach - needs entity ID
        if not payload.args or not payload.args.entityId then
            return {ok=false, reason="missing_entity"}
        end
        local entityId = payload.args.entityId
        local ent = db.getEntity(entityId)
        if not ent then return {ok=false, reason="unknown_entity"} end
        db.declareBreach(entityId, ent.zone, person.name)
        db.setFacilityState("breach")
        db.setZoneLockdown(ent.zone, true)
        db.setEntityStatus(entityId, "breached")
        pulseAlarms(nil, "breach")
        local cid = db.getChamberByEntity(entityId)
        if cid then proto.send(cid, "chamber_alert", {status="breached"}) end
        meta.entity = entityId
        db.logFrom("facility", ">>> CONTAINMENT BREACH <<< "..entityId.." by "..person.name, from, meta)
        broadcastFacilityAlert()
        return {ok=true, effect="BREACH DECLARED: "..entityId}

    elseif payload.action == "end_breach" then
        if not payload.args or not payload.args.entityId then
            return {ok=false, reason="missing_entity"}
        end
        db.endBreach(payload.args.entityId)
        db.setEntityStatus(payload.args.entityId, "contained")
        local cid = db.getChamberByEntity(payload.args.entityId)
        if cid then proto.send(cid, "chamber_alert", {status="contained"}) end
        if #db.activeBreaches() == 0 then
            db.setFacilityState("normal")
            pulseAlarms(nil, "allclear")
        end
        meta.entity = payload.args.entityId
        db.logFrom("facility", "breach contained: "..payload.args.entityId.." by "..person.name, from, meta)
        broadcastFacilityAlert()
        return {ok=true, effect="BREACH CONTAINED"}

    elseif payload.action == "zone_lockdown" then
        local zone = (payload.args and payload.args.zone) or actionTerm.zone
        db.setZoneLockdown(zone, true)
        pulseAlarms(zone, "lockdown")
        meta.zone_affected = zone
        db.logFrom("facility", "zone lockdown: "..zone.." by "..person.name, from, meta)
        broadcastFacilityAlert()
        return {ok=true, effect="LOCKDOWN: "..zone}

    elseif payload.action == "zone_unlock" then
        local zone = (payload.args and payload.args.zone) or actionTerm.zone
        db.setZoneLockdown(zone, false)
        pulseAlarms(zone, "allclear")
        meta.zone_affected = zone
        db.logFrom("facility", "zone unlock: "..zone.." by "..person.name, from, meta)
        broadcastFacilityAlert()
        return {ok=true, effect="UNLOCKED: "..zone}

    elseif payload.action == "facility_lockdown" then
        db.setFacilityState("lockdown")
        pulseAlarms(nil, "breach")
        db.logFrom("facility", ">>> FACILITY LOCKDOWN <<< by "..person.name, from, meta)
        broadcastFacilityAlert()
        return {ok=true, effect="FACILITY LOCKDOWN ACTIVE"}

    elseif payload.action == "facility_normal" then
        db.setFacilityState("normal")
        pulseAlarms(nil, "allclear")
        db.logFrom("facility", "facility restored to NORMAL by "..person.name, from, meta)
        broadcastFacilityAlert()
        return {ok=true, effect="FACILITY NORMAL"}
    end

    return {ok=false, reason="unknown_action"}
end

-- Panic button: a redstone-triggered action terminal fires this without a card.
-- It's hard-coded to security_breach severity so it can't be escalated without a swipe.
function handlers.panic_button(from, payload)
    local actionTerm = db.getActionTerminal(from)
    if not actionTerm then
        db.logFrom("security", "PANIC from unregistered terminal", from, {})
        return {ok=false, reason="unregistered_terminal"}
    end
    db.setFacilityState("warning")
    pulseAlarms(actionTerm.zone, "panic")
    db.logFrom("facility", ">>> PANIC BUTTON <<< at "..actionTerm.zone, from,
        {terminal_label=actionTerm.label, terminal_zone=actionTerm.zone})
    broadcastFacilityAlert()
    return {ok=true}
end

-- ============================================================
-- Remote admin commands
-- Payload: {passcode, action, args, issuedBy}
-- ============================================================
local adminActions = {}

adminActions.add_person = function(args)
    if not args.name or not args.clearance or not args.department then
        return {ok=false, reason="missing_args"}
    end
    db.addPerson(args.name, args.clearance, args.department, args.flags or {})
    return {ok=true}
end

adminActions.set_clearance = function(args)
    if db.setClearance(args.name, args.clearance) then return {ok=true} end
    return {ok=false, reason="not_found"}
end

adminActions.set_flag = function(args)
    if db.setFlag(args.name, args.flag, args.value) then return {ok=true} end
    return {ok=false, reason="not_found"}
end

adminActions.set_status = function(args)
    if db.setStatus(args.name, args.status) then return {ok=true} end
    return {ok=false, reason="not_found"}
end

adminActions.add_door = function(args)
    db.addDoor(args.doorName, args.terminalId, args.zone, args.minClearance, {
        requiredFlag = args.requiredFlag,
        requiredDepartments = args.requiredDepartments,
    })
    db.removePending(args.terminalId)
    return {ok=true}
end

adminActions.add_alarm = function(args)
    db.addAlarm(args.terminalId, args.zone)
    db.removePending(args.terminalId)
    return {ok=true}
end

adminActions.add_detector = function(args)
    db.addDetector(args.terminalId, args.zone)
    db.removePending(args.terminalId)
    return {ok=true}
end

adminActions.add_chamber = function(args)
    db.addChamber(args.terminalId, args.entityId, args.zone)
    db.removePending(args.terminalId)
    return {ok=true}
end

adminActions.add_action = function(args)
    db.addActionTerminal(args.terminalId, args.zone, args.label)
    db.removePending(args.terminalId)
    return {ok=true}
end

adminActions.list_actions = function()
    return {ok=true, actions=db.listActionTerminals()}
end

adminActions.add_entity = function(args)
    db.addEntity(args.entityId, {
        name=args.name, class=args.class, zone=args.zone,
        status=args.status, threat=args.threat,
        description=args.description, procedures=args.procedures,
        minClearance=args.minClearance,
    })
    return {ok=true}
end

adminActions.update_entity = function(args)
    if db.updateEntity(args.entityId, args.fields or {}) then return {ok=true} end
    return {ok=false, reason="not_found"}
end

adminActions.delete_entity = function(args)
    if db.deleteEntity(args.entityId) then return {ok=true} end
    return {ok=false, reason="not_found"}
end

adminActions.list_entities = function()
    return {ok=true, entities=db.listEntities()}
end

adminActions.get_entity = function(args)
    local e = db.getEntity(args.entityId)
    if not e then return {ok=false, reason="not_found"} end
    return {ok=true, entity=e}
end

adminActions.list_chambers = function()
    return {ok=true, chambers=db.listChambers()}
end

adminActions.reject_pending = function(args)
    db.removePending(args.terminalId)
    return {ok=true}
end

adminActions.revoke_disk = function(args)
    if db.revokeDisk(args.diskID) then return {ok=true} end
    return {ok=false, reason="not_found"}
end

adminActions.list_personnel = function()
    local out = {}
    for name, p in pairs(db.get().personnel) do
        out[#out+1] = {name=p.name, clearance=p.clearance, department=p.department, status=p.status}
    end
    return {ok=true, personnel=out}
end

adminActions.list_disks = function()
    local out = {}
    for id, d in pairs(db.get().disks) do
        out[#out+1] = {id=id, owner=d.owner, status=d.status, issuedBy=d.issuedBy}
    end
    return {ok=true, disks=out}
end

adminActions.list_doors = function()
    local out = {}
    for name, d in pairs(db.get().doors) do
        out[#out+1] = {
            name=name, terminalId=d.terminalId, zone=d.zone,
            minClearance=d.minClearance, requiredFlag=d.requiredFlag,
        }
    end
    return {ok=true, doors=out}
end

adminActions.list_pending = function()
    return {ok=true, pending=db.listPending()}
end

adminActions.set_passcode = function(args)
    db.setPasscode(args.which, args.code)
    return {ok=true}
end

adminActions.add_document = function(args)
    db.addDocument(args.id, args.title, args.folder, args.minClearance, args.body, args.author)
    return {ok=true}
end

adminActions.view_log = function(args)
    return {ok=true, log=db.readLog(args.n or 40)}
end

function handlers.admin_command(from, payload)
    if not db.checkPasscode("admin", payload.passcode) then
        db.log("security", "ADMIN: bad passcode", {from=from, attempted=payload.issuedBy or "?"})
        return {ok=false, reason="bad_passcode"}
    end
    local action = adminActions[payload.action]
    if not action then return {ok=false, reason="unknown_action"} end

    local ok, result = pcall(action, payload.args or {})
    if not ok then
        db.log("error", "admin crash: "..tostring(result), {action=payload.action})
        return {ok=false, reason="crash"}
    end

    if not payload.action:match("^list_") and payload.action ~= "view_log" then
        db.log("admin", "remote: "..payload.action, {by=payload.issuedBy})
    end
    return result
end

-- ============================================================
-- Main loop with parallel tasks
-- ============================================================
local function networkLoop()
    while true do
        local from, msgType, payload = proto.receive()
        if from then
            local handler = handlers[msgType]
            if handler then
                local ok, result = pcall(handler, from, payload)
                if ok and result then
                    proto.send(from, msgType.."_reply", result)
                elseif not ok then
                    db.log("error", "handler crash: "..tostring(result), {type=msgType, from=from})
                end
            else
                db.log("security", "unknown msg type", {from=from, type=msgType})
            end
        else
            if msgType and msgType ~= "timeout" then
                db.log("security", "rejected message: "..msgType, {})
            end
        end
    end
end

local function displayLoop()
    while true do
        pcall(drawStatus)
        sleep(1)
    end
end

local function persistenceLoop()
    -- Occasionally flush in-memory state (like occupancy) to disk.
    while true do
        sleep(30)
        pcall(db.save)
    end
end

drawStatus()
parallel.waitForAny(networkLoop, displayLoop, persistenceLoop)

-- terminals/radmin.lua
-- Remote admin terminal for CTN mainframe.
-- Handles personnel, doors, entities, chambers, pending-approval queue, logs.

package.path = package.path .. ";/lib/?.lua"
local proto = require("ctnproto")
local ui    = require("ctnui")
local cfg   = require("ctnconfig")

local myCfg = cfg.loadOrWizard("radmin", {
    {key="mainframe_id", prompt="Mainframe computer ID", type="number", default=1},
})

proto.openModem()
local MAINFRAME = myCfg.mainframe_id

local DEPARTMENTS = {"Security","Research","MTF","Medical","Admin","Janitor","Guest","Ethics","Director"}
local ZONES = {"Office","Security","Testing","LCZ","HCZ"}
local CLASSES = {"Safe","Euclid","Keter","Thaumiel","Apollyon","Neutralized"}
local ENTITY_STATUSES = {"contained","breached","testing","maintenance","decommissioned","deceased"}

local session = {passcode=nil, username=nil}

-- ============================================================
-- Network
-- ============================================================
local function sendAdmin(action, args)
    return proto.request(MAINFRAME, "admin_command", {
        passcode = session.passcode,
        issuedBy = session.username,
        action = action,
        args = args or {},
    }, 5)
end

-- ============================================================
-- UI helpers
-- ============================================================
local function pause()
    term.setCursorPos(2, select(2, term.getSize()) - 2)
    term.setTextColor(ui.DIM); write("[ press Enter ]")
    read()
end

local function section(title)
    ui.frame(term.current(), title, "REMOTE ADMIN")
    term.setCursorPos(2, 5)
end

local function pickFromList(title, list)
    ui.frame(term.current(), title, "")
    for i, v in ipairs(list) do
        term.setCursorPos(4, 4 + i)
        term.setTextColor(ui.DIM); write("["..i.."] ")
        term.setTextColor(ui.FG);  write(v)
    end
    term.setCursorPos(2, 5 + #list + 1)
    term.setTextColor(ui.FG); write("> "); term.setTextColor(ui.ACCENT)
    local n = tonumber(read())
    term.setTextColor(ui.FG)
    return list[n]
end

local function showResult(reply, successMsg)
    if not reply then
        ui.bigStatus(term.current(), {"MAINFRAME","UNREACHABLE"}, "error")
    elseif reply.ok then
        ui.bigStatus(term.current(), {successMsg or "OK"}, "granted")
    else
        ui.bigStatus(term.current(), {"FAILED","",string.upper(reply.reason or "?")}, "denied")
    end
    sleep(1.5)
end

local function promptBody(header)
    term.setTextColor(ui.DIM)
    print(header or "Enter text. End with '.' on its own line.")
    term.setTextColor(ui.FG)
    local lines = {}
    while true do
        local l = read()
        if l == "." then break end
        lines[#lines+1] = l
    end
    return table.concat(lines, "\n")
end

-- ============================================================
-- Login
-- ============================================================
local function login()
    while true do
        ui.frame(term.current(), "AUTHENTICATION", "REMOTE ADMIN CONSOLE")
        term.setCursorPos(2, 5); term.setTextColor(ui.WARN)
        print("Unauthorised access is a Class-3 offence.")
        term.setCursorPos(2, 7); term.setTextColor(ui.FG)
        local username = ui.prompt("Username: ")
        term.setCursorPos(2, 8)
        local passcode = ui.promptHidden("Admin passcode: ")
        session.passcode = passcode
        session.username = username
        ui.bigStatus(term.current(), {"AUTHENTICATING..."}, "working")
        local reply = sendAdmin("list_personnel", {})
        if not reply then
            ui.bigStatus(term.current(), {"MAINFRAME","UNREACHABLE"}, "error"); sleep(2)
        elseif reply.ok then
            ui.bigStatus(term.current(), {"ACCESS GRANTED","","Welcome, "..username}, "granted"); sleep(1)
            return
        else
            ui.bigStatus(term.current(), {"ACCESS DENIED","",(reply.reason or "?"):upper()}, "denied"); sleep(2)
        end
    end
end

-- ============================================================
-- Menu actions: Personnel
-- ============================================================
local menu = {}

menu.addPerson = function()
    section("ADD PERSONNEL")
    local name = ui.prompt("Player name: ")
    term.setCursorPos(2, 6); local clearance = tonumber(ui.prompt("Clearance (0-5): "))
    local dept = pickFromList("DEPARTMENT", DEPARTMENTS)
    showResult(sendAdmin("add_person", {name=name, clearance=clearance, department=dept}),
        "ADDED: "..name)
end

menu.setClearance = function()
    section("MODIFY CLEARANCE")
    local name = ui.prompt("Player name: ")
    term.setCursorPos(2, 6); local c = tonumber(ui.prompt("New clearance: "))
    showResult(sendAdmin("set_clearance", {name=name, clearance=c}), "UPDATED: "..name)
end

menu.setFlag = function()
    section("SET PERSONNEL FLAG")
    local name = ui.prompt("Player name: ")
    term.setCursorPos(2, 6); local flag = ui.prompt("Flag name: ")
    term.setCursorPos(2, 7); local val = ui.prompt("y/n: ") == "y"
    showResult(sendAdmin("set_flag", {name=name, flag=flag, value=val}), "FLAG SET")
end

menu.suspend = function()
    section("SUSPEND / REINSTATE")
    local name = ui.prompt("Player name: ")
    local status = pickFromList("STATUS", {"active","suspended","terminated"})
    showResult(sendAdmin("set_status", {name=name, status=status}), "UPDATED")
end

menu.listPersonnel = function()
    ui.bigStatus(term.current(), {"LOADING..."}, "working")
    local r = sendAdmin("list_personnel", {})
    if not r or not r.ok then return showResult(r) end
    ui.frame(term.current(), "PERSONNEL ROSTER", "")
    table.sort(r.personnel, function(a,b) return a.clearance < b.clearance end)
    local y, _, h = 4, nil, select(2, term.getSize())
    for _, p in ipairs(r.personnel) do
        if y > h - 2 then break end
        term.setCursorPos(2, y); term.setTextColor(ui.FG); write(string.format("L%d ", p.clearance))
        term.setTextColor(ui.ACCENT); write(string.format("%-14s ", p.name))
        term.setTextColor(ui.DIM);    write(string.format("%-10s ", p.department))
        local c = p.status == "active" and ui.OK or ui.ERR
        term.setTextColor(c); write("["..p.status.."]")
        y = y + 1
    end
    pause()
end

-- ============================================================
-- Menu actions: Cards & Doors
-- ============================================================
menu.revokeDisk = function()
    section("REVOKE ID CARD")
    local id = tonumber(ui.prompt("Disk ID: "))
    showResult(sendAdmin("revoke_disk", {diskID=id}), "REVOKED")
end

menu.listDisks = function()
    ui.bigStatus(term.current(), {"LOADING..."}, "working")
    local r = sendAdmin("list_disks", {})
    if not r or not r.ok then return showResult(r) end
    ui.frame(term.current(), "ID CARD REGISTRY", "")
    local y, _, h = 4, nil, select(2, term.getSize())
    for _, d in ipairs(r.disks) do
        if y > h - 2 then break end
        term.setCursorPos(2, y); term.setTextColor(ui.FG); write(string.format("#%-4d ", d.id))
        term.setTextColor(ui.ACCENT); write(string.format("%-14s ", d.owner))
        local c = d.status == "active" and ui.OK or ui.ERR
        term.setTextColor(c); write("["..d.status.."]")
        y = y + 1
    end
    pause()
end

menu.listDoors = function()
    local r = sendAdmin("list_doors", {})
    if not r or not r.ok then return showResult(r) end
    ui.frame(term.current(), "DOOR REGISTRY", "")
    local y, _, h = 4, nil, select(2, term.getSize())
    for _, d in ipairs(r.doors) do
        if y > h - 2 then break end
        term.setCursorPos(2, y); term.setTextColor(ui.ACCENT); write(string.format("%-22s ", d.name))
        term.setTextColor(ui.FG);     write(string.format("%-8s ", d.zone))
        term.setTextColor(ui.DIM);    write(string.format("L<=%d term#%d", d.minClearance, d.terminalId))
        y = y + 1
    end
    pause()
end

-- ============================================================
-- Approvals / pending queue
-- ============================================================
menu.approvePending = function()
    ui.bigStatus(term.current(), {"LOADING..."}, "working")
    local r = sendAdmin("list_pending", {})
    if not r or not r.ok then return showResult(r) end
    if #r.pending == 0 then
        ui.bigStatus(term.current(), {"NO PENDING","","TERMINALS"}, "idle"); sleep(1.5); return
    end

    -- Show list, pick one
    ui.frame(term.current(), "PENDING APPROVALS", tostring(#r.pending).." waiting")
    for i, p in ipairs(r.pending) do
        term.setCursorPos(2, 4 + i)
        term.setTextColor(ui.DIM); write("["..i.."] ")
        term.setTextColor(ui.FG);
        write(string.format("#%-4d %-10s %s", p.id, p.type, p.hostname or "?"))
    end
    term.setCursorPos(2, 5 + #r.pending + 1); term.setTextColor(ui.FG)
    write("Pick one to approve (or 0 to cancel): ")
    term.setTextColor(ui.ACCENT)
    local n = tonumber(read())
    if not n or n < 1 or n > #r.pending then return end
    local p = r.pending[n]

    -- Branch on terminal type
    if p.type == "door" then
        section("APPROVE DOOR #"..p.id)
        local doorName = ui.prompt("Door name (unique): ")
        local zone = pickFromList("ZONE", ZONES)
        section("APPROVE DOOR #"..p.id)
        term.setCursorPos(2, 5); local mc = tonumber(ui.prompt("Min clearance (0-5): "))
        term.setCursorPos(2, 6); local flag = ui.prompt("Required flag (blank): ")
        showResult(sendAdmin("add_door", {
            doorName=doorName, terminalId=p.id, zone=zone,
            minClearance=mc, requiredFlag = flag ~= "" and flag or nil,
        }), "DOOR APPROVED")
    elseif p.type == "alarm" or p.type == "siren" then
        local zone = pickFromList("SIREN ZONE", ZONES)
        showResult(sendAdmin("add_alarm", {terminalId=p.id, zone=zone}), "SIREN APPROVED")
    elseif p.type == "detector" then
        local zone = pickFromList("DETECTOR ZONE", ZONES)
        showResult(sendAdmin("add_detector", {terminalId=p.id, zone=zone}), "DETECTOR APPROVED")
    elseif p.type == "chamber" then
        section("APPROVE CHAMBER #"..p.id)
        local entityId = ui.prompt("Link to entity ID (e.g. CTN-001) [blank for none]: ")
        local zone = pickFromList("CHAMBER ZONE", ZONES)
        showResult(sendAdmin("add_chamber", {
            terminalId=p.id, entityId = entityId ~= "" and entityId or nil, zone=zone,
        }), "CHAMBER APPROVED")
    elseif p.type == "action" then
        section("APPROVE ACTION TERMINAL #"..p.id)
        local label = ui.prompt("Label (e.g. 'HCZ Guard Post'): ")
        local zone = pickFromList("ACTION TERMINAL ZONE", ZONES)
        showResult(sendAdmin("add_action", {
            terminalId=p.id, label=label, zone=zone,
        }), "ACTION TERMINAL APPROVED")
    else
        showResult(sendAdmin("reject_pending", {terminalId=p.id}), "REJECTED (unknown type)")
    end
end

-- ============================================================
-- Entities
-- ============================================================
menu.addEntity = function()
    section("REGISTER ENTITY")
    local id = ui.prompt("Entity ID (e.g. CTN-001): ")
    term.setCursorPos(2, 6); local name = ui.prompt("Name / designation: ")
    local class = pickFromList("OBJECT CLASS", CLASSES)
    section("REGISTER ENTITY: "..id)
    local zone = pickFromList("ZONE", ZONES)
    section("REGISTER ENTITY: "..id)
    term.setCursorPos(2, 5); local threat = tonumber(ui.prompt("Threat level (1-5): "))
    term.setCursorPos(2, 6); local mc = tonumber(ui.prompt("Min clearance for procedures (0-5): "))
    term.setCursorPos(2, 8); term.setTextColor(ui.ACCENT); print("Short description:")
    term.setCursorPos(2, 9); term.setTextColor(ui.FG)
    local desc = ui.prompt("")
    term.setCursorPos(2, 11); term.setTextColor(ui.ACCENT); print("Containment procedures (long).")
    term.setCursorPos(2, 12); term.setTextColor(ui.FG)
    local proc = promptBody()
    showResult(sendAdmin("add_entity", {
        entityId=id, name=name, class=class, zone=zone,
        threat=threat, minClearance=mc,
        description=desc, procedures=proc,
    }), "ENTITY REGISTERED: "..id)
end

menu.listEntities = function()
    local r = sendAdmin("list_entities", {})
    if not r or not r.ok then return showResult(r) end
    ui.frame(term.current(), "ENTITY REGISTRY", tostring(#r.entities).." contained")
    local y, _, h = 4, nil, select(2, term.getSize())
    for _, e in ipairs(r.entities) do
        if y > h - 2 then break end
        term.setCursorPos(2, y); term.setTextColor(ui.ACCENT); write(string.format("%-10s ", e.entityId))
        term.setTextColor(ui.FG); write(string.format("%-8s ", e.class))
        term.setTextColor(ui.DIM); write(string.format("%-6s ", e.zone))
        local c = ({contained=ui.OK, breached=ui.ERR, testing=ui.WARN, maintenance=ui.WARN})[e.status] or ui.FG
        term.setTextColor(c); write("["..e.status.."] ")
        term.setTextColor(ui.DIM); write("T"..(e.threat or "?"))
        y = y + 1
    end
    pause()
end

menu.editEntity = function()
    section("EDIT ENTITY")
    local id = ui.prompt("Entity ID: ")
    local r = sendAdmin("get_entity", {entityId=id})
    if not r or not r.ok then return showResult(r) end
    local e = r.entity
    section("EDITING "..id)
    term.setCursorPos(2, 5); term.setTextColor(ui.DIM)
    print("Leave blank to keep current value.")
    term.setCursorPos(2, 6); term.setTextColor(ui.FG)
    write("Name ["..e.name.."]: "); term.setTextColor(ui.ACCENT)
    local name = read(); term.setTextColor(ui.FG)
    term.setCursorPos(2, 7); write("Threat ["..e.threat.."]: "); term.setTextColor(ui.ACCENT)
    local threat = read(); term.setTextColor(ui.FG)
    term.setCursorPos(2, 8); write("Description ["..(e.description:sub(1,20)).."...]: "); term.setTextColor(ui.ACCENT)
    local desc = read(); term.setTextColor(ui.FG)
    term.setCursorPos(2, 10); term.setTextColor(ui.DIM)
    print("Update procedures? (y/n)")
    term.setTextColor(ui.FG); term.setCursorPos(2, 11); write("> ")
    local doProc = read()
    local fields = {}
    if name ~= "" then fields.name = name end
    if threat ~= "" then fields.threat = tonumber(threat) end
    if desc ~= "" then fields.description = desc end
    if doProc == "y" then
        section("NEW PROCEDURES")
        fields.procedures = promptBody()
    end
    showResult(sendAdmin("update_entity", {entityId=id, fields=fields}), "ENTITY UPDATED")
end

menu.deleteEntity = function()
    section("DELETE ENTITY")
    local id = ui.prompt("Entity ID: ")
    term.setCursorPos(2, 7); term.setTextColor(ui.ERR)
    write("Type YES to confirm: "); term.setTextColor(ui.ACCENT)
    if read() == "YES" then
        showResult(sendAdmin("delete_entity", {entityId=id}), "DELETED")
    end
end

-- ============================================================
-- Docs, passcodes, log
-- ============================================================
menu.addDocument = function()
    section("ADD DOCUMENT")
    local id = ui.prompt("ID: ")
    term.setCursorPos(2, 6); local title = ui.prompt("Title: ")
    term.setCursorPos(2, 7); local folder = ui.prompt("Folder: ")
    term.setCursorPos(2, 8); local mc = tonumber(ui.prompt("Min clearance: "))
    term.setCursorPos(2, 10); term.setTextColor(ui.DIM)
    print("Body (end with '.' alone):")
    term.setTextColor(ui.FG)
    local body = promptBody()
    showResult(sendAdmin("add_document", {
        id=id, title=title, folder=folder, minClearance=mc,
        body=body, author=session.username,
    }), "DOCUMENT SAVED")
end

menu.setPasscode = function()
    local which = pickFromList("WHICH PASSCODE", {"issuer","control","admin"})
    section("SET "..which:upper().." PASSCODE")
    local code = ui.promptHidden("New code: ")
    showResult(sendAdmin("set_passcode", {which=which, code=code}), "PASSCODE SET")
end

menu.viewLog = function()
    local r = sendAdmin("view_log", {n=40})
    if not r or not r.ok then return showResult(r) end
    ui.frame(term.current(), "SECURITY LOG", "MOST RECENT LAST")
    local _, h = term.getSize()
    local y = 4
    for _, e in ipairs(r.log) do
        if y > h - 2 then break end
        local t = os.date("%H:%M:%S", e.ts / 1000)
        term.setCursorPos(2, y); term.setTextColor(ui.DIM); write("["..t.."] ")
        local c = ({security=ui.ERR, access=ui.WARN, admin=ui.OK, facility=ui.ACCENT, docs=ui.FG, error=ui.ERR})[e.category] or ui.FG
        term.setTextColor(c); write(e.category:upper()..": ")
        term.setTextColor(ui.FG); write(tostring(e.message))
        y = y + 1
    end
    pause()
end

menu.logout = function()
    session.passcode = nil; session.username = nil
    ui.bigStatus(term.current(), {"SESSION ENDED"}, "idle"); sleep(1)
end

-- ============================================================
-- Main loop
-- ============================================================
login()

local options = {
    {"Add personnel",       menu.addPerson},
    {"Set clearance",       menu.setClearance},
    {"Set flag",            menu.setFlag},
    {"Suspend / reinstate", menu.suspend},
    {"List personnel",      menu.listPersonnel},
    {"Revoke ID card",      menu.revokeDisk},
    {"List ID cards",       menu.listDisks},
    {"List doors",          menu.listDoors},
    {"Approve pending",     menu.approvePending},
    {"Add entity",          menu.addEntity},
    {"List entities",       menu.listEntities},
    {"Edit entity",         menu.editEntity},
    {"Delete entity",       menu.deleteEntity},
    {"Add document",        menu.addDocument},
    {"Set passcode",        menu.setPasscode},
    {"View security log",   menu.viewLog},
    {"Log out",             function() menu.logout(); login() end},
}

while true do
    ui.frame(term.current(), "REMOTE ADMIN ["..session.username.."]", "C.T.N // CLASSIFIED")
    local labels = {}
    for i, o in ipairs(options) do labels[i] = o[1] end
    local choice = ui.menu(nil, labels, 5)
    if choice and options[choice] then
        local ok, err = pcall(options[choice][2])
        if not ok then
            ui.bigStatus(term.current(), {"ERROR","",tostring(err)}, "error"); sleep(2)
        end
    end
end

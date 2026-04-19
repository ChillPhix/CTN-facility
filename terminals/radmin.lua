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
ui.bootIdentity()
local MAINFRAME = myCfg.mainframe_id

local DEPARTMENTS = {"Security","Research","MTF","Medical","Admin","Janitor","Guest","Ethics","Director"}
local function getZones()
    local r = sendAdmin("list_zones", {})
    local zones = {}
    if type(r) == "table" then
        for _, z in ipairs(r) do
            if type(z) == "table" and z.name then zones[#zones+1] = z.name end
        end
    end
    table.sort(zones)
    if #zones == 0 then zones = {"(no zones)"} end
    return zones
end
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

local function scrollMenu(title, footer, options)
    local selected, top = 1, 1
    while true do
        ui.frame(term.current(), title, footer)
        local w, h = term.getSize()
        local listY = 5
        local rows = h - 8
        if rows < 3 then rows = 3 end

        top = math.max(1, math.min(top, math.max(1, #options - rows + 1)))
        selected = math.max(1, math.min(selected, #options))
        if selected < top then top = selected end
        if selected >= top + rows then top = selected - rows + 1 end

        term.setCursorPos(2, 4); term.setTextColor(ui.DIM)
        term.write("UP/DOWN move  ENTER select  Q logout")

        for row = 1, rows do
            local idx = top + row - 1
            local opt = options[idx]
            if not opt then break end
            local y = listY + row - 1
            local hotkey = row <= 9 and tostring(row) or nil
            local prefix = hotkey and ("["..hotkey.."] ") or "    "
            local text = prefix..opt[1]

            term.setCursorPos(2, y)
            if idx == selected then
                term.setBackgroundColor(ui.FG); term.setTextColor(ui.BG)
            else
                term.setBackgroundColor(ui.BG); term.setTextColor(ui.FG)
            end
            term.write(text:sub(1, w - 3))
            term.write(string.rep(" ", math.max(0, w - 2 - #text)))
            term.setBackgroundColor(ui.BG)
        end

        term.setCursorPos(2, h - 2); term.setTextColor(ui.DIM)
        local pageEnd = math.min(#options, top + rows - 1)
        term.write(("Showing "..top.."-"..pageEnd.." of "..#options):sub(1, w - 3))

        local event, key = os.pullEvent("key")
        if key == keys.up and selected > 1 then
            selected = selected - 1
        elseif key == keys.down and selected < #options then
            selected = selected + 1
        elseif key == keys.pageUp then
            selected = math.max(1, selected - rows)
        elseif key == keys.pageDown then
            selected = math.min(#options, selected + rows)
        elseif key == keys.home then
            selected = 1
        elseif key == keys["end"] then
            selected = #options
        elseif key == keys.enter then
            return selected
        elseif key == keys.q then
            return #options
        elseif key >= keys.one and key <= keys.nine then
            local row = key - keys.one + 1
            local idx = top + row - 1
            if options[idx] then return idx end
        end
    end
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

local function archivePathLabel(path)
    local parts = {}
    for _, p in ipairs(path or {}) do parts[#parts+1] = p.name end
    local s = table.concat(parts, " / ")
    if s == "" then s = "Departments" end
    return s
end

local function chooseArchiveFolder(title)
    local folderId = "root"
    while true do
        local r = sendAdmin("browse_archive", {folderId=folderId})
        if not r or not r.ok then showResult(r); return nil end
        local archive = r.archive
        ui.frame(term.current(), title or "SELECT ARCHIVE FOLDER", "0 = choose current")
        term.setCursorPos(2, 4); term.setTextColor(ui.DIM)
        term.write(archivePathLabel(archive.path):sub(1, select(1, term.getSize()) - 3))

        term.setCursorPos(2, 6); term.setTextColor(ui.ACCENT)
        term.write("[0] Use this folder")
        local y = 8
        local folders = archive.folders or {}
        for i, f in ipairs(folders) do
            term.setCursorPos(4, y)
            term.setTextColor(ui.DIM); write("["..i.."] ")
            term.setTextColor(ui.FG); write("[L"..(f.minClearance or 5).."] "..f.name)
            y = y + 1
            if y > select(2, term.getSize()) - 4 then break end
        end
        term.setCursorPos(2, select(2, term.getSize()) - 3); term.setTextColor(ui.DIM)
        write("B = parent, X = cancel")
        term.setCursorPos(2, select(2, term.getSize()) - 2); term.setTextColor(ui.FG)
        write("> "); term.setTextColor(ui.ACCENT)
        local choice = read()
        if choice == "0" then
            return archive.folder.id, archivePathLabel(archive.path)
        elseif choice:lower() == "x" then
            return nil
        elseif choice:lower() == "b" then
            folderId = archive.folder.parent or "root"
        else
            local n = tonumber(choice)
            if n and folders[n] then folderId = folders[n].id end
        end
    end
end

local function archiveItems(archive)
    local items = {}
    if archive.folder and archive.folder.parent then
        items[#items+1] = {kind="back", label="..", id=archive.folder.parent}
    end
    for _, f in ipairs(archive.folders or {}) do
        items[#items+1] = {kind="folder", label=f.name, id=f.id, minClearance=f.minClearance}
    end
    for _, d in ipairs(archive.documents or {}) do
        items[#items+1] = {kind="doc", label=d.title, id=d.id, minClearance=d.minClearance}
    end
    return items
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
            -- Sync facility identity
            local sr = proto.request(MAINFRAME, "status_request", {}, 2)
            ui.syncIdentity(sr)
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

menu.setPin = function()
    section("SET TABLET PIN")
    local name = ui.prompt("Player name: ")
    term.setCursorPos(2, 6)
    term.setTextColor(ui.DIM); print("PIN is used to login to pocket tablets.")
    term.setCursorPos(2, 7)
    local pin = ui.promptHidden("New PIN: ")
    if not pin or pin == "" then
        ui.bigStatus(term.current(), {"CANCELLED"}, "idle"); sleep(1); return
    end
    showResult(sendAdmin("set_pin", {name=name, pin=pin}), "PIN SET: "..name)
end

menu.setIdentity = function()
    section("SET FACILITY IDENTITY")
    local name = ui.prompt("Facility name (e.g. O.M.E.G.A): ")
    if name == "" then return end
    term.setCursorPos(2, 6)
    local subtitle = ui.prompt("Subtitle (e.g. RESEARCH DIVISION): ")
    if subtitle == "" then subtitle = "FACILITY SYSTEM" end
    local colorNames = ui.COLOR_NAMES
    local fgPick = pickFromList("PRIMARY COLOR (text/borders)", colorNames)
    if not fgPick then return end
    local bgPick = pickFromList("BACKGROUND COLOR", colorNames)
    if not bgPick then return end
    showResult(sendAdmin("set_identity", {
        name=name, subtitle=subtitle, fgColor=fgPick, bgColor=bgPick,
    }), "IDENTITY UPDATED")
    ui.applyIdentity({name=name, subtitle=subtitle, fgColor=fgPick, bgColor=bgPick})
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
        local zone = pickFromList("ZONE", getZones())
        section("APPROVE DOOR #"..p.id)
        term.setCursorPos(2, 5); local mc = tonumber(ui.prompt("Min clearance (0-5): "))
        term.setCursorPos(2, 6); local flag = ui.prompt("Required flag (blank): ")
        showResult(sendAdmin("add_door", {
            doorName=doorName, terminalId=p.id, zone=zone,
            minClearance=mc, requiredFlag = flag ~= "" and flag or nil,
        }), "DOOR APPROVED")
    elseif p.type == "alarm" or p.type == "siren" then
        local zone = pickFromList("SIREN ZONE", getZones())
        showResult(sendAdmin("add_alarm", {terminalId=p.id, zone=zone}), "SIREN APPROVED")
    elseif p.type == "detector" then
        local zone = pickFromList("DETECTOR ZONE", getZones())
        showResult(sendAdmin("add_detector", {terminalId=p.id, zone=zone}), "DETECTOR APPROVED")
    elseif p.type == "chamber" then
        section("APPROVE CHAMBER #"..p.id)
        local entityId = ui.prompt("Link to entity ID (e.g. CTN-001) [blank for none]: ")
        local zone = pickFromList("CHAMBER ZONE", getZones())
        showResult(sendAdmin("add_chamber", {
            terminalId=p.id, entityId = entityId ~= "" and entityId or nil, zone=zone,
        }), "CHAMBER APPROVED")
    elseif p.type == "action" then
        section("APPROVE ACTION TERMINAL #"..p.id)
        local label = ui.prompt("Label (e.g. 'HCZ Guard Post'): ")
        local zone = pickFromList("ACTION TERMINAL ZONE", getZones())
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
    local zone = pickFromList("ZONE", getZones())
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
menu.addFolder = function()
    local parentId, parentPath = chooseArchiveFolder("NEW FOLDER PARENT")
    if not parentId then return end
    section("CREATE ARCHIVE FOLDER")
    term.setCursorPos(2, 5); term.setTextColor(ui.DIM)
    term.write(parentPath:sub(1, select(1, term.getSize()) - 3))
    term.setCursorPos(2, 7); term.setTextColor(ui.FG)
    local name = ui.prompt("Folder name: ")
    term.setCursorPos(2, 8)
    local mc = tonumber(ui.prompt("Required clearance (0-5): "))
    showResult(sendAdmin("add_folder", {
        parentId=parentId, name=name, minClearance=mc, author=session.username,
    }), "FOLDER CREATED")
end

menu.addDocument = function()
    local folderId, folderPath = chooseArchiveFolder("DOCUMENT FOLDER")
    if not folderId then return end
    section("ADD DOCUMENT")
    local id = ui.prompt("ID: ")
    term.setCursorPos(2, 6); local title = ui.prompt("Title: ")
    term.setCursorPos(2, 7); term.setTextColor(ui.DIM)
    term.write(("Folder: "..folderPath):sub(1, select(1, term.getSize()) - 3))
    term.setCursorPos(2, 8); term.setTextColor(ui.FG)
    local mc = tonumber(ui.prompt("Required clearance (0-5): "))
    term.setCursorPos(2, 10); term.setTextColor(ui.DIM)
    print("Body (end with '.' alone):")
    term.setTextColor(ui.FG)
    local body = promptBody()
    showResult(sendAdmin("add_document", {
        id=id, title=title, folderId=folderId, minClearance=mc,
        body=body, author=session.username,
    }), "DOCUMENT SAVED")
end

menu.deleteArchiveItem = function()
    local folderId = "root"
    local selected, top = 1, 1
    while true do
        local r = sendAdmin("browse_archive", {folderId=folderId})
        if not r or not r.ok then return showResult(r) end
        local archive = r.archive
        local items = archiveItems(archive)
        local w, h = term.getSize()
        local rows = h - 10
        if rows < 3 then rows = 3 end
        selected = math.max(1, math.min(selected, math.max(1, #items)))
        if selected < top then top = selected end
        if selected >= top + rows then top = selected - rows + 1 end

        ui.frame(term.current(), "ARCHIVE MANAGER", "ENTER=open  D=delete  Q=back")
        term.setCursorPos(2, 4); term.setTextColor(ui.DIM)
        term.write(archivePathLabel(archive.path):sub(1, w - 3))
        term.setCursorPos(2, 6); term.setTextColor(ui.ACCENT)
        term.write("TYPE     ACCESS  NAME")
        for row = 1, rows do
            local idx = top + row - 1
            local item = items[idx]
            if not item then break end
            term.setCursorPos(2, 6 + row)
            if idx == selected then
                term.setBackgroundColor(ui.FG); term.setTextColor(ui.BG)
            else
                term.setBackgroundColor(ui.BG); term.setTextColor(ui.FG)
            end
            local typ = item.kind == "folder" and "FOLDER" or item.kind == "doc" and "DOC" or "BACK"
            local acc = item.kind == "back" and "--" or ("L"..tostring(item.minClearance or 5))
            local name = item.kind == "folder" and ("["..item.label.."]") or item.label
            local line = string.format("%-8s %-7s %s", typ, acc, name)
            term.write(line:sub(1, w - 3))
            term.write(string.rep(" ", math.max(0, w - 2 - #line)))
            term.setBackgroundColor(ui.BG)
        end
        term.setCursorPos(2, h - 2); term.setTextColor(ui.DIM)
        term.write("Folders must be empty before deletion.")

        local _, key = os.pullEvent("key")
        if key == keys.up and selected > 1 then
            selected = selected - 1
        elseif key == keys.down and selected < #items then
            selected = selected + 1
        elseif key == keys.enter and items[selected] then
            local item = items[selected]
            if item.kind == "back" then
                folderId = item.id; selected, top = 1, 1
            elseif item.kind == "folder" then
                folderId = item.id; selected, top = 1, 1
            end
        elseif key == keys.d and items[selected] then
            local item = items[selected]
            if item.kind ~= "back" then
                ui.clear(term.current())
                ui.header(term.current(), "CONFIRM DELETE")
                term.setCursorPos(2, 5); term.setTextColor(ui.ERR)
                term.write("Delete "..item.kind..": "..item.label)
                term.setCursorPos(2, 7); term.setTextColor(ui.FG)
                term.write("Type DELETE to confirm: "); term.setTextColor(ui.ACCENT)
                if read() == "DELETE" then
                    local action = item.kind == "folder" and "delete_folder" or "delete_document"
                    local args = item.kind == "folder" and {folderId=item.id} or {docId=item.id}
                    showResult(sendAdmin(action, args), "DELETED")
                    selected, top = 1, 1
                end
            end
        elseif key == keys.q or key == keys.backspace then
            return
        end
    end
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

menu.addZone = function()
    section("ADD ZONE")
    local name = ui.prompt("Zone name: ")
    if not name or name == "" then return end
    showResult(sendAdmin("add_zone", {name=name}), "ZONE ADDED: "..name)
end

menu.removeZone = function()
    section("REMOVE ZONE")
    local r = sendAdmin("list_zones", {})
    if not r then
        ui.bigStatus(term.current(), {"MAINFRAME","UNREACHABLE"}, "error"); sleep(1.5); return
    end
    -- list_zones returns raw array from db.listZones()
    local zones = {}
    if type(r) == "table" then
        for _, z in ipairs(r) do
            if type(z) == "table" and z.name then zones[#zones+1] = z.name end
        end
    end
    if #zones == 0 then
        ui.bigStatus(term.current(), {"NO ZONES"}, "idle"); sleep(1.5); return
    end
    local pick = pickFromList("REMOVE WHICH ZONE", zones)
    if not pick then return end
    if not ui.confirm("Remove zone: "..pick.."?") then return end
    showResult(sendAdmin("remove_zone", {name=pick}), "ZONE REMOVED")
end

menu.listZones = function()
    section("ZONES")
    local r = sendAdmin("list_zones", {})
    if not r then
        ui.bigStatus(term.current(), {"MAINFRAME","UNREACHABLE"}, "error"); sleep(2); return
    end
    local zones = type(r) == "table" and r or {}
    local w, h = term.getSize()
    local y = 5
    for _, z in ipairs(zones) do
        if y >= h - 3 then break end
        term.setCursorPos(2, y)
        if z.lockdown then term.setTextColor(ui.ERR); term.write("[LOCK] ")
        else term.setTextColor(ui.OK); term.write("[open] ") end
        term.setTextColor(ui.FG); term.write(z.name)
        local occ = z.occupants and #z.occupants or 0
        if occ > 0 then term.setTextColor(ui.DIM); term.write("  ("..occ.." personnel)") end
        y = y + 1
    end
    if #zones == 0 then
        term.setCursorPos(2, 5); term.setTextColor(ui.DIM); term.write("No zones configured.")
    end
    term.setCursorPos(2, h - 2); term.setTextColor(ui.DIM); term.write("Press any key...")
    os.pullEvent("key")
end
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
    {"Add zone",            menu.addZone},
    {"Remove zone",         menu.removeZone},
    {"List zones",          menu.listZones},
    {"Approve pending",     menu.approvePending},
    {"Add entity",          menu.addEntity},
    {"List entities",       menu.listEntities},
    {"Edit entity",         menu.editEntity},
    {"Delete entity",       menu.deleteEntity},
    {"Add archive folder",  menu.addFolder},
    {"Add document",        menu.addDocument},
    {"Delete archive item", menu.deleteArchiveItem},
    {"Set passcode",         menu.setPasscode},
    {"Set tablet PIN",       menu.setPin},
    {"Set facility identity", menu.setIdentity},
    {"View security log",    menu.viewLog},
    {"Log out",             function() menu.logout(); login() end},
}

while true do
    local choice = scrollMenu("REMOTE ADMIN ["..session.username.."]", "C.T.N // CLASSIFIED", options)
    if choice and options[choice] then
        local ok, err = pcall(options[choice][2])
        if not ok then
            ui.bigStatus(term.current(), {"ERROR","",tostring(err)}, "error"); sleep(2)
        end
    end
end

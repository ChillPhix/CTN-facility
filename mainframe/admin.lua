-- mainframe/admin.lua
-- Local admin console for the CTN mainframe.
-- Run on the mainframe computer itself.

package.path = package.path .. ";/lib/?.lua;/mainframe/?.lua"
local db = require("db")
local ui = require("ctnui")
db.load()

local DEPARTMENTS = {"Security","Research","MTF","Medical","Admin","Janitor","Guest","Ethics","Director"}
local ZONES = {"Office","Security","Testing","LCZ","HCZ"}

local function pause()
    term.setCursorPos(2, select(2, term.getSize()) - 2)
    term.setTextColor(ui.DIM); write("[ press Enter ]")
    read()
end

local function pickFromList(title, list)
    ui.frame(term.current(), title, "SELECT OPTION")
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

local function section(title)
    ui.frame(term.current(), title, "ADMIN CONSOLE")
    term.setCursorPos(2, 5)
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
        local archive = db.listArchiveChildren(folderId, 0)
        archive.path = db.getArchivePath(folderId)
        ui.frame(term.current(), title or "SELECT ARCHIVE FOLDER", "0 = choose current")
        term.setCursorPos(2, 4); term.setTextColor(ui.DIM)
        term.write(archivePathLabel(archive.path):sub(1, select(1, term.getSize()) - 3))

        term.setCursorPos(2, 6); term.setTextColor(ui.ACCENT)
        term.write("[0] Use this folder")
        local folders = archive.folders or {}
        local y = 8
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

local menu = {}

menu.addPerson = function()
    section("ADD PERSONNEL")
    local name = ui.prompt("Player name: ")
    term.setCursorPos(2, 6)
    local clearance = tonumber(ui.prompt("Clearance (0-5): "))
    local dept = pickFromList("SELECT DEPARTMENT", DEPARTMENTS)
    db.addPerson(name, clearance, dept, {})
    ui.bigStatus(term.current(), {"ADDED", "", name, "L"..clearance.." "..dept}, "granted")
    sleep(1.5)
end

menu.setClearance = function()
    section("MODIFY CLEARANCE")
    local name = ui.prompt("Player name: ")
    term.setCursorPos(2, 6)
    local c = tonumber(ui.prompt("New clearance (0-5): "))
    if db.setClearance(name, c) then
        ui.bigStatus(term.current(), {"UPDATED", "", name, "now L"..c}, "granted")
    else
        ui.bigStatus(term.current(), {"NOT FOUND", "", name}, "denied")
    end
    sleep(1.5)
end

menu.setFlag = function()
    section("SET PERSONNEL FLAG")
    local name = ui.prompt("Player name: ")
    term.setCursorPos(2, 6)
    local flag = ui.prompt("Flag name: ")
    term.setCursorPos(2, 7)
    local val = ui.prompt("Value (y/n): ") == "y"
    if db.setFlag(name, flag, val) then
        ui.bigStatus(term.current(), {"UPDATED", "", flag.." = "..tostring(val)}, "granted")
    else
        ui.bigStatus(term.current(), {"NOT FOUND"}, "denied")
    end
    sleep(1.5)
end

menu.suspend = function()
    section("SUSPEND / REINSTATE")
    local name = ui.prompt("Player name: ")
    term.setCursorPos(2, 6)
    local status = pickFromList("NEW STATUS", {"active","suspended","terminated"})
    if db.setStatus(name, status) then
        ui.bigStatus(term.current(), {"UPDATED", "", name, status:upper()}, "granted")
    else
        ui.bigStatus(term.current(), {"NOT FOUND"}, "denied")
    end
    sleep(1.5)
end

menu.addDoor = function()
    section("ADD DOOR")
    local name = ui.prompt("Door name: ")
    term.setCursorPos(2, 6)
    local tid = tonumber(ui.prompt("Terminal computer ID: "))
    local zone = pickFromList("ZONE", ZONES)
    section("ADD DOOR")
    term.setCursorPos(2, 5)
    local mc = tonumber(ui.prompt("Min clearance: "))
    term.setCursorPos(2, 6)
    local flag = ui.prompt("Required flag (blank for none): ")
    db.addDoor(name, tid, zone, mc, {requiredFlag = flag ~= "" and flag or nil})
    ui.bigStatus(term.current(), {"DOOR ADDED", "", name, zone.." L<="..mc}, "granted")
    sleep(1.5)
end

menu.revokeDisk = function()
    section("REVOKE ID CARD")
    local id = tonumber(ui.prompt("Disk ID: "))
    if db.revokeDisk(id) then
        ui.bigStatus(term.current(), {"REVOKED", "", "Disk #"..id}, "granted")
    else
        ui.bigStatus(term.current(), {"NOT FOUND"}, "denied")
    end
    sleep(1.5)
end

menu.listPersonnel = function()
    ui.frame(term.current(), "PERSONNEL ROSTER", "SCROLL WITH ARROWS")
    local y = 4
    local data = db.get()
    local names = {}
    for n in pairs(data.personnel) do names[#names+1] = n end
    table.sort(names)
    local _, h = term.getSize()
    for _, n in ipairs(names) do
        if y > h - 2 then break end
        local p = data.personnel[n]
        term.setCursorPos(2, y)
        term.setTextColor(ui.FG); write(string.format("L%d  ", p.clearance))
        term.setTextColor(ui.ACCENT); write(string.format("%-14s ", p.name))
        term.setTextColor(ui.DIM); write(string.format("%-10s ", p.department))
        local c = p.status == "active" and ui.OK or ui.ERR
        term.setTextColor(c); write("["..p.status.."]")
        y = y + 1
    end
    pause()
end

menu.listDisks = function()
    ui.frame(term.current(), "ID CARD REGISTRY", "")
    local y = 4
    local _, h = term.getSize()
    for id, d in pairs(db.get().disks) do
        if y > h - 2 then break end
        term.setCursorPos(2, y)
        term.setTextColor(ui.FG);     write(string.format("#%-4d ", id))
        term.setTextColor(ui.ACCENT); write(string.format("%-14s ", d.owner))
        local c = d.status == "active" and ui.OK or ui.ERR
        term.setTextColor(c); write("["..d.status.."]")
        term.setTextColor(ui.DIM); write(" by "..d.issuedBy)
        y = y + 1
    end
    pause()
end

menu.listDoors = function()
    ui.frame(term.current(), "DOOR REGISTRY", "")
    local y = 4
    local _, h = term.getSize()
    for name, d in pairs(db.get().doors) do
        if y > h - 2 then break end
        term.setCursorPos(2, y)
        term.setTextColor(ui.ACCENT); write(string.format("%-22s ", name))
        term.setTextColor(ui.FG);     write(string.format("%-8s ", d.zone))
        term.setTextColor(ui.DIM);    write(string.format("L<=%d term#%d", d.minClearance, d.terminalId))
        y = y + 1
    end
    pause()
end

menu.setPasscode = function()
    section("SET PASSCODE")
    local which = pickFromList("WHICH PASSCODE", {"issuer","control","admin"})
    section("SET PASSCODE")
    term.setCursorPos(2, 5)
    local code = ui.promptHidden("New code: ")
    db.setPasscode(which, code)
    ui.bigStatus(term.current(), {"PASSCODE UPDATED", "", which}, "granted")
    sleep(1.5)
end

menu.addDocument = function()
    local folderId, folderPath = chooseArchiveFolder("DOCUMENT FOLDER")
    if not folderId then return end
    section("ADD DOCUMENT")
    local id = ui.prompt("ID (e.g. SCP-173): ")
    term.setCursorPos(2, 6); local title = ui.prompt("Title: ")
    term.setCursorPos(2, 7); term.setTextColor(ui.DIM)
    term.write(("Folder: "..folderPath):sub(1, select(1, term.getSize()) - 3))
    term.setCursorPos(2, 8); term.setTextColor(ui.FG)
    local mc = tonumber(ui.prompt("Required clearance (0-5): "))
    term.setCursorPos(2, 10); term.setTextColor(ui.DIM)
    print("Enter body. End with a single '.' on its own line.")
    term.setTextColor(ui.FG)
    local body = {}
    while true do
        local line = read()
        if line == "." then break end
        body[#body+1] = line
    end
    db.addDocument(id, title, folderId, mc, table.concat(body, "\n"), "admin")
    ui.bigStatus(term.current(), {"DOCUMENT SAVED", "", id.." - "..title}, "granted")
    sleep(1.5)
end

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
    local id, err = db.addFolder(parentId, name, mc, "admin")
    if id then
        ui.bigStatus(term.current(), {"FOLDER CREATED", "", name}, "granted")
    else
        ui.bigStatus(term.current(), {"FAILED", "", tostring(err)}, "denied")
    end
    sleep(1.5)
end

menu.deleteArchiveItem = function()
    local folderId = "root"
    local selected, top = 1, 1
    while true do
        local archive = db.listArchiveChildren(folderId, 0)
        archive.path = db.getArchivePath(folderId)
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
            if item.kind == "back" or item.kind == "folder" then
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
                    local ok, err
                    if item.kind == "folder" then ok, err = db.deleteFolder(item.id)
                    else ok, err = db.deleteDocument(item.id) end
                    if ok then
                        ui.bigStatus(term.current(), {"DELETED"}, "granted")
                    else
                        ui.bigStatus(term.current(), {"FAILED", "", tostring(err)}, "denied")
                    end
                    sleep(1.5)
                    selected, top = 1, 1
                end
            end
        elseif key == keys.q or key == keys.backspace then
            return
        end
    end
end

menu.viewLog = function()
    ui.frame(term.current(), "SECURITY AUDIT LOG", "MOST RECENT LAST")
    local entries = db.readLog(40)
    local _, h = term.getSize()
    local start = math.max(1, #entries - (h - 6))
    local y = 4
    for i = start, #entries do
        local e = entries[i]
        if y > h - 2 then break end
        local t = os.date("%H:%M:%S", e.ts / 1000)
        term.setCursorPos(2, y)
        term.setTextColor(ui.DIM); write("["..t.."] ")
        local cat = e.category
        local c = ({security=ui.ERR, access=ui.WARN, admin=ui.OK, facility=ui.ACCENT, docs=ui.FG, error=ui.ERR})[cat] or ui.FG
        term.setTextColor(c); write(cat:upper()..": ")
        term.setTextColor(ui.FG); write(tostring(e.message))
        y = y + 1
    end
    pause()
end

local options = {
    {"Add personnel",       menu.addPerson},
    {"Set clearance",       menu.setClearance},
    {"Set flag",            menu.setFlag},
    {"Suspend / reinstate", menu.suspend},
    {"Add door",            menu.addDoor},
    {"Revoke ID card",      menu.revokeDisk},
    {"List personnel",      menu.listPersonnel},
    {"List ID cards",       menu.listDisks},
    {"List doors",          menu.listDoors},
    {"Set passcode",        menu.setPasscode},
    {"Add archive folder",  menu.addFolder},
    {"Add document",        menu.addDocument},
    {"Delete archive item", menu.deleteArchiveItem},
    {"View security log",   menu.viewLog},
    {"Exit",                function() error("exit", 0) end},
}

while true do
    ui.frame(term.current(), "MAINFRAME ADMIN CONSOLE", "C.T.N // CLASSIFIED")
    local labels = {}
    for i, opt in ipairs(options) do labels[i] = opt[1] end
    local choice = ui.menu(nil, labels, 5)
    if choice and options[choice] then
        local ok, err = pcall(options[choice][2])
        if not ok and err ~= "exit" then
            ui.bigStatus(term.current(), {"ERROR", "", tostring(err)}, "error")
            sleep(2)
        end
        if err == "exit" then
            ui.clear(term.current()); print("Goodbye."); break
        end
    end
end

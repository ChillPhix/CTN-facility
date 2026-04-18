-- terminals/archive.lua
-- Hierarchical CTN archive browser. Card-authenticated users can see the
-- archive tree, but restricted folders/documents cannot be opened unless
-- their card clearance is high enough.

package.path = package.path .. ";/lib/?.lua"
local proto = require("ctnproto")
local ui    = require("ctnui")
local cfg   = require("ctnconfig")

local myCfg = cfg.loadOrWizard("archive", {
    {key="mainframe_id", prompt="Mainframe computer ID", type="number", default=1},
})

proto.openModem()
local MAINFRAME = myCfg.mainframe_id

local function findPeripheral(typeName)
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == typeName then return peripheral.wrap(side) end
    end
end

local drive = findPeripheral("drive")
if not drive then error("No disk drive attached.") end

local function waitForDisk()
    ui.frame(term.current(), "DOCUMENT ARCHIVE", "INSERT ID CARD")
    term.setCursorPos(2, 5); term.setTextColor(ui.ACCENT)
    print("C.T.N HIERARCHICAL ARCHIVE")
    term.setCursorPos(2, 7); term.setTextColor(ui.DIM)
    print("Folders remain visible. Restricted records")
    term.setCursorPos(2, 8)
    print("require the proper clearance to open.")
    while not drive.getDiskID() do os.pullEvent("disk") end
    return drive.getDiskID()
end

local function browseRequest(diskID, folderId)
    return proto.request(MAINFRAME, "doc_request", {
        diskID = diskID,
        action = "browse",
        folderId = folderId or "root",
    }, 3)
end

local function readRequest(diskID, docId)
    return proto.request(MAINFRAME, "doc_request", {
        diskID = diskID,
        action = "read",
        docId = docId,
    }, 3)
end

local function pathText(path)
    local parts = {}
    for _, p in ipairs(path or {}) do parts[#parts+1] = p.name end
    local s = table.concat(parts, " / ")
    if s == "" then s = "Departments" end
    return s
end

local function makeItems(archive)
    local items = {}
    local folder = archive.folder or {id="root"}
    if folder.parent then
        items[#items+1] = {kind="back", label="..", target=folder.parent}
    end
    for _, f in ipairs(archive.folders or {}) do
        items[#items+1] = {kind="folder", label=f.name, id=f.id,
            minClearance=f.minClearance, locked=f.locked}
    end
    for _, d in ipairs(archive.documents or {}) do
        items[#items+1] = {kind="doc", label=d.title, id=d.id,
            minClearance=d.minClearance, locked=d.locked, author=d.author}
    end
    return items
end

local function drawBrowser(reply, selected, top)
    local archive = reply.archive
    local person = reply.person or {name="?", clearance="?"}
    local items = makeItems(archive)
    local w, h = term.getSize()

    ui.frame(term.current(), "ARCHIVE", person.name.."  //  L"..person.clearance)
    term.setCursorPos(2, 4); term.setTextColor(ui.DIM)
    term.write(pathText(archive.path):sub(1, w - 3))

    term.setCursorPos(2, 6); term.setTextColor(ui.ACCENT)
    term.write(string.format("%-3s %-8s %-6s %s", "", "TYPE", "ACCESS", "NAME"))
    term.setCursorPos(2, 7); term.setTextColor(ui.BORDER)
    term.write(string.rep("-", w - 3))

    local rows = h - 10
    top = math.max(1, math.min(top or 1, math.max(1, #items - rows + 1)))
    selected = math.max(1, math.min(selected or 1, math.max(1, #items)))

    if #items == 0 then
        term.setCursorPos(4, 9); term.setTextColor(ui.DIM)
        term.write("This folder is empty.")
    else
        for row = 1, rows do
            local idx = top + row - 1
            local item = items[idx]
            if not item then break end
            local y = 7 + row
            local isSelected = idx == selected
            term.setCursorPos(2, y)
            if isSelected then
                term.setBackgroundColor(ui.FG); term.setTextColor(ui.BG)
            else
                term.setBackgroundColor(ui.BG); term.setTextColor(ui.FG)
            end

            local typeLabel = item.kind == "folder" and "FOLDER"
                or item.kind == "doc" and "DOC"
                or "BACK"
            local access = item.kind == "back" and "--"
                or ((item.locked and "L"..item.minClearance.." LOCK") or "L"..item.minClearance)
            local prefix = isSelected and ">" or " "
            local name = item.label
            if item.kind == "folder" then name = "["..name.."]" end
            local line = string.format("%-3s %-8s %-6s %s", prefix, typeLabel, access, name)
            term.write(line:sub(1, w - 3))
            term.write(string.rep(" ", math.max(0, w - 2 - #line)))
            term.setBackgroundColor(ui.BG)
        end
    end

    term.setCursorPos(2, h - 2); term.setTextColor(ui.DIM)
    term.write("arrows=move  ENTER=open  BACKSPACE=up  Q=eject")
    ui.footer(term.current(), "C.T.N ARCHIVE // "..#(archive.folders or {}).." folders // "..#(archive.documents or {}).." docs")
    return items, selected, top
end

local function denied(reason)
    local label = ({
        folder_restricted = "FOLDER RESTRICTED",
        insufficient_clearance = "INSUFFICIENT CLEARANCE",
        not_found = "RECORD NOT FOUND",
    })[reason] or tostring(reason or "ACCESS DENIED"):upper()
    ui.bigStatus(term.current(), {"ACCESS DENIED", "", label}, "denied")
    sleep(1.5)
end

local function wrapText(text, width)
    local lines = {}
    text = tostring(text or "").."\n"
    for raw in text:gmatch("(.-)\n") do
        if raw == "" then
            lines[#lines+1] = ""
        else
            local line = ""
            for word in raw:gmatch("%S+") do
                if #line + #word + 1 > width then
                    lines[#lines+1] = line
                    line = word
                else
                    line = line == "" and word or (line.." "..word)
                end
            end
            if line ~= "" then lines[#lines+1] = line end
        end
    end
    return lines
end

local function viewDoc(diskID, docId)
    ui.bigStatus(term.current(), {"LOADING RECORD..."}, "working")
    local reply = readRequest(diskID, docId)
    if not reply or not reply.ok then
        denied(reply and reply.reason or "mainframe_unreachable")
        return
    end

    local doc = reply.doc
    local w, h = term.getSize()
    local body = wrapText(doc.body or "", w - 4)
    local scroll = 0

    while true do
        ui.frame(term.current(), doc.title or doc.id, "L"..(doc.minClearance or "?").." RECORD")
        term.setCursorPos(2, 4); term.setTextColor(ui.DIM)
        term.write(("ID: "..doc.id.."  AUTHOR: "..tostring(doc.author or "?")):sub(1, w - 3))
        term.setCursorPos(2, 5); term.setTextColor(ui.BORDER)
        term.write(string.rep("-", w - 3))

        local visible = h - 9
        for i = 1, visible do
            local line = body[scroll + i]
            if not line then break end
            term.setCursorPos(3, 5 + i); term.setTextColor(ui.FG)
            term.write(line:sub(1, w - 4))
        end

        term.setCursorPos(2, h - 2); term.setTextColor(ui.DIM)
        term.write("arrows/page=scroll  BACKSPACE=back")
        local _, key = os.pullEvent("key")
        if key == keys.up and scroll > 0 then scroll = scroll - 1
        elseif key == keys.down and scroll < math.max(0, #body - visible) then scroll = scroll + 1
        elseif key == keys.pageUp then scroll = math.max(0, scroll - visible)
        elseif key == keys.pageDown then scroll = math.min(math.max(0, #body - visible), scroll + visible)
        elseif key == keys.backspace then return end
    end
end

local function archiveSession(diskID)
    local folderId = "root"
    local selected, top = 1, 1

    while drive.getDiskID() do
        ui.bigStatus(term.current(), {"OPENING ARCHIVE..."}, "working")
        local reply = browseRequest(diskID, folderId)
        if not reply then
            ui.bigStatus(term.current(), {"MAINFRAME", "UNREACHABLE"}, "error")
            sleep(2); return
        elseif not reply.ok then
            denied(reply.reason)
            folderId = "root"
            selected, top = 1, 1
        else
            while drive.getDiskID() do
                local items
                items, selected, top = drawBrowser(reply, selected, top)
                local _, key = os.pullEvent("key")
                if key == keys.up and selected > 1 then
                    selected = selected - 1
                    if selected < top then top = selected end
                elseif key == keys.down and selected < #items then
                    selected = selected + 1
                    local rows = select(2, term.getSize()) - 10
                    if selected >= top + rows then top = top + 1 end
                elseif key == keys.enter and items[selected] then
                    local item = items[selected]
                    if item.kind == "back" then
                        folderId = item.target
                        selected, top = 1, 1
                        break
                    elseif item.locked then
                        denied(item.kind == "folder" and "folder_restricted" or "insufficient_clearance")
                    elseif item.kind == "folder" then
                        folderId = item.id
                        selected, top = 1, 1
                        break
                    elseif item.kind == "doc" then
                        viewDoc(diskID, item.id)
                    end
                elseif key == keys.backspace then
                    local parent = reply.archive and reply.archive.folder and reply.archive.folder.parent
                    if parent then
                        folderId = parent
                        selected, top = 1, 1
                        break
                    end
                elseif key == keys.q then
                    return
                end
            end
        end
    end
end

while true do
    local diskID = waitForDisk()
    ui.bigStatus(term.current(), {"VERIFYING CARD..."}, "working")
    archiveSession(diskID)
    while drive.getDiskID() do sleep(0.3) end
end

-- terminals/archive.lua
-- Hierarchical CTN archive browser. Card-authenticated users can see the
-- archive tree, but restricted folders/documents cannot be opened unless
-- their card clearance is high enough.

package.path = package.path .. ";/lib/?.lua"
local proto = require("ctnproto")
local ui    = require("ctnui")
local cfg   = require("ctnconfig")
local gpu   = require("ctngpu")

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

local printer = findPeripheral("printer")
local display = gpu.openBackend({preferGpu=true})
if display and display.mode == "term" then display = false end
local lastButtons = {}
local lastDocButtons = {}
local lastActionButtons = {}
local lastDisplayButtons = {}

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

local function mutateRequest(diskID, action, payload)
    payload = payload or {}
    payload.diskID = diskID
    payload.action = action
    return proto.request(MAINFRAME, "doc_request", payload, 4)
end

local function pathText(path)
    local parts = {}
    for _, p in ipairs(path or {}) do parts[#parts+1] = p.name end
    local s = table.concat(parts, " / ")
    if s == "" then s = "Departments" end
    return s
end

local function trimLine(s, n)
    s = tostring(s or "")
    if #s <= n then return s end
    return s:sub(1, math.max(1, n - 3)).."..."
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
    lastButtons = {}
    lastActionButtons = {}
    lastDisplayButtons = {}
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
            lastButtons[#lastButtons+1] = {x=2, y=y, w=w-2, h=1, index=idx}
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

    local bw = math.max(7, math.floor((w - 6) / 4))
    local ay = h - 3
    lastActionButtons = {
        {key="c", label="FOLDER", x=2, y=ay, w=bw, h=1},
        {key="n", label="NEW DOC", x=3+bw, y=ay, w=bw, h=1},
        {key="i", label="IMPORT", x=4+bw*2, y=ay, w=bw, h=1},
        {key="d", label="DELETE", x=5+bw*3, y=ay, w=w-(5+bw*3), h=1},
    }
    for _, b in ipairs(lastActionButtons) do
        ui.drawButton(term.current(), b.x, b.y, b.w, b.h, b.label, {hotkey=b.key})
    end

    term.setCursorPos(2, h - 2); term.setTextColor(ui.DIM)
    term.write("ENTER=open  C/N/I=create/import  D=delete  Q=eject")
    ui.footer(term.current(), "C.T.N ARCHIVE // "..#(archive.folders or {}).." folders // "..#(archive.documents or {}).." docs")

    if display then
        local ok = pcall(function()
            display:clear(gpu.COLORS.bg)
            local dw, dh = display:size()
            gpu.header(display, "C.T.N ARCHIVE", pathText(archive.path))
            if display.mode == "gpu" then
                local p = gpu.panel(display, 8, 44, dw - 16, dh - 60, "FILES // "..person.name.." L"..person.clearance, "normal")
                local y = p.contentY + 4
                local rowH = 16
                local visible = math.floor((p.h - 24) / rowH)
                for row = 1, visible do
                    local idx = top + row - 1
                    local item = items[idx]
                    if not item then break end
                    local bg = idx == selected and gpu.COLORS.dim or gpu.COLORS.panelBg
                    display:fillRect(p.x + 4, y - 2, p.w - 8, rowH, bg)
                    local kind = item.kind == "folder" and "DIR" or item.kind == "doc" and "DOC" or "UP"
                    local col = item.locked and gpu.COLORS.err or (item.kind == "folder" and gpu.COLORS.accent2 or gpu.COLORS.fg)
                    display:text(p.x + 10, y, kind, gpu.COLORS.dim, 10, "bold")
                    display:text(p.x + 50, y, item.locked and "LOCK" or ("L"..tostring(item.minClearance or "-")), col, 10, "bold")
                    display:text(p.x + 100, y, trimLine(item.label, math.floor((p.w - 120) / 6)), col, 10, "plain")
                    y = y + rowH
                end
                display:text(12, dh - 14, "C folder  N document  I import disk text  D delete  P print records", gpu.COLORS.dim, 10, "plain")
            else
                local p = gpu.panel(display, 1, 3, dw, dh - 3, "FILES", "normal")
                local y = p.contentY
                local visible = p.h - 5
                for row = 1, visible do
                    local idx = top + row - 1
                    local item = items[idx]
                    if not item then break end
                    lastDisplayButtons[#lastDisplayButtons+1] = {kind="item", x=1, y=y, w=dw, h=1, index=idx}
                    local col = item.locked and gpu.COLORS.err or gpu.COLORS.fg
                    local marker = idx == selected and ">" or " "
                    local kind = item.kind == "folder" and "[D]" or item.kind == "doc" and "[F]" or "[^]"
                    display:text(p.x + 1, y, trimLine(marker.." "..kind.." "..item.label, p.w - 2), col)
                    y = y + 1
                end
                local by = dh - 1
                local bw = math.max(6, math.floor(dw / 4))
                local labels = {
                    {key="c", label="FOLDER", x=1, y=by, w=bw, h=1},
                    {key="n", label="NEW DOC", x=1+bw, y=by, w=bw, h=1},
                    {key="i", label="IMPORT", x=1+bw*2, y=by, w=bw, h=1},
                    {key="d", label="DELETE", x=1+bw*3, y=by, w=dw-bw*3, h=1},
                }
                for _, b in ipairs(labels) do
                    display:fillRect(b.x, b.y, b.w, b.h, gpu.COLORS.fg)
                    display:textBg(b.x + 1, b.y, trimLine(b.label, b.w - 2), gpu.COLORS.bg, gpu.COLORS.fg)
                    lastDisplayButtons[#lastDisplayButtons+1] = {kind="action", x=b.x, y=b.y, w=b.w, h=b.h, key=b.key}
                end
            end
            display:update()
        end)
        if not ok then display = false end
    end
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

local function printDoc(doc)
    if not printer then
        ui.bigStatus(term.current(), {"NO PRINTER", "", "Attach a printer peripheral."}, "denied")
        sleep(1.5)
        return false
    end

    local ok, err = pcall(function()
        if not printer.newPage() then error("printer_not_ready") end
        local pw, ph = printer.getPageSize()
        printer.setPageTitle((doc.title or doc.id or "CTN Record"):sub(1, 32))
        printer.setCursorPos(1, 1)
        printer.write("C.T.N ARCHIVE RECORD")
        printer.setCursorPos(1, 2)
        printer.write(trimLine((doc.id or "?").." - "..(doc.title or ""), pw))
        printer.setCursorPos(1, 3)
        printer.write(trimLine("Clearance L"..tostring(doc.minClearance or "?").."  Author: "..tostring(doc.author or "?"), pw))
        printer.setCursorPos(1, 4)
        printer.write(string.rep("-", pw))

        local lines = wrapText(doc.body or "", pw)
        local y = 5
        for _, line in ipairs(lines) do
            if y > ph then
                printer.endPage()
                if not printer.newPage() then error("printer_out_of_paper") end
                printer.setPageTitle((doc.title or doc.id or "CTN Record"):sub(1, 32))
                y = 1
            end
            printer.setCursorPos(1, y)
            printer.write(line:sub(1, pw))
            y = y + 1
        end
        printer.endPage()
    end)

    if ok then
        ui.bigStatus(term.current(), {"PRINT SENT", "", doc.id or "RECORD"}, "granted")
    else
        ui.bigStatus(term.current(), {"PRINT FAILED", "", tostring(err)}, "error")
    end
    sleep(1.5)
    return ok
end

local function showMutationResult(reply, success)
    if not reply then
        ui.bigStatus(term.current(), {"MAINFRAME", "UNREACHABLE"}, "error")
    elseif reply.ok then
        ui.bigStatus(term.current(), {success or "DONE"}, "granted")
    else
        ui.bigStatus(term.current(), {"FAILED", "", tostring(reply.reason or "?"):upper()}, "denied")
    end
    sleep(1.5)
end

local function promptClearance(default)
    term.setTextColor(ui.FG)
    write("Required clearance (0-5)")
    if default ~= nil then write(" ["..default.."]") end
    write(": ")
    term.setTextColor(ui.ACCENT)
    local s = read()
    term.setTextColor(ui.FG)
    if s == "" and default ~= nil then return default end
    local n = tonumber(s)
    if not n then return default or 5 end
    return math.max(0, math.min(5, n))
end

local function promptBody()
    term.setTextColor(ui.DIM)
    print("Body text. End with a single '.' on its own line.")
    term.setTextColor(ui.FG)
    local lines = {}
    while true do
        local line = read()
        if line == "." then break end
        lines[#lines+1] = line
    end
    return table.concat(lines, "\n")
end

local function createFolder(diskID, parentId, person)
    ui.frame(term.current(), "CREATE FOLDER", "Current folder")
    term.setCursorPos(2, 5); term.setTextColor(ui.FG)
    write("Folder name: "); term.setTextColor(ui.ACCENT)
    local name = read()
    term.setCursorPos(2, 7)
    local minClearance = promptClearance(person and person.clearance or 5)
    showMutationResult(mutateRequest(diskID, "create_folder", {
        parentId=parentId, name=name, minClearance=minClearance,
    }), "FOLDER CREATED")
end

local function createDocument(diskID, folderId, person, importedBody, importedTitle)
    ui.frame(term.current(), importedBody and "IMPORT DOCUMENT" or "CREATE DOCUMENT", "Current folder")
    term.setCursorPos(2, 5); term.setTextColor(ui.FG)
    write("Document ID: "); term.setTextColor(ui.ACCENT)
    local id = read()
    term.setCursorPos(2, 6); term.setTextColor(ui.FG)
    write("Title")
    if importedTitle then write(" ["..importedTitle.."]") end
    write(": "); term.setTextColor(ui.ACCENT)
    local title = read()
    if title == "" then title = importedTitle or id end
    term.setCursorPos(2, 8)
    local minClearance = promptClearance(person and person.clearance or 5)
    local body
    if importedBody then
        body = importedBody
    else
        term.setCursorPos(2, 10)
        body = promptBody()
    end
    showMutationResult(mutateRequest(diskID, "create_document", {
        folderId=folderId, id=id, title=title, minClearance=minClearance, body=body,
    }), "DOCUMENT SAVED")
end

local function listImportFiles(base)
    local out = {}
    local function walk(path)
        for _, name in ipairs(fs.list(path)) do
            local p = path == "" and name or (path.."/"..name)
            if fs.isDir(p) then
                walk(p)
            else
                local lower = name:lower()
                if lower:match("%.txt$") or lower:match("%.md$") or lower:match("%.log$") then
                    out[#out+1] = p
                end
            end
        end
    end
    walk(base)
    table.sort(out)
    return out
end

local function importDocument(diskID, folderId, person)
    local mount = drive.getMountPath()
    if not mount then
        ui.bigStatus(term.current(), {"NO DISK FILES", "", "Card mount unavailable."}, "denied")
        sleep(1.5)
        return
    end
    local files = listImportFiles(mount)
    if #files == 0 then
        ui.bigStatus(term.current(), {"NO TEXT FILES", "", "Put .txt/.md/.log on the card."}, "denied")
        sleep(2)
        return
    end

    local selected, top = 1, 1
    while true do
        ui.frame(term.current(), "IMPORT FROM DISK", "Text files on inserted card")
        local w, h = term.getSize()
        local rows = h - 8
        for row = 1, rows do
            local idx = top + row - 1
            local file = files[idx]
            if not file then break end
            term.setCursorPos(2, 4 + row)
            if idx == selected then
                term.setBackgroundColor(ui.FG); term.setTextColor(ui.BG)
            else
                term.setBackgroundColor(ui.BG); term.setTextColor(ui.FG)
            end
            local shown = file:gsub("^"..mount.."/?", "")
            term.write(trimLine(shown, w - 3))
            term.write(string.rep(" ", math.max(0, w - 2 - #shown)))
            term.setBackgroundColor(ui.BG)
        end
        term.setCursorPos(2, h - 2); term.setTextColor(ui.DIM)
        term.write("ENTER=import  BACKSPACE=cancel")
        local _, key = os.pullEvent("key")
        if key == keys.up and selected > 1 then
            selected = selected - 1
            if selected < top then top = selected end
        elseif key == keys.down and selected < #files then
            selected = selected + 1
            if selected >= top + rows then top = top + 1 end
        elseif key == keys.enter then
            local f = fs.open(files[selected], "r")
            local body = f.readAll()
            f.close()
            local title = fs.getName(files[selected]):gsub("%.%w+$", "")
            createDocument(diskID, folderId, person, body, title)
            return
        elseif key == keys.backspace then
            return
        end
    end
end

local function deleteSelected(diskID, item)
    if not item or item.kind == "back" then return end
    ui.clear(term.current())
    ui.header(term.current(), "CONFIRM DELETE")
    term.setCursorPos(2, 5); term.setTextColor(ui.ERR)
    term.write("Delete "..item.kind..": "..item.label)
    term.setCursorPos(2, 7); term.setTextColor(ui.FG)
    term.write("Type DELETE to confirm: "); term.setTextColor(ui.ACCENT)
    if read() ~= "DELETE" then return end
    local action = item.kind == "folder" and "delete_folder" or "delete_document"
    local payload = item.kind == "folder" and {folderId=item.id} or {docId=item.id}
    showMutationResult(mutateRequest(diskID, action, payload), "DELETED")
end

local function runBrowserAction(actionKey, diskID, folderId, person, selectedItem)
    if actionKey == "c" then createFolder(diskID, folderId, person)
    elseif actionKey == "n" then createDocument(diskID, folderId, person)
    elseif actionKey == "i" then importDocument(diskID, folderId, person)
    elseif actionKey == "d" then deleteSelected(diskID, selectedItem) end
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
        lastDocButtons = {
            back = {x=2, y=h-3, w=math.floor((w-4)/2), h=1},
            print = {x=3+math.floor((w-4)/2), y=h-3, w=w-3-math.floor((w-4)/2), h=1},
        }
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

        ui.drawButton(term.current(), lastDocButtons.back.x, lastDocButtons.back.y, lastDocButtons.back.w, 1, "BACK", {hotkey="b"})
        ui.drawButton(term.current(), lastDocButtons.print.x, lastDocButtons.print.y, lastDocButtons.print.w, 1, "PRINT", {hotkey="p", disabled=not printer})
        term.setCursorPos(2, h - 2); term.setTextColor(ui.DIM)
        term.write("arrows/page=scroll  BACKSPACE=back  P=print")

        if display then
            local ok = pcall(function()
                display:clear(gpu.COLORS.bg)
                local dw, dh = display:size()
                gpu.header(display, doc.title or doc.id, "L"..(doc.minClearance or "?").." // "..doc.id)
                if display.mode == "gpu" then
                    local p = gpu.panel(display, 8, 44, dw - 16, dh - 60, "RECORD BODY", "normal")
                    local y = p.contentY + 4
                    local lines = wrapText(doc.body or "", math.floor((p.w - 24) / 6))
                    for i = 1, math.floor((p.h - 20) / 12) do
                        local line = lines[scroll + i]
                        if not line then break end
                        display:text(p.x + 12, y, line, gpu.COLORS.fg, 10, "plain")
                        y = y + 12
                    end
                    display:text(12, dh - 14, printer and "P prints this record." or "No printer attached.", gpu.COLORS.dim, 10, "plain")
                else
                    local p = gpu.panel(display, 1, 3, dw, dh - 3, "RECORD", "normal")
                    local lines = wrapText(doc.body or "", p.w - 2)
                    for i = 1, p.h - 3 do
                        local line = lines[scroll + i]
                        if not line then break end
                        display:text(p.x + 1, p.contentY + i - 1, line, gpu.COLORS.fg)
                    end
                end
                display:update()
            end)
            if not ok then display = false end
        end

        local evt = {os.pullEvent()}
        if evt[1] == "key" then
            local key = evt[2]
            if key == keys.up and scroll > 0 then scroll = scroll - 1
            elseif key == keys.down and scroll < math.max(0, #body - visible) then scroll = scroll + 1
            elseif key == keys.pageUp then scroll = math.max(0, scroll - visible)
            elseif key == keys.pageDown then scroll = math.min(math.max(0, #body - visible), scroll + visible)
            elseif key == keys.backspace or key == keys.b then return
            elseif key == keys.p then
                printDoc(doc)
            end
        elseif evt[1] == "mouse_scroll" then
            local dir = evt[2]
            scroll = math.max(0, math.min(math.max(0, #body - visible), scroll + dir))
        elseif evt[1] == "mouse_click" then
            local x, y = evt[3], evt[4]
            if ui.hit(lastDocButtons.back, x, y) then return end
            if printer and ui.hit(lastDocButtons.print, x, y) then printDoc(doc) end
        end
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
                local evt = {os.pullEvent()}
                local function openItem(item)
                    if not item then return false end
                    if item.kind == "back" then
                        folderId = item.target
                        selected, top = 1, 1
                        return true
                    elseif item.locked then
                        denied(item.kind == "folder" and "folder_restricted" or "insufficient_clearance")
                    elseif item.kind == "folder" then
                        folderId = item.id
                        selected, top = 1, 1
                        return true
                    elseif item.kind == "doc" then
                        viewDoc(diskID, item.id)
                    end
                    return false
                end

                if evt[1] == "key" then
                    local key = evt[2]
                    if key == keys.up and selected > 1 then
                        selected = selected - 1
                        if selected < top then top = selected end
                    elseif key == keys.down and selected < #items then
                        selected = selected + 1
                        local rows = select(2, term.getSize()) - 10
                        if selected >= top + rows then top = top + 1 end
                    elseif key == keys.enter and items[selected] then
                        if openItem(items[selected]) then break end
                    elseif key == keys.c then
                        runBrowserAction("c", diskID, reply.archive.folder.id, reply.person, items[selected])
                        break
                    elseif key == keys.n then
                        runBrowserAction("n", diskID, reply.archive.folder.id, reply.person, items[selected])
                        break
                    elseif key == keys.i then
                        runBrowserAction("i", diskID, reply.archive.folder.id, reply.person, items[selected])
                        break
                    elseif key == keys.d then
                        runBrowserAction("d", diskID, reply.archive.folder.id, reply.person, items[selected])
                        break
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
                elseif evt[1] == "mouse_click" then
                    local x, y = evt[3], evt[4]
                    local handledAction = false
                    for _, b in ipairs(lastActionButtons) do
                        if ui.hit(b, x, y) then
                            handledAction = true
                            runBrowserAction(b.key, diskID, reply.archive.folder.id, reply.person, items[selected])
                            break
                        end
                    end
                    if handledAction then break end
                    for _, btn in ipairs(lastButtons) do
                        if ui.hit(btn, x, y) then
                            selected = btn.index
                            if openItem(items[selected]) then break end
                        end
                    end
                    if folderId ~= (reply.archive.folder and reply.archive.folder.id) then
                        break
                    end
                elseif evt[1] == "mouse_scroll" then
                    local dir = evt[2]
                    local rows = select(2, term.getSize()) - 10
                    top = math.max(1, math.min(math.max(1, #items - rows + 1), top + dir))
                    selected = math.max(top, math.min(selected, top + rows - 1))
                elseif evt[1] == "monitor_touch" then
                    local x, y = evt[3], evt[4]
                    local refreshNeeded = false
                    for _, btn in ipairs(lastDisplayButtons) do
                        if x >= btn.x and x < btn.x + btn.w and y >= btn.y and y < btn.y + btn.h then
                            if btn.kind == "item" then
                                selected = btn.index
                                if openItem(items[selected]) then break end
                            elseif btn.kind == "action" then
                                runBrowserAction(btn.key, diskID, reply.archive.folder.id, reply.person, items[selected])
                                refreshNeeded = true
                                break
                            end
                        end
                    end
                    if refreshNeeded or folderId ~= (reply.archive.folder and reply.archive.folder.id) then
                        break
                    end
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

-- terminals/archive.lua
-- Document Archive Terminal. Clearance-gated folder browser for
-- SCP files, protocols, incident reports, and other facility documents.
--
-- Peripherals:
--   - wireless modem
--   - disk drive (for ID card authentication)

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

-- ============================================================
-- Screens
-- ============================================================
local function waitForDisk()
    ui.frame(term.current(), "DOCUMENT ARCHIVE", "INSERT ID CARD TO ACCESS")
    term.setCursorPos(2, 5); term.setTextColor(ui.FG)
    print("C.T.N CLASSIFIED DOCUMENT ARCHIVE")
    term.setCursorPos(2, 7); term.setTextColor(ui.DIM)
    print("Insert a valid ID card to browse documents")
    term.setCursorPos(2, 8); print("appropriate to your clearance level.")
    while not drive.getDiskID() do os.pullEvent("disk") end
    return drive.getDiskID()
end

local function fetchDocs(diskID)
    return proto.request(MAINFRAME, "doc_request", {diskID=diskID, action="list"}, 3)
end

local function fetchDoc(diskID, docId)
    return proto.request(MAINFRAME, "doc_request", {diskID=diskID, action="read", docId=docId}, 3)
end

local function groupByFolder(docs)
    local folders = {}
    local order = {}
    for _, d in ipairs(docs) do
        if not folders[d.folder] then
            folders[d.folder] = {}
            order[#order+1] = d.folder
        end
        table.insert(folders[d.folder], d)
    end
    table.sort(order)
    for _, f in ipairs(order) do
        table.sort(folders[f], function(a,b) return a.id < b.id end)
    end
    return folders, order
end

-- Forward declarations so the three browsing functions can reference each other.
local browseFolders, browseDocs, viewDoc

browseFolders = function(diskID, reply)
    local folders, order = groupByFolder(reply.docs)
    local selectedFolder = 1
    while true do
        ui.frame(term.current(), "ARCHIVE - FOLDERS", (reply.person and reply.person.name or "?"))
        term.setCursorPos(2, 5); term.setTextColor(ui.DIM)
        term.write("Arrow keys + Enter. Q to exit.")
        for i, f in ipairs(order) do
            term.setCursorPos(4, 6 + i)
            if i == selectedFolder then
                term.setBackgroundColor(ui.FG); term.setTextColor(ui.BG)
            else
                term.setBackgroundColor(ui.BG); term.setTextColor(ui.FG)
            end
            term.write(" "..f.." ("..#folders[f]..") ")
            term.setBackgroundColor(ui.BG)
        end
        local event, key = os.pullEvent("key")
        if key == keys.up and selectedFolder > 1 then selectedFolder = selectedFolder - 1
        elseif key == keys.down and selectedFolder < #order then selectedFolder = selectedFolder + 1
        elseif key == keys.enter then
            browseDocs(diskID, order[selectedFolder], folders[order[selectedFolder]])
        elseif key == keys.q then return end
    end
end

browseDocs = function(diskID, folder, docs)
    local selected = 1
    while true do
        ui.frame(term.current(), "ARCHIVE - "..folder, "")
        term.setCursorPos(2, 5); term.setTextColor(ui.DIM)
        term.write("Arrow keys + Enter. Backspace to go back.")
        local _, h = term.getSize()
        local pageSize = h - 8
        local top = math.max(1, selected - math.floor(pageSize/2))
        for i = top, math.min(top + pageSize - 1, #docs) do
            local d = docs[i]
            term.setCursorPos(4, 6 + (i - top + 1))
            if i == selected then
                term.setBackgroundColor(ui.FG); term.setTextColor(ui.BG)
            else
                term.setBackgroundColor(ui.BG); term.setTextColor(ui.FG)
            end
            term.write(string.format(" [L%d] %-15s %s ", d.minClearance, d.id, d.title or ""))
            term.setBackgroundColor(ui.BG)
        end
        local event, key = os.pullEvent("key")
        if key == keys.up and selected > 1 then selected = selected - 1
        elseif key == keys.down and selected < #docs then selected = selected + 1
        elseif key == keys.enter then
            viewDoc(diskID, docs[selected].id)
        elseif key == keys.backspace then return end
    end
end

viewDoc = function(diskID, docId)
    local reply = fetchDoc(diskID, docId)
    if not reply or not reply.ok then
        ui.bigStatus(term.current(), {"ACCESS DENIED", "", reply and (reply.reason or "?"):upper() or "NO RESPONSE"}, "denied")
        sleep(2); return
    end
    local doc = reply.doc
    local scroll = 0
    -- wrap body text to column width
    local lines = {}
    local _, h = term.getSize()
    local w, _ = term.getSize()
    for line in (doc.body or ""):gmatch("[^\n]+") do
        local current = ""
        for word in line:gmatch("%S+") do
            if #current + #word + 1 > w - 4 then
                lines[#lines+1] = current; current = word
            else
                current = current == "" and word or (current.." "..word)
            end
        end
        if current ~= "" then lines[#lines+1] = current end
        lines[#lines+1] = ""  -- blank line between paragraphs
    end
    while true do
        ui.frame(term.current(), doc.id.." - "..(doc.title or ""), doc.folder)
        local visible = h - 6
        for i = 1, visible do
            local ln = lines[scroll + i]
            if not ln then break end
            term.setCursorPos(3, 4 + i); term.setTextColor(ui.FG)
            term.write(ln)
        end
        term.setCursorPos(2, h - 1); term.setTextColor(ui.DIM)
        term.write("arrows=scroll  BACKSPACE=back  L"..doc.minClearance.."+")
        local event, key = os.pullEvent("key")
        if key == keys.up and scroll > 0 then scroll = scroll - 1
        elseif key == keys.down and scroll < #lines - visible then scroll = scroll + 1
        elseif key == keys.pageUp then scroll = math.max(0, scroll - visible)
        elseif key == keys.pageDown then scroll = math.min(#lines - visible, scroll + visible)
        elseif key == keys.backspace then return end
    end
end

-- ============================================================
-- Main loop
-- ============================================================
while true do
    local diskID = waitForDisk()
    ui.bigStatus(term.current(), {"VERIFYING..."}, "working")
    local reply = fetchDocs(diskID)
    if not reply then
        ui.bigStatus(term.current(), {"MAINFRAME", "UNREACHABLE"}, "error"); sleep(2)
    elseif not reply.ok then
        ui.bigStatus(term.current(), {"CARD INVALID"}, "denied"); sleep(2)
    else
        ui.bigStatus(term.current(), {"ACCESS GRANTED", "", reply.person.name, "Clearance L"..reply.person.clearance}, "granted")
        sleep(1)
        browseFolders(diskID, reply)
    end
    -- wait for card removal
    while drive.getDiskID() do sleep(0.3) end
end

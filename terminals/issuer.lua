-- terminals/issuer.lua
-- Card issuer terminal. First-run wizard.

package.path = package.path .. ";/lib/?.lua"
local proto = require("ctnproto")
local ui    = require("ctnui")
local cfg   = require("ctnconfig")

local myCfg = cfg.loadOrWizard("issuer", {
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
if not drive then error("No disk drive attached") end

local DEPARTMENTS = {"Security","Research","MTF","Medical","Admin","Janitor","Guest","Ethics","Director"}

local function waitForDisk()
    ui.frame(term.current(), "ID ISSUANCE TERMINAL", "INSERT BLANK DISK")
    term.setCursorPos(2, 5); term.setTextColor(ui.FG)
    write("Status: ")
    term.setTextColor(ui.WARN); write("WAITING FOR DISK")
    term.setCursorPos(2, 7); term.setTextColor(ui.DIM)
    write("Insert a blank floppy into the drive to issue")
    term.setCursorPos(2, 8); write("a new CTN access card.")
    while not drive.getDiskID() do os.pullEvent("disk") end
    return drive.getDiskID()
end

local function issuanceFlow(diskID)
    ui.frame(term.current(), "ID ISSUANCE TERMINAL", "DISK #"..diskID)

    term.setCursorPos(2, 5); term.setTextColor(ui.FG)
    local passcode = ui.promptHidden("Issuer passcode: ")
    term.setCursorPos(2, 6)
    local issuedBy = ui.prompt("Your username:   ")
    term.setCursorPos(2, 7)
    local playerName = ui.prompt("Cardholder:      ")
    term.setCursorPos(2, 8)
    local clearance = tonumber(ui.prompt("Clearance (0-5): "))

    term.setCursorPos(2, 10); term.setTextColor(ui.FG); print("Department:")
    for i, d in ipairs(DEPARTMENTS) do
        term.setCursorPos(4, 10 + i)
        term.setTextColor(ui.DIM); write("["..i.."] ")
        term.setTextColor(ui.FG);  write(d)
    end
    term.setCursorPos(2, 11 + #DEPARTMENTS)
    term.setTextColor(ui.FG); write("> "); term.setTextColor(ui.ACCENT)
    local deptN = tonumber(read())
    local department = DEPARTMENTS[deptN] or "Guest"

    ui.bigStatus(term.current(), {"ISSUING CARD...","",playerName}, "working")

    local reply = proto.request(MAINFRAME, "issue_request", {
        passcode=passcode, diskID=diskID,
        playerName=playerName, clearance=clearance,
        department=department, issuedBy=issuedBy,
    }, 3)

    if not reply then
        ui.bigStatus(term.current(), {"MAINFRAME","UNREACHABLE"}, "error")
    elseif reply.ok then
        local mnt = drive.getMountPath()
        if mnt then
            local f = fs.open(mnt.."/id.txt","w")
            f.writeLine("========================")
            f.writeLine("  C.T.N ID ACCESS CARD  ")
            f.writeLine("========================")
            f.writeLine("Holder:     "..playerName)
            f.writeLine("Clearance:  L"..clearance)
            f.writeLine("Department: "..department)
            f.writeLine("Issued by:  "..issuedBy)
            f.close()
            drive.setDiskLabel(playerName.." L"..clearance)
        end
        ui.bigStatus(term.current(), {
            "CARD ISSUED", "",
            playerName, "L"..clearance.." "..department,
            "", "Remove disk to continue",
        }, "granted")
    else
        ui.bigStatus(term.current(), {"ISSUANCE FAILED","",string.upper(reply.reason or "?")}, "denied")
    end

    while drive.getDiskID() do sleep(0.3) end
    sleep(0.5)
end

while true do
    local diskID = waitForDisk()
    local ok, err = pcall(issuanceFlow, diskID)
    if not ok then
        ui.bigStatus(term.current(), {"TERMINAL ERROR","",tostring(err)}, "error"); sleep(3)
    end
end

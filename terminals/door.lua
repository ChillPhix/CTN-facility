-- terminals/door.lua
-- Door scanner terminal. First-run wizard replaces manual CONFIG editing.
--
-- Peripherals:
--   - wireless modem
--   - disk drive
--   - optional: advanced monitor
--   - optional: Advanced Peripherals Redstone Integrator, OR direct redstone.

package.path = package.path .. ";/lib/?.lua"
local proto = require("ctnproto")
local ui    = require("ctnui")
local cfg   = require("ctnconfig")

local myCfg = cfg.loadOrWizard("door", {
    {key="mainframe_id",  prompt="Mainframe computer ID", type="number", default=1},
    {key="door_label",    prompt="Door label (e.g. HCZ-173)", default="SECTOR ACCESS"},
    {key="rs_side",       prompt="Redstone output side",
     type="pick", options={"back","front","left","right","top","bottom"}, default="back"},
    {key="open_duration", prompt="Open duration (seconds)", type="number", default=3},
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

local monitor = findPeripheral("monitor")
if monitor then monitor.setTextScale(1) end

-- Announce ourselves to mainframe for admin approval
proto.request(MAINFRAME, "announce", {
    type = "door",
    hostname = os.getComputerLabel() or myCfg.door_label,
}, 2)

local function drawState(state, lines)
    ui.bigStatus(term.current(), lines, state)
    if monitor then ui.bigStatus(monitor, lines, state) end
end

local function setDoor(open)
    redstone.setOutput(myCfg.rs_side or "back", open)
end

-- Lockdown-aware state
local facilityState = "normal"
local zoneLock = false
local myZone = nil   -- not known until mainframe tells us via alert; until then, show generic

local function drawIdle()
    local bannerState = nil
    if facilityState == "lockdown" or facilityState == "breach" then
        bannerState = facilityState
    elseif zoneLock then
        bannerState = "lockdown"
    end

    if bannerState then
        -- Custom banner display on terminal + monitor
        for _, t in ipairs({term.current(), monitor}) do
            if t then
                ui.clear(t)
                ui.alertBanner(t, bannerState,
                    bannerState == "breach" and "CONTAINMENT BREACH" or "LOCKDOWN IN EFFECT")
                local w, h = t.getSize()
                ui.box(t, 2, 5, w - 2, h - 8, ui.ERR)
                t.setBackgroundColor(ui.BG); t.setTextColor(ui.ACCENT)
                local l = myCfg.door_label or "SECTOR ACCESS"
                t.setCursorPos(math.max(1, math.floor((w - #l)/2)+1), 7); t.write(l)
                local l2 = ">> INSERT ID CARD <<"
                t.setCursorPos(math.max(1, math.floor((w - #l2)/2)+1), 9); t.write(l2)
                t.setTextColor(ui.DIM)
                local l3 = "L<=2 personnel only during lockdown"
                t.setCursorPos(math.max(1, math.floor((w - #l3)/2)+1), 11); t.write(l3)
                ui.footer(t, "C.T.N  //  LOCKDOWN")
            end
        end
    else
        drawState("idle", {
            myCfg.door_label or "SECTOR ACCESS",
            "",
            ">>  INSERT ID CARD  <<",
            "",
            "Authorised personnel only.",
        })
    end
end

setDoor(false)
drawIdle()

local function processCard(diskID)
    drawState("working", {"VERIFYING...","","Contacting mainframe"})
    local reply = proto.request(MAINFRAME, "auth_request", {diskID=diskID}, 3)
    if not reply then
        drawState("error", {"MAINFRAME","UNREACHABLE"})
    elseif reply.granted then
        drawState("granted", {
            "ACCESS GRANTED", "",
            reply.person.name,
            "Clearance L"..reply.person.clearance,
            reply.person.department,
        })
        -- learn our zone from the reply so future alerts update correctly
        if reply.door and reply.door.zone then myZone = reply.door.zone end
        setDoor(true)
        sleep(myCfg.open_duration or 3)
        setDoor(false)
    else
        local pretty = ({
            insufficient_clearance = "INSUFFICIENT CLEARANCE",
            wrong_department       = "DEPARTMENT NOT AUTHORISED",
            facility_lockdown      = "FACILITY LOCKDOWN",
            zone_lockdown          = "ZONE LOCKDOWN",
            bad_disk               = "INVALID CARD",
            revoked                = "CARD REVOKED",
            lost                   = "CARD FLAGGED LOST",
            unregistered_terminal  = "TERMINAL NOT AUTHORISED",
        })[reply.reason] or string.upper(tostring(reply.reason or "UNKNOWN"))
        drawState("denied", {"ACCESS DENIED","",pretty})
    end
    sleep(2)
    while drive.getDiskID() do sleep(0.3) end
    drawIdle()
end

-- Single event loop: handles disk events, rednet alerts, and redraws.
while true do
    local evt = {os.pullEvent()}
    local etype = evt[1]
    if etype == "disk" then
        local diskID = drive.getDiskID()
        if not diskID then
            drawState("denied", {"INVALID MEDIA","","Not a valid ID card."})
            sleep(1.5); drawIdle()
        else
            processCard(diskID)
        end
    elseif etype == "rednet_message" then
        local message, proto_name = evt[3], evt[4]
        if proto_name == proto.PROTOCOL and type(message) == "table"
           and message.from == MAINFRAME then
            if message.type == "facility_alert" then
                local payload = message.payload or {}
                facilityState = payload.state or facilityState
                if myZone and payload.zones and payload.zones[myZone] then
                    zoneLock = payload.zones[myZone].lockdown or false
                end
                drawIdle()
            elseif message.type == "remote_open" then
                -- Remote open from tablet / control room
                local payload = message.payload or {}
                local duration = payload.duration or myCfg.open_duration or 3
                local openedBy = payload.openedBy or "REMOTE"
                drawState("granted", {
                    "REMOTE ACCESS", "",
                    "Opened by: "..openedBy,
                    "", "REMOTE OVERRIDE",
                })
                setDoor(true)
                sleep(duration)
                setDoor(false)
                sleep(1)
                drawIdle()
            end
        end
    end
end

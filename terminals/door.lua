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

local function idle()
    drawState("idle", {
        myCfg.door_label or "SECTOR ACCESS",
        "",
        ">>  INSERT ID CARD  <<",
        "",
        "Authorised personnel only.",
    })
end

setDoor(false)
idle()

local function mainLoop()
    while true do
        os.pullEvent("disk")
        local diskID = drive.getDiskID()
        if not diskID then
            drawState("denied", {"INVALID MEDIA","","Not a valid ID card."})
            sleep(1.5); idle()
        else
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
            idle()
        end
    end
end

local function alertLoop()
    -- Intentionally empty: running proto.receive here would race with
    -- the main loop's proto.request calls. If you want the door to
    -- react to lockdown broadcasts in real time, fold that into
    -- mainLoop using os.pullEvent.
    while true do sleep(60) end
end

parallel.waitForAny(mainLoop, alertLoop)

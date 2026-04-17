-- terminals/alarm.lua
-- Alarm / siren node. Receives alarm commands from the mainframe
-- and outputs redstone to drive sirens, flashing lights, etc.
--
-- Peripherals: wireless modem.
-- Config asks for mainframe ID and which redstone side to output on.

package.path = package.path .. ";/lib/?.lua"
local proto = require("ctnproto")
local ui    = require("ctnui")
local cfg   = require("ctnconfig")

local myCfg = cfg.loadOrWizard("alarm", {
    {key="mainframe_id", prompt="Mainframe computer ID", type="number", default=1},
    {key="rs_side", prompt="Redstone output side",
     type="pick", options={"back","front","left","right","top","bottom"}, default="back"},
})

proto.openModem()
local MAINFRAME = myCfg.mainframe_id
local RS_SIDE   = myCfg.rs_side

local state = {pattern = "off"}  -- "off" | "steady" | "pulse"

local function announce()
    proto.request(MAINFRAME, "announce", {
        type = "alarm",
        hostname = os.getComputerLabel() or ("alarm-"..os.getComputerID()),
    }, 2)
end

local function render()
    ui.clear(term.current())
    ui.header(term.current(), "ALARM NODE")
    term.setCursorPos(2, 5); term.setTextColor(ui.FG); term.write("Pattern: ")
    local c = ({off=ui.OK, steady=ui.ERR, pulse=ui.WARN})[state.pattern]
    term.setTextColor(c); term.write(state.pattern:upper())
    term.setCursorPos(2, 6); term.setTextColor(ui.DIM)
    term.write("Redstone out: "..RS_SIDE)
    term.setCursorPos(2, 7); term.setTextColor(ui.DIM)
    term.write("Mainframe ID: "..MAINFRAME)
    ui.footer(term.current(), "ID#"..os.getComputerID())
end

announce()
render()

-- Pulse loop for the siren
local function pulseLoop()
    while true do
        if state.pattern == "pulse" then
            redstone.setOutput(RS_SIDE, true); sleep(0.5)
            redstone.setOutput(RS_SIDE, false); sleep(0.5)
        elseif state.pattern == "steady" then
            redstone.setOutput(RS_SIDE, true); sleep(1)
        else
            redstone.setOutput(RS_SIDE, false); sleep(0.5)
        end
    end
end

local function netLoop()
    while true do
        local from, mtype, payload = proto.receive()
        if from == MAINFRAME and mtype == "alarm_set" then
            state.pattern = payload.pattern or "off"
            render()
        end
    end
end

parallel.waitForAny(pulseLoop, netLoop)

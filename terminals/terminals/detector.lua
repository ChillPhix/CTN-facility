-- terminals/detector.lua
-- Player detector node. Uses Advanced Peripherals' Player Detector
-- to report which players are in this zone to the mainframe.
--
-- Peripherals:
--   - wireless modem
--   - Advanced Peripherals "playerDetector"

package.path = package.path .. ";/lib/?.lua"
local proto = require("ctnproto")
local ui    = require("ctnui")
local cfg   = require("ctnconfig")

local myCfg = cfg.loadOrWizard("detector", {
    {key="mainframe_id", prompt="Mainframe computer ID", type="number", default=1},
    {key="radius",       prompt="Detection radius (blocks)", type="number", default=32},
})

proto.openModem()
ui.bootIdentity()
local MAINFRAME = myCfg.mainframe_id
local RADIUS    = myCfg.radius

local function findPeripheral(typeName)
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == typeName then return peripheral.wrap(side) end
    end
end

-- Advanced Peripherals Player Detector may expose as "playerDetector" or "player_detector"
local pd = peripheral.find("playerDetector") or peripheral.find("player_detector")
if not pd then
    -- try by side names
    pd = findPeripheral("playerDetector") or findPeripheral("player_detector")
end

if not pd then
    ui.clear(term.current())
    ui.header(term.current(), "DETECTOR NODE")
    term.setCursorPos(2, 5); term.setTextColor(ui.ERR)
    term.write("NO PLAYER DETECTOR FOUND")
    term.setCursorPos(2, 7); term.setTextColor(ui.FG)
    term.write("Attach an Advanced Peripherals")
    term.setCursorPos(2, 8)
    term.write("Player Detector to this computer.")
    ui.footer(term.current(), "WAITING")
    -- keep running so user can attach it, then reboot
    while true do sleep(5) end
end

local function announce()
    local _aReply = proto.request(MAINFRAME, "announce", {
        type = "detector",
        hostname = os.getComputerLabel() or ("detector-"..os.getComputerID()),
    }, 2)
    ui.syncIdentity(_aReply)
end

local state = {players = {}, lastSend = 0, registered = false}

local function render()
    ui.clear(term.current())
    ui.header(term.current(), "PLAYER DETECTOR")
    term.setCursorPos(2, 5); term.setTextColor(ui.FG)
    term.write("Radius: "..RADIUS.." blocks")
    term.setCursorPos(2, 6); term.setTextColor(ui.FG)
    term.write("Detected: "..#state.players)
    term.setCursorPos(2, 8); term.setTextColor(ui.ACCENT)
    term.write("Players in range:")
    for i, name in ipairs(state.players) do
        term.setCursorPos(4, 8 + i); term.setTextColor(ui.FG)
        term.write("- "..name)
        if 8 + i > select(2, term.getSize()) - 3 then break end
    end
    ui.footer(term.current(), state.registered and "LINKED" or "PENDING APPROVAL")
end

local function scan()
    -- Advanced Peripherals Player Detector exposes getPlayersInRange(range).
    -- Returns a list of player names (strings) within the given range.
    local ok, list = pcall(pd.getPlayersInRange, RADIUS)
    if ok and type(list) == "table" then
        state.players = list
    else
        state.players = {}
    end
end

announce()

while true do
    scan()
    local reply = proto.request(MAINFRAME, "detector_report", {players=state.players}, 2)
    if reply and reply.ok then state.registered = true
    else state.registered = false end
    render()
    sleep(3)
end

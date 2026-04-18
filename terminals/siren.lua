-- terminals/siren.lua
-- CTN Siren node. Plays Minecraft sounds through a Speaker peripheral
-- for different alert types, plus an optional redstone output for in-world
-- lighting / sirens.
--
-- Peripherals:
--   - wireless modem
--   - speaker (required)
--   - optional: redstone output side

package.path = package.path .. ";/lib/?.lua"
local proto = require("ctnproto")
local ui    = require("ctnui")
local cfg   = require("ctnconfig")

local myCfg = cfg.loadOrWizard("siren", {
    {key="mainframe_id", prompt="Mainframe computer ID", type="number", default=1},
    {key="rs_side",      prompt="Redstone out (or 'none')",
     type="pick", options={"none","back","front","left","right","top","bottom"}, default="none"},
    {key="volume",       prompt="Speaker volume (1-3)", type="number", default=3},
})

proto.openModem()
local MAINFRAME = myCfg.mainframe_id
local RS_SIDE   = myCfg.rs_side ~= "none" and myCfg.rs_side or nil
local VOLUME    = math.max(1, math.min(3, myCfg.volume or 3))

local speaker = peripheral.find("speaker")
if not speaker then
    ui.clear(term.current()); ui.header(term.current(), "SIREN ERROR")
    term.setCursorPos(2,5); term.setTextColor(ui.ERR); term.write("NO SPEAKER ATTACHED")
    term.setCursorPos(2,7); term.setTextColor(ui.FG); term.write("Attach a speaker peripheral.")
    while true do sleep(5) end
end

-- ============================================================
-- Sound patterns per alert state
-- Each pattern is {interval=seconds, sounds={sound_name, ...}}
-- Sounds play in sequence, then pause `interval`, then repeat.
-- ============================================================
local PATTERNS = {
    off = nil,
    pulse = {
        interval = 0.5,
        sounds = { "block.bell.use" },
    },
    steady = {
        interval = 1.0,
        sounds = { "block.beacon.activate" },
    },
    security = {
        interval = 0.4,
        sounds = { "block.note_block.pling", "block.note_block.pling" },
    },
    breach = {
        -- urgent, overlapping klaxon feel
        interval = 0.3,
        sounds = { "entity.wither.spawn", "block.beacon.deactivate" },
    },
    lockdown = {
        interval = 0.6,
        sounds = { "block.anvil.land", "block.note_block.bass" },
    },
    panic = {
        interval = 0.2,
        sounds = { "block.note_block.pling", "block.note_block.pling", "block.note_block.pling" },
    },
    allclear = {
        -- single play only
        once = true,
        sounds = { "block.note_block.chime", "block.note_block.chime" },
    },
}

-- ============================================================
-- Announce to mainframe
-- ============================================================
local function announce()
    proto.request(MAINFRAME, "announce", {
        type = "siren",
        hostname = os.getComputerLabel() or ("siren-"..os.getComputerID()),
    }, 2)
    -- Legacy "alarm" type also, so mainframe registers us under either name
    proto.request(MAINFRAME, "announce", {
        type = "alarm",
        hostname = os.getComputerLabel() or ("siren-"..os.getComputerID()),
    }, 2)
end

-- ============================================================
-- State + rendering
-- ============================================================
local state = {pattern = "off", registered = false, lastPlayed = 0}

local function render()
    ui.clear(term.current())
    ui.header(term.current(), "SIREN NODE")
    term.setCursorPos(2, 5); term.setTextColor(ui.FG); term.write("Pattern: ")
    local c = ({
        off=ui.OK, pulse=ui.WARN, steady=ui.ERR,
        security=ui.WARN, breach=ui.ERR, lockdown=ui.ERR,
        panic=ui.ERR, allclear=ui.OK,
    })[state.pattern] or ui.FG
    term.setTextColor(c); term.write(state.pattern:upper())
    term.setCursorPos(2, 7); term.setTextColor(ui.DIM)
    term.write("Redstone out: "..(RS_SIDE or "(none)"))
    term.setCursorPos(2, 8); term.write("Volume: "..VOLUME)
    term.setCursorPos(2, 9); term.write("Mainframe: #"..MAINFRAME)
    ui.footer(term.current(), state.registered and "LINKED" or "PENDING APPROVAL")
end

-- ============================================================
-- Playback loop
-- ============================================================
local function playLoop()
    while true do
        local pat = PATTERNS[state.pattern]
        if pat then
            for _, snd in ipairs(pat.sounds) do
                pcall(speaker.playSound, snd, VOLUME)
                sleep(0.12)
            end
            if RS_SIDE then
                redstone.setOutput(RS_SIDE, true); sleep(0.2)
                redstone.setOutput(RS_SIDE, false)
            end
            if pat.once then
                state.pattern = "off"; render(); sleep(0.1)
            else
                sleep(pat.interval)
            end
        else
            if RS_SIDE then redstone.setOutput(RS_SIDE, false) end
            sleep(0.5)
        end
    end
end

-- ============================================================
-- Network loop (accepts alarm_set and siren_set messages)
-- ============================================================
local function netLoop()
    while true do
        local from, mtype, payload = proto.receive()
        if from == MAINFRAME and (mtype == "alarm_set" or mtype == "siren_set") then
            state.pattern = payload.pattern or "off"
            state.registered = true
            render()
        end
    end
end

announce()
render()
parallel.waitForAny(playLoop, netLoop)

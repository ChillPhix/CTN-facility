-- N.O.V.A TAKEOVER PAYLOAD
-- Deploy: copy this to target's /startup.lua
-- The target computer is locked. Ctrl+T is caught. Ctrl+S/Ctrl+R
-- will reboot but this runs again on startup.
-- Only way out: break the computer block or boot from floppy.

-- Disable terminate
local oldPull = os.pullEvent
os.pullEvent = os.pullEventRaw

local PUR = colors.purple
local BLK = colors.black
local WHT = colors.white
local RED = colors.red
local GRN = colors.lime
local GRY = colors.gray
local CYN = colors.cyan
local MAG = colors.magenta

-- Find monitor too
local monitor
for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "monitor" then
        monitor = peripheral.wrap(side)
        monitor.setTextScale(0.5)
        break
    end
end

local SHIELD = {
    "        /\\        ",
    "       /  \\       ",
    "      / ** \\      ",
    "     / *  * \\     ",
    "    / *    * \\    ",
    "   /  * ** *  \\   ",
    "  /   *    *   \\  ",
    " /    * ++ *    \\ ",
    " \\    * ++ *    / ",
    "  \\   * ** *   /  ",
    "   \\  *    *  /   ",
    "    \\ * ** * /    ",
    "     \\      /     ",
    "      \\    /      ",
    "       \\  /       ",
    "        \\/        ",
}

-- Read motto/callsign from hidden config if present
local MOTTO = "In Shadows, We See All"
local CALLSIGN = "N.O.V.A"
if fs.exists("/.nova_payload_cfg") then
    local f = fs.open("/.nova_payload_cfg", "r")
    local s = f.readAll(); f.close()
    local ok, t = pcall(textutils.unserialize, s)
    if ok and t then
        MOTTO = t.motto or MOTTO
        CALLSIGN = t.callsign or CALLSIGN
    end
end

-- ============================================================
-- Phase 1: Glitch effect (system appears to malfunction)
-- ============================================================
local function glitchPhase(t)
    local w, h = t.getSize()

    -- Start with whatever was on screen, then corrupt it
    for i = 1, 15 do
        local gy = math.random(1, h)
        t.setCursorPos(1, gy)
        t.setBackgroundColor(BLK)
        t.setTextColor(({RED, PUR, GRN, WHT, CYN, MAG})[math.random(1, 6)])
        local noise = ""
        for j = 1, w do noise = noise .. string.char(math.random(33, 126)) end
        t.write(noise)
        sleep(0.04)
    end

    -- Flicker black
    for i = 1, 3 do
        t.setBackgroundColor(BLK); t.clear()
        sleep(0.1)
        t.setBackgroundColor(PUR); t.clear()
        sleep(0.05)
    end
    t.setBackgroundColor(BLK); t.clear()
    sleep(0.3)

    -- Fake error messages
    local errors = {
        "CRITICAL: kernel fault at 0x00F4A2",
        "STACK OVERFLOW: rednet handler",
        "WARNING: unauthorized access detected",
        "FATAL: security module compromised",
        "ERROR: filesystem integrity check FAILED",
        "WARNING: encryption keys corrupted",
        "CRITICAL: remote shell injected",
        "FATAL: unable to recover system state",
        "",
        "SYSTEM COMPROMISED",
    }

    local y = 2
    for _, line in ipairs(errors) do
        if y >= h then break end
        t.setCursorPos(2, y)
        if line:find("CRITICAL") or line:find("FATAL") then
            t.setTextColor(RED)
        elseif line:find("WARNING") then
            t.setTextColor(MAG)
        elseif line == "SYSTEM COMPROMISED" then
            t.setTextColor(RED)
        else
            t.setTextColor(GRY)
        end
        -- Type effect
        for i = 1, #line do
            t.write(line:sub(i, i))
            if i % 3 == 0 then sleep(0.01) end
        end
        y = y + 1
        sleep(0.15)
    end

    sleep(1)

    -- Screen goes black
    t.setBackgroundColor(BLK); t.clear()
    sleep(0.5)
end

-- ============================================================
-- Phase 2: Shield reveal with flash
-- ============================================================
local function shieldPhase(t)
    local w, h = t.getSize()
    t.setBackgroundColor(BLK); t.clear()

    local sy = math.max(1, math.floor((h - #SHIELD) / 2) - 3)

    -- Draw shield line by line
    for i, line in ipairs(SHIELD) do
        local x = math.max(1, math.floor((w - #line) / 2) + 1)
        t.setCursorPos(x, sy + i - 1)
        t.setTextColor(PUR)
        t.write(line)
        sleep(0.06)
    end

    sleep(0.2)

    -- Triple flash
    for flash = 1, 3 do
        t.setBackgroundColor(PUR); t.clear()
        sleep(0.04)
        t.setBackgroundColor(BLK); t.clear()
        for i, line in ipairs(SHIELD) do
            local x = math.max(1, math.floor((w - #line) / 2) + 1)
            t.setCursorPos(x, sy + i - 1)
            t.setTextColor(flash == 3 and WHT or PUR)
            t.write(line)
        end
        sleep(0.07)
    end

    -- Title animation
    local titleY = sy + #SHIELD + 1
    local title = "N . O . V . A"
    local tx = math.max(1, math.floor((w - #title) / 2) + 1)
    t.setTextColor(WHT)
    for i = 1, #title do
        t.setCursorPos(tx + i - 1, titleY)
        t.write(title:sub(i, i))
        sleep(0.05)
    end

    sleep(0.2)

    -- "SYSTEM SEIZED"
    local seized = ">> SYSTEM SEIZED <<"
    local sx = math.max(1, math.floor((w - #seized) / 2) + 1)
    t.setCursorPos(sx, titleY + 2)
    t.setTextColor(RED)
    t.write(seized)

    sleep(0.3)

    -- Motto
    local mottoLine = '"' .. MOTTO .. '"'
    local mx = math.max(1, math.floor((w - #mottoLine) / 2) + 1)
    t.setCursorPos(mx, titleY + 4)
    t.setTextColor(GRY)
    t.write(mottoLine)

    -- Callsign
    local csLine = "// " .. CALLSIGN .. " //"
    local cx = math.max(1, math.floor((w - #csLine) / 2) + 1)
    t.setCursorPos(cx, titleY + 6)
    t.setTextColor(CYN)
    t.write(csLine)
end

-- ============================================================
-- Phase 3: Lockout screen (permanent loop)
-- ============================================================
local function lockScreen(t)
    local w, h = t.getSize()

    while true do
        t.setBackgroundColor(BLK); t.clear()

        -- Header
        t.setCursorPos(1, 1); t.setBackgroundColor(PUR); t.setTextColor(BLK)
        t.write(string.rep(" ", w))
        local hdr = "N.O.V.A // SEIZED"
        t.setCursorPos(math.max(1, math.floor((w - #hdr) / 2) + 1), 1)
        t.write(hdr)
        t.setBackgroundColor(BLK)

        -- Shield (smaller, centered)
        local miniShield = {
            "    /\\    ",
            "   / *\\   ",
            "  / ** \\  ",
            " / *++* \\ ",
            " \\ *++* / ",
            "  \\ ** /  ",
            "   \\*/   ",
            "    \\/    ",
        }

        local sy = math.max(3, math.floor((h - #miniShield) / 2) - 3)
        for i, line in ipairs(miniShield) do
            local x = math.max(1, math.floor((w - #line) / 2) + 1)
            t.setCursorPos(x, sy + i - 1)
            t.setTextColor(PUR); t.write(line)
        end

        -- Messages
        local my = sy + #miniShield + 1
        local msgs = {
            {"THIS SYSTEM HAS BEEN SEIZED", RED},
            {"", WHT},
            {"All data has been extracted.", GRY},
            {"All credentials compromised.", GRY},
            {"All communications logged.", GRY},
            {"", WHT},
            {'"' .. MOTTO .. '"', PUR},
            {"", WHT},
            {"// " .. CALLSIGN .. " //", CYN},
        }

        for _, msg in ipairs(msgs) do
            if my >= h - 1 then break end
            local text, col = msg[1], msg[2]
            local mx = math.max(1, math.floor((w - #text) / 2) + 1)
            t.setCursorPos(mx, my); t.setTextColor(col); t.write(text)
            my = my + 1
        end

        -- Footer
        t.setCursorPos(1, h); t.setBackgroundColor(PUR); t.setTextColor(BLK)
        t.write(string.rep(" ", w))
        local ft = os.date("%H:%M:%S") .. "  LOCKED"
        t.setCursorPos(math.max(1, w - #ft), h); t.write(ft)
        t.setBackgroundColor(BLK)

        -- Random glitch line every few seconds
        sleep(2 + math.random() * 3)
        local gy = math.random(3, h - 2)
        t.setCursorPos(1, gy); t.setTextColor(({PUR, RED, MAG})[math.random(1, 3)])
        local noise = ""
        for i = 1, w do noise = noise .. string.char(math.random(33, 126)) end
        t.write(noise)
        sleep(0.15)
    end
end

-- ============================================================
-- Run the takeover
-- ============================================================

-- Disable all other startup programs
-- (this file IS startup.lua, so we're already first)

local targets = {term.current()}
if monitor then targets[#targets+1] = monitor end

-- Phase 1: Glitch on all screens
for _, t in ipairs(targets) do
    glitchPhase(t)
end

-- Phase 2: Shield reveal on all screens
for _, t in ipairs(targets) do
    shieldPhase(t)
end

sleep(3)

-- Phase 3: Permanent lock screen
-- Run on both screens in parallel
if monitor then
    parallel.waitForAny(
        function() lockScreen(term.current()) end,
        function() lockScreen(monitor) end
    )
else
    lockScreen(term.current())
end

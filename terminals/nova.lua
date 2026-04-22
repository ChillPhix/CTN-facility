-- terminals/nova.lua
-- [CLASSIFIED] N.O.V.A PROJECT — NETWORK OFFENSIVE & VULNERABILITY ARSENAL
-- Universal ComputerCraft network penetration framework.
-- Works against ANY program, ANY protocol, ANY system.

package.path = package.path .. ";/lib/?.lua"
local ui  = require("ctnui")
local cfg = require("ctnconfig")

local myCfg = cfg.loadOrWizard("nova", {
    {key="motto",    prompt="Operational motto", default="In Shadows, We See All"},
    {key="callsign", prompt="Operator callsign", default="SPECTER"},
})
local MOTTO    = myCfg.motto
local CALLSIGN = myCfg.callsign

-- ============================================================
-- Colors
-- ============================================================
local PUR=colors.purple  local BLK=colors.black local WHT=colors.white
local GRY=colors.gray    local RED=colors.red   local GRN=colors.lime
local YEL=colors.yellow  local CYN=colors.cyan  local MAG=colors.magenta

-- ============================================================
-- Find all modems and open them RAW (not via rednet)
-- ============================================================
local modems = {}
for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "modem" then
        local m = peripheral.wrap(side)
        -- RAW modem only — do NOT use rednet.open()
        -- This makes N.O.V.A invisible on the network.
        -- Channel 65535 = rednet traffic
        m.open(65535)
        -- Also open common channels for non-rednet traffic
        for ch = 1, 128 do pcall(m.open, ch) end
        modems[#modems+1] = {peripheral=m, side=side, isWireless=m.isWireless and m.isWireless()}
    end
end

-- Find monitor
local monitor
for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "monitor" then
        monitor = peripheral.wrap(side); monitor.setTextScale(0.5); break
    end
end

-- Find disk drive
local drive
for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "drive" then drive = peripheral.wrap(side); break end
end

-- ============================================================
-- Data stores
-- ============================================================
local captures = {}        -- all intercepted messages
local rawCaptures = {}     -- raw modem_message captures
local knownHosts = {}      -- {id = {lastSeen, channels={}, msgCount, protocols={}, types={}, rawMsgs={}}}
local knownProtocols = {}  -- {name = {count, hosts={}}}
local crackerJobs = {}     -- {id = {target_msg, status, attempts, secret_found, wordlist}}
local stolenCards = {}     -- {diskID, ts, label}
local MAX_CAPTURES = 1000
local MAX_RAW = 500
local scanning = true      -- always-on background scanning

-- ============================================================
-- Persistence
-- ============================================================
local function saveData()
    -- Save captures
    local f = fs.open("/.nova_captures", "w")
    local start = math.max(1, #captures - 200)
    for i = start, #captures do
        f.writeLine(textutils.serialize(captures[i], {compact=true}))
    end
    f.close()
    -- Save hosts
    local hd = {}
    for id, h in pairs(knownHosts) do
        hd[id] = {lastSeen=h.lastSeen, msgCount=h.msgCount,
                  protocols=h.protocols, types=h.types, channels=h.channels}
    end
    local f2 = fs.open("/.nova_hosts", "w")
    f2.write(textutils.serialize(hd)); f2.close()
    -- Save stolen cards
    if #stolenCards > 0 then
        local f3 = fs.open("/.nova_stolen_cards", "w")
        for _, c in ipairs(stolenCards) do
            f3.writeLine(textutils.serialize(c, {compact=true}))
        end; f3.close()
    end
end

local function loadData()
    if fs.exists("/.nova_captures") then
        local f = fs.open("/.nova_captures", "r")
        while true do
            local l = f.readLine(); if not l then break end
            local ok, e = pcall(textutils.unserialize, l)
            if ok and e then captures[#captures+1] = e end
        end; f.close()
    end
    if fs.exists("/.nova_hosts") then
        local f = fs.open("/.nova_hosts", "r")
        local s = f.readAll(); f.close()
        local ok, t = pcall(textutils.unserialize, s)
        if ok and type(t) == "table" then
            for id, h in pairs(t) do knownHosts[id] = h end
        end
    end
    if fs.exists("/.nova_stolen_cards") then
        local f = fs.open("/.nova_stolen_cards", "r")
        while true do
            local l = f.readLine(); if not l then break end
            local ok, e = pcall(textutils.unserialize, l)
            if ok and e then stolenCards[#stolenCards+1] = e end
        end; f.close()
    end
end
loadData()

local function tblCount(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end

-- ============================================================
-- Core engine: process ANY intercepted message
-- ============================================================
local function processRaw(side, channel, replyChannel, message, distance)
    local entry = {
        ts = os.epoch("utc"),
        channel = channel,
        replyChannel = replyChannel,
        distance = distance,
        side = side,
        raw = true,
    }

    -- Try to extract useful info from the message
    if type(message) == "table" then
        entry.msgType = message.type or message.sType or "?"
        entry.protocol = message.sProtocol or message.proto or message.protocol or nil
        entry.from = message.nMessageID and "rednet" or (message.from or "?")
        entry.hasSig = message.sig ~= nil
        entry.nonce = message.nonce
        entry.msgTs = message.ts
        -- Rednet wrapper detection
        if message.nMessageID and message.message then
            -- This is a rednet-wrapped message
            entry.rednetId = message.nMessageID
            entry.protocol = message.sProtocol
            local inner = message.message
            if type(inner) == "table" then
                entry.msgType = inner.type or "?"
                entry.from = inner.from or replyChannel
                entry.hasSig = inner.sig ~= nil
                entry.nonce = inner.nonce
                entry.innerTs = inner.ts
                entry.version = inner.version
                entry.proto = inner.proto
                entry.payloadKeys = {}
                if inner.payload and type(inner.payload) == "table" then
                    for k in pairs(inner.payload) do
                        entry.payloadKeys[#entry.payloadKeys+1] = k
                    end
                end
                -- Store full inner envelope for cracking
                entry.envelope = inner
            else
                entry.plaintext = tostring(inner):sub(1, 200)
            end
        else
            entry.payloadKeys = {}
            if message.payload and type(message.payload) == "table" then
                for k in pairs(message.payload) do
                    entry.payloadKeys[#entry.payloadKeys+1] = k
                end
            end
            entry.envelope = message
        end
    elseif type(message) == "string" then
        entry.plaintext = message:sub(1, 200)
        entry.msgType = "string"
        entry.from = replyChannel
    elseif type(message) == "number" then
        entry.plaintext = tostring(message)
        entry.msgType = "number"
        entry.from = replyChannel
    else
        entry.msgType = type(message)
        entry.from = replyChannel
    end

    rawCaptures[#rawCaptures+1] = entry
    while #rawCaptures > MAX_RAW do table.remove(rawCaptures, 1) end

    -- Also add to main captures
    captures[#captures+1] = entry
    while #captures > MAX_CAPTURES do table.remove(captures, 1) end

    -- Update host tracking (use replyChannel as host ID for raw)
    local hostId = entry.from ~= "?" and tostring(entry.from) or tostring(replyChannel)
    if not knownHosts[hostId] then
        knownHosts[hostId] = {lastSeen=0, channels={}, msgCount=0, protocols={}, types={}}
    end
    local host = knownHosts[hostId]
    host.lastSeen = os.epoch("utc")
    host.msgCount = host.msgCount + 1
    host.channels[channel] = (host.channels[channel] or 0) + 1
    if entry.protocol then
        host.protocols[entry.protocol] = (host.protocols[entry.protocol] or 0) + 1
    end
    if entry.msgType then
        host.types[entry.msgType] = (host.types[entry.msgType] or 0) + 1
    end

    -- Update protocol tracking
    if entry.protocol then
        if not knownProtocols[entry.protocol] then
            knownProtocols[entry.protocol] = {count=0, hosts={}}
        end
        knownProtocols[entry.protocol].count = knownProtocols[entry.protocol].count + 1
        knownProtocols[entry.protocol].hosts[hostId] = true
    end
end

-- Also capture rednet-level messages
local function processRednet(sender, message, protocol)
    local entry = {
        ts = os.epoch("utc"),
        from = sender,
        protocol = protocol or "?",
        channel = 65535,
        raw = false,
    }
    if type(message) == "table" then
        entry.msgType = message.type or "?"
        entry.hasSig = message.sig ~= nil
        entry.version = message.version
        entry.nonce = message.nonce
        entry.msgTs = message.ts
        entry.proto = message.proto
        entry.payloadKeys = {}
        if message.payload and type(message.payload) == "table" then
            for k in pairs(message.payload) do entry.payloadKeys[#entry.payloadKeys+1] = k end
        end
        entry.envelope = message
    else
        entry.plaintext = tostring(message):sub(1, 200)
        entry.msgType = type(message)
    end

    captures[#captures+1] = entry
    while #captures > MAX_CAPTURES do table.remove(captures, 1) end

    local hostId = tostring(sender)
    if not knownHosts[hostId] then
        knownHosts[hostId] = {lastSeen=0, channels={}, msgCount=0, protocols={}, types={}}
    end
    local host = knownHosts[hostId]
    host.lastSeen = os.epoch("utc")
    host.msgCount = host.msgCount + 1
    if protocol then
        host.protocols[protocol] = (host.protocols[protocol] or 0) + 1
    end
    if entry.msgType then host.types[entry.msgType] = (host.types[entry.msgType] or 0) + 1 end

    if protocol then
        if not knownProtocols[protocol] then knownProtocols[protocol] = {count=0, hosts={}} end
        knownProtocols[protocol].count = knownProtocols[protocol].count + 1
        knownProtocols[protocol].hosts[hostId] = true
    end
end

-- ============================================================
-- HMAC cracker (brute force)
-- ============================================================
local sha256, hmac
do
    -- Import from ctnproto
    local p = require("ctnproto")
    sha256 = p.sha256
    hmac = p.hmac
end

local function canonical(envelope)
    local function ser(v)
        local t = type(v)
        if t == "nil" then return "N"
        elseif t == "boolean" then return v and "T" or "F"
        elseif t == "number" then return "n:"..string.format("%.14g", v)
        elseif t == "string" then return "s:"..#v..":"..v
        elseif t == "table" then
            local keys = {}
            for k in pairs(v) do keys[#keys+1] = k end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            local parts = {"{"}
            for _, k in ipairs(keys) do parts[#parts+1] = ser(k).."="..ser(v[k])..";" end
            parts[#parts+1] = "}"; return table.concat(parts)
        else return "?:"..t end
    end
    local keys = {}
    for k in pairs(envelope) do if k ~= "sig" then keys[#keys+1] = k end end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts+1] = k.."="..ser(envelope[k]) end
    return table.concat(parts, "&")
end

local DEFAULT_WORDLIST = {
    -- Common weak secrets
    "secret","password","1234","12345","123456","admin","test",
    "pass","letmein","welcome","monkey","dragon","master","abc123",
    "MYSECRET","changeme","default","root","toor","minecraft",
    "computercraft","ctn","facility","security","classified",
    "overseer","containment","breach","lockdown","rednet",
    -- Short patterns
    "aaa","bbb","ccc","111","222","333","000",
    "password1","admin123","test123","pass123",
}

local function crackAttempt(envelope, candidateSecret)
    local can = canonical(envelope)
    local computed = hmac(candidateSecret, can)
    return computed == envelope.sig
end

-- ============================================================
-- UI helpers
-- ============================================================
local function novaHeader(t, subtitle)
    t = t or term.current()
    local w = select(1, t.getSize())
    t.setCursorPos(1, 1); t.setBackgroundColor(PUR); t.setTextColor(BLK)
    t.write(string.rep(" ", w))
    local title = "N.O.V.A // "..CALLSIGN
    t.setCursorPos(math.max(1, math.floor((w-#title)/2)+1), 1); t.write(title)
    t.setCursorPos(1, 2); t.setBackgroundColor(BLK); t.setTextColor(PUR)
    t.write(string.rep(" ", w))
    if subtitle then
        t.setCursorPos(math.max(1, math.floor((w-#subtitle)/2)+1), 2); t.write(subtitle)
    end
    t.setCursorPos(1, 3); t.setTextColor(PUR); t.write(string.rep("=", w))
    t.setBackgroundColor(BLK)
end

local function novaFooter(t, text)
    t = t or term.current()
    local w, h = t.getSize()
    t.setCursorPos(1, h); t.setBackgroundColor(PUR); t.setTextColor(BLK)
    t.write(string.rep(" ", w))
    if text then t.setCursorPos(2, h); t.write(text:sub(1, w-2)) end
    t.setBackgroundColor(BLK); t.setTextColor(PUR)
end

local function novaClear(t)
    t = t or term.current()
    t.setBackgroundColor(BLK); t.setTextColor(PUR); t.clear(); t.setCursorPos(1,1)
end

local function novaStatus(lines, state)
    novaClear(); novaHeader(nil, "OPERATION")
    local w, h = term.getSize()
    local col = ({working=YEL, ok=GRN, fail=RED, info=CYN})[state] or PUR
    local boxH = math.min(#lines + 4, h - 6)
    local boxY = math.floor((h - boxH) / 2) + 1
    ui.box(term.current(), 2, boxY, w-2, boxH, col)
    for i, line in ipairs(lines) do
        term.setCursorPos(math.max(1, math.floor((w-#line)/2)+1), boxY+1+i)
        term.setTextColor(col); term.write(line)
    end
    novaFooter(nil, "N.O.V.A // "..string.upper(state or ""))
end

local function scrollList(title, items, footer)
    local selected, top = 1, 1
    while true do
        novaClear(); novaHeader(nil, title)
        local w, h = term.getSize()
        local rows = h - 5
        top = math.max(1, math.min(top, math.max(1, #items-rows+1)))
        if #items == 0 then
            term.setCursorPos(2, 5); term.setTextColor(GRY); term.write("(no data)")
        else
            for row = 1, rows do
                local idx = top + row - 1; local item = items[idx]
                if not item then break end
                term.setCursorPos(1, 3+row)
                if idx == selected then
                    term.setBackgroundColor(PUR); term.setTextColor(BLK)
                else
                    term.setBackgroundColor(BLK); term.setTextColor(item.color or PUR)
                end
                local line = (idx==selected and " > " or "   ")..(item.label or "?")
                term.write(line:sub(1,w)); term.write(string.rep(" ", math.max(0,w-#line)))
                term.setBackgroundColor(BLK)
            end
        end
        novaFooter(nil, footer or "ENTER=select  Q=back")
        local evt = {os.pullEvent()}
        if evt[1] == "key" then
            if evt[2] == keys.up and selected > 1 then selected=selected-1; if selected<top then top=selected end
            elseif evt[2] == keys.down and selected < #items then selected=selected+1; if selected>=top+rows then top=top+1 end
            elseif evt[2] == keys.enter and items[selected] then return selected, items[selected]
            elseif evt[2] == keys.q or evt[2] == keys.backspace then return nil end
        elseif evt[1] == "mouse_click" then
            local idx = top + (evt[4]-4)
            if idx >= 1 and idx <= #items then return idx, items[idx] end
        elseif evt[1] == "mouse_scroll" then
            top = math.max(1, math.min(math.max(1,#items-rows+1), top+evt[2]))
        -- Keep capturing even while in menus
        elseif evt[1] == "modem_message" then
            processRaw(evt[2], evt[3], evt[4], evt[5], evt[6])
        end
    end
end

-- ============================================================
-- Monitor: live feed
-- ============================================================
local function drawMonitorFeed()
    if not monitor then return end
    local w, h = monitor.getSize()
    monitor.setBackgroundColor(BLK); monitor.clear()

    novaHeader(monitor, "LIVE INTERCEPT")
    local phase = math.floor(os.epoch("utc") / 300) % 4
    local scanAnim = ({"|","/","-","\\"})[phase+1]

    monitor.setCursorPos(1, 4); monitor.setTextColor(GRN)
    monitor.write(" "..scanAnim.." "..#captures.." cap | "..tblCount(knownHosts).." hosts | "..tblCount(knownProtocols).." proto")
    monitor.setCursorPos(1, 5); monitor.setTextColor(PUR); monitor.write(string.rep("-", w))

    local feedStart = 6
    local feedRows = h - feedStart - 1
    local startIdx = math.max(1, #captures - feedRows + 1)
    for row = 0, feedRows - 1 do
        local c = captures[startIdx + row]
        if not c then break end
        local y = feedStart + row
        local ts = os.date("%H:%M:%S", (c.ts or 0) / 1000)
        monitor.setCursorPos(1, y); monitor.setTextColor(GRY); monitor.write(ts.." ")
        monitor.setTextColor(PUR); monitor.write(("#"..tostring(c.from or "?"):sub(1,5)):sub(1,6).." ")
        local pCol = WHT
        if c.protocol and type(c.protocol) == "string" then
            if c.protocol:find("CTN") or c.protocol:find("ctn") then pCol = YEL
            elseif c.protocol == "dns" or c.protocol == "gps" then pCol = CYN end
        end
        monitor.setTextColor(pCol)
        monitor.write((tostring(c.protocol or c.channel or "?"):sub(1, 8)).." ")
        monitor.setTextColor(c.hasSig and RED or GRN)
        monitor.write(tostring(c.msgType or c.plaintext or "?"):sub(1, w - 24))
    end

    novaFooter(monitor, CALLSIGN.."  "..os.date("%H:%M:%S").."  "..scanAnim.."  RAW+REDNET")
end

-- ============================================================
-- Boot animation
-- ============================================================
local function bootSequence()
    local targets = {term.current()}
    if monitor then targets[#targets+1] = monitor end

    for _, t in ipairs(targets) do t.setBackgroundColor(BLK); t.clear() end

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

    local bootLines = {
        {delay=0.15, text="NOVA KERNEL v3.0 LOADING...", color=GRY},
        {delay=0.1,  text="CRYPTOGRAPHIC ENGINE: ONLINE", color=GRN},
        {delay=0.1,  text="RAW MODEM ACCESS: ENABLED", color=GRN},
        {delay=0.1,  text="REDNET INTERCEPT: ENABLED", color=GRN},
        {delay=0.1,  text="CHANNEL SNIFFER: "..#modems.." modem(s)", color=GRN},
        {delay=0.15, text="HMAC CRACKER: LOADED", color=PUR},
        {delay=0.1,  text="SIGNAL JAMMER: LOADED", color=PUR},
        {delay=0.1,  text="IMPERSONATOR: LOADED", color=PUR},
        {delay=0.1,  text="DISK CLONER: LOADED", color=PUR},
        {delay=0.1,  text="KEYLOGGER: LOADED", color=PUR},
        {delay=0.1,  text="MITM ENGINE: LOADED", color=PUR},
        {delay=0.3,  text="ALL SYSTEMS NOMINAL", color=GRN},
    }

    local y = 2
    for _, line in ipairs(bootLines) do
        for _, t in ipairs(targets) do
            local _, th = t.getSize()
            if y >= th - 1 then t.scroll(1) end
            t.setCursorPos(2, math.min(y, th-1))
            t.setBackgroundColor(BLK); t.setTextColor(line.color)
            t.write(line.text)
        end
        y = y + 1; sleep(line.delay)
    end
    sleep(0.3)

    -- Shield splash
    for _, t in ipairs(targets) do
        t.setBackgroundColor(BLK); t.clear()
        local w, h = t.getSize()
        local sy = math.max(1, math.floor((h - #SHIELD)/2) - 2)
        for i, line in ipairs(SHIELD) do
            t.setCursorPos(math.max(1, math.floor((w-#line)/2)+1), sy+i-1)
            t.setTextColor(PUR); t.write(line)
        end
    end
    sleep(0.3)

    -- Flash
    for flash = 1, 3 do
        for _, t in ipairs(targets) do t.setBackgroundColor(PUR); t.clear() end
        sleep(0.04)
        for _, t in ipairs(targets) do
            t.setBackgroundColor(BLK); t.clear()
            local w, h = t.getSize()
            local sy = math.max(1, math.floor((h-#SHIELD)/2)-2)
            for i, line in ipairs(SHIELD) do
                t.setCursorPos(math.max(1, math.floor((w-#line)/2)+1), sy+i-1)
                t.setTextColor(flash==3 and WHT or PUR); t.write(line)
            end
        end
        sleep(0.06)
    end

    -- Title
    for _, t in ipairs(targets) do
        local w, h = t.getSize()
        local ty = math.max(1, math.floor((h-#SHIELD)/2)-2) + #SHIELD + 1
        local title = "N . O . V . A"
        t.setTextColor(WHT)
        for i = 1, #title do
            t.setCursorPos(math.max(1, math.floor((w-#title)/2)+1)+i-1, ty)
            t.write(title:sub(i,i))
        end
        t.setCursorPos(math.max(1, math.floor((w-34)/2)+1), ty+1)
        t.setTextColor(PUR); t.write("P R O J E C T   O V E R S I G H T")
        t.setCursorPos(math.max(1, math.floor((w-#MOTTO-2)/2)+1), ty+3)
        t.setTextColor(GRY); t.write('"'..MOTTO..'"')
        t.setCursorPos(math.max(1, math.floor((w-10-#CALLSIGN)/2)+1), ty+5)
        t.setTextColor(CYN); t.write("OPERATOR: "..CALLSIGN)
    end
    sleep(1.5)

    -- Glitch
    for g = 1, 8 do
        for _, t in ipairs(targets) do
            local w, h = t.getSize()
            local gy = math.random(1, h)
            t.setCursorPos(1, gy); t.setTextColor(({PUR,RED,GRN,CYN,MAG})[math.random(1,5)])
            local noise = ""; for i=1,w do noise=noise..string.char(math.random(33,126)) end
            t.write(noise)
        end
        sleep(0.03)
    end
    sleep(0.2)
end

-- ============================================================
-- Tools
-- ============================================================

-- Tool 1: Live Scanner (with raw modem + rednet)
local function scannerView()
    local startCount = #captures
    local refreshTimer = os.startTimer(0.4)
    while true do
        novaClear(); novaHeader(nil, "OMNISCANNER // RAW + REDNET")
        local w, h = term.getSize()
        local nc = #captures - startCount
        local phase = math.floor(os.epoch("utc")/300) % 4
        local anim = ({"|","/","-","\\"})[phase+1]

        term.setCursorPos(2,5); term.setTextColor(GRN)
        term.write(">> "..nc.." new  ("..#captures.." total)  ["..anim.."]")
        term.setCursorPos(2,6); term.setTextColor(PUR)
        term.write(">> "..tblCount(knownHosts).." hosts  "..tblCount(knownProtocols).." protocols")
        term.setCursorPos(2,7); term.write(">> "..#rawCaptures.." raw modem  "..#modems.." modem(s)")
        term.setCursorPos(2,9); term.setTextColor(CYN); term.write("LIVE:")
        term.setCursorPos(2,10); term.setTextColor(PUR); term.write(string.rep("-", w-2))

        local y = 11
        for i = math.max(1, #captures-(h-y-2)), #captures do
            if y >= h-1 then break end
            local c = captures[i]; if not c then break end
            local ts = os.date("%H:%M:%S", (c.ts or 0)/1000)
            term.setCursorPos(2,y); term.setTextColor(GRY); term.write(ts.." ")
            term.setTextColor(PUR); term.write(("#"..tostring(c.from or "?"):sub(1,5)):sub(1,6).." ")
            term.setTextColor(WHT); term.write(tostring(c.protocol or c.channel or "?"):sub(1,8).." ")
            term.setTextColor(c.hasSig and YEL or GRN)
            term.write(tostring(c.msgType or "?"):sub(1, w-28))
            y = y + 1
        end
        novaFooter(nil, "Q=stop  "..anim.." scanning  RAW+REDNET")
        pcall(drawMonitorFeed)

        local evt = {os.pullEvent()}
        if evt[1] == "modem_message" then processRaw(evt[2], evt[3], evt[4], evt[5], evt[6])
        elseif evt[1] == "timer" and evt[2] == refreshTimer then refreshTimer = os.startTimer(0.4)
        elseif evt[1] == "key" and evt[2] == keys.q then
            saveData()
            novaStatus({"SCANNER STOPPED","",nc.." new captures",#captures.." total"}, "ok")
            sleep(1.5); return
        end
    end
end

-- Tool 2: Host Intel
local function hostIntel()
    local items = {}
    for id, h in pairs(knownHosts) do
        local age = math.floor((os.epoch("utc") - (h.lastSeen or 0)) / 1000)
        local protos = {}
        for p in pairs(h.protocols or {}) do protos[#protos+1] = p end
        items[#items+1] = {
            label = string.format("#%-5s %4dmsg %s", id, h.msgCount or 0, table.concat(protos,","):sub(1,18)),
            host=h, id=id,
            color = age < 10 and GRN or (age < 60 and YEL or GRY),
        }
    end
    table.sort(items, function(a,b) return (a.host.msgCount or 0) > (b.host.msgCount or 0) end)
    local idx, item = scrollList("HOST INTEL // "..tblCount(knownHosts).." TARGETS", items)
    if not idx then return end

    novaClear(); novaHeader(nil, "TARGET #"..item.id)
    local w, sh = term.getSize(); local y = 5
    local function line(l,v,c) if y>=sh-2 then return end
        term.setCursorPos(2,y); term.setTextColor(PUR); term.write(l..": ")
        term.setTextColor(c or WHT); term.write(tostring(v):sub(1,w-#l-5)); y=y+1 end
    line("ID", item.id, CYN)
    line("Messages", item.host.msgCount or 0)
    line("Last seen", os.date("%H:%M:%S", ((item.host.lastSeen or 0))/1000))
    local active = (os.epoch("utc") - (item.host.lastSeen or 0)) < 10000
    line("Status", active and "ACTIVE" or "COLD", active and GRN or RED)
    y=y+1; term.setCursorPos(2,y); term.setTextColor(CYN); term.write("PROTOCOLS:"); y=y+1
    for p, count in pairs(item.host.protocols or {}) do
        if y>=sh-3 then break end
        term.setCursorPos(4,y); term.setTextColor(GRY); term.write(p..": "..count); y=y+1
    end
    y=y+1; term.setCursorPos(2,y); term.setTextColor(CYN); term.write("MSG TYPES:"); y=y+1
    for t, count in pairs(item.host.types or {}) do
        if y>=sh-2 then break end
        term.setCursorPos(4,y); term.setTextColor(GRY); term.write(t..": "..count); y=y+1
    end
    novaFooter(nil, "Any key"); os.pullEvent("key")
end

-- Tool 3: Protocol Analysis
local function protocolAnalysis()
    local items = {}
    for name, p in pairs(knownProtocols) do
        items[#items+1] = {
            label = string.format("%-12s %4dmsg %dhosts", name:sub(1,12), p.count, tblCount(p.hosts)),
            protocol=p, name=name,
        }
    end
    table.sort(items, function(a,b) return a.protocol.count > b.protocol.count end)
    local idx, item = scrollList("PROTOCOLS", items)
    if not idx then return end
    local hi = {}
    for hid in pairs(item.protocol.hosts) do hi[#hi+1] = {label="#"..hid} end
    scrollList("HOSTS ON: "..item.name, hi)
end

-- Tool 4: Capture Viewer
local function captureViewer()
    local items = {}
    for i = #captures, math.max(1, #captures-100), -1 do
        local c = captures[i]; if not c then break end
        local ts = os.date("%H:%M:%S", (c.ts or 0)/1000)
        local src = tostring(c.from or c.replyChannel or "?"):sub(1,5)
        items[#items+1] = {
            label = ts.." #"..src.." "..(c.protocol or c.channel or "?").." "..tostring(c.msgType or "?"),
            capture=c, color = c.hasSig and YEL or (c.plaintext and GRN or GRY),
        }
    end
    local idx, item = scrollList("CAPTURES // "..#captures, items, "ENTER=inspect  Q=back")
    if not idx then return end
    local c = item.capture
    novaClear(); novaHeader(nil, "INTERCEPT")
    local w, h = term.getSize(); local y = 5
    local function line(l,v,col) if y>=h-2 then return end
        term.setCursorPos(2,y); term.setTextColor(PUR); term.write(l..": ")
        term.setTextColor(col or WHT); term.write(tostring(v):sub(1,w-#l-5)); y=y+1 end
    line("Time", os.date("%H:%M:%S", (c.ts or 0)/1000))
    line("Source", c.from or c.replyChannel or "?", CYN)
    line("Channel", c.channel or "?")
    line("Protocol", c.protocol or "?")
    line("Type", c.msgType or "?")
    line("Signed", c.hasSig and "YES (HMAC)" or "NO", c.hasSig and RED or GRN)
    if c.nonce then line("Nonce", c.nonce) end
    if c.version then line("Version", c.version) end
    if c.distance then line("Distance", c.distance.." blocks") end
    if c.payloadKeys and #c.payloadKeys > 0 then line("Fields", table.concat(c.payloadKeys, ", ")) end
    if c.plaintext then line("Plaintext", c.plaintext, GRN) end
    novaFooter(nil, "C=crack this  any=back")
    local _, k = os.pullEvent("key")
    if k == keys.c and c.envelope and c.hasSig then
        -- Launch cracker on this envelope
        crackerJobs[#crackerJobs+1] = {envelope=c.envelope, status="pending", attempts=0}
        novaStatus({"CRACKER JOB QUEUED","","Job #"..#crackerJobs}, "info"); sleep(1)
    end
end

-- Tool 5: HMAC Cracker
local function crackerView()
    -- Pick a job or start new
    if #crackerJobs == 0 then
        -- Auto-find signed captures
        local signed = {}
        for i = #captures, math.max(1, #captures-50), -1 do
            local c = captures[i]
            if c and c.hasSig and c.envelope then
                signed[#signed+1] = c; if #signed >= 10 then break end
            end
        end
        if #signed == 0 then
            novaStatus({"NO SIGNED MESSAGES","","Run scanner first to","capture signed traffic."}, "info")
            sleep(2); return
        end
        local items = {}
        for i, c in ipairs(signed) do
            items[#items+1] = {
                label = "#"..tostring(c.from or "?").." "..tostring(c.protocol or "?").." "..tostring(c.msgType or "?"),
                capture=c,
            }
        end
        local idx, item = scrollList("SELECT TARGET TO CRACK", items, "ENTER=crack  Q=back")
        if not idx then return end
        crackerJobs[#crackerJobs+1] = {envelope=item.capture.envelope, status="pending", attempts=0}
    end

    -- Run the latest job
    local job = crackerJobs[#crackerJobs]
    if not job or not job.envelope then
        novaStatus({"NO VALID JOB"}, "fail"); sleep(1.5); return
    end

    job.status = "running"
    novaClear(); novaHeader(nil, "HMAC CRACKER")
    local w, h = term.getSize()

    -- Dictionary attack first
    term.setCursorPos(2, 5); term.setTextColor(YEL); term.write("Phase 1: Dictionary attack...")
    term.setCursorPos(2, 6); term.setTextColor(GRY); term.write(#DEFAULT_WORDLIST.." candidates")

    for i, word in ipairs(DEFAULT_WORDLIST) do
        job.attempts = job.attempts + 1
        if crackAttempt(job.envelope, word) then
            job.status = "CRACKED"
            job.secret = word
            novaStatus({"!! SECRET FOUND !!","",'"'..word..'"',"","Attempts: "..job.attempts}, "ok")
            sleep(3); return
        end
        if i % 5 == 0 then
            term.setCursorPos(2, 8); term.setTextColor(PUR)
            term.write("Trying: "..word..string.rep(" ", 20))
            term.setCursorPos(2, 9); term.setTextColor(GRY)
            term.write("Attempts: "..job.attempts)
        end
        if i % 10 == 0 then sleep(0.05) end -- yield
    end

    -- Brute force: short strings
    term.setCursorPos(2, 11); term.setTextColor(YEL); term.write("Phase 2: Brute force (1-4 chars)...")
    local charset = "abcdefghijklmnopqrstuvwxyz0123456789"
    local found = false

    -- 1-char
    for i = 1, #charset do
        job.attempts = job.attempts + 1
        local c = charset:sub(i,i)
        if crackAttempt(job.envelope, c) then
            job.status = "CRACKED"; job.secret = c
            novaStatus({"!! SECRET FOUND !!","",'"'..c..'"',"","Attempts: "..job.attempts}, "ok")
            sleep(3); return
        end
    end

    -- 2-char
    for i = 1, #charset do for j = 1, #charset do
        job.attempts = job.attempts + 1
        local c = charset:sub(i,i)..charset:sub(j,j)
        if crackAttempt(job.envelope, c) then
            job.status = "CRACKED"; job.secret = c
            novaStatus({"!! SECRET FOUND !!","",'"'..c..'"',"","Attempts: "..job.attempts}, "ok")
            sleep(3); return
        end
        if job.attempts % 100 == 0 then
            term.setCursorPos(2, 13); term.setTextColor(GRY)
            term.write("Attempts: "..job.attempts..string.rep(" ",10))
            sleep(0.05)
        end
    end end

    -- 3-4 char would take too long in CC:T, skip with notice
    job.status = "exhausted"
    novaStatus({"DICTIONARY EXHAUSTED","","Secret is > 2 chars and","not in wordlist.","","Attempts: "..job.attempts,"","Try obtaining it physically."}, "fail")
    sleep(3)
end

-- Tool 6: Signal Jammer
local function signalJammer()
    novaClear(); novaHeader(nil, "SIGNAL JAMMER")
    term.setCursorPos(2,5); term.setTextColor(PUR); term.write("Target protocol/channel: "); term.setTextColor(WHT)
    local target = read(); if not target or target == "" then return end
    term.setCursorPos(2,6); term.setTextColor(PUR); term.write("Target host (0=all): "); term.setTextColor(WHT)
    local tHost = tonumber(read()) or 0
    term.setCursorPos(2,7); term.setTextColor(PUR); term.write("Duration (sec): "); term.setTextColor(WHT)
    local dur = tonumber(read()) or 10
    term.setCursorPos(2,9); term.setTextColor(RED); term.write("Type EXECUTE: "); term.setTextColor(WHT)
    if read() ~= "EXECUTE" then return end

    local deadline = os.clock() + dur; local count = 0; local w = term.getSize()
    local ch = tonumber(target) or 65535 -- use as channel if numeric

    while os.clock() < deadline do
        local garbage = {type="x"..math.random(1,999999), sig=string.rep("0",64),
            nonce=tostring(math.random(1,2^30)), ts=os.epoch("utc"), payload={}}
        -- Send via raw modem only (no rednet — we're invisible)
        for _, m in ipairs(modems) do
            pcall(m.peripheral.transmit, ch, os.getComputerID(), garbage)
        end
        count = count + 1

        if count % 30 == 0 then
            novaClear(); novaHeader(nil, "!! JAMMING !!")
            local elapsed = os.clock() - (deadline - dur)
            local bar = string.rep("#", math.floor(elapsed/dur * (w-6)))
            term.setCursorPos(2,6); term.setTextColor(RED); term.write("TARGET: "..target)
            term.setCursorPos(2,8); term.setTextColor(YEL); term.write("PACKETS: "..count)
            term.setCursorPos(2,9); term.setTextColor(PUR); term.write("LEFT: "..math.floor(deadline-os.clock()).."s")
            term.setCursorPos(2,11); term.setTextColor(RED)
            term.write("["..bar..string.rep("-",math.max(0,w-6-#bar)).."]")
            -- Glitch
            local _, sh = term.getSize()
            for g=1,2 do
                term.setCursorPos(1, math.random(13,sh-2)); term.setTextColor(({RED,PUR,YEL})[math.random(1,3)])
                local n=""; for i=1,w do n=n..string.char(math.random(33,126)) end; term.write(n)
            end
            novaFooter(nil, "JAMMING // "..count)
            if monitor then
                monitor.setBackgroundColor(BLK); monitor.clear()
                local mw = monitor.getSize()
                monitor.setCursorPos(1,1); monitor.setBackgroundColor(RED); monitor.setTextColor(BLK)
                monitor.write(string.rep(" ",mw)); monitor.setCursorPos(2,1); monitor.write("!! JAMMING !!")
                monitor.setBackgroundColor(BLK); monitor.setTextColor(RED)
                monitor.setCursorPos(2,3); monitor.write("TARGET: "..target)
                monitor.setCursorPos(2,4); monitor.write("PACKETS: "..count)
            end
        end
        sleep(0.02)
    end
    novaStatus({"JAM COMPLETE","",count.." packets","Target: "..target}, "ok"); sleep(2)
end

-- Tool 7: Impersonator (uses raw modem transmit — no rednet footprint)
local function impersonator()
    novaClear(); novaHeader(nil, "IMPERSONATOR")
    term.setCursorPos(2,5); term.setTextColor(PUR); term.write("Target secret: "); term.setTextColor(WHT)
    local secret = read("*"); if not secret or secret == "" then return end
    term.setCursorPos(2,6); term.setTextColor(PUR); term.write("Target protocol: "); term.setTextColor(WHT)
    local tProto = read(); if not tProto or tProto == "" then tProto = "CTN" end

    local actions = {
        {label="Fake LOCKDOWN alert"},
        {label="Fake BREACH alert"},
        {label="Fake ALL CLEAR"},
        {label="Trigger sirens (breach)"},
        {label="Trigger sirens (panic)"},
        {label="Stop sirens"},
        {label="Inject radio message"},
        {label="Send custom message"},
    }
    local idx, item = scrollList("IMPERSONATE", actions)
    if not idx then return end

    -- Build and sign a message manually using raw modem
    local proto = require("ctnproto")

    local function rawSend(target, msgType, payload)
        local nonce = tostring(os.getComputerID())..":"..tostring(os.epoch("utc"))..":"..tostring(math.random(1,2^30))
        local env = {
            type = msgType,
            payload = payload,
            nonce = nonce,
            ts = os.epoch("utc"),
            proto = tProto,
            version = 1,
        }
        -- Sign with stolen secret using canonical + HMAC
        local can = canonical(env)
        env.sig = hmac(secret, can)

        -- Wrap in rednet format so target's rednet.receive picks it up
        local rednetMsg = {
            nMessageID = math.random(1, 2^30),
            nRecipient = target or nil,
            message = env,
            sProtocol = tProto,
        }

        -- Transmit on channel 65535 (rednet default)
        for _, m in ipairs(modems) do
            if target then
                pcall(m.peripheral.transmit, target, os.getComputerID(), rednetMsg)
            else
                -- Broadcast: send on channel 65535 with no specific target
                pcall(m.peripheral.transmit, 65535, os.getComputerID(), rednetMsg)
            end
        end
    end

    if idx == 1 then rawSend(nil, "facility_alert", {state="lockdown",zones={},breaches={}})
        novaStatus({"LOCKDOWN SPOOFED"}, "ok")
    elseif idx == 2 then rawSend(nil, "facility_alert", {state="breach",zones={},breaches={{scpId="???",zone="?"}}})
        novaStatus({"BREACH INJECTED"}, "ok")
    elseif idx == 3 then rawSend(nil, "facility_alert", {state="normal",zones={},breaches={}})
        novaStatus({"ALL CLEAR SPOOFED"}, "ok")
    elseif idx == 4 then rawSend(nil, "alarm_set", {pattern="breach"})
        novaStatus({"SIRENS TRIGGERED"}, "ok")
    elseif idx == 5 then rawSend(nil, "alarm_set", {pattern="panic"})
        novaStatus({"PANIC SENT"}, "ok")
    elseif idx == 6 then rawSend(nil, "alarm_set", {pattern="off"})
        novaStatus({"SIRENS SILENCED"}, "ok")
    elseif idx == 7 then
        novaClear(); novaHeader(nil, "FAKE RADIO")
        term.setCursorPos(2,5); term.setTextColor(PUR); term.write("Sender: "); term.setTextColor(WHT)
        local fn=read()
        term.setCursorPos(2,6); term.setTextColor(PUR); term.write("Msg: "); term.setTextColor(WHT)
        local fm=read()
        rawSend(nil, "radio_broadcast", {from=fn, message=fm, channel="ALL", ts=os.epoch("utc")})
        novaStatus({"RADIO INJECTED"}, "ok")
    elseif idx == 8 then
        novaClear(); novaHeader(nil, "CUSTOM MESSAGE")
        term.setCursorPos(2,5); term.setTextColor(PUR); term.write("Msg type: "); term.setTextColor(WHT)
        local mt=read()
        term.setCursorPos(2,6); term.setTextColor(PUR); term.write("Target ID (0=all): "); term.setTextColor(WHT)
        local tid=tonumber(read()) or 0
        term.setCursorPos(2,7); term.setTextColor(PUR); term.write("Payload (lua table): "); term.setTextColor(WHT)
        local pl=read()
        local payload = {}; pcall(function() payload = textutils.unserialize("{"..pl.."}") or {} end)
        rawSend(tid > 0 and tid or nil, mt, payload)
        novaStatus({"CUSTOM MSG SENT","","Type: "..mt}, "ok")
    end
    sleep(2)
end

-- Tool 8: Disk Cloner
local function diskCloner()
    if not drive then novaStatus({"NO DISK DRIVE"}, "fail"); sleep(1.5); return end
    novaClear(); novaHeader(nil, "DISK CLONER")
    term.setCursorPos(2,5); term.setTextColor(PUR); term.write("Insert source disk...")
    while not drive.getDiskID() do
        local evt = {os.pullEvent()}
        if evt[1] == "key" and evt[2] == keys.q then return end
    end
    local srcId = drive.getDiskID()
    local srcLabel = drive.getDiskLabel() or "(none)"
    local srcMount = drive.getMountPath()
    local srcFiles = {}
    if srcMount then
        local function walk(path)
            for _, name in ipairs(fs.list(path)) do
                local p = path.."/"..name
                if fs.isDir(p) then walk(p) else
                    local f=fs.open(p,"r"); srcFiles[p:sub(#srcMount+2)]=f.readAll(); f.close()
                end
            end
        end
        pcall(walk, srcMount)
    end

    term.setCursorPos(2,7); term.setTextColor(GRN); term.write("SOURCE DISK:")
    term.setCursorPos(4,8); term.setTextColor(WHT); term.write("ID: "..srcId)
    term.setCursorPos(4,9); term.write("Label: "..srcLabel)
    term.setCursorPos(4,10); term.write("Files: "..tblCount(srcFiles))

    -- Log the card
    stolenCards[#stolenCards+1] = {diskID=srcId, ts=os.epoch("utc"), label=srcLabel}

    term.setCursorPos(2,12); term.setTextColor(YEL); term.write("Remove source, insert blank disk...")
    term.setCursorPos(2,13); term.setTextColor(GRY); term.write("(Q to skip cloning, just log)")
    while drive.getDiskID() do sleep(0.3) end -- wait for removal

    while true do
        local evt = {os.pullEvent()}
        if evt[1] == "disk" then break
        elseif evt[1] == "key" and evt[2] == keys.q then
            saveData()
            novaStatus({"CARD LOGGED","","Disk #"..srcId,"Label: "..srcLabel,"(not cloned)"}, "info")
            sleep(2); return
        end
    end

    -- Clone files to new disk
    local destMount = drive.getMountPath()
    if destMount then
        pcall(drive.setDiskLabel, srcLabel)
        for path, content in pairs(srcFiles) do
            local fullPath = destMount.."/"..path
            local dir = fs.getDir(fullPath)
            if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
            local f = fs.open(fullPath, "w"); f.write(content); f.close()
        end
    end

    novaStatus({"DISK CLONED","","Original: #"..srcId,"Files: "..tblCount(srcFiles),"Label: "..srcLabel,
        "","NOTE: Disk ID cannot be cloned.","New disk has different ID.","Files and label copied."}, "ok")
    sleep(3); saveData()
end

-- Tool 9: Keylogger
local function keyloggerMode()
    if not drive then novaStatus({"NO DISK DRIVE"}, "fail"); sleep(1.5); return end
    novaClear(); novaHeader(nil, "KEYLOGGER")
    term.setCursorPos(2,5); term.setTextColor(PUR); term.write("Fake door label: "); term.setTextColor(WHT)
    local label = read(); if label == "" then label = "SECTOR ACCESS" end
    term.setCursorPos(2,7); term.setTextColor(PUR); term.write("Type DEPLOY: "); term.setTextColor(WHT)
    if read() ~= "DEPLOY" then return end

    local caught = {}
    while true do
        ui.bigStatus(term.current(), {label,"",">>  INSERT ID CARD  <<","","Authorised personnel only."}, "idle")
        if monitor then ui.bigStatus(monitor, {label,"",">>  INSERT ID CARD  <<","","Authorised personnel only."}, "idle") end
        local evt = {os.pullEvent()}
        if evt[1] == "disk" then
            local did = drive.getDiskID()
            if did then
                caught[#caught+1] = {diskID=did, ts=os.epoch("utc"), label=drive.getDiskLabel()}
                stolenCards[#stolenCards+1] = caught[#caught]
                ui.bigStatus(term.current(), {"VERIFYING...","","Contacting mainframe"}, "working")
                if monitor then ui.bigStatus(monitor, {"VERIFYING...","","Contacting mainframe"}, "working") end
                sleep(math.random(10,25)/10)
                ui.bigStatus(term.current(), {"MAINFRAME","UNREACHABLE","","Try another terminal."}, "error")
                if monitor then ui.bigStatus(monitor, {"MAINFRAME","UNREACHABLE","","Try another terminal."}, "error") end
                sleep(3)
                while drive.getDiskID() do sleep(0.3) end
            end
        elseif evt[1] == "key" and evt[2] == keys.f1 then
            saveData()
            novaStatus({"KEYLOGGER STOPPED","",#caught.." card(s) captured"}, "ok"); sleep(2); return
        end
    end
end

-- Tool 10: Stolen Cards
local function stolenCardsView()
    if #stolenCards == 0 then novaStatus({"NO CARDS","","Use keylogger or cloner."}, "info"); sleep(1.5); return end
    local items = {}
    for _, c in ipairs(stolenCards) do
        items[#items+1] = {label="DISK #"..c.diskID.."  "..(c.label or "").."  "..os.date("%m/%d %H:%M",(c.ts or 0)/1000), color=YEL}
    end
    scrollList("STOLEN CARDS // "..#stolenCards, items)
end

-- Settings
local function settings()
    novaClear(); novaHeader(nil, "SETTINGS")
    term.setCursorPos(2,5); term.setTextColor(PUR); term.write("Callsign: "); term.setTextColor(WHT); term.write(CALLSIGN)
    term.setCursorPos(2,6); term.setTextColor(PUR); term.write("Motto: "); term.setTextColor(GRY); term.write('"'..MOTTO..'"')
    term.setCursorPos(2,8); term.setTextColor(PUR); term.write("New callsign: "); term.setTextColor(WHT)
    local nc=read(); if nc~="" then CALLSIGN=nc; myCfg.callsign=nc end
    term.setCursorPos(2,9); term.setTextColor(PUR); term.write("New motto: "); term.setTextColor(WHT)
    local nm=read(); if nm~="" then MOTTO=nm; myCfg.motto=nm end
    cfg.save(myCfg)
    novaStatus({"SAVED"}, "ok"); sleep(1)
end

-- Purge
local function purgeData()
    novaClear(); novaHeader(nil, "!! PURGE !!")
    term.setCursorPos(2,6); term.setTextColor(RED); term.write("DESTROY ALL EVIDENCE?")
    term.setCursorPos(2,8); term.setTextColor(PUR); term.write("Type PURGE: "); term.setTextColor(WHT)
    if read() ~= "PURGE" then return end
    captures={}; rawCaptures={}; knownHosts={}; knownProtocols={}; crackerJobs={}; stolenCards={}
    fs.delete("/.nova_captures"); fs.delete("/.nova_hosts"); fs.delete("/.nova_stolen_cards")
    novaStatus({"ALL DATA PURGED","","Evidence destroyed."}, "ok"); sleep(2)
end

-- Payload deployer: write takeover script to floppy
local function deployPayload()
    if not drive then novaStatus({"NO DISK DRIVE","","Attach a drive."}, "fail"); sleep(1.5); return end
    novaClear(); novaHeader(nil, "PAYLOAD DEPLOYER")

    term.setCursorPos(2, 5); term.setTextColor(PUR); term.write("This creates a takeover floppy.")
    term.setCursorPos(2, 6); term.setTextColor(GRY); term.write("Insert into target computer to seize it.")
    term.setCursorPos(2, 8); term.setTextColor(PUR); term.write("Custom motto (blank=default): ")
    term.setTextColor(WHT); local pmotto = read()
    if pmotto == "" then pmotto = MOTTO end
    term.setCursorPos(2, 9); term.setTextColor(PUR); term.write("Custom callsign (blank=default): ")
    term.setTextColor(WHT); local pcall_ = read()
    if pcall_ == "" then pcall_ = CALLSIGN end

    term.setCursorPos(2, 11); term.setTextColor(YEL); term.write("Insert blank floppy disk...")
    while not drive.getDiskID() do
        local evt = {os.pullEvent()}
        if evt[1] == "key" and evt[2] == keys.q then return end
    end

    local mount = drive.getMountPath()
    if not mount or mount == "" then
        novaStatus({"MOUNT ERROR"}, "fail"); sleep(1.5); return
    end

    -- Read the takeover payload from our own lib
    local payloadSrc
    if fs.exists("/lib/secret-takeover.lua") then
        local f = fs.open("/lib/secret-takeover.lua", "r")
        payloadSrc = f.readAll(); f.close()
    else
        novaStatus({"PAYLOAD NOT FOUND","","Missing /lib/secret-takeover.lua"}, "fail")
        sleep(2); return
    end

    -- Write payload as startup.lua on the floppy
    local f = fs.open(mount.."/startup.lua", "w")
    f.write(payloadSrc); f.close()

    -- Write config with motto/callsign
    local f2 = fs.open(mount.."/.nova_payload_cfg", "w")
    f2.write(textutils.serialize({motto=pmotto, callsign=pcall_}))
    f2.close()

    -- Set disk label to something innocent
    pcall(drive.setDiskLabel, "System Update")

    novaStatus({
        "PAYLOAD ARMED",
        "",
        "Floppy is ready.",
        "Label: 'System Update'",
        "",
        "HOW TO DEPLOY:",
        "1. Put floppy in target's drive",
        "2. Target reboots or starts up",
        "3. Payload runs from floppy",
        "",
        "OR for permanent takeover:",
        "1. Access target computer",
        "2. Copy floppy startup.lua to",
        "   target's /startup.lua",
        "3. Remove floppy, reboot target",
    }, "ok")
    os.pullEvent("key")
end

-- ============================================================
-- Main menu
-- ============================================================
local menuItems = {
    {label="Omniscanner (RAW+Rednet)", action=scannerView,      icon="[~]"},
    {label="Host Intelligence",        action=hostIntel,         icon="[#]"},
    {label="Protocol Analysis",        action=protocolAnalysis,  icon="[?]"},
    {label="Capture Viewer",           action=captureViewer,     icon="[>]"},
    {label="HMAC Cracker",             action=crackerView,       icon="[!]"},
    {label="Signal Jammer",            action=signalJammer,      icon="[%]"},
    {label="Impersonator",             action=impersonator,      icon="[*]"},
    {label="Disk Cloner",              action=diskCloner,        icon="[$]"},
    {label="Keylogger Deploy",         action=keyloggerMode,     icon="[@]"},
    {label="Payload Deploy",           action=deployPayload,     icon="[!]"},
    {label="Stolen Cards",             action=stolenCardsView,   icon="[&]"},
    {label="Settings",                 action=settings,          icon="[=]"},
    {label="Purge All Data",           action=purgeData,         icon="[X]"},
}

local function mainMenu()
    while true do
        novaClear()
        local w, h = term.getSize()
        term.setCursorPos(1,1); term.setBackgroundColor(PUR); term.setTextColor(BLK)
        term.write(string.rep(" ",w))
        local title = "N.O.V.A // "..CALLSIGN
        term.setCursorPos(math.max(1,math.floor((w-#title)/2)+1),1); term.write(title)
        term.setBackgroundColor(BLK)
        term.setCursorPos(1,2); term.setTextColor(GRN)
        local stats = " "..#captures.."cap "..tblCount(knownHosts).."hosts "..tblCount(knownProtocols).."proto "..#stolenCards.."cards"
        term.write(stats:sub(1,w))
        term.setCursorPos(1,3); term.setTextColor(PUR); term.write(string.rep("=",w))

        pcall(drawMonitorFeed)

        local selected, top = 1, 1
        local rows = h - 6
        while true do
            for row = 1, rows do
                local idx = top+row-1; local item = menuItems[idx]
                term.setCursorPos(1, 3+row)
                if not item then term.setBackgroundColor(BLK); term.write(string.rep(" ",w))
                elseif idx == selected then
                    term.setBackgroundColor(PUR); term.setTextColor(BLK)
                    local line = " "..item.icon.." "..item.label
                    term.write(line:sub(1,w)); term.write(string.rep(" ",math.max(0,w-#line)))
                    term.setBackgroundColor(BLK)
                else
                    term.setBackgroundColor(BLK); term.setTextColor(PUR)
                    local line = " "..item.icon.." "..item.label
                    term.write(line:sub(1,w)); term.write(string.rep(" ",math.max(0,w-#line)))
                end
            end
            term.setCursorPos(1,h-1); term.setTextColor(GRY)
            local ml='"'..MOTTO..'"'
            term.write(string.rep(" ",math.max(0,math.floor((w-#ml)/2)))); term.write(ml:sub(1,w))
            novaFooter(nil, os.date("%H:%M").."  N.O.V.A  "..CALLSIGN)

            local evt = {os.pullEvent()}
            if evt[1] == "key" then
                if evt[2]==keys.up and selected>1 then selected=selected-1; if selected<top then top=selected end
                elseif evt[2]==keys.down and selected<#menuItems then selected=selected+1; if selected>=top+rows then top=top+1 end
                elseif evt[2]==keys.enter then pcall(menuItems[selected].action); break end
            elseif evt[1] == "mouse_click" then
                local idx=top+(evt[4]-4); if idx>=1 and idx<=#menuItems then pcall(menuItems[idx].action); break end
            elseif evt[1] == "modem_message" then processRaw(evt[2],evt[3],evt[4],evt[5],evt[6]); pcall(drawMonitorFeed)
            end
        end
    end
end

bootSequence()
mainMenu()

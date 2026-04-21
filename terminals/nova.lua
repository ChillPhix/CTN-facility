-- terminals/nova.lua
-- [CLASSIFIED]

package.path = package.path .. ";/lib/?.lua"
local proto = require("ctnproto")
local ui    = require("ctnui")
local cfg   = require("ctnconfig")

local myCfg = cfg.loadOrWizard("nova", {
    {key="mainframe_id", prompt="Home mainframe ID", type="number", default=1},
    {key="motto",        prompt="Operational motto", default="In Shadows, We See All"},
    {key="callsign",     prompt="Operator callsign", default="SPECTER"},
})

proto.openModem()
local HOME_MF  = myCfg.mainframe_id
local MOTTO    = myCfg.motto
local CALLSIGN = myCfg.callsign

-- Find monitor
local monitor
for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "monitor" then
        monitor = peripheral.wrap(side)
        monitor.setTextScale(0.5)
        break
    end
end

-- ============================================================
-- Colors
-- ============================================================
local PUR = colors.purple
local BLK = colors.black
local WHT = colors.white
local GRY = colors.gray
local RED = colors.red
local GRN = colors.lime
local YEL = colors.yellow
local CYN = colors.cyan

-- ============================================================
-- ASCII art
-- ============================================================
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

-- ============================================================
-- Render helper: draw to target (monitor or term)
-- ============================================================
local function drawOn(t)
    return t or term.current()
end

-- ============================================================
-- Boot animation (plays on BOTH screens)
-- ============================================================
local function bootSequence()
    local targets = {term.current()}
    if monitor then targets[#targets+1] = monitor end

    for _, t in ipairs(targets) do
        t.setBackgroundColor(BLK); t.clear()
    end

    local bootLines = {
        {delay=0.3, text="INITIALIZING...", color=GRY},
        {delay=0.2, text="LOADING CRYPTOGRAPHIC MODULES...", color=GRY},
        {delay=0.4, text="SCANNING NETWORK INTERFACES...", color=GRY},
        {delay=0.2, text="MODEM DETECTED: ENDER", color=GRN},
        {delay=0.3, text="ESTABLISHING SECURE CHANNEL...", color=GRY},
        {delay=0.5, text="CHANNEL ENCRYPTED", color=GRN},
        {delay=0.2, text="LOADING OFFENSIVE MODULES...", color=PUR},
        {delay=0.3, text="  >> SCANNER........... OK", color=GRN},
        {delay=0.2, text="  >> INTERCEPTOR....... OK", color=GRN},
        {delay=0.2, text="  >> JAMMER............ OK", color=GRN},
        {delay=0.2, text="  >> CRACKER........... OK", color=GRN},
        {delay=0.2, text="  >> IMPERSONATOR...... OK", color=GRN},
        {delay=0.2, text="  >> KEYLOGGER......... OK", color=GRN},
        {delay=0.4, text="ALL SYSTEMS NOMINAL", color=GRN},
        {delay=0.6, text="", color=GRY},
    }

    local y = 2
    for _, line in ipairs(bootLines) do
        for _, t in ipairs(targets) do
            local _, th = t.getSize()
            if y >= th - 1 then t.scroll(1) end
            t.setCursorPos(2, math.min(y, th - 1))
            t.setBackgroundColor(BLK); t.setTextColor(line.color)
            for i = 1, #line.text do
                t.write(line.text:sub(i, i))
                if i % 6 == 0 then sleep(0.01) end
            end
        end
        y = y + 1
        sleep(line.delay)
    end
    sleep(0.3)

    -- Phase 2: Shield splash on ALL screens
    for _, t in ipairs(targets) do
        t.setBackgroundColor(BLK); t.clear()
        local w, h = t.getSize()
        local shieldStartY = math.max(1, math.floor((h - #SHIELD) / 2) - 2)
        for i, line in ipairs(SHIELD) do
            local x = math.max(1, math.floor((w - #line) / 2) + 1)
            t.setCursorPos(x, shieldStartY + i - 1)
            t.setTextColor(PUR); t.write(line)
        end
    end
    sleep(0.3)

    -- Flash
    for flash = 1, 3 do
        for _, t in ipairs(targets) do
            t.setBackgroundColor(PUR); t.clear()
        end
        sleep(0.05)
        for _, t in ipairs(targets) do
            t.setBackgroundColor(BLK); t.clear()
            local w, h = t.getSize()
            local sy = math.max(1, math.floor((h - #SHIELD) / 2) - 2)
            for i, line in ipairs(SHIELD) do
                local x = math.max(1, math.floor((w - #line) / 2) + 1)
                t.setCursorPos(x, sy + i - 1)
                t.setTextColor(flash == 3 and WHT or PUR); t.write(line)
            end
        end
        sleep(0.08)
    end

    -- Title + motto on all screens
    for _, t in ipairs(targets) do
        local w, h = t.getSize()
        local titleY = math.max(1, math.floor((h - #SHIELD) / 2) - 2) + #SHIELD + 1
        local title = "N . O . V . A"
        t.setTextColor(WHT)
        for i = 1, #title do
            t.setCursorPos(math.max(1, math.floor((w - #title) / 2) + 1) + i - 1, titleY)
            t.write(title:sub(i, i))
        end
        sleep(0.02)

        local sub = "P R O J E C T   O V E R S I G H T"
        t.setCursorPos(math.max(1, math.floor((w - #sub)/2)+1), titleY + 1)
        t.setTextColor(PUR); t.write(sub)

        t.setCursorPos(math.max(1, math.floor((w - #MOTTO)/2)+1), titleY + 3)
        t.setTextColor(GRY); t.write('"'..MOTTO..'"')

        local csLine = "OPERATOR: "..CALLSIGN
        t.setCursorPos(math.max(1, math.floor((w - #csLine)/2)+1), titleY + 5)
        t.setTextColor(CYN); t.write(csLine)
    end
    sleep(1.5)

    -- Glitch transition
    for glitch = 1, 6 do
        for _, t in ipairs(targets) do
            local w, h = t.getSize()
            local gy = math.random(1, h)
            t.setCursorPos(1, gy)
            t.setTextColor(({PUR, RED, GRN, CYN})[math.random(1, 4)])
            local noise = ""
            for i = 1, w do noise = noise .. string.char(math.random(33, 126)) end
            t.write(noise)
        end
        sleep(0.04)
    end
    sleep(0.2)
end

-- ============================================================
-- Data stores
-- ============================================================
local captures = {}
local knownHosts = {}
local knownProtocols = {}
local MAX_CAPTURES = 500

local function saveCapturesFile()
    local f = fs.open("/.nova_captures", "w")
    for _, c in ipairs(captures) do
        f.writeLine(textutils.serialize(c, {compact=true}))
    end
    f.close()
end

local function loadCapturesFile()
    if not fs.exists("/.nova_captures") then return end
    local f = fs.open("/.nova_captures", "r")
    while true do
        local l = f.readLine()
        if not l then break end
        local ok, entry = pcall(textutils.unserialize, l)
        if ok and entry then captures[#captures+1] = entry end
    end
    f.close()
end
loadCapturesFile()

local function tblCount(t)
    local n = 0; for _ in pairs(t) do n = n + 1 end; return n
end

-- ============================================================
-- Monitor live feed renderer
-- ============================================================
local function drawMonitorFeed()
    if not monitor then return end
    local w, h = monitor.getSize()
    monitor.setBackgroundColor(BLK); monitor.clear()

    -- Header
    monitor.setCursorPos(1, 1); monitor.setBackgroundColor(PUR); monitor.setTextColor(BLK)
    monitor.write(string.rep(" ", w))
    local title = "N.O.V.A // LIVE INTERCEPT"
    monitor.setCursorPos(math.max(1, math.floor((w-#title)/2)+1), 1); monitor.write(title)
    monitor.setBackgroundColor(BLK)

    -- Stats bar
    monitor.setCursorPos(1, 2); monitor.setTextColor(GRY)
    local phase = math.floor(os.epoch("utc") / 300) % 4
    local scanAnim = ({"|", "/", "-", "\\"})[phase + 1]
    local stats = " "..scanAnim.." "..#captures.." cap  "..tblCount(knownHosts).." hosts  "..tblCount(knownProtocols).." proto"
    monitor.write(stats:sub(1, w))
    monitor.setCursorPos(1, 3); monitor.setTextColor(PUR); monitor.write(string.rep("-", w))

    -- Live feed (newest at bottom)
    local feedStart = 4
    local feedRows = h - feedStart
    local startIdx = math.max(1, #captures - feedRows + 1)

    for row = 0, feedRows - 1 do
        local idx = startIdx + row
        local c = captures[idx]
        local y = feedStart + row
        if not c then break end

        local ts = os.date("%H:%M:%S", (c.ts or 0) / 1000)
        monitor.setCursorPos(1, y)
        monitor.setTextColor(GRY); monitor.write(ts.." ")
        monitor.setTextColor(PUR); monitor.write("#"..tostring(c.from):sub(1,4).." ")

        -- Protocol colored by type
        local pCol = WHT
        if c.protocol and c.protocol:find("CTN") then pCol = YEL end
        monitor.setTextColor(pCol); monitor.write((c.protocol or "?"):sub(1, 10).." ")

        -- Message type
        local tCol = c.hasSignature and YEL or GRN
        monitor.setTextColor(tCol)
        local remaining = w - 22
        monitor.write((c.type or "?"):sub(1, remaining))
    end

    -- Footer
    monitor.setCursorPos(1, h); monitor.setBackgroundColor(PUR); monitor.setTextColor(BLK)
    monitor.write(string.rep(" ", w))
    local ft = CALLSIGN.."  "..os.date("%H:%M:%S").."  "..scanAnim
    monitor.setCursorPos(math.max(1, w - #ft), h); monitor.write(ft)
    monitor.setBackgroundColor(BLK)
end

-- ============================================================
-- UI framework (computer screen)
-- ============================================================
local function novaHeader(subtitle)
    local w = term.getSize()
    term.setCursorPos(1, 1); term.setBackgroundColor(PUR); term.setTextColor(BLK)
    term.write(string.rep(" ", w))
    local title = "N.O.V.A // "..CALLSIGN
    term.setCursorPos(math.max(1, math.floor((w - #title)/2)+1), 1); term.write(title)
    term.setCursorPos(1, 2); term.setBackgroundColor(BLK); term.setTextColor(PUR)
    if subtitle then
        term.write(string.rep(" ", w))
        term.setCursorPos(math.max(1, math.floor((w - #subtitle)/2)+1), 2); term.write(subtitle)
    else term.write(string.rep(" ", w)) end
    term.setCursorPos(1, 3); term.setTextColor(PUR); term.write(string.rep("=", w))
    term.setBackgroundColor(BLK)
end

local function novaFooter(text)
    local w, h = term.getSize()
    term.setCursorPos(1, h); term.setBackgroundColor(PUR); term.setTextColor(BLK)
    term.write(string.rep(" ", w))
    if text then term.setCursorPos(2, h); term.write(text:sub(1, w - 2)) end
    term.setBackgroundColor(BLK); term.setTextColor(PUR)
end

local function novaClear()
    term.setBackgroundColor(BLK); term.setTextColor(PUR)
    term.clear(); term.setCursorPos(1, 1)
end

local function novaStatus(lines, state)
    novaClear(); novaHeader("OPERATION")
    local w, h = term.getSize()
    local col = ({working=YEL, ok=GRN, fail=RED, info=CYN})[state] or PUR
    local boxH = math.min(#lines + 4, h - 6)
    local boxY = math.floor((h - boxH) / 2) + 1
    ui.box(term.current(), 2, boxY, w - 2, boxH, col)
    for i, line in ipairs(lines) do
        term.setCursorPos(math.max(1, math.floor((w - #line)/2)+1), boxY + 1 + i)
        term.setTextColor(col); term.write(line)
    end
    novaFooter("N.O.V.A // "..string.upper(state or ""))
end

local function scrollList(title, items, footer)
    local selected, top = 1, 1
    while true do
        novaClear(); novaHeader(title)
        local w, h = term.getSize()
        local rows = h - 5
        top = math.max(1, math.min(top, math.max(1, #items - rows + 1)))
        if #items == 0 then
            term.setCursorPos(2, 5); term.setTextColor(GRY); term.write("(no data)")
        else
            for row = 1, rows do
                local idx = top + row - 1
                local item = items[idx]
                if not item then break end
                term.setCursorPos(1, 3 + row)
                if idx == selected then
                    term.setBackgroundColor(PUR); term.setTextColor(BLK)
                else
                    term.setBackgroundColor(BLK); term.setTextColor(item.color or PUR)
                end
                local line = (idx == selected and " > " or "   ") .. (item.label or "?")
                term.write(line:sub(1, w)); term.write(string.rep(" ", math.max(0, w - #line)))
                term.setBackgroundColor(BLK)
            end
        end
        novaFooter(footer or "ENTER=select  Q=back")
        local evt = {os.pullEvent()}
        if evt[1] == "key" then
            if evt[2] == keys.up and selected > 1 then
                selected = selected - 1; if selected < top then top = selected end
            elseif evt[2] == keys.down and selected < #items then
                selected = selected + 1; if selected >= top + rows then top = top + 1 end
            elseif evt[2] == keys.enter and items[selected] then return selected, items[selected]
            elseif evt[2] == keys.q or evt[2] == keys.backspace then return nil end
        elseif evt[1] == "mouse_click" then
            local idx = top + (evt[4] - 4)
            if idx >= 1 and idx <= #items then return idx, items[idx] end
        elseif evt[1] == "mouse_scroll" then
            top = math.max(1, math.min(math.max(1, #items - rows + 1), top + evt[2]))
        end
    end
end

-- ============================================================
-- Capture processor
-- ============================================================
local function processCapture(sender, message, protocol)
    local entry = {ts=os.epoch("utc"), from=sender, protocol=protocol or "?"}
    if type(message) == "table" then
        entry.type = message.type or "?"
        entry.hasSignature = message.sig ~= nil
        entry.version = message.version
        entry.nonce = message.nonce
        entry.msgTs = message.ts
        entry.payloadKeys = {}
        if message.payload and type(message.payload) == "table" then
            for k in pairs(message.payload) do entry.payloadKeys[#entry.payloadKeys+1] = k end
        end
        entry.raw = message
    else entry.type = "non-table" end

    captures[#captures+1] = entry
    while #captures > MAX_CAPTURES do table.remove(captures, 1) end

    if not knownHosts[sender] then
        knownHosts[sender] = {lastSeen=0, protocols={}, msgCount=0, types={}}
    end
    local host = knownHosts[sender]
    host.lastSeen = os.epoch("utc")
    host.msgCount = host.msgCount + 1
    host.protocols[protocol or "?"] = (host.protocols[protocol or "?"] or 0) + 1
    if entry.type then host.types[entry.type] = (host.types[entry.type] or 0) + 1 end

    local pkey = protocol or "?"
    if not knownProtocols[pkey] then knownProtocols[pkey] = {count=0, hosts={}} end
    knownProtocols[pkey].count = knownProtocols[pkey].count + 1
    knownProtocols[pkey].hosts[sender] = true
end

-- ============================================================
-- Tool 1: Network Scanner
-- ============================================================
local function scannerView()
    local startCount = #captures
    local listenTimer = os.startTimer(0.5)
    while true do
        novaClear(); novaHeader("PASSIVE SCANNER // LIVE")
        local w, h = term.getSize()
        local newCaptures = #captures - startCount
        local phase = math.floor(os.epoch("utc") / 300) % 4
        local scanAnim = ({"|", "/", "-", "\\"})[phase + 1]

        term.setCursorPos(2, 5); term.setTextColor(GRN)
        term.write(">> INTERCEPTED: "..newCaptures.." new  ("..#captures.." total)")
        term.setCursorPos(2, 6); term.setTextColor(PUR)
        term.write(">> HOSTS: "..tblCount(knownHosts).."  PROTOCOLS: "..tblCount(knownProtocols))
        term.setCursorPos(w - 3, 5); term.setTextColor(GRN); term.write("["..scanAnim.."]")

        term.setCursorPos(2, 8); term.setTextColor(CYN); term.write("LIVE FEED:")
        term.setCursorPos(2, 9); term.setTextColor(PUR); term.write(string.rep("-", w - 2))
        local y = 10
        for i = math.max(1, #captures - (h - y - 2)), #captures do
            if y >= h - 1 then break end
            local c = captures[i]
            if c then
                local ts = os.date("%H:%M:%S", (c.ts or 0) / 1000)
                term.setCursorPos(2, y); term.setTextColor(GRY); term.write(ts.." ")
                term.setTextColor(PUR); term.write("#"..tostring(c.from):sub(1,4).." ")
                term.setTextColor(WHT); term.write((c.protocol or "?"):sub(1,10).." ")
                term.setTextColor(c.hasSignature and YEL or GRN)
                term.write((c.type or "?"):sub(1, w - 28))
                y = y + 1
            end
        end
        novaFooter("Q=stop  "..scanAnim.." scanning...")

        -- Also update monitor
        pcall(drawMonitorFeed)

        local evt = {os.pullEvent()}
        if evt[1] == "rednet_message" then
            processCapture(evt[2], evt[3], evt[4])
        elseif evt[1] == "timer" and evt[2] == listenTimer then
            listenTimer = os.startTimer(0.5)
        elseif evt[1] == "key" and evt[2] == keys.q then
            saveCapturesFile()
            novaStatus({"SCANNER STOPPED","",newCaptures.." captured",#captures.." total"}, "ok")
            sleep(1.5); return
        end
    end
end

-- ============================================================
-- Tool 2: Host Intelligence
-- ============================================================
local function hostIntel()
    local items = {}
    for id, h in pairs(knownHosts) do
        local age = math.floor((os.epoch("utc") - h.lastSeen) / 1000)
        local protos = {}
        for p in pairs(h.protocols) do protos[#protos+1] = p end
        items[#items+1] = {
            label = string.format("#%-4s %3dmsg  %s", id, h.msgCount, table.concat(protos,","):sub(1,20)),
            host = h, id = id,
            color = age < 10 and GRN or (age < 60 and YEL or GRY),
        }
    end
    table.sort(items, function(a,b) return (a.host.msgCount or 0) > (b.host.msgCount or 0) end)
    local idx, item = scrollList("HOST INTELLIGENCE // "..tblCount(knownHosts).." TARGETS", items)
    if not idx then return end

    novaClear(); novaHeader("TARGET: #"..item.id)
    local h_ = item.host
    local w, sh = term.getSize()
    local y = 5
    local function line(label, val, col)
        if y >= sh - 2 then return end
        term.setCursorPos(2, y); term.setTextColor(PUR); term.write(label..": ")
        term.setTextColor(col or WHT); term.write(tostring(val):sub(1, w - #label - 5)); y = y + 1
    end
    line("Computer ID", item.id, CYN)
    line("Messages", h_.msgCount)
    line("Last seen", os.date("%H:%M:%S", (h_.lastSeen or 0) / 1000))
    line("Status", (os.epoch("utc") - h_.lastSeen < 10000) and "ACTIVE" or "INACTIVE",
        (os.epoch("utc") - h_.lastSeen < 10000) and GRN or RED)
    y = y + 1
    term.setCursorPos(2, y); term.setTextColor(CYN); term.write("PROTOCOLS:"); y = y + 1
    for p, count in pairs(h_.protocols) do
        if y >= sh - 4 then break end
        term.setCursorPos(4, y); term.setTextColor(GRY); term.write(p..": "..count.." msgs"); y = y + 1
    end
    y = y + 1
    term.setCursorPos(2, y); term.setTextColor(CYN); term.write("MESSAGE TYPES:"); y = y + 1
    for t, count in pairs(h_.types or {}) do
        if y >= sh - 2 then break end
        term.setCursorPos(4, y); term.setTextColor(GRY); term.write(t..": "..count); y = y + 1
    end
    novaFooter("Any key to return"); os.pullEvent("key")
end

-- ============================================================
-- Tool 3: Protocol Analysis
-- ============================================================
local function protocolAnalysis()
    local items = {}
    for name, p in pairs(knownProtocols) do
        items[#items+1] = {
            label = string.format("%-15s %4dmsg  %d hosts", name:sub(1,15), p.count, tblCount(p.hosts)),
            protocol = p, name = name,
        }
    end
    table.sort(items, function(a,b) return a.protocol.count > b.protocol.count end)
    local idx, item = scrollList("PROTOCOL ANALYSIS", items)
    if not idx then return end
    local hostItems = {}
    for hid in pairs(item.protocol.hosts) do
        local h = knownHosts[hid]
        hostItems[#hostItems+1] = {
            label = "#"..hid.."  "..(h and h.msgCount or "?").."msg",
            color = h and (os.epoch("utc") - h.lastSeen < 10000) and GRN or GRY,
        }
    end
    scrollList("HOSTS ON: "..item.name, hostItems)
end

-- ============================================================
-- Tool 4: Capture Viewer
-- ============================================================
local function captureViewer()
    local items = {}
    for i = #captures, math.max(1, #captures - 100), -1 do
        local c = captures[i]
        if c then
            local ts = os.date("%H:%M:%S", (c.ts or 0) / 1000)
            items[#items+1] = {
                label = ts.." #"..c.from.." "..c.protocol.." "..tostring(c.type),
                capture = c, color = c.hasSignature and YEL or GRY,
            }
        end
    end
    local idx, item = scrollList("CAPTURES // "..#captures, items, "ENTER=inspect  Q=back")
    if not idx then return end
    local c = item.capture
    novaClear(); novaHeader("INTERCEPT DETAIL")
    local w, h = term.getSize()
    local y = 5
    local function line(label, val, col)
        if y >= h - 2 then return end
        term.setCursorPos(2, y); term.setTextColor(PUR); term.write(label..": ")
        term.setTextColor(col or WHT); term.write(tostring(val):sub(1, w - #label - 5)); y = y + 1
    end
    line("Time", os.date("%H:%M:%S", (c.ts or 0) / 1000))
    line("Source", "#"..c.from, CYN)
    line("Protocol", c.protocol)
    line("Type", c.type)
    line("Signed", c.hasSignature and "YES (HMAC-SHA256)" or "NO", c.hasSignature and RED or GRN)
    line("Version", c.version or "?")
    if c.nonce then line("Nonce", c.nonce) end
    if c.msgTs then line("Timestamp", tostring(c.msgTs)) end
    if c.payloadKeys and #c.payloadKeys > 0 then
        line("Payload fields", table.concat(c.payloadKeys, ", "))
    end
    novaFooter("Any key to return"); os.pullEvent("key")
end

-- ============================================================
-- Tool 5: Signal Jammer
-- ============================================================
local function signalJammer()
    novaClear(); novaHeader("SIGNAL JAMMER")
    term.setCursorPos(2, 5); term.setTextColor(PUR); term.write("Target protocol: "); term.setTextColor(WHT)
    local targetProto = read(); if not targetProto or targetProto == "" then return end
    term.setCursorPos(2, 6); term.setTextColor(PUR); term.write("Target host (0=all): "); term.setTextColor(WHT)
    local targetHost = tonumber(read()) or 0
    term.setCursorPos(2, 7); term.setTextColor(PUR); term.write("Duration (seconds): "); term.setTextColor(WHT)
    local duration = tonumber(read()) or 10
    term.setCursorPos(2, 9); term.setTextColor(RED); term.write("Type EXECUTE to confirm: "); term.setTextColor(WHT)
    if read() ~= "EXECUTE" then return end

    local deadline = os.clock() + duration
    local count = 0
    local w = term.getSize()
    while os.clock() < deadline do
        local garbage = {proto=targetProto, type="x"..math.random(1,999999),
            nonce=tostring(math.random(1,2^30)), ts=os.epoch("utc"), payload={}, sig=string.rep("0",64)}
        if targetHost > 0 then rednet.send(targetHost, garbage, targetProto)
        else rednet.broadcast(garbage, targetProto) end
        count = count + 1
        if count % 20 == 0 then
            novaClear(); novaHeader("JAMMING ACTIVE")
            local elapsed = os.clock() - (deadline - duration)
            local bar = string.rep("#", math.floor(elapsed / duration * (w - 6)))
            term.setCursorPos(2, 6); term.setTextColor(RED)
            term.write("TARGET: "..targetProto..(targetHost > 0 and " #"..targetHost or " ALL"))
            term.setCursorPos(2, 8); term.setTextColor(YEL); term.write("PACKETS: "..count)
            term.setCursorPos(2, 9); term.setTextColor(PUR); term.write("LEFT: "..math.floor(deadline-os.clock()).."s")
            term.setCursorPos(2, 11); term.setTextColor(RED)
            term.write("["..bar..string.rep("-", math.max(0, w-6-#bar)).."]")
            for g = 1, 2 do
                local _, sh = term.getSize()
                local gy = math.random(13, sh - 2)
                term.setCursorPos(1, gy); term.setTextColor(({RED,PUR,YEL})[math.random(1,3)])
                local noise = ""; for i = 1, w do noise = noise..string.char(math.random(33,126)) end
                term.write(noise)
            end
            novaFooter("JAMMING // "..count.." packets")
            -- Update monitor with jam status
            if monitor then
                monitor.setBackgroundColor(BLK); monitor.clear()
                local mw, mh = monitor.getSize()
                monitor.setCursorPos(1, 1); monitor.setBackgroundColor(RED); monitor.setTextColor(BLK)
                monitor.write(string.rep(" ", mw))
                local jt = "!! JAMMING ACTIVE !!"
                monitor.setCursorPos(math.max(1,math.floor((mw-#jt)/2)+1), 1); monitor.write(jt)
                monitor.setBackgroundColor(BLK); monitor.setTextColor(RED)
                monitor.setCursorPos(2, 4); monitor.write("TARGET: "..targetProto)
                monitor.setCursorPos(2, 5); monitor.write("PACKETS: "..count)
                monitor.setCursorPos(2, 7); monitor.setTextColor(YEL)
                monitor.write("["..bar..string.rep("-", math.max(0, mw-6-#bar)).."]")
            end
        end
        sleep(0.02)
    end
    novaStatus({"JAM COMPLETE","",count.." packets sent","Target: "..targetProto}, "ok"); sleep(2)
end

-- ============================================================
-- Tool 6: Impersonator
-- ============================================================
local function impersonator()
    novaClear(); novaHeader("IMPERSONATOR")
    term.setCursorPos(2, 5); term.setTextColor(PUR); term.write("Target secret: "); term.setTextColor(WHT)
    local secret = read("*"); if not secret or secret == "" then return end
    term.setCursorPos(2, 6); term.setTextColor(PUR); term.write("Target mainframe ID: "); term.setTextColor(WHT)
    local mfId = tonumber(read()); if not mfId then return end

    local actions = {
        {label="Fake LOCKDOWN alert", action="lockdown"},
        {label="Fake BREACH alert", action="breach"},
        {label="Fake ALL CLEAR", action="allclear"},
        {label="Trigger sirens (breach)", action="siren_breach"},
        {label="Trigger sirens (panic)", action="siren_panic"},
        {label="Stop sirens", action="siren_off"},
        {label="Inject radio message", action="radio"},
    }
    local idx, item = scrollList("IMPERSONATE // #"..mfId, actions, "ENTER=execute  Q=abort")
    if not idx then return end

    -- Swap secret temporarily
    local origSecret
    if fs.exists(proto.SECRET_PATH) then
        local f = fs.open(proto.SECRET_PATH, "r"); origSecret = f.readAll(); f.close()
    end
    local f = fs.open(proto.SECRET_PATH, "w"); f.write(secret); f.close()

    local act = item.action
    if act == "lockdown" then
        proto.send(nil, "facility_alert", {state="lockdown", zones={}, breaches={}})
        novaStatus({"LOCKDOWN SPOOFED"}, "ok")
    elseif act == "breach" then
        proto.send(nil, "facility_alert", {state="breach", zones={}, breaches={{scpId="???",zone="UNKNOWN"}}})
        novaStatus({"BREACH INJECTED"}, "ok")
    elseif act == "allclear" then
        proto.send(nil, "facility_alert", {state="normal", zones={}, breaches={}})
        novaStatus({"ALL CLEAR SPOOFED"}, "ok")
    elseif act == "siren_breach" then
        proto.send(nil, "alarm_set", {pattern="breach"})
        novaStatus({"SIRENS TRIGGERED"}, "ok")
    elseif act == "siren_panic" then
        proto.send(nil, "alarm_set", {pattern="panic"})
        novaStatus({"PANIC SENT"}, "ok")
    elseif act == "siren_off" then
        proto.send(nil, "alarm_set", {pattern="off"})
        novaStatus({"SIRENS SILENCED"}, "ok")
    elseif act == "radio" then
        novaClear(); novaHeader("FAKE RADIO")
        term.setCursorPos(2, 5); term.setTextColor(PUR); term.write("Sender name: "); term.setTextColor(WHT)
        local fakeName = read()
        term.setCursorPos(2, 6); term.setTextColor(PUR); term.write("Message: "); term.setTextColor(WHT)
        local fakeMsg = read()
        proto.send(nil, "radio_broadcast", {from=fakeName, message=fakeMsg, channel="ALL", ts=os.epoch("utc")})
        novaStatus({"RADIO INJECTED","","As: "..fakeName}, "ok")
    end
    sleep(2)

    -- Restore
    if origSecret then
        local f2 = fs.open(proto.SECRET_PATH, "w"); f2.write(origSecret); f2.close()
    end
end

-- ============================================================
-- Tool 7: Keylogger
-- ============================================================
local function keyloggerMode()
    novaClear(); novaHeader("KEYLOGGER DEPLOY")
    term.setCursorPos(2, 5); term.setTextColor(RED); term.write("Disguises as a door scanner.")
    term.setCursorPos(2, 6); term.write("Captures card disk IDs silently.")
    term.setCursorPos(2, 8); term.setTextColor(PUR); term.write("Door label: "); term.setTextColor(WHT)
    local doorLabel = read(); if doorLabel == "" then doorLabel = "SECTOR ACCESS" end
    term.setCursorPos(2, 10); term.setTextColor(PUR); term.write("Type DEPLOY: "); term.setTextColor(WHT)
    if read() ~= "DEPLOY" then return end

    local drive
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == "drive" then drive = peripheral.wrap(side); break end
    end
    if not drive then novaStatus({"NO DISK DRIVE"}, "fail"); sleep(2); return end

    local stolen = {}
    while true do
        -- Fake door idle
        ui.bigStatus(term.current(), {doorLabel,"",">>  INSERT ID CARD  <<","","Authorised personnel only."}, "idle")
        if monitor then
            ui.bigStatus(monitor, {doorLabel,"",">>  INSERT ID CARD  <<","","Authorised personnel only."}, "idle")
        end
        local evt = {os.pullEvent()}
        if evt[1] == "disk" then
            local diskID = drive.getDiskID()
            if diskID then
                stolen[#stolen+1] = {diskID=diskID, ts=os.epoch("utc")}
                ui.bigStatus(term.current(), {"VERIFYING...","","Contacting mainframe"}, "working")
                if monitor then ui.bigStatus(monitor, {"VERIFYING...","","Contacting mainframe"}, "working") end
                sleep(math.random(10, 25) / 10)
                ui.bigStatus(term.current(), {"MAINFRAME","UNREACHABLE","","Try another terminal."}, "error")
                if monitor then ui.bigStatus(monitor, {"MAINFRAME","UNREACHABLE","","Try another terminal."}, "error") end
                sleep(3)
                while drive.getDiskID() do sleep(0.3) end
            end
        elseif evt[1] == "key" and evt[2] == keys.f1 then
            local f = fs.open("/.nova_stolen_cards", "w")
            for _, s in ipairs(stolen) do f.writeLine(textutils.serialize(s, {compact=true})) end
            f.close()
            novaStatus({"KEYLOGGER STOPPED","",#stolen.." card(s) captured"}, "ok"); sleep(2); return
        end
    end
end

-- ============================================================
-- Tool 8: Stolen Cards
-- ============================================================
local function stolenCardsView()
    local cards = {}
    if fs.exists("/.nova_stolen_cards") then
        local f = fs.open("/.nova_stolen_cards", "r")
        while true do
            local l = f.readLine(); if not l then break end
            local ok, entry = pcall(textutils.unserialize, l)
            if ok and entry then cards[#cards+1] = entry end
        end; f.close()
    end
    if #cards == 0 then novaStatus({"NO STOLEN CARDS","","Deploy keylogger first."}, "info"); sleep(1.5); return end
    local items = {}
    for _, c in ipairs(cards) do
        items[#items+1] = {label="DISK #"..c.diskID.."  "..os.date("%m/%d %H:%M", (c.ts or 0)/1000), color=YEL}
    end
    scrollList("STOLEN CARDS // "..#cards, items)
end

-- ============================================================
-- Settings + Purge
-- ============================================================
local function settings()
    novaClear(); novaHeader("SETTINGS")
    term.setCursorPos(2, 5); term.setTextColor(PUR); term.write("Callsign: "); term.setTextColor(WHT); term.write(CALLSIGN)
    term.setCursorPos(2, 6); term.setTextColor(PUR); term.write("Motto: "); term.setTextColor(GRY); term.write('"'..MOTTO..'"')
    term.setCursorPos(2, 8); term.setTextColor(PUR); term.write("New callsign: "); term.setTextColor(WHT)
    local nc = read(); if nc ~= "" then CALLSIGN = nc; myCfg.callsign = nc end
    term.setCursorPos(2, 9); term.setTextColor(PUR); term.write("New motto: "); term.setTextColor(WHT)
    local nm = read(); if nm ~= "" then MOTTO = nm; myCfg.motto = nm end
    require("ctnconfig").save(myCfg)
    novaStatus({"SETTINGS SAVED"}, "ok"); sleep(1)
end

local function purgeData()
    novaClear(); novaHeader("PURGE ALL DATA")
    term.setCursorPos(2, 6); term.setTextColor(RED); term.write("Delete ALL captured data?")
    term.setCursorPos(2, 8); term.setTextColor(PUR); term.write("Type PURGE: "); term.setTextColor(WHT)
    if read() ~= "PURGE" then return end
    captures = {}; knownHosts = {}; knownProtocols = {}
    fs.delete("/.nova_captures"); fs.delete("/.nova_stolen_cards")
    novaStatus({"DATA PURGED","","All evidence destroyed."}, "ok"); sleep(2)
end

-- ============================================================
-- Main menu
-- ============================================================
local menuItems = {
    {label="Network Scanner",   action="scanner",    icon="[~]"},
    {label="Host Intelligence", action="hosts",      icon="[#]"},
    {label="Protocol Analysis", action="protocols",  icon="[?]"},
    {label="Capture Viewer",    action="captures",   icon="[>]"},
    {label="Signal Jammer",     action="jammer",     icon="[!]"},
    {label="Impersonator",      action="impersonate", icon="[*]"},
    {label="Keylogger Deploy",  action="keylogger",  icon="[@]"},
    {label="Stolen Cards",      action="cards",      icon="[$]"},
    {label="Settings",          action="settings",   icon="[=]"},
    {label="Purge All Data",    action="purge",      icon="[X]"},
}

local ACTIONS = {
    scanner=scannerView, hosts=hostIntel, protocols=protocolAnalysis,
    captures=captureViewer, jammer=signalJammer, impersonate=impersonator,
    keylogger=keyloggerMode, cards=stolenCardsView, settings=settings, purge=purgeData,
}

local function mainMenu()
    while true do
        novaClear()
        local w, h = term.getSize()
        term.setCursorPos(1, 1); term.setBackgroundColor(PUR); term.setTextColor(BLK)
        term.write(string.rep(" ", w))
        local title = "N.O.V.A // "..CALLSIGN
        term.setCursorPos(math.max(1, math.floor((w-#title)/2)+1), 1); term.write(title)
        term.setBackgroundColor(BLK)
        term.setCursorPos(1, 2); term.setTextColor(GRY)
        local stats = " "..#captures.." cap  "..tblCount(knownHosts).." hosts  "..tblCount(knownProtocols).." proto"
        term.write(stats:sub(1, w))
        term.setCursorPos(1, 3); term.setTextColor(PUR); term.write(string.rep("=", w))

        -- Update monitor with idle feed
        pcall(drawMonitorFeed)

        local selected, top = 1, 1
        local rows = h - 6
        while true do
            for row = 1, rows do
                local idx = top + row - 1
                local item = menuItems[idx]
                term.setCursorPos(1, 3 + row)
                if not item then
                    term.setBackgroundColor(BLK); term.write(string.rep(" ", w))
                elseif idx == selected then
                    term.setBackgroundColor(PUR); term.setTextColor(BLK)
                    local line = " "..item.icon.." "..item.label
                    term.write(line:sub(1,w)); term.write(string.rep(" ", math.max(0, w-#line)))
                    term.setBackgroundColor(BLK)
                else
                    term.setBackgroundColor(BLK); term.setTextColor(PUR)
                    local line = " "..item.icon.." "..item.label
                    term.write(line:sub(1,w)); term.write(string.rep(" ", math.max(0, w-#line)))
                end
            end
            term.setCursorPos(1, h-1); term.setTextColor(GRY)
            local ml = '"'..MOTTO..'"'
            term.write(string.rep(" ", math.max(0, math.floor((w-#ml)/2)))); term.write(ml:sub(1,w))
            novaFooter(os.date("%H:%M").."  N.O.V.A  "..CALLSIGN)

            local evt = {os.pullEvent()}
            if evt[1] == "key" then
                if evt[2] == keys.up and selected > 1 then
                    selected = selected - 1; if selected < top then top = selected end
                elseif evt[2] == keys.down and selected < #menuItems then
                    selected = selected + 1; if selected >= top + rows then top = top + 1 end
                elseif evt[2] == keys.enter then
                    local fn = ACTIONS[menuItems[selected].action]
                    if fn then pcall(fn) end; break
                end
            elseif evt[1] == "mouse_click" then
                local idx = top + (evt[4] - 4)
                if idx >= 1 and idx <= #menuItems then
                    local fn = ACTIONS[menuItems[idx].action]; if fn then pcall(fn) end; break
                end
            elseif evt[1] == "rednet_message" then
                -- Passive capture even from main menu
                processCapture(evt[2], evt[3], evt[4])
                pcall(drawMonitorFeed)
            end
        end
    end
end

-- ============================================================
-- Boot
-- ============================================================
bootSequence()
mainMenu()

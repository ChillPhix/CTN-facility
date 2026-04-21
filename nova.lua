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

-- ============================================================
-- Purple/black theme constants
-- ============================================================
local PUR  = colors.purple
local BLK  = colors.black
local WHT  = colors.white
local GRY  = colors.gray
local RED  = colors.red
local GRN  = colors.lime
local YEL  = colors.yellow
local CYN  = colors.cyan

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

local SKULL = {
    "   ______   ",
    "  /      \\  ",
    " | (o)(o) | ",
    " |   /\\   | ",
    " |  ||||  | ",
    "  \\______/  ",
}

local EYE = {
    "  /---\\  ",
    " / o o \\ ",
    " \\  ^  / ",
    "  \\---/  ",
}

-- ============================================================
-- Boot animation
-- ============================================================
local function bootSequence()
    local w, h = term.getSize()

    -- Phase 1: black screen with slow text reveal
    term.setBackgroundColor(BLK); term.clear()
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
        if y >= h - 1 then
            -- Scroll effect
            sleep(0.1)
            term.scroll(1)
            y = y - 1
        end
        term.setCursorPos(2, y)
        term.setTextColor(line.color)
        -- Type each character
        for i = 1, #line.text do
            term.write(line.text:sub(i, i))
            if i % 4 == 0 then sleep(0.01) end
        end
        y = y + 1
        sleep(line.delay)
    end

    sleep(0.3)

    -- Phase 2: Shield splash with animation
    term.setBackgroundColor(BLK); term.clear()

    -- Draw shield centered
    local shieldStartY = math.max(1, math.floor((h - #SHIELD) / 2) - 2)
    for i, line in ipairs(SHIELD) do
        local x = math.max(1, math.floor((w - #line) / 2) + 1)
        term.setCursorPos(x, shieldStartY + i - 1)
        term.setTextColor(PUR)
        -- Animate: reveal line by line with flash
        term.write(line)
        sleep(0.05)
    end

    sleep(0.3)

    -- Flash effect
    for flash = 1, 3 do
        term.setBackgroundColor(PUR); term.clear()
        sleep(0.05)
        term.setBackgroundColor(BLK); term.clear()
        -- Redraw shield
        for i, line in ipairs(SHIELD) do
            local x = math.max(1, math.floor((w - #line) / 2) + 1)
            term.setCursorPos(x, shieldStartY + i - 1)
            term.setTextColor(flash == 3 and WHT or PUR)
            term.write(line)
        end
        sleep(0.08)
    end

    -- Title under shield
    local titleY = shieldStartY + #SHIELD + 1
    local title = "N . O . V . A"
    local titleX = math.max(1, math.floor((w - #title) / 2) + 1)
    term.setTextColor(WHT)
    -- Animate title character by character
    for i = 1, #title do
        term.setCursorPos(titleX + i - 1, titleY)
        term.write(title:sub(i, i))
        sleep(0.06)
    end

    sleep(0.2)

    -- Subtitle
    local sub = "P R O J E C T   O V E R S I G H T"
    local subX = math.max(1, math.floor((w - #sub) / 2) + 1)
    term.setCursorPos(subX, titleY + 1); term.setTextColor(PUR)
    term.write(sub)

    sleep(0.3)

    -- Motto
    local mottoX = math.max(1, math.floor((w - #MOTTO) / 2) + 1)
    term.setCursorPos(mottoX, titleY + 3); term.setTextColor(GRY)
    term.write('"'..MOTTO..'"')

    sleep(0.4)

    -- Callsign
    local csLine = "OPERATOR: "..CALLSIGN
    local csX = math.max(1, math.floor((w - #csLine) / 2) + 1)
    term.setCursorPos(csX, titleY + 5); term.setTextColor(CYN)
    term.write(csLine)

    sleep(1.5)

    -- Phase 3: Glitch transition
    for glitch = 1, 6 do
        local gy = math.random(1, h)
        term.setCursorPos(1, gy)
        term.setTextColor(({PUR, RED, GRN, CYN})[math.random(1, 4)])
        local noise = ""
        for i = 1, w do
            noise = noise .. string.char(math.random(33, 126))
        end
        term.write(noise)
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
-- UI framework
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
    else
        term.write(string.rep(" ", w))
    end
    term.setCursorPos(1, 3); term.setTextColor(PUR)
    term.write(string.rep("=", w))
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
                term.write(line:sub(1, w))
                term.write(string.rep(" ", math.max(0, w - #line)))
                term.setBackgroundColor(BLK)
            end
        end
        novaFooter(footer or "ENTER=select  Q=back")
        local evt = {os.pullEvent()}
        if evt[1] == "key" then
            if evt[2] == keys.up and selected > 1 then
                selected = selected - 1
                if selected < top then top = selected end
            elseif evt[2] == keys.down and selected < #items then
                selected = selected + 1
                if selected >= top + rows then top = top + 1 end
            elseif evt[2] == keys.enter and items[selected] then
                return selected, items[selected]
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
-- Network capture processor
-- ============================================================
local function processCapture(sender, message, protocol)
    local entry = {
        ts = os.epoch("utc"),
        from = sender,
        protocol = protocol or "?",
    }
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
    else
        entry.type = "non-table"
    end

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

        -- Stats bar
        term.setCursorPos(2, 5); term.setTextColor(GRN)
        term.write(">> INTERCEPTED: "..newCaptures.." new  ("..#captures.." total)")
        term.setCursorPos(2, 6); term.setTextColor(PUR)
        term.write(">> HOSTS: "..tblCount(knownHosts).."  PROTOCOLS: "..tblCount(knownProtocols))

        -- Animated scanner indicator
        local phase = math.floor(os.epoch("utc") / 300) % 4
        local scanAnim = ({"|", "/", "-", "\\"})[phase + 1]
        term.setCursorPos(w - 3, 5); term.setTextColor(GRN); term.write("["..scanAnim.."]")

        -- Recent intercepts
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

        novaFooter("Q=stop and save  "..scanAnim.." scanning...")

        local evt = {os.pullEvent()}
        if evt[1] == "rednet_message" then
            processCapture(evt[2], evt[3], evt[4])
        elseif evt[1] == "timer" and evt[2] == listenTimer then
            listenTimer = os.startTimer(0.5)
        elseif evt[1] == "key" and evt[2] == keys.q then
            saveCapturesFile()
            novaStatus({"SCANNER STOPPED", "", newCaptures.." messages captured", #captures.." total in database"}, "ok")
            sleep(1.5)
            return
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

    -- Detail view
    novaClear(); novaHeader("TARGET: #"..item.id)
    local h_ = item.host
    local w, sh = term.getSize()
    local y = 5
    local function line(label, val, col)
        if y >= sh - 2 then return end
        term.setCursorPos(2, y); term.setTextColor(PUR); term.write(label..": ")
        term.setTextColor(col or WHT); term.write(tostring(val):sub(1, w - #label - 5))
        y = y + 1
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
    novaFooter("Any key to return")
    os.pullEvent("key")
end

-- ============================================================
-- Tool 3: Protocol Analysis
-- ============================================================
local function protocolAnalysis()
    local items = {}
    for name, p in pairs(knownProtocols) do
        local hostCount = tblCount(p.hosts)
        items[#items+1] = {
            label = string.format("%-15s %4dmsg  %d hosts", name:sub(1,15), p.count, hostCount),
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
                capture = c,
                color = c.hasSignature and YEL or GRY,
            }
        end
    end
    local idx, item = scrollList("CAPTURES // "..#captures.." TOTAL", items, "ENTER=inspect  Q=back")
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
    novaFooter("Any key to return")
    os.pullEvent("key")
end

-- ============================================================
-- Tool 5: Signal Jammer
-- ============================================================
local function signalJammer()
    novaClear(); novaHeader("SIGNAL JAMMER")
    local w = term.getSize()
    term.setCursorPos(2, 5); term.setTextColor(PUR); term.write("Target protocol: "); term.setTextColor(WHT)
    local targetProto = read()
    if not targetProto or targetProto == "" then return end
    term.setCursorPos(2, 6); term.setTextColor(PUR); term.write("Target host (0=broadcast): "); term.setTextColor(WHT)
    local targetHost = tonumber(read()) or 0
    term.setCursorPos(2, 7); term.setTextColor(PUR); term.write("Duration (seconds): "); term.setTextColor(WHT)
    local duration = tonumber(read()) or 10
    term.setCursorPos(2, 9); term.setTextColor(RED)
    term.write("WARNING: This will flood the target network.")
    term.setCursorPos(2, 11); term.setTextColor(PUR)
    term.write("Type EXECUTE to confirm: "); term.setTextColor(WHT)
    if read() ~= "EXECUTE" then return end

    local deadline = os.clock() + duration
    local count = 0

    while os.clock() < deadline do
        local garbage = {
            proto = targetProto, type = "x"..math.random(1,999999),
            nonce = tostring(math.random(1,2^30)), ts = os.epoch("utc"),
            payload = {}, sig = string.rep("0", 64),
        }
        if targetHost > 0 then
            rednet.send(targetHost, garbage, targetProto)
        else
            rednet.broadcast(garbage, targetProto)
        end
        count = count + 1

        if count % 20 == 0 then
            novaClear(); novaHeader("JAMMING ACTIVE")
            local phase = math.floor(os.epoch("utc") / 200) % 4
            local bar = string.rep("#", math.floor((os.clock() - (deadline - duration)) / duration * (w - 6)))
            term.setCursorPos(2, 6); term.setTextColor(RED)
            term.write("TARGET: "..targetProto..(targetHost > 0 and " #"..targetHost or " ALL"))
            term.setCursorPos(2, 8); term.setTextColor(YEL)
            term.write("PACKETS SENT: "..count)
            term.setCursorPos(2, 9); term.setTextColor(PUR)
            term.write("REMAINING: "..math.floor(deadline - os.clock()).."s")
            term.setCursorPos(2, 11); term.setTextColor(RED)
            term.write("["..bar..string.rep("-", math.max(0, w - 6 - #bar)).."]")

            -- Glitch lines
            for g = 1, 2 do
                local gy = math.random(13, select(2, term.getSize()) - 2)
                term.setCursorPos(1, gy); term.setTextColor(({RED,PUR,YEL})[math.random(1,3)])
                local noise = ""
                for i = 1, w do noise = noise .. string.char(math.random(33, 126)) end
                term.write(noise)
            end
            novaFooter("JAMMING // "..count.." packets")
        end
        sleep(0.02)
    end

    novaStatus({"JAM COMPLETE", "", count.." packets sent", "Target: "..targetProto}, "ok")
    sleep(2)
end

-- ============================================================
-- Tool 6: Impersonator
-- ============================================================
local function impersonator()
    novaClear(); novaHeader("IMPERSONATOR")
    local w = term.getSize()
    term.setCursorPos(2, 5); term.setTextColor(PUR); term.write("Target facility secret: "); term.setTextColor(WHT)
    local secret = read("*")
    if not secret or secret == "" then return end
    term.setCursorPos(2, 6); term.setTextColor(PUR); term.write("Target mainframe ID: "); term.setTextColor(WHT)
    local mfId = tonumber(read())
    if not mfId then return end

    term.setCursorPos(2, 8); term.setTextColor(CYN)
    term.write("Actions available with stolen secret:")
    local actions = {
        {label="Send fake LOCKDOWN alert",    action="lockdown"},
        {label="Send fake BREACH alert",      action="breach"},
        {label="Send fake ALL CLEAR",         action="allclear"},
        {label="Trigger sirens (breach)",      action="siren_breach"},
        {label="Trigger sirens (panic)",       action="siren_panic"},
        {label="Stop sirens",                  action="siren_off"},
        {label="Send fake radio message",      action="radio"},
    }

    local idx, item = scrollList("IMPERSONATION // #"..mfId, actions, "ENTER=execute  Q=abort")
    if not idx then return end

    -- Temporarily override the secret for sending
    local origSecret = nil
    if fs.exists(proto.SECRET_PATH) then
        local f = fs.open(proto.SECRET_PATH, "r"); origSecret = f.readAll(); f.close()
    end
    -- Write target secret temporarily
    local f = fs.open(proto.SECRET_PATH, "w"); f.write(secret); f.close()

    local act = item.action
    if act == "lockdown" then
        proto.send(nil, "facility_alert", {state="lockdown", zones={}, breaches={}})
        novaStatus({"LOCKDOWN ALERT SENT", "", "Spoofed as facility broadcast"}, "ok")
    elseif act == "breach" then
        proto.send(nil, "facility_alert", {state="breach", zones={}, breaches={{scpId="???", zone="UNKNOWN"}}})
        novaStatus({"BREACH ALERT SENT", "", "Phantom breach injected"}, "ok")
    elseif act == "allclear" then
        proto.send(nil, "facility_alert", {state="normal", zones={}, breaches={}})
        novaStatus({"ALL CLEAR SENT", "", "Facility state spoofed to normal"}, "ok")
    elseif act == "siren_breach" then
        -- Need to know siren computer IDs; broadcast to all
        rednet.broadcast({type="alarm_set", payload={pattern="breach"}, proto="CTN", sig="", nonce="", ts=0}, "CTN")
        -- Actually use the proper proto.send
        proto.send(nil, "alarm_set", {pattern="breach"})
        novaStatus({"SIREN TRIGGER SENT", "", "Breach pattern broadcast"}, "ok")
    elseif act == "siren_panic" then
        proto.send(nil, "alarm_set", {pattern="panic"})
        novaStatus({"PANIC SIREN SENT"}, "ok")
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
        novaStatus({"RADIO INJECTED", "", "As: "..fakeName, fakeMsg:sub(1,30)}, "ok")
    end

    sleep(2)

    -- Restore original secret
    if origSecret then
        local f2 = fs.open(proto.SECRET_PATH, "w"); f2.write(origSecret); f2.close()
    end
end

-- ============================================================
-- Tool 7: Keylogger Terminal Mode
-- ============================================================
local function keyloggerMode()
    novaClear(); novaHeader("KEYLOGGER MODE")
    local w, h = term.getSize()
    term.setCursorPos(2, 5); term.setTextColor(RED)
    term.write("This mode disguises this terminal as a")
    term.setCursorPos(2, 6)
    term.write("legitimate door scanner. When a card is")
    term.setCursorPos(2, 7)
    term.write("inserted, it logs the disk ID silently.")
    term.setCursorPos(2, 9); term.setTextColor(PUR)
    term.write("Door label to display: "); term.setTextColor(WHT)
    local doorLabel = read()
    if not doorLabel or doorLabel == "" then doorLabel = "SECTOR ACCESS" end

    term.setCursorPos(2, 11); term.setTextColor(PUR)
    term.write("Type DEPLOY to activate: "); term.setTextColor(WHT)
    if read() ~= "DEPLOY" then return end

    local drive
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == "drive" then drive = peripheral.wrap(side); break end
    end
    if not drive then
        novaStatus({"NO DISK DRIVE", "", "Attach a drive to capture cards."}, "fail")
        sleep(2); return
    end

    local stolen = {}

    -- Disguise as legitimate door
    while true do
        -- Show fake door idle screen
        ui.bigStatus(term.current(), {doorLabel, "", ">>  INSERT ID CARD  <<", "", "Authorised personnel only."}, "idle")

        local evt = {os.pullEvent()}
        if evt[1] == "disk" then
            local diskID = drive.getDiskID()
            if diskID then
                stolen[#stolen+1] = {diskID=diskID, ts=os.epoch("utc")}
                -- Show fake "processing" then fake "error"
                ui.bigStatus(term.current(), {"VERIFYING...","","Contacting mainframe"}, "working")
                sleep(math.random(10, 25) / 10)
                ui.bigStatus(term.current(), {"MAINFRAME","UNREACHABLE","","Please try another terminal."}, "error")
                sleep(3)
                -- Wait for disk removal
                while drive.getDiskID() do sleep(0.3) end
            end
        elseif evt[1] == "key" and evt[2] == keys.f1 then
            -- Secret exit: F1 returns to NOVA menu
            -- Save stolen card data
            local f = fs.open("/.nova_stolen_cards", "w")
            for _, s in ipairs(stolen) do
                f.writeLine(textutils.serialize(s, {compact=true}))
            end
            f.close()
            novaStatus({"KEYLOGGER STOPPED", "", #stolen.." card(s) captured", "Saved to /.nova_stolen_cards"}, "ok")
            sleep(2)
            return
        end
    end
end

-- ============================================================
-- Tool 8: Stolen Cards Viewer
-- ============================================================
local function stolenCardsView()
    local cards = {}
    if fs.exists("/.nova_stolen_cards") then
        local f = fs.open("/.nova_stolen_cards", "r")
        while true do
            local l = f.readLine()
            if not l then break end
            local ok, entry = pcall(textutils.unserialize, l)
            if ok and entry then cards[#cards+1] = entry end
        end
        f.close()
    end
    if #cards == 0 then
        novaStatus({"NO STOLEN CARDS", "", "Deploy keylogger first."}, "info")
        sleep(1.5); return
    end
    local items = {}
    for _, c in ipairs(cards) do
        local ts = os.date("%m/%d %H:%M", (c.ts or 0) / 1000)
        items[#items+1] = {label = "DISK #"..c.diskID.."  captured "..ts, color=YEL}
    end
    scrollList("STOLEN CARDS // "..#cards, items)
end

-- ============================================================
-- Settings
-- ============================================================
local function settings()
    novaClear(); novaHeader("SETTINGS")
    local w = term.getSize()
    term.setCursorPos(2, 5); term.setTextColor(PUR); term.write("Current callsign: "); term.setTextColor(WHT); term.write(CALLSIGN)
    term.setCursorPos(2, 6); term.setTextColor(PUR); term.write("Current motto: "); term.setTextColor(GRY); term.write('"'..MOTTO..'"')
    term.setCursorPos(2, 8); term.setTextColor(PUR); term.write("New callsign (blank=keep): "); term.setTextColor(WHT)
    local newCS = read()
    if newCS and newCS ~= "" then
        CALLSIGN = newCS
        myCfg.callsign = newCS
    end
    term.setCursorPos(2, 9); term.setTextColor(PUR); term.write("New motto (blank=keep): "); term.setTextColor(WHT)
    local newMotto = read()
    if newMotto and newMotto ~= "" then
        MOTTO = newMotto
        myCfg.motto = newMotto
    end
    -- Save config
    local cfgMod = require("ctnconfig")
    cfgMod.save(myCfg)
    novaStatus({"SETTINGS SAVED"}, "ok")
    sleep(1)
end

-- ============================================================
-- Purge data
-- ============================================================
local function purgeData()
    novaClear(); novaHeader("PURGE ALL DATA")
    term.setCursorPos(2, 6); term.setTextColor(RED)
    term.write("This will delete ALL captured data,")
    term.setCursorPos(2, 7); term.write("stolen cards, and local files.")
    term.setCursorPos(2, 9); term.setTextColor(PUR)
    term.write("Type PURGE to confirm: "); term.setTextColor(WHT)
    if read() ~= "PURGE" then return end
    captures = {}; knownHosts = {}; knownProtocols = {}
    fs.delete("/.nova_captures")
    fs.delete("/.nova_stolen_cards")
    novaStatus({"DATA PURGED", "", "All evidence destroyed."}, "ok")
    sleep(2)
end

-- ============================================================
-- Main menu
-- ============================================================
local menuItems = {
    {label="Network Scanner",      action="scanner",   icon="[~]"},
    {label="Host Intelligence",    action="hosts",     icon="[#]"},
    {label="Protocol Analysis",    action="protocols", icon="[?]"},
    {label="Capture Viewer",       action="captures",  icon="[>]"},
    {label="Signal Jammer",        action="jammer",    icon="[!]"},
    {label="Impersonator",         action="impersonate",icon="[*]"},
    {label="Keylogger Deploy",     action="keylogger", icon="[@]"},
    {label="Stolen Cards",         action="cards",     icon="[$]"},
    {label="Settings",             action="settings",  icon="[=]"},
    {label="Purge All Data",       action="purge",     icon="[X]"},
}

local ACTIONS = {
    scanner     = scannerView,
    hosts       = hostIntel,
    protocols   = protocolAnalysis,
    captures    = captureViewer,
    jammer      = signalJammer,
    impersonate = impersonator,
    keylogger   = keyloggerMode,
    cards       = stolenCardsView,
    settings    = settings,
    purge       = purgeData,
}

local function mainMenu()
    while true do
        novaClear()
        local w, h = term.getSize()

        -- Header with animated eye
        term.setCursorPos(1, 1); term.setBackgroundColor(PUR); term.setTextColor(BLK)
        term.write(string.rep(" ", w))
        local title = "N.O.V.A // "..CALLSIGN
        term.setCursorPos(math.max(1, math.floor((w - #title)/2)+1), 1); term.write(title)
        term.setBackgroundColor(BLK)

        -- Status line
        term.setCursorPos(1, 2); term.setTextColor(GRY)
        local statusLine = " "..#captures.." captures  "..tblCount(knownHosts).." hosts  "..tblCount(knownProtocols).." protocols"
        term.write(statusLine:sub(1, w))
        term.setCursorPos(1, 3); term.setTextColor(PUR); term.write(string.rep("=", w))

        -- Menu items with icons
        local selected = 1
        local top = 1
        local rows = h - 6

        while true do
            for row = 1, rows do
                local idx = top + row - 1
                local item = menuItems[idx]
                local y = 3 + row
                term.setCursorPos(1, y)
                if not item then
                    term.setBackgroundColor(BLK); term.write(string.rep(" ", w))
                elseif idx == selected then
                    term.setBackgroundColor(PUR); term.setTextColor(BLK)
                    local line = " "..item.icon.." "..item.label
                    term.write(line:sub(1,w)); term.write(string.rep(" ", math.max(0, w - #line)))
                    term.setBackgroundColor(BLK)
                else
                    term.setBackgroundColor(BLK); term.setTextColor(PUR)
                    local line = " "..item.icon.." "..item.label
                    term.write(line:sub(1,w)); term.write(string.rep(" ", math.max(0, w - #line)))
                end
            end

            -- Motto at bottom
            term.setCursorPos(1, h - 1); term.setTextColor(GRY)
            local mottoLine = '"'..MOTTO..'"'
            term.write(string.rep(" ", math.max(0, math.floor((w - #mottoLine)/2))))
            term.write(mottoLine:sub(1, w))

            novaFooter(os.date("%H:%M").."  N.O.V.A  "..CALLSIGN)

            local evt = {os.pullEvent()}
            if evt[1] == "key" then
                if evt[2] == keys.up and selected > 1 then
                    selected = selected - 1
                    if selected < top then top = selected end
                elseif evt[2] == keys.down and selected < #menuItems then
                    selected = selected + 1
                    if selected >= top + rows then top = top + 1 end
                elseif evt[2] == keys.enter then
                    local fn = ACTIONS[menuItems[selected].action]
                    if fn then pcall(fn) end
                    break
                end
            elseif evt[1] == "mouse_click" then
                local idx = top + (evt[4] - 4)
                if idx >= 1 and idx <= #menuItems then
                    selected = idx
                    local fn = ACTIONS[menuItems[selected].action]
                    if fn then pcall(fn) end
                    break
                end
            end
        end
    end
end

-- ============================================================
-- Boot
-- ============================================================
bootSequence()
mainMenu()

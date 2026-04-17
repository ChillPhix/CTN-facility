-- ctnproto.lua
-- Shared networking protocol for the CTN facility system.
-- Provides HMAC-signed messages with nonces and timestamp replay protection.
--
-- Place this file at /lib/ctnproto.lua on every CTN computer.
-- The shared secret lives at /.ctn_secret (600-ish perms by convention, CC has no real perms).

local M = {}

-- ============================================================
-- Configuration
-- ============================================================
M.PROTOCOL     = "CTN"
M.VERSION      = 1
M.MAX_AGE      = 10        -- seconds; reject messages older than this
M.SECRET_PATH  = "/.ctn_secret"
M.SEEN_NONCES  = {}        -- in-memory replay cache

-- ============================================================
-- SHA-256 implementation (compact, pure Lua)
-- Based on the FIPS 180-4 spec. Works in CC:T's Lua 5.1-ish env.
-- ============================================================
local band, bor, bxor, bnot = bit32.band, bit32.bor, bit32.bxor, bit32.bnot
local rshift, lshift, rrotate = bit32.rshift, bit32.lshift, bit32.rrotate

local K = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}

local function str2bytes(s)
    local t = {}
    for i = 1, #s do t[i] = s:byte(i) end
    return t
end

local function bytes2hex(b)
    local t = {}
    for i = 1, #b do t[i] = string.format("%02x", b[i]) end
    return table.concat(t)
end

local function sha256(msg)
    local bytes = type(msg) == "string" and str2bytes(msg) or msg
    local origLen = #bytes
    local bitLen = origLen * 8

    bytes[#bytes + 1] = 0x80
    while (#bytes % 64) ~= 56 do bytes[#bytes + 1] = 0 end
    for i = 7, 0, -1 do
        bytes[#bytes + 1] = band(rshift(bitLen, i * 8), 0xff)
    end

    local H = {
        0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
        0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19,
    }

    for chunk = 0, #bytes - 1, 64 do
        local w = {}
        for i = 0, 15 do
            local j = chunk + i * 4
            w[i + 1] = lshift(bytes[j+1],24) + lshift(bytes[j+2],16) + lshift(bytes[j+3],8) + bytes[j+4]
        end
        for i = 17, 64 do
            local s0 = bxor(rrotate(w[i-15],7), rrotate(w[i-15],18), rshift(w[i-15],3))
            local s1 = bxor(rrotate(w[i-2],17), rrotate(w[i-2],19), rshift(w[i-2],10))
            w[i] = band(w[i-16] + s0 + w[i-7] + s1, 0xffffffff)
        end
        local a,b,c,d,e,f,g,h = H[1],H[2],H[3],H[4],H[5],H[6],H[7],H[8]
        for i = 1, 64 do
            local S1 = bxor(rrotate(e,6), rrotate(e,11), rrotate(e,25))
            local ch = bxor(band(e,f), band(bnot(e),g))
            local temp1 = band(h + S1 + ch + K[i] + w[i], 0xffffffff)
            local S0 = bxor(rrotate(a,2), rrotate(a,13), rrotate(a,22))
            local mj = bxor(band(a,b), band(a,c), band(b,c))
            local temp2 = band(S0 + mj, 0xffffffff)
            h = g; g = f; f = e
            e = band(d + temp1, 0xffffffff)
            d = c; c = b; b = a
            a = band(temp1 + temp2, 0xffffffff)
        end
        H[1]=band(H[1]+a,0xffffffff); H[2]=band(H[2]+b,0xffffffff)
        H[3]=band(H[3]+c,0xffffffff); H[4]=band(H[4]+d,0xffffffff)
        H[5]=band(H[5]+e,0xffffffff); H[6]=band(H[6]+f,0xffffffff)
        H[7]=band(H[7]+g,0xffffffff); H[8]=band(H[8]+h,0xffffffff)
    end

    local out = {}
    for i = 1, 8 do
        out[#out+1] = band(rshift(H[i],24),0xff)
        out[#out+1] = band(rshift(H[i],16),0xff)
        out[#out+1] = band(rshift(H[i],8),0xff)
        out[#out+1] = band(H[i],0xff)
    end
    return bytes2hex(out)
end

-- HMAC-SHA256 (RFC 2104)
local function hmac(key, message)
    local keyBytes = str2bytes(key)
    if #keyBytes > 64 then
        local h = sha256(keyBytes)
        keyBytes = {}
        for i = 1, #h, 2 do keyBytes[#keyBytes+1] = tonumber(h:sub(i,i+1),16) end
    end
    while #keyBytes < 64 do keyBytes[#keyBytes+1] = 0 end

    local o, ii = {}, {}
    for i = 1, 64 do
        o[i]  = bxor(keyBytes[i], 0x5c)
        ii[i] = bxor(keyBytes[i], 0x36)
    end

    local msgBytes = str2bytes(message)
    local inner = {}
    for i = 1, 64 do inner[i] = ii[i] end
    for i = 1, #msgBytes do inner[64+i] = msgBytes[i] end
    local innerHash = sha256(inner)

    local outer = {}
    for i = 1, 64 do outer[i] = o[i] end
    for i = 1, #innerHash, 2 do
        outer[64 + (i+1)/2] = tonumber(innerHash:sub(i,i+1),16)
    end
    return sha256(outer)
end

M.sha256 = sha256
M.hmac   = hmac

-- ============================================================
-- Secret management
-- ============================================================
function M.loadSecret()
    if not fs.exists(M.SECRET_PATH) then
        error("CTN secret not found at "..M.SECRET_PATH..". Run secret-install first.", 2)
    end
    local f = fs.open(M.SECRET_PATH, "r")
    local s = f.readAll()
    f.close()
    return s:gsub("%s+$", "")
end

function M.installSecret(secret)
    local f = fs.open(M.SECRET_PATH, "w")
    f.write(secret)
    f.close()
end

-- ============================================================
-- Nonce + envelope
-- ============================================================
local function makeNonce()
    return string.format("%d-%d-%d", os.epoch("utc"), math.random(1, 2^30), os.getComputerID())
end

local function canonical(envelope)
    -- Deterministic recursive serializer that guarantees identical output
    -- on sender and receiver regardless of Lua's internal table key order.
    local function ser(v)
        local t = type(v)
        if t == "nil" then
            return "N"
        elseif t == "boolean" then
            return v and "T" or "F"
        elseif t == "number" then
            -- use %.14g for stable number formatting
            return "n:"..string.format("%.14g", v)
        elseif t == "string" then
            return "s:"..#v..":"..v
        elseif t == "table" then
            -- collect + sort keys (convert to strings for comparability)
            local keys = {}
            for k in pairs(v) do keys[#keys+1] = k end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            local parts = {"{"}
            for _, k in ipairs(keys) do
                parts[#parts+1] = ser(k).."="..ser(v[k])..";"
            end
            parts[#parts+1] = "}"
            return table.concat(parts)
        else
            return "?:"..t
        end
    end

    -- Serialize envelope top-level, skipping the sig field itself.
    local keys = {}
    for k in pairs(envelope) do if k ~= "sig" then keys[#keys+1] = k end end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts+1] = k.."="..ser(envelope[k])
    end
    return table.concat(parts, "&")
end

--- Send a signed message to a target computer ID.
-- @param target  computer ID (number) or nil for broadcast
-- @param msgType string e.g. "auth_request", "door_open"
-- @param payload table
function M.send(target, msgType, payload)
    local secret = M.loadSecret()
    local env = {
        proto   = M.PROTOCOL,
        version = M.VERSION,
        type    = msgType,
        from    = os.getComputerID(),
        nonce   = makeNonce(),
        ts      = os.epoch("utc"),
        payload = payload or {},
    }
    env.sig = hmac(secret, canonical(env))
    if target then
        rednet.send(target, env, M.PROTOCOL)
    else
        rednet.broadcast(env, M.PROTOCOL)
    end
end

--- Receive + verify a message.
-- @param timeout seconds or nil
-- @return senderID, msgType, payload  OR  nil, errReason
function M.receive(timeout)
    local secret = M.loadSecret()
    local sender, env, proto = rednet.receive(M.PROTOCOL, timeout)
    if not sender then return nil, "timeout" end
    if type(env) ~= "table" then return nil, "malformed" end
    if env.proto ~= M.PROTOCOL then return nil, "wrong_proto" end
    if env.version ~= M.VERSION then return nil, "wrong_version" end
    if type(env.sig) ~= "string" then return nil, "no_sig" end

    local expected = hmac(secret, canonical(env))
    if expected ~= env.sig then return nil, "bad_sig" end

    -- Replay protection: reject old or duplicate nonces
    local now = os.epoch("utc")
    if math.abs(now - env.ts) > M.MAX_AGE * 1000 then return nil, "stale" end
    if M.SEEN_NONCES[env.nonce] then return nil, "replay" end
    M.SEEN_NONCES[env.nonce] = now

    -- GC old nonces occasionally
    if math.random(1, 50) == 1 then
        for n, t in pairs(M.SEEN_NONCES) do
            if now - t > M.MAX_AGE * 2000 then M.SEEN_NONCES[n] = nil end
        end
    end

    return env.from, env.type, env.payload
end

--- Open the first available modem. Returns the side opened.
function M.openModem()
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == "modem" then
            if not rednet.isOpen(side) then rednet.open(side) end
            return side
        end
    end
    error("No modem found. Attach a wireless modem to this computer.", 2)
end

--- Send a request and wait for a reply of type msgType.."_reply".
-- @param target   computer ID
-- @param msgType  string
-- @param payload  table
-- @param timeout  seconds (default 3)
-- @return reply payload, or nil on timeout
function M.request(target, msgType, payload, timeout)
    timeout = timeout or 3
    M.send(target, msgType, payload)
    local deadline = os.clock() + timeout
    while os.clock() < deadline do
        local from, mtype, reply = M.receive(0.5)
        if from == target and mtype == msgType .. "_reply" then
            return reply
        end
    end
    return nil
end

return M

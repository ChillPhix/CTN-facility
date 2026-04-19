-- mainframe/db.lua
-- Persistent database for CTN mainframe.
-- Stores: personnel, disks, doors, zones, passcodes, logs.

local M = {}

M.PATH = "/ctn_db"
M.LOG_PATH = "/ctn_log"
M.MAX_LOG_LINES = 5000

-- ============================================================
-- In-memory schema
-- ============================================================
-- personnel[playerName] = {
--     name = "Bob",
--     clearance = 4,              -- 0 highest .. 5 lowest
--     department = "Security",    -- "Security" | "Research" | "MTF" | "Medical" | "Admin" | "Janitor" | "Guest"
--     flags = { maintenance = true, scp173_access = true },  -- arbitrary perms
--     status = "active",          -- "active" | "suspended" | "terminated"
-- }
--
-- disks[diskID] = {
--     owner = "Bob",              -- playerName in personnel
--     issued = 1234567890,        -- epoch ms
--     issuedBy = "AdminName",
--     status = "active",          -- "active" | "revoked" | "lost"
-- }
--
-- doors[doorName] = {
--     terminalId = 17,            -- computer ID of the door's scanner terminal
--     zone = "HCZ",
--     minClearance = 3,           -- must be <= this number
--     requiredDepartments = nil,  -- nil = any, or {"Security","MTF"}
--     requiredFlag = nil,         -- nil, or "maintenance"
-- }
--
-- zones[zoneName] = { lockdown = false, alarm = "normal" }
--
-- passcodes = { issuer = "1234" }  -- passcode for the card issuer terminal
--
-- facility = { state = "normal" } -- "normal" | "caution" | "warning" | "lockdown" | "breach"

local data = {
    personnel = {},
    disks     = {},
    doors     = {},
    zones     = {},
    passcodes = { issuer = "0000", control = "0000", admin = "0000" },
    facility  = { state = "normal" },
    identity  = {
        name     = "FACILITY",
        subtitle = "SYSTEM",
        fgColor  = "yellow",
        bgColor  = "black",
    },
    documents = {},
    archiveFolders = {
        root = {
            id = "root",
            name = "Departments",
            parent = nil,
            minClearance = 5,
            created = 0,
            author = "SYSTEM",
        },
    },

    -- Pending terminals awaiting admin approval.
    -- pending[computerID] = {type="door"|"alarm"|"detector", requested_at, hostname}
    pending   = {},

    -- Alarm/siren nodes registered in the facility.
    -- alarms[computerID] = {zone = "HCZ"}
    alarms    = {},

    -- Player detector nodes.
    -- detectors[computerID] = {zone = "HCZ"}
    detectors = {},

    -- Active breach / active SCP status.
    -- breaches[entityId] = {entityId, zone, declared_at, declared_by, active=true}
    breaches  = {},

    -- Contained entities.
    -- entities[entityId] = {
    --   entityId, name, class, zone, status, threat,
    --   description, procedures, minClearance, last_inspection
    -- }
    entities  = {},

    -- Chamber terminals; one per containment cell.
    -- chambers[computerId] = {entityId, zone}
    chambers  = {},
}

-- ============================================================
-- Schema migration / compatibility
-- ============================================================
local function slug(s)
    s = tostring(s or ""):lower()
    s = s:gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    if s == "" then s = "item" end
    return s
end

local function folderId(parentId, name)
    return tostring(parentId or "root").."."..slug(name)
end

local function ensureArchiveSchema()
    data.archiveFolders = data.archiveFolders or {}
    data.archiveFolders.root = data.archiveFolders.root or {
        id = "root",
        name = "Departments",
        parent = nil,
        minClearance = 5,
        created = 0,
        author = "SYSTEM",
    }
    data.documents = data.documents or {}

    -- Older databases stored documents with a plain string folder name.
    -- Promote those labels into real archive folders and attach the docs.
    for id, doc in pairs(data.documents) do
        if not doc.folderId then
            local folderName = doc.folder or "General"
            local fid = folderId("root", folderName)
            if not data.archiveFolders[fid] then
                data.archiveFolders[fid] = {
                    id = fid,
                    name = folderName,
                    parent = "root",
                    minClearance = 5,
                    created = doc.created or os.epoch("utc"),
                    author = doc.author or "SYSTEM",
                }
            end
            doc.folderId = fid
        end
        doc.id = doc.id or id
        doc.title = doc.title or id
        doc.minClearance = doc.minClearance or 5
    end
end

-- ============================================================
-- Persistence
-- ============================================================
function M.load()
    if not fs.exists(M.PATH) then M.save(); return end
    local f = fs.open(M.PATH, "r")
    local s = f.readAll()
    f.close()
    local loaded = textutils.unserialize(s)
    if type(loaded) == "table" then
        -- merge so new fields in code don't break old saves
        for k, v in pairs(loaded) do data[k] = v end
    end
    ensureArchiveSchema()
end

function M.save()
    ensureArchiveSchema()
    local f = fs.open(M.PATH, "w")
    f.write(textutils.serialize(data))
    f.close()
end

function M.get()
    ensureArchiveSchema()
    return data
end

-- ============================================================
-- Personnel
-- ============================================================
function M.addPerson(name, clearance, department, flags)
    data.personnel[name] = {
        name = name,
        clearance = clearance,
        department = department,
        flags = flags or {},
        status = "active",
    }
    M.save()
end

function M.setClearance(name, clearance)
    if data.personnel[name] then
        data.personnel[name].clearance = clearance
        M.save(); return true
    end
    return false
end

function M.setStatus(name, status)
    if data.personnel[name] then
        data.personnel[name].status = status
        M.save(); return true
    end
    return false
end

function M.setFlag(name, flag, value)
    if data.personnel[name] then
        data.personnel[name].flags[flag] = value
        M.save(); return true
    end
    return false
end

function M.setPin(name, pin)
    if data.personnel[name] then
        data.personnel[name].pin = pin
        M.save(); return true
    end
    return false
end

function M.authByPin(name, pin)
    local p = data.personnel[name]
    if not p then return nil, "unknown_person" end
    if p.status ~= "active" then return nil, "personnel_"..p.status end
    if not p.pin or p.pin == "" then return nil, "no_pin_set" end
    if p.pin ~= pin then return nil, "bad_pin" end
    return p
end

function M.getPerson(name)
    return data.personnel[name]
end

function M.listPersonnel()
    local out = {}
    for name, p in pairs(data.personnel) do
        out[#out+1] = {name=p.name, clearance=p.clearance, department=p.department,
                       status=p.status, flags=p.flags}
    end
    table.sort(out, function(a,b) return a.clearance < b.clearance or
        (a.clearance == b.clearance and a.name < b.name) end)
    return out
end

-- ============================================================
-- Radio message log (facility-wide broadcast history)
-- ============================================================
function M.addRadioMessage(from, message, channel)
    data.radioLog = data.radioLog or {}
    data.radioLog[#data.radioLog+1] = {
        ts = os.epoch("utc"),
        from = from,
        msg = message,
        channel = channel or "ALL",
    }
    -- Keep last 100
    while #data.radioLog > 100 do table.remove(data.radioLog, 1) end
    M.save()
end

function M.getRadioHistory(n)
    data.radioLog = data.radioLog or {}
    n = n or 30
    local out = {}
    local start = math.max(1, #data.radioLog - n + 1)
    for i = start, #data.radioLog do
        out[#out+1] = data.radioLog[i]
    end
    return out
end

-- ============================================================
-- Door listing for remote control
-- ============================================================
function M.listDoors()
    local out = {}
    for name, d in pairs(data.doors) do
        out[#out+1] = {
            id = name,
            name = d.name or name,
            zone = d.zone,
            computerId = d.computerId,
            minClearance = d.minClearance,
        }
    end
    table.sort(out, function(a,b) return (a.zone or "") < (b.zone or "") end)
    return out
end

-- ============================================================
-- Disks (keycards)
-- ============================================================
function M.issueDisk(diskID, owner, issuedBy)
    if not data.personnel[owner] then return false, "unknown_person" end
    data.disks[diskID] = {
        owner = owner,
        issued = os.epoch("utc"),
        issuedBy = issuedBy or "SYSTEM",
        status = "active",
    }
    M.save()
    return true
end

function M.revokeDisk(diskID)
    if data.disks[diskID] then
        data.disks[diskID].status = "revoked"
        M.save(); return true
    end
    return false
end

function M.lookupDisk(diskID)
    local d = data.disks[diskID]
    if not d then return nil, "unknown_disk" end
    if d.status ~= "active" then return nil, d.status end
    local p = data.personnel[d.owner]
    if not p then return nil, "no_owner" end
    if p.status ~= "active" then return nil, "personnel_"..p.status end
    return p, d
end

-- ============================================================
-- Doors
-- ============================================================
function M.addDoor(doorName, terminalId, zone, minClearance, opts)
    opts = opts or {}
    data.doors[doorName] = {
        terminalId = terminalId,
        zone = zone,
        minClearance = minClearance,
        requiredDepartments = opts.requiredDepartments,
        requiredFlag = opts.requiredFlag,
        -- live state
        liveState = "closed",    -- "closed" | "open" | "forced_open" | "forced_closed" | "offline"
        lastSeen = 0,            -- epoch ms of last heartbeat from terminal
        lastUser = nil,          -- name of last person who scanned
        lastAction = nil,        -- "granted" | "denied" | "remote_open" | etc
    }
    M.save()
end

function M.removeDoor(doorName)
    if data.doors[doorName] then
        data.doors[doorName] = nil
        M.save(); return true
    end
    return false
end

function M.updateDoorState(terminalId, state, meta)
    for _, d in pairs(data.doors) do
        if d.terminalId == terminalId then
            d.liveState = state or d.liveState
            d.lastSeen = os.epoch("utc")
            if meta then
                d.lastUser = meta.user or d.lastUser
                d.lastAction = meta.action or d.lastAction
            end
            M.save()
            return true
        end
    end
    return false
end

function M.setDoorForced(doorName, forced)
    -- forced: "open" | "closed" | nil (release)
    local d = data.doors[doorName]
    if not d then return false end
    if forced == "open" then d.liveState = "forced_open"
    elseif forced == "closed" then d.liveState = "forced_closed"
    else d.liveState = "closed" end
    M.save()
    return true
end

function M.getDoorByTerminal(terminalId)
    for name, d in pairs(data.doors) do
        if d.terminalId == terminalId then return name, d end
    end
    return nil
end

--- Evaluate whether a person can open a door.
-- @return allowed (bool), reason (string)
function M.checkAccess(person, door)
    if data.facility.state == "lockdown" and person.clearance > 2 then
        return false, "facility_lockdown"
    end
    if data.zones[door.zone] and data.zones[door.zone].lockdown and person.clearance > 2 then
        return false, "zone_lockdown"
    end

    -- clearance (lower number = higher clearance)
    if person.clearance > door.minClearance then
        -- special flag override
        if door.requiredFlag and person.flags[door.requiredFlag] then
            return true, "flag_override"
        end
        return false, "insufficient_clearance"
    end

    -- department filter (if specified)
    if door.requiredDepartments then
        local ok = false
        for _, dept in ipairs(door.requiredDepartments) do
            if person.department == dept then ok = true; break end
        end
        if not ok then return false, "wrong_department" end
    end

    return true, "granted"
end

-- ============================================================
-- Facility state / lockdown
-- ============================================================
function M.setFacilityState(state)
    data.facility.state = state
    M.save()
end

function M.getIdentity()
    data.identity = data.identity or {
        name = "C.T.N",
        subtitle = "CONTAINMENT DIVISION",
        colorScheme = "yellow",
    }
    return data.identity
end

function M.setIdentity(name, subtitle, fgColor, bgColor)
    data.identity = data.identity or {}
    data.identity.name = name or data.identity.name or "FACILITY"
    data.identity.subtitle = subtitle or data.identity.subtitle or "SYSTEM"
    data.identity.fgColor = fgColor or data.identity.fgColor or "yellow"
    data.identity.bgColor = bgColor or data.identity.bgColor or "black"
    M.save()
end

function M.setZoneLockdown(zone, value)
    if data.zones[zone] then
        data.zones[zone].lockdown = value
        M.save(); return true
    end
    return false
end

function M.addZone(name)
    if not name or name == "" then return false, "missing_name" end
    if data.zones[name] then return false, "zone_exists" end
    data.zones[name] = {lockdown=false, alarm="normal", occupants={}}
    M.save()
    return true
end

function M.removeZone(name)
    if not name or not data.zones[name] then return false, "not_found" end
    data.zones[name] = nil
    M.save()
    return true
end

function M.listZones()
    local out = {}
    for name, z in pairs(data.zones) do
        out[#out+1] = {name=name, lockdown=z.lockdown, occupants=z.occupants or {}}
    end
    table.sort(out, function(a,b) return a.name < b.name end)
    return out
end

function M.getZoneNames()
    local out = {}
    for name in pairs(data.zones) do out[#out+1] = name end
    table.sort(out)
    return out
end

-- ============================================================
-- Archive folders + documents
-- ============================================================
function M.getFolder(folderId_)
    ensureArchiveSchema()
    return data.archiveFolders[folderId_ or "root"]
end

function M.canAccessFolder(clearance, folderId_)
    ensureArchiveSchema()
    local fid = folderId_ or "root"
    local seen = {}
    while fid do
        if seen[fid] then return false end
        seen[fid] = true
        local folder = data.archiveFolders[fid]
        if not folder then return false end
        if clearance > (folder.minClearance or 5) then return false end
        fid = folder.parent
    end
    return true
end

function M.addFolder(parentId, name, minClearance, author)
    ensureArchiveSchema()
    parentId = parentId or "root"
    if not data.archiveFolders[parentId] then return nil, "parent_not_found" end
    if not name or name == "" then return nil, "missing_name" end
    local base = folderId(parentId, name)
    local id = base
    local n = 2
    while data.archiveFolders[id] do
        id = base.."_"..n
        n = n + 1
    end
    data.archiveFolders[id] = {
        id = id,
        name = name,
        parent = parentId,
        minClearance = minClearance or 5,
        created = os.epoch("utc"),
        author = author or "admin",
    }
    M.save()
    return id
end

function M.deleteFolder(folderId_)
    ensureArchiveSchema()
    if not folderId_ or folderId_ == "root" then return false, "cannot_delete_root" end
    if not data.archiveFolders[folderId_] then return false, "folder_not_found" end
    for _, f in pairs(data.archiveFolders) do
        if f.parent == folderId_ then return false, "folder_not_empty" end
    end
    for _, doc in pairs(data.documents) do
        if doc.folderId == folderId_ then return false, "folder_not_empty" end
    end
    data.archiveFolders[folderId_] = nil
    M.save()
    return true
end

function M.listArchiveChildren(folderId_, clearance)
    ensureArchiveSchema()
    local fid = folderId_ or "root"
    local folder = data.archiveFolders[fid]
    if not folder then return nil, "folder_not_found" end
    if not M.canAccessFolder(clearance, fid) then return nil, "folder_restricted" end

    local folders, docs = {}, {}
    for id, f in pairs(data.archiveFolders) do
        if f.parent == fid then
            folders[#folders+1] = {
                id = id,
                name = f.name,
                minClearance = f.minClearance or 5,
                locked = clearance > (f.minClearance or 5),
            }
        end
    end
    table.sort(folders, function(a, b) return a.name:lower() < b.name:lower() end)

    for id, doc in pairs(data.documents) do
        if doc.folderId == fid then
            docs[#docs+1] = {
                id = id,
                title = doc.title,
                folderId = doc.folderId,
                minClearance = doc.minClearance or 5,
                author = doc.author,
                created = doc.created,
                locked = clearance > (doc.minClearance or 5),
            }
        end
    end
    table.sort(docs, function(a, b) return a.title:lower() < b.title:lower() end)

    return {
        folder = {
            id = folder.id,
            name = folder.name,
            parent = folder.parent,
            minClearance = folder.minClearance or 5,
        },
        folders = folders,
        documents = docs,
    }
end

function M.getArchivePath(folderId_)
    ensureArchiveSchema()
    local path = {}
    local fid = folderId_ or "root"
    local seen = {}
    while fid do
        if seen[fid] then break end
        seen[fid] = true
        local f = data.archiveFolders[fid]
        if not f then break end
        table.insert(path, 1, {id=f.id, name=f.name, minClearance=f.minClearance or 5})
        fid = f.parent
    end
    return path
end

function M.addDocument(id, title, folder, minClearance, body, author)
    ensureArchiveSchema()
    local folderId_ = folder or "root"
    if not data.archiveFolders[folderId_] then
        folderId_ = folderId("root", folder)
        if not data.archiveFolders[folderId_] then
            data.archiveFolders[folderId_] = {
                id = folderId_,
                name = folder or "General",
                parent = "root",
                minClearance = 5,
                created = os.epoch("utc"),
                author = author or "admin",
            }
        end
    end
    data.documents[id] = {
        id = id, title = title, folderId = folderId_, folder = folderId_,
        minClearance = minClearance or 5, body = body, author = author,
        created = os.epoch("utc"),
    }
    M.save()
end

function M.deleteDocument(id)
    ensureArchiveSchema()
    if not data.documents[id] then return false, "not_found" end
    data.documents[id] = nil
    M.save()
    return true
end

function M.listDocuments(clearance)
    ensureArchiveSchema()
    local out = {}
    for id, doc in pairs(data.documents) do
        local folderOk = M.canAccessFolder(clearance, doc.folderId or "root")
        out[#out+1] = {
            id=id, title=doc.title, folder=doc.folder, folderId=doc.folderId,
            minClearance=doc.minClearance, locked = not folderOk or clearance > doc.minClearance,
        }
    end
    return out
end

function M.getDocument(id, clearance)
    ensureArchiveSchema()
    local d = data.documents[id]
    if not d then return nil, "not_found" end
    if not M.canAccessFolder(clearance, d.folderId or "root") then return nil, "folder_restricted" end
    if clearance > d.minClearance then return nil, "insufficient_clearance" end
    return d
end

-- ============================================================
-- Passcodes
-- ============================================================
function M.checkPasscode(name, code)
    return data.passcodes[name] == code
end

function M.setPasscode(name, code)
    data.passcodes[name] = code
    M.save()
end

-- ============================================================
-- Logs (append-only, with rotation)
-- ============================================================
function M.log(category, message, meta)
    local line = textutils.serialize({
        ts = os.epoch("utc"),
        category = category,
        message = message,
        meta = meta or {},
    }, {compact=true})
    local mode = fs.exists(M.LOG_PATH) and "a" or "w"
    local f = fs.open(M.LOG_PATH, mode)
    f.writeLine(line)
    f.close()
end

function M.readLog(n)
    if not fs.exists(M.LOG_PATH) then return {} end
    local f = fs.open(M.LOG_PATH, "r")
    local lines = {}
    while true do
        local l = f.readLine()
        if not l then break end
        lines[#lines+1] = l
    end
    f.close()
    n = n or 50
    local out = {}
    for i = math.max(1, #lines - n + 1), #lines do
        out[#out+1] = textutils.unserialize(lines[i])
    end
    return out
end

-- ============================================================
-- Pending terminals (auto-discovery queue)
-- ============================================================
function M.addPending(computerId, termType, hostname)
    data.pending[computerId] = {
        type = termType,
        requested_at = os.epoch("utc"),
        hostname = hostname or "?",
    }
    M.save()
end

function M.removePending(computerId)
    data.pending[computerId] = nil
    M.save()
end

function M.listPending()
    local out = {}
    for id, p in pairs(data.pending) do
        out[#out+1] = {id=id, type=p.type, hostname=p.hostname, requested_at=p.requested_at}
    end
    return out
end

-- ============================================================
-- Alarm nodes
-- ============================================================
function M.addAlarm(computerId, zone)
    data.alarms[computerId] = {zone=zone}
    M.save()
end

function M.getAlarmsInZone(zone)
    local out = {}
    for id, a in pairs(data.alarms) do
        if a.zone == zone then out[#out+1] = id end
    end
    return out
end

function M.allAlarms()
    local out = {}
    for id, _ in pairs(data.alarms) do out[#out+1] = id end
    return out
end

-- ============================================================
-- Player detector nodes
-- ============================================================
function M.addDetector(computerId, zone)
    data.detectors[computerId] = {zone=zone}
    M.save()
end

function M.getDetectorZone(computerId)
    local d = data.detectors[computerId]
    return d and d.zone or nil
end

-- ============================================================
-- Zone occupancy (updated by detector reports)
-- ============================================================
function M.updateZoneOccupants(zone, playerList)
    if data.zones[zone] then
        data.zones[zone].occupants = playerList
        -- don't save here; occupancy changes too often. Save periodically elsewhere.
    end
end

function M.getZoneOccupants(zone)
    return data.zones[zone] and data.zones[zone].occupants or {}
end

-- ============================================================
-- Breaches
-- ============================================================
function M.declareBreach(scpId, zone, declaredBy)
    data.breaches[scpId] = {
        scpId = scpId, zone = zone,
        declared_at = os.epoch("utc"),
        declared_by = declaredBy,
        active = true,
    }
    M.save()
end

function M.endBreach(scpId)
    if data.breaches[scpId] then
        data.breaches[scpId].active = false
        M.save()
        return true
    end
    return false
end

function M.activeBreaches()
    local out = {}
    for id, b in pairs(data.breaches) do
        if b.active then out[#out+1] = b end
    end
    return out
end

-- ============================================================
-- Contained entities
-- ============================================================
function M.addEntity(entityId, fields)
    data.entities[entityId] = {
        entityId     = entityId,
        name         = fields.name or "Unknown",
        class        = fields.class or "Euclid",
        zone         = fields.zone or "HCZ",
        status       = fields.status or "contained",
        threat       = fields.threat or 3,
        description  = fields.description or "",
        procedures   = fields.procedures or "",
        minClearance = fields.minClearance or 4,
        last_inspection = os.epoch("utc"),
    }
    M.save()
end

function M.updateEntity(entityId, fields)
    local e = data.entities[entityId]
    if not e then return false end
    for k, v in pairs(fields) do
        if e[k] ~= nil or k == "status" or k == "description" or k == "procedures" or k == "threat" then
            e[k] = v
        end
    end
    M.save()
    return true
end

function M.setEntityStatus(entityId, status)
    if data.entities[entityId] then
        data.entities[entityId].status = status
        M.save()
        return true
    end
    return false
end

function M.deleteEntity(entityId)
    if data.entities[entityId] then
        data.entities[entityId] = nil
        -- also end any active breach for this entity
        if data.breaches[entityId] then data.breaches[entityId] = nil end
        -- unlink any chamber
        for cid, c in pairs(data.chambers) do
            if c.entityId == entityId then c.entityId = nil end
        end
        M.save()
        return true
    end
    return false
end

function M.getEntity(entityId)
    return data.entities[entityId]
end

function M.listEntities()
    local out = {}
    for id, e in pairs(data.entities) do
        out[#out+1] = {
            entityId=e.entityId, name=e.name, class=e.class,
            zone=e.zone, status=e.status, threat=e.threat,
            minClearance=e.minClearance,
        }
    end
    table.sort(out, function(a,b) return a.entityId < b.entityId end)
    return out
end

-- ============================================================
-- Chamber terminals
-- ============================================================
function M.addChamber(computerId, entityId, zone)
    data.chambers[computerId] = {entityId=entityId, zone=zone}
    M.save()
end

function M.getChamber(computerId)
    return data.chambers[computerId]
end

function M.getChamberByEntity(entityId)
    for cid, c in pairs(data.chambers) do
        if c.entityId == entityId then return cid, c end
    end
    return nil
end

function M.listChambers()
    local out = {}
    for cid, c in pairs(data.chambers) do
        out[#out+1] = {computerId=cid, entityId=c.entityId, zone=c.zone}
    end
    return out
end

-- ============================================================
-- Action terminals (scattered throughout facility)
-- actions[computerId] = {zone, label}
-- ============================================================
data.actions = data.actions or {}

function M.addActionTerminal(computerId, zone, label)
    data.actions[computerId] = {zone=zone, label=label or ("action-"..computerId)}
    M.save()
end

function M.getActionTerminal(computerId)
    return data.actions[computerId]
end

function M.listActionTerminals()
    local out = {}
    for cid, a in pairs(data.actions) do
        out[#out+1] = {computerId=cid, zone=a.zone, label=a.label}
    end
    return out
end

-- ============================================================
-- describeTerminal: look up what a computer ID represents.
-- Used to enrich log entries with human-readable context.
-- Returns {type="door"|"chamber"|..., name=..., zone=...} or nil.
-- ============================================================
function M.describeTerminal(computerId)
    for name, d in pairs(data.doors) do
        if d.terminalId == computerId then
            return {type="door", name=name, zone=d.zone}
        end
    end
    if data.chambers[computerId] then
        local c = data.chambers[computerId]
        return {type="chamber", name=c.entityId or "unassigned", zone=c.zone}
    end
    if data.alarms[computerId] then
        return {type="alarm", name="alarm-"..computerId, zone=data.alarms[computerId].zone}
    end
    if data.detectors[computerId] then
        return {type="detector", name="detector-"..computerId, zone=data.detectors[computerId].zone}
    end
    if data.actions[computerId] then
        local a = data.actions[computerId]
        return {type="action", name=a.label, zone=a.zone}
    end
    return nil
end

--- Log with automatic terminal enrichment. If fromComputerId is given,
--- annotates the meta with terminal details looked up from the registry.
function M.logFrom(category, message, fromComputerId, extra)
    local meta = extra or {}
    meta.from = fromComputerId
    if fromComputerId then
        local info = M.describeTerminal(fromComputerId)
        if info then
            meta.terminal_type = info.type
            meta.terminal_name = info.name
            meta.zone = info.zone
        end
    end
    M.log(category, message, meta)
end

return M

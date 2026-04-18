-- install.lua (GitHub edition)
-- CTN Facility System installer.
-- Downloads files from a GitHub repository.
--
-- HOW TO USE:
-- 1. Edit the GITHUB block below with your username, repo, and branch.
-- 2. Upload this installer to pastebin ONCE. Note its paste ID.
--    (Only the installer needs pastebin. Everything else comes from GitHub.)
-- 3. On each CTN computer:
--        pastebin get <installerID> install
--        install <role>
--    Roles: mainframe, door, issuer, radmin
--
-- TO UPDATE a computer later (after pushing changes to GitHub):
--        install update
--    (re-runs the installer for whatever role this computer was set up as,
--     if you saved it; otherwise just run install <role> again.)

-- ============================================================
-- EDIT THESE
-- ============================================================
local GITHUB = {
    user   = "YOUR_USERNAME_HERE",
    repo   = "ctn-facility",
    branch = "main",
}
-- ============================================================

local function rawUrl(path)
    return string.format("https://raw.githubusercontent.com/%s/%s/%s/%s",
        GITHUB.user, GITHUB.repo, GITHUB.branch, path)
end

-- File manifest: source path in repo -> destination on computer
-- (Role-specific; see ROLES below.)
local LIB = {
    {src="lib/ctnproto.lua",  dest="/lib/ctnproto.lua"},
    {src="lib/ctnui.lua",     dest="/lib/ctnui.lua"},
    {src="lib/ctnconfig.lua", dest="/lib/ctnconfig.lua"},
    {src="lib/ctngpu.lua",    dest="/lib/ctngpu.lua"},
}

local function role(main)
    local t = {}
    for _, e in ipairs(LIB) do t[#t+1] = e end
    for _, e in ipairs(main) do t[#t+1] = e end
    return t
end

local ROLES = {
    mainframe = role({
        {src="mainframe/db.lua",        dest="/mainframe/db.lua"},
        {src="mainframe/mainframe.lua", dest="/startup.lua"},
        {src="mainframe/admin.lua",     dest="/admin.lua"},
    }),
    door      = role({{src="terminals/door.lua",     dest="/startup.lua"}}),
    issuer    = role({{src="terminals/issuer.lua",   dest="/startup.lua"}}),
    radmin    = role({{src="terminals/radmin.lua",   dest="/startup.lua"}}),
    control   = role({{src="terminals/control.lua",  dest="/startup.lua"}}),
    chamber   = role({{src="terminals/chamber.lua",  dest="/startup.lua"}}),
    siren     = role({{src="terminals/siren.lua",    dest="/startup.lua"}}),
    detector  = role({{src="terminals/detector.lua", dest="/startup.lua"}}),
    archive   = role({{src="terminals/archive.lua",  dest="/startup.lua"}}),
    action    = role({{src="terminals/action.lua",   dest="/startup.lua"}}),
}

-- ============================================================
-- Download helpers
-- ============================================================
local function download(url, dest)
    local dir = fs.getDir(dest)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end

    local handle, err = http.get(url)
    if not handle then
        return false, "HTTP error: "..tostring(err)
    end
    local body = handle.readAll()
    handle.close()

    if fs.exists(dest) then fs.delete(dest) end
    local f = fs.open(dest, "w")
    f.write(body)
    f.close()
    return true
end

-- Remember which role this computer was installed as, so `install update` works.
local ROLE_FILE = "/.ctn_role"
local function saveRole(role)
    local f = fs.open(ROLE_FILE, "w"); f.write(role); f.close()
end
local function loadRole()
    if not fs.exists(ROLE_FILE) then return nil end
    local f = fs.open(ROLE_FILE, "r"); local r = f.readAll(); f.close()
    return r:gsub("%s+$", "")
end

-- ============================================================
-- Main
-- ============================================================
local args = {...}
local role = args[1]

if role == "update" then
    role = loadRole()
    if not role then
        print("This computer has no saved role.")
        print("Run: install <role>  (mainframe/door/issuer/radmin)")
        return
    end
    print("Updating as: "..role)
elseif not role or not ROLES[role] then
    print("Usage: install <role>")
    print("       install update   (re-install using saved role)")
    print("Roles:")
    for r in pairs(ROLES) do print("  - "..r) end
    return
end

if not http then
    print("HTTP API disabled. Enable it in the CC:T config.")
    return
end

if GITHUB.user == "YOUR_USERNAME_HERE" then
    print("Edit install.lua first! Set GITHUB.user / GITHUB.repo / GITHUB.branch.")
    return
end

print("CTN Installer")
print("Source: "..GITHUB.user.."/"..GITHUB.repo.." ("..GITHUB.branch..")")
print("Role:   "..role)
print("Computer ID: "..os.getComputerID())
print("")

local failed = 0
for _, entry in ipairs(ROLES[role]) do
    write("  "..entry.src.." -> "..entry.dest.." ... ")
    local ok, err = download(rawUrl(entry.src), entry.dest)
    if ok then
        print("OK")
    else
        print("FAIL ("..tostring(err)..")")
        failed = failed + 1
    end
end

if failed > 0 then
    print("")
    print(failed.." file(s) failed. Check GitHub settings and network.")
    return
end

saveRole(role)

print("")
print("=== INSTALL COMPLETE ===")
print("")
print("Next steps:")
print("1. Attach a wireless modem.")
print("2. Install the shared secret: edit .ctn_secret")
print("3. Reboot.")
print("4. On first boot, this terminal will ask for its config.")
print("")
if role == "mainframe" then
    print("After reboot, the mainframe runs automatically.")
    print("Ctrl+T then type 'admin' for local admin console.")
elseif role == "door" then
    print("Also needs: disk drive + redstone output to the door.")
    print("A new door will announce itself; approve it via a radmin")
    print("terminal or the local admin console on the mainframe.")
elseif role == "issuer" then
    print("Also needs: disk drive.")
elseif role == "chamber" then
    print("Recommended: advanced monitor (any size array).")
    print("Optional: disk drive (for procedure viewing), redstone output")
    print("(for emergency lighting).")
    print("Register the chamber via a radmin terminal, linking it to an")
    print("entity ID you've already added.")
elseif role == "archive" then
    print("Also needs: disk drive.")
elseif role == "control" then
    print("Recommended: large advanced monitor array (3x2 or 4x3).")
    print("You need the 'control' passcode set on the mainframe first.")
elseif role == "detector" then
    print("Also needs: Advanced Peripherals Player Detector.")
elseif role == "siren" then
    print("Also needs: speaker peripheral.")
    print("Optional: redstone output wired to in-world lights or")
    print("mechanical sirens.")
    print("Plays different Minecraft sounds for breach/lockdown/panic/etc.")
elseif role == "action" then
    print("Also needs: disk drive. Optional: advanced monitor (touchable)")
    print("and a panic button wired to a redstone input side.")
    print("This terminal is card-authenticated: card holder clearance")
    print("determines what actions are shown.")
elseif role == "radmin" then
    print("You need the 'admin' passcode set on the mainframe first.")
end
print("")
print("To update this computer later: install update")

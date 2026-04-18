=====================================================
  C.T.N FACILITY COMPUTER SYSTEM
  Containment Division - Computer Network
=====================================================

A complete SCP-style facility computer system for
ComputerCraft: Tweaked + Advanced Peripherals.

Features
--------
- ID card system using floppy disks
- Clearance-gated door access (L0 Overseer to L5 Guest)
- Department-based permissions (Security, Research, MTF, ...)
- Special flags (maintenance, MTF units, per-SCP access)
- Containment chamber terminals per entity
- Breach system with facility-wide alerts + chamber flashing
- Zone + facility-wide lockdowns
- Alarm/siren nodes with redstone pulse output
- Player detection via Advanced Peripherals
- Hierarchical document archive with clearance-gated folders and records
- Archive terminals support mouse input, monitor/DirectGPU display, and printing
- Central mainframe with live status monitor
- Multiple remote admin terminals (no more single point of admin)
- Control room with dashboard + breach/lockdown controls
- Auto-discovery: new terminals announce to the mainframe for approval
- First-run wizards on every terminal (no editing code)
- HMAC-SHA256 signed rednet protocol with replay protection
- Security audit log of every action

Roles / terminal types
----------------------
- mainframe : central server, database, auth
- door      : ID-card scanner at each door (lockdown-aware idle)
- issuer    : passcode-gated card issuance
- radmin    : remote admin console (does everything locally-managed
              admin does, over the network)
- control   : control room dashboard + facility commands
              (DirectGPU-powered when available, falls back to monitor/term)
- chamber   : containment chamber terminal (per SCP, flashes during breach)
- siren     : speaker-based alarm node. Plays different Minecraft sounds
              for breach, lockdown, panic, security, etc. Optional
              redstone out for in-world lights.
- detector  : player detector reporting zone occupancy
- archive   : hierarchical document archive browser. Optional monitor/
              DirectGPU display and printer output.
- action    : facility-wide emergency response terminal. Card-authenticated.
              Clearance determines available actions. Clickable UI.
              Optional panic button via redstone input.


GETTING IT INTO MINECRAFT
=========================

RECOMMENDED WORKFLOW: GitHub
----------------------------
1. Create a GitHub repo and upload every file in this project,
   preserving the folder structure (lib/, mainframe/, terminals/).
2. Open install.lua and fill in your GitHub details:
       local GITHUB = {
           user   = "YourGitHubUsername",
           repo   = "ctn-facility",
           branch = "main",
       }
3. Upload install.lua to pastebin as a single paste. Note the paste ID.
4. That's it. From now on, to update ANY computer:
       install update

FIRST-TIME DEPLOYMENT
---------------------

1. Generate a shared secret.
   Any random string of 32+ characters. Write it down; you'll
   type it into every CTN computer.

2. Set up the MAINFRAME first.
   - Advanced Computer + wireless modem.
   - Run:
         pastebin get <installID> install
         install mainframe
   - Install secret:
         edit .ctn_secret    (paste secret, save, exit)
   - Reboot.
   - First boot will run setup wizard (answer prompts).
   - Mainframe goes online; note its computer ID.
   - Ctrl+T, then: admin
     Go to Set passcode and set the issuer, control, and admin
     passcodes. Then reboot so the mainframe comes back online.

3. For every other terminal (door, issuer, control, chamber,
   alarm, detector, archive, radmin):
   - Advanced Computer + wireless modem + role-specific peripherals.
   - Run:
         pastebin get <installID> install
         install <role>
   - Install the SAME secret:
         edit .ctn_secret
   - Reboot.
   - First boot asks a few config questions (mainframe ID,
     redstone side, etc).
   - Terminal announces itself to the mainframe.
   - On a radmin terminal, choose "Approve pending" to approve
     it (link a door to a zone + clearance, a chamber to an entity, etc).

4. Issue your first ID card.
   - Insert a blank floppy into the issuer's disk drive.
   - Enter the issuer passcode.
   - Fill in the cardholder's username, clearance, department.
   - Test the card at a door.


PERIPHERALS PER ROLE
====================

mainframe: wireless modem.   Optional: advanced monitor (status display).
door:      wireless modem + disk drive + redstone output to the door.
           Optional: advanced monitor (external display), Redstone Integrator.
issuer:    wireless modem + disk drive.
radmin:    wireless modem only.
control:   wireless modem. Optional: LARGE advanced monitor (3x2+).
chamber:   wireless modem. Optional: advanced monitor, disk drive
           (procedure viewing), redstone output (emergency light).
alarm:     wireless modem + redstone output (wired to sirens/lights).
detector:  wireless modem + Advanced Peripherals Player Detector.
archive:   wireless modem + disk drive. Optional: advanced monitor or
           DirectGPU display, printer.


CLEARANCE LEVELS
================
L0 Overseer
L1 Ethical Board
L2 Directors
L3 Captains / Research Directors
L4 Security / Researchers
L5 Guests / Janitors

Lower number = higher clearance. A door with minClearance=3 can be
opened by L0/L1/L2/L3, not by L4/L5.


ENTITY SYSTEM
=============
Contained entities (e.g. CTN-001) live in the mainframe database.
Each has:
- ID           (you set it: CTN-001, CTN-173, etc)
- Name / designation
- Object class (Safe, Euclid, Keter, Thaumiel, Apollyon, Neutralized)
- Zone (Office/Security/Testing/LCZ/HCZ)
- Status (contained / breached / testing / maintenance / ...)
- Threat level (1-5)
- Public description (shown on chamber terminal always)
- Containment procedures (shown only to cards with sufficient clearance)
- minClearance for procedures

A chamber terminal is mounted on the front of the entity's cell and
displays its info. Researchers insert their ID card to view procedures.

When the control room declares a breach on an entity, the chamber
flashes red and can drive redstone for emergency lighting.


SECURITY MODEL
==============
Every rednet message is signed with HMAC-SHA256 using the shared secret.
Messages include nonces and timestamps; old and duplicate messages are
rejected.

Attacks that still work (by design - "hard but possible"):
- Physically steal a valid ID floppy from another player
- Break into the mainframe room and read /.ctn_secret
- Break into a terminal and read its config
- Social-engineer an admin to issue you a better card
- Find real bugs in the code

Defense layers:
- Admin passcode protects remote admin commands
- Control passcode protects lockdown/breach commands
- Issuer passcode protects card issuance
- Every failed auth logged with timestamp + source
- Cards can be revoked instantly
- Personnel can be suspended without revoking cards


ARCHIVE SYSTEM
==============
The archive is a browsable folder tree rooted at:

    Departments

Admins can create folders and text documents anywhere in the tree from
the local admin console or any remote admin terminal. Each folder and
document has a required clearance level. Folder restrictions inherit
downward: if a user cannot open a parent folder, they cannot open any
documents or subfolders inside it.

Archive users insert an ID card at an archive terminal. They can use
arrow keys, mouse clicks, and mouse wheel scrolling. They can see folder
names in the current folder, including restricted folders, but locked
folders and documents cannot be opened without the required clearance.
If a printer is attached, an open document can be printed with P or the
PRINT button.


TROUBLESHOOTING
===============

"MAINFRAME UNREACHABLE"
- Different secret on each computer. Re-run edit .ctn_secret;
  make sure they match byte-for-byte.
- Wrong mainframe ID in config. Delete /.ctn_config and reboot
  to re-run the wizard.
- Mainframe not online. Walk over and check.
- Wireless modems too far apart. Use Ender Modems for unlimited range.

"bad_sig" in mainframe log
- Secret mismatch, or different ctnproto.lua versions. Run
  'install update' on every computer.

Terminal shows "NOT CONFIGURED / WAITING FOR APPROVAL"
- Normal on first boot. Go to a radmin terminal and approve it.

Card works everywhere
- Too-high minClearance on doors. Lower numbers are more restricted;
  5 lets everyone in.

Door won't close
- Door's OPEN_DURATION may be too long. Delete /.ctn_config and
  reboot to re-run wizard, or edit it directly with textutils.


UPDATING
========
After pushing code changes to GitHub:
    install update
    reboot
on each affected computer.


FILE LAYOUT
===========
lib/ctnproto.lua    - Signed rednet protocol (on every computer)
lib/ctnui.lua       - Yellow/black UI library (on every computer)
lib/ctnconfig.lua   - First-run wizard (on every terminal)

mainframe/mainframe.lua - Main server (runs as /startup.lua)
mainframe/db.lua        - Database module
mainframe/admin.lua     - Local admin CLI (runs as /admin.lua)

terminals/door.lua      - Door scanner
terminals/issuer.lua    - Card issuer
terminals/radmin.lua    - Remote admin console
terminals/control.lua   - Control room dashboard
terminals/chamber.lua   - Containment chamber terminal
terminals/alarm.lua     - Siren/alarm node
terminals/detector.lua  - Player detector
terminals/archive.lua   - Hierarchical document archive browser

install.lua             - GitHub-based installer


C.T.N - CONTAINMENT DIVISION

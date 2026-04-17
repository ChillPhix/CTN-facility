-- secret-install.lua
-- Run once on every CTN computer to install the shared HMAC secret.
-- After running, DELETE THIS FILE or overwrite it, and never print the secret anywhere.

term.clear()
term.setCursorPos(1,1)
print("=== CTN Secret Installer ===")
print("Enter shared secret (input hidden):")
write("> ")
local secret = read("*")

if #secret < 16 then
    print("Secret too short. Use at least 16 characters.")
    return
end

local f = fs.open("/.ctn_secret", "w")
f.write(secret)
f.close()

print("Secret installed at /.ctn_secret")
print("DELETE /secret-install.lua now for safety.")

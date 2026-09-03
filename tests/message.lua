-- run: nvim -l tests/message.lua
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path
local k = require("kappa")
local function dump(label, v)
	print(label .. ": " .. vim.inspect(v))
end

-- 1. ping passes straight through
local ping = k.parse_message("PING :tmi.twitch.tv")
dump("ping", ping)
assert(ping == "PING")

-- 2. full tags: display-name wins, color kept
local m = k.parse_message("@color=#FF0000;display-name=FooBar;mod=0 :foobar!foobar@x PRIVMSG #c :hi there")
dump("tagged", m)
assert(m.nick == "FooBar", "display-name should win over prefix nick")
assert(m.msg == "hi there")
assert(m.color == "#FF0000")

-- 3. empty tags: fall back to prefix nick, color must be nil not ""
local e = k.parse_message("@color=;display-name= :plainuser!plainuser@x PRIVMSG #c :yo")
dump("empty tags", e)
assert(e.nick == "plainuser", "empty display-name must fall back to prefix nick")
assert(e.msg == "yo")
assert(e.color == nil, "empty color must become nil, got " .. tostring(e.color))

-- 4. untagged line (before CAP ACK) still works
local u = k.parse_message(":olduser!olduser@x PRIVMSG #c :legacy")
dump("untagged", u)
assert(u.nick == "olduser" and u.msg == "legacy" and u.color == nil)

-- 5. server noise is ignored
local n = k.parse_message(":tmi.twitch.tv CAP * ACK :twitch.tv/tags")
dump("cap ack", n)
assert(n == nil)

print("ok")

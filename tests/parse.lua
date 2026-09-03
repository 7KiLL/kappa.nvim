-- run: nvim -l tests/parse.lua
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path
local k = require("kappa")
-- dump(label, ...) prints any values readably. vim.inspect turns tables into text.
local function dump(label, ...)
	print(label .. ": " .. vim.inspect({ ... }))
end
assert(k.parse("PING :tmi.twitch.tv") == "PING")
local nick, msg = k.parse(":foo!foo@foo.tmi.twitch.tv PRIVMSG #bar :hello world")
assert(nick == "foo" and msg == "hello world", nick .. "|" .. tostring(msg))
assert(k.parse(":tmi.twitch.tv 001 justinfan1 :Welcome, GLHF!") == nil)

-- tag prefix
local tags, rest = k.parse_tags("@color=#FF0000;display-name=Foo;mod=0 :foo!foo@x PRIVMSG #c :hi")
dump("tagged", tags, rest)
assert(tags.color == "#FF0000", tostring(tags.color))
assert(tags["display-name"] == "Foo")
assert(rest == ":foo!foo@x PRIVMSG #c :hi", rest)
local t2, r2 = k.parse_tags("PING :tmi.twitch.tv")
dump("ping", t2, r2)
assert(next(t2) == nil and r2 == "PING :tmi.twitch.tv")
local t3 = k.parse_tags("@color=;display-name= :foo!foo@x PRIVMSG #c :hi")
dump("empty", t3)
assert(t3.color == "" and t3["display-name"] == "") -- empty values must not crash
print("ok")

-- run: nvim -l tests/parse.lua
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path
local k = require("kappa")
assert(k.parse("PING :tmi.twitch.tv") == "PING")
local nick, msg = k.parse(":foo!foo@foo.tmi.twitch.tv PRIVMSG #bar :hello world")
assert(nick == "foo" and msg == "hello world", nick .. "|" .. tostring(msg))
assert(k.parse(":tmi.twitch.tv 001 justinfan1 :Welcome, GLHF!") == nil)
print("ok")

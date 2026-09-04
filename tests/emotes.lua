-- run: nvim -l tests/emotes.lua
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path
local em = require("kappa.emotes")
local function dump(label, v)
	print(label .. ": " .. vim.inspect(v))
end

-- 1. twitch tag, two emotes, one repeated
local msg = "Kappa hi Kappa PogChamp"
local t = em.twitch("25:0-4,9-13/305954156:15-22", msg)
dump("twitch", t)
assert(#t == 3)
assert(t[1].name == "Kappa" and t[1].s == 0 and t[1].e == 5)
assert(t[3].name == "PogChamp" and t[3].id == "305954156")
assert(t[3].url:find("305954156", 1, true))

-- 2. codepoint → byte: multibyte char before the emote
local u = "é Kappa"
local tu = em.twitch("25:2-6", u)
dump("utf8", tu)
assert(tu[1].name == "Kappa", tu[1].name)
assert(tu[1].s == 3 and tu[1].e == 8, tu[1].s .. "-" .. tu[1].e)

-- 3. empty / missing tag
assert(#em.twitch("", msg) == 0 and #em.twitch(nil, msg) == 0)

-- 4. 7tv: whole words only, byte offsets, url
local set = { KEKW = "abc", OMEGALUL = "def" }
local s = em.seventv("KEKW lol KEKWait OMEGALUL", set)
dump("7tv", s)
assert(#s == 2, "expected 2 got " .. #s)
assert(s[1].name == "KEKW" and s[1].s == 0 and s[1].e == 4)
assert(s[2].name == "OMEGALUL" and s[2].id == "def" and s[2].s == 17)
assert(s[2].url == "https://cdn.7tv.app/emote/def/2x.webp", s[2].url)

-- 5. merged, sorted
local f = em.find("KEKW Kappa", { emotes = "25:5-9" }, set)
dump("find", f)
assert(#f == 2 and f[1].name == "KEKW" and f[2].name == "Kappa")

print("ok")

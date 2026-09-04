local M = {}

---@class kappa.Emote
---@field id string    provider emote id
---@field name string  the text as it appears in the message
---@field s integer    0-based byte offset of the first char
---@field e integer    0-based byte offset after the last char (exclusive, extmark convention)
---@field url string   image url

---@alias kappa.EmoteSet table<string, string>  emote name → image url (7TV and BTTV)

--- Twitch "emotes" tag: "25:0-4,12-16/1902:6-10"
--- id:start-end pairs, offsets are unicode codepoints, end inclusive.
---@param tag string|nil  raw value of the `emotes` IRC tag
---@param msg string      message text the offsets refer to
---@return kappa.Emote[]
function M.twitch(tag, msg)
	local out = {}
	if not tag or tag == "" then
		return out
	end
	for _, emote in ipairs(vim.split(tag, "/")) do -- 25:0-4,12-16
		local id, ranges = unpack(vim.split(emote, ":")) -- 25 and 0-4,12-16
		for _, range in ipairs(vim.split(ranges, ",")) do -- 0-4 and 12-16
			local s, e = unpack(vim.split(range, "-")) -- 0 and 4; 12 and 16
			-- Twitch counts codepoints, extmarks want bytes. "utf-32" = one unit per codepoint.
			local bs = vim.str_byteindex(msg, "utf-32", tonumber(s))
			local be = vim.str_byteindex(msg, "utf-32", tonumber(e) + 1)
			out[#out + 1] = {
				id = id,
				name = msg:sub(bs + 1, be),
				s = bs,
				e = be,
				url = ("https://static-cdn.jtvnw.net/emoticons/v2/%s/default/dark/2.0"):format(id),
			}
		end
	end
	return out
end

--- Third-party emotes (7TV, BTTV) have no tag; match whole whitespace-separated words.
---@param msg string
---@param set kappa.EmoteSet
---@return kappa.Emote[]
function M.seventv(msg, set)
	--- @type kappa.Emote[]
	local out = {}
	for s, word, e in msg:gmatch("()(%S+)()") do
		if set[word] then
			table.insert(out, {
				id = set[word], -- url doubles as id, unique per emote
				name = word,
				s = s - 1,
				e = e - 1,
				url = set[word],
			})
		end
	end

	return out
end

--- Merge both sources, sorted by start offset.
---@param msg string
---@param tags kappa.Tags|nil
---@param set kappa.EmoteSet|nil
---@return kappa.Emote[]
function M.find(msg, tags, set)
	local all = M.twitch(tags and tags.emotes, msg)
	for _, e in ipairs(M.seventv(msg, set or {})) do
		all[#all + 1] = e
	end
	table.sort(all, function(a, b)
		return a.s < b.s
	end)
	return all
end

--- Third-party emote set per Twitch room-id, fetched once: 7TV + BTTV, channel + global.
---@type table<string, kappa.EmoteSet>
M.sets = {}

-- Each source: url (with %s for room-id or none for global), how to dig the list out
-- of the JSON, and how to turn one entry into name → image url.
local sources = {
	{
		url = "https://7tv.io/v3/users/twitch/%s",
		list = function(d) return d.emote_set and d.emote_set.emotes end,
		name = function(e) return e.name, "https://cdn.7tv.app/emote/" .. e.id .. "/2x.webp" end,
	},
	{
		url = "https://7tv.io/v3/emote-sets/global",
		list = function(d) return d.emotes end,
		name = function(e) return e.name, "https://cdn.7tv.app/emote/" .. e.id .. "/2x.webp" end,
	},
	{
		url = "https://api.betterttv.net/3/cached/users/twitch/%s",
		list = function(d) return vim.list_extend(d.channelEmotes or {}, d.sharedEmotes or {}) end,
		name = function(e) return e.code, "https://cdn.betterttv.net/emote/" .. e.id .. "/2x.webp" end,
	},
	{
		url = "https://api.betterttv.net/3/cached/emotes/global",
		list = function(d) return d end,
		name = function(e) return e.code, "https://cdn.betterttv.net/emote/" .. e.id .. "/2x.webp" end,
	},
}

---@param url string
---@param cb fun(emotes: { name: string, id: string }[])
local function get(url, cb)
	-- ponytail: 7tv.io is flaky, let curl retry; no in-session refresh, :Kappa again reuses the set
	local cmd = { "curl", "-sf", "--retry", "3", "--retry-all-errors", "--retry-delay", "1", "--max-time", "30", url }
	vim.system(cmd, { text = true }, function(res)
		if res.code ~= 0 then
			return
		end
		local ok, data = pcall(vim.json.decode, res.stdout)
		if ok and data then
			cb(data)
		end
	end)
end

--- Kick off a fetch for room_id if not already done. Fills M.sets[room_id] asynchronously.
---@param room_id string|nil  value of the `room-id` IRC tag
function M.fetch(room_id)
	if not room_id or M.sets[room_id] then
		return
	end
	local set = {}
	M.sets[room_id] = set -- ponytail: placeholder stops duplicate fetches; no retry on failure
	-- ponytail: all four fetched in parallel, first to land wins a name. Order by
	-- priority (channel before global) if collisions ever matter.
	for _, src in ipairs(sources) do
		get(src.url:format(room_id), function(data)
			for _, e in ipairs(src.list(data) or {}) do
				local name, url = src.name(e)
				set[name] = set[name] or url
			end
		end)
	end
end

return M

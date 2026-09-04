local M = {}

---@class kappa.Emote
---@field id string    provider emote id
---@field name string  the text as it appears in the message
---@field s integer    0-based byte offset of the first char
---@field e integer    0-based byte offset after the last char (exclusive, extmark convention)
---@field url string   image url

---@alias kappa.EmoteSet table<string, string>  emote name → id

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

--- 7TV has no tag; match whole whitespace-separated words against the set.
--- url: https://cdn.7tv.app/emote/<id>/2x.webp
---@param msg string
---@param set kappa.EmoteSet
---@return kappa.Emote[]
function M.seventv(msg, set)
	--- @type kappa.Emote[]
	local out = {}
	for s, word, e in msg:gmatch("()(%S+)()") do
		if set[word] then
			table.insert(out, {
				id = set[word],
				name = word,
				s = s - 1,
				e = e - 1,
				url = string.format("https://cdn.7tv.app/emote/%s/2x.webp", set[word]),
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

--- 7TV emote set per Twitch room-id, fetched once.
---@type table<string, kappa.EmoteSet>
M.sets = {}

--- Kick off a fetch for room_id if not already done. Fills M.sets[room_id] asynchronously.
---@param room_id string|nil  value of the `room-id` IRC tag
function M.fetch(room_id)
	if not room_id or M.sets[room_id] then
		return
	end
	M.sets[room_id] = {} -- ponytail: placeholder stops duplicate fetches; no retry on failure
	vim.system({ "curl", "-sf", "https://7tv.io/v3/users/twitch/" .. room_id }, { text = true }, function(res)
		if res.code ~= 0 then
			return
		end
		local ok, data = pcall(vim.json.decode, res.stdout)
		if not ok or not (data.emote_set and data.emote_set.emotes) then
			return
		end
		local set = {}
		for _, e in ipairs(data.emote_set.emotes) do
			set[e.name] = e.id
		end
		M.sets[room_id] = set
	end)
end

return M

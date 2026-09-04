local M = {}

---@class kappa.Config
---@field channel string|nil   default channel for :Kappa with no argument
---@field width integer        sidebar width in columns
---@field timestamps boolean   prefix lines with HH:MM
---@field max_lines integer    oldest lines are dropped past this
---@field images boolean       render emotes as images when the terminal can (needs snacks.nvim)
---@field emote_width integer   max image width in cells, aspect kept
---@field emote_height integer  rows; 1 inline, 3+ adds virtual lines below the message (2 is clamped to 1 by snacks)
---@field nick string          anonymous justinfanNNNNN login

---@class kappa.Tags: table<string, string>
---@field color string|nil            "#RRGGBB" or ""
---@field ["display-name"] string|nil
---@field ["room-id"] string|nil
---@field emotes string|nil           "id:start-end,.../id:..."

---@class kappa.Message
---@field nick string       display-name if set, else prefix nick
---@field msg string        message text
---@field color string|nil  "#RRGGBB", never ""
---@field tags kappa.Tags   raw tags, {} for untagged lines

---@alias kappa.Mark { [1]: integer, [2]: integer, [3]: string, url?: string }  col_start, col_end (exclusive), hl group, optional image

---@class kappa.State
---@field tcp uv.uv_tcp_t|nil
---@field buf integer|nil
---@field win integer|nil
---@field images boolean|nil                    decided once in open()
---@field placements { p: snacks.image.Placement, row: integer }[]|nil  1-based rows

---@type kappa.Config
M.config = {
	channel = nil, -- default channel for :Kappa with no argument
	width = 40,
	timestamps = true,
	max_lines = 10000, -- oldest lines are dropped past this
	images = true, -- emotes as images if snacks.nvim + a kitty-graphics terminal are present
	emote_width = 2, -- max cells wide, aspect kept
	emote_height = 1, -- rows; 3+ pads virtual lines below the message, 2 is clamped to 1 by snacks
	-- ponytail: anonymous read-only login; sending needs an oauth token, add when wanted
	nick = "justinfan" .. math.random(10000, 99999),
}

local emotes = require("kappa.emotes")

---@type kappa.State
local state = { tcp = nil, buf = nil, win = nil }

-- Twitch prefixes chat lines with IRCv3 tags once we CAP REQ them:
--   @color=#0000FF;display-name=foofoo;... :foofoo!foofoo@foofoo.tmi.twitch.tv PRIVMSG #bar :hi
-- We use "color" (hex, may be empty) and "display-name" (cased nick, may be empty).

-- A namespace keeps our highlights separate from other plugins' marks.
-- Create it once, reuse it everywhere. Docs: :h nvim_create_namespace
local ns = vim.api.nvim_create_namespace("kappa")

-- One highlight group per distinct color, created lazily and remembered here
-- so we don't call nvim_set_hl 500 times for the same red.
-- Key: "#FF0000"  →  value: "FF0000" (the group name we created)
---@type table<string, string>
local hl_cache = {}

---@param opts kappa.Config|nil
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

--- Parse one IRC line. Returns nick, message for PRIVMSG; "PING" for pings; nil otherwise.
---@param line string  untagged IRC line
---@return string|nil nick  "PING" for pings
---@return string|nil msg
function M.parse(line)
	if line:find("^PING") then
		return "PING"
	end
	local nick, msg = line:match("^:([^!]+)!%S+ PRIVMSG #%S+ :(.*)$")
	if nick then
		return nick, msg
	end
end

--- Split the leading "@k=v;k=v " block off an IRC line.
---@param line string
---@return kappa.Tags tags  {} when the line has no tags
---@return string rest      the line without the tag block
function M.parse_tags(line)
	local tags = {}
	if not line:find("^@", 1) then
		return {}, line
	end

	local sb = line:find(" ", 1, true)
	local tag_str = line:sub(2, sb - 1)
	for pair in tag_str:gmatch("[^;]+") do
		local key, value = pair:match("^([^=]*)=(.*)$")

		tags[key] = value
	end

	return tags, line:sub(sb + 1 or 0)
end

--- Combine parse_tags + parse into one answer handle() can use.
--- Returns one of:
---   "PING"                                       → caller must PONG
---   { nick = "Foo", msg = "hi", color = "#FF0000" }  → a chat message (color may be nil)
---   nil                                          → anything else, ignore
--- Rules:
---   - nick is tags["display-name"] when that is a non-empty string, else the nick from the prefix
---   - color is tags.color when non-empty, else nil (NOT "" — append will test `if color`)
---   - works on untagged lines too (before CAP ACK arrives, or if Twitch NAKs)
---@param line string
---@return kappa.Message|"PING"|nil
function M.parse_message(line)
	local tags, rest = M.parse_tags(line)
	local nick, msg = M.parse(rest)
	if nick == "PING" then
		return "PING"
	end
	if not nick then
		return nil
	end

	local name = nick
	if tags["display-name"] ~= "" and tags["display-name"] ~= nil then
		name = tags["display-name"]
	end

	local color = tags.color
	if tags.color == "" then
		color = nil
	end

	return { nick = name, msg = msg, color = color, tags = tags }
end

--- Turn a hex color into a highlight group name, creating it on first use.
---   "#FF0000" → "KappaFF0000"
--- Decide once whether emotes can be drawn as images in this session.
--- Must be false when snacks.nvim is missing, the terminal lacks graphics
--- support (Snacks.image.supports_terminal), or the user turned images off.
---@return boolean
local function images_ok()
	if M.config.images == false then
		return false
	end

	local ok, snacks = pcall(require, "snacks")
	if not ok then
		return false
	end

	if snacks.image.supports_terminal() == false then
		return false
	end

	return true
end

--- Returns nil for empty/missing color so the caller can skip highlighting.
---@param color string|nil
---@return string|nil group
local function hl_for(color)
	if color == "" or color == nil then
		return nil
	end

	if hl_cache[color] then
		return hl_cache[color]
	end

	local hl_name = color:gsub("#", "")
	hl_cache[color] = hl_name
	-- handle() runs in the socket callback (fast context), API calls must be scheduled.
	-- The extmark using this group is scheduled later from append(), so it lands after.
	vim.schedule(function()
		vim.api.nvim_set_hl(0, hl_name, { fg = color })
	end)

	return hl_name
end

vim.api.nvim_set_hl(0, "KappaEmote", { link = "Special", default = true })

--- Append one line to the chat buffer and paint marks on it. Safe from any thread.
---@param line string
---@param marks kappa.Mark[]|nil  0-based bytes into `line`, end exclusive
local function append(line, marks)
	vim.schedule(function()
		if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
			return
		end
		vim.bo[state.buf].modifiable = true
		vim.api.nvim_buf_set_lines(state.buf, -1, -1, false, { line })
		-- ponytail: trim in batches (10% over), not on every message
		local n = vim.api.nvim_buf_line_count(state.buf)
		if n > M.config.max_lines * 1.1 then
			local k = n - M.config.max_lines
			vim.api.nvim_buf_set_lines(state.buf, 0, k, false, {})
			-- placements on trimmed rows die, the rest shift up
			local keep = {}
			for _, pl in ipairs(state.placements or {}) do
				if pl.row <= k then
					pl.p:close()
				else
					pl.row = pl.row - k
					keep[#keep + 1] = pl
				end
			end
			state.placements = keep
		end
		vim.bo[state.buf].modifiable = false

		local row = vim.api.nvim_buf_line_count(state.buf) - 1
		for _, mk in ipairs(marks or {}) do
			vim.api.nvim_buf_set_extmark(state.buf, ns, row, mk[1], { end_col = mk[2], hl_group = mk[3] })
			if mk.url and state.images then
				-- ponytail: image over the emote text, first frame only
				local p = Snacks.image.placement.new(state.buf, mk.url, {
					pos = { row + 1, mk[1] },
					range = { row + 1, mk[1], row + 1, mk[2] },
					inline = true,
					conceal = true,
					width = M.config.emote_width,
					height = M.config.emote_height,
				})
				table.insert(state.placements, { p = p, row = row + 1 })
			end
		end
		-- ponytail: always tail; stop following when user scrolls up if it annoys
		if state.win and vim.api.nvim_win_is_valid(state.win) then
			vim.api.nvim_win_set_cursor(state.win, { vim.api.nvim_buf_line_count(state.buf), 0 })
		end
	end)
end

---@param line string  one raw IRC line, no CRLF
local function handle(line)
	local m = M.parse_message(line)

	if m == "PING" then
		state.tcp:write("PONG :tmi.twitch.tv\r\n")
	elseif m then
		local ts = M.config.timestamps and os.date("%H:%M ") or ""
		local marks = {}
		local group = hl_for(m.color)
		if group then
			marks[#marks + 1] = { #ts, #ts + #m.nick, group }
		end
		emotes.fetch(m.tags["room-id"])
		local off = #ts + #m.nick + 2 -- ": "
		for _, e in ipairs(emotes.find(m.msg, m.tags, emotes.sets[m.tags["room-id"]])) do
			marks[#marks + 1] = { off + e.s, off + e.e, "KappaEmote", url = e.url }
		end
		append(("%s%s: %s"):format(ts, m.nick, m.msg), marks)
	end
end

---@param channel string  lowercase, no "#"
local function connect(channel)
	local uv = vim.uv or vim.loop
	uv.getaddrinfo("irc.chat.twitch.tv", nil, { family = "inet", socktype = "stream" }, function(err, res)
		if err or not (res and res[1]) then
			return append("! dns failed: " .. tostring(err))
		end
		local tcp = uv.new_tcp()
		state.tcp = tcp
		tcp:connect(res[1].addr, 6667, function(cerr)
			if cerr then
				return append("! connect failed: " .. cerr)
			end
			tcp:write("CAP REQ :twitch.tv/tags\r\n")
			tcp:write(("NICK %s\r\nJOIN #%s\r\n"):format(M.config.nick, channel))
			append("* joined #" .. channel)
			local rest = ""
			tcp:read_start(function(rerr, chunk)
				if rerr or not chunk then
					return append("! disconnected")
				end
				rest = rest .. chunk
				while true do
					local i = rest:find("\r\n", 1, true)
					if not i then
						break
					end
					handle(rest:sub(1, i - 1))
					rest = rest:sub(i + 2)
				end
			end)
		end)
	end)
end

--- Reset state and close the socket. Returns the old state so close() can tear down the UI.
---@return kappa.State
local function disconnect()
	local s = state
	state = { tcp = nil, buf = nil, win = nil }
	if s.tcp and not s.tcp:is_closing() then
		s.tcp:close()
	end
	return s
end

function M.close()
	local s = disconnect()
	if s.win and vim.api.nvim_win_is_valid(s.win) then
		vim.api.nvim_win_close(s.win, true)
	end
	if s.buf and vim.api.nvim_buf_is_valid(s.buf) then
		vim.api.nvim_buf_delete(s.buf, { force = true })
	end
end

---@param channel string|nil  falls back to config.channel
function M.open(channel)
	channel = (channel or M.config.channel or ""):lower():gsub("^#", "")
	if channel == "" then
		return vim.notify("kappa: channel required (:Kappa <channel>)", vim.log.levels.ERROR)
	end
	M.close()
	state.buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(state.buf, "kappa://" .. channel)
	vim.bo[state.buf].buftype = "nofile"
	vim.bo[state.buf].filetype = "kappa"
	vim.bo[state.buf].modifiable = false
	vim.api.nvim_create_autocmd("BufWipeout", { buffer = state.buf, once = true, callback = disconnect })
	state.images = images_ok()
	state.placements = {}
	if state.images and M.config.max_lines > 300 then
		M.config.max_lines = 300 -- ponytail: images are expensive, keep the buffer short
	end

	vim.cmd("botright vsplit")
	state.win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(state.win, state.buf)
	vim.api.nvim_win_set_width(state.win, M.config.width)
	local wo = vim.wo[state.win]
	wo.wrap, wo.number, wo.relativenumber, wo.signcolumn, wo.winfixwidth = true, false, false, "no", true
	vim.cmd.wincmd("p")

	connect(channel)
end

---@param channel string|nil  with a channel: (re)open it; without: close if open, else open config.channel
function M.toggle(channel)
	if state.win and vim.api.nvim_win_is_valid(state.win) and not channel then
		return M.close()
	end
	M.open(channel)
end

return M

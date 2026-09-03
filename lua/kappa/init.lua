local M = {}

M.config = {
	channel = nil, -- default channel for :Kappa with no argument
	width = 40,
	timestamps = true,
	-- ponytail: anonymous read-only login; sending needs an oauth token, add when wanted
	nick = "justinfan" .. math.random(10000, 99999),
}

local state = { tcp = nil, buf = nil, win = nil }

-- Twitch prefixes chat lines with IRCv3 tags once we CAP REQ them:
--   @color=#0000FF;display-name=foofoo;... :foofoo!foofoo@foofoo.tmi.twitch.tv PRIVMSG #bar :hi
-- We use "color" (hex, may be empty) and "display-name" (cased nick, may be empty).

-- A namespace keeps our highlights separate from other plugins' marks.
-- Create it once, reuse it everywhere. Docs: :h nvim_create_namespace
local ns = vim.api.nvim_create_namespace("kappa")

-- One highlight group per distinct color, created lazily and remembered here
-- so we don't call nvim_set_hl 500 times for the same red.
-- Key: "#FF0000"  →  value: "KappaFF0000" (the group name we created)
local hl_cache = {}

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

--- Parse one IRC line. Returns nick, message for PRIVMSG; "PING" for pings; nil otherwise.
function M.parse(line)
	if line:find("^PING") then
		return "PING"
	end
	local nick, msg = line:match("^:([^!]+)!%S+ PRIVMSG #%S+ :(.*)$")
	if nick then
		return nick, msg
	end
end

--- @param line string
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

	return { nick = name, msg = msg, color = color }
end

--- Turn a hex color into a highlight group name, creating it on first use.
---   "#FF0000" → "KappaFF0000"
--- Returns nil for empty/missing color so the caller can skip highlighting.
--- @param color string
local function hl_for(color)
	if color == "" or color == nil then
		return nil
	end

	if hl_cache[color] then
		return hl_cache[color]
	end

	local hl_name = color:gsub("#", "")
	hl_cache[color] = hl_name
	vim.api.nvim_set_hl(0, hl_name, { fg = color })

	return hl_name
end

--- Paint columns [col_start, col_end) of a buffer row with a highlight group.
--- Rows and columns are 0-based here (the extmark API is 0-based, unlike cursor positions).
local function highlight_nick(row, col_start, col_end, group)
	vim.api.nvim_buf_set_extmark(state.buf, ns, row, col_start, {
		end_col = col_end,
		hl_group = group,
	})
end

local function append(line, nick_start, nick_end, color)
	vim.schedule(function()
		if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
			return
		end
		vim.bo[state.buf].modifiable = true
		vim.api.nvim_buf_set_lines(state.buf, -1, -1, false, { line })
		vim.bo[state.buf].modifiable = false

		local row = vim.api.nvim_buf_line_count(state.buf)
		local group = hl_for(color)
		if group then
			highlight_nick(row - 1, nick_start, nick_end, group)
		end
		-- ponytail: always tail; stop following when user scrolls up if it annoys
		if state.win and vim.api.nvim_win_is_valid(state.win) then
			vim.api.nvim_win_set_cursor(state.win, { vim.api.nvim_buf_line_count(state.buf), 0 })
		end
	end)
end

local function handle(line)
	local m = M.parse_message(line)

	if m == "PING" then
		state.tcp:write("PONG :tmi.twitch.tv\r\n")
	elseif m then
		local ts = M.config.timestamps and os.date("%H:%M ") or ""
		local nick_start = #ts -- 6, the length of "21:36 "
		local nick_end = #ts + #m.nick
		append(("%s%s: %s"):format(ts, m.nick, m.msg), nick_start, nick_end, m.color)
	end
end

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

	vim.cmd("botright vsplit")
	state.win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(state.win, state.buf)
	vim.api.nvim_win_set_width(state.win, M.config.width)
	local wo = vim.wo[state.win]
	wo.wrap, wo.number, wo.relativenumber, wo.signcolumn, wo.winfixwidth = true, false, false, "no", true
	vim.cmd.wincmd("p")

	connect(channel)
end

function M.toggle(channel)
	if state.win and vim.api.nvim_win_is_valid(state.win) and not channel then
		return M.close()
	end
	M.open(channel)
end

return M

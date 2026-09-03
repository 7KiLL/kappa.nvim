local M = {}

M.config = {
	channel = nil, -- default channel for :Kappa with no argument
	width = 40,
	timestamps = true,
	-- ponytail: anonymous read-only login; sending needs an oauth token, add when wanted
	nick = "justinfan" .. math.random(10000, 99999),
}

local state = { tcp = nil, buf = nil, win = nil }

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

local function append(line)
	vim.schedule(function()
		if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
			return
		end
		vim.bo[state.buf].modifiable = true
		vim.api.nvim_buf_set_lines(state.buf, -1, -1, false, { line })
		vim.bo[state.buf].modifiable = false
		-- ponytail: always tail; stop following when user scrolls up if it annoys
		if state.win and vim.api.nvim_win_is_valid(state.win) then
			vim.api.nvim_win_set_cursor(state.win, { vim.api.nvim_buf_line_count(state.buf), 0 })
		end
	end)
end

local function handle(line)
	local nick, msg = M.parse(line)
	if nick == "PING" then
		state.tcp:write("PONG :tmi.twitch.tv\r\n")
	elseif nick then
		local ts = M.config.timestamps and os.date("%H:%M ") or ""
		append(("%s%s: %s"):format(ts, nick, msg))
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

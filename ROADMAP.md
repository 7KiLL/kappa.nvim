# Roadmap

Rough order. Each item is small and independent.

## Done

- [x] Read-only anonymous chat in a right sidebar (`:Kappa <channel>`, `:Kappa` to toggle)
- [x] Colored nicknames via IRCv3 tags (`display-name`, `color`)
- [x] Unicode emoji: free, the buffer is UTF-8 and nick offsets are byte-based already

## Next

- [ ] **Scroll lock** (~5 lines)
  Only follow the tail when the cursor is already on the last line.
  Otherwise scrolling up to read gets yanked back on every message.
  Where: `append()`, check cursor row before `nvim_buf_set_lines`.

- [ ] **Dimmed timestamps** (~5 lines)
  Link a `KappaTime` group to `Comment`, extmark on columns `0..#ts`.
  Same trick as nick colors.

- [ ] **Reconnect** (~15 lines)
  On `! disconnected`, `vim.defer_fn` a retry with backoff, give up after N tries.
  Where: `read_start` error branch in `connect()`.

- [ ] **README screenshot**
  Needed for awesome-neovim. `assets/demo.png` like copybara.

- [ ] **Twitch emote highlighting** (~15 lines)
  The `emotes` tag gives `id:start-end,start-end/id:...` with offsets into the
  message. Paint those ranges with a `KappaEmote` group.
  Gotcha: offsets are in Unicode codepoints, extmarks want bytes. `vim.str_byteindex` converts.

- [ ] **7TV emote highlighting** (~40 lines, needs `curl`)
  `room-id` tag = Twitch channel id. Once per channel:
  `GET https://7tv.io/v3/users/twitch/<room-id>` → `emote_set.emotes[].name`
  (public, no auth, ~1000 names for big channels).
  Fetch with `vim.system({ "curl", "-s", url })`, parse with `vim.json.decode`,
  keep a `set[name] = true`. Per message: split on spaces, highlight words in the set.
  Where: new `lua/kappa/seventv.lua`, hook in `handle()` after parse.

- [ ] **Sending messages** (~30 lines + config)
  Needs an OAuth token with `chat:edit` scope and `PASS oauth:<token>` before `NICK`.
  UI: `:KappaSend <text>` or `vim.ui.input` from a keymap.
  Update README and lazy spec.

## Maybe

- **Emote images** (Twitch + 7TV). Terminals can't show images in a buffer
  without the kitty graphics protocol and a plugin like `image.nvim`. Would be an
  optional integration: if `image.nvim` is installed and the terminal supports it,
  swap highlighted names for the CDN webp (`https://cdn.7tv.app/emote/<id>/1x.webp`).
  Big, keep last.
- Badges: mod / sub / broadcaster prefix from the `badges` tag
- Multiple channels, one buffer each

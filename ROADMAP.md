# Roadmap

Rough order. Each item is small and independent.

## Done

- [x] Read-only anonymous chat in a right sidebar (`:Kappa <channel>`, `:Kappa` to toggle)
- [x] Colored nicknames via IRCv3 tags (`display-name`, `color`)
- [x] Unicode emoji: free, the buffer is UTF-8 and nick offsets are byte-based already
- [x] Zebra rows: every other message gets `KappaAlt` (links to `CursorLine`)
- [x] Badges: glyph + color per role before the nick, first of broadcaster/mod/vip/sub wins
- [x] `@name` mentions highlighted with `KappaMention`
- [x] Dimmed timestamps: `KappaTime` linked to `Comment`
- [x] Scroll lock: tail only while the cursor is on the last line, `G` resumes
- [x] Emotes: Twitch (`emotes` tag) + 7TV (per room-id set), images via snacks.nvim, text highlight fallback

## Next

- [ ] **Mentions of you** (after Sending messages, needs auth to know your name)
  Whole-line tint (`KappaMentionMe` → `Visual`, `line_hl_group` on the extmark),
  `vim.notify` and optionally a sound. Plain `@name` highlighting is already done.

- [ ] **Reconnect** (~15 lines)
  On `! disconnected`, `vim.defer_fn` a retry with backoff, give up after N tries.
  Where: `read_start` error branch in `connect()`.

- [ ] **README screenshot**
  Needed for awesome-neovim. `assets/demo.png` like copybara.


- [ ] **Sending messages** (~30 lines + config)
  Needs an OAuth token with `chat:edit` scope and `PASS oauth:<token>` before `NICK`.
  UI: `:KappaSend <text>` or `vim.ui.input` from a keymap.
  Update README and lazy spec.

- [ ] **Whispers** (after Sending messages, needs auth)
  Add `twitch.tv/commands` to the CAP REQ, parse `:from!from@x WHISPER you :text`,
  show in the chat buffer with a distinct color or in a second buffer.
  Receiving only. Twitch dropped sending whispers over IRC, that needs a Helix call.

## Known ceilings

- Zebra rows are opaque on transparent terminals. Cells have no alpha. Override `KappaAlt`
  with a bg near your wallpaper, or use an fg-only stripe.
- Animated emotes show their first frame. Snacks converts to one PNG; streaming frames over
  the kitty protocol per visible emote is not something any Neovim plugin does.
- Wrapped lines that end in an emote get a blank virtual row under them. Snacks skips its
  overlay path when the text is wider than the window. Wider sidebar helps, real fix is upstream.

## Maybe

- Multiple channels, one buffer each

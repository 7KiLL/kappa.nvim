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

- [ ] **Mentions / keywords** (~15 lines)
  `highlights = { "yourname", "kappa.nvim" }` in opts. Case-insensitive match on the
  message text. Hit → tint the whole line (`KappaMention` group, `line_hl_group` on the
  extmark) and `vim.notify` if `notify = true`. Works anonymously, it's just text.

- [ ] **Badges** (~20 lines)
  The `badges` tag: `broadcaster/1,moderator/1,vip/1,subscriber/12`.
  Prefix the nick with a glyph per role, each with its own highlight group:
  ```lua
  badges = {           -- opts, override with nerd-font glyphs if you like
    broadcaster = { "●", "#E91916" },
    moderator   = { "⚔", "#00AD03" },
    vip         = { "◆", "#E005B9" },
    subscriber  = { "★", "#9146FF" },
  }
  ```
  Only the first matching role shows. Nick offsets shift by the prefix length.
  Badge images need an authed Helix call for the URL map, not worth it.

- [ ] **Reconnect** (~15 lines)
  On `! disconnected`, `vim.defer_fn` a retry with backoff, give up after N tries.
  Where: `read_start` error branch in `connect()`.

- [ ] **README screenshot**
  Needed for awesome-neovim. `assets/demo.png` like copybara.

- [ ] **Emotes: Twitch + 7TV** (~150 lines, new `lua/kappa/emotes.lua`)
  Images by default, text fallback when the terminal can't. Never "unsupported".

  Finding them:
  - Twitch: the `emotes` tag gives `id:start-end,...` in codepoint offsets
    (`vim.str_byteindex` to bytes). Image: `https://static-cdn.jtvnw.net/emoticons/v2/<id>/default/dark/2.0`
  - 7TV: `room-id` tag → `GET https://7tv.io/v3/users/twitch/<room-id>` once per channel,
    public, no auth. `emote_set.emotes[].name` + id. Match words per message.
    Image: `https://cdn.7tv.app/emote/<id>/2x.webp`

  Rendering, picked once at open:
  1. `Snacks.image.supports_terminal()` true (kitty, ghostty; tmux ok, zellij no)
     → download once to `stdpath("cache")/kappa/`, then
       `Snacks.image.placement.new(buf, file, { pos = {row, col}, inline = true, width = 2, height = 1 })`
       over the emote text. First frame only, no animation.
  2. otherwise → highlight the range with a `KappaEmote` group and wrap it, e.g. `⟨KEKW⟩`,
     so emotes read differently from words.

  Keep it cheap: cap buffer at ~300 lines, drop placements on lines that scroll out,
  one download per emote id.

- [ ] **Sending messages** (~30 lines + config)
  Needs an OAuth token with `chat:edit` scope and `PASS oauth:<token>` before `NICK`.
  UI: `:KappaSend <text>` or `vim.ui.input` from a keymap.
  Update README and lazy spec.

- [ ] **Whispers** (after Sending messages, needs auth)
  Add `twitch.tv/commands` to the CAP REQ, parse `:from!from@x WHISPER you :text`,
  show in the chat buffer with a distinct color or in a second buffer.
  Receiving only. Twitch dropped sending whispers over IRC, that needs a Helix call.

## Maybe

- Multiple channels, one buffer each

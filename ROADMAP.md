# Roadmap

Rough order. Each item is small and independent.

## Done

- [x] Read-only anonymous chat in a right sidebar (`:Kappa <channel>`, `:Kappa` to toggle)
- [x] Colored nicknames via IRCv3 tags (`display-name`, `color`)

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

- [ ] **Sending messages** (~30 lines + config)
  Needs an OAuth token with `chat:edit` scope and `PASS oauth:<token>` before `NICK`.
  UI: `:KappaSend <text>` or `vim.ui.input` from a keymap.
  Update README and lazy spec.

## Maybe

- Strip or render emotes (the `emotes` tag gives byte ranges)
- Badges: mod / sub / broadcaster prefix from the `badges` tag
- Multiple channels, one buffer each

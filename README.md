# kappa.nvim

Twitch chat in a Neovim sidebar. Read-only, anonymous, zero dependencies.

## Install (lazy.nvim)

```lua
{
  "7KiLL/kappa.nvim",
  cmd = "Kappa",
  opts = { channel = "yourfavstreamer", width = 40 },
}
```

## Usage

- `:Kappa <channel>` — open chat for a channel
- `:Kappa` — toggle sidebar (uses `opts.channel`)

## License

MIT

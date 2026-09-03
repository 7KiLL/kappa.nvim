# kappa.nvim

Twitch chat in a Neovim sidebar. Read-only, anonymous, zero dependencies.

## Install (lazy.nvim)

```lua
{
  "7KiLL/kappa.nvim",
  cmd = "Kappa",
  opts = { channel = "yourfavstreamer" },
}
```

## Options

```lua
{
  channel = nil,      -- default channel for :Kappa with no argument
  width = 40,         -- sidebar width
  timestamps = true,  -- prefix messages with HH:MM
  max_lines = 10000,  -- oldest lines are dropped past this
}
```

## Usage

- `:Kappa <channel>` — open chat for a channel
- `:Kappa` — toggle sidebar (uses `opts.channel`)

## License

MIT

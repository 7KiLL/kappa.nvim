# kappa.nvim

Twitch chat in a Neovim sidebar. Read-only, anonymous, zero required dependencies.
Twitch and 7TV emotes render as images when [snacks.nvim](https://github.com/folke/snacks.nvim) is installed and the terminal supports graphics (kitty, ghostty, wezterm, tmux). Elsewhere they are highlighted as text.

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
  max_lines = 10000,  -- oldest lines are dropped past this (300 in image mode)
  images = true,      -- emotes as images via snacks.nvim when the terminal can
  emote_width = 2,    -- max emote image width in cells
  emote_height = 1,   -- rows; 3+ pads virtual lines below the message (2 acts like 1)
}
```

## Usage

- `:Kappa <channel>` — open chat for a channel
- `:Kappa` — toggle sidebar (uses `opts.channel`)

## License

MIT

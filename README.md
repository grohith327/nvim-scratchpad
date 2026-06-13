# nvim-scratchpad

A small branch-aware markdown scratchpad for Neovim.

`nvim-scratchpad` gives each Git branch its own local notes buffer. Open it,
write quick markdown notes, switch branches, and the scratchpad saves and
reloads the right content automatically.

https://github.com/user-attachments/assets/4376718c-7b41-464d-93fa-931df7cd60f6

## Features

- Branch-specific scratchpads for each Git repository.
- Markdown file buffers with normal Neovim editing and `:write` support.
- Debounced autosave while typing.
- Automatic save and reload when the current Git branch changes.
- Scratchpad files stored outside the repo in Neovim's data directory.
- Three commands: `:ScratchpadOpen`, `:ScratchpadClose`, and `:ScratchpadWrite`.

## Requirements

- Neovim >= 0.10
- Git

## Installation

### lazy.nvim

```lua
{
  "grohith327/nvim-scratchpad",
  opts = {},
}
```

### packer.nvim

```lua
use({
  "grohith327/nvim-scratchpad",
  config = function()
    require("nvim-scratchpad").setup()
  end,
})
```

### vim-plug

```vim
Plug 'grohith327/nvim-scratchpad'
```

Then configure it in Lua:

```lua
require("nvim-scratchpad").setup()
```

## Setup

The default setup is enough for most use cases:

```lua
require("nvim-scratchpad").setup()
```

Available options:

```lua
require("nvim-scratchpad").setup({
  autosave_delay = 500, -- milliseconds after edits stop before saving
  split_height = 12,    -- bottom split height
})
```

## Usage

Open Neovim inside a Git repository and run:

```vim
:ScratchpadOpen
```

Write notes as normal markdown. The buffer autosaves after edits stop, and
regular `:write` also works because the scratchpad is backed by a real file.

To open the scratchpad with `<leader>sp`, add this to your Neovim config:

```lua
vim.keymap.set("n", "<leader>sp", "<cmd>ScratchpadOpen<cr>", {
  desc = "Open scratchpad",
})
```

Switch branches in another terminal:

```sh
git checkout -b feature
```

When Neovim regains focus, enters a buffer, or resumes, `nvim-scratchpad`
saves the previous branch scratchpad and loads the scratchpad for the new
branch.

## Commands

| Command | Description |
| --- | --- |
| `:ScratchpadOpen` | Open or focus the scratchpad for the current repo and branch. |
| `:ScratchpadClose` | Save and close the scratchpad window. |
| `:ScratchpadWrite` | Save the current scratchpad explicitly. |

## Storage

Scratchpads are stored under:

```text
stdpath("data")/nvim-scratchpad/<repo-hash>/<branch-hash>.md
```

The repo path and branch name are hashed, so branch names with slashes or other
special characters are safe. Files are not written to the project working tree
and will not affect `git status`.

Detached HEAD states are stored separately using the short commit SHA.

## Manual Test

```sh
mkdir /tmp/scratchpad-test
cd /tmp/scratchpad-test
git init -b main
nvim
```

Inside Neovim:

```vim
:ScratchpadOpen
```

Add some markdown text, wait briefly for autosave, then switch branches from
another terminal:

```sh
cd /tmp/scratchpad-test
git checkout -b feature
```

Return to Neovim or run:

```vim
:doautocmd FocusGained
```

The feature branch scratchpad should load independently. Switch back to `main`
and trigger focus again to confirm the original notes return.

## Tests

Run the headless integration tests:

```sh
nvim --headless -u NONE -S tests/scratchpad_spec.lua
```

The tests create temporary Git repositories and verify open, autosave,
branch-specific reload, explicit write, and outside-repo error behavior.


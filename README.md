# grepsearch for micro
a plugin for the blazingly fast [micro editor](https://micro-editor.github.io)

Enables to search recursive with grep inside current folder (and subfolders)

## Installation

for now clone this repository inside your micro-plugin directory (for example `$HOME/.config/micro/plug/`)

tested with micro v. 2.0.8 and 2.0.10

## Usage
open micro inside directory you want to search with.
grepsearch will use this directory as base-folder for its search.

open micro-terminal (ctrl + e) and type grepsearch and what you want to search for:

```
> grepsearch "whatever you want to search for"

```

it opens up a pane with the search-result. you can use up- and down-arrow to select search entry and open file / jump to line with `Enter`.
at first it will split the current pane verticaly and opens the file in this pane,
once a pane is opened grepsearch will reuse this pane to open selected entrys afterwards.

close search-pane with `ctrl-q`

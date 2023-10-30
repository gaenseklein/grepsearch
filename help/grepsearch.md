# grepsearch for micro
Enables to search recursive with grep inside current folder (and subfolders)

## Usage

open micro-terminal (ctrl + e) and type grepsearch and what you want to search for:

```
> grepsearch "whatever you want to search for"

```

it opens up a pane with the search-result. you can use up- and down-arrow to select search entry and open file / jump to line with `Enter`.
at first it will split the current pane verticaly and opens the file in this pane,
once a pane is opened grepsearch will reuse this pane to open selected entrys afterwards.

close search-pane with `ctrl-q` or `Escape`

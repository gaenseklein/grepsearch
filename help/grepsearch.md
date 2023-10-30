# grepsearch for micro
A plugin for the micro text editor. Enables to search recursive with grep inside current folder (and subfolders)

## Usage

open micro-terminal (ctrl + e) and type grepsearch and what you want to search for:

```
> grepsearch "whatever you want to search for"

```

it opens up a pane with the search-result. you can use up- and down-arrow to select search entry 
and open file / jump to line with `Enter`.
at first it will split the current pane verticaly and opens the file in this pane,
once a pane is opened grepsearch will reuse this pane to open selected entrys afterwards.

close search-pane with `ctrl-q`

## Filter

you can filter where to search from. right now there are 3 options 
for filters you can change in your micro options:

- searchgitrepository: use "git grep" instead of just "grep" (excludes files from .gitignore) - default true
- searchdotgit: include files in ./.git/ - default false (only in effect if searchgitrepository is false)
- searchdotfiles: include hidden files - default true

for more info about micros options see `> help options`

you can alter the use-git filter and hidden filter on the fly on the search-pane - this will not be 
saved into your standard micro options though. just select the filter and press `Ènter`
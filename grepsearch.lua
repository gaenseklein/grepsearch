VERSION = "1.0.0"

local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local buffer = import("micro/buffer")
local os = import("os")
local filepath = import("path/filepath")

local search_results = {}
local search_mapping_lines = {}
local search_term = ""
-- Holds the micro.CurPane() we're manipulating
local search_view = nil
-- Holds the Pane we are open Files into
local target_buff = nil
local target_pane
-- Keeps track of the current working directory
local current_dir = ""

local inside_git = false 
local searchsymstart = "⇛"
local searchsymend = "⇚"


-- constructs a new search entry
-- filepath, linenr, linetext, searchterm: string
local function new_search_entry(filepath, linenr, linetext, searchterm)
	local pos = string.find(linetext,searchterm)
	local max = search_view:GetView().Width - #linenr - 4 --4 is for ': ' and the 2 markers 
	--local length = string.len(linetext)
	-- lets shorten the text as grep can produce very big results
	local text = linetext --string.sub(linetext, string.find(linetext, '%S'))
	local firstl = string.sub(text,1,1)
	local cutted = 0
	-- first cut off all whitespaces to left, because they are annoying
	while firstl ==' ' or firstl == '\t' do 
		text = string.sub(text,2) 
		firstl = string.sub(text,1,1)
		cutted = cutted + 1
	end	
	-- cutting from left to search term to make searchterm visible:
	if pos - cutted > max - #searchterm - 2 then 
		--local cuttedpos = pos - cutted 
		local cutpos = (pos - cutted - max) + ((max - max % 2) / 2)
		text = '(...)' .. string.sub(linetext,cutpos)
	end
	-- cutting right to avoid huuuuge lines
	if #text > max*10 then
		text = string.sub(text, 1, max*10) .. '(...)'
	end
	local sstart, ssend = string.find(text,searchterm)
	text = string.sub(text,1,sstart-1)..searchsymstart..searchterm..searchsymend..string.sub(text,ssend+1)
	return {
		path = filepath,
		line = linenr,
		text = text,
		pos = pos
	}
end

-- filter:
local includegit = false --= config.GetGlobalOption("grepsearch.searchdotgit")
local include_dots = true --config.GetGlobalOption("grepsearch.searchdotfiles")
local use_git = true --config.GetGlobalOption("grepsearch.searchgitrepository")
local show_filter = true

 
local function grep_exec(searchterm)
	-- standard-command: exclude .git-directory 
	local runCommand = 'grep -rnI --exclude-dir=.git "' .. searchterm .. '"'
	-- if user wants to search inside .git also
	if includegit then runCommand = 'grep -rnI "' .. searchterm .. '"' end
	-- if user does not want to search in hidden files
	if not include_dots then runCommand = 'grep -rnI --exclude=\'.*\' --exclude-dir=\'.*\' "' .. searchterm .. '"' end
	-- if inside repo and user prefers git use git instead
	-- local git_tree = shell.RunCommand('git rev-parse --is-inside-work-tree')
	if inside_git and use_git then
		runCommand = 'git grep -rnI "' .. searchterm .. '"'
	end
--	micro.TermError("runCommand",56,runCommand ..' << usegit:'.. boolstring(use_git) .. 'inside_git' .. boolstring(inside_git))
	-- run the command
	-- TODO: as it can endure a while we should give visual feedback maybe that we are still searching?
	micro.InfoBar():Message('grepsearch command:' .. runCommand)
	local grep_result, grep_error = shell.RunCommand(runCommand)	
	return grep_result
end


local function parse_grep_result(grep_result, searchterm)
	--parse all grep-result in one go
	local line = 0
	local linetext = ""
	local filepath = ""
	local linenr = ""
	local startpos = 1
	-- end of line:
	local endpos = string.find(grep_result,'\n',startpos)
	-- first : marks separation of filename (1->filepos)
	local filepos = string.find(grep_result,':',startpos)
	-- if we dont find filepos its an empty result, grep did not find anything
	if filepos == nil then return {} end
	-- linepos marks separation of line-number of result (filepos -> linepos)
	local linepos = string.find(grep_result,':',filepos+1)
	
	local result = {}
	while endpos~=nil do		
		line = line + 1
		filepath = string.sub(grep_result,startpos,filepos-1)
		linenr = string.sub(grep_result,filepos+1,linepos-1)		
		linetext = string.sub(grep_result, linepos+1, endpos -1)				
		result[line] = new_search_entry(filepath, linenr, linetext, searchterm)
		
		startpos = endpos + 1
		endpos = string.find(grep_result,'\n',startpos)
		filepos = string.find(grep_result,':',startpos)
		if filepos~=nil then linepos = string.find(grep_result,':',filepos +1) end
	end		
	return result
end

-- programmaticaly search
local function programmaticaly_search(term)
	local searchterm = term 
	if searchterm == nil then searchterm = search_term end
	if searchterm == nil then return end
	local grep_result = grep_exec(searchterm)
	local parsed_search = parse_grep_result(grep_result,searchterm)
	--show some feedback on info-bar:
	micro.InfoBar():Message('search for ' .. searchterm .. "  " .. #parsed_search .. " results")
	-- show results in search_pane:		
	display_grepsearch(parsed_search, searchterm)
end

-- user starts a search
function grep_search(bp, args)
	--open up search_result pane if not open yet:
	toggle_tree(true)
	if #args < 1 then 
		-- we dont want to perform empty searches:
		close_tree()
		return
	end
	
	local searchterm = args[1]
	local grep_result = grep_exec(searchterm)
	local parsed_search = parse_grep_result(grep_result,searchterm)
	--show some feedback on info-bar:
	micro.InfoBar():Message('search for ' .. searchterm .. "  " .. #parsed_search .. " results")
	-- show results in search_pane:		
	display_grepsearch(parsed_search, searchterm)
	search_term = searchterm
end

--~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
--filter
--~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local filteraction = {}

local function display_filter(linenr)
	-- local includegit = config.GetGlobalOption("grepsearch.searchdotgit")
	-- local include_dots = config.GetGlobalOption("grepsearch.searchdotfiles")
	-- local use_git = config.GetGlobalOption("grepsearch.searchgitrepository")
	filteraction = {}
	local actline = linenr
	local res = "############\n"
	if inside_git then 
		res = res .. "#.gitignore:"..boolstring(use_git).."\n" 
		filteraction[actline] = ".gitignore"
		actline = actline + 1 
	end
	res = res .. "#include hidden files:"..boolstring(include_dots).."\n"
	filteraction[actline] = "hidden"
	actline = actline + 1	
	return res, actline
end

local function try_change_filter()
	local y = search_view.Cursor.Loc.Y 
	if filteraction[y]==nil then 
		micro.TermError('filteraction is nil',y,"filteraction.length:"..#filteraction)
		return false 
	end
	if filteraction[y]==".gitignore" then use_git = not use_git end
	if filteraction[y]=="hidden" then include_dots = not include_dots end
--	micro.TermError('gi:'..boolstring(use_git),186,'hidden:'..boolstring(include_dots))
	programmaticaly_search()
	return true
end


function display_grepsearch(search_result, searchterm, grep_result)
	-- i copied most code from filemanager plugin and adapted to my needs
	search_mapping_lines = {}
	-- Delete everything in the view/buffer
	search_view.Buf.EventHandler:Remove(search_view.Buf:Start(), search_view.Buf:End())

	-- Insert the top 3 things that are always there
	-- Current dir
	--local cd = "~/grepsearch"
	search_view.Buf.EventHandler:Insert(buffer.Loc(0, 0), "#search for \""..searchterm .. "\" in "..current_dir.."\n")
	-- An ASCII separator
	search_view.Buf.EventHandler:Insert(buffer.Loc(0, 1), string.rep("#", search_view:GetView().Width-4) .. "\n")
	-- The ".." and use a newline if there are things in the current dir
	--search_view.Buf.EventHandler:Insert(buffer.Loc(0, 2), (#search_result > 0 and "..\n" or ".."))

	-- Holds the current basename of the path (purely for display)
	local display_content
	local act_file = ""
	ii = 2
	-- NOTE: might want to not do all these concats in the loop, it can get slow
	for i = 1, #search_result do
		ii = ii + 1
		local res = search_result[i]
		local space = ""
		display_content = res.line .. ': ' .. res.text
		if res.path ~= act_file then
			act_file = res.path
			--space = res.path
			display_content = '\n/' .. res.path .. ':\n' .. display_content
			search_mapping_lines[ii+1]=search_result[i]
			ii = ii +2
		end
		-- Newlines are needed for all inserts except the last
		-- If you insert a newline on the last, it leaves a blank spot at the bottom
		if i < #search_result then
			display_content = display_content .. "\n"
		end
		

		-- Insert line-by-line to avoid out-of-bounds on big folders
		-- +2 so we skip the 0/1/2 positions that hold the top dir/separator/..
		search_view.Buf.EventHandler:Insert(buffer.Loc(0, ii), display_content)
		search_mapping_lines[ii]=search_result[i]
	end
	if #search_result == 0 then
		ii = ii+1
		display_content = "\nno matches found\n"
		search_view.Buf.EventHandler:Insert(buffer.Loc(0, ii), display_content)		
		ii = ii+2
	end
	-- debug:
	-- if grep_result ~= nil then
		-- search_view.Buf.EventHandler:Insert(buffer.Loc(0, 20), grep_result)
		-- return
	-- end

	if show_filter then			
			search_view.Buf.EventHandler:Insert(buffer.Loc(#display_content+1, ii), "\n")
			ii=ii+1
			local filtertext, endline = display_filter(ii)
			search_view.Buf.EventHandler:Insert(buffer.Loc(0, ii), filtertext)
			ii=endline
	end
	--search_view.Buf.EventHandler:Insert(buffer.Loc(0,10), grep_result)

	-- Resizes all views after messing with ours
    search_view:Tab():Resize()
    -- go to first search entry
	search_view:GotoCmd({"4"})

end

-- open_tree setup's the view
local function open_tree()
	-- Open a new Vsplit (on the very left)
	micro.CurPane():VSplitIndex(buffer.NewBuffer("", "grepsearchview"), false)
	-- Save the new view so we can access it later
	search_view = micro.CurPane()

	-- Set the width of search_view to 30% & lock it
    search_view:ResizePane(55)
	-- Set the type to unsavable
    -- search_view.Buf.Type = buffer.BTLog
    search_view.Buf.Type.Scratch = true
    --search_view.Buf.Type.Readonly = true

	-- Set the various display settings, but only on our view (by using SetLocalOption instead of SetOption)
	-- NOTE: Micro requires the true/false to be a string
	-- Softwrap long strings (the file/dir paths)
    search_view.Buf:SetOptionNative("softwrap", false)
    -- No line numbering
    search_view.Buf:SetOptionNative("ruler", false)
    -- Is this needed with new non-savable settings from being "vtLog"?
    search_view.Buf:SetOptionNative("autosave", false)
    -- Don't show the statusline to differentiate the view from normal views
    search_view.Buf:SetOptionNative("statusformatr", "")
    search_view.Buf:SetOptionNative("statusformatl", "search result")
    search_view.Buf:SetOptionNative("scrollbar", false)
    search_view.Buf:SetOptionNative("filetype","grepsearch")

	-- Fill the search_result, and then print its contents to search_view
	-- update_current_dir(os.Getwd())
end

-- close_tree will close the tree plugin view and release memory.
local function close_tree()
	if search_view ~= nil then
		search_view:Quit()
		search_view = nil
		--clear_messenger()
	end
end

-- toggle_tree will toggle the tree view visible (create) and hide (delete).
function toggle_tree(open_again)
	if search_view == nil then
		open_tree()
	else
		close_tree()
		if open_again then open_tree() end
	end
end

local function try_open()
	local y = search_view.Cursor.Loc.Y + 1
	-- If it's a file, then open it
	if search_mapping_lines[y] then 
		local ty = string.sub(search_mapping_lines[y].line,1,-1)
		micro.InfoBar():Message("grepsearch opened ", search_mapping_lines[y].path, ':',ty)
		-- Opens the absolute path in new vertical view
		target_buff = buffer.NewBufferFromFile(search_mapping_lines[y].path)
		if target_pane == nil then 
			target_pane = micro.CurPane():VSplitIndex(target_buff, true)
			--target_pane:SetID(13)
		else 
			target_pane:OpenBuffer(target_buff)
			micro.CurPane():NextSplit()
		end
		-- Goes to line of search_entry
		micro.CurPane():GotoCmd({ty})
		return true
		
		--local cursor = search_target:GetActiveCursor()
		--cursor:GotoLoc({X=1, Y=y})
		--search_target:SetCurCursor()
		--search_target.Cursor.Loc.Y = tonumber(string.sub(search_mapping_lines[y],1,-2))-- does not work
		--search_pane:GotoCmd({string.sub(search_mapping_lines[y].line,1,-2)})
		--micro.CurPane():goto(ty)
		--search_target.GotoLoc(0,y)
	else 
		micro.InfoBar():Error("grepsearch failed")
		return false
	end
	-- Resizes all views after opening a file
	-- tabs[curTab + 1]:Resize()
end

function onQuit(bp)
	if target_pane == bp then 
		--micro.InfoBar():Message('hi', target_pane)
		target_pane = nil
	end
end

local function is_inside_git()
	local test_git = string.sub(shell.RunCommand('git rev-parse --is-inside-work-tree'),1,4)
	local is_git = (string.sub(test_git,1,4) == 'true')
--	micro.TermError('inside git?',272,'>>'..test_git..'<<'..boolstring(inside_git))
	return is_git	
end

local function set_current_dir()
	local cd = os.Getwd()
	local pos = string.find(cd, "/")
	if pos == nil then
		return
	end
	local nextpos = string.find(cd,"/",pos+1)
	while nextpos ~= nil do
		pos=nextpos
		nextpos = string.find(cd,"/",pos+1)
	end
	current_dir = string.sub(cd, pos)
end

function init()
	inside_git = is_inside_git()
	set_current_dir()
	config.MakeCommand("grepsearch", grep_search, config.NoComplete)
	config.AddRuntimeFile("grepsearch",config.RTHelp, "help/grepsearch.md")
	config.AddRuntimeFile("grepsearch", config.RTSyntax, "syntax.yaml")
	-- Let the user decide to include .git-directory:
    config.RegisterCommonOption("grepsearch", "searchdotgit", false)
    includegit = config.GetGlobalOption("grepsearch.searchdotgit")
	-- Let the user decide to search inside dot-files
    config.RegisterCommonOption("grepsearch", "searchdotfiles", true)
    include_dots = config.GetGlobalOption("grepsearch.searchdotfiles")
    -- Let the user decide to use git grep respecting .gitignore-file to exclude from grep-search
    config.RegisterCommonOption("grepsearch", "searchgitrepository", true)
    use_git = config.GetGlobalOption("grepsearch.searchgitrepository")
    
	--micro.Log('test')
end

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Shorthand functions for actions to reduce repeat code
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local function select_line()
	search_view.Cursor:SelectLine()
end

-- Used to fail certain actions that we shouldn't allow on the search_view
local function false_if_tree(view)
	if view == search_view then
		return false
	end
end

-- Select the line at the cursor
local function selectline_if_tree(view)
	if view == search_view then
		select_line()
	end
end



-- Move the cursor to the top, but don't allow the action
local function aftermove_if_tree(view)
	if view == search_view then
		if search_view.Cursor.Loc.Y < 2 then
			-- If it went past the "..", move back onto it
			search_view.Cursor:DownN(2 - search_view.Cursor.Loc.Y)
		end
		select_line()
	end
end

local function clearselection_if_tree(view)
	if view == search_view then
		-- Clear the selection when doing a find, so it doesn't copy the current line
		search_view.Cursor:ResetSelection()
	end
end

function boolstring(bol)
	if bol then return "true" else return "false" end
end

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- All the events for certain Micro keys go below here
-- Other than things we flat-out fail
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

-- Close current
function preQuit(view)
	if view == search_view then
		-- A fake quit function
		close_tree()
		-- Don't actually "quit", otherwise it closes everything without saving for some reason
		return false
	end
end
-- Close all
function preQuitAll(view)
	close_tree()
end

-- Up
function onCursorUp(view)
	selectline_if_tree(view)
end
-- Down
function onCursorDown(view)
	selectline_if_tree(view)
end

function onEscape(view)
	if view ~= search_view then
		return true
	end
	close_tree()
end

-- exclude all keystrokes on search result pane:
function preRune(view, r)
	if view ~= search_view then 
		return true 
	end
	return false
end

-- handle enter on search result
function preInsertNewline(view)
    if view == search_view then
    	local openedfile = try_open()
    	if not openedfile then 
			try_change_filter()			
    	end
        return false
    end
    return true
end
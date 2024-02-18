---@alias namespace_id integer
---@alias iterator function

---@class UI
---@field connections_loaded boolean
---@field initial_layout_loaded boolean
---@field help_toggled boolean
---@field sidebar_ns namespace_id
---@field active_db string
---@field dbs table
---@field num_dbs integer
---@field buffers table<buffer|table<buffer>>
---@field windows table<window|table<window>>
---@field last_cursor_position table<table<integer, integer>>
---@field last_active_buffer buffer
---@field current_active_buffer buffer
---@field last_active_window window
---@field current_active_window window

local UI = {
	connections_loaded = false,
	initial_layout_loaded = false,
	help_toggled = false,
	sidebar_ns = 0,
	active_db = "",
	dbs = {},
	num_dbs = 0,
	buffers = {
		sidebar = 0,
		editors = {},
		results = {},
	},
	windows = {
		sidebar = 0,
		editors = {},
		results = {},
	},
	last_cursor_position = {
		sidebar = {},
		editor = {},
		result = {},
	},
	last_active_buffer = 0,
	current_active_buffer = 0,
	last_active_window = 0,
	current_active_window = 0,
}

local Utils = require("sqlua.utils")

local UI_ICONS = {
	db = " ",
	buffers = "",
	folder = " ",
	schemas = " ",
	schema = "פּ ",
	-- schema = '󱁊 ',
	table = "藺",
	file = " ",
	new_query = "璘 ",
	table_stmt = "離 ",
	-- table = ' ',
}

local ICONS_SUB = "[פּ󱁊藺璘離]"
local EDITOR_NUM = 1

---@param buf buffer
---@param val boolean
---@return nil
local function setSidebarModifiable(buf, val)
	vim.api.nvim_set_option_value("modifiable", val, { buf = buf })
end

---Sets highlighting in the sidebar based on the hl
local function highlightSidebarNumbers()
	local buf = vim.api.nvim_win_get_buf(UI.windows.sidebar)
	local lines = vim.api.nvim_buf_get_lines(
        buf, 0, vim.api.nvim_buf_line_count(buf), false
    )
	for line, text in ipairs(lines) do
		local s = text:find("%s%(")
		local e = text:find("%)")
		if s and e then
			vim.api.nvim_buf_add_highlight(
                UI.buffers.sidebar, UI.sidebar_ns, "Comment", line - 1, s, e
            )
		end
	end
end

---@param buf buffer
---@return string|nil, buffer|nil
---Searches existing buffers and returns the buffer type, and buffer number
local function getBufferType(buf)
	if UI.buffers.sidebar == buf then
		return "sidebar", UI.buffers.sidebar
	end
	for _, v in pairs(UI.buffers.editors) do
		if v == buf then
			return "editor", v
		end
	end
	for _, v in pairs(UI.buffers.results) do
		if v == buf then
			return "result", v
		end
	end
end

---@param table table table to begin the search at
---@param search string what to search for to toggle
---@return nil
--[[Recursively searches the given table to toggle the 'expanded'
  attribute for the given item.
]]
local function toggleExpanded(table, search)
	for key, value in Utils.pairsByKeys(table) do
		if key == search then
            table[search].expanded = not table[search].expanded
            return
		elseif type(value) == "table" then
			toggleExpanded(value, search)
		end
	end
end

---@param buf buffer
---@param srow integer
---@param text string
---@param sep string
local function printSidebarExpanded(buf, srow, text, sep)
	vim.api.nvim_buf_set_lines(buf, srow, srow, false, { sep .. " " .. text })
	return srow + 1
end

---@param buf buffer
---@param srow integer
---@param text string
---@param sep string
local function printSidebarCollapsed(buf, srow, text, sep)
	vim.api.nvim_buf_set_lines(buf, srow, srow, false, { sep .. " " .. text })
	return srow + 1
end

---@param buf buffer
---@param srow integer
---@param text string
local function printSidebarEmpty(buf, srow, text)
	vim.api.nvim_buf_set_lines(buf, srow, srow, false, { text })
	return srow + 1
end

---@param type string the type of table statement
---@param tbl string table
---@param schema string schema
---@param db string database
---@return nil
---Creates the specified statement to query the given table.
---Query is pulled based on active_db rdbms, and fills the available buffer.
local function createTableStatement(type, tbl, schema, db)
	local queries = require("sqlua/queries." .. UI.dbs[db].rdbms)
	local buf = UI.last_active_buffer
	local win = UI.last_active_window
	if buf == 0 then
		buf = UI.buffers.editors[1]
		win = UI.windows.editors[1]
	end
	vim.api.nvim_set_current_win(win)
	vim.api.nvim_win_set_buf(win, buf)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
	vim.api.nvim_win_set_cursor(win, { 1, 0 })
	local stmt = {}
	local query = queries.getQueries(
        tbl, schema, UI.options.default_limit
    )[type]
	for line in string.gmatch(query, "[^\r\n]+") do
        local q, _ = line:gsub("%s+", " ")
        q, _ = q:gsub("%.%s", ".")
		table.insert(stmt, q)
	end
	vim.api.nvim_buf_set_lines(buf, 0, 0, false, stmt)
    UI.dbs[db]:execute()
end

---@param type string the type to search for
---@param num integer the starting row to begin the search
---@return string|nil db
---@return integer|nil num
---@return nil
--[[Searches the sidebar from the given starting point upwards
  for the given type, returning the first occurence of either
  table, schema, or db
]]
local function sidebarFind(type, num)
	if type == "table" then
		local tbl = nil
		while true do
			tbl = vim.api.nvim_buf_get_lines(
                UI.buffers.sidebar, num - 1, num, false
            )[1]
			if not tbl then
				return
			elseif string.find(tbl, "") then
				break
			end
			num = num - 1
		end
		num = num - 1
		-- tbl = tbl:gsub("%s+", "")
        if tbl then
            if tbl:find("%(") then
                tbl = tbl:sub(1, tbl:find("%(") - 1)
            end
        end
		return tbl, num
	elseif type == "schema" then
		local schema = nil
		while true do
			schema = vim.api.nvim_buf_get_lines(
                UI.buffers.sidebar, num - 1, num, false
            )[1]
			if string.find(schema, "   ") then
				break
			end
			num = num - 1
		end
        if schema then
            if schema:find("%(") then
                schema = schema:sub(1, schema:find("%(") - 1)
            end
        end
		return schema, num
	elseif type == "database" then
		local db = nil
		while true do
			db = vim.api.nvim_buf_get_lines(
                UI.buffers.sidebar, num - 1, num, false
            )[1]
			if string.find(db, "^ ", 1) or string.find(db, "^ ", 1) then
				db = db:gsub("%s+", "")
				db = db:gsub(ICONS_SUB, "")
				break
			end
			num = num - 1
		end
        if db then
            if db:find("%(") then
                db = db:sub(1, db:find("%(") - 1)
            end
        end
		return db, num
	end
end


function UI:refreshSidebar()
	---@param buf buffer
	---@param tables table
	---@param srow integer
	---@param db string
	---@return integer srow
	local function refreshTables(buf, tables, srow, db)
		local sep = "     "
		local queries = require("sqlua/queries." .. UI.dbs[db].rdbms)
		local statements = queries.ddl
		for table, _ in Utils.pairsByKeys(tables) do
			local text = UI_ICONS.table .. table
			if tables[table].expanded then
				srow = printSidebarExpanded(buf, srow, text, sep)

				for _, stmt in Utils.pairsByKeys(statements) do
					text = UI_ICONS.table_stmt .. stmt
					srow = printSidebarEmpty(buf, srow, sep .. "    " .. text)
				end
			else
				srow = printSidebarCollapsed(buf, srow, text, sep)
			end
		end
		return srow
	end

	---@param buf buffer
	---@param dir table
	---@param srow integer
	---@param sep string
	---@return integer srow
	local function refreshSavedQueries(buf, file, srow, sep)
        if file.isdir then
            local text = UI_ICONS.folder .. file.name
            if file.expanded then
                srow = printSidebarExpanded(buf, srow, text, sep)
                if next(file.files) ~= nil then
                    for _, f in Utils.pairsByKeys(file.files) do
                        srow = refreshSavedQueries(
                            buf, f, srow, sep .. "  "
                        )
                    end
                end
            else
                srow = printSidebarCollapsed(buf, srow, text, sep)
            end
        else
            local text = UI_ICONS.file .. file.name
            srow = printSidebarEmpty(buf, srow, sep .. "  " .. text)
        end
		return srow
	end

	---@param buf buffer
	---@param db string
	---@param srow integer
	---@return integer srow
	local function refreshSchema(buf, db, srow)
		local sep = "   "
		for schema, _ in Utils.pairsByKeys(UI.dbs[db].schema) do
			local text = UI_ICONS.schema .. schema .. " (" ..
                UI.dbs[db].schema[schema].num_tables .. ")"
			if UI.dbs[db].schema[schema].expanded then
				if type(UI.dbs[db].schema[schema]) == "table" then
					srow = printSidebarExpanded(buf, srow, text, sep)
					local tables = UI.dbs[db].schema[schema].tables
					srow = refreshTables(buf, tables, srow, db)
				end
			else
				srow = printSidebarCollapsed(buf, srow, text, sep)
			end
		end
		return srow
	end

	---@param buf buffer
	---@param db string
	---@param srow integer
    ---@returns integer srow
	local function refreshOverview(buf, db, srow)
		local sep = "   "
		local text = UI_ICONS.folder .. "Saved Queries"
		if UI.dbs[db].files_expanded then
			srow = printSidebarExpanded(buf, srow, text, sep)
            for _, file in Utils.pairsByKeys(UI.dbs[db].files.files) do
                srow = refreshSavedQueries(
                    buf, file, srow, sep .. "  "
                )
            end
			srow = refreshSchema(buf, db, srow)
		else
			srow = printSidebarCollapsed(buf, srow, text, sep)
			srow = refreshSchema(buf, db, srow)
		end
		return srow
	end

	local buf = UI.buffers.sidebar
	local sep = " "

	setSidebarModifiable(buf, true)
	vim.api.nvim_buf_set_lines(UI.buffers.sidebar, 0, -1, false, {})

	local winwidth = vim.api.nvim_win_get_width(UI.windows.sidebar)
	local helptext = "press ? to toggle help"
    local hl = string.len(helptext) / 2
	local helpTextTable = {
		string.format("%+" .. winwidth / 2 - (hl) .. "s%s", "", helptext),
        " a - add a file in the select dir",
        " d - delete the select file",
        " "..UI.options.keybinds.activate_db.." - set the active db",
		" <C-t> - toggle sidebar focus",
        " "..UI.options.keybinds.execute_query.." - run query",
	}
	local setCursor = UI.last_cursor_position.sidebar
	local srow = 2


	if UI.help_toggled then
		UI.last_cursor_position.sidebar = vim.api.nvim_win_get_cursor(
            UI.windows.sidebar
        )
		vim.cmd("syn match SQLuaHelpKey /.*\\( -\\)\\@=/")
		vim.cmd("syn match SQLuaHelpText /\\(- \\).*/")
		vim.api.nvim_buf_set_lines(buf, 0, 0, false, helpTextTable)
		vim.cmd("syn match SQLuaHelpText /^$/")
		srow = srow + #helpTextTable
		vim.api.nvim_buf_add_highlight(
            UI.buffers.sidebar, UI.sidebar_ns, "Comment", 0, 0, winwidth
        )
		setCursor[1] = setCursor[1] + #helpTextTable
	else
		vim.api.nvim_buf_set_lines(buf, 0, 0, false, {
			string.format("%+" .. winwidth / 2 - (hl) .. "s%s", "", helptext),
		})
		vim.api.nvim_buf_add_highlight(
            UI.buffers.sidebar, UI.sidebar_ns, "Comment", 0, 0, winwidth
        )
	end

	vim.api.nvim_set_current_win(UI.windows.sidebar)
	for db, _ in Utils.pairsByKeys(UI.dbs) do
		local text = UI_ICONS.db .. db .. " (" .. UI.dbs[db].num_schema .. ")"
		if UI.dbs[db].expanded then
			printSidebarExpanded(buf, srow - 1, text, sep)
			srow = refreshOverview(buf, db, srow)
		else
			printSidebarCollapsed(buf, srow - 1, text, sep)
		end
		srow = srow + 1
		vim.api.nvim_buf_add_highlight(
            UI.buffers.sidebar,
            UI.sidebar_ns,
            "active_db",
            srow - 1, 10,
            string.len(db)
        )
	end
	if not pcall(function()
		vim.api.nvim_win_set_cursor(UI.windows.sidebar, setCursor)
	end) then
		vim.api.nvim_win_set_cursor(UI.windows.sidebar, {
			math.min(srow, UI.last_cursor_position.sidebar[1] - #helpTextTable),
			math.max(2, UI.last_cursor_position.sidebar[2]),
		})
	end
	highlightSidebarNumbers()
	setSidebarModifiable(buf, false)
end

---@param con Connection
---Adds the Connection object to the UI object
function UI:addConnection(con)
	-- local copy = vim.deepcopy(con)
	local db = con.name
	if UI.active_db == "" then
		UI.active_db = db
	end
	UI.dbs[db] = con
    UI.dbs[db].files = require("sqlua.files"):setup(db)
	UI.num_dbs = UI.num_dbs + 1
	setSidebarModifiable(UI.buffers.sidebar, false)
	-- UI:populateSavedQueries(db)
end

local function openFileInEditor(db, filename)
    local path = UI.dbs[db].files:find(filename).path
    local existing_buf = nil
    for _, buffer in pairs(UI.buffers.editors) do
        local name = vim.api.nvim_buf_get_name(buffer)
        if name == path then
            existing_buf = buffer
        end
    end
    if existing_buf then
        vim.api.nvim_win_set_buf(UI.windows.editors[1], existing_buf)
    else
        local buf = vim.api.nvim_create_buf(true, false)
        table.insert(UI.buffers.editors, buf)
        vim.api.nvim_buf_set_name(buf, path)
        vim.api.nvim_buf_call(buf, vim.cmd.edit)
        vim.api.nvim_win_set_buf(UI.windows.editors[1], buf)
    end
end

---@return nil
local function createSidebar()
	local win = UI.windows.sidebar
	local buf = vim.api.nvim_create_buf(true, true)
	vim.api.nvim_buf_set_name(buf, "Sidebar")
	vim.api.nvim_win_set_buf(win, buf)
	vim.api.nvim_set_current_win(win)
	vim.api.nvim_win_set_width(0, 40)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.api.nvim_set_option_value("wfw", true, { win = win })
	vim.api.nvim_set_option_value("wrap", false, { win = win })
	vim.api.nvim_set_option_value("number", false, { win = win })
	vim.api.nvim_set_option_value("cursorline", true, { win = win })
	vim.api.nvim_set_option_value("cursorlineopt", "line", { win = win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = win })
	vim.cmd("syn match Function /[פּ藺璘]/")
	vim.cmd("syn match String /[פּ󱁊]/")
	vim.cmd("syn match Boolean /[離]/")
	vim.cmd("syn match Comment /[]/")
	UI.buffers.sidebar = buf
	vim.api.nvim_set_keymap("n", "<C-t>", "", {
		callback = function()
			local curbuf = vim.api.nvim_get_current_buf()
			local sidebar_pos = UI.last_cursor_position.sidebar
			local editor_pos = UI.last_cursor_position.editor
			local result_pos = UI.last_cursor_position.result
			if not next(editor_pos) then
				editor_pos = { 1, 0 }
			end
			local _type, _ = getBufferType(curbuf)
			if _type == "sidebar" then
				local lastwin = UI.last_active_window
				vim.api.nvim_set_current_win(lastwin)
				local lastbuf, _ = getBufferType(UI.last_active_buffer)
				if lastbuf == "editor" then
					vim.api.nvim_win_set_cursor(lastwin, editor_pos)
				elseif lastbuf == "result" then
					vim.api.nvim_win_set_cursor(lastwin, result_pos)
				end
			elseif _type == "editor" or _type == "result" then
				local sidebarwin = UI.windows.sidebar
				vim.api.nvim_set_current_win(sidebarwin)
				vim.api.nvim_win_set_cursor(sidebarwin, sidebar_pos)
			end
		end,
	})
	vim.api.nvim_buf_set_keymap(buf, "n", "?", "", {
		callback = function()
			UI.last_cursor_position.sidebar = vim.api.nvim_win_get_cursor(
                UI.windows.sidebar
            )
			UI.help_toggled = not UI.help_toggled
			UI:refreshSidebar()
		end,
	})
	vim.api.nvim_buf_set_keymap(buf, "n", "R", "", {
		callback = function()
			UI.last_cursor_position.sidebar = vim.api.nvim_win_get_cursor(0)
			for _, con in pairs(UI.dbs) do
                local queries = require('sqlua.queries.postgres')
                local query = string.gsub(queries.SchemaQuery, "\n", " ")
                con:executeUv("refresh", query)
                con.files:refresh()
			end
			UI:refreshSidebar()
		end,
	})
    vim.api.nvim_buf_set_keymap(buf, "n", "a", "", {
        nowait = true,
        callback = function()
            local pos = vim.api.nvim_win_get_cursor(0)
			local text = vim.api.nvim_get_current_line()
            local is_folder = text:match("") ~= nil
            local is_file = text:match("") ~= nil
            if not is_folder and not is_file then
                return
            end
            local db, _ = sidebarFind("database", pos[1])
			text = text:gsub("%s+", "")
            text = text:gsub(ICONS_SUB, "")
            local file = UI.dbs[db].files:find(text)
            local parent_path = ""
            local show_path = ""
            if file == nil and text == "SavedQueries" then
                parent_path = Utils.concat({
                    vim.fn.stdpath("data"), "sqlua", db
                })
                show_path = parent_path
            else
                if file.isdir then
                    parent_path = file.path
                else
                    parent_path = file.path:match(".*/"):sub(1, -2)
                end
                show_path = parent_path:match(db..".*")
            end
            local newfile = vim.fn.input("Create file: "..show_path.."/")
            local save_path = Utils.concat({parent_path, newfile})
            vim.fn.writefile({}, save_path)
            UI.dbs[db].files:refresh()
            UI:refreshSidebar()
        end
    })
    vim.api.nvim_buf_set_keymap(buf, "n", "d", "", {
        nowait = true,
        callback = function()
            local pos = vim.api.nvim_win_get_cursor(0)
			local text = vim.api.nvim_get_current_line()
            local db, _ = sidebarFind("database", pos[1])
            local is_folder = text:match("") ~= nil
            local is_file = text:match("") ~= nil
            if not is_folder and not is_file then
                return
            end
			text = text:gsub("%s+", "")
            text = text:gsub(ICONS_SUB, "")
            if text == "SavedQueries" then
                return
            end
            local file = UI.dbs[db].files:find(text)
            local show_path = file.path:match(db..".*")
            local response = vim.fn.input("Are you sure you want to remove "..show_path.."? [Y/n]")
            if response == "Y" then
                assert(os.remove(file.path))
                UI.dbs[db].files:refresh()
                UI:refreshSidebar()
            end
        end
    })
	vim.api.nvim_buf_set_keymap(buf, "n", UI.options.keybinds.activate_db, "", {
		callback = function()
			local cursorPos = vim.api.nvim_win_get_cursor(0)
			local num = cursorPos[1]
			local db, _ = sidebarFind("database", num)
			UI.active_db = db
			vim.cmd("syn match SQLua_active_db /"..UI.active_db..".*$/")
			UI:refreshSidebar()
			vim.api.nvim_win_set_cursor(0, cursorPos)
		end,
	})
	-- expand and collapse
	vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "", {
		callback = function()
			local cursorPos = vim.api.nvim_win_get_cursor(0)
			local num_lines = vim.api.nvim_buf_line_count(UI.buffers.sidebar)
			local num = cursorPos[1]
			-- if on last line, choose value above
			if num == num_lines then
				local cursorCol = cursorPos[2]
				local newpos = { num - 1, cursorCol }
				vim.api.nvim_win_set_cursor(UI.windows.sidebar, newpos)
			end

			local val = vim.api.nvim_get_current_line()
			val = val:gsub("%s+", "")
			if val:find("%(") then
				val = val:sub(1, val:find("%(") - 1)
			end
			if val == "" then
				return
			end

			local is_collapsed, _ = string.find(val, "")
			local is_expanded, _ = string.find(val, "")
			if is_collapsed or is_expanded then
                local is_folder, _ = string.find(val, "")
				local db = nil
				db, _ = sidebarFind("database", num)
				val = val:gsub(ICONS_SUB, "")
				if db and db == val then
					toggleExpanded(UI.dbs, val)
				elseif val == "SavedQueries" then
					UI.dbs[db].files_expanded =
                        not UI.dbs[db].files_expanded
                elseif is_folder then
                    toggleExpanded(UI.dbs[db].files, val)
				else
					toggleExpanded(UI.dbs[db], val)
				end
				UI:refreshSidebar()
				vim.api.nvim_win_set_cursor(0, cursorPos)
			else
				local is_file, _ = string.find(val, "")
				if is_file then
					local file = val:gsub(ICONS_SUB, "")
					local db, _ = sidebarFind("database", num)
                    -- UI.dbs[db].files:find(file):open(buf)
					openFileInEditor(db, file)
				else
					local tbl = nil
					local schema = nil
					local db = nil
					tbl, _ = sidebarFind("table", num)
					schema, _ = sidebarFind("schema", num)
					db, _ = sidebarFind("database", num)
                    if tbl then
                        tbl = tbl:gsub(ICONS_SUB, "")
                    end
                    if schema then
                        schema = schema:gsub(ICONS_SUB, "")
                    end
                    if db then
                        db = db:gsub(ICONS_SUB, "")
                    end
					val = val:gsub(ICONS_SUB, "")
					if not tbl or not schema or not db then
						return
					end
					createTableStatement(val, tbl, schema, db)
				end
			end
			highlightSidebarNumbers()
		end,
	})
end

---@param win window
---@return nil
local function createEditor(win)
    local name = Utils.concat({
        vim.fn.stdpath("data"),
        "sqlua",
        "Editor_"..EDITOR_NUM
    })
	vim.api.nvim_set_current_win(win)
    -- TODO: change scratch to False and add autocmd
    -- to save the file
	local buf = vim.api.nvim_create_buf(true, true)
	vim.api.nvim_buf_set_name(buf, name)
	vim.api.nvim_win_set_buf(win, buf)
	vim.api.nvim_win_set_cursor(win, { 1, 0 })
	vim.cmd("setfiletype sql")
	table.insert(UI.buffers.editors, buf)
	if not UI.last_active_window or not UI.last_active_buffer then
		UI.last_active_buffer = buf
		UI.last_active_window = win
	end
	EDITOR_NUM = EDITOR_NUM + 1
end

---@param config table
---@return nil
function UI:setup(config)
	UI.options = config
	for _, buf in pairs(vim.api.nvim_list_bufs()) do
		vim.api.nvim_buf_delete(buf, { force = true, unload = false })
	end

	vim.api.nvim_set_keymap("", config.keybinds.execute_query, "", {
		callback = function()
            -- return if in sidebar or results
            local win = vim.api.nvim_get_current_win()
            local tobreak = true
            for _, w in pairs(UI.windows.editors) do
                if win == w then
                    tobreak = false
                end
            end
            local buf = vim.api.nvim_get_current_buf()
            for _, b in pairs(UI.buffers.editors) do
                if buf == b then
                    tobreak = false
                end
            end
            if tobreak then return end

			local mode = vim.api.nvim_get_mode().mode
            local db = UI.dbs[UI.active_db]
            if not db then
                print("No Active Connection")
            end
            db:execute(mode)
		end,
	})

	vim.api.nvim_create_autocmd({ "BufDelete", "BufHidden" }, {
		callback = function()
			local closed_buf = vim.api.nvim_get_current_buf()
			if not closed_buf == UI.buffers.sidebar then
				local bufs = vim.api.nvim_list_bufs()
				for _, buf in pairs(bufs) do
					if buf == closed_buf then
						vim.api.nvim_buf_delete(buf, { unload = true })
					end
				end
				EDITOR_NUM = EDITOR_NUM - 1
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "BufLeave" }, {
		callback = function()
			local curwin = vim.api.nvim_get_current_win()
			local curbuf = vim.api.nvim_get_current_buf()
			if UI.connections_loaded and UI.initial_layout_loaded then
				UI.last_active_buffer = curbuf
				UI.last_active_window = curwin
				local _type, _ = getBufferType(curbuf)
				if _type == nil then
					return
				end
				UI.last_cursor_position[_type] = vim.api.nvim_win_get_cursor(
                    curwin
                )
			else
				UI.last_cursor_position.sidebar = vim.api.nvim_win_get_cursor(
                    curwin
                )
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "WinNew" }, {
		callback = function(ev)
			local sidebar, _ = string.find(ev.file, "Sidebar")
			if ev.buf == 1 or sidebar then
				return
			end
			for _, value in pairs(UI.buffers.editors) do
				if value == ev.buf then
					return
				end
			end
			createEditor(vim.api.nvim_get_current_win())
		end,
	})
	vim.api.nvim_create_autocmd({ "CursorMoved" }, {
		callback = function(ev)
			if ev.buf ~= UI.buffers.sidebar then
				return
			end
			if not UI.initial_layout_loaded then
				return
			end
			local pos = vim.api.nvim_win_get_cursor(0)
			pos[1] = math.max(pos[1], 2)
			pos[2] = math.max(pos[2], 1)
            if next(UI.dbs) == nil then
                vim.api.nvim_win_set_cursor(0, {1, 0})
            else
                vim.api.nvim_win_set_cursor(0, pos)
            end
		end,
	})

	UI.sidebar_ns = vim.api.nvim_create_namespace("SQLuaSidebar")
	vim.api.nvim_set_hl(0, "SQLua_active_db", { fg = "#00ff00", bold = true })
	vim.api.nvim_set_hl(0, "SQLuaHelpKey", {
		fg = vim.api.nvim_get_hl(0, { name = "String" }).fg,
	})
	vim.api.nvim_set_hl(0, "SQLuaHelpText", {
		fg = vim.api.nvim_get_hl(0, { name = "Comment" }).fg,
	})

	local sidebar_win = vim.api.nvim_get_current_win()
	UI.windows.sidebar = sidebar_win
	vim.cmd("vsplit")
	local editor_win = vim.api.nvim_get_current_win()
	table.insert(UI.windows.editors, editor_win)

	createSidebar()
	createEditor(editor_win)
end

return UI

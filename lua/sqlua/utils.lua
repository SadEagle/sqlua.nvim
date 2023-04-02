local M = {}

---@param v table
---@return table v
---prints the content of a given table
P = function(v)
  print(vim.inspect(v))
  return v
end


RELOAD = function(...)
  return require("plenary.reload").reload_module(...)
end


R = function(name)
  RELOAD(name)
  return require(name)
end


local sep = (function()
  ---@diagnostic disable-next-line: undefined-global
  if jit then
      ---@diagnostic disable-next-line: undefined-global
      local os = string.lower(jit.os)
      if os == "linux" or os == "osx" or os == "bsd" then
          return "/"
      else
          return "\\"
      end
  else
      -- return string.sub(package.config, 1, 1)
  end
end)()


---@param path_components string[]
---@return string
function M.concat(path_components)
    return table.concat(path_components, sep)
end


---@param orig table
---@return table
---Creates a shallow copy of a given table
M.shallowcopy = function(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end


---@param str string string
---@param separator string delimiter
---@return string[]
---Splits string by given delimiter and returns an array
M.splitString = function(str, separator)
  if separator == nil then
    separator = "%s"
  end
  local t = {}
  for s in string.gmatch(str, "([^"..separator.."]+)") do
    table.insert(t, s)
  end
  return t
end


---@param arr table
---@param element any
---@return boolean
---Checks whether the given element is in the top level of the array/table
M.inArray = function(arr, element)
  for _, value in ipairs(arr) do
    if value == element then
      return true
    end
  end
  return false
end


---@param arr table
---@return table
---Returns a new table with duplicate values removed (top level only)
M.removeDuplicates = function(arr)
  local newArray = {}
  for _, element in ipairs(arr) do
    if not M.inArray(newArray, element) then
      table.insert(newArray, element)
    end
  end
  return newArray
end


---@param table table table to begin searching
---@param search_for any what to search for
---@param replacement any value to replace with
---@return nil
M.deepReplace = function(table, search_for, replacement)
  if not table then return end
  for key, value in pairs(table) do
    if type(value) == 'table' then
      M.deep_replace(value, search_for, replacement)
    else
      table[key] = value:gsub(search_for, replacement)
    end
  end
end


---@param line string
---@return string
---Trims leading and trailing whitespace
M.removeEndWhitespace = function(line)
  return line:gsub("^%s*(.-)%s*$", "%1")
end


---@param file table the connections.json file
---@return table content json table object
M.getDatabases = function(file)
  local content = vim.fn.readfile(file)
  content = vim.fn.json_decode(vim.fn.join(content, "\n"))
  return content
end


-- local parseUrl = function(url)
--   local db = string.gsub(
--     string.sub(url, string.find(url, "%w+:")),
--     "[:]", ""
--   )
--   local username = string.gsub(
--     string.sub(url, string.find(url, "//%w+:")),
--     "[/:]", ""
--   )
--   local password = string.gsub(
--     string.sub(url, string.find(url, ":[%w!@#%$%%%^&%*%(%)%-_=%+]+@")),
--     "[:@]", ""
--   )
--   local server = string.gsub(
--     string.sub(url, string.find(url, "@.+/")),
--     "[@/]", ""
--   )
--   local ip = ""
--   local port = ""
--   if server == "localhost" then
--     ip = "127.0.0.1"
--     port = "5432"
--   else
--     ip = string.sub(server, string.find(server, "+[:/]"))
--     port = string.sub(server, string.find(server, ":+"))
--   end
--   return {
--     db = db,
--     username = username,
--     password = password,
--     server = server,
--     ip = ip,
--     port = port
--   }
-- end

return M

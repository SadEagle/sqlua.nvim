local Connection = require("sqlua.connectors.base")
local utils = require("sqlua.utils")

---@class Mariadb : Connection
Mariadb = Connection:new()


function Mariadb:setup(name, url)
    ---@class Mariadb
    local s = Mariadb:new()
    s.name = name
    s.url = url
    s.dbms = "mysql"
    s.cmd = "mariadb"
    s.cli_args = {}
    s.connection_info = s:parseUrl()
    for k, v in pairs(s.connection_info) do
        if type(v) == "table" then
            if next(v) ~= nil then
                for _, item in pairs(v) do
                    table.insert(s.cli_args, " --"..item)
                end
            end
        elseif v ~= "" and k ~= "dbms" then
            table.insert(s.cli_args, "--"..k.."="..v)
        end
    end
    table.insert(s.cli_args, "-t") -- table output

    local queries = require("sqlua.queries."..s.dbms)
    s.schema_query = string.gsub(queries.SchemaQuery, "\n", " ")
    return s
end

function Mariadb:cleanSchema(data)
	local schema = utils.shallowcopy(data)
    table.remove(schema, 1)
    table.remove(schema, 1)
    table.remove(schema, 1)
    table.remove(schema)
    for i, _ in ipairs(schema) do
        schema[i] = string.gsub(schema[i], "%s", "")
        schema[i] = string.sub(schema[i], 2, -2)
        schema[i] = utils.splitString(schema[i], "|")
    end
    return schema
end

return Mariadb

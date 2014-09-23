--gist:c63fb3c8de9b976fd08b
local component = require("component")
local internet = require("internet")
local fs = require("filesystem")
local shell = require("shell")

if not component.isAvailable("internet") then
    io.stderr:write("This program requires an internet card to run.\n")
    return
end

local args, options = shell.parse(...)

if #args < 1 or #args > 2 then
    io.stderr:write("Invalid arguments\n")
    io.write("USAGE: gist [<gist id>] <file name>\n")
    io.write("If no gist id is given, and the file exists,\n")
    io.write("the program attempts to read the id on\n")
    io.write("the first line of the file in the following\n")
    io.write("format:\n")
    io.write("--gist:<gist id>\n")
    return
end

local path = shell.resolve(#args == 2 and args[2] or args[1])
local gistId = #args == 2 and args[1] or nil

if not gistId then
    io.write(string.format("No gist id given. Attempting to update \"%s\"\n", path))

    if not fs.exists(path) or fs.isDirectory(path) then
        io.stderr:write(string.format("\"%s\" does not exist or is not a file\n", path))
        return
    end

    local file, err = io.open(path, "r")

    if not file then
        io.stderr:write(string.format("Unable to open \"%s\" for reading: %s\n", path, err))
        return
    end

    local firstLine = string.gsub(file:read("*line") or "", "%s", "")
    file:close()

    local header, id = string.match(firstLine, "(--gist:)(%x+)")

    if not header or not id then
        io.stderr:write(string.format("Unable to read gist header from \"%s\"\n", path))
        return
    end

    io.write(string.format("Gist id found: %s\n", id))
    gistId = id
elseif not string.match(gistId, "^%x+$") then
    io.stderr:write(string.format("Invalid gist id: %s\n", gistId))
end

local tmppath = os.tmpname()
local file, err = io.open(tmppath, "w")
if not file then
    io.stderr:write(string.format("Unable to open  temporary file for writing: %s\n", err))
    return
end

io.write("Downloading from gist.github.com...")
local url = "https://gist.github.com/raw/" .. gistId

local result, response = pcall(internet.request, url)
if result then
    io.write("success\n")
    for chunk in response do
        string.gsub(chunk, "\r\n", "\n")
        file:write(chunk)
    end
    file:close()

    if fs.isDirectory(path) or (fs.exists(path) and not fs.remove(path)) or not fs.rename(tmppath, path) then
        io.stderr:write("Unable to save data to \"%s\"\n", path)
        return
    end

    io.write(string.format("Saved data to \"%s\"\n", path))
else
    io.write("failed.\n")
    f:close()
    fs.remove(tmppath)
    io.stderr:write(string.format("HTTP request failed: %s\n", response))
end
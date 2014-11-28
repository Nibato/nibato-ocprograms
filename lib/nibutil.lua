--gist:2cf8d094009635fe9c42
-----------------------------------------------------------------------------
-- Module declaration
-----------------------------------------------------------------------------
local nibutil = {}

-----------------------------------------------------------------------------
-- Public functions
-----------------------------------------------------------------------------

--- Generates a table from an existing table with the key/value pairs reversed
-- @param t The table to fetch key/value pairs from
-- a clone of t with the key/value pairs reversed
function nibutil.reverseKeysValues(t)
    local reverse = {}
    for k,v in pairs(t) do
        reverse[v] = k
    end

    return reverse
end

return nibutil
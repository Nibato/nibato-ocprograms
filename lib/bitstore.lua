--gist:254968e481fe50b2106b
local bitstore = {}
local metabitstore = {}

metabitstore.__index = function(t, k)
-- We only take numbers for keys
    k = tonumber(k)
    if not k then return nil end

    -- Calculate our "real" index
    local index = math.ceil((k * t.bitSize) / 32)

    -- Return nil if real index is out of bounds
    if index < 1 or index > #t.backstore then
        return nil
    end

    -- Calculate the position of the "fake" index
    local bitPos = (((k - 1) * t.bitSize) % 32)

    -- Extract and return the value at the "fake" index
    return bit32.extract(t.backstore[index], bitPos, t.bitSize)
end

metabitstore.__newindex = function(t, k, v)
-- We only take numbers for keys, and values
    k = tonumber(k)
    v = tonumber(v)
    assert(k, "key must be a number")
    assert(v, "value must be a number")

    -- Calculate our "real" index
    local index = math.ceil((k * t.bitSize) / 32)

    -- Throw an error if it's out of range
    assert(index >= 1 and index <= #t.backstore, "key out of bounds")

    -- Calculate the position of the "fake" index
    local bitPos = (((k - 1) * t.bitSize) % 32)

    -- Take our input value, make it fit in t.bitSize bits, and shift it to fit at it's "fake" index
    v = bit32.lshift((math.floor(v) % t.bitSize ^ 2), bitPos)

    -- Create a bitmask to erase the previous values at the "fake" index
    local bitmask = bit32.bor(bit32.lshift(0xFFFFFFFF, t.bitSize + bitPos), bit32.rshift(0xFFFFFFFF, 32 - bitPos))

    -- Apply the bitmask, and then insert out new value at the "fake" index
    t.backstore[index] = bit32.bor(bit32.band(t.backstore[index], bitmask), v)
end

-- Return our "fake" size
metabitstore.__len = function(t)
    return t.size
end

-- Loop through our "fake" values
metabitstore.__ipairs = function(t)
    return function(t, k)
        if not k then
            k = 1
        else
            k = k + 1
        end

        if k > #t then return nil end

        return k, t[k]
    end, t, nil
end

-- This table is only index based, so pairs() = ipairs()
metabitstore.__pairs = metabitstore.__ipairs

function bitstore.new(size, bitSize)
    -- argument checking
    bitSize = math.floor(tonumber(bitSize or 1))
    size = tonumber(size)
    -- this could probably handle arbitrary bitsizes, but it'd be wasteful, and it's not something i want to support
    assert(bitSize > 0 and 16 % bitSize == 0, "bitSize must be 1, 2, 4, 8, 16")
    assert(size, "size must be a number greater than zero")

    -- Setup our table
    local bs = {
        bitSize = bitSize,
        size = size,
        backstore = {}
    }

    -- allocate backstore, i wish there was a better way to do this in lua 5.2
    for i = 1, math.ceil((bs.size * bs.bitSize) / 32) do
        table.insert(bs.backstore, 0)
    end

    -- Attach and return the metatable
    return setmetatable(bs, metabitstore)
end

return bitstore
--gist:036f6139506ee782b39f
-----------------------------------------------------------------------------
-- Imports and dependencies
-----------------------------------------------------------------------------
local robot = require("robot")
local sides = require("sides")

-----------------------------------------------------------------------------
-- Module declaration
-----------------------------------------------------------------------------
local nibnav = {}

-----------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------

--- Lookup table for calculating turns. Also, I couldn't resist the name

nibnav.sideLookup = {
    -- Negative values are left turns, positive values are right turns
    turn = {
        [sides.north] = {
            [sides.south] = 2,
            [sides.east] = 1,
            [sides.west] = -1
        },
        [sides.south] = {
            [sides.north] = 2,
            [sides.east] = -1,
            [sides.west] = 1
        },
        [sides.east] = {
            [sides.north] = -1,
            [sides.south] = 1,
            [sides.west] = 2
        },
        [sides.west] = {
            [sides.north] = 1,
            [sides.south] = -1,
            [sides.east] = 2
        }
    },

    -- Translation table for turning a local direction into a cardinal/global direction
    translation = {
        [sides.north] = {
            [sides.front] = sides.north,
            [sides.back] = sides.south,
            [sides.left] = sides.west,
            [sides.right] = sides.east
        },
        [sides.south] = {
            [sides.front] = sides.south,
            [sides.back] = sides.north,
            [sides.left] = sides.east,
            [sides.right] = sides.west
        },
        [sides.east] = {
            [sides.front] = sides.east,
            [sides.back] = sides.west,
            [sides.left] = sides.north,
            [sides.right] = sides.south
        },
        [sides.west] = {
            [sides.front] = sides.west,
            [sides.back] = sides.east,
            [sides.left] = sides.south,
            [sides.right] = sides.north
        }
    },

    offsets = {
        [sides.down] = { 0, -1, 0 },
        [sides.up] = { 0, 1, 0 },
        [sides.north] = { 0, 0, -1 },
        [sides.south] = { 0, 0, 1 },
        [sides.west] = { -1, 0, 0 },
        [sides.east] = { 1, 0, 0 }
    },

    valid = { sides.down, sides.up, sides.north, sides.south, sides.west, sides.east }
}

-----------------------------------------------------------------------------
-- Persist data
-----------------------------------------------------------------------------
local _position = { x = 0, y = 0, z = 0, facing = sides.north }

-----------------------------------------------------------------------------
-- Private functions
-----------------------------------------------------------------------------

--- Runs a function, if it returns true, run another function
-- @param action a function to run that will return true or false/nil, and an optional
-- @param run the function that will be run if @action returns true
-- @param ... arguments to pass to run
-- @return returns true or nil, and the second argument that action returned
local function ifAction(action, run, ...)
    local ok, err = action()

    if ok then
        run(...)
    end

    return ok, err
end

--- Runs a function a certain amount of times, unless it returns nil or false
-- @param times number of times to run the function
-- @param action the function to run
-- @param ... arguments to pass to the function
-- @return returns true on success, or nil, and the second argument the function returned
local function repeatAction(times, action, ...)
    for i = 1, times do
        local ok, err = action(...)

        if not ok then
            return ok, err
        end
    end
    return true
end

--- Runs an action, if it returns nil or false, throw an error with it's second returned argument, if any
-- To be used inside of the function passed to protected()
-- @param action the function to run
-- @param ... arguments to pass to the function
local function tryAction(action, ...)
    local ok, err = action(...)
    if not ok then
        error(err, 0)
    end
end

--- Attempts to catch and return any errors thrown inside of the given function
-- @param body the function to run and catch errors from
-- @param ... arguments to pass to the function
-- @return true if no errors, otherwise returns nil, and the error message
local function protected(body, ...)
    local ok, err = pcall(body, ...)
    return ok or nil, err
end

-----------------------------------------------------------------------------
-- Public functions
-----------------------------------------------------------------------------

--- Turns the robot left
-- Use this and avoid robot.turnLeft() to keep track the robot's facing
-- @return true on success, or nil, and an optional error message
function nibnav.turnLeft()
    local newFacing = nibnav.sideLookup.translation[nibnav.getFacing()][sides.left]
    return ifAction(robot.turnLeft, function()
        _position.facing = newFacing
    end)
end

--- Turns the robot right
-- Use this and avoid robot.turnRight() to keep track the robot's facing
-- @return true on success, or nil, and an optional error message
function nibnav.turnRight()
    local newFacing = nibnav.sideLookup.translation[nibnav.getFacing()][sides.right]
    return ifAction(robot.turnRight, function()
        _position.facing = newFacing
    end)
end

--- Turns the robot around. This is the same as calling turnLeft or turnRight twice
-- Use this and avoid robot.turnAround() to keep track the robot's facing
-- @return true on success, or nil, and an optional error message
function nibnav.turnAround()
    local turn = math.random() < 0.5 and nibnav.turnLeft or nibnav.turnRight

    return protected(function()
        tryAction(turn)
        tryAction(turn)
    end)
end

--- Gets which way the robot is facing relative to it's tracking data
-- @returns A sides constant representing which way the robot is facing
function nibnav.getFacing() return _position.facing end

--- Returns which way a particular side of the robot is facing
-- For example, if the robot is facing north, passing sides.left would return sides.west
-- @param side The side of the robot
-- @returns The facing of the robot's side
function nibnav.getFacingFromSide(side)
    -- Don't translate up/down
    if side == sides.up or side == sides.down then
        return side
    end

    assert(side, "Invalid side")
    local facing = nibnav.getFacing()
    local lookup =  nibnav.sideLookup.translation[facing][side]
    assert(lookup, "Invalid side")

    return lookup
end

--- Gets the relative x, y, z position of the robot according to it's tracking data
-- @return 3 numbers representing the x, y, and z of the robot
function nibnav.getPosition() return _position.x, _position.y, _position.z end

--- Moves the robot forward one space
-- Use this and avoid robot.forward() to keep track the robot's position
-- @return true on success, or nil, and an optional error message
function nibnav.forward()
    return ifAction(robot.forward, function()
        local facing = nibnav.getFacing()
        if facing == sides.posx then _position.x = _position.x + 1
        elseif facing == sides.negx then _position.x = _position.x - 1
        elseif facing == sides.posz then _position.z = _position.z + 1
        elseif facing == sides.negz then _position.z = _position.z - 1
        end
    end)
end

--- Moves the robot back one space
-- Use this and avoid robot.back() to keep track the robot's position
-- @return true on success, or nil, and an optional error message
function nibnav.back()
    return ifAction(robot.back, function()
        local facing = nibnav.getFacing()
        if facing == sides.posx then _position.x = _position.x - 1
        elseif facing == sides.negx then _position.x = _position.x + 1
        elseif facing == sides.posz then _position.z = _position.z - 1
        elseif facing == sides.negz then _position.z = _position.z + 1
        end
    end)
end

--- Moves the robot up one space
-- Use this and avoid robot.up() to keep track the robot's position
-- @return true on success, or nil, and an optional error message
function nibnav.up()
    return ifAction(robot.up, function()
        _position.y = _position.y + 1
    end)
end

--- Moves the robot down one space
-- Use this and avoid robot.down() to keep track the robot's position
-- @return true on success, or nil, and an optional error message
function nibnav.down()
    return ifAction(robot.down, function()
        _position.y = _position.y - 1
    end)
end

--- Turns the robot to face the side constant. front/back/left/right are interpreted as south/north/west/east as per
-- the definition in the sides constant. The facing is relative to the robot's tracking data.
-- @param side the side the robot will turn to face
-- @return true on success, or nil, and an optional error message
function nibnav.faceSide(side)
    local oldSide = nibnav.getFacing()

    if (oldSide == side) then
        return true
    end

    local turn = nibnav.sideLookup.turn[oldSide] and nibnav.sideLookup.turn[oldSide][side]
    assert(turn, "Unable to face side: " .. side or "nil")

    return turn == 2 and nibnav.turnAround() or turn == -1 and nibnav.turnLeft() or turn == 1 and nibnav.turnRight()
end

--- Moves the robot in a direction a certain distance relative to his tracking data
-- @param direction The direction the robot will travel
-- @param distance The distance in blocks the robot will travel
-- @param wrapper Optional function to call inplace of the movement function. The default movement function will be
-- passed as the first argument. This function must return true or nil, and an optional error message
-- @return true on success, or nil, and an optional error message
function nibnav.move(direction, distance, wrapper)
    direction, distance = tonumber(direction), tonumber(distance)
    assert(direction and distance, "direction and distance must be a number")

    if distance <= 0 then
        return true
    end

    wrapper = wrapper or function(m) return m() end
    assert(type(wrapper) == "function", "wrapper must be a function")

    return protected(function()
        local moveFunc

        if direction == sides.up then
            moveFunc = nibnav.up
        elseif direction == sides.down then
            moveFunc = nibnav.down
        else
            assert(nibnav.sideLookup.turn[direction], "invalid direction")
            tryAction(nibnav.faceSide, direction)
            moveFunc = nibnav.forward
        end

        tryAction(repeatAction, distance, wrapper, moveFunc)
    end)
end

--- Makes the robot move along the X axis until he reaches a given X
-- @param x The X the robot will travel to
-- @param wrapper Optional function to call inplace of the movement function. The default movement function will be
-- passed as the first argument. This function must return true or nil, and an optional error message
-- @return true on success, or nil, and an optional error message
function nibnav.moveX(x, wrapper)
    x = tonumber(x)
    assert(x, "x must be a number")
    assert(wrapper == nil or type(wrapper) == "function", "wrapper must be a function")

    local ourX = nibnav.getPosition()
    return nibnav.move(ourX < x and sides.posx or sides.negx, math.abs(ourX - x), wrapper)
end

--- Makes the robot move along the Y axis until he reaches a given Y
-- @param y The Y the robot will travel to
-- @param wrapper Optional function to call inplace of the movement function. The default movement function will be
-- passed as the first argument. This function must return true or nil, and an optional error message
-- @return true on success, or nil, and an optional error message
function nibnav.moveY(y, wrapper)
    y = tonumber(y)
    assert(y, "y must be a number")
    assert(wrapper == nil or type(wrapper) == "function", "wrapper must be a function")

    local _, ourY = nibnav.getPosition()

    return nibnav.move(ourY < y and sides.up or sides.down, math.abs(ourY - y), wrapper)
end

--- Makes the robot move along the Z axis until he reaches a given Z
-- @param z The Z the robot will travel to
-- @param wrapper Optional function to call inplace of the movement function. The default movement function will be
-- passed as the first argument. This function must return true or nil, and an optional error message
-- @return true on success, or nil, and an optional error message
function nibnav.moveZ(z, wrapper)
    z = tonumber(z)
    assert(z, "z must be a number")
    assert(wrapper == nil or type(wrapper) == "function", "wrapper must be a function")

    local _, _, ourZ = nibnav.getPosition()
    return nibnav.move(ourZ < z and sides.posz or sides.negz, math.abs(ourZ - z), wrapper)
end

--- Makes the robot move along the Z and X axes until he reaches the given destination. The robot will attempt to move
-- on whichever axes he is already facing.
-- @param x The X the robot will travel to
-- @param z The Z the robot will travel to
-- @param wrapper Optional function to call inplace of the movement function. The default movement function will be
-- passed as the first argument. This function must return true or nil, and an optional error message
-- @return true on success, or nil, and an optional error message
function nibnav.moveXZ(x, z, wrapper)
    x, z = tonumber(x), tonumber(z)
    assert(x and z, "x and z must be a number")
    assert(wrapper == nil or type(wrapper) == "function", "wrapper must be a function")

    return protected(function()
        local _, _, ourZ = nibnav.getPosition()
        local zFacing = ourZ < z and sides.posz or sides.negz
        if zFacing == nibnav.getFacing() then
            tryAction(nibnav.moveZ, z, wrapper)
            tryAction(nibnav.moveX, x, wrapper)
        else
            tryAction(nibnav.moveX, x, wrapper)
            tryAction(nibnav.moveZ, z, wrapper)
        end
    end)
end

--- Setings the robots position and facing in the tracking data. Note that this does not physically move the robot.
-- This is useful for loading position and facing from the navigation component, resetting the robot's origin, etc.
-- @param x The X position of the robot
-- @param y The Y position of the robot
-- @param z The Z position of the robot
-- @param facing a sides constant representing the direction the robot is facing
function nibnav.setPosition(x, y, z, facing)
    x, y, z, facing = tonumber(x), tonumber(y), tonumber(z), tonumber(facing)
    assert(x and y and z, "Invalid x,y,z")
    assert(nibnav.sideLookup.turn[facing], "Invalid facing")
    _position.x, _position.y, _position.z = x, y, z
    _position.facing = facing
end

--- Gets the euclidean distance between two 3 dimensional points
-- @param x1 The X of the first point
-- @param y1 The Y of the first point
-- @param z1 The Z of the first point
-- @param x2 The X of the second point
-- @param y2 The Y of the second point
-- @param z2 The Z of the second point
-- @return The distance between the two points
function nibnav.distance(x1, y1, z1, x2, y2, z2)
    return math.sqrt(nibnav.distancesq(x1, y1, z1, x2, y2, z2))
end

--- Gets the squared (or manhattan) distance between two 3 dimensional points
-- @param x1 The X of the first point
-- @param y1 The Y of the first point
-- @param z1 The Z of the first point
-- @param x2 The X of the second point
-- @param y2 The Y of the second point
-- @param z2 The Z of the second point
-- @return The squared distance between the two points
function nibnav.distancesq(x1, y1, z1, x2, y2, z2)
    return math.abs(x1 - x2) + math.abs(y1 - y2) + math.abs(z1 - z2)
end

--- Gets the position of the six neighboing blocks of a point
-- @param x The origin X to get the neighbors of
-- @param y The origin Y to get the neighbors of
-- @param z The origin Z to get the neighbors of
-- @return A list of x, y, z, and sides constant for each neighbor describing its direction in relation to the origin
function nibnav.getBlockNeighbors(x, y, z)
    return {
        { x - 1, y, z, sides.negx },
        { x + 1, y, z, sides.posx },
        { x, y, z - 1, sides.negz },
        { x, y, z + 1, sides.posz },
        { x, y - 1, z, sides.negy },
        { x, y + 1, z, sides.posy }
    }
end

--- Uses the A* search algorithm to pathfind from a starting point to a goal
-- @param sX The starting point's X
-- @param sY The starting point's Y
-- @param sZ The starting point's Z
-- @param gX The goal point's X
-- @param gY The goal point's Y
-- @param gZ The goal point's Z
-- @param getCost A required function that is run on each node to calculate it's cost.
--      it is called with the following arguments:
--      getWeight(nodeX, nodeY, nodeZ, nodeData, fromX, fromY, fromZ, fromData)
--      node is the node to calculate the cost for
--      from is the node we came from to get to the one we're calculating the cost for
--      If this function returns nil, this node will be ignored and considered impassable.
--      See below pathfind() for an example function
-- @param getNeighbors An optional function that returns a list of neighbors a given X, Y, Z, and Data
--      it is called with the following arguments:
--      getNeighbors(x, y, z, data)
--      and is expected to return an array of tables containing { x, y, z, data }
--      Data can be anything you want, including nil. It is for your own use with the callbacks for your function
--      if getNeighbors is not provided, getBlockNeighbors() will be used by default
-- @param sData The optional data for the starting node.
-- @return an ordered array of tables containing { x, y, z, data } for each node that needs to be visited
-- to get to the the goal

function nibnav.pathfind(sX, sY, sZ, gX, gY, gZ, getCost, getNeighbors, sData)
    sX, sY, sZ = tonumber(sX), tonumber(sY), tonumber(sZ)
    gX, gY, gZ = tonumber(gX), tonumber(gY), tonumber(gZ)
    assert(sX and sY and sZ and gX and gY and gZ, "sX, sY, sZ, eX, eY, and eZ must be numbers")
    assert(type(getCost) == "function", "getWeight must be a function")
    getNeighbors = getNeighbors or nibnav.getBlockNeighbors
    assert(type(getNeighbors) == "function", "getNeighbors must be a function")

    -- ["x,y,z"] = x, y, z, gScore, fScore, userData (can be anything, for use with callbacks)
    local sKey = string.format("%d,%d,%d", sX, sY, sZ)
    local open = {
        [sKey] = { sX, sY, sZ, 0, nibnav.distancesq(sX, sY, sZ, gX, gY, gZ), sData }
    }
    local closed = {}
    local visited = {
        [sKey] = { sX, sY, sZ, sData, nil }
    }

    while true do
        local cKey, current

        -- find the best node in the open set
        do
            local fScore = math.huge
            for key, node in pairs(open) do
                if node[5] < fScore then
                    cKey = key
                    current = node
                    fScore = node[5]
                end
            end
        end

        -- node nodes left, we failed to find the goal
        if not current then
            break
        end

        -- we found the goal
        if current[1] == gX and current[2] == gY and current[3] == gZ then
            local path = {}
            local x, y, z, data
            local key = cKey

            repeat
                x, y, z, data, key = table.unpack(visited[key])
                table.insert(path, 1, { x, y, z, data })
            until not visited[key]

            return path
        end

        -- remove node from open set, add to closed set
        open[cKey] = nil
        closed[cKey] = current

        -- scan neigbhors
        for _, nPos in ipairs(getNeighbors(current[1], current[2], current[3], current[6])) do
            local x, y, z, data = table.unpack(nPos)
            local nKey = string.format("%d,%d,%d", x, y, z)

            local cost = getCost(x, y, z, data, current[1], current[2], current[3], current[6])
            if cost then
                local gScore = current[4] + cost

                -- this neighbor has a better gScore then the current node
                -- add it to the open set or update its gScore if it's already there
                if not closed[nKey] and (not open[nKey] or gScore < open[nKey][4]) then
                    visited[nKey] = { x, y, z, data, cKey }
                    open[nKey] = { x, y, z, gScore, gScore + nibnav.distancesq(x, y, z, gX, gY, gZ), data }
                end
            end
        end
    end
end


--[[ Example getCost function for use with pathfind(). This example assuming that getBlockNeighbors() was passed.
local moveCost = <How much energy a robot consumes while moving>
local turnCost = <How much energy a robot consumes while turning>
local grid = <A 3D array where 1 is a solid block and 0 is an empty block>
local function getCost(x, y, z, facing, _, _, _, prevFacing)
    -- Check to see if this block is out of range or impassable
    if not grid[x] or not grid[x][y] or not grid[x][y][z] or grid[x][y][z] == 1 then
        return -- returns nil to ignore it in the pathfinding search
    end

    local cost = moveCost

    -- If we have to turn, then add the turn cost
    if facing ~= prevFacing and nibnav.sideLookup.turn[prevFacing] and nibnav.sideLookup.turn[prevFacing][facing] then
        cost = cost + math.abs(nibnav.sideLookup.turn[prevFacing][facing])
    end

    -- Return the cost to move to this node
    return cost
end
]]

return nibnav
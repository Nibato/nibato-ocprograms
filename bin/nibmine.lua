--gist:77db85f518078c148421
-- WARNING: heavy work in progress. this code will be ugly and hacktastic

-- libraries
local robot = require("robot")
local computer = require("computer")
local sides = require("sides")
local nav = require("nibnav")
local component = require("component")
local bitstore = require("bitstore")

-- components
local inv = component.inventory_controller
local chunkloader = component.chunkloader

-- settings
local lowToolCharge = 0.20 -- what percentage of tool power to trigger resupply
local lowEnergy = 0.30 -- what percentage of power to trigger resupply
local lowItemSpace = 3 -- resupply when we have less than or equal to this many free item slots
local torchSpacing = 8 -- how far apart we attempt to place torches
local swingRetries = 20 -- how many times we attempt to retry a failed swing (punching entities, digging blocks, etc)

-- These positons will always be considered walls when pathfinding
local navBlacklist =
{
    { -1, 0 },
    { 1, 0 },
    { 0, 1 }
}

-- references, dont edit these
local lastBlackListSlot = 0
local torchSlot
local lastTorchSlot
local navMap

-- To be used with try(). if no errors are thrown, returns the first two returned results, otherwise returns nil, error
local function protected(func, ...)
    local ok, arg1, arg2 = pcall(func, ...)

    if ok then
        return arg1, arg2
    else
        return nil, arg1
    end
end

-- Runs func, if it returns false, throw it's second argument as an error
local function try(func, ...)
    local ok, err = func(...)

    if not ok then
        error(err, 0)
    end
end

-- Rotates an x,y pair by 90 degrees count amount of times
local function rotateXY(x, y, count)
    for _ = 1, count do
        local t = x
        x = -y
        y = t
    end

    return x, y
end

-- Generates a navigation map for the branch mine
local function genMap(centerSize, branchCount, branchSpacing)
    local branchLength = ((branchSpacing + 1) * (branchCount)) - (1 + centerSize)
    local size = 1 + centerSize + branchLength

    -- Allocate a 2-bit bitstore, and default all values to 0, which represent walls
    local map = bitstore.new(size * size, 1, 0)

    -- Setup our access functions
    function map.rawget(x, y)
        return x <= size and map[((y - 1) * size) + x]
    end

    function map.rawset(x, y, v)
        if x > size then return end
        map[((y - 1) * size) + x] = v
    end


    function map.get(x, y)
        -- Figure out which map quadrant we're in
        local quad
        if x > 0 then
            quad = y > 0 and 0 or 1
        else
            quad = y > 0 and 3 or 2
        end

        -- Normally we'd offset our origin, but
        -- we want to translate our coordinates so that 0,0 is the new origin
        local rX, rY = x, y

        -- Rotate by 90 degrees until we reach our quadrant
        for _ = 1, quad do
            local t = -rX
            rX = -rY
            rY = t
        end

        -- Get the absolute value
        rX = math.abs(rX)
        rY = math.abs(rY)

        -- re-add our origin, and return
        return map.rawget(rX + 1, rY + 1)
    end

    -- Dig out the center room
    for y = 1, centerSize + 1 do
        for x = 1, centerSize + 1 do
            map.rawset(x, y, 1)
        end
    end

    -- This table will hold all of the waypoints for digging
    map.waypoints = {}

    -- 1 + centerSize = the corner of the center room
    local start = 1 + centerSize
    local max = size
    local nextBranch = (start + branchSpacing) - centerSize
    for y = start + 1, max do
        -- See if we dig a branch at this Y
        if y >= nextBranch then
            -- Dig out branch
            for x = start + 1, max do map.rawset(x, y, 1) end

            -- Create waypoints
            table.insert(map.waypoints, { start - 1, y - 1 })
            table.insert(map.waypoints, { max - 1, y - 1 })

            -- We have room for another branch, dig down and do a u turn
            local yNext = y + branchSpacing + 1
            if yNext <= max then
                for yU = 1, branchSpacing do
                    map.rawset(max, y + yU, 1)
                end

                -- Dig out the next new shaft in reverse
                for x2 = max, start + 1, -1 do
                    map.rawset(x2, yNext, 1)
                end

                -- Create waypoint
                table.insert(map.waypoints, { max - 1, yNext - 1 })
                table.insert(map.waypoints, { start - 1, yNext - 1 })

                -- Set the y of our next branch
                nextBranch = yNext + branchSpacing + 1
            else
                -- We won't be able to fit another branch in, stop digging and move back to main shaft
                table.insert(map.waypoints, { start - 1, y - 1, true })
                nextBranch = nil
            end
        end

        -- Dig main shaft
        map.rawset(start, y, 1)

        -- No more branches, quit digging the main shaft
        if not nextBranch then
            break
        end
    end

    -- Insert a copy of our first waypoint, so we dig out the "main" shaft completely on our way back
    table.insert(map.waypoints, map.waypoints[1])

    -- Insert a waypoint for the resupply
    table.insert(map.waypoints, { 0, 0 })

    -- store map info
    map.size = (size * 2) - 2
    map.rawSize = size
    map.branchLength = branchLength
    map.branchSpacing = branchSpacing
    map.branchCount = branchCount
    map.centerSize = centerSize

    return map
end

local function checkResupply()
    if (computer.energy() / computer.maxEnergy()) <= lowEnergy then return nil, "low energy" end

    local durability, _, maxDurability = robot.durability()
    if not durability then return nil, "invalid tool" end
    if (durability / maxDurability) <= lowToolCharge then return nil, "low tool charge" end


    local freeSlots = 0
    for i = 1, robot.inventorySize() do
        if robot.count(i) <= 0 then
            freeSlots = freeSlots + 1
        end
    end

    if freeSlots <= lowItemSpace then return nil, "low item space" end

    return true
end

-- Place tool in inventory beneath the robot, wait for it to charge, and pick it back up
local function chargeTool()
    return protected(function()
        local durability, _, maxDurability = robot.durability()

        if not durability then return nil, "invalid tool" end
        if durability >= (maxDurability - 1) then return true end

        if inv.getInventorySize(sides.front) ~= 2 then return nil, "wrong inventory size for batbox" end

        try(robot.select, torchSlot)
        try(inv.equip)


        try(inv.dropIntoSlot, sides.front, 1)
        local tool
        repeat
            os.sleep(1)
            tool = inv.getStackInSlot(sides.front, 1)
            if not tool then return nil, "tool disappeared from batbox" end
        until tool.charge >= tool.maxCharge

        try(inv.suckFromSlot, sides.front, 1)
        try(inv.equip)

        return true
    end)
end

-- marks all items between the second slot and the next slot matching the first slot as blacklisted
-- ignores duplicates
local function setupBlackList()
    lastBlackListSlot = 0
    for i = 1, robot.inventorySize() do
        robot.select(i)
        local item = inv.getStackInSlot(sides.back, i)

        if item and item.size > 0 then
            -- see if this item is already in the black list
            local ignore
            for j = 1, i - 1 do
                if robot.compareTo(j) then
                    ignore = true
                    break
                end
            end

            -- add item to black list
            if not ignore then
                lastBlackListSlot = lastBlackListSlot + 1
                robot.transferTo(lastBlackListSlot)

                -- Torch signifies the end of the blacklist
                if item.name == "tile.torch" then
                    torchSlot = lastBlackListSlot
                    break
                end
            end
        end
    end

    if not torchSlot then
        return nil, "no torch found, unable to determine blacklist"
    end

    return true
end

-- consolidates all item stacks in inventory to try and free up slots
local function consolidateItems()
    local i = 1
    local lastOccupiedSlot = robot.inventorySize()
    while i <= lastOccupiedSlot do
        local lastScannedSlot

        for j = i + 1, lastOccupiedSlot do
            robot.select(j)
            if robot.count(i) <= 0 then
                robot.transferTo(i)
            elseif robot.space(i) == 0 then
                lastScannedSlot = nil
                break
            elseif robot.compareTo(i) then
                robot.transferTo(i, math.min(robot.space(i), robot.count(j)))
            end

            if robot.count(j) > 0 then
                lastScannedSlot = j
            end
        end

        -- We couldn't find any items to fill this empty slot, so we're done
        if robot.count(i) <= 0 then
            break
        end

        if lastScannedSlot then
            lastOccupiedSlot = lastScannedSlot
        end

        i = i + 1
    end
end


-- Drops all items that are on the blacklist, leaving a single item in each black list slot
-- Returns the number of stacks/slots that were dropped
local function dropItems(trashOnly, keepTrying)
    local function tryDrop(saveOne)
        local ok

        while true do
            local count = robot.count() - (saveOne and 1 or 0)

            if count <= 0 then
                return true
            end

            ok = robot.drop(count)

            if not ok then
                if keepTrying then
                    os.sleep(1)
                else
                    break
                end
            end
        end

        return ok
    end

    local dropped = 0
    for i = 2, robot.inventorySize() do
        robot.select(i)

        -- Don't drop torches
        if not robot.compareTo(torchSlot) then
            -- This item is on the black list, leave at least 1
            if i >= 1 and i <= lastBlackListSlot then
                tryDrop(true)
            else
                if trashOnly then
                    for j = 1, lastBlackListSlot do
                        if robot.compareTo(j) then
                            if tryDrop() then
                                dropped = dropped + 1
                            end
                            break
                        end
                    end
                else
                    if tryDrop() then
                        dropped = dropped + 1
                    end
                end
            end
        end
    end

    return dropped
end

local function getTorches()
    local torch = inv.getStackInSlot(sides.back, torchSlot)

    if not torch then
        return false
    end

    -- how many torches we need
    local required = (navMap.branchLength * (navMap.branchCount + 2)) / torchSpacing

    -- how many torches we have, start at negative one because we always need on in the first slot
    local count = -1
    local emptySlot
    for i = 1, robot.inventorySize() do
        robot.select(i)

        if robot.compareTo(torchSlot) then
            count = count + robot.count()
        end

        -- Keep track of the first free inventory slot we found
        if not emptySlot and robot.count() <= 0 then
            emptySlot = i
        end
    end


    -- Only grab more torches if we have inventory space
    if emptySlot then
        local attempts = 0
        while attempts < 3 and count < required do
            -- Scan the chest
            for i = 1, inv.getInventorySize(sides.front) do
                local item = inv.getStackInSlot(sides.front, i)

                -- Check to see if this item is a torch
                if item and item.id == torch.id then

                    -- select empty inventory slot
                    for j = emptySlot or 1, robot.inventorySize() do
                        robot.select(j)
                        if robot.count() <= 0 then
                            emptySlot = j
                            break
                        end
                    end

                    -- pull torches into that slot
                    if inv.suckFromSlot(sides.front, i) then
                        count = count + item.size
                    end
                end

                -- We have enough torches
                if count >= required then
                    break
                end
            end

            attempts = attempts + 1
            os.sleep(1)
        end
    end

    -- drop any extra torches
    if count > required then
        for i = 1, robot.inventorySize() do
            robot.select(i)
            if robot.compareTo(torchSlot) then
                local dropAmount = math.min(count - required, robot.count() - (i == torchSlot and 1 or 0))
                robot.drop(dropAmount)
                count = count - dropAmount

                if count <= required then
                    break
                end
            end
        end
    end

    return true
end


local function placeTorch()
    if not lastTorchSlot then
        lastTorchSlot = torchSlot
    end

    robot.select(lastTorchSlot)

    if (torchSlot == lastTorchSlot and robot.count() <= 1) or robot.count() <= 0 then
        local found

        for i = 1, robot.inventorySize() do
            robot.select(i)
            if robot.compareTo(torchSlot) then
                if (i == torchSlot and robot.count() > 1) or
                        (i ~= torchSlot and robot.count() > 0)
                then
                    found = true
                    lastTorchSlot = i
                    break
                end
            end
        end

        if not found then
            return nil, "no torches found"
        end
    end

    return robot.placeDown()
end

local function digMove(move)

    return protected(function()
        local detect
        local swing

        if move == nav.up then
            detect = robot.detectUp
            swing = robot.swingUp
        elseif move == nav.down then
            detect = robot.detectDown
            swing = robot.swingDown
        elseif move == nav.forward or move == nav.back then
            detect = robot.detect
            swing = robot.swing
        else
            error("invalid movement function", 2)
        end

        local count = 0
        while true do
            if move ~= nav.back or count > 0 then

                -- Special case for backing up, we turn around to punch what was behind us
                if move == nav.back then try(nav.turnAround) end

                local failCount = 0
                while detect() do
                    if not swing() then
                        failCount = failCount + 1

                        if failCount > swingRetries then
                            return nil, "failed swing"
                        end
                    end
                end

                -- turn back around to face our original position
                if move == nav.back then try(nav.turnAround) end
            end

            local ok, err = move()

            -- If we had no issues moving, we're done
            if ok then
                return true
                -- If it's something that punching won't fix, we failed and we're done :(
            elseif err == "impossible move" or err == "not enough energy" then
                return nil, err
            end

            count = count + 1
        end
    end)
end

local function detectOre(side)
    side = side or sides.front
    local detect = component.robot.detect
    local compare = component.robot.compare
    local swing = component.robot.swing

    local ok, type = detect(side)
    if not ok then return nil end

    -- Keep punching any entites in our way
    while type == "entity" do
        swing(side)
        ok, type = detect(side)

        if not ok then return nil end
    end

    -- See if this block is on the black list
    for i = 1, lastBlackListSlot do
        robot.select(i)
        if compare(side, i) then
            return nil
        end
    end

    return true
end

local function checkOre(ignoreFront, ignoreUp, ignoreDown)
    return protected(function()
    -- check sides
        for i = 1, 4 do
            if i ~= 1 or not ignoreFront then
                -- Dig any detected ore
                if detectOre() then
                    -- Graceful failure if we can't dig the ore out
                    if digMove(nav.forward) then
                        try(checkOre)
                        try(digMove, nav.back)
                    end
                end
            end
            try(nav.turnLeft)
        end

        -- check up
        if not ignoreUp and detectOre(sides.up) then
            if digMove(nav.up) then
                try(checkOre)
                try(digMove, nav.down)
            end
        end

        -- check down
        if not ignoreDown and detectOre(sides.down) then
            if digMove(nav.down) then
                try(checkOre)
                try(digMove, nav.up)
            end
        end

        return true
    end)
end

local function initResupply()
    if robot.inventorySize() <= 0 then return nil, "robot must have at least one inventory upgrade" end

    -- figure out which side of our resupply is the exit
    local exit
    for i = 1, 4 do
        if not robot.detect() then
            if exit then return nil, "resupply setup is invalid" end
            exit = nav.getFacing()
        end

        if i ~= 4 then
            nav.turnRight()
        end
    end

    if not exit then return nil, "resupply setup is invalid" end

    -- Reset our navigation data
    try(nav.faceSide, exit)
    nav.setPosition(0, 0, 0, sides.north)

    return true
end

local function getMoveCost(x, y, z, dir, _, _, _, oldDir)
    -- We work on a 2d plane, so reject any y but 0
    -- Also reject any walls for pathing consideration
    if y ~= 0 or navMap.get(x, z) ~= 1 then return nil end

    -- Look for any extra walls in the blacklist
    for _, v in pairs(navBlacklist) do
        if x == v[1] and z == v[2] then
            return nil
        end
    end

    -- 1.5 for moving with a 0.25 penalty for turning
    return 1.5 + (dir ~= oldDir and 0.25 or 0)
end

local function moveTo(x, z)
    return protected(function()
        print(string.format("Heading to %d, %d", x, z))
        local sX, _, sZ = nav.getPosition()

        local paths = nav.pathfind(sX, 0, sZ, x, 0, z, getMoveCost)

        if not paths then
            return false, "no path found"
        end

        try(nav.moveY, 0, digMove)
        for i = 2, #paths do
            local x, _, z = table.unpack(paths[i])
            try(nav.moveXZ, x, z, digMove)
        end

        return true
    end)
end

local function doResupply(noGetItems)
    return protected(function()
        local x, y, z = nav.getPosition()
        local facing = nav.getFacing()

        -- Move to our resupply
        try(moveTo, 0, 0)

        -- Face tool charger and charge
        print("Charging tool")
        try(nav.faceSide, sides.east)
        try(chargeTool)

        -- Face chest and drop off load, resupply torches
        try(nav.faceSide, sides.west)
        print("Unloading items")
        try(dropItems, false, true)

        if not noGetItems then
            print("Resupplying torches")
            try(getTorches)
            consolidateItems()
        end

        -- Wait for our energy to get full
        try(nav.faceSide, sides.north)
        print("Charging self")
        while computer.energy() < (computer.maxEnergy() * 0.99) do
            os.sleep(1)
        end

        -- Move back to our last position/facing
        try(moveTo, x, z)
        try(nav.faceSide, facing)
        try(nav.moveY, y, digMove)

        return true
    end)
end

local function main()
    -- Start going through our branches
    local ok, err = protected(function()
        navMap = genMap(2, 10, 3)

        if component.isAvailable("chunkloader") then
            print("Enabling chunkloader")
            chunkloader.setActive(true)
        end

        try(initResupply)
        try(setupBlackList)

        for quad = 0, 3 do
            -- Force a resupply at the start of each quadrant
            try(doResupply)

            print("Starting quadrant: " .. quad)

            local lastTorch = 0

            -- Loop through our waypoints for this map
            for wp = 1, #navMap.waypoints do
                local gX, gZ, noOre = table.unpack(navMap.waypoints[wp])

                -- Make sure we're at y = 0 if we aren't digging ore
                if noOre then try(nav.moveY, 0, digMove) end

                gX, gZ = rotateXY(gX, gZ, quad)
                local sX, _, sZ = nav.getPosition()

                print(string.format("Heading to %d, %d", gX, gZ))
                local paths = nav.pathfind(sX, 0, sZ, gX, 0, gZ, getMoveCost)
                if not paths then
                    error("unable to create path")
                end

                for i = 2, #paths do
                    -- Check if we need to resupply
                    if not checkResupply() then
                        print("Emergency resupply")
                        try(doResupply)
                    end

                    local x, _, z = table.unpack(paths[i])
                    try(nav.moveXZ, x, z, digMove)
                    lastTorch = lastTorch + 1

                    -- Check for ore, ignore the front since we dig it out regardless
                    -- Don't check for ore in the center room though
                    if not noOre and (math.abs(x) > navMap.centerSize or math.abs(z) > navMap.centerSize) then
                        local _, y, _ = nav.getPosition()

                        -- Do an up/down zig-zag alternation when mining
                        if y == 0 then
                            -- Top position
                            try(checkOre, x ~= gX or z ~= gZ, false, true)
                            try(digMove, nav.down)
                        else
                            -- Bottom position
                            try(checkOre, x ~= gX or z ~= gZ, true, false)
                            try(digMove, nav.up)

                            if lastTorch >= torchSpacing then
                                placeTorch() --Don't catch/throw errors for torches, it isn't a big deal
                                lastTorch = 0
                            end
                        end

                        try(checkOre, x ~= gX or z ~= gZ)
                    end
                end

                try(nav.moveY, 0, digMove)
            end
        end
    end)

    if not ok then
        print("FATAL ERROR: " .. (err or "unknown"))
    end

    nav.moveY(0, digMove)
    moveTo(0,0)
    doResupply(true)

    print("Done")

    if component.isAvailable("chunkloader") then
        print("Disabling chunkloader")
        component.chunkloader.setActive(false)
    end
end

main()
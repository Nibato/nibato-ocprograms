--gist:bb274dc8d35e12eefccc
-----------------------------------------------------------------------------
-- Imports and dependencies
-----------------------------------------------------------------------------
local component = require("component")
local robot = require("robot")
local sides = require("sides")

local inv = component.inventory_controller

-----------------------------------------------------------------------------
-- Module declaration
-----------------------------------------------------------------------------
local nibinv = {}
nibinv.robot = {}

-----------------------------------------------------------------------------
-- Private functions
-----------------------------------------------------------------------------

--- Verifies if an item matches the given description
-- @param item Item to check, must be a table returned from an
-- inventory_controller component
-- @param label Localized item name, or nil not comparing
-- @param name Unlocalized item name, or nil not comparing
-- @param metadata Item Metadata/damage value, or nil not comparing
-- @return true if item matches description, otherwise nil
local function itemMatches(item, label,  name, metadata)
    if not item then return end
    local nameMatches, metadataMatches, labelMatches

    nameMatches = name and item.name == name or not name
    metadataMatches = metadata and item.damage == metadata or not metadata
    labelMatches = label and item.label == label or not label

    return nameMatches and metadataMatches and labelMatches
end

-----------------------------------------------------------------------------
-- Public functions
-----------------------------------------------------------------------------

--- Verifies if an item in a particular slot matches the given description
-- @param side Side to check. Back = self
-- @param slot Slot to check
-- @param label Localized item name, or nil not comparing
-- @param name Unlocalized item name, or nil not comparing
-- @param metadata Item Metadata/damage value, or nil not comparing
-- @return true if item matches description, otherwise nil
function nibinv.slotMatches(side, slot, label, name, metadata)
    local item = inv.getStackInSlot(side, slot)
    return itemMatches(item, label, name, metadata)
end

--- Generates an iterator that loops through items
-- @param side Side to check. Back = self
-- @param slot Slot to check
-- @param label Localized item name, or nil not comparing
-- @param name Unlocalized item name, or nil not comparing
-- @param metadata Item Metadata/damage value, or nil not comparing
-- @return An iterator that returns slot, item for every slot that contains an item
function nibinv.items(side, label, name, metadata)
    local i = 0
    local max = inv.getInventorySize(side)

    return function()
        while i < max do
            i = i + 1
            local item = inv.getStackInSlot(side, i)
            if item and itemMatches(item, label, name, metadata) then
                return i, item
            end
        end
    end
end

--- Checks to see if an inventory contains an item matching the given description
-- @param side Side to check. Back = self
-- @param label Localized item name, or nil not comparing
-- @param name Unlocalized item name, or nil not comparing
-- @param metadata Item Metadata/damage value, or nil not comparing
-- @return Returns the slot the found item was in, and a table describing the item
function nibinv.hasItem(side, label, name, metadata)
    return nibinv.items(side, label, name, metadata)()
end

---
-- @param side Side to check. Back = self
-- @param label Localized item name, or nil not comparing
-- @param name Unlocalized item name, or nil not comparing
-- @param metadata Item Metadata/damage value, or nil not comparing
-- @return Returns the total number of items found that match the description
function nibinv.getTotal(side, label, name, metadata)
    local count = 0
    for _, item in nibinv.items(side, label, name, metadata) do
        count = count + item.size
    end
    return count
end

--- Finds the first empty inventory slot
-- @param side Side to check. Back = self
-- @param start Slot number to start at when scanning. 1 by default
-- @param finish Slot number to stop at when scanning, getInventorySize() by default
-- @return The slot number of the first empty inventory slot, or nil if inventory is full/invalid
function nibinv.findEmptySlot(side, start, finish)
    for i=start or 1, finish or inv.getInventorySize(side) do
        if not inv.getStackInSlot(side, i) then return i end
    end
end

--- Consolidates all the item stacks in the robot's inventory
function nibinv.robot.consolidate()
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

function nibinv.robot.equipItem(name)
    local tool = nibinv.hasItem(sides.back, name)

    if not name then return nil, "item not found" end
    if not robot.select(tool) then return nil, "unable to select item slot for equipping" end
    if not inv.equip() then return nil, "unable to equip item" end

    return true
end

function nibinv.robot.selectItem(name)
    local item = nibinv.hasItem(sides.back, name)

    if not item then return nil, "item not found" end
    if not robot.select(item) then return nil, "unable to select item slot" end

    return true
end

return nibinv
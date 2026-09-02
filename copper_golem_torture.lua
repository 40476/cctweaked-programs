-- Configuration
local TARGET_NAME = "chest_236" -- Set this to the EXACT string printed by the modem
local CHECK_INTERVAL = 3       -- Delay in seconds between cycles

-- Helper function: Check if a specific chest is completely empty
local function isInventoryEmpty(inv)
    local items = inv.list()
    for _ in pairs(items) do
        return false -- Found at least one item stack
    end
    return true
end

-- Helper function: Shuffle a table randomly
local function shuffle(tbl)
    for i = #tbl, 2, -1 do
        local j = math.random(i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
    return tbl
end

-- Main function to find all inventories on the network
local function getInventories()
    local allInvs = {}
    local target = nil

    -- Find all peripherals that act as inventories
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.hasType(name, "inventory") then
            -- Match the exact target chest name or search substring
            if name == TARGET_NAME or name:find(TARGET_NAME) then
                target = { name = name, inv = peripheral.wrap(name) }
            else
                table.insert(allInvs, { name = name, inv = peripheral.wrap(name) })
            end
        end
    end

    return target, allInvs
end

print("=== Chest Refiller Started ===")
print("Targeting peripheral containing: " .. TARGET_NAME)

while true do
    local targetData, sourceInvs = getInventories()

    if not targetData or not targetData.inv then
        print("Waiting for target chest '" .. TARGET_NAME .. "' to connect...")
    else
        -- Check if target chest is empty
        if isInventoryEmpty(targetData.inv) then
            print("Target chest is empty! Picking random items from sources...")

            if #sourceInvs == 0 then
                print("Warning: No source inventories found on network.")
            else
                -- Pick random source chests
                shuffle(sourceInvs)
                local itemsMoved = false

                for _, source in ipairs(sourceInvs) do
                    local items = source.inv.list()
                    local occupiedSlots = {}

                    for slot, _ in pairs(items) do
                        table.insert(occupiedSlots, slot)
                    end

                    -- If this chest has items, pick random slots from it
                    if #occupiedSlots > 0 then
                        shuffle(occupiedSlots)
                        local countFromThisChest = 0

                        for _, slot in ipairs(occupiedSlots) do
                            -- Move items from source to target chest
                            local moved = source.inv.pushItems(targetData.name, slot)
                            if moved > 0 then
                                itemsMoved = true
                                countFromThisChest = countFromThisChest + 1
                                
                                -- Take a max of 3 items per chest to ensure variety
                                if countFromThisChest >= 3 then
                                    break
                                end
                            end
                        end
                    end

                    -- Stop picking items if target chest is no longer empty
                    if not isInventoryEmpty(targetData.inv) then
                        break
                    end
                end

                if itemsMoved then
                    print("Successfully refilled target chest!")
                else
                    print("No items were available to move.")
                end
            end
        end
    end

    sleep(CHECK_INTERVAL)
end

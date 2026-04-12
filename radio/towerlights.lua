-- relay_toggler.lua
-- Toggles all outputs on redstone_relay_0 through redstone_relay_3

-- Configuration
local INTERVAL = 2.0 -- Time in seconds between each toggle
local RELAY_NAMES = {
    "redstone_relay_0",
    "redstone_relay_1",
    "redstone_relay_2",
    "redstone_relay_3"
}
local SIDES = {"top", "bottom", "left", "right", "front", "back"}

-- Find and wrap all the valid relays
local connected_relays = {}
print("Scanning for relays...")

for _, name in ipairs(RELAY_NAMES) do
    local relay = peripheral.wrap(name)
    if relay then
        table.insert(connected_relays, relay)
        print("Found: " .. name)
    else
        print("Missing: " .. name .. " (Check your wired modem!)")
    end
end

-- Stop if none are found
if #connected_relays == 0 then
    print("No redstone relays were found on the network. Exiting.")
    return
end

print("\nStarting toggle loop with " .. #connected_relays .. " relays.")
print("Interval: " .. INTERVAL .. " seconds.")
print("Press Ctrl+T to stop.")

local state = false

while true do
    -- Flip the state (true becomes false, false becomes true)
    state = not state 
    
    -- Loop through every found relay
    for _, relay in ipairs(connected_relays) do
        -- Loop through every possible side and set the redstone output
        for _, side in ipairs(SIDES) do
            -- We use pcall (protected call) just in case a specific mod's relay 
            -- uses slightly different syntax, so it won't crash your script.
            pcall(function()
                relay.setOutput(side, state)
            end)
        end
    end
    
    -- Wait for the interval
    os.sleep(INTERVAL)
end
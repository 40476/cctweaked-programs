-- Configuration
local monitorName = "monitor_0"
local maxStars = 40    -- Maximum stars on screen at once
local twinkleSpeed = 0.1 -- Seconds between updates
local mon = peripheral.wrap(monitorName)

if not mon then
    error("Monitor '" .. monitorName .. "' not found. Check modem connection!")
end

mon.setTextScale(0.5)
local width, height = mon.getSize()
local stars = {} -- This table will track {x, y, char}

-- Clear the screen initially
mon.setBackgroundColor(colors.black)
mon.clear()

-- Function to add a new star to the tracker
local function addStar()
    local newStar = {
        x = math.random(1, width),
        y = math.random(1, height),
        char = ({"*", ".", "+"})[math.random(1, 3)],
        color = (math.random() > 0.3) and colors.white or colors.yellow
    }
    table.insert(stars, newStar)
    
    -- Draw it
    mon.setCursorPos(newStar.x, newStar.y)
    mon.setTextColor(newStar.color)
    mon.write(newStar.char)
end

-- Function to remove the oldest star
local function removeOldestStar()
    if #stars > 0 then
        local oldStar = table.remove(stars, 1) -- Remove first item in table
        mon.setCursorPos(oldStar.x, oldStar.y)
        mon.write(" ") -- Overwrite with a space
    end
end

-- Main Animation Loop
while true do
    -- Add a star if we haven't hit the limit
    if #stars < maxStars then
        addStar()
    end

    -- Randomly decide to "blink" a star out
    if #stars > 5 and math.random(1, 3) == 1 then
        removeOldestStar()
    end

    -- Add a fresh star to replace the one we just blinked
    addStar()

    -- Small delay so it doesn't look like a strobe light
    sleep(twinkleSpeed)
end

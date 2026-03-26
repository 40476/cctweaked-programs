-- Configuration
local monitorName = "monitor_0"
local starCount = 15 -- How many stars to show at once
local mon = peripheral.wrap(monitorName)

if not mon then
    error("Monitor 'monitor_0' not found. Is it connected via modem and wrapped?")
end

mon.setTextScale(0.5)
local width, height = mon.getSize()

-- Function to draw a single star at a random position
local function drawStar(x, y, color)
    mon.setCursorPos(x, y)
    mon.setTextColor(color)
    -- Randomly pick a star shape for variety
    local shapes = {"*", "+", "."}
    mon.write(shapes[math.random(1, #shapes)])
end

mon.setBackgroundColor(colors.black)
mon.clear()

while true do
    -- Pick a random spot
    local x = math.random(1, width)
    local y = math.random(1, height)
    
    -- "Birth" a star (Bright White or Yellow)
    local starColor = math.random() > 0.5 and colors.white or colors.yellow
    drawStar(x, y, starColor)
    
    -- Short delay for the "twinkle" speed
    sleep(0.1)
    
    -- "Fade" a random star by drawing a black space over a random area
    -- This keeps the screen from filling up entirely
    mon.setCursorPos(math.random(1, width), math.random(1, height))
    mon.write(" ")
    
    -- Occasionally clear a small batch to keep it moving
    if math.random(1, 20) == 1 then
        mon.setCursorPos(math.random(1, width), math.random(1, height))
        mon.write("  ")
    end
end

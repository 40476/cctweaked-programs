-- Configuration
local monitorSide = "back"
local redstoneSide = "top"
local mon = peripheral.wrap(monitorSide)

if not mon then
    error("No monitor found on " .. monitorSide)
end

local isOn = redstone.getOutput(redstoneSide)

local function drawUI()
    mon.setBackgroundColor(colors.black)
    mon.clear()
    
    -- Set color based on state
    local bulbColor = isOn and colors.yellow or colors.lightGray
    local textColor = isOn and colors.black or colors.white
    local statusText = isOn and "ON" or "OFF"

    -- Draw the "Bulb" (a 5x3 box in the center)
    mon.setBackgroundColor(bulbColor)
    for y = 2, 4 do
        mon.setCursorPos(3, y)
        mon.write("       ")
    end
    
    -- Draw the text label
    mon.setCursorPos(5, 3)
    mon.setTextColor(textColor)
    mon.write(statusText)
    
    -- Reset for next time
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.setCursorPos(1, 1)
    mon.write("Light Switch")
end

-- Initial Draw
drawUI()

-- Main Loop
while true do
    -- Wait for a touch event on the monitor
    local event, side, x, y = os.pullEvent("monitor_touch")
    
    -- Toggle the state
    isOn = not isOn
    
    -- Apply Redstone
    redstone.setOutput(redstoneSide, isOn)
    
    -- Update Display
    drawUI()
end

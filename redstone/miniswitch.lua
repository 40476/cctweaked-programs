-- Configuration
local monitorSide = "back"
local redstoneSide = "top"
local stateFile = "state.txt"
local mon = peripheral.wrap(monitorSide)

if not mon then
    error("No monitor found on " .. monitorSide)
end

-- Function to save state to a file
local function saveState(state)
    local file = fs.open(stateFile, "w")
    file.write(tostring(state))
    file.close()
end

-- Function to load state from a file
local function loadState()
    if fs.exists(stateFile) then
        local file = fs.open(stateFile, "r")
        local content = file.readAll()
        file.close()
        return content == "true"
    end
    return false -- Default if no file exists
end

-- Initial Setup
local isOn = loadState()
redstone.setOutput(redstoneSide, isOn)

mon.setTextScale(0.5) -- Set the requested resolution

local function drawUI()
    mon.setBackgroundColor(colors.black)
    mon.clear()
    
    local bulbColor = isOn and colors.yellow or colors.lightGray
    local textColor = isOn and colors.black or colors.white
    local statusText = isOn and "ON" or "OFF"

    -- Draw the "Bulb" icon (Larger now due to 0.5 scale)
    mon.setBackgroundColor(bulbColor)
    for y = 4, 10 do
        mon.setCursorPos(5, y)
        mon.write("                 ")
    end
    
    mon.setCursorPos(11, 7)
    mon.setTextColor(textColor)
    mon.write(statusText)
    
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.setCursorPos(2, 2)
    mon.write("SYSTEM: " .. (isOn and "ACTIVE" or "IDLE"))
end

drawUI()

-- Main Loop
while true do
    local event, side, x, y = os.pullEvent("monitor_touch")
    
    isOn = not isOn
    
    -- Apply and Persist
    redstone.setOutput(redstoneSide, isOn)
    saveState(isOn)
    
    drawUI()
end

-- CONFIGURATION
local CORRECT_CODE = "1234"      -- Set your PIN here
local OPEN_TIME = 5              -- Seconds to keep door open
local RS_SIDE = "back"           -- Which side the door is on
local PASS_LENGTH = #CORRECT_CODE

-- Variables
local input = ""
local w, h = term.getSize()

-- Helper to draw buttons
local function drawButton(x, y, label)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.setCursorPos(x, y)
    term.write(" " .. label .. " ")
end

local function drawUI()
    term.setBackgroundColor(colors.black)
    term.clear()
    
    -- Draw Header
    term.setCursorPos(math.floor(w/2 - 6), 2)
    term.setTextColor(colors.yellow)
    term.write("ENTER PASSCODE")

    -- Draw Input Mask (stars)
    term.setCursorPos(math.floor(w/2 - (PASS_LENGTH/2)), 4)
    term.setTextColor(colors.lime)
    local display = string.rep("*", #input) .. string.rep("_", PASS_LENGTH - #input)
    term.write(display)

    -- Draw Keypad (centered)
    local startX = math.floor(w/2 - 5)
    local startY = 6
    
    for i = 1, 9 do
        local row = math.ceil(i / 3)
        local col = (i - 1) % 3
        drawButton(startX + (col * 4), startY + (row * 2), tostring(i))
    end
    drawButton(startX + 4, startY + 8, "0") -- Zero at the bottom
end

local function checkClick(x, y)
    local startX = math.floor(w/2 - 5)
    local startY = 6
    
    -- Logic to check if a button was clicked
    for i = 1, 9 do
        local row = math.ceil(i / 3)
        local col = (i - 1) % 3
        local bx, by = startX + (col * 4), startY + (row * 2)
        if x >= bx and x <= bx + 2 and y == by then return tostring(i) end
    end
    
    if x >= startX + 4 and x <= startX + 6 and y == startY + 8 then return "0" end
    return nil
end

-- Main Loop
while true do
    drawUI()
    local event, side, x, y = os.pullEvent("mouse_click")
    local button = checkClick(x, y)
    
    if button then
        input = input .. button
        
        if #input == PASS_LENGTH then
            drawUI() -- Update stars one last time
            sleep(0.2)
            
            if input == CORRECT_CODE then
                term.setCursorPos(math.floor(w/2 - 3), h - 1)
                term.setTextColor(colors.lime)
                term.write("ACCESS GRANTED")
                redstone.setOutput(RS_SIDE, true)
                sleep(OPEN_TIME)
                redstone.setOutput(RS_SIDE, false)
            else
                term.setCursorPos(math.floor(w/2 - 3), h - 1)
                term.setTextColor(colors.red)
                term.write("WRONG CODE")
                sleep(1.5)
            end
            input = "" -- Reset
        end
    end
end

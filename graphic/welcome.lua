-- Welcome Animation with Isolated Effects (Multi-Monitor Mirroring with 2x Scale)
-- Effects: Rainbow, Glitch, Pulse, Wave, Typewriter

local ART = {
"WELCOME"
}

-- Configuration
local CONFIG = {
    effectDuration = 5,      -- Seconds per effect
    typewriterSpeed = 0.04,  -- Lower = faster typing
    colorSpeed = 0.8,        -- Color change speed
    waveIntensity = 0.7,     -- Wave effect strength
    pulseSpeed = 1.5,        -- Border pulse speed
    monitorScale = 2         -- 2 = Double scaling (Default is 1)
}

-------------------------------------------------------------------------------
-- MULTI-MONITOR MIRRORING ENGINE
-------------------------------------------------------------------------------
-- Find all attached monitors and wrap them as windows
local monitors = {}
for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "monitor" then
        local mon = peripheral.wrap(side)
        
        -- Apply the text scale factor here
        mon.setTextScale(CONFIG.monitorScale)
        
        -- Read sizing AFTER scaling is applied
        local w, h = mon.getSize()
        
        -- Use the window API to track individual cursor and sizing data safely
        table.insert(monitors, window.create(mon, 1, 1, w, h))
    end
end

-- Fallback to local terminal if no monitors are attached
if #monitors == 0 then
    local w, h = term.getSize()
    table.insert(monitors, window.create(term.current(), 1, 1, w, h))
end

-- Custom terminal wrapper that duplicates drawing commands to all monitors
local multiTerm = {}
local methods = {
    "clear", "clearLine", "setCursorPos", "write", "setTextColor", 
    "setBackgroundColor", "getCursorPos", "setCursorBlink",
    "getPaletteColor", "setPaletteColor", "isColor", "blit", "scroll"
}

for _, method in ipairs(methods) do
    multiTerm[method] = function(...)
        local results
        for _, mon in ipairs(monitors) do
            if mon[method] then
                results = { mon[method](...) }
            end
        end
        return table.unpack(results or {})
    end
end

-- FIX: Safely retrieve baseline resolution using the first monitor object
multiTerm.getSize = function()
    return monitors[1].getSize()
end
-------------------------------------------------------------------------------

-- Animation Terminal Setup
multiTerm.setCursorBlink(false)
local w, h = multiTerm.getSize()

-- FIX: Calculate centered boundaries using string element lengths
local centerX = math.floor((w - #ART[1]) / 2) + 1
local centerY = math.floor((h - #ART) / 2) + 1

-- Safety boundary clamps for tight 3x1 scaled setups
if centerX < 1 then centerX = 1 end
if centerY < 1 then centerY = 1 end

-- Effect definition table
local EFFECTS = {
    "typewriter",
    "rainbow",
    "wave",
    "pulse",
    "glitch"
}

local currentEffect = 1
local effectStart = 0
local effectActive = false

-- RGB color converter
local function lookupRGB(r, g, b)
    local colorTable = {
        {color = colors.white,      r = 1.00, g = 1.00, b = 1.00},
        {color = colors.orange,     r = 1.00, g = 0.60, b = 0.00},
        {color = colors.magenta,    r = 1.00, g = 0.40, b = 1.00},
        {color = colors.lightBlue,  r = 0.40, g = 0.70, b = 1.00},
        {color = colors.yellow,     r = 1.00, g = 1.00, b = 0.20},
        {color = colors.lime,       r = 0.45, g = 1.00, b = 0.20},
        {color = colors.pink,       r = 1.00, g = 0.70, b = 0.80},
        {color = colors.gray,       r = 0.45, g = 0.45, b = 0.45},
        {color = colors.lightGray,  r = 0.70, g = 0.70, b = 0.70},
        {color = colors.cyan,       r = 0.20, g = 0.80, b = 0.90},
        {color = colors.purple,     r = 0.70, g = 0.30, b = 1.00},
        {color = colors.blue,       r = 0.15, g = 0.40, b = 1.00},
        {color = colors.brown,      r = 0.60, g = 0.40, b = 0.10},
        {color = colors.green,      r = 0.35, g = 0.70, b = 0.15},
        {color = colors.red,        r = 1.00, g = 0.25, b = 0.25},
        {color = colors.black,      r = 0.15, g = 0.15, b = 0.15}
    }

    if r > 1 or g > 1 or b > 1 then
        r = r / 255
        g = g / 255
        b = b / 255
    end

    local closestColor = colors.white
    local minDistance = math.huge

    for _, col in ipairs(colorTable) do
        local dr = (r - col.r) * 0.299
        local dg = (g - col.g) * 0.587
        local db = (b - col.b) * 0.114
        local distance = dr*dr + dg*dg + db*db

        if distance < minDistance then
            minDistance = distance
            closestColor = col.color
        end
    end

    return closestColor
end

-- Individual effect implementations (re-routed to multiTerm)
local effectFunctions = {
    typewriter = function(progress)
        multiTerm.setBackgroundColor(colors.black)
        multiTerm.clear()
        
        for y, line in ipairs(ART) do
            local charsToDraw = math.min(#line, math.floor(progress * #line))
            for x = 1, charsToDraw do
                multiTerm.setCursorPos(centerX + x - 1, centerY + y - 1)
                multiTerm.write(line:sub(x, x))
            end
        end
    end,
    
    rainbow = function(step)
        multiTerm.setBackgroundColor(colors.black)
        multiTerm.clear()
        
        for y, line in ipairs(ART) do
            for x = 1, #line do
                local hue = (step * CONFIG.colorSpeed + x/3 + y/2) % 6
                local r = math.min(1, math.abs(math.sin(hue * 0.5)))
                local g = math.min(1, math.abs(math.sin((hue + 2) * 0.5)))
                local b = math.min(1, math.abs(math.sin((hue + 4) * 0.5)))
                
                multiTerm.setCursorPos(centerX + x - 1, centerY + y - 1)
                multiTerm.setTextColor(lookupRGB(r, g, b))
                multiTerm.write(line:sub(x, x))
            end
        end
    end,
    
    wave = function(step)
        multiTerm.setBackgroundColor(colors.black)
        multiTerm.clear()
        
        for y, line in ipairs(ART) do
            local offset = math.sin(step + y/2) * CONFIG.waveIntensity
            for x = 1, #line do
                local waveOff = math.sin(x/2 + step * 2) * 0.5
                local finalX = math.floor(centerX + x - 1 + offset + waveOff)
                
                -- Keep rendering within visible frame bounds
                if finalX >= 1 and finalX <= w then
                    multiTerm.setCursorPos(finalX, centerY + y - 1)
                    multiTerm.write(line:sub(x, x))
                end
            end
        end
    end,
    
    pulse = function(step)
        local pulse = math.sin(step * CONFIG.pulseSpeed) * 0.5 + 0.5
        multiTerm.setBackgroundColor(lookupRGB(pulse*0.2, pulse*0.1, pulse*0.3))
        multiTerm.clear()
        
        for y, line in ipairs(ART) do
            for x = 1, #line do
                multiTerm.setCursorPos(centerX + x - 1, centerY + y - 1)
                multiTerm.setTextColor(lookupRGB(1, 0.8 - pulse*0.3, 0.6 - pulse*0.2))
                multiTerm.write(line:sub(x, x))
            end
        end
    end,
    
    glitch = function(step)
        multiTerm.setBackgroundColor(colors.black)
        multiTerm.clear()
        
        for y, line in ipairs(ART) do
            for x = 1, #line do
                if math.random() < 0.15 then
                    local char = string.char(math.random(33, 126))
                    local finalX = centerX + x - 1 + math.random(-1,1)
                    local finalY = centerY + y - 1 + math.random(-1,1)
                    
                    if finalX >= 1 and finalX <= w and finalY >= 1 and finalY <= h then
                        multiTerm.setCursorPos(finalX, finalY)
                        multiTerm.setTextColor(lookupRGB(
                            math.random(),
                            math.random(),
                            math.random()
                        ))
                        multiTerm.write(char)
                    end
                else
                    multiTerm.setCursorPos(centerX + x - 1, centerY + y - 1)
                    multiTerm.setTextColor(colors.white)
                    multiTerm.write(line:sub(x, x))
                end
            end
        end
    end
}

-- Main animation loop
local startTime = os.clock()
multiTerm.clear()

while true do
    local elapsedTotal = os.clock() - startTime
    local elapsedEffect = os.clock() - effectStart
    local textProgress = math.min(1, elapsedTotal / (#ART[1] * CONFIG.typewriterSpeed))
    
    -- Effect transition logic
    if elapsedEffect > CONFIG.effectDuration then
        currentEffect = currentEffect % #EFFECTS + 1
        effectStart = os.clock()
        effectActive = false
        multiTerm.clear()
    end
    
    -- Only activate effect after text has appeared
    if not effectActive and textProgress == 1 then
        effectStart = os.clock()
        effectActive = true
    end
    
    -- Draw appropriate effect
    if effectActive then
        local step = os.clock() - effectStart
        effectFunctions[EFFECTS[currentEffect]](step)
    else
        effectFunctions.typewriter(textProgress)
    end
    
    -- Sync rendering to monitors
    for _, mon in ipairs(monitors) do
        mon.setVisible(true)
    end
    
    -- Handle exit
    sleep(0.05)
    if os.pullEvent == os.pullEventRaw then
        local event = os.pullEventRaw(0.001)
        if event == "terminate" then
            break
        end
    end
end

multiTerm.clear()
multiTerm.setCursorPos(1,1)

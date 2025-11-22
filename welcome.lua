-- Welcome Animation with Isolated Effects
-- Effects: Rainbow, Glitch, Pulse, Wave, Typewriter

local ART = {
" _      ________   _________  __  _______",
"| | /| / / __/ /  / ___/ __ \/  |/  / __/",
"| |/ |/ / _// /__/ /__/ /_/ / /|_/ / _/  ",
"|__/|__/___/____/\___/\____/_/  /_/___/  ",
}

-- Configuration
local CONFIG = {
    effectDuration = 5,      -- Seconds per effect
    typewriterSpeed = 0.04,  -- Lower = faster typing
    colorSpeed = 0.8,        -- Color change speed
    waveIntensity = 0.7,     -- Wave effect strength
    pulseSpeed = 1.5         -- Border pulse speed
}

-- Terminal setup
term.setCursorBlink(false)
local w, h = term.getSize()
local centerX = math.floor((w - #ART[1]) / 2)
local centerY = math.floor((h - #ART) / 2)

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
    -- Standard CC color palette in RGB (0-1 range)
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

    -- Handle integer RGB (0-255) inputs
    if r > 1 or g > 1 or b > 1 then
        r = r / 255
        g = g / 255
        b = b / 255
    end

    -- Find closest color using perceptually weighted distance
    local closestColor = colors.white
    local minDistance = math.huge

    for _, col in ipairs(colorTable) do
        -- Calculate color difference with luminosity weighting
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


-- Individual effect implementations
local effectFunctions = {
    typewriter = function(progress)
        term.setBackgroundColor(colors.black)
        term.clear()
        
        for y, line in ipairs(ART) do
            for x = 1, math.min(#line, progress * #line) do
                term.setCursorPos(centerX + x - 1, centerY + y - 1)
                term.write(line:sub(x, x))
            end
        end
    end,
    
    rainbow = function(step)
        term.setBackgroundColor(colors.black)
        term.clear()
        
        for y, line in ipairs(ART) do
            for x = 1, #line do
                local hue = (step * CONFIG.colorSpeed + x/3 + y/2) % 6
                local r = math.min(1, math.abs(math.sin(hue * 0.5)))
                local g = math.min(1, math.abs(math.sin((hue + 2) * 0.5)))
                local b = math.min(1, math.abs(math.sin((hue + 4) * 0.5)))
                
                term.setCursorPos(centerX + x - 1, centerY + y - 1)
                term.setTextColor(lookupRGB(r, g, b))
                term.write(line:sub(x, x))
            end
        end
    end,
    
    wave = function(step)
        term.setBackgroundColor(colors.black)
        term.clear()
        
        for y, line in ipairs(ART) do
            local offset = math.sin(step + y/2) * CONFIG.waveIntensity
            for x = 1, #line do
                local waveOff = math.sin(x/2 + step * 2) * 0.5
                term.setCursorPos(
                    math.floor(centerX + x - 1 + offset + waveOff),
                    centerY + y - 1
                )
                term.write(line:sub(x, x))
            end
        end
    end,
    
    pulse = function(step)
        local pulse = math.sin(step * CONFIG.pulseSpeed) * 0.5 + 0.5
        term.setBackgroundColor(lookupRGB(pulse*0.2, pulse*0.1, pulse*0.3))
        term.clear()
        
        for y, line in ipairs(ART) do
            for x = 1, #line do
                term.setCursorPos(centerX + x - 1, centerY + y - 1)
                term.setTextColor(lookupRGB(1, 0.8 - pulse*0.3, 0.6 - pulse*0.2))
                term.write(line:sub(x, x))
            end
        end
    end,
    
    glitch = function(step)
        term.setBackgroundColor(colors.black)
        term.clear()
        
        for y, line in ipairs(ART) do
            for x = 1, #line do
                if math.random() < 0.15 then
                    local char = string.char(math.random(33, 126))
                    term.setCursorPos(
                        centerX + x - 1 + math.random(-1,1),
                        centerY + y - 1 + math.random(-1,1)
                    )
                    term.setTextColor(lookupRGB(
                        math.random(),
                        math.random(),
                        math.random()
                    ))
                    term.write(char)
                else
                    term.setCursorPos(centerX + x - 1, centerY + y - 1)
                    term.setTextColor(colors.white)
                    term.write(line:sub(x, x))
                end
            end
        end
    end
}

-- Main animation loop
local startTime = os.clock()
term.clear()

while true do
    local elapsedTotal = os.clock() - startTime
    local elapsedEffect = os.clock() - effectStart
    local textProgress = math.min(1, elapsedTotal / (#ART[1] * CONFIG.typewriterSpeed))
    
    -- Effect transition logic
    if elapsedEffect > CONFIG.effectDuration then
        currentEffect = currentEffect % #EFFECTS + 1
        effectStart = os.clock()
        effectActive = false
        term.clear()
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
    
    -- Handle exit
    sleep(0.05)
    if os.pullEvent == os.pullEventRaw then
        local event = os.pullEventRaw(0.001)
        if event == "terminate" then
            break
        end
    end
end

term.clear()
term.setCursorPos(1,1)
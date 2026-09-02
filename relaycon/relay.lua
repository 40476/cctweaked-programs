local PORT = 4242
local CONFIG_FILE = "relays.json"
local isPocket = (pocket ~= nil)

-- Bind Wireless/Ender Modem
local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if modem then modem.open(PORT) end

local relays = {}
local selectedIdx = 1
local scrollOffset = 0
local monitorScale = 0.5
local SCALES = { 0.5, 1.0, 1.5, 2.0 }
local lastPlayerPos = nil
local activePulses = {} -- Tracks non-blocking pulse timers

-- Color Helper
local function setColors(target, fg, bg)
    if target.isColor and target.isColor() then
        if fg then target.setTextColor(fg) end
        if bg then target.setBackgroundColor(bg) end
    end
end

-- Flush Pending Keyboard Events
local function flushEvents()
    local timerID = os.startTimer(0)
    while true do
        local ev, p1 = os.pullEvent()
        if ev == "timer" and p1 == timerID then break end
    end
end

-- Input Helper with Preserved Defaults
local function promptInput(promptText, defaultVal)
    flushEvents()
    local suffix = defaultVal and (" [" .. tostring(defaultVal) .. "]") or ""
    write(promptText .. suffix .. ": ")
    local val = read()
    if val == "" then return defaultVal end
    return val
end

-- Persistent Storage
local function saveConfig()
    local f = fs.open(CONFIG_FILE, "w")
    f.write(textutils.serializeJSON({ relays = relays, scale = monitorScale }))
    f.close()
end

local function applyRedstone()
    if isPocket then return end
    for _, r in ipairs(relays) do
        if r.relayName and r.side then
            pcall(function()
                local relayPeripheral = peripheral.wrap(r.relayName)
                if relayPeripheral and relayPeripheral.setOutput then
                    relayPeripheral.setOutput(r.side, r.state or false)
                end
            end)
        end
    end
end

local function loadConfig()
    if fs.exists(CONFIG_FILE) then
        local f = fs.open(CONFIG_FILE, "r")
        local data = textutils.unserializeJSON(f.readAll()) or {}
        f.close()
        if data.relays then
            relays = data.relays
            monitorScale = data.scale or 0.5
        else
            relays = data
        end
    end
    applyRedstone()
end

local function broadcastSync()
    if modem and not isPocket then
        modem.transmit(PORT, PORT, { cmd = "sync", data = relays })
    end
end

-- Automation Evaluator
local function evaluateAutomations()
    if isPocket then return end
    local curTime = os.time()
    local stateChanged = false

    for _, r in ipairs(relays) do
        if not r.paused then
            local autoTargetState = nil
            local hasActiveTrigger = false

            -- 1. Time Trigger
            if r.autoTime and r.autoTime.enabled then
                hasActiveTrigger = true
                local startH = r.autoTime.startHour or 6.0
                local endH = r.autoTime.endHour or 18.0
                if startH < endH then
                    autoTargetState = (curTime >= startH and curTime < endH)
                else
                    autoTargetState = (curTime >= startH or curTime < endH)
                end
            end

            -- 2. Redstone Trigger
            if r.autoRedstone and r.autoRedstone.enabled then
                hasActiveTrigger = true
                local inSide = r.autoRedstone.side or "left"
                autoTargetState = redstone.getInput(inSide)
            end

            -- 3. GPS Proximity Trigger
            if r.autoGPS and r.autoGPS.enabled and lastPlayerPos then
                hasActiveTrigger = true
                local dx = lastPlayerPos.x - (r.autoGPS.x or 0)
                local dz = lastPlayerPos.z - (r.autoGPS.z or 0)
                local dist2D = math.sqrt(dx*dx + dz*dz)
                
                local inRadius = dist2D <= (r.autoGPS.radius or 10)
                local yMax = r.autoGPS.maxYDiff or 1.5
                local inY = true
                if r.autoGPS.targetY ~= nil then
                    inY = math.abs(lastPlayerPos.y - r.autoGPS.targetY) <= yMax
                end
                
                autoTargetState = (inRadius and inY)
            end

            if hasActiveTrigger and autoTargetState ~= nil then
                if r.override then
                    if (r.lastAutoState ~= nil and r.lastAutoState ~= autoTargetState) or (r.state == autoTargetState) then
                        r.override = false
                    end
                end

                r.lastAutoState = autoTargetState

                if not r.override then
                    if r.state ~= autoTargetState then
                        r.state = autoTargetState
                        stateChanged = true
                    end
                end
            end
        end
    end

    if stateChanged then
        applyRedstone()
        saveConfig()
        broadcastSync()
    end
end

local function cycleMonitorScale()
    local idx = 1
    for i, s in ipairs(SCALES) do
        if math.abs(s - monitorScale) < 0.1 then idx = i; break end
    end
    monitorScale = SCALES[(idx % #SCALES) + 1]
    saveConfig()
end

-- Non-blocking trigger helper
local function triggerRelay(idx)
    local r = relays[idx]
    if not r then return end

    r.override = true

    if r.mode == "toggle" then
        r.state = not r.state
        applyRedstone(); saveConfig(); broadcastSync()
    elseif r.mode == "pulse_on" or r.mode == "pulse_off" then
        local activeState = (r.mode == "pulse_on")
        r.state = activeState
        applyRedstone(); saveConfig(); broadcastSync()
        
        -- Schedule non-blocking pulse reset
        local timerID = os.startTimer(0.5)
        activePulses[timerID] = { index = idx, targetState = not activeState }
    end
end

-- Dynamic GPS Polling Rate
local function getDynamicGPSInterval(currentX, currentY, currentZ)
    if not currentX or not currentZ then return 2.0 end
    
    local minDist = math.huge
    for _, r in ipairs(relays) do
        if r.autoGPS and r.autoGPS.enabled and not r.paused then
            local dx = currentX - (r.autoGPS.x or 0)
            local dz = currentZ - (r.autoGPS.z or 0)
            local dist2D = math.sqrt(dx*dx + dz*dz)
            local triggerRadius = r.autoGPS.radius or 10

            local distToEdge = math.max(0, dist2D - triggerRadius)
            if distToEdge < minDist then minDist = distToEdge end
        end
    end

    if minDist == math.huge then return 2.0 end

    if minDist <= 5 then
        return 0.1
    elseif minDist >= 50 then
        return 2.0
    else
        return 0.1 + ((minDist - 5) / (50 - 5)) * (2.0 - 0.1)
    end
end

-- GUI Renderer
local function drawUI(target, activeSelected, offset)
    local w, h = target.getSize()
    setColors(target, colors.white, colors.black)
    target.clear()

    -- Header Bar
    setColors(target, colors.white, colors.blue)
    target.setCursorPos(1, 1)

    local gpsTag = lastPlayerPos and "[GPS OK]" or "[NO GPS]"
    local titleLeft = isPocket and "HUB (POCKET)" or string.format("HUB (BASE %.1fx)", monitorScale)
    if w < 28 then titleLeft = "HUB" end

    local availableSpace = math.max(1, w - #titleLeft - #gpsTag)
    local headerText = titleLeft .. string.rep(" ", availableSpace) .. gpsTag
    target.write(headerText:sub(1, w))

    local viewH = h - 2
    local totalItems = #relays
    offset = math.max(0, math.min(offset, math.max(0, totalItems - viewH)))
    local rowMap = {}

    if totalItems == 0 then
        setColors(target, colors.yellow, colors.black)
        target.setCursorPos(2, 3); target.write("No Relays Configured!")
        setColors(target, colors.lightGray, colors.black)
        target.setCursorPos(2, 5); target.write("Press [A] to setup relays.")
    else
        for i = 1, viewH do
            local itemIdx = i + offset
            if itemIdx > totalItems then break end
            local r = relays[itemIdx]
            local lineY = i + 1
            rowMap[lineY] = itemIdx

            local isSelected = (activeSelected == itemIdx)
            local bg = isSelected and colors.gray or colors.black
            setColors(target, colors.white, bg)
            target.setCursorPos(1, lineY)
            target.write(string.rep(" ", w - 1))

            -- Col 1: Status Icon
            target.setCursorPos(1, lineY)
            local hasTrig = (r.autoTime and r.autoTime.enabled) or (r.autoRedstone and r.autoRedstone.enabled) or (r.autoGPS and r.autoGPS.enabled)
            
            if r.paused then
                setColors(target, colors.yellow, bg)
                target.write("P")
            elseif r.override then
                setColors(target, colors.orange or colors.red, bg)
                target.write("!")
            elseif hasTrig then
                setColors(target, colors.cyan, bg)
                target.write("A")
            else
                target.write(" ")
            end

            -- Col 2: State Button
            target.setCursorPos(2, lineY)
            if r.state then
                setColors(target, colors.white, colors.green); target.write(" ON ")
            else
                setColors(target, colors.white, colors.red); target.write(" OFF ")
            end

            -- Trigger Badges [T R G]
            local trig = ""
            if r.autoTime and r.autoTime.enabled then trig = trig .. "T" end
            if r.autoRedstone and r.autoRedstone.enabled then trig = trig .. "R" end
            if r.autoGPS and r.autoGPS.enabled then trig = trig .. "G" end

            local badge = (trig ~= "") and string.format(" [%s]", trig) or ""

            -- Col 7: Details
            setColors(target, isSelected and colors.yellow or colors.white, bg)
            target.setCursorPos(7, lineY)
            local label = string.format("%d.%s%s", itemIdx, r.name or "Relay", badge)
            if w > 36 then
                label = label .. string.format(" (%s:%s)", r.relayName or "relay", r.side or "top")
            end
            target.write(label:sub(1, w - 8))
        end
    end

    -- Right Scrollbar
    local sidebarX = w
    setColors(target, colors.black, colors.yellow)
    target.setCursorPos(sidebarX, 2); target.write("^")

    local trackH = viewH - 2
    if trackH > 0 then
        setColors(target, colors.gray, colors.lightGray)
        for y = 3, h - 2 do
            target.setCursorPos(sidebarX, y); target.write("|")
        end
        if totalItems > viewH then
            local thumbY = math.floor(3 + (offset / math.max(1, totalItems - viewH)) * (trackH - 1))
            setColors(target, colors.white, colors.cyan)
            target.setCursorPos(sidebarX, thumbY); target.write("#")
        end
    end

    setColors(target, colors.black, colors.yellow)
    target.setCursorPos(sidebarX, h - 1); target.write("v")

    -- Footer Bar
    setColors(target, colors.black, colors.lightGray)
    target.setCursorPos(1, h); target.write(string.rep(" ", w)); target.setCursorPos(1, h)
    if w < 30 then
        setColors(target, colors.white, colors.blue); target.write("A"); setColors(target, colors.black, colors.lightGray); target.write("+ ");
        setColors(target, colors.white, colors.purple); target.write("T"); setColors(target, colors.black, colors.lightGray); target.write("rig ");
        setColors(target, colors.white, colors.yellow); target.write("P"); setColors(target, colors.black, colors.lightGray); target.write("ause ");
        setColors(target, colors.white, colors.red); target.write("D"); setColors(target, colors.black, colors.lightGray); target.write("el")
    else
        setColors(target, colors.white, colors.blue); target.write(" [A] Add "); target.write(" ")
        setColors(target, colors.white, colors.blue); target.write(" [E] Edit "); target.write(" ")
        setColors(target, colors.white, colors.purple); target.write(" [T] Triggers "); target.write(" ")
        setColors(target, colors.white, colors.yellow); target.write(" [P] Pause "); target.write(" ")
        setColors(target, colors.white, colors.red); target.write(" [D] Del "); target.write(" ")
        if not isPocket then
            setColors(target, colors.white, colors.cyan); target.write(" [S] Scale "); target.write(" ")
        end
        setColors(target, colors.black, colors.lightGray); target.write(" [Enter] Toggle")
    end

    setColors(target, colors.white, colors.black)
    return rowMap
end

-- Basic Relay Info Config Form
local function promptRelayConfig(existingIdx)
    term.clear()
    term.setCursorPos(1, 1)
    local r = existingIdx and relays[existingIdx] or {}

    setColors(term, colors.yellow, colors.black)
    print("--- RELAY CONFIGURATION ---")
    setColors(term, colors.white, colors.black)

    r.name = promptInput("Name", r.name or ("Relay " .. (#relays + 1)))
    r.relayName = promptInput("Peripheral ID", r.relayName or "redstone_relay_0")
    r.side = promptInput("Output Side", r.side or "top")
    r.mode = promptInput("Mode (toggle/pulse_on/pulse_off)", r.mode or "toggle")

    r.state = r.state or false
    return r
end

-- Dedicated Automation Triggers Config Form
local function promptTriggerConfig(existingIdx)
    if not existingIdx or not relays[existingIdx] then return end
    term.clear()
    term.setCursorPos(1, 1)
    local r = relays[existingIdx]

    setColors(term, colors.cyan, colors.black)
    print("--- AUTOMATION TRIGGERS (" .. (r.name or "Relay") .. ") ---")
    setColors(term, colors.white, colors.black)

    -- 1. Time Trigger
    local timeEnable = promptInput("Enable Time Trigger? (y/n)", (r.autoTime and r.autoTime.enabled) and "y" or "n")
    if timeEnable:lower() == "y" then
        r.autoTime = r.autoTime or {}
        r.autoTime.enabled = true
        r.autoTime.startHour = tonumber(promptInput("  Start Hour (0-23.9)", r.autoTime.startHour or 6.0)) or 6.0
        r.autoTime.endHour = tonumber(promptInput("  End Hour (0-23.9)", r.autoTime.endHour or 18.0)) or 18.0
    else
        r.autoTime = { enabled = false }
    end

    -- 2. Redstone Input Trigger
    local rsEnable = promptInput("\nEnable Redstone Input Trigger? (y/n)", (r.autoRedstone and r.autoRedstone.enabled) and "y" or "n")
    if rsEnable:lower() == "y" then
        r.autoRedstone = r.autoRedstone or {}
        r.autoRedstone.enabled = true
        r.autoRedstone.side = promptInput("  Input Side on Base (left/right/top/bottom/front/back)", r.autoRedstone.side or "left")
    else
        r.autoRedstone = { enabled = false }
    end

    -- 3. GPS Proximity Trigger
    local gpsEnable = promptInput("\nEnable GPS Proximity Trigger? (y/n)", (r.autoGPS and r.autoGPS.enabled) and "y" or "n")
    if gpsEnable:lower() == "y" then
        r.autoGPS = r.autoGPS or {}
        r.autoGPS.enabled = true

        local defX, defY, defZ = 0, 64, 0
        if isPocket then
            local gx, gy, gz = gps.locate(1)
            if gx then defX, defY, defZ = math.floor(gx), math.floor(gy), math.floor(gz) end
        elseif lastPlayerPos then
            defX, defY, defZ = math.floor(lastPlayerPos.x), math.floor(lastPlayerPos.y), math.floor(lastPlayerPos.z)
        end

        r.autoGPS.x = tonumber(promptInput("  Target X Coord", r.autoGPS.x or defX)) or defX

        local defaultYStr = r.autoGPS.targetY and tostring(r.autoGPS.targetY) or "any"
        local yInput = promptInput("  Target Y Coord ('any' to ignore height)", defaultYStr)
        if yInput:lower() == "any" then
            r.autoGPS.targetY = nil
        else
            r.autoGPS.targetY = tonumber(yInput) or defY
            r.autoGPS.maxYDiff = tonumber(promptInput("  Max Y Height Diff (+/- blocks)", r.autoGPS.maxYDiff or 1.5)) or 1.5
        end

        r.autoGPS.z = tonumber(promptInput("  Target Z Coord", r.autoGPS.z or defZ)) or defZ
        r.autoGPS.radius = tonumber(promptInput("  Activation Radius (blocks)", r.autoGPS.radius or 10)) or 10
    else
        r.autoGPS = { enabled = false }
    end

    r.paused = false
    r.override = false
    relays[existingIdx] = r
    return r
end

-- Base Station Engine
local function runHost()
    loadConfig()
    local clockTimer = os.startTimer(1.0)

    while true do
        selectedIdx = math.max(1, math.min(selectedIdx, math.max(1, #relays)))

        local mon = peripheral.find("monitor")
        local monRowMap = {}
        if mon then
            mon.setTextScale(monitorScale)
            monRowMap = drawUI(mon, 0, scrollOffset)
        end
        local termRowMap = drawUI(term, selectedIdx, scrollOffset)

        local ev, p1, p2, p3, msg = os.pullEvent()

        if ev == "timer" then
            if p1 == clockTimer then
                evaluateAutomations()
                clockTimer = os.startTimer(1.0)
            elseif activePulses[p1] then
                local pulseInfo = activePulses[p1]
                if relays[pulseInfo.index] then
                    relays[pulseInfo.index].state = pulseInfo.targetState
                    applyRedstone(); saveConfig(); broadcastSync()
                end
                activePulses[p1] = nil
            end
        elseif ev == "redstone" then
            evaluateAutomations()
        elseif ev == "key" then
            if p1 == keys.up then 
                selectedIdx = math.max(1, selectedIdx - 1)
                if selectedIdx - 1 < scrollOffset then scrollOffset = selectedIdx - 1 end
            elseif p1 == keys.down then 
                selectedIdx = math.min(#relays, selectedIdx + 1)
                local _, h = term.getSize()
                if selectedIdx > scrollOffset + (h - 2) then scrollOffset = selectedIdx - (h - 2) end
            elseif (p1 == keys.enter or p1 == keys.space) and #relays > 0 then triggerRelay(selectedIdx)
            elseif p1 == keys.a then
                table.insert(relays, promptRelayConfig(nil))
                saveConfig(); applyRedstone(); broadcastSync()
            elseif p1 == keys.e and #relays > 0 then
                relays[selectedIdx] = promptRelayConfig(selectedIdx)
                saveConfig(); applyRedstone(); broadcastSync()
            elseif p1 == keys.t and #relays > 0 then
                promptTriggerConfig(selectedIdx)
                saveConfig(); applyRedstone(); broadcastSync()
            elseif p1 == keys.p and #relays > 0 then
                local r = relays[selectedIdx]
                if r.override then
                    r.override = false
                    r.paused = false
                else
                    r.paused = not r.paused
                end
                saveConfig(); applyRedstone(); broadcastSync()
            elseif p1 == keys.d and #relays > 0 then
                table.remove(relays, selectedIdx)
                saveConfig(); applyRedstone(); broadcastSync()
            elseif p1 == keys.s then
                cycleMonitorScale()
            end
        elseif ev == "mouse_scroll" then
            scrollOffset = math.max(0, math.min(scrollOffset + p1, math.max(0, #relays - 1)))
        elseif ev == "mouse_click" or ev == "monitor_touch" then
            local targetMap = (ev == "monitor_touch") and monRowMap or termRowMap
            local targetW = (ev == "monitor_touch" and mon) and select(1, mon.getSize()) or select(1, term.getSize())
            local targetH = (ev == "monitor_touch" and mon) and select(2, mon.getSize()) or select(2, term.getSize())

            if p2 == targetW then
                if p3 == 2 then scrollOffset = math.max(0, scrollOffset - 1)
                elseif p3 == targetH - 1 then scrollOffset = math.min(math.max(0, #relays - (targetH - 2)), scrollOffset + 1) end
            else
                local clickedIdx = targetMap[p3]
                if clickedIdx then selectedIdx = clickedIdx; triggerRelay(selectedIdx) end
            end
        elseif ev == "modem_message" and type(msg) == "table" then
            if msg.cmd == "toggle" then triggerRelay(msg.index)
            elseif msg.cmd == "get" then broadcastSync()
            elseif msg.cmd == "updateConfig" then
                relays = msg.data or {}; saveConfig(); applyRedstone(); broadcastSync()
            elseif msg.cmd == "location" then
                lastPlayerPos = { x = msg.x, y = msg.y, z = msg.z }
                evaluateAutomations()
            end
        end
    end
end

-- Pocket Client Engine (Parallel UI & Network to prevent GPS event stealing)
local function runClient()
    if modem then modem.transmit(PORT, PORT, { cmd = "get" }) end

    local function clientUIThread()
        local heartbeatTimer = os.startTimer(5.0)

        while true do
            selectedIdx = math.max(1, math.min(selectedIdx, math.max(1, #relays)))
            local termRowMap = drawUI(term, selectedIdx, scrollOffset)

            local ev, p1, p2, p3, msg = os.pullEvent()

            if ev == "timer" and p1 == heartbeatTimer then
                if modem then modem.transmit(PORT, PORT, { cmd = "get" }) end
                heartbeatTimer = os.startTimer(5.0)
            elseif ev == "key" then
                if p1 == keys.up then 
                    selectedIdx = math.max(1, selectedIdx - 1)
                    if selectedIdx - 1 < scrollOffset then scrollOffset = selectedIdx - 1 end
                elseif p1 == keys.down then 
                    selectedIdx = math.min(#relays, selectedIdx + 1)
                    local _, h = term.getSize()
                    if selectedIdx > scrollOffset + (h - 2) then scrollOffset = selectedIdx - (h - 2) end
                elseif (p1 == keys.enter or p1 == keys.space) and #relays > 0 then
                    if modem then modem.transmit(PORT, PORT, { cmd = "toggle", index = selectedIdx }) end
                elseif p1 == keys.a then
                    local newR = promptRelayConfig(nil)
                    table.insert(relays, newR)
                    if modem then modem.transmit(PORT, PORT, { cmd = "updateConfig", data = relays }) end
                elseif p1 == keys.e and #relays > 0 then
                    relays[selectedIdx] = promptRelayConfig(selectedIdx)
                    if modem then modem.transmit(PORT, PORT, { cmd = "updateConfig", data = relays }) end
                elseif p1 == keys.t and #relays > 0 then
                    promptTriggerConfig(selectedIdx)
                    if modem then modem.transmit(PORT, PORT, { cmd = "updateConfig", data = relays }) end
                elseif p1 == keys.p and #relays > 0 then
                    local r = relays[selectedIdx]
                    if r.override then
                        r.override = false
                        r.paused = false
                    else
                        r.paused = not r.paused
                    end
                    if modem then modem.transmit(PORT, PORT, { cmd = "updateConfig", data = relays }) end
                elseif p1 == keys.d and #relays > 0 then
                    table.remove(relays, selectedIdx)
                    if modem then modem.transmit(PORT, PORT, { cmd = "updateConfig", data = relays }) end
                end
            elseif ev == "mouse_scroll" then
                scrollOffset = math.max(0, math.min(scrollOffset + p1, math.max(0, #relays - 1)))
            elseif ev == "mouse_click" then
                local w, h = term.getSize()
                if p2 == w then
                    if p3 == 2 then scrollOffset = math.max(0, scrollOffset - 1)
                    elseif p3 == h - 1 then scrollOffset = math.min(math.max(0, #relays - (h - 2)), scrollOffset + 1) end
                else
                    local clickedIdx = termRowMap[p3]
                    if clickedIdx then
                        selectedIdx = clickedIdx
                        if modem then modem.transmit(PORT, PORT, { cmd = "toggle", index = selectedIdx }) end
                    end
                end
            elseif ev == "modem_message" and type(msg) == "table" and msg.cmd == "sync" then
                relays = msg.data or {}
            end
        end
    end

    local function clientGPSThread()
        local gpsTimer = os.startTimer(0.5)

        while true do
            local ev, p1 = os.pullEvent()
            if ev == "timer" and p1 == gpsTimer then
                local x, y, z = gps.locate(0.2)
                local delay = 2.0
                if x and modem then
                    modem.transmit(PORT, PORT, { cmd = "location", x = x, y = y, z = z })
                    delay = getDynamicGPSInterval(x, y, z)
                end
                gpsTimer = os.startTimer(delay)
            end
        end
    end

    parallel.waitForAny(clientUIThread, clientGPSThread)
end

if isPocket then runClient() else runHost() end

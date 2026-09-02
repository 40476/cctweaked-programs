-- client.lua
-- Feature-rich Radio Receiver with Tuning, Volume, and Anti-Starvation Heartbeats

local dfpwm = require("cc.audio.dfpwm")
local speaker = peripheral.find("speaker") or error("No speaker attached!")
local modem = peripheral.find("modem", function(n, p) return p.isWireless() end) 
    or peripheral.find("modem") 
    or error("No modem attached!")

-- State Variables
local CHANNEL = 101
local METADATA_CHANNEL = CHANNEL + 1
local SYNC_CHANNEL = CHANNEL + 2
local PRIVATE_SYNC_CHANNEL = math.random(60000, 65000)

local volume = 1.0
local audioQueue = {}
local isBuffering = true
local currentStation = "Unknown Station"
local currentTitle = "Waiting for broadcast..."
local clientStatus = "Requesting sync..."
local last_heartbeat = os.clock()

local decoder = dfpwm.make_decoder()
local supports_volume = true -- Flag to track if the speaker accepts volume args

local function tuneModems()
    modem.closeAll()
    METADATA_CHANNEL = CHANNEL + 1
    SYNC_CHANNEL = CHANNEL + 2
    modem.open(CHANNEL)
    modem.open(METADATA_CHANNEL)
    modem.open(PRIVATE_SYNC_CHANNEL)
end
tuneModems()

-- === UI & EVENT HANDLING === --
local function drawUI()
    term.setBackgroundColor(colors.black)
    term.clear()
    
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.red)
    term.setTextColor(colors.white)
    term.clearLine()
    term.setCursorPos(2, 1)
    term.write("Radio Receiver")
    
    term.setBackgroundColor(colors.black)
    term.setCursorPos(2, 3)
    term.setTextColor(colors.cyan)
    term.write("Station: ")
    term.setTextColor(colors.white)
    term.write(currentStation)

    term.setCursorPos(2, 5)
    term.setTextColor(colors.yellow)
    term.write("Now Playing:")
    term.setCursorPos(2, 6)
    term.setTextColor(colors.white)
    term.write(currentTitle)
    
    term.setCursorPos(2, 9)
    term.setTextColor(colors.green)
    term.write("Volume: [ - ] " .. math.floor(volume * 100) .. "% [ + ]")
    term.setCursorPos(2, 11)
    term.write("Tuning: [ < ] CH: " .. CHANNEL .. " [ > ]")
    
    term.setCursorPos(2, 14)
    term.setTextColor(colors.cyan)
    term.write("Status: ")
    if clientStatus:match("Lost Signal") then term.setTextColor(colors.red) else term.setTextColor(colors.white) end
    term.write(clientStatus)
end

local function setStatus(msg)
    if clientStatus ~= msg then
        clientStatus = msg
        drawUI()
    end
end

local function changeChannel(diff)
    CHANNEL = math.max(1, CHANNEL + diff)
    tuneModems()
    currentStation = "Unknown Station"
    currentTitle = "Waiting for broadcast..."
    audioQueue = {}
    isBuffering = true
    setStatus("Tuned to " .. CHANNEL .. ". Syncing...")
    modem.transmit(SYNC_CHANNEL, PRIVATE_SYNC_CHANNEL, "SYNC_REQUEST")
end

local function changeVolume(diff)
    volume = math.max(0.0, math.min(3.0, volume + diff))
    drawUI()
end

local function handleUIEvents()
    while true do
        local e, p1, p2, p3 = os.pullEvent()
        if e == "mouse_click" then
            if p3 == 9 then
                if p2 >= 9 and p2 <= 13 then changeVolume(-0.1)
                elseif p2 >= 22 and p2 <= 26 then changeVolume(0.1) end
            elseif p3 == 11 then
                if p2 >= 9 and p2 <= 13 then changeChannel(-1)
                elseif p2 >= 22 and p2 <= 26 then changeChannel(1) end
            end
        elseif e == "key" then
            if p1 == keys.up then changeVolume(0.1)
            elseif p1 == keys.down then changeVolume(-0.1)
            elseif p1 == keys.left then changeChannel(-1)
            elseif p1 == keys.right then changeChannel(1) end
        end
    end
end

-- === AUDIO RECEIVER LOGIC === --
modem.transmit(SYNC_CHANNEL, PRIVATE_SYNC_CHANNEL, "SYNC_REQUEST")

local function receiveLoop()
    while true do
        local event, side, channel, replyChannel, message = os.pullEvent("modem_message")
        
        if (channel == CHANNEL or channel == PRIVATE_SYNC_CHANNEL) and type(message) == "string" then
            if message:match("^{") then
                local ok, data = pcall(textutils.unserializeJSON, message)
                -- Safety check: verify data is actually a table before indexing
                if ok and type(data) == "table" and data.type == "song" then
                    currentStation = data.station or "Unknown Station"
                    currentTitle = data.title or "Unknown"
                    drawUI()
                end
            else
                local chunkSize = 4 * 1024
                for i = 1, #message, chunkSize do
                    table.insert(audioQueue, decoder(message:sub(i, i + chunkSize - 1)))
                end
                os.queueEvent("new_audio")
            end
            
        elseif channel == METADATA_CHANNEL and type(message) == "string" then
            local ok, data = pcall(textutils.unserializeJSON, message)
            -- Safety check: verify data is actually a table before indexing
            if ok and type(data) == "table" then
                if data.type == "heartbeat" then
                    last_heartbeat = os.clock() -- Reset starvation timer!
                elseif data.type == "control" then
                    setStatus("Control Command: " .. tostring(data.command))
                elseif data.type == "song" then
                    currentStation = data.station or "Unknown Station"
                    currentTitle = data.title or "Unknown"
                    decoder = dfpwm.make_decoder()
                    audioQueue = {}
                    isBuffering = true
                    setStatus("Buffering...")
                end
            end
        end
    end
end

local function playLoop()
    while true do
        if isBuffering and #audioQueue < 4 then
            local timeout = os.startTimer(1.0)
            while isBuffering and #audioQueue < 4 do
                local event_data = {os.pullEvent()}
                if event_data[1] == "timer" and event_data[2] == timeout then
                    -- Check if we are kept alive by a heartbeat packet (1.5 seconds)
                    if os.clock() > last_heartbeat + 1.5 then
                        if #audioQueue > 0 then
                            isBuffering = false
                        else
                            speaker.playNote("bell", 1, 12)
                            setStatus("Lost Signal! Syncing...")
                            modem.transmit(SYNC_CHANNEL, PRIVATE_SYNC_CHANNEL, "SYNC_REQUEST")
                            timeout = os.startTimer(1.0)
                        end
                    else
                        timeout = os.startTimer(1.0) -- Heartbeat saved us, keep waiting safely
                    end
                elseif event_data[1] == "new_audio" and #audioQueue >= 4 then
                    isBuffering = false
                    break
                end
            end
        elseif #audioQueue > 0 then
            setStatus("Playing")
            isBuffering = false
            local buffer = table.remove(audioQueue, 1)
            local success = false
            
            -- Attempt to play with volume. Safely catch errors if volume isn't supported.
            if supports_volume then
                local ok, res = pcall(speaker.playAudio, buffer, volume)
                if ok then
                    success = res
                else
                    -- It errored! This version of CC doesn't support the volume argument.
                    supports_volume = false
                    success = speaker.playAudio(buffer)
                end
            else
                -- We already know it doesn't support volume, skip the pcall.
                success = speaker.playAudio(buffer)
            end
            
            -- If it failed to queue (speaker is full), wait until it empties and try again
            while not success do
                os.pullEvent("speaker_audio_empty")
                if supports_volume then
                    success = speaker.playAudio(buffer, volume)
                else
                    success = speaker.playAudio(buffer)
                end
            end
        else
            isBuffering = true
            setStatus("Lost Signal! Syncing...")
            speaker.playNote("bell", 1, 12)
            modem.transmit(SYNC_CHANNEL, PRIVATE_SYNC_CHANNEL, "SYNC_REQUEST")
        end
    end
end

drawUI()
parallel.waitForAny(handleUIEvents, receiveLoop, playLoop)
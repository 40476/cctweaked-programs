-- client.lua
-- Receives DFPWM broadcast over modem and decodes it to a speaker

local dfpwm = require("cc.audio.dfpwm")
local speaker = peripheral.find("speaker") or error("No speaker attached!")
local modem = peripheral.find("modem", function(n, p) return p.isWireless() end) 
    or peripheral.find("modem") 
    or error("No modem attached!")
    
local CHANNEL = 101
local METADATA_CHANNEL = CHANNEL + 1
local SYNC_CHANNEL = CHANNEL + 2

-- Pick a random, temporary private channel for this specific client to receive its sync data
local PRIVATE_SYNC_CHANNEL = math.random(10000, 65000)

modem.open(CHANNEL)
modem.open(METADATA_CHANNEL)
modem.open(PRIVATE_SYNC_CHANNEL)
local decoder = dfpwm.make_decoder()

-- UI State Variables
local audioQueue = {}
local isBuffering = true
local currentStation = "Unknown Station"
local currentTitle = "Waiting for broadcast..."
local currentArtist = ""
local clientStatus = ""

-- === UI FUNCTIONS === --
local function drawUI()
    term.setBackgroundColor(colors.black)
    term.clear()
    
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.red)
    term.setTextColor(colors.white)
    term.clearLine()
    term.setCursorPos(2, 1)
    term.write("Radio Receiver - CH: " .. CHANNEL)
    
    term.setBackgroundColor(colors.black)
    term.setCursorPos(2, 3)
    term.setTextColor(colors.cyan)
    term.write("Station:")
    term.setCursorPos(2, 4)
    term.setTextColor(colors.white)
    term.write(currentStation)

    term.setCursorPos(2, 6)
    term.setTextColor(colors.yellow)
    term.write("Now Playing:")
    
    term.setCursorPos(2, 7)
    term.setTextColor(colors.white)
    term.write(currentTitle)
    
    if currentArtist ~= "" then
        term.setCursorPos(2, 8)
        term.setTextColor(colors.lightGray)
        term.write(currentArtist)
    end
    
    term.setCursorPos(2, 11)
    term.setTextColor(colors.cyan)
    term.write("Status: ")
    
    -- Color code the status for errors!
    if clientStatus:match("Lost Signal") then
        term.setTextColor(colors.red)
    else
        term.setTextColor(colors.white)
    end
    term.write(clientStatus)
end

local function setStatus(msg)
    if clientStatus ~= msg then
        clientStatus = msg
        drawUI()
    end
end
-- ==================== --

setStatus("Requesting sync from station...")

-- Send the initial sync request!
modem.transmit(SYNC_CHANNEL, PRIVATE_SYNC_CHANNEL, "SYNC_REQUEST")

-- Task 1: Only listens to the modem and handles incoming data
local function receiveLoop()
    while true do
        local event, side, channel, replyChannel, message = os.pullEvent("modem_message")
        
        -- Accept audio from the LIVE channel OR our PRIVATE catch-up channel
        if (channel == CHANNEL or channel == PRIVATE_SYNC_CHANNEL) and type(message) == "string" then
            
            -- If it's a metadata packet masquerading as a string (from sync)
            if message:match("^{") then
                local ok, data = pcall(textutils.unserialiseJSON, message)
                if ok and type(data) == "table" then
                    currentStation = data.station or "Unknown Station"
                    currentTitle = data.title or "Unknown"
                    currentArtist = data.artist or ""
                    drawUI()
                end
            else
                -- Otherwise, it's audio! Slice it up.
                local chunkSize = 4 * 1024
                for i = 1, #message, chunkSize do
                    local slice = message:sub(i, i + chunkSize - 1)
                    local buffer = decoder(slice)
                    table.insert(audioQueue, buffer)
                end
                os.queueEvent("new_audio")
            end
            
        elseif channel == METADATA_CHANNEL and type(message) == "string" then
            -- Decode live metadata
            local ok, data = pcall(textutils.unserialiseJSON, message)
            if ok and type(data) == "table" then
                currentStation = data.station or "Unknown Station"
                currentTitle = data.title or "Unknown"
                currentArtist = data.artist or ""
                
                decoder = dfpwm.make_decoder()
                audioQueue = {}
                isBuffering = true
                setStatus("Buffering...")
            end
        end
    end
end

-- Task 2: Only handles pushing audio to the speaker
local function playLoop()
    while true do
        if isBuffering and #audioQueue < 4 then
            
            local timeout = os.startTimer(0.5)
            
            while isBuffering and #audioQueue < 4 do
                local event_data = {os.pullEvent()}
                
                if event_data[1] == "timer" and event_data[2] == timeout then
                    if #audioQueue > 0 then
                        -- We got at least SOME audio, force play it so it doesn't stay silent
                        isBuffering = false
                    else
                        -- Oh no, we are completely starved of audio mid-stream!
                        -- Beep the speaker, show an error, and request a sync packet!
                        speaker.playNote("bell", 1, 12)
                        setStatus("Lost Signal! Syncing...")
                        modem.transmit(SYNC_CHANNEL, PRIVATE_SYNC_CHANNEL, "SYNC_REQUEST")
                        
                        -- Reset the timeout timer so it beeps again if it fails
                        timeout = os.startTimer(0.5)
                    end
                elseif event_data[1] == "new_audio" then
                    if #audioQueue >= 4 then
                        isBuffering = false
                        break
                    end
                end
            end
            
        elseif #audioQueue > 0 then
            setStatus("Playing")
            isBuffering = false
            local buffer = table.remove(audioQueue, 1)
            
            while not speaker.playAudio(buffer) do
                os.pullEvent("speaker_audio_empty")
            end
            
        else
            -- We ran out of audio! Switch back to buffering mode and instantly trigger a sync.
            isBuffering = true
            setStatus("Lost Signal! Syncing...")
            speaker.playNote("bell", 1, 12)
            modem.transmit(SYNC_CHANNEL, PRIVATE_SYNC_CHANNEL, "SYNC_REQUEST")
        end
    end
end

parallel.waitForAny(receiveLoop, playLoop)
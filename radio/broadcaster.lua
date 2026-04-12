-- broadcaster.lua
-- Reads a playlist, downloads/converts streams, and broadcasts over a modem

local CHANNEL = 101
local METADATA_CHANNEL = CHANNEL + 1
local SYNC_CHANNEL = CHANNEL + 2

local modem = peripheral.find("modem", function(n, p) return p.isWireless() end) 
    or peripheral.find("modem") 
    or error("No modem found attached to the broadcaster!")

local SHUFFLE_PLAYLIST = false

-- Your backend URL, API Version, and Station Name
local YOUTUBE_BACKEND_URL = "https://ipod-2to6magyna-uc.a.run.app/" 
local API_VERSION = "2.1"
local STATION_NAME = "DEFAULT STATION NAME"

local now_playing = nil
local status_text = "Starting up..."
local history_buffer = {} -- Stores the last 8 chunks for sync requests

-- Open the sync channel to listen for new clients
modem.open(SYNC_CHANNEL)

-- === UI FUNCTIONS === --
local function drawUI()
    term.setBackgroundColor(colors.black)
    term.clear()
    
    -- Header
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    term.setCursorPos(2, 1)
    term.write(STATION_NAME .. " - Broadcaster")
    
    -- Main Area
    term.setBackgroundColor(colors.black)
    
    term.setCursorPos(2, 3)
    term.setTextColor(colors.yellow)
    term.write("Now Playing:")
    
    term.setCursorPos(2, 4)
    term.setTextColor(colors.white)
    if now_playing then
        term.write(now_playing.title or "Unknown Title")
        term.setCursorPos(2, 5)
        term.setTextColor(colors.lightGray)
        term.write(now_playing.artist or "")
    else
        term.write("Idle / Buffering...")
    end
    
    term.setCursorPos(2, 8)
    term.setTextColor(colors.cyan)
    term.write("Status: ")
    term.setTextColor(colors.white)
    term.write(status_text)
    
    term.setCursorPos(2, 10)
    term.setTextColor(colors.gray)
    term.write("Broadcasting on Channel " .. CHANNEL)
end

local function setStatus(msg)
    status_text = msg
    drawUI()
end
-- ==================== --

local function urlEncode(str)
    if str then
        str = string.gsub(str, "\n", "\r\n")
        str = string.gsub(str, "([^%w ])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
        str = string.gsub(str, " ", "%%20")
    end
    return str
end

local function getDynamicText(text)
    local timeStr = textutils.formatTime(os.time("ingame"), false) 
    return text:gsub("!!time!!", timeStr)
end

local function extractYTId(url)
    local id = url:match("v=([%w%-_]+)")
    if not id then
        id = url:match("youtu%.be/([%w%-_]+)")
    end
    return id
end

-- Broadcast song metadata (title, artist, station) on the metadata channel
local function broadcastMetadata(songInfo)
    if not songInfo then return end
    
    local metadata = textutils.serialiseJSON({
        title = songInfo.title or "",
        artist = songInfo.artist or "",
        station = STATION_NAME,
    })
    modem.transmit(METADATA_CHANNEL, METADATA_CHANNEL, metadata)
end

-- Custom sleep function that listens for client sync requests while yielding
local function syncAwareSleep(duration)
    if duration <= 0 then
        -- Yield for 1 tick to prevent "Too long without yielding" crash, but process quickly
        os.queueEvent("fake_yield")
        os.pullEvent("fake_yield")
        return
    end
    
    local timer = os.startTimer(duration)
    while true do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
        
        if event == "timer" and p1 == timer then
            break -- Sleep is finished
            
        elseif event == "modem_message" and p2 == SYNC_CHANNEL then
            -- A client sent a message on the Sync Channel
            if type(p4) == "string" and p4 == "SYNC_REQUEST" then
                local clientReplyChannel = p3
                
                -- Send the client the current metadata so their UI updates
                if now_playing then
                    local meta = textutils.serialiseJSON({
                        title = now_playing.title or "",
                        artist = now_playing.artist or "",
                        station = STATION_NAME
                    })
                    modem.transmit(clientReplyChannel, SYNC_CHANNEL, meta)
                end
                
                -- Blast the last 8 chunks of audio directly to that client
                for _, history_chunk in ipairs(history_buffer) do
                    modem.transmit(clientReplyChannel, SYNC_CHANNEL, history_chunk)
                end
            end
        end
    end
end

-- Uses the async event pattern from music.lua
local function playStream(url)
    setStatus("Requesting stream from server...")
    http.request({url = url, binary = true})
    
    while true do
        local event, param1, param2 = os.pullEvent()
        
        if event == "http_success" and param1 == url then
            local handle = param2
            
            -- Read first 4 bytes to check format
            local start = handle.read(4)
            if start == "RIFF" then
                setStatus("Skipping: WAV not supported!")
                handle.close()
                os.sleep(2)
                return
            end
            
            setStatus("Broadcasting live audio...")
            
            -- Broadcast metadata before streaming audio
            if now_playing then
                broadcastMetadata(now_playing)
            end
            
            local CHUNK_SIZE = 16 * 1024
            local SECONDS_PER_CHUNK = CHUNK_SIZE / 6000
            local TARGET_BUFFER = 8
            
            local stream_start_time = os.clock()
            local chunks_sent = 0
            history_buffer = {} -- Clear the history for the new track
            
            -- Stream the rest of the file
            while true do
                local chunk = handle.read(CHUNK_SIZE)
                if not chunk or #chunk == 0 then break end
                
                -- Transmit the raw DFPWM chunk
                modem.transmit(CHANNEL, CHANNEL, chunk)
                chunks_sent = chunks_sent + 1
                
                -- Keep a rolling history of the last 8 chunks for new clients
                table.insert(history_buffer, chunk)
                if #history_buffer > TARGET_BUFFER then
                    table.remove(history_buffer, 1)
                end
                
                -- === Internal Queue Simulation ===
                -- Calculate how many chunks the client has theoretically played based on real time
                local elapsed_time = os.clock() - stream_start_time
                local simulated_chunks_played = elapsed_time / SECONDS_PER_CHUNK
                local buffered_chunks = chunks_sent - simulated_chunks_played
                
                if buffered_chunks >= TARGET_BUFFER then
                    -- The buffer is full! Sleep exactly long enough for the client to "play" a chunk
                    -- so the buffered amount drops back down to (TARGET_BUFFER - 1)
                    local sleep_duration = (buffered_chunks - (TARGET_BUFFER - 1)) * SECONDS_PER_CHUNK
                    syncAwareSleep(math.max(0, sleep_duration))
                else
                    -- Yield for 1 tick so we don't crash the computer, but stream as fast as possible 
                    -- to fill the client buffer!
                    syncAwareSleep(0)
                end
            end
            
            handle.close()
            setStatus("Finished broadcasting item.")
            break
            
        elseif event == "http_failure" and param1 == url then
            setStatus("HTTP request failed!")
            os.sleep(2)
            break
        end
    end
end

local function loadPlaylist()
    local lines = {}
    local songPool = {}
    
    if not fs.exists("playlist.txt") then
        error("playlist.txt not found! Please create it.")
    end
    
    local f = fs.open("playlist.txt", "r")
    for line in f.readLine do
        table.insert(lines, line)
        if line:match("^!song (https?://)") then
            table.insert(songPool, line)
        end
    end
    f.close()
    
    return lines, songPool
end

local function main()
    drawUI()
    
    while true do
        local playlist, songPool = loadPlaylist()
        
        if SHUFFLE_PLAYLIST then
            for i = #playlist, 2, -1 do
                local j = math.random(i)
                playlist[i], playlist[j] = playlist[j], playlist[i]
            end
        end

        for _, line in ipairs(playlist) do
            if line:sub(1, 5) == "!song" then
                local url = line:sub(7)
                
                if url:lower() == "pickrandom" then
                    if #songPool > 0 then
                        url = songPool[math.random(1, #songPool)]:sub(7)
                        setStatus("Picked random song...")
                    else
                        setStatus("No valid songs found to pick randomly.")
                        url = nil
                    end
                end
                
                if url then
                    local id = extractYTId(url)
                    if id then
                        now_playing = { title = "YouTube ID: " .. id, artist = "" }
                        local final_url = YOUTUBE_BACKEND_URL .. "?v=" .. API_VERSION .. "&id=" .. urlEncode(id)
                        playStream(final_url)
                    else
                        setStatus("Invalid YouTube URL: " .. url)
                        os.sleep(2)
                    end
                end
                
            elseif line:sub(1, 4) == "!tts" then
                local text = getDynamicText(line:sub(6))
                now_playing = { title = "TTS Announcement", artist = "System Host" }
                
                local url = "https://music.madefor.cc/tts?text=" .. urlEncode(text)
                playStream(url)
                
            elseif line:sub(1,5) == "!info" then
                now_playing = nil
                setStatus("Station: " .. STATION_NAME)
            end
            
            now_playing = nil
            setStatus("Idle")
            os.sleep(1) -- Brief pause between items
        end
    end
end

main()
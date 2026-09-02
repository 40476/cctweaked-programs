local CHANNEL
local METADATA_CHANNEL
local SYNC_CHANNEL

local modem = peripheral.find("modem", function(n, p) return p.isWireless() end) 
    or peripheral.find("modem") 
    or error("No modem found attached to the broadcaster!")

-- Default Config Options
local config = {
    CHANNEL = 101,
    STATION_NAME = "CC:Radio Station",
    BACKEND_URL = "https://ipod-2to6magyna-uc.a.run.app/",
    API_VERSION = "2.1",
    SHUFFLE_PLAYLIST = "false"
}
local playlist = {}

local now_playing = nil
local status_text = "Starting up..."
local history_buffer = {}

-- UI State Variables
local UI_STATE = "DASHBOARD"
local editor_sel = 1
local input_text = ""

-- === CONFIG & CACHE MANAGEMENT === --
local function getFilenameFor(cmd)
    if cmd:sub(1,5) == "!song" then
        local id = cmd:match("v=([%w%-_]+)") or cmd:match("youtu%.be/([%w%-_]+)")
        if id then return "yt_" .. id .. ".dfpwm" end
    elseif cmd:sub(1,4) == "!tts" then
        local text = cmd:sub(6):gsub("[%W]", "_"):sub(1, 20)
        return "tts_" .. text .. ".dfpwm"
    end
    return nil
end

-- Dynamically find internal and external drive cache folders
local function getCacheDirectories()
    local dirs = {"radio_cache"} -- Default internal fallback
    for _, name in ipairs(fs.list("/")) do
        if name:match("^disk%d+$") and fs.isDir(name) then
            table.insert(dirs, name .. "/radio_cache")
        end
    end
    return dirs
end

local function cleanCache()
    local valid_files = {}
    for _, item in ipairs(playlist) do
        local fn = getFilenameFor(item)
        if fn then valid_files[fn] = true end
    end
    
    for _, dir in ipairs(getCacheDirectories()) do
        if not fs.exists(dir) then 
            pcall(fs.makeDir, dir) 
        else
            for _, file in ipairs(fs.list(dir)) do
                if not valid_files[file] then
                    pcall(fs.delete, dir .. "/" .. file)
                end
            end
        end
    end
end

local function getCachedPath(filename)
    if not filename then return nil end
    for _, dir in ipairs(getCacheDirectories()) do
        local path = dir .. "/" .. filename
        if fs.exists(path) then return path end
    end
    return nil
end

local function getBestSaveLocation(filename)
    if not filename then return nil end
    local best_dir = nil
    local max_space = 0
    
    for _, dir in ipairs(getCacheDirectories()) do
        if not fs.exists(dir) then pcall(fs.makeDir, dir) end
        local space = fs.getFreeSpace(dir)
        if space > max_space then
            max_space = space
            best_dir = dir
        end
    end
    
    -- Require at least ~100KB of free space to bother starting a cache file
    if best_dir and max_space > 100000 then
        return best_dir .. "/" .. filename
    end
    return nil
end

local function loadConfig()
    playlist = {}
    if not fs.exists("config.txt") then
        local f = fs.open("config.txt", "w")
        for k, v in pairs(config) do f.writeLine("@" .. k .. " " .. tostring(v)) end
        f.writeLine("!tts Hello and welcome to the station!")
        f.writeLine("!song https://youtu.be/dQw4w9WgXcQ")
        f.close()
    end
    
    for line in io.lines("config.txt") do
        if line:sub(1,1) == "@" then
            local key, val = line:match("^@(%S+)%s+(.*)")
            if key and val then config[key] = val end
        elseif line:sub(1,1) == "!" or line:sub(1,1) == "#" then
            table.insert(playlist, line)
        end
    end
    
    CHANNEL = tonumber(config.CHANNEL) or 101
    METADATA_CHANNEL = CHANNEL + 1
    SYNC_CHANNEL = CHANNEL + 2
    modem.open(SYNC_CHANNEL)
    cleanCache()
end

local function saveConfig()
    local f = fs.open("config.txt", "w")
    for k, v in pairs(config) do f.writeLine("@" .. k .. " " .. tostring(v)) end
    f.writeLine("")
    for _, item in ipairs(playlist) do f.writeLine(item) end
    f.close()
    loadConfig()
end

-- === UI FUNCTIONS === --
local function drawUI()
    term.setBackgroundColor(colors.black)
    term.clear()
    
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    term.setCursorPos(2, 1)
    term.write(config.STATION_NAME .. " - Broadcaster")
    
    term.setBackgroundColor(colors.black)
    
    if UI_STATE == "DASHBOARD" then
        term.setCursorPos(2, 3)
        term.setTextColor(colors.yellow)
        term.write("Now Playing:")
        term.setCursorPos(2, 4)
        term.setTextColor(colors.white)
        term.write(now_playing and (now_playing.title or "Unknown") or "Idle")
        
        term.setCursorPos(2, 7)
        term.setTextColor(colors.cyan)
        term.write("Status: ")
        term.setTextColor(colors.white)
        term.write(status_text)
        
        term.setCursorPos(2, 9)
        term.setTextColor(colors.gray)
        term.write("Channel " .. CHANNEL .. " | Drives: " .. #getCacheDirectories())
        
        term.setCursorPos(2, 12)
        term.setTextColor(colors.green)
        term.write("[ E ] Edit Config & Playlist")
        
    elseif UI_STATE == "EDITOR" then
        term.setCursorPos(2, 3)
        term.setTextColor(colors.cyan)
        term.write("--- Playlist Editor ---")
        
        for i = 1, 7 do
            local idx = editor_sel - 3 + i
            term.setCursorPos(2, 4 + i)
            if idx >= 1 and idx <= #playlist then
                if idx == editor_sel then
                    term.setTextColor(colors.yellow)
                    term.write("> " .. string.sub(playlist[idx], 1, 40))
                else
                    term.setTextColor(colors.lightGray)
                    term.write("  " .. string.sub(playlist[idx], 1, 40))
                end
            end
        end
        
        term.setCursorPos(2, 13)
        term.setTextColor(colors.green)
        term.write("[A] Add  [Del] Remove  [Esc] Save & Exit")
        
    elseif UI_STATE == "INPUT" then
        term.setCursorPos(2, 3)
        term.setTextColor(colors.yellow)
        term.write("Enter new line (!song, !tts, #cmd):")
        term.setCursorPos(2, 5)
        term.setTextColor(colors.white)
        term.write("> " .. input_text)
    end
end

local function setStatus(msg)
    status_text = msg
    drawUI()
end

local function handleUIEvents()
    while true do
        local e, p1 = os.pullEvent()
        if e == "key" then
            if UI_STATE == "DASHBOARD" and p1 == keys.e then
                UI_STATE = "EDITOR"
                editor_sel = 1
                drawUI()
            elseif UI_STATE == "EDITOR" then
                if p1 == keys.up then 
                    editor_sel = math.max(1, editor_sel - 1)
                elseif p1 == keys.down then 
                    editor_sel = math.min(#playlist, editor_sel + 1)
                elseif p1 == keys.delete and #playlist > 0 then
                    table.remove(playlist, editor_sel)
                    if editor_sel > #playlist then editor_sel = math.max(1, #playlist) end
                elseif p1 == keys.a then
                    UI_STATE = "INPUT"
                    input_text = ""
                elseif p1 == keys.escape then
                    saveConfig()
                    UI_STATE = "DASHBOARD"
                end
                drawUI()
            elseif UI_STATE == "INPUT" then
                if p1 == keys.backspace then
                    input_text = input_text:sub(1, -2)
                elseif p1 == keys.enter then
                    if input_text ~= "" then table.insert(playlist, input_text) end
                    UI_STATE = "EDITOR"
                elseif p1 == keys.escape then
                    UI_STATE = "EDITOR"
                end
                drawUI()
            end
        elseif e == "char" and UI_STATE == "INPUT" then
            input_text = input_text .. p1
            drawUI()
        end
    end
end

-- === AUDIO STREAMING LOGIC === --
local function broadcastMetadata(songInfo)
    if not songInfo then return end
    local metadata = textutils.serialiseJSON({
        type = "song",
        title = songInfo.title or "",
        artist = songInfo.artist or "",
        station = config.STATION_NAME
    })
    modem.transmit(METADATA_CHANNEL, METADATA_CHANNEL, metadata)
end

local function syncAwareSleep(duration)
    if duration <= 0 then
        os.queueEvent("fake_yield")
        os.pullEvent("fake_yield")
        return
    end
    local timer = os.startTimer(duration)
    while true do
        local event, p1, p2, p3, p4 = os.pullEvent()
        if event == "timer" and p1 == timer then
            break
        elseif event == "modem_message" and p2 == SYNC_CHANNEL and type(p4) == "string" and p4 == "SYNC_REQUEST" then
            if now_playing then
                modem.transmit(p3, SYNC_CHANNEL, textutils.serialiseJSON({
                    type = "song", title = now_playing.title or "", station = config.STATION_NAME
                }))
            end
            for _, history_chunk in ipairs(history_buffer) do
                modem.transmit(p3, SYNC_CHANNEL, history_chunk)
            end
        end
    end
end

local function streamAudio(reader_func)
    if now_playing then broadcastMetadata(now_playing) end
    
    local CHUNK_SIZE = 16 * 1024
    local SECONDS_PER_CHUNK = CHUNK_SIZE / 6000
    local TARGET_BUFFER = 12 
    local stream_start_time = os.clock()
    local chunks_sent = 0
    history_buffer = {}
    
    while true do
        local chunk = reader_func(CHUNK_SIZE)
        if not chunk or #chunk == 0 then break end
        
        modem.transmit(CHANNEL, CHANNEL, chunk)
        chunks_sent = chunks_sent + 1
        
        table.insert(history_buffer, chunk)
        if #history_buffer > TARGET_BUFFER then table.remove(history_buffer, 1) end
        
        local elapsed = os.clock() - stream_start_time
        local simulated = elapsed / SECONDS_PER_CHUNK
        local buffered = chunks_sent - simulated
        
        if buffered >= TARGET_BUFFER then
            syncAwareSleep(math.max(0, (buffered - (TARGET_BUFFER - 1)) * SECONDS_PER_CHUNK))
        else
            syncAwareSleep(0)
        end
    end
    setStatus("Finished broadcasting item.")
end

local function playStream(url, filename)
    local cached_path = getCachedPath(filename)
    
    if cached_path then
        setStatus("Playing from local disk...")
        local f = fs.open(cached_path, "rb")
        streamAudio(function(size) return f.read(size) end)
        f.close()
    else
        setStatus("Fetching from internet...")
        http.request({url = url, binary = true})
        local heartbeat = os.startTimer(1)
        
        while true do
            local event, p1, p2 = os.pullEvent()
            if event == "timer" and p1 == heartbeat then
                modem.transmit(METADATA_CHANNEL, METADATA_CHANNEL, textutils.serialiseJSON({type="heartbeat"}))
                heartbeat = os.startTimer(1)
            elseif event == "http_success" and p1 == url then
                local handle = p2
                if handle.read(4) == "RIFF" then handle.close(); return end
                
                setStatus("Broadcasting & Caching...")
                local save_path = getBestSaveLocation(filename)
                local f = nil
                if save_path then f = fs.open(save_path, "wb") end
                
                streamAudio(function(size)
                    local chunk = handle.read(size)
                    if chunk and f then
                        -- Safely write to disk to prevent "Out of space" crashes mid-song
                        local ok = pcall(function() f.write(chunk) end)
                        if not ok then
                            f.close()
                            f = nil
                            pcall(fs.delete, save_path) -- Delete partial file
                            setStatus("Drive full! Streaming Live...")
                        end
                    end
                    return chunk
                end)
                
                if f then f.close() end
                handle.close()
                break
            elseif event == "http_failure" and p1 == url then
                setStatus("HTTP Request Failed!")
                os.sleep(2)
                break
            end
        end
    end
end

-- === MAIN AUDIO LOOP === --
local function audioLoop()
    while true do
        loadConfig()
        
        local current_playlist = {}
        for _, v in ipairs(playlist) do table.insert(current_playlist, v) end
        
        if config.SHUFFLE_PLAYLIST == "true" then
            for i = #current_playlist, 2, -1 do
                local j = math.random(i)
                current_playlist[i], current_playlist[j] = current_playlist[j], current_playlist[i]
            end
        end

        for _, line in ipairs(current_playlist) do
            if line:sub(1, 5) == "!song" then
                local id = line:match("v=([%w%-_]+)") or line:match("youtu%.be/([%w%-_]+)")
                if id then
                    now_playing = { title = "YouTube ID: " .. id }
                    playStream(config.BACKEND_URL .. "?v=" .. config.API_VERSION .. "&id=" .. id, getFilenameFor(line))
                end
            elseif line:sub(1, 4) == "!tts" then
                local text = textutils.formatTime(os.time("ingame"), false)
                local msg = line:sub(6):gsub("!!time!!", text)
                now_playing = { title = "TTS Announcement" }
                playStream("https://music.madefor.cc/tts?text=" .. textutils.urlEncode(msg), getFilenameFor(line))
            elseif line:sub(1, 1) == "#" then
                local cmd = line:sub(2)
                setStatus("Broadcasting Control: " .. cmd)
                modem.transmit(METADATA_CHANNEL, METADATA_CHANNEL, textutils.serialiseJSON({
                    type = "control", command = cmd, station = config.STATION_NAME
                }))
                os.sleep(0.5)
            end
            
            now_playing = nil
            setStatus("Idle")
            os.sleep(1)
        end
    end
end

loadConfig()
drawUI()
parallel.waitForAny(handleUIEvents, audioLoop)
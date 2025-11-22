-- server_dual_modem.lua

-- Wrap modems
wlsmdmside = "right"
local wirelessModem = peripheral.wrap(wlsmdmside)
local wiredModem = peripheral.wrap("bottom")

-- Wrap monitor
local monitor = peripheral.wrap("monitor_6")
monitor.setTextScale(0.5)
monitor.clear()

-- Open wireless channel
local listenChannel = 124
wirelessModem.open(listenChannel)

-- Find remote redstone relay
local relayName = nil
for _, name in ipairs(wiredModem.getNamesRemote()) do
  print("Found: " .. name)
  if wiredModem.hasTypeRemote(name, "redstone_relay") then
    relayName = name
    break
    end
    end
    
    if not relayName then
      error("No redstone relay found on wired modem network")
      end
      
      print("Connected to remote relay:", relayName)
      print("Listening for wireless commands on channel " .. listenChannel)
      
      -- ASCII art definitions
      local ascii_locked = {
        '    .-""-. ',
        '   / .--. \\ ',
        '  / /    \\ \\ ',
        '  | |    | | ',
        '  | |.-""-.| ',
        ' ///`.::::.`\\ ',
        '||| ::/  \\:: ; ',
        '||; ::\\__/:: ; ',
        ' \\\\\\ ::::: / ',
        '  `=::-..-:` ',
      }
      
      local ascii_unlocked = {
        '    .-""-. ',
        '   / .--. \\ ',
        '  / /        ',
        '  | |        ',
        '  | |.-""-.  ',
        ' ///`.::::.`\\ ',
        '||| ::/  \\:: ; ',
        '||; ::\\__/:: ; ',
        ' \\\\\\ ::::: / ',
        '  `=::-..-:` ',
      }
      
local logFile = "door_log.txt"

-- Load log from file
local log = {}
if fs.exists(logFile) then
  local f = fs.open(logFile, "r")
  local line = f.readLine()
  while line do
    table.insert(log, line)
    line = f.readLine()
  end
  f.close()
end

-- Save log to file (with cap equal to monitor capacity)
local function saveLog()
  local _, monHeight = monitor.getSize()
  local artHeight = #ascii_locked
  local availableLines = monHeight - artHeight

  -- Trim log to fit monitor
  while #log > availableLines do
    table.remove(log, 1)
  end

  local f = fs.open(logFile, "w")
  for _, entry in ipairs(log) do
    f.writeLine(entry)
  end
  f.close()
end

-- Function to update monitor
local function updateMonitor(isLocked)
  monitor.clear()
  monitor.setCursorPos(1,1)
  local art = isLocked and ascii_locked or ascii_unlocked
  for _, line in ipairs(art) do
    monitor.write(line)
    local x, y = monitor.getCursorPos()
    monitor.setCursorPos(1, y+1)
  end

  -- Calculate remaining space
  local _, monHeight = monitor.getSize()
  local artHeight = #art
  local availableLines = monHeight - artHeight

  -- Print only the last entries that fit
  local startIndex = math.max(1, #log - availableLines + 1)
  local y = artHeight + 1
  for i = startIndex, #log do
    monitor.setCursorPos(1, y)
    monitor.write(log[i])
    y = y + 1
  end
end

-- Helper to add log entry
local function addLog(isLocked)
  local ts
  if os.epoch then
    ts = math.ceil(os.epoch("utc")/1000)
  else
    ts = os.time()
  end
  local prefix = isLocked and "LO " or "UN "
  table.insert(log, prefix .. ts)
  saveLog()
end

-- Lock door on startup
wiredModem.callRemote(relayName, "setOutput", "front", false)
print("Door locked on startup")
addLog(true)
updateMonitor(true)

-- Main loop
while true do
  local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
  if side == wlsmdmside and channel == listenChannel then
    if message == "open" then
      wiredModem.callRemote(relayName, "setOutput", "front", true)
      print("Door opened")
      addLog(false)
      updateMonitor(false)
    elseif message == "close" then
      wiredModem.callRemote(relayName, "setOutput", "front", false)
      print("Door closed")
      addLog(true)
      updateMonitor(true)
    else
      print("Unknown command:", tostring(message))
    end
  end
end

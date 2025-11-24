-- homectl/config_gen.lua

write("Modem side: ") local modemSide = read()
write("Redstone output side: ") local redstoneSide = read()
write("Redstone input side: ") local inputSide = read()
write("Channel number: ") local channel = tonumber(read())
write("Default value (on/off/none): ") local defaultValue = read()
write("Mode (1=normal,2=pulse,3=invert): ") local mode = tonumber(read())

-- Ask about monitor
write("Use monitor display? (y/n): ") local useMonitor = read()
local monitorName = nil
if useMonitor == "y" then
  write("Enter monitor peripheral name (e.g. monitor_6): ")
  monitorName = read()
end

-- Build config block
local configBlock = string.format([[
-- Configuration
local modemSide = "%s"
local redstoneSide = "%s"
local inputSide = "%s"
local channel = %d
local defaultValue = '%s'
local mode = %d
local monitorName = %s
]], modemSide, redstoneSide, inputSide, channel, defaultValue, mode,
   monitorName and string.format('"%s"', monitorName) or "nil")

-- Read client_base.lua
local f = fs.open("client_base.lua", "r")
local clientBase = f.readAll()
f.close()

-- If monitor requested, append monitor code
local monitorCode = ""
if monitorName then
  monitorCode = [[

-- Optional monitor display
local monitor = peripheral.wrap(monitorName)
monitor.setTextScale(0.5)
monitor.clear()

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
local log = {}

local function saveLog()
  local _, monHeight = monitor.getSize()
  local artHeight = #ascii_locked
  local availableLines = monHeight - artHeight
  while #log > availableLines do table.remove(log,1) end
  local f = fs.open(logFile,"w")
  for _,entry in ipairs(log) do f.writeLine(entry) end
  f.close()
end

local function updateMonitor(isLocked)
  monitor.clear()
  monitor.setCursorPos(1,1)
  local art = isLocked and ascii_locked or ascii_unlocked
  for _,line in ipairs(art) do
    monitor.write(line)
    local x,y = monitor.getCursorPos()
    monitor.setCursorPos(1,y+1)
  end
  local _, monHeight = monitor.getSize()
  local artHeight = #art
  local availableLines = monHeight - artHeight
  local startIndex = math.max(1,#log-availableLines+1)
  local y = artHeight+1
  for i=startIndex,#log do
    monitor.setCursorPos(1,y)
    monitor.write(log[i])
    y=y+1
  end
end

local function addLog(isLocked)
  local ts = os.epoch and math.ceil(os.epoch("utc")/1000) or os.time()
  local prefix = isLocked and "LO " or "UN "
  table.insert(log,prefix..ts)
  saveLog()
end
]]
end

-- Write combined client
local out = fs.open("client_gen.lua", "w")
out.write(configBlock .. "\n" .. clientBase .. "\n" .. monitorCode)
out.close()

-- Save channel for controller integration
local f2 = fs.open("last_channel.txt", "w")
f2.write(tostring(channel))
f2.close()

print("Client generated as client_gen.lua")

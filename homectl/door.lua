-- door.lua (monitor integration)

print("Module: door.lua")

if monitorName then
  print("door.lua | monitor found!")
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

  -- Load existing log
  if fs.exists(logFile) then
    local f = fs.open(logFile, "r")
    local line = f.readLine()
    while line do
      table.insert(log, line)
      line = f.readLine()
    end
    f.close()
  end

  local function saveLog()
    local _, monHeight = monitor.getSize()
    local artHeight = #ascii_locked
    local availableLines = monHeight - artHeight
    while #log > availableLines do table.remove(log,1) end
    local f = fs.open(logFile,"w")
    for _,entry in ipairs(log) do f.writeLine(entry) end
    f.close()
  end

  local function updateMonitor(isOn)
    monitor.clear()
    monitor.setCursorPos(1,1)
    local art = isOn and ascii_unlocked or ascii_locked
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

  local function addLog(isOn)
    local ts = os.epoch and math.ceil(os.epoch("utc")/1000) or os.time()
    local prefix = isOn and "LO " or "UN "
    table.insert(log,prefix..ts)
    saveLog()
  end

  -- Hook into state changes
  function monitor_refresh(command)
      addLog(command)
      updateMonitor(command)
    end
  end

  -- Initial display
  addLog(false)
  updateMonitor(false)
end

local configFile = "devices.cfg"
local winWidth, winHeight = term.getSize()
local tmpClientFile = "client_gen.lua"

-- Load devices from file or start with defaults
local devices = {}
if fs.exists(configFile) then
  local f = fs.open(configFile, "r")
  local data = textutils.unserialize(f.readAll())
  f.close()
  if type(data) == "table" then devices = data end
end
if #devices == 0 then
  devices = {
    { channel = 1, name = "DEMO", status = "[?]" },
  }
end

-- Save config
local function saveConfig()
  local f = fs.open(configFile, "w")
  f.write(textutils.serialize(devices))
  f.close()
end

local function generateClient()
    local tmpClientFile = "client_gen.lua"
    
    -- Always download the latest config_gen.lua and client_base.lua
    shell.run("wget https://raw.githubusercontent.com/40476/cctweaked-programs/main/homectl/config_gen.lua config_gen.lua")
    shell.run("wget https://raw.githubusercontent.com/40476/cctweaked-programs/main/homectl/client_base.lua client_base.lua")

    -- Run config_gen.lua to prompt user for settings
    shell.run("config_gen.lua")

    -- Upload to Pastebin and capture the returned ID
    print("Uploading client to Pastebin...")
    shell.run("pastebin put " .. tmpClientFile)
    print("make note of this and press enter")
    read()

    -- Ask to add to controller config
    write("Add this device to controller config? (y/n): ")
    local ans = read()
    if ans == "y" then
        write("Enter a name for this device: ")
        local name = read()
        local f = fs.open("last_channel.txt", "r")
        local channel = tonumber(f.readAll())
        f.close()
        table.insert(devices, { channel = channel, name = name, status = "[?]"})
        saveConfig()
        print("Device added to controller config.")
    end
    shell.run("rm config_gen.lua")
    shell.run("rm client_base.lua")
    shell.run("rm config_gen.lua")
end


-- Open modem
local modem = peripheral.find("modem") or error("No modem found!")
for _, dev in ipairs(devices) do modem.open(dev.channel) end

-- Async status request
local pending = {}
local function requestStatus()
  pending = {}
  for _, dev in ipairs(devices) do
    modem.transmit(dev.channel, dev.channel, "status")
    pending[dev.channel] = { dev = dev, timeout = os.clock() + 5 }
    dev.status = "[...]"
  end
end

-- Handle modem responses & timeouts
local function handleEvents()
  while true do
    local event, p1, p2, p3, p4 = os.pullEvent()
    if event == "modem_message" then
      local side, ch, reply, msg = p1, p2, p3, p4
      if pending[ch] then
        local dev = pending[ch].dev
        dev.status = (msg == "ON") and "[ON]" or (msg == "OFF" and "[OFF]" or "[ERR]")
        pending[ch] = nil
      end
    elseif event == "timer" then
      -- not used here, we check timeouts manually
    end
    -- check timeouts
    local now = os.clock()
    for ch, info in pairs(pending) do
      if now > info.timeout then
        info.dev.status = "[ERR]"
        pending[ch] = nil
      end
    end
  end
end

-- Config editor: add/remove/reorder
local function editConfig()
  while true do
    term.clear()
    print("=== Config Editor ===")
    for i, dev in ipairs(devices) do
      print(i .. ". " .. dev.name .. " (Channel " .. dev.channel .. ")")
    end
    print("a=add, r=remove, m=move, q=quit")
    local choice = read()
    if choice == "q" then
      break
    elseif choice == "a" then
      generateClient()
    elseif choice == "r" then
      write("Index to remove: ")
      local idx = tonumber(read())
      if devices[idx] then table.remove(devices, idx) end
    elseif choice == "m" then
      write("Index to move: ")
      local idx = tonumber(read())
      write("New position: ")
      local pos = tonumber(read())
      if devices[idx] and pos >= 1 and pos <= #devices then
        local dev = table.remove(devices, idx)
        table.insert(devices, pos, dev)
      end
    end
    saveConfig()
  end
end

-- UI loop
local currentIndex, cursor = 1, 1
local function mainUI()
  requestStatus()
  while true do
    term.clear()
    term.setCursorPos(1,1)
    for i=0, winHeight-1 do
      local idx = currentIndex+i
      if idx <= #devices then
        local dev = devices[idx]
        local line = dev.status.." "..dev.name
        if cursor == i+1 then write("-> "..line) else write(line) end
        term.setCursorPos(1,i+2)
      end
    end

    local event, p1 = os.pullEvent()
    if event == "key" then
      local key = p1
      if key == keys.enter then
        local dev = devices[currentIndex+cursor-1]
        if dev then
          local cmd = (dev.status=="[ON]") and "off" or "on"
          modem.transmit(dev.channel, dev.channel, cmd)
          os.sleep(0.5)
          requestStatus()
        end
      elseif key == keys.c then
        editConfig()
        requestStatus()
      elseif key == keys.r then
        requestStatus()
      elseif key == keys.q then
        break
      elseif key == keys.up then
        if cursor>1 then cursor=cursor-1 elseif currentIndex>1 then currentIndex=currentIndex-1 end
      elseif key == keys.down then
        if cursor<winHeight-1 and cursor<#devices-currentIndex+1 then cursor=cursor+1
        elseif currentIndex+winHeight-1<#devices then currentIndex=currentIndex+1 end
      end
    elseif event == "modem_message" then
      -- just redraw, statuses already updated by handleEvents
    elseif event == "timer" then
      -- could trigger periodic refresh
    end
  end
end


-- Run event handler in parallel with UI
parallel.waitForAny(handleEvents, mainUI)
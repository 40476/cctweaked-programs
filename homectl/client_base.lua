-- wait a few to make sure we arent loading before the chunks are ready or smth
os.sleep(5)

-- Persistence helpers (mode 4)
local persistFile = "state.dat"
local function saveState(val)
  local f = fs.open(persistFile, "w")
  f.write(val)
  f.close()
end
local function loadState()
  if fs.exists(persistFile) then
    local f = fs.open(persistFile, "r")
    local val = f.readAll()
    f.close()
    return val
  end
  return defaultValue
end

-- Optional monitor hook: door.lua defines monitor_refresh(nameOrBool)
local function safe_monitor_refresh(isOn)
  if monitor_refresh then
    pcall(monitor_refresh, isOn)
  end
end

-- Device path (non-gateway): wireless + local redstone
local modem = (not gatewayMode and modemSide) and peripheral.wrap(modemSide) or nil
local lock = false
if modem then modem.open(channel) end

local redstoneState = inputSide and redstone.getInput(inputSide) or false
local previousInputState = redstoneState

local function stateChange(value, command)
  local case = {
    [1] = function()
      if command == "on" then
        lock = true
        redstone.setOutput(redstoneSide, true)
        redstoneState = redstone.getInput(redstoneSide)
        saveState((mode == 4) and "on" or (defaultValue or "none"))
        print("Redstone signal turned ON via remote command")
        safe_monitor_refresh(true)
      elseif command == "off" then
        lock = true
        redstone.setOutput(redstoneSide, false)
        redstoneState = redstone.getInput(redstoneSide)
        saveState((mode == 4) and "off" or (defaultValue or "none"))
        print("Redstone signal turned OFF via remote command")
        safe_monitor_refresh(false)
      end
    end,
    [2] = function()
      redstone.setOutput(redstoneSide, not redstone.getInput(redstoneSide))
      sleep(0.2)
      redstone.setOutput(redstoneSide, not redstone.getInput(redstoneSide))
      print("Redstone signal pulsed via remote command")
    end,
    [3] = function()
      redstoneState = not redstoneState
      redstone.setOutput(redstoneSide, redstoneState)
      print("Redstone signal inverted via remote command")
      safe_monitor_refresh(redstoneState)
    end,
    [4] = function()
      -- Persistence mode: set and save
      if command == "on" or command == "off" then
        redstone.setOutput(redstoneSide, command == "on")
        redstoneState = redstone.getInput(redstoneSide)
        saveState(command)
        print("Persisted state set to: " .. command:upper())
        safe_monitor_refresh(command == "on")
      elseif command == "none" then
        local s = loadState()
        redstone.setOutput(redstoneSide, s == "on")
        redstoneState = redstone.getInput(redstoneSide)
        print("Restored persisted state: " .. (s or "none"))
        safe_monitor_refresh(s == "on")
      end
    end,
  }
  (case[value] or case[1])()
end

-- Startup default
do
  local startupDefault = defaultValue
  if mode == 4 then startupDefault = loadState() or defaultValue end
  stateChange((mode == 4) and 4 or 1, startupDefault)
end

-- Monitor input changes -> mirror to output
local function monitorInput()
  while true do
    if checkInput and inputSide then
      local current = redstone.getInput(inputSide)
      if previousInputState ~= current then
        if not lock then
          lock = true
          previousInputState = current
          redstone.setOutput(redstoneSide, current)
          redstoneState = current
          print("Input changed. Redstone output updated to: " .. (current and "ON" or "OFF"))
          safe_monitor_refresh(current)
        else
          print("waiting to unlock")
          sleep(2)
          lock = false
        end
      end
    end
    sleep(0.1)
  end
end

-- Wireless command handler (device path)
local function handleModemMessages()
  while true do
    local event, side, receivedChannel, replyChannel, message = os.pullEvent("modem_message")
    if receivedChannel == channel then
      if message == "on" or message == "off" then
        stateChange(mode, message)
      elseif message == "status" then
        local statusMessage
        if not inputToStatus then
          statusMessage = (redstone.getInput(redstoneSide) and "ON" or "OFF")
        else
          statusMessage = (redstone.getInput(inputSide) and "ON" or "OFF")
        end
        modem.transmit(channel, channel, statusMessage)
        print("Status queried. Sent response: " .. statusMessage)
      end
      safe_monitor_refresh(redstone.getInput(redstoneSide))
    end
  end
end

print("Loading additional inbuilt modules!")

-- Gateway path (wired only, fixed channel, auth)
local function gatewayLoop()
  if not gatewayMode then return end

  local wired = wiredSide and peripheral.wrap(wiredSide) or nil
  if not wired then error("Gateway enabled but no wired modem found on side: " .. tostring(wiredSide)) end

  -- Discover a remote redstone relay
  local relayName
  for _, name in ipairs(wired.getNamesRemote()) do
    if wired.hasTypeRemote(name, "redstone_relay") then relayName = name break end
  end
  if not relayName then error("No redstone relay found on wired modem network") end

  -- Wireless modem for gateway comms if present. No normal device usage, and no channel prompt.
  local gwWireless = peripheral.find("modem")
  if gwWireless then gwWireless.open(channel) end

  print("Gateway connected to relay: " .. relayName .. " on channel " .. tostring(channel))
  while true do
    local event, side, ch, reply, msg = os.pullEvent("modem_message")
    if ch == channel and type(msg) == "table" then
      local okAuth = (msg.token == authToken)
      if not okAuth then
        print("Unauthorized gateway command ignored")
      else
        if msg.cmd == "on" then
          wired.callRemote(relayName, "setOutput", "front", true)
          print("Gateway: ON")
        elseif msg.cmd == "off" then
          wired.callRemote(relayName, "setOutput", "front", false)
          print("Gateway: OFF")
        elseif msg.cmd == "status" then
          local out = wired.callRemote(relayName, "getOutput", "front")
          if gwWireless then gwWireless.transmit(channel, channel, out and "ON" or "OFF") end
          print("Gateway: STATUS -> " .. (out and "ON" or "OFF"))
        end
      end
    end
  end
end

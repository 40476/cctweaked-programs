-- wait a few to make sure we arent loading before the chunks are ready or smth
os.sleep(5)

local lock = false
local redstoneState = inputSide and redstone.getInput(inputSide) or false
local previousInputState = redstoneState

-- Gateway vs normal modem wrap
local modem = nil
local wired = nil
if useGateway then
  wired = peripheral.wrap(wiredSide)
  wired.open(channel)
else
  modem = peripheral.wrap(modemSide)
  modem.open(channel)
end

local function stateChange(value, command)
  local case = {
    [1] = function()
      if command == "on" then
        lock = true
        redstone.setOutput(redstoneSide, true)
        redstoneState = redstone.getInput(redstoneSide)
        print("Redstone signal turned ON via remote command")
      elseif command == "off" then
        lock = true
        redstone.setOutput(redstoneSide, false)
        redstoneState = redstone.getInput(redstoneSide)
        print("Redstone signal turned OFF via remote command")
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
    end,
  }
  if case[value] then case[value]() end
end

-- Apply default value at startup
stateChange(1, defaultValue)

-- Monitor input changes
local function monitorInput()
  while true do
    if checkInput and inputSide then
      local currentInputState = redstone.getInput(inputSide)
      if previousInputState ~= currentInputState then
        if not lock then
          lock = true
          previousInputState = currentInputState
          redstone.setOutput(redstoneSide, currentInputState)
          redstoneState = currentInputState
          print("Input changed. Redstone output updated to: " .. (currentInputState and "ON" or "OFF"))
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

-- Normal wireless client handler
local function handleModemMessages()
  while true do
    local event, side, receivedChannel, replyChannel, message = os.pullEvent("modem_message")
    if receivedChannel == channel then
      if message == "on" or message == "off" then
        stateChange(mode, message)
      elseif message == "status" then
        local statusMessage
        if not inputToStatus then
          statusMessage = redstone.getInput(redstoneSide) and "ON" or "OFF"
        else
          statusMessage = redstone.getInput(inputSide) and "ON" or "OFF"
        end
        modem.transmit(channel, channel, statusMessage)
        print("Status queried. Sent response: " .. statusMessage)
      end
      if monitor_refresh then
        monitor_refresh(redstone.getInput(redstoneSide))
      end
    end
  end
end

-- Gateway client handler (wired only)
local function handleGatewayMessages()
  while true do
    local event, side, receivedChannel, replyChannel, message = os.pullEvent("modem_message")
    if side == peripheral.getName(wired) and receivedChannel == channel then
      if message == "on" or message == "off" then
        stateChange(mode, message)
        wired.transmit(channel, channel, message:upper())
      elseif message == "status" then
        local s = redstone.getOutput(redstoneSide)
        wired.transmit(channel, channel, s and "ON" or "OFF")
        print("Gateway client: STATUS -> " .. (s and "ON" or "OFF"))
      end
    end
  end
end

print("Loading additional inbuilt modules!")

if useGateway then
  parallel.waitForAny(monitorInput, handleGatewayMessages)
else
  parallel.waitForAny(monitorInput, handleModemMessages)
end

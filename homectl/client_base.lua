local modem = peripheral.wrap(modemSide)
local lock = false
modem.open(channel)

local redstoneState = redstone.getInput(inputSide) -- Initialize with the current input state
local previousInputState = redstone.getInput(inputSide) -- Initialize with the current input state

local function stateChange(value,command)
    local case = {
        [1] = function()
            if command == "on" then
                lock = true
                redstone.setOutput(redstoneSide, true) -- Force activation
                    redstoneState = redstone.getInput(redstoneSide)
                    print("Redstone signal turned ON via remote command")
            elseif command == "off" then
                lock = true
                redstone.setOutput(redstoneSide, false) -- Force deactivation
                    redstoneState = redstone.getInput(redstoneSide)
                    print("Redstone signal turned OFF via remote command")
            end
        end,
        [2] = function()
            redstone.setOutput(redstoneSide, not redstone.getInput(redstoneSide))
            sleep(0.2)
            redstone.setOutput(redstoneSide, not redstone.getInput(redstoneSide))
--             redstoneState = not redstoneState
            print("Redstone signal pulsed via remote command")
        end,
        [3] = function()
            redstoneState = not redstoneState
            redstone.setOutput(redstoneSide,redstoneState)
            print("Redstone signal inverted via remote command")
        end,
    }
    case[value]()
end
stateChange(1,defaultValue)
-- Function to monitor input and update output only when it changes
local function monitorInput()
    while true do
        if previousInputState ~= redstone.getInput(inputSide) and checkInput == true then
            if lock==false then
                lock=true
                local currentInputState = redstone.getInput(inputSide)
                previousInputState = currentInputState
                redstone.setOutput(redstoneSide, currentInputState)
                redstoneState = currentInputState
                print("Input changed. Redstone output updated to: " .. (currentInputState and "ON" or "OFF"))
            else
                print("waiting to unlock")
                sleep(2)
                lock=false
            end
        end
        sleep(0.1) -- Delay to avoid excessive polling
    end
end

-- Function to handle modem messages
local function handleModemMessages()
    while true do
        local event, side, receivedChannel, replyChannel, message, distance = os.pullEvent("modem_message")
        if receivedChannel == channel then
            if message == "on" then
                stateChange(mode,message)
            elseif message == "off" then
                stateChange(mode,message)
            elseif message == "status" then
                
                if inputToStatus == false then
                    statusMessage =  redstone.getInput(redstoneSide) and "ON" or "OFF"
                else
                    statusMessage =  redstone.getInput(inputSide) and "ON" or "OFF"
                end
                modem.transmit(channel, channel, statusMessage) -- Respond with current status
                print("Status queried. Sent response: " .. statusMessage)
            end
        end
    end
end

-- Run input monitoring and message handling in parallel
print("Listening for signals and monitoring input...")
parallel.waitForAny(monitorInput, handleModemMessages)

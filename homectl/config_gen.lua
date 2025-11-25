-- homectl/config_gen.lua

local function yn(prompt)
  write(prompt .. " (y/n): ")
  local ans = read()
  return ans == "y"
end

-- Gateway mode first (affects following prompts)
local gatewayMode = yn("Enable gateway mode")

local modemSide, channel
local wiredSide
local defaultValue
local mode
local checkInput, inputToStatus

if gatewayMode then
  -- Gateway: wired-only device bridge, no channel prompt for normal device
  write("Wired modem side (e.g. bottom): ") wiredSide = read()
  -- Fixed gateway listen channel (controller logic will use the same). You can change this constant in client_base if needed.
  channel = 124
  modemSide = nil
  defaultValue = "none"
  mode = 1 -- ignored in gateway path
  checkInput = false
  inputToStatus = false
else
  write("Modem side (e.g. right): ") modemSide = read()
  write("Redstone output side (e.g. top): ") local redstoneSide = read()
  write("Redstone input side (e.g. front): ") local inputSide = read()
  write("Channel number: ") channel = tonumber(read())
  write("Default value (on/off/none): ") defaultValue = read()
  write("Mode (1=normal,2=pulse,3=invert,4=persist): ") mode = tonumber(read() or "1")
  write("Check input to mirror? (y/n): ") checkInput = (read() == "y")
  write("Use input side for status? (y/n): ") inputToStatus = (read() == "y")
  -- stash for later
  _G._cfg_redstoneSide = redstoneSide
  _G._cfg_inputSide = inputSide
end

-- Ask about monitor
local monitorName = nil
if yn("Use monitor display") then
  write("Enter monitor peripheral name (e.g. monitor_6): ")
  monitorName = read()
end

-- Gateway auth token
local authToken = nil
if gatewayMode then
  write("Gateway auth token (leave blank to auto-generate): ")
  local tok = read()
  if tok and tok ~= "" then
    authToken = tok
  else
    -- simple random token
    local chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
    local t = {}
    for i = 1, 12 do
      local idx = math.random(#chars)
      t[i] = chars:sub(idx, idx)
    end
    authToken = table.concat(t)
  end
end

-- Build config block
local function q(s) return s and string.format('"%s"', s) or "nil" end
local configBlock

if gatewayMode then
  configBlock = string.format([[
-- Configuration (gateway)
local gatewayMode = true
local wiredSide = %s
local channel = %d
local authToken = %s
local modemSide = nil
local redstoneSide = nil
local inputSide = nil
local defaultValue = 'none'
local mode = 1
local checkInput = false
local inputToStatus = false
local monitorName = %s
]], q(wiredSide), channel, q(authToken), q(monitorName))
else
  configBlock = string.format([[
-- Configuration (device)
local gatewayMode = false
local modemSide = %s
local redstoneSide = %s
local inputSide = %s
local channel = %d
local defaultValue = '%s'
local mode = %d
local checkInput = %s
local inputToStatus = %s
local monitorName = %s
]], q(modemSide), q(_G._cfg_redstoneSide), q(_G._cfg_inputSide), channel, defaultValue, mode,
     tostring(checkInput), tostring(inputToStatus), q(monitorName))
end

-- Read client_base.lua
local f = fs.open("client_base.lua", "r")
local clientBase = f.readAll()
f.close()

-- Optional monitor module
local monitorCode = ""
if monitorName then
  shell.run("wget https://raw.githubusercontent.com/40476/cctweaked-programs/main/homectl/door.lua door.lua")
  local f2 = fs.open("door.lua", "r")
  monitorCode = f2.readAll()
  f2.close()
  shell.run("rm door.lua")
end

-- Write combined client
local out = fs.open("client_gen.lua", "w")
out.write(configBlock .. "\n" .. monitorCode .. "\n" .. clientBase ..
  "\nprint('Listening...')\n" ..
  "if gatewayMode then parallel.waitForAny(gatewayLoop) else parallel.waitForAny(monitorInput, handleModemMessages) end")
out.close()

-- Save channel for controller integration (skip for gateway)
if not gatewayMode then
  local f3 = fs.open("last_channel.txt", "w")
  f3.write(tostring(channel))
  f3.close()
end

-- Save gateway marker for controller
local f4 = fs.open("last_gateway.txt", "w")
f4.write(gatewayMode and "1" or "0")
f4.close()

print("Client generated as client_gen.lua")

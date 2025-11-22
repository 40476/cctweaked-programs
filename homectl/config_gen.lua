-- homectl/config_gen.lua

write("Modem side: ") local modemSide = read()
write("Redstone output side: ") local redstoneSide = read()
write("Redstone input side: ") local inputSide = read()
write("Channel number: ") local channel = tonumber(read())
write("Default value (on/off/none): ") local defaultValue = read()
write("Mode (1=normal,2=pulse,3=invert): ") local mode = tonumber(read())

-- Build config block
local configBlock = string.format([[
  -- Configuration
  local modemSide = "%s"
  local redstoneSide = "%s"
  local inputSide = "%s"
  local channel = %d
  local checkInput = false
  local inputToStatus = false
  local defaultValue = '%s'
local mode = %d
]], modemSide, redstoneSide, inputSide, channel, defaultValue, mode)

-- Read client_base.lua
local f = fs.open("client_base.lua", "r")
local clientBase = f.readAll()
f.close()

-- Write combined client
local out = fs.open("client_gen.lua", "w")
out.write(configBlock .. "\n" .. clientBase)
out.close()

-- Save channel for controller integration
local f2 = fs.open("last_channel.txt", "w")
f2.write(tostring(channel))
f2.close()

print("Client generated as client_gen.lua")

-- homectl/config_gen.lua

write("Use gateway mode? (y/n): ")
local useGateway = (read() == "y")

local modemSide, channel, redstoneSide, inputSide
if useGateway then
  -- Gateway mode: wired only, no wireless modem
  write("Wired modem side: ") local wiredSide = read()
  write("Redstone output side: ") redstoneSide = read()
  write("Redstone input side: ") inputSide = read()
  channel = 124 -- fixed channel for gateway
  modemSide = nil
else
  write("Modem side: ") modemSide = read()
  write("Redstone output side: ") redstoneSide = read()
  write("Redstone input side: ") inputSide = read()
  write("Channel number: ") channel = tonumber(read())
end

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
local useGateway = %s
local modemSide = %s
local wiredSide = %s
local redstoneSide = "%s"
local inputSide = "%s"
local channel = %d
local defaultValue = '%s'
local mode = %d
local monitorName = %s
]], tostring(useGateway),
   modemSide and string.format('"%s"', modemSide) or "nil",
   useGateway and string.format('"%s"', wiredSide) or "nil",
   redstoneSide, inputSide, channel, defaultValue, mode,
   monitorName and string.format('"%s"', monitorName) or "nil")

-- Read client_base.lua
local f = fs.open("client_base.lua", "r")
local clientBase = f.readAll()
f.close()

-- If monitor requested, download door.lua and append
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
out.write(configBlock .. "\n" .. monitorCode .. "\n" .. clientBase)
out.close()

-- Save channel for controller integration (skip for gateway)
if not useGateway then
  local f3 = fs.open("last_channel.txt", "w")
  f3.write(tostring(channel))
  f3.close()
end

print("Client generated as client_gen.lua")

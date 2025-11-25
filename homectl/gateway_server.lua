-- homectl/gateway_server.lua

local wireless = peripheral.wrap("right")   -- wireless modem side
local wired    = peripheral.wrap("bottom")  -- wired modem side

local listenChannel = 124
local password = "superSecret123"           -- shared password with controller

wireless.open(listenChannel)
wired.open(listenChannel)

print("Gateway server listening on wireless channel "..listenChannel)

while true do
  local event, side, ch, reply, msg = os.pullEvent("modem_message")
  if side == peripheral.getName(wireless) and ch == listenChannel then
    -- Received from controller
    if type(msg) == "table" and msg.password == password then
      print("Controller -> Gateway: "..tostring(msg.cmd))
      -- Forward to all wired clients
      wired.transmit(listenChannel, listenChannel, msg.cmd)
    else
      print("Unauthorized wireless command ignored")
    end
  elseif side == peripheral.getName(wired) and ch == listenChannel then
    -- Received from a gateway client
    print("Client -> Gateway: "..tostring(msg))
    -- Relay back to controller
    wireless.transmit(listenChannel, listenChannel, msg)
  end
end

-- homectl/gateway_server.lua

local wireless = peripheral.wrap(wirelessModemSide)
local wired = peripheral.wrap(wiredModemSide)

wireless.open(listenChannel)
wired.open(listenChannel)

print("Gateway server listening on channel "..listenChannel)

while true do
  local event, side, ch, reply, msg = os.pullEvent("modem_message")
  if side == peripheral.getName(wireless) and ch == listenChannel then
    if type(msg) == "table" and msg.password == password then
      print("Controller -> Gateway: "..tostring(msg.cmd))
      wired.transmit(listenChannel, listenChannel, msg.cmd)
    else
      print("Unauthorized wireless command ignored")
    end
  elseif side == peripheral.getName(wired) and ch == listenChannel then
    print("Client -> Gateway: "..tostring(msg))
    wireless.transmit(listenChannel, listenChannel, msg)
  end
end
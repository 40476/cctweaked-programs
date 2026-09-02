-- grid_buttons.lua
-- Runs on monitor_7, divides into 3x3 grid, each cell shows status of a function with labels

-- Wrap monitor
local monitor = peripheral.wrap("monitor_7")
monitor.setTextScale(0.5)
monitor.clear()
monitor.setBackgroundColor(colors.black)

-- Example functions (replace with your own logic)
local functions = {
  function() 
    local relay = peripheral.wrap("redstone_relay_5")
    relay.setOutput("front", not relay.getOutput("front"))
    return relay.getOutput('front')
  end,
  function() return false end,
  function() return false end,
  function() return false end,
  function() return false end,
  function() return false end,
  function() return false end,
  function() return false end,
  function() return false end,
}

-- Labels for each function
local labels = {
  "Main Lights",
  "Sensor B",
  "Random C",
  "Check D",
  "Check E",
  "Check F",
  "Random G",
  "Sensor H",
  "Sensor I",
}

-- Draw grid
local function drawGrid()
  monitor.clear()
  local w, h = monitor.getSize()
  local cellW = math.floor(w / 3)
  local cellH = math.floor(h / 3)

  for i, func in ipairs(functions) do
    local row = math.floor((i-1) / 3)
    local col = (i-1) % 3
    local x1 = col * cellW + 1
    local y1 = row * cellH + 1
    local x2 = (col+1) * cellW
    local y2 = (row+1) * cellH

    local ok = false
    local success, result = pcall(func)
    if success and result then ok = true end

    local color = ok and colors.green or colors.red
    monitor.setBackgroundColor(color)

    -- Fill cell background
    for y = y1, y2 do
      monitor.setCursorPos(x1, y)
      monitor.write(string.rep(" ", cellW))
    end

    -- Center label text
    local label = labels[i] or tostring(i)
    local textX = x1 + math.floor((cellW - #label) / 2)
    local textY = y1 + math.floor(cellH / 2)
    monitor.setCursorPos(textX, textY)
    monitor.setTextColor(colors.white)
    monitor.write(label)
  end
end

-- Main loop: refresh every second
while true do
  drawGrid()
  sleep(1)
end

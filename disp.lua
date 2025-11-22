-- display_nfp_scaled.lua
-- Usage: display_nfp_scaled <filename>

local args = {...}
if #args < 1 then
  print("Usage: display_nfp_scaled <filename>")
  return
end

local filename = args[1]

-- Load NFP image
local image = paintutils.loadImage(filename)
if not image then
  print("Failed to load image: " .. filename)
  return
end

-- Determine image size
local imgW, imgH = #image[1], #image

-- Get monitor or terminal size
local w, h = term.getSize()

-- Compute scale factors
local scaleX = w / imgW
local scaleY = h / imgH
local scale = math.min(scaleX, scaleY)

-- Clear screen
term.clear()

-- Draw scaled image
for y = 1, imgH do
  for x = 1, imgW do
    local color = image[y][x]
    if color then
      -- Draw a block of pixels scaled to monitor size
      local startX = math.floor((x-1) * scale) + 1
      local startY = math.floor((y-1) * scale) + 1
      local endX   = math.floor(x * scale)
      local endY   = math.floor(y * scale)
      for dy = startY, endY do
        for dx = startX, endX do
          paintutils.drawPixel(dx, dy, color)
        end
      end
    end
  end
end

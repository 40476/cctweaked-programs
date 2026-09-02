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
local scaleX = imgW / w
local scaleY = imgH / h

-- Clear screen
term.clear()

-- Draw scaled image using nearest-neighbor sampling
for dy = 1, h do
  for dx = 1, w do
    -- Map monitor pixel back to image coordinates
    local srcX = math.floor(dx * scaleX)
    local srcY = math.floor(dy * scaleY)

    -- Clamp to image bounds
    if srcX < 1 then srcX = 1 end
    if srcY < 1 then srcY = 1 end
    if srcX > imgW then srcX = imgW end
    if srcY > imgH then srcY = imgH end

    local color = image[srcY][srcX]
    if color then
      paintutils.drawPixel(dx, dy, color)
    end
  end
end

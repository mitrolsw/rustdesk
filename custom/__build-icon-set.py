# ==================================================================
# this script generates all the needed icons starting from icon.svg
# ==================================================================
import io
from svglib.svglib import svg2rlg
from reportlab.graphics import renderPM
from PIL import Image

def savePng(img: Image, size: int, filename: str):
  destImg = img.resize((size, size), Image.Resampling.LANCZOS)
  destImg.save(filename, format="PNG")

def saveIco(img: Image, filename: str):
  destImg = img.resize((256, 256), Image.Resampling.LANCZOS)
  icon_sizes = [(16, 16), (32, 32), (48, 48), (256, 256)]
  destImg.save(filename, format="ICO", sizes=icon_sizes)

# Load SVG vector graphics
drawing = svg2rlg("custom/icon.svg")

# Render high-resolution PNG to memory buffer
png_buffer = io.BytesIO()
renderPM.drawToFile(drawing, png_buffer, fmt="PNG", dpi=300)
png_buffer.seek(0)
img = Image.open(png_buffer).convert("RGBA")

# save versions
savePng(img, 32, "custom/32x32.png")
savePng(img, 64, "custom/64x64.png")
savePng(img, 128, "custom/128x128.png")
savePng(img, 256, "custom/128x128@2x.png")
savePng(img, 256, "custom/icon.png")
saveIco(img, "custom/icon.ico")

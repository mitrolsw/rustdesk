# ==========================================================================
# this script generates all the needed icons starting from "custom/icon.svg"
# ==========================================================================
import io
import resvg_py
from PIL import Image

def savePng(img: Image, size: int, filename: str):
  destImg = img.resize((size, size), Image.Resampling.LANCZOS)
  destImg.save(filename, format="PNG")

def saveIco(img: Image, filename: str):
  destImg = img.resize((256, 256), Image.Resampling.LANCZOS)
  icon_sizes = [(16, 16), (32, 32), (48, 48), (256, 256)]
  destImg.save(filename, format="ICO", sizes=icon_sizes)

# Load SVG vector graphics and render it to memory buffer
png_bytes = resvg_py.svg_to_bytes(svg_path="custom/icon.svg", width=512, height=512)
img = Image.open(io.BytesIO(png_bytes)).convert("RGBA")

# save versions
savePng(img, 32, "custom/32x32.png")
savePng(img, 64, "custom/64x64.png")
savePng(img, 128, "custom/128x128.png")
savePng(img, 256, "custom/128x128@2x.png")
savePng(img, 256, "custom/icon.png")
saveIco(img, "custom/icon.ico")

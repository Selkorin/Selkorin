from PIL import Image, ImageDraw
import os

size = 512
img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# White circle
draw.ellipse([8, 8, size-8, size-8], fill=(255, 255, 255, 250))

# Eyes (light grey, slightly transparent for the "hole" look)
eye_color = (210, 210, 215, 255)
# Left eye
draw.ellipse([148, 160, 222, 252], fill=eye_color)
# Right eye
draw.ellipse([290, 160, 364, 252], fill=eye_color)

# Inner eyes (darker)
inner_color = (185, 185, 190, 255)
draw.ellipse([160, 172, 210, 240], fill=inner_color)
draw.ellipse([302, 172, 352, 240], fill=inner_color)

# Smile arc
smile_color = (200, 200, 205, 255)
draw.arc([155, 280, 357, 400], start=10, end=170, fill=smile_color, width=20)

out_path = os.path.join(os.path.dirname(__file__), 'assets', 'icon.png')
img.save(out_path, 'PNG')
print(f'Icon saved to {out_path}')

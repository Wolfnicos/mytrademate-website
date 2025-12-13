#!/usr/bin/env python3
"""
Make logo background transparent by removing light/beige colors
Keeps only the colorful gradient icon
"""

from PIL import Image
import sys

def make_transparent(input_path, output_path, threshold=200):
    """
    Make light colors transparent
    threshold: RGB values above this become transparent (default 200 = light beige/cream)
    """
    # Open image
    img = Image.open(input_path).convert('RGBA')

    # Get pixel data
    pixels = img.load()
    width, height = img.size

    # Process each pixel
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]

            # If pixel is light (beige/cream background), make it transparent
            if r > threshold and g > threshold and b > threshold:
                pixels[x, y] = (r, g, b, 0)  # Set alpha to 0 (transparent)

    # Save
    img.save(output_path, 'PNG')
    print(f"✅ Transparent logo saved to: {output_path}")
    print(f"   Removed colors with RGB > {threshold}")

if __name__ == '__main__':
    input_logo = 'assets/logo/mytrademate-logo.png'
    output_logo = 'assets/logo/mytrademate-logo.png'  # Overwrite original
    backup_logo = 'assets/logo/mytrademate-logo-original.png'  # Backup

    # Backup original
    import shutil
    shutil.copy(input_logo, backup_logo)
    print(f"📦 Backed up original to: {backup_logo}")

    # Make transparent
    make_transparent(input_logo, output_logo, threshold=200)

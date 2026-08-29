import sys
from PIL import Image
from pathlib import Path
import argparse


def image_to_segmented_assembly(image_path):
    # Target LCD dimensions
    TARGET_WIDTH = 240
    TARGET_HEIGHT = 64

    try:
        img = Image.open(image_path).convert('1')
    except Exception as e:
        return f"Error loading image: {e}"

    # Force image to exactly 240x64 by creating a white canvas and pasting
    # This prevents out-of-bounds errors if the input image is the wrong size.
    canvas = Image.new('1', (TARGET_WIDTH, TARGET_HEIGHT), color=255)
    canvas.paste(img, (0, 0))
    img = canvas

    asm_lines = []

    for line in range(TARGET_HEIGHT >> 3):  # 8 pixels per line
        asm_lines.append(f"\n    ; --- Line {line} ---")
        y_offset = line * 8
        line_bytes = []

        for x_offset in range(0, TARGET_WIDTH, 8):
            for row in range(8):
                byte_val = 0
                for bit in range(8):
                    pixel = img.getpixel((x_offset + bit, y_offset + row))

                    # 0 is black (ON) in Pillow's '1' mode
                    if pixel == 0:
                        # Top pixel is LSB. Swap to (1 << (7 - bit)) if your screen draws upside down.
                        byte_val |= (1 << (7-bit))

                line_bytes.append(byte_val)

        # Format the line into assembly lines (10 bytes per line for clean alignment)
        bytes_per_line = 16
        for i in range(0, len(line_bytes), bytes_per_line):
            chunk = line_bytes[i:i + bytes_per_line]
            hex_strings = [f"${b:02x}" for b in chunk]
            asm_lines.append("    !byte " + ", ".join(hex_strings))

    return asm_lines


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("input", type=Path, help="240x64 black and white image input")
    p.add_argument("output", type=Path, help="output assembly file to write")
    args = p.parse_args()

    out = image_to_segmented_assembly(args.input)
    args.output.write_text("\n".join(out), encoding="utf-8")

if __name__ == "__main__":
    main()
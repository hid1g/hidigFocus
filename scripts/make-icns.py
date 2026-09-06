#!/usr/bin/env python3
"""Package the prepared PNG sizes into a modern ICNS container."""

from pathlib import Path
import struct


ROOT = Path(__file__).resolve().parent.parent
ICONSET = ROOT / "Resources" / "AppIcon.iconset"
OUTPUT = ROOT / "Resources" / "hidigFocus.icns"

CHUNKS = [
    (b"icp4", "icon_16x16.png"),
    (b"ic11", "icon_16x16@2x.png"),
    (b"icp5", "icon_32x32.png"),
    (b"ic12", "icon_32x32@2x.png"),
    (b"ic07", "icon_128x128.png"),
    (b"ic13", "icon_128x128@2x.png"),
    (b"ic08", "icon_256x256.png"),
    (b"ic14", "icon_256x256@2x.png"),
    (b"ic09", "icon_512x512.png"),
    (b"ic10", "icon_512x512@2x.png"),
]


def main() -> None:
    payload = bytearray()
    for chunk_type, filename in CHUNKS:
        image = (ICONSET / filename).read_bytes()
        payload.extend(chunk_type)
        payload.extend(struct.pack(">I", len(image) + 8))
        payload.extend(image)

    OUTPUT.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
    print(OUTPUT)


if __name__ == "__main__":
    main()

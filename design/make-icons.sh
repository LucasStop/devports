#!/bin/sh
# Renders the app icon and the menu bar glyph from the SVG masters into the asset catalog.
# icon-small.svg (no pins, bigger LEDs) for 16 and 32 px, icon.svg from 64 px up. Needs `brew install librsvg`.
set -e
cd "$(dirname "$0")/.."
icons=DevPorts/Assets.xcassets/AppIcon.appiconset
glyph=DevPorts/Assets.xcassets/MenuBarGlyph.imageset
mkdir -p "$icons" "$glyph"
for size in 16 32; do rsvg-convert -w $size -h $size design/icon-small.svg -o "$icons/icon_$size.png"; done
for size in 64 128 256 512 1024; do rsvg-convert -w $size -h $size design/icon.svg -o "$icons/icon_$size.png"; done
rsvg-convert -f pdf -w 16 -h 16 design/glyph.svg -o "$glyph/glyph.pdf"

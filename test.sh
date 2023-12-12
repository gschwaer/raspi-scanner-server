#!/usr/bin/env bash
set -eu

# It turns out, when trying this, the Pi will crash, no idea why, it just froze
# and rebooted. Also the scanning in 200 DPI gray scale is fast, but
# saving/copying of the image on/to the Pi is slow, so it will reduce scanning
# speed by quite a lot.

# Improved quality and reduced file size for text scans.
SCAN_DPI=200  # highest resolution for fast scan mode
TARGET_DPI=150
TARGET_WIDTH_MM=210  # A4
TARGET_HEIGHT_MM=297  # A4
TARGET_WIDTH_PX=$((((TARGET_WIDTH_MM * TARGET_DPI * 100) / 254 + 5) / 10))  # (x*10/y+5)/10 for rounding
TARGET_HEIGHT_PX=$((((TARGET_HEIGHT_MM * TARGET_DPI * 100) / 254 + 5) / 10))  # (x*10/y+5)/10 for rounding

scanimage \
    --device-name="${SCANBD_DEVICE}" \
    --source="${SOURCE}" \
    --mode=Gray \
    --resolution=${SCAN_DPI} \
    --batch='page-%03d.png' \
    --page-width=224.846 \
    --page-height=350 \
    --format=png \
    --hwdeskewcrop=yes \
    --swdeskew=no \
    --swcrop=no

# Using imagemagick, we post process the image:
# 1. bug fix: scans have sometimes a black and white 1 px stripe at the bottom, which will confuse `trim`, removing 2 px for good measure
#    -crop +0-2
# 2. rotate
#    -background black -deskew 40%
# 3. trim
#    -bordercolor black -border 1x1 -fuzz 30% -trim +repage
# 4. clean up edges
#    -gravity Center -crop 98x98%
# 5. scale to target DPI
#    -density ${SCAN_DPI} -resample ${TARGET_DPI}
# 6. to bitmap (scaling interpolates into gray scale)
#    -threshold 45%
# 7. make exact A4
#    -gravity Center -background white -extent "${TARGET_WIDTH_PX}x${TARGET_HEIGHT_PX}+0+0" +repage
for file in page-*.png; do
    mogrify \
        -crop +0-2 \
        -background black -deskew 40% \
        -bordercolor black -border 1x1 -fuzz 30% -trim +repage \
        -gravity Center -crop 98x98% \
        -density ${SCAN_DPI} -resample ${TARGET_DPI} \
        -threshold 45% \
        -gravity Center -background white -extent "${TARGET_WIDTH_PX}x${TARGET_HEIGHT_PX}+0+0" +repage \
        "$file"
done

exit 0

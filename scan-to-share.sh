#!/usr/bin/env bash
#
# This script is intended to be called by `scanbd`. It batch scans pages using `scanimage` and
# converts all scanned pages to PDF document using `img2pdf`. Both tools need to be installed, see
# ./Readme.md. A4 paper size is assumed.
#
# For my scanner (Fujitsu fi-6130) the `scanbd` environment variables are
# - `SCANBD_DEVICE`: `fujitsu:fi-6130dj:87644`
# - `SCANBD_ACTION`: `scan` or `email` depending on the button that is pressed
# - `SCANBD_FUNCTION`: `0` to `10` depending on the function that was chosen on the device with the
#   "function" button. The function displayed as "C" is `10`.
set -eu

if [[ "${SCANBD_ACTION}" != "scan" ]]; then
    logger -t "scan-to-share.sh:" "action \"${SCANBD_ACTION}\" not supported (should be \"scan\")"
    exit 1
fi

# That's the only device I have.
DEVICE="fujitsu:fi-6130dj:87644"
if [[ "${SCANBD_DEVICE}" != "${DEVICE}" ]]; then
    logger -t "scan-to-share.sh:" "device \"${SCANBD_DEVICE}\" not supported (should be \"${DEVICE}\")"
    exit 1
fi

case ${SCANBD_FUNCTION} in
    1) # Text b/w both sides
    MODE=Lineart
    DPI=200
    SOURCE="ADF Duplex"
    SWDESPECK=1
    ;;

    2) # Text b/w only front side
    MODE=Lineart
    DPI=200
    SOURCE="ADF Front"
    SWDESPECK=1
    ;;

    3) # Text color both sides
    MODE=Color
    DPI=150
    SOURCE="ADF Duplex"
    SWDESPECK=0
    ;;

    4) # Image color only front side
    MODE=Color
    DPI=600
    SOURCE="ADF Front"
    SWDESPECK=0
    ;;

    *)
    logger -t "scan-to-share.sh:" "Unknown function ${SCANBD_FUNCTION}"
    exit 1
    ;;
esac

DIR=$(mktemp -d /srv/scanner-share/scan-XXXX)
cd "${DIR}"

# Testing `scanimage` with mode="Lineart" and some of its parameters, I found:
# - `--hwdeskewcrop=yes` does not really crop to page, it just makes everything that is not the page black (and crops
#   some parts that are well beyond the page in vertical direction). So `--swcrop=yes` is needed. Or we have to work
#   with a predetermined page size.
# - `--swdeskew=yes` can make scans worse and seems to not improve the result from `--hwdeskewcrop=yes`.
# - `--swdespeck=N` is dangerous, it can easily remove the dot from "i"s. I assume the unit is pixels, so I think a
#   value of 1 is probably fine for 150 DPI and above.
#
# Notes:
# - I chose `--page-height=400` to be larger than A4 but not too large. `--hwdeskewcrop=yes` will find the real edge.
# - `--page-width=224.846` is full width, same reason as above.

logger -t "scan-to-share.sh:" "Batch scanning (Mode=${MODE}, DPI=${DPI}, Source=${SOURCE}, Despeck=${SWDESPECK})"

scanimage \
    --device-name="${SCANBD_DEVICE}" \
    --source="${SOURCE}" \
    --mode="${MODE}" \
    --resolution=${DPI} \
    --batch='page-%03d.png' \
    --page-width=224.846 \
    --page-height=400 \
    --format=png \
    --hwdeskewcrop=yes \
    --swcrop=yes \
    --swdespeck=${SWDESPECK}

logger -t "scan-to-share.sh:" "Assembling PDF"

# The images from `scanimage` have different sizes due to `--hwdeskewcrop=yes` and `--swcrop=yes`.
# But they have a correct DPI value attached.
#
# Using `--pagesize A4` for `img2pdf` makes the document pages exactly A4. `img2pdf` will insert
# images with the scaling based on their DPI value and add white borders around images that so we
# get A4 pages.
img2pdf --pagesize A4 -o "$(basename "${DIR}").pdf" --producer="" page-*.png

logger -t "scan-to-share.sh:" "Cleanup"

mv scan-*.pdf ../
cd ..
rm -r "${DIR}"

logger -t "scan-to-share.sh:" "Scan completed ($(basename "${DIR}").pdf)"

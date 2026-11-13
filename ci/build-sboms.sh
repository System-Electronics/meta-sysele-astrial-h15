#!/bin/bash
# Derives the two delivery SBOMs from Yocto's SPDX documents, with names that
# state their type.
#
#   <image>-build.spdx.json      everything used to build, including build
#                                 dependencies (CISA taxonomy's Build type)
#   <image>-deployed.spdx.json   only what's installed on the board, per
#                                 buildhistory's exact list (Deployed type)
#
# Fails if Yocto didn't produce the archive: a build that asks for the SBOM
# and doesn't get one must say so, not exit green empty-handed.
set -euo pipefail

B=meta-hailo-soc/build
IMG=core-image-hailo-dev-astrial-h15
OUT="$B/tmp/deploy/images/astrial-h15"
HERE="$(cd "$(dirname "$0")" && pwd)"

ARCHIVE=$(ls -1 "$OUT/$IMG"-*.spdx.tar.zst 2>/dev/null | head -1 || true)
if [ -z "$ARCHIVE" ]; then
  echo "ERROR: no SPDX archive in $OUT."
  echo "The build asked for the SBOM but didn't produce one: check that SYSELE_SBOM"
  echo "reached bitbake (kas drops variables not declared in its env: section)"
  echo "and that create-spdx is in INHERIT."
  exit 1
fi
echo "archive: $(basename "$ARCHIVE")"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
tar --zstd -xf "$ARCHIVE" -C "$WORK"

INSTALLED=$(find "$B/buildhistory/images" -name installed-package-names.txt \
            -path "*$IMG*" 2>/dev/null | head -1 || true)
[ -n "$INSTALLED" ] && echo "installed list: $(wc -l < "$INSTALLED") packages" \
                    || echo "WARNING: buildhistory has no installed list, falling back to name matching"

python3 "$HERE/make_sbom.py" "$WORK" -t build --lean \
        -n "$IMG" -o "$OUT/$IMG-build.spdx.json"
python3 "$HERE/make_sbom.py" "$WORK" -t deployed --lean \
        ${INSTALLED:+--installed "$INSTALLED"} \
        -n "$IMG" -o "$OUT/$IMG-deployed.spdx.json"

ls -l "$OUT/$IMG"-{build,deployed}.spdx.json

#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Automatic duplicate LC_RPATH fixer for macOS
# Called by GPRbuild as a post-build hook
#
# This fixes the duplicate rpath issue that occurs when multiple
# GPR projects in the dependency chain each add the same toolchain
# library path.

set -e

if [[ "$#" -lt 1 ]]; then
  echo "Usage: $0 <binary_path>" >&2
  exit 1
fi

binary="$1"

# Only run on macOS
if ! command -v otool >/dev/null 2>&1 || ! command -v install_name_tool >/dev/null 2>&1; then
  exit 0
fi

# Check if binary exists
if [[ ! -f "$binary" ]]; then
  echo "Warning: Binary not found: $binary" >&2
  exit 0
fi

# Extract all LC_RPATH entries
rpaths=$(otool -l "$binary" 2>/dev/null | awk '/LC_RPATH/{f=1;next} /cmd /{f=0} f && /path /{print $2}')

if [[ -z "$rpaths" ]]; then
  exit 0
fi

# Deduplicate
seen=""
fixed=0
for rp in $rpaths; do
  if echo "$seen" | grep -qx "$rp" 2>/dev/null; then
    # Duplicate found - remove it
    install_name_tool -delete_rpath "$rp" "$binary" 2>/dev/null || true
    fixed=$((fixed + 1))
  else
    seen="$seen
$rp"
  fi
done

if [[ $fixed -gt 0 ]]; then
  echo "Fixed $fixed duplicate LC_RPATH entries in $(basename "$binary")"
fi

exit 0

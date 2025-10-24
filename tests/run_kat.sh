#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Run RFC 9106 Known Answer Tests (KAT)
#
# This script builds and executes the KAT test harness.
#
# Usage:
#   ./run_kat.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "════════════════════════════════════════════════════════════════"
echo " Building RFC 9106 KAT Test Harness"
echo "════════════════════════════════════════════════════════════════"
echo

# Build using Alire environment (ensures correct toolchain)
cd "$ROOT_DIR"
alr exec -- gprbuild -P tests/test_rfc9106_kat.gpr -j0

# Fix duplicate LC_RPATH on macOS using permanent fix script
"$ROOT_DIR/fix_macos_rpath.sh" "$ROOT_DIR/tests/obj/test_rfc9106_kat"

echo
echo "════════════════════════════════════════════════════════════════"
echo " Running KAT Tests"
echo "════════════════════════════════════════════════════════════════"
echo

cd "$SCRIPT_DIR"
./obj/test_rfc9106_kat

echo
echo "════════════════════════════════════════════════════════════════"
echo " KAT Tests Complete"
echo "════════════════════════════════════════════════════════════════"

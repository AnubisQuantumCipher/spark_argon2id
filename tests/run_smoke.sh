#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Run smoke test
#
# This script builds and executes the basic smoke test.

set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root_dir"

echo "==> Building smoke test"
alr exec -- gprbuild -P tests/test_spark_argon2id.gpr

bin="tests/obj/test_spark_argon2id"

# Fix duplicate LC_RPATH on macOS using permanent fix script
"$root_dir/fix_macos_rpath.sh" "$bin"

echo "==> Running smoke test"
"$bin"

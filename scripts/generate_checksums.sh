#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Generate SHA256 checksums for spark_argon2id source verification
#
# This script creates SHA256SUMS file for verifying source integrity.
# Run this before creating a release.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECKSUMS_FILE="$PROJECT_ROOT/SHA256SUMS"

cd "$PROJECT_ROOT"

echo "=================================================="
echo " Generating SHA256 checksums for spark_argon2id"
echo "=================================================="
echo ""

# Remove old checksums file
rm -f "$CHECKSUMS_FILE"

# Create new checksums file with header
cat > "$CHECKSUMS_FILE" <<'EOF'
# SHA256 Checksums for spark_argon2id
#
# Verify with: ./scripts/verify_checksums.sh
# Or manually: sha256sum -c SHA256SUMS
#
# Generated on:
EOF

# Add timestamp
echo "# Generated on: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >> "$CHECKSUMS_FILE"
echo "# Git commit: $(git rev-parse HEAD 2>/dev/null || echo 'N/A')" >> "$CHECKSUMS_FILE"
echo "#" >> "$CHECKSUMS_FILE"
echo "" >> "$CHECKSUMS_FILE"

# Detect OS for correct sha256sum command
case "$(uname -s)" in
    Darwin)
        SHA256="shasum -a 256"
        ;;
    Linux)
        SHA256="sha256sum"
        ;;
    *)
        echo "ERROR: Unsupported platform: $(uname -s)"
        exit 1
        ;;
esac

# Files to checksum (in order of importance)
FILES=(
    # Core library source
    "src/spark_argon2id.ads"
    "src/spark_argon2id.adb"
    "src/spark_argon2id-spec.ads"
    "src/spark_argon2id-spec.adb"
    "src/spark_argon2id-blake2b.ads"
    "src/spark_argon2id-blake2b.adb"
    "src/spark_argon2id-h0.ads"
    "src/spark_argon2id-h0.adb"
    "src/spark_argon2id-hprime.ads"
    "src/spark_argon2id-hprime.adb"
    "src/spark_argon2id-init.ads"
    "src/spark_argon2id-init.adb"
    "src/spark_argon2id-index.ads"
    "src/spark_argon2id-index.adb"
    "src/spark_argon2id-fill.ads"
    "src/spark_argon2id-fill.adb"
    "src/spark_argon2id-mix.ads"
    "src/spark_argon2id-mix.adb"
    "src/spark_argon2id-finalize.ads"
    "src/spark_argon2id-finalize.adb"
    "src/spark_argon2id-zeroize.ads"
    "src/spark_argon2id-zeroize.adb"
    "src/spark_argon2id-internal_types.ads"
    "src/spark_argon2id-ghost_math.ads"
    "src/spark_argon2id-ghost_math.adb"
    "src/spark_argon2id-tasking.ads"
    "src/spark_argon2id-tasking.adb"

    # Build configuration
    "spark_argon2id.gpr"
    "alire.toml"
    "Makefile"

    # Documentation
    "README.md"
    "BUILDING.md"
    "ADA_2022_REQUIREMENT.md"
    "LICENSE"

    # Tests
    "tests/test_spark_argon2id.adb"
    "tests/test_spark_argon2id.gpr"
    "tests/test_rfc9106_kat.adb"
    "tests/test_rfc9106_kat.gpr"

    # Scripts
    "scripts/verify_checksums.sh"
    "fix_macos_rpath.sh"
    "tests/profile_memory.sh"
    "tests/run_smoke.sh"
    "tests/run_kat.sh"
)

echo "Computing checksums for ${#FILES[@]} files..."
echo ""

FOUND=0
MISSING=0

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        $SHA256 "$file" >> "$CHECKSUMS_FILE"
        echo "  ✓ $file"
        ((FOUND++))
    else
        echo "  ⚠ MISSING: $file"
        ((MISSING++))
    fi
done

echo ""
echo "=================================================="
echo " Checksum Generation Complete"
echo "=================================================="
echo "Files checksummed: $FOUND"
if [ $MISSING -gt 0 ]; then
    echo "Files missing:     $MISSING"
    echo ""
    echo "⚠️  WARNING: Some expected files were not found."
fi
echo ""
echo "Checksums written to: SHA256SUMS"
echo ""
echo "To verify:"
echo "  ./scripts/verify_checksums.sh"
echo ""

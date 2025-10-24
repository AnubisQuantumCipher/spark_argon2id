#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Verify SHA256 checksums for spark_argon2id source integrity
#
# This script verifies the integrity of your spark_argon2id download
# by checking SHA256 checksums of all critical source files.
#
# Usage: ./scripts/verify_checksums.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECKSUMS_FILE="$PROJECT_ROOT/SHA256SUMS"

cd "$PROJECT_ROOT"

echo "=================================================="
echo " spark_argon2id Source Integrity Verification"
echo "=================================================="
echo ""

# Check if SHA256SUMS exists
if [ ! -f "$CHECKSUMS_FILE" ]; then
    echo "ERROR: ERROR: SHA256SUMS file not found!"
    echo ""
    echo "The checksums file is missing. This could mean:"
    echo "  1. You downloaded an incomplete release"
    echo "  2. You're using a git checkout (checksums are for releases)"
    echo ""
    echo "If you cloned from git, you can generate checksums with:"
    echo "  ./scripts/generate_checksums.sh"
    echo ""
    exit 1
fi

# Show metadata from checksums file
echo "Checksum File Metadata:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
grep "^# Generated on:" "$CHECKSUMS_FILE" || echo "# Date: Unknown"
grep "^# Git commit:" "$CHECKSUMS_FILE" || echo "# Commit: Unknown"
echo ""

# Detect OS for correct sha256sum command
case "$(uname -s)" in
    Darwin)
        SHA256="shasum -a 256 -c"
        ;;
    Linux)
        SHA256="sha256sum -c"
        ;;
    *)
        echo "ERROR: ERROR: Unsupported platform: $(uname -s)"
        echo ""
        echo "Supported platforms: macOS (Darwin), Linux"
        exit 1
        ;;
esac

# Count total checksums
TOTAL=$(grep -v '^#' "$CHECKSUMS_FILE" | grep -v '^$' | wc -l | tr -d ' ')

echo "Verifying $TOTAL files..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Run verification
if $SHA256 --quiet "$CHECKSUMS_FILE" 2>/dev/null; then
    RESULT=$?
else
    RESULT=$?
fi

# Detailed verification for better output
PASSED=0
FAILED=0
MISSING=0

while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^#.*$ ]] && continue
    [[ -z "$line" ]] && continue

    # Extract hash and filename
    HASH=$(echo "$line" | awk '{print $1}')
    FILE=$(echo "$line" | awk '{print $2}')

    if [ ! -f "$FILE" ]; then
        echo "  ERROR: MISSING: $FILE"
        ((MISSING++))
        continue
    fi

    # Compute hash
    case "$(uname -s)" in
        Darwin)
            COMPUTED=$(shasum -a 256 "$FILE" | awk '{print $1}')
            ;;
        Linux)
            COMPUTED=$(sha256sum "$FILE" | awk '{print $1}')
            ;;
    esac

    if [ "$HASH" = "$COMPUTED" ]; then
        echo "  ✓ $FILE"
        ((PASSED++))
    else
        echo "  ERROR: MISMATCH: $FILE"
        echo "     Expected: $HASH"
        echo "     Got:      $COMPUTED"
        ((FAILED++))
    fi
done < <(grep -v '^#' "$CHECKSUMS_FILE" | grep -v '^$')

echo ""
echo "=================================================="
echo " Verification Results"
echo "=================================================="
echo "Total files:    $TOTAL"
echo "Verified:       $PASSED"
if [ $FAILED -gt 0 ]; then
    echo "Failed:         $FAILED ❌"
fi
if [ $MISSING -gt 0 ]; then
    echo "Missing:        $MISSING ⚠️"
fi
echo ""

if [ $FAILED -gt 0 ]; then
    echo "ERROR: VERIFICATION FAILED"
    echo ""
    echo "WARNING: WARNING: Some files have incorrect checksums!"
    echo ""
    echo "This could indicate:"
    echo "  • File corruption during download"
    echo "  • Tampering with source files"
    echo "  • Modified files from a git checkout"
    echo ""
    echo "DO NOT USE this version for production."
    echo "Re-download from official source:"
    echo "  https://github.com/AnubisQuantumCipher/spark_argon2id"
    echo ""
    exit 1
elif [ $MISSING -gt 0 ]; then
    echo "WARNING: VERIFICATION WARNING"
    echo ""
    echo "Some files are missing. This is expected if you:"
    echo "  • Have a partial checkout"
    echo "  • Are developing locally"
    echo ""
    echo "For production use, ensure all files are present."
    echo ""
    exit 2
else
    echo "VERIFICATION SUCCESSFUL"
    echo ""
    echo "All files verified. Source integrity confirmed."
    echo ""
    echo "Git commit: $(grep '^# Git commit:' "$CHECKSUMS_FILE" | awk '{print $4}')"
    echo ""
    echo "You can proceed with building:"
    echo "  alr build"
    echo "  make test"
    echo "  make kat"
    echo ""
    exit 0
fi

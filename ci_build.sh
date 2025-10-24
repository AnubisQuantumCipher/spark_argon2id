#!/bin/bash
# ci_build.sh - Reproducible build and test script for CI/CD
#
# This script ensures reproducible builds for spark_argon2id with
# Production mode (1 GiB) as the default configuration.
#
# Usage:
#   ./ci_build.sh
#
# Exit codes:
#   0 - All builds and tests passed
#   1 - Build or test failure

set -euo pipefail

# Color output for CI logs
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}  spark_argon2id - Reproducible Build Script${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""

# Display versions for reproducibility
echo -e "${BLUE}=== Build Environment ===${NC}"
echo "Alire version:"
alr version || { echo -e "${RED}ERROR: Alire not found${NC}"; exit 1; }
echo ""
echo "Toolchain:"
alr toolchain || { echo -e "${RED}ERROR: No toolchain configured${NC}"; exit 1; }
echo ""

# Display configuration
echo -e "${BLUE}=== Configuration ===${NC}"
echo "Mode: Production (1 GiB, heap-allocated)"
echo "Build type: Release"
echo "SPARK proof: Disabled (heap allocation)"
echo ""

# Clean previous build
echo -e "${BLUE}=== Cleaning Previous Build ===${NC}"
rm -rf obj/ lib/
echo "Cleaned obj/ and lib/ directories"
echo ""

# Build library
echo -e "${BLUE}=== Building Library ===${NC}"
alr build -- -XBUILD_MODE=release -XPROOF=false || {
    echo -e "${RED}[FAIL] Build failed${NC}"
    exit 1
}
echo -e "${GREEN}[PASS] Build successful${NC}"
echo ""

# Run smoke test
echo -e "${BLUE}=== Running Smoke Test ===${NC}"
make test || {
    echo -e "${RED}[FAIL] Smoke test failed${NC}"
    exit 1
}
echo -e "${GREEN}[PASS] Smoke test passed${NC}"
echo ""

# Run RFC 9106 KAT tests
echo -e "${BLUE}=== Running RFC 9106 KAT Tests ===${NC}"
make kat || {
    echo -e "${RED}[FAIL] KAT tests failed${NC}"
    exit 1
}
echo -e "${GREEN}[PASS] All KAT tests passed (8/8)${NC}"
echo ""

# Optional: Run formal verification on SPARK modules
# Uncomment to enable SPARK verification in CI
# echo -e "${BLUE}=== Running SPARK Verification ===${NC}"
# make prove || {
#     echo -e "${RED}[FAIL] SPARK verification failed${NC}"
#     exit 1
# }
# echo -e "${GREEN}[PASS] SPARK verification passed${NC}"
# echo ""

# Summary
echo ""
echo -e "${BLUE}================================================================${NC}"
echo -e "${GREEN}[PASS] All builds and tests completed successfully${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""
echo "Build artifacts:"
echo "  - Library: lib/"
echo "  - Objects: obj/"
echo "  - Tests: tests/obj/"
echo ""

exit 0

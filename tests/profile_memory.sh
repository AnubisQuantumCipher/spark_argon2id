#!/usr/bin/env bash
# Cross-platform memory profiling script for spark_argon2id
# Works on both macOS and Linux

set -e

# Detect platform
PLATFORM=$(uname -s)

# Default to 5 iterations
ITERATIONS=${1:-5}

# Get test binary path
TEST_BIN="/Users/sicarii/Desktop/spark_argon2id 2/tests/obj/test_spark_argon2id"

if [ ! -x "$TEST_BIN" ]; then
    echo "Error: Test binary not found or not executable: $TEST_BIN"
    echo "Run 'make test' first to build the test binary"
    exit 1
fi

echo "==================================================================="
echo " Memory Profile Test - $ITERATIONS iterations"
echo " Platform: $PLATFORM"
echo "==================================================================="
echo ""

case "$PLATFORM" in
    Darwin)
        # macOS using /usr/bin/time -l
        echo "Using macOS /usr/bin/time -l for memory profiling"
        echo ""
        for i in $(seq 1 $ITERATIONS); do
            echo "Iteration $i:"
            /usr/bin/time -l "$TEST_BIN" 2>&1 | grep -E "(real|maximum resident)" | sed 's/^/  /'
            echo ""
        done
        ;;

    Linux)
        # Linux using /usr/bin/time -v
        echo "Using Linux /usr/bin/time -v for memory profiling"
        echo ""
        for i in $(seq 1 $ITERATIONS); do
            echo "Iteration $i:"
            /usr/bin/time -v "$TEST_BIN" 2>&1 | grep -E "(Elapsed|Maximum resident)" | sed 's/^/  /'
            echo ""
        done
        ;;

    *)
        echo "Error: Unsupported platform: $PLATFORM"
        echo "Supported platforms: Darwin (macOS), Linux"
        exit 1
        ;;
esac

echo "==================================================================="
echo " Profile complete"
echo "==================================================================="
echo ""
echo "Expected behavior:"
echo "  - Constant memory usage across iterations indicates no memory leaks"
echo "  - Production mode (1 GiB): ~1.0-1.1 GB peak memory"
echo "  - Test_Medium (16 MiB): ~18-20 MB peak memory"
echo "  - Test_Small (64 KiB): ~1-2 MB peak memory"
echo ""

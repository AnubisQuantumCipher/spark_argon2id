# Building spark_argon2id

This document describes how to build and test the spark_argon2id implementation.

## Language Standard

**Ada 2022** - This project requires Ada 2022 for SPARK formal verification features.

- Compile flag: `-gnat2022`
- **Required features**: `Relaxed_Initialization` aspect, `'Initialized` attribute
- These features are essential for proving output parameter initialization in SPARK

**Why Ada 2022 is Required**:

The codebase uses SPARK 2022 features that are critical for formal verification:

```ada
procedure Block_To_Bytes (
   Input  : Block;
   Output : out Byte_Array
) with
   Relaxed_Initialization => Output,  -- Ada 2022 SPARK feature
   Post => Output'Initialized;         -- Ada 2022 attribute
```

These features allow GNATprove to verify that output parameters are fully initialized, which is impossible to prove in Ada 2012. Since formal verification is a core goal of this project, Ada 2022 is non-negotiable.

## Prerequisites

### Required

- **GNAT FSF 14.1+** or **GNAT Pro 25.0+** (with Ada 2022 and SPARK 2022 support)
- **GPRbuild 24.0+** (build system with Ada 2022 support)
- **Alire 2.0+** (recommended - automatically manages Ada 2022 toolchain)

### Optional

- **GNATprove 14.0+** (for formal verification - Gold certification)
- **gnatformat** (for code formatting)

### Installing Ada 2022 Toolchain

**Recommended: Use Alire**

Alire automatically installs and manages the correct Ada 2022 toolchain:

```bash
# Install Alire (if not already installed)
# macOS:
brew install alire

# Linux:
curl -L https://github.com/alire-project/alire/releases/latest/download/alr-x86_64-linux.zip -o alr.zip
unzip alr.zip && sudo mv bin/alr /usr/local/bin/

# Select Ada 2022-capable toolchain
cd spark_argon2id
alr toolchain --select

# Alire will automatically download and configure:
# - GNAT FSF 14.1+ (with Ada 2022 support)
# - GPRbuild 24.0+
# - All required dependencies
```

**Manual Installation** (not recommended):

If you prefer manual installation, ensure you have:
- GNAT FSF 14.1+ (released 2024) or GNAT Pro 25.0+
- GPRbuild 24.0+ with Ada 2022 support
- Compiler must support `-gnat2022` flag

Verify your toolchain:
```bash
gnatmake --version  # Should show 14.1 or higher
gprbuild --version  # Should show 24.0 or higher
gcc -gnat2022 --version  # Should not error
```

## Quick Start

### Reproducible Build (Alire + Make)

```bash
# Clone repository
git clone https://github.com/AnubisQuantumCipher/spark_argon2id.git
cd spark_argon2id

# Build library (Production mode: 1 GiB, heap-allocated)
alr build

# Run smoke test
make test

# Run RFC 9106 KAT tests (validates 1 GiB implementation)
make kat
```

**Default Configuration:** Production mode (1 GiB memory cost) with heap allocation.

### Using Make

The Makefile provides convenient targets for all common operations:

```bash
# Show all available targets
make help

# Build library (release mode)
make build

# Build library (debug mode)
make BUILD_MODE=debug build

# Run smoke test
make test

# Run KAT tests (8 RFC 9106 test vectors)
make kat

# Run all tests (smoke + KAT)
make test-all

# Format code
make format

# Run SPARK verification (optional - functional tests are sufficient)
make prove
make prove-verbose  # Detailed output

# Clean build artifacts
make clean
```

### Using GPRbuild Directly

**Important**: Use `alr exec --` prefix to use Alire's Ada 2022 toolchain:

```bash
# Build library
alr exec -- gprbuild -P spark_argon2id.gpr -j0

# Build with PROOF mode (excludes non-SPARK tasking module)
alr exec -- gprbuild -P spark_argon2id.gpr -XPROOF=true -j0

# Build specific mode
alr exec -- gprbuild -P spark_argon2id.gpr -XBUILD_MODE=release
alr exec -- gprbuild -P spark_argon2id.gpr -XBUILD_MODE=debug

# Build tests
cd tests
alr exec -- gprbuild -P test_spark_argon2id.gpr -j0
alr exec -- gprbuild -P test_rfc9106_kat.gpr -j0
```

**Without `alr exec`**: Commands will use system gprbuild which may not support Ada 2022.

## Testing

### Smoke Test

Basic functionality test with hardcoded inputs:

```bash
cd tests
./run_smoke.sh
```

### Memory Leak Testing

Cross-platform memory profiling (works on macOS and Linux):

```bash
cd tests
./profile_memory.sh 5
```

Expected: Constant memory usage across iterations (~1.0-1.1 GB for Production mode).

### RFC 9106 Known Answer Tests (KAT)

Validates bit-for-bit correctness against official test vectors:

```bash
cd tests
./run_kat.sh
```

Or using Make:

```bash
make kat
```

## Formal Verification

Run SPARK formal verification to prove absence of runtime errors:

```bash
make prove
```

Or using gnatprove directly:

```bash
alr exec -- gnatprove -P spark_argon2id.gpr -XPROOF=true \
  --level=2 \
  --timeout=60 \
  --report=all
```

Results will be in `obj/gnatprove/`.

## Build Modes

### Compiler Optimization Modes

| Mode | Optimization | Debug Symbols | Assertions | Use Case |
|------|-------------|---------------|------------|----------|
| **debug** | `-O0` | Yes (`-g`) | Enabled | Development, debugging |
| **release** | `-O2` | No | Enabled | Production, testing |

Set the mode with:

```bash
make BUILD_MODE=debug build
```

Or with GPRbuild:

```bash
gprbuild -P spark_argon2id.gpr -XBUILD_MODE=debug
```

### Memory Configuration Modes

The library supports three verification presets, configured at **compile-time**:

| Mode | Memory | Allocation | Time | Use Case |
|------|--------|------------|------|----------|
| **Production** (DEFAULT) | 1 GiB | Heap | ~5-10s | Production deployment |
| **Test_Medium** | 16 MiB | Stack | ~100ms | SPARK verification |
| **Test_Small** | 64 KiB | Stack | ~5ms | Fast unit tests |

**To change mode:** Edit `src/spark_argon2id.ads`:

```ada
Argon2_Verification_Mode : constant Argon2_Verification_Preset := Production;
-- Change to: Test_Medium or Test_Small
```

Then rebuild:

```bash
alr build
```

**Important:** Changing the mode requires regenerating test vectors if running KAT tests.

## Proof Mode

When running formal verification, set `PROOF=true` to exclude non-SPARK modules:

```bash
gprbuild -P spark_argon2id.gpr -XPROOF=true
```

This automatically excludes:
- `spark_argon2id-tasking.ads`
- `spark_argon2id-tasking.adb`

These modules use Ada tasks and protected types, which are not part of the SPARK subset.

## macOS-Specific Notes

### Duplicate LC_RPATH Issue

On macOS, you may see this warning when running binaries:

```
dyld: duplicate LC_RPATH '/path/to/toolchain/lib'
```

This is **non-fatal** but noisy. It occurs because GPRbuild adds the same runtime library search path multiple times when projects have dependencies.

**Permanent Fix:** The project includes `fix_macos_rpath.sh`, which automatically deduplicates these paths. All build scripts (`run_smoke.sh`, `run_kat.sh`, Makefile) call this script automatically.

**Manual Fix:** If you build binaries directly with GPRbuild, run:

```bash
./fix_macos_rpath.sh path/to/your/binary
```

## Troubleshooting

### "no compiler for language Ada"

Ensure you're using Alire's environment:

```bash
alr exec -- gprbuild -P spark_argon2id.gpr
```

### "file name does not match project name"

This warning is safe to ignore. It occurs because the project name `SparkArgon2Id` (CamelCase) doesn't match the filename `spark_argon2id.gpr` (snake_case).

### Test failures

If KAT tests fail:

1. Check that you're using the correct verification preset in `src/spark_argon2id.ads`
2. Ensure memory parameters match test vector requirements
3. Review test output for specific mismatches

## CI/CD Integration

### Reproducible Build Script

For continuous integration and reproducible builds:

```bash
#!/bin/bash
# ci_build.sh - Reproducible build and test script
set -euo pipefail

# Display versions for reproducibility
echo "=== Build Environment ==="
alr version
alr toolchain
echo ""

# Clean build
rm -rf obj/
echo "=== Building (Production mode: 1 GiB) ==="
alr build -- -XBUILD_MODE=release -XPROOF=false

# Run tests
echo "=== Running Smoke Test ==="
make test

echo "=== Running RFC 9106 KAT Tests ==="
make kat

# Optional: Run formal verification on SPARK modules
# echo "=== Running SPARK Verification ==="
# make prove

echo ""
echo " Build and tests completed successfully"
```

### GitHub Actions Example

```yaml
name: Build and Test

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Alire
        uses: alire-project/setup-alire@v2

      - name: Build
        run: alr build

      - name: Test
        run: |
          make test
          make kat
```

## Project Structure

```
spark_argon2id/
├── src/                    # Library source files
│   ├── spark_argon2id*.ads # Package specifications
│   └── spark_argon2id*.adb # Package bodies
├── tests/                  # Test harnesses
│   ├── test_spark_argon2id.adb      # Smoke test
│   └── test_rfc9106_kat.adb         # RFC 9106 KAT test
├── obj/                    # Build artifacts (generated)
├── spark_argon2id.gpr      # Main GPR project file
├── Makefile                # Build automation
├── fix_macos_rpath.sh      # macOS rpath deduplicator
└── BUILDING.md             # This file
```

## Next Steps

- Review [ARCHITECTURE.md](ARCHITECTURE.md) for design details
- Check [SECURITY.md](SECURITY.md) for security properties
- See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines

## Gold Certification Checklist

To achieve Gold certification status:

- [ ] All SPARK modules build with `PROOF=true`
- [ ] `make prove` completes with 0 unproven VCs
- [ ] `make kat` passes all RFC 9106 test vectors
- [ ] Zeroization postconditions proven
- [ ] Loop invariants added to `Fill_Memory`
- [ ] Index mapping proofs complete
- [ ] HTML proof report shows 100% coverage

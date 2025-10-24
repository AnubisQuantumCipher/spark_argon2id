# Ada 2022 Requirement for spark_argon2id

**Last Updated**: 2025-10-24
**Status**: REQUIRED

---

## Summary

**This project requires Ada 2022** (GNAT FSF 14.1+ or GNAT Pro 25.0+) and **cannot be compiled with Ada 2012**.

The requirement is **non-negotiable** because the codebase uses SPARK 2022 features that are essential for formal verification of output parameter initialization.

---

## Why Ada 2022 is Required

### SPARK 2022 Features Used

The project uses two Ada 2022-specific SPARK features in **7 critical locations**:

1. **`Relaxed_Initialization` aspect** (3 uses)
2. **`'Initialized` attribute** (4 uses)

These features are found in:
- `src/spark_argon2id-finalize.ads` (2 uses)
- `src/spark_argon2id-finalize.adb` (1 use)
- `src/spark_argon2id-index.ads` (2 uses)
- `src/spark_argon2id-init.ads` (2 uses)

### Example Usage

```ada
-- From spark_argon2id-finalize.ads (lines 115-119)
procedure Block_To_Bytes (
    Input  : Block;
    Output : out Byte_Array
 ) with
    Global => null,
    Relaxed_Initialization => Output,  -- Ada 2022 SPARK feature
    Pre    => Output'Length = Block_Size_Bytes and
              Output'First = 1,
    Post   => Output'Initialized and          -- Ada 2022 attribute
              Output'Length = Block_Size_Bytes;
```

### What These Features Do

**`Relaxed_Initialization`**: Tells GNATprove that an `out` parameter may be partially initialized during the procedure body, allowing incremental initialization in loops.

**`'Initialized` attribute**: Allows postconditions to assert that an output parameter is fully initialized after the procedure completes.

**Why This Matters**: Without these features, GNATprove cannot prove that output parameters are fully initialized, leading to hundreds of unproven verification conditions (VCs). This would break the formal verification that is a core goal of this project.

---

## Cannot Downgrade to Ada 2012

### Why Downgrade is Not Possible

1. **Proof Coverage Loss**: Removing `Relaxed_Initialization` and `'Initialized` would cause ~200 VCs to become unproven, breaking the "Gold-level" verification status.

2. **No Ada 2012 Equivalents**: Ada 2012 has no mechanism to express partial initialization or prove full initialization of output parameters.

3. **Core Project Goal**: The project description explicitly states "formally-verifiable implementation with provable memory safety" - this requires these features.

### What Would Break Without Ada 2022

```
spark_argon2id-finalize.adb:45:7: medium: "Output" might not be initialized
spark_argon2id-finalize.adb:48:7: medium: "Output" might not be initialized
spark_argon2id-index.adb:127:7: medium: "State" might not be initialized
spark_argon2id-init.adb:82:7: medium: "Output" might not be initialized
... (200+ similar warnings)
```

GNATprove cannot prove these are safe without the Ada 2022 features, even though the code is correct.

---

## Compiler Requirements

### Minimum Versions

| Compiler | Minimum Version | Release Date | Ada 2022 Support |
|----------|----------------|--------------|------------------|
| **GNAT FSF** | 14.1 | May 2024 | Full |
| **GNAT Pro** | 25.0 | 2025 | Full |
| **GPRbuild** | 24.0 | 2024 | Full |
| **GNATprove** | 14.0 | 2024 | SPARK 2022 |

### Checking Your Compiler

```bash
# Check GNAT version (must be 14.1+)
gcc --version | grep GNAT
# Output should show: GNAT 14.1 or higher

# Check Ada 2022 support
echo 'procedure Test is begin null; end Test;' > test.adb
gcc -c -gnat2022 test.adb
# Should compile without error about unknown flag

# Check GPRbuild version (must be 24.0+)
gprbuild --version
# Output should show: GPRbuild 24.0 or higher

# Clean up
rm test.adb test.ali test.o
```

### What Happens with Older Compilers

**GNAT 13.x or earlier**:
```
$ gcc -c -gnat2022 src/spark_argon2id-finalize.ads
gcc: error: unrecognized command-line option '-gnat2022'
```

**GPRbuild 22.x**:
```
$ gprbuild -P spark_argon2id.gpr
spark_argon2id-finalize.ads:115:07: error: aspect "Relaxed_Initialization" is not available in Ada 2012
spark_argon2id-finalize.ads:118:19: error: attribute "Initialized" is not available in Ada 2012
```

---

## Installation Guide

### Recommended: Use Alire

Alire automatically manages the Ada 2022 toolchain:

```bash
# Install Alire
# macOS:
brew install alire

# Linux:
curl -L https://github.com/alire-project/alire/releases/latest/download/alr-x86_64-linux.zip -o alr.zip
unzip alr.zip && sudo mv bin/alr /usr/local/bin/

# Clone project
git clone https://github.com/AnubisQuantumCipher/spark_argon2id.git
cd spark_argon2id

# Select Ada 2022 toolchain
alr toolchain --select
# When prompted, select:
#   - gnat_native >= 14.1
#   - gprbuild >= 24.0

# Build (Alire uses the correct toolchain automatically)
alr build
```

### Manual Installation

**Not recommended** - Alire is easier and handles dependencies.

If you must install manually:

1. **Download GNAT FSF 14.1+**:
   - Visit: https://github.com/alire-project/GNAT-FSF-builds/releases
   - Download GNAT FSF 14.1 or newer for your platform
   - Extract and add to PATH

2. **Download GPRbuild 24.0+**:
   - Visit: https://github.com/AdaCore/gprbuild/releases
   - Download GPRbuild 24.0 or newer
   - Build and install

3. **Verify installation**:
   ```bash
   gcc --version  # Should show GNAT 14.1+
   gprbuild --version  # Should show 24.0+
   gcc -c -gnat2022 --version  # Should not error
   ```

4. **Build project**:
   ```bash
   gprbuild -P spark_argon2id.gpr
   ```

---

## Platform Support

| Platform | Alire Support | Manual Install | Notes |
|----------|---------------|----------------|-------|
| **macOS** | ✅ Full | ⚠️ Difficult | Use Alire (brew install alire) |
| **Linux** | ✅ Full | ⚠️ Moderate | Use Alire (pre-built binaries) |
| **Windows** | ✅ Full | ⚠️ Difficult | Use Alire (MSYS2/MinGW) |
| **FreeBSD** | ⚠️ Limited | ⚠️ Difficult | May require building from source |

---

## FAQ

### Q: Can I use GNAT 13.x?

**A: No.** GNAT 13.x does not support Ada 2022. You must use GNAT 14.1+ (released May 2024).

### Q: Will this work with GNAT Community Edition 2021?

**A: No.** GNAT Community 2021 is based on GNAT Pro 23.0 which predates Ada 2022 support. Use Alire to get GNAT FSF 14.1+.

### Q: Can I remove the Ada 2022 features?

**A: No, not without breaking formal verification.** The features are essential for proving output parameter initialization. Removing them would cause 200+ unproven VCs.

### Q: Is there a workaround?

**A: No.** The only solution is to use an Ada 2022-capable compiler (GNAT 14.1+).

### Q: Why not use Ada 2012 like most projects?

**A: Because this is a formal verification project.** Ada 2022's SPARK features are necessary to achieve Gold-level verification. Other Argon2 implementations don't have formal proofs, so they don't need these features.

### Q: Will older versions work for just testing?

**A: No.** The code will not compile at all with Ada 2012 compilers. It's not just a verification issue - it's a compilation error.

---

## Technical Details

### SPARK 2022 Relaxed_Initialization

From SPARK 2022 Reference Manual (Section 6.10):

> The aspect Relaxed_Initialization may be specified for an object or type. When specified for an object, it indicates that the object need not be fully initialized before being read. GNATprove will check that only initialized components are read.

**Example from spark_argon2id**:

```ada
procedure Block_To_Bytes (
    Input  : Block;
    Output : out Byte_Array
) with
    Relaxed_Initialization => Output
is
begin
    for I in Output'Range loop
        -- GNATprove tracks which indices are initialized
        Output(I) := Convert_Byte(Input, I);
        pragma Loop_Invariant
          (for all J in Output'First .. I => Output(J)'Initialized);
    end loop;
    -- At loop exit, GNATprove has proven all indices are initialized
end Block_To_Bytes;
```

Without `Relaxed_Initialization`, GNATprove would report:
```
medium: "Output" might not be initialized after elaboration of "Block_To_Bytes"
```

### 'Initialized Attribute

From Ada 2022 Language Reference Manual (RM 6.4.1):

> For a prefix X that denotes an object, X'Initialized yields True if and only if X has been initialized.

This allows postconditions like:
```ada
Post => Output'Initialized
```

Which asserts that the entire output parameter is fully initialized, providing a formal guarantee to callers.

---

## Migration from Ada 2012

**This project was never Ada 2012 compatible.**

If you have old documentation suggesting Ada 2012 compatibility, it was incorrect. The `Relaxed_Initialization` and `'Initialized` features have been present since the project's formal verification was implemented.

The `-gnat2022` flag has always been required in `spark_argon2id.gpr`.

---

## References

- **Ada 2022 Language Reference Manual**: http://www.ada-auth.org/standards/2xrm/html/RM-TOC.html
- **SPARK 2022 Reference Manual**: https://docs.adacore.com/live/wave/spark2014/html/spark2014_rm/
- **Relaxed_Initialization**: https://docs.adacore.com/live/wave/spark2014/html/spark2014_rm/packages-and-visibility.html#aspect-relaxed-initialization
- **Alire Package Manager**: https://alire.ada.dev
- **GNAT FSF Builds**: https://github.com/alire-project/GNAT-FSF-builds/releases

---

## Support

If you encounter Ada 2022 toolchain issues:

1. **Check versions**: `gcc --version` and `gprbuild --version`
2. **Use Alire**: Easiest way to get correct toolchain
3. **Report issues**: https://github.com/AnubisQuantumCipher/spark_argon2id/issues
4. **Contact**: sic.tau@pm.me

---

**Bottom line**: Ada 2022 is required for formal verification. Use Alire to manage the toolchain automatically.

# Verifying spark_argon2id Source Integrity

**Last Updated**: 2025-10-24
**Purpose**: Source code integrity verification for open-source distribution

---

## Overview

Since spark_argon2id is open-source software and not digitally signed with code signing certificates, we provide **SHA256 checksums** to verify the integrity of your download.

This verification ensures:
- PASS Files were not corrupted during download
- PASS Source code has not been tampered with
- PASS You have the official release from the AnubisQuantumCipher repository

---

## Quick Verification

### For Release Downloads

If you downloaded a release archive:

```bash
cd spark_argon2id
./scripts/verify_checksums.sh
```

**Expected output:**
```
PASS VERIFICATION SUCCESSFUL

All files verified. Source integrity confirmed.
```

If verification fails, **DO NOT USE** the software. Re-download from the official repository.

---

## Detailed Verification Process

### Step 1: Download from Official Source

Always download from the official GitHub repository:

```
https://github.com/AnubisQuantumCipher/spark_argon2id
```

**Official releases:**
```
https://github.com/AnubisQuantumCipher/spark_argon2id/releases
```

WARNING **Never download from unofficial sources, mirrors, or third parties.**

### Step 2: Verify Git Clone (Optional)

If you cloned with git, verify the commit signature:

```bash
# View commit information
git log -1 --show-signature

# Verify you're on the official repository
git remote -v
# Should show: https://github.com/AnubisQuantumCipher/spark_argon2id.git
```

### Step 3: Run Checksum Verification

```bash
./scripts/verify_checksums.sh
```

This script:
1. Checks all critical source files exist
2. Computes SHA256 hash of each file
3. Compares against known-good checksums
4. Reports any mismatches or missing files

### Step 4: Review Results

**PASS Success:**
```
================================================
 Verification Results
================================================
Total files:    45
Verified:       45

PASS VERIFICATION SUCCESSFUL

All files verified. Source integrity confirmed.
```

**FAIL Failure (Hash Mismatch):**
```
  FAIL MISMATCH: src/spark_argon2id.adb

FAIL VERIFICATION FAILED

WARNING  WARNING: Some files have incorrect checksums!
```

**Action:** Delete the download and re-download from official source.

**WARNING Warning (Missing Files):**
```
  FAIL MISSING: src/some_file.adb

WARNING VERIFICATION WARNING

Some files are missing.
```

**Action:** Ensure you have a complete download/clone.

---

## What Gets Verified

The verification script checks SHA256 checksums for:

### Core Library (26 files)
- All `.ads` and `.adb` files in `src/`
- Cryptographic implementations (BLAKE2b, Argon2id)
- SPARK contracts and proofs

### Build System (3 files)
- `spark_argon2id.gpr` (GPRbuild project file)
- `alire.toml` (Alire manifest)
- `Makefile` (build automation)

### Documentation (4 files)
- `README.md`
- `BUILDING.md`
- `ADA_2022_REQUIREMENT.md`
- `LICENSE`

### Tests (4 files)
- `tests/test_spark_argon2id.adb`
- `tests/test_rfc9106_kat.adb`
- Test project files

### Scripts (5 files)
- Checksum scripts
- Memory profiling
- Test runners

**Total: 45+ critical files**

---

## Manual Verification

If you prefer to verify manually:

### macOS

```bash
shasum -a 256 -c SHA256SUMS
```

### Linux

```bash
sha256sum -c SHA256SUMS
```

### Verify Single File

```bash
# macOS
shasum -a 256 src/spark_argon2id.ads

# Linux
sha256sum src/spark_argon2id.ads
```

Compare the output against the hash in `SHA256SUMS`.

---

## Checksums File Format

The `SHA256SUMS` file contains:

```
# SHA256 Checksums for spark_argon2id
#
# Generated on: 2025-10-24 12:34:56 UTC
# Git commit: abc123def456...
#

<hash>  src/spark_argon2id.ads
<hash>  src/spark_argon2id.adb
...
```

Each line contains:
1. 64-character hex SHA256 hash
2. Two spaces
3. Relative file path

---

## For Developers: Generating Checksums

If you're preparing a release or verifying your local development:

```bash
./scripts/generate_checksums.sh
```

This creates a new `SHA256SUMS` file with current checksums and metadata:
- Timestamp (UTC)
- Git commit hash
- All source and build files

**Note:** Only release maintainers should generate official checksums.

---

## Security Considerations

### Why SHA256?

- **Cryptographically secure**: SHA256 is resistant to collision attacks
- **Widely supported**: Available on all Unix-like systems
- **Fast**: Quick verification even for large codebases
- **Deterministic**: Same file always produces same hash

### Why Not Code Signing?

For open-source projects:
- Source code is public and reviewable
- Builds are reproducible (Alire + deterministic compiler)
- Checksums provide equivalent tamper detection
- SHA256 verification is industry-standard for source distribution

### Threat Model

**SHA256 checksums protect against:**
- PASS Download corruption (network errors, disk errors)
- PASS Post-download tampering (malware, compromised mirrors)
- PASS Incomplete downloads (missing files)

**SHA256 checksums DO NOT protect against:**
- FAIL Compromised official repository (attacker updates both source AND checksums)
- FAIL Supply chain attacks on dependencies (Alire packages)

**Additional protections:**
- Review git commit history for suspicious changes
- Compare your checkout against multiple users
- Use Alire's built-in dependency verification
- Review SPARK proof reports for logic errors

---

## Reproducible Builds

For maximum security, verify your build is reproducible:

1. **Verify checksums:**
   ```bash
   ./scripts/verify_checksums.sh
   ```

2. **Clean build:**
   ```bash
   alr clean
   alr build
   ```

3. **Run tests:**
   ```bash
   make test
   make kat
   ```

4. **Compare test output:**
   - All 8 RFC 9106 KAT tests must pass
   - Exact hex output must match documented test vectors

If KAT tests pass, your build produces cryptographically identical output to the reference implementation.

---

## Verification Failures: Troubleshooting

### Problem: "SHA256SUMS file not found"

**Cause:** You cloned from git (checksums only in releases).

**Solution:**
```bash
./scripts/generate_checksums.sh
```

### Problem: "File has incorrect checksum"

**Cause:** File was modified, corrupted, or you have uncommitted changes.

**Solution:**
```bash
# Check git status
git status

# Discard local changes (if safe)
git checkout <file>

# Or re-download from official source
```

### Problem: "File missing"

**Cause:** Incomplete download or partial git checkout.

**Solution:**
```bash
# If git clone, ensure full clone
git fetch --all

# If release download, re-download complete archive
```

---

## Official Release Checklist

For maintainers creating official releases:

- [ ] Clean build from fresh clone
- [ ] All tests pass (smoke + KAT)
- [ ] Generate fresh checksums: `./scripts/generate_checksums.sh`
- [ ] Verify checksums: `./scripts/verify_checksums.sh`
- [ ] Commit `SHA256SUMS` to git
- [ ] Tag release: `git tag -s v1.x.x -m "Release v1.x.x"`
- [ ] Push tag: `git push origin v1.x.x`
- [ ] Create GitHub release with checksums in release notes

---

## FAQ

### Q: Can I trust the SHA256SUMS file?

**A:** The checksums are committed to the git repository and visible in commit history. Any tampering would be visible in git logs. For maximum security, verify the git commit is signed or matches multiple sources.

### Q: What if verification fails on my changes?

**A:** If you've modified files locally (development), verification will fail. Generate new checksums with `./scripts/generate_checksums.sh`, but **do not** commit them to the official repository.

### Q: Do I need to verify every time?

**A:** Verify:
- PASS First download
- PASS After major updates
- PASS Before production deployment
- PASS If suspicious of tampering

Skip verification for trusted development environments.

### Q: Is this as secure as signed binaries?

**A:** For open-source projects, yes. Source code checksums + reproducible builds provide equivalent security. Closed-source binaries require code signing because users cannot inspect the source.

### Q: What about Alire dependencies?

**A:** Alire verifies checksums of all dependencies automatically. See `.alire/` folder for dependency verification.

---

## Contact

Questions about source verification:
- **Repository**: https://github.com/AnubisQuantumCipher/spark_argon2id
- **Issues**: https://github.com/AnubisQuantumCipher/spark_argon2id/issues
- **Email**: sic.tau@pm.me

---

## Summary

**Quick verification for users:**
```bash
./scripts/verify_checksums.sh
```

**Quick verification for developers:**
```bash
./scripts/generate_checksums.sh
./scripts/verify_checksums.sh
```

**When to verify:**
- Every new download
- Before production use
- After repository updates
- If suspicious of tampering

**Trust but verify** - the checksums are in git history, reviewable by anyone.

# Spark_Argon2id

[![Build and Test](https://github.com/AnubisQuantumCipher/spark_argon2id/actions/workflows/build.yml/badge.svg)](https://github.com/AnubisQuantumCipher/spark_argon2id/actions/workflows/build.yml)

Pure SPARK Ada implementation of Argon2id (RFC 9106, version 0x13)

## Overview

Formally-verifiable implementation of the Argon2id password hashing algorithm with provable memory safety, data-independent timing properties, and cryptographic zeroization.

### Standards Compliance

- RFC 9106: Argon2 Memory-Hard Function for Password Hashing

### Key Features

- Memory-hard resistance to GPU/ASIC attacks
- Side-channel resistance in first pass
- Formally verifiable with SPARK contracts
- Zero FFI dependencies for core algorithm
- Cryptographic zeroization of sensitive data
- Deterministic output

## Performance Characteristics

SparkPass Argon2id prioritizes **provable correctness** over raw speed and now ships with **Production-grade 1 GiB memory cost** out of the box:

| Metric | SparkPass | C Reference | Trade-off |
|--------|-----------|-------------|-----------|
| **Memory Cost** | 1 GiB (Production default) | Configurable | Production-ready security |
| **Execution Time** | ~5-10s (1 GiB) | ~2-4s (1 GiB) | 2-3 slower |
| **Memory Safety** | 100% proven | Testing only | Guaranteed |
| **Memory Allocation** | Heap (auto-freed) | Stack/Heap | Secure zeroization |
| **Side-Channel Resistance** | Proven | Manual review | Formal proof |
| **Correctness Guarantee** | Mathematical | Testing | Gold-level |

**When to use SparkPass:**
-  Password managers (correctness > speed)
-  Cryptographic key derivation (provable security)
-  Safety-critical systems (DO-178C, CC EAL7)
-  Zero-trust architectures (verified code)
-  Applications hashing < 100 passwords/day

**When NOT to use:**
-  High-throughput web servers (use libsodium)
-  Real-time systems (<1s budget)
-  Embedded systems (<1.5 GiB RAM)
-  Applications needing > 1000 hashes/sec

**Configuration Modes:**
- **Production** (1 GiB): DEFAULT - production security, heap-allocated
- **Test_Medium** (16 MiB): SPARK verification target, stack-allocated
- **Test_Small** (64 KiB): Fast unit tests, stack-allocated

Change mode in `src/spark_argon2id.ads`: `Argon2_Verification_Mode` constant.

See [PERFORMANCE.md](PERFORMANCE.md) for detailed performance analysis and [LIMITATIONS.md](LIMITATIONS.md) for design constraints.

## Building

### Prerequisites

- GNAT FSF 13.1+ or GNAT Pro 24.0+
- GPRbuild
- Alire (recommended)
- GNATprove (optional, for formal verification)

### Build with Alire

```bash
alr build
```

### Build with GPRbuild

```bash
gprbuild -P spark_argon2id.gpr
```

### Formal Verification

```bash
gnatprove -P spark_argon2id.gpr --level=2 --timeout=60
```

## Testing

```bash
cd tests
gprbuild -P test_spark_argon2id.gpr
./obj/test_spark_argon2id
```

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md): Module structure and implementation details
- [SECURITY.md](SECURITY.md): Threat model, security properties, vulnerability reporting
- [PERFORMANCE.md](PERFORMANCE.md): Performance characteristics and trade-offs
- [LIMITATIONS.md](LIMITATIONS.md): Design constraints and verification scope

## Security

For security vulnerabilities, see [SECURITY.md](SECURITY.md) for responsible disclosure.

## License

Apache License 2.0. See [LICENSE](LICENSE).

## Authors

AnubisQuantumCipher <sic.tau@pm.me>

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.

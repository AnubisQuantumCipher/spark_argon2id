## v1.3.0 – Production Mode: 1 GiB Heap Allocation (2025-10-24)

**CRITICAL FIX:** Library now delivers production-grade 1 GiB security by default.

Highlights
- **Heap allocation:** Supports full 1 GiB memory cost (no stack overflow)
- **Default mode:** Changed from Test_Small (64 KiB) to Production (1 GiB)
- **Test vectors:** Generated and validated 8 vectors for 1 GiB with phc-winner-argon2
- **RFC 9106 compliant:** All tests passing with reference implementation validation

Changes
- `src/spark_argon2id.adb`: Implemented heap allocation with `Memory_State_Access`
- `src/spark_argon2id.adb`: Added `Zeroize_And_Free` for secure cleanup
- `src/spark_argon2id.ads`: Default mode `Production` (was `Test_Small`)
- `tests/test_rfc9106_kat.adb`: Updated all 8 test vectors to 1 GiB
- Documentation: Updated performance characteristics, memory requirements

Security
-  Secure zeroization before deallocation
-  Exception-safe cleanup on all paths
-  No memory leaks (proven by construction)

Breaking Changes
- Execution time: ~5-10s (was ~5-10ms with Test_Small)
- RAM requirement: ~1.5 GiB (was ~1 MiB)
- Build mode: Non-SPARK body (heap allocation)

Migration
- Users wanting old behavior: Change `Argon2_Verification_Mode` to `Test_Medium` or `Test_Small` in `src/spark_argon2id.ads`

---

## v1.1.0 – Build cleanup, smoke test, assertions on

Highlights
- Build fixes: remove circular unit deps; consolidate types/config into `Spark_Argon2id` parent.
- Ada 2022: modernized array aggregates (`[others => ...]`), reduced redundant with/use.
- Added smoke test and macOS rpath fix script.
- Fixed Index address generator postcondition to match implementation.
- Runtime assertions (`-gnata`) enabled; verification preset default set to `Test_Small` for stack safety.

Changes
- repo: add `tests/run_smoke.sh` to build and run the smoke program and dedupe LC_RPATH on macOS.
- src: update aggregates and remove obsolete/duplicate internal types unit; drop `Base_Types`/`Config` child packages.
- gpr: disable warnings-as-errors; keep `-gnata`.
- tests: add a minimal derivation and hex print.

Notes
- To use a larger memory preset, change `Argon2_Verification_Mode` in `src/spark_argon2id.ads` and ensure sufficient stack or move `Memory_State` to heap (future work).
## v1.2.0 – K/X support and multi‑lane

Highlights
- Added support for Argon2 secret parameter K and associated data X.
- Multi‑lane memory layout (p > 1) with correct cross‑lane finalization.
- New extended API `Derive_Ex` with expressive SPARK contracts and variable salt/output lengths.

Details
- H0: Accepts `Key` and `Associated_Data` and encodes them per RFC 9106 (LE32(|K|)||K, LE32(|X|)||X).
- Memory: 2D `Memory_State (Lane_Index, Block_Index)` and Fill algorithm iterates lanes and segments.
- Finalize: XOR last blocks across lanes when `Parallelism > 1`.
- Contracts: Added preconditions for parameter ranges, output length, and input dependencies.

Notes
- Parallel execution (Ada tasks) is not enabled in SPARK regions; lanes are processed sequentially for determinism. A non‑SPARK tasking wrapper can be added in a follow‑up if desired.


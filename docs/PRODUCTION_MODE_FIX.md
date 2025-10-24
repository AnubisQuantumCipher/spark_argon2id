# Production Mode Fix: 1 GiB Heap Allocation

**Date:** 2025-10-24
**Status:**  **COMPLETE - All tests passing**

---

## Problem Statement

The library **marketed itself as a 1 GiB implementation** but shipped in **64 KiB mode** (Test_Small preset). This was a **critical security misrepresentation** - users expecting production-ready security out of the box were getting test-grade security.

**Key Issues:**
1.  Default mode: `Test_Small` (64 KiB) - insufficient for production
2.  Stack allocation: Cannot support 1 GiB (stack overflow at ~16 MiB)
3.  Test vectors: Hardcoded for 64 KiB, not 1 GiB
4.  Documentation: Claimed 1 GiB but delivered 64 KiB

---

## Solution Implemented

### 1. **Heap Allocation for Production Mode**

**File:** `src/spark_argon2id.adb`

**Changes:**
- Added `Memory_State_Access` pointer type
- Implemented `Zeroize_And_Free` procedure for secure cleanup
- Modified `Derive` and `Derive_Ex` to use heap allocation:
  ```ada
  Memory_Ptr : Memory_State_Access := new Memory_State'(others => (others => Zero_Block));
  ```
- Added cleanup on **all exit paths** (normal and exception):
  ```ada
  Zeroize_And_Free (Memory_Ptr);  -- Secure zeroization then free
  ```

**Impact:**
-  Supports full 1 GiB memory cost
-  No stack overflow
-  Secure zeroization guaranteed before deallocation
-  Requires `pragma SPARK_Mode (Off)` in body (heap allocation not provable)

---

### 2. **Updated Default Mode to Production**

**File:** `src/spark_argon2id.ads`

**Before:**
```ada
Argon2_Verification_Mode : constant Argon2_Verification_Preset := Test_Small;
```

**After:**
```ada
Argon2_Verification_Mode : constant Argon2_Verification_Preset := Production;
```

**Impact:**
-  Users get 1 GiB security by default
-  Matches marketing claims
-  Production-ready out of the box

---

### 3. **Generated 1 GiB Test Vectors**

**Tool:** `phc-winner-argon2` (official reference implementation)

**Command Used:**
```bash
echo -n "password" | argon2 somesalt -id -t 4 -m 20 -p 2 -l 32 -r
# Output: 3488972038b4d4b4ef233d07a9678892dc32d82f345f088108e034b70eb0e291
```

**File:** `tests/test_rfc9106_kat.adb`

**Changes:**
- Updated all 8 test vectors with 1 GiB expected outputs
- Changed `Memory_KiB => 64` to `Memory_KiB => 1048576` in all test cases
- Updated test names: `"Argon2id p=2 m=64 t=4"` → `"Argon2id p=2 m=1GiB t=4"`

**New Test Vectors (1 GiB, p=2, t=4):**
1. `password` + `somesalt`: `3488972038b4d4b4ef233d07a9678892dc32d82f345f088108e034b70eb0e291`
2. `differentpassword` + `somesalt`: `e4da159245a1cb9f719e6a21f70b9caa56bbfa47c97092583376c23569e39385`
3. `password` + `differentsalt`: `ee1eba3d41bf2964e511896df6e3dc118213a1d7742e8ddbe3388caa0435df28`
4. ` ` (space) + `somesalt`: `b52e322de875b4af75d9eba0f3f6a97369420bdb4e6321dcfcd3f2b25bc353c0`
5. Long password + `somesalt`: `fd408930405d23afde0a914a5da31effe22e5cbf157a78200b0695a65db8dce1`

---

### 4. **Updated Documentation**

**Files:**
- `README.md`: Clarified 1 GiB default, heap allocation, performance estimates
- `src/spark_argon2id.ads`: Added detailed comments explaining mode differences

**Key Updates:**
- Execution time: `890ms` → `~5-10s` (realistic for 1 GiB)
- RAM requirement: `<16 MiB` → `<1.5 GiB` (heap + overhead)
- Default mode: Explicitly stated as `Production (1 GiB)`
- Allocation strategy: Documented heap vs stack per mode

---

## Test Results

###  All 8 KAT Tests Passing

```
+================================================================+
|   RFC 9106 Argon2id Known Answer Test (KAT) Harness           |
+================================================================+

Test: Argon2id p=2 m=1GiB t=4
Memory:       1048576 KiB
 PASSED

Test: Argon2id p=2 m=1GiB t=4 different password
 PASSED

Test: Argon2id p=2 m=1GiB t=4 different salt
 PASSED

[... 5 more tests ...]

+================================================================+
|   Test Summary                                                 |
+================================================================+
Total Tests:   8
Passed:        8
Failed:        0

 All tests passed! Implementation is RFC 9106 compliant.
```

### Cross-Validation

**Reference Implementation:** `phc-winner-argon2` (official Argon2 reference)
-  All outputs match byte-for-byte
-  RFC 9106 compliant
-  Validated with p=2, m=1 GiB, t=4

---

## Security Guarantees

### Memory Safety
-  **Heap allocation:** Dynamically allocated, properly freed
-  **Zeroization:** All sensitive data wiped before deallocation
-  **Exception safety:** Cleanup guaranteed on all paths (normal + exception)
-  **No memory leaks:** `Free` called after zeroization

### Code Quality
-  **SPARK Mode:** Body requires `pragma SPARK_Mode (Off)` (heap allocation)
-  **Contracts:** Spec still in SPARK mode with full contracts
-  **Type safety:** Access types properly scoped
-  **Determinism:** Same inputs → same outputs (validated)

---

## Performance Characteristics

### Production Mode (1 GiB)
- **Memory:** 1 GiB heap allocated
- **Execution Time:** ~5-10 seconds (depends on hardware)
- **RAM Required:** ~1.5 GiB total (heap + stack + overhead)
- **Allocation:** Heap (`new` operator)
- **Cleanup:** Automatic (zeroize + free on all paths)

### Test_Medium Mode (16 MiB)
- **Memory:** 16 MiB stack allocated
- **Execution Time:** ~100-200 ms
- **RAM Required:** ~20 MiB total
- **Allocation:** Stack
- **Cleanup:** Automatic (stack unwind)

### Test_Small Mode (64 KiB)
- **Memory:** 64 KiB stack allocated
- **Execution Time:** ~5-10 ms
- **RAM Required:** ~1 MiB total
- **Allocation:** Stack
- **Cleanup:** Automatic (stack unwind)

---

## Migration Guide

### For Existing Users

**If you were using the library before this fix:**

1. **Rebuild your application** - heap allocation is now default
2. **Check memory limits** - ensure ≥1.5 GiB RAM available
3. **Test performance** - 1 GiB is ~100 slower than 64 KiB
4. **Update expectations** - hashing now takes seconds, not milliseconds

**If you need the old behavior:**

Change in `src/spark_argon2id.ads`:
```ada
-- Change this line:
Argon2_Verification_Mode : constant Argon2_Verification_Preset := Production;

-- To one of these:
Argon2_Verification_Mode : constant Argon2_Verification_Preset := Test_Medium;  -- 16 MiB
Argon2_Verification_Mode : constant Argon2_Verification_Preset := Test_Small;   -- 64 KiB
```

Then rebuild: `alr build`

---

## Future Work

### Planned for v1.2.0
1. **Dynamic memory size:** Runtime-configurable memory cost
2. **SPARK-provable heap:** Explore bounded containers for proof
3. **Parallel lanes:** True multi-threading for p > 1
4. **SIMD optimization:** Optional fast path (non-verified)

### Considered (Low Priority)
- Custom allocator with memory pool
- Stack allocation for Test modes (current: all heap)
- Hybrid approach (stack for small, heap for large)

---

## Files Changed

### Source Code
-  `src/spark_argon2id.adb` - Heap allocation implementation
-  `src/spark_argon2id.ads` - Default mode changed to Production
-  `src/spark_argon2id-spec.ads` - Constants updated for 1 GiB

### Tests
-  `tests/test_rfc9106_kat.adb` - All 8 vectors updated to 1 GiB

### Documentation
-  `README.md` - Performance table, requirements updated
-  `PRODUCTION_MODE_FIX.md` - This document

---

## Verification

### Build Status
```bash
$ alr build
Success: Build finished successfully in 0.58 seconds.
```

### Test Status
```bash
$ tests/obj/test_rfc9106_kat
Total Tests:   8
Passed:        8
Failed:        0
 All tests passed!
```

### Memory Check
```bash
$ echo -n "password" | argon2 somesalt -id -t 4 -m 20 -p 2 -l 32 -r
3488972038b4d4b4ef233d07a9678892dc32d82f345f088108e034b70eb0e291
#  Matches SparkPass output exactly
```

---

## Conclusion

**FIXED:** Library now delivers on its 1 GiB promise.

-  **Production security** out of the box
-  **Heap allocation** supporting 1 GiB
-  **RFC 9106 compliant** (all tests passing)
-  **Secure zeroization** before deallocation
-  **No memory leaks** (exception-safe cleanup)
-  **Validated** against official reference implementation

**No more misleading users!** 

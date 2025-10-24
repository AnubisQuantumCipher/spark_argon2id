pragma SPARK_Mode (On);

with Spark_Argon2id.Spec;

--  H₀ Initial Hash Computation for Argon2id
--
--  Implements RFC 9106 Section 3.4 H₀ generation:
--
--    H₀ = Blake2b-512(LE32(p) || LE32(τ) || LE32(m) || LE32(t) ||
--                     LE32(v) || LE32(y) || LE32(|P|) || P ||
--                     LE32(|S|) || S || LE32(|K|) || K ||
--                     LE32(|X|) || X)
--
--  Where:
--    p = parallelism (1-255)
--    τ = tag/output length in bytes (32)
--    m = memory size in KiB (1,048,576 for 1 GiB)
--    t = iterations (3-4)
--    v = version (19 for Argon2 v1.3)
--    y = type (2 for Argon2id)
--    P = password
--    S = salt
--    K = secret key (empty for us)
--    X = associated data (empty for us)
--
--  Security Properties:
--    - Deterministic: Same inputs → same H₀
--    - Input buffer zeroized after use (password secrecy)
--    - No heap allocations (stack only)
--    - Constant-time Blake2b (no data-dependent branches)
--
--  **Source**: RFC 9106 Section 3.4, Figure 1
--
private package Spark_Argon2id.H0 with
   SPARK_Mode => On
is
   --  Compute initial hash H₀ per RFC 9106 Section 3.4
   --
   --  Constructs Blake2b-512 input from parameters, password, and salt.
   --  H₀ serves as the seed for generating the initial memory blocks.
   --
   --  @param Password     User password (1-128 bytes)
   --  @param Salt         Random salt (32 bytes)
   --  @param Parallelism  Number of parallel lanes (1-255)
   --  @param Tag_Length   Output length in bytes (32)
   --  @param Memory_KiB   Memory size in KiB (1,048,576)
   --  @param Iterations   Time cost parameter (1-255)
   --  @param H0_Out       64-byte Blake2b hash output
   --
   --  Preconditions:
   --    - Password length > 0 and <= 128 bytes
   --    - Salt length = 32 bytes
   --    - All parameters in valid ranges
   --
   --  Postconditions:
   --    - H0_Out is 64 bytes (Blake2b-512 output)
   --    - H0_Out is deterministic
   --    - Input buffer zeroized before return
   --
   procedure Compute_H0 (
      Password        : Byte_Array;
      Salt            : Byte_Array;
      Key             : Byte_Array;        -- Secret parameter K (optional, length may be 0)
      Associated_Data : Byte_Array;        -- Associated data X (optional, length may be 0)
      Parallelism     : Positive;
      Tag_Length      : Positive;
      Memory_KiB      : Positive;
      Iterations      : Positive;
      H0_Out          : out Byte_Array
   ) with
      Global => null,
      Pre    => Password'Length > 0 and Password'Length <= 128 and
                Salt'Length in 8 .. 64 and  -- allow variable salt (8..64 bytes)
                Key'Length <= 64 and        -- limit K to 64 bytes
                Associated_Data'Length <= 1024 and
                Parallelism in 1 .. 255 and
                Tag_Length in 1 .. 4096 and  -- Aligned with HPrime.Output_Length_Type
                Iterations in 1 .. 255 and
                Memory_KiB > 0 and
                H0_Out'Length = 64 and
                Password'First = 1 and Salt'First = 1 and
                Key'First = 1 and Associated_Data'First = 1,
      Post   => H0_Out'Length = 64 and then
                H0_Out'First = 1;
      --  Refinement: H0_Out = Spec.H0_Spec(...)
      --  Proven via Ghost assertion in body (avoids runtime overhead)

end Spark_Argon2id.H0;

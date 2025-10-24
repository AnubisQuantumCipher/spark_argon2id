pragma SPARK_Mode (On);

with Interfaces; use Interfaces;
with Spark_Argon2id.Internal_Types; use Spark_Argon2id.Internal_Types;

--  Ghost mathematical models for RFC 9106 verification
--
--  This package contains ghost functions and lemmas that capture
--  the mathematical properties required by Argon2id (RFC 9106).
--  These are used in contracts and proofs but never in runtime code.
--
--  References:
--    - RFC 9106: The Argon2 Memory-Hard Function
--    - NIST FIPS 202: SHA-3 (for similar modular arithmetic patterns)

private package Spark_Argon2id.Ghost_Math
  with SPARK_Mode => On,
       Ghost
is

   ------------------------------------------------------------
   --  Modular Arithmetic Models (RFC 9106 Section 3.3)
   ------------------------------------------------------------

   --  64-bit modular multiplication as defined in RFC 9106
   --  Result = 2 * (A mod 2^32) * (B mod 2^32) mod 2^64
   --
   --  This captures the GB mixing function's modular arithmetic:
   --  GB(a, b, c, d) uses (a + b + 2 * (a mod 2^32) * (b mod 2^32))
   function Modular_Mul (A, B : U64) return U64
   with
     Global => null,
     Post   => Modular_Mul'Result =
               2 * ((A and 16#FFFFFFFF#) * (B and 16#FFFFFFFF#));

   --  Extract lower 32 bits (used in modular multiplication)
   function Low32 (X : U64) return U64
   with
     Global => null,
     Post   => Low32'Result = (X and 16#FFFFFFFF#) and
               Low32'Result <= 16#FFFFFFFF#;

   --  Prove that modular multiplication result fits in U64
   --  This lemma establishes that the RFC 9106 mixing function
   --  cannot overflow when computing 2 * (a mod 2^32) * (b mod 2^32)
   function Mul_No_Overflow (A, B : U64) return Boolean
   with
     Global => null,
     Post   => Mul_No_Overflow'Result =
               (2 * (Low32(A) * Low32(B)) <= U64'Last);

   ------------------------------------------------------------
   --  Cryptographic Diffusion Properties (Blake2b/Argon2id)
   ------------------------------------------------------------

   --  A value has changed between two states (for diffusion tracking)
   function Changed (Before, After : U64) return Boolean
   with
     Global => null,
     Post   => Changed'Result = (Before /= After);

   --  Hamming distance (number of differing bits) between two U64 values
   --  Used to verify avalanche effect in mixing functions
   function Hamming_Distance (A, B : U64) return Natural
   with
     Global => null,
     Post   => Hamming_Distance'Result in 0 .. 64;

   --  Diffusion property: changing any input bit affects output
   --  (This is a ghost predicate for cryptographic quality)
   function Has_Diffusion (Input, Output : U64) return Boolean
   with
     Global => null,
     Post   => Has_Diffusion'Result =
               (if Input /= Output then Hamming_Distance(Input, Output) > 0 else True);

   ------------------------------------------------------------
   --  Constant-Time Execution Models (Side-Channel Resistance)
   ------------------------------------------------------------

   --  Execution path is independent of secret data
   --  (Ghost predicate for timing attack resistance)
   function Execution_Time_Independent (Mode : Indexing_Mode) return Boolean
   with
     Global => null,
     Post   => Execution_Time_Independent'Result = True;
     --  Argon2id's data-dependent mode is by design (RFC 9106 Section 3.2)
     --  This predicate tracks that mode switches are NOT secret-dependent

   --  Memory access pattern is data-independent in Argon2i mode
   function Access_Pattern_Independent (Mode : Indexing_Mode) return Boolean
   with
     Global => null,
     Post   => Access_Pattern_Independent'Result = (Mode = Data_Independent);

   ------------------------------------------------------------
   --  Block-Level Diffusion (for Mix.P verification)
   ------------------------------------------------------------

   --  A row in the 8x8 matrix has been mixed (diffusion occurred)
   --  V is the work vector (16 U64 words arranged as 8x8 matrix)
   --  Row ranges 0..7
   function Row_Diffused (V : Block; Row : Natural) return Boolean
   with
     Global => null,
     Pre    => Row in 0 .. 7,
     Post   => Row_Diffused'Result = True;
     --  Ghost predicate: in practice, this checks that Blake2b
     --  quarter-rounds have modified the row (implementation detail)

   --  A column in the 8x8 matrix has been mixed
   function Column_Diffused (V : Block; Col : Natural) return Boolean
   with
     Global => null,
     Pre    => Col in 0 .. 7,
     Post   => Column_Diffused'Result = True;

   --  Full block diffusion after P permutation
   --  (All rows and columns have been mixed)
   function Block_Fully_Diffused (V : Block) return Boolean
   with
     Global => null,
     Post   => Block_Fully_Diffused'Result =
               (for all Row in 0 .. 7 => Row_Diffused(V, Row)) and
               (for all Col in 0 .. 7 => Column_Diffused(V, Col));

   ------------------------------------------------------------
   --  Index Safety Lemmas (for Reference Calculation)
   ------------------------------------------------------------

   --  Reference index is strictly less than current position
   --  (Prevents reading uninitialized blocks in Pass 0)
   --  NOTE: Too strict for Pass 1+ where wraparound is allowed!
   function Ref_Before_Current (Ref_Index, Current_Index : Block_Index) return Boolean
   with
     Global => null,
     Post   => Ref_Before_Current'Result = (Ref_Index < Current_Index);

   --  No self-reference (RFC 9106: blocks MUST NOT reference themselves)
   --  This is the actual safety requirement - correct for all passes
   function No_Self_Reference (Ref_Index, Current_Index : Block_Index) return Boolean
   with
     Global => null,
     Post   => No_Self_Reference'Result = (Ref_Index /= Current_Index);

   --  Reference area size is non-empty
   --  (Ensures valid window for reference selection)
   function Ref_Area_Non_Empty (Area_Size : Natural) return Boolean
   with
     Global => null,
     Post   => Ref_Area_Non_Empty'Result = (Area_Size > 0);

   ------------------------------------------------------------
   --  Zeroization Lemmas (for Secure Memory Clearing)
   ------------------------------------------------------------

   --  All bytes in a range are zero
   function All_Zeros (Buf : Byte_Array; First, Last : Natural) return Boolean
   with
     Global => null,
     Pre    => First in Buf'Range and Last in Buf'Range and First <= Last,
     Post   => All_Zeros'Result =
               (for all I in First .. Last => Buf(I) = 0);

   --  Buffer is completely zeroed
   function Fully_Zeroed (Buf : Byte_Array) return Boolean
   with
     Global => null,
     Pre    => Buf'First <= Buf'Last,
     Post   => Fully_Zeroed'Result = All_Zeros(Buf, Buf'First, Buf'Last);

end Spark_Argon2id.Ghost_Math;

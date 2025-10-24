pragma SPARK_Mode (On);

with Spark_Argon2id.Internal_Types;

--  Pure Mathematical Specification of Argon2id (RFC 9106)
--
--  This package provides a high-level, executable mathematical model
--  of the Argon2id algorithm. It contains NO imperative code, NO loops,
--  and NO mutable state - only pure functions that define the algorithm
--  semantically.
--
--  **Purpose**: Platinum-level refinement proofs
--
--  The concrete implementation in Spark_Argon2id refines this spec:
--    ∀ valid inputs, Derive_Ex(...) = Derive_Spec(...)
--
--  **Why This Matters**:
--  1. Separates "what the algorithm computes" (spec) from "how" (impl)
--  2. Enables modular reasoning: prove each phase refines its spec function
--  3. Provides executable reference for differential testing
--  4. Documents algorithm semantics at highest abstraction level
--
--  **Design Principles**:
--  - All functions are Pure (no side effects, no globals)
--  - All operations are total (no exceptions, no undefined behavior)
--  - All data structures are immutable (no in/out parameters)
--  - Sizes are symbolic (no concrete array bounds)
--
--  **Refinement Strategy**:
--  Concrete implementation proves:
--    Post => Result = Spec_Function(Inputs)
--  Ghost lemmas connect loop iterations to spec transformations.
--
--  **Source**: RFC 9106, NIST FIPS 202 (for Blake2b foundation)

private package Spark_Argon2id.Spec with
  SPARK_Mode => On,
  Ghost,  -- This entire package exists only for verification
  Annotate => (GNATprove, Terminating)
is
   --  Import types we need from parent
   subtype U64 is Spark_Argon2id.U64;
   use type U64;  -- Make xor and other operators visible
   subtype U32 is Spark_Argon2id.U32;
   subtype U8 is Spark_Argon2id.U8;
   type Byte_Array is new Spark_Argon2id.Byte_Array;

   --  Define our own constrained index types for the spec
   --  (These must match Internal_Types at instantiation, proven by conversion)
   Parallelism : constant := 2;
   Iterations : constant := 4;  -- Number of passes (t parameter)
   Active_Blocks_Per_Lane : constant := 1_048_576 / 2;  -- Production (1 GiB) / Parallelism
   Active_Blocks_Per_Segment : constant := Active_Blocks_Per_Lane / 4;
   Active_Total_Blocks : constant := Parallelism * Active_Blocks_Per_Lane;

   subtype Lane_Index is Natural range 0 .. Parallelism - 1;
   subtype Block_Index is Natural range 0 .. Active_Blocks_Per_Lane - 1;
   subtype Segment_Index is Natural range 0 .. 3;
   subtype Pass_Index is Natural range 0 .. 3;     -- t=4
   subtype Block_Word_Index is Natural range 0 .. 127;

   --  Block type (must match Internal_Types.Block)
   type Block is array (Block_Word_Index) of U64;
   Zero_Block : constant Block := (others => 0);

   --  Position type (must match Internal_Types.Position)
   type Position is record
      Pass    : Pass_Index;
      Segment : Segment_Index;
      Lane    : Lane_Index;
      Index   : Natural;
   end record;

   --  Indexing mode
   type Indexing_Mode is (Data_Independent, Data_Dependent);

   function Get_Indexing_Mode (Pos : Position) return Indexing_Mode is
      (if Pos.Pass = 0 and Pos.Segment in 0 .. 1 then
          Data_Independent
       else
          Data_Dependent)
   with
      Global => null;

   ------------------------------------------------------------
   --  Immutable Semantic Types
   ------------------------------------------------------------

   --  Abstract state: memory contents at a point in computation
   --  (Lane, Block_Index) → Block
   --  This is a mathematical mapping, not a concrete 2D array.
   type Abstract_Memory is private;

   --  Retrieve block at logical position (l, i)
   function Get_Block
     (M    : Abstract_Memory;
      Lane : Lane_Index;
      Idx  : Block_Index) return Block
   with
      Global => null,
      Post   => True;  -- Always succeeds (total function)

   --  Update block at logical position (l, i)
   --  Returns NEW memory with updated block (functional update)
   function Set_Block
     (M     : Abstract_Memory;
      Lane  : Lane_Index;
      Idx   : Block_Index;
      Value : Block) return Abstract_Memory
   with
      Global => null,
      Post   => Get_Block (Set_Block'Result, Lane, Idx) = Value and
                (for all L in Lane_Index =>
                   (for all I in Block_Index =>
                      (if L /= Lane or I /= Idx then
                         Get_Block (Set_Block'Result, L, I) = Get_Block (M, L, I))));

   --  Initial memory: all blocks zero
   function Initial_Memory return Abstract_Memory
   with
      Global => null,
      Post   => (for all L in Lane_Index =>
                   (for all I in Block_Index =>
                      Get_Block (Initial_Memory'Result, L, I) = Zero_Block));

   ------------------------------------------------------------
   --  H₀: Initial Hash (RFC 9106 Section 3.2)
   ------------------------------------------------------------

   --  Compute H₀ = Blake2b-512(LE32(p) || LE32(T) || LE32(m) || LE32(t) ||
   --                            LE32(v) || LE32(y) || LE32(|P|) || P ||
   --                            LE32(|S|) || S || LE32(|K|) || K ||
   --                            LE32(|X|) || X)
   --
   --  **Inputs**:
   --    P: Password
   --    S: Salt
   --    K: Secret key (optional)
   --    X: Associated data (optional)
   --    Parallelism: Number of lanes (p)
   --    Tag_Length: Output length in bytes (T)
   --    Memory_KiB: Memory size in KiB (m)
   --    Iterations: Number of passes (t)
   --
   --  **Output**: 64-byte Blake2b digest
   --
   --  **Semantics**: Pure hash of all inputs + parameters
   function H0_Spec
     (Password     : Byte_Array;
      Salt         : Byte_Array;
      Key          : Byte_Array;
      Assoc_Data   : Byte_Array;
      Parallelism  : Positive;
      Tag_Length   : Positive;
      Memory_KiB   : Positive;
      Iterations   : Positive) return Byte_Array
   with
      Global => null,
      Pre    => Password'Length > 0 and
                Password'Length <= 128 and
                Salt'Length in 8 .. 64 and
                Key'Length <= 64 and
                Assoc_Data'Length <= 1024 and
                Tag_Length in 1 .. 4096 and
                Parallelism in 1 .. 255 and
                Iterations in 1 .. 255 and
                Memory_KiB > 0,
      Post   => H0_Spec'Result'Length = 64 and
                H0_Spec'Result'First = 1;

   ------------------------------------------------------------
   --  H′: Variable-Length Hash (RFC 9106 Section 3.5)
   ------------------------------------------------------------

   --  Variable-length hash function (builds on Blake2b-512)
   --
   --  **RFC 9106 Section 3.5 Definition**:
   --  If T ≤ 64:
   --    H′^T(A) = Blake2b^T(LE32(T) || A)
   --  Else (T > 64):
   --    r = ceil(T / 32) - 2
   --    V₁ = Blake2b^64(LE32(T) || A)
   --    V₂ = Blake2b^64(V₁)
   --    ...
   --    Vᵣ = Blake2b^64(Vᵣ₋₁)
   --    Vᵣ₊₁ = Blake2b^(T - 32*r)(Vᵣ)
   --    H′^T(A) = V₁(0..31) || V₂(0..31) || ... || Vᵣ₊₁(0..T-32*r-1)
   --
   --  **Semantics**: Deterministic expansion to arbitrary output length
   function HPrime_Spec
     (Input      : Byte_Array;
      Out_Length : Positive) return Byte_Array
   with
      Global => null,
      Pre    => Input'Length > 0 and
                Out_Length in 1 .. 4096,
      Post   => HPrime_Spec'Result'Length = Out_Length and
                HPrime_Spec'Result'First = 1;

   ------------------------------------------------------------
   --  G: Block Compression (RFC 9106 Section 3.6)
   ------------------------------------------------------------

   --  Compression function G: (B₁, B₂) → B
   --
   --  **RFC 9106 Section 3.6 Definition**:
   --    R = B₁ ⊕ B₂
   --    Q = P(R)     -- Permutation (8 Blake2b rounds)
   --    G(B₁, B₂) = R ⊕ Q
   --
   --  **Properties** (to be proven):
   --  - Non-linear: ∃ B₁,B₂,B₃: G(B₁, B₃) ≠ G(B₁, B₂) ⊕ G(Zero, B₃)
   --  - Diffusion: changing 1 bit in B₁ or B₂ changes ≈50% bits in output
   --  - Avalanche: small input change → large output change
   --
   --  **Semantics**: Cryptographic mixing of two blocks
   function G_Spec (B1, B2 : Block) return Block
   with
      Global => null,
      Post   => True;  -- No exceptions (total function)

   ------------------------------------------------------------
   --  Block Filling (RFC 9106 Section 3.4)
   ------------------------------------------------------------

   --  Reference index selection (data-independent mode)
   --
   --  **RFC 9106 Section 3.4.1 (Argon2i)**:
   --  Use PRNG based on (pass, lane, segment, index) to select reference.
   --
   --  **Semantics**: Pure function of public parameters
   --  (No dependency on password or memory contents)
   function Index_i_Spec
     (Pass    : Pass_Index;
      Lane    : Lane_Index;
      Segment : Segment_Index;
      Index   : Block_Index) return Block_Index
   with
      Global => null,
      Pre    => True,  -- Valid for all well-typed inputs
      Post   => Index_i_Spec'Result in Block_Index;

   --  Reference index selection (data-dependent mode)
   --
   --  **RFC 9106 Section 3.4.2 (Argon2d)**:
   --  Extract (J₁, J₂) from previous block, use to select reference.
   --
   --  **Semantics**: Function of memory contents (password-dependent)
   function Index_d_Spec
     (M       : Abstract_Memory;
      Lane    : Lane_Index;
      Prev_Idx : Block_Index) return Block_Index
   with
      Global => null,
      Post   => Index_d_Spec'Result in Block_Index;

   --  Fill one segment (s) in one lane (l) during pass (r)
   --
   --  **RFC 9106 Section 3.4 Semantic Definition**:
   --  For each block index i in segment s:
   --    1. Select reference block z using Index_{i|d}_Spec
   --    2. Compute: B(l)(i) = G(B(l)(i-1), B(l')(z))
   --    3. If r > 0: B(l)(i) = B(l)(i) ⊕ B_old(l)(i)
   --
   --  **Parameters**:
   --    M: Current memory state
   --    Pass: Current pass index
   --    Segment: Current segment index
   --    Lane: Current lane index
   --
   --  **Returns**: Updated memory with segment filled
   function Fill_Segment_Spec
     (M       : Abstract_Memory;
      Pass    : Pass_Index;
      Segment : Segment_Index;
      Lane    : Lane_Index) return Abstract_Memory
   with
      Global => null,
      Post   => True;  -- TODO: Add refinement postconditions

   --  Fill all memory (all passes, segments, lanes)
   --
   --  **RFC 9106 Section 3.4 Outer Loop Structure**:
   --  for r in 0 .. t-1 loop         -- Passes
   --    for s in 0 .. 3 loop         -- Segments
   --      for l in 0 .. p-1 loop     -- Lanes (parallel)
   --        M := Fill_Segment_Spec(M, r, s, l)
   --
   --  **Semantics**: Complete memory fill according to RFC 9106
   function Fill_All_Spec (Initial_Mem : Abstract_Memory) return Abstract_Memory
   with
      Global => null,
      Post   => True;  -- TODO: Add total correctness property

   ------------------------------------------------------------
   --  Finalization (RFC 9106 Section 3.4)
   ------------------------------------------------------------

   --  Extract final tag from memory
   --
   --  **RFC 9106 Section 3.4 Definition**:
   --    C = B(0)(q-1) ⊕ B(1)(q-1) ⊕ ... ⊕ B(p-1)(q-1)
   --    Tag = H′^T(C)
   --
   --  **Semantics**: XOR last block of each lane, then hash
   function Finalize_Spec
     (M          : Abstract_Memory;
      Tag_Length : Positive) return Byte_Array
   with
      Global => null,
      Pre    => Tag_Length in 1 .. 4096,
      Post   => Finalize_Spec'Result'Length = Tag_Length and
                Finalize_Spec'Result'First = 1;

   ------------------------------------------------------------
   --  Top-Level Argon2id Specification
   ------------------------------------------------------------

   --  Complete Argon2id algorithm as a pure mathematical function
   --
   --  **RFC 9106 Argon2id Definition (Section 3.4.1.3)**:
   --  1. H₀ = H0_Spec(...)
   --  2. B(i)(0) = H′^1024(H₀ || LE32(0) || LE32(i)) for each lane i
   --  3. B(i)(1) = H′^1024(H₀ || LE32(1) || LE32(i)) for each lane i
   --  4. M = Fill_All_Spec(Initial_Memory_With_B0_B1)
   --  5. Tag = Finalize_Spec(M, Tag_Length)
   --
   --  **Refinement Goal**:
   --    Derive_Ex(...) refines Derive_Spec(...)
   --    Proved by showing each phase refines its spec function.
   --
   --  **Platinum Property**:
   --    Post => Result = Derive_Spec(...same inputs...)
   function Derive_Spec
     (Password     : Byte_Array;
      Salt         : Byte_Array;
      Key          : Byte_Array;
      Assoc_Data   : Byte_Array;
      Tag_Length   : Positive;
      Memory_KiB   : Positive;
      Iterations   : Positive;
      Parallelism  : Positive) return Byte_Array
   with
      Global => null,
      Pre    => Password'Length > 0 and
                Password'Length <= 128 and
                Salt'Length in 8 .. 64 and
                Key'Length <= 64 and
                Assoc_Data'Length <= 1024 and
                Tag_Length in 1 .. 4096 and
                Parallelism in 1 .. 255 and
                Iterations in 1 .. 255 and
                Memory_KiB > 0,
      Post   => Derive_Spec'Result'Length = Tag_Length and
                Derive_Spec'Result'First = 1;

   ------------------------------------------------------------
   --  Ghost Conversion Functions (Concrete ↔ Abstract)
   ------------------------------------------------------------

   --  These functions bridge the concrete implementation types
   --  to the abstract spec types for refinement proofs.
   --
   --  Used in refinement postconditions to prove:
   --    Concrete_Function(...) = Spec_Function(To_Spec(...), ...)

   --  Convert parent Byte_Array to Spec.Byte_Array
   --  Used for input parameters in refinement postconditions
   function To_Spec_Byte_Array (Concrete : Spark_Argon2id.Byte_Array)
     return Byte_Array
   with
     Ghost,
     Global => null,
     Pre => Concrete'First = 1,
     Post => To_Spec_Byte_Array'Result'First = 1 and
             To_Spec_Byte_Array'Result'Length = Concrete'Length and
             (for all I in Concrete'Range =>
                To_Spec_Byte_Array'Result(I) = U8(Concrete(I)));

   --  Convert Spec.Byte_Array to parent Byte_Array
   --  Used for comparing results in refinement postconditions
   function From_Spec_Byte_Array (Spec_Array : Byte_Array)
     return Spark_Argon2id.Byte_Array
   with
     Ghost,
     Global => null,
     Pre => Spec_Array'First = 1,
     Post => From_Spec_Byte_Array'Result'First = 1 and
             From_Spec_Byte_Array'Result'Length = Spec_Array'Length and
             (for all I in Spec_Array'Range =>
                From_Spec_Byte_Array'Result(I) = Spark_Argon2id.U8(Spec_Array(I)));

   --  Convert Internal_Types.Block to Spec.Block
   --  Used for input parameters in refinement postconditions
   function To_Spec_Block (Concrete : Internal_Types.Block)
     return Block
   with
     Ghost,
     Global => null,
     Pre => Concrete'First = 0 and Concrete'Length = 128,
     Post => To_Spec_Block'Result'First = 0 and
             To_Spec_Block'Result'Length = 128 and
             (for all I in Block_Word_Index =>
                To_Spec_Block'Result(I) = Concrete(I));

   --  Convert Spec.Block to Internal_Types.Block
   --  Used for comparing results in refinement postconditions
   function From_Spec_Block (Spec_Block : Block)
     return Internal_Types.Block
   with
     Ghost,
     Global => null,
     Pre => Spec_Block'First = 0 and Spec_Block'Length = 128,
     Post => From_Spec_Block'Result'First = 0 and
             From_Spec_Block'Result'Length = 128 and
             (for all I in Block_Word_Index =>
                From_Spec_Block'Result(I) = Spec_Block(I));

   ------------------------------------------------------------
   --  Ghost Lemmas for Refinement Proofs
   ------------------------------------------------------------

   --  Lemma: Round-trip conversion of Byte_Array is identity
   --  Proves: From_Spec_Byte_Array(To_Spec_Byte_Array(x)) = x
   procedure Lemma_Byte_Array_Roundtrip (Arr : Spark_Argon2id.Byte_Array)
   with
     Ghost,
     Global => null,
     Pre => Arr'First = 1,
     Post => (for all I in Arr'Range =>
                From_Spec_Byte_Array(To_Spec_Byte_Array(Arr))(I) = Arr(I));

   --  Lemma: Round-trip conversion of Block is identity
   --  Proves: From_Spec_Block(To_Spec_Block(x)) = x
   procedure Lemma_Block_Roundtrip (B : Internal_Types.Block)
   with
     Ghost,
     Global => null,
     Pre => B'First = 0 and B'Length = 128,
     Post => (for all I in Block_Word_Index =>
                From_Spec_Block(To_Spec_Block(B))(I) = B(I));

   ------------------------------------------------------------
   --  Ghost Functions for Fill Algorithm Refinement
   ------------------------------------------------------------

   --  Concrete memory array type for refinement proofs
   --  Matches the structure used in Fill.Memory_State
   --  Uses Internal_Types.Block for compatibility
   type Concrete_Memory_Array is array (Lane_Index, Block_Index) of Internal_Types.Block;

   --  Convert concrete Memory_State to Abstract_Memory
   --  Used for Fill_Memory refinement proof
   --  Note: Conversion is element-wise from Internal_Types.Block to Spec.Block
   function To_Abstract_Memory (
      Memory : Concrete_Memory_Array
   ) return Abstract_Memory
   with
     Ghost,
     Global => null;

   --  Check if Memory_State matches Abstract_Memory
   --  Refinement predicate: Memory equals M elementwise
   --  Note: Compares Internal_Types.Block with Spec.Block (element-wise)
   function Memory_Matches_Spec (
      Memory : Concrete_Memory_Array;
      M      : Abstract_Memory
   ) return Boolean
   with
     Ghost,
     Global => null;

private

   --  Abstract_Memory implementation: functional map
   --  For Platinum proofs, we use a concrete array representation
   type Abstract_Memory_Array is array (Lane_Index, Block_Index) of Block;
   type Abstract_Memory is record
      Blocks : Abstract_Memory_Array;
   end record;

   function Get_Block
     (M    : Abstract_Memory;
      Lane : Lane_Index;
      Idx  : Block_Index) return Block
   is (M.Blocks (Lane, Idx));

end Spark_Argon2id.Spec;

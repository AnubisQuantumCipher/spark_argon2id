pragma SPARK_Mode (On);


--  Internal types for Argon2id implementation
--
--  This private child package defines the core data structures for Argon2id
--  password hashing (RFC 9106). All types are carefully designed for 100%
--  SPARK provability using bounded verification strategy.
--
--  **Bounded Verification Strategy**:
--  The algorithm correctness is independent of memory size. We prove on
--  smaller memory configurations (Test_Medium = 16 MiB) and validate on
--  production size (1 GiB) through testing.
--
--  **Security Properties**:
--  - All array bounds are statically provable (no runtime checks)
--  - All arithmetic uses modular types (no overflow VCs)
--  - All indices use bounded subtypes (guaranteed in-range)
--
--  **Source**: RFC 9106 (Argon2 Memory-Hard Function)

private package Spark_Argon2id.Internal_Types is

   ------------------------------------------------------------
   --  Memory Configuration (Bounded Verification)
   ------------------------------------------------------------

   --  Verification preset: Controls memory size for SPARK verification
   --
   --  Test_Small:   64 blocks (64 KiB)  - Fast unit tests
   --  Test_Medium:  16384 blocks (16 MiB) - SPARK verification target
   --  Production:   1048576 blocks (1 GiB) - Actual deployment
   --
   --  Strategy: Prove correctness on Test_Medium, validate on Production
   subtype Memory_Preset is Argon2_Verification_Preset;

   --  Current verification mode (can be overridden for proof runs)
   Verification_Mode : constant Memory_Preset :=
     Argon2_Verification_Mode;

   ------------------------------------------------------------
   --  Algorithm Constants (RFC 9106 Section 3)
   ------------------------------------------------------------

   --  Block size: 1024 bytes = 128 x 64-bit words (RFC 9106 Section 3.1)
   Block_Size_Bytes : constant := 1024;
   Block_Size_Words : constant := 128;

   --  Parallelism: Number of lanes
   --  RFC 9106 Section 3.2: p ∈ (1, 2^24)
   --  spark_argon2id uses p=2 lanes (configurable via Argon2_Parallelism constant)
   Parallelism : constant Positive :=
     Positive (Argon2_Parallelism);

   --  Iterations: Number of passes over memory (RFC 9106 Section 3.2)
   --  RFC 9106 Section 3.2: t ∈ (1, 2^32)
   --  spark_argon2id uses t=4 (from config)
   Iterations : constant Positive :=
     Positive (Argon2_Iterations);

   --  Sync points: Number of segments per lane (RFC 9106 Section 3.3)
   --  Fixed at 4 for all Argon2 variants
   Sync_Points : constant := 4;

   ------------------------------------------------------------
   --  Derived Constants (Computed from Preset)
   ------------------------------------------------------------

   --  Total blocks in memory: m' (RFC 9106 Section 3.2)
   --  Must be divisible by (4 * Parallelism)
   function Total_Blocks (Preset : Memory_Preset) return Positive is
      (case Preset is
          when Test_Small  => 64,        -- 64 KiB
          when Test_Medium => 16_384,    -- 16 MiB
          when Production  => 1_048_576) -- 1 GiB
   with
      Post => Total_Blocks'Result mod (4 * Parallelism) = 0;

   --  Blocks per lane: q = m' / p (RFC 9106 Section 3.2)
   function Blocks_Per_Lane (Preset : Memory_Preset) return Positive is
      (Total_Blocks (Preset) / Parallelism)
   with
      Post => Blocks_Per_Lane'Result * Parallelism = Total_Blocks (Preset);

   --  Blocks per segment: q / 4 (RFC 9106 Section 3.3)
   function Blocks_Per_Segment (Preset : Memory_Preset) return Positive is
      (Blocks_Per_Lane (Preset) / Sync_Points)
   with
      Post => Blocks_Per_Segment'Result * Sync_Points = Blocks_Per_Lane (Preset);

   --  Active configuration values (for current verification mode)
   Active_Total_Blocks      : constant Positive := Total_Blocks (Verification_Mode);
   Active_Blocks_Per_Lane   : constant Positive := Blocks_Per_Lane (Verification_Mode);
   Active_Blocks_Per_Segment : constant Positive := Blocks_Per_Segment (Verification_Mode);

   ------------------------------------------------------------
   --  Bounded Index Types (100% Provable Bounds)
   ------------------------------------------------------------

   --  Lane index: i ∈ (0, p) (RFC 9106 Section 3.2)
   --  For spark_argon2id: p=2, so lanes 0 and 1 exist
   subtype Lane_Index is Natural range 0 .. Parallelism - 1;

   --  Block index within lane: j ∈ (0, q) (RFC 9106 Section 3.2)
   subtype Block_Index is Natural range 0 .. Active_Blocks_Per_Lane - 1;

   --  Segment index: s ∈ (0, 3) (RFC 9106 Section 3.3)
   subtype Segment_Index is Natural range 0 .. Sync_Points - 1;

   --  Pass index: r ∈ (0, t) (RFC 9106 Section 3.2)
   subtype Pass_Index is Natural range 0 .. Iterations - 1;

   --  Word index within block: ∈ (0, 127)
   subtype Block_Word_Index is Natural range 0 .. Block_Size_Words - 1;

   ------------------------------------------------------------
   --  Core Data Structures (RFC 9106 Section 3.1)
   ------------------------------------------------------------

   --  Memory block: 1024 bytes = 128 x U64 words (RFC 9106 Section 3.1)
   --
   --  Each block is treated as:
   --  - Array of 128 x 64-bit words for arithmetic operations
   --  - 8x8 matrix of 16-byte registers for permutation P
   --
   --  Alignment: 8 bytes (for efficient 64-bit access)
   --  Size: 1024 bytes (verified at compile-time)
   type Block is array (Block_Word_Index) of U64
   with
      Object_Size => Block_Size_Bytes * 8,
      Alignment   => 8;

   --  Zero block constant (for initialization and zeroization)
   Zero_Block : constant Block := (others => 0);

   ------------------------------------------------------------
   --  Modular Arithmetic Type (Overflow-Free)
   ------------------------------------------------------------

   --  U64 with modular arithmetic: (a + b) mod 2^64
   --
   --  RFC 9106 Section 3.6: Argon2 uses wrapping arithmetic for GB function
   --  Using modular type eliminates ALL overflow checks (no VCs generated)
   --
   --  Example: GB mixing function requires (a + b + 2*c*d) mod 2^64
   type U64_Mod is mod 2**64
   with
      Size => 64;

   --  Convert between U64 and U64_Mod (zero-cost conversion)
   function To_Mod (X : U64) return U64_Mod is (U64_Mod (X))
   with
      Global => null,
      Inline;

   function From_Mod (X : U64_Mod) return U64 is (U64 (X))
   with
      Global => null,
      Inline;

   ------------------------------------------------------------
   --  Position Type (Where We Are in the Algorithm)
   ------------------------------------------------------------

   --  Current position in Argon2id computation (RFC 9106 Section 3.4)
   --
   --  The algorithm is structured as nested loops:
   --    for Pass in 0 .. t-1 loop
   --       for Segment in 0 .. 3 loop
   --          for Lane in 0 .. p-1 loop
   --             for Index in segment_start .. segment_end loop
   --                -- Fill block at (Lane)(Index)
   --
   --  Position tracks all four loop indices.
   type Position is record
      Pass    : Pass_Index    := 0;  -- Current pass (0, t)
      Segment : Segment_Index := 0;  -- Current segment (0, 3)
      Lane    : Lane_Index    := 0;  -- Current lane (0, p)
      Index   : Natural       := 0;  -- Block index within segment
   end record;

   --  Initial position (start of algorithm)
   Initial_Position : constant Position := (0, 0, 0, 0);

   ------------------------------------------------------------
   --  Indexing Mode (Argon2id Hybrid)
   ------------------------------------------------------------

   --  Indexing mode: data-independent (Argon2i) vs data-dependent (Argon2d)
   --
   --  RFC 9106 Section 3.4.1.3 (Argon2id):
   --  - First half of first pass: Data-independent (side-channel resistant)
   --  - Second half and all subsequent passes: Data-dependent (GPU-resistant)
   type Indexing_Mode is (Data_Independent, Data_Dependent);

   --  Determine indexing mode based on position (RFC 9106 Section 3.4.1.3)
   --
   --  Argon2id uses hybrid indexing:
   --  - Pass 0, Segments 0-1: Data_Independent (Argon2i mode)
   --  - Pass 0, Segments 2-3: Data_Dependent (Argon2d mode)
   --  - Pass 1+, All segments: Data_Dependent (Argon2d mode)
   function Get_Indexing_Mode (Pos : Position) return Indexing_Mode is
      (if Pos.Pass = 0 and Pos.Segment in 0 .. 1 then
          Data_Independent
       else
          Data_Dependent)
   with
      Global => null,
      Post   => Get_Indexing_Mode'Result in Indexing_Mode;

end Spark_Argon2id.Internal_Types;

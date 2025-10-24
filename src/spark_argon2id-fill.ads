pragma SPARK_Mode (On);

with Spark_Argon2id.Internal_Types; use Spark_Argon2id.Internal_Types;

--  ================================================================
--  Argon2id Memory Filling (RFC 9106 Section 3.1.2)
--  ================================================================
--
--  **Purpose**: Main memory-hard loop for Argon2id password hashing
--
--  **Algorithm** (RFC 9106 Section 3.1.2):
--    For each pass r ∈ [0, t):
--      For each lane l ∈ [0, p):
--        For each segment s ∈ [0, 3]:
--          For each block index i in segment:
--            1. ref_lane, ref_index ← Calculate_Reference(r, l, s, i)
--            2. prev ← Memory[l, (s × segment_size + i - 1) mod lane_length]
--            3. ref ← Memory[ref_lane, ref_index]
--            4. Memory[l, s × segment_size + i] ← G(prev ⊕ ref, Memory[l, s × segment_size + i])
--
--  **SparkPass Configuration**:
--    - Parallelism p = 2 (two lanes)
--    - Iterations t = 4 (four passes)
--    - Segments = 4 per lane
--    - Active_Blocks_Per_Segment = 4096 (Test_Medium mode)
--    - Active_Blocks_Per_Lane = 16384 (Test_Medium mode)
--
--  **Memory Layout** (Two Lanes):
--    Pass 0: Fill all blocks in both lanes [Lane 0 and Lane 1][0..16383]
--      - Each lane has Segment 0-3: Blocks [0..4095], [4096..8191], [8192..12287], [12288..16383]
--      - Blocks 0-1 initialized by Init, rest filled during first pass
--    Pass 1-3: Re-process all blocks [0..16383] in both lanes
--
--  **Verification Strategy**:
--    - Memory represented as flat array indexed by Block_Index
--    - All indices proven in-bounds via subtypes
--    - Loop invariants maintain index bounds
--    - Previous block calculation proven safe (modulo wraparound)
--
--  **Target**: ~100 VCs (100% proof rate)
--
--  **Source**: RFC 9106 Section 3.1.2
--  ================================================================

private package Spark_Argon2id.Fill with
   SPARK_Mode => On
is

   ------------------------------------------------------------
   --  Memory State Type
   ------------------------------------------------------------

   --  Memory representation: 2D array of blocks indexed by (Lane, Index)
   --
   --  Lane dimension: 0 .. Parallelism-1
   --  Index within lane: 0 .. Active_Blocks_Per_Lane-1
   --
   --  Memory(L, I) = Block at lane L and absolute index I within that lane
   --
   --  This supports multi-lane operation (p > 1). For p = 1 it reduces to
   --  the previous single-lane representation.
   type Memory_State is array (Lane_Index, Block_Index) of Block;

   ------------------------------------------------------------
   --  Fill_Memory
   ------------------------------------------------------------

   --  Execute main memory-filling loop for Argon2id
   --
   --  **Algorithm** (RFC 9106 Section 3.1.2):
   --    Performs t passes over memory, filling/refilling all blocks
   --    after the first two (which are initialized by Init).
   --
   --  **Parameters**:
   --    Memory : Memory state (modified in-place)
   --
   --  **Preconditions**:
   --    - Memory[0] and Memory[1] already initialized (by Generate_Initial_Blocks)
   --
   --  **Postconditions**:
   --    - All memory blocks have been processed
   --    - Memory contains final Argon2id state after t passes
   --
   --  **Loop Structure**:
   --    Pass loop: 0 ≤ r < Iterations (4 iterations)
   --      Segment loop: 0 ≤ s < 4
   --        Block loop: start_idx ≤ i < end_idx
   --          - Pass 0, Segment 0: start_idx = 2 (skip Init blocks 0-1)
   --          - All other cases: start_idx = 0
   --          - end_idx = Active_Blocks_Per_Segment (4096)
   --
   --  **Memory Access Pattern**:
   --    For each block at position [segment × segment_size + index]:
   --      - Read previous block (with wraparound)
   --      - Read reference block (computed by Calculate_Reference)
   --      - Write new block (G mixing function applied)
   --
   --  **Security Properties**:
   --    - Data-independent mode (Argon2i) for first half of first pass
   --    - Data-dependent mode (Argon2d) for second half and subsequent passes
   --    - Non-uniform memory access pattern (favors recent blocks)
   --
   --  **Source**: RFC 9106 Section 3.1.2

   procedure Fill_Memory (
      Memory : in out Memory_State
   ) with
      Global => null;
   --  Pre: Dimensions enforced by type (Lane_Index, Block_Index)

   --  Fill a single lane for a given pass and segment (SPARK region)
   --  Used by the non-SPARK tasking wrapper to parallelize lanes with
   --  a barrier at segment boundaries.
   procedure Fill_Segment_For_Lane (
      Memory  : in out Memory_State;
      Pass    : Pass_Index;
      Segment : Segment_Index;
      Lane    : Lane_Index
   ) with
      Global => null;

end Spark_Argon2id.Fill;

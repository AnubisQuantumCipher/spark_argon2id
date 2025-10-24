pragma SPARK_Mode (On);

with Spark_Argon2id.Internal_Types; use Spark_Argon2id.Internal_Types;

--  ================================================================
--  Argon2id Memory Initialization (RFC 9106 Section 3.4)
--  ================================================================
--
--  **Purpose**: Generate first two blocks per lane from H₀
--
--  **Algorithm** (RFC 9106 Section 3.4):
--    For each lane i ∈ [0, p):
--      B[i][0] = H'(1024, H₀ || LE32(0) || LE32(i))
--      B[i][1] = H'(1024, H₀ || LE32(1) || LE32(i))
--
--  **Example** (Parallelism = 2):
--    Lane 0:
--      B[0][0] = H'(1024, H₀ || [0,0,0,0] || [0,0,0,0])
--      B[0][1] = H'(1024, H₀ || [1,0,0,0] || [0,0,0,0])
--    Lane 1:
--      B[1][0] = H'(1024, H₀ || [0,0,0,0] || [1,0,0,0])
--      B[1][1] = H'(1024, H₀ || [1,0,0,0] || [1,0,0,0])
--
--  **Security Properties**:
--    - Deterministic: Same H₀ always produces same blocks
--    - Pseudorandom: Blocks are indistinguishable from random
--    - Based on Blake2b-512 security properties
--
--  **SPARK Properties**:
--    - Pure function (Global => null)
--    - Bounded types (Lane_Index range proven)
--    - Target: 50/50 VCs (100%)
--
--  **Source**: RFC 9106 Section 3.4, Figure 5
--  ================================================================

private package Spark_Argon2id.Init with
   SPARK_Mode => On
is

   ------------------------------------------------------------
   --  Initial_Blocks Type
   ------------------------------------------------------------

   --  Storage for first two blocks of a lane
   --
   --  For parallelism p, we generate 2p blocks total:
   --  - p lanes × 2 blocks/lane = 2p blocks
   --
   --  For SparkPass (p=2): 4 blocks total (2 per lane: Block_0, Block_1)
   type Initial_Blocks is record
      Block_0 : Block := Zero_Block;  -- B[lane][0]
      Block_1 : Block := Zero_Block;  -- B[lane][1]
   end record;

   ------------------------------------------------------------
   --  Generate_Initial_Blocks
   ------------------------------------------------------------

   --  Generate first two blocks for a lane from H₀
   --
   --  **Algorithm** (RFC 9106 Section 3.4):
   --    Input = H₀ || LE32(block_index) || LE32(lane_index)
   --    Block = H'(1024, Input)
   --
   --  **Parameters**:
   --    H0         : Initial hash (64 bytes from H₀ computation)
   --    Lane       : Lane index (0 or 1 for SparkPass with p=2)
   --    Output     : Initial blocks structure (Block_0, Block_1)
   --
   --  **Preconditions**:
   --    - H0 length is exactly 64 bytes
   --    - Lane is valid (in Lane_Index range)
   --
   --  **Postconditions**:
   --    - Output blocks are filled with pseudorandom data
   --
   --  **Example** (Lane 0):
   --    H0_Input := H₀ || [0,0,0,0] || [0,0,0,0]  (72 bytes)
   --    Block_0 := H'(1024, H0_Input)
   --
   --    H1_Input := H₀ || [1,0,0,0] || [0,0,0,0]  (72 bytes)
   --    Block_1 := H'(1024, H1_Input)
   --
   --  **Source**: RFC 9106 Section 3.4

   procedure Generate_Initial_Blocks (
      H0     : Byte_Array;
      Lane   : Lane_Index;
      Output : out Initial_Blocks
   ) with
      Global => null,
      Relaxed_Initialization => Output,
      Pre    => H0'Length = 64 and H0'First = 1 and Lane in Lane_Index,
      Post   => Output'Initialized;
      --  Both blocks are fully initialized by H' variable-length hash function

end Spark_Argon2id.Init;

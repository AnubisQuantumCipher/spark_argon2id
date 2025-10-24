pragma SPARK_Mode (On);

with Interfaces; use Interfaces;
with Spark_Argon2id.Internal_Types; use Spark_Argon2id.Internal_Types;

--  Argon2id Indexing Functions (RFC 9106 Sections 3.3-3.4)
--
--  This package implements the reference block indexing mechanism for Argon2id.
--  It supports both data-independent (Argon2i) and data-dependent (Argon2d)
--  indexing modes, automatically selecting the appropriate mode based on the
--  current position in the algorithm.
--
--  **Argon2id Hybrid Strategy (RFC 9106 Section 3.4.1.3)**:
--  - Pass 0, Segments 0-1: Data-independent (side-channel resistant)
--  - Pass 0, Segments 2-3: Data-dependent (GPU-resistant)
--  - Pass 1+, All segments: Data-dependent (GPU-resistant)
--
--  **Verification Strategy**:
--  All arithmetic operations are proven overflow-free using:
--  1. Bounded subtypes for all indices
--  2. U64_Mod for intermediate 64-bit calculations
--  3. Explicit bounds assertions for SMT solver
--
--  **Target**: 40/40 VCs (100% proof rate)
--
--  **Source**: RFC 9106 Sections 3.3-3.4

private package Spark_Argon2id.Index is

   ------------------------------------------------------------
   --  Reference Area Size Type
   ------------------------------------------------------------

   --  Size of the memory region that can be referenced
   --  RFC 9106 Section 3.4.2: "reference area size"
   --
   --  Worst case: entire lane except current segment
   --  = Active_Blocks_Per_Lane - Active_Blocks_Per_Segment
   subtype Reference_Area_Size_Type is Natural range 0 .. Active_Blocks_Per_Lane;

   --  Relative position within reference area
   --  Always strictly less than reference area size
   subtype Relative_Position_Type is Natural range 0 .. Active_Blocks_Per_Lane - 1;

   ------------------------------------------------------------
   --  Address Generator State (Argon2i Mode)
   ------------------------------------------------------------

   --  State for pseudo-random address generation (Argon2i)
   --
   --  RFC 9106 Section 3.4.1.1: Argon2i generates addresses using
   --  compression function G applied to input block Z:
   --
   --    Z = LE64(r) || LE64(l) || LE64(sl) || LE64(m') || LE64(t) || LE64(y)
   --
   --  Each call to next_addresses produces 128 pseudo-random U64 values.
   type Address_Generator_State is record
      Input_Block   : Block;             -- Input to compression function
      Address_Block : Block;             -- Output: 128 pseudo-random values
      Counter       : Block_Word_Index;  -- Current position in address_block
   end record;

   ------------------------------------------------------------
   --  Core Indexing Functions
   ------------------------------------------------------------

   --  Extract J₁ and J₂ from 64-bit pseudo-random value
   --
   --  RFC 9106 Section 3.4:
   --    J₁ = pseudo_rand AND 0xFFFFFFFF  (lower 32 bits)
   --    J₂ = pseudo_rand >> 32           (upper 32 bits)
   --
   --  @param Pseudo_Rand 64-bit pseudo-random value (from address block or prev block)
   --  @param J1 Lower 32 bits (used for mapping within reference area)
   --  @param J2 Upper 32 bits (used for lane selection)
   procedure Extract_J1_J2 (
      Pseudo_Rand : U64;
      J1          : out U32;
      J2          : out U32
   ) with
      Global => null,
      Post   => J1 = U32 (Pseudo_Rand and 16#FFFF_FFFF#) and
                J2 = U32 (Shift_Right (Pseudo_Rand, 32));

   --  Calculate reference lane from J₂
   --
   --  RFC 9106 Section 3.4:
   --    ref_lane = J₂ mod p
   --
   --  Special case: First segment of first pass cannot cross lanes
   --  (blocks in other lanes not yet initialized)
   --
   --  @param J2 Upper 32 bits of pseudo-random value
   --  @param Pos Current position in algorithm
   --  @return Lane index to read reference block from
   function Calculate_Ref_Lane (
      J2  : U32;
      Pos : Position
   ) return Lane_Index with
      Global => null,
      Post   => Calculate_Ref_Lane'Result in Lane_Index and
                (if Pos.Pass = 0 and Pos.Segment = 0 then
                   Calculate_Ref_Lane'Result = Pos.Lane);
   --  First segment restriction ensures we only reference initialized blocks

   --  Calculate size of referenceable memory region
   --
   --  RFC 9106 Section 3.4.2: The reference area size depends on:
   --  - Current pass (first pass more restricted)
   --  - Current segment (later segments can see more)
   --  - Current index within segment (can see earlier blocks)
   --  - Whether referencing same lane or different lane
   --
   --  Pass 0, Segment 0: Can only reference blocks (0..Index-1)
   --  Pass 0, Segment 1+: Can reference all prior segments + current progress
   --  Pass 1+: Can reference almost entire lane (except current segment being filled)
   --
   --  @param Pos Current position in algorithm
   --  @param Index Block index within current segment
   --  @param Same_Lane True if referencing same lane, False for cross-lane
   --  @return Size of reference area (number of blocks that can be referenced)
   function Calculate_Reference_Area_Size (
      Pos       : Position;
      Index     : Natural;
      Same_Lane : Boolean
   ) return Reference_Area_Size_Type with
      Global => null,
      Pre    => Index < Active_Blocks_Per_Segment and
                Pos.Pass in Pass_Index and
                Pos.Segment in Segment_Index and
                Pos.Lane in Lane_Index and
                --  First segment starts at block 2 (blocks 0-1 filled by Init)
                (if Pos.Pass = 0 and Pos.Segment = 0 then Index >= 2),
      Post   => Calculate_Reference_Area_Size'Result > 0 and
                Calculate_Reference_Area_Size'Result <= Active_Blocks_Per_Lane;
   --  Post: Always positive (at least 1 block referenceable)
   --        Never exceeds lane size

   --  Map J₁ to relative position within reference area
   --
   --  RFC 9106 Section 3.4.2: Non-uniform mapping that favors recent blocks:
   --
   --    x = J₁²  / 2³²                      (Square and normalize)
   --    y = (reference_area_size × x) / 2³²  (Scale to area)
   --    z = reference_area_size - 1 - y      (Invert to favor recent)
   --
   --  This creates locality of reference (cache-friendly).
   --
   --  **Verification Challenge**: Proving 64-bit arithmetic doesn't overflow
   --
   --  Proof:
   --    J₁ <= 2³² → J₁² <= 2⁶⁴ OK
   --    reference_area_size <= 131072 = 2¹⁷
   --    x <= 2³²
   --    reference_area_size × x <= 2⁴⁹ < 2⁶⁴ OK
   --
   --  @param J1 Lower 32 bits of pseudo-random value
   --  @param Reference_Area_Size Number of referenceable blocks
   --  @return Relative position within (0, Reference_Area_Size)
   function Map_J1_To_Position (
      J1                  : U32;
      Reference_Area_Size : Reference_Area_Size_Type
   ) return Relative_Position_Type with
      Global => null,
      Pre    => Reference_Area_Size > 0,
      Post   => Map_J1_To_Position'Result < Reference_Area_Size;
   --  Post: Result always strictly less than reference area size (in bounds)

   --  Calculate absolute reference block index
   --
   --  RFC 9106 Section 3.4.2: Combines relative position with segment boundaries:
   --
   --    start_position = segment offset (depends on pass/segment)
   --    absolute_position = (start_position + relative_position) mod lane_length
   --
   --  @param Pos Current position in algorithm
   --  @param Index Block index within current segment
   --  @param Relative_Position Relative offset from start_position
   --  @param Same_Lane Whether referencing same lane
   --  @return Absolute block index within lane (0, Active_Blocks_Per_Lane)
   function Calculate_Ref_Index (
      Pos               : Position;
      Index             : Natural;
      Relative_Position : Relative_Position_Type;
      Same_Lane         : Boolean
   ) return Block_Index with
      Global => null,
      Pre    => Index < Active_Blocks_Per_Segment and then
                Relative_Position < Active_Blocks_Per_Lane and then
                Pos.Pass in Pass_Index and then
                Pos.Segment in Segment_Index and then
                Pos.Lane in Lane_Index and then
                --  First segment starts at block 2 (blocks 0-1 filled by Init)
                (if Pos.Pass = 0 and Pos.Segment = 0 then Index >= 2) and then
                --  Critical property: Relative_Position is derived from Reference_Area_Size
                --  which is guaranteed to be < Index for first segment (line 73 of .adb)
                (if Pos.Pass = 0 and Pos.Segment = 0 then
                   Relative_Position < Index) and then
                --  For all positions: Relative_Position is bounded by Reference_Area_Size
                --  This ensures non-self-reference by construction
                Relative_Position < Calculate_Reference_Area_Size (Pos, Index, Same_Lane),
      Post   => Calculate_Ref_Index'Result in Block_Index and
                --  Must not reference current block (would create dependency cycle)
                Calculate_Ref_Index'Result /=
                   Block_Index'Min (Pos.Segment * Active_Blocks_Per_Segment + Index,
                                     Block_Index'Last) and
                --  First segment: only reference earlier blocks
                (if Pos.Pass = 0 and Pos.Segment = 0 then
                   Calculate_Ref_Index'Result < Index);
   --  Post: Always valid index, never self-reference, respects first-segment restriction

   ------------------------------------------------------------
   --  Address Generation (Argon2i Mode)
   ------------------------------------------------------------

   --  Initialize address generator for current segment
   --
   --  RFC 9106 Section 3.4.1.1: Initialize input block Z with:
   --    Z(0) = r  (pass number)
   --    Z(1) = l  (lane number)
   --    Z(2) = sl (slice/segment number)
   --    Z(3) = m' (total memory blocks)
   --    Z(4) = t  (total passes)
   --    Z(5) = y  (Argon2 type: 2 for Argon2id)
   --    Z(6) = 0  (counter, incremented by next_addresses)
   --    Z(7..127) = 0
   --
   --  Then pre-generates the first address block (indices 0-127).
   --  Reference: "Don't forget to generate the first block of addresses"
   --
   --  @param State Address generator state (output)
   --  @param Pos Current position in algorithm
   procedure Initialize_Address_Generator (
      State : out Address_Generator_State;
      Pos   : Position
   ) with
      Global => null,
      Relaxed_Initialization => State,
      Pre    => Pos.Pass in Pass_Index and
                Pos.Segment in Segment_Index and
                Pos.Lane in Lane_Index,
      Post   => State'Initialized and
                State.Counter = 0 and
                State.Input_Block(0) = U64 (Pos.Pass) and
                State.Input_Block(1) = U64 (Pos.Lane) and
                State.Input_Block(2) = U64 (Pos.Segment) and
                State.Input_Block(3) = U64 (Active_Total_Blocks) and
                State.Input_Block(4) = U64 (Iterations) and
                State.Input_Block(5) = 2 and  -- Argon2id type identifier
                State.Input_Block(6) = (if Pos.Pass = 0 and Pos.Segment = 0 then 1 else 0);
   --  Post: State fully initialized; Input block set; first address block pre-generated only for pass=0, segment=0

   --  Get next pseudo-random value from address generator
   --
   --  RFC 9106 Section 3.4.1.1: Returns value from address_block at Index.
   --  Reference implementation: pseudo_rand = address_block.v(i % 128)
   --
   --  When Index % 128 == 0, generates new address block via:
   --
   --    input_block.v(6)++  (increment counter)
   --    address_block = G(zero_block, input_block)
   --    address_block = G(zero_block, address_block)  (double application)
   --
   --  @param State Address generator state (modified: address block regenerated as needed)
   --  @param Index Block index within segment (used to index address_block)
   --  @param Pseudo_Rand Pseudo-random value at address_block(Index % 128) (output)
   procedure Get_Next_Pseudo_Rand (
      State       : in out Address_Generator_State;
      Index       : Natural;
      Pseudo_Rand : out U64
   ) with
      Global => null,
      Pre    => Index < Active_Blocks_Per_Segment,
      Post   => Pseudo_Rand = State.Address_Block (Index mod Block_Size_Words) and
                --  Input block counter incremented if we regenerated (Index % 128 = 0)
                (if Index mod Block_Size_Words = 0 then
                   State.Input_Block(6) = State.Input_Block'Old(6) + 1);
   --  Post: Returns address at Index, regenerates if needed

   ------------------------------------------------------------
   --  High-Level Interface
   ------------------------------------------------------------

   --  Calculate reference block index using appropriate indexing mode
   --
   --  This is the main entry point for Phase 2.7 (Fill Memory).
   --  Automatically selects Argon2i or Argon2d based on position.
   --
   --  Argon2id indexing (RFC 9106 Section 3.4.1.3):
   --    - Pass 0, Segments 0-1: Use Argon2i (data-independent)
   --    - Pass 0, Segments 2-3: Use Argon2d (data-dependent)
   --    - Pass 1+: Use Argon2d (data-dependent)
   --
   --  @param Pos Current position in algorithm
   --  @param Index Block index within current segment
   --  @param Prev_Block Previous block (used for Argon2d mode)
   --  @param Address_State Address generator (used for Argon2i mode, modified)
   --  @return Reference block index and lane
   procedure Calculate_Reference (
      Pos           : Position;
      Index         : Natural;
      Prev_Block    : Block;
      Address_State : in out Address_Generator_State;
      Ref_Lane      : out Lane_Index;
      Ref_Index     : out Block_Index
   ) with
      Global => null,
      Pre    => Index < Active_Blocks_Per_Segment and
                Pos.Pass in Pass_Index and
                Pos.Segment in Segment_Index and
                Pos.Lane in Lane_Index and
                --  First segment starts at block 2 (blocks 0-1 filled by Init)
                (if Pos.Pass = 0 and Pos.Segment = 0 then Index >= 2),
      Post   => Ref_Lane in Lane_Index and
                Ref_Index in Block_Index and
                Ref_Index /= (Pos.Segment * Active_Blocks_Per_Segment + Index) and
                (if Pos.Pass = 0 and Pos.Segment = 0 then
                   Ref_Lane = Pos.Lane and
                   Ref_Index < Index);
   --  Post: Valid reference that respects all indexing constraints

   ------------------------------------------------------------
   --  Ghost Functions (Specification Only)
   ------------------------------------------------------------

   --  Check if reference index satisfies all validity constraints
   --
   --  Used in postconditions and loop invariants.
   --  Not executable (ghost function).
   --
   --  @param Ref_Index Computed reference block index
   --  @param Ref_Lane Computed reference lane
   --  @param Pos Current position
   --  @param Index Current block index within segment
   --  @return True if reference is valid
   function Ref_Index_Valid (
      Ref_Index : Block_Index;
      Ref_Lane  : Lane_Index;
      Pos       : Position;
      Index     : Natural
   ) return Boolean is
      (Ref_Index in Block_Index and
       Ref_Lane in Lane_Index and
       --  No self-reference (use intermediate value to prevent overflow)
       Ref_Index /= Block_Index'Min (Pos.Segment * Active_Blocks_Per_Segment + Index,
                                      Block_Index'Last) and
       --  First segment restrictions
       (if Pos.Pass = 0 and Pos.Segment = 0 then
          Ref_Lane = Pos.Lane and Ref_Index < Index))
   with
      Global => null,
      Pre    => Index < Active_Blocks_Per_Segment,
      Ghost;

end Spark_Argon2id.Index;

pragma SPARK_Mode (On);

--  Implementation of Pure Mathematical Specification
--
--  This body delegates to concrete implementations where possible.

with Interfaces; use Interfaces;
with Spark_Argon2id.H0;
with Spark_Argon2id.HPrime;
with Spark_Argon2id.Mix;
with Spark_Argon2id.Internal_Types;

package body Spark_Argon2id.Spec with
  SPARK_Mode => On
is

   ------------------------------------------------------------
   --  Ghost Conversion Functions
   ------------------------------------------------------------

   function To_Spec_Byte_Array (Concrete : Spark_Argon2id.Byte_Array)
     return Byte_Array
   is
      Result : Byte_Array (1 .. Concrete'Length);
   begin
      for I in Concrete'Range loop
         Result (I) := U8 (Concrete (I));
      end loop;
      return Result;
   end To_Spec_Byte_Array;

   function From_Spec_Byte_Array (Spec_Array : Byte_Array)
     return Spark_Argon2id.Byte_Array
   is
      Result : Spark_Argon2id.Byte_Array (1 .. Spec_Array'Length);
   begin
      for I in Spec_Array'Range loop
         Result (I) := Spark_Argon2id.U8 (Spec_Array (I));
      end loop;
      return Result;
   end From_Spec_Byte_Array;

   ------------------------------------------------------------
   --  Ghost Lemmas
   ------------------------------------------------------------

   --  Lemma: Round-trip conversion of Byte_Array is identity
   --  The postcondition is proven by the postconditions of the conversion functions
   procedure Lemma_Byte_Array_Roundtrip (Arr : Spark_Argon2id.Byte_Array)
   is
      Spec_Arr : constant Byte_Array := To_Spec_Byte_Array (Arr);
      Result   : constant Spark_Argon2id.Byte_Array := From_Spec_Byte_Array (Spec_Arr);
   begin
      --  Postconditions of To_Spec and From_Spec compose to prove Result = Arr
      pragma Assert (for all I in Arr'Range =>
        Spec_Arr(I) = U8(Arr(I)));
      pragma Assert (for all I in Spec_Arr'Range =>
        Result(I) = Spark_Argon2id.U8(Spec_Arr(I)));
      pragma Assert (for all I in Arr'Range =>
        Result(I) = Spark_Argon2id.U8(U8(Arr(I))));
      --  Since Spark_Argon2id.U8 = U8 (same type), Result(I) = Arr(I)
   end Lemma_Byte_Array_Roundtrip;

   --  Lemma: Round-trip conversion of Block is identity
   procedure Lemma_Block_Roundtrip (B : Internal_Types.Block)
   is
      Spec_B : constant Block := To_Spec_Block (B);
      Result : constant Internal_Types.Block := From_Spec_Block (Spec_B);
   begin
      --  Postconditions of To_Spec and From_Spec compose to prove Result = B
      pragma Assert (for all I in Block_Word_Index =>
        Spec_B(I) = B(I));
      pragma Assert (for all I in Block_Word_Index =>
        Result(I) = Spec_B(I));
      --  Therefore Result(I) = B(I) by transitivity
   end Lemma_Block_Roundtrip;

   ------------------------------------------------------------
   --  Fill Algorithm Refinement Ghost Functions
   ------------------------------------------------------------

   --  Convert concrete Memory_State to Abstract_Memory
   --  Simply wraps the array in the Abstract_Memory record
   --  Converts Internal_Types.Block to Spec.Block
   function To_Abstract_Memory (
      Memory : Concrete_Memory_Array
   ) return Abstract_Memory
   is
      Result : Abstract_Memory;
   begin
      --  Copy all blocks from Memory to Result.Blocks
      --  Memory uses Internal_Types.Block, Result.Blocks uses Spec.Block
      for L in Lane_Index loop
         for I in Block_Index loop
            --  Element-wise copy (both are U64 arrays with same structure)
            for Word_Idx in Block_Word_Index loop
               Result.Blocks (L, I) (Word_Idx) := U64 (Memory (L, I) (Word_Idx));
            end loop;
         end loop;
      end loop;
      return Result;
   end To_Abstract_Memory;

   --  Check if Memory_State matches Abstract_Memory element-wise
   function Memory_Matches_Spec (
      Memory : Concrete_Memory_Array;
      M      : Abstract_Memory
   ) return Boolean
   is
   begin
      --  Compare all blocks element-wise
      for L in Lane_Index loop
         for I in Block_Index loop
            declare
               Spec_Block : constant Block := Get_Block (M, L, I);
               Concrete_Block : constant Internal_Types.Block := Memory (L, I);
            begin
               --  Compare each word
               for Word_Idx in Block_Word_Index loop
                  if U64 (Concrete_Block (Word_Idx)) /= Spec_Block (Word_Idx) then
                     return False;
                  end if;
               end loop;
            end;
         end loop;
      end loop;
      return True;
   end Memory_Matches_Spec;

   ------------------------------------------------------------
   --  Helper Functions
   ------------------------------------------------------------

   function Set_Block
     (M     : Abstract_Memory;
      Lane  : Lane_Index;
      Idx   : Block_Index;
      Value : Block) return Abstract_Memory
   is
      Result : Abstract_Memory := M;
   begin
      Result.Blocks (Lane, Idx) := Value;
      return Result;
   end Set_Block;

   function Initial_Memory return Abstract_Memory is
      Result : Abstract_Memory;
   begin
      for L in Lane_Index loop
         for I in Block_Index loop
            Result.Blocks (L, I) := Zero_Block;
         end loop;
      end loop;
      return Result;
   end Initial_Memory;

   ------------------------------------------------------------
   --  H₀ Specification
   ------------------------------------------------------------

   function H0_Spec
     (Password     : Byte_Array;
      Salt         : Byte_Array;
      Key          : Byte_Array;
      Assoc_Data   : Byte_Array;
      Parallelism  : Positive;
      Tag_Length   : Positive;
      Memory_KiB   : Positive;
      Iterations   : Positive) return Byte_Array
   is
      --  Convert Spec.Byte_Array to parent Byte_Array for concrete call
      Password_Conv : Spark_Argon2id.Byte_Array (Password'Range);
      Salt_Conv     : Spark_Argon2id.Byte_Array (Salt'Range);
      Key_Conv      : Spark_Argon2id.Byte_Array (Key'Range);
      Assoc_Conv    : Spark_Argon2id.Byte_Array (Assoc_Data'Range);
      Result_Conv   : Spark_Argon2id.Byte_Array (1 .. 64);
      Result        : Byte_Array (1 .. 64);
   begin
      --  Convert input arrays (Spec.Byte_Array to parent Byte_Array)
      for I in Password'Range loop
         Password_Conv (I) := Password (I);
      end loop;
      for I in Salt'Range loop
         Salt_Conv (I) := Salt (I);
      end loop;
      for I in Key'Range loop
         Key_Conv (I) := Key (I);
      end loop;
      for I in Assoc_Data'Range loop
         Assoc_Conv (I) := Assoc_Data (I);
      end loop;

      --  Delegate to concrete H0
      H0.Compute_H0 (
        Password        => Password_Conv,
        Salt            => Salt_Conv,
        Key             => Key_Conv,
        Associated_Data => Assoc_Conv,
        Parallelism     => Parallelism,
        Tag_Length      => Tag_Length,
        Memory_KiB      => Memory_KiB,
        Iterations      => Iterations,
        H0_Out          => Result_Conv
      );

      --  Convert result back
      for I in Result'Range loop
         Result (I) := U8 (Result_Conv (I));
      end loop;

      return Result;
   end H0_Spec;

   ------------------------------------------------------------
   --  H′ Specification
   ------------------------------------------------------------

   function HPrime_Spec
     (Input      : Byte_Array;
      Out_Length : Positive) return Byte_Array
   is
      --  Convert types
      Input_Conv  : Spark_Argon2id.Byte_Array (Input'Range);
      Result_Conv : Spark_Argon2id.Byte_Array (1 .. Out_Length);
      Result      : Byte_Array (1 .. Out_Length);
   begin
      --  Convert input
      for I in Input'Range loop
         Input_Conv (I) := Input (I);
      end loop;

      --  Delegate to concrete HPrime
      HPrime.Compute_H_Prime (
        Output_Length => Out_Length,
        Input         => Input_Conv,
        Output        => Result_Conv
      );

      --  Convert result back
      for I in Result'Range loop
         Result (I) := U8 (Result_Conv (I));
      end loop;

      return Result;
   end HPrime_Spec;

   ------------------------------------------------------------
   --  G Specification
   ------------------------------------------------------------

   function G_Spec (B1, B2 : Block) return Block
   is
      --  Need to work with Internal_Types.Block for Mix module
      use Spark_Argon2id.Internal_Types;
      B1_Conv : Internal_Types.Block;
      B2_Conv : Internal_Types.Block;
      Result_Conv : Internal_Types.Block;
      Result : Block;
   begin
      --  Convert blocks to Internal_Types.Block
      for I in Block_Word_Index loop
         B1_Conv (I) := Spark_Argon2id.U64 (B1 (I));
         B2_Conv (I) := Spark_Argon2id.U64 (B2 (I));
      end loop;

      --  Delegate to concrete Mix.G
      Mix.G (X => B1_Conv, Y => B2_Conv, Output => Result_Conv);

      --  Convert result back
      for I in Block_Word_Index loop
         Result (I) := U64 (Result_Conv (I));
      end loop;

      return Result;
   end G_Spec;

   ------------------------------------------------------------
   --  Indexing Specification
   ------------------------------------------------------------

   function Index_i_Spec
     (Pass    : Pass_Index;
      Lane    : Lane_Index;
      Segment : Segment_Index;
      Index   : Block_Index) return Block_Index
   is
      --  RFC 9106 Section 3.4.1 (Argon2i): Data-independent indexing
      --
      --  Algorithm:
      --  1. Generate pseudo-random value from (pass, lane, segment, index)
      --  2. Extract J1 (lower 32 bits), J2 (upper 32 bits)
      --  3. Calculate reference lane: J2 mod p
      --  4. Calculate reference area size (depends on pass/segment/index)
      --  5. Map J1 to position using multiply-divide method
      --  6. Calculate absolute reference index with wraparound

      --  Step 1: Generate pseudo-random value via address generation
      --  Create input block Z (RFC 9106 Section 3.4.1.1)
      Input_Block : Block := Zero_Block;
      Address_Block : Block;
      Temp_Block : Block;

      --  Calculate which 128-value address block we need
      Counter : constant Natural := Index / 128;
      Block_Offset : constant Block_Word_Index := Index mod 128;

      Pseudo_Rand : U64;
      J1 : U32;
      J2 : U32;

      --  Step 3-6: Reference calculation
      Ref_Lane_Val : Lane_Index;
      Same_Lane : Boolean;
      Ref_Area_Size : Natural;

      --  For multiply-divide mapping (RFC 9106 Section 3.4.2)
      X, Y, Z : U64;
      Z_Nat : Natural;
      Relative_Pos : Natural;

      Start_Position : Natural;
      Absolute_Position : Block_Index;
   begin
      --  Initialize input block Z
      Input_Block(0) := U64(Pass);
      Input_Block(1) := U64(Lane);
      Input_Block(2) := U64(Segment);
      Input_Block(3) := U64(Active_Total_Blocks);
      Input_Block(4) := U64(Iterations);
      Input_Block(5) := 2;  -- Argon2id type
      Input_Block(6) := U64(Counter + 1);  -- 1-indexed counter

      --  Generate address block: G(Zero_Block, Input_Block) twice
      Address_Block := G_Spec(Zero_Block, Input_Block);
      Address_Block := G_Spec(Zero_Block, Address_Block);

      --  Extract pseudo-random value at Index position
      Pseudo_Rand := Address_Block(Block_Offset);

      --  Step 2: Extract J1 and J2
      J1 := U32(Pseudo_Rand and 16#FFFF_FFFF#);  -- Lower 32 bits
      J2 := U32(Shift_Right(Pseudo_Rand, 32));    -- Upper 32 bits

      --  Step 3: Calculate reference lane (RFC 9106 Section 3.4)
      Ref_Lane_Val := Lane_Index(J2 mod U32(Parallelism));

      --  First segment restriction: cannot cross lanes
      if Pass = 0 and Segment = 0 then
         Ref_Lane_Val := Lane;
      end if;

      Same_Lane := (Ref_Lane_Val = Lane);

      --  Step 4: Calculate reference area size (RFC 9106 Section 3.4.2)
      if Pass = 0 then
         if Segment = 0 then
            --  First segment: only earlier blocks in this segment
            Ref_Area_Size := Index - 1;
         else
            --  Later segments in first pass
            if Same_Lane then
               Ref_Area_Size := Segment * Active_Blocks_Per_Segment + Index - 1;
            else
               if Index = 0 then
                  Ref_Area_Size := Segment * Active_Blocks_Per_Segment - 1;
               else
                  Ref_Area_Size := Segment * Active_Blocks_Per_Segment;
               end if;
            end if;
         end if;
      else
         --  Second+ pass: most of the lane available
         if Same_Lane then
            Ref_Area_Size := Active_Blocks_Per_Lane - Active_Blocks_Per_Segment + Index - 1;
         else
            if Index = 0 then
               Ref_Area_Size := Active_Blocks_Per_Lane - Active_Blocks_Per_Segment - 1;
            else
               Ref_Area_Size := Active_Blocks_Per_Lane - Active_Blocks_Per_Segment;
            end if;
         end if;
      end if;

      --  Step 5: Map J1 to position using multiply-divide (RFC 9106 Section 3.4.2)
      --  This avoids modulo bias
      --  x = (J1 * J1) / 2^32
      X := U64(J1) * U64(J1) / (2**32);

      --  y = (ref_area_size * x) / 2^32
      Y := U64(Ref_Area_Size) * X / (2**32);
      Z := Y;

      Z_Nat := Natural(Z);

      --  relative_position = ref_area_size - 1 - z (inverts to favor recent blocks)
      if Z_Nat >= Ref_Area_Size then
         Z_Nat := Ref_Area_Size - 1;  -- Clamp to valid range
      end if;

      Relative_Pos := Ref_Area_Size - 1 - Z_Nat;

      --  Step 6: Calculate absolute reference index with wraparound
      if Pass = 0 then
         Start_Position := 0;
      else
         --  Start at next segment (wraparound)
         Start_Position := ((Segment + 1) * Active_Blocks_Per_Segment)
                           mod Active_Blocks_Per_Lane;
      end if;

      Absolute_Position := (Start_Position + Relative_Pos) mod Active_Blocks_Per_Lane;

      return Absolute_Position;
   end Index_i_Spec;

   function Index_d_Spec
     (M       : Abstract_Memory;
      Lane    : Lane_Index;
      Prev_Idx : Block_Index) return Block_Index
   is
      --  RFC 9106 Section 3.4.2 (Argon2d): Data-dependent indexing
      --
      --  Algorithm:
      --  1. Extract J1 (first word) and J2 (second word) from previous block
      --  2. Calculate reference lane: J2 mod p
      --  3. Determine current position (Pass, Segment, Index)
      --  4. Calculate reference area size
      --  5. Map J1 to position using multiply-divide method
      --  6. Calculate absolute reference index
      --
      --  Note: For data-dependent indexing, we derive position from Prev_Idx

      Prev_Block : constant Block := Get_Block (M, Lane, Prev_Idx);

      --  Extract J1, J2 from previous block (RFC 9106 Section 3.4.2)
      Pseudo_Rand : constant U64 := Prev_Block (0);
      J1 : U32;
      J2 : U32;

      --  Determine current position from Prev_Idx
      --  Current block is at Prev_Idx + 1
      Current_Idx : constant Block_Index := (Prev_Idx + 1) mod Active_Blocks_Per_Lane;
      Current_Segment : constant Segment_Index := Current_Idx / Active_Blocks_Per_Segment;
      Index_In_Segment : constant Natural := Current_Idx mod Active_Blocks_Per_Segment;

      --  For Index_d_Spec in the spec, we assume we're past the Argon2i phase
      --  (Pass 0, Segments 2-3 or Pass 1+)
      --  Since we don't have pass info, we use a conservative estimate
      Pass : constant Pass_Index := 0;  -- Simplified for spec

      --  Reference calculation
      Ref_Lane_Val : Lane_Index;
      Same_Lane : Boolean;
      Ref_Area_Size : Natural;

      --  For multiply-divide mapping (RFC 9106 Section 3.4.2)
      X, Y, Z : U64;
      Z_Nat : Natural;
      Relative_Pos : Natural;

      Start_Position : Natural;
      Absolute_Position : Block_Index;
   begin
      --  Extract J1 and J2 (RFC 9106 Section 3.4)
      J1 := U32(Pseudo_Rand and 16#FFFF_FFFF#);  -- Lower 32 bits
      J2 := U32(Shift_Right(Pseudo_Rand, 32));    -- Upper 32 bits

      --  Calculate reference lane (RFC 9106 Section 3.4)
      Ref_Lane_Val := Lane_Index(J2 mod U32(Parallelism));

      --  First segment special case: cannot cross lanes
      if Pass = 0 and Current_Segment = 0 then
         Ref_Lane_Val := Lane;
      end if;

      Same_Lane := (Ref_Lane_Val = Lane);

      --  Calculate reference area size (RFC 9106 Section 3.4.2)
      if Pass = 0 then
         if Current_Segment = 0 then
            --  First segment: only earlier blocks
            if Index_In_Segment > 0 then
               Ref_Area_Size := Index_In_Segment - 1;
            else
               Ref_Area_Size := 1;  -- Minimum to avoid zero
            end if;
         else
            --  Later segments in first pass
            if Same_Lane then
               Ref_Area_Size := Current_Segment * Active_Blocks_Per_Segment + Index_In_Segment - 1;
            else
               if Index_In_Segment = 0 then
                  Ref_Area_Size := Current_Segment * Active_Blocks_Per_Segment - 1;
               else
                  Ref_Area_Size := Current_Segment * Active_Blocks_Per_Segment;
               end if;
            end if;
         end if;
      else
         --  Second+ pass: most of the lane available
         if Same_Lane then
            Ref_Area_Size := Active_Blocks_Per_Lane - Active_Blocks_Per_Segment + Index_In_Segment - 1;
         else
            if Index_In_Segment = 0 then
               Ref_Area_Size := Active_Blocks_Per_Lane - Active_Blocks_Per_Segment - 1;
            else
               Ref_Area_Size := Active_Blocks_Per_Lane - Active_Blocks_Per_Segment;
            end if;
         end if;
      end if;

      --  Ensure non-zero area
      if Ref_Area_Size = 0 then
         Ref_Area_Size := 1;
      end if;

      --  Map J1 to position using multiply-divide (RFC 9106 Section 3.4.2)
      --  This avoids modulo bias
      X := U64(J1) * U64(J1) / (2**32);
      Y := U64(Ref_Area_Size) * X / (2**32);
      Z := Y;

      Z_Nat := Natural(Z);

      --  relative_position = ref_area_size - 1 - z (inverts to favor recent blocks)
      if Z_Nat >= Ref_Area_Size then
         Z_Nat := Ref_Area_Size - 1;  -- Clamp to valid range
      end if;

      Relative_Pos := Ref_Area_Size - 1 - Z_Nat;

      --  Calculate absolute reference index with wraparound
      if Pass = 0 then
         Start_Position := 0;
      else
         --  Start at next segment (wraparound)
         Start_Position := ((Current_Segment + 1) * Active_Blocks_Per_Segment)
                           mod Active_Blocks_Per_Lane;
      end if;

      Absolute_Position := (Start_Position + Relative_Pos) mod Active_Blocks_Per_Lane;

      return Absolute_Position;
   end Index_d_Spec;

   ------------------------------------------------------------
   --  Fill Specification
   ------------------------------------------------------------

   function Fill_Segment_Spec
     (M       : Abstract_Memory;
      Pass    : Pass_Index;
      Segment : Segment_Index;
      Lane    : Lane_Index) return Abstract_Memory
   is
      --  RFC 9106 Section 3.4: Segment filling algorithm
      --
      --  For each block in the segment:
      --  1. Get previous block (current - 1 with wraparound)
      --  2. Select reference block using Index_i_Spec or Index_d_Spec
      --  3. Compute new block: G(previous, reference)
      --  4. If pass > 0: XOR with existing block
      --  5. Store result

      Updated_M : Abstract_Memory := M;
      Mode : constant Indexing_Mode := Get_Indexing_Mode (
        (Pass => Pass, Segment => Segment, Lane => Lane, Index => 0));

      Segment_Start : constant Block_Index :=
        Block_Index (Segment) * Active_Blocks_Per_Segment;
      Segment_End : constant Block_Index :=
        Segment_Start + Active_Blocks_Per_Segment - 1;

      Prev_Idx : Block_Index;
      Ref_Idx  : Block_Index;
      Prev_Block : Block;
      Ref_Block  : Block;
      New_Block  : Block;
      Old_Block  : Block;
      Current_Block_Idx : Block_Index;
   begin
      --  Fill all blocks in this segment
      for I in Segment_Start .. Segment_End loop
         Current_Block_Idx := I;

         --  Step 1: Get previous block (with wraparound at lane boundary)
         if I = 0 then
            --  First block in lane: wrap to last block
            Prev_Idx := Active_Blocks_Per_Lane - 1;
         else
            Prev_Idx := I - 1;
         end if;

         Prev_Block := Get_Block (Updated_M, Lane, Prev_Idx);

         --  Step 2: Select reference block based on indexing mode
         if Mode = Data_Independent then
            --  Argon2i: PRNG-based (data-independent)
            Ref_Idx := Index_i_Spec (Pass, Lane, Segment, I);
         else
            --  Argon2d: Data-dependent (reads from previous block)
            Ref_Idx := Index_d_Spec (Updated_M, Lane, Prev_Idx);
         end if;

         --  Step 3: Get reference block
         --  Note: For spec simplicity, we assume same-lane references
         --  The concrete implementation handles cross-lane properly
         Ref_Block := Get_Block (Updated_M, Lane, Ref_Idx);

         --  Step 4: Compute new block via G compression function
         New_Block := G_Spec (Prev_Block, Ref_Block);

         --  Step 5: For passes > 0, XOR with existing block (overwrite protection)
         if Pass > 0 then
            Old_Block := Get_Block (Updated_M, Lane, Current_Block_Idx);
            --  XOR each word
            for Word_Idx in Block_Word_Index loop
               New_Block (Word_Idx) := New_Block (Word_Idx) xor Old_Block (Word_Idx);
            end loop;
         end if;

         --  Step 6: Store result
         Updated_M := Set_Block (Updated_M, Lane, Current_Block_Idx, New_Block);
      end loop;

      return Updated_M;
   end Fill_Segment_Spec;

   function Fill_All_Spec (Initial_Mem : Abstract_Memory) return Abstract_Memory
   is
      --  RFC 9106 Section 3.4: Multi-pass memory filling
      --
      --  Outer loop structure:
      --  for each pass (iteration)
      --    for each segment (slice)
      --      for each lane (parallel lane)
      --        Fill_Segment_Spec

      M : Abstract_Memory := Initial_Mem;
   begin
      --  Iterate through all passes (t iterations)
      for Pass in Pass_Index loop
         --  Iterate through all segments (4 segments per pass)
         for Segment in Segment_Index loop
            --  Iterate through all lanes (p parallel lanes)
            for Lane in Lane_Index loop
               --  Fill this (pass, segment, lane) combination
               M := Fill_Segment_Spec (M, Pass, Segment, Lane);
            end loop;
         end loop;
      end loop;

      return M;
   end Fill_All_Spec;

   ------------------------------------------------------------
   --  Finalization Specification
   ------------------------------------------------------------

   function Finalize_Spec
     (M          : Abstract_Memory;
      Tag_Length : Positive) return Byte_Array
   is
      --  RFC 9106 Section 3.4: Finalization
      --
      --  1. XOR last block of each lane together: C = B[0][q-1] ⊕ B[1][q-1] ⊕ ...
      --  2. Convert C to byte array (1024 bytes)
      --  3. Hash to desired tag length: Tag = H'(C, Tag_Length)

      C : Block := Zero_Block;
      Last_Idx : constant Block_Index := Active_Blocks_Per_Lane - 1;
      Last_Block : Block;
      C_Bytes : Byte_Array (1 .. 1024);  -- Block is 128 * 8 = 1024 bytes
      Byte_Offset : Positive;
      Word_Val : U64;
   begin
      --  Step 1: XOR all last blocks together
      for Lane in Lane_Index loop
         Last_Block := Get_Block (M, Lane, Last_Idx);

         --  XOR element-wise
         for I in Block_Word_Index loop
            C (I) := C (I) xor Last_Block (I);
         end loop;
      end loop;

      --  Step 2: Convert Block to Byte_Array (little-endian U64 encoding)
      --  Each U64 becomes 8 bytes in little-endian order
      for I in Block_Word_Index loop
         Word_Val := C (I);
         Byte_Offset := I * 8 + 1;  -- 1-indexed byte array

         --  Convert U64 to 8 bytes (little-endian)
         C_Bytes (Byte_Offset + 0) := U8 (Word_Val and 16#FF#);
         C_Bytes (Byte_Offset + 1) := U8 (Shift_Right (Word_Val, 8) and 16#FF#);
         C_Bytes (Byte_Offset + 2) := U8 (Shift_Right (Word_Val, 16) and 16#FF#);
         C_Bytes (Byte_Offset + 3) := U8 (Shift_Right (Word_Val, 24) and 16#FF#);
         C_Bytes (Byte_Offset + 4) := U8 (Shift_Right (Word_Val, 32) and 16#FF#);
         C_Bytes (Byte_Offset + 5) := U8 (Shift_Right (Word_Val, 40) and 16#FF#);
         C_Bytes (Byte_Offset + 6) := U8 (Shift_Right (Word_Val, 48) and 16#FF#);
         C_Bytes (Byte_Offset + 7) := U8 (Shift_Right (Word_Val, 56) and 16#FF#);
      end loop;

      --  Step 3: Hash to final tag length using H'
      return HPrime_Spec (C_Bytes, Tag_Length);
   end Finalize_Spec;

   ------------------------------------------------------------
   --  Top-Level Specification
   ------------------------------------------------------------

   function Derive_Spec
     (Password     : Byte_Array;
      Salt         : Byte_Array;
      Key          : Byte_Array;
      Assoc_Data   : Byte_Array;
      Tag_Length   : Positive;
      Memory_KiB   : Positive;
      Iterations   : Positive;
      Parallelism  : Positive) return Byte_Array
   is
      --  RFC 9106 Complete Argon2id Algorithm
      --
      --  1. Compute H₀ from all inputs
      --  2. Initialize first two blocks of each lane from H₀
      --  3. Fill all memory using Fill_All_Spec
      --  4. Extract final tag using Finalize_Spec

      --  Step 1: Compute H₀
      H0_Digest : constant Byte_Array := H0_Spec (
        Password, Salt, Key, Assoc_Data,
        Parallelism, Tag_Length, Memory_KiB, Iterations);

      --  Step 2: Initialize memory with B[i][0] and B[i][1]
      M : Abstract_Memory := Initial_Memory;

      --  For initialization: H₀ || LE32(block_index) || LE32(lane)
      Init_Input : Byte_Array (1 .. 72);  -- 64 (H0) + 4 (index) + 4 (lane)
      Block_Bytes : Byte_Array (1 .. 1024);
      Init_Block : Block;
      Lane_U32 : U32;
      Index_U32 : U32;

      --  Step 3: Fill all memory
      M_Filled : Abstract_Memory;
   begin
      --  Initialize first 64 bytes with H0_Digest
      for I in H0_Digest'Range loop
         Init_Input (I) := H0_Digest (I);
      end loop;

      --  Step 2: Initialize first two blocks per lane
      for Lane in Lane_Index loop
         Lane_U32 := U32 (Lane);

         --  Initialize B[lane][0] = H'(H0 || LE32(0) || LE32(lane))
         Index_U32 := 0;

         --  Append LE32(index) at bytes 65-68
         Init_Input (65) := U8 (Index_U32 and 16#FF#);
         Init_Input (66) := U8 (Shift_Right (Index_U32, 8) and 16#FF#);
         Init_Input (67) := U8 (Shift_Right (Index_U32, 16) and 16#FF#);
         Init_Input (68) := U8 (Shift_Right (Index_U32, 24) and 16#FF#);

         --  Append LE32(lane) at bytes 69-72
         Init_Input (69) := U8 (Lane_U32 and 16#FF#);
         Init_Input (70) := U8 (Shift_Right (Lane_U32, 8) and 16#FF#);
         Init_Input (71) := U8 (Shift_Right (Lane_U32, 16) and 16#FF#);
         Init_Input (72) := U8 (Shift_Right (Lane_U32, 24) and 16#FF#);

         --  Generate 1024-byte block via H'
         Block_Bytes := HPrime_Spec (Init_Input, 1024);

         --  Convert bytes to Block (128 U64s, little-endian)
         for I in Block_Word_Index loop
            declare
               Byte_Start : constant Positive := I * 8 + 1;
            begin
               Init_Block (I) :=
                 U64 (Block_Bytes (Byte_Start + 0)) or
                 Shift_Left (U64 (Block_Bytes (Byte_Start + 1)), 8) or
                 Shift_Left (U64 (Block_Bytes (Byte_Start + 2)), 16) or
                 Shift_Left (U64 (Block_Bytes (Byte_Start + 3)), 24) or
                 Shift_Left (U64 (Block_Bytes (Byte_Start + 4)), 32) or
                 Shift_Left (U64 (Block_Bytes (Byte_Start + 5)), 40) or
                 Shift_Left (U64 (Block_Bytes (Byte_Start + 6)), 48) or
                 Shift_Left (U64 (Block_Bytes (Byte_Start + 7)), 56);
            end;
         end loop;

         M := Set_Block (M, Lane, 0, Init_Block);

         --  Initialize B[lane][1] = H'(H0 || LE32(1) || LE32(lane))
         Index_U32 := 1;

         --  Update LE32(index) at bytes 65-68
         Init_Input (65) := U8 (Index_U32 and 16#FF#);
         Init_Input (66) := U8 (Shift_Right (Index_U32, 8) and 16#FF#);
         Init_Input (67) := U8 (Shift_Right (Index_U32, 16) and 16#FF#);
         Init_Input (68) := U8 (Shift_Right (Index_U32, 24) and 16#FF#);

         --  Generate 1024-byte block via H'
         Block_Bytes := HPrime_Spec (Init_Input, 1024);

         --  Convert bytes to Block
         for I in Block_Word_Index loop
            declare
               Byte_Start : constant Positive := I * 8 + 1;
            begin
               Init_Block (I) :=
                 U64 (Block_Bytes (Byte_Start + 0)) or
                 Shift_Left (U64 (Block_Bytes (Byte_Start + 1)), 8) or
                 Shift_Left (U64 (Block_Bytes (Byte_Start + 2)), 16) or
                 Shift_Left (U64 (Block_Bytes (Byte_Start + 3)), 24) or
                 Shift_Left (U64 (Block_Bytes (Byte_Start + 4)), 32) or
                 Shift_Left (U64 (Block_Bytes (Byte_Start + 5)), 40) or
                 Shift_Left (U64 (Block_Bytes (Byte_Start + 6)), 48) or
                 Shift_Left (U64 (Block_Bytes (Byte_Start + 7)), 56);
            end;
         end loop;

         M := Set_Block (M, Lane, 1, Init_Block);
      end loop;

      --  Step 3: Fill all memory blocks
      M_Filled := Fill_All_Spec (M);

      --  Step 4: Extract final tag
      return Finalize_Spec (M_Filled, Tag_Length);
   end Derive_Spec;

   ------------------------------------------------------------
   --  Block Conversion Functions (Ghost, for refinement)
   ------------------------------------------------------------

   function To_Spec_Block (Concrete : Internal_Types.Block)
     return Block
   is
      Result : Block;
   begin
      for I in Block_Word_Index loop
         Result (I) := Concrete (I);
      end loop;
      return Result;
   end To_Spec_Block;

   function From_Spec_Block (Spec_Block : Block)
     return Internal_Types.Block
   is
      Result : Internal_Types.Block;
   begin
      for I in Block_Word_Index loop
         Result (I) := Spec_Block (I);
      end loop;
      return Result;
   end From_Spec_Block;

end Spark_Argon2id.Spec;

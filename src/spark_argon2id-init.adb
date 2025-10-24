pragma SPARK_Mode (On);

with Interfaces; use Interfaces;
with Spark_Argon2id.HPrime;

package body Spark_Argon2id.Init with
   SPARK_Mode => On
is

   ------------------------------------------------------------
   --  Little-Endian 32-bit Encoder
   ------------------------------------------------------------

   --  Encode 32-bit unsigned integer as 4 bytes (little-endian)
   --  Reused from H' module for consistency
   function LE32 (Value : Unsigned_32) return Byte_Array is
     (1 => U8 (Value and 16#FF#),
      2 => U8 (Shift_Right (Value, 8) and 16#FF#),
      3 => U8 (Shift_Right (Value, 16) and 16#FF#),
      4 => U8 (Shift_Right (Value, 24) and 16#FF#))
   with
      Global => null,
      Post   => LE32'Result'Length = 4,
      Inline;

   ------------------------------------------------------------
   --  Bytes_To_Block (Little-Endian Conversion)
   ------------------------------------------------------------

   --  Convert 1024 bytes to Block (128 × U64 words, little-endian)
   --
   --  **Algorithm**:
   --    For each word w in (0..127):
   --      offset = w * 8
   --      word(w) = bytes(offset+0)       |
   --                bytes(offset+1) << 8  |
   --                ...                   |
   --                bytes(offset+7) << 56
   --
   --  **Why Little-Endian**: Blake2b uses little-endian byte order
   --  **Why Inline**: Zero-overhead conversion
   --
   --  **Example**:
   --    Bytes (0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0, ...)
   --    Word(0) = 0xF0DEBC9A78563412 (little-endian)

   function Bytes_To_Block (Bytes : Byte_Array) return Block
   with
      Global => null,
      Pre    => Bytes'Length = 1024 and Bytes'First = 1,
      Post   => Bytes_To_Block'Result'Length = 128
   is
      Result : Block := Zero_Block;
      Offset : Natural;
   begin
      for W in Block_Word_Index loop
         pragma Loop_Optimize (No_Unroll);
         pragma Loop_Invariant (Result'Length = 128);

         --  Each word is 8 bytes, offset = w * 8 + 1 (1-indexed array)
         Offset := W * 8 + 1;

         --  Pack 8 bytes into U64 (little-endian)
         Result (W) :=
            U64 (Bytes (Offset + 0))              or
            Shift_Left (U64 (Bytes (Offset + 1)), 8)  or
            Shift_Left (U64 (Bytes (Offset + 2)), 16) or
            Shift_Left (U64 (Bytes (Offset + 3)), 24) or
            Shift_Left (U64 (Bytes (Offset + 4)), 32) or
            Shift_Left (U64 (Bytes (Offset + 5)), 40) or
            Shift_Left (U64 (Bytes (Offset + 6)), 48) or
            Shift_Left (U64 (Bytes (Offset + 7)), 56);
      end loop;

      return Result;
   end Bytes_To_Block;

   ------------------------------------------------------------
   --  Generate_Initial_Blocks Implementation
   ------------------------------------------------------------

   --  Generate first two blocks for a lane from H₀
   --
   --  **Algorithm** (RFC 9106 Section 3.4):
   --
   --  For block_index in (0, 1):
   --    1. Build input: H₀ || LE32(block_index) || LE32(lane_index)
   --    2. Call H' to generate 1024-byte output
   --    3. Convert bytes to Block (128 × U64 words)
   --
   --  **Memory Usage**: 72 bytes input + 1024 bytes output = 1096 bytes
   --  **Time Complexity**: 2 × H' calls = ~4 × Blake2b-512 calls
   --
   --  **Source**: RFC 9106 Section 3.4, Figure 5

   procedure Generate_Initial_Blocks (
      H0     : Byte_Array;
      Lane   : Lane_Index;
      Output : out Initial_Blocks
   ) is
      --  Input buffer: H₀ (64) || LE32(block) (4) || LE32(lane) (4) = 72 bytes
      Input_Buffer : Byte_Array (1 .. 72) := (others => 0);

      --  H' output buffer: 1024 bytes per block
      Block_Bytes : Byte_Array (1 .. 1024) := (others => 0);

   begin
      --  Initialize output to safe default
      Output := (Block_0 => Zero_Block, Block_1 => Zero_Block);

      ------------------------------------------------------------
      --  Generate Block_0: B(lane)(0) = H'(1024, H₀ || 0 || lane)
      ------------------------------------------------------------

      --  Build input: H₀ || LE32(0) || LE32(lane)
      Input_Buffer (1 .. 64) := H0;
      Input_Buffer (65 .. 68) := LE32 (0);  -- Block index = 0
      Input_Buffer (69 .. 72) := LE32 (Unsigned_32 (Lane));

      pragma Assert (Input_Buffer'Length = 72);

      --  Generate 1024-byte block via H'
      HPrime.Compute_H_Prime (
         Output_Length => 1024,
         Input         => Input_Buffer,
         Output        => Block_Bytes
      );

      --  Convert bytes to U64 words (little-endian)
      Output.Block_0 := Bytes_To_Block (Block_Bytes);

      ------------------------------------------------------------
      --  Generate Block_1: B(lane)(1) = H'(1024, H₀ || 1 || lane)
      ------------------------------------------------------------

      --  Build input: H₀ || LE32(1) || LE32(lane)
      --  (H₀ and lane are already in buffer, just update block index)
      Input_Buffer (65 .. 68) := LE32 (1);  -- Block index = 1

      pragma Assert (Input_Buffer'Length = 72);

      --  Generate 1024-byte block via H'
      HPrime.Compute_H_Prime (
         Output_Length => 1024,
         Input         => Input_Buffer,
         Output        => Block_Bytes
      );

      --  Convert bytes to U64 words (little-endian)
      Output.Block_1 := Bytes_To_Block (Block_Bytes);

   end Generate_Initial_Blocks;

end Spark_Argon2id.Init;

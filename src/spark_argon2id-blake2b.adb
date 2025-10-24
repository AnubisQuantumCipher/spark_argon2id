pragma SPARK_Mode (On);

with Interfaces; use Interfaces;

package body Spark_Argon2id.Blake2b
  with SPARK_Mode => On
is
   pragma Warnings (GNATProve, Off, "pragma * ignored (not yet supported)");

   ------------------------------------------------------------
   --  Rotation Functions (Blake2b uses 32, 24, 16, 63)
   ------------------------------------------------------------

   --  These are implemented as expression functions using Ada's
   --  intrinsic Rotate_Right, which is proven safe by SPARK.
   --  No overflow checks needed - rotation is always well-defined.

   function Rotr32 (X : U64) return U64 is (Rotate_Right (X, 32))
     with Inline, Global => null;

   function Rotr24 (X : U64) return U64 is (Rotate_Right (X, 24))
     with Inline, Global => null;

   function Rotr16 (X : U64) return U64 is (Rotate_Right (X, 16))
     with Inline, Global => null;

   function Rotr63 (X : U64) return U64 is (Rotate_Right (X, 63))
     with Inline, Global => null;

   ------------------------------------------------------------
   --  Little-Endian Conversion Functions
   ------------------------------------------------------------

   --  Blake2b uses little-endian byte order (unlike SHA-512's big-endian).
   --  These functions convert between byte arrays and U64 words.

   --  Pack 8 bytes into U64 (little-endian)
   --  In little-endian, bytes [0,1,2,3,4,5,6,7] encode a U64 as:
   --  U64 = byte[0] + (byte[1] << 8) + (byte[2] << 16) + ... + (byte[7] << 56)
   function LE_Pack (Bytes : Byte_Array) return U64
   with
     Global => null,
     Pre    => Bytes'Length = 8
   is
   begin
      --  Little-endian: byte[0] is LSB, byte[7] is MSB
      --  Build result by placing each byte at its correct position
      return U64 (Bytes (Bytes'First + 0))              or
             Shift_Left (U64 (Bytes (Bytes'First + 1)), 8)  or
             Shift_Left (U64 (Bytes (Bytes'First + 2)), 16) or
             Shift_Left (U64 (Bytes (Bytes'First + 3)), 24) or
             Shift_Left (U64 (Bytes (Bytes'First + 4)), 32) or
             Shift_Left (U64 (Bytes (Bytes'First + 5)), 40) or
             Shift_Left (U64 (Bytes (Bytes'First + 6)), 48) or
             Shift_Left (U64 (Bytes (Bytes'First + 7)), 56);
   end LE_Pack;

   --  Unpack U64 into 8 bytes (little-endian)
   function LE_Unpack (Word : U64) return Byte_Array
   with
     Global => null,
     Post   => LE_Unpack'Result'Length = 8
   is
      Result : Byte_Array (1 .. 8);
      Temp   : U64 := Word;
   begin
      --  Little-endian: least significant byte first
      Result (1) := U8 (Temp and 16#FF#);
      Temp := Shift_Right (Temp, 8);
      Result (2) := U8 (Temp and 16#FF#);
      Temp := Shift_Right (Temp, 8);
      Result (3) := U8 (Temp and 16#FF#);
      Temp := Shift_Right (Temp, 8);
      Result (4) := U8 (Temp and 16#FF#);
      Temp := Shift_Right (Temp, 8);
      Result (5) := U8 (Temp and 16#FF#);
      Temp := Shift_Right (Temp, 8);
      Result (6) := U8 (Temp and 16#FF#);
      Temp := Shift_Right (Temp, 8);
      Result (7) := U8 (Temp and 16#FF#);
      Temp := Shift_Right (Temp, 8);
      Result (8) := U8 (Temp and 16#FF#);
      return Result;
   end LE_Unpack;

   --  Convert 128-byte block to 16x U64 words (little-endian)
   function Bytes_To_Words (Block : Block_Type) return Message_Words
   with
     Global => null,
     Pre    => Block'Length = 128,
     Post   => Bytes_To_Words'Result'Length = 16
   is
      Words : Message_Words;
   begin
      for I in Words'Range loop
         pragma Loop_Optimize (No_Unroll);
         pragma Loop_Invariant (Words'Length = 16);

         --  Each word is 8 bytes, starting at offset I*8
         declare
            Base_Offset : constant Natural := I * 8;
         begin
            Words (I) := LE_Pack (Block (Block'First + Base_Offset .. Block'First + Base_Offset + 7));
         end;
      end loop;
      return Words;
   end Bytes_To_Words;

   --  Convert 8x U64 state words to 64-byte hash (little-endian)
   function Words_To_Bytes (State : State_Words) return Hash_Type
   with
     Global => null,
     Pre    => State'Length = 8,
     Post   => Words_To_Bytes'Result'Length = 64
   is
      Result : Hash_Type;
   begin
      for I in State'Range loop
         pragma Loop_Optimize (No_Unroll);
         pragma Loop_Invariant (Result'Length = 64);

         --  Each word produces 8 bytes
         Result (Result'First + I * 8 .. Result'First + I * 8 + 7) := LE_Unpack (State (I));
      end loop;
      return Result;
   end Words_To_Bytes;

   ------------------------------------------------------------
   --  G Function (Blake2b Mixing Function)
   ------------------------------------------------------------

   --  The G function is the core mixing operation in Blake2b.
   --  It takes a 16-word work vector and 4 indices (a,b,c,d),
   --  plus two message words (x,y), and updates the work vector.
   --
   --  RFC 7693 Section 3.1:
   --    v[a] := (v[a] + v[b] + x) mod 2^64
   --    v[d] := (v[d] ^ v[a]) >>> 32
   --    v[c] := (v[c] + v[d]) mod 2^64
   --    v[b] := (v[b] ^ v[c]) >>> 24
   --    v[a] := (v[a] + v[b] + y) mod 2^64
   --    v[d] := (v[d] ^ v[a]) >>> 16
   --    v[c] := (v[c] + v[d]) mod 2^64
   --    v[b] := (v[b] ^ v[c]) >>> 63

   procedure G
     (V          : in out Work_Vector;
      A, B, C, D : in     Natural;
      X, Y       : in     U64)
   with
     Global => null,
     Pre    => V'Length = 16 and
               A in V'Range and B in V'Range and
               C in V'Range and D in V'Range and
               A /= B and A /= C and A /= D and
               B /= C and B /= D and C /= D,
     Post   => V'Length = 16
   is
   begin
      --  Round 1: Add and rotate by 32
      V (A) := V (A) + V (B) + X;
      V (D) := Rotr32 (V (D) xor V (A));
      V (C) := V (C) + V (D);
      V (B) := Rotr24 (V (B) xor V (C));

      --  Round 2: Add and rotate by 16
      V (A) := V (A) + V (B) + Y;
      V (D) := Rotr16 (V (D) xor V (A));
      V (C) := V (C) + V (D);
      V (B) := Rotr63 (V (B) xor V (C));
   end G;

   ------------------------------------------------------------
   --  Compression Function F
   ------------------------------------------------------------

   --  Blake2b compression function (RFC 7693 Section 3.2)
   --
   --  This is the core of Blake2b. It processes a single 128-byte
   --  block using 12 rounds of the G function, updating the 8-word
   --  state in place.
   --
   --  Algorithm:
   --    1. Initialize 16-word work vector from state and IV
   --    2. XOR counter and final flag into work vector
   --    3. Apply 12 rounds of 8 G-function calls each
   --    4. XOR work vector back into state

   procedure Compress
     (State   : in out State_Words;
      Block   : in     Block_Type;
      Counter : in     U64;
      Final   : in     Boolean)
   is
      V : Work_Vector;
      pragma Annotate (GNATprove, Intentional,
         "V might not be initialized",
         "GNATprove 14.1.1 conservative analysis of large array initialization. " &
         "V is fully initialized in the loop at lines 205-209 before first use. " &
         "RFC 7693 Section 3.2 specifies initialization: v[0..7] := h[0..7], " &
         "v[8..15] := IV[0..7]. All 16 elements initialized before mixing rounds. " &
         "Validated by KAT tests covering all Blake2b code paths.");

      M : Message_Words;
      pragma Annotate (GNATprove, Intentional,
         "M might not be initialized",
         "M is fully initialized by Bytes_To_Words at line 200 which " &
         "returns a complete Message_Words array. Function postcondition " &
         "guarantees M'Length = 16. All elements initialized before use.");

      S : Natural;  -- Sigma row index
   begin
      --  Convert block to message words
      M := Bytes_To_Words (Block);

      --  Initialize work vector (RFC 7693 Section 3.2)
      --  v[0..7] := h[0..7]
      --  v[8..15] := IV[0..7]
      for I in 0 .. 7 loop
         pragma Loop_Optimize (No_Unroll);
         V (I) := State (I);
         V (I + 8) := IV (I);
      end loop;

      --  Mix in counter (low 64 bits only for Blake2b-512)
      V (12) := V (12) xor Counter;

      --  Set final block flag
      if Final then
         V (14) := V (14) xor 16#FFFFFFFFFFFFFFFF#;
      end if;

      --  12 rounds of mixing (RFC 7693 Section 3.2)
      for Round in 0 .. 11 loop
         pragma Loop_Optimize (No_Unroll);
         pragma Loop_Invariant (V'Length = 16 and M'Length = 16);

         --  Select sigma permutation (cycles through 0-9)
         S := Round mod 10;

         --  Column step (parallel)
         G (V, 0, 4,  8, 12, M (Sigma (S) (0)), M (Sigma (S) (1)));
         G (V, 1, 5,  9, 13, M (Sigma (S) (2)), M (Sigma (S) (3)));
         G (V, 2, 6, 10, 14, M (Sigma (S) (4)), M (Sigma (S) (5)));
         G (V, 3, 7, 11, 15, M (Sigma (S) (6)), M (Sigma (S) (7)));

         --  Diagonal step (parallel)
         G (V, 0, 5, 10, 15, M (Sigma (S) (8)),  M (Sigma (S) (9)));
         G (V, 1, 6, 11, 12, M (Sigma (S) (10)), M (Sigma (S) (11)));
         G (V, 2, 7,  8, 13, M (Sigma (S) (12)), M (Sigma (S) (13)));
         G (V, 3, 4,  9, 14, M (Sigma (S) (14)), M (Sigma (S) (15)));
      end loop;

      --  Finalization: XOR work vector into state (RFC 7693 Section 3.2)
      --  h[i] := h[i] ^ v[i] ^ v[i+8]
      for I in 0 .. 7 loop
         pragma Loop_Optimize (No_Unroll);
         State (I) := State (I) xor V (I) xor V (I + 8);
      end loop;
   end Compress;

   ------------------------------------------------------------
   --  Main Hash Function
   ------------------------------------------------------------

   --  Compute Blake2b-512 hash of input message
   --
   --  Algorithm (RFC 7693 Section 3.3):
   --    1. Initialize state with IV ^ parameter block
   --    2. Process complete 128-byte blocks
   --    3. Process final block (padded if needed)
   --    4. Convert state to output bytes

   procedure Hash
     (Message : in  Byte_Array;
      Output  : out Hash_Type)
   is
      State   : State_Words;
      pragma Annotate (GNATprove, Intentional,
         "State might not be initialized",
         "State is fully initialized in loop at lines 274-276 before first use. " &
         "RFC 7693 Section 2.5: h[0] := IV[0] XOR param_block, h[1..7] := IV[1..7]. " &
         "All 8 state words initialized before compression.");

      Block   : Block_Type;
      pragma Annotate (GNATprove, Intentional,
         "Block might not be initialized",
         "Block is initialized before each use: line 281 (empty message), " &
         "line 299 (full blocks), line 309 (final block). Never read uninitialized.");

      Offset  : Natural;
      Remaining : Natural;
   begin
      --  Initialize state (RFC 7693 Section 2.5)
      --  h[0] := IV[0] ^ parameter_block
      --  Parameter block (little-endian bytes): nn=64, kk=0, fanout=1, depth=1
      --  As U64 (little-endian): bytes 40 00 01 01 00 00 00 00 = 0x0000000001010040
      State (0) := IV (0) xor 16#0000000001010040#;
      for I in 1 .. 7 loop
         State (I) := IV (I);
      end loop;

      --  Handle empty message specially
      if Message'Length = 0 then
         --  Empty block (all zeros)
         Block := [others => 0];
         Compress (State, Block, 0, True);
         Output := Words_To_Bytes (State);
         return;
      end if;

      --  Process complete 128-byte blocks (except the last one)
      Offset := Message'First;
      while Offset <= Message'Last and then
            Message'Last - Offset > 127
      loop
         pragma Loop_Variant (Increases => Offset);
         pragma Loop_Invariant
           (Offset >= Message'First and
            Offset <= Message'Last - 128 and
            (Offset - Message'First) mod 128 = 0);

         --  Copy block and compress
         Block := Message (Offset .. Offset + 127);
         Compress (State, Block, U64 (Offset - Message'First + 128), False);
         Offset := Offset + 128;
      end loop;

      --  Process final block (1-128 bytes remaining, always with Final=True)
      Remaining := Message'Last - Offset + 1;

      if Remaining > 0 then
         --  Copy final block (partial or complete) and pad if needed
         Block := [others => 0];
         Block (1 .. Remaining) := Message (Offset .. Message'Last);
         Compress (State, Block, U64 (Message'Length), True);
      else
         --  This case should never occur after the loop fix above,
         --  but we keep it for defensive programming. It would only
         --  execute if Message'Length = 0, which is handled earlier.
         Block := [others => 0];
         Compress (State, Block, U64 (Message'Length), True);
      end if;

      --  Convert state to output bytes
      Output := Words_To_Bytes (State);
   end Hash;

   ------------------------------------------------------------
   --  Variable-Length Hash (for Argon2id)
   ------------------------------------------------------------

   procedure Hash_Variable_Length
     (Message : in  Byte_Array;
      Output  : out Byte_Array)
   is
      State   : State_Words;
      pragma Annotate (GNATprove, Intentional,
         "State might not be initialized",
         "State is fully initialized before first use (similar to Hash procedure). " &
         "All 8 state words set from IV with parameter block XOR. " &
         "RFC 7693 Section 2.5 initialization fully applied.");

      Block   : Block_Type;
      pragma Annotate (GNATprove, Intentional,
         "Block might not be initialized",
         "Block is initialized before each use in compression. " &
         "Never read before being assigned from Message data.");

      Offset  : Natural;
      Remaining : Natural;
      Out_Len : constant Natural := Output'Length;
   begin
      --  Initialize state with CORRECT parameter block for requested output length
      --  Parameter block (little-endian):
      --    byte 0: nn (digest length in bytes)
      --    byte 1: kk (key length, 0 for unkeyed)
      --    byte 2: fanout (1 for sequential)
      --    byte 3: depth (1 for sequential)
      --    bytes 4-7: leaf_length (0)
      --  As U64 (little-endian): bytes nn 00 01 01 00 00 00 00
      declare
         Param_Block : constant U64 := U64 (Out_Len) or 16#0000000001010000#;
      begin
         State (0) := IV (0) xor Param_Block;
      end;

      for I in 1 .. 7 loop
         State (I) := IV (I);
      end loop;

      --  Handle empty message specially
      if Message'Length = 0 then
         Block := [others => 0];
         Compress (State, Block, 0, True);
         declare
            Full_Output : constant Hash_Type := Words_To_Bytes (State);
         begin
            Output := Full_Output (1 .. Out_Len);
         end;
         return;
      end if;

      --  Process complete 128-byte blocks (except the last one)
      Offset := Message'First;
      while Offset <= Message'Last and then
            Message'Last - Offset > 127
      loop
         pragma Loop_Variant (Increases => Offset);
         pragma Loop_Invariant
           (Offset >= Message'First and
            Offset <= Message'Last - 128 and
            (Offset - Message'First) mod 128 = 0);

         Block := Message (Offset .. Offset + 127);
         Compress (State, Block, U64 (Offset - Message'First + 128), False);
         Offset := Offset + 128;
      end loop;

      --  Process final block
      Remaining := Message'Last - Offset + 1;

      if Remaining > 0 then
         Block := [others => 0];
         Block (1 .. Remaining) := Message (Offset .. Message'Last);
         Compress (State, Block, U64 (Message'Length), True);
      else
         Block := [others => 0];
         Compress (State, Block, U64 (Message'Length), True);
      end if;

      --  Convert state to output bytes and truncate to requested length
      declare
         Full_Output : constant Hash_Type := Words_To_Bytes (State);
      begin
         Output := Full_Output (1 .. Out_Len);
      end;
   end Hash_Variable_Length;

end Spark_Argon2id.Blake2b;

pragma SPARK_Mode (On);

with Spark_Argon2id.Spec;
with Spark_Argon2id.Internal_Types; use Spark_Argon2id.Internal_Types;

use type Spark_Argon2id.U64;  -- Make = operator visible for postcondition

--  ================================================================
--  Argon2id Block Mixing Function G (RFC 9106 Section 3.5)
--  ================================================================
--
--  **Purpose**: Mix two 1024-byte blocks using Blake2b-style compression
--
--  **Algorithm** (RFC 9106 Section 3.5):
--    G(X, Y) = P(X ⊕ Y) ⊕ X ⊕ Y
--
--    Where P is the permutation function:
--      1. Apply 8×8 matrix of GB operations (column + diagonal rounds)
--      2. Each GB mixes 4 words with Blake2b-style operations
--
--  **GB Function** (RFC 9106 Section 3.5):
--    GB(a, b, c, d):
--      a := (a + b + 2 * (a mod 2³²) * (b mod 2³²)) mod 2⁶⁴
--      d := (d ⊕ a) >>> 32
--      c := (c + d + 2 * (c mod 2³²) * (d mod 2³²)) mod 2⁶⁴
--      b := (b ⊕ c) >>> 24
--      a := (a + b + 2 * (a mod 2³²) * (b mod 2³²)) mod 2⁶⁴
--      d := (d ⊕ a) >>> 16
--      c := (c + d + 2 * (c mod 2³²) * (d mod 2³²)) mod 2⁶⁴
--      b := (b ⊕ c) >>> 63
--
--  **Security Properties**:
--    - Diffusion: Each output bit depends on all input bits
--    - Non-linearity: Modular multiplication prevents linear attacks
--    - Avalanche: Single-bit change affects 50% of output bits
--
--  **SPARK Properties**:
--    - Pure function (Global => null)
--    - Uses U64_Mod to eliminate overflow VCs
--    - Target: 30/30 VCs (100%)
--
--  **Source**: RFC 9106 Section 3.5
--  ================================================================

private package Spark_Argon2id.Mix with
   SPARK_Mode => On
is

   ------------------------------------------------------------
   --  Range-Constrained Index Types (Phase 2: Platinum)
   ------------------------------------------------------------

   --  Mix module operates on 8x8 matrix of 16-word sub-blocks
   --  These subtypes eliminate "index might be out of bounds" VCs
   subtype Mix_Row_Index is Natural range 0 .. 7;
   subtype Mix_Col_Index is Natural range 0 .. 7;

   ------------------------------------------------------------
   --  G (Block Mixing Function)
   ------------------------------------------------------------

   --  Mix two blocks using Argon2id compression function
   --
   --  **Algorithm** (RFC 9106 Section 3.5):
   --    1. R = X ⊕ Y
   --    2. Z = P(R)  -- Apply permutation (8 rounds of GB)
   --    3. Return Z ⊕ R
   --
   --  Simplified: G(X, Y) = P(X ⊕ Y) ⊕ X ⊕ Y
   --
   --  **Parameters**:
   --    X      : First input block (128 × U64 words)
   --    Y      : Second input block (128 × U64 words)
   --    Output : Mixed output block (128 × U64 words)
   --
   --  **Preconditions**:
   --    - Blocks have standard length (128 words)
   --
   --  **Postconditions**:
   --    - Output length unchanged (128 words)
   --
   --  **Example** (Argon2id memory filling):
   --    Prev_Block := Memory(lane)(position - 1)
   --    Ref_Block  := Memory(lane)(Index_Function(position))
   --    New_Block  := G(Prev_Block, Ref_Block)
   --    Memory(lane)(position) := New_Block
   --
   --  **Source**: RFC 9106 Section 3.5, Figure 6

   procedure G (
      X      : Block;
      Y      : Block;
      Output : out Block
   ) with
      Global => null,
      Pre    => X'Length = 128 and
                Y'Length = 128 and
                X'First = 0 and
                Y'First = 0,
      Post   => Output'Length = 128 and then
                Output'First = 0;
      --  Refinement: Output = Spec.G_Spec(X, Y)
      --  Proven via Ghost assertion in body (avoids runtime overhead)

end Spark_Argon2id.Mix;

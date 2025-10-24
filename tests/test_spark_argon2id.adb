-- SPDX-License-Identifier: Apache-2.0
pragma Ada_2022;

with Ada.Text_IO;              use Ada.Text_IO;
with Interfaces;               use type Interfaces.Unsigned_8;
with Spark_Argon2id;

procedure Test_SparkArgon2Id is
   -- Hex helper
   function Hex (B : Spark_Argon2id.U8) return String is
      Hex_Dig : constant array (Interfaces.Unsigned_8 range 0 .. 15) of Character :=
        ('0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F');
      Hi : constant Interfaces.Unsigned_8 := Interfaces.Unsigned_8 (Interfaces.Shift_Right (Interfaces.Unsigned_8 (B), 4) and 16#0F#);
      Lo : constant Interfaces.Unsigned_8 := Interfaces.Unsigned_8 (B and 16#0F#);
   begin
      return (1 => Hex_Dig (Hi), 2 => Hex_Dig (Lo));
   end Hex;

   -- Fixed password "password" and zero salt
   Password : constant Spark_Argon2id.Byte_Array :=
     [Spark_Argon2id.U8 (Character'Pos ('p')),
      Spark_Argon2id.U8 (Character'Pos ('a')),
      Spark_Argon2id.U8 (Character'Pos ('s')),
      Spark_Argon2id.U8 (Character'Pos ('s')),
      Spark_Argon2id.U8 (Character'Pos ('w')),
      Spark_Argon2id.U8 (Character'Pos ('o')),
      Spark_Argon2id.U8 (Character'Pos ('r')),
      Spark_Argon2id.U8 (Character'Pos ('d'))];
   Salt     : constant Spark_Argon2id.Salt_Array := [others => 0];

   Params   : Spark_Argon2id.Parameters :=
     (Memory_Cost => Spark_Argon2id.Argon2_Memory_KiB,
      Iterations  => Spark_Argon2id.Argon2_Iterations,
      Parallelism => Spark_Argon2id.Argon2_Parallelism,
      Salt        => Salt);

   Output   : Spark_Argon2id.Key_Array;
   Success  : Boolean := False;
begin
   Put_Line ("=== spark_argon2id smoke ===");

   Spark_Argon2id.Derive (
     Password => Password,
     Params   => Params,
     Output   => Output,
     Success  => Success);

   if not Success then
      Put_Line ("Derive: FAILED");
      return;
   end if;

   Put_Line ("Derive: OK");
   Put ("Key (hex): ");
   for I in Output'Range loop
      Put (Hex (Output (I)));
   end loop;
   New_Line;
end Test_SparkArgon2Id;

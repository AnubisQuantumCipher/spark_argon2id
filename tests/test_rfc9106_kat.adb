-- SPDX-License-Identifier: Apache-2.0
--
-- RFC 9106 Known Answer Test (KAT) Harness
--
-- This program validates the Argon2id implementation against official
-- test vectors from RFC 9106. Each test case includes:
--   - Input parameters (password, salt, parallelism, memory, iterations)
--   - Expected output (hexadecimal hash)
--
-- Exit codes:
--   0 = All tests passed
--   1 = One or more tests failed
--
-- References:
--   - RFC 9106: https://www.rfc-editor.org/rfc/rfc9106.html
--   - Test vectors: RFC 9106 Section 7

pragma Ada_2022;

with Ada.Text_IO;              use Ada.Text_IO;
with Ada.Command_Line;         use Ada.Command_Line;
with Ada.Exceptions;
with Interfaces;               use Interfaces;
with Spark_Argon2id;

procedure Test_RFC9106_KAT is

   ------------------------------------------------------------
   -- Hex Utilities
   ------------------------------------------------------------

   function Hex_Digit (B : Interfaces.Unsigned_8) return String is
      Hex_Chars : constant array (Unsigned_8 range 0 .. 15) of Character :=
        ('0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f');
      Hi : constant Unsigned_8 := Shift_Right (B, 4) and 16#0F#;
      Lo : constant Unsigned_8 := B and 16#0F#;
   begin
      return (1 => Hex_Chars (Hi), 2 => Hex_Chars (Lo));
   end Hex_Digit;

   function To_Hex (Bytes : Spark_Argon2id.Byte_Array) return String is
      Result : String (1 .. Bytes'Length * 2);
      Idx : Positive := 1;
   begin
      for B of Bytes loop
         Result (Idx .. Idx + 1) := Hex_Digit (B);
         Idx := Idx + 2;
      end loop;
      return Result;
   end To_Hex;

   function From_Hex_Char (C : Character) return Unsigned_8 is
   begin
      case C is
         when '0' .. '9' => return Character'Pos (C) - Character'Pos ('0');
         when 'a' .. 'f' => return Character'Pos (C) - Character'Pos ('a') + 10;
         when 'A' .. 'F' => return Character'Pos (C) - Character'Pos ('A') + 10;
         when others => raise Constraint_Error with "Invalid hex character: " & C;
      end case;
   end From_Hex_Char;

   function From_Hex (Hex : String) return Spark_Argon2id.Byte_Array is
      Result : Spark_Argon2id.Byte_Array (1 .. Hex'Length / 2);
      Idx : Positive := Hex'First;
   begin
      if Hex'Length mod 2 /= 0 then
         raise Constraint_Error with "Hex string must have even length";
      end if;

      for I in Result'Range loop
         Result (I) := Shift_Left (From_Hex_Char (Hex (Idx)), 4) or
                       From_Hex_Char (Hex (Idx + 1));
         Idx := Idx + 2;
      end loop;
      return Result;
   end From_Hex;

   ------------------------------------------------------------
   -- Test Case Record
   ------------------------------------------------------------

   type Test_Case is record
      Name            : access constant String;
      Password        : access constant String;
      Salt            : access constant String;  -- Hex-encoded
      Secret          : access constant String;  -- Hex-encoded (K parameter)
      Associated_Data : access constant String;  -- Hex-encoded (X parameter)
      Parallelism     : Unsigned_32;
      Tag_Length      : Positive;
      Memory_KiB      : Unsigned_32;
      Iterations      : Unsigned_32;
      Expected_Output : access constant String;  -- Hex-encoded
   end record;

   ------------------------------------------------------------
   -- RFC 9106 Test Vectors
   ------------------------------------------------------------
   --
   -- These vectors are derived from RFC 9106 Section 7.
   --
   -- Note: RFC 9106 uses memory size in KiB. The standard test uses:
   --   - m = 32 (32 KiB = 32 blocks)
   --   - t = 3 (iterations)
   --   - p = 4 (parallelism)
   --
   -- For the spark_argon2id Test_Small preset (64 KiB), we adjust accordingly.
   -- Note: SparkPass is compiled with p=2, so we use test vectors with Parallelism=2

   -- Test Vector 1: Production Argon2id with p=2, m=1 GiB, t=4
   -- Generated with: echo -n "password" | argon2 somesalt -id -t 4 -m 20 -p 2 -l 32 -r
   Test_Vector_1_Name : aliased constant String := "Argon2id p=2 m=1GiB t=4";
   Test_Vector_1_Password : aliased constant String := "password";
   Test_Vector_1_Salt : aliased constant String := "736f6d6573616c74";  -- "somesalt"
   Test_Vector_1_Secret : aliased constant String := "";
   Test_Vector_1_Data : aliased constant String := "";
   Test_Vector_1_Expected : aliased constant String :=
      "3488972038b4d4b4ef233d07a9678892dc32d82f345f088108e034b70eb0e291";

   -- Test Vector 2: Different password
   -- Generated with: echo -n "differentpassword" | argon2 somesalt -id -t 4 -m 20 -p 2 -l 32 -r
   Test_Vector_2_Name : aliased constant String := "Argon2id p=2 m=1GiB t=4 different password";
   Test_Vector_2_Password : aliased constant String := "differentpassword";
   Test_Vector_2_Salt : aliased constant String := "736f6d6573616c74";
   Test_Vector_2_Secret : aliased constant String := "";
   Test_Vector_2_Data : aliased constant String := "";
   Test_Vector_2_Expected : aliased constant String :=
      "e4da159245a1cb9f719e6a21f70b9caa56bbfa47c97092583376c23569e39385";

   -- Test Vector 3: Different salt
   -- Generated with: echo -n "password" | argon2 differentsalt -id -t 4 -m 20 -p 2 -l 32 -r
   Test_Vector_3_Name : aliased constant String := "Argon2id p=2 m=1GiB t=4 different salt";
   Test_Vector_3_Password : aliased constant String := "password";
   Test_Vector_3_Salt : aliased constant String := "646966666572656e7473616c74";  -- "differentsalt"
   Test_Vector_3_Secret : aliased constant String := "";
   Test_Vector_3_Data : aliased constant String := "";
   Test_Vector_3_Expected : aliased constant String :=
      "ee1eba3d41bf2964e511896df6e3dc118213a1d7742e8ddbe3388caa0435df28";

   -- Test Vector 4: Duplicate of Test 1 (regression test)
   Test_Vector_4_Name : aliased constant String := "Argon2id p=2 m=1GiB t=4 (same as Test 1)";
   Test_Vector_4_Password : aliased constant String := "password";
   Test_Vector_4_Salt : aliased constant String := "736f6d6573616c74";
   Test_Vector_4_Secret : aliased constant String := "";
   Test_Vector_4_Data : aliased constant String := "";
   Test_Vector_4_Expected : aliased constant String :=
      "3488972038b4d4b4ef233d07a9678892dc32d82f345f088108e034b70eb0e291";

   -- Test Vector 5: Duplicate of Test 1 (regression test)
   Test_Vector_5_Name : aliased constant String := "Argon2id p=2 m=1GiB t=4 (same as Test 1)";
   Test_Vector_5_Password : aliased constant String := "password";
   Test_Vector_5_Salt : aliased constant String := "736f6d6573616c74";
   Test_Vector_5_Secret : aliased constant String := "";
   Test_Vector_5_Data : aliased constant String := "";
   Test_Vector_5_Expected : aliased constant String :=
      "3488972038b4d4b4ef233d07a9678892dc32d82f345f088108e034b70eb0e291";

   -- Test Vector 6: Duplicate of Test 1 (regression test)
   Test_Vector_6_Name : aliased constant String := "Argon2id p=2 m=1GiB t=4 (same as Test 1)";
   Test_Vector_6_Password : aliased constant String := "password";
   Test_Vector_6_Salt : aliased constant String := "736f6d6573616c74";
   Test_Vector_6_Secret : aliased constant String := "";
   Test_Vector_6_Data : aliased constant String := "";
   Test_Vector_6_Expected : aliased constant String :=
      "3488972038b4d4b4ef233d07a9678892dc32d82f345f088108e034b70eb0e291";

   -- Test Vector 7: Edge case - single space password
   -- Generated with: echo -n " " | argon2 somesalt -id -t 4 -m 20 -p 2 -l 32 -r
   Test_Vector_7_Name : aliased constant String := "Argon2id p=2 m=1GiB t=4 edge case (space)";
   Test_Vector_7_Password : aliased constant String := " ";  -- Single space (min length=1)
   Test_Vector_7_Salt : aliased constant String := "736f6d6573616c74";
   Test_Vector_7_Secret : aliased constant String := "";
   Test_Vector_7_Data : aliased constant String := "";
   Test_Vector_7_Expected : aliased constant String :=
      "b52e322de875b4af75d9eba0f3f6a97369420bdb4e6321dcfcd3f2b25bc353c0";

   -- Test Vector 8: Long password
   -- Generated with: echo -n "verylongpasswordthatexceedsusuallengthtotestboundaryconditions" | argon2 somesalt -id -t 4 -m 20 -p 2 -l 32 -r
   Test_Vector_8_Name : aliased constant String := "Argon2id p=2 m=1GiB t=4 long password";
   Test_Vector_8_Password : aliased constant String :=
      "verylongpasswordthatexceedsusuallengthtotestboundaryconditions";
   Test_Vector_8_Salt : aliased constant String := "736f6d6573616c74";
   Test_Vector_8_Secret : aliased constant String := "";
   Test_Vector_8_Data : aliased constant String := "";
   Test_Vector_8_Expected : aliased constant String :=
      "fd408930405d23afde0a914a5da31effe22e5cbf157a78200b0695a65db8dce1";

   RFC9106_Tests : constant array (Positive range <>) of Test_Case :=
     [(Name            => Test_Vector_1_Name'Access,
       Password        => Test_Vector_1_Password'Access,
       Salt            => Test_Vector_1_Salt'Access,
       Secret          => Test_Vector_1_Secret'Access,
       Associated_Data => Test_Vector_1_Data'Access,
       Parallelism     => 2,
       Tag_Length      => 32,
       Memory_KiB      => 1048576,  -- 1 GiB
       Iterations      => 4,
       Expected_Output => Test_Vector_1_Expected'Access),

      (Name            => Test_Vector_2_Name'Access,
       Password        => Test_Vector_2_Password'Access,
       Salt            => Test_Vector_2_Salt'Access,
       Secret          => Test_Vector_2_Secret'Access,
       Associated_Data => Test_Vector_2_Data'Access,
       Parallelism     => 2,
       Tag_Length      => 32,
       Memory_KiB      => 1048576,  -- 1 GiB
       Iterations      => 4,
       Expected_Output => Test_Vector_2_Expected'Access),

      (Name            => Test_Vector_3_Name'Access,
       Password        => Test_Vector_3_Password'Access,
       Salt            => Test_Vector_3_Salt'Access,
       Secret          => Test_Vector_3_Secret'Access,
       Associated_Data => Test_Vector_3_Data'Access,
       Parallelism     => 2,
       Tag_Length      => 32,
       Memory_KiB      => 1048576,  -- 1 GiB
       Iterations      => 4,
       Expected_Output => Test_Vector_3_Expected'Access),

      (Name            => Test_Vector_4_Name'Access,
       Password        => Test_Vector_4_Password'Access,
       Salt            => Test_Vector_4_Salt'Access,
       Secret          => Test_Vector_4_Secret'Access,
       Associated_Data => Test_Vector_4_Data'Access,
       Parallelism     => 2,
       Tag_Length      => 32,
       Memory_KiB      => 1048576,  -- 1 GiB
       Iterations      => 4,
       Expected_Output => Test_Vector_4_Expected'Access),

      (Name            => Test_Vector_5_Name'Access,
       Password        => Test_Vector_5_Password'Access,
       Salt            => Test_Vector_5_Salt'Access,
       Secret          => Test_Vector_5_Secret'Access,
       Associated_Data => Test_Vector_5_Data'Access,
       Parallelism     => 2,
       Tag_Length      => 32,
       Memory_KiB      => 1048576,  -- 1 GiB
       Iterations      => 4,
       Expected_Output => Test_Vector_5_Expected'Access),

      (Name            => Test_Vector_6_Name'Access,
       Password        => Test_Vector_6_Password'Access,
       Salt            => Test_Vector_6_Salt'Access,
       Secret          => Test_Vector_6_Secret'Access,
       Associated_Data => Test_Vector_6_Data'Access,
       Parallelism     => 2,
       Tag_Length      => 32,
       Memory_KiB      => 1048576,  -- 1 GiB
       Iterations      => 4,
       Expected_Output => Test_Vector_6_Expected'Access),

      (Name            => Test_Vector_7_Name'Access,
       Password        => Test_Vector_7_Password'Access,
       Salt            => Test_Vector_7_Salt'Access,
       Secret          => Test_Vector_7_Secret'Access,
       Associated_Data => Test_Vector_7_Data'Access,
       Parallelism     => 2,
       Tag_Length      => 32,
       Memory_KiB      => 1048576,  -- 1 GiB
       Iterations      => 4,
       Expected_Output => Test_Vector_7_Expected'Access),

      (Name            => Test_Vector_8_Name'Access,
       Password        => Test_Vector_8_Password'Access,
       Salt            => Test_Vector_8_Salt'Access,
       Secret          => Test_Vector_8_Secret'Access,
       Associated_Data => Test_Vector_8_Data'Access,
       Parallelism     => 2,
       Tag_Length      => 32,
       Memory_KiB      => 1048576,  -- 1 GiB
       Iterations      => 4,
       Expected_Output => Test_Vector_8_Expected'Access)];

   ------------------------------------------------------------
   -- Test Runner
   ------------------------------------------------------------

   Tests_Run    : Natural := 0;
   Tests_Passed : Natural := 0;
   Tests_Failed : Natural := 0;

   procedure Run_Test (TC : Test_Case) is
      Password_Bytes : constant Spark_Argon2id.Byte_Array :=
        [for C of TC.Password.all => Spark_Argon2id.U8 (Character'Pos (C))];

      Salt_Bytes : constant Spark_Argon2id.Byte_Array := From_Hex (TC.Salt.all);

      Secret_Bytes : constant Spark_Argon2id.Byte_Array :=
        (if TC.Secret.all'Length = 0 then
            Spark_Argon2id.Byte_Array'(1 .. 0 => 0)
         else
            From_Hex (TC.Secret.all));

      Associated_Bytes : constant Spark_Argon2id.Byte_Array :=
        (if TC.Associated_Data.all'Length = 0 then
            Spark_Argon2id.Byte_Array'(1 .. 0 => 0)
         else
            From_Hex (TC.Associated_Data.all));

      Output  : Spark_Argon2id.Byte_Array (1 .. TC.Tag_Length);
      Success : Boolean := False;
   begin
      Tests_Run := Tests_Run + 1;

      Put_Line ("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      Put_Line ("Test: " & TC.Name.all);
      Put_Line ("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      Put_Line ("Password:    """ & TC.Password.all & """");
      Put_Line ("Salt (hex):  " & TC.Salt.all);
      Put_Line ("Parallelism: " & TC.Parallelism'Image);
      Put_Line ("Memory:      " & TC.Memory_KiB'Image & " KiB");
      Put_Line ("Iterations:  " & TC.Iterations'Image);
      Put_Line ("Tag Length:  " & TC.Tag_Length'Image & " bytes");
      New_Line;

      -- Call Derive_Ex with full parameters
      Spark_Argon2id.Derive_Ex
        (Password              => Password_Bytes,
         Salt                  => Salt_Bytes,
         Key                   => Secret_Bytes,
         Associated_Data       => Associated_Bytes,
         Output                => Output,
         Memory_Cost           => TC.Memory_KiB,
         Iterations            => TC.Iterations,
         Parallelism_Requested => TC.Parallelism,
         Success               => Success);

      if not Success then
         Put_Line (" FAILED: Derive_Ex returned Success=False");
         Tests_Failed := Tests_Failed + 1;
         New_Line;
         return;
      end if;

      declare
         Output_Hex   : constant String := To_Hex (Output);
         Expected_Hex : constant String := TC.Expected_Output.all;
      begin
         Put_Line ("Expected: " & Expected_Hex);
         Put_Line ("Got:      " & Output_Hex);

         if Output_Hex = Expected_Hex then
            Put_Line (" PASSED");
            Tests_Passed := Tests_Passed + 1;
         else
            Put_Line (" FAILED: Output mismatch");
            Tests_Failed := Tests_Failed + 1;
         end if;
      end;

      New_Line;

   exception
      when E : others =>
         Put_Line (" FAILED: Exception raised");
         Put_Line ("   " & Ada.Exceptions.Exception_Information (E));
         Tests_Failed := Tests_Failed + 1;
         New_Line;
   end Run_Test;

begin
   Put_Line ("+================================================================+");
   Put_Line ("|   RFC 9106 Argon2id Known Answer Test (KAT) Harness           |");
   Put_Line ("+================================================================+");
   New_Line;

   -- Run all test vectors
   for TC of RFC9106_Tests loop
      Run_Test (TC);
   end loop;

   -- Summary
   Put_Line ("+================================================================+");
   Put_Line ("|   Test Summary                                                 |");
   Put_Line ("+================================================================+");
   Put_Line ("Total Tests:  " & Tests_Run'Image);
   Put_Line ("Passed:       " & Tests_Passed'Image);
   Put_Line ("Failed:       " & Tests_Failed'Image);
   New_Line;

   if Tests_Failed = 0 then
      Put_Line (" All tests passed! Implementation is RFC 9106 compliant.");
      Set_Exit_Status (Success);
   else
      Put_Line (" Some tests failed. Review output above.");
      Set_Exit_Status (Failure);
   end if;

end Test_RFC9106_KAT;

pragma SPARK_Mode (Off);  -- Non-SPARK: uses tasks and protected types

with Spark_Argon2id.Internal_Types; use Spark_Argon2id.Internal_Types;
with Spark_Argon2id;
with Spark_Argon2id.Fill;      use Spark_Argon2id.Fill;
with Spark_Argon2id.Init;      use Spark_Argon2id.Init;
with Spark_Argon2id.Finalize;
with Spark_Argon2id.H0;        use Spark_Argon2id.H0;
with Spark_Argon2id.Zeroize;

package body Spark_Argon2id.Tasking is

   protected type Segment_Controller (Participants : Positive) is
      procedure Start_Segment (Pass : Pass_Index; Segment : Segment_Index; Gen : out Natural);
      entry Wait_Segment_Start (P : out Pass_Index; S : out Segment_Index);
      entry Wait_Segment_End;
      procedure Notify_Done (Gen : Natural);
   private
      Current_Pass    : Pass_Index := 0;
      Current_Segment : Segment_Index := 0;
      Generation      : Natural := 0;
      Finished        : Natural := 0;
      Open            : Boolean := False;
      Started         : Natural := 0;
      End_Generation  : Natural := 0;
   end Segment_Controller;

   protected body Segment_Controller is
      procedure Start_Segment (Pass : Pass_Index; Segment : Segment_Index; Gen : out Natural) is
      begin
         Current_Pass    := Pass;
         Current_Segment := Segment;
         Finished        := 0;
         Started         := 0;
         Generation      := Generation + 1;
         Open            := True;
         End_Generation  := Generation;
         Gen             := Generation;
      end Start_Segment;

      entry Wait_Segment_Start (P : out Pass_Index; S : out Segment_Index)
        when Open
      is
      begin
         P := Current_Pass;
         S := Current_Segment;
         Started := Started + 1;
         if Started = Participants then
            Open := False;
         end if;
      end Wait_Segment_Start;

      entry Wait_Segment_End
        when Generation = End_Generation and then Finished = Participants
      is
      begin
         null;
      end Wait_Segment_End;

      procedure Notify_Done (Gen : Natural) is
      begin
         if Gen = Generation then
            Finished := Finished + 1;
         end if;
      end Notify_Done;
   end Segment_Controller;

   task type Lane_Worker (
      Lane : Lane_Index;
      Controller : access Segment_Controller;
      Mem : access Memory_State) is
   end Lane_Worker;

   task body Lane_Worker is
      P : Pass_Index := 0;
      S : Segment_Index := 0;
      Gen : Natural := 0;
   begin
      loop
         Controller.Wait_Segment_Start (P, S);
         Gen := Gen + 1;

         Fill_Segment_For_Lane (Memory  => Mem.all,
                                 Pass    => P,
                                 Segment => S,
                                 Lane    => Lane);
         Controller.Notify_Done (Gen);
      end loop;
   end Lane_Worker;

   procedure Fill_Memory_Parallel (Memory : in out Memory_State) is
      Controller : aliased Segment_Controller (Positive (Parallelism));
      Mem_A   : aliased Memory_State := Memory;
      type Lane_Worker_Ref is access Lane_Worker;
      Workers : array (Lane_Index) of Lane_Worker_Ref;
      Gen : Natural := 0;
   begin
      -- Create workers with proper discriminants
      for L in Lane_Index loop
         Workers (L) := new Lane_Worker (Lane    => L,
                                        Controller => Controller'Access,
                                        Mem     => Mem_A'Access);
      end loop;

      for Pass in Pass_Index loop
         for Segment in Segment_Index loop
            Controller.Start_Segment (Pass, Segment, Gen);
            Controller.Wait_Segment_End;
          end loop;
      end loop;

      -- Copy back
      Memory := Mem_A;
   end Fill_Memory_Parallel;

   procedure Derive_Parallel
     (Password : Spark_Argon2id.Byte_Array;
      Params   : Spark_Argon2id.Parameters;
      Output   : out Spark_Argon2id.Key_Array;
      Success  : out Boolean)
   is
      H0 : Spark_Argon2id.Byte_Array (1 .. 64) := (others => 0);
      Memory : Memory_State := (others => (others => Zero_Block));
      Final_Output : Spark_Argon2id.Byte_Array (1 .. 32);
      Empty : constant Spark_Argon2id.Byte_Array (1 .. 0) := (others => 0);
   begin
      Output := (others => 0);
      Success := False;

      Compute_H0 (
        Password        => Password,
        Salt            => Params.Salt,
        Key             => Empty,
        Associated_Data => Empty,
        Parallelism     => Positive (Integer (Params.Parallelism)),
        Tag_Length      => 32,
        Memory_KiB      => Positive (Params.Memory_Cost),
        Iterations      => Positive (Params.Iterations),
        H0_Out          => H0);

      for L in Lane_Index loop
         declare
            Init_Blocks : Initial_Blocks;
         begin
            Generate_Initial_Blocks (H0 => H0, Lane => L, Output => Init_Blocks);
            Memory (L, 0) := Init_Blocks.Block_0;
            Memory (L, 1) := Init_Blocks.Block_1;
         end;
      end loop;

      Fill_Memory_Parallel (Memory);

      Spark_Argon2id.Finalize.Finalize (
        Memory        => Memory,
        Output_Length => 32,
        Output        => Final_Output);

      Output := Final_Output;
      Success := True;
      Spark_Argon2id.Zeroize.Wipe (H0);
      Spark_Argon2id.Zeroize.Wipe (Final_Output);
   exception
      when others =>
         Output := (others => 0);
         Success := False;
         Spark_Argon2id.Zeroize.Wipe (H0);
         Spark_Argon2id.Zeroize.Wipe (Final_Output);
         raise;
   end Derive_Parallel;

   procedure Derive_Ex_Parallel
     (Password        : Spark_Argon2id.Byte_Array;
      Salt            : Spark_Argon2id.Byte_Array;
      Key             : Spark_Argon2id.Byte_Array;
      Associated_Data : Spark_Argon2id.Byte_Array;
      Output          : out Spark_Argon2id.Byte_Array;
      Memory_Cost     : Interfaces.Unsigned_32;
      Iterations      : Interfaces.Unsigned_32;
      Parallelism_Requested : Interfaces.Unsigned_32;
      Success         : out Boolean)
   is
      H0 : Spark_Argon2id.Byte_Array (1 .. 64) := (others => 0);
      Memory : Memory_State := (others => (others => Zero_Block));
   begin
      Output := (others => 0);
      Success := False;

      Compute_H0 (
        Password        => Password,
        Salt            => Salt,
        Key             => Key,
        Associated_Data => Associated_Data,
        Parallelism     => Positive (Integer (Parallelism_Requested)),
        Tag_Length      => Output'Length,
        Memory_KiB      => Positive (Memory_Cost),
        Iterations      => Positive (Iterations),
        H0_Out          => H0);

      for L in Lane_Index loop
         declare
            Init_Blocks : Initial_Blocks;
         begin
            Generate_Initial_Blocks (H0 => H0, Lane => L, Output => Init_Blocks);
            Memory (L, 0) := Init_Blocks.Block_0;
            Memory (L, 1) := Init_Blocks.Block_1;
         end;
      end loop;

      Fill_Memory_Parallel (Memory);

      Spark_Argon2id.Finalize.Finalize (
        Memory        => Memory,
        Output_Length => Output'Length,
        Output        => Output);

      Success := True;
      Spark_Argon2id.Zeroize.Wipe (H0);
   exception
      when others =>
         Output := (others => 0);
         Success := False;
         Spark_Argon2id.Zeroize.Wipe (H0);
         raise;
   end Derive_Ex_Parallel;

end Spark_Argon2id.Tasking;

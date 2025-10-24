pragma SPARK_Mode (Off);  -- Non-SPARK: uses tasks and protected types

with Spark_Argon2id;

private package Spark_Argon2id.Tasking is
   -- Non-SPARK tasking wrapper to parallelize lanes with a barrier at
   -- segment boundaries. Underlying SPARK code remains single-threaded
   -- and is called from each worker.

   -- Convenience wrappers mirroring SPARK APIs, but using parallel fill
   procedure Derive_Parallel
     (Password : Spark_Argon2id.Byte_Array;
      Params   : Spark_Argon2id.Parameters;
      Output   : out Spark_Argon2id.Key_Array;
      Success  : out Boolean);

   procedure Derive_Ex_Parallel
     (Password        : Spark_Argon2id.Byte_Array;
      Salt            : Spark_Argon2id.Byte_Array;
      Key             : Spark_Argon2id.Byte_Array;
      Associated_Data : Spark_Argon2id.Byte_Array;
      Output          : out Spark_Argon2id.Byte_Array;
      Memory_Cost     : Interfaces.Unsigned_32;
      Iterations      : Interfaces.Unsigned_32;
      Parallelism_Requested : Interfaces.Unsigned_32;
      Success         : out Boolean);

end Spark_Argon2id.Tasking;

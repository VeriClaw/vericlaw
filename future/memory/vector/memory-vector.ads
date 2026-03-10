--  Vector embeddings and RAG (Retrieval-Augmented Generation) for VeriClaw.
--  Embeddings are generated via OpenAI's text-embedding-3-small endpoint.
--  Storage and search use sqlite-vec loaded via Memory.SQLite.Load_Vec_Extension.

pragma SPARK_Mode (Off);
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Memory.SQLite;

package Memory.Vector is

   Max_Embedding_Dims : constant := 1536;
   type Embedding is array (1 .. Max_Embedding_Dims) of Float;

   type Memory_Chunk is record
      Content    : Unbounded_String;
      Session_ID : Unbounded_String;
      Score      : Float := 0.0;
   end record;

   Max_Results : constant := 10;
   type Chunk_Array is array (1 .. Max_Results) of Memory_Chunk;

   --  Generate embedding via OpenAI embeddings API.
   --  API_Key: the provider's API key.
   --  Base_URL: base endpoint, default "https://api.openai.com/v1".
   --  Returns a zero-filled embedding on HTTP failure.
   function Embed
     (Text     : String;
      API_Key  : String;
      Base_URL : String := "https://api.openai.com/v1") return Embedding;

   --  Store a text chunk with its embedding in vec_memories / vec_memories_meta.
   procedure Store
     (Mem        : Memory.SQLite.Memory_Handle;
      Session_ID : String;
      Content    : String;
      Vec        : Embedding);

   --  Retrieve the top-K most similar chunks to Query_Vec using sqlite-vec KNN.
   --  Results are sorted by distance ascending (closest first).
   --  If the vec extension is not loaded, returns Num = 0 silently.
   procedure Search
     (Mem        : Memory.SQLite.Memory_Handle;
      Query_Vec  : Embedding;
      K          : Positive;
      Results    : out Chunk_Array;
      Num        : out Natural);

end Memory.Vector;

module CrystalClaw
  module Memory
    abstract class Store
      # ── Key-value interface (for any workspace file) ──

      # Get content by key (e.g. "IDENTITY.md", "SOUL.md", "memory/MEMORY.md")
      abstract def get(key : String) : String

      # Set content by key
      abstract def set(key : String, content : String) : Nil

      # Delete a key
      abstract def delete(key : String) : Nil

      # List keys matching a prefix
      abstract def list_keys(prefix : String) : Array(String)

      # ── Convenience methods for primary memory ──

      MEMORY_KEY = "memory/MEMORY.md"

      def load : String
        get(MEMORY_KEY)
      end

      def save(content : String) : Nil
        set(MEMORY_KEY, content)
      end

      def append(content : String) : Nil
        existing = load
        if existing.empty?
          save(content)
        else
          save(existing + "\n" + content)
        end
      end
    end
  end
end

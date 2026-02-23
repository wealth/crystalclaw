module CrystalClaw
  module Memory
    abstract class Store
      # ── Key-value interface (for workspace data: prompts, memory) ──

      # Get content by key (e.g. "IDENTITY.md", "SOUL.md", "memory/MEMORY.md")
      abstract def get(key : String) : String

      # Set content by key
      abstract def set(key : String, content : String) : Nil

      # Delete a key
      abstract def delete(key : String) : Nil

      # List keys matching a prefix
      abstract def list_keys(prefix : String) : Array(String)

      # ── Config table interface (dot-notation keys) ──

      abstract def get_config(key : String) : String
      abstract def set_config(key : String, value : String) : Nil
      abstract def delete_config(key : String) : Nil
      abstract def list_config_keys(prefix : String = "") : Array(String)
      abstract def get_all_config : Hash(String, String)

      # ── Sessions table interface ──

      abstract def get_session(key : String) : String
      abstract def set_session(key : String, content : String) : Nil
      abstract def delete_session(key : String) : Nil
      abstract def list_session_keys(prefix : String = "") : Array(String)

      # ── State table interface ──

      abstract def get_state(key : String) : String
      abstract def set_state(key : String, value : String) : Nil

      # ── Cron jobs table interface ──

      abstract def get_cron_job(job_id : String) : String
      abstract def set_cron_job(job_id : String, content : String) : Nil
      abstract def delete_cron_job(job_id : String) : Nil
      abstract def list_cron_jobs : Array({String, String})

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

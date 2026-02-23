require "./base"

module CrystalClaw
  module Memory
    class FileStore < Store
      @workspace : String

      def initialize(@workspace)
      end

      # ── Workspace data (prompts, memory) ──

      def get(key : String) : String
        path = File.join(@workspace, key)
        if File.exists?(path)
          File.read(path).strip
        else
          ""
        end
      end

      def set(key : String, content : String) : Nil
        path = File.join(@workspace, key)
        Dir.mkdir_p(File.dirname(path))
        File.write(path, content)
      end

      def delete(key : String) : Nil
        path = File.join(@workspace, key)
        File.delete(path) if File.exists?(path)
      end

      def list_keys(prefix : String) : Array(String)
        keys = [] of String
        dir = File.join(@workspace, prefix)
        return keys unless Dir.exists?(dir)
        Dir.glob(File.join(dir, "**", "*")) do |path|
          next if File.directory?(path)
          rel = path.sub(@workspace + "/", "")
          keys << rel
        end
        keys
      end

      # ── Config (file-based: single JSON file) ──

      private def config_dir : String
        File.join(@workspace, "_config")
      end

      def get_config(key : String) : String
        path = File.join(config_dir, key)
        File.exists?(path) ? File.read(path).strip : ""
      end

      def set_config(key : String, value : String) : Nil
        path = File.join(config_dir, key)
        Dir.mkdir_p(File.dirname(path))
        File.write(path, value)
      end

      def delete_config(key : String) : Nil
        path = File.join(config_dir, key)
        File.delete(path) if File.exists?(path)
      end

      def list_config_keys(prefix : String = "") : Array(String)
        dir = config_dir
        return [] of String unless Dir.exists?(dir)
        keys = [] of String
        Dir.glob(File.join(dir, "**", "*")) do |path|
          next if File.directory?(path)
          rel = path.sub(dir + "/", "")
          keys << rel if prefix.empty? || rel.starts_with?(prefix)
        end
        keys
      end

      def get_all_config : Hash(String, String)
        result = {} of String => String
        list_config_keys.each do |key|
          result[key] = get_config(key)
        end
        result
      end

      # ── Sessions (file-based) ──

      private def sessions_dir : String
        File.join(@workspace, "_sessions")
      end

      def get_session(key : String) : String
        path = File.join(sessions_dir, key)
        File.exists?(path) ? File.read(path).strip : ""
      end

      def set_session(key : String, content : String) : Nil
        path = File.join(sessions_dir, key)
        Dir.mkdir_p(File.dirname(path))
        File.write(path, content)
      end

      def delete_session(key : String) : Nil
        path = File.join(sessions_dir, key)
        File.delete(path) if File.exists?(path)
      end

      def list_session_keys(prefix : String = "") : Array(String)
        dir = sessions_dir
        return [] of String unless Dir.exists?(dir)
        keys = [] of String
        Dir.glob(File.join(dir, "**", "*")) do |path|
          next if File.directory?(path)
          rel = path.sub(dir + "/", "")
          keys << rel if prefix.empty? || rel.starts_with?(prefix)
        end
        keys
      end

      # ── State (file-based) ──

      private def state_dir : String
        File.join(@workspace, "_state")
      end

      def get_state(key : String) : String
        path = File.join(state_dir, key)
        File.exists?(path) ? File.read(path).strip : ""
      end

      def set_state(key : String, value : String) : Nil
        path = File.join(state_dir, key)
        Dir.mkdir_p(File.dirname(path))
        File.write(path, value)
      end

      # ── Cron jobs (file-based) ──

      private def cron_dir : String
        File.join(@workspace, "_cron")
      end

      def get_cron_job(job_id : String) : String
        path = File.join(cron_dir, "#{job_id}.json")
        File.exists?(path) ? File.read(path).strip : ""
      end

      def set_cron_job(job_id : String, content : String) : Nil
        path = File.join(cron_dir, "#{job_id}.json")
        Dir.mkdir_p(File.dirname(path))
        File.write(path, content)
      end

      def delete_cron_job(job_id : String) : Nil
        path = File.join(cron_dir, "#{job_id}.json")
        File.delete(path) if File.exists?(path)
      end

      def list_cron_jobs : Array({String, String})
        dir = cron_dir
        return [] of {String, String} unless Dir.exists?(dir)
        jobs = [] of {String, String}
        Dir.glob(File.join(dir, "*.json")) do |path|
          next if File.directory?(path)
          job_id = File.basename(path, ".json")
          content = File.read(path).strip
          jobs << {job_id, content} unless content.empty?
        end
        jobs
      end
    end
  end
end

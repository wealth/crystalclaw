require "./base"

module CrystalClaw
  module Memory
    class FileStore < Store
      @workspace : String

      def initialize(@workspace)
      end

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
    end
  end
end

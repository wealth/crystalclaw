module CrystalClaw
  module Logger
    enum Level
      DEBUG
      INFO
      WARN
      ERROR
    end

    @@level : Level = Level::INFO
    @@log_file : File? = nil
    @@mutex = Mutex.new

    def self.level=(level : Level)
      @@level = level
    end

    def self.level : Level
      @@level
    end

    def self.set_log_file(path : String)
      @@mutex.synchronize do
        @@log_file.try &.close
        Dir.mkdir_p(File.dirname(path))
        @@log_file = File.open(path, "a")
      end
    end

    def self.debug(msg : String)
      log(Level::DEBUG, msg)
    end

    def self.info(msg : String)
      log(Level::INFO, msg)
    end

    def self.warn(msg : String)
      log(Level::WARN, msg)
    end

    def self.error(msg : String)
      log(Level::ERROR, msg)
    end

    def self.debug(component : String, msg : String, fields : Hash(String, String | Int32 | Int64 | Float64 | Bool | Nil) = {} of String => String | Int32 | Int64 | Float64 | Bool | Nil)
      log_cf(Level::DEBUG, component, msg, fields)
    end

    def self.info(component : String, msg : String, fields : Hash(String, String | Int32 | Int64 | Float64 | Bool | Nil) = {} of String => String | Int32 | Int64 | Float64 | Bool | Nil)
      log_cf(Level::INFO, component, msg, fields)
    end

    def self.warn(component : String, msg : String, fields : Hash(String, String | Int32 | Int64 | Float64 | Bool | Nil) = {} of String => String | Int32 | Int64 | Float64 | Bool | Nil)
      log_cf(Level::WARN, component, msg, fields)
    end

    def self.error(component : String, msg : String, fields : Hash(String, String | Int32 | Int64 | Float64 | Bool | Nil) = {} of String => String | Int32 | Int64 | Float64 | Bool | Nil)
      log_cf(Level::ERROR, component, msg, fields)
    end

    private def self.log(level : Level, msg : String)
      return if level < @@level

      timestamp = Time.local.to_s("%Y-%m-%d %H:%M:%S")
      color = level_color(level)
      label = level_label(level)

      formatted = "#{timestamp} #{color}[#{label}]\e[0m #{msg}"
      file_formatted = "#{timestamp} [#{label}] #{msg}"

      @@mutex.synchronize do
        STDERR.puts(formatted)
        @@log_file.try &.puts(file_formatted)
        @@log_file.try &.flush
      end
    end

    private def self.log_cf(level : Level, component : String, msg : String, fields : Hash)
      return if level < @@level

      parts = [msg]
      fields.each do |k, v|
        parts << "#{k}=#{v}"
      end

      timestamp = Time.local.to_s("%Y-%m-%d %H:%M:%S")
      color = level_color(level)
      label = level_label(level)
      body = parts.join(" ")

      formatted = "#{timestamp} #{color}[#{label}]\e[0m [#{component}] #{body}"
      file_formatted = "#{timestamp} [#{label}] [#{component}] #{body}"

      @@mutex.synchronize do
        STDERR.puts(formatted)
        @@log_file.try &.puts(file_formatted)
        @@log_file.try &.flush
      end
    end

    private def self.level_color(level : Level) : String
      case level
      when .debug? then "\e[36m" # cyan
      when .info?  then "\e[32m" # green
      when .warn?  then "\e[33m" # yellow
      when .error? then "\e[31m" # red
      else              "\e[0m"
      end
    end

    private def self.level_label(level : Level) : String
      case level
      when .debug? then "DEBUG"
      when .info?  then "INFO"
      when .warn?  then "WARN"
      when .error? then "ERROR"
      else              "UNKN"
      end
    end
  end
end

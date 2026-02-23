require "json"
require "db"

module CrystalClaw
  class Config
    include JSON::Serializable

    property agents : AgentsConfig = AgentsConfig.new
    property channels : ChannelsConfig = ChannelsConfig.new
    property providers : ProvidersConfig = ProvidersConfig.new
    property gateway : GatewayConfig = GatewayConfig.new
    property tools : ToolsConfig = ToolsConfig.new
    property heartbeat : HeartbeatConfig = HeartbeatConfig.new
    property devices : DevicesConfig = DevicesConfig.new
    property memory : MemoryConfig = MemoryConfig.new

    def initialize
    end

    def workspace_path : String
      path = agents.defaults.workspace
      path = path.sub("~", Path.home.to_s)
      path
    end

    def self.config_dir : String
      File.join(Path.home.to_s, ".crystalclaw")
    end

    def self.config_path : String
      File.join(config_dir, "config.json")
    end

    def self.default : Config
      cfg = Config.new
      cfg.agents.defaults.workspace = "~/.crystalclaw/workspace"
      cfg.agents.defaults.model = "openrouter/auto"
      cfg.agents.defaults.max_tokens = 8192
      cfg.agents.defaults.temperature = 0.7
      cfg.agents.defaults.max_tool_iterations = 20
      cfg.agents.defaults.restrict_to_workspace = true
      cfg.gateway.host = "0.0.0.0"
      cfg.gateway.port = 18791
      cfg.heartbeat.interval = 30
      cfg.heartbeat.enabled = false
      cfg.tools.web.duckduckgo.enabled = true
      cfg.tools.web.duckduckgo.max_results = 5
      cfg.tools.web.brave.max_results = 5
      cfg.tools.cron.exec_timeout_minutes = 5
      cfg
    end

    CONFIG_PG_KEY = "_config"

    def self.load(path : String) : Config
      unless File.exists?(path)
        return self.default
      end
      data = File.read(path)
      cfg = Config.from_json(data)
      cfg
    end

    def self.load_from_pg(db : DB::Database) : Config
      data = db.query_one?(
        "SELECT content FROM workspace_data WHERE key = $1",
        CONFIG_PG_KEY,
        as: String
      )
      if data && !data.empty?
        cfg = Config.from_json(data)
      else
        cfg = self.default
        save_to_pg(db, cfg)
      end
      cfg
    end

    def self.save_to_pg(db : DB::Database, cfg : Config)
      db.exec(
        <<-SQL,
        INSERT INTO workspace_data (key, content, updated_at)
        VALUES ($1, $2, NOW())
        ON CONFLICT (key) DO UPDATE SET content = $2, updated_at = NOW()
        SQL
        CONFIG_PG_KEY, cfg.to_pretty_json
      )
    end

    def self.save(path : String, cfg : Config)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, cfg.to_pretty_json)
    end
  end

  class AgentsConfig
    include JSON::Serializable
    property defaults : AgentDefaults = AgentDefaults.new
    property list : Array(AgentConfigEntry) = [] of AgentConfigEntry

    def initialize
    end
  end

  class AgentDefaults
    include JSON::Serializable
    property workspace : String = "~/.crystalclaw/workspace"
    property restrict_to_workspace : Bool = true
    property provider : String = ""
    property model : String = "openrouter/auto"
    property model_fallbacks : Array(String) = [] of String
    property max_tokens : Int32 = 8192
    property temperature : Float64 = 0.7
    property max_tool_iterations : Int32 = 20

    def initialize
    end
  end

  class AgentConfigEntry
    include JSON::Serializable
    property id : String = ""
    property default : Bool = false
    property name : String = ""
    property workspace : String = ""
    property model : String = ""
    property skills : Array(String) = [] of String

    def initialize
    end
  end

  class ChannelsConfig
    include JSON::Serializable
    property telegram : TelegramConfig = TelegramConfig.new
    property discord : DiscordConfig = DiscordConfig.new
    property slack : SlackConfig = SlackConfig.new
    property line : LINEConfig = LINEConfig.new
    property dingtalk : DingTalkConfig = DingTalkConfig.new
    property qq : QQConfig = QQConfig.new
    property max_messenger : MaxMessengerConfig = MaxMessengerConfig.new

    def initialize
    end
  end

  class TelegramConfig
    include JSON::Serializable
    property enabled : Bool = false
    property token : String = ""
    property proxy : String = ""
    property allow_from : Array(String) = [] of String

    def initialize
    end
  end

  class DiscordConfig
    include JSON::Serializable
    property enabled : Bool = false
    property token : String = ""
    property allow_from : Array(String) = [] of String

    def initialize
    end
  end

  class SlackConfig
    include JSON::Serializable
    property enabled : Bool = false
    property bot_token : String = ""
    property app_token : String = ""
    property allow_from : Array(String) = [] of String

    def initialize
    end
  end

  class LINEConfig
    include JSON::Serializable
    property enabled : Bool = false
    property channel_secret : String = ""
    property channel_access_token : String = ""
    property webhook_host : String = "0.0.0.0"
    property webhook_port : Int32 = 18791
    property webhook_path : String = "/webhook/line"
    property allow_from : Array(String) = [] of String

    def initialize
    end
  end

  class DingTalkConfig
    include JSON::Serializable
    property enabled : Bool = false
    property client_id : String = ""
    property client_secret : String = ""
    property allow_from : Array(String) = [] of String

    def initialize
    end
  end

  class QQConfig
    include JSON::Serializable
    property enabled : Bool = false
    property app_id : String = ""
    property app_secret : String = ""
    property allow_from : Array(String) = [] of String

    def initialize
    end
  end

  class MaxMessengerConfig
    include JSON::Serializable
    property enabled : Bool = false
    property token : String = ""
    property allow_from : Array(String) = [] of String

    def initialize
    end
  end

  class ProvidersConfig
    include JSON::Serializable
    property openrouter : ProviderEntry = ProviderEntry.new
    property anthropic : ProviderEntry = ProviderEntry.new
    property openai : ProviderEntry = ProviderEntry.new
    property gemini : ProviderEntry = ProviderEntry.new
    property zhipu : ProviderEntry = ProviderEntry.new
    property groq : ProviderEntry = ProviderEntry.new
    property vllm : ProviderEntry = ProviderEntry.new
    property deepseek : ProviderEntry = ProviderEntry.new
    property ollama : ProviderEntry = ProviderEntry.new

    def initialize
    end
  end

  class ProviderEntry
    include JSON::Serializable
    property api_key : String = ""
    property api_base : String = ""
    property auth_method : String = ""
    property read_timeout : Int32 = 120

    def initialize
    end
  end

  class GatewayConfig
    include JSON::Serializable
    property host : String = "0.0.0.0"
    property port : Int32 = 18791

    def initialize
    end
  end

  class ToolsConfig
    include JSON::Serializable
    property web : WebToolsConfig = WebToolsConfig.new
    property cron : CronToolConfig = CronToolConfig.new

    def initialize
    end
  end

  class WebToolsConfig
    include JSON::Serializable
    property brave : BraveConfig = BraveConfig.new
    property duckduckgo : DuckDuckGoConfig = DuckDuckGoConfig.new

    def initialize
    end
  end

  class BraveConfig
    include JSON::Serializable
    property enabled : Bool = false
    property api_key : String = ""
    property max_results : Int32 = 5

    def initialize
    end
  end

  class DuckDuckGoConfig
    include JSON::Serializable
    property enabled : Bool = true
    property max_results : Int32 = 5

    def initialize
    end
  end

  class CronToolConfig
    include JSON::Serializable
    property exec_timeout_minutes : Int32 = 5

    def initialize
    end
  end

  class HeartbeatConfig
    include JSON::Serializable
    property enabled : Bool = false
    property interval : Int32 = 30

    def initialize
    end
  end

  class DevicesConfig
    include JSON::Serializable
    property enabled : Bool = false
    property monitor_usb : Bool = false

    def initialize
    end
  end

  class MemoryConfig
    include JSON::Serializable
    property postgres_url : String = ""

    def initialize
    end
  end
end

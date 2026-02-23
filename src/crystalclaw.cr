# CrystalClaw — Ultra-lightweight personal AI assistant
# Crystal port of PicoClaw (https://github.com/sipeed/picoclaw)
# License: MIT

require "./config/config"
require "./logger/logger"
require "./bus/bus"
require "./providers/types"
require "./providers/openai_compat"
require "./providers/anthropic"
require "./providers/factory"
require "./tools/base"
require "./tools/filesystem"
require "./tools/edit"
require "./tools/shell"
require "./tools/web"
require "./tools/message"
require "./agent/context"
require "./agent/instance"
require "./agent/registry"
require "./agent/loop"
require "./session/manager"
require "./routing/route"
require "./channels/base"
require "./channels/telegram"
require "./channels/discord"
require "./channels/max_messenger"
require "./heartbeat/service"
require "./cron/service"
require "./state/state"
require "./skills/loader"
require "./health/server"
require "./memory/factory"

module CrystalClaw
  VERSION  = "0.1.0"
  LOGO     = "🕷️"
  APP_NAME = "crystalclaw"

  def self.main
    if ARGV.size < 1
      print_help
      exit(1)
    end

    command = ARGV[0]

    case command
    when "onboard"
      onboard
    when "agent"
      agent_cmd
    when "gateway"
      gateway_cmd
    when "status"
      status_cmd
    when "cron"
      cron_cmd
    when "skills"
      skills_cmd
    when "version", "--version", "-v"
      print_version
    when "--help", "-h", "help"
      print_help
    else
      STDERR.puts "Unknown command: #{command}"
      print_help
      exit(1)
    end
  end

  def self.print_version
    puts "#{LOGO} crystalclaw v#{VERSION}"
    puts "  Crystal: #{Crystal::VERSION}"
  end

  def self.print_help
    puts "#{LOGO} crystalclaw - Personal AI Assistant v#{VERSION}"
    puts
    puts "Usage: crystalclaw <command>"
    puts
    puts "Commands:"
    puts "  onboard     Initialize crystalclaw configuration and workspace"
    puts "  agent       Interact with the agent directly"
    puts "  gateway     Start crystalclaw gateway"
    puts "  status      Show crystalclaw status"
    puts "  cron        Manage scheduled tasks"
    puts "  skills      Manage skills (list, show)"
    puts "  version     Show version information"
  end

  # ── Onboard ──

  def self.onboard
    config_path = Config.config_path

    if File.exists?(config_path)
      print "Config already exists at #{config_path}\nOverwrite? (y/n): "
      response = gets
      unless response.try(&.strip.downcase) == "y"
        puts "Aborted."
        return
      end
    end

    cfg = Config.default
    Config.save(config_path, cfg)

    workspace = cfg.workspace_path
    create_workspace_templates(workspace)

    puts "#{LOGO} crystalclaw is ready!"
    puts
    puts "Next steps:"
    puts "  1. Add your API key to #{config_path}"
    puts "     Get one at: https://openrouter.ai/keys"
    puts "  2. Chat: crystalclaw agent -m \"Hello!\""
  end

  private def self.create_workspace_templates(workspace : String)
    Dir.mkdir_p(workspace)

    # Copy templates from embedded workspace directory
    src_dir = File.join(File.dirname(Process.executable_path || __DIR__), "..", "workspace")

    # Fallback: check if workspace exists next to source
    unless Dir.exists?(src_dir)
      src_dir = File.join(__DIR__, "..", "workspace")
    end

    if Dir.exists?(src_dir)
      copy_directory(src_dir, workspace)
    else
      # Create minimal templates inline
      write_template(workspace, "AGENT.md", <<-MD
      # CrystalClaw Agent

      You are CrystalClaw, a helpful personal AI assistant. You help users with tasks by leveraging your available tools.

      ## Behavior Guidelines
      - Be concise and helpful
      - Use tools when appropriate to accomplish tasks
      - Always confirm destructive actions before executing them
      - Maintain conversation context across messages
      MD
      )

      write_template(workspace, "IDENTITY.md", <<-MD
      # Identity

      You are CrystalClaw (🕷️), an ultra-lightweight personal AI assistant built in Crystal.

      ## Core Traits
      - **Efficient**: You value conciseness and precision
      - **Helpful**: You proactively suggest solutions
      - **Safe**: You respect workspace boundaries and never execute dangerous commands
      MD
      )

      write_template(workspace, "SOUL.md", "# Soul\n\nI embody efficiency, helpfulness, and safety.")
      write_template(workspace, "USER.md", "# User Preferences\n\n- Language: English\n- Response style: Concise, technical")
      write_template(workspace, "memory/MEMORY.md", "# Long-Term Memory\n\nThis file stores important information across sessions.")

      # Create directories
      Dir.mkdir_p(File.join(workspace, "sessions"))
      Dir.mkdir_p(File.join(workspace, "state"))
      Dir.mkdir_p(File.join(workspace, "cron"))
      Dir.mkdir_p(File.join(workspace, "skills"))
    end
  end

  private def self.write_template(workspace : String, relative_path : String, content : String)
    path = File.join(workspace, relative_path)
    Dir.mkdir_p(File.dirname(path))
    unless File.exists?(path) # don't overwrite existing user files
      File.write(path, content)
    end
  end

  private def self.copy_directory(src : String, dst : String)
    Dir.mkdir_p(dst)
    Dir.each_child(src) do |child|
      src_path = File.join(src, child)
      dst_path = File.join(dst, child)
      if File.directory?(src_path)
        copy_directory(src_path, dst_path)
      else
        unless File.exists?(dst_path)
          Dir.mkdir_p(File.dirname(dst_path))
          File.copy(src_path, dst_path)
        end
      end
    end
  end

  # ── Agent Command ──

  def self.agent_cmd
    message = ""
    session_key = "cli:default"

    i = 1
    while i < ARGV.size
      case ARGV[i]
      when "--debug", "-d"
        Logger.level = Logger::Level::DEBUG
        STDERR.puts "🔍 Debug mode enabled"
      when "-m", "--message"
        if i + 1 < ARGV.size
          message = ARGV[i + 1]
          i += 1
        end
      when "-s", "--session"
        if i + 1 < ARGV.size
          session_key = ARGV[i + 1]
          i += 1
        end
      end
      i += 1
    end

    cfg = load_config
    provider = Providers.create_provider(cfg)
    msg_bus = Bus::MessageBus.new
    agent_loop = Agent::AgentLoop.new(cfg, msg_bus, provider)

    info = agent_loop.get_startup_info
    Logger.info("agent", "Agent initialized", {"tools_count" => info["tools_count"].to_s})

    if !message.empty?
      # One-shot mode
      response = agent_loop.process_direct(message, session_key)
      puts "\n#{LOGO} #{response}"
    else
      # Interactive mode
      puts "#{LOGO} Interactive mode (type 'exit' to quit)\n"
      interactive_mode(agent_loop, session_key)
    end
  end

  private def self.interactive_mode(agent_loop : Agent::AgentLoop, session_key : String)
    loop do
      print "#{LOGO} You: "
      line = gets
      break unless line

      input = line.strip
      next if input.empty?

      if input == "exit" || input == "quit"
        puts "Goodbye!"
        break
      end

      begin
        response = agent_loop.process_direct(input, session_key)
        puts "\n#{LOGO} #{response}\n"
      rescue ex
        STDERR.puts "Error: #{ex.message}"
      end
    end
  end

  # ── Gateway Command ──

  def self.gateway_cmd
    # Check for debug flag
    ARGV[1..]?.try &.each do |arg|
      if arg == "--debug" || arg == "-d"
        Logger.level = Logger::Level::DEBUG
        STDERR.puts "🔍 Debug mode enabled"
      end
    end

    # Bootstrap: connect to PG and load config from database
    postgres_url = ENV["CRYSTALCLAW_POSTGRES_URL"]?
    if postgres_url && !postgres_url.empty?
      store = Memory.create_pg_store(postgres_url)
      cfg = Config.load_from_pg(store.db)
      # Ensure postgres_url is set in config
      cfg.memory.postgres_url = postgres_url
    else
      cfg = load_config
      store = Memory.create_store(cfg)
    end

    provider = Providers.create_provider(cfg)
    msg_bus = Bus::MessageBus.new
    agent_loop = Agent::AgentLoop.new(cfg, msg_bus, provider)

    info = agent_loop.get_startup_info
    puts "\n📦 Agent Status:"
    puts "  • Tools: #{info["tools_count"]} loaded"

    # Setup channels
    channel_manager = Channels::Manager.new(msg_bus)

    if cfg.channels.telegram.enabled && !cfg.channels.telegram.token.empty?
      tg = Channels::TelegramChannel.new(
        cfg.channels.telegram.token,
        cfg.channels.telegram.allow_from,
        msg_bus
      )
      channel_manager.register(tg)

      # Set outbound handler for Telegram
      msg_bus.on_outbound do |msg|
        if msg.channel == "telegram"
          if thinking_id = msg.metadata["thinking_message_id"]?
            tg.edit_message(msg.chat_id, thinking_id.to_i64, msg.content)
          else
            tg.send_message(msg.chat_id, msg.content)
          end
        end
      end
    end

    if cfg.channels.discord.enabled && !cfg.channels.discord.token.empty?
      dc = Channels::DiscordChannel.new(
        cfg.channels.discord.token,
        cfg.channels.discord.allow_from,
        msg_bus
      )
      channel_manager.register(dc)

      existing_handler = msg_bus.@outbound_handler
      msg_bus.on_outbound do |msg|
        case msg.channel
        when "discord"
          dc.send_message(msg.chat_id, msg.content)
        else
          existing_handler.try(&.call(msg))
        end
      end
    end

    if cfg.channels.max_messenger.enabled && !cfg.channels.max_messenger.token.empty?
      mm = Channels::MaxMessengerChannel.new(
        cfg.channels.max_messenger.token,
        cfg.channels.max_messenger.allow_from,
        msg_bus
      )
      channel_manager.register(mm)

      existing_handler = msg_bus.@outbound_handler
      msg_bus.on_outbound do |msg|
        case msg.channel
        when "max_messenger"
          mm.send_message(msg.chat_id, msg.content)
        else
          existing_handler.try(&.call(msg))
        end
      end
    end

    enabled = channel_manager.get_enabled_channels
    if enabled.size > 0
      puts "✓ Channels enabled: #{enabled.join(", ")}"
    else
      puts "⚠ Warning: No channels enabled"
    end

    # Setup cron (uses memory store)
    cron_service = Cron::Service.new(store)
    cron_service.start
    puts "✓ Cron service started"

    # Setup heartbeat (uses memory store)
    heartbeat = Heartbeat::Service.new(
      store,
      cfg.heartbeat.interval,
      cfg.heartbeat.enabled
    )
    heartbeat.start
    puts "✓ Heartbeat service started"

    # Health server
    health = Health::Server.new(cfg.gateway.host, cfg.gateway.port)
    health.start
    puts "✓ Health endpoints at http://#{cfg.gateway.host}:#{cfg.gateway.port}/health"

    puts "✓ Gateway started on #{cfg.gateway.host}:#{cfg.gateway.port}"
    puts "Press Ctrl+C to stop"

    # Start channels
    channel_manager.start_all

    # Start agent loop in a fiber
    spawn do
      agent_loop.run
    end

    # Wait for signal
    Signal::INT.trap do
      puts "\nShutting down..."
      agent_loop.stop
      channel_manager.stop_all
      heartbeat.stop
      cron_service.stop
      health.stop
      puts "✓ Gateway stopped"
      exit(0)
    end

    # Keep main fiber alive
    sleep
  end

  # ── Status Command ──

  def self.status_cmd
    cfg = load_config
    config_path = Config.config_path

    puts "#{LOGO} crystalclaw Status"
    puts "Version: #{VERSION}"
    puts

    if File.exists?(config_path)
      puts "Config: #{config_path} ✓"
    else
      puts "Config: #{config_path} ✗"
    end

    workspace = cfg.workspace_path
    if Dir.exists?(workspace)
      puts "Workspace: #{workspace} ✓"
    else
      puts "Workspace: #{workspace} ✗"
    end

    puts "Model: #{cfg.agents.defaults.model}"

    status = ->(enabled : Bool) { enabled ? "✓" : "not set" }

    puts "OpenRouter API: #{status.call(!cfg.providers.openrouter.api_key.empty?)}"
    puts "Anthropic API: #{status.call(!cfg.providers.anthropic.api_key.empty?)}"
    puts "OpenAI API: #{status.call(!cfg.providers.openai.api_key.empty?)}"
    puts "Gemini API: #{status.call(!cfg.providers.gemini.api_key.empty?)}"
    puts "Zhipu API: #{status.call(!cfg.providers.zhipu.api_key.empty?)}"
    puts "Groq API: #{status.call(!cfg.providers.groq.api_key.empty?)}"
    if !cfg.providers.vllm.api_base.empty?
      puts "vLLM/Local: ✓ #{cfg.providers.vllm.api_base}"
    else
      puts "vLLM/Local: not set"
    end
  end

  # ── Cron Command ──

  def self.cron_cmd
    if ARGV.size < 2
      cron_help
      return
    end

    cfg = load_config
    store = Memory.create_store(cfg)

    case ARGV[1]
    when "list"
      cs = Cron::Service.new(store)
      jobs = cs.list_jobs(include_disabled: true)
      if jobs.empty?
        puts "No scheduled jobs."
        return
      end
      puts "\nScheduled Jobs:"
      puts "----------------"
      jobs.each do |job|
        schedule = case job.schedule.kind
                   when "every"
                     ms = job.schedule.every_ms || 0_i64
                     "every #{ms / 1000}s"
                   when "cron"
                     job.schedule.expr || "?"
                   else
                     "one-time"
                   end
        status = job.enabled ? "enabled" : "disabled"
        puts "  #{job.name} (#{job.id})"
        puts "    Schedule: #{schedule}"
        puts "    Status: #{status}"
      end
    when "add"
      cron_add_cmd(store)
    when "remove"
      if ARGV.size < 3
        puts "Usage: crystalclaw cron remove <job_id>"
        return
      end
      cs = Cron::Service.new(store)
      if cs.remove_job(ARGV[2])
        puts "✓ Removed job #{ARGV[2]}"
      else
        puts "✗ Job #{ARGV[2]} not found"
      end
    when "enable"
      if ARGV.size < 3
        puts "Usage: crystalclaw cron enable <job_id>"
        return
      end
      cs = Cron::Service.new(store)
      if job = cs.enable_job(ARGV[2], true)
        puts "✓ Job '#{job.name}' enabled"
      else
        puts "✗ Job #{ARGV[2]} not found"
      end
    when "disable"
      if ARGV.size < 3
        puts "Usage: crystalclaw cron disable <job_id>"
        return
      end
      cs = Cron::Service.new(store)
      if job = cs.enable_job(ARGV[2], false)
        puts "✓ Job '#{job.name}' disabled"
      else
        puts "✗ Job #{ARGV[2]} not found"
      end
    else
      puts "Unknown cron command: #{ARGV[1]}"
      cron_help
    end
  end

  private def self.cron_add_cmd(store : Memory::Store)
    name = ""
    message = ""
    every_sec : Int64? = nil
    cron_expr = ""

    i = 2
    while i < ARGV.size
      case ARGV[i]
      when "-n", "--name"
        if i + 1 < ARGV.size
          name = ARGV[i + 1]; i += 1
        end
      when "-m", "--message"
        if i + 1 < ARGV.size
          message = ARGV[i + 1]; i += 1
        end
      when "-e", "--every"
        if i + 1 < ARGV.size
          every_sec = ARGV[i + 1].to_i64; i += 1
        end
      when "-c", "--cron"
        if i + 1 < ARGV.size
          cron_expr = ARGV[i + 1]; i += 1
        end
      end
      i += 1
    end

    if name.empty?
      puts "Error: --name is required"; return
    end
    if message.empty?
      puts "Error: --message is required"; return
    end
    if every_sec.nil? && cron_expr.empty?
      puts "Error: Either --every or --cron must be specified"; return
    end

    schedule = if es = every_sec
                 Cron::CronSchedule.new(kind: "every", every_ms: es * 1000)
               else
                 Cron::CronSchedule.new(kind: "cron", expr: cron_expr)
               end

    cs = Cron::Service.new(store)
    job = cs.add_job(name, schedule, message)
    puts "✓ Added job '#{job.name}' (#{job.id})"
  end

  private def self.cron_help
    puts "\nCron commands:"
    puts "  list              List all scheduled jobs"
    puts "  add               Add a new scheduled job"
    puts "  remove <id>       Remove a job by ID"
    puts "  enable <id>       Enable a job"
    puts "  disable <id>      Disable a job"
    puts
    puts "Add options:"
    puts "  -n, --name       Job name"
    puts "  -m, --message    Message for agent"
    puts "  -e, --every      Run every N seconds"
    puts "  -c, --cron       Cron expression"
  end

  # ── Skills Command ──

  def self.skills_cmd
    if ARGV.size < 2
      skills_help
      return
    end

    cfg = load_config
    workspace = cfg.workspace_path
    loader = Skills::Loader.new(workspace)

    case ARGV[1]
    when "list"
      all_skills = loader.list_skills
      if all_skills.empty?
        puts "No skills installed."
        return
      end
      puts "\nInstalled Skills:"
      puts "------------------"
      all_skills.each do |skill|
        puts "  ✓ #{skill.name} (#{skill.source})"
        puts "    #{skill.description}" unless skill.description.empty?
      end
    when "show"
      if ARGV.size < 3
        puts "Usage: crystalclaw skills show <skill-name>"
        return
      end
      if content = loader.load_skill(ARGV[2])
        puts "\n📦 Skill: #{ARGV[2]}"
        puts "----------------------"
        puts content
      else
        puts "✗ Skill '#{ARGV[2]}' not found"
      end
    else
      puts "Unknown skills command: #{ARGV[1]}"
      skills_help
    end
  end

  private def self.skills_help
    puts "\nSkills commands:"
    puts "  list              List installed skills"
    puts "  show <name>       Show skill details"
  end

  # ── Config helpers ──

  private def self.load_config : Config
    # Check if PG URL is available for config loading
    if (pg_url = ENV["CRYSTALCLAW_POSTGRES_URL"]?) && !pg_url.empty?
      store = Memory.create_pg_store(pg_url)
      Config.load_from_pg(store.db)
    else
      Config.load(Config.config_path)
    end
  end
end

# Entry point
CrystalClaw.main

require "./file_store"
require "./pg_store"
require "../config/config"
require "../logger/logger"

module CrystalClaw
  module Memory
    # Keys that should be seeded from workspace files on first PG use
    SEED_KEYS = [
      "IDENTITY.md",
      "SOUL.md",
      "AGENT.md",
      "USER.md",
      "memory/MEMORY.md",
    ]

    def self.create_store(cfg : Config) : Store
      mem_cfg = cfg.memory
      if !mem_cfg.postgres_url.empty?
        Logger.info("memory", "Using PostgreSQL memory backend")
        store = PgStore.new(mem_cfg.postgres_url)
        seed_from_workspace(store, cfg.workspace_path)
        store
      else
        Logger.info("memory", "Using file memory backend")
        FileStore.new(cfg.workspace_path)
      end
    end

    # Create a store directly from a postgres URL (for gateway bootstrap)
    def self.create_pg_store(postgres_url : String) : PgStore
      Logger.info("memory", "Using PostgreSQL memory backend")
      PgStore.new(postgres_url)
    end

    # On first use, import workspace files into PostgreSQL so the agent
    # has its identity, soul, etc. available without the filesystem.
    private def self.seed_from_workspace(store : PgStore, workspace : String)
      SEED_KEYS.each do |key|
        # Only seed if the key doesn't already exist in PG
        next unless store.get(key).empty?

        path = File.join(workspace, key)
        if File.exists?(path)
          content = File.read(path).strip
          unless content.empty?
            store.set(key, content)
            Logger.info("memory", "Seeded '#{key}' from workspace into PostgreSQL")
          end
        end
      end
    end
  end
end

require "db"
require "pg"
require "./base"

module CrystalClaw
  module Memory
    class PgStore < Store
      getter db : DB::Database

      def initialize(postgres_url : String)
        @db = DB.open(postgres_url)
        ensure_table
      end

      def get(key : String) : String
        @db.query_one?(
          "SELECT content FROM workspace_data WHERE key = $1",
          key,
          as: String
        ) || ""
      end

      def set(key : String, content : String) : Nil
        @db.exec(
          <<-SQL,
          INSERT INTO workspace_data (key, content, updated_at)
          VALUES ($1, $2, NOW())
          ON CONFLICT (key) DO UPDATE SET content = $2, updated_at = NOW()
          SQL
          key, content
        )
      end

      def delete(key : String) : Nil
        @db.exec("DELETE FROM workspace_data WHERE key = $1", key)
      end

      def list_keys(prefix : String) : Array(String)
        keys = [] of String
        @db.query(
          "SELECT key FROM workspace_data WHERE key LIKE $1",
          prefix + "%"
        ) do |rs|
          rs.each do
            keys << rs.read(String)
          end
        end
        keys
      end

      def close
        @db.close
      end

      private def ensure_table
        @db.exec(<<-SQL)
          CREATE TABLE IF NOT EXISTS workspace_data (
            id         SERIAL PRIMARY KEY,
            key        TEXT NOT NULL UNIQUE,
            content    TEXT NOT NULL DEFAULT '',
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
          )
        SQL
      end
    end
  end
end

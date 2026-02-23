require "db"
require "pg"
require "./base"

module CrystalClaw
  module Memory
    class PgStore < Store
      getter db : DB::Database

      def initialize(postgres_url : String)
        @db = DB.open(postgres_url)
        ensure_tables
      end

      # ── Workspace data (prompts, memory) ──

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

      # ── Config table (dot-notation keys) ──

      def get_config(key : String) : String
        @db.query_one?(
          "SELECT value FROM config WHERE key = $1",
          key,
          as: String
        ) || ""
      end

      def set_config(key : String, value : String) : Nil
        @db.exec(
          <<-SQL,
          INSERT INTO config (key, value, updated_at)
          VALUES ($1, $2, NOW())
          ON CONFLICT (key) DO UPDATE SET value = $2, updated_at = NOW()
          SQL
          key, value
        )
      end

      def delete_config(key : String) : Nil
        @db.exec("DELETE FROM config WHERE key = $1", key)
      end

      def list_config_keys(prefix : String = "") : Array(String)
        keys = [] of String
        if prefix.empty?
          @db.query("SELECT key FROM config ORDER BY key") do |rs|
            rs.each { keys << rs.read(String) }
          end
        else
          @db.query(
            "SELECT key FROM config WHERE key LIKE $1 ORDER BY key",
            prefix + "%"
          ) do |rs|
            rs.each { keys << rs.read(String) }
          end
        end
        keys
      end

      def get_all_config : Hash(String, String)
        result = {} of String => String
        @db.query("SELECT key, value FROM config ORDER BY key") do |rs|
          rs.each do
            k = rs.read(String)
            v = rs.read(String)
            result[k] = v
          end
        end
        result
      end

      # ── Sessions table ──

      def get_session(key : String) : String
        @db.query_one?(
          "SELECT content FROM sessions WHERE session_key = $1",
          key,
          as: String
        ) || ""
      end

      def set_session(key : String, content : String) : Nil
        @db.exec(
          <<-SQL,
          INSERT INTO sessions (session_key, content, updated_at)
          VALUES ($1, $2, NOW())
          ON CONFLICT (session_key) DO UPDATE SET content = $2, updated_at = NOW()
          SQL
          key, content
        )
      end

      def delete_session(key : String) : Nil
        @db.exec("DELETE FROM sessions WHERE session_key = $1", key)
      end

      def list_session_keys(prefix : String = "") : Array(String)
        keys = [] of String
        if prefix.empty?
          @db.query("SELECT session_key FROM sessions ORDER BY session_key") do |rs|
            rs.each { keys << rs.read(String) }
          end
        else
          @db.query(
            "SELECT session_key FROM sessions WHERE session_key LIKE $1 ORDER BY session_key",
            prefix + "%"
          ) do |rs|
            rs.each { keys << rs.read(String) }
          end
        end
        keys
      end

      # ── State table ──

      def get_state(key : String) : String
        @db.query_one?(
          "SELECT value FROM state WHERE key = $1",
          key,
          as: String
        ) || ""
      end

      def set_state(key : String, value : String) : Nil
        @db.exec(
          <<-SQL,
          INSERT INTO state (key, value, updated_at)
          VALUES ($1, $2, NOW())
          ON CONFLICT (key) DO UPDATE SET value = $2, updated_at = NOW()
          SQL
          key, value
        )
      end

      # ── Cron jobs table ──

      def get_cron_job(job_id : String) : String
        @db.query_one?(
          "SELECT content FROM cron_jobs WHERE job_id = $1",
          job_id,
          as: String
        ) || ""
      end

      def set_cron_job(job_id : String, content : String) : Nil
        @db.exec(
          <<-SQL,
          INSERT INTO cron_jobs (job_id, content, updated_at)
          VALUES ($1, $2, NOW())
          ON CONFLICT (job_id) DO UPDATE SET content = $2, updated_at = NOW()
          SQL
          job_id, content
        )
      end

      def delete_cron_job(job_id : String) : Nil
        @db.exec("DELETE FROM cron_jobs WHERE job_id = $1", job_id)
      end

      def list_cron_jobs : Array({String, String})
        jobs = [] of {String, String}
        @db.query("SELECT job_id, content FROM cron_jobs ORDER BY job_id") do |rs|
          rs.each do
            id = rs.read(String)
            content = rs.read(String)
            jobs << {id, content}
          end
        end
        jobs
      end

      def close
        @db.close
      end

      private def ensure_tables
        @db.exec(<<-SQL)
          CREATE TABLE IF NOT EXISTS workspace_data (
            id         SERIAL PRIMARY KEY,
            key        TEXT NOT NULL UNIQUE,
            content    TEXT NOT NULL DEFAULT '',
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
          )
        SQL

        @db.exec(<<-SQL)
          CREATE TABLE IF NOT EXISTS config (
            id         SERIAL PRIMARY KEY,
            key        TEXT NOT NULL UNIQUE,
            value      TEXT NOT NULL DEFAULT '',
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
          )
        SQL

        @db.exec(<<-SQL)
          CREATE TABLE IF NOT EXISTS sessions (
            id          SERIAL PRIMARY KEY,
            session_key TEXT NOT NULL UNIQUE,
            content     TEXT NOT NULL DEFAULT '',
            created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
          )
        SQL

        @db.exec(<<-SQL)
          CREATE TABLE IF NOT EXISTS state (
            id         SERIAL PRIMARY KEY,
            key        TEXT NOT NULL UNIQUE,
            value      TEXT NOT NULL DEFAULT '',
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
          )
        SQL

        @db.exec(<<-SQL)
          CREATE TABLE IF NOT EXISTS cron_jobs (
            id         SERIAL PRIMARY KEY,
            job_id     TEXT NOT NULL UNIQUE,
            content    TEXT NOT NULL DEFAULT '',
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
          )
        SQL
      end
    end
  end
end

#!/bin/sh
set -e

export HOME=/home/crystalclaw

if [ -n "$CRYSTALCLAW_POSTGRES_URL" ]; then
    # ── Postgres mode: no file config ──

    echo "🕷️ Waiting for PostgreSQL..."
    until pg_isready -d "$CRYSTALCLAW_POSTGRES_URL" -q; do sleep 1; done

    # Ensure the config table exists (crystal app creates it on first connect,
    # but we need it before we can check/seed it)
    psql "$CRYSTALCLAW_POSTGRES_URL" -q <<'SQL'
        CREATE TABLE IF NOT EXISTS config (
            id         SERIAL PRIMARY KEY,
            key        TEXT NOT NULL UNIQUE,
            value      TEXT NOT NULL DEFAULT '',
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );
SQL

    # Seed provider config on first run (when table is empty)
    COUNT=$(psql "$CRYSTALCLAW_POSTGRES_URL" -t -c "SELECT COUNT(*) FROM config;" | tr -d ' ')
    if [ "$COUNT" = "0" ]; then
        echo "🕷️ Seeding initial config into PostgreSQL..."
        psql "$CRYSTALCLAW_POSTGRES_URL" -q <<SQL
            INSERT INTO config (key, value) VALUES
                ('agents.defaults.model',           '"qwen3.5-4b"'),
                ('agents.defaults.provider',        '"ollama"'),
                ('agents.defaults.max_tokens',      '8192'),
                ('agents.defaults.temperature',     '0.7'),
                ('agents.defaults.max_tool_iterations', '20'),
                ('agents.defaults.restrict_to_workspace', 'true'),
                ('agents.defaults.report_tool_usage', 'false'),
                ('agents.defaults.workspace',       '"~/.crystalclaw/workspace"'),
                ('gateway.host',                    '"0.0.0.0"'),
                ('gateway.port',                    '18791'),
                ('heartbeat.interval',              '30'),
                ('heartbeat.enabled',               'false'),
                ('tools.web.duckduckgo.enabled',    'true'),
                ('tools.web.duckduckgo.max_results','5'),
                ('tools.web.brave.max_results',     '5'),
                ('tools.cron.exec_timeout_minutes', '5'),
                ('providers.ollama.api_key',        '"dummy"'),
                ('providers.ollama.api_base',       '"http://llama:8080/v1"')
            ON CONFLICT (key) DO NOTHING;
SQL
    fi

    # Fix workspace ownership (volume may be root-owned)
    mkdir -p "${HOME}/.crystalclaw/workspace"
    chown -R crystalclaw:crystalclaw "${HOME}/.crystalclaw"
else
    # ── File mode ──
    CONFIG_DIR="${HOME}/.crystalclaw"
    CONFIG_FILE="${CONFIG_DIR}/config.json"

    mkdir -p "$CONFIG_DIR/workspace"
    chown -R crystalclaw:crystalclaw "$CONFIG_DIR"

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "🕷️ No config found — running onboard to create defaults..."
        gosu crystalclaw /app/bin/crystalclaw onboard
    fi
fi

exec gosu crystalclaw /app/bin/crystalclaw "$@"

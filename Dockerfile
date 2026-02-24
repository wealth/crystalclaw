# ── Build stage ──
FROM crystallang/crystal:1.19.1 AS builder

RUN apt-get update && apt-get install -y libpq-dev

WORKDIR /app

# Copy dependency manifest first for layer caching
COPY shard.yml ./
COPY shard.lock ./
RUN shards install --production

# Copy source and workspace templates
COPY src/ src/
COPY workspace/ workspace/

# Build a dynamically-linked release binary
RUN shards build --release --no-debug

# ── Runtime stage ──
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    tzdata \
    gosu \
    libpq5 \
    sudo \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user and allow passwordless sudo
RUN groupadd -r crystalclaw && useradd -m -r -g crystalclaw crystalclaw \
    && echo "crystalclaw ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers \
    && printf '#!/bin/sh\nexec sudo /usr/bin/apt "$@"\n' > /usr/local/bin/apt \
    && chmod +x /usr/local/bin/apt \
    && printf '#!/bin/sh\nexec sudo /usr/bin/apt-get "$@"\n' > /usr/local/bin/apt-get \
    && chmod +x /usr/local/bin/apt-get \
    && printf '#!/bin/sh\nexec sudo /usr/bin/dpkg "$@"\n' > /usr/local/bin/dpkg \
    && chmod +x /usr/local/bin/dpkg

WORKDIR /app

# Copy the compiled binary
COPY --from=builder /app/bin/crystalclaw /app/bin/crystalclaw

# Copy workspace templates (used by the onboard command)
COPY workspace/ /app/workspace/

# Copy entrypoint script
COPY docker-entrypoint.sh /app/docker-entrypoint.sh

# Set ownership of app directory (volumes are fixed at runtime by entrypoint)
RUN chown -R crystalclaw:crystalclaw /home/crystalclaw /app

EXPOSE 18791

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:18791/health || exit 1

ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["gateway"]

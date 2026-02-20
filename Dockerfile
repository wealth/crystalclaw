# ── Build stage ──
FROM crystallang/crystal:1.19.1-alpine AS builder

WORKDIR /app

# Copy dependency manifest first for layer caching
COPY shard.yml ./
RUN shards install --production

# Copy source and workspace templates
COPY src/ src/
COPY workspace/ workspace/

# Build a statically-linked release binary
RUN shards build --release --static --no-debug

# ── Runtime stage ──
FROM alpine:3.21

RUN apk add --no-cache \
    ca-certificates \
    tzdata

# Create a non-root user
RUN addgroup -S crystalclaw && adduser -S crystalclaw -G crystalclaw

WORKDIR /app

# Copy the compiled binary
COPY --from=builder /app/bin/crystalclaw /app/bin/crystalclaw

# Copy workspace templates (used by the onboard command)
COPY workspace/ /app/workspace/

# Create default config and workspace directories
RUN mkdir -p /home/crystalclaw/.crystalclaw/workspace && \
    chown -R crystalclaw:crystalclaw /home/crystalclaw /app

USER crystalclaw

EXPOSE 18791

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:18791/health || exit 1

ENTRYPOINT ["/app/bin/crystalclaw"]
CMD ["gateway"]

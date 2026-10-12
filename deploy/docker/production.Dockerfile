# ─────────────────────────────────────────────────────────────
# OpenHuman Server — Production Multi-stage Dockerfile (ARM64 & x86)
# ─────────────────────────────────────────────────────────────

# Build stage
FROM rust:bookworm AS builder
WORKDIR /build

# Pre-install dependencies for compilation (including OpenSSL dev headers)
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy source tree and compile release binary
COPY . .
RUN cargo build --release

# Runtime stage
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    tzdata \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Run as non-root user for maximum security
RUN useradd -m -u 10001 -U openhuman

COPY --from=builder --chown=openhuman:openhuman /build/target/release/openhuman-server /usr/local/bin/openhuman-server

USER openhuman
WORKDIR /home/openhuman

EXPOSE 8080
ENV RUST_LOG="openhuman_server=info,tower_http=info"

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
    CMD curl -f http://localhost:8080/healthz || exit 1

ENTRYPOINT ["openhuman-server"]

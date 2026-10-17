ARG JAVA_VERSION=17

FROM rust:1-bookworm AS rust-base

FROM golang:1-bookworm AS go-base

FROM python:3.12-slim-bookworm
ARG JAVA_VERSION

# All runtime configuration flows through CODING_TOOLS_MCP_* environment variables,
# which the server reads directly. EXEC_ALLOW_ROOTS only needs the JDK/Maven config
# dirs under /etc; everything under /usr is already a built-in read root.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    CODING_TOOLS_MCP_WORKSPACE=/workspace \
    CODING_TOOLS_MCP_HOST=0.0.0.0 \
    CODING_TOOLS_MCP_PORT=8765 \
    CODING_TOOLS_MCP_PERMISSION_MODE=trusted \
    CODING_TOOLS_MCP_GENERATE_AUTH_TOKEN=1 \
    CODING_TOOLS_MCP_EXEC_ALLOW_ROOTS=/etc/java-${JAVA_VERSION}-openjdk:/etc/maven \
    JAVA_HOME=/usr/lib/jvm/java-${JAVA_VERSION}-openjdk-amd64 \
    CODING_TOOLS_MCP_SHELL_ENV_SET='{"CARGO_HOME":"/usr/local/cargo","RUSTUP_HOME":"/usr/local/rustup"}'

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        clang \
        cmake \
        curl \
        g++ \
        gcc \
        git \
        make \
        lua5.4 \
        luarocks \
        maven \
        ninja-build \
        nodejs \
        npm \
        openjdk-${JAVA_VERSION}-jdk-headless \
        pkg-config \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# Lua 5.5.1: built from the official lua/lua tag (apt only ships 5.4.4)
RUN curl -fsSL https://codeload.github.com/lua/lua/tar.gz/refs/tags/v5.5.1 -o /tmp/lua.tar.gz \
    && mkdir /tmp/lua-src \
    && tar xzf /tmp/lua.tar.gz -C /tmp/lua-src --strip-components=1 \
    && make -C /tmp/lua-src -j"$(nproc)" \
    && install -m 0755 /tmp/lua-src/lua /usr/local/bin/lua5.5 \
    && ln -s lua5.5 /usr/local/bin/lua \
    && rm -rf /tmp/lua-src /tmp/lua.tar.gz \
    && lua -v

# Lune: standalone Luau runtime (prebuilt binary, pinned version)
RUN curl -fsSL https://github.com/lune-org/lune/releases/download/v0.10.5/lune-0.10.5-linux-x86_64.zip -o /tmp/lune.zip \
    && unzip -q /tmp/lune.zip -d /usr/local/bin \
    && chmod +x /usr/local/bin/lune \
    && rm /tmp/lune.zip \
    && lune --version

# luau-lsp: Luau type checker (analyze mode) + Roblox type definitions
RUN curl -fsSL https://github.com/JohnnyMorganz/luau-lsp/releases/download/1.70.1/luau-lsp-linux-x86_64.zip -o /tmp/luau-lsp.zip \
    && unzip -q /tmp/luau-lsp.zip -d /usr/local/bin \
    && chmod +x /usr/local/bin/luau-lsp \
    && rm /tmp/luau-lsp.zip \
    && mkdir -p /usr/local/share/luau \
    && curl -fsSL https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.None.d.luau -o /usr/local/share/luau/globalTypes.None.d.luau \
    && luau-lsp --version

COPY --from=go-base /usr/local/go /usr/local/go
COPY --from=rust-base /usr/local/cargo /usr/local/cargo
COPY --from=rust-base /usr/local/rustup /usr/local/rustup

ENV PATH=/usr/local/go/bin:/usr/local/cargo/bin:$PATH \
    CARGO_HOME=/usr/local/cargo \
    RUSTUP_HOME=/usr/local/rustup

WORKDIR /app
COPY pyproject.toml README.md LICENSE ./
COPY coding_tools_mcp ./coding_tools_mcp
RUN python -m pip install --no-cache-dir . \
    && mkdir -p /workspace

EXPOSE 8765
ENTRYPOINT ["coding-tools-mcp"]

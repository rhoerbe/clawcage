FROM node:22-bookworm

# System deps for Playwright + SSH + Git + session recording
RUN apt-get update && apt-get install -y \
    openssh-client \
    git \
    curl \
    bsdutils \
    net-tools \
    iputils-ping \
    jq \
    vim \
    mosquitto-clients \
    # Playwright's Chromium dependencies
    libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 \
    libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 \
    libxfixes3 libxrandr2 libgbm1 libpango-1.0-0 \
    libasound2 libatspi2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Claude Code
RUN npm install -g @anthropic-ai/claude-code

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && apt-get install -y gh && rm -rf /var/lib/apt/lists/*

# yq - YAML processor (for HA config files)
RUN curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

# Playwright MCP server + browser
RUN npm install -g @playwright/mcp && npx playwright install chromium

WORKDIR /workspace

# Set /workspace as home directory for node user (fixes SSH config lookup with --userns=keep-id)
# SSH reads home from /etc/passwd, not $HOME environment variable
RUN usermod -d /workspace node

# Ensure npm cache is writable for rootless podman with --userns=keep-id
RUN mkdir -p /workspace/.npm && chmod 777 /workspace/.npm

# MCP config template (copied to user home at runtime via --userns=keep-id)
COPY mcp-config.json /etc/claude/mcp-config.json

# Entrypoint script for "always latest" Claude Code updates
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["claude"]

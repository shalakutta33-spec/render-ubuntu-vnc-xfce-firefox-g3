FROM accetto/ubuntu-vnc-xfce-firefox-g3:latest

USER root

# Install Tailscale
RUN apt-get update \
    && apt-get install -y curl \
    && curl -fsSL https://tailscale.com/install.sh | sh \
    && rm -rf /var/lib/apt/lists/*

# Interactive Tailscale login
RUN printf '%s\n' \
    '#!/bin/bash' \
    'read -rsp "Enter Tailscale auth key: " TS_KEY' \
    'echo' \
    'tailscale up --auth-key="$TS_KEY"' \
    'unset TS_KEY' \
    > /usr/local/bin/tailscale-login \
    && chmod +x /usr/local/bin/tailscale-login

EXPOSE 5901
EXPOSE 6901

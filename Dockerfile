FROM accetto/ubuntu-vnc-xfce-firefox-g3:latest

USER root

# Install Tailscale
RUN apt-get update \
    && apt-get install -y curl \
    && curl -fsSL https://tailscale.com/install.sh | sh \
    && rm -rf /var/lib/apt/lists/*

EXPOSE 5901
EXPOSE 6901

FROM accetto/ubuntu-vnc-xfce-firefox-g3:latest

USER root

RUN apt-get update \
    && apt-get install -y curl \
    && curl -fsSL https://tailscale.com/install.sh | sh \
    && rm -rf /var/lib/apt/lists/*

COPY start.sh /start.sh
RUN chmod +x /start.sh

# ponytail: Deplexo runs rootfs read-only except /data + /tmp; redirect Accetto writes there
RUN rm -rf /home/headless/.config /home/headless/.cache \
    && mkdir -p /data/.config /data/.cache /home/headless \
    && ln -s /data/.config /home/headless/.config \
    && ln -s /data/.cache /home/headless/.cache \
    && ln -sf /tmp/vnc.log /dockerstartup/vnc.log \
    && ln -sf /tmp/novnc.log /dockerstartup/novnc.log \
    && touch /tmp/vnc.log /tmp/novnc.log || true

EXPOSE 5901
EXPOSE 6901

ENTRYPOINT ["/start.sh"]

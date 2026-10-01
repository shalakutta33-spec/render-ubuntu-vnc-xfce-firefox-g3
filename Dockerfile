FROM accetto/ubuntu-vnc-xfce-firefox-g3:latest

USER root

RUN apt-get update \
    && apt-get install -y curl \
    && curl -fsSL https://tailscale.com/install.sh | sh \
    && rm -rf /var/lib/apt/lists/*

COPY start.sh /start.sh
RUN chmod +x /start.sh

# ponytail: redirect Accetto writes to /data + /tmp (read-only rootfs hosts)
RUN rm -rf /home/headless/.config /home/headless/.cache \
    && mkdir -p /data/.config /data/.cache /home/headless \
    && ln -s /data/.config /home/headless/.config \
    && ln -s /data/.cache /home/headless/.cache \
    && ln -sf /tmp/vnc.log /dockerstartup/vnc.log \
    && ln -sf /tmp/novnc.log /dockerstartup/novnc.log \
    && touch /tmp/vnc.log /tmp/novnc.log || true

# ponytail: Render runs as UID 1001, not root; pre-open writes Accetto startup needs
RUN touch /dockerstartup/.initial_sudo_password \
    && chmod 666 /dockerstartup/.initial_sudo_password \
    && chmod 777 /dockerstartup \
    && chmod 666 /etc/passwd /etc/group || true
RUN mkdir -p /data && chmod 777 /data \
    && chmod -R a+rwX /home/headless /tmp /dockerstartup || true

EXPOSE 5901
EXPOSE 6901

ENTRYPOINT ["/start.sh"]

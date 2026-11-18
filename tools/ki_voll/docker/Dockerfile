# Insel-KI-Training im Docker (josh 2026-11-18). Bauen und starten im Paketordner:
#   docker compose up -d --build        danach im Browser: http://<server>:8765/
# Das Spiel wird beim Bauen einmal vorbereitet; alles, was das Training erzeugt, liegt im Ordner lauf/ (Volume).
FROM python:3.12-slim

ARG GODOT_VERSION=4.7.2-stable
ARG TARGETARCH
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl unzip ca-certificates libfontconfig1 \
 && rm -rf /var/lib/apt/lists/*
RUN case "$TARGETARCH" in arm64) A=arm64 ;; *) A=x86_64 ;; esac \
 && curl -fsSL -o /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.${A}.zip" \
 && mkdir -p /opt/godot && unzip -q /tmp/godot.zip -d /opt/godot && rm /tmp/godot.zip \
 && mv /opt/godot/Godot_v*_linux.* /opt/godot/godot && chmod +x /opt/godot/godot

WORKDIR /insel
COPY spiel/ spiel/
# zweimal importieren wie auf dem Mac (beim ersten Lauf fehlen sonst Klassen)
RUN export HOME=/tmp/godot-home; \
    /opt/godot/godot --headless --path spiel --import >/dev/null 2>&1; \
    /opt/godot/godot --headless --path spiel --import >/dev/null 2>&1; \
    test -d spiel/.godot/imported && rm -rf /tmp/godot-home
COPY training/ training/
COPY LIESMICH.md ./
COPY lauf/einstellungen.json vorlage/einstellungen.json
COPY docker-start.sh /usr/local/bin/insel-start
RUN chmod +x /usr/local/bin/insel-start

ENV INSEL_DOCKER=1 INSEL_HOST=0.0.0.0 INSEL_PORT=8765 PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
EXPOSE 8765
VOLUME /insel/lauf
CMD ["insel-start"]

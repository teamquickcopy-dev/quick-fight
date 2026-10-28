# Infra

One VPS running Docker Compose, with three services:
- **Caddy:** HTTPS, serves the web build with brotli, and proxies `/ws` to the server.
- **The signaling server.**
- **coturn:** a relay for players whose direct WebRTC connection fails, for example behind strict mobile or office networks.

1. Point DNS for your domain at the VPS. Open TCP 80 and 443, UDP 443, TCP+UDP 3478, and UDP 49160–49200.
2. `cp .env.example .env` and fill it in. `TURN_SECRET`: `openssl rand -hex 32`.
3. Put the web build in `infra/web/`. Precompress it so Caddy serves brotli: `brotli -k web/*.wasm web/*.pck web/*.js`.
4. `docker compose up -d`, then check `https://<domain>/healthz`.

Not done yet: MinIO for builds, Postgres/Redis, Umami and CI deploys (from the design doc's stack). The prototype needs none of them.

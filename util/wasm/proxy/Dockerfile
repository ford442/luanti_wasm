# Luanti WebSocket UDP proxy. Build context: this directory.
#   docker build -t luanti-proxy util/wasm/proxy
# Run it behind TLS (see deploy/docker-compose.yml); it speaks plain ws:// itself.
FROM node:24-bookworm-slim AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

FROM node:24-bookworm-slim
ENV NODE_ENV=production \
    LUANTI_PROXY_HOST=0.0.0.0 \
    LUANTI_PROXY_PORT=8080
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY package.json server.mjs protocol.mjs policy.mjs limits.mjs metrics.mjs ./
USER node
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD node -e "fetch('http://127.0.0.1:8080/healthz').then(r => process.exit(r.ok ? 0 : 1), () => process.exit(1))"
# 0.0.0.0 needs LUANTI_PROXY_ALLOWED_ORIGINS (the server refuses to start without it).
CMD ["node", "server.mjs"]

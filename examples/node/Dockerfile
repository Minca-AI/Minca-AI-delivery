# Fixture image: no runtime dependencies, so no install step; the node image's
# built-in `node` user is uid 1000, declared numerically for runAsNonRoot.
FROM node:22-bookworm-slim
WORKDIR /app
COPY package.json index.js greeting.js ./
USER 1000
ENTRYPOINT ["node", "index.js"]

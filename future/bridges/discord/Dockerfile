FROM node:20-slim

WORKDIR /app
COPY bridge-common/ ./bridge-common/
COPY discord-bridge/package*.json ./
RUN npm install --omit=dev

COPY discord-bridge/index.js ./

RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app \
               --home-dir /nonexistent \
               --shell /usr/sbin/nologin app \
    && chown -R app:app /app

USER app:app
EXPOSE 3002
CMD ["node", "index.js"]

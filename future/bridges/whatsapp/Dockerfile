FROM node:20-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libglib2.0-0 libexpat1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev

COPY index.js ./

RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app \
               --home-dir /nonexistent \
               --shell /usr/sbin/nologin app \
    && mkdir -p /app/sessions \
    && chown -R app:app /app

USER app:app
VOLUME ["/app/sessions"]
EXPOSE 3000
CMD ["node", "index.js"]

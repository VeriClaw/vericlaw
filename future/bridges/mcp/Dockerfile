FROM node:20-slim

WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev

COPY index.js ./

ENV PORT=3004
EXPOSE 3004

CMD ["node", "index.js"]

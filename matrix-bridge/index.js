const sdk = require('matrix-js-sdk');
const express = require('express');

const client = sdk.createClient({
  baseUrl: process.env.MATRIX_HOMESERVER || 'https://matrix.org',
  accessToken: process.env.MATRIX_TOKEN,
  userId: process.env.MATRIX_USER_ID,
});

const messageQueue = [];
const seenIds = new Set();

client.on('Room.timeline', (event) => {
  if (event.getType() !== 'm.room.message') return;
  const id = event.getId();
  if (!seenIds.has(id)) {
    seenIds.add(id);
    const sender = event.getSender();
    const text = event.getContent().body;
    const room = event.getRoomId();
    messageQueue.push({ id, from: sender, room, text });
  }
});

client.startClient({ initialSyncLimit: 0 });

const api = express();
api.use(express.json());
api.get('/sessions/matrix/messages', (req, res) => {
  const limit = parseInt(req.query.limit) || 10;
  res.json(messageQueue.splice(0, limit));
});
api.post('/sessions/matrix/messages', async (req, res) => {
  const { room, text } = req.body;
  await client.sendTextMessage(room, text);
  res.json({ ok: true });
});
api.get('/health', (req, res) => res.json({ ok: true }));
api.listen(3006, () => console.log('Matrix bridge listening on port 3006'));

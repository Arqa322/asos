import crypto from 'node:crypto';
import express from 'express';
import { createServer } from 'node:http';
import { Server } from 'socket.io';
import Database from 'better-sqlite3';

const PORT = Number(process.env.PORT || 3001);
const app = express();
const httpServer = createServer(app);
const io = new Server(httpServer, {
  cors: { origin: '*' },
});

const db = new Database('pulsemesh.db');
db.pragma('journal_mode = WAL');

db.exec(`
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  avatar_url TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  room_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  username TEXT NOT NULL,
  avatar_url TEXT,
  content TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  event TEXT NOT NULL,
  user_id TEXT,
  room_id TEXT,
  payload TEXT,
  created_at TEXT NOT NULL
);
`);

app.use(express.json({ limit: '4mb' }));

const usersBySocket = new Map();
const activeRoomBySocket = new Map();

const insertLog = db.prepare(
  'INSERT INTO logs (event, user_id, room_id, payload, created_at) VALUES (?, ?, ?, ?, ?)',
);
const insertMessage = db.prepare(
  'INSERT INTO messages (room_id, user_id, username, avatar_url, content, created_at) VALUES (?, ?, ?, ?, ?, ?)',
);
const createUser = db.prepare(
  'INSERT INTO users (id, username, password_hash, avatar_url, created_at) VALUES (?, ?, ?, ?, ?)',
);
const findUserByUsername = db.prepare('SELECT * FROM users WHERE username = ?');
const findUserById = db.prepare('SELECT id, username, avatar_url, created_at FROM users WHERE id = ?');
const getRoomMessages = db.prepare(
  'SELECT id, room_id, user_id, username, avatar_url, content, created_at FROM messages WHERE room_id = ? ORDER BY id DESC LIMIT 100',
);

const hashPassword = (password) => crypto.createHash('sha256').update(password).digest('hex');
const sanitizeName = (name) => String(name || '').trim().slice(0, 32);

app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'pulsemesh-server', port: PORT });
});

app.post('/api/register', (req, res) => {
  const username = sanitizeName(req.body?.username);
  const password = String(req.body?.password || '');
  const avatarUrl = typeof req.body?.avatarUrl === 'string' ? req.body.avatarUrl.slice(0, 2_000_000) : '';

  if (!username || password.length < 4) {
    res.status(400).json({ error: 'Введите username и пароль минимум 4 символа.' });
    return;
  }

  if (findUserByUsername.get(username)) {
    res.status(409).json({ error: 'Пользователь с таким именем уже существует.' });
    return;
  }

  const userId = crypto.randomUUID();
  const createdAt = new Date().toISOString();
  createUser.run(userId, username, hashPassword(password), avatarUrl, createdAt);
  insertLog.run('register', userId, null, JSON.stringify({ username }), createdAt);

  res.json({
    user: {
      id: userId,
      username,
      avatarUrl,
      createdAt,
    },
  });
});

app.post('/api/login', (req, res) => {
  const username = sanitizeName(req.body?.username);
  const password = String(req.body?.password || '');
  const user = findUserByUsername.get(username);

  if (!user || user.password_hash !== hashPassword(password)) {
    res.status(401).json({ error: 'Неверный логин или пароль.' });
    return;
  }

  const profile = findUserById.get(user.id);
  insertLog.run('login', user.id, null, JSON.stringify({ username }), new Date().toISOString());
  res.json({ user: profile });
});

app.get('/api/rooms/:roomId/messages', (req, res) => {
  const roomId = String(req.params.roomId || '').trim();
  if (!roomId) {
    res.status(400).json({ error: 'roomId required' });
    return;
  }
  const messages = getRoomMessages.all(roomId).reverse();
  res.json({ messages });
});

const participantsForRoom = (roomId) => {
  const participants = [];
  for (const [socketId, room] of activeRoomBySocket.entries()) {
    if (room !== roomId) continue;
    const user = usersBySocket.get(socketId);
    if (user) participants.push({ ...user, socketId });
  }
  return participants;
};

io.on('connection', (socket) => {
  const authUser = socket.handshake.auth?.user;
  if (!authUser?.id || !authUser?.username) {
    socket.disconnect();
    return;
  }

  const user = {
    id: String(authUser.id),
    username: sanitizeName(authUser.username),
    avatarUrl: typeof authUser.avatarUrl === 'string' ? authUser.avatarUrl.slice(0, 2_000_000) : '',
  };
  usersBySocket.set(socket.id, user);
  insertLog.run('socket_connected', user.id, null, JSON.stringify({ socketId: socket.id }), new Date().toISOString());

  socket.on('join_room', ({ roomId }) => {
    const targetRoom = String(roomId || '').trim().slice(0, 64) || 'general';
    socket.join(targetRoom);
    activeRoomBySocket.set(socket.id, targetRoom);

    const messages = getRoomMessages.all(targetRoom).reverse();
    const participants = participantsForRoom(targetRoom);
    socket.emit('room_state', { roomId: targetRoom, participants, messages });
    socket.to(targetRoom).emit('user_joined', { ...user, socketId: socket.id });

    insertLog.run('join_room', user.id, targetRoom, JSON.stringify({ socketId: socket.id }), new Date().toISOString());
  });

  socket.on('leave_room', ({ roomId }) => {
    const current = activeRoomBySocket.get(socket.id);
    const targetRoom = String(roomId || current || '').trim();
    if (!targetRoom) return;

    socket.leave(targetRoom);
    activeRoomBySocket.delete(socket.id);
    socket.to(targetRoom).emit('user_left', { userId: user.id, socketId: socket.id });
    insertLog.run('leave_room', user.id, targetRoom, JSON.stringify({ socketId: socket.id }), new Date().toISOString());
  });

  socket.on('chat_message', ({ roomId, content }) => {
    const normalizedRoom = String(roomId || activeRoomBySocket.get(socket.id) || '').trim();
    const text = String(content || '').trim();
    if (!normalizedRoom || !text) return;

    const payload = {
      room_id: normalizedRoom,
      user_id: user.id,
      username: user.username,
      avatar_url: user.avatarUrl,
      content: text.slice(0, 4000),
      created_at: new Date().toISOString(),
    };
    const row = insertMessage.run(
      payload.room_id,
      payload.user_id,
      payload.username,
      payload.avatar_url,
      payload.content,
      payload.created_at,
    );
    io.to(normalizedRoom).emit('chat_message', { id: row.lastInsertRowid, ...payload });
  });

  socket.on('voice_state', ({ roomId, micLevel, speakerLevel, muted }) => {
    const normalizedRoom = String(roomId || activeRoomBySocket.get(socket.id) || '').trim();
    if (!normalizedRoom) return;

    socket.to(normalizedRoom).emit('voice_state', {
      userId: user.id,
      socketId: socket.id,
      micLevel: Number(micLevel || 100),
      speakerLevel: Number(speakerLevel || 100),
      muted: Boolean(muted),
    });
  });

  socket.on('webrtc_offer', ({ toSocketId, offer, roomId }) => {
    io.to(toSocketId).emit('webrtc_offer', {
      fromSocketId: socket.id,
      roomId,
      offer,
      user,
    });
  });

  socket.on('webrtc_answer', ({ toSocketId, answer, roomId }) => {
    io.to(toSocketId).emit('webrtc_answer', {
      fromSocketId: socket.id,
      roomId,
      answer,
    });
  });

  socket.on('webrtc_ice', ({ toSocketId, candidate, roomId }) => {
    io.to(toSocketId).emit('webrtc_ice', {
      fromSocketId: socket.id,
      roomId,
      candidate,
    });
  });

  socket.on('disconnect', () => {
    const roomId = activeRoomBySocket.get(socket.id);
    if (roomId) {
      socket.to(roomId).emit('user_left', { userId: user.id, socketId: socket.id });
    }

    activeRoomBySocket.delete(socket.id);
    usersBySocket.delete(socket.id);
    insertLog.run('socket_disconnected', user.id, roomId || null, JSON.stringify({ socketId: socket.id }), new Date().toISOString());
  });
});

httpServer.listen(PORT, () => {
  console.log(`PulseMesh server is running on http://localhost:${PORT}`);
});

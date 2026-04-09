import { useEffect, useMemo, useRef, useState } from 'react';
import { io, type Socket } from 'socket.io-client';

type AuthMode = 'login' | 'register';

type SessionUser = {
  id: string;
  username: string;
  avatarUrl?: string;
};

type RoomMessage = {
  id: number;
  room_id: string;
  user_id: string;
  username: string;
  avatar_url?: string;
  content: string;
  created_at: string;
};

type Participant = {
  id: string;
  username: string;
  avatarUrl?: string;
  socketId: string;
  muted?: boolean;
  micLevel?: number;
  speakerLevel?: number;
  screenLevel?: number;
};

const STORAGE_KEY = 'pulsemesh-session-v2';

const rtcConfig: RTCConfiguration = {
  iceServers: [
    { urls: ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'] },
    { urls: ['stun:stun2.l.google.com:19302'] },
  ],
};

const joinClass = (...parts: Array<string | false | null | undefined>) =>
  parts.filter(Boolean).join(' ');

const nowString = (value: string) =>
  new Date(value).toLocaleTimeString('ru-RU', {
    hour: '2-digit',
    minute: '2-digit',
  });

const fileToDataUrl = (file: File) =>
  new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error('Не удалось прочитать файл.'));
    reader.onload = () => resolve(String(reader.result || ''));
    reader.readAsDataURL(file);
  });

function App() {
  const [serverUrl, setServerUrl] = useState('http://localhost:3001');
  const [roomId, setRoomId] = useState('general');
  const [authMode, setAuthMode] = useState<AuthMode>('login');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [authError, setAuthError] = useState('');
  const [avatarPreview, setAvatarPreview] = useState('');
  const [session, setSession] = useState<SessionUser | null>(null);
  const [connected, setConnected] = useState(false);
  const [messages, setMessages] = useState<RoomMessage[]>([]);
  const [participants, setParticipants] = useState<Participant[]>([]);
  const [messageInput, setMessageInput] = useState('');
  const [statusText, setStatusText] = useState('Отключено');
  const [showInstructions, setShowInstructions] = useState(false);
  const [audioInputs, setAudioInputs] = useState<MediaDeviceInfo[]>([]);
  const [videoInputs, setVideoInputs] = useState<MediaDeviceInfo[]>([]);
  const [selectedMicId, setSelectedMicId] = useState('');
  const [selectedCameraId, setSelectedCameraId] = useState('');
  const [micMuted, setMicMuted] = useState(false);
  const [speakerMaster, setSpeakerMaster] = useState(100);
  const [micMaster, setMicMaster] = useState(100);
  const [inCall, setInCall] = useState(false);
  const [popoverFor, setPopoverFor] = useState('');

  const socketRef = useRef<Socket | null>(null);
  const localVideoRef = useRef<HTMLVideoElement | null>(null);
  const remoteVideoRefs = useRef<Record<string, HTMLVideoElement | null>>({});
  const localStreamRef = useRef<MediaStream | null>(null);
  const peerMapRef = useRef<Map<string, RTCPeerConnection>>(new Map());

  const selfSocketId = socketRef.current?.id || '';
  const remoteParticipants = useMemo(
    () => participants.filter((item) => item.socketId !== selfSocketId),
    [participants, selfSocketId],
  );

  const applyRemoteVolume = (socketId: string, speakerLevel: number, screenLevel: number) => {
    const el = remoteVideoRefs.current[socketId];
    if (!el) return;
    const volume = Math.max(0, Math.min(1, (speakerLevel / 100) * (screenLevel / 100) * (speakerMaster / 100)));
    el.volume = volume;
  };

  const emitVoiceState = (participantPatch?: Partial<Participant>) => {
    const socket = socketRef.current;
    if (!socket || !connected) return;

    socket.emit('voice_state', {
      roomId,
      muted: participantPatch?.muted ?? micMuted,
      micLevel: participantPatch?.micLevel ?? micMaster,
      speakerLevel: participantPatch?.speakerLevel ?? speakerMaster,
    });
  };

  const updateParticipantLevels = (socketId: string, patch: Partial<Participant>) => {
    setParticipants((prev) =>
      prev.map((item) => {
        if (item.socketId !== socketId) return item;
        const updated = { ...item, ...patch };
        applyRemoteVolume(socketId, updated.speakerLevel ?? 100, updated.screenLevel ?? 100);
        return updated;
      }),
    );
  };

  const closePeer = (socketId: string) => {
    const peer = peerMapRef.current.get(socketId);
    if (!peer) return;
    peer.ontrack = null;
    peer.onicecandidate = null;
    peer.close();
    peerMapRef.current.delete(socketId);
  };

  const cleanupMedia = () => {
    for (const peerSocketId of peerMapRef.current.keys()) {
      closePeer(peerSocketId);
    }
    localStreamRef.current?.getTracks().forEach((track) => track.stop());
    localStreamRef.current = null;

    if (localVideoRef.current) {
      localVideoRef.current.srcObject = null;
    }
    for (const key of Object.keys(remoteVideoRefs.current)) {
      const el = remoteVideoRefs.current[key];
      if (el) el.srcObject = null;
    }
    setInCall(false);
  };

  const createPeer = (targetSocketId: string) => {
    const existing = peerMapRef.current.get(targetSocketId);
    if (existing) return existing;

    const socket = socketRef.current;
    const peer = new RTCPeerConnection(rtcConfig);

    if (localStreamRef.current) {
      localStreamRef.current.getTracks().forEach((track) => peer.addTrack(track, localStreamRef.current as MediaStream));
    }

    peer.ontrack = (event) => {
      const [stream] = event.streams;
      if (!stream) return;
      const el = remoteVideoRefs.current[targetSocketId];
      if (el && el.srcObject !== stream) {
        el.srcObject = stream;
      }
    };

    peer.onicecandidate = (event) => {
      if (!event.candidate || !socket) return;
      socket.emit('webrtc_ice', {
        roomId,
        toSocketId: targetSocketId,
        candidate: event.candidate,
      });
    };

    peerMapRef.current.set(targetSocketId, peer);
    return peer;
  };

  const callPeer = async (targetSocketId: string) => {
    const socket = socketRef.current;
    if (!socket) return;

    const peer = createPeer(targetSocketId);
    const offer = await peer.createOffer();
    await peer.setLocalDescription(offer);

    socket.emit('webrtc_offer', {
      roomId,
      toSocketId: targetSocketId,
      offer,
    });
  };

  const startCall = async () => {
    if (inCall) return;
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          deviceId: selectedMicId ? { exact: selectedMicId } : undefined,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        },
        video: selectedCameraId ? { deviceId: { exact: selectedCameraId } } : true,
      });

      localStreamRef.current = stream;
      if (localVideoRef.current) {
        localVideoRef.current.srcObject = stream;
      }

      const audioTrack = stream.getAudioTracks()[0];
      if (audioTrack) {
        audioTrack.enabled = !micMuted;
      }

      setInCall(true);
      for (const participant of remoteParticipants) {
        await callPeer(participant.socketId);
      }
    } catch {
      setStatusText('Нет доступа к камере или микрофону.');
    }
  };

  const stopCall = () => {
    cleanupMedia();
  };

  const refreshDevices = async () => {
    try {
      const devices = await navigator.mediaDevices.enumerateDevices();
      const mics = devices.filter((item) => item.kind === 'audioinput');
      const cams = devices.filter((item) => item.kind === 'videoinput');
      setAudioInputs(mics);
      setVideoInputs(cams);
      if (!selectedMicId && mics[0]) setSelectedMicId(mics[0].deviceId);
      if (!selectedCameraId && cams[0]) setSelectedCameraId(cams[0].deviceId);
    } catch {
      setStatusText('Не удалось получить список устройств.');
    }
  };

  const connectSocket = (user: SessionUser, targetRoom: string) => {
    const current = socketRef.current;
    if (current) {
      current.disconnect();
      socketRef.current = null;
    }

    const socket = io(serverUrl, {
      transports: ['websocket'],
      auth: { user },
    });
    socketRef.current = socket;

    socket.on('connect', () => {
      setConnected(true);
      setStatusText(`Подключено: ${serverUrl}`);
      socket.emit('join_room', { roomId: targetRoom });
      emitVoiceState();
    });

    socket.on('disconnect', () => {
      setConnected(false);
      setStatusText('Соединение разорвано');
      cleanupMedia();
      setParticipants([]);
    });

    socket.on('room_state', (payload: { participants: Participant[]; messages: RoomMessage[] }) => {
      setParticipants(
        payload.participants.map((item) => ({
          ...item,
          micLevel: item.micLevel ?? 100,
          speakerLevel: item.speakerLevel ?? 100,
          screenLevel: item.screenLevel ?? 100,
        })),
      );
      setMessages(payload.messages);
      setStatusText(`Комната: ${targetRoom}`);
    });

    socket.on('user_joined', (userJoin: Participant) => {
      setParticipants((prev) => {
        const exists = prev.some((item) => item.socketId === userJoin.socketId);
        if (exists) return prev;
        return [...prev, { ...userJoin, micLevel: 100, speakerLevel: 100, screenLevel: 100 }];
      });

      if (inCall) {
        void callPeer(userJoin.socketId);
      }
    });

    socket.on('user_left', ({ socketId }: { socketId: string }) => {
      setParticipants((prev) => prev.filter((item) => item.socketId !== socketId));
      closePeer(socketId);
      delete remoteVideoRefs.current[socketId];
    });

    socket.on('chat_message', (msg: RoomMessage) => {
      setMessages((prev) => [...prev, msg]);
    });

    socket.on(
      'voice_state',
      (payload: { socketId: string; muted: boolean; micLevel: number; speakerLevel: number }) => {
        updateParticipantLevels(payload.socketId, {
          muted: payload.muted,
          micLevel: payload.micLevel,
          speakerLevel: payload.speakerLevel,
        });
      },
    );

    socket.on(
      'webrtc_offer',
      async ({ fromSocketId, offer }: { fromSocketId: string; offer: RTCSessionDescriptionInit }) => {
        const peer = createPeer(fromSocketId);
        await peer.setRemoteDescription(new RTCSessionDescription(offer));
        const answer = await peer.createAnswer();
        await peer.setLocalDescription(answer);

        socket.emit('webrtc_answer', {
          roomId,
          toSocketId: fromSocketId,
          answer,
        });
      },
    );

    socket.on('webrtc_answer', async ({ fromSocketId, answer }: { fromSocketId: string; answer: RTCSessionDescriptionInit }) => {
      const peer = peerMapRef.current.get(fromSocketId);
      if (!peer) return;
      await peer.setRemoteDescription(new RTCSessionDescription(answer));
    });

    socket.on('webrtc_ice', async ({ fromSocketId, candidate }: { fromSocketId: string; candidate: RTCIceCandidateInit }) => {
      const peer = peerMapRef.current.get(fromSocketId);
      if (!peer) return;
      await peer.addIceCandidate(new RTCIceCandidate(candidate));
    });
  };

  const sendMessage = () => {
    const socket = socketRef.current;
    const content = messageInput.trim();
    if (!socket || !connected || !content) return;

    socket.emit('chat_message', {
      roomId,
      content,
    });
    setMessageInput('');
  };

  const handleAuth = async () => {
    setAuthError('');
    try {
      const endpoint = authMode === 'login' ? '/api/login' : '/api/register';
      const response = await fetch(`${serverUrl}${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          username,
          password,
          avatarUrl: avatarPreview,
        }),
      });
      const payload = await response.json();
      if (!response.ok) {
        setAuthError(payload.error || 'Ошибка авторизации.');
        return;
      }

      const user = payload.user as SessionUser;
      setSession(user);
      localStorage.setItem(STORAGE_KEY, JSON.stringify(user));
      connectSocket(user, roomId);
      await refreshDevices();
    } catch {
      setAuthError('Не удалось подключиться к серверу. Проверьте адрес и запуск backend.');
    }
  };

  const changeRoom = () => {
    const socket = socketRef.current;
    if (!socket) return;

    socket.emit('leave_room', {});
    socket.emit('join_room', { roomId });
    setMessages([]);
    cleanupMedia();
  };

  const logout = () => {
    socketRef.current?.disconnect();
    socketRef.current = null;
    cleanupMedia();
    setParticipants([]);
    setMessages([]);
    setSession(null);
    localStorage.removeItem(STORAGE_KEY);
    setStatusText('Отключено');
  };

  const playSound = (frequency: number) => {
    const context = new AudioContext();
    const oscillator = context.createOscillator();
    const gain = context.createGain();
    oscillator.type = 'triangle';
    oscillator.frequency.value = frequency;
    gain.gain.value = 0.1;
    oscillator.connect(gain);
    gain.connect(context.destination);
    oscillator.start();
    oscillator.stop(context.currentTime + 0.2);
    setTimeout(() => context.close(), 300);
  };

  useEffect(() => {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return;
    try {
      const parsed = JSON.parse(raw) as SessionUser;
      if (!parsed?.id || !parsed?.username) return;
      setSession(parsed);
      setUsername(parsed.username);
      setAvatarPreview(parsed.avatarUrl || '');
      connectSocket(parsed, roomId);
      void refreshDevices();
    } catch {
      localStorage.removeItem(STORAGE_KEY);
    }

    return () => {
      socketRef.current?.disconnect();
      cleanupMedia();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const audioTrack = localStreamRef.current?.getAudioTracks()[0];
    if (audioTrack) {
      audioTrack.enabled = !micMuted;
    }
    emitVoiceState({ muted: micMuted });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [micMuted]);

  useEffect(() => {
    emitVoiceState({ micLevel: micMaster, speakerLevel: speakerMaster });
    for (const participant of participants) {
      applyRemoteVolume(participant.socketId, participant.speakerLevel ?? 100, participant.screenLevel ?? 100);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [micMaster, speakerMaster]);

  if (!session) {
    return (
      <div className="min-h-screen bg-[#101115] text-slate-100 flex items-center justify-center p-6">
        <div className="w-full max-w-md rounded-xl border border-white/10 bg-[#17181d] p-6 space-y-4">
          <h1 className="text-2xl font-semibold">PulseMesh Desktop</h1>
          <p className="text-sm text-slate-400">Простое клиент-серверное приложение для чата, звонков и экрана.</p>

          <label className="space-y-1 block">
            <span className="text-xs text-slate-400">Адрес сервера</span>
            <input
              className="w-full rounded-md border border-white/10 bg-[#101115] px-3 py-2"
              value={serverUrl}
              onChange={(event) => setServerUrl(event.target.value)}
            />
          </label>

          <div className="grid grid-cols-2 gap-2">
            <button
              className={joinClass(
                'rounded-md px-3 py-2 text-sm transition',
                authMode === 'login' ? 'bg-indigo-500 text-white' : 'bg-white/5 hover:bg-white/10',
              )}
              onClick={() => setAuthMode('login')}
            >
              Вход
            </button>
            <button
              className={joinClass(
                'rounded-md px-3 py-2 text-sm transition',
                authMode === 'register' ? 'bg-indigo-500 text-white' : 'bg-white/5 hover:bg-white/10',
              )}
              onClick={() => setAuthMode('register')}
            >
              Регистрация
            </button>
          </div>

          <label className="space-y-1 block">
            <span className="text-xs text-slate-400">Имя пользователя</span>
            <input
              className="w-full rounded-md border border-white/10 bg-[#101115] px-3 py-2"
              value={username}
              onChange={(event) => setUsername(event.target.value)}
            />
          </label>
          <label className="space-y-1 block">
            <span className="text-xs text-slate-400">Пароль</span>
            <input
              className="w-full rounded-md border border-white/10 bg-[#101115] px-3 py-2"
              type="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
            />
          </label>

          {authMode === 'register' && (
            <label className="space-y-1 block">
              <span className="text-xs text-slate-400">Аватар (PNG/JPG/GIF/WebP)</span>
              <input
                className="w-full rounded-md border border-white/10 bg-[#101115] px-3 py-2 text-sm"
                type="file"
                accept="image/*"
                onChange={async (event) => {
                  const file = event.target.files?.[0];
                  if (!file) return;
                  const data = await fileToDataUrl(file);
                  setAvatarPreview(data);
                }}
              />
              {avatarPreview && <img src={avatarPreview} alt="avatar" className="h-14 w-14 rounded-full object-cover border border-white/15" />}
            </label>
          )}

          {authError && <p className="text-sm text-rose-300">{authError}</p>}

          <button className="w-full rounded-md bg-indigo-500 px-3 py-2 font-medium hover:bg-indigo-400" onClick={handleAuth}>
            Продолжить
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="h-screen bg-[#101115] text-slate-100 flex">
      <aside className="w-20 border-r border-white/10 p-3 flex flex-col items-center gap-3 bg-[#15171d]">
        <div className="h-12 w-12 rounded-2xl bg-indigo-500 flex items-center justify-center text-lg font-semibold">PM</div>
        <button className="w-full rounded-md bg-white/5 px-2 py-2 text-xs hover:bg-white/10" onClick={() => setShowInstructions((v) => !v)}>
          Help
        </button>
        <button className="w-full rounded-md bg-white/5 px-2 py-2 text-xs hover:bg-white/10" onClick={logout}>
          Выход
        </button>
      </aside>

      <section className="w-72 border-r border-white/10 bg-[#17181d] p-4 flex flex-col gap-4">
        <h2 className="text-sm font-semibold text-slate-300">Подключение</h2>
        <label className="space-y-1 block text-xs text-slate-400">
          Сервер
          <input
            className="w-full rounded-md border border-white/10 bg-[#101115] px-3 py-2 text-slate-100"
            value={serverUrl}
            onChange={(event) => setServerUrl(event.target.value)}
          />
        </label>
        <label className="space-y-1 block text-xs text-slate-400">
          Комната
          <div className="flex gap-2">
            <input
              className="w-full rounded-md border border-white/10 bg-[#101115] px-3 py-2 text-slate-100"
              value={roomId}
              onChange={(event) => setRoomId(event.target.value)}
            />
            <button className="rounded-md bg-indigo-500 px-3 py-2 text-xs hover:bg-indigo-400" onClick={changeRoom}>
              Войти
            </button>
          </div>
        </label>

        {showInstructions && (
          <div className="rounded-md border border-white/10 bg-[#101115] p-3 text-xs text-slate-300 space-y-1">
            <p>1. Запустите сервер на хосте: node server/index.js</p>
            <p>2. Укажите адрес сервера и войдите.</p>
            <p>3. Введите комнату и нажмите Войти.</p>
            <p>4. Сообщения хранятся в SQLite на сервере.</p>
          </div>
        )}

        <div className="rounded-md border border-white/10 bg-[#101115] p-3 space-y-2">
          <p className="text-sm font-medium">Soundboard</p>
          <div className="grid grid-cols-3 gap-2">
            <button className="rounded bg-white/10 p-2 text-xs hover:bg-white/20" onClick={() => playSound(440)}>
              Ping
            </button>
            <button className="rounded bg-white/10 p-2 text-xs hover:bg-white/20" onClick={() => playSound(540)}>
              Bell
            </button>
            <button className="rounded bg-white/10 p-2 text-xs hover:bg-white/20" onClick={() => playSound(660)}>
              Pop
            </button>
          </div>
        </div>

        <div className="rounded-md border border-white/10 bg-[#101115] p-3 space-y-2 text-xs">
          <p className="font-medium">Аудио устройства</p>
          <label className="block space-y-1">
            Микрофон
            <select
              className="w-full rounded-md border border-white/10 bg-[#17181d] px-2 py-1"
              value={selectedMicId}
              onChange={(event) => setSelectedMicId(event.target.value)}
            >
              {audioInputs.map((item) => (
                <option key={item.deviceId} value={item.deviceId}>
                  {item.label || 'Микрофон'}
                </option>
              ))}
            </select>
          </label>
          <label className="block space-y-1">
            Камера
            <select
              className="w-full rounded-md border border-white/10 bg-[#17181d] px-2 py-1"
              value={selectedCameraId}
              onChange={(event) => setSelectedCameraId(event.target.value)}
            >
              {videoInputs.map((item) => (
                <option key={item.deviceId} value={item.deviceId}>
                  {item.label || 'Камера'}
                </option>
              ))}
            </select>
          </label>
          <button className="w-full rounded-md bg-white/10 px-3 py-2 hover:bg-white/20" onClick={refreshDevices}>
            Обновить список
          </button>
        </div>

        <div className="text-xs text-slate-400">{statusText}</div>
      </section>

      <main className="flex-1 flex flex-col bg-[#111318]">
        <div className="flex-1 overflow-y-auto p-4 space-y-3">
          {messages.map((msg) => (
            <div key={`${msg.id}-${msg.created_at}`} className="flex gap-3">
              <img
                src={msg.avatar_url || session.avatarUrl || 'https://placehold.co/40x40/1f2937/ffffff?text=U'}
                alt={msg.username}
                className="h-9 w-9 rounded-full object-cover"
              />
              <div className="min-w-0">
                <div className="flex items-center gap-2 text-sm">
                  <span className="font-medium">{msg.username}</span>
                  <span className="text-xs text-slate-500">{nowString(msg.created_at)}</span>
                </div>
                <p className="text-sm text-slate-200 whitespace-pre-wrap break-words">{msg.content}</p>
              </div>
            </div>
          ))}
          {!messages.length && <p className="text-sm text-slate-500">Пока нет сообщений.</p>}
        </div>

        <div className="border-t border-white/10 p-3 flex gap-2">
          <input
            className="flex-1 rounded-md border border-white/10 bg-[#17181d] px-3 py-2"
            placeholder="Напишите сообщение..."
            value={messageInput}
            onChange={(event) => setMessageInput(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === 'Enter') sendMessage();
            }}
          />
          <button className="rounded-md bg-indigo-500 px-4 py-2 hover:bg-indigo-400" onClick={sendMessage}>
            Отправить
          </button>
        </div>

        <div className="border-t border-white/10 p-3 grid grid-cols-4 gap-3 text-xs bg-[#17181d]">
          <button className="rounded-md bg-white/10 px-3 py-2 hover:bg-white/20" onClick={inCall ? stopCall : startCall}>
            {inCall ? 'Завершить звонок' : 'Начать звонок'}
          </button>
          <button className="rounded-md bg-white/10 px-3 py-2 hover:bg-white/20" onClick={() => setMicMuted((v) => !v)}>
            {micMuted ? 'Включить микрофон' : 'Выключить микрофон'}
          </button>
          <label className="rounded-md bg-white/5 px-3 py-2 flex items-center gap-2">
            Mic
            <input
              className="w-full"
              type="range"
              min={0}
              max={100}
              value={micMaster}
              onChange={(event) => setMicMaster(Number(event.target.value))}
            />
          </label>
          <label className="rounded-md bg-white/5 px-3 py-2 flex items-center gap-2">
            Speaker
            <input
              className="w-full"
              type="range"
              min={0}
              max={100}
              value={speakerMaster}
              onChange={(event) => setSpeakerMaster(Number(event.target.value))}
            />
          </label>
        </div>
      </main>

      <aside className="w-[330px] border-l border-white/10 bg-[#17181d] p-4 flex flex-col gap-3 overflow-y-auto">
        <h3 className="text-sm font-semibold">Участники</h3>
        {participants.map((participant) => {
          const open = popoverFor === participant.socketId;
          const isSelf = participant.socketId === selfSocketId;

          return (
            <div key={participant.socketId} className="rounded-md border border-white/10 bg-[#101115] p-2">
              <button className="w-full flex items-center gap-2" onClick={() => setPopoverFor(open ? '' : participant.socketId)}>
                <img
                  src={participant.avatarUrl || 'https://placehold.co/40x40/1f2937/ffffff?text=U'}
                  alt={participant.username}
                  className="h-8 w-8 rounded-full object-cover"
                />
                <div className="flex-1 text-left">
                  <p className="text-sm leading-none">{participant.username}</p>
                  <p className="text-xs text-slate-500">{isSelf ? 'Вы' : 'Online'}</p>
                </div>
                <span className="h-2 w-2 rounded-full bg-emerald-400" />
              </button>

              {open && (
                <div className="mt-2 rounded-md border border-white/10 bg-[#17181d] p-2 space-y-2 text-xs">
                  <label className="block space-y-1">
                    Громкость динамика
                    <input
                      className="w-full"
                      type="range"
                      min={0}
                      max={100}
                      value={participant.speakerLevel ?? 100}
                      onChange={(event) =>
                        updateParticipantLevels(participant.socketId, {
                          speakerLevel: Number(event.target.value),
                        })
                      }
                    />
                  </label>
                  <label className="block space-y-1">
                    Чувствительность микрофона
                    <input
                      className="w-full"
                      type="range"
                      min={0}
                      max={100}
                      value={participant.micLevel ?? 100}
                      onChange={(event) =>
                        updateParticipantLevels(participant.socketId, {
                          micLevel: Number(event.target.value),
                        })
                      }
                    />
                  </label>
                  <label className="block space-y-1">
                    Звук демонстрации экрана
                    <input
                      className="w-full"
                      type="range"
                      min={0}
                      max={100}
                      value={participant.screenLevel ?? 100}
                      onChange={(event) =>
                        updateParticipantLevels(participant.socketId, {
                          screenLevel: Number(event.target.value),
                        })
                      }
                    />
                  </label>
                </div>
              )}
            </div>
          );
        })}

        <h3 className="text-sm font-semibold mt-2">Видео</h3>
        <video ref={localVideoRef} autoPlay muted playsInline className="w-full rounded-md border border-white/10 bg-black/30" />
        {remoteParticipants.map((participant) => (
          <video
            key={participant.socketId}
            ref={(node) => {
              remoteVideoRefs.current[participant.socketId] = node;
              if (node) {
                const speaker = participant.speakerLevel ?? 100;
                const screen = participant.screenLevel ?? 100;
                applyRemoteVolume(participant.socketId, speaker, screen);
              }
            }}
            autoPlay
            playsInline
            className="w-full rounded-md border border-white/10 bg-black/30"
          />
        ))}
        {!remoteParticipants.length && <p className="text-xs text-slate-500">Другие участники появятся здесь.</p>}
      </aside>
    </div>
  );
}

export default App;
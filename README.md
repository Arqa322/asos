# PulseMesh Desktop (Client-Server)

Минималистичное десктоп-приложение в стиле мессенджера:

- клиент: React + Vite (рендер в Electron)
- сервер: Node.js + Express + Socket.io
- база данных: SQLite (`pulsemesh.db`)
- звонки: WebRTC c сигналингом через Socket.io

## Что реализовано

- Регистрация и вход (username/password)
- Загрузка своей аватарки (включая анимированные GIF/WebP)
- Комнаты и общий чат
- Хранение истории сообщений в SQLite
- Логи пользователей на сервере (вход, подключение, комната, отключение)
- Выбор микрофона и камеры из подключенных устройств
- Простая панель звуков (soundboard)
- Всплывающая панель под каждым пользователем с ползунками:
  - громкость динамика
  - чувствительность микрофона
  - громкость экрана
- Отдельная плашка-инструкция по подключению
- Базовый WebRTC-видеозвонок в комнате (client-server signaling)

## Структура

- `src/App.tsx` - весь UI и клиентская логика
- `server/index.js` - backend + Socket.io + SQLite
- `electron/main.mjs` - main process Electron
- `electron/preload.mjs` - безопасный bridge
- `electron-builder.yml` - конфиг сборки установщика

## Запуск локально

1. Установить зависимости:

```bash
npm install
```

2. Запустить сервер:

```bash
node server/index.js
```

3. Запустить клиент:

```bash
npm run dev
```

Клиент подключается к `http://localhost:3001` по умолчанию.

## Деплой на хост (сервер)

1. Скопировать проект на VPS/хостинг.
2. Установить Node.js 20+.
3. Выполнить:

```bash
npm install
PORT=3001 node server/index.js
```

4. Открыть порт 3001 в firewall.
5. Рекомендуется поставить reverse proxy (Nginx) и SSL.

## Desktop сборка

В проекте уже есть Electron scaffold и `electron-builder.yml`.
Для упаковки используйте electron-builder в вашем CI/CD или локально.

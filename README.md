# FeedbackBot

FeedbackBot — Telegram-бот для сбора офисных обращений, построенный на Vapor 4 (совместим со Swift 6) + Fluent + PostgreSQL, с контейнеризацией через Docker и полным циклом CI/CD на GitHub Actions с автоматическими уведомлениями о результатах сборки и деплоя в Telegram, а также интеграцией health‑эндпоинтов с Uptime Kuma.

## Описание проекта

Telegram-бот уже работает через Long-Polling. Реализованы меню `/start` и кнопка «Оставить обращение». Бот принимает сообщения и сохраняет их в базу данных PostgreSQL. Проект работает в Docker-контейнерах. CI/CD и health-check эндпоинты `/health` и `/healthz`.

## Текущий статус

### Реализовано
- Telegram-бот с Long-Polling, меню `/start` и кнопкой «Оставить обращение»;
- Приём сообщений из Telegram и сохранение обращений в PostgreSQL;
- Backend на Vapor 4 (Swift 6) с feature-folder структурой;
- Модель Feedback и миграции (Fluent + PostgreSQL);
- Health-эндпоинты `/health` и `/healthz` для проверки сервера и базы данных;
- Dockerfile и `docker-compose.yml` для локального и продакшн окружений;
- CI/CD: автоматическая сборка и деплой на VPS через GitHub Actions с уведомлениями в Telegram;
- Мониторинг через Uptime Kuma с алертами в Telegram-бот @KumaNotifierGKUBot.

## Архитектура Telegram-бота

Проект содержит следующие ключевые компоненты для работы Telegram-бота:

- **TelegramTypes.swift** — определения структур, описывающих Telegram API объекты (сообщения, обновления, клавиатуры и т.д.);
- **TelegramService.swift** — сервис для взаимодействия с Telegram API, отправки сообщений и обработки запросов;
- **TelegramPolling.swift** — реализация Long-Polling для получения обновлений от Telegram;
- **TelegramUpdateProcessor.swift** — обработка входящих обновлений, маршрутизация команд и сообщений;
- **SessionStore.swift** — хранение сессий пользователей для управления состоянием диалогов;
- **Feedback.swift** — модель данных для хранения обращений пользователей в базе данных.

## Пример `.env`

```env
BOT_TOKEN=your_telegram_bot_token_here
DATABASE_URL=postgresql://user:password@localhost:5432/feedbackbotdb
SERVER_PORT=8080
```

## Структура проекта

```text
.
├── README.md
├── Package.swift
├── Package.resolved
├── Dockerfile
├── docker-compose.yml
├── docker-compose.prod.yml
├── Run/
│   └── Main.swift
└── Sources/
    └── App/
        ├── Configuration/
        │   ├── Bootstrap.swift
        │   ├── Configure.swift
        │   ├── Migrations.swift
        │   └── Routes.swift
        ├── Core/
        │   ├── CSVExporter.swift
        │   ├── Environment+Extensions.swift
        │   ├── SessionStore.swift
        │   ├── TelegramPolling.swift
        │   ├── TelegramService.swift
        │   ├── TelegramTypes.swift
        │   └── TelegramUpdateProcessor.swift
        └── Features/
            ├── BotMenu/
            │   └── BotMenuController.swift
            └── Feedback/
                ├── Controllers/
                │   └── FeedbackController.swift
                ├── Migrations/
                │   └── CreateFeedback.swift
                └── Models/
                    └── Feedback.swift
```

## Мониторинг

Эндпоинты `/health` и `/healthz` интегрированы с Uptime Kuma для отслеживания статуса приложения и подключения к базе данных. Рекомендуется использовать `/healthz` в Uptime Kuma, так как он дополнительно проверяет доступность Postgres.

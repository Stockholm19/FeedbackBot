# FeedbackBot

**FeedbackBot** — корпоративный Telegram-бот для сбора и экспорта обращений сотрудников.  
Бот построен на **Vapor 4 (Swift 6)** с использованием **PostgreSQL**, контейнеризован через **Docker** и снабжён полноценным **CI/CD-циклом** на GitHub Actions.  
Уведомления о сборках и состоянии сервера приходят в Telegram, а health-эндпоинты интегрированы с **Uptime Kuma**.

## Текущий статус

### Реализовано
- Полностью работающий Telegram-бот на Long-Polling;
- Главное меню `/start` и кнопки «Оставить обращение» / «Экспорт»;
- Приём обращений и сохранение в PostgreSQL;
- Экспорт обращений в **CSV-файл** с корректным экранированием и отправкой в Telegram;
- Сервис `TelegramService` с безопасной обработкой multipart-запросов;
- Модуль `CSVExporter` (RFC-4180-совместимый формат, поддержка Excel/Numbers);
- Логирование и защита от зацикливания при экспорте;
- CI/CD: автоматическая сборка и деплой на сервер через GitHub Actions;
- Docker-окружение для локальной разработки и продакшена;
- Health-эндпоинты `/health` и `/healthz`, совместимые с **Uptime Kuma**;
- Уведомления о деплое и состоянии контейнера в Telegram.

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

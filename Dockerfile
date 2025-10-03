# --- Build stage --------------------------------------------------------------
FROM swift:5.10-jammy AS build
WORKDIR /app

# 1) Кэш зависимостей
COPY Package.swift ./
RUN swift package resolve

# 2) Копируем весь исходник и собираем бинарь
COPY . .
# статическая линковка удобна для маленького рантайма
RUN swift build -c release --static-swift-stdlib

# --- Runtime stage ------------------------------------------------------------
FROM ubuntu:22.04 AS run
WORKDIR /run

# Системные зависимости для Vapor (TLS/SSL и корневые сертификаты)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      libssl3 \
      curl \
      && rm -rf /var/lib/apt/lists/*

# Копируем бинарь
COPY --from=build /app/.build/release/Run /run/Run

# Стандартный порт Vapor
ENV PORT=8080
EXPOSE 8080

# По умолчанию просто запускаем приложение
CMD ["./Run"]

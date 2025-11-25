# Миграция с sing-box на Clash Meta (mihomo)

## Что изменилось

VLF VPN клиент теперь использует **Clash Meta (mihomo)** вместо sing-box как ядро VPN-туннеля.

### Новые файлы

- `lib/clash_config.dart` — генератор YAML-конфигурации для Clash из VLESS-подписок
- `lib/clash_manager.dart` — менеджер процесса mihomo (запуск, остановка, логирование)
- `tools/test_clash_config.dart` — тестовый скрипт для проверки генерации конфигов
- `mihomo.exe` — бинарник Clash Meta (должен находиться в корне проекта)

### Изменённые файлы

- `lib/core/vlf_core.dart` — интегрирован ClashManager вместо SingboxManager
- `tools/build_and_package.ps1` — обновлён для копирования mihomo.exe

### Удалённые/переименованные файлы

Старые sing-box файлы переименованы с суффиксом `.old`:
- `lib/singbox_manager.dart.old`
- `lib/singbox_config_clean.dart.old`
- `lib/singbox_config.dart.old`

## Требования

1. **mihomo.exe** — должен находиться в корне проекта (рядом с `pubspec.yaml`)
2. **wintun.dll** — должен находиться там же (для TUN-интерфейса в Windows)

## API Совместимость

ClashManager реализует тот же интерфейс, что и SingboxManager:
- `start(profileUrl, baseDir, ...)` — запуск туннеля
- `stop()` — остановка
- `isRunningNotifier` — ValueNotifier для UI
- `updateIp()` — получение внешнего IP
- `logger` — поток логов

UI и пользовательский опыт остались **без изменений**.

## Как протестировать

### 1. Проверка генерации конфига

```bash
dart run tools/test_clash_config.dart
```

Это создаст `config_test_clash.yaml` с тестовой конфигурацией.

### 2. Запуск приложения

```bash
flutter run -d windows
```

или

```bash
flutter build windows --release
```

### 3. Проверка работы туннеля

1. Запустите приложение
2. Добавьте профиль (VLESS-подписку)
3. Нажмите кнопку включения туннеля
4. Проверьте логи — должны быть сообщения от Clash Meta
5. Проверьте IP и локацию в статусе

## Конфигурация Clash

Генерируется автоматически в `config.yaml` при запуске туннеля:

- **TUN режим** — весь трафик идёт через туннель
- **DNS** — DoH через 1.1.1.1 и dns.google
- **Правила**:
  - Локальный трафик (GEOIP,private) → DIRECT
  - RU-режим: .ru, .su, .рф → DIRECT (опционально)
  - Исключения по доменам → DIRECT
  - Исключения по процессам → DIRECT
  - Всё остальное → VPN

## Структура конфига YAML

```yaml
port: 7890                    # HTTP порт (не используется в TUN-режиме)
socks-port: 7891              # SOCKS порт (не используется в TUN-режиме)
mode: rule                    # Режим правил
log-level: info               # Уровень логирования

dns:
  enabled: true
  listen: 0.0.0.0:1053
  nameserver:
    - https://1.1.1.1/dns-query
    - https://dns.google/dns-query

tun:
  enable: true                # TUN-интерфейс (главный режим)
  stack: system               # Системный сетевой стек
  auto-route: true            # Автоматическая маршрутизация
  auto-detect-interface: true # Автоопределение интерфейса

proxies:
  - name: "VLF-PROXY"
    type: vless
    server: "..."
    port: ...
    uuid: "..."
    flow: "xtls-rprx-vision"
    reality-opts:
      public-key: "..."
      short-id: "..."

proxy-groups:
  - name: "VLF"
    type: select
    proxies:
      - "VLF-PROXY"

rules:
  - GEOIP,private,DIRECT
  - DOMAIN-SUFFIX,ru,DIRECT    # RU-режим
  - MATCH,VLF                  # Остальное через VPN
```

## Отличия от sing-box

| Параметр | sing-box | Clash Meta |
|----------|----------|------------|
| Формат конфига | JSON | YAML |
| Запуск | `sing-box run -c config.json` | `mihomo -f config.yaml` |
| Поддержка VLESS Reality | ✅ | ✅ |
| TUN режим | ✅ | ✅ |
| Правила по процессам | ✅ | ✅ (PROCESS-NAME) |
| Размер бинарника | ~15 MB | ~20 MB |

## Troubleshooting

### Ошибка "mihomo.exe не найден"

```
FileSystemException: mihomo.exe не найден
```

**Решение:** Скопируйте `mihomo.exe` в корень проекта:

```powershell
Copy-Item tools\mihomo.exe . -Force
```

### TUN-интерфейс не создаётся

```
Access is denied
```

**Решение:** Запустите приложение с правами администратора. Приложение должно автоматически запросить повышение прав.

### Конфиг не генерируется

Проверьте формат VLESS-подписки:

```bash
dart run tools/test_clash_config.dart
```

## Сборка релиза

```powershell
# Полная сборка с упаковкой
.\tools\build_and_package.ps1 -Zip

# Результат
release\windows_x64_release\
  ├── VLF_VPN.exe
  ├── mihomo.exe
  ├── wintun.dll
  └── (другие файлы Flutter)
```

## Дополнительная информация

- [Clash Meta (mihomo) документация](https://wiki.metacubex.one/)
- [VLESS протокол](https://xtls.github.io/config/outbounds/vless.html)
- [Reality обфускация](https://github.com/XTLS/REALITY)

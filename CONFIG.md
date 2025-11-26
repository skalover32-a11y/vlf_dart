# Конфигурационные файлы VLF VPN

## Рабочие конфигурации (используются в runtime)

### `config.yaml`
**Генерируется автоматически** при запуске туннеля через `ClashManager.start()`.
- Формат: YAML (Clash Meta)
- Расположение: в `baseDir` (обычно корень проекта при разработке, рядом с .exe в release)
- Содержимое: proxy-groups (DIRECT-GROUP, VLF-PROXY-GROUP, FINAL-GROUP), правила маршрутизации, DNS, TUN
- **НЕ КОММИТИТЬ** — файл перезаписывается при каждом старте туннеля

### `config_debug.yaml`
**Опциональный дамп** для отладки конфигурации Clash Meta.
- Создаётся одновременно с `config.yaml` при запуске туннеля
- Содержит ту же конфигурацию, что и `config.yaml`
- Используется для ручной проверки сгенерированных правил
- **НЕ КОММИТИТЬ** — временный файл

### `vlf_gui_config.json`
**Постоянный конфиг GUI**, читается/записывается `ConfigStore`.
- Формат: JSON
- Поля: `ru_mode` (boolean), `mode` (string), `site_exclusions` (list), `app_exclusions` (list)
- **КОММИТИТЬ С ОСТОРОЖНОСТЬЮ** — можно добавить в .gitignore если содержит приватные данные

### `profiles.json`
**Профили VLESS-подключений**, управляются `ProfileManager`.
- Формат: JSON (массив объектов `Profile`)
- Содержит: `name`, `url` (vless://), `isActive`
- **НЕ КОММИТИТЬ** — содержит приватные URL подключений

## Генерируемые артефакты (игнорируются git)

### Конфигурации
- `config.yaml`, `config_debug.yaml` — рабочие конфиги Clash Meta
- `config.json`, `config_debug.json` — старые форматы (больше не используются)
- `config_*.yaml`, `config_*.json` — любые временные конфиги из тестов

### Логи
- `*.log` — все логи (singbox.log, singbox_debug.log, singbox_test.log и т.д.)
- `singbox_*.txt` — временные дампы окружения

### Бинарники и артефакты сборки
- `mihomo.exe` — Clash Meta binary (копируется в проект для упаковки)
- `wintun.dll` — TUN driver для Windows
- `sing-box.exe` — старый backend (теперь не используется, но может быть в корне)
- `*.zip` — архивы релизов
- `tree.txt` — дампы структуры проекта

## Примеры конфигураций (dev/config_examples/)

Архивные/тестовые конфигурации, сохранённые для справки:
- `config_test*.yaml` — выходы тестовых скриптов (`dart run tools/gen_config.dart`)
- `config_global*.yaml` — примеры конфигов в глобальном режиме
- `config_rf*.yaml` — примеры конфигов в РФ-режиме
- `config_ru.yaml` — старые форматы
- `example_config.yaml` — эталонный пример

**Не используются в runtime** — только для отладки и документации.

## Как работает генерация конфигов

1. **При старте туннеля** (`VlfCore.start()` → `ClashManager.start()`):
   - Читаются настройки из `vlf_gui_config.json` (RF mode, exclusions)
   - Читается активный профиль из `profiles.json`
   - Генерируется `config.yaml` через `buildClashConfig()` из `lib/clash_config.dart`
   - Записывается `config_debug.yaml` (опционально)
   - Запускается `mihomo.exe -f config.yaml`

2. **При тестировании** (`dart run test_rules_priority.dart`):
   - Вызывается `buildClashConfig()` напрямую
   - Генерируются временные конфиги (НЕ влияют на runtime)

3. **Для отладки** (`dart run tools/gen_config.dart`):
   - Создаёт `config_test.yaml` с примером конфигурации
   - **DEPRECATED** — используйте `test_rules_priority.dart` вместо этого

## Что НЕ нужно коммитить

```gitignore
config.yaml
config_debug.yaml
config.json
config_debug.json
config_*.yaml
config_*.json
!vlf_gui_config.json  # исключение — GUI-конфиг можно коммитить
profiles.json
*.log
*.exe
*.dll
*.zip
```

## Что можно (и нужно) коммитить

- `lib/clash_config.dart` — логика генерации конфигов
- `tools/*.dart` — тестовые скрипты
- `dev/config_examples/*.yaml` — архивные примеры
- `CONFIG.md` (этот файл) — документация

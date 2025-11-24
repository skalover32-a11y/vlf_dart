<!-- Copilot / AI agent instructions for contributors -->
# Быстрый старт для AI-агента

Ниже — концентрированное, практически полезное руководство для AI-агентов, работающих с этим репозиторием. Файл ориентирован на то, чтобы вы могли сразу вносить правки, писать код и понимать ключевые интеграции.

- **Главная цель проекта:** Flutter UI вокруг локального `sing-box` (sing-box.exe), который запускается как внешний процесс и управляется через `SingboxManager`.

- **Ключевые директории/файлы:**
  - `lib/` — основная логика и UI. См. `lib/main.dart`, `lib/core/vlf_core.dart`, `lib/singbox_manager.dart`.
  - `tools/build_and_package.ps1` — Windows packaging script (выполняет `flutter pub get`, `flutter build windows --release`, копирует бинарники и опционально собирает zip).
  - `tools/gen_config.dart` — пример генерации `config_test.json` через `lib/singbox_config.dart` (используется для тестов/отладки конфигурации sing-box).
  - `vlf_gui_config.json`, `profiles.json` — runtime-конфиги, читаемые/записываемые `ConfigStore` (`lib/config_store.dart`).

- **Архитектура — кратко:**
  - `VlfCore` (файл `lib/core/vlf_core.dart`) — фасад для UI: хранит `ConfigStore`, `ProfileManager`, `Exclusions`, `SingboxManager` и `Logger`. UI взаимодействует только с этим фасадом.
  - `SingboxManager` (`lib/singbox_manager.dart`) — отвечает за формирование `config.json`, запуск/остановку `sing-box.exe`, обработку stdout/stderr и нотификации через `ValueNotifier<bool> isRunningNotifier` и `Logger`.
  - `ProfileManager` / `ConfigStore` — простая сериализация профилей и GUI-настроек в JSON-файлы рядом с приложением.
  - `subscription_decoder.dart` — правила извлечения `vless://` из сырых текстов, URL-ответов и base64-обёрток.

- **Особенности и часто встречающиеся паттерны:**
  - ValueNotifier-heavy UI: состояние подключения и режим работы (`VlfWorkMode`) публикуются через `ValueNotifier` и должны обновляться аккуратно при изменениях.
  - Логирование: приложение использует `Logger` (стрим строк) — UI подписывается на `logger.stream`.
  - Конфигурация sing-box генерируется в рантайме: `SingboxManager.start()` записывает `config.json` в `baseDir` перед запуском.
  - Проверка доступа в Windows: `SingboxManager.isWindowsAdmin()` использует PowerShell вызов; есть метод `relaunchAsAdmin()` для поднятия привилегий.
  - Процессы: при запуске sing-box слушаем stdout/stderr и ждём маркеров успешного старта (поиск строк `sing-box started`, `tcp server started` и т.п.). Таймауты — короткие (обычно 5s): учитывать в тестах/фикстурах.

- **Build / release workflow (что реально выполнять):**
  - Локальная сборка Windows (основной сценарий):
    - `pwsh .\tools\build_and_package.ps1 -ProjectRoot (Get-Location).Path` — выполнит `flutter pub get`, `flutter build windows --release`, скопирует артефакты в `release\windows_x64_release` и переименует exe в `VLF_VPN.exe`.
    - Скрипт также ищет нативные бинарники в `..\client` и `..\client\_internal` и копирует `sing-box.exe`, `wintun.dll`, `libiconv.dll` если найдёт.
  - Для генерации примера конфигурации sing-box используйте:
    - `dart run tools/gen_config.dart` (работает из корня репозитория) — создаст `config_test.json`.

- **Формат конфигов / названия файлов:**
  - GUI-конфиг: `vlf_gui_config.json` (поля: `profiles`, `ru_mode`, `mode`, `site_exclusions`, `app_exclusions`). Чтение/запись — `ConfigStore`.
  - Профили: `profiles.json` — список объектов `Profile` (см. `lib/profile_manager.dart`).
  - Runtime sing-box config: `config.json` (в baseDir), генерируется `SingboxManager`.

- **Примеры кода/вызовов для быстрых правок:**
  - Перезапуск sing-box при смене режима: вызов `VlfCore.setWorkMode(...)` — фасад сам сохранит конфиг и перезапустит sing-box при необходимости.
  - Добавление профиля из произвольного текста: `VlfCore.addProfileFromText(text)` использует `extractVlessFromAny`.

- **Что стоит учитывать при изменениях:**
  - Не изменяйте имена runtime-файлов (`vlf_gui_config.json`, `profiles.json`, `config.json`) без одновременного правки `ConfigStore` и `SingboxManager`.
  - Любые изменения запуска sing-box должны учитывать: создание `config.json`, проверку наличия `sing-box.exe`, и корректную подписку/отписку от stdout/stderr, иначе UI потеряет доступ к логам.
  - Packaging script (`tools/build_and_package.ps1`) ожидает Windows PowerShell; при изменениях обновляйте логику переименования exe и список включаемых нативных файлов.

- **Где искать при отладке ошибок:**
  - `release\windows_x64_release` и `build\windows\x64\runner\Release` — содержимое после сборки.
  - Логи sing-box отображаются в UI и формируются через `Logger` — можно подписаться на `VlfCore.logStream`.
  - Для проблем с подписками/парсингом — проверьте `lib/subscription_decoder.dart` и сценарий `tools/gen_config.dart`.

Если что-то неполно или вы хотите, чтобы я включил примеры коммитов/PR-шаблонов, скажите — внесу правки.

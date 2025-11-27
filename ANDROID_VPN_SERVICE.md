# Android VPN Service Implementation

## Архитектура

### Компоненты

1. **VlfVpnService** (`VlfVpnService.kt`)
   - Основной VPN сервис, наследует `android.net.VpnService`
   - Поднимает TUN-интерфейс с помощью `VpnService.Builder`
   - Создаёт foreground notification для индикации активного VPN
   - Управляет жизненным циклом: `onCreate` → `onStartCommand` → `onDestroy` / `onRevoke`

2. **VlfAndroidEngine** (`VlfAndroidEngine.kt`)
   - Связующий слой между Flutter (Dart) и нативным кодом Android
   - Реализует `MethodChannel` для команд: `startTunnel`, `stopTunnel`, `getStatus`
   - Реализует `EventChannel` для передачи статусов: `running`, `stopped`, `error:...`
   - Управляет запросом VPN-разрешения через `VpnService.prepare()`

3. **AndroidPlatformRunner** (`lib/platform/android_platform_runner.dart`)
   - Dart-обёртка над MethodChannel/EventChannel
   - Реализует интерфейс `PlatformRunner`
   - Генерирует YAML конфиг и передаёт в нативный слой

### Поток данных

```
Flutter UI
    ↓
VlfCore.startTunnel()
    ↓
ClashManager.start()
    ↓
AndroidPlatformRunner.start()
    ↓
MethodChannel('vlf_android_engine').startTunnel
    ↓
VlfAndroidEngine.onMethodCall()
    ↓
VpnService.prepare() → если нужно разрешение
    ↓
startActivityForResult() → пользователь подтверждает
    ↓
VlfAndroidEngine.onActivityResult()
    ↓
context.startForegroundService(VlfVpnService)
    ↓
VlfVpnService.onStartCommand()
    ↓
VpnService.Builder.establish() → TUN interface
    ↓
VlfVpnService.notifyStatus("running")
    ↓
EventChannel → statusStream
    ↓
ClashManager обновляет isRunningNotifier
    ↓
UI показывает зелёный статус
```

### Статусы и синхронизация

#### Жизненный цикл статусов VPN

```
[stopped] ─────────────────────┐
    ↑                          ↓
    │                    [starting]
    │                          ↓
    │                    [running]
    │                          ↓
    │                    [stopping]
    └──────────────────────────┘
    
    Ошибка на любом этапе → [error:message] → [stopped]
```

#### Описание статусов

- **`stopped`** — VPN не активен, интерфейс закрыт, иконка VPN отсутствует
- **`starting`** — VPN запускается, foreground notification создаётся, TUN интерфейс устанавливается
- **`running`** — VPN интерфейс активен, трафик маршрутизируется через TUN, иконка VPN в статус-баре
- **`stopping`** — VPN завершается, интерфейс закрывается
- **`error:<message>`** — ошибка при старте или во время работы, после чего автоматически переход в `stopped`

#### Механизм синхронизации

1. **VlfVpnService → VlfAndroidEngine**
   - `VlfVpnService` вызывает `notifyStatus(status)` при изменении состояния
   - Статус передаётся через зарегистрированный callback в `VlfAndroidEngine`

2. **VlfAndroidEngine → Flutter**
   - `statusSink?.success(status)` отправляет статус в EventChannel
   - Flutter слушает `_statusChannel.receiveBroadcastStream()`

3. **Flutter → UI**
   - `AndroidPlatformRunner` обновляет `_running` флаг и `_statusCtl` stream
   - `ClashManager` подписан на `runner.statusStream`
   - `ClashManager.isRunningNotifier` триггерит перерисовку UI через `ValueListenableBuilder`

#### Особенности синхронизации

- **При подключении EventChannel** (`onListen`) отправляется текущий статус для синхронизации UI
- **При переподключении приложения** (после фона или перезапуска) UI получает актуальный статус VPN
- **При отключении извне** (onRevoke) статус гарантированно доходит до UI до завершения сервиса
- **При краше сервиса** следующий вызов `getStatus()` вернёт `stopped`

### Остановка VPN

VPN может быть остановлен несколькими способами, и в каждом случае гарантируется корректная очистка ресурсов и обновление UI:

#### 1. Пользователь нажал кнопку OFF в приложении

**Поток:**
```
Flutter UI (кнопка OFF)
    ↓
VlfCore.stopTunnel()
    ↓
ClashManager.stop()
    ↓
AndroidPlatformRunner.stop()
    ↓
MethodChannel('vlf_android_engine').stopTunnel
    ↓
VlfAndroidEngine.stopVpnService()
    ↓
Отправка Intent с ACTION_STOP в VlfVpnService
    ↓
VlfVpnService.onStartCommand() с ACTION_STOP
    ↓
VlfVpnService.stopVpn()
    ↓
1. notifyStatus("stopping")
2. vpnInterface.close() — закрыть TUN интерфейс
3. stopForeground(STOP_FOREGROUND_REMOVE) — убрать уведомление
4. notifyStatus("stopped") — уведомить Flutter
5. stopSelf() — остановить сервис
    ↓
EventChannel → statusStream
    ↓
AndroidPlatformRunner обновляет _running = false
    ↓
ClashManager обновляет isRunningNotifier
    ↓
UI показывает "Отключено"
```

**Критически важно:** 
- `notifyStatus("stopped")` вызывается **ДО** `stopSelf()`, чтобы Flutter успел получить статус
- `stopForeground(STOP_FOREGROUND_REMOVE)` убирает уведомление **и иконку VPN из статус-бара**
- После `vpnInterface.close()` система автоматически удаляет VPN-интерфейс

#### 2. Пользователь нажал "Остановить" в уведомлении

**Поток идентичен п.1** — уведомление отправляет тот же `ACTION_STOP` Intent.

#### 3. Пользователь отключил VPN из шторки Android (или через Settings)

**Поток:**
```
Пользователь отключает VPN через системную шторку
    ↓
Система вызывает VlfVpnService.onRevoke()
    ↓
1. vpnInterface.close() — закрыть TUN интерфейс
2. notifyStatus("stopped") — уведомить Flutter
3. super.onRevoke() — система завершит сервис
    ↓
Система автоматически вызывает onDestroy()
    ↓
EventChannel → statusStream → UI обновляется
```

**Важно:** 
- В `onRevoke()` **НЕ** вызываем `stopSelf()` — система сама завершает сервис
- `notifyStatus("stopped")` гарантирует синхронизацию UI даже при отключении извне

#### 4. Система убивает сервис (Low Memory Killer или форс-стоп)

**Поток:**
```
Android система завершает процесс VlfVpnService
    ↓
VlfVpnService.onDestroy()
    ↓
1. vpnInterface.close() — закрыть TUN интерфейс
2. stopForeground(STOP_FOREGROUND_REMOVE) — убрать уведомление
3. notifyStatus("stopped") — попытка уведомить Flutter
4. instance = null
    ↓
EventChannel → statusStream (если успеет)
    ↓
UI обновляется или показывает последний известный статус
```

**Примечание:** При агрессивном завершении EventChannel может не успеть доставить статус. В этом случае при следующем запуске приложения `onListen()` в `VlfAndroidEngine` отправит актуальный статус `stopped`.

#### Гарантии корректного завершения

✅ **Системная иконка VPN исчезает** — `stopForeground(STOP_FOREGROUND_REMOVE)` + `vpnInterface.close()`  
✅ **Уведомление убирается** — `stopForeground(STOP_FOREGROUND_REMOVE)`  
✅ **UI синхронизирован** — статусы `stopping` → `stopped` через EventChannel  
✅ **Нет утечек ресурсов** — `vpnInterface` всегда закрывается в `try-catch`  
✅ **Работает при любом сценарии** — остановка из UI, из уведомления, из системных настроек, при убийстве процесса

## Конфигурация TUN-интерфейса

Текущие параметры (минимальная реализация без mihomo):

```kotlin
Builder()
    .setSession("VLF Tunnel")
    .addAddress("10.0.0.2", 24)     // Виртуальный IP
    .addRoute("0.0.0.0", 0)          // Весь трафик через VPN
    .addDnsServer("8.8.8.8")         // Google DNS
    .addDnsServer("1.1.1.1")         // Cloudflare DNS
    .setMtu(1500)
    .setBlocking(false)
    .establish()
```

## Разрешения (AndroidManifest.xml)

```xml
<uses-permission android:name="android.permission.BIND_VPN_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
```

## Что работает сейчас

✅ Запрос VPN-разрешения у пользователя  
✅ Создание TUN-интерфейса  
✅ Маршрутизация трафика через VPN  
✅ Foreground notification "VLF Tunnel активен"  
✅ Синхронизация статуса UI ↔ VpnService  
✅ Обработка отключения из шторки (`onRevoke`)  
✅ Корректная остановка при уничтожении сервиса  
✅ Логирование всех событий в Logcat (тег `VLF-VpnService`)  

## Что НЕ работает (TODO следующего этапа)

❌ Интеграция с mihomo (Clash Meta) для проксирования  
❌ Обработка входящих/исходящих пакетов из TUN  
❌ Маршрутизация через VLESS сервер  
❌ Применение правил из `configYaml` (ru_mode, исключения)  
❌ Отображение статистики трафика  

## Проверка работы

### 1. Сборка и установка

```powershell
# Собрать APK
flutter build apk --release

# Установить на подключённое устройство
flutter install -d <device-id>

# Или запустить в debug режиме для live-reload
flutter run -d <device-id>
```

### 2. Тестирование включения VPN

1. Запустить приложение
2. Добавить VLESS профиль (или использовать существующий)
3. Нажать кнопку "Включить туннель"
4. **Ожидаемое поведение:**
   - Появляется системный диалог "Запрос на подключение к VPN" (при первом запуске)
   - После подтверждения иконка ключа (VPN) появляется в статус-баре
   - UI показывает "Туннель активен" с зелёным индикатором
   - Появляется постоянное уведомление "VLF Tunnel активен" с кнопкой "Остановить"

### 3. Тестирование выключения VPN

**Сценарий A: Отключение через UI приложения**
1. Нажать кнопку "Выключить туннель" в UI
2. **Ожидаемое:**
   - Иконка VPN в статус-баре **исчезает**
   - Уведомление убирается
   - UI показывает "Отключено"

**Сценарий B: Отключение через уведомление**
1. Открыть шторку уведомлений
2. Нажать "Остановить" в уведомлении VLF
3. **Ожидаемое:** идентично сценарию A

**Сценарий C: Отключение через системные настройки**
1. Открыть шторку → долгое нажатие на иконку VPN → Настройки VPN
2. Выключить "VLF Tunnel"
3. **Ожидаемое:**
   - Иконка VPN исчезает
   - Уведомление убирается
   - При возврате в приложение UI показывает "Отключено"

### 4. Проверка логов

```powershell
# Фильтр по тегам VLF
adb logcat -s VLF-VpnService:D VLF:D

# Полный лог с временными метками
adb logcat -v time -s VLF-VpnService VLF

# Очистить лог и следить за новыми событиями
adb logcat -c; adb logcat -s VLF-VpnService VLF
```

**Что искать в логах:**

✅ **При включении:**
```
VLF-VpnService: onCreate() called
VLF: VPN permission already granted - starting service
VLF-VpnService: onStartCommand() - action: null
VLF-VpnService: Building VPN interface...
VLF-VpnService: Foreground notification started
VLF-VpnService: VPN Builder configured: address=10.0.0.2/24, ...
VLF-VpnService: ✅ VPN interface established successfully - fd: 123
VLF-VpnService: Notifying status: running
```

✅ **При выключении через UI:**
```
VLF: AndroidEngine.stopTunnel
VLF: Stopping VPN service...
VLF-VpnService: onStartCommand() - action: com.example.vlf_dart.STOP_VPN
VLF-VpnService: Stop action received
VLF-VpnService: Stopping VPN...
VLF-VpnService: Notifying status: stopping
VLF-VpnService: VPN interface closed
VLF-VpnService: Foreground notification removed
VLF-VpnService: Notifying status: stopped
VLF-VpnService: VPN stopped, status sent to Flutter
VLF-VpnService: onDestroy() called
```

✅ **При отключении из шторки:**
```
VLF-VpnService: ⚠️ onRevoke() called - User revoked VPN permission from system settings
VLF-VpnService: VPN interface closed in onRevoke()
VLF-VpnService: Notifying status: stopped
VLF-VpnService: VPN revoked by system, status sent to Flutter
VLF-VpnService: onDestroy() called
```

### 5. Проверка статуса VPN в системе

```powershell
# Проверить активные VPN подключения
adb shell dumpsys connectivity | Select-String -Pattern "VPN|tun0" -Context 5

# Проверить сетевые интерфейсы (должен появиться tun0 при активном VPN)
adb shell ip addr show

# Проверить маршруты (должен быть маршрут через tun0)
adb shell ip route show
```

### 6. Проверка IP адреса (пока не работает без mihomo)

```powershell
# Проверить внешний IP через устройство
adb shell "curl -s https://api.ipify.org"

# Примечание: без интеграции mihomo IP не изменится,
# но TUN интерфейс должен быть активен
```

## Отладка

### Проблема: разрешение не запрашивается

Проверьте, что `VlfAndroidEngine` реализует `ActivityAware` и регистрируется правильно в `MainActivity`.

### Проблема: VPN не включается

Проверьте логи:
```bash
adb logcat -s VLF-VpnService:D VLF:D
```

Ищите ошибки в `establish()` — возможно, конфликт с другим активным VPN.

### Проблема: статус не обновляется в UI

Убедитесь, что:
- `VlfVpnService.setStatusCallback()` вызывается в `onAttachedToEngine`
- `statusSink` не null в момент вызова `notifyStatus()`
- EventChannel listener подключен (`onListen` вызван)

## Следующие шаги

1. Интегрировать mihomo:
   - Скомпилировать mihomo как Android library (Go Mobile)
   - Передавать file descriptor от `establish()` в mihomo
   - Запускать mihomo с конфигом в отдельном потоке

2. Обработка пакетов:
   - Читать из `vpnInterface.fileDescriptor`
   - Отправлять в mihomo для проксирования
   - Записывать ответы обратно в TUN

3. Применение правил:
   - Парсить `configYaml` из Dart
   - Конфигурировать mihomo с правилами ru_mode и исключениями

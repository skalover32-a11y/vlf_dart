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

### Статусы

Статусы передаются из `VlfVpnService` в Flutter через `EventChannel`:

- **`stopped`** — VPN не активен
- **`running`** — VPN интерфейс установлен, трафик идёт через TUN
- **`error:<message>`** — ошибка при старте или во время работы

### Остановка VPN

Может произойти несколькими способами:

1. **Пользователь нажал кнопку OFF в UI**
   - Flutter → `stopTunnel()` → MethodChannel → `VlfVpnService.stopSelf()`

2. **Пользователь отключил VPN из шторки Android**
   - Система вызывает `VlfVpnService.onRevoke()`
   - Статус `stopped` отправляется в Dart
   - UI обновляется автоматически

3. **Система убила сервис (нехватка памяти)**
   - `VlfVpnService.onDestroy()` вызывается
   - Статус `stopped` отправляется в Dart

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

1. Собрать APK:
```bash
flutter build apk --release
```

2. Установить на устройство:
```bash
flutter install -d <device>
```

3. Запустить и включить туннель в UI

4. Проверить логи:
```bash
adb logcat -s VLF-VpnService VLF
```

5. Проверить смену IP:
```bash
adb shell curl https://api.ipify.org
```

6. Проверить системный статус VPN:
```bash
adb shell dumpsys connectivity | grep -A 10 "VPN"
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

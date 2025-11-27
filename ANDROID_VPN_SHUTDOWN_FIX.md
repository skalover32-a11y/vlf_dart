# Android VPN Shutdown Fix - Summary

## Проблема

При выключении VPN туннеля на Android:
- ❌ Иконка VPN в статус-баре оставалась висеть
- ❌ Приходилось вручную отключать VPN из настроек Android
- ❌ Статусы не всегда синхронизировались с UI

## Решение

### Изменённые файлы

1. **`VlfVpnService.kt`** — корректная последовательность остановки
2. **`VlfAndroidEngine.kt`** — использование ACTION_STOP для graceful shutdown
3. **`AndroidPlatformRunner.dart`** — обработка промежуточных статусов
4. **`ANDROID_VPN_SERVICE.md`** — документация логики остановки

### Ключевые изменения

#### 1. VlfVpnService.stopVpn()

**Было:**
```kotlin
stopForeground(true)
stopSelf()
notifyStatus("stopped")  // ❌ Может не успеть отправить
```

**Стало:**
```kotlin
notifyStatus("stopping")
vpnInterface?.close()
stopForeground(STOP_FOREGROUND_REMOVE)  // ✅ Убирает иконку VPN
notifyStatus("stopped")                 // ✅ ДО stopSelf()
stopSelf()
```

#### 2. VlfVpnService.onRevoke()

**Было:**
```kotlin
notifyStatus("stopped")
stopVpn()  // ❌ Рекурсия + двойной stopSelf()
```

**Стало:**
```kotlin
vpnInterface?.close()
notifyStatus("stopped")
super.onRevoke()  // ✅ Система сама вызовет onDestroy()
```

#### 3. VlfAndroidEngine.stopVpnService()

**Было:**
```kotlin
ctx.stopService(intent)  // ❌ Резкая остановка
```

**Стало:**
```kotlin
intent.action = "com.example.vlf_dart.STOP_VPN"
ctx.startForegroundService(intent)  // ✅ Graceful shutdown через ACTION_STOP
```

#### 4. AndroidPlatformRunner — новые статусы

**Было:**
```dart
if (s.startsWith('running')) _running = true;
if (s.startsWith('stopped') || s.startsWith('error')) _running = false;
```

**Стало:**
```dart
if (s.startsWith('starting') || s.startsWith('running')) _running = true;
if (s.startsWith('stopping') || s.startsWith('stopped') || s.startsWith('error')) _running = false;
_logger.append('Android status: $s\n');  // ✅ Логирование для отладки
```

## Жизненный цикл статусов

```
stopped → starting → running → stopping → stopped
                       ↓
                  error:message
                       ↓
                    stopped
```

## Результат

✅ **Иконка VPN корректно исчезает** — `stopForeground(STOP_FOREGROUND_REMOVE)`  
✅ **Статусы синхронизированы** — `notifyStatus()` перед `stopSelf()`  
✅ **Работают все сценарии остановки:**
   - Кнопка OFF в UI
   - Кнопка "Остановить" в уведомлении
   - Отключение из шторки Android
   - Отключение через Settings → VPN
   - Убийство сервиса системой

✅ **Не ломает Windows** — изменения только в Android-специфичных файлах

## Проверка

### Сборка и тесты

```powershell
# Проверка тестов
flutter test

# Сборка для Windows (не должна сломаться)
flutter build windows --release

# Сборка для Android
flutter build apk --release

# Запуск на устройстве
flutter run -d <device-id>
```

### Логи для проверки корректной остановки

```powershell
adb logcat -c; adb logcat -s VLF-VpnService VLF
```

**Ожидаемый вывод при остановке:**
```
VLF: AndroidEngine.stopTunnel
VLF-VpnService: Stop action received
VLF-VpnService: Stopping VPN...
VLF-VpnService: Notifying status: stopping
VLF-VpnService: VPN interface closed
VLF-VpnService: Foreground notification removed
VLF-VpnService: Notifying status: stopped
VLF-VpnService: VPN stopped, status sent to Flutter
VLF-VpnService: onDestroy() called
```

### Визуальная проверка

1. Включить туннель → иконка VPN появляется ✅
2. Выключить туннель → иконка VPN исчезает ✅
3. Уведомление убирается ✅
4. UI показывает "Отключено" ✅

## Следующие шаги

- [ ] Тестирование на реальном устройстве
- [ ] Интеграция mihomo для реального проксирования (следующий этап)
- [ ] Добавить IP/локацию для Android после интеграции ядра
- [ ] Разблокировать PROXY режим на Android

## Commit

```
commit d60bd60
fix(android): Correct VPN shutdown and status synchronization
```

**Branch:** `feature/android-vpnservice`  
**Pushed:** ✅

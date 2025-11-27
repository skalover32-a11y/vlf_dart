# VLF tunnel — CHANGELOG

## v0.4.0 (Preview)

### Windows
- TUN режим (Wintun) + PROXY режим
- РФ-режим: российский трафик напрямую, остальной через VPN
- Экран логов: просмотр stdout/stderr движка
- Трэй-иконка: быстрый доступ к статусу и действиям

### Android
- Системный VPN-туннель (VpnService) — preview
- PROXY-режим временно отключён
- Ядро VLESS для Android в разработке (интеграция mihomo/sing-box в следующих релизах)

### UI/Адаптивность
- Единое брендирование: "VLF tunnel" в заголовках
- Адаптивная верстка: масштабирование дизайна 430px для десктопа и мобильных
- Минимальные безопасные отступы через MediaQuery

### Прочее
- Обновление метаданных пакета: `name: vlf_tunnel`, версия `0.4.0`
- Документация по Android VPN: `ANDROID_VPN_SERVICE.md` + `ANDROID_VPN_SHUTDOWN_FIX.md`

---
Следующий этап: интеграция VLESS core на Android (маршрутизация через TUN FD).

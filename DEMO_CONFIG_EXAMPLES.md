# Примеры генерируемых конфигураций Clash/Mihomo

## ТЕСТ 1: Глобальный режим без исключений
```yaml
rules:
  # --- Локальные сети ---
  - GEOIP,private,DIRECT,no-resolve

  # --- Всё остальное через VPN ---
  - MATCH,VLF
```

## ТЕСТ 2: Глобальный режим с исключениями
```yaml
rules:
  # --- Исключения: приложения ---
  - PROCESS-NAME,chrome.exe,DIRECT
  - PROCESS-NAME,Telegram.exe,DIRECT

  # --- Исключения: домены ---
  - DOMAIN-SUFFIX,kinopoisk.ru,DIRECT
  - DOMAIN-SUFFIX,vk.com,DIRECT

  # --- Локальные сети ---
  - GEOIP,private,DIRECT,no-resolve

  # --- Всё остальное через VPN ---
  - MATCH,VLF
```

## ТЕСТ 3: РФ-режим без исключений
```yaml
rules:
  # --- Локальные сети ---
  - GEOIP,private,DIRECT,no-resolve

  # --- РФ-режим: российский трафик в обход VPN ---
  - DOMAIN-SUFFIX,ru,DIRECT
  - DOMAIN-SUFFIX,su,DIRECT
  - DOMAIN-SUFFIX,рф,DIRECT
  - GEOIP,RU,DIRECT,no-resolve
  - DOMAIN-SUFFIX,2ip.ru,DIRECT

  # --- Всё остальное через VPN ---
  - MATCH,VLF
```

## ТЕСТ 4: РФ-режим с исключениями
```yaml
rules:
  # --- Исключения: приложения ---
  - PROCESS-NAME,chrome.exe,DIRECT
  - PROCESS-NAME,Telegram.exe,DIRECT

  # --- Исключения: домены ---
  - DOMAIN-SUFFIX,kinopoisk.ru,DIRECT
  - DOMAIN-SUFFIX,vk.com,DIRECT

  # --- Локальные сети ---
  - GEOIP,private,DIRECT,no-resolve

  # --- РФ-режим: российский трафик в обход VPN ---
  - DOMAIN-SUFFIX,ru,DIRECT
  - DOMAIN-SUFFIX,su,DIRECT
  - DOMAIN-SUFFIX,рф,DIRECT
  - GEOIP,RU,DIRECT,no-resolve
  - DOMAIN-SUFFIX,2ip.ru,DIRECT

  # --- Всё остальное через VPN ---
  - MATCH,VLF
```

## ТЕСТ 5: РФ-режим с 2ip.ru в исключениях (нет дубликатов)
```yaml
rules:
  # --- Исключения: домены ---
  - DOMAIN-SUFFIX,2ip.ru,DIRECT

  # --- Локальные сети ---
  - GEOIP,private,DIRECT,no-resolve

  # --- РФ-режим: российский трафик в обход VPN ---
  - DOMAIN-SUFFIX,ru,DIRECT
  - DOMAIN-SUFFIX,su,DIRECT
  - DOMAIN-SUFFIX,рф,DIRECT
  - GEOIP,RU,DIRECT,no-resolve

  # --- Всё остальное через VPN ---
  - MATCH,VLF
```

## Приоритет правил

Clash проверяет правила **сверху вниз**, первое совпадение побеждает:

1. **Исключения по процессам** — PROCESS-NAME (самый высокий приоритет)
2. **Исключения по доменам** — DOMAIN-SUFFIX
3. **Локальные сети** — GEOIP,private
4. **РФ-режим** (если включен) — DOMAIN-SUFFIX,ru/su/рф + GEOIP,RU + 2ip.ru
5. **Всё остальное** — MATCH,VLF (через VPN)

## Как это работает

### Глобальный режим (ruMode = false)
- Весь внешний трафик → VPN (VLF)
- Исключения → DIRECT
- Локальные сети → DIRECT

### РФ-режим (ruMode = true)
- Российский трафик (.ru, .su, .рф, GeoIP RU) → DIRECT
- Остальной трафик → VPN (VLF)
- Исключения → DIRECT (приоритет выше РФ-правил)
- Локальные сети → DIRECT

## Предотвращение дубликатов

Если `2ip.ru` добавлен в пользовательские исключения, он **не будет** добавлен повторно в РФ-блок:

```dart
if (!siteExcl.contains('2ip.ru')) {
  buffer.writeln('  - DOMAIN-SUFFIX,2ip.ru,DIRECT');
}
```

# vlf_dart

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Android libbox runtime

Android-сборка использует JNI-надстройку поверх официального `libsingbox_libbox.so`.
Если библиотека отсутствует, сервис автоматически откатывается на CLI-режим.

1. Установите **Go 1.21+**, **Android NDK** и утилиту `gomobile`:
	- `go install golang.org/x/mobile/cmd/gomobile@latest`
	- один раз выполните `gomobile init`
	- экспортируйте `ANDROID_NDK_HOME` (и при необходимости `ANDROID_HOME`).
2. Обновите подмодуль: `git submodule update --init --recursive`.
3. Выполните скрипт:

	```bash
	chmod +x tools/build_libbox_android.sh
	tools/build_libbox_android.sh
	```

	Скрипт вызовет официальную цель `cmd/internal/build_libbox`, распакует `libbox.aar`
	и положит готовый `libsingbox_libbox.so` (arm64-v8a) в `android/app/src/main/jniLibs/arm64-v8a/`.
4. Снова выполните `flutter build apk` или `flutter run -d android` — Gradle упакует
	полученную `.so` вместе с приложением.

> **Важно:** без `libsingbox_libbox.so` приложение продолжит использовать
> `CliSingboxEngine` и запускать `sing-box` через CLI. Это удобно для разработки,
> но не решает ограничений Android TUN.

## Подпись Windows (SmartScreen)

Для выпуска релизов без предупреждений SmartScreen подпишите `VLF_VPN.exe` перед
распространением.

1. Купите Code Signing сертификат (OV/EV) у доверенного CA и выгрузите его в формат `.pfx`.
	Храните сертификат и пароль вне репозитория (например, в защищённом секретном хранилище).
2. Установите **Windows SDK / App Certification Kit**, чтобы `signtool.exe` был доступен в PATH.
3. После сборки релиза выполните в PowerShell:

	```powershell
	pwsh tools/sign_vlf.ps1 \
	  -ExecutablePath "release\windows_x64_release\VLF_VPN.exe" \
	  -CertificatePath "C:\certs\company.pfx" \
	  -CertificatePassword 'P@ssw0rd' \
	  -TimestampUrl "http://timestamp.digicert.com"
	```

	Параметр `-SigntoolPath` можно указать вручную, если `signtool.exe` не найден автоматически.
4. Проверьте подпись: `signtool verify /pa release\windows_x64_release\VLF_VPN.exe`.

Скрипт `tools/sign_vlf.ps1` просто оборачивает `signtool` и не зависит от конкретного сертификата.

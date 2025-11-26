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
